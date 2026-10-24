# Tools for the infrastructure containers

## pkg_sizes.py

Shows where the space goes in an image built on Pentoo: the biggest
packages, optionally only the ones added on top of the base image, and how
much of their files are kinds a runtime image can usually do without
(headers, static libraries, extra Python bytecode, 32-bit libraries, ...).
It needs only Python 3, so it runs in any of the images:

```sh
# the packages in pentoo-core, to leave out
docker run --rm pentoolinux/pentoo-core sh -c \
  'cd /var/db/pkg && for p in */*; do echo "$p $(cat $p/COUNTER)"; done' > base.txt

# what an image adds on top of it
docker run --rm -v "$PWD:/t:ro" rfhs/fosphor_knob \
  python3 /t/pkg_sizes.py --base /t/base.txt --kinds
```

Run it from this directory, so that `base.txt` and the script are both in
`/t`. Without `--base` it lists every package in the image. Packages that
were reinstalled over the base are marked: their files are in the image
twice, once in each layer.

## make_gentoo_cache.sh (one directory up)

Makes `portage_and_overlay.tar.xz`, the Gentoo and Pentoo trees the images
build from, matched to what the Pentoo binhost built its packages from. A
newer tree than the binhost's makes emerge build the newer versions from
source, and an older one downgrades: both put copies of base packages in the
image. `contestant_containers/make_gentoo_cache.sh` is a link to the same
script.

```sh
./make_gentoo_cache.sh               # writes ./portage_and_overlay.tar.xz
# anywhere without the Gentoo and Pentoo keyrings:
docker run --rm -v "$PWD:/work" -w /work docker.io/pentoolinux/pentoo-core:latest ./make_gentoo_cache.sh
```

- It uses exactly the revisions in the build host's `TREE` (see below), and
  exits 1 if it can't fetch it.
- Gentoo comes from the gentoo-mirror git repository, which carries the
  metadata cache; Pentoo comes from pentoo-overlay on GitHub.
- The branch tips are verified with gpgv against
  `/usr/share/openpgp-keys/gentoo-release.asc` and
  `/usr/share/pentoo/pentoo-keyring.asc` (override with `GENTOO_KEY` and
  `PENTOO_KEY`), as portage does on sync; the commits used have to be in
  their history. gpgv never starts gpg-agent or touches your own keys.
- It exits 1 with a warning if the tree is more than 7 days old.
- The tarball's mtime is the gentoo-mirror commit's time, so the build
  scripts' 7-day check is on the age of the tree, not of the file.
- Other overrides: `TREE_URL` (default `https://pentoo.glpgs.io/TREE`),
  `BINHOST` (default `https://pentoo.glpgs.io/Packages/amd64_23.0s-hardened`,
  the profile pentoo-core uses, whose index `TIMESTAMP` is checked against
  `TREE`), `GENTOO_GIT`, `GENTOO_BRANCH`, `PENTOO_GIT`, `PENTOO_BRANCH`.

It needs git, curl, gpgv, base64, GNU tar and xz, and no root. It takes
about a minute and downloads about 130 MB; the tarball is about 35 MB.

## TREE

pentoo-livecd's `specs/snap.sh` writes it at the end of every snapshot, to
`/catalyst/packages/local_mirror/TREE` on the build host, which the mirror
serves as `https://pentoo.glpgs.io/TREE` for every profile:

```
PUBLISHED: 1792776600
GENTOO_MIRROR_COMMIT: 7499b687d0dfced56fe88dc3d1d8f06c700c2dd0
GENTOO_MIRROR_COMMIT_TIME: 1792771258
PENTOO_COMMIT: 51da1a6d95a00c815408c572e7155a6ed00d92c8
```

The Gentoo commit is the `stable` commit catalyst made its snapshot from, and
the Pentoo one is the overlay checkout catalyst builds with. The binhost's
packages are built after the snapshot, so make_gentoo_cache.sh warns when
`TREE` is newer than the binhost index: the build run for that snapshot
failed or hasn't finished, and the packages may come from an older tree.

## test_make_gentoo_cache.sh

Tests make_gentoo_cache.sh: it serves a fake binhost from 127.0.0.1 with
`TREE` files that name real gentoo-mirror and pentoo-overlay commits (it
creates no commits of its own), and checks the exported tree and its
metadata cache, the tarball's mtime, the warning for a `TREE` newer than
the index, the 7-day limit, a malformed or missing `TREE` and the wrong
keyring. It needs the network and python3; from
`infrastructure_containers`, on Gentoo/Pentoo or in pentoo-core:

```sh
./tools/test_make_gentoo_cache.sh
docker run --rm -v "$PWD:/work" -w /work docker.io/pentoolinux/pentoo-core:latest ./tools/test_make_gentoo_cache.sh
```

It takes about three minutes and prints PASS or FAIL for each check.
