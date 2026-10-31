# Tools shared by the images

## bench_healthcheck.sh

Benchmarks the docker healthcheck of running containers, and measures each
container's baseline (idle) CPU. It runs the healthcheck the way docker does,
with `docker exec`: the HEALTHCHECK of the container's image, `CMD` as is and
`CMD-SHELL` with `/bin/sh -c`, unless `-x` gives a shell command to run
instead. It works in any image with a POSIX shell, busybox included.

Build scripts run it on the image they built, before their own test and
before they push anything, with `-t 100`: the build fails if the median
healthcheck takes over 100 ms or any run of it fails.

- `contestant_containers/build-*` bench `contestant-checker`.
- `infrastructure_containers/build-rfctf-client` benches `ldm_checker
  --test`, since the clients have no APs to connect to in CI.
- openwrt's `docker-build.sh`, in [rfhs/openwrt](https://github.com/rfhs/openwrt),
  benches `rfhs_checker` from an rfctf-container checkout, by default
  `~/development/rfhs/rfctf-container` (set `RFCTF_CONTAINER` for another).

It first waits up to 300 s for every container to be healthy, as docker
means it: the healthcheck passed once. Those checks run with a `notify-send`
that does nothing, so the contestant images' popups don't count. Then each
run is an idle window, which gives the baseline, followed by a window that
starts with the healthcheck in all the containers at once (the worst case for
several on one host). It prints, for each run and container:

- exec: the wall time of `docker exec` running the healthcheck, which is how
  docker runs it
- checker: the healthcheck itself, timed in the container; `-t` is checked
  against this. It is to the ms, or to 10 ms where `date` has no `%N`, as in
  busybox.
- checker CPU: the CPU the whole container used in the window after the
  healthcheck started, less the baseline. It comes from the container's
  cgroup, so it counts what the healthcheck makes other processes do, such
  as supervisord answering it or the notification daemon drawing a popup. It
  can come out below zero when the baseline varies, as Kali's does.
- idle: the container's CPU in the idle window, as a percentage of one CPU

then the medians and the range of the baseline, and the ten processes in
each container that used the most CPU over the runs, with the children they
waited for. Under GitHub Actions the whole report also goes to the job
summary.

The containers have to run without docker's own healthcheck
(`--no-healthcheck`), whose runs would land in the windows; it refuses them
otherwise. To start the contestant images the way `startup/rfhs-container-init`
does, with the privileges `contestant_docker_args` in `startup/rfhs-helpers.sh`
gives them:

```sh
. ./startup/rfhs-helpers.sh
for d in pentoo kali parrot blackarch; do
  case "${d}" in pentoo) img=rfhs/pentoo;; *) img="ghcr.io/rfhs/${d}";; esac
  # shellcheck disable=SC2046
  docker run --rm -d --no-healthcheck --name "bench-${d}" \
    --tmpfs /run:mode=0755,nosuid,nodev,nr_inodes=800k,size=20%,strictatime \
    $(contestant_docker_args ./startup) "${img}"
done
```

Then:

```sh
./tools/bench_healthcheck.sh bench-pentoo bench-kali bench-parrot bench-blackarch
# a checker that isn't in the images yet, e.g. this checkout's
./tools/bench_healthcheck.sh -c contestant_containers/files/contestant-checker \
  bench-pentoo bench-kali bench-parrot bench-blackarch
# the degraded state: novnc stopped, every pass failing
./tools/bench_healthcheck.sh -s 'supervisorctl stop novnc' -f bench-kali
```

openwrt and rfctf-client need radios; `hwsim_containers.sh` below starts
them. Then:

```sh
./tools/bench_healthcheck.sh bench-openwrt
./tools/bench_healthcheck.sh -x './ldm_checker --test' bench-rfctf-client
# openwrt's and leeloodallasmultipass' checkouts' checkers
./tools/bench_healthcheck.sh -c ../openwrt/files/usr/sbin/rfhs_checker bench-openwrt
./tools/bench_healthcheck.sh -c ../leeloodallasmultipass/ldm_checker \
  -x './ldm_checker --test' bench-rfctf-client
```

Options:

- `-n` the number of runs (default 10)
- `-w` the window in seconds (default 15, long enough for a notification
  popup to come and go)
- `-t` the limit in ms for the median checker time
- `-c file` copies a checker into the containers and runs it in place of
  the healthcheck's program, with the same arguments
- `-x command` runs this shell command as the healthcheck
- `-s command` runs a shell command in each container once it is healthy,
  before the runs, e.g. to break something; the containers stay that way
- `-f` expects the healthcheck to fail in every run, to measure a degraded
  container; a run that passes counts as bad

It exits 1 if a run was bad or a median is over the limit. It needs cgroup
v2 and read access to `/sys/fs/cgroup`, which is world readable by default.
It keeps its files in the containers in `/healthcheck-bench`, not `/tmp`,
which docker's `--tmpfs` mounts noexec, and removes them when it finishes.

## hwsim_containers.sh

Starts openwrt and rfctf-client on `mac80211_hwsim` radios, the way their
build scripts do but without docker's healthcheck, so `bench_healthcheck.sh`
can measure them together; `stop` stops them and unloads mac80211_hwsim. It
needs root, and refuses to start when mac80211_hwsim is already loaded.

```sh
sudo ./tools/hwsim_containers.sh start   # rfhs/openwrt:latest and rfhs/rfctf-client:latest
sudo ./tools/hwsim_containers.sh start my/openwrt:test my/rfctf-client:test
sudo ./tools/hwsim_containers.sh stop
```

The containers are `bench-openwrt` and `bench-rfctf-client`. rfctf-client
gets the radios whose interfaces are wlan10 to wlan25, which its ldm.conf
uses, and openwrt 10 others. All hwsim radios share one medium, so the
clients find the APs. It only moves mac80211_hwsim radios, so a wifi card on
the host stays where it is.

## give_hwsim_radios.sh

Moves `mac80211_hwsim` radios into a running container. The contestant
build scripts give their test container four, as the game gives each
contestant, for `contestant-checker excessive`'s wifi tests: hostapd and
wpa_supplicant, the distribution's DHCP client getting a lease from
kea-dhcp4 over that link, and `aireplay-ng --test`. It needs root.

```sh
sudo ./tools/give_hwsim_radios.sh rfhs-kali-ci 4
```

It loads mac80211_hwsim with that many radios when it isn't loaded, and
reloads it with that many when too few are free but none is in another
namespace. When other containers hold the rest, it fails rather than take
theirs. The radios go back to the host when the container stops.

## test_contestant_images.sh

Tests contestant images the way their build scripts do, without building or
pushing them, e.g. images built by hand under another tag. One at a time,
each runs with the game's privileges (`contestant_docker_args`) and four
radios from `give_hwsim_radios.sh`, then gets `bench_healthcheck.sh -t 100`,
`contestant-checker excessive`,
`contestant_containers/tests/test_healthcheck.sh` and
`contestant_containers/tests/test_firefox_sandbox.sh`. It needs root, for
the radios.

```sh
sudo ./tools/test_contestant_images.sh my/kali:test my/parrot:test
```

`STARTUP_WAIT` (default 120) is how long each image gets to start its
services. It exits 1 if any image failed.

## test_first_install_vm.sh

Tests `misc/first_install` and the startup scripts on a fresh Ubuntu, as on
a new AMI: it boots Ubuntu's cloud image for that release in a KVM VM,
copies this checkout in, runs `first_install` twice (it has to be safe to
run again), reboots so rc.local runs the startup scripts as at boot, and
checks that openwrt and the four contestants are healthy, that every
container runs unprivileged, that each contestant has its four radios, that
rfctf-client's clients are running, that docker remaps the contestants'
root, and that each contestant shows notifications (GTK loading icons under
Ubuntu's AppArmor) and sandboxes Firefox's content processes. With `ec2`
the VM is made like Ubuntu's AMIs, which can't be downloaded: it switches to the `linux-aws` kernel they run, whose modules
are packaged differently from the cloud image's generic kernel, boots with
UEFI from an NVMe disk as on Nitro, and gives Amazon EC2 as its board vendor, so
`first_install` takes its EC2 path and has to install the AWS CLI; the
EC2-only startup scripts still fail there, with no instance metadata or
credentials to use.

```sh
./tools/test_first_install_vm.sh 24.04 ec2
./tools/test_first_install_vm.sh 26.04 other ~/vm-test
```

It needs KVM, QEMU, OVMF for `ec2`, one of cloud-localds, genisoimage or
xorriso, and about 100 GB free in the work directory (by default
`./first-install-vm-<release>-<platform>`), which keeps the cloud image for
the next run. `VM_MEMORY` (default 12G) and `VM_CPUS` (default all) size the
VM. `.github/workflows/first_install.yml` runs it for both releases and both
platforms.


## profile_contestant_security.sh

Shows what contestant images need beyond docker's default seccomp and
AppArmor profiles, so that the contestants' exceptions in
`startup/rfhs-contestant-seccomp.json` and `misc/contestant_apparmor` stay
what they use. One image at a time, it starts a container as the build
scripts do, with four radios from `give_hwsim_radios.sh`, but under the
seccomp profile without its own rules (those commented `rfhs-contestant:`)
and with every syscall it doesn't allow logged instead of denied, and on hosts with AppArmor under `rfhs-contestant` in complain mode
without its exceptions (`userns`, `mount` and `pivot_root`) and with docker's
deny rules made audit rules. Once its services have started (`STARTUP_WAIT`,
default 120 s) it runs `contestant-checker excessive`, `test_healthcheck.sh`,
`test_firefox_sandbox.sh`, a notification and the wireless tools
(airmon-ng, airodump-ng, dumpcap, tshark, tcpdump, hcxdumptool, wash, mdk4,
kismet, macchanger) on one of its radios. Then it loads the real AppArmor
profile again and prints the syscalls the seccomp profile would deny, by
command, and the AppArmor events: an `ALLOWED` event is one docker's
profile denies, and an `AUDIT` one hit one of its deny rules. Run it on an
Ubuntu host or `test_first_install_vm.sh`'s VM, with auditd, `rfkill` and
radios no container is using (stop the game's contestants first):

```sh
sudo apt-get install auditd rfkill
sudo ./tools/profile_contestant_security.sh ghcr.io/rfhs/kali ghcr.io/rfhs/parrot ghcr.io/rfhs/blackarch rfhs/pentoo
```

## check_contestant_profiles.py

Docker can't extend its default seccomp and AppArmor profiles, only replace
them, so the contestants' profiles are copies of moby/profiles' defaults
with their own rules added, and docker's later fixes don't reach them by
themselves. This fetches moby/profiles' main branch and fails, with a diff,
unless `startup/rfhs-contestant-seccomp.json` is exactly `seccomp/default.json`
plus the rules whose comment starts with `rfhs-contestant:`, and the profile
in `misc/contestant_apparmor` is `apparmor/template.go`'s rendered for
`rfhs-contestant`, without `deny mount,` (a deny rule wins over bwrap's mount
rules), followed by its own rules from the `${userns}` line. `--sync`
rewrites both from upstream and keeps the contestants' rules; then test them
and commit. `.github/workflows/contestant_profiles.yml` runs the check
daily and on changes to them.

```sh
./tools/check_contestant_profiles.py
./tools/check_contestant_profiles.py --sync
```
