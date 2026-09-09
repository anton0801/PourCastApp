import SwiftUI

/// One day of the week timeline: date, 24h score bar (23/25 on DST days),
/// best-block chip. The bar is the day's verdict fingerprint — colored
/// segments per candidate hour over a formwork tick ruler.
struct DayRow: View {
    let day: DayVerdicts
    let calendar: Calendar
    var collapseChip: Bool = false

    @Environment(\.dynamicTypeSize) private var typeSize

    private var dayHourCount: Int {
        let start = day.day
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return 24 }
        return max(Int(next.timeIntervalSince(start) / 3600), 1)
    }

    var body: some View {
        HStack(spacing: PCSpacing.m) {
            let label = PCFormat.dayLabel(day.day, calendar: calendar)
            VStack(alignment: .leading, spacing: 0) {
                Text(label.weekday)
                    .pcCapsLabel(.textPrimary)
                Text(label.day)
                    .font(PCType.monoSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(width: typeSize >= .xxLarge ? 60 : 40, alignment: .leading)

            ScoreBar(day: day, dayHourCount: dayHourCount, calendar: calendar)
                .frame(height: 30)

            chip
                .frame(width: collapseChip || typeSize >= .xxLarge ? 54 : 96, alignment: .trailing)
        }
        .padding(.vertical, PCSpacing.m)
        .padding(.horizontal, PCSpacing.l)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var chip: some View {
        if let best = day.best {
            VStack(alignment: .trailing, spacing: 1) {
                if !(collapseChip || typeSize >= .xxLarge) {
                    Text(PCFormat.hourRange(best.start, best.end, calendar: calendar))
                        .font(PCType.monoSmall)
                        .foregroundStyle(Color.textPrimary)
                }
                Text("\(best.score)")
                    .font(PCType.mono)
                    .foregroundStyle(blockColor(best))
            }
        } else {
            // No candidates at all means the forecast doesn't reach this day.
            Text(day.candidates.isEmpty ? "No data" : "No window")
                .pcCapsLabel()
                .multilineTextAlignment(.trailing)
        }
    }

    private func blockColor(_ best: BestBlock) -> Color {
        best.score >= 80 ? .accentTeal : (best.score >= 50 ? .warningOchre : .dangerClay)
    }

    private var accessibilitySummary: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let weekday = formatter.string(from: day.day)
        guard let best = day.best else {
            return "\(weekday), no pour window"
        }
        let verdict: String = best.score >= 80 ? "go" : (best.score >= 50 ? "caution" : "no go")
        let start = calendar.component(.hour, from: best.start)
        let end = calendar.component(.hour, from: best.end)
        return "\(weekday), best window \(start) to \(end), score \(best.score), \(verdict)"
    }
}

private struct ScoreBar: View {
    let day: DayVerdicts
    let dayHourCount: Int
    let calendar: Calendar

    var body: some View {
        Canvas { context, size in
            let barHeight: CGFloat = size.height - 8
            let track = CGRect(x: 0, y: 0, width: size.width, height: barHeight)
            context.fill(
                Path(roundedRect: track, cornerRadius: PCShape.innerRadius),
                with: .color(.surface)
            )

            let hourWidth = size.width / CGFloat(dayHourCount)

            // Candidate segments, colored by verdict.
            context.clip(to: Path(roundedRect: track, cornerRadius: PCShape.innerRadius))
            for candidate in day.candidates {
                let offset = candidate.start.timeIntervalSince(day.day) / 3600
                guard offset >= 0 else { continue }
                let rect = CGRect(
                    x: CGFloat(offset) * hourWidth,
                    y: 0,
                    width: hourWidth + 0.5,
                    height: barHeight
                )
                context.fill(Path(rect), with: .color(candidate.verdict.color.opacity(0.85)))
            }

            // Best block: brighter cap line on top of its span.
            if let best = day.best {
                let from = CGFloat(best.start.timeIntervalSince(day.day) / 3600) * hourWidth
                let to = CGFloat(best.end.timeIntervalSince(day.day) / 3600) * hourWidth
                let cap = CGRect(x: from, y: 0, width: to - from, height: 2.5)
                context.fill(Path(cap), with: .color(.textPrimary.opacity(0.65)))
            }

            // Formwork ticks under the bar: minor every hour, major every 6.
            var ticks = context
            ticks.clip(to: Path(CGRect(origin: .zero, size: size)))
            for hour in 0...dayHourCount {
                let x = CGFloat(hour) * hourWidth
                let major = hour % 6 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: barHeight + 2))
                tick.addLine(to: CGPoint(x: x, y: barHeight + (major ? 8 : 5)))
                ticks.stroke(
                    tick,
                    with: .color(.textSecondary.opacity(major ? 0.5 : 0.25)),
                    lineWidth: 1
                )
            }
        }
    }
}
