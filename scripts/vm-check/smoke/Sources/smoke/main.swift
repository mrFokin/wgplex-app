import Foundation
import WgplexKit

// Integration smoke: WgplexKit against a live daemon in the check VM.
// Modes: admin (default, full scenario), guest <phase> (user outside control_group),
// member (user in control_group, not the config owner).

let sock = "/opt/homebrew/var/run/wgplex.sock"
let cfgDir = "/opt/homebrew/etc/wgplex"
let cfgYAML = cfgDir + "/wgplex.yaml"
let bin = "/opt/homebrew/opt/wgplex/bin/wgplex"

nonisolated(unsafe) var passes = 0
nonisolated(unsafe) var fails = 0

func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok {
        passes += 1
        print("PASS \(name)")
    } else {
        fails += 1
        print("FAIL \(name) :: \(detail())")
    }
}

func info(_ s: String) { print("INFO \(s)") }

@discardableResult
func sh(_ cmd: String) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    p.standardInput = FileHandle.nullDevice
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func locate(prefixes: [String] = Engine.prefixes) async -> EngineState {
    await Engine.locate(
        prefixes: prefixes,
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        status: { try await Client(path: $0).status() })
}

let client = Client(path: sock)

func ready() async -> Status? {
    if case .ready(let s) = await locate() { return s }
    return nil
}

func waitFor(_ secs: Double, _ cond: () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(secs)
    while Date() < end {
        if await cond() { return true }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return await cond()
}

func tunnel(_ s: Status?, _ n: String) -> TunnelStatus? { s?.tunnels.first { $0.name == n } }

func stopDaemon() async {
    sh("sudo pkill -TERM -x wgplex")
    _ = await waitFor(20) { !FileManager.default.fileExists(atPath: sock) }
}

func startDaemon() async {
    sh("sudo sh -c 'nohup \(bin) daemon -v >/dev/null 2>&1 </dev/null &'")
    _ = await waitFor(30) { await ready() != nil }
}

// ---- copy of the private LogFile of Sources/Wgplex/LogsView.swift (keep in sync) ----
enum LogFile {
    enum Failure { case noAccess, notFound, other(String) }
    enum Result {
        case failed(Failure)
        case truncated
        case data(start: UInt64, bytes: Data, inode: UInt64)
    }

    static func read(path: String, offset: UInt64, maxBytes: Int, inode: UInt64?) -> Result {
        let fd = open(path, O_RDONLY)
        if fd < 0 {
            switch errno {
            case EACCES: return .failed(.noAccess)
            case ENOENT: return .failed(.notFound)
            default: return .failed(.other(String(cString: strerror(errno))))
            }
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var st = stat()
        guard fstat(fd, &st) == 0 else { return .failed(.other(String(cString: strerror(errno)))) }
        let ino = UInt64(st.st_ino)
        let size = UInt64(max(st.st_size, 0))
        if size < offset || (inode != nil && inode != ino) { return .truncated }
        let start = offset == 0 && size > UInt64(maxBytes) ? size - UInt64(maxBytes) : offset
        do {
            try handle.seek(toOffset: start)
            let bytes = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            return .data(start: start, bytes: bytes, inode: ino)
        } catch {
            return .failed(.other(error.localizedDescription))
        }
    }
}

/// One iteration of LogsView.follow (without sleeping): returns false on failure.
struct Follower {
    var tail = LogTail()
    var inode: UInt64?
    var lastFailure: LogFile.Failure?
    let path: String

    mutating func step() {
        while true {
            switch LogFile.read(path: path, offset: tail.offset, maxBytes: tail.maxBytes, inode: inode) {
            case .failed(let f):
                lastFailure = f
                return
            case .truncated:
                lastFailure = nil
                tail.reset()
                inode = nil
                continue
            case .data(let start, let bytes, let ino):
                lastFailure = nil
                inode = ino
                if start != tail.offset { tail.offset = start }
                if !bytes.isEmpty { tail.append(bytes) }
                return
            }
        }
    }
}

func isNoAccess(_ f: LogFile.Failure?) -> Bool { if case .noAccess = f { return true }; return false }
func isNotFound(_ f: LogFile.Failure?) -> Bool { if case .notFound = f { return true }; return false }

func serverCode(_ error: Error) -> Int? {
    if let e = error as? RPCError, case .server(let code, _, _) = e { return code }
    return nil
}

func permissionDenied(_ name: String, _ call: () async throws -> Void) async {
    do {
        try await call()
        check(false, "\(name): error 5 expected", "no error")
    } catch {
        let kind = (error as? RPCError)?.kind
        check(kind == .permissionDenied(controlGroup: "admin"), "\(name): error 5 permissionDenied(admin)", "\(error)")
        check(actionErrorText(error) == "Нет прав на управление", "\(name): actionErrorText", actionErrorText(error))
    }
}

func tunnelDump(_ s: Status) -> String {
    s.tunnels.map { "\($0.name)=\($0.state)/en:\($0.enabled)" }.joined(separator: " ")
}

// =============================================================================
// guest: a user outside control_group
// =============================================================================
func runGuest(phase: String) async {
    print("--- guest (\(phase)) uid=\(getuid())")
    guard let s = await ready() else { check(false, "guest: status ready"); return }
    check(!s.canControl, "guest: can_control false")
    check(s.controlGroup == "admin", "guest: control_group visible", s.controlGroup)
    check(!s.configDir.isEmpty && !s.logPath.isEmpty, "guest: config_dir/log_path visible")
    check(s.tunnels.flatMap(\.peers).allSatisfy { $0.endpoint == nil && $0.resolved == nil },
        "guest: peers endpoint/resolved redacted")
    check(s.tunnels.allSatisfy { $0.check?.addr == nil }, "guest: check.addr redacted")
    check(s.tunnels.allSatisfy { $0.reason == nil && $0.error == nil }, "guest: reason/error redacted")
    check(s.configErrors.isEmpty && s.warnings.isEmpty, "guest: config_errors/warnings redacted")
    check(s.tunnels.count == 3 && s.rules.count == 2, "guest: names/states visible", tunnelDump(s))
    if phase == "dead" {
        check(tunnel(s, "beta")?.state == .dead, "guest: dead state stays visible (reason hidden)", tunnelDump(s))
    }
    if phase == "broken" {
        check(s.configErrorCount > 0, "guest: config_error_count > 0 while config_errors hidden", "\(s.configErrorCount)")
    }
    let state = EngineState.ready(s)
    let win = WindowModel.make(from: state)
    check(!win.actions.pauseEnabled && !win.actions.disableAllEnabled && !win.actions.reloadEnabled,
        "guest: ActionBar all disabled")
    let menu = MenuModel.make(from: state)
    check(!menu.pauseEnabled && menu.tunnels.allSatisfy { !$0.enabled }, "guest: menu toggles/pause disabled")
    if phase == "dead" {
        check(win.tunnels.first { $0.row.name == "beta" }?.endpoint == nil, "guest: TunnelDetail without endpoint")
    }
    await permissionDenied("guest enable") { _ = try await client.enable("alpha") }
    await permissionDenied("guest disable") { try await client.disable("alpha") }
    await permissionDenied("guest disableAll") { try await client.disableAll() }
    await permissionDenied("guest pause") { try await client.pause() }
    await permissionDenied("guest resume") { try await client.resume() }
    await permissionDenied("guest reload") { _ = try await client.reload() }
    if let ex = try? await client.explain("a.test.example") {
        check(ex.servers.isEmpty && ex.addrs.isEmpty, "guest: explain servers/addrs redacted")
        check(ex.rule != nil, "guest: explain still names the rule")
    } else { check(false, "guest: explain works") }
    if let r = try? await client.routes() {
        check(!r.routes.isEmpty && r.routes.allSatisfy { $0.names.isEmpty }, "guest: routes names redacted", "\(r.routes.count)")
    } else { check(false, "guest: routes works") }

    var f = Follower(path: s.logPath)
    f.step()
    check(isNoAccess(f.lastFailure), "guest: LogFile -> EACCES (noAccess)", "\(String(describing: f.lastFailure))")
    let canRead = access(s.configDir, R_OK) == 0
    let acc = ConfigDirAccess.describe(path: s.configDir, canRead: canRead)
    check(acc == .adminOnly(s.configDir) && acc.note == "Конфиг правит администратор",
        "guest: config dir adminOnly + note", "\(acc)")
}

// =============================================================================
// member: in control_group, not the config owner
// =============================================================================
func runMember() async {
    print("--- member uid=\(getuid())")
    guard let s = await ready() else { check(false, "member: status ready"); return }
    check(s.canControl, "member: can_control true via group")
    check(s.tunnels.flatMap(\.peers).contains { $0.endpoint != nil }, "member: endpoints visible")
    let win = WindowModel.make(from: .ready(s))
    check(win.actions.pauseEnabled && win.actions.disableAllEnabled && win.actions.reloadEnabled, "member: ActionBar enabled")
    var f = Follower(path: s.logPath)
    f.step()
    check(f.lastFailure == nil && !f.tail.lines.isEmpty, "member: log readable via group", "\(f.tail.lines.count)")
    do { try await client.disable("gamma"); check(true, "member: disable (idempotent) allowed") }
    catch { check(false, "member: disable allowed", "\(error)") }
    let acc = ConfigDirAccess.describe(path: s.configDir, canRead: access(s.configDir, R_OK) == 0)
    check(acc == .adminOnly(s.configDir), "member: config dir (0700 admin) adminOnly", "\(acc)")
}

// =============================================================================
// admin: full scenario
// =============================================================================
func runGuestAs(_ user: String, _ args: String) {
    let (_, out) = sh("sudo -u \(user) /tmp/wgsmoke \(args)")
    for line in out.split(separator: "\n") {
        print("  [\(user)] \(line)")
        if line.hasPrefix("PASS") { passes += 1 }
        if line.hasPrefix("FAIL") { fails += 1 }
    }
}

func writeConfig(_ text: String) {
    try? text.write(toFile: cfgYAML, atomically: false, encoding: .utf8)
    chmod(cfgYAML, 0o600)
}

func runAdmin() async {
    let origYAML = (try? String(contentsOfFile: cfgYAML, encoding: .utf8)) ?? ""
    precondition(!origYAML.isEmpty, "no config")

    // ---- state 1: not installed
    print("--- 1. три состояния")
    let ni = await locate(prefixes: ["/nonexistent-prefix"])
    check(ni == .notInstalled, "locate: notInstalled for a prefix without the binary", "\(ni)")
    let niMenu = MenuModel.make(from: ni)
    check(niMenu.unavailable?.statusText == "wgplex не установлен" && niMenu.icon == .unavailable, "menu: notInstalled")
    let niWin = WindowModel.make(from: ni)
    check(niWin.banner?.kind == .daemonUnavailable && niWin.banner?.text == "wgplex не установлен", "window: banner notInstalled")

    // ---- state 2: daemon stopped
    await stopDaemon()
    let nr = await locate()
    check(nr == .notRunning, "locate: notRunning with daemon stopped", "\(nr)")
    let nrMenu = MenuModel.make(from: nr)
    check(nrMenu.unavailable?.statusText == "Демон не запущен" && nrMenu.tunnels.isEmpty && nrMenu.pauseTitle == nil,
        "menu: notRunning", "\(nrMenu)")
    let nrWin = WindowModel.make(from: nr)
    check(nrWin.banner?.kind == .daemonUnavailable && nrWin.banner?.text == "Демон не запущен" && nrWin.banner?.target == .daemon,
        "window: banner daemonUnavailable", "\(String(describing: nrWin.banner))")
    check(!nrWin.actions.pauseEnabled && !nrWin.actions.reloadEnabled && nrWin.tunnels.isEmpty, "window: ActionBar disabled, no tunnels")
    do { _ = try await client.status(); check(false, "client.status with stopped daemon throws") }
    catch { check((error as? RPCError).map { if case .unavailable = $0 { return true } else { return false } } ?? false,
        "client.status -> RPCError.unavailable", "\(error)") }

    // ---- state 3: running
    await startDaemon()
    guard let s0 = await ready() else { check(false, "locate: ready after start"); return }
    check(true, "locate: ready after start")
    check(s0.apiVersion == 1 && s0.canControl && s0.controlGroup == "admin" && s0.configured,
        "status: api_version 1, can_control, control_group admin, configured", "\(s0.apiVersion) \(s0.canControl) \(s0.controlGroup)")
    check(s0.configDir == cfgDir && s0.logPath.hasSuffix("wgplex.log"), "status: config_dir/log_path", "\(s0.configDir) \(s0.logPath)")
    check(tunnel(s0, "alpha")?.state == .up && tunnel(s0, "gamma")?.state == .off && tunnel(s0, "gamma")?.enabled == false,
        "status: alpha up, gamma off", tunnelDump(s0))
    check(s0.rules.count == 2, "status: 2 rules")
    let m0 = MenuModel.make(from: .ready(s0))
    check(m0.tunnels.map(\.name) == ["alpha", "beta", "gamma"] && m0.tunnels.map(\.checked) == [true, true, false] && m0.pauseTitle == "Приостановить",
        "menu: tunnel rows + pause title", "\(m0.tunnels.map { "\($0.name):\($0.checked)" })")
    check(m0.tunnels.allSatisfy(\.enabled) && m0.pauseEnabled, "menu: controls enabled for admin")
    let w0 = WindowModel.make(from: .ready(s0))
    check(w0.actions.pauseEnabled && w0.actions.disableAllEnabled && w0.actions.reloadEnabled, "window: ActionBar enabled for admin")
    check(w0.actions.pauseTitle == "Приостановить", "window: pause title")
    if let a = w0.tunnels.first(where: { $0.row.name == "alpha" }) {
        info("alpha detail: endpoint=\(a.endpoint ?? "-") iface=\(a.interface ?? "-") addr=\(a.addresses) hs=\(a.handshakeText ?? "-") traffic=\(a.trafficText ?? "-") routes=\(a.routeCount)")
        check(a.endpoint == "192.0.2.10:51820" && a.interface?.hasPrefix("utun") == true && a.addresses == ["10.77.0.2/32"],
            "window: alpha detail (endpoint, utun, address)")
        check(a.handshakeText == "нет" && (a.trafficText ?? "").hasPrefix("↓ "), "window: alpha handshake 'нет' + traffic text", "\(a.handshakeText ?? "") \(a.trafficText ?? "")")
    } else { check(false, "window: alpha detail") }
    info("banner at start: \(String(describing: w0.banner)) icon=\(m0.icon)")

    // ---- dead tunnel (check fails x3, ~30 s)
    print("--- 2. dead туннель / правило на резерве")
    let gotDead = await waitFor(120) { tunnel(await ready(), "beta")?.state == .dead }
    check(gotDead, "beta becomes dead (check 10.77.1.1 fails)")
    if let sd = await ready() {
        let menu = MenuModel.make(from: .ready(sd))
        let win = WindowModel.make(from: .ready(sd))
        info("dead: icon=\(sd.icon) menu.icon=\(menu.icon) problem=\(String(describing: menu.problem)) banner=\(String(describing: win.banner))")
        check(sd.icon == .warn && menu.icon == .warn, "dead: icon warn")
        check(menu.tunnels.first { $0.name == "beta" }?.warn == true, "menu: beta row warn")
        let r0 = sd.rules[0]
        check(r0.degraded && r0.reason == .dead && r0.tunnel == "alpha" && !r0.inFallback, "rule 0 degraded/dead on alpha", "\(r0)")
        check(win.banner?.kind == .ruleFallback && win.banner?.text == "svc-a на резерве" && win.banner?.target == .rule(0),
            "window: banner ruleFallback 'svc-a на резерве'", "\(String(describing: win.banner))")
        check(menu.problem == ProblemRow(text: "svc-a на резерве", target: .rule(0)), "menu: problem row", "\(String(describing: menu.problem))")
        check(win.rules[0].stateText == "на резерве" && win.rules[0].reasonText == "туннель недоступен" && win.rules[0].isProblem,
            "window: rule row 'на резерве'/'туннель недоступен'", "\(win.rules[0])")
        check(win.rules[1].stateText == "ok", "window: rule 1 ok", win.rules[1].stateText)
        if let b = win.tunnels.first(where: { $0.row.name == "beta" }) {
            info("beta detail: reason=\(b.reason ?? "-") check=\(b.checkText ?? "-")")
            check(b.reason != nil && (b.checkText ?? "").hasPrefix("сбоев:"), "window: beta detail reason + 'сбоев: N'")
        }
        runGuestAs("wgguest", "guest dead")
        runGuestAs("wgmember", "member")
    }

    // ---- toggles
    print("--- 3. переключатели, выключить все, пауза")
    do {
        let r = try await client.enable("gamma")
        check(!r.startsOnResume, "enable gamma: starts_on_resume false")
        let up = await waitFor(15) { tunnel(await ready(), "gamma")?.state == .up }
        check(up, "gamma up after enable")
        let w = WindowModel.make(from: .ready((await ready())!))
        check(w.tunnels.first { $0.row.name == "gamma" }?.routeCount ?? 0 >= 1, "gamma route_count >= 1 (routes: config)")
        try await client.disable("gamma")
        let off = await waitFor(15) { tunnel(await ready(), "gamma")?.state == .off }
        check(off, "gamma off after disable")
    } catch { check(false, "enable/disable gamma", "\(error)") }

    do {
        try await client.disableAll()
        let sa = await ready()!
        check(sa.tunnels.allSatisfy { !$0.enabled && $0.state == .off }, "disableAll: all enabled=false/off", tunnelDump(sa))
        check(sa.icon == .off, "disableAll: icon off", "\(sa.icon)")
        let wa = WindowModel.make(from: .ready(sa))
        info("after disableAll: rules=\(wa.rules.map { "\($0.stateText)/\($0.reasonText ?? "-")" }) banner=\(String(describing: wa.banner))")
        check(sa.rules.allSatisfy { $0.inFallback || $0.via.isEmpty || $0.degraded }, "disableAll: rules in fallback/degraded")
        check(wa.banner == nil || wa.banner?.kind != .configError, "disableAll: deliberate state is not a config error banner")
        check(wa.rules[0].reasonText == "туннель выключен", "window: rule reason 'туннель выключен'", "\(wa.rules[0].reasonText ?? "nil")")
        check(!wa.rules[0].isProblem && wa.banner == nil, "disabled-by-user is not a problem/banner", "\(String(describing: wa.banner))")
    } catch { check(false, "disableAll", "\(error)") }

    do {
        try await client.pause()
        let sp = await ready()!
        let mp = MenuModel.make(from: .ready(sp))
        let wp = WindowModel.make(from: .ready(sp))
        check(sp.paused && sp.icon == .paused && mp.icon == .paused && mp.paused && mp.pauseTitle == "Возобновить",
            "pause: icon paused, menu 'Возобновить'")
        check(wp.banner == Banner(kind: .paused, text: "Приостановлено", target: .config) && wp.actions.pauseTitle == "Возобновить",
            "pause: window banner + ActionBar title", "\(String(describing: wp.banner))")
        let er = try await client.enable("alpha")
        check(er.startsOnResume, "pause: enable alpha -> starts_on_resume true")
        let eb = try await client.enable("beta")
        check(eb.startsOnResume, "pause: enable beta -> starts_on_resume true")
        let sp2 = await ready()!
        let mp2 = MenuModel.make(from: .ready(sp2), startsOnResume: ["alpha"])
        check(mp2.tunnels.first { $0.name == "alpha" }?.startsOnResume == true && mp2.tunnels.first { $0.name == "alpha" }?.dimmed == true,
            "pause: menu row startsOnResume + dimmed")
        check(sp2.tunnels.allSatisfy { $0.state == .off }, "pause: nothing is brought up", tunnelDump(sp2))
        try await client.resume()
        let up = await waitFor(15) { tunnel(await ready(), "alpha")?.state == .up }
        check(up, "resume: alpha up (toggle kept)")
        let sr = await ready()!
        check(!sr.paused && MenuModel.make(from: .ready(sr)).pauseTitle == "Приостановить", "resume: not paused, title back")
        check(sr.tunnels.first { $0.name == "gamma" }?.state == .off, "resume: gamma stays off")
    } catch { check(false, "pause/resume", "\(error)") }

    // ---- explain / routes
    print("--- 4. explain / routes")
    do {
        let ex = try await client.explain("a.test.example")
        info("explain domain: kind=\(ex.kind) rule=\(String(describing: ex.rule?.index)) upstream=\(ex.upstream ?? "-") zone=\(ex.zone ?? "-")")
        check(ex.kind == .domain && ex.rule?.index == 0 && ex.rule?.services == ["svc-a"], "explain domain -> rule 0 svc-a")
        let ei = try await client.explain("203.0.113.7")
        check(ei.kind == .ip && ei.rule?.index == 1 && ei.route?.tunnel == "alpha", "explain ip -> rule 1, route via alpha", "\(String(describing: ei.route))")
        do { _ = try await client.explain("bad name!"); check(false, "explain invalid -> -32602") }
        catch { check((error as? RPCError)?.kind == .invalidParams, "explain invalid -> invalidParams", "\(error)") }
        let rt = try await client.routes()
        check(rt.routes.contains { $0.prefix == "203.0.113.0/24" && $0.tunnel == "alpha" && $0.source == .ruleCIDR }, "routes: rule-cidr 203.0.113.0/24 via alpha",
            "\(rt.routes.map { $0.prefix })")
        check(rt.syncError == nil, "routes: no sync_error", rt.syncError ?? "")
        info("routes: \(rt.routes.count) entries")
    } catch { check(false, "explain/routes", "\(error)") }

    // ---- reload: valid, tunnel failing to start, broken config
    print("--- 5. reload")
    do {
        let rr = try await client.reload()
        check(rr.tunnels.isEmpty, "reload valid: tunnels empty", "\(rr.tunnels)")
    } catch { check(false, "reload valid", "\(error)") }

    // delta: enabled tunnel with an unresolvable endpoint -> start error
    sh("""
    cd \(cfgDir) && printf '[Interface]\\nPrivateKey = %s\\nAddress = 10.77.3.2/32\\n[Peer]\\nPublicKey = %s\\nEndpoint = nx.invalid:51820\\nAllowedIPs = 10.77.3.1/32\\n' "$(openssl rand -base64 32)" "$(openssl rand -base64 32)" > delta.conf && chmod 600 delta.conf
    """)
    writeConfig(origYAML.replacingOccurrences(of: "services:\n", with: "  - name: delta\n    conf: delta.conf\n    routes: rules\n    autostart: true\nservices:\n"))
    do {
        let rr = try await client.reload()
        info("reload with delta: tunnels=\(rr.tunnels.map { "\($0.name): \($0.error.prefix(80))" }) warnings=\(rr.warnings)")
        check(rr.tunnels.count == 1 && rr.tunnels[0].name == "delta" && !rr.tunnels[0].error.isEmpty, "reload: non-empty tunnels (delta failed to start)")
        let sd = await ready()!
        check(tunnel(sd, "delta")?.state == .error && tunnel(sd, "delta")?.error?.isEmpty == false, "status: delta state error with text", tunnelDump(sd))
        check(sd.icon == .warn, "status: icon warn with error tunnel")
        let md = MenuModel.make(from: .ready(sd))
        check(md.problem?.text == "delta: не поднялся" && md.problem?.target == .tunnel("delta"), "menu: problem 'delta: не поднялся'", "\(String(describing: md.problem))")
        let wd = WindowModel.make(from: .ready(sd))
        check(wd.tunnels.first { $0.row.name == "delta" }?.error != nil && wd.tunnels.first { $0.row.name == "delta" }?.row.warn == true, "window: delta detail error + warn")
        // reload result text of the app (WindowViews) is UI-only; just print
    } catch { check(false, "reload with delta", "\(error)") }
    writeConfig(origYAML)
    sh("rm -f \(cfgDir)/delta.conf")
    do { let rr = try await client.reload(); check(rr.tunnels.isEmpty, "reload: delta removed") } catch { check(false, "reload restore", "\(error)") }

    // broken config
    writeConfig(origYAML + "\nbogus_key: 1\n")
    do {
        _ = try await client.reload()
        check(false, "reload broken -> error 1 expected")
    } catch {
        if case .configInvalid(let errors, _)? = (error as? RPCError)?.kind {
            check(!errors.isEmpty, "reload broken: error 1 configInvalid with errors", "\(errors)")
            info("config errors: \(errors)")
        } else { check(false, "reload broken kind", "\(error)") }
        info("actionErrorText: \(actionErrorText(error))")
        check(actionErrorText(error).hasPrefix("Конфиг не применён: 1 ошиб"), "actionErrorText for configInvalid", actionErrorText(error))
    }
    if let sb = await ready() {
        check(sb.configErrorCount > 0 && !sb.configErrors.isEmpty && sb.configured, "status: config_errors set, previous config runs", "\(sb.configErrorCount)")
        check(sb.icon == .warn, "broken: icon warn")
        let wb = WindowModel.make(from: .ready(sb))
        check(wb.banner == Banner(kind: .configError, text: "ошибка конфига", target: .config), "window: banner configError (top priority)", "\(String(describing: wb.banner))")
        check(MenuModel.make(from: .ready(sb)).problem == ProblemRow(text: "ошибка конфига", target: .config), "menu: problem 'ошибка конфига'")
        check(tunnel(sb, "alpha")?.state == .up, "broken: alpha keeps running")
        runGuestAs("wgguest", "guest broken")
    }
    writeConfig(origYAML)
    do { _ = try await client.reload(); check(true, "reload restored") } catch { check(false, "reload restore", "\(error)") }
    if let sr = await ready() { check(sr.configErrorCount == 0 && sr.configErrors.isEmpty, "config errors cleared after good reload") }

    // ---- LogTail on the real log + synthetic rotation
    print("--- 6. LogTail")
    let logPath = (await ready())!.logPath
    var f = Follower(path: logPath)
    f.step()
    check(f.lastFailure == nil && f.tail.lines.count > 5, "log: initial read", "\(f.tail.lines.count) \(String(describing: f.lastFailure))")
    let levels = Set(f.tail.lines.map(\.level))
    check(levels.contains(.info) && levels.contains(.debug), "log: levels info+debug parsed (daemon -v)", "\(levels)")
    check(f.tail.lines.contains { $0.level == .warn || $0.level == .error }, "log: has warn/error lines (broken-config reload)")
    check(f.tail.filtered(level: .warn, query: "").allSatisfy { $0.level >= .warn && $0.level != .unknown }, "log: filter level warn+")
    check(!f.tail.filtered(level: nil, query: "RELOAD").isEmpty || !f.tail.filtered(level: nil, query: "config").isEmpty, "log: substring filter case-insensitive")
    let before = f.tail.lines.count
    let beforeOffset = f.tail.offset
    _ = try? await client.reload()
    try? await Task.sleep(nanoseconds: 500_000_000)
    f.step()
    check(f.tail.lines.count > before && f.tail.offset > beforeOffset, "log: follow picks up new lines after reload", "\(before) -> \(f.tail.lines.count)")
    var st = stat(); stat(logPath, &st)
    check(UInt64(st.st_size) == f.tail.offset, "log: offset == file size", "\(st.st_size) vs \(f.tail.offset)")

    // synthetic file: partial line, rotation by move, truncation
    let fake = "/tmp/smoke-fake.log"
    sh("rm -f \(fake) \(fake).1; printf 'time=1 level=INFO msg=a\\ntime=2 level=WARN msg=partial' > \(fake)")
    var g = Follower(path: fake)
    g.step()
    check(g.tail.lines.count == 1 && g.tail.lines[0].level == .info, "fake: partial last line is held back", "\(g.tail.lines)")
    sh("printf ' rest\\ntime=3 level=ERROR msg=c\\n' >> \(fake)")
    g.step()
    check(g.tail.lines.count == 3 && g.tail.lines[1].text.hasSuffix("partial rest") && g.tail.lines[2].level == .error, "fake: partial completed + new line", "\(g.tail.lines.map(\.text))")
    sh("mv \(fake) \(fake).1; printf 'time=9 level=DEBUG msg=new\\n' > \(fake)")
    g.step()
    check(g.tail.lines.count == 1 && g.tail.lines[0].level == .debug, "fake: rotation by move (new inode) -> reset and reread", "\(g.tail.lines.map(\.text))")
    sh(": > \(fake); printf 'x level=INFO y\\n' >> \(fake)")
    g.step()
    check(g.tail.lines.count == 1 && g.tail.lines[0].text == "x level=INFO y", "fake: truncation (same inode, smaller) -> reset", "\(g.tail.lines.map(\.text))")
    sh("rm -f \(fake)")
    g.step()
    check(isNotFound(g.lastFailure), "fake: removed file -> notFound")
    sh("printf 'z level=INFO\\n' > \(fake)")
    g.step()
    check(g.lastFailure == nil && g.tail.lines.map(\.text) == ["z level=INFO"], "fake: file reappears -> recovers", "\(g.tail.lines.map(\.text)) \(String(describing: g.lastFailure))")
    sh("rm -f \(fake) \(fake).1")

    // ---- config dir access
    let acc = ConfigDirAccess.describe(path: cfgDir, canRead: access(cfgDir, R_OK) == 0)
    check(acc == .open(cfgDir), "admin: config dir readable -> open", "\(acc)")

    // ---- leave the VM in a sane state
    for n in ["alpha", "beta"] { _ = try? await client.enable(n) }
    try? await client.disable("gamma")
    print("--- done")
}

// Real rotation of the engine log: pad the log to > 5 MB while the daemon is stopped, start it
// and let the follower (LogsView logic) cross the rotation.
// ---- A4: NotificationPlanner / UpdateCheck on live daemon status (design 7, design 2) ----
// Feeds consecutive real `status.get` states into plan(prev:next:now:). `skew` shifts the planner clock
// so the 5-minute anti-flap window can be crossed without waiting.
nonisolated(unsafe) var skew: TimeInterval = 0

struct Watcher {
    var planner = NotificationPlanner()
    var prev: EngineState?

    /// Polls every second until `done` holds for the state (or `secs` pass), then `settle` more polls.
    mutating func run(_ secs: Double, settle: Int = 4, until done: (EngineState) -> Bool = { _ in false }) async -> [AppNotification] {
        var out: [AppNotification] = []
        let end = Date().addingTimeInterval(secs)
        var left = -1
        while Date() < end {
            let next = await locate()
            out += planner.plan(prev: prev, next: next, now: Date().addingTimeInterval(skew))
            prev = next
            if left < 0, done(next) { left = settle }
            if left == 0 { break }
            if left > 0 { left -= 1 }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return out
    }
}

func describe(_ n: [AppNotification]) -> String {
    n.map { "[\($0.title) | \($0.body) | \($0.target)]" }.joined(separator: " ")
}

func betaState(_ s: EngineState) -> TunnelState? {
    if case .ready(let st) = s { return tunnel(st, "beta")?.state }
    return nil
}

func cli(_ args: String) -> String { sh("\(bin) \(args)").1 }

func runNotify() async {
    let orig = (try? String(contentsOfFile: cfgYAML, encoding: .utf8)) ?? ""
    precondition(orig.contains("check: 10.77.1.1"), "unexpected config")
    print("--- N1. запуск: первый опрос только запоминает")
    await stopDaemon()
    await startDaemon()
    var w = Watcher()
    var n = await w.run(3, settle: 0)
    check(n.isEmpty, "first poll after start: no notification", describe(n))

    print("--- N2. туннель умер (check fails x3) -> правило на резерве")
    n = await w.run(150, until: { betaState($0) == .dead })
    check(n.count == 1 && n[0].title == "beta не отвечает" && n[0].body == "svc-a → alpha" && n[0].target == .tunnel("beta"),
        "beta dead: 'beta не отвечает' / 'svc-a → alpha'", describe(n))

    print("--- N3. пауза / возобновление / переключения молчат")
    _ = cli("pause")
    n = await w.run(8, settle: 6, until: { if case .ready(let s) = $0 { return s.paused }; return false })
    check(n.isEmpty, "pause: silent", describe(n))
    _ = cli("resume")
    n = await w.run(60, settle: 5, until: { betaState($0) == .dead })
    // beta dies again, but within the 5 min anti-flap window of N2.
    check(n.isEmpty, "resume + beta dead again within 5 min: silent (anti-flap)", describe(n))
    _ = cli("down beta")
    n = await w.run(8, settle: 4)
    check(n.isEmpty, "down beta (intentional): silent", describe(n))
    _ = cli("up beta")
    n = await w.run(8, settle: 4)
    check(n.isEmpty, "up beta: silent", describe(n))
    _ = cli("up gamma")
    n = await w.run(8, settle: 4)
    check(n.isEmpty, "up gamma (switch): silent", describe(n))
    _ = cli("down gamma")
    n = await w.run(6, settle: 3)
    check(n.isEmpty, "down gamma: silent", describe(n))

    print("--- N4. после окна анти-мигания — снова уведомляет")
    n = await w.run(90, settle: 2, until: { betaState($0) == .dead })
    skew += 600
    n = await w.run(4, settle: 0)  // flush
    _ = cli("down beta")
    _ = await w.run(6, settle: 2)
    _ = cli("up beta")
    n = await w.run(150, until: { betaState($0) == .dead })
    check(n.count == 1 && n[0].title == "beta не отвечает", "beta dead after +10 min: notified again", describe(n))

    print("--- N5. восстановление (check убран из конфига + reload)")
    skew += 600
    writeConfig(orig.replacingOccurrences(of: "    check: 10.77.1.1\n", with: ""))
    _ = cli("reload")
    n = await w.run(40, until: { betaState($0) == .up })
    check(n.count == 1 && n[0].title == "beta снова работает" && n[0].body == "svc-a через beta" && n[0].target == .tunnel("beta"),
        "recovery: 'beta снова работает' / 'svc-a через beta'", describe(n))

    print("--- N6. ошибка конфига при reload")
    let bad1 = orig + "bogus_key: 1\n"
    writeConfig(bad1)
    var r = sh("\(bin) reload")
    info("reload: \(r.1.trimmingCharacters(in: .whitespacesAndNewlines))")
    n = await w.run(15, settle: 3, until: { if case .ready(let s) = $0 { return s.configErrorCount > 0 }; return false })
    check(n.count == 1 && n[0].title == "Изменения конфига не применены: 1 ошибка" && n[0].body == "Работает прежний конфиг" && n[0].target == .config,
        "config error on reload", describe(n))
    n = await w.run(5, settle: 3)
    check(n.isEmpty, "same error stays: no repeat", describe(n))
    writeConfig(orig + "other_bogus: 2\n")
    _ = cli("reload")
    n = await w.run(15, settle: 3, until: { if case .ready(let s) = $0 { return s.configErrors.joined().contains("other_bogus") }; return false })
    check(n.count == 1 && n[0].target == .config, "repeated failed reload with another text: notified", describe(n))
    w.planner.noteOwnReload()
    writeConfig(orig + "third_bogus: 3\n")
    _ = cli("reload")
    n = await w.run(15, settle: 3, until: { if case .ready(let s) = $0 { return s.configErrors.joined().contains("third_bogus") }; return false })
    check(n.isEmpty, "own reload (noteOwnReload): config error silent", describe(n))
    writeConfig(orig)
    _ = cli("reload")
    n = await w.run(40, settle: 3, until: { if case .ready(let s) = $0 { return s.configErrorCount == 0 }; return false })
    check(n.allSatisfy { $0.target != .config }, "good reload: no config notification", describe(n))

    print("--- N7. демон пропал / вернулся")
    skew += 600
    await stopDaemon()
    n = await w.run(15, settle: 2, until: { $0 == .notRunning })
    check(n.count == 1 && n[0].title == "wgplex не работает" && n[0].target == .daemon, "daemon gone", describe(n))
    await startDaemon()
    n = await w.run(60, settle: 2, until: { if case .ready = $0 { return true }; return false })
    check(n.count == 1 && n[0].title == "wgplex снова работает" && n[0].target == .daemon, "daemon back", describe(n))

    print("--- N8. демон стартует с битым конфигом")
    await stopDaemon()
    _ = await w.run(10, settle: 1, until: { $0 == .notRunning })
    writeConfig(orig + "bogus_key: 1\n")
    await startDaemon()
    n = await w.run(60, settle: 2, until: { if case .ready = $0 { return true }; return false })
    info("start with broken config: \(describe(n))")
    check(n.count == 1 && n[0].title.contains("запущен без туннелей") || (n.count == 1 && n[0].title == "wgplex снова работает" && n[0].body.contains("запущен без туннелей")),
        "start with errors: one merged notification mentioning 'запущен без туннелей'", describe(n))
    writeConfig(orig)
    _ = cli("reload")
    _ = await w.run(40, settle: 2, until: { if case .ready(let s) = $0 { return s.configured && s.configErrorCount == 0 }; return false })

    print("--- N9. UpdateCheck")
    let body = Data(#"{"tag_name":"v9.9.9","html_url":"https://github.com/mrFokin/wgplex-app/releases/tag/v9.9.9"}"#.utf8)
    check(UpdateCheck.parse(body) == UpdateInfo(version: "9.9.9", url: "https://github.com/mrFokin/wgplex-app/releases/tag/v9.9.9"), "parse tag_name/html_url")
    check(UpdateCheck.isNewer("9.9.9") && !UpdateCheck.isNewer("0.1.0-dev") && UpdateCheck.isNewer("0.1.0"), "isNewer vs appVersion \(appVersion)")
    var uc = UpdateCheck()
    let live = await uc.check(now: Date()) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/mrFokin/wgplex-app/releases/latest")!)
        req.timeoutInterval = 15
        let (d, resp) = try await URLSession.shared.data(for: req)
        guard let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { throw URLError(.badServerResponse) }
        return d
    }
    info("live GitHub check result: \(live)")
    check(live == .failed || { if case .available = live { return true }; return live == .upToDate }(), "live GitHub fetch: no crash (.failed expected while repo has no releases)")
    check(await uc.check(now: Date(), fetch: { body }) == .notDue, "second check same day: notDue")
}

func runRotate() async {
    print("--- real log rotation")
    guard let s = await ready() else { check(false, "rotate: ready"); return }
    var f = Follower(path: s.logPath)
    f.step()
    let ino0 = f.inode
    check(f.lastFailure == nil && f.tail.lines.count > 0, "rotate: initial read", "\(f.tail.lines.count)")
    await stopDaemon()
    sh("sudo sh -c 'yes \"time=2026-01-01T00:00:00.000Z level=INFO msg=padpadpadpadpadpadpadpadpad\" | head -c 5300000 >> \(s.logPath)'")
    f.step()
    check(f.lastFailure == nil && f.tail.lines.contains { $0.text.contains("msg=padpad") }, "rotate: follower reads padded lines")
    await startDaemon()
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    let (_, ls) = sh("ls -l \(s.logPath)*")
    info("log files:\n\(ls)")
    var st = stat(); stat(s.logPath, &st)
    let rotated = FileManager.default.fileExists(atPath: s.logPath + ".1")
    check(rotated, "rotate: engine rotated log to wgplex.log.1 (>5 MB)")
    check(UInt64(st.st_ino) != (ino0 ?? 0), "rotate: new inode for wgplex.log", "\(st.st_ino) vs \(String(describing: ino0))")
    f.step()
    check(f.lastFailure == nil && !f.tail.lines.contains { $0.text.contains("msg=padpad") } && f.tail.lines.count > 0,
        "rotate: follower reset and reads the new file only", "\(f.tail.lines.count) lines, pad: \(f.tail.lines.filter { $0.text.contains("padpad") }.count)")
    check(f.tail.lines.contains { $0.text.contains("rpc listening") }, "rotate: new file has 'rpc listening'")
    var st2 = stat(); stat(s.logPath, &st2)
    check(UInt64(st2.st_size) == f.tail.offset, "rotate: offset == new file size")
    sh("sudo rm -f \(s.logPath).1 \(s.logPath).2")
    let enabled = (await ready())?.tunnels.filter(\.enabled).count
    info("tunnels enabled after daemon restart: \(String(describing: enabled))")
}

let mode = CommandLine.arguments.dropFirst().first ?? "admin"
switch mode {
case "guest": await runGuest(phase: CommandLine.arguments.dropFirst(2).first ?? "")
case "member": await runMember()
case "rotate": await runRotate()
case "notify": await runNotify()
default: await runAdmin()
}
print("SUMMARY pass=\(passes) fail=\(fails)")
exit(fails == 0 ? 0 : 1)
