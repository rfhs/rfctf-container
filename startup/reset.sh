#!/bin/bash -x

set -eu -o pipefail 

modprobe -r mac80211_hwsim
modprobe    mac80211_hwsim

sleep 5
for i in $(airmon-ng | awk /phy/'{print $2}'); do
        ip link set ${i} down;
        macchanger -r ${i};
done
