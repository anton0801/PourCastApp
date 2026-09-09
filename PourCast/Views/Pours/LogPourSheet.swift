import SwiftUI

/// S3 entry — start guarding a pour. Element / mix / protection tiles,
/// start time, site. Saving arms the 48h Cure Watch.
struct LogPourSheet: View {
    let plannedStart: Date?

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var sites: SiteStore
    @EnvironmentObject private var forecast: ForecastStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var element: ElementType = .slab
    @State private var mix: MixType = .standard
    @State private var protection: ProtectionType = .none
    @State private var start = Date()
    @State private var siteID: UUID?
    @State private var loaded = false

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PCSpacing.l) {
                    SegmentTileGroup(title: "Element", options: ElementType.allCases, selection: $element)
                    SegmentTileGroup(title: "Mix", options: MixType.allCases, selection: $mix)
                    SegmentTileGroup(title: "Protection", options: ProtectionType.allCases, selection: $protection)

                    VStack(alignment: .leading, spacing: PCSpacing.s) {
                        Text("Pour start")
                            .pcCapsLabel()
                        DatePicker(
                            "Pour start",
                            selection: $start,
                            in: Date().addingTimeInterval(-48 * 3600)...Date().addingTimeInterval(7 * 86_400),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(.accentTeal)
                        .padding(PCSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pcTile()
                    }

                    if sites.sites.count > 1 {
                        VStack(alignment: .leading, spacing: PCSpacing.s) {
                            Text("Site")
                                .pcCapsLabel()
                            ForEach(sites.sites) { site in
                                siteRow(site)
                            }
                        }
                    }

                    if forecast.isStale(siteID ?? sites.selectedSiteID) {
                        HStack(spacing: PCSpacing.s) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 12, weight: .medium))
                            Text("Forecast is stale — verdicts will update on the next refresh.")
                                .font(PCType.footnote)
                        }
                        .foregroundStyle(Color.warningOchre)
                        .padding(PCSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.warningMuted, in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous))
                    }

                    Button("Start cure watch") {
                        save()
                    }
                    .buttonStyle(.pcPrimary)
                    .disabled(siteID == nil && sites.selectedSiteID == nil)
                }
                .padding(PCSpacing.l)
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("Log pour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.accentTeal)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            element = settings.defaults.element
            mix = settings.defaults.mix
            protection = settings.defaults.protection
            siteID = sites.selectedSiteID
            if let plannedStart {
                start = plannedStart
            }
        }
    }

    private func siteRow(_ site: Site) -> some View {
        let selected = (siteID ?? sites.selectedSiteID) == site.id
        return Button {
            Haptics.selection()
            siteID = site.id
        } label: {
            HStack {
                Image(systemName: "mappin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Color.accentTeal : Color.textSecondary)
                Text(site.name)
                    .font(PCType.body)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentTeal)
                }
            }
            .padding(PCSpacing.m)
            .background(
                selected ? Color.accentMuted : Color.surfaceElevated,
                in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                    .strokeBorder(selected ? Color.accentTeal : Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
    }

    private func save() {
        guard let resolvedSite = siteID ?? sites.selectedSiteID else { return }
        let pour = Pour(
            siteID: resolvedSite,
            start: start,
            element: element,
            mix: mix,
            protection: protection
        )
        Haptics.medium()
        dismiss()
        Task { await app.logPour(pour) }
    }
}
