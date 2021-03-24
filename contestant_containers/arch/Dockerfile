FROM docker.io/library/archlinux:latest
LABEL maintainer "Trevor Bryant <@apporima>"

# WORKAROUND for glibc 2.33 and old Docker
# See https://github.com/actions/virtual-environments/issues/2658
# Thanks to https://github.com/lxqt/lxqt-panel/pull/1562
RUN patched_glibc=glibc-linux4-2.33-4-x86_64.pkg.tar.zst && \
    curl -LO "https://repo.archlinuxcn.org/x86_64/$patched_glibc" && \
    bsdtar -C / -xvf "$patched_glibc"

# Install BlackArch
WORKDIR /root
COPY files/strap.sh /root/strap.sh
# Set execute bit
RUN chmod +x strap.sh
# Run strap.sh, remove strap.sh
RUN ./strap.sh

# Install packages
RUN pacman -Syu --noconfirm git make gcc pkgconf which python-pip wget openssh vim tmux screen supervisor iw mlocate man pciutils less bash-completion xorg-server-xvfb x11vnc dialog xfce4 xfce4-goodies xfce4-power-manager inetutils \
# rfctf tools
    hostapd wpa_supplicant bully wireshark-qt wireshark-cli aircrack-ng mdk3 mdk4 freeradius asleap hostapd-wpe wifite pixiewps reaver hashcat hashcat-utils hcxtools hcxdumptool

# Install packages from source
# noVNC -- copied from https://github.com/ponsfrilus/arch-novnc
WORKDIR /opt/
RUN git clone https://github.com/kanaka/noVNC.git
# Avoid another checkout when launching noVnc
WORKDIR /opt/noVNC/utils/
RUN git clone https://github.com/kanaka/websockify

# Expose ssh port
EXPOSE 22/tcp
EXPOSE 8080/tcp
ENV DISPLAY=:0

# Clean up environment
RUN rm -r /etc/hostapd-wpe/certs/*
RUN rm -r /root/strap.sh 

# Set operable environment
WORKDIR /root
#COPY files/cyberpunk.words /root/cyberpunk.words
COPY files/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "--pidfile", "/run/supervisord.pid"]
ENTRYPOINT []
