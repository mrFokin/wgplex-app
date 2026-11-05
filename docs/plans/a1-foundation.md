# A1 — основа

Статус: план согласован пользователем. Ветка `a1-foundation` от `master`.

**Цель:** в `WgplexKit` — клиент API движка, модели ответов, поиск движка и три состояния «без движка», фейковый сервер для XCTest. UI нет. Контракт — `docs/api.md` движка (`../wgplex`, `master`, `api_version: 1`); код Wirefork (`../wirefork/app/Sources/WireforkKit`: `Client`, `HTTP`, `RPC`) берётся как заготовка и сверяется с контрактом, не наоборот.

## Вход (из «Хода работы» M3)

Движок `0.1.0-dev`, `api_version: 1`. Сокет принимает всех; `status.get`, `diag.*` — всем, но без права управления (`can_control: false`) ответ урезан (`docs/api.md`, Redaction). Изменяющие методы — ошибка `5` с `data.control_group`. `tunnel.setEnabled` заменён на `tunnel.enable`/`tunnel.disable`; новые `daemon.pause`/`resume`. Поля только добавляются, неизвестные клиент игнорирует. Обратной совместимости с Wirefork нет.

## Решения

1. **Транспорт:** `UnixTransport` на Network.framework (`NWConnection` к unix-сокету), один запрос — одно соединение, таймаут; путь сокета ≥104 байт — ошибка, не краш. `Client` принимает замыкание `roundTrip` (как в Wirefork) — клиентские тесты без сокета.
2. **JSON-RPC поверх HTTP/1.1:** `POST /rpc`, `Content-Type: application/json`, одиночные запросы (батчи не нужны). Разбор HTTP — минимальный (статус, `Content-Length`/до EOF). HTTP 413/415 и чужие статусы — `RPCError.transport`. Ответ с ошибкой — всегда HTTP 200, 403 не бывает.
3. **Ошибки:** `RPCError` — `unavailable` (сокет/таймаут), `transport`, `server(code, message, data)`; типизированные коды `1`–`5` (`configInvalid(errors, warnings)`, `notConfigured`, `unknownTunnel`, `tunnelStartFailed`, `permissionDenied(controlGroup)`) и стандартные `-327xx`.
4. **Методы клиента:** `status()`, `explain(_:)`, `routes()`, `reload()`, `enable(_:)` → `EnableResult`, `disable(_:)`, `disableAll()`, `pause()`, `resume()`.
5. **Модели** (`Decodable`, `Sendable`, `Equatable`): `Status`, `TunnelStatus`, `PeerStatus`, `CheckStatus`, `RuleStatus`, `Explanation`, `Routes`, `RouteInfo`, `ApplyResult`, `EnableResult`. «Omitted when empty» → опциональные поля или значения по умолчанию, неизвестные поля игнорируются, времена — RFC 3339 (с дробной частью и без). `state`, `icon`, `reason`, `kind`, `target`, `source` — enum с запасным `.unknown(String)`, чтобы новое значение не ломало разбор.
6. **Поиск движка (design 3):** `Engine.locate(...)`: префиксы `/opt/homebrew`, `/usr/local`; переопределение пути сокета; результат — `EngineState`: `notInstalled` (нет `<prefix>/opt/wgplex/bin/wgplex`) | `notRunning` (бинарник есть, сокет отсутствует или `status.get` не ответил) | `outdated(apiVersion)` (`api_version` < `minAPIVersion = 1`) | `ready(Status)`. Проверка файлов и вызов клиента — через внедряемые замыкания (без FS и сети в тестах). Тексты и команды `brew` — слой UI (A2/A3), не A1.
7. **Фейковый сервер:** `FakeAPIServer` в тестах — настоящий unix-сокет (POSIX `socket/bind/listen` в фоновом потоке), отдаёт заданные JSON-ответы по методу и записывает запросы; нужен для `UnixTransport` и сквозного `Client`. Остальные тесты — на замыкании `roundTrip`.
8. **Фикстуры:** JSON-ответы сверены с примерами и таблицами `docs/api.md` (полный и редактированный `status.get`, `degraded` с каждым `reason`, `paused`, `configured: false` + `block_snapshot`). Ключей WireGuard нет.

## Не в A1

Представление для меню (`Present`: галочки, строка проблемы, заголовок «Приостановить») — A2, когда понятна форма меню. Вычисление уведомлений — A4. Опрос по таймеру, `ConfigDir` (приложение конфиг не читает), UI, `Info.plist`.

## Правки design.md в этой ветке

- Раздел 1: контракт появился (`docs/api.md`, `api_version: 1`), оговорку «намерение, а не контракт» убрать.
- Раздел 4: туннель включён на паузе, `tunnel.enable` вернул `starts_on_resume` — отметка «запустится после возобновления».

## Задачи

| # | Задача | Кто | Файлы |
|---|---|---|---|
| 1 | Сигнатуры: модели, `RPCError`, `Client`, `UnixTransport`, `Engine`/`EngineState` с `fatalError("not implemented")`; коммит | swift-dev | `Sources/WgplexKit/*` |
| 2 | Реализация: HTTP, RPC, транспорт, декодирование, `Engine.locate` | swift-dev | `Sources/WgplexKit/*` |
| 3 | Тесты: модели/фикстуры, RPC и ошибки, HTTP-разбор, `Engine`, `FakeAPIServer` + транспорт — по `docs/api.md` и сигнатурам, без реализации | test-dev (параллельно с 2) | `Tests/WgplexKitTests/*` |
| 4 | `make check`, правка design.md | оркестратор | — |
| 5 | Ревью диффа | reviewer | — |
| 6 | Слияние по условиям CLAUDE.md (ручной проверки в A1 нет: UI отсутствует) | оркестратор | — |

## Ход работы

(заполняется оркестратором)
