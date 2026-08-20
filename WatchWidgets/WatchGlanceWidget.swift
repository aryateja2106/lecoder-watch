import WidgetKit
import SwiftUI

@main
struct WatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchGlanceWidget()
    }
}

/// A watch-face complication and Smart Stack card: how many agents are waiting on you,
/// or how much of your mesh is up when nothing is.
///
/// The timeline is a single entry refreshed on a schedule, plus an immediate reload
/// whenever the app writes a new glance (`GlanceStore.write`). A complication cannot
/// poll the mesh itself, so everything here comes from the app's last reading — and
/// says so once that reading goes stale.
struct WatchGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeshGlance", provider: GlanceProvider()) { entry in
            GlanceView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agents waiting")
        .description("How many agents are waiting on you, and how much of your mesh is up.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct GlanceEntry: TimelineEntry {
    let date: Date
    let glance: WatchGlance
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), glance: WatchGlance(
            updatedISO: ISO8601DateFormatter().string(from: Date()),
            waiting: [.init(host: "studio", session: "api", line: "Allow edit?")],
            machinesUp: 2, machinesTotal: 3,
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(GlanceEntry(date: Date(), glance: context.isPreview ? placeholder(in: context).glance : GlanceStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        let glance = GlanceStore.read()
        // Two entries: now, and the moment the reading turns stale — so the face stops
        // asserting a count it can no longer stand behind without needing the app to
        // wake up and tell it.
        var entries = [GlanceEntry(date: now, glance: glance)]
        if let updated = glance.updated {
            let goesStale = updated.addingTimeInterval(TimeInterval(WatchGlance.staleAfterMinutes * 60))
            if goesStale > now { entries.append(GlanceEntry(date: goesStale, glance: glance)) }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

struct GlanceView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlanceEntry

    private var glance: WatchGlance { entry.glance }
    private var waiting: Bool { !glance.isStale(now: entry.date) && !glance.waiting.isEmpty }
    private var tint: Color { waiting ? .orange : .secondary }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(glance.headline(now: entry.date), systemImage: symbol)

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: symbol).font(.caption2).foregroundStyle(tint)
                    Text(glance.shortLabel(now: entry.date))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }

        case .accessoryCorner:
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .widgetLabel(glance.headline(now: entry.date))

        default:
            // Three bands: how many, which one, and what it asked. The question is the
            // only actionable line, so it never gets dropped to make room for a count.
            let bands = glance.entry(now: entry.date)
            VStack(alignment: .leading, spacing: 1) {
                Label(bands.eyebrow, systemImage: symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(bands.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(glance.isStale(now: entry.date) ? .secondary : .primary)
                    .lineLimit(1)
                if !bands.body.isEmpty {
                    Text(bands.body)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var symbol: String {
        if glance.isStale(now: entry.date) { return "clock.badge.questionmark" }
        guard let first = glance.waiting.first else { return "checkmark.circle" }
        // A question that would rewrite history or delete files gets the warning glyph,
        // so the face distinguishes "answer me" from "think before you answer me".
        return first.isRisky ? "exclamationmark.triangle.fill" : "exclamationmark.bubble.fill"
    }
}
