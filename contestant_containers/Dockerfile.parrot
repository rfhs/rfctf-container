FROM docker.io/parrotsec/core:latest
RUN \
  echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io && \
  echo 'deb https://deb.parrotsec.io/parrot echo main contrib non-free non-free-firmware' > /etc/apt/sources.list.d/parrotsec.list && \
  echo 'deb https://deb.parrotsec.io/direct/parrot echo-security main contrib non-free non-free-firmware' >> /etc/apt/sources.list.d/parrotsec.list && \
  echo 'deb https://deb.parrotsec.io/parrot echo-backports main contrib non-free non-free-firmware' >> /etc/apt/sources.list.d/parrotsec.list && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get -o Dpkg::Options::="--force-confnew" update && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get -o Dpkg::Options::="--force-confnew" dist-upgrade -y && \
  # missing/broken urh, gr-lora_sdr, nrsc5a, freeradius-wpe
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get -o Dpkg::Options::="--force-confnew" install --no-install-recommends aircrack-ng asleap hostapd-mana iw mdk3 mdk4 pixiewps reaver wifi-honey wifite tshark wireshark termshark vim plocate man pciutils hashcat wpasupplicant less bash-completion ssh supervisor novnc xvfb x11vnc dbus-x11 dialog tmux tcpdump nmap curl gnuradio gqrx-sdr gr-osmosdr fldigi qsstv wsjtx make firefox-esr libnotify-bin kismet parrot-desktop-xfce xfce4-notifyd echo-themes -y --allow-remove-essential && \
  apt-get autoremove --purge -y && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  rm -f /etc/ssh/ssh_host_* && \
  #cd /etc/freeradius-wpe/3.0/certs && \
  #make clean && \
  cd /etc/hostapd-mana/certs && \
  rm ca.pem csr.csr dhparam.pem server.key server.pem && \
  sed -i 's/#X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config && \
  # "fix" xfce panel
  rm -f /usr/share/desktop-base/profiles/xdg-config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml && \
  rm -f /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml && \
  rm -f /usr/lib/parrot-skel/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml && \
  rm -f /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml && \
  # "fix" xfce backdrop
  rm /usr/share/backgrounds/xfce/xfce-x.svg && \
  ln -s /usr/share/wallpapers/EchoWallpaper/contents/images/1920x1080.png /usr/share/backgrounds/xfce/xfce-x.svg

# Expose needed ports
EXPOSE 22/tcp
EXPOSE 8080/tcp

# Set operable environment
ENV DISPLAY=:0

COPY files/2026-2027_cyberpunk.words /root/2026-2027_cyberpunk.words
COPY files/supervisord-debianish.conf /etc/supervisord/supervisord.conf
COPY files/contestant-checker /usr/local/sbin/contestant-checker
COPY files/contestant_start /usr/local/sbin/contestant_start

WORKDIR /root
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord/supervisord.conf", "--pidfile", "/run/supervisord.pid"]
ENTRYPOINT []

HEALTHCHECK --interval=300s --start-period=120s --retries=2 CMD /usr/local/sbin/contestant-checker
