#!/bin/bash
# Runs INSIDE the VM as admin (needs the daemon set up by setup-engine.sh and ~/out/Wgplex.app
# from make-app.sh). Drives the real ad-hoc .app in the GUI session of admin (uid 501) and counts
# banners that usernoted delivers for it (unified log: "Delivering <NotificationRecord app:...>").
# Notification text is <private> in the log, so texts are covered by `smoke notify`; here we check
# WHEN the app posts: count per trigger. First-run alert is skipped (firstRunDone) because it needs a click.
# usage: a4-app-check.sh
set -uo pipefail
W=/opt/homebrew/opt/wgplex/bin/wgplex
C=/opt/homebrew/etc/wgplex/wgplex.yaml
APP=$HOME/out/Wgplex.app
ID=io.github.mrfokin.wgplex
GU() { sudo launchctl asuser 501 sudo -u admin "$@"; }
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1 (got $3)"; pass=$((pass+1)); else echo "FAIL $1 (want $2, got $3)"; fail=$((fail+1)); fi; }
stamp() { date "+%Y-%m-%d %H:%M:%S"; }
delivered() { # since <stamp>
  sudo log show --start "$1" --info --debug 2>/dev/null |
    grep -c "usernoted.*Delivering <NotificationRecord app:\"$ID\""
}
cp "$C" /tmp/orig.yaml
restore() { cp /tmp/orig.yaml "$C"; $W reload >/dev/null 2>&1; }
trap restore EXIT

echo "--- A1. app starts with an existing problem: first poll is silent"
pkill -x Wgplex; sleep 1
defaults delete $ID >/dev/null 2>&1 || true
GU defaults write $ID firstRunDone -bool true
$W up alpha >/dev/null; $W up beta >/dev/null; $W down gamma >/dev/null
sleep 45   # beta is dead (check) before the app starts
t=$(stamp)
GU open "$APP"; sleep 6
pgrep -x Wgplex >/dev/null && ok "app running" 1 1 || ok "app running" 1 0
sleep 24
ok "A1 existing problem: no banner" 0 "$(delivered "$t")"
echo "INFO lastCheck(update): $(defaults read $ID update.lastCheck 2>&1)"

echo "--- A2. intentional actions are silent"
t=$(stamp)
$W down alpha >/dev/null; $W down beta >/dev/null; sleep 12
$W pause >/dev/null; sleep 12; $W resume >/dev/null; sleep 12
$W up gamma >/dev/null; sleep 12; $W down gamma >/dev/null; sleep 14
ok "A2 pause/resume/toggle: no banner" 0 "$(delivered "$t")"

echo "--- A3. tunnel dies with rules moving to reserve"
t=$(stamp)
$W up alpha >/dev/null; $W up beta >/dev/null
sleep 70
ok "A3 beta dead: one banner" 1 "$(delivered "$t")"

echo "--- A4. config error on reload"
t=$(stamp)
echo "bogus_key: 1" >> "$C"; $W reload >/dev/null 2>&1; sleep 25
ok "A4 config error: one banner" 1 "$(delivered "$t")"
t=$(stamp)
restore; sleep 25
ok "A4 restore good config: no banner" 0 "$(delivered "$t")"

echo "--- A5. daemon gone / back"
t=$(stamp)
sudo pkill -TERM -x wgplex; sleep 25
ok "A5 daemon stopped: one banner" 1 "$(delivered "$t")"
t=$(stamp)
sudo sh -c "nohup /opt/homebrew/opt/wgplex/bin/wgplex daemon -v >/dev/null 2>&1 </dev/null &"; sleep 30
ok "A5 daemon back: one banner" 1 "$(delivered "$t")"

echo "--- A6. app still alive, no crash reports"
pgrep -x Wgplex >/dev/null && ok "app alive after all triggers" 1 1 || ok "app alive after all triggers" 1 0
ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i wgplex || echo "INFO no Wgplex crash reports"

echo "--- A7. update banner state restored from defaults (restart with a newer version stored)"
pkill -x Wgplex; sleep 1
GU defaults write $ID update.version -string 9.9.9
GU defaults write $ID update.url -string https://github.com/mrFokin/wgplex-app/releases/tag/v9.9.9
GU open "$APP"; sleep 8
pgrep -x Wgplex >/dev/null && ok "app runs with stored update" 1 1 || ok "app runs with stored update" 1 0
echo "SUMMARY pass=$pass fail=$fail"
