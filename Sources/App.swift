import SwiftUI
import ServiceManagement

@main
struct RedlineApp: App {
    @StateObject private var stats = Stats()
    @AppStorage("menuBarStyle") private var style = BarStyle.graph

    init() {
        // Open at login by default; after the first launch the panel toggle is in charge.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didSetUpLoginItem") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "didSetUpLoginItem")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(stats: stats)
        } label: {
            Image(nsImage: MenuBarIcon.image(style: style, readings: stats.readings, cpuHistory: stats.cpuHistory))
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Live stats

@MainActor
final class Stats: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var temperature: Double?
    @Published private(set) var fans: [Fan] = []

    let memoryTotal = MemoryReader.total
    private let historyLength = 60
    private let cpuReader = CPUReader()
    private let smc = SMC()
    private let thermal = ThermalReader()
    private var timer: Timer?

    init() {
        _ = cpuReader.usage() // prime the baseline
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    var readings: [Reading] {
        var readings = [
            Reading(letter: "C", text: percent(cpu), widestText: "100%", fraction: cpu, health: .cpu(cpu)),
            Reading(letter: "R", text: percent(memoryFraction), widestText: "100%", fraction: memoryFraction,
                    health: .memory(memoryFraction)),
        ]
        if let temperature {
            readings.append(Reading(letter: "T", text: "\(Int(temperature.rounded()))°", widestText: "100°",
                                    fraction: temperature / 105, health: .temperature(temperature)))
        }
        return readings
    }

    private func refresh() {
        cpu = cpuReader.usage()
        cpuHistory = Array((cpuHistory + [cpu]).suffix(historyLength))
        memoryUsed = MemoryReader.used()
        temperature = thermal.cpuTemperature()
        fans = smc?.fans() ?? []
    }
}

func percent(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
}

func gigabytes(_ bytes: Double) -> String {
    String(format: "%.1f GB", bytes / 1_073_741_824)
}

// MARK: - Panel

struct PanelView: View {
    @ObservedObject var stats: Stats
    @AppStorage("menuBarStyle") private var style = BarStyle.graph
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Redline").font(.headline)

            MetricRow(icon: "cpu", title: "CPU", value: percent(stats.cpu), fraction: stats.cpu,
                      health: .cpu(stats.cpu))
            Sparkline(values: stats.cpuHistory)
                .frame(height: 36)

            MetricRow(icon: "memorychip", title: "Memory",
                      value: "\(gigabytes(stats.memoryUsed)) of \(gigabytes(stats.memoryTotal))",
                      fraction: stats.memoryFraction, health: .memory(stats.memoryFraction))

            if let temperature = stats.temperature {
                MetricRow(icon: "thermometer.medium", title: "Chip temperature",
                          value: "\(Int(temperature.rounded()))°C",
                          fraction: min(temperature / 105, 1), health: .temperature(temperature))
            }

            ForEach(stats.fans) { fan in
                let fraction = fan.maxRPM > 0 ? min(fan.rpm / fan.maxRPM, 1) : 0
                MetricRow(icon: "fan", title: stats.fans.count > 1 ? "Fan \(fan.id + 1)" : "Fan",
                          value: fan.rpm < 1 ? "Off (quiet)" : "\(Int(fan.rpm)) RPM",
                          fraction: fraction, health: .fan(fraction))
            }

            HStack(spacing: 10) {
                ForEach(Health.allCases, id: \.self) { level in
                    HStack(spacing: 4) {
                        Circle().fill(Color(nsColor: level.color)).frame(width: 7, height: 7)
                        Text(level.name)
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Menu bar style").font(.callout)
                Picker("Menu bar style", selection: $style) {
                    ForEach(BarStyle.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            HStack {
                Button("Activity Monitor") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

struct MetricRow: View {
    let icon: String
    let title: String
    let value: String
    let fraction: Double
    let health: Health

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            ProgressView(value: fraction)
                .tint(Color(nsColor: health.color))
        }
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let step = geo.size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(max(v, 0), 1))))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5))
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(Color.accentColor.opacity(0.25))
                    Path { path in
                        path.addLines(points)
                    }
                    .stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
