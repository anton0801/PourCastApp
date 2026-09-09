import SwiftUI

/// S6 — units, notifications, theme, attribution, export, about.
/// Every control is live; nothing decorative.
struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sites: SiteStore
    @EnvironmentObject private var pourStore: PourStore
    @EnvironmentObject private var forecast: ForecastStore

    @State private var exportURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PCSpacing.l) {
                defaultsLink

                SegmentTileGroup(title: "Units", options: TemperatureUnit.allCases, selection: $settings.unit)
                SegmentTileGroup(title: "Theme", options: AppTheme.allCases, selection: $settings.theme)

                notificationSection
                dataSection
                attributionSection
                aboutSection
            }
            .padding(PCSpacing.l)
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(PCType.navTitle)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    // MARK: - Pour defaults (S5) entry

    private var defaultsLink: some View {
        NavigationLink(value: Route.pourSetup) {
            HStack(spacing: PCSpacing.m) {
                IconTile(systemName: "slider.horizontal.3")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pour setup")
                        .font(PCType.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(settings.defaults.element.label) · \(settings.defaults.mix.label) · \(settings.defaults.protection.shortLabel.lowercased()) · \(String(format: "%02d–%02d", settings.defaults.workday.start, settings.defaults.workday.end))")
                        .font(PCType.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(PCSpacing.m)
            .pcTile()
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            Text("Notifications")
                .pcCapsLabel()
                .padding(.leading, PCSpacing.xs)

            VStack(spacing: 0) {
                toggleRow(
                    "Window opens tomorrow",
                    detail: "Evening heads-up when tomorrow has a GO block of 4h or more.",
                    isOn: $settings.notifyWindowTomorrow
                )
                Rectangle().fill(Color.hairline).frame(height: 1)
                toggleRow(
                    "Risk enters a cure",
                    detail: "Immediate alert when new frost or rain lands inside a guarded 48h window.",
                    isOn: $settings.notifyFrostCure
                )
            }
            .pcTile()
        }
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { value in
                isOn.wrappedValue = value
                Haptics.selection()
                Task {
                    if value { await app.planner.ensurePermission() }
                    await app.replan()
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PCType.body)
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(PCType.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .tint(.accentTeal)
        .padding(PCSpacing.m)
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            Text("Data")
                .pcCapsLabel()
                .padding(.leading, PCSpacing.xs)

            Group {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        exportLabel(ready: true)
                    }
                } else {
                    Button {
                        Haptics.selection()
                        exportURL = Persistence.shared.exportAll(
                            sites: sites.sites,
                            pours: pourStore.pours,
                            caches: Array(forecast.caches.values),
                            defaults: settings.defaults
                        )
                    } label: {
                        exportLabel(ready: false)
                    }
                }
            }
            .buttonStyle(.pressable)

            Text("Everything stays on this phone — sites, pours and the cached forecast. Export is a plain JSON file.")
                .font(PCType.footnote)
                .foregroundStyle(Color.textSecondary)
                .padding(.leading, PCSpacing.xs)
        }
    }

    private func exportLabel(ready: Bool) -> some View {
        HStack(spacing: PCSpacing.m) {
            IconTile(systemName: ready ? "checkmark.circle" : "square.and.arrow.up")
            Text(ready ? "Share PourCast-export.json" : "Export data as JSON")
                .font(PCType.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .padding(PCSpacing.m)
        .pcTile()
    }

    // MARK: - Weather source (provider choice + attribution)

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            SegmentTileGroup(
                title: "Weather source",
                options: WeatherSource.allCases,
                selection: $settings.weatherSource
            )

            if settings.weatherSource == .openWeatherMap {
                linkRow(
                    url: "https://openweathermap.org",
                    symbol: "cloud",
                    title: "OpenWeatherMap",
                    subtitle: "Weather data by OpenWeatherMap."
                )
            } else {
                linkRow(
                    url: "https://weatherkit.apple.com/legal-attribution.html",
                    symbol: "cloud",
                    title: "\u{F8FF} Weather",
                    subtitle: "Forecasts by Apple Weather. Legal attribution."
                )
                Text("Apple Weather needs this app's Apple provisioning — if forecasts fail, switch back to OpenWeatherMap.")
                    .font(PCType.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.leading, PCSpacing.xs)
            }
        }
    }

    private func linkRow(url: String, symbol: String, title: String, subtitle: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: PCSpacing.m) {
                IconTile(systemName: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PCType.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(PCType.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(PCSpacing.m)
            .pcTile()
        }
        .buttonStyle(.pressable)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            Text("About")
                .pcCapsLabel()
                .padding(.leading, PCSpacing.xs)

            VStack(alignment: .leading, spacing: PCSpacing.m) {
                HStack {
                    Text("PourCast")
                        .font(PCType.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(appVersion)
                        .font(PCType.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                Text("Scores every pour hour of the coming week against your mix and element, then guards each pour through its first 48 hours.")
                    .font(PCType.footnote)
                    .foregroundStyle(Color.textSecondary)
                Rectangle().fill(Color.hairline).frame(height: 1)
                Text("Guidance, not engineering advice — follow your mix supplier's specification.")
                    .font(PCType.footnote.italic())
                    .foregroundStyle(Color.textSecondary)
                Text(settings.weatherSource == .weatherKit ? "\u{F8FF} Weather" : "Weather data by OpenWeatherMap")
                    .font(PCType.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(PCSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pcTile()
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }
}
