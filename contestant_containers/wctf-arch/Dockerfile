FROM docker.io/library/archlinux
LABEL maintainer "Trevor Bryant <@apporima>"

# WORKAROUND for glibc 2.33 and old Docker
# See https://github.com/actions/virtual-environments/issues/2658
# Thanks to https://github.com/lxqt/lxqt-panel/pull/1562
RUN patched_glibc=glibc-linux4-2.33-4-x86_64.pkg.tar.zst && \
    curl -LO "https://repo.archlinuxcn.org/x86_64/$patched_glibc" && \
    bsdtar -C / -xvf "$patched_glibc"

# Install packages
RUN pacman -Sy --noconfirm git make gcc pkgconf which python-pip wget hostapd wpa_supplicant bully openssh vim wireshark-cli tmux screen supervisor

# Download current WCTF wordlist
RUN wget https://raw.githubusercontent.com/rfhs/wctf-files/master/wordlist/cyberpunk.words -O /root/cyberpunk.words

# Permit root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN ssh-keygen -A

# Change root password to "toor"
RUN echo "root:toor" | chpasswd

# Expose ssh port
EXPOSE 22/tcp

# Set operable environment
WORKDIR /root
COPY files/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "--pidfile", "/run/supervisord.pid"]
ENTRYPOINT []
