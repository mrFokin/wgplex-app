#!/bin/bash
# Runs INSIDE the VM as admin, in a terminal of the GUI session (needs the daemon and ~/out/Wgplex.app
# from a4-prepare.sh). Interactive walk through the manual A4 checks: the script runs the triggers,
# you look at the screen and answer y/n. Summary at the end.
# usage: a4-manual.sh
set -uo pipefail
W=/opt/homebrew/opt/wgplex/bin/wgplex
C=/opt/homebrew/etc/wgplex/wgplex.yaml
APP=$HOME/out/Wgplex.app
ID=io.github.mrfokin.wgplex
pass=0; fail=0; failed=()

cp "$C" /tmp/orig.yaml
restore() {
  cp /tmp/orig.yaml "$C"; $W reload >/dev/null 2>&1
  defaults delete $ID update.version >/dev/null 2>&1
  defaults delete $ID update.url >/dev/null 2>&1
  pgrep -x wgplex >/dev/null || start_daemon
}
start_daemon() {
  sudo sh -c "nohup /opt/homebrew/opt/wgplex/bin/wgplex daemon -v >/tmp/daemon.log 2>&1 </dev/null &"
}
trap restore EXIT

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask() { # <id> <question>
  local a
  while true; do
    read -r -p "  ? $2 [y/n] " a
    case "$a" in
      y|Y) echo "  PASS $1"; pass=$((pass+1)); return ;;
      n|N) read -r -p "  что не так (Enter — пропустить): " why
           echo "  FAIL $1 ${why:+— $why}"; fail=$((fail+1)); failed+=("$1 ${why:+— $why}"); return ;;
    esac
  done
}
wait_enter() { read -r -p "  [Enter] когда готово " _; }

say "0. Подготовка: приложение запущено?"
if ! pgrep -x Wgplex >/dev/null; then
  echo "  приложение не запущено — запускаю с чистыми настройками (появится вопрос первого запуска)"
  defaults delete $ID >/dev/null 2>&1 || true
  open "$APP"; sleep 4
fi

say "1. Первый запуск"
echo "  Должен быть вопрос «Запускать Wgplex при входе?». Нажмите «Запускать»,"
echo "  затем разрешите уведомления в системном запросе."
ask first-run "вопрос появился, разрешение на уведомления запросили"

say "2. Автозапуск включён"
sleep 2
sudo sfltool dumpbtm 2>/dev/null | grep -i -B2 -A8 wgplex | head -30
ask login-on "в выводе одна запись Wgplex (Open at Login), она включена"
echo "  Откройте Системные настройки → Основные → Объекты входа."
ask login-ui "Wgplex есть в списке «Open at Login»"

say "3. Настройки (⌘, или «Настройки…» в меню значка)"
echo "  Выключите «Запускать при входе»."
wait_enter
sudo sfltool dumpbtm 2>/dev/null | grep -i -B2 -A8 wgplex | head -30
ask login-off "запись Wgplex выключена или исчезла"
echo "  Включите «Запускать при входе» снова."
wait_enter
sudo sfltool dumpbtm 2>/dev/null | grep -i -B2 -A8 wgplex | head -30
ask login-on-again "запись снова включена"
echo "  Снимите и снова поставьте «Проверять обновления», затем «Уведомления»."
wait_enter
defaults read $ID
ask settings-persist "значения переключателей в defaults совпадают с окном"

say "4a. Туннель умер: beta"
echo "  выключаю beta, через 15 с включаю, жду 75 с (check должен упасть)..."
$W down beta >/dev/null; sleep 15; $W up beta >/dev/null; sleep 75
ask n-dead "пришёл баннер «beta не отвечает» с «svc-a → alpha»"
echo "  Щёлкните по баннеру."
ask click-tunnel "окно открылось на туннеле beta"

say "4b. Ошибка конфига при reload (из CLI)"
echo 'bogus_key: 1' >> "$C"; $W reload; sleep 20
ask n-config "баннер «Изменения конфига не применены: 1 ошибка… Работает прежний конфиг»"
echo "  Щёлкните по баннеру."
ask click-config "окно открылось на разделе «Туннели» (отдельного раздела «Конфиг» нет, баннер ошибки конфига ведёт туда)"
cp /tmp/orig.yaml "$C"; $W reload >/dev/null; sleep 12

say "4c. Демон пропал и вернулся"
sudo pkill -x wgplex; sleep 25
ask n-daemon-down "баннер «wgplex не работает»"
start_daemon; sleep 25
ask n-daemon-up "баннер «wgplex снова работает»"

say "4d. Пауза и переключатели не уведомляют"
$W pause >/dev/null; sleep 15; $W resume >/dev/null; sleep 15
$W up gamma >/dev/null; sleep 15; $W down gamma >/dev/null; sleep 15
ask silent "за это время НОВЫХ баннеров не было (alpha/beta могли умереть сами — это не считается)"

say "5. «Перечитать» в окне — без своего уведомления"
echo 'bogus_key: 1' >> "$C"
echo "  Откройте окно (меню значка → «Открыть Wgplex…») и нажмите «Перечитать конфиг»."
wait_enter; sleep 15
ask own-reload "результат виден в окне, отдельного баннера не пришло"
cp /tmp/orig.yaml "$C"; $W reload >/dev/null

say "6. Холодный запуск по клику на баннер"
echo "  Сейчас закрою приложение, вызову баннер и запущу приложение заново."
pkill -x Wgplex; sleep 2
$W down beta >/dev/null; sleep 15; $W up beta >/dev/null
echo "  Приложение закрыто — баннер не придёт. Запускаю приложение, ждите баннера «beta не отвечает»"
echo "  (если уже висит старый баннер в Центре уведомлений — щёлкните по нему)."
open "$APP"; sleep 75
echo "  Щёлкните по баннеру в Центре уведомлений."
ask cold-click "окно открылось на нужном разделе"

say "7. Баннер обновления"
echo "  Баннер обновления скрыт любой проблемой (мёртвый туннель, пауза...), поэтому ставлю конфиг без правил."
cat > "$C" <<'YAML'
control_group: admin
tunnels:
  - name: gamma
    conf: gamma.conf
    routes: config
    autostart: false
YAML
$W reload >/dev/null; sleep 15
defaults write $ID update.version -string 9.9.9
defaults write $ID update.url -string https://github.com/mrFokin/wgplex-app/releases/tag/v9.9.9
pkill -x Wgplex; sleep 2; open "$APP"; sleep 8
echo "  Откройте окно приложения."
ask update-banner "баннер «Доступна новая версия» с командой brew upgrade --cask wgplex-app, кнопками «Скопировать команду» и «Страница релиза»"
ask update-copy "после «Скопировать команду» вставка в терминал даёт эту команду"
defaults delete $ID update.version; defaults delete $ID update.url
cp /tmp/orig.yaml "$C"; $W reload >/dev/null

say "8. Уведомления выключены"
echo "  В настройках снимите «Уведомления»."
wait_enter
$W down beta >/dev/null; sleep 15; $W up beta >/dev/null; sleep 75
ask notif-off "баннера не пришло"
echo "  Верните «Уведомления» в настройках."

say "Итог: PASS=$pass FAIL=$fail"
for f in "${failed[@]}"; do echo "  FAIL $f"; done
echo "Конфиг восстановлен. Удалить VM на хосте: ../wgplex/scripts/vm.sh down app"
