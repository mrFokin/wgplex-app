# A2 — меню

Статус: план согласован (2026-11-05); в работе. Ветка `a2-menu` от `master`.

**Цель:** menu-bar приложение: `NSStatusItem` с иконкой по состоянию, меню по design 4 (туннели с галочками, строка проблемы, пауза, «Открыть Wgplex…», «Выход»), три состояния «без движка» (design 3). Окно (A3) — заглушка: пункт «Открыть Wgplex…» и строка проблемы пока ничего не открывают (или открывают пустое окно-заглушку — решение 6).

## Решения

1. **Представление в `WgplexKit` (`Present`):** чистая функция `MenuModel.make(from: EngineState) -> MenuModel` без AppKit. `MenuModel` — иконка (`off/on/warn/paused/unavailable`), список строк туннелей (`name`, `checked`, `warn`, `dimmed` на паузе, `enabled` = `canControl`, `startsOnResume`-пометка), строка проблемы (текст + цель: `rule(i)`/`tunnel(name)`/`config`/`daemon`), заголовок паузы («Приостановить»/«Возобновить», активность), тексты состояний без движка. Покрыто XCTest.
2. **Иконка:** берётся из `status.icon` движка (`off/on/warn/paused`); `unknown` → как `warn`; движок недоступен (`notInstalled`/`notRunning`/`outdated`) — отдельная иконка «!». Template-изображения рисуются кодом (`NSImage` через `NSBezierPath`, щит: контур / залитый / с «!» / с паузой) — без ресурсов и ассетов.
3. **Строка проблемы:** первая из: `configErrorCount > 0` → «ошибка конфига»; правило `inFallback`/`degraded` → «<service> на резерве» / «… недоступно»; туннель `dead`/`error` с `enabled`; движок недоступен. Порядок и тексты — в `Present`, тесты по фикстурам A1.
4. **Состояния без движка (design 3):** в меню — одна строка-статус + действия: «не установлен» → «Как установить…» (открывает страницу README/релиза, URL — константа); «Демон не запущен» → пункт «Копировать команду запуска» (`sudo brew services start --sudo-service-user=root wgplex`); «Обновите wgplex» → «Копировать команды обновления» (две команды). Остальных пунктов нет, кроме «Выход».
5. **Опрос (`StatusPoller`, в приложении, не в Kit):** `status.get` через `Engine.locate` при `menuNeedsUpdate`; пока меню открыто — раз в 1,5 с (`Timer` в `.common`); в фоне — раз в 10 с для иконки. Результат — `EngineState` на main actor; меню перестраивается на месте (`NSMenu.update`/замена items без закрытия).
6. **Действия:** щелчок по туннелю → `enable`/`disable`; пауза → `pause`/`resume`; после действия — немедленный `status.get`. Ошибки (`permissionDenied`, `tunnelStartFailed`, …) — строка проблемы + `NSAlert` не нужен: короткое сообщение в строке до следующего опроса. `can_control: false` — пункты неактивны.
7. **`Sources/Wgplex`:** `main.swift` → `NSApplication` с `.accessory` (без Dock), `AppDelegate`, `StatusController` (NSStatusItem + NSMenu), `Icons.swift`. Окно A3 — пункт «Открыть Wgplex…» неактивен до A3 (проще, чем заглушка); строка проблемы тоже без перехода.
8. **Не в A2:** окно, автозапуск, уведомления, проверка обновлений, настройки (в т. ч. переопределение сокета — до A3 только дефолтный поиск), `Info.plist`/бандл (A5; `swift run` запускает как accessory-приложение).

## Правки design.md в этой ветке

- Раздел 4: порядок строки проблемы и тексты состояний; «Открыть Wgplex…» неактивен до A3 — не вносить (это план, не дизайн). Правок дизайна ожидается ноль; если они понадобятся — согласовать.

## Задачи

| # | Задача | Кто | Файлы |
|---|---|---|---|
| 1 | Сигнатуры `MenuModel`/`Present` с `fatalError`; коммит | swift-dev | `Sources/WgplexKit/Present.swift` |
| 2 | Реализация `Present` | swift-dev | `Sources/WgplexKit/Present.swift` |
| 3 | Тесты `Present`: иконка, галочки, ⚠, пауза/серые, `starts_on_resume`, `can_control: false`, порядок строки проблемы, тексты трёх состояний — по design 3–4 и фикстурам | test-dev (параллельно с 2) | `Tests/WgplexKitTests/PresentTests.swift` |
| 4 | AppKit-слой: `AppDelegate`, `StatusController`, `StatusPoller`, `Icons` (после 2) | swift-dev | `Sources/Wgplex/*` |
| 5 | `make check` | оркестратор | — |
| 6 | Ревью диффа | reviewer | — |
| 7 | Ручная проверка (пользователь): `swift run Wgplex` без движка — три состояния и иконка; с запущенным движком — галочки, переключение, пауза, ⚠, меню обновляется при открытии | пользователь | — |
| 8 | Слияние по условиям CLAUDE.md | оркестратор | — |

## Ход работы

(пусто)
