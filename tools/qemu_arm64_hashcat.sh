#!/bin/sh
# Runs contestant-checker's hashcat OpenCL test in an arm64 container of a
# distro's base image with only hashcat, pocl and the ICD loader installed,
# once for each emulated CPU, and reports whether hashcat cracked the hash,
# crashed or failed. On a failure it also prints hashcat -I and POCL_DEBUG=all
# output. hashcat dlopens libOpenCL, so the loader isn't one of its dependencies.
# Needs the host's binfmt_misc to run aarch64 binaries with a static
# qemu-aarch64 registered with the F flag, so containers don't need their own.
#   ./tools/qemu_arm64_hashcat.sh parrot|kali [qemu-cpu...]
# The default CPUs are neoverse-n2 (GitHub's arm64 runners), neoverse-v1,
# neoverse-n1 (no SVE) and max. Under emulation pocl takes minutes to build
# the kernel, so each CPU gets an hour.
set -eu

missing_tools=""
for tool in docker grep jq sed tail; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
if ! grep -q '^flags: .*F' /proc/sys/fs/binfmt_misc/qemu-aarch64 2> /dev/null; then
  printf 'aarch64 binaries need registering with binfmt_misc, with the F flag\n' >&2
  exit 1
fi

repo="$(cd "$(dirname "${0}")/.." && pwd)"
distro="${1:-}"
case "${distro}" in
  parrot)
    base="docker.io/parrotsec/core:latest"
    mount=""
    # as Dockerfile.parrot
    setup="echo 'deb https://deb.parrotsec.io/parrot echo main contrib non-free non-free-firmware' > /etc/apt/sources.list.d/parrotsec.list &&
      echo 'deb https://deb.parrotsec.io/direct/parrot echo-security main contrib non-free non-free-firmware' >> /etc/apt/sources.list.d/parrotsec.list &&
      echo 'deb https://deb.parrotsec.io/parrot echo-backports main contrib non-free non-free-firmware' >> /etc/apt/sources.list.d/parrotsec.list &&
      apt-get update --error-on=any"
    ;;
  kali)
    base="docker.io/kalilinux/kali-rolling:latest"
    mount="${repo}/contestant_containers/files/kali_apt_update:/tmp/kali_apt_update:ro"
    setup="sh /tmp/kali_apt_update"
    ;;
  *)
    printf 'Usage: %s parrot|kali [qemu-cpu...]\n' "${0##*/}" >&2
    exit 1
    ;;
esac
shift
if [ "$#" -eq 0 ]; then
  set -- neoverse-n2 neoverse-v1 neoverse-n1 max
fi

# Pulled by digest, so the host's amd64 :latest keeps its tag
digest="$(docker buildx imagetools inspect --raw "${base}" \
  | jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "arm64") | .digest' | sed -n 1p)"
if [ -z "${digest}" ]; then
  printf '%s has no linux/arm64 image\n' "${base}" >&2
  exit 1
fi
ref="${base%:*}@${digest}"
pulled=""
if ! docker image inspect "${ref}" > /dev/null 2>&1; then
  docker pull --platform linux/arm64 "${ref}"
  pulled=1
fi

name="claude-test-qemu-hashcat-${distro}"
image="claude-test/qemu-hashcat-${distro}"
remove_test() {
  docker rm -f "${name}" > /dev/null 2>&1 || true
  docker rmi "${image}" > /dev/null 2>&1 || true
}
cleanup() {
  remove_test
  if [ -n "${pulled}" ]; then
    docker rmi "${ref}" > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
remove_test

printf 'Installing hashcat and pocl in %s (arm64)...\n' "${ref}"
docker run --platform linux/arm64 --name "${name}" ${mount:+"--volume=${mount}"} "${ref}" sh -c "
  set -eu
  export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
  ${setup}
  nice -n 19 apt-get install --no-install-recommends -y hashcat pocl-opencl-icd ocl-icd-libopencl1
  dpkg-query -W hashcat pocl-opencl-icd ocl-icd-libopencl1"
docker commit "${name}" "${image}" > /dev/null
docker rm "${name}" > /dev/null

# contestant-checker's command, but with an hour for the emulated CPU
crack="printf 'password\nhashcat!\n' | timeout 3600 nice -n 19 hashcat -m 22000 -a 0 \
  --backend-ignore-cuda --backend-ignore-hip --session contestant-checker --restore-disable \
  --potfile-disable --logfile-disable --quiet \
  'WPA*01*4d4fe7aac3a2cecab195321ceb99a7d0*fc690c158264*f4747f87f9f4*686173686361742d6573736964***'"
results=""
for cpu in "$@"; do
  printf 'Cracking with QEMU_CPU=%s...\n' "${cpu}"
  out="$(docker run --rm --platform linux/arm64 -e QEMU_CPU="${cpu}" "${image}" sh -c "${crack}" 2>&1)" && rc=0 || rc=$?
  if printf '%s\n' "${out}" | grep -q ':hashcat!$'; then
    result="cracked it"
  elif [ "${rc}" = 139 ] || printf '%s\n' "${out}" | grep -q 'Segmentation fault'; then
    result="segfaulted"
  else
    result="failed with ${rc}"
  fi
  printf '%s\n%s: %s\n' "${out}" "${cpu}" "${result}"
  results="${results}${cpu}: ${result}
"
  if [ "${result}" != "cracked it" ]; then
    printf -- '--- hashcat -I with QEMU_CPU=%s\n' "${cpu}"
    docker run --rm --platform linux/arm64 -e QEMU_CPU="${cpu}" "${image}" \
      sh -c 'timeout 3600 hashcat -I 2>&1' || true
    printf -- '--- the last 60 lines with POCL_DEBUG=all, QEMU_CPU=%s\n' "${cpu}"
    docker run --rm --platform linux/arm64 -e QEMU_CPU="${cpu}" -e POCL_DEBUG=all "${image}" \
      sh -c "${crack} 2>&1" 2>&1 | tail -n 60 || true
  fi
done
printf '\n%s (arm64):\n%s' "${distro}" "${results}"
