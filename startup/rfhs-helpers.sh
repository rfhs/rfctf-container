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
