// MachineStatsView.swift — a machine's load at a glance: memory, disk and CPU gauges, a live line of the last minute, the heaviest processes, and how many more agents would fit.
//
// The question this answers is "can I start another agent on this box?" — so the headline is
// the room left, in agents, worked out from free memory against what one coding agent
// actually costs here (a Claude Code session measured ~700 MB on the Pi). Everything comes
// from `/stats`, polled every 3 s while the screen is up and kept as a 60-point history.
import SwiftUI
import Charts

/// One reading of `/stats`, stamped so the chart has a time axis.
private struct StatsSample: Identifiable {
    let id = UUID()
    let at: Date
    let cpu: Double
    let memPct: Double
}

/// The compact row for the machine page: three gauges, tap for the full screen.
struct MachineStatsRow: View {
    let stats: Stats

    var body: some View {
        HStack(spacing: 18) {
            gauge("Memory", stats.mem.pct, "\(Int(stats.mem.usedMB / 1024)) / \(Int(stats.mem.totalMB / 1024)) GB")
            gauge("Disk", stats.disk.pct, "\(Int(stats.disk.usedGB)) / \(Int(stats.disk.totalGB)) GB")
            gauge("CPU", stats.cpuPct, String(format: "load %.1f", stats.load.first ?? 0))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(agentsThatFit(stats))")
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text("more agents fit").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func gauge(_ label: String, _ pct: Double, _ detail: String) -> some View {
        VStack(spacing: 4) {
            Gauge(value: min(100, max(0, pct)), in: 0...100) {
                Text(label)
            } currentValueLabel: {
                Text("\(Int(pct))").font(.caption2.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(loadColor(pct))
            .scaleEffect(0.8)
            .frame(width: 48, height: 48)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(label) \(Int(pct)) percent, \(detail)")
    }
}

/// How many more coding agents this machine has room for, on memory alone: each one is
/// budgeted at 700 MB (a Claude Code session on the Pi measured 683 MB) with 1 GB kept
/// back for the OS. CPU is not in the sum — an idle agent costs none, a working one takes
/// what it can get — so this is a ceiling, and the CPU gauge says whether it is busy now.
func agentsThatFit(_ stats: Stats) -> Int {
    let freeMB = stats.mem.totalMB - stats.mem.usedMB - 1024
    return max(0, Int(freeMB / 700))
}

private func loadColor(_ pct: Double) -> Color {
    pct >= 90 ? .red : pct >= 75 ? .orange : .green
}

struct MachineStatsView: View {
    @EnvironmentObject var store: MeshStore
    let machine: Machine
    @State private var latest: Stats?
    @State private var history: [StatsSample] = []
    @State private var failure: String?

    var body: some View {
        List {
            if let latest {
                Section {
                    MachineStatsRow(stats: latest)
                    Text("\(agentsThatFit(latest)) more coding agents fit by memory (700 MB each, 1 GB kept for the system) — \(latest.agentsCount) session\(latest.agentsCount == 1 ? "" : "s") running now.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Last minute") {
                    Chart(history) { sample in
                        LineMark(x: .value("Time", sample.at), y: .value("CPU %", sample.cpu))
                            .foregroundStyle(by: .value("Series", "CPU"))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", sample.at), y: .value("Memory %", sample.memPct))
                            .foregroundStyle(by: .value("Series", "Memory"))
                            .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis { AxisMarks(values: [0, 50, 100]) }
                    .chartXAxis(.hidden)
                    .chartForegroundStyleScale(["CPU": Color.blue, "Memory": Color.purple])
                    .frame(height: 140)
                }
                Section("Memory") {
                    LabeledContent("Used", value: String(format: "%.1f GB", latest.mem.usedMB / 1024))
                    LabeledContent("Total", value: String(format: "%.1f GB", latest.mem.totalMB / 1024))
                }
                Section("Disk · \(latest.disk.path)") {
                    LabeledContent("Used", value: String(format: "%.0f GB", latest.disk.usedGB))
                    LabeledContent("Free", value: String(format: "%.0f GB", latest.disk.totalGB - latest.disk.usedGB))
                }
                if !latest.topProcs.isEmpty {
                    Section("Heaviest processes") {
                        Chart(latest.topProcs.prefix(6)) { proc in
                            BarMark(x: .value("Memory MB", proc.memMB), y: .value("Process", proc.cmd))
                                .foregroundStyle(Color.purple.opacity(0.7))
                                .annotation(position: .trailing) {
                                    Text(String(format: "%.0f MB · %.0f%% CPU", proc.memMB, proc.cpuPct))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(min(6, latest.topProcs.count)) * 34)
                    }
                }
            } else if let failure {
                ContentUnavailableView("No reading", systemImage: "gauge.with.dots.needle.33percent", description: Text(failure))
            } else {
                ProgressView("Reading \(machine.host)…")
            }
        }
        .navigationTitle("Load on \(machine.host)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                do {
                    let stats = try await store.client(for: machine).stats()
                    latest = stats
                    failure = nil
                    history.append(StatsSample(at: Date(), cpu: stats.cpuPct, memPct: stats.mem.pct))
                    if history.count > 60 { history.removeFirst(history.count - 60) }
                } catch {
                    if latest == nil { failure = "Couldn't reach \(machine.host)." }
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
