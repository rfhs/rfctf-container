#!/bin/sh
# Tests make_gentoo_cache.sh against a fake binhost on 127.0.0.1, using real
# gentoo-mirror and pentoo-overlay commits (it makes none).
# Needs the network, python3 and the Gentoo and Pentoo keyrings; from
# infrastructure_containers, run it as is or in pentoo-core:
#   ./tools/test_make_gentoo_cache.sh
#   docker run --rm -v "$PWD:/work" -w /work docker.io/pentoolinux/pentoo-core:latest ./tools/test_make_gentoo_cache.sh
set -eu

here="$(cd "$(dirname "${0}")" && pwd)"
snapshot="${here}/../make_gentoo_cache.sh"
GENTOO_GIT="${GENTOO_GIT:-https://github.com/gentoo-mirror/gentoo.git}"
PENTOO_GIT="${PENTOO_GIT:-https://github.com/pentoo/pentoo-overlay.git}"
export GENTOO_GIT PENTOO_GIT
# ignore the user's git config (signing, hooks)
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

t="$(mktemp -d "${TMPDIR:-/var/tmp}/test_make_gentoo_cache.XXXXXX")"
server=""
trap '[ -n "${server}" ] && kill "${server}"; rm -rf "${t}"' EXIT
failures=0
pass() {
  printf 'PASS: %s\n' "$*"
}
fail() {
  printf 'FAIL: %s\n' "$*"
  failures=$((failures + 1))
}

now="$(date +%s)"
mkdir -p "${t}/binhost" "${t}/run"
printf 'Picking commits from %s and %s\n' "${GENTOO_GIT}" "${PENTOO_GIT}"
git init -q --bare "${t}/gentoo.git"
git -C "${t}/gentoo.git" fetch -q --shallow-since="$(date -u -d "@$((now - 2 * 86400))" '+%Y-%m-%dT%H:%M:%SZ')" \
  "${GENTOO_GIT}" +refs/heads/stable:refs/heads/stable
git init -q --bare "${t}/pentoo.git"
git -C "${t}/pentoo.git" fetch -q "${PENTOO_GIT}" +refs/heads/master:refs/heads/master

# gentoo-mirror's metadata cache commits, newest first: each one's parent merges master
git -C "${t}/gentoo.git" log --first-parent --format='%H %P' stable > "${t}/log"
awk 'NR == FNR { if (NF == 3) merge[$1] = 1; next }
  NF == 2 && ($2 in merge) { print $1 }' "${t}/log" "${t}/log" > "${t}/cache"
# not the newest, so it isn't just "the tip"
cache_c="$(sed -n '2p' "${t}/cache")"
pentoo_p="$(git -C "${t}/pentoo.git" rev-parse master~3)"
time_of() {
  git -C "${t}/${1}.git" log -1 --format=%ct "${2}"
}
write_tree() {
  # $1: PUBLISHED; the format pentoo-livecd's snap.sh writes
  cat > "${t}/binhost/TREE" << EOF
PUBLISHED: ${1}
GENTOO_MIRROR_COMMIT: ${cache_c}
GENTOO_MIRROR_COMMIT_TIME: $(time_of gentoo "${cache_c}")
PENTOO_COMMIT: ${pentoo_p}
EOF
}

printf 'TIMESTAMP: %s\n\nCPV: fake/package-1\n' "${now}" > "${t}/binhost/Packages"
write_tree "$((now + 60))"

port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
python3 -m http.server --bind 127.0.0.1 --directory "${t}/binhost" "${port}" > "${t}/http.log" 2>&1 &
server=$!
sleep 1
export BINHOST="http://127.0.0.1:${port}"
export TREE_URL="${BINHOST}/TREE"

snap() {
  # $1: test name; output in ${t}/run/$1.log, tarball ${t}/run/$1.tar.xz
  (cd "${t}/run" && "${snapshot}" "${1}.tar.xz") > "${t}/run/${1}.log" 2>&1
}
expect() {
  # $1: test name, $2: grep -E pattern the output must have
  if grep -Eq -- "${2}" "${t}/run/${1}.log"; then
    return 0
  fi
  printf -- '--- %s output:\n' "${1}"
  cat "${t}/run/${1}.log"
  return 1
}

if snap mirror && expect mirror "^  gentoo-mirror: ${cache_c} " && expect mirror "^  pentoo:      ${pentoo_p} " &&
    expect mirror "after the binhost index"; then
  git -C "${t}/gentoo.git" ls-tree -r --name-only "${cache_c}" | sort > "${t}/want"
  tar -tJf "${t}/run/mirror.tar.xz" | sed -n 's#^\./var/db/repos/gentoo/##p' | grep -v -e '/$' -e '^$' | sort > "${t}/got"
  if cmp -s "${t}/want" "${t}/got" && grep -q '^metadata/md5-cache/' "${t}/got"; then
    pass "a published gentoo-mirror commit is exported as it is, metadata cache included, and a TREE newer than the index is warned about"
  else
    fail "the gentoo-mirror commit's tree differs from the tarball"
  fi
else
  fail "published gentoo-mirror commit"
fi
if [ "$(date -r "${t}/run/mirror.tar.xz" +%s)" = "$(time_of gentoo "${cache_c}")" ]; then
  pass "the tarball's mtime is the gentoo-mirror commit time"
else
  fail "the tarball's mtime isn't the gentoo-mirror commit time"
fi

sed -i "s/^GENTOO_MIRROR_COMMIT_TIME: .*/GENTOO_MIRROR_COMMIT_TIME: $((now - 8 * 86400))/" "${t}/binhost/TREE"
if ! snap old && expect old "more than 7 days ago" && ! expect old Fetching > /dev/null; then
  pass "a tree more than 7 days old: warning and exit 1"
else
  fail "a tree more than 7 days old"
fi

sed -i "s/^PENTOO_COMMIT: .*/PENTOO_COMMIT: \$(id)/; s/^GENTOO_MIRROR_COMMIT_TIME: .*/GENTOO_MIRROR_COMMIT_TIME: ${now}/" \
  "${t}/binhost/TREE"
if ! snap bad && expect bad "no valid PENTOO_COMMIT"; then
  pass "an invalid TREE is refused"
else
  fail "an invalid TREE"
fi

rm "${t}/binhost/TREE"
if ! snap missing && expect missing "can't fetch ${TREE_URL}"; then
  pass "a missing TREE is refused"
else
  fail "a missing TREE"
fi

write_tree "$((now - 60))"
if ! GENTOO_KEY="${PENTOO_KEY:-/usr/share/pentoo/pentoo-keyring.asc}" snap wrongkey &&
    expect wrongkey "gentoo commit stable isn't signed by a key in its keyring"; then
  pass "a Gentoo tree checked against the wrong keyring is refused"
else
  fail "a Gentoo tree checked against the wrong keyring"
fi

if [ "${failures}" -gt 0 ]; then
  printf '%s test(s) failed\n' "${failures}"
  exit 1
fi
printf 'All tests passed\n'
