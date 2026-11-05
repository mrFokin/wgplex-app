#!/bin/bash
# Runs INSIDE the VM as admin: builds the smoke package and runs it.
set -euo pipefail
cd ~/wgplex-app/scripts/vm-check/smoke
ln -sfn ../../../../Sources/WgplexKit Sources/WgplexKit
swift build -c release 2>&1 | tail -15
sudo cp .build/release/smoke /tmp/wgsmoke
sudo chmod 755 /tmp/wgsmoke
/tmp/wgsmoke "${1:-admin}"
