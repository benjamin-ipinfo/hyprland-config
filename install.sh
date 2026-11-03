#!/usr/bin/env bash
# Picks the installer for this machine:
#   Apple silicon Mac (Fedora Asahi Remix)  -> macbook/install.sh
#   amd64 PC (the workhorse desktop)        -> amd64/install.sh
# Both share common/lib.sh and common/ (dotfiles). Run either directly if you prefer.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
if [ -r /proc/device-tree/compatible ] && tr -d '\0' < /proc/device-tree/compatible | grep -q apple; then
  exec ./macbook/install.sh "$@"
elif [ "$(uname -m)" = x86_64 ]; then
  exec ./amd64/install.sh "$@"
else
  echo "Unsupported machine ($(uname -m)): neither an Apple silicon Mac nor amd64." >&2; exit 1
fi
