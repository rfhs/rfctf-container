#!/bin/sh
# Checks misc/first_install's package function on an Ubuntu release: in an
# ubuntu:release container, for every command first_install's needs lines
# name, the package it gives has to install and provide that command, with
# the file it runs from that package or one it depends on, so first_install
# can install whatever a host is missing.
#   ./tools/test_first_install_packages.sh 24.04
set -eu

missing_tools=""
for tool in docker sed sort; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
if [ "$#" -ne 1 ]; then
  printf 'usage: %s release\n' "${0}" >&2
  exit 2
fi
release="${1}"
first_install="$(dirname "${0}")/../misc/first_install"

package_function="$(sed -n '/^package() {$/,/^}$/p' "${first_install}")"
if [ -z "${package_function}" ]; then
  printf '%s has no package function\n' "${first_install}" >&2
  exit 1
fi
commands="$(sed -n 's/^ *needs [^ ]* //p' "${first_install}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
printf 'Commands: %s\n' "${commands}"

docker pull -q "ubuntu:${release}" > /dev/null
docker run --rm -i -e "COMMANDS=${commands} snap" "ubuntu:${release}" sh -s << EOF
set -eu
${package_function}
packages=""
for tool in \${COMMANDS}; do
  packages="\${packages} \$(package "\${tool}")"
done
apt-get -q update > /dev/null
# shellcheck disable=SC2086
DEBIAN_FRONTEND=noninteractive apt-get -q install -y --no-install-recommends \${packages} > /dev/null
failed=0
for tool in \${COMMANDS}; do
  pkg="\$(package "\${tool}")"
  path="\$(command -v "\${tool}" || true)"
  if [ -z "\${path}" ]; then
    printf 'FAIL: %s: %s installed, but there is no %s\n' "${release}" "\${pkg}" "\${tool}"
    failed=1
    continue
  fi
  real="\$(readlink -f "\${path}")"
  # The file's package, or a dependency of it such as python3's
  # python3.12-minimal, has to come with pkg
  deps="\$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks \\
    --no-replaces --no-enhances "\${pkg}" | sed -n 's/^\\([^ <]\\)/\\1/p')"
  found=""
  for file in "\${path}" "\${real}" "\${real#/usr}"; do
    for owner in \$(dpkg -S "\${file}" 2> /dev/null | sed 's/: .*//; s/,/ /g'); do
      if printf '%s\\n' "\${deps}" | grep -qx "\${owner}"; then
        found="\${owner}"
      fi
    done
  done
  if [ -n "\${found}" ]; then
    printf 'PASS: %s: %s comes with %s, in %s\\n' "${release}" "\${tool}" "\${pkg}" "\${found}"
  else
    printf 'FAIL: %s: %s (%s) does not come with %s\\n' "${release}" "\${tool}" "\${real}" "\${pkg}"
    failed=1
  fi
done
exit "\${failed}"
EOF
