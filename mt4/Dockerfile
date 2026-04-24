FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEPREFIX=/wine \
    WINEARCH=win64 \
    DISPLAY=:0 \
    WINEDEBUG=fixme-all,err-ole

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg2 software-properties-common \
        xvfb x11vnc fluxbox supervisor \
        novnc websockify \
        cabextract \
        winbind \
        procps tini && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
      -o /usr/local/bin/winetricks && chmod +x /usr/local/bin/winetricks

RUN mkdir -p /wine /mt4-install /mql4-payload /novnc-web && \
    ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh    /entrypoint.sh
COPY healthcheck.sh   /healthcheck.sh
RUN chmod 0755 /entrypoint.sh /healthcheck.sh && \
    sed -i 's/\r$//' /entrypoint.sh /healthcheck.sh && \
    bash -n /entrypoint.sh && bash -n /healthcheck.sh && \
    ls -la /entrypoint.sh /healthcheck.sh

COPY payload/MQL4 /mql4-payload/MQL4

EXPOSE 6080 5900

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
  CMD /bin/bash /healthcheck.sh

# Invoke bash explicitly instead of relying on shebang + exec bit so the
# container starts even if the file mode is weird (git/COPY quirks).
ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "/entrypoint.sh"]
