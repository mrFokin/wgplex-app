# A5 — поставка

Статус: план, ждёт согласования. Ветка `a5-delivery` от `master`.

**Вход (от пользователя, 2026-11-05):** движок `0.1.0` будет опубликован после одобрения пользователя; `api_version = 1`; `docs/api.md` движка не менялся с M3. Клиент написан по этому контракту — менять Kit не нужно.

**Цель:** design 2 и 8 — `make dmg`, README, релиз `0.1.0`, cask `wgplex-app` в `mrFokin/homebrew-tap`.

## Решения

1. **Сборка (`make dmg`)** — `scripts/dmg.sh` (комментарии английские): `swift build -c release --arch arm64 --arch x86_64`, бандл `Wgplex.app` (универсальный; `Info.plist` из шаблона `packaging/Info.plist`, версия подставляется из `VERSION`; `LSUIElement`, `LSMinimumSystemVersion 13.0`, `CFBundleIdentifier io.github.mrfokin.wgplex`), ad-hoc подпись с постоянным требованием `designated => identifier "io.github.mrfokin.wgplex"`, `hdiutil create` → `dist/Wgplex-<VERSION>.dmg` + sha256. `scripts/vm-check/make-app.sh` остаётся для быстрых проверок.
2. **Версия:** `VERSION` → `0.1.0`; `appVersion` в `Version.swift` должна совпадать — проверка в `make dmg` (сбой при расхождении), а не вторая правка руками. В режиме разработки остаётся `0.1.0-dev`.
3. **README** (английский, коротко): что это, установка (`brew trust mrfokin/tap`, `brew install --cask mrfokin/tap/wgplex-app`), первый запуск и «Open Anyway» (тексты по design 2, M0 K6/K7), автозапуск для всех пользователей (plist в `/Library/LaunchAgents`, design 6), обновление (`brew upgrade --cask wgplex-app`; ручная замена из `.dmg` требует «Open Anyway» снова), удаление, сборка из исходников, FileVault (design wgplex 18).
4. **Cask** `Casks/wgplex-app.rb` в `../homebrew-tap`: `depends_on formula: "mrfokin/tap/wgplex"`, `depends_on macos: ">= :ventura"`, `url` на релиз GitHub, `sha256`, `app "Wgplex.app"`, `zap` на defaults `io.github.mrfokin.wgplex`. Готовится как файл; коммит в tap — после одобрения.
5. **Релиз** по design wgplex 16.3: сначала движок и формула (`wgplex` 0.1.0 — вне этого плана, по вашему одобрению), потом приложение: тег `v0.1.0`, `gh release create` с `.dmg`. **Push, тег, релиз и коммит в tap — только после вашего явного одобрения** (CLAUDE.md).
6. **Иконка** (решение пользователя, 2026-11-05): белый щит из иконки меню на скруглённом квадрате, градиент индиго → синий. `scripts/make-icon.swift` (AppKit + `iconutil`) генерирует `packaging/AppIcon.icns`; готовый файл в репозитории. `Info.plist` — `CFBundleIconFile = AppIcon`, `dmg.sh` копирует его в `Contents/Resources`.
7. **Не в A5:** Developer ID и нотаризация, CI, Sparkle.

## Вопросы

- Репозиторий `mrFokin/wgplex-app` на GitHub уже есть (origin отвечает): публичный ли он уже? Проверка обновлений обращается к `releases/latest`.

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
