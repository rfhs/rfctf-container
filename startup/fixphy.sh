#!/bin/bash

set -eu -o pipefail 

FIX_PHY="${FIX_PHY:-}"

DEBUG="${DEBUG:-}"

if [ -n "${DEBUG}" ]; then
  set -x
fi

findFreeInterface() {
  if [ -z "${1}" ]; then
    printf "findFreeInterface needs a target mode.\n"
    exit 1
  fi
  if [ "${1}" != "monitor" ] && [ "${1}" != "station" ]; then
    printf "findFreeInterface only supports monitor and station for target mode.\n"
    exit 1
  fi
  target_mode="${1}"
  if [ "$target_mode" = "monitor" ]; then
    target_suffix="mon"
    target_type="803"
  else
    target_suffix=""
    target_type="1"
  fi
  for i in $(seq 0 100); do
    if [ "$i" = "100" ]; then
      printf "\nUnable to find a free name between wlan0 and wlan99, you are on your own from here.\n"
      return 1
    fi
    if [ "$DEBUG" = "1" ]; then
      printf "\nChecking candidate wlan${i}\n"
    fi
    if [ ! -e /sys/class/net/wlan${i} ]; then
      if [ "$DEBUG" = "1" ]; then
        printf "\nCandidate wlan${i} is not in use\n"
      fi
      if [ ! -e /sys/class/net/wlan${i}mon ]; then
        if [ "$DEBUG" = "1" ]; then
          printf "\nCandidate wlan${i} and wlan${i}mon are both clear, creating wlan${i}${target_suffix}\n"
        fi
        #IW_ERROR="$(iw phy ${PHYDEV} interface add wlan${i}${target_suffix} type ${target_mode} 2>&1)"
        IW_ERROR="$(iw phy ${PHYDEV} interface add wlan${i}${target_suffix} type __ap 2>&1)"
        if [ -z "${IW_ERROR}" ]; then
          if [ -d /sys/class/ieee80211/${PHYDEV}/device/net ]; then
            for j in $(ls /sys/class/ieee80211/${PHYDEV}/device/net/); do
              if [ "$(cat /sys/class/ieee80211/${PHYDEV}/device/net/${j}/type)" = "${target_type}" ]; then
                #here is where we catch udev renaming our interface
                k=${j#wlan}
                i=${k%mon}
              fi
            done
          else
            printf "Unable to create wlan${i}${target_suffix} and no error received.\n"
            return 1
          fi
          printf "\n(mac80211 ${target_mode} mode vif enabled on [${PHYDEV}]wlan${i}${target_suffix}\n"
          unset IW_ERROR
          break
        else
          printf "\n\n ERROR adding ${target_mode} mode interface: ${IW_ERROR}\n"
          break
        fi
      else
        if [ "$DEBUG" = "1" ]; then
          printf "\nCandidate wlan${i} does not exist, but wlan${i}mon does, skipping...\n"
        fi
      fi
    else
      if [ "$DEBUG" = "1" ]; then
        printf "\nCandidate wlan${i} is in use already.\n"
      fi
    fi
  done
}

handleLostPhys() {
  MISSING_INTERFACE=""
  if [ -d /sys/class/ieee80211 ]; then
    for i in $(ls /sys/class/ieee80211/); do
      if [ ! -d /sys/class/ieee80211/${i}/device/net ]; then
        MISSING_INTERFACE="${i}"
        PHYDEV=${MISSING_INTERFACE}
        echo "Found missing interface ${PHYDEV}"
        if [ -n "${FIX_PHY}" ]; then
          findFreeInterface station
        fi
      fi
    done
  fi
}

handleLostPhys
