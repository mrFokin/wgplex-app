#!/bin/bash
# Runs INSIDE the VM (as admin, uses sudo). Mimics the formula layout (design 16.4)
# and writes a test config with generated throwaway keys.
set -euo pipefail
P=/opt/homebrew
sudo mkdir -p $P/opt/wgplex/bin $P/etc $P/var/run $P/var/wgplex $P/var/log/wgplex
sudo cp ~/wgplex-bin $P/opt/wgplex/bin/wgplex
sudo chmod 755 $P/opt/wgplex/bin/wgplex
# formula-like: config dir owned by the brew user (admin), 0700
sudo mkdir -p $P/etc/wgplex
sudo chown admin:admin $P/etc/wgplex
chmod 700 $P/etc/wgplex
sudo chown admin:admin $P/var/log/wgplex $P/var/wgplex $P/var/run 2>/dev/null || true
C=$P/etc/wgplex
key() { openssl rand -base64 32; }
mkconf() { # name addr endpoint allowed
  cat > $C/$1.conf <<CONF
[Interface]
PrivateKey = $(key)
Address = $2
[Peer]
PublicKey = $(key)
Endpoint = $3
AllowedIPs = $4
PersistentKeepalive = 25
CONF
  chmod 600 $C/$1.conf
}
mkconf alpha 10.77.0.2/32 192.0.2.10:51820 10.77.0.1/32
mkconf beta  10.77.1.2/32 192.0.2.11:51820 10.77.1.1/32
mkconf gamma 10.77.2.2/32 192.0.2.12:51820 10.88.0.0/24
cat > $C/wgplex.yaml <<'YAML'
control_group: admin
tunnels:
  - name: alpha
    conf: alpha.conf
    routes: rules
    autostart: true
  - name: beta
    conf: beta.conf
    routes: rules
    autostart: true
    check: 10.77.1.1
  - name: gamma
    conf: gamma.conf
    routes: config
    autostart: false
services:
  svc-a:
    domains: [a.test.example]
  svc-b:
    cidrs: [203.0.113.0/24]
rules:
  - services: [svc-a]
    via: [beta, alpha]
    fallback: default
  - services: [svc-b]
    via: [alpha]
    fallback: block
YAML
chmod 600 $C/wgplex.yaml
echo setup done
