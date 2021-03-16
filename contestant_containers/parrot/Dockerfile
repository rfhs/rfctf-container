FROM parrotsec/core
RUN DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get update && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get dist-upgrade -y && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get install --no-install-recommends aircrack-ng asleap freeradius-wpe hostapd-wpe iw kismet mdk3 mdk4 pixiewps reaver wifi-honey wifite tshark wireshark termshark vim mlocate man pciutils hashcat wpasupplicant less bash-completion ssh supervisor novnc xvfb x11vnc parrot-xfce dbus-x11 dialog -y && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  rm -f /etc/ssh/ssh_host_* && \
  cd /etc/freeradius-wpe/3.0/certs && \
  make clean && \
  cd /etc/hostapd-wpe/certs && \
  make clean

EXPOSE 22/tcp
EXPOSE 8080/tcp
ENV DISPLAY=:0

WORKDIR /root/
COPY files/cyberpunk.words /root/cyberpunk.words
COPY files/supervisord.conf /etc/supervisord/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord/supervisord.conf", "--pidfile", "/run/supervisord.pid"]
ENTRYPOINT []
