FROM pentoolinux/pentoo-core
RUN echo 'FEATURES="-ipc-sandbox -network-sandbox -pid-sandbox"' >> /etc/portage/make.conf && \
  echo 'VIDEO_CARDS=""' >> /etc/portage/make.conf && \
  sed -i 's#-livecd#-drivers -pulseaudio -vnc opencl#' /etc/portage/make.conf
RUN  emerge --sync
RUN  emerge --usepkg=y --buildpkg=n --jobs=$(nproc) pentoo/rfhs-rfctf && \
  emerge --depclean --with-bdeps=n && \
  rm -rf /var/{binpkgs,distfiles}/* /var/db/repos/*

EXPOSE 22/tcp
EXPOSE 8080/tcp
ENV DISPLAY=:0

WORKDIR /root/
COPY files/cyberpunk.words /root/cyberpunk.words
COPY files/supervisord.conf /etc/supervisord/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord/supervisord.conf", "--pidfile", "/run/supervisord.pid"]
ENTRYPOINT []
