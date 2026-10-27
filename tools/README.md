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
- `infrastructure_containers/build-rfctf-client.sh` benches `ldm_checker
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
does:

```sh
for d in pentoo kali parrot blackarch; do
  case "${d}" in pentoo) img=rfhs/pentoo;; *) img="ghcr.io/rfhs/${d}";; esac
  docker run --rm -d --no-healthcheck --name "bench-${d}" \
    --tmpfs /run:mode=0755,nosuid,nodev,nr_inodes=800k,size=20%,strictatime \
    --cap-add net_raw --cap-add net_admin --cap-add=dac_read_search \
    --security-opt seccomp=unconfined "${img}"
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
