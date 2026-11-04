import SwiftUI
import ServiceManagement
import ApplicationServices

struct DaySchedule: Codable, Identifiable {
    var id: Int            // 1 = Sunday ... 7 = Saturday (Calendar weekday)
    var enabled: Bool
    var startMinutes: Int
    var endMinutes: Int
}

final class Settings: ObservableObject {
    static let defaultDays = (1...7).map { DaySchedule(id: $0, enabled: (2...6).contains($0), startMinutes: 9 * 60, endMinutes: 17 * 60) }
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var interval: Double { didSet { d.set(interval, forKey: "interval") } }
    @Published var maxDistance: Double { didSet { d.set(maxDistance, forKey: "maxDistance") } }
    @Published var idleThreshold: Double { didSet { d.set(idleThreshold, forKey: "idleThreshold") } }
    @Published var useSchedule: Bool { didSet { d.set(useSchedule, forKey: "useSchedule") } }
    @Published var days: [DaySchedule] { didSet { d.set(try? JSONEncoder().encode(days), forKey: "days") } }
    @Published var launchAtLogin: Bool
    @Published var language: String { didSet { d.set(language, forKey: "language") } }

    // "system" follows the system language; supported: en, pl (English is the fallback).
    var languageCode: String {
        language == "system" ? (Bundle.main.preferredLocalizations.first ?? "en") : language
    }
    func tr(_ key: String, _ args: CVarArg...) -> String {
        let b = Bundle.main.path(forResource: languageCode, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
        return String(format: b.localizedString(forKey: key, value: key, table: nil), arguments: args)
    }

    init() {
        d.register(defaults: ["enabled": true, "interval": 30.0, "maxDistance": 50.0, "idleThreshold": 60.0, "useSchedule": false])
        enabled = d.bool(forKey: "enabled")
        interval = d.double(forKey: "interval")
        maxDistance = d.double(forKey: "maxDistance")
        language = d.string(forKey: "language") ?? "system"
        idleThreshold = d.double(forKey: "idleThreshold")
        useSchedule = d.bool(forKey: "useSchedule")
        if let data = d.data(forKey: "days"), let v = try? JSONDecoder().decode([DaySchedule].self, from: data) { days = v }
        else { days = Settings.defaultDays }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { NSLog("Login item error: \(error)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func inSchedule(_ now: Date = Date()) -> Bool {
        guard useSchedule else { return true }
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: now)
        guard let day = days.first(where: { $0.id == c.weekday }), day.enabled else { return false }
        let m = c.hour! * 60 + c.minute!
        if day.startMinutes <= day.endMinutes { return m >= day.startMinutes && m < day.endMinutes }
        return m >= day.startMinutes || m < day.endMinutes
    }
}

final class Mover: ObservableObject {
    let settings: Settings
    private var timer: Timer?
    @Published var lastMove: Date?
    @Published var trusted = AXIsProcessTrusted()
    @Published var running = false

    init(_ s: Settings) { settings = s; schedule() }

    private var ownMoveAt: Date?
    private var idleAtOwnMove: TimeInterval = 0

    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    // Our synthetic events reset the system idle counter, so the user's idle time is reconstructed.
    private func userIdleSeconds() -> TimeInterval {
        let sys = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if let t = ownMoveAt {
            let since = Date().timeIntervalSince(t)
            if sys >= since - 1 { return idleAtOwnMove + since }
            ownMoveAt = nil
        }
        return sys
    }

    func requestAccess() {
        trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    // False when another user is on the console (fast user switching) or the screen is locked.
    private var sessionActive: Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        let onConsole = d["kCGSSessionOnConsoleKey"] as? Bool ?? false
        let locked = d["CGSSessionScreenIsLocked"] as? Bool ?? false
        return onConsole && !locked
    }

    var active: Bool { settings.enabled && settings.inSchedule() }

    func tick() {
        trusted = AXIsProcessTrusted()
        guard active, trusted, sessionActive else { running = false; return }
        let idle = userIdleSeconds()
        let nowRunning = idle >= settings.idleThreshold
        if running != nowRunning { running = nowRunning }
        guard nowRunning else { return }
        if let t = ownMoveAt, Date().timeIntervalSince(t) < settings.interval - 0.5 { return }
        var bounds = CGRect.null
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        for i in ids.prefix(Int(n)) { bounds = bounds.union(CGDisplayBounds(i)) }
        guard let cur = CGEvent(source: nil)?.location, !bounds.isNull else { return }
        let angle = Double.random(in: 0..<(2 * .pi))
        let dist = Double.random(in: 1...max(1, settings.maxDistance))
        let p = CGPoint(x: min(max(cur.x + cos(angle) * dist, bounds.minX), bounds.maxX - 1),
                        y: min(max(cur.y + sin(angle) * dist, bounds.minY), bounds.maxY - 1))
        idleAtOwnMove = idle
        animate(from: cur, to: p, duration: 0.25 + dist / 400)
    }

    private var animTimer: Timer?

    private func post(_ p: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        ownMoveAt = Date()
        lastMove = ownMoveAt
    }

    // Smooth ease-in-out movement; aborted if the user moves the mouse meanwhile.
    private func animate(from a: CGPoint, to b: CGPoint, duration: TimeInterval) {
        animTimer?.invalidate()
        let start = Date()
        var expected = a
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if let now = CGEvent(source: nil)?.location, hypot(now.x - expected.x, now.y - expected.y) > 3 {
                t.invalidate(); self.ownMoveAt = nil; return
            }
            let k = min(1, Date().timeIntervalSince(start) / duration)
            let e = k * k * (3 - 2 * k)
            expected = CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
            self.post(expected)
            if k >= 1 { t.invalidate() }
        }
    }
}

let dayNames: [Int: LocalizedStringKey] = [1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday", 5: "Thursday", 6: "Friday", 7: "Saturday"]

struct TimeField: View {
    @Binding var minutes: Int
    var body: some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())! },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes = c.hour! * 60 + c.minute! }),
            displayedComponents: .hourAndMinute).labelsHidden().frame(width: 80)
    }
}

enum Tab: CaseIterable {
    case start, settings, schedule, info
    var icon: String {
        switch self {
        case .start: return "computermouse"
        case .settings: return "gearshape"
        case .schedule: return "calendar"
        case .info: return "info.circle"
        }
    }
}

struct ContentView: View {
    @ObservedObject var s: Settings
    @ObservedObject var m: Mover
    @State private var tab = Tab.start

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button { tab = t } label: {
                        Image(systemName: t.icon)
                            .font(.system(size: 22))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(tab == t ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tab == t ? Color.accentColor : Color.secondary)
                }
            }
            Group {
                switch tab {
                case .start: startView
                case .settings: settingsView
                case .schedule: scheduleView
                case .info: infoView
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(12)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12).frame(width: 390)
        .environment(\.locale, Locale(identifier: s.languageCode)).fixedSize(horizontal: false, vertical: true)
    }

    var startView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(LocalizedStringKey(s.enabled ? "Enabled" : "Disabled"), isOn: $s.enabled).toggleStyle(.switch)
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            if !m.trusted {
                Button("Grant Accessibility access…") { m.requestAccess() }
                Text("Required to move the cursor.").font(.caption).foregroundStyle(.red)
            }
            Image("Rat").resizable().scaledToFit().frame(width: 200, height: 200)
                .foregroundStyle(s.enabled ? Color.accentColor : Color.secondary)
                .shadow(color: s.enabled ? .black.opacity(0.8) : .clear, radius: 14)
                .animation(.easeInOut(duration: 0.3), value: s.enabled)
                .padding(.vertical, 10).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { s.enabled.toggle() }
        }
    }

    var settingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("Move every: \(Int(s.interval)) s", value: $s.interval, in: 1...3600, step: s.interval >= 60 ? 10 : 5)
            Stepper("After idle: \(Int(s.idleThreshold)) s", value: $s.idleThreshold, in: 1...7200, step: s.idleThreshold >= 60 ? 30 : 5)
            Stepper("Max distance: \(Int(s.maxDistance)) px", value: $s.maxDistance, in: 1...1000, step: 5)
            Picker("Language", selection: $s.language) {
                Text("System").tag("system")
                Text("English").tag("en")
                Text("Polski").tag("pl")
            }
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { s.launchAtLogin }, set: { s.setLaunchAtLogin($0) }))
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    var scheduleView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Use schedule", isOn: $s.useSchedule)
            VStack(alignment: .leading, spacing: 12) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                    let i = s.days.firstIndex { $0.id == wd }!
                    let day = s.days[i]
                    HStack {
                        Toggle(dayNames[wd]!, isOn: $s.days[i].enabled)
                        Spacer()
                        TimeField(minutes: $s.days[i].startMinutes).disabled(!day.enabled)
                        Text("-")
                        TimeField(minutes: $s.days[i].endMinutes).disabled(!day.enabled)
                    }
                }
            }
            .padding(.leading, 22)
            .disabled(!s.useSchedule).opacity(s.useSchedule ? 1 : 0.5)
        }
    }

    var infoView: some View {
        VStack(spacing: 10) {
            Text("Move Mouse").font(.title2.bold())
            Image("Rat").resizable().scaledToFit().frame(width: 110, height: 110)
                .foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 2)
            Text("A menu bar app that smoothly moves the cursor while you are idle, so other programs see your activity.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Author: Adrian Frydmański").font(.callout)
            HStack(spacing: 8) {
                Link("Repository", destination: URL(string: "https://github.com/Adrian94F/Move-Mouse-MacOS")!)
                Text("|").foregroundStyle(.tertiary)
                Link("License", destination: URL(string: "https://github.com/Adrian94F/Move-Mouse-MacOS/blob/master/LICENSE")!)
                Text("|").foregroundStyle(.tertiary)
                Link("frydmanski.cc", destination: URL(string: "https://frydmanski.cc")!)
            }
            .font(.callout)
            .padding(.top, 6)
        }
    }

    var statusText: String {
        if !s.enabled { return s.tr("Paused") }
        if !s.inSchedule() { return s.tr("Outside schedule") }
        let base = s.tr("Active")
        guard let t = m.lastMove else { return base }
        return base + " · " + s.tr("last move %@", t.formatted(date: .omitted, time: .standard))
    }
}

// MenuBarExtra has no right-click support, so a local monitor catches clicks on its status item.
final class ContextMenuController: NSObject {
    private let settings: Settings
    private var monitor: Any?

    init(_ s: Settings) {
        settings = s
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let w = event.window, w.className.contains("StatusBar"), let view = w.contentView else { return event }
            let menu = NSMenu()
            let toggle = NSMenuItem(title: self.settings.tr(self.settings.enabled ? "Disable" : "Enable"), action: #selector(self.toggle), keyEquivalent: "")
            toggle.target = self
            let quit = NSMenuItem(title: self.settings.tr("Quit"), action: #selector(self.quit), keyEquivalent: "")
            quit.target = self
            menu.addItem(toggle)
            menu.addItem(.separator())
            menu.addItem(quit)
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            return nil
        }
    }

    @objc private func toggle() { settings.enabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

struct MenuIcon: View {
    let enabled: Bool
    let running: Bool
    var body: some View {
        let name = enabled ? "computermouse.fill" : "computermouse"
        if running, let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.systemGreen])) {
            Image(nsImage: img)
        } else {
            Image(systemName: name)
        }
    }
}

@main
struct MoveMouseApp: App {
    @StateObject private var settings: Settings
    @StateObject private var mover: Mover
    private let contextMenu: ContextMenuController

    init() {
        let s = Settings()
        _settings = StateObject(wrappedValue: s)
        _mover = StateObject(wrappedValue: Mover(s))
        contextMenu = ContextMenuController(s)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(s: settings, m: mover)
        } label: {
            MenuIcon(enabled: settings.enabled, running: mover.running)
        }
        .menuBarExtraStyle(.window)
    }
}
