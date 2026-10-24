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

## Building the images
Each image has a build script next to its Dockerfile (`contestant_containers/build-*`, `infrastructure_containers/build-*`) which builds it, tests it, and only pushes from the RFHS build hosts.
rfctf-client and rfctf-sdr share their first stage (`rfctf-minimal`), so their build scripts only skip the cache for each image's own stage: built on the same host, the second one reuses those layers instead of building and pushing its own copy.
The pentoo based images (pentoo, rfctf-client, rfctf-sdr, fosphor_knob) build from `portage_and_overlay.tar.xz`, a snapshot of the Gentoo and Pentoo trees the Pentoo binhost built its packages from, so they install binary packages instead of building newer versions from source.  Make it with `infrastructure_containers/make_gentoo_cache.sh` (see `infrastructure_containers/tools/README.md`) and copy it to `contestant_containers/` too.  It refuses to make a snapshot of a tree more than a week old, and the build scripts refuse a tarball whose tree is more than a week old.  The Dockerfiles only mount the tree while they install packages, so it is never part of an image.

## CI
GitHub Actions builds and tests every image with the same build scripts used by hand; the scripts only push from the RFHS build hosts, so CI never pushes.

- **Pentoo images** (`.github/workflows/pentoo-images.yml`): one job tests and runs `infrastructure_containers/make_gentoo_cache.sh` in pentoo-core to snapshot the Gentoo and Pentoo trees the binhost was built from, and the pentoo contestant, rfctf-client, rfctf-sdr and fosphor_knob images are all built from that one tarball.  If the binhost's trees are more than a week old the snapshot fails and nothing is built.
- **Contestant images** (`.github/workflows/contestant-images.yml`): Kali, Parrot and BlackArch.

Each build script's test runs in the workflow: `contestant-checker excessive` for the contestant images, `ldm_checker --test` for rfctf-client, `challengectl.py --test` for rfctf-sdr, and `tests/fosphor_knob_selftest.py` for fosphor_knob, which then also gets `startup/tests/fosphor_knob_start_test.sh` (08_fosphor_knob.start's docker arguments against an Xvfb on the runner).  The rfctf-client test needs `mac80211_hwsim` radios on the runner and the host's `airmon-ng`, `iw` and `rfkill`; the workflow installs them and fails if the module can't be loaded.

The workflows run on pushes to `main` and pull requests that touch an image, every Tuesday (rolling distributions and the binhost change without commits here), and by hand from the Actions tab ("Run workflow") or with `gh workflow run pentoo-images.yml` / `gh workflow run contestant-images.yml`.  Set `STARTUP_WAIT` (seconds) to give a slow machine longer before a build script's test runs; CI uses 120, and 180 for rfctf-client.
