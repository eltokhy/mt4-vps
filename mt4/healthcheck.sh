#!/bin/bash
# Passes if noVNC port is listening and terminal.exe is running under Wine.
set -e
curl -fsS http://localhost:6080/ >/dev/null
pgrep -f terminal.exe >/dev/null
