import SwiftUI

/// 48h cure rail: elapsed fill over a formwork tick ruler, forecast risks
/// pinned at their hour, live hours-remaining readout.
struct ProgressRail: View {
    let pour: Pour
    let risks: [Violation]
    var compact = false
    /// Onboarding drives the rail through its script instead of wall-clock time.
    var elapsedHoursOverride: Double? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let elapsed = elapsedHoursOverride ?? (now.timeIntervalSince(pour.start) / 3600)
            let progress = min(max(elapsed / Double(WindowEngine.cureWindowHours), 0), 1)
            let remaining = max(Double(WindowEngine.cureWindowHours) - elapsed, 0)

            VStack(alignment: .leading, spacing: PCSpacing.xs) {
                if !compact {
                    HStack(alignment: .firstTextBaseline) {
                        Text("48h cure")
                            .pcCapsLabel()
                        Spacer()
                        readout(remaining: remaining)
                    }
                }

                RailCanvas(
                    progress: progress,
                    risks: risks,
                    violations: pour.violations,
                    status: pour.status,
                    start: pour.start
                )
                .frame(height: compact ? 18 : 26)

                if compact {
                    readout(remaining: remaining)
                }
            }
        }
    }

    @ViewBuilder
    private func readout(remaining: Double) -> some View {
        // A driven rail (onboarding script) never shows the future-pour label.
        let untilStart = elapsedHoursOverride == nil ? pour.start.timeIntervalSinceNow / 3600 : 0
        switch pour.status {
        case .completed:
            Text("Cured")
                .pcCapsLabel(.accentTeal)
        case .violated where remaining <= 0:
            Text("Ended · violated")
                .pcCapsLabel(.dangerClay)
        default:
            if untilStart > 0 {
                Text("Starts in \(Int(untilStart.rounded(.up)))h")
                    .font(PCType.monoSmall)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("\(Int(remaining.rounded(.up)))h remaining")
                    .font(PCType.monoSmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

private struct RailCanvas: View {
    let progress: Double
    let risks: [Violation]
    let violations: [Violation]
    let status: PourStatus
    let start: Date

    var body: some View {
        Canvas { context, size in
            let railHeight: CGFloat = 8
            let railY = size.height - railHeight - 6
            let rail = CGRect(x: 0, y: railY, width: size.width, height: railHeight)

            context.fill(
                Path(roundedRect: rail, cornerRadius: 3),
                with: .color(.surface)
            )
            context.stroke(
                Path(roundedRect: rail, cornerRadius: 3),
                with: .color(.hairline),
                lineWidth: 1
            )

            // Elapsed fill — teal while clean, clay once violated.
            let fillColor: Color = status == .violated ? .dangerClay : .accentTeal
            if progress > 0 {
                let fill = CGRect(x: 0, y: railY, width: size.width * progress, height: railHeight)
                var clipped = context
                clipped.clip(to: Path(roundedRect: rail, cornerRadius: 3))
                clipped.fill(Path(fill), with: .color(fillColor))
            }

            // Ticks below: minor each 2h, major each 6h over 48h.
            for hour in stride(from: 0, through: WindowEngine.cureWindowHours, by: 2) {
                let x = size.width * CGFloat(hour) / CGFloat(WindowEngine.cureWindowHours)
                let major = hour % 6 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: railY + railHeight + 1))
                tick.addLine(to: CGPoint(x: x, y: railY + railHeight + (major ? 6 : 3.5)))
                context.stroke(
                    tick,
                    with: .color(.textSecondary.opacity(major ? 0.5 : 0.25)),
                    lineWidth: 1
                )
            }

            // Pins: violations that happened (filled) + forecast risks (outlined).
            func pin(at hour: Date, filled: Bool, kind: Violation.Kind) {
                let offset = hour.timeIntervalSince(start) / 3600
                guard offset >= 0, offset <= Double(WindowEngine.cureWindowHours) else { return }
                let x = size.width * CGFloat(offset) / CGFloat(WindowEngine.cureWindowHours)
                let color: Color = kind == .frost ? .dangerClay : .warningOchre
                let dot = CGRect(x: x - 3.5, y: railY - 8, width: 7, height: 7)
                if filled {
                    context.fill(Path(ellipseIn: dot), with: .color(color))
                } else {
                    context.stroke(Path(ellipseIn: dot), with: .color(color), lineWidth: 1.5)
                }
                var stem = Path()
                stem.move(to: CGPoint(x: x, y: railY - 1))
                stem.addLine(to: CGPoint(x: x, y: railY - 2.5))
                context.stroke(stem, with: .color(color), lineWidth: 1)
            }

            for violation in violations {
                pin(at: violation.hour, filled: true, kind: violation.kind)
            }
            for risk in risks where !violations.contains(where: { $0.id == risk.id }) {
                pin(at: risk.hour, filled: false, kind: risk.kind)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let percent = Int(progress * 100)
        let riskText = risks.isEmpty ? "no upcoming risks" : "\(risks.count) upcoming risk\(risks.count == 1 ? "" : "s")"
        return "Cure \(percent) percent complete, \(riskText)"
    }
}
