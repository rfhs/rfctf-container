#!/bin/sh
# Tests the healthcheck's failure and recovery handling in a running contestant
# container, with notify-send, ss and curl replaced by fakes earlier in PATH: a
# healthy pass notifies nobody, every failing pass notifies and writes a
# report of only that pass, and only the first healthy pass after a failure
# notifies Recovered.
#   ./tests/test_healthcheck.sh container [checker]
# The checker defaults to the image's; services have to be up already.
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf 'usage: %s container [checker]\n' "${0}" >&2
  exit 2
fi
missing_tools=""
for tool in docker grep sed; do
  command -v "${tool}" > /dev/null 2>&1 || missing_tools="${missing_tools} ${tool}"
done
if [ -n "${missing_tools}" ]; then
  printf '%s: required commands not found:%s\n' "${0##*/}" "${missing_tools}" >&2
  exit 1
fi
c="${1}"
checker=/usr/local/sbin/contestant-checker
if [ -n "${2:-}" ]; then
  checker=/tmp/contestant-checker-test
  docker cp -q "${2}" "${c}:${checker}"
fi

ss="$(docker exec "${c}" sh -c 'command -v ss')"
curl="$(docker exec "${c}" sh -c 'command -v curl')"
docker exec "${c}" mkdir -p /tmp/healthcheck-test
trap 'docker exec "${c}" rm -rf /tmp/healthcheck-test /tmp/contestant-checker-test /root/HEALTHCHECK_DEGRADED' EXIT
docker exec -i "${c}" sh -c 'cat > /tmp/healthcheck-test/notify-send' << 'EOF'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/healthcheck-test/notify.log
EOF
docker exec -i "${c}" sh -c 'cat > /tmp/healthcheck-test/ss' << EOF
#!/bin/sh
${ss} "\$@" | sed "\${SS_SED:-}"
EOF
# CURL_FAKE=refused fails as curl does when nothing listens; CURL_FAKE=down
# answers getAllProcessInfo the way supervisord does, one <name> per line, with
# xfce missing, x11vnc FATAL and novnc STOPPED
docker exec -i "${c}" sh -c 'cat > /tmp/healthcheck-test/curl' << EOF
#!/bin/sh
case "\${CURL_FAKE:-}" in
  '') exec ${curl} "\$@";;
  refused)
    echo 'curl: (7) Failed to connect to 127.0.0.1 port 9001 after 0 ms: Could not connect to server' >&2
    exit 7;;
esac
process() {
  printf '<value><struct>\n'
  printf '<member>\n<name>%s</name>\n<value><string>%s</string></value>\n</member>\n' \
    name "\${1}" group "\${1}" statename "\${2}" description "\${3}"
  printf '</struct></value>\n'
}
printf "<?xml version='1.0'?>\n<methodResponse>\n<params>\n<param>\n<value><array><data>\n"
process X11 RUNNING "pid 158, uptime \${CURL_UPTIME}"
process novnc STOPPED 'Oct 26 11:38 AM'
process sshd RUNNING "pid 129, uptime \${CURL_UPTIME}"
process x11vnc FATAL 'Exited too quickly (process log may have details) &lt;&amp;&gt;'
printf '</data></array></value>\n</param>\n</params>\n</methodResponse>\n'
EOF
docker exec "${c}" sh -c 'chmod +x /tmp/healthcheck-test/notify-send /tmp/healthcheck-test/ss /tmp/healthcheck-test/curl
  rm -f /root/HEALTHCHECK_DEGRADED'

failures=0
pass() {
  printf 'PASS: %s\n' "$*"
}
fail() {
  printf 'FAIL: %s\n' "$*"
  failures=$((failures + 1))
}

# run_check "ss sed script" [curl fake] [uptime]: prints the exit status, the
# notifications and the degraded file, then clears the notification log
run_check() {
  docker exec -e SS_SED="${1}" -e CURL_FAKE="${2:-}" -e CURL_UPTIME="${3:-}" "${c}" sh -c '
    if PATH="/tmp/healthcheck-test:${PATH}" "$1" > /dev/null 2>&1; then echo "exit 0"; else echo "exit $?"; fi
    if [ -f /tmp/healthcheck-test/notify.log ]; then sed "s/^/notify /" /tmp/healthcheck-test/notify.log; fi
    rm -f /tmp/healthcheck-test/notify.log
    if [ -e /root/HEALTHCHECK_DEGRADED ]; then echo degraded; sed "s/^/report /" /root/HEALTHCHECK_DEGRADED; fi' sh "${checker}"
}

# count "pattern": how many lines of ${out} match
count() {
  printf '%s\n' "${out}" | grep -c -- "${1}" || true
}

out="$(run_check '')"
if [ "${out}" = "exit 0" ]; then
  pass 'a healthy pass succeeds without a notification or a degraded file'
else
  fail "a healthy pass gave: ${out}"
fi

out="$(run_check '/ 0\.0\.0\.0:22 /d')"
if [ "$(count '^exit 1$')" -eq 1 ] && [ "$(count '^notify Healthcheck Failed')" -eq 1 ] \
  && [ "$(count '^degraded$')" -eq 1 ] \
  && [ "$(printf '%s\n' "${out}" | sed -n '/^degraded$/{n;p;}')" = 'report Nothing is listening on port 22' ] \
  && [ "$(count '^report Nothing is listening')" -eq 1 ]; then
  pass 'nothing on port 22 fails with one notification and a report that starts with it'
else
  fail "nothing on port 22 gave: ${out}"
fi

# the last pass left its report, so one report here means this pass replaced it
out="$(run_check 's/ 0\.0\.0\.0:22 / 0.0.0.0:2222 /')"
if [ "$(count '^exit 1$')" -eq 1 ] && [ "$(count '^notify Healthcheck Failed')" -eq 1 ] \
  && [ "$(count '^report Nothing is listening on port 22$')" -eq 1 ] \
  && [ "$(count '^report Nothing is listening')" -eq 1 ]; then
  pass 'port 2222 does not count as port 22, the same failure notifies again, and the report is only this pass'"'"'s'
else
  fail "only port 2222 gave: ${out}"
fi

out="$(run_check '/ 0\.0\.0\.0:8080 /d')"
if [ "$(count '^exit 1$')" -eq 1 ] && [ "$(count '^notify Healthcheck Failed')" -eq 1 ] \
  && [ "$(count '^report Nothing is listening on port 8080$')" -eq 1 ] \
  && [ "$(count '^report Nothing is listening')" -eq 1 ]; then
  pass 'a different failure, nothing on port 8080, notifies and replaces the report'
else
  fail "nothing on port 8080 gave: ${out}"
fi

expected="$(printf 'report %-33s%-10s%s\n' \
  sshd RUNNING 'pid 129, uptime 0:01:00' \
  X11 RUNNING 'pid 158, uptime 0:01:00' \
  xfce ERROR '(no such process)' \
  x11vnc FATAL 'Exited too quickly (process log may have details) <&>' \
  novnc STOPPED 'Oct 26 11:38 AM')"
out="$(run_check '' down 0:01:00)"
if [ "$(count '^exit 1$')" -eq 1 ] && [ "$(count '^notify Healthcheck Failed')" -eq 1 ] \
  && [ "$(printf '%s\n' "${out}" | sed -n '/^degraded$/,$p')" = "$(printf 'degraded\nreport Not running: xfce, x11vnc, novnc\n%s' "${expected}")" ]; then
  pass 'services that are not running fail with a notification and a report in supervisorctl status'"'"'s format'
else
  fail "services not running gave: ${out}"
fi

out="$(run_check '' down 0:02:00)"
if [ "$(count '^exit 1$')" -eq 1 ] && [ "$(count '^notify Healthcheck Failed')" -eq 1 ] \
  && [ "$(count '^report sshd .*uptime 0:02:00$')" -eq 1 ] && [ "$(count '^report ')" -eq 6 ]; then
  pass 'the same services still not running notify again and replace the report with this pass'"'"'s uptimes'
else
  fail "the same services still not running gave: ${out}"
fi

out="$(run_check '' refused)"
if [ "$(count '^exit 1$')" -eq 1 ] && [ "$(count '^notify Healthcheck Failed')" -eq 1 ] \
  && [ "$(printf '%s\n' "${out}" | sed -n '/^degraded$/,$p')" = "$(printf 'degraded\nreport supervisord did not answer on 127.0.0.1:9001\nreport curl: (7) Failed to connect to 127.0.0.1 port 9001 after 0 ms: Could not connect to server')" ]; then
  pass 'supervisord not answering fails with a notification and curl'"'"'s error'
else
  fail "supervisord not answering gave: ${out}"
fi

out="$(run_check '')"
if [ "${out}" = "$(printf 'exit 0\nnotify Healthcheck Recovered --icon=dialog-information')" ]; then
  pass 'the first healthy pass after a failure notifies Recovered and removes the degraded file'
else
  fail "the first healthy pass after a failure gave: ${out}"
fi

out="$(run_check '')"
if [ "${out}" = "exit 0" ]; then
  pass 'the next healthy pass notifies nobody'
else
  fail "the next healthy pass gave: ${out}"
fi

if [ "${failures}" -ne 0 ]; then
  printf '%s check(s) failed\n' "${failures}"
  exit 1
fi
