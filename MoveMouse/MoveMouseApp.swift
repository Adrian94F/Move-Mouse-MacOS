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

    init() {
        d.register(defaults: ["enabled": true, "interval": 30.0, "maxDistance": 50.0, "idleThreshold": 60.0, "useSchedule": false])
        enabled = d.bool(forKey: "enabled")
        interval = d.double(forKey: "interval")
        maxDistance = d.double(forKey: "maxDistance")
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

let dayNames = [1: "Niedziela", 2: "Poniedziałek", 3: "Wtorek", 4: "Środa", 5: "Czwartek", 6: "Piątek", 7: "Sobota"]

struct TimeField: View {
    @Binding var minutes: Int
    var body: some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())! },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes = c.hour! * 60 + c.minute! }),
            displayedComponents: .hourAndMinute).labelsHidden().frame(width: 80)
    }
}

struct ContentView: View {
    @ObservedObject var s: Settings
    @ObservedObject var m: Mover

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Włączony", isOn: $s.enabled).toggleStyle(.switch)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image("Rat").resizable().scaledToFit().frame(width: 56, height: 56)
                    .foregroundStyle(s.enabled ? Color.accentColor : Color.secondary)
            }
            if !m.trusted {
                Button("Przyznaj dostęp do Uniwersalnego dostępu…") { m.requestAccess() }
                Text("Wymagane do poruszania kursorem.").font(.caption).foregroundStyle(.red)
            }
            Divider()
            Stepper("Ruch co: \(Int(s.interval)) s", value: $s.interval, in: 1...3600, step: s.interval >= 60 ? 10 : 5)
            Stepper("Po bezczynności: \(Int(s.idleThreshold)) s", value: $s.idleThreshold, in: 1...7200, step: s.idleThreshold >= 60 ? 30 : 5)
            Stepper("Maks. odległość: \(Int(s.maxDistance)) px", value: $s.maxDistance, in: 1...1000, step: 5)
            Divider()
            Toggle("Używaj harmonogramu", isOn: $s.useSchedule)
            if s.useSchedule {
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
            }
            Divider()
            Toggle("Uruchamiaj przy logowaniu", isOn: Binding(get: { s.launchAtLogin }, set: { s.setLaunchAtLogin($0) }))
            Button("Zakończ") { NSApp.terminate(nil) }
        }
        .padding(20).frame(width: 390)
    }

    var statusText: String {
        if !s.enabled { return "Wstrzymany" }
        if !s.inSchedule() { return "Poza harmonogramem" }
        return "Aktywny" + (m.lastMove.map { " · ostatni ruch " + $0.formatted(date: .omitted, time: .standard) } ?? "")
    }
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

    init() {
        let s = Settings()
        _settings = StateObject(wrappedValue: s)
        _mover = StateObject(wrappedValue: Mover(s))
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
