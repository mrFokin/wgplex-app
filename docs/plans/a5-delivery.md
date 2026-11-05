# A5 — поставка

Статус: в работе (задачи 0–3 сделаны, ревью пройдено). Ветка `a5-delivery` от `master`.

**Вход (от пользователя, 2026-11-05):** движок `0.1.0` будет опубликован после одобрения пользователя; `api_version = 1`; `docs/api.md` движка не менялся с M3. Клиент написан по этому контракту — менять Kit не нужно.

**Цель:** design 2 и 8 — `make dmg`, README, релиз `0.1.0`, cask `wgplex-app` в `mrFokin/homebrew-tap`.

## Решения

1. **Сборка (`make dmg`)** — `scripts/dmg.sh` (комментарии английские): `swift build -c release --arch arm64 --arch x86_64`, бандл `Wgplex.app` (универсальный; `Info.plist` из шаблона `packaging/Info.plist`, версия подставляется из `VERSION`; `LSUIElement`, `LSMinimumSystemVersion 13.0`, `CFBundleIdentifier io.github.mrfokin.wgplex`), ad-hoc подпись с постоянным требованием `designated => identifier "io.github.mrfokin.wgplex"`, `hdiutil create` → `dist/Wgplex-<VERSION>.dmg` + sha256. `scripts/vm-check/make-app.sh` остаётся для быстрых проверок.
2. **Версия:** `VERSION` → `0.1.0`; `appVersion` в `Version.swift` должна совпадать — проверка в `make dmg` (сбой при расхождении), а не вторая правка руками. После релиза `VERSION` и `appVersion` поднимаются вместе до `0.1.1-dev` (иначе dev-сборка считает себя старше релиза и проверка обновлений покажет баннер).
3. **README** (английский, коротко): что это, установка (`brew trust mrfokin/tap`, `brew install --cask mrfokin/tap/wgplex-app`), первый запуск и «Open Anyway» (тексты по design 2, M0 K6/K7), автозапуск для всех пользователей (plist в `/Library/LaunchAgents`, design 6), обновление (`brew upgrade --cask wgplex-app`; ручная замена из `.dmg` требует «Open Anyway» снова), удаление, сборка из исходников, FileVault (design wgplex 18).
4. **Cask** `Casks/wgplex-app.rb` в `../homebrew-tap`: `depends_on formula: "mrfokin/tap/wgplex"`, `depends_on macos: :ventura`, `url` на релиз GitHub, `sha256`, `app "Wgplex.app"`, `zap` на defaults `io.github.mrfokin.wgplex`. Готовится как файл; коммит в tap — после одобрения.
5. **Релиз** по design wgplex 16.3: сначала движок и формула (`wgplex` 0.1.0 — вне этого плана, по вашему одобрению), потом приложение: тег `v0.1.0`, `gh release create` с `.dmg`. **Push, тег, релиз и коммит в tap — только после вашего явного одобрения** (CLAUDE.md).
6. **Иконка** (решение пользователя, 2026-11-05): белый щит из иконки меню на скруглённом квадрате, градиент индиго → синий. `scripts/make-icon.swift` (AppKit + `iconutil`) генерирует `packaging/AppIcon.icns`; готовый файл в репозитории. `Info.plist` — `CFBundleIconFile = AppIcon`, `dmg.sh` копирует его в `Contents/Resources`.
7. **Не в A5:** Developer ID и нотаризация, CI, Sparkle.

## Вопросы

- ~~Публичность `mrFokin/wgplex-app`~~ — публичен (пользователь, 2026-11-05); `releases/latest` и `homepage` cask доступны.

## Правки design.md в этой ветке

Только если выяснится расхождение (например, уточнение порядка «движок → приложение»).

## Задачи

| # | Задача | Кто | Файлы |
|---|---|---|---|
| 0 | Иконка: `scripts/make-icon.swift`, `packaging/AppIcon.icns` | оркестратор | `scripts/make-icon.swift`, `packaging/AppIcon.icns` |
| 1 | `packaging/Info.plist` (с `CFBundleIconFile`), `scripts/dmg.sh` (копирует иконку), цель `make dmg`, проверка `VERSION` ↔ `appVersion` | swift-dev | `packaging/`, `scripts/dmg.sh`, `Makefile` |
| 2 | README | general-purpose (sonnet) | `README.md` |
| 3 | Cask (файл в `../homebrew-tap`, не коммитить до одобрения; `brew style`/`brew audit --cask` локально без установки) | general-purpose (sonnet) | `../homebrew-tap/Casks/wgplex-app.rb` |
| 4 | `make check`, `make dmg` на хосте (только сборка, без запуска `.app`) | оркестратор | — |
| 5 | Ревью | reviewer | — |
| 6 | Проверка в VM (одноразовая `wgp-check-*`): монтирование `.dmg`, универсальный бинарник (`lipo -info`), подпись/требование, запуск; установка по cask из локального tap — только если получится без публикации, иначе шаги за пользователем; «Open Anyway» — за пользователем | агент + пользователь | `scripts/vm-check/` |
| 7 | Слияние по условиям CLAUDE.md | оркестратор | — |
| 8 | Релиз `0.1.0` (push, тег, `gh release`, tap) | оркестратор, **после одобрения** | — |

## Ход работы

- Вход: движок 0.1.0 опубликован (`brew install mrfokin/tap/wgplex`, `sudo brew services start --sudo-service-user=root wgplex`), `api_version = 1`, `api.md` не менялся с M3. A5 разблокирован.
- Задача 0 (иконка) сделана: `.icns` собран, превью проверено.
- Задача 1 сделана (swift-dev, коммит a9b1ba2, влит fast-forward): `packaging/Info.plist`, `scripts/dmg.sh`, `make dmg`. `VERSION` и `appVersion` = `0.1.0`; суффикс `-dev` допускается с предупреждением, CFBundleVersion без суффикса. После релиза обе строки поднять вместе до `0.1.1-dev`. Оркестратор: `make check` — 177 тестов зелёные; `make dmg` проходит, универсальный бинарник (x86_64 + arm64), ad-hoc подпись с требованием `identifier`, `Wgplex-0.1.0.dmg`. `.app` не запускался.
- Задачи 2 и 3 сделаны (sonnet). README влит (b6d412b) + правки оркестратора: LaunchAgent через `/usr/bin/open -g -a` (прямой запуск бинарника мог дать второй экземпляр рядом с записью входа), убрано непроверенное объяснение про `brew upgrade` и «Open Anyway». Для VM-проверки (задача 6): plist из README, текст диалога «Open Anyway». Cask `../homebrew-tap/Casks/wgplex-app.rb` создан, не закоммичен; `depends_on macos: :ventura` (`brew style` не принимает `">= :ventura"`); sha256 локального образа `bbebc0fb…` — перед релизом сверить с загружаемым файлом; `brew audit --cask --new` — после коммита в tap.
- Ревью (reviewer): блокеров нет. Исправлено: команды установки LaunchAgent и удаление plist в README, строка про `brew upgrade` без «Open Anyway» возвращена со ссылкой на design 2 (проверить в VM), очистка iconset в `make-icon.swift`, статус и решение 2 плана. Обязательный шаг задачи 8: загружать в релиз тот самый `dist/Wgplex-0.1.0.dmg`, чей sha256 в cask (образ при каждой сборке иной), после загрузки скачать и пересчитать sha256, и только потом коммитить tap. Ждут решения пользователя: `CFBundleDevelopmentRegion` `ru`, правка design.md:15 (`:ventura`), `uninstall quit:` в cask.
- Решения пользователя по ревью: `CFBundleDevelopmentRegion = ru` (проверить в VM: системные строки по-русски); `design.md:15` обновлён (`:ventura`); `uninstall quit:` в cask не добавляем.
- Задача 6 (VM `wgp-check-a5`, автоматическая часть): `scripts/vm-check/a5-check.sh` — 14/14 PASS: `hdiutil verify`, монтирование, ссылка `Applications`, универсальный бинарник, подпись и требование, регион `ru`, версия 0.1.0, иконка в Resources, запуск `.app`, plist из README (lint, bootstrap, один экземпляр, повторный `open` не плодит второй). За пользователем: «Open Anyway», иконка в Finder/Dock, русские системные строки, `brew upgrade --cask` без повторного «Open Anyway».
- GUI-шаги в VM пройдены пользователем (2026-11-05): «Open Anyway», иконка, русские системные строки. `brew upgrade --cask` без повторного «Open Anyway» — после публикации релиза.
- Релиз 0.1.0 (одобрен пользователем, 2026-11-05): push `master` и тег `v0.1.0`, `gh release` с `.dmg` и `.sha256`; sha256 скачанного из релиза файла = `b485befe…` = в cask. Cask закоммичен и запушен в tap (`1e8a950`). В VM (bridged): `brew tap`, `brew trust`, `brew install --cask mrfokin/tap/wgplex-app` ставит формулу `wgplex` и приложение (подпись adhoc, `com.apple.quarantine`). `brew audit --cask --new` — единственная претензия «GitHub repository not notable enough» (критерий официального cask, для собственного tap не применим). Не проверено: `brew upgrade --cask` без повторного «Open Anyway» — нужна вторая версия. NAT-режим VM при поднятых туннелях хоста не достаёт github.com — использовать bridged.
- После релиза: `VERSION` и `appVersion` = `0.1.1-dev`.
