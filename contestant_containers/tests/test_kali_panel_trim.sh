#!/bin/sh
# Tests contestant_containers/files/kali_panel_trim in a running Kali
# contestant container, on copies of kali-themes' panel: it removes exactly
# cpugraph and genmon, and anything other than the panel it expects fails and
# is left as it was. Also checks the image's own panel has neither.
#   ./contestant_containers/tests/test_kali_panel_trim.sh container
set -eu

missing_tools=""
for tool in dirname docker; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
if [ -z "${1:-}" ]; then
  printf 'Usage: %s container\n' "${0}" >&2
  exit 2
fi
c="${1}"

docker cp -q "$(dirname "${0}")/../files/kali_panel_trim" "${c}:/tmp/kali_panel_trim"
docker exec -i "${c}" sh -s << 'EOF'
orig=/usr/share/kali-themes/etc/xdg/xfce4/panel/default.xml
t=/tmp/kali-panel-test
mkdir -p "${t}"
failures=0
result() {
  if [ "${1}" = 0 ]; then
    printf 'PASS: %s\n' "${2}"
  else
    printf 'FAIL: %s; its output:\n' "${2}"
    sed 's/^/    /' "${t}/out"
    failures=$((failures + 1))
  fi
}
# trim panel: runs kali_panel_trim on a copy of panel, leaving the copy in
# ${t}/panel, a copy of that before in ${t}/before and its output in ${t}/out
trim() {
  cp "${1}" "${t}/panel"
  cp "${t}/panel" "${t}/before"
  sh /tmp/kali_panel_trim "${t}/panel" > "${t}/out" 2>&1
}
# fails_unchanged: the last trim failed and left the panel as it was
fails_unchanged() {
  [ "${rc}" != 0 ] && cmp -s "${t}/before" "${t}/panel" && grep -q 'is not what this expects' "${t}/out"
}

trim "${orig}" && rc=0 || rc=$?
[ "${rc}" = 0 ] && ! grep -q -e cpugraph -e genmon "${t}/panel" \
  && [ "$(($(wc -l < "${t}/before") - $(wc -l < "${t}/panel")))" = 37 ] \
  && grep -q '<property name="plugin-14"' "${t}/panel" && grep -q '<property name="plugin-16"' "${t}/panel"
result $? "kali-themes' panel loses cpugraph and genmon, their ids and nothing else"
cp "${t}/panel" "${t}/trimmed"

trim "${t}/trimmed" && rc=0 || rc=$?
fails_unchanged
result $? 'a panel without them fails and is left as it was'

sed '/"enable-single-row"/a\      <property name="new" type="bool" value="true"/>' "${orig}" > "${t}/changed"
trim "${t}/changed" && rc=0 || rc=$?
fails_unchanged
result $? 'a changed genmon plugin fails and is left as it was'

sed '/<property name="plugin-14"/d' "${orig}" > "${t}/changed"
trim "${t}/changed" && rc=0 || rc=$?
fails_unchanged
result $? 'a panel without the plugin after cpugraph fails and is left as it was'

! grep -q -e cpugraph -e genmon /etc/xdg/xfce4/panel/default.xml > "${t}/out" 2>&1
result $? "the image's panel has neither"

rm -rf "${t}" /tmp/kali_panel_trim
exit "${failures}"
EOF
