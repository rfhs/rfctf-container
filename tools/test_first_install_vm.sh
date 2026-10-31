#!/bin/sh
# Tests misc/first_install and the startup scripts it sets up on a fresh
# Ubuntu, as on a new AMI: boots Ubuntu's cloud image in a KVM VM, copies
# this checkout in, runs first_install twice (it has to be safe to run again),
# reboots so rc.local runs the startup scripts as at boot, and checks the game
# came up: openwrt and the contestants healthy, rfctf-client's clients
# running and trying to connect, docker remapping the contestants' root.
# With "ec2" the VM is made like Ubuntu's AMIs: it boots the linux-aws kernel
# they run, with UEFI from an NVMe disk, and says its board vendor is Amazon
# EC2, so first_install takes its EC2 path (the AWS CLI); the EC2-only startup
# scripts still fail, as there is no instance metadata or credentials.
#   ./tools/test_first_install_vm.sh release ec2|other [workdir]
#   ./tools/test_first_install_vm.sh 24.04 ec2
# It needs KVM, OVMF for ec2, and about 100 GB free in workdir (default
# ./first-install-vm-<release>-<platform>), which keeps the downloaded image
# for the next run. VM_MEMORY (default 12G) and VM_CPUS (default all) size the
# VM.
set -eu

missing_tools=""
for tool in curl git grep nproc qemu-img qemu-system-x86_64 sed sha256sum sleep ssh ssh-keygen tar; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
seed_tool=""
for tool in cloud-localds genisoimage xorriso; do
  if command -v "${tool}" > /dev/null 2>&1; then
    seed_tool="${tool}"
    break
  fi
done
if [ -z "${seed_tool}" ]; then
  missing_tools="${missing_tools} cloud-localds-or-genisoimage-or-xorriso"
fi
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
if [ "$#" -lt 2 ] || { [ "${2}" != ec2 ] && [ "${2}" != other ]; }; then
  printf 'usage: %s release ec2|other [workdir]\n' "${0}" >&2
  exit 2
fi
# SeaBIOS can't boot from NVMe with 4 GB or more, so ec2 boots with UEFI, as
# Ubuntu's AMIs do on Nitro
ovmf=""
if [ "${2}" = ec2 ]; then
  for firmware in /usr/share/ovmf/OVMF.fd /usr/share/qemu/OVMF.fd /usr/share/edk2-ovmf/OVMF_CODE.fd \
    /usr/share/edk2/x64/OVMF.4m.fd /usr/share/qemu/edk2-x86_64-code.fd; do
    if [ -f "${firmware}" ]; then
      ovmf="${firmware}"
      break
    fi
  done
  if [ -z "${ovmf}" ]; then
    printf '%s: no OVMF (UEFI) firmware found for ec2\n' "${0##*/}" >&2
    exit 1
  fi
fi
if [ ! -w /dev/kvm ]; then
  printf '%s: /dev/kvm is missing or not writable\n' "${0##*/}" >&2
  exit 1
fi
release="${1}"
platform="${2}"
work="${3:-./first-install-vm-${release}-${platform}}"
repo="$(cd "$(dirname "${0}")/.." && pwd)"
mkdir -p "${work}"
work="$(cd "${work}" && pwd)"

# The cloud image, checked against Ubuntu's SHA256SUMS
image="ubuntu-${release}-server-cloudimg-amd64.img"
url="https://cloud-images.ubuntu.com/releases/${release}/release"
curl -fsSL -o "${work}/SHA256SUMS" "${url}/SHA256SUMS"
if ! (cd "${work}" && grep " \*\{0,1\}${image}\$" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c --status - 2> /dev/null); then
  curl -fL -o "${work}/${image}" "${url}/${image}"
  (cd "${work}" && grep " \*\{0,1\}${image}\$" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c -)
fi

rm -f "${work}/disk.qcow2" "${work}/key" "${work}/key.pub" "${work}/console.log"
qemu-img create -q -f qcow2 -b "${work}/${image}" -F qcow2 "${work}/disk.qcow2" 100G
ssh-keygen -q -t ed25519 -N '' -f "${work}/key"
cat > "${work}/user-data" << EOF
#cloud-config
users:
  - name: rfhs
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "${work}/key.pub")
EOF
printf 'instance-id: first-install-test\nlocal-hostname: first-install-test\n' > "${work}/meta-data"
case "${seed_tool}" in
  cloud-localds) cloud-localds "${work}/seed.img" "${work}/user-data" "${work}/meta-data" ;;
  genisoimage) genisoimage -quiet -output "${work}/seed.img" -volid cidata -joliet -rock "${work}/user-data" "${work}/meta-data" ;;
  xorriso) xorriso -as mkisofs -quiet -output "${work}/seed.img" -volid cidata -joliet -rock "${work}/user-data" "${work}/meta-data" ;;
esac

port=$((20000 + $$ % 10000))
if [ "${platform}" = ec2 ]; then
  set -- -bios "${ovmf}" -drive "file=${work}/disk.qcow2,if=none,id=root" \
    -device nvme,drive=root,serial=vol0,bootindex=0 -smbios 'type=2,manufacturer=Amazon EC2'
else
  set -- -drive "file=${work}/disk.qcow2,if=virtio"
fi
qemu-system-x86_64 -enable-kvm -cpu host -smp "${VM_CPUS:-$(nproc)}" -m "${VM_MEMORY:-12G}" "$@" \
  -drive "file=${work}/seed.img,if=virtio,format=raw" \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${port}-:22" -device virtio-net-pci,netdev=net0 \
  -display none -serial "file:${work}/console.log" -daemonize -pidfile "${work}/qemu.pid"
trap 'kill "$(cat "${work}/qemu.pid")" 2> /dev/null || true' EXIT

vm() {
  ssh -q -i "${work}/key" -p "${port}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 -o ServerAliveInterval=30 rfhs@127.0.0.1 "$@"
}
# wait_for_ssh seconds
wait_for_ssh() {
  waited=0
  until vm true 2> /dev/null; do
    if [ "${waited}" -ge "${1}" ]; then
      printf 'The VM did not answer ssh in %s s; its console:\n' "${1}"
      tail -n 50 "${work}/console.log"
      exit 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}
failures=0
# check description command: runs the command in the VM and records whether
# it passed
check() {
  description="${1}"
  shift
  if vm "$@"; then
    result 0 "${description}"
  else
    result 1 "${description}"
  fi
}
reboot_vm() {
  vm 'sudo systemctl reboot' || true
  sleep 20
  wait_for_ssh 600
}
result() {
  if [ "${1}" = 0 ]; then
    printf 'PASS: [%s %s] %s\n' "${release}" "${platform}" "${2}"
  else
    printf 'FAIL: [%s %s] %s\n' "${release}" "${platform}" "${2}"
    failures=$((failures + 1))
  fi
}

wait_for_ssh 600
vm cloud-init status --wait > /dev/null || true
if [ "${platform}" = ec2 ]; then
  # The cloud image runs the generic kernel; the AMIs run linux-aws, whose
  # modules are packaged differently
  vm 'sudo apt-get -q update --error-on=any > /dev/null && sudo DEBIAN_FRONTEND=noninteractive apt-get -q install -y linux-aws > /dev/null &&
    echo GRUB_FLAVOUR_ORDER=aws | sudo tee /etc/default/grub.d/99-linux-aws.cfg > /dev/null && sudo update-grub 2> /dev/null'
  reboot_vm
  check 'the VM runs the linux-aws kernel, as the AMIs do' 'uname -r | grep -q -- "-aws\$"'
fi
vm 'cat /etc/os-release; uname -r; cat /sys/devices/virtual/dmi/id/board_vendor 2> /dev/null || true'

# The checkout's tracked and unignored files; first_install links the startup
# scripts from where it is, so it has to stay
(cd "${repo}" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) \
  | vm 'sudo mkdir -p /opt/rfctf-container && sudo tar -C /opt/rfctf-container -xf -'

check 'first_install runs on a fresh install' 'cd /opt/rfctf-container/misc && sudo ./first_install'
check 'and again' 'cd /opt/rfctf-container/misc && sudo ./first_install > /dev/null 2>&1'
check 'docker is installed and remaps user namespaces' \
  "docker --version && sudo docker info --format '{{.SecurityOptions}}' | grep -q name=userns"
if [ "${platform}" = ec2 ]; then
  check 'the AWS CLI is installed' 'aws --version'
fi

reboot_vm
# rc-local runs the startup scripts; its unit has RemainAfterExit, so it is
# done once its SubState is exited
waited=0
until [ "$(vm systemctl show -p SubState --value rc-local)" = exited ] \
  || [ "$(vm systemctl show -p ActiveState --value rc-local)" = failed ] || [ "${waited}" -ge 2400 ]; do
  sleep 15
  waited=$((waited + 15))
done
vm 'systemctl show -p ActiveState -p Result rc-local; sudo journalctl -b -u rc-local --no-pager | tail -n 100'
check "the startup doesn't ask Let's Encrypt for first_install's stub name" \
  "sudo journalctl -b -u rc-local --no-pager | grep -q 'is the stub from misc/first_install'"

# wait_healthy seconds container...: waits for docker to call each healthy
wait_healthy() {
  limit="${1}"
  shift
  waited=0
  while :; do
    unhealthy=""
    for c in "$@"; do
      if [ "$(vm sudo docker inspect -f '{{.State.Health.Status}}' "${c}" 2> /dev/null)" != healthy ]; then
        unhealthy="${unhealthy} ${c}"
      fi
    done
    if [ -z "${unhealthy}" ] || [ "${waited}" -ge "${limit}" ]; then
      break
    fi
    sleep 15
    waited=$((waited + 15))
  done
  [ -z "${unhealthy}" ] || printf 'Not healthy:%s\n' "${unhealthy}"
  [ -z "${unhealthy}" ]
}
vm 'sudo docker ps -a --format "{{.Names}}\t{{.Status}}"'
if wait_healthy 900 openwrt pentoo-contestant kali-contestant parrot-contestant blackarch-contestant; then
  result 0 'openwrt and the four contestants are healthy'
else
  result 1 'openwrt and the four contestants are healthy'
fi
# The public openwrt image lacks the 11r and 11w APs until it's rebuilt, so
# those clients can't connect yet; --test checks every client is running and
# trying
check "rfctf-client's clients are running and trying to connect" \
  'sudo docker exec -w /root/leeloodallasmultipass rfctf-client ./ldm_checker --test | tail -n 1'
for c in openwrt rfctf-client; do
  check "${c} runs unprivileged" "[ \"\$(sudo docker inspect -f '{{.HostConfig.Privileged}}' ${c})\" = false ]"
done
for c in pentoo-contestant kali-contestant parrot-contestant blackarch-contestant; do
  check "${c} runs unprivileged with its four radios" \
    "[ \"\$(sudo docker inspect -f '{{.HostConfig.Privileged}}' ${c})\" = false ] && [ \"\$(sudo docker exec ${c} sh -c 'iw dev | grep -c Interface')\" = 4 ]"
done

if [ "${failures}" -ne 0 ]; then
  # shellcheck disable=SC2016 # it expands in the VM
  vm 'sudo docker ps -a; for c in $(sudo docker ps -aq); do echo "== $(sudo docker inspect -f "{{.Name}}" "${c}")"; sudo docker logs --tail 40 "${c}" 2>&1; done' || true
  printf '%s check(s) failed\n' "${failures}"
  exit 1
fi
