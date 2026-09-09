import SwiftUI

extension VerdictClass {
    var color: Color {
        switch self {
        case .go: return .accentTeal
        case .caution: return .warningOchre
        case .noGo: return .dangerClay
        }
    }
}

/// The hero: verdict word in display type, reason line, score.
/// Tinted border only — no fill flood.
struct VerdictCard: View {
    let title: String
    let verdict: VerdictClass
    let reason: String
    let score: Int?
    /// Extra line when the cache is >12h old.
    let staleLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            Text(title)
                .pcCapsLabel()

            HStack(alignment: .firstTextBaseline) {
                Text(verdict.word)
                    .font(PCType.display)
                    .tracking(PCType.displayTracking)
                    .foregroundStyle(verdict.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .id(verdict)
                    .transition(.opacity.combined(with: .offset(y: 8)))

                Spacer(minLength: PCSpacing.s)

                if let score {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(score)")
                            .font(PCType.monoDisplay)
                            .foregroundStyle(Color.textPrimary)
                            .contentTransition(.numericText())
                        Text("/100")
                            .pcCapsLabel()
                    }
                }
            }

            Text(reason)
                .font(PCType.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let staleLine {
                HStack(spacing: PCSpacing.xs) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 11, weight: .medium))
                    Text(staleLine)
                        .font(PCType.footnote)
                }
                .foregroundStyle(Color.warningOchre)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PCSpacing.l)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                .strokeBorder(verdict.color.opacity(0.6), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(verdict.word). \(reason)\(score.map { ". Score \($0)" } ?? "")")
    }
}
