import SwiftUI

// MARK: - AgeBadge: "Updated 12m ago", quiet → ochre by staleness

struct AgeBadge: View {
    let fetchedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let stale = fetchedAt.map {
                timeline.date.timeIntervalSince($0) > ForecastStore.staleAfter
            } ?? true

            HStack(spacing: PCSpacing.xs) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                Text(fetchedAt.map { "Updated \(PCFormat.age(since: $0, now: timeline.date))" } ?? "No data yet")
                    .font(PCType.monoSmall)
            }
            .foregroundStyle(stale ? Color.warningOchre : Color.textSecondary)
            .padding(.horizontal, PCSpacing.s)
            .padding(.vertical, PCSpacing.xs)
            .background(
                stale ? Color.warningMuted : Color.surfaceElevated,
                in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
        }
    }
}

// MARK: - SkeletonRow: shaped like a DayRow, shimmer via TimelineView phase

struct SkeletonRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6

            HStack(spacing: PCSpacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    block(width: 30, height: 10)
                    block(width: 20, height: 8)
                }
                .frame(width: 40, alignment: .leading)
                block(height: 22)
                block(width: 72, height: 18)
            }
            .padding(.vertical, PCSpacing.m)
            .padding(.horizontal, PCSpacing.l)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
            .overlay(shimmer(phase: phase))
            .clipShape(RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
        }
    }

    private func block(width: CGFloat? = nil, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.surface)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }

    @ViewBuilder
    private func shimmer(phase: Double) -> some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color.textPrimary.opacity(0.05), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width / 2.5)
                .offset(x: (phase * 1.5 - 0.4) * geo.size.width)
            }
        }
    }
}

// MARK: - TickRuler: the formwork tick motif along timeline/chart edges

struct TickRuler: View {
    var spacing: CGFloat = 8
    var majorEvery: Int = 6

    var body: some View {
        Canvas { context, size in
            var index = 0
            var y: CGFloat = 0
            while y <= size.height {
                let major = index % majorEvery == 0
                var tick = Path()
                tick.move(to: CGPoint(x: 0, y: y))
                tick.addLine(to: CGPoint(x: major ? 10 : 6, y: y))
                context.stroke(
                    tick,
                    with: .color(.textSecondary.opacity(major ? 0.45 : 0.22)),
                    lineWidth: 1
                )
                index += 1
                y += spacing
            }
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - RefreshTicks: pull-to-refresh ring (never the system spinner)

struct RefreshTicks: View {
    /// 0…1 pull progress; ticks light up and the ring winds with the pull.
    var progress: Double
    var spinning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tickCount = 12

    var body: some View {
        TimelineView(.animation(paused: !spinning || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let spinPhase = (t.truncatingRemainder(dividingBy: 0.9)) / 0.9

            Canvas { context, size in
                drawTicks(context: context, size: size, spinPhase: spinPhase)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    private func drawTicks(context: GraphicsContext, size: CGSize, spinPhase: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: Double = Double(min(size.width, size.height)) / 2 - 3
        let visible: Int = spinning ? tickCount : Int((progress * Double(tickCount)).rounded())
        let rotation: Double
        if spinning {
            rotation = spinPhase * 2 * Double.pi
        } else if reduceMotion {
            rotation = 0
        } else {
            rotation = progress * Double.pi * 0.66
        }
        let litIndex: Int = spinning ? Int(spinPhase * Double(tickCount)) % tickCount : -1

        for i in 0..<visible {
            let fraction: Double = Double(i) / Double(tickCount)
            let angle: Double = fraction * 2 * Double.pi - Double.pi / 2 + rotation
            let dx: Double = cos(angle)
            let dy: Double = sin(angle)
            let inner = CGPoint(x: Double(center.x) + dx * (radius - 5), y: Double(center.y) + dy * (radius - 5))
            let outer = CGPoint(x: Double(center.x) + dx * radius, y: Double(center.y) + dy * radius)
            var tick = Path()
            tick.move(to: inner)
            tick.addLine(to: outer)
            let color: Color = (i == litIndex) ? Color.accentTeal : Color.textSecondary.opacity(0.45)
            context.stroke(tick, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}
