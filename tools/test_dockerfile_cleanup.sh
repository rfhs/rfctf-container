#!/bin/sh
# Checks the cleanup in every Dockerfile step that runs emerge: it has to
# empty PKGDIR and every binrepos.conf location with eclean-pkg, since the
# Pentoo binhosts' binpkgs are kept under /var/cache/binhost rather than in
# PKGDIR, and rm -rf of the usual paths would leave them in the image. It
# also has to remove /etc/portage/gnupg, the Portage trust keyring with its
# private key, which each system has to make for itself.
#   ./tools/test_dockerfile_cleanup.sh [Dockerfile...]
set -eu

here="$(dirname "${0}")"
if [ "$#" -eq 0 ]; then
  set -- "${here}"/../*_containers/Dockerfile.*
fi
# shellcheck disable=SC2016 # the Dockerfile line, verbatim
eclean='mkdir -p "$(portageq pkgdir)" && ROOT=/var/empty eclean-pkg --deep &&'

failed=0
steps=0
for dockerfile in "$@"; do
  # one line per instruction, continuations joined, comment lines dropped
  instructions="$(awk '
    /^[[:space:]]*#/ { next }
    { line = line $0 }
    /\\$/ { sub(/\\$/, "", line); next }
    { print line; line = "" }
  ' "${dockerfile}")"
  n=0
  while IFS= read -r instruction; do
    case "${instruction}" in
      RUN*emerge\ *) ;;
      *) continue ;;
    esac
    n=$((n + 1))
    steps=$((steps + 1))
    name="${dockerfile##*/} RUN #${n}"
    squeezed="$(printf '%s\n' "${instruction}" | tr -s ' ')"
    case "${squeezed}" in
      *"${eclean}"*) printf 'ok   %s: empties every binpkg location with eclean-pkg\n' "${name}" ;;
      *) printf 'FAIL %s: does not run %s\n' "${name}" "${eclean}"; failed=1 ;;
    esac
    if printf '%s\n' "${squeezed}" | grep -qE 'rm -rf [^&]*/etc/portage/gnupg'; then
      printf 'ok   %s: removes /etc/portage/gnupg\n' "${name}"
    else
      printf 'FAIL %s: does not remove /etc/portage/gnupg\n' "${name}"
      failed=1
    fi
    if printf '%s\n' "${squeezed}" | grep -qE 'rm -rf [^&]*(binpkgs|PKGDIR|/var/cache/binhost)'; then
      printf 'FAIL %s: removes binpkg locations with rm, leave them to eclean-pkg\n' "${name}"
      failed=1
    else
      printf 'ok   %s: leaves the binpkg locations to eclean-pkg\n' "${name}"
    fi
  done <<INSTRUCTIONS
${instructions}
INSTRUCTIONS
done
if [ "${steps}" -eq 0 ]; then
  printf 'FAIL no Dockerfile step runs emerge\n'
  failed=1
fi
exit "${failed}"
