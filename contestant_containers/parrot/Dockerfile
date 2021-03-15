FROM parrotsec/core
RUN apt update && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt update && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt dist-upgrade -y && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt install --no-install-recommends aircrack-ng asleap freeradius-wpe hostapd-wpe iw kismet mdk3 mdk4 pixiewps reaver wifi-honey wifite tshark wireshark termshark vim mlocate man pciutils hashcat wpasupplicant less bash-completion ssh supervisor novnc xvfb x11vnc parrot-xfce dbus-x11 -y && \
  apt clean && \
  rm -rf /var/lib/apt/lists/* && \
  rm -f /etc/ssh/ssh_host_*

EXPOSE 22/tcp
EXPOSE 8080/tcp
ENV DISPLAY=:0

WORKDIR /root/
COPY files/supervisord.conf /etc/supervisord/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord/supervisord.conf"]
ENTRYPOINT []
