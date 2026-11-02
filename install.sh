#!/usr/bin/env bash
# Picks the installer for this machine:
#   Apple silicon Mac (Fedora Asahi Remix)  -> install-asahi.sh
#   amd64 PC (the workhorse desktop)        -> install-amd64.sh
# Both share lib/common.sh. Run either directly if you prefer.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
if [ -r /proc/device-tree/compatible ] && tr -d '\0' < /proc/device-tree/compatible | grep -q apple; then
  exec ./install-asahi.sh "$@"
elif [ "$(uname -m)" = x86_64 ]; then
  exec ./install-amd64.sh "$@"
else
  echo "Unsupported machine ($(uname -m)): neither an Apple silicon Mac nor amd64." >&2; exit 1
fi
