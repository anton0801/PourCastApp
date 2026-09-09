import SwiftUI

// Designed state compositions for S1 — every one a deliberate layout,
// never a gray icon + "No data".

// MARK: - First-launch loading: skeleton hero + 7 skeleton rows

struct SkeletonHome: View {
    var body: some View {
        VStack(spacing: PCSpacing.l) {
            VStack(alignment: .leading, spacing: PCSpacing.s) {
                RoundedRectangle(cornerRadius: 3).fill(Color.surface).frame(width: 80, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(Color.surface).frame(width: 180, height: 34)
                RoundedRectangle(cornerRadius: 3).fill(Color.surface).frame(width: 240, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PCSpacing.l)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )

            VStack(spacing: PCSpacing.s) {
                ForEach(0..<7, id: \.self) { index in
                    SkeletonRow()
                        .staggerIn(index: index)
                }
            }
        }
        .accessibilityLabel("Loading forecast")
    }
}

// MARK: - Error card (no cache to fall back on)

struct ErrorCard: View {
    let error: WeatherFetchError
    let retry: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PCSpacing.m) {
            IconTile(
                systemName: error.isKeyProblem ? "key" : "antenna.radiowaves.left.and.right.slash",
                tint: .dangerClay, fill: .dangerMuted
            )
            Text(title)
                .font(PCType.title)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(PCType.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if error.isKeyProblem {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.pcPrimary)
            } else {
                Button("Retry", action: retry)
                    .buttonStyle(.pcPrimary)
            }
        }
        .pcCard()
    }

    private var title: String {
        switch error {
        case .missingKey: return "Weather isn't configured."
        case .invalidKey: return "The weather service refused this app."
        default: return "Couldn't reach the weather service."
        }
    }

    private var message: String {
        switch error {
        case .missingKey:
            return "This build has no weather key yet. Switch to Apple Weather in Settings, or try again later."
        case .invalidKey:
            return "OpenWeatherMap rejected the request. Try again later, or switch to Apple Weather in Settings."
        case .offline:
            return "No connection. Showing nothing would be worse — retry when you're back in coverage?"
        default:
            return "Showing nothing would be worse — retry?"
        }
    }
}

// MARK: - Error banner (rendered OVER cached content)

struct ErrorBanner: View {
    let error: WeatherFetchError
    let retry: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: PCSpacing.m) {
            Image(systemName: error.isKeyProblem ? "key" : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.warningOchre)
            Text(message)
                .font(PCType.footnote)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: PCSpacing.s)
            Button {
                if error.isKeyProblem { openSettings() } else { retry() }
            } label: {
                Text(error.isKeyProblem ? "Settings" : "Retry")
                    .font(PCType.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentTeal)
            }
            .buttonStyle(.pressable)
        }
        .padding(PCSpacing.m)
        .background(Color.warningMuted, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                .strokeBorder(Color.warningOchre.opacity(0.35), lineWidth: 1)
        )
    }

    private var message: String {
        switch error {
        case .missingKey: return "Weather not configured — cached forecast shown."
        case .invalidKey: return "Weather service refused — cached forecast shown."
        case .offline: return "No connection — showing cached forecast."
        case .serviceUnavailable: return "Weather service unavailable — cached forecast still works."
        }
    }
}

// MARK: - No site yet

struct NoSiteCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PCSpacing.m) {
            FormworkTile(systemName: "mappin")
            Text("Set your site to get verdicts")
                .font(PCType.title)
                .foregroundStyle(Color.textPrimary)
            Text("PourCast scores every pour hour of the next 7 days for your location — add a site by search or GPS.")
                .font(PCType.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a site", action: action)
                .buttonStyle(.pcPrimary)
        }
        .pcCard()
    }
}

// MARK: - Empty cure watch: formwork outline in hairlines

struct EmptyPoursCard: View {
    let logAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PCSpacing.m) {
            FormworkOutline()
                .frame(height: 64)
                .frame(maxWidth: .infinity)
            Text("No active pours. Log one and PourCast will guard its first 48 hours.")
                .font(PCType.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Log pour", action: logAction)
                .buttonStyle(.pcPrimary)
        }
        .pcCard()
    }
}

/// Empty-state motif: a formwork profile drawn in hairlines — never a cloud.
struct FormworkOutline: View {
    var body: some View {
        Canvas { context, size in
            let form = CGRect(x: size.width / 2 - 70, y: 8, width: 140, height: size.height - 16)
            context.stroke(
                Path(roundedRect: form, cornerRadius: PCShape.innerRadius),
                with: .color(.textSecondary.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
            for i in 1..<4 {
                let x = form.minX + form.width * CGFloat(i) / 4
                var rib = Path()
                rib.move(to: CGPoint(x: x, y: form.minY))
                rib.addLine(to: CGPoint(x: x, y: form.maxY))
                context.stroke(rib, with: .color(.textSecondary.opacity(0.2)), lineWidth: 1)
            }
            // Side ties.
            for x in [form.minX - 8, form.maxX + 8] {
                var tie = Path()
                tie.move(to: CGPoint(x: x, y: form.midY - 8))
                tie.addLine(to: CGPoint(x: x, y: form.midY + 8))
                context.stroke(tie, with: .color(.textSecondary.opacity(0.35)), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A symbol inside the formwork-styled tile (empty states / Sites).
struct FormworkTile: View {
    let systemName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                .strokeBorder(Color.textSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                .frame(width: 44, height: 44)
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentTeal)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Active pour card (cure progress on Home)

struct ActivePourCard: View {
    let pour: Pour
    let siteName: String
    let risks: [Violation]
    let calendar: Calendar
    let celebrate: () -> Void

    @State private var stampScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: PCSpacing.m) {
            HStack {
                IconTile(systemName: pour.element.symbol)
                VStack(alignment: .leading, spacing: 0) {
                    Text(pour.element.label)
                        .font(PCType.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(siteName) · \(PCFormat.weekdayHour(pour.start, calendar: calendar))")
                        .font(PCType.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                statusBadge
            }

            ProgressRail(pour: pour, risks: risks, compact: true)

            if pour.status == .violated, let violation = pour.violations.first {
                Text(violationLine(violation))
                    .font(PCType.footnote)
                    .foregroundStyle(Color.dangerClay)
            }
        }
        .pcCard()
        .onAppear(perform: celebrateIfNeeded)
        .onChange(of: pour.status) { _ in celebrateIfNeeded() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch pour.status {
        case .completed:
            // The CURED stamp — the app's one celebration moment.
            Text("CURED")
                .font(PCType.capsLabel)
                .tracking(PCType.capsTracking)
                .foregroundStyle(Color.accentTeal)
                .padding(.horizontal, PCSpacing.s)
                .padding(.vertical, PCSpacing.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.accentTeal, lineWidth: 1.5)
                )
                .rotationEffect(.degrees(-4))
                .scaleEffect(stampScale)
        case .violated:
            Text("Violated")
                .pcCapsLabel(.dangerClay)
        case .active:
            Text("Curing")
                .pcCapsLabel(.accentTeal)
        }
    }

    private func violationLine(_ violation: Violation) -> String {
        switch violation.kind {
        case .frost:
            return "Frost hit at h\(violation.cureHour) — inspect before loading."
        case .rain:
            return "Rain hit at h\(violation.cureHour) — check the surface finish."
        }
    }

    private func celebrateIfNeeded() {
        guard pour.status == .completed, !pour.curedCelebrated else { return }
        if reduceMotion {
            stampScale = 1
        } else {
            stampScale = 1.3
            withAnimation(.pc) { stampScale = 1.0 }
        }
        Haptics.medium()
        Haptics.success()
        celebrate()
    }
}
