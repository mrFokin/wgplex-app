#!/bin/bash
# Runs INSIDE the VM as admin. Checks the release .dmg (copied to ~/Wgplex-<ver>.dmg):
# mount, bundle layout, universal binary, ad-hoc signature, launch, and the all-users
# LaunchAgent plist from README (loads, starts exactly one instance). GUI steps
# ("Open Anyway", icon in Finder, Russian system strings) stay manual.
# usage: a5-check.sh <path-to.dmg>
set -uo pipefail
DMG=${1:?dmg}
ID=io.github.mrfokin.wgplex
PL=/Library/LaunchAgents/$ID.plist
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1 (got $3)"; pass=$((pass+1)); else echo "FAIL $1 (want $2, got $3)"; fail=$((fail+1)); fi; }
GU() { sudo launchctl asuser 501 sudo -u admin "$@"; }

hdiutil verify "$DMG" >/dev/null 2>&1; ok "hdiutil verify" 0 $?
MNT=$(hdiutil attach -nobrowse -readonly "$DMG" | awk -F'\t' '/\/Volumes/{print $NF}' | tail -1)
ok "mounted" 1 "$([ -d "$MNT/Wgplex.app" ] && echo 1 || echo 0)"
ok "Applications link" 1 "$([ -L "$MNT/Applications" ] && echo 1 || echo 0)"
sudo rm -rf /Applications/Wgplex.app
sudo cp -R "$MNT/Wgplex.app" /Applications/ && hdiutil detach "$MNT" >/dev/null
A=/Applications/Wgplex.app
echo "INFO $(lipo -info $A/Contents/MacOS/Wgplex)"
ok "universal" 2 "$(lipo -archs $A/Contents/MacOS/Wgplex | wc -w | tr -d ' ')"
ok "codesign verify" 0 "$(codesign --verify --strict $A 2>&1; echo $?)" || true
codesign -d -r- $A 2>&1 | grep -q "identifier \"$ID\""; ok "designated requirement" 0 $?
ok "region" ru "$(/usr/libexec/PlistBuddy -c 'Print CFBundleDevelopmentRegion' $A/Contents/Info.plist)"
ok "version" 0.1.0 "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' $A/Contents/Info.plist)"
ok "icon file" 1 "$([ -f $A/Contents/Resources/AppIcon.icns ] && echo 1 || echo 0)"

echo "--- direct launch"
pkill -x Wgplex; sleep 1
GU defaults write $ID firstRunDone -bool true
GU open "$A"; sleep 5
ok "launched" 1 "$(pgrep -x Wgplex | wc -l | tr -d ' ')"
pkill -x Wgplex; sleep 1

echo "--- all-users LaunchAgent from README"
cat > /tmp/$ID.plist <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.github.mrfokin.wgplex</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>-a</string>
        <string>/Applications/Wgplex.app</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
P
sudo cp /tmp/$ID.plist /Library/LaunchAgents/
sudo chown root:wheel $PL; sudo chmod 644 $PL
plutil -lint $PL >/dev/null; ok "plist lint" 0 $?
sudo launchctl bootstrap gui/501 $PL; ok "bootstrap" 0 $?
sleep 6
ok "agent started one instance" 1 "$(pgrep -x Wgplex | wc -l | tr -d ' ')"
# second activation via open must not create a second instance
GU open -g -a "$A"; sleep 3
ok "still one instance" 1 "$(pgrep -x Wgplex | wc -l | tr -d ' ')"
sudo launchctl bootout gui/501/$ID 2>/dev/null
pkill -x Wgplex; sudo rm -f $PL
echo "== PASS $pass FAIL $fail"
[ $fail = 0 ]
