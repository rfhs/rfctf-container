FROM docker.io/parrotsec/core
RUN \
  # https://www.parrotsec.org/docs/mirrors/mirrors-list
  echo 'deb https://deb.parrot.sh/parrot parrot main contrib non-free' >> /etc/apt/sources.list && \
  echo 'deb https://mirrors.aliyun.com/parrot parrot main contrib non-free' >> /etc/apt/sources.list && \
  echo 'deb http://mirrors.mit.edu/parrot/ parrot main contrib non-free' >> /etc/apt/sources.list && \
  echo 'deb https://mirror.clarkson.edu/parrot/ parrot main contrib non-free' >> /etc/apt/sources.list && \
  echo 'deb https://mirror.math.princeton.edu/pub/parrot/ parrot main contrib non-free' >> /etc/apt/sources.list && \
  echo 'deb https://ftp.osuosl.org/pub/parrotos parrot main contrib non-free' >> /etc/apt/sources.list && \
  echo 'deb https://mirrors.ocf.berkeley.edu/parrot/ parrot main contrib non-free' >> /etc/apt/sources.list && \
  echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get -o Dpkg::Options::="--force-confnew" update && \
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get -o Dpkg::Options::="--force-confnew" dist-upgrade -y && \
  # missing urh, gr-lora_sdr nrsc5
  DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get -o Dpkg::Options::="--force-confnew" install --no-install-recommends aircrack-ng asleap freeradius-wpe hostapd-mana iw kismet mdk3 mdk4 pixiewps reaver wifi-honey wifite tshark wireshark termshark vim mlocate man pciutils hashcat wpasupplicant less bash-completion ssh supervisor novnc xvfb x11vnc parrot-desktop-xfce dbus-x11 dialog tmux tcpdump nmap curl gnuradio gqrx-sdr gr-osmosdr fldigi qsstv wsjtx make firefox-esr -y --allow-remove-essential && \
  # dpkg -P --force-depends xfce4-power-manager-plugins && \
  # rm -f /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml && \
  # sed -i '/power-manager-plugin/d' /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml && \
  # DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get -o Dpkg::Options::="--force-confnew" install --no-install-recommends -y equivs && \
  # equivs-control xfce4-power-manager-plugins && \
  # sed -i "s/Package:.*/Package: xfce4-power-manager-plugins/" xfce4-power-manager-plugins && \
  # sed -i "s/^# Version:.*/Version: 1:4.16.0-1/" xfce4-power-manager-plugins && \
  # equivs-build xfce4-power-manager-plugins && \
  # mv ./xfce4-power-manager-plugins_4.16.0-1_all.deb /tmp/ && \
  # chmod 666 /tmp/xfce4-power-manager-plugins_4.16.0-1_all.deb && \
  # apt-get -o Dpkg::Options::="--force-confnew" install -y /tmp/xfce4-power-manager-plugins_4.16.0-1_all.deb && \
  # rm /tmp/xfce4-power-manager-plugins_4.16.0-1_all.deb && \
  # apt-get purge -y equivs && \
  apt-get autoremove --purge -y && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  rm -f /etc/ssh/ssh_host_* && \
  cd /etc/freeradius-wpe/3.0/certs && \
  make clean && \
  cd /etc/hostapd-mana/certs && \
  rm ca.pem csr.csr dhparam.pem server.key server.pem

# Expose needed ports
EXPOSE 22/tcp
EXPOSE 8080/tcp

# Set operable environment
ENV DISPLAY=:0

COPY files/fava_beans.words /root/fava_beans.words
COPY files/supervisord-debianish.conf /etc/supervisord/supervisord.conf
COPY files/contestant-checker /usr/local/sbin/contestant-checker

WORKDIR /root
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord/supervisord.conf", "--pidfile", "/run/supervisord.pid"]
ENTRYPOINT []

HEALTHCHECK --interval=60s --start-period=30s --retries=2 CMD /usr/local/sbin/contestant-checker
