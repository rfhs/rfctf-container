# Tests for the contestant containers

## test_healthcheck.sh

Tests how the healthcheck, `contestant-checker` without arguments, reports
failures and recoveries, in a running contestant container whose services
are up. It puts fake `notify-send`, `ss` and `curl` first in `PATH`: the fake
`notify-send` logs the notifications, the fake `ss` edits the real one's
output to make a port disappear, and the fake `curl` can answer the services
check with supervisord's reply for services that aren't running, or fail as
if supervisord weren't listening. It checks that:

- a healthy pass notifies nobody and leaves no `/root/HEALTHCHECK_DEGRADED`
- nothing listening on port 22 fails with one notification and a report of
  only that pass, which starts with the failure
- a listener on port 2222 doesn't count as port 22, and the same failure
  notifies again and replaces the report
- a different failure, nothing on port 8080, notifies and replaces the report
- services that aren't running fail with a notification and a report in
  `supervisorctl status`'s format, for a stopped, a fatal and a missing
  service; the same services still down notify again, and the report has
  this pass's uptimes
- supervisord not answering fails with a notification and curl's error
- only the first healthy pass after a failure notifies Recovered

`contestant-checker excessive` covers a really stopped service the same way,
by stopping novnc. The build scripts run this test after `contestant-checker
excessive`, in the container they tested.

Start a container as in the top-level `tools/README.md` and wait until
supervisord has started everything, then, from `contestant_containers`:

```sh
./tests/test_healthcheck.sh bench-kali                           # the image's checker
./tests/test_healthcheck.sh bench-kali files/contestant-checker  # this checkout's
```

It prints PASS or FAIL for each check and exits 1 if any failed.

## test_firefox_sandbox.sh

Tests that Firefox sandboxes its content processes in a running contestant
container: it starts a headless Firefox with a new profile and passes once
one of its content processes runs in a user namespace of its own under a
seccomp filter. Docker's default seccomp profile denies the user namespaces
and Firefox then runs its content without them, so this fails if the
contestants lose `seccomp=unconfined`, or on AppArmor hosts the `userns`
rule in `misc/contestant_apparmor`'s profile. The build scripts run it after
`test_healthcheck.sh`, and `tools/test_first_install_vm.sh` in each
contestant of its VM.

```sh
./tests/test_firefox_sandbox.sh bench-kali
```

It prints PASS or FAIL, with the content processes it found, and exits 1 on
a failure.
