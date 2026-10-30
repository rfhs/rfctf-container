Contestant images: [![pentoo](https://github.com/rfhs/rfctf-container/actions/workflows/pentoo.yml/badge.svg?branch=main)](https://github.com/rfhs/rfctf-container/actions/workflows/pentoo.yml) [![kali](https://github.com/rfhs/rfctf-container/actions/workflows/kali.yml/badge.svg?branch=main)](https://github.com/rfhs/rfctf-container/actions/workflows/kali.yml) [![parrot](https://github.com/rfhs/rfctf-container/actions/workflows/parrot.yml/badge.svg?branch=main)](https://github.com/rfhs/rfctf-container/actions/workflows/parrot.yml) [![blackarch](https://github.com/rfhs/rfctf-container/actions/workflows/blackarch.yml/badge.svg?branch=main)](https://github.com/rfhs/rfctf-container/actions/workflows/blackarch.yml)

Infrastructure images: [![rfctf-client](https://github.com/rfhs/rfctf-container/actions/workflows/rfctf-client.yml/badge.svg?branch=main)](https://github.com/rfhs/rfctf-container/actions/workflows/rfctf-client.yml) [![rfctf-sdr](https://github.com/rfhs/rfctf-container/actions/workflows/rfctf-sdr.yml/badge.svg?branch=main)](https://github.com/rfhs/rfctf-container/actions/workflows/rfctf-sdr.yml) [![fosphor_knob](https://github.com/rfhs/rfctf-container/actions/workflows/fosphor_knob.yml/badge.svg?branch=main)](https://github.com/rfhs/rfctf-container/actions/workflows/fosphor_knob.yml)

If you are interested in hosting your own CTF with regards to wifi hacking, you are in the right place.
This CTF can be run as a virtual event, or using real hardware, with almost no difference between.

To start using follow these basic steps:

Clone this repo and enter the directory
```
git clone https://github.com/rfhs/rfctf-container
cd rfctf-container
```

The actual challenges are all run from docker containers.  The build files are all included in this repo, however, to simply run a game, you want to enter the "startup" directory.
```
cd startup
```

`misc/first_install` sets a machine up to run them at boot, and is safe to run again: it checks that the commands the startup scripts run are installed, installs docker, iw, the running kernel's mac80211_hwsim and, on EC2, the AWS CLI (from apt where the release packages it, otherwise AWS's snap) if they're missing, turns on docker's user namespace remapping with `misc/docker_userns_remap`, links the startup scripts into /etc/local.d and pulls the images.

No container runs `--privileged`.  The `*_docker_args` functions in `startup/rfhs-helpers.sh` give each one only what it needs (capabilities, namespaced sysctls, the SDRs' USB devices), and the build scripts test the images with the same.  The contestants run remapped, so their root is host uid and gid 231072, which owns the log, storage and key files `rfhs-container-init` gives them; it refuses to start them when docker isn't remapping.  `misc/docker_userns_remap` adds a `dockremap` user with exactly that range in /etc/subuid and /etc/subgid, as docker would otherwise pick the next free one, and sets `"userns-remap": "dockremap"` in /etc/docker/daemon.json.  openwrt, rfctf-client and rfctf-sdr use `--userns host`, as they need the host's devices and restricted files.

The scripts are named in a lexical order to be run in that order.  A description of the function for each script is as follows:

### 00_aws_set_dns.start
Used by RFHS to set per player dns in our AWS environment.  You don't need to run this, but it will exit safely if you do.

### 00_radio_init.start
When running a virtual game, this sets up and configures the virtual wifi radios.  If you want to run a physical game, and have the required "ton" of wifi interfaces, skip this step.

## The following scripts set up the challenges themselves and expect "fixphy.sh" and "rfhs-container-init" to be in the same directory.
### 01_openwrt.start
This script starts the openwrt container which runs the Access Point half of the wifi challenges.  It uses the virtual wifi cards created by 00_radio_init.start OR physical wifi cards available in the system.
It does not verify the capabilities of your physical wifi cards, you are expected to provide 802.11n/Wifi4 or newer wifi cards which support at least 4 APs each.  You can check with `iw list | grep -A2 'combinations'`.
Good example (supports 2048 ssids):
```
valid interface combinations:
	 * #{ IBSS } <= 1, #{ managed, AP, mesh point, P2P-client, P2P-GO } <= 2048, #{ P2P-device } <= 1,
```
Bad example (supports 1 ssid):
```
valid interface combinations:
	 * #{ managed } <= 1, #{ AP, P2P-client, P2P-GO } <= 1, #{ P2P-device } <= 1,
```

### 02_rfctf-client.start
This script starts the rfctf-client container which runs the wifi client half of the wifi challenges.  If uses the virtual wifi cards created by 00_radio_init.start OR physical wifi cards available in the system.

## The following scripts set up the contestant containers and expect "fixphy.sh" and "rfhs-container-init" to be in the same directory
These scripts should not by used for physical games (contestants use their own computers)

### 03_pentoo-contestant.start
Pentoo contestant container.  Includes four virtual wifi cards.

### 04_kali-contestant.start
Kali contestant container.  Includes four virtual wifi cards.

### 05_parrot-contestant.start
Parrot contestant container.  Includes four virtual wifi cards.

### 06_blackarch-contestant.start
Blackarch contestant container.  Includes four virtual wifi cards.

## The following container exists, but isn't fully open sourced and usable yet.  We hope it will be at some point soon, but it's internal use only for right now.
### 07_rfctf-sdr.start
This script sets up the software defined radio challenges.  It is NOT currently usable for anyone outside RFHS due to us not releasing our transmitter framework.  We hope to release it at some point in the near future, but right now, this container is not useful for anyone else.

### 08_fosphor_knob.start
This script starts fosphor_knob, the live spectrum display we show at the RF Village, on the physical display box.  It is not for virtual games: it exits right away in a VM, and first_install neither enables it nor pulls its image.  To start it at boot on the display box, link it into /etc/local.d yourself (`ln -s "$(pwd)/08_fosphor_knob.start" /etc/local.d/`).
It needs an X server on :0 (set FOSPHOR_KNOB_DISPLAY for another display) and waits up to 5 minutes for one at boot.  It uses the X server's own cookie, so no xhost is needed.  It also needs a supported SDR (B205mini, bladeRF 2.0 or HackRF) and, for every mode but hackrf_sweep, a Griffin PowerMate or the Waveshare knob.  The SDRs and the knob can be replugged while it runs.  It runs fosphor_knob_sponsors unless FOSPHOR_KNOB_MODE names another mode (e.g. `FOSPHOR_KNOB_MODE=fosphor_knob_uhd`).
Any GPU works, or none:
* Intel and AMD: it passes /dev/dri, and /dev/kfd (for ROCm) when the host has it.
* NVIDIA: it uses the proprietary driver from the host, which requires the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed and docker restarted.  Without the toolkit, the script warns and fosphor_knob most likely can't use OpenGL.
* No GPU: fosphor_knob runs on the CPU.

## Is it working?
After you run all the following commands check if the expected docker containers are running with `docker ps`

The contestant containers' docker healthcheck is `contestant-checker`, which checks that supervisord has the services running and that ssh and noVNC are listening.  It shows a notification on the contestant's desktop on every failing pass, so a problem can't go unnoticed, and again when it recovers; `/root/HEALTHCHECK_DEGRADED` holds the last failing pass's report.  openwrt's healthcheck is `rfhs_checker` and rfctf-client's is `ldm_checker`.  `tools/bench_healthcheck.sh` measures what any of them costs, healthy or degraded, and `tools/hwsim_containers.sh` starts openwrt and rfctf-client on mac80211_hwsim radios to measure them (see `tools/README.md`).

## Building the images
Each image has a build script next to its Dockerfile (`contestant_containers/build-*`, `infrastructure_containers/build-*`) which builds it, tests it, and only pushes from the RFHS build hosts.
rfctf-client and rfctf-sdr share their first stage (`rfctf-minimal`), so their build scripts only skip the cache for each image's own stage: built on the same host, the second one reuses those layers instead of building and pushing its own copy.
The pentoo based images (pentoo, rfctf-client, rfctf-sdr, fosphor_knob) build from `portage_and_overlay.tar.xz`, a snapshot of the Gentoo and Pentoo trees the Pentoo binhost built its packages from, so they install binary packages instead of building newer versions from source.  Make it with `infrastructure_containers/make_gentoo_cache.sh` (see `infrastructure_containers/tools/README.md`) and copy it to `contestant_containers/` too.  It refuses to make a snapshot of a tree more than a week old, and the build scripts refuse a tarball whose tree is more than a week old.  The Dockerfiles only mount the tree while they install packages, so it is never part of an image.

## CI
GitHub Actions builds and tests every image with the same build scripts used by hand.  Each image has its own workflow in `.github/workflows/` (`pentoo.yml`, `kali.yml`, `parrot.yml`, `blackarch.yml`, `rfctf-client.yml`, `rfctf-sdr.yml` and `fosphor_knob.yml`, which all call `build-image.yml`), and it runs only for changes to the files that image is built and tested from: a change to a shared file, such as `contestant_containers/files/contestant-checker`, runs every image that uses it.  `make_gentoo_cache.yml` runs `infrastructure_containers/tools/test_make_gentoo_cache.sh`.  `first_install.yml` runs `tools/test_first_install_vm.sh` on Ubuntu 24.04 and 26.04, each as EC2 and as anything else: it boots Ubuntu's cloud image in a VM, as fresh as a new AMI and, for EC2, with the AMIs' `linux-aws` kernel, booted with UEFI from an NVMe disk, runs `misc/first_install` twice, reboots so the startup scripts run as they do at boot, and checks that openwrt and the contestants come up healthy and unprivileged, with docker remapping the contestants' root and, on EC2, the AWS CLI installed.

`shellcheck.yml` runs ShellCheck 0.11.0 on every push and pull request, over every tracked file with a sh, bash or dash shebang, and fails on any finding at the default severity.  `.shellcheckrc` makes it follow the scripts the startup scripts source.  To run the same check locally:
```
git ls-files | while read -r f; do head -n 1 -- "$f" | grep -qE '^#!.*\b(ba|da)?sh\b' && printf '%s\n' "$f"; done | xargs shellcheck
```

The Pentoo based images first run `infrastructure_containers/make_gentoo_cache.sh` in pentoo-core, to snapshot the Gentoo and Pentoo trees the binhost was built from.  If those are more than a week old the snapshot fails and the image isn't built.

Each build script's test runs in the workflow: for the contestant images, `tools/bench_healthcheck.sh -t 100` (the healthcheck's time and CPU and the container's baseline CPU, with the ten processes using the most, failing if the median healthcheck takes over 100 ms; the report also goes to the job summary), then `contestant-checker excessive` (the wireless tools every distribution packages are installed and their libraries resolve, known answers from wpa_passphrase, tshark's 802.11 and EAPOL dissectors, wifite starting, notify-send, a 30 second aircrack-ng benchmark, hashcat cracking a WPA hash with OpenCL, then on the container's radios hostapd running a WPA2 AP that wpa_supplicant joins, the distribution's DHCP client getting a lease from kea-dhcp4 over it and `aireplay-ng --test` against it, the services and ports the healthcheck checks, noVNC and x11vnc answering, then the healthcheck failing with novnc stopped and recovering once it is started again) and then `contestant_containers/tests/test_healthcheck.sh` (the healthcheck's notifications and report when a port is missing, when services aren't running and when supervisord doesn't answer, that every failing pass notifies, and that it recovers), and for Kali `contestant_containers/tests/test_kali_panel_trim.sh` (that `contestant_containers/files/kali_panel_trim`, which drops the panel's cpugraph and genmon plugins at build time to save idle CPU, removes exactly those, and fails without changing anything on a panel it doesn't expect), the same benchmark of `ldm_checker --test` and then `ldm_checker --excessive` for rfctf-client (what `--test` checks, and then that dhcpcd still titles its process as unified_client expects, on a dummy interface), `challengectl.py --test` for rfctf-sdr, and `tests/fosphor_knob_selftest.py` for fosphor_knob, which then also gets `startup/tests/fosphor_knob_start_test.sh` (08_fosphor_knob.start's docker arguments against an Xvfb on the runner).  The contestant and rfctf-client tests run in containers started as the game starts them, the contestants' with docker's user namespace remapping on, and need `mac80211_hwsim` radios on the runner (each contestant gets four, from `tools/give_hwsim_radios.sh`) and the host's `iw` and `rfkill`; the workflow installs them, builds mac80211_hwsim with `infrastructure_containers/tools/build_mac80211_hwsim.sh` when the runner's kernel doesn't have it, and fails if the module can't be loaded.

The Kali, Parrot and BlackArch workflows run every Monday (05:47 UTC) and the Pentoo based ones every Tuesday (05:23 UTC), because rolling distributions and the binhost change without commits here.  They also run on pushes to `main` and pull requests that touch their files, and by hand from the Actions tab ("Run workflow") or with `gh workflow run kali.yml` and so on.  Set `STARTUP_WAIT` (seconds) to give a slow machine longer before a build script's test runs; CI uses 120, and 180 for rfctf-client.

The build scripts only push to Docker Hub from the RFHS build hosts, so CI never pushes there.  When Kali, Parrot or BlackArch passes on `main`, its workflow pushes it to GitHub Container Registry as `ghcr.io/rfhs/<distro>:<VERS>` and `:latest`.  The Kali, Parrot and BlackArch start scripts run those `:latest` images, so the packages have to stay public; the other images still come from Docker Hub.
