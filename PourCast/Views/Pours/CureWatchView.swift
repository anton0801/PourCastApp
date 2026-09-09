import SwiftUI

/// S3 watch — one pour's 48 hours. Full rail with pinned risks, conditions
/// now, violation banner, CURED stamp.
struct CureWatchView: View {
    let pourID: UUID

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var pourStore: PourStore
    @EnvironmentObject private var forecast: ForecastStore
    @EnvironmentObject private var sites: SiteStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false

    private var calendar: Calendar { .current }

    private var pour: Pour? {
        pourStore.pours.first { $0.id == pourID }
    }

    var body: some View {
        Group {
            if let pour {
                content(pour: pour)
            } else {
                Text("This pour was removed.")
                    .font(PCType.body)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: PCSpacing.s) {
                    Text("Cure watch")
                        .font(PCType.navTitle)
                        .foregroundStyle(Color.textPrimary)
                    FarmPropStrip(names: ["FarmProp-vane", "FarmProp-puddle", "FarmProp-barricade"], size: 22)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dangerClay)
                }
                .accessibilityLabel("Delete pour")
            }
        }
        .confirmationDialog("Remove this pour?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove pour", role: .destructive) {
                if let pour {
                    Task {
                        await app.deletePour(pour)
                        dismiss()
                    }
                }
            }
        }
    }

    private func content(pour: Pour) -> some View {
        let risks = pourStore.upcomingRisks(for: pour, caches: forecast.caches)
        let siteName = sites.sites.first { $0.id == pour.siteID }?.name ?? "Site"

        return ScrollView {
            VStack(alignment: .leading, spacing: PCSpacing.l) {
                // Identity card.
                HStack(spacing: PCSpacing.m) {
                    IconTile(systemName: pour.element.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pour.element.label) · \(pour.mix.label)")
                            .font(PCType.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("\(siteName) · \(pour.start > Date() ? "planned" : "poured") \(PCFormat.weekdayHour(pour.start, calendar: calendar)) · \(pour.protection.shortLabel.lowercased())")
                            .font(PCType.monoSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }
                .pcCard()

                if pour.status == .violated, let first = pour.violations.first {
                    violatedBanner(first)
                }
                if pour.status == .completed {
                    curedCard
                }

                // The rail, full size, with the tick ruler at its left.
                HStack(alignment: .top, spacing: PCSpacing.xs) {
                    TickRuler()
                        .frame(height: 48)
                    VStack(alignment: .leading, spacing: PCSpacing.s) {
                        ProgressRail(pour: pour, risks: risks)
                    }
                }
                .pcCard()

                // Upcoming risks, each pinned at its hour.
                VStack(alignment: .leading, spacing: PCSpacing.s) {
                    Text("Forecast risks")
                        .pcCapsLabel()
                        .padding(.leading, PCSpacing.xs)
                    if risks.isEmpty && pour.violations.isEmpty {
                        HStack(spacing: PCSpacing.m) {
                            IconTile(systemName: "checkmark.seal")
                            Text(pour.status == .completed
                                 ? "48 hours, clean. Strip when the mix spec allows."
                                 : "Nothing in the forecast threatens this cure.")
                                .font(PCType.body)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .padding(PCSpacing.m)
                        .pcTile()
                    } else {
                        ForEach(pour.violations) { violation in
                            riskRow(violation, happened: true)
                        }
                        ForEach(risks.filter { risk in !pour.violations.contains { $0.id == risk.id } }) { risk in
                            riskRow(risk, happened: false)
                        }
                    }
                }

                conditionsNow(pour: pour)
            }
            .padding(PCSpacing.l)
        }
    }

    private func violatedBanner(_ violation: Violation) -> some View {
        HStack(spacing: PCSpacing.m) {
            Image(systemName: violation.kind == .frost ? "snowflake" : "cloud.rain")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.dangerClay)
            Text(violation.kind == .frost
                 ? "Frost hit at h\(violation.cureHour) — inspect before loading."
                 : "Rain hit at h\(violation.cureHour) — check the surface finish.")
                .font(PCType.body.weight(.semibold))
                .foregroundStyle(Color.dangerClay)
            Spacer()
        }
        .padding(PCSpacing.m)
        .background(Color.dangerMuted, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                .strokeBorder(Color.dangerClay.opacity(0.4), lineWidth: 1)
        )
    }

    private var curedCard: some View {
        HStack {
            Spacer()
            Text("CURED")
                .font(PCType.title)
                .tracking(3)
                .foregroundStyle(Color.accentTeal)
                .padding(.horizontal, PCSpacing.l)
                .padding(.vertical, PCSpacing.s)
                .overlay(
                    RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                        .strokeBorder(Color.accentTeal, lineWidth: 2)
                )
                .rotationEffect(.degrees(-4))
            Spacer()
        }
        .padding(.vertical, PCSpacing.s)
    }

    private func riskRow(_ violation: Violation, happened: Bool) -> some View {
        HStack(alignment: .top, spacing: PCSpacing.m) {
            IconTile(
                systemName: violation.kind == .frost ? "snowflake" : "cloud.rain",
                tint: happened ? .dangerClay : .warningOchre,
                fill: happened ? .dangerMuted : .warningMuted
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(violation.kind == .frost ? "Frost" : "Rain")
                        .font(PCType.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(PCFormat.weekdayHour(violation.hour, calendar: calendar))
                        .font(PCType.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("h\(violation.cureHour)")
                        .font(PCType.mono)
                        .foregroundStyle(happened ? Color.dangerClay : Color.warningOchre)
                }
                Text(happened
                     ? (violation.kind == .frost ? "Hit during cure — inspect before loading." : "Hit during cure — check the finish.")
                     : (violation.kind == .frost
                        ? "\(PCFormat.temperature(violation.tempC, unit: settings.unit)) forecast — cover or heat before it lands."
                        : "Cover the surface before it lands."))
                    .font(PCType.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(PCSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pcTile()
    }

    @ViewBuilder
    private func conditionsNow(pour: Pour) -> some View {
        if let cache = forecast.caches[pour.siteID],
           let nowHour = cache.hours.min(by: {
               abs($0.date.timeIntervalSinceNow) < abs($1.date.timeIntervalSinceNow)
           }),
           abs(nowHour.date.timeIntervalSinceNow) < 2 * 3600 {
            VStack(alignment: .leading, spacing: PCSpacing.s) {
                Text("On site now")
                    .pcCapsLabel()
                    .padding(.leading, PCSpacing.xs)
                HStack(spacing: PCSpacing.l) {
                    Label(PCFormat.temperature(nowHour.tempC, unit: settings.unit), systemImage: "thermometer.medium")
                    Label("\(PCFormat.percent(nowHour.precipProb)) rain", systemImage: "cloud.rain")
                    Label(PCFormat.wind(nowHour.windKMH), systemImage: "wind")
                    Spacer()
                }
                .font(PCType.monoSmall)
                .foregroundStyle(Color.textSecondary)
                .padding(PCSpacing.m)
                .pcTile()
            }
        }
    }
}
