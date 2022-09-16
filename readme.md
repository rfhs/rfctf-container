If you are interested in hosting your own CTF with regards to wifi hacking, you are in the right place.
This CTF can be run as a virtual event, or using real hardware, with almost no difference between.

To start using follow these basic steps:

Clone this repo and enter the directory
```
git clone https://github.com/rfhs/rfctf-container
cd rf-ctfcontainer
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

## Is it working?
After you run all the following commands check if the expected docker containers are running with `docker ps`
