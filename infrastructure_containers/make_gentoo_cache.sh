#!/bin/sh
# Make portage_and_overlay.tar.xz from exactly the Gentoo and Pentoo trees in the
# build host's TREE (pentoo-livecd's snap.sh writes it), the ones the Pentoo
# binhost built its packages from.
#
# Usage: ./make_gentoo_cache.sh [OUTPUT]    (default ./portage_and_overlay.tar.xz)
# Needs git, curl, gpgv, base64, GNU tar, xz and the Gentoo and Pentoo
# keyrings; anywhere else, run it in pentoo-core:
#   docker run --rm -v "$PWD:/work" -w /work docker.io/pentoolinux/pentoo-core:latest ./make_gentoo_cache.sh
set -eu

OUTPUT="${1:-portage_and_overlay.tar.xz}"
BINHOST="${BINHOST:-https://pentoo.glpgs.io/Packages/amd64_23.0s-hardened}"
BINHOST="${BINHOST%/}"
TREE_URL="${TREE_URL:-https://pentoo.glpgs.io/TREE}"
GENTOO_GIT="${GENTOO_GIT:-https://github.com/gentoo-mirror/gentoo.git}"
GENTOO_BRANCH="${GENTOO_BRANCH:-stable}"
GENTOO_KEY="${GENTOO_KEY:-/usr/share/openpgp-keys/gentoo-release.asc}"
PENTOO_GIT="${PENTOO_GIT:-https://github.com/pentoo/pentoo-overlay.git}"
PENTOO_BRANCH="${PENTOO_BRANCH:-master}"
PENTOO_KEY="${PENTOO_KEY:-/usr/share/pentoo/pentoo-keyring.asc}"
MAX_AGE_DAYS=7
# ignore the user's git config (signing, hooks)
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

die() {
  printf 'make_gentoo_cache.sh: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

utc() {
  date -u -d "@${1}" '+%Y-%m-%d %H:%M:%S UTC'
}

too_old() {
  # $1: unix time of the tree, $2: what it is
  if [ "$(( $(date +%s) - ${1} ))" -gt "$(( MAX_AGE_DAYS * 86400 ))" ]; then
    warn "${2} is from $(utc "${1}"), more than ${MAX_AGE_DAYS} days ago."
    warn "The binhost hasn't finished a build run since then; refusing to make a snapshot this old."
    exit 1
  fi
}

missing_tools=""
for tool in awk base64 cat chmod curl date git gpgv grep head mkdir mktemp mv rm sed tar touch tr wc xz; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
[ -z "${missing_tools}" ] || die "required commands not found:${missing_tools}"
for key in "${GENTOO_KEY}" "${PENTOO_KEY}"; do
  if [ ! -r "${key}" ]; then
    die "can't read the signing keys ${key}; set GENTOO_KEY/PENTOO_KEY, or run this in docker.io/pentoolinux/pentoo-core"
  fi
done

work="$(mktemp -d "${TMPDIR:-/var/tmp}/make_gentoo_cache.XXXXXX")"
cleanup() {
  # gpgv starts no agents; this is in case anything ever did
  if [ -d "${work}/gnupg" ] && command -v gpgconf > /dev/null 2>&1; then
    GNUPGHOME="${work}/gnupg" gpgconf --kill all > /dev/null 2>&1 || true
  fi
  rm -rf "${work}" "${OUTPUT}.tmp.$$"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

# gpgv only verifies against the keyring it's given, never starts agents and
# never reads the user's GNUPGHOME; the wrapper drops the gpg options git
# passes. One keyring per repo, so neither's keys can sign the other's commits.
mkdir -m 700 "${work}/gnupg"
printf 'disable-scdaemon\n' > "${work}/gnupg/gpg-agent.conf"
cat > "${work}/gpgv-git" << 'EOF'
#!/bin/sh
for arg; do
  shift
  case "${arg}" in
    --keyid-format=* | --verify) ;;
    *) set -- "$@" "${arg}" ;;
  esac
done
exec gpgv --homedir "${GV_HOME}" --keyring "${GV_KEYRING}" "$@"
EOF
chmod 755 "${work}/gpgv-git"
dearmor() {
  # $1: armored keyring, $2: output; every public key block in $1, unarmored for gpgv
  rm -f "${2}" "${work}/block."*
  awk -v out="${work}/block." '
    /^-----BEGIN PGP PUBLIC KEY BLOCK-----/ { n++; body = 0; next }
    /^-----END PGP PUBLIC KEY BLOCK-----/ { body = -1; next }
    body == 0 && /^[[:space:]]*$/ { body = 1; next }
    body == 1 && !/^=/ { print > (out n) }' "${1}"
  for block in "${work}/block."*; do
    [ -f "${block}" ] || die "no public key block in ${1}"
    base64 -d "${block}" >> "${2}" || die "can't decode ${1}"
  done
}
dearmor "${GENTOO_KEY}" "${work}/gentoo.gpg"
dearmor "${PENTOO_KEY}" "${work}/pentoo.gpg"

verify_commit() {
  # $1: repo name (gentoo/pentoo), $2: commit
  if GNUPGHOME="${work}/gnupg" GV_HOME="${work}/gnupg" GV_KEYRING="${work}/${1}.gpg" \
      git -C "${work}/${1}.git" -c gpg.program="${work}/gpgv-git" verify-commit --raw "${2}" \
      2> "${work}/verify.out" && grep -q '^\[GNUPG:\] GOODSIG ' "${work}/verify.out"; then
    return 0
  fi
  cat "${work}/verify.out" >&2
  die "the ${1} commit ${2} isn't signed by a key in its keyring"
}

# Read one "KEY: value" field from a binhost file, only if it matches $3.
field() {
  sed -n "s/^${1}: *\(${3}\) *\$/\1/p" "${2}" | head -n 1
}
SHA='[0-9a-f]\{40\}'
NUM='[0-9]\{1,\}'

printf 'Reading the binhost index: %s/Packages\n' "${BINHOST}"
# The header ends at the first empty line; the packages follow.
curl -fsSL -r 0-65535 -o "${work}/Packages.part" "${BINHOST}/Packages" || die "can't fetch ${BINHOST}/Packages"
sed -n '/^$/q;p' "${work}/Packages.part" > "${work}/Packages"
index_ts="$(field TIMESTAMP "${work}/Packages" "${NUM}")"
[ -n "${index_ts}" ] || die "${BINHOST}/Packages has no TIMESTAMP"
printf 'Binhost index TIMESTAMP: %s\n' "$(utc "${index_ts}")"

curl -fsSL -o "${work}/TREE" "${TREE_URL}" || die "can't fetch ${TREE_URL}"
gentoo_c="$(field GENTOO_MIRROR_COMMIT "${work}/TREE" "${SHA}")"
gentoo_c_ts="$(field GENTOO_MIRROR_COMMIT_TIME "${work}/TREE" "${NUM}")"
pentoo_p="$(field PENTOO_COMMIT "${work}/TREE" "${SHA}")"
published="$(field PUBLISHED "${work}/TREE" "${NUM}")"
{ [ -n "${gentoo_c}" ] && [ -n "${gentoo_c_ts}" ]; } || die "${TREE_URL} has no valid GENTOO_MIRROR_COMMIT with its time"
[ -n "${pentoo_p}" ] || die "${TREE_URL} has no valid PENTOO_COMMIT"
[ -n "${published}" ] || die "${TREE_URL} has no valid PUBLISHED"
if [ "${index_ts}" -lt "${published}" ]; then
  warn "TREE was written ($(utc "${published}")) after the binhost index: the build run for it failed or hasn't finished, so the packages may come from an older tree."
fi
too_old "${gentoo_c_ts}" "The binhost's tree"

# only as deep as it takes to reach the TREE commit
since="$(date -u -d "@$(( gentoo_c_ts - 3 * 86400 ))" '+%Y-%m-%dT%H:%M:%SZ')"
printf 'Fetching %s %s since %s\n' "${GENTOO_GIT}" "${GENTOO_BRANCH}" "${since}"
git init -q --bare "${work}/gentoo.git"
git -C "${work}/gentoo.git" fetch -q --shallow-since="${since}" "${GENTOO_GIT}" \
  "+refs/heads/${GENTOO_BRANCH}:refs/heads/${GENTOO_BRANCH}" || die "fetching ${GENTOO_GIT} failed"
printf 'Fetching %s %s\n' "${PENTOO_GIT}" "${PENTOO_BRANCH}"
git init -q --bare "${work}/pentoo.git"
git -C "${work}/pentoo.git" fetch -q "${PENTOO_GIT}" \
  "+refs/heads/${PENTOO_BRANCH}:refs/heads/${PENTOO_BRANCH}" || die "fetching ${PENTOO_GIT} failed"

# Only the tips are signed; the TREE commits must be in their history.
verify_commit gentoo "${GENTOO_BRANCH}"
verify_commit pentoo "${PENTOO_BRANCH}"

in_history() {
  # $1: repo name, $2: commit, $3: branch
  git -C "${work}/${1}.git" cat-file -e "${2}^{commit}" 2> /dev/null &&
    git -C "${work}/${1}.git" merge-base --is-ancestor "${2}" "${3}"
}
in_history gentoo "${gentoo_c}" "${GENTOO_BRANCH}" ||
  die "the binhost's gentoo-mirror commit ${gentoo_c} isn't on ${GENTOO_GIT} ${GENTOO_BRANCH}"
in_history pentoo "${pentoo_p}" "${PENTOO_BRANCH}" ||
  die "the binhost's pentoo commit ${pentoo_p} isn't on ${PENTOO_GIT} ${PENTOO_BRANCH}"

commit_time() {
  git -C "${work}/${1}.git" log -1 --format=%ct "${2}"
}
tree_ts="$(commit_time gentoo "${gentoo_c}")"
too_old "${tree_ts}" "The Gentoo tree"

printf 'Exporting the trees\n'
root="${work}/root"
mkdir -p "${root}/var/db/repos/gentoo" "${root}/var/db/repos/pentoo"
export_tree() {
  # $1: repo name, $2: commit
  git -C "${work}/${1}.git" -c tar.umask=0022 archive -o "${work}/export.tar" "${2}" ||
    die "exporting ${1} ${2} failed"
  tar -xf "${work}/export.tar" -C "${root}/var/db/repos/${1}" || die "unpacking ${1} failed"
  rm -f "${work}/export.tar"
}
export_tree gentoo "${gentoo_c}"
export_tree pentoo "${pentoo_p}"

printf 'Compressing %s\n' "${OUTPUT}"
tar -cf "${work}/tree.tar" --numeric-owner --owner=0 --group=0 --no-recursion \
  -C "${root}" . ./var ./var/db ./var/db/repos
tar -rf "${work}/tree.tar" --owner=portage:250 --group=portage:250 \
  -C "${root}" ./var/db/repos/gentoo ./var/db/repos/pentoo
rm -rf "${root}"
xz -T0 -c "${work}/tree.tar" > "${OUTPUT}.tmp.$$" || die "compressing failed"
# the build scripts' age check reads the mtime
touch -d "@${tree_ts}" "${OUTPUT}.tmp.$$"
mv "${OUTPUT}.tmp.$$" "${OUTPUT}"

printf '\nWrote %s (%s bytes)\n' "${OUTPUT}" "$(wc -c < "${OUTPUT}" | tr -d ' ')"
printf '  binhost:     %s, index TIMESTAMP %s\n' "${BINHOST}" "$(utc "${index_ts}")"
printf '  gentoo-mirror: %s (%s)\n' "${gentoo_c}" "$(utc "${tree_ts}")"
printf '  pentoo:      %s (%s)\n' "${pentoo_p}" "$(utc "$(commit_time pentoo "${pentoo_p}")")"
