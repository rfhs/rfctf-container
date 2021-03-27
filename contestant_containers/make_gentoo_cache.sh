#!/bin/sh

set -e

##make the gentoo portage module
rm -rf /dev/shm/portage/rootfs/var/db/repos/gentoo
mkdir -p /dev/shm/portage/rootfs/var/db/repos/gentoo
rsync -aEXu --delete /var/db/repos/gentoo/* /dev/shm/portage/rootfs/var/db/repos/gentoo
## add the pentoo overlay
mkdir -p /dev/shm/portage/rootfs/var/db/repos/pentoo/
rsync -aEXu --progress --delete /var/db/repos/pentoo/ /dev/shm/portage/rootfs/var/db/repos/pentoo/
#fix the perms
chown root.root /dev/shm/portage/rootfs/var/db/repos
chown root.root /dev/shm/portage/rootfs/var/db
chown root.root /dev/shm/portage/rootfs/var
chown root.root /dev/shm/portage/rootfs
chown root.root /dev/shm/portage
chown portage.portage -R /dev/shm/portage/rootfs/var/db/repos/pentoo
chown portage.portage -R /dev/shm/portage/rootfs/var/db/repos/gentoo
# make the unified tarball
tar cJf repos.tar.xz -C /dev/shm/portage/rootfs/ .
#don't waste RAM forever
rm -rf /dev/shm/portage/rootfs/var/db/repos/gentoo
