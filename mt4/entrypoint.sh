#!/bin/bash
# MT4 container entrypoint.
#   - First run: bootstrap Wine prefix, install MT4 from broker installer,
#     drop our Guardrail EA + preset into MQL4/.
#   - Subsequent runs: skip install, just launch terminal.exe.
# Runs under supervisord as PID 1 via tini.

set -euo pipefail

MARKER="/wine/.mt4_ready"
TERMINAL_EXE="/wine/drive_c/Program Files (x86)/MetaTrader 4/terminal.exe"
INSTALLER_URL="${MT4_INSTALLER_URL:-https://download.mql5.com/cdn/web/8472/mt4/icmarkets4setup.exe}"
VNC_PASSWORD="${VNC_PASSWORD:-changeme}"

log() { echo "[entrypoint] $*"; }

bootstrap_prefix() {
    log "bootstrapping Wine prefix at $WINEPREFIX"
    mkdir -p "$WINEPREFIX"
    wineboot --init 2>&1 | sed 's/^/[wineboot] /' || true
    wineserver -w
}

install_mt4() {
    log "downloading MT4 installer: $INSTALLER_URL"
    curl -fsSL "$INSTALLER_URL" -o /tmp/mt4setup.exe
    log "running silent install"
    wine /tmp/mt4setup.exe /auto 2>&1 | sed 's/^/[mt4-setup] /' || true
    wineserver -w
    rm -f /tmp/mt4setup.exe
    if [ ! -f "$TERMINAL_EXE" ]; then
        log "ERROR: terminal.exe not found after install; listing Program Files:"
        ls -la "/wine/drive_c/Program Files (x86)/" || true
        exit 1
    fi
}

stage_payload() {
    local dest="/wine/drive_c/Program Files (x86)/MetaTrader 4/MQL4"
    if [ -d /mql4-payload/MQL4 ]; then
        log "staging payload MQL4 files into $dest"
        mkdir -p "$dest"/{Experts,Indicators,Libraries,Presets}
        cp -r /mql4-payload/MQL4/. "$dest"/
    fi
}

setup_vnc_password() {
    if [ ! -f /wine/.vncpass ] && [ "$VNC_PASSWORD" != "changeme" ]; then
        x11vnc -storepasswd "$VNC_PASSWORD" /wine/.vncpass || true
    fi
}

case "${1:-main}" in
    run-mt4)
        cd "$(dirname "$TERMINAL_EXE")"
        exec wine "$TERMINAL_EXE"
        ;;
    main|*)
        if [ ! -f "$MARKER" ]; then
            bootstrap_prefix
            install_mt4
            stage_payload
            setup_vnc_password
            touch "$MARKER"
            log "bootstrap complete"
        else
            log "prefix already initialized (marker present)"
            stage_payload
        fi
        exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
        ;;
esac
