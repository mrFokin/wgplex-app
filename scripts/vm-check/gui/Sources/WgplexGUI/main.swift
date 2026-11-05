import AppKit
import Foundation
import WgplexKit

// In-process driver of the real app code. Output: PASS/FAIL/INFO lines on stdout,
// PNGs of the window content in the directory given as argv[1].
// argv[2] = "admin" (default) | "guest".

let outDir = CommandLine.arguments.dropFirst().first ?? "/tmp/shots"
let who = CommandLine.arguments.dropFirst(2).first ?? "admin"
nonisolated(unsafe) var passes = 0
nonisolated(unsafe) var fails = 0

func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok { passes += 1; print("PASS \(name)") } else { fails += 1; print("FAIL \(name) :: \(detail())") }
    fflush(stdout)
}
func info(_ s: String) { print("INFO \(s)"); fflush(stdout) }

func sh(_ cmd: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", cmd]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try? p.run()
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: d, as: UTF8.self)
}

/// "type=" of this process in lsappinfo: Foreground = Dock icon, UIElement = none.
func appType() -> String {
    let out = sh("lsappinfo list")
    let pid = getpid()
    var found = false
    for line in out.split(separator: "\n") {
        if line.contains("pid = \(pid) ") {
            found = true
            if let r = line.range(of: "type=\"") {
                return String(line[r.upperBound...].prefix { $0 != "\"" })
            }
        }
    }
    return found ? "?" : "not-found"
}

func field<T>(_ obj: Any, _ name: String, as: T.Type = T.self) -> T? {
    for c in Mirror(reflecting: obj).children where (c.label ?? "").contains(name) {
        if let v = c.value as? T { return v }
    }
    return nil
}

func dumpMenu(_ menu: NSMenu) -> [String] {
    menu.items.map { i in
        i.isSeparatorItem ? "---" : "\(i.state == .on ? "[x]" : "[ ]") \(i.title)\(i.isEnabled ? "" : "  (disabled)")"
    }
}

@MainActor func snap(_ w: NSWindow, _ name: String) {
    guard let v = w.contentView else { check(false, "snapshot \(name): contentView"); return }
    v.layoutSubtreeIfNeeded()
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { check(false, "snapshot \(name): rep"); return }
    v.cacheDisplay(in: v.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { check(false, "snapshot \(name): png"); return }
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let path = "\(outDir)/\(who)-\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    // A blank render would be a single flat colour: count distinct sampled pixels.
    var colours = Set<UInt32>()
    for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
        for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                colours.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
            }
        }
    }
    check(colours.count > 8, "snapshot \(name): \(rep.pixelsWide)x\(rep.pixelsHigh), \(colours.count) colours (not blank)")
}

@MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { allViews($0) } }

@MainActor func button(_ w: NSWindow, _ title: String) -> NSButton? {
    allViews(w.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title }
}

/// Synthesised mouse click delivered straight to the window (in-process: needs no TCC permission).
@MainActor func clickAt(_ w: NSWindow, x: CGFloat, yFromTop: CGFloat) {
    guard let cv = w.contentView else { return }
    let p = cv.convert(NSPoint(x: x, y: cv.bounds.height - yFromTop), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            w.sendEvent(e)
        }
    }
}

@MainActor func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

@MainActor func scenario(delegate: AppDelegate) async {
    if who == "admin" {
        // menu-bar icons of every state, on white, x8
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let all: [(String, MenuIcon)] = [("off", .off), ("on", .on), ("warn", .warn), ("paused", .paused), ("unavailable", .unavailable)]
        let sheet = NSImage(size: NSSize(width: 18 * 8 * 5 + 60, height: 18 * 8 + 20), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            for (i, (_, icon)) in all.enumerated() {
                let img = Icons.image(for: icon)
                NSColor.black.set()
                img.draw(in: NSRect(x: 10 + CGFloat(i) * (18 * 8 + 10), y: 10, width: 18 * 8, height: 18 * 8))
            }
            return true
        }
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "\(outDir)/icons-off-on-warn-paused-unavailable.png"))
        }
        info("icon sizes: \(all.map { "\($0.0)=\(Icons.image(for: $0.1).size) template=\(Icons.image(for: $0.1).isTemplate)" })")
    }
    await pause(2.5)
    guard let controller: StatusController = field(delegate, "controller") else { check(false, "AppDelegate has a StatusController"); exit(2) }
    check(true, "StatusController created by AppDelegate")
    guard let menu: NSMenu = field(controller, "menu"), let item: NSStatusItem = field(controller, "item") else { check(false, "menu/item"); exit(2) }
    info("policy at start: \(NSApp.activationPolicy().rawValue) (1 = accessory), lsappinfo type=\(appType())")
    check(NSApp.activationPolicy() == .accessory && appType() == "UIElement", "start: accessory, no Dock icon", appType())
    check(item.isVisible && item.button?.image != nil, "status item exists, visible, has an icon", "visible=\(item.isVisible)")
    info("status item button window frame: \(String(describing: item.button?.window?.frame))")
    let m0 = dumpMenu(menu)
    info("menu:\n  " + m0.joined(separator: "\n  "))
    check(m0.contains { $0.hasSuffix("Открыть Wgplex…") } && m0.contains { $0.hasSuffix("Выход") }, "menu has 'Открыть Wgplex…' and 'Выход'")
    if who == "admin" {
        check(m0.contains { $0.contains("alpha") } && m0.contains { $0.contains("gamma") } && m0.contains { $0.contains("Приостановить") },
            "menu (admin): tunnels + pause")
        check(!m0.contains { $0.contains("(disabled)") && ($0.contains("alpha") || $0.contains("Приостановить")) }, "menu (admin): toggles enabled")
    } else {
        check(m0.contains { $0.contains("alpha") && $0.contains("(disabled)") } && m0.contains { $0.contains("Приостановить") && $0.contains("(disabled)") },
            "menu (guest): toggles and pause disabled")
    }

    // ---- open the window from the menu (real action of the item)
    func click(_ title: String) -> Bool {
        guard let idx = menu.items.firstIndex(where: { $0.title.hasSuffix(title) || $0.title.hasPrefix(title) }) else { return false }
        menu.performActionForItem(at: idx)
        return true
    }
    let problemRow = menu.items.first { $0.title.hasPrefix("⚠ ") }?.title
    info("problem row at start: \(problemRow ?? "none")")

    check(click("Открыть Wgplex…"), "click 'Открыть Wgplex…'")
    await pause(2.5)
    guard let wc: WindowController = field(controller, "window") else { check(false, "WindowController created"); exit(2) }
    let wstate = wc.state
    guard let window: NSWindow = field(wc, "window") else { check(false, "NSWindow created"); exit(2) }
    check(window.isVisible && window.title == "Wgplex", "window visible, title Wgplex")
    check(NSApp.activationPolicy() == .regular, "policy regular while window is open")
    let t = appType()
    check(t == "Foreground", "lsappinfo type Foreground (Dock icon) while the window is open", t)
    check(wstate.section == .tunnels, "window opens on 'Туннели'")
    await pause(1.5)
    snap(window, "01-tunnels")
    // SwiftUI buttons are not NSButtons here: the action bar is checked through the model
    // the buttons bind to (and visually on the PNGs); presses call the same WindowState methods.
    let bar = wstate.model?.actions
    check(bar?.pauseEnabled == (who == "admin") && bar?.disableAllEnabled == (who == "admin") && bar?.reloadEnabled == (who == "admin"),
        "action bar model: buttons \(who == "admin" ? "enabled" : "disabled")")
    let access = ConfigDirAccess.describe(path: wstate.status?.configDir ?? "", canRead: FileManager.default.isReadableFile(atPath: wstate.status?.configDir ?? ""))
    check(who == "admin" ? access == .open(wstate.status?.configDir ?? "") : access.note == "Конфиг правит администратор", "config dir: \(access)")

    // ---- tunnel detail
    wstate.selectedTunnel = "alpha"
    await pause(1.5)
    snap(window, "02-tunnel-alpha")
    wstate.selectedTunnel = "beta"
    await pause(1)
    snap(window, "03-tunnel-beta")
    if who == "admin" {
        let d = wstate.model?.tunnels.first { $0.row.name == "beta" }
        check(d?.endpoint == "192.0.2.11:51820", "detail beta: endpoint shown (admin)", "\(String(describing: d?.endpoint))")
    } else {
        let d = wstate.model?.tunnels.first { $0.row.name == "beta" }
        check(d?.endpoint == nil && d?.reason == nil, "detail beta: endpoint/reason hidden (guest)")
    }

    // ---- sections
    wstate.section = .rules
    await pause(2)
    wstate.selectedRule = 0
    await pause(1)
    snap(window, "04-rules")
    wstate.section = .diagnostics
    await pause(1.5)
    // type into the real text field, press the real buttons
    if let tf = allViews(window.contentView!).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }) {
        window.makeFirstResponder(tf)
        tf.currentEditor()?.insertText("a.test.example")
        await pause(0.5)
        button(window, "Объяснить")?.performClick(nil)
        await pause(2)
        button(window, "Обновить")?.performClick(nil)
        await pause(2)
        check(true, "diagnostics: typed query and pressed 'Объяснить'/'Обновить'")
    } else { check(false, "diagnostics: text field found") }
    snap(window, "05-diagnostics")
    wstate.section = .logs
    await pause(2.5)
    snap(window, "06-logs")
    wstate.section = .tunnels
    await pause(1)

    if who == "admin" {
        // ---- the problem row of the menu leads to the rule
        if let problemRow {
            wstate.section = .logs
            await pause(0.5)
            check(click(problemRow), "click menu problem row")
            await pause(1.5)
            check(wstate.section == .rules && wstate.selectedRule == 0, "problem row -> 'Правила', rule 0 selected", "\(wstate.section) \(String(describing: wstate.selectedRule))")
            snap(window, "07-from-problem-row")
            wstate.section = .tunnels
            await pause(0.5)
        }

        // ---- real buttons: reload, pause/resume
        wstate.reload()
        await pause(2)
        check(wstate.message == WindowState.Message(text: "Применено", isError: false), "reload button: message 'Применено'", "\(String(describing: wstate.message))")
        snap(window, "08-reload-ok")
        wstate.togglePause()
        await pause(3)
        check(wstate.model?.banner?.kind == .paused && wstate.model?.actions.pauseTitle == "Возобновить", "pause: banner paused + button title 'Возобновить'")
        check(dumpMenu(menu).contains { $0.contains("Возобновить") }, "paused: menu shows 'Возобновить'")
        snap(window, "09-paused")
        wstate.togglePause()
        await pause(3)
        check(wstate.model?.banner?.kind != .paused && wstate.model?.actions.pauseTitle == "Приостановить", "resume: banner gone, title back")

        // ---- toggle through the real switch (third switch = gamma)
        let switches = allViews(window.contentView!).compactMap { $0 as? NSControl }.filter { String(describing: type(of: $0)).contains("Switch") }
        info("switches found: \(switches.count) (\(Set(switches.map { String(describing: type(of: $0)) })))")
        if switches.count >= 3 {
            switches[2].performClick(nil)
            await pause(4)
            let g = wstate.status?.tunnels.first { $0.name == "gamma" }
            check(g?.enabled == true && (g?.state == .up || g?.state == .starting), "switch gamma on: enabled, up/starting", "\(String(describing: g?.state))")
            snap(window, "10-gamma-on")
            let sw2 = allViews(window.contentView!).compactMap { $0 as? NSControl }.filter { String(describing: type(of: $0)).contains("Switch") }
            sw2[2].performClick(nil)
            await pause(3)
            check(wstate.status?.tunnels.first { $0.name == "gamma" }?.enabled == false, "switch gamma off")
        } else { check(false, "switches found in window") }

        // ---- config error through the real reload button
        let cfg = "/opt/homebrew/etc/wgplex/wgplex.yaml"
        let orig = (try? String(contentsOfFile: cfg, encoding: .utf8)) ?? ""
        try? (orig + "\nbogus_key: 1\n").write(toFile: cfg, atomically: false, encoding: .utf8)
        wstate.reload()
        await pause(3)
        snap(window, "11-config-error")
        check(wstate.model?.banner?.kind == .configError, "config error: window banner configError")
        check(wstate.message?.isError == true && (wstate.message?.text.hasPrefix("Конфиг не применён") ?? false), "config error: message 'Конфиг не применён…'", "\(String(describing: wstate.message))")
        check(!(wstate.status?.configErrors.isEmpty ?? true), "config error: errors listed in Туннели")
        check(dumpMenu(menu).contains { $0.contains("⚠ ошибка конфига") }, "config error: menu problem row 'ошибка конфига'")
        // banner click leads to config (tunnels section)
        wstate.section = .rules
        wstate.navigate(to: wstate.model!.banner!.target)
        check(wstate.section == .tunnels, "banner target .config -> 'Туннели'")
        try? orig.write(toFile: cfg, atomically: false, encoding: .utf8)
        wstate.reload()
        await pause(3)
        snap(window, "12-config-restored")
        check(wstate.model?.banner?.kind != .configError, "config restored: banner gone")

        // ---- 'Выключить все' through the real button; then restore alpha/beta
        wstate.disableAll()
        await pause(3)
        check(wstate.status?.tunnels.allSatisfy { !$0.enabled } == true, "'Выключить все' button: all toggles off")
        snap(window, "13-all-off")
        wstate.toggle("alpha", on: true)
        await pause(2)
        wstate.toggle("beta", on: true)
        await pause(2)
    }

    if who == "admin" {
        // ---- daemon goes away while the window is open, then comes back
        _ = sh("sudo pkill -TERM -x wgplex")
        await pause(14)  // poll interval is 1.5 s with the window open
        check(wstate.model?.banner?.kind == .daemonUnavailable && wstate.model?.banner?.text == "Демон не запущен", "daemon stopped: window banner 'Демон не запущен'", "\(String(describing: wstate.model?.banner))")
        check(dumpMenu(menu).first == "[ ] Демон не запущен  (disabled)" || dumpMenu(menu).contains { $0.contains("Демон не запущен") }, "daemon stopped: menu 'Демон не запущен'", "\(dumpMenu(menu))")
        check(dumpMenu(menu).contains { $0.contains("Копировать команду запуска") }, "daemon stopped: menu 'Копировать команду запуска'")
        snap(window, "15-daemon-stopped")
        wstate.section = .logs
        await pause(2)
        snap(window, "16-daemon-stopped-logs")
        wstate.section = .tunnels
        _ = sh("sudo sh -c 'nohup /opt/homebrew/opt/wgplex/bin/wgplex daemon -v >/dev/null 2>&1 </dev/null &'")
        await pause(14)
        check(wstate.status != nil && wstate.model?.banner?.kind != .daemonUnavailable, "daemon back: window recovers without restart of the app", "\(String(describing: wstate.model?.banner))")
        snap(window, "17-daemon-back")
    }

    // ---- close: Dock icon disappears
    window.close()
    await pause(2)
    check(NSApp.activationPolicy() == .accessory, "policy accessory after window close")
    let t2 = appType()
    check(t2 == "UIElement", "lsappinfo type UIElement (Dock icon gone) after close", t2)
    check(click("Открыть Wgplex…"), "reopen from menu")
    await pause(2)
    check(window.isVisible && appType() == "Foreground", "reopened: window visible, Dock icon back")
    snap(window, "14-reopened")
    window.close()
    await pause(1)
    print("SUMMARY pass=\(passes) fail=\(fails)")
    fflush(stdout)
    exit(fails == 0 ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
Task { @MainActor in await scenario(delegate: delegate) }
app.run()
