#!/bin/bash

is_vm() {
  # Adapted from systemd src/basic/virt.c
  dmi='/sys/class/dmi/id'
  for file in product_name sys_vendor board_vendor bios_vendor product_version; do
    if [ -r "${dmi}/${file}" ]; then
      case "$(cat "${dmi}/${file}")" in
        KVM*) return 0;;
        OpenStack*) return 0;;
        KubeVirt*) return 0;;
        Amazon\ EC2*) return 0;;
        QEMU*) return 0;;
        VMware*) return 0;;
        VMw*) return 0;;
        innotek\ GmbH*) return 0;;
        VirtualBox*) return 0;;
        Xen*) return 0;;
        Bochs*) return 0;;
        Parallels*) return 0;;
        BHYVE*) return 0;;
        Hyper-V*) return 0;;
        Apple\ Virtualization*) return 0;;
      esac
    fi
  done
  return 1
}

# The *_args functions print docker run arguments one per line, which
# rfhs-container-init splits on newlines; warnings go to stderr.

x_display_number() {
  n="${1#*:}"
  printf '%s' "${n%%.*}"
}

# Wait up to ${2} seconds for X display ${1} to be listening
wait_for_x() {
  waited=0
  while [ ! -S "/tmp/.X11-unix/X$(x_display_number "${1}")" ]; do
    if [ "${waited}" -ge "${2}" ]; then
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

# The -auth file of the X server for display ${1}. Servers started without a
# display argument (slim, gdm's -displayfd) count as :0 if no server names it.
x_server_auth() {
  num="$(x_display_number "${1}")"
  fallback=""
  for cmdline in /proc/[0-9]*/cmdline; do
    found="$({ tr '\0' '\n' < "${cmdline}"; } 2>/dev/null | awk '
      NR == 1 { n = split($0, path, "/") }
      NR == 1 && path[n] !~ /^(X|Xorg|Xwayland|Xvfb|Xvnc|Xtigervnc|Xephyr)$/ { exit }
      NR == 1 { xserver = 1; next }
      want_auth { auth = $0; want_auth = 0; next }
      $0 == "-auth" { want_auth = 1; next }
      /^:[0-9]+$/ { display = substr($0, 2) }
      END { if (xserver && auth != "") print (display == "" ? "-" : display) " " auth }')" || continue
    case "${found}" in
      "${num} "*) printf '%s' "${found#* }"; return 0;;
      "- "*) [ -z "${fallback}" ] && fallback="${found#* }";;
    esac
  done
  if [ "${num}" = "0" ] && [ -n "${fallback}" ]; then
    printf '%s' "${fallback}"
  fi
}

# Display managers write the cookie for this host's name (FamilyLocal) and
# Xlib only offers a cookie whose host matches, hence --hostname. --ipc=host
# is for MIT-SHM, which Mesa and Qt use to hand images to the X server.
x11_docker_args() {
  printf '%s\n' -e "DISPLAY=${1}" -v /tmp/.X11-unix:/tmp/.X11-unix --ipc=host --hostname "$(uname -n)"
  auth="$(x_server_auth "${1}")"
  if [ -z "${auth}" ] && [ -n "${XAUTHORITY:-}" ] && [ -r "${XAUTHORITY}" ]; then
    auth="${XAUTHORITY}"
  fi
  if [ -n "${auth}" ]; then
    # --mount, because -v splits on the colon in names like lightdm's /var/run/lightdm/root/:0
    printf '%s\n' --mount "type=bind,source=${auth},target=/tmp/.Xauthority,readonly" -e XAUTHORITY=/tmp/.Xauthority
  else
    printf 'WARNING: no cookie found for X display %s, the container can only connect if the X server allows it without one (xhost)\n' "${1}" >&2
  fi
}

# NVIDIA's OpenGL and OpenCL libraries only come from the host, through the
# NVIDIA Container Toolkit
gpu_docker_args() {
  if [ -d /dev/dri ]; then
    printf '%s\n' --device /dev/dri
  fi
  if [ -c /dev/kfd ]; then
    printf '%s\n' --device /dev/kfd
  fi
  if [ -c /dev/nvidiactl ]; then
    # docker's --gpus is implemented by the toolkit's hook
    if command -v nvidia-container-runtime-hook > /dev/null 2>&1 || command -v nvidia-container-toolkit > /dev/null 2>&1; then
      printf '%s\n' --gpus all
    elif command -v nvidia-ctk > /dev/null 2>&1 && ls /etc/cdi/*nvidia* /var/run/cdi/*nvidia* > /dev/null 2>&1; then
      printf '%s\n' --device nvidia.com/gpu=all
    else
      printf 'WARNING: NVIDIA driver found but not the NVIDIA Container Toolkit. The X server will want the NVIDIA OpenGL libraries, which the container only gets through the toolkit: install it (nvidia-container-toolkit) and restart docker.\n' >&2
    fi
  fi
}

# The directories are mounted, not the nodes, and the cgroup rules allow the
# whole major numbers, so replugged SDRs and knobs show up
usb_input_docker_args() {
  printf '%s\n' -v /dev/bus/usb:/dev/bus/usb --device-cgroup-rule 'c 189:* rmw' \
    -v /dev/input:/dev/input --device-cgroup-rule 'c 13:* rmw'
  # udev's database names the devices for lsusb and libusb
  if [ -d /run/udev ]; then
    printf '%s\n' -v /run/udev:/run/udev:ro
  fi
}

# The privileges each game container runs with, in place of --privileged.
# Only the contestants run with docker's remapping, as uid 231072; the others
# need host root's devices and restricted files, so --userns host.
# rfhs-container-init starts the containers with these, and the build scripts
# and tools/hwsim_containers.sh test the images with them, so an image that
# needs more fails its build. dhcpcd sets the promote_secondaries sysctl on
# each interface it starts on, and exits when it can't: /proc/sys is
# read-only, and a radio moved into a container takes the namespace's
# default, which otherwise comes from the host.
# dac_read_search: Pentoo's dumpcap has it as a file capability, so without
# it in the container's bounding set dumpcap can't run and nothing captures.
# seccomp: rfhs-contestant-seccomp.json, in the directory given (where this
# file is), is docker's default profile from moby/profiles plus the user
# namespaces Firefox's content sandbox and bwrap make.
# apparmor=rfhs-contestant: docker's AppArmor profile plus bwrap's mounts,
# without which Kali's and BlackArch's GTK abort when glycin can't sandbox
# its image loaders; misc/contestant_apparmor loads the profile.
contestant_docker_args() {
  printf '%s\n' --cap-add net_raw --cap-add net_admin --cap-add dac_read_search \
    --security-opt "seccomp=${1:?contestant_docker_args needs the directory of rfhs-contestant-seccomp.json}/rfhs-contestant-seccomp.json" \
    --sysctl net.ipv4.conf.default.promote_secondaries=1
  if [ "$(cat /sys/module/apparmor/parameters/enabled 2> /dev/null)" = Y ]; then
    printf '%s\n' --security-opt apparmor=rfhs-contestant
  fi
}

# contestant_profiles_ready dir: whether the contestants' seccomp profile is
# in dir, as contestant_docker_args uses it, and AppArmor, where it's on, has
# loaded rfhs-contestant; otherwise says how to put them in place, as docker
# run only says it can't find them
contestant_profiles_ready() {
  if [ ! -r "${1}/rfhs-contestant-seccomp.json" ]; then
    printf "%s has no rfhs-contestant-seccomp.json, the contestants' seccomp profile; run misc/first_install from the rfctf-container checkout, which links it there with the startup scripts\n" "${1}" >&2
    return 1
  fi
  [ "$(cat /sys/module/apparmor/parameters/enabled 2> /dev/null)" = Y ] || return 0
  for profile in /sys/kernel/security/apparmor/policy/profiles/rfhs-contestant.*; do
    if [ "$(cat "${profile}/name" 2> /dev/null)" = rfhs-contestant ]; then
      return 0
    fi
  done
  printf "AppArmor hasn't loaded rfhs-contestant, the contestants' profile; run misc/contestant_apparmor from the rfctf-container checkout as root (misc/first_install does)\n" >&2
  return 1
}

rfctf_client_docker_args() {
  printf '%s\n' --userns host --cap-add net_raw --cap-add net_admin --sysctl net.ipv4.conf.default.promote_secondaries=1
}

# The SDRs, as usb_input_docker_args does
rfctf_sdr_docker_args() {
  printf '%s\n' --userns host -v /dev/bus/usb:/dev/bus/usb --device-cgroup-rule 'c 189:* rmw'
  if [ -d /run/udev ]; then
    printf '%s\n' -v /run/udev:/run/udev:ro
  fi
}

# The per-namespace sysctls from openwrt's /etc/sysctl.d, which it can't set
# itself. With --privileged it also set its kernel.*, fs.* and vm.* ones on
# the host, and procd took the host's hardware watchdog, which reset the host
# a minute after the container stopped. procd mounts no tmpfs on /tmp, which
# /var links to, without privileges.
openwrt_docker_args() {
  printf '%s\n' --userns host --cap-add net_admin --cap-add net_raw \
    --tmpfs /tmp:mode=1777,nosuid,nodev,exec,nr_inodes=800k,size=20% \
    --sysctl net.ipv4.ip_forward=1 \
    --sysctl net.ipv4.conf.all.arp_ignore=1 --sysctl net.ipv4.conf.default.arp_ignore=1 \
    --sysctl net.ipv4.igmp_max_memberships=100 \
    --sysctl net.ipv4.tcp_fin_timeout=30 --sysctl net.ipv4.tcp_keepalive_time=120 \
    --sysctl net.ipv6.conf.all.forwarding=1 --sysctl net.ipv6.conf.default.forwarding=1 \
    --sysctl net.ipv6.conf.all.accept_ra=0 --sysctl net.ipv6.conf.default.accept_ra=0
}
