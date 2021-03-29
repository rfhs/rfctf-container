FROM pentoolinux/pentoo-core:latest
ADD portage_and_overlay.tar.xz /
#this run contains things which have been merged into pentoo-core and should be removed
RUN eselect profile set pentoo:pentoo/hardened/linux/amd64_r1/binary && \
  echo 'VIDEO_CARDS=""' >> /etc/portage/make.conf
#CAP_SYS_ADMIN CAP_NET_ADMIN
RUN echo 'FEATURES="-ipc-sandbox -network-sandbox -pid-sandbox"' >> /etc/portage/make.conf && \
  sed -i 's#-livecd#-drivers -pulseaudio -vnc opencl rfctf-wifi rfctf-virtual rfctf-minimal#' /etc/portage/make.conf
RUN emerge --getbinpkg=y --buildpkg=n --jobs=$(nproc) --deep --update --newuse pentoo/rfctf-client
RUN emerge --jobs=$(nproc) --deep --update --newuse @world
RUN emerge --depclean --with-bdeps=n --jobs=$(nproc)
RUN rm -rf /var/cache/{binpkgs,distfiles}/* /var/db/repos/*

EXPOSE 22/tcp
EXPOSE 8080/tcp
ENV DISPLAY=:0

WORKDIR /root/
COPY files/supervisord.conf /etc/supervisord/supervisord.conf
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord/supervisord.conf", "--pidfile", "/run/supervisord.pid"]
ENTRYPOINT []
