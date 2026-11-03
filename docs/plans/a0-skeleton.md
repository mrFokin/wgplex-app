# A0 — каркас

Статус: план на согласовании (2026-11-03). Ветка `a0-skeleton` от `master` нового репозитория.

**Цель:** репозиторий `wgplex-app` с правилами работы, агентами, разделом 17 дизайна и собирающимся пустым Swift Package. Логики нет. Правила — design wgplex 17, 21.2 (A0), 21.3; `CLAUDE.md` репозитория `wgplex` (образец).

«design wgplex N» — раздел N `docs/design.md` репозитория `mrFokin/wgplex` (локально `/Users/da_fokin/Projects/claude/wgplex`).

## Контекст

- `../wgplex-app` — пустой каталог без git. GitHub-репозиторий `mrFokin/wgplex-app` не существует. `wgplex` — публичный, ветка по умолчанию `master`.
- Контракт API неполный: `docs/api.md` движка появится в M3. A0 его не использует.
- Источник каркаса Swift — `app/Package.swift` Wirefork: swift-tools 6.0, macOS 13+, режим языка Swift 6, три таргета (Kit, исполняемый, тесты). Стоит Swift 6.4.2.
- Код Wirefork (`Client`, `HTTP`, `RPC`, `Present`, `ConfigDir`) в A0 **не переносится**: это A1 после M3; `ConfigDir` приложению не нужен вовсе (design wgplex 17.7: без чтения конфига).

## Решения

1. **Таргеты:** библиотека `WgplexKit` (логика под XCTest), исполняемый `Wgplex` (зависит от `WgplexKit`), тесты `WgplexKitTests`. Имена по образцу Wirefork. Режим языка Swift 6, `platforms: [.macOS(.v13)]`, зависимостей нет.
2. **Заглушки без логики:** `Sources/WgplexKit/Version.swift` (`public let appVersion = "0.1.0-dev"` — нужен, чтобы таргет не был пустым), `Sources/Wgplex/main.swift` (печатает версию и выходит; AppKit-меню — A2), один дымовой тест версии, чтобы `swift test` реально что-то запускал.
3. **`Makefile`:** `check` (= `swift build` + `swift test`), `build`, `test`, `clean`. `make dmg` — A5, в A0 его нет. Файл `VERSION` как в `wgplex` (`0.1.0-dev`), `Version.swift` пока дублирует его константой; связать при A5.
4. **`design.md` нового репозитория** — свой, на русском. Раздел 17 переносится целиком (17.1–17.7), но нумерация собственная:

   | wgplex-app | wgplex |
   |---|---|
   | 1. Задача и связь с движком (новое, коротко) | — |
   | 2. Поставка | 17.1 |
   | 3. Движок | 17.2 |
   | 4. Меню | 17.3 |
   | 5. Окно | 17.4 |
   | 6. Автозапуск | 17.5 |
   | 7. Уведомления | 17.6 |
   | 8. Сборка | 17.7 |
   | 9. План реализации (A0–A5, зависимости) | 21.2, 21.3 |

   Ссылки внутри раздела пересчитываются на новые номера (`17.6` → `7`). Ссылки на движок получают префикс: `(14)` → `(design wgplex 14)`, `(15)`, `(5)`, `(16.1)`, `(9)`, `(12)` и т. д. Ссылки на факты spike `(M0, K4, K11, S1–S6 …)` → `(design wgplex M0, K4)` с пояснением в разделе 1: факты — в `docs/plans/m0-spike.md` репозитория `wgplex`. Точку «контракт API» раздел 1 указывает как `docs/api.md` движка (появится в M3; до тех пор поля `reason`, `can_control`, `api_version`, `paused`, ошибка `5` в разделах 3–7 — намерение, а не контракт). Вводная строка исходного 17 («раздел переносится сюда») удаляется; в design wgplex при слиянии A0 она заменяется ссылкой на репозиторий — **правка чужого репозитория, только по вашему слову** (см. вопрос 4).
5. **`CLAUDE.md`** — по образцу `wgplex/CLAUDE.md`: источник истины, принципы (KISS, без привилегированного кода в приложении, без чтения конфига, ключей и конфига движка), структура (Sources/Tests/docs), проверки (`make check`), границы (на хосте — без `sudo`, launchd, объектов входа; GUI-проверки — шаги пользователя), Git (ветки `a<N>-<slug>`, коммиты, слияние, push — по одобрению), сессии, мультиагентный процесс, блок «Дальше». Отличия от образца: Go → Swift, VM не нужна (приложение ничего не меняет в системе), рамки A1: «клиент пишется по `docs/api.md` движка, не по Wirefork». Вход A1 — текст для `wgplex-app` из «Хода работы» M3 (версия движка, `api_version`, добавленное).
6. **Агенты** `.claude/agents/`: `swift-dev` (opus; аналог `go-dev`: Swift-код по задаче, свои unit-тесты, сигнатуры `fatalError("not implemented")`, без `sudo`, `swift build`/`make check` в конце, коммит с `Co-Authored-By`), `test-dev` (sonnet; XCTest по design.md и публичным сигнатурам, фейковый сервер API — A1), `reviewer` (opus, только чтение; пункты образца с поправками: нет Wirefork-имён — `io.github.mrfokin.wirefork`, `Wirefork`; приложение не читает конфиг и не делает привилегированных вызовов; API-клиент против `docs/api.md`).
7. **Идентификатор приложения:** `io.github.mrfokin.wgplex` (design 8, постоянное требование подписи). В A0 нигде не используется, кроме записи в CLAUDE.md/дизайне.
8. **Git:** `git init -b master`; первый коммит — `.gitignore` (`.build/`, `.claude/worktrees/`, `*.dmg`) и `CLAUDE.md`, дальше работа в `a0-skeleton`, слияние в `master` по условиям CLAUDE.md. **Push и создание GitHub-репозитория — только после вашего одобрения.**

## Структура

```
Package.swift
Makefile
VERSION
CLAUDE.md
.gitignore
.claude/agents/{swift-dev,test-dev,reviewer}.md
Sources/WgplexKit/Version.swift
Sources/Wgplex/main.swift
Tests/WgplexKitTests/VersionTests.swift
docs/design.md
docs/plans/a0-skeleton.md
```

README и `Info.plist` — A5 (README пишется вместе с текстами первого запуска, design 2).

## Не в A0

Клиент API, модели статуса, фейковый сервер, поиск движка, AppKit, Info.plist, `make dmg`, подпись, README, CI, перенос кода Wirefork.

## Задачи

Все — оркестратор напрямую (документы и ~20 строк Swift; агенты для такого объёма дороже работы). Агенты создаются как файлы для A1+.

| # | Задача | Проверка |
|---|---|---|
| 1 | `git init`, `.gitignore`, `CLAUDE.md`, коммит в `master`; ветка `a0-skeleton` | `git log` |
| 2 | `.claude/agents/*.md` | чтение: нет Go/Wirefork-остатков (`grep -ri 'go\b\|wirefork'`) |
| 3 | `Package.swift`, `Version.swift`, `main.swift`, тест, `Makefile`, `VERSION` | `make check` зелёный; `swift run Wgplex` печатает версию |
| 4 | `docs/design.md`: раздел 17 с пересчётом номеров и ссылок, разделы 1 и 9 | `grep -n '([0-9]' docs/design.md` — каждая ссылка либо на раздел этого файла, либо с префиксом «design wgplex»; сверка с оригиналом по абзацам |
| 5 | Ревью диффа субагентом `reviewer` (по образцу — после его создания), исправления | отчёт в «Ходе работы» |
| 6 | Слияние `a0-skeleton` → `master` после зелёного `make check` и вашей приёмки | `make check` на `master` |
| 7 | (после вашего одобрения) создать `mrFokin/wgplex-app`, push | `gh repo view` |

Порядок: 1 → 2, 3, 4 (независимы) → 5 → 6 → 7.

## Ход работы

(пусто — ждёт согласования плана)
