import AppKit
import Carbon
import Darwin
import Foundation

// Carbon hotkeys need no new Accessibility permission. Register only while OmniWM runs.
// Horizontal keys retain one repeat owner across tmux/app boundaries; J/K pass through.
let omniBundleID = "com.barut.OmniWM"
let terminalBundleIDs: Set<String> = ["com.github.wez.wezterm"]
let signature: OSType = 0x4f574d48
let cli = "/opt/homebrew/bin/omniwmctl"

enum Shortcut: UInt32, CaseIterable {
    case left = 1, down, up, right, narrower, taller, shorter, wider
    case moveLeft, moveRight
    case joinLeft, joinRight

    var keyCode: UInt32 {
        switch self {
        case .left, .narrower, .moveLeft, .joinLeft: return UInt32(kVK_ANSI_H)
        case .down, .taller: return UInt32(kVK_ANSI_J)
        case .up, .shorter: return UInt32(kVK_ANSI_K)
        case .right, .wider, .moveRight, .joinRight: return UInt32(kVK_ANSI_L)
        }
    }

    var isFocus: Bool { rawValue <= Shortcut.right.rawValue }
    var isHorizontalFocus: Bool { self == .left || self == .right }
    var isWindowMove: Bool { self == .moveLeft || self == .moveRight }
    var isJoin: Bool { self == .joinLeft || self == .joinRight }
    var repeats: Bool { !isJoin }
    var isResize: Bool { !isFocus && !isWindowMove && !isJoin }
    var modifiers: UInt32 {
        if isJoin { return UInt32(optionKey | cmdKey | shiftKey) }
        return UInt32(optionKey) | (isWindowMove ? UInt32(cmdKey) : isResize ? UInt32(shiftKey) : 0)
    }

    func shouldRegister(running: Bool, terminal: Bool) -> Bool {
        running && !(isFocus && terminal && !isHorizontalFocus)
    }

    func arguments(layout: String) -> [String]? {
        switch self {
        case .left: return ["command", "focus", "left"]
        case .down: return ["command", "focus", "down"]
        case .up: return ["command", "focus", "up"]
        case .right: return ["command", "focus", "right"]
        case .moveLeft: return ["command", "move", "left"]
        case .moveRight: return ["command", "move", "right"]
        case .joinLeft, .joinRight: return nil
        default: break
        }
        let grow = self == .wider || self == .taller
        let horizontal = self == .narrower || self == .wider
        switch layout {
        case "niri":
            return ["command", horizontal ? "set-container-primary-span" : "set-window-secondary-span",
                    grow ? "+10%" : "-10%"]
        case "dwindle":
            return ["command", "resize", horizontal ? "horizontal" : "vertical", grow ? "grow" : "shrink"]
        default: return nil
        }
    }
}

struct HoldSequence {
    private(set) var shortcut: Shortcut?
    private var nextRepeat = 0.0

    mutating func press(_ shortcut: Shortcut, at time: Double) -> Shortcut? {
        guard self.shortcut != shortcut else { return nil }
        self.shortcut = shortcut
        nextRepeat = time + 0.25
        return shortcut
    }

    mutating func release(_ shortcut: Shortcut) {
        if self.shortcut == shortcut { self.shortcut = nil }
    }

    mutating func cancel() {
        shortcut = nil
    }

    mutating func repeatIfDue(at time: Double, modifiersMatch: Bool) -> Shortcut? {
        guard modifiersMatch else { cancel(); return nil }
        guard let shortcut, time >= nextRepeat else { return nil }
        // Keep the original cadence; a late callback must not delay every later repeat.
        // Skip missed intervals instead of replaying a burst of stale commands.
        nextRepeat += (floor((time - nextRepeat) / 0.08) + 1) * 0.08
        return shortcut
    }
}

func runCLI(_ arguments: [String], executable: String = cli) -> Data? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    } catch {
        fputs("OmniWM shortcut command failed: \(error)\n", stderr)
        return nil
    }
}

func focusedWeztermPane(in data: Data, pid: pid_t) -> Int? {
    guard let clients = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let client = clients.first(where: { ($0["pid"] as? Int) == Int(pid) }),
          let pane = client["focused_pane_id"] as? Int, pane >= 0 else { return nil }
    return pane
}

func terminalNavigationArguments(_ shortcut: Shortcut, pane: Int) -> [String]? {
    guard shortcut.isHorizontalFocus else { return nil }
    return ["cli", "--no-auto-start", "send-text", "--no-paste", "--pane-id", String(pane),
            "--", "\u{1b}" + (shortcut == .left ? "h" : "l")]
}

struct WindowJoinPlan: Equatable {
    let workspace: String
    let direction: String
    let needsExtraction: Bool
    let rollbackUpMoves: Int
}

func windowJoinPlan(_ shortcut: Shortcut, windows: [[String: Any]]) -> WindowJoinPlan? {
    guard shortcut.isJoin,
          let source = windows.first(where: { $0["isFocused"] as? Bool == true }),
          source["mode"] as? String == "tiling",
          let sourceID = source["id"] as? String,
          let sourceColumn = source["columnIndex"] as? Int,
          let workspace = (source["workspace"] as? [String: Any])?["id"] as? String else { return nil }
    let candidates = windows.filter {
        ($0["workspace"] as? [String: Any])?["id"] as? String == workspace
            && $0["mode"] as? String == "tiling" && $0["columnIndex"] as? Int != nil
    }
    let columns = Set(candidates.compactMap { $0["columnIndex"] as? Int })
    let neighbour = shortcut == .joinLeft
        ? columns.filter { $0 < sourceColumn }.max()
        : columns.filter { $0 > sourceColumn }.min()
    guard neighbour != nil else { return nil }
    let members = candidates.filter { $0["columnIndex"] as? Int == sourceColumn }.sorted {
        let firstY = ($0["frame"] as? [String: Any])?["y"] as? Double ?? 0
        let secondY = ($1["frame"] as? [String: Any])?["y"] as? Double ?? 0
        return firstY == secondY ? ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") : firstY < secondY
    }
    guard let index = members.firstIndex(where: { $0["id"] as? String == sourceID }) else { return nil }
    return WindowJoinPlan(workspace: workspace,
                          direction: shortcut == .joinLeft ? "left" : "right",
                          needsExtraction: members.count > 1, rollbackUpMoves: members.count - 1 - index)
}

func nativeCommandExecuted(_ arguments: [String]) -> Bool {
    guard let data = runCLI(["command"] + arguments) else { return false }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "executed"
}

func joinWindow(_ shortcut: Shortcut) {
    guard let data = runCLI(["query", "windows", "--fields", "id,workspace,column-index,frame,mode,is-focused", "--format", "json"]),
          let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let result = response["result"] as? [String: Any],
          let payload = result["payload"] as? [String: Any],
          let windows = payload["windows"] as? [[String: Any]],
          let plan = windowJoinPlan(shortcut, windows: windows),
          let workspaceData = runCLI(["query", "workspaces", "--workspace", plan.workspace, "--fields", "layout", "--format", "json"]),
          let workspaceResponse = try? JSONSerialization.jsonObject(with: workspaceData) as? [String: Any],
          let workspaceResult = workspaceResponse["result"] as? [String: Any],
          let workspacePayload = workspaceResult["payload"] as? [String: Any],
          let workspaces = workspacePayload["workspaces"] as? [[String: Any]],
          workspaces.first?["layout"] as? String == "niri" else { return }
    // Native consumption preserves the destination's width, members and display mode.
    // Extract only the selected source first when it currently shares a column.
    if plan.needsExtraction, !nativeCommandExecuted(["move", plan.direction]) { return }
    if nativeCommandExecuted(["consume-or-expel-window-" + plan.direction]) { return }
    if plan.needsExtraction {
        let opposite = plan.direction == "left" ? "right" : "left"
        if nativeCommandExecuted(["consume-or-expel-window-" + opposite]) {
            for _ in 0..<plan.rollbackUpMoves { _ = nativeCommandExecuted(["move", "up"]) }
        } else {
            fputs("OmniWM window join was refused and the source could not be restored\n", stderr)
        }
    }
}

func execute(_ shortcut: Shortcut, terminalPID: pid_t? = nil) {
    if shortcut.isJoin { joinWindow(shortcut); return }
    if shortcut.isHorizontalFocus, let terminalPID {
        let wezterm = "/opt/homebrew/bin/wezterm"
        guard let clients = runCLI(["cli", "--no-auto-start", "list-clients", "--format", "json"], executable: wezterm),
              let pane = focusedWeztermPane(in: clients, pid: terminalPID),
              let arguments = terminalNavigationArguments(shortcut, pane: pane) else { return }
        _ = runCLI(arguments, executable: wezterm)
        return
    }
    if shortcut.isFocus || shortcut.isWindowMove {
        guard let args = shortcut.arguments(layout: "") else { return }
        _ = runCLI(args)
        return
    }
    guard let data = runCLI(["query", "workspaces", "--current", "--fields", "layout", "--format", "json"]),
          let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let result = response["result"] as? [String: Any],
          let payload = result["payload"] as? [String: Any],
          let workspaces = payload["workspaces"] as? [[String: Any]],
          let layout = workspaces.first?["layout"] as? String,
          let args = shortcut.arguments(layout: layout)
    else { return }
    _ = runCLI(args)
}

enum InputLanguage: String {
    case english, korean

    var rgb: [String: Double] {
        switch self {
        case .english: return ["red": 137 / 255.0, "green": 180 / 255.0, "blue": 250 / 255.0]
        case .korean: return ["red": 245 / 255.0, "green": 169 / 255.0, "blue": 127 / 255.0]
        }
    }

    static func detect(id: String, languages: [String]) -> InputLanguage? {
        let id = id.lowercased()
        if id.hasSuffix(".roman") { return .english }
        let language = languages.first?.lowercased().split(separator: "-").first
        if language == "ko" { return .korean }
        if language == "en" { return .english }
        if id.contains("korean") { return .korean }
        if ["com.apple.keylayout.abc", "com.apple.keylayout.us"].contains(id) { return .english }
        return nil
    }
}

struct KeyboardInputSource {
    let id: String
    let languages: [String]

    var language: InputLanguage? { InputLanguage.detect(id: id, languages: languages) }

    private static func describe(_ source: TISInputSource) -> KeyboardInputSource? {
        guard let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        let id = Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages).flatMap {
            Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String]
        } ?? []
        return KeyboardInputSource(id: id, languages: languages)
    }

    static func current() -> KeyboardInputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return describe(source)
    }
}

enum BorderColorUpdateError: Error {
    case missingColorSection, missingComponent(String), concurrentChange
}

func updatingBorderColors(in document: String, language: InputLanguage) throws -> String {
    let sections = try NSRegularExpression(pattern: "(?ms)^\\[borders\\.(color|darkColor)\\][ \\t]*\\r?\\n.*?(?=^\\[|\\z)")
    let matches = sections.matches(in: document, range: NSRange(document.startIndex..., in: document))
    guard matches.contains(where: { Range($0.range(at: 1), in: document).map { document[$0] == "color" } == true })
    else { throw BorderColorUpdateError.missingColorSection }
    var result = document
    for match in matches.reversed() {
        guard let range = Range(match.range, in: result) else { continue }
        var block = String(result[range])
        for (component, target) in language.rgb {
            let regex = try NSRegularExpression(pattern: "(?m)^" + component + "[ \\t]*=[ \\t]*([^\\r\\n#]+)")
            guard let found = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
                  let valueRange = Range(found.range(at: 1), in: block),
                  let current = Double(block[valueRange].trimmingCharacters(in: .whitespaces)), current.isFinite,
                  let numericRange = block.range(of: block[valueRange].trimmingCharacters(in: .whitespaces), range: valueRange)
            else { throw BorderColorUpdateError.missingComponent(component) }
            if abs(current - target) > 0.00000001 {
                block.replaceSubrange(numericRange, with: String(target))
            }
        }
        result.replaceSubrange(range, with: block)
    }
    return result
}

final class InputBorderController {
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?

    func start() {
        for name in [kTISNotifySelectedKeyboardInputSourceChanged, kTISNotifyEnabledKeyboardInputSourcesChanged].compactMap({ $0 }) {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name as String), object: nil, queue: .main
            ) { [weak self] _ in self?.scheduleRefresh() })
        }
        scheduleRefresh()
    }

    func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = work
        // TIS can still report the old input source inside its change notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: work)
    }

    private func refresh() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: omniBundleID).isEmpty,
              let source = KeyboardInputSource.current(), let language = source.language else { return }
        let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let root: URL
        if let configHome, configHome.hasPrefix("/") {
            root = URL(fileURLWithPath: configHome)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        let file = root.appendingPathComponent("omniwm/settings.toml").resolvingSymlinksInPath()
        do {
            for _ in 0..<3 {
                let data = try Data(contentsOf: file)
                let text = String(decoding: data, as: UTF8.self)
                let updated = try updatingBorderColors(in: text, language: language)
                guard updated != text else { return }
                let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
                guard try Data(contentsOf: file) == data else { continue }
                try Data(updated.utf8).write(to: file, options: .atomic)
                if let permissions { try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path) }
                print("Input border: \(language.rawValue) \(source.id)")
                fflush(stdout)
                return
            }
            throw BorderColorUpdateError.concurrentChange
        } catch {
            fputs("Could not update input-language border: \(error)\n", stderr)
        }
    }
}

func fullscreenDisplayIDs(in displays: [[String: Any]]) -> Set<String>? {
    guard !displays.isEmpty else { return nil }
    var result = Set<String>()
    for display in displays {
        guard let id = display["Display Identifier"] as? String, !id.isEmpty,
              let current = display["Current Space"] as? [String: Any],
              let type = current["type"] as? Int, type == 0 || type == 4 else { return nil }
        if type == 4 { result.insert(id) }
    }
    return result
}

struct FullscreenExitTracker {
    private var previous: Set<String>?

    mutating func observe(_ current: Set<String>?) -> Set<String> {
        guard let current else { return [] }
        let exited = previous?.subtracting(current) ?? []
        previous = current
        return exited
    }
}

final class FullscreenBarRefreshController {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private let library: UnsafeMutableRawPointer?
    private let connection: MainConnection?
    private let copySpaces: CopySpaces?
    private let queue = DispatchQueue(label: "com.giho.omniwm-fullscreen-bar")
    private var observer: NSObjectProtocol?
    private var tracker = FullscreenExitTracker()
    private var generation = 0
    private var pending: DispatchWorkItem?

    init() {
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        connection = library.flatMap { dlsym($0, "SLSMainConnectionID") }.map {
            unsafeBitCast($0, to: MainConnection.self)
        }
        copySpaces = library.flatMap { dlsym($0, "SLSCopyManagedDisplaySpaces") }.map {
            unsafeBitCast($0, to: CopySpaces.self)
        }
    }

    private func currentFullscreenDisplays() -> Set<String>? {
        guard let connection, let copySpaces,
              let displays = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return fullscreenDisplayIDs(in: displays)
    }

    func start() {
        guard connection != nil, copySpaces != nil else {
            fputs("Fullscreen bar refresh unavailable: native Space symbols missing\n", stderr)
            return
        }
        _ = tracker.observe(currentFullscreenDisplays())
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            generation += 1
            sample(generation: generation, remaining: 24)
        }
    }

    private func sample(generation: Int, remaining: Int) {
        guard self.generation == generation else { return }
        let exited = tracker.observe(currentFullscreenDisplays())
        if !exited.isEmpty {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let fullscreen = currentFullscreenDisplays(),
                      fullscreen.isDisjoint(with: exited),
                      !NSRunningApplication.runningApplications(withBundleIdentifier: omniBundleID).isEmpty else { return }
                queue.async {
                    guard let data = runCLI(["query", "workspace-bar", "--format", "json"]),
                          let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let result = response["result"] as? [String: Any],
                          let payload = result["payload"] as? [String: Any],
                          let monitors = payload["monitors"] as? [[String: Any]],
                          monitors.contains(where: { $0["enabled"] as? Bool == true }) else { return }
                    // Paired toggles invalidate/recreate the bar while preserving its manual
                    // visibility state. They issue no focus command and never rewrite settings.
                    guard runCLI(["command", "toggle-workspace-bar"]) != nil else { return }
                    _ = runCLI(["command", "toggle-workspace-bar"])
                    print("Fullscreen bar refresh: native fullscreen exited")
                    fflush(stdout)
                }
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
        // Space notifications may precede the end of the transition. Sample only this
        // short event window; there is no idle polling timer.
        if remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.sample(generation: generation, remaining: remaining - 1)
            }
        }
    }
}

final class ShortcutHelper {
    private var registrations: [Shortcut: EventHotKeyRef] = [:]
    private let commands = DispatchQueue(label: "com.giho.omniwm-shortcuts.commands", qos: .userInteractive)
    private var observers: [NSObjectProtocol] = []
    private var reported: Set<Shortcut> = []
    private var hold = HoldSequence()
    private var repeatTimer: DispatchSourceTimer?
    private var commandsInFlight = 0
    private let inputBorder = InputBorderController()
    private let fullscreenBar = FullscreenBarRefreshController()

    func start() {
        print("Shortcut helper: individual-window Alt+Cmd+H/L routing active")
        fflush(stdout)
        inputBorder.start()
        fullscreenBar.start()
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification,
                      NSWorkspace.didTerminateApplicationNotification,
                      NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        refresh()
    }

    func refresh() {
        inputBorder.scheduleRefresh()
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: omniBundleID).isEmpty
        let terminal = terminalBundleIDs.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
        for shortcut in Shortcut.allCases {
            let wanted = shortcut.shouldRegister(running: running, terminal: terminal)
            if !wanted, let registration = registrations.removeValue(forKey: shortcut) {
                released(shortcut)
                UnregisterEventHotKey(registration)
            } else if wanted, registrations[shortcut] == nil {
                var reference: EventHotKeyRef?
                let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                                EventHotKeyID(signature: signature, id: shortcut.rawValue),
                                                GetApplicationEventTarget(), 0, &reference)
                if status == noErr, let reference {
                    registrations[shortcut] = reference
                } else {
                    fputs("Could not register OmniWM shortcut \(shortcut): \(status)\n", stderr)
                }
            }
        }
        let active = Set(registrations.keys)
        if active != reported {
            print("Registered focus=\(active.filter(\.isFocus).count) resize=\(active.filter(\.isResize).count) windowMoves=\(active.filter(\.isWindowMove).count) joins=\(active.filter(\.isJoin).count) terminalPassthrough=\(terminal)")
            fflush(stdout)
            reported = active
        }
    }

    func pressed(_ shortcut: Shortcut) {
        guard registrations[shortcut] != nil,
              let initial = hold.press(shortcut, at: ProcessInfo.processInfo.systemUptime)
        else { return }
        submit(initial)
        repeatTimer?.cancel()
        repeatTimer = nil
        guard shortcut.repeats else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(80), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.repeatHeldKey()
        }
        repeatTimer = timer
        timer.resume()
    }

    func released(_ shortcut: Shortcut) {
        hold.release(shortcut)
        if hold.shortcut == nil {
            repeatTimer?.cancel()
            repeatTimer = nil
        }
    }

    private func repeatHeldKey() {
        guard let shortcut = hold.shortcut else { return }
        let mask = UInt32(optionKey | shiftKey | controlKey | cmdKey)
        let expected = shortcut.modifiers
        let matches = (GetCurrentKeyModifiers() & mask) == expected
        if let next = hold.repeatIfDue(at: ProcessInfo.processInfo.systemUptime, modifiersMatch: matches) {
            submit(next, isRepeat: true)
        }
        if hold.shortcut == nil {
            repeatTimer?.cancel()
            repeatTimer = nil
        }
    }

    private func submit(_ shortcut: Shortcut, isRepeat: Bool = false) {
        // Preserve discrete presses; hold-repeat ticks never queue behind a running command.
        guard !isRepeat || commandsInFlight == 0 else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let terminalPID = terminalBundleIDs.contains(frontmost?.bundleIdentifier ?? "") ? frontmost?.processIdentifier : nil
        commandsInFlight += 1
        commands.async {
            execute(shortcut, terminalPID: terminalPID)
            DispatchQueue.main.async { self.commandsInFlight -= 1 }
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    let regularDisplay: [String: Any] = ["Display Identifier": "display-a", "Current Space": ["type": 0]]
    let fullscreenDisplay: [String: Any] = ["Display Identifier": "display-a", "Current Space": ["type": 4]]
    assert(fullscreenDisplayIDs(in: [regularDisplay]) == [])
    assert(fullscreenDisplayIDs(in: [fullscreenDisplay]) == ["display-a"])
    assert(fullscreenDisplayIDs(in: []) == nil)
    assert(fullscreenDisplayIDs(in: [["Display Identifier": "display-a"]]) == nil)
    var exits = FullscreenExitTracker()
    assert(exits.observe(["display-a"]).isEmpty) // Startup in fullscreen must not redraw.
    assert(exits.observe(nil).isEmpty) // An incomplete transition is not an exit.
    assert(exits.observe(["display-a"]).isEmpty)
    assert(exits.observe([]) == ["display-a"])
    assert(exits.observe([]).isEmpty) // Exactly once per exit.
    assert(exits.observe(["display-a", "display-b"]).isEmpty)
    assert(exits.observe(["display-b"]) == ["display-a"])
    assert(exits.observe([]) == ["display-b"])
    // Validate behavior across both layouts and reject an unknown layout.
    assert(Shortcut.narrower.arguments(layout: "niri") == ["command", "set-container-primary-span", "-10%"])
    assert(Shortcut.wider.arguments(layout: "niri") == ["command", "set-container-primary-span", "+10%"])
    assert(Shortcut.narrower.arguments(layout: "dwindle") == ["command", "resize", "horizontal", "shrink"])
    assert(Shortcut.taller.arguments(layout: "niri") == ["command", "set-window-secondary-span", "+10%"])
    assert(Shortcut.shorter.arguments(layout: "dwindle") == ["command", "resize", "vertical", "shrink"])
    assert(Shortcut.wider.arguments(layout: "dwindle") == ["command", "resize", "horizontal", "grow"])
    assert(Shortcut.narrower.arguments(layout: "unknown") == nil)
    assert(Shortcut.moveLeft.arguments(layout: "niri") == ["command", "move", "left"])
    assert(Shortcut.moveRight.arguments(layout: "niri") == ["command", "move", "right"])
    assert(Shortcut.moveLeft.modifiers == UInt32(optionKey | cmdKey))
    assert(Shortcut.joinLeft.modifiers == UInt32(optionKey | cmdKey | shiftKey))
    assert(Shortcut.joinRight.shouldRegister(running: true, terminal: true))
    assert(!Shortcut.joinLeft.isResize && !Shortcut.joinLeft.repeats && Shortcut.moveLeft.repeats)
    func joinRow(_ id: String, _ column: Int, _ y: Double, focused: Bool = false, workspace: String = "ws") -> [String: Any] {
        ["id": id, "columnIndex": column, "frame": ["y": y], "isFocused": focused,
         "mode": "tiling", "workspace": ["id": workspace]]
    }
    let joinRows = [joinRow("source", 2, 0, focused: true), joinRow("source-sibling", 2, 400),
                    joinRow("left-bottom", 1, 400), joinRow("left-top", 1, 0), joinRow("right", 3, 0),
                    joinRow("other-workspace", 1, 0, workspace: "other")]
    assert(windowJoinPlan(.joinLeft, windows: joinRows) == WindowJoinPlan(
        workspace: "ws", direction: "left", needsExtraction: true, rollbackUpMoves: 1))
    assert(windowJoinPlan(.joinRight, windows: joinRows)?.direction == "right")
    assert(windowJoinPlan(.joinRight, windows: joinRows)?.needsExtraction == true)
    assert(windowJoinPlan(.joinLeft, windows: [joinRow("solo", 2, 0, focused: true), joinRow("target", 1, 0)])?.needsExtraction == false)
    assert(windowJoinPlan(.joinLeft, windows: [joinRow("edge", 1, 0, focused: true)]) == nil)
    assert(windowJoinPlan(.joinRight, windows: [joinRow("edge", 1, 0, focused: true)]) == nil)
    assert(windowJoinPlan(.moveLeft, windows: joinRows) == nil)
    assert(Shortcut.left.modifiers == UInt32(optionKey))
    assert(Shortcut.narrower.modifiers == UInt32(optionKey | shiftKey))
    assert(Shortcut.wider.modifiers == UInt32(optionKey | shiftKey))
    assert(Shortcut.narrower.keyCode == UInt32(kVK_ANSI_H))
    assert(Shortcut.wider.keyCode == UInt32(kVK_ANSI_L))
    for terminal in [false, true] {
        assert(Shortcut.left.shouldRegister(running: true, terminal: terminal))
        assert(Shortcut.right.shouldRegister(running: true, terminal: terminal))
        assert(!Shortcut.left.shouldRegister(running: false, terminal: terminal))
        assert(Shortcut.down.shouldRegister(running: true, terminal: terminal) == !terminal)
        assert(Shortcut.wider.shouldRegister(running: true, terminal: terminal))
        assert(Shortcut.moveLeft.shouldRegister(running: true, terminal: terminal))
        assert(!Shortcut.moveRight.shouldRegister(running: false, terminal: terminal))
    }
    let clients = Data("[{\"pid\":12,\"focused_pane_id\":7},{\"pid\":34,\"focused_pane_id\":8}]".utf8)
    assert(focusedWeztermPane(in: clients, pid: 34) == 8)
    assert(focusedWeztermPane(in: clients, pid: 56) == nil)
    assert(focusedWeztermPane(in: Data("invalid".utf8), pid: 34) == nil)
    assert(terminalNavigationArguments(.left, pane: 8)?.suffix(2) == ["--", "\u{1b}h"])
    assert(terminalNavigationArguments(.right, pane: 8)?.suffix(2) == ["--", "\u{1b}l"])
    assert(terminalNavigationArguments(.down, pane: 8) == nil)
    var sequence = HoldSequence()
    assert(sequence.press(.left, at: 0) == .left)
    assert(sequence.repeatIfDue(at: 0.1, modifiersMatch: true) == nil)
    assert(sequence.repeatIfDue(at: 0.25, modifiersMatch: true) == .left)
    assert(sequence.press(.left, at: 0.26) == nil) // Ignore native autorepeat duplicates.
    assert(sequence.repeatIfDue(at: 0.3, modifiersMatch: true) == nil)
    assert(sequence.repeatIfDue(at: 0.34, modifiersMatch: true) == .left)
    sequence.release(.left)
    assert(sequence.repeatIfDue(at: 1, modifiersMatch: true) == nil)
    assert(sequence.press(.right, at: 2) == .right)
    sequence.release(.left) // Releasing the old direction must not stop the new one.
    assert(sequence.repeatIfDue(at: 2.25, modifiersMatch: true) == .right)
    assert(sequence.repeatIfDue(at: 2.4, modifiersMatch: false) == nil)
    assert(sequence.repeatIfDue(at: 3, modifiersMatch: true) == nil)
    assert(sequence.press(.taller, at: 4) == .taller)
    assert(sequence.repeatIfDue(at: 4.25, modifiersMatch: true) == .taller)
    sequence.cancel()
    assert(sequence.repeatIfDue(at: 5, modifiersMatch: true) == nil)
    assert(sequence.press(.moveLeft, at: 6) == .moveLeft)
    assert(sequence.repeatIfDue(at: 6.1, modifiersMatch: true) == nil)
    assert(sequence.repeatIfDue(at: 6.25, modifiersMatch: true) == .moveLeft)
    assert(sequence.repeatIfDue(at: 6.34, modifiersMatch: true) == .moveLeft)
    sequence.release(.moveLeft)
    assert(sequence.repeatIfDue(at: 7, modifiersMatch: true) == nil)
    assert(sequence.press(.moveRight, at: 8) == .moveRight)
    assert(sequence.repeatIfDue(at: 8.25, modifiersMatch: false) == nil)
    // Late callbacks retain the original timeline, including after a long stall.
    var cadence = HoldSequence()
    assert(cadence.press(.left, at: 0) == .left)
    assert(cadence.repeatIfDue(at: 0.25, modifiersMatch: true) == .left)
    assert(cadence.repeatIfDue(at: 0.335, modifiersMatch: true) == .left)
    assert(cadence.repeatIfDue(at: 0.411, modifiersMatch: true) == .left)
    assert(cadence.repeatIfDue(at: 0.491, modifiersMatch: true) == .left)
    assert(cadence.repeatIfDue(at: 1.0, modifiersMatch: true) == .left)
    assert(cadence.repeatIfDue(at: 1.001, modifiersMatch: true) == nil)
    assert(cadence.repeatIfDue(at: 1.05, modifiersMatch: true) == .left)
    cadence.release(.left)
    assert(cadence.repeatIfDue(at: 1.13, modifiersMatch: true) == nil)
    assert(InputLanguage.detect(id: "com.apple.inputmethod.Korean.2SetKorean", languages: ["ko"]) == .korean)
    assert(InputLanguage.detect(id: "com.apple.keylayout.ABC", languages: ["en"]) == .english)
    assert(InputLanguage.detect(id: "com.apple.inputmethod.Korean.Roman", languages: ["ko"]) == .english)
    assert(InputLanguage.detect(id: "com.apple.inputmethod.Korean.3SetKorean", languages: []) == .korean)
    assert(InputLanguage.detect(id: "third-party-korean", languages: ["ko-KR"]) == .korean)
    assert(InputLanguage.detect(id: "unknown", languages: ["ja"]) == nil)
    let document = """
    # 한영 색상 🎨
    [borders]
    width = 5.0
    [borders.color]
    red = 0.5372549019607843 # keep comment
    green = 0.7058823529411765
    blue = 0.9803921568627451
    alpha = 0.9
    [borders.darkColor]
    red = 0.5372549019607843
    green = 0.7058823529411765
    blue = 0.9803921568627451
    alpha = 1.0
    [other]
    red = 0.123
    shortcut = "Option+Space"
    """
    do {
        let unchangedEnglish = try updatingBorderColors(in: document, language: .english)
        assert(unchangedEnglish == document)
        let orange = try updatingBorderColors(in: document, language: .korean)
        assert(orange.contains("red = 0.9607843137254902 # keep comment"))
        assert(orange.components(separatedBy: "blue = 0.4980392156862745").count == 3)
        assert(orange.contains("width = 5.0") && orange.contains("alpha = 0.9"))
        assert(orange.contains("red = 0.123") && orange.contains("shortcut = \"Option+Space\""))
        let unchangedKorean = try updatingBorderColors(in: orange, language: .korean)
        assert(unchangedKorean == orange)
        let restoredEnglish = try updatingBorderColors(in: orange, language: .english)
        assert(restoredEnglish == document)
        do {
            _ = try updatingBorderColors(in: "[borders.color]\nred = 0.5\n", language: .korean)
            fatalError("Missing color fields must not be rewritten")
        } catch BorderColorUpdateError.missingComponent { }
    } catch { fatalError("Language-border checks failed: \(error)") }
    print("Shortcut, repeat/release, fullscreen-exit tracking, input-language detection, color round-trip and config-preservation checks passed")
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let helper = ShortcutHelper()
    var specs = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
    ]
    let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
              id.signature == signature, let shortcut = Shortcut(rawValue: id.id)
        else { return OSStatus(eventNotHandledErr) }
        let helper = Unmanaged<ShortcutHelper>.fromOpaque(context).takeUnretainedValue()
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
            helper.released(shortcut)
        } else {
            helper.pressed(shortcut)
        }
        return noErr
    }, 2, &specs, Unmanaged.passUnretained(helper).toOpaque(), nil)
    guard installStatus == noErr else {
        fputs("Could not install OmniWM shortcut handler: \(installStatus)\n", stderr)
        exit(1)
    }
    helper.start()
    withExtendedLifetime(helper) { app.run() }
}
