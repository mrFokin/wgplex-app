#!/bin/bash
# Runs INSIDE the VM as admin. Builds the GUI harness (real app sources) with the 26.5 SDK
# (the CLT default SDK 27 lacks the SwiftUIMacros plugin) and runs it in the GUI session.
# usage: run-gui.sh [admin|guest]
set -euo pipefail
who=${1:-admin}
cd ~/wgplex-app/scripts/vm-check/gui
ln -sfn ../../../../Sources/WgplexKit Sources/WgplexKit
for f in ../../../Sources/Wgplex/*.swift; do
  b=$(basename $f); [ "$b" = main.swift ] && continue
  ln -sf ../../../../../Sources/Wgplex/$b Sources/WgplexGUI/$b
done
swift build --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk 2>&1 | grep -E "error|Build complete" || true
bin=$(find .build -name WgplexGUI -type f -perm +111 | head -1)
sudo cp "$bin" /tmp/WgplexGUI; sudo chmod 755 /tmp/WgplexGUI
rm -rf /tmp/shots; mkdir -p /tmp/shots; chmod 777 /tmp/shots
pkill -x Wgplex-run || true
if [ "$who" = guest ]; then u=wgguest; else u=admin; fi
sudo launchctl asuser 501 sudo -u $u /tmp/WgplexGUI /tmp/shots $who > /tmp/gui-$who.log 2>&1 || true
cat /tmp/gui-$who.log
