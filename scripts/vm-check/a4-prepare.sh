#!/bin/bash
# HOST side: recreates the check VM `app` (wgp-check-app) WITH a window, deploys the engine and the
# app sources, starts the daemon, builds the ad-hoc Wgplex.app and launches it with clean defaults
# (so the first-run question appears). Only talks to the VM through ../wgplex/scripts/vm.sh.
# usage: scripts/vm-check/a4-prepare.sh [--no-launch]
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
V=$root/../wgplex/scripts/vm.sh
engine=$root/../wgplex/build/wgplex   # universal binary from `make build` in ../wgplex
[ -x "$engine" ] || { echo "no $engine: run 'make build' in ../wgplex" >&2; exit 1; }
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

"$V" list | grep -q 'wgp-check-app ' && "$V" down app
"$V" up app --gui
rsync -a --exclude .build --exclude .git --exclude shots "$root/" "$stage/wgplex-app/"
"$V" cp app "$stage/wgplex-app" "$engine" '~/'
"$V" ssh app 'mv ~/wgplex ~/wgplex-bin'
"$V" ssh app 'bash ~/wgplex-app/scripts/vm-check/setup-engine.sh &&
  sudo sh -c "nohup /opt/homebrew/opt/wgplex/bin/wgplex daemon -v >/tmp/daemon.log 2>&1 </dev/null &"'
"$V" ssh app 'cd ~/wgplex-app && mkdir -p ~/out &&
  SWIFT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk bash scripts/vm-check/make-app.sh ~/out'
if [ "${1:-}" != --no-launch ]; then
  "$V" ssh app 'until launchctl print gui/501 >/dev/null 2>&1; do sleep 2; done; sleep 5
    sudo launchctl asuser 501 sudo -u admin defaults delete io.github.mrfokin.wgplex 2>/dev/null || true
    sudo launchctl asuser 501 sudo -u admin open ~/out/Wgplex.app'
fi
echo "VM ready: $V ssh app   (window is open on the host)"
