import SwiftUI

/// S4 — up to three sites. Add via city search or current location;
/// custom swipe delete; per-site next-best-window chip.
struct SitesView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var sites: SiteStore
    @EnvironmentObject private var forecast: ForecastStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var query = ""
    @State private var results: [GeocodedPlace] = []
    @State private var searching = false
    @State private var locating = false
    @State private var locationFailed = false

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PCSpacing.l) {
                if sites.sites.isEmpty {
                    emptyState
                } else {
                    siteList
                }
                if sites.canAdd {
                    addSection
                } else {
                    Text("Three sites is the crew limit — remove one to add another.")
                        .font(PCType.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(PCSpacing.l)
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Sites")
                    .font(PCType.navTitle)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    // MARK: - Empty state (formwork motif, never a cloud)

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: PCSpacing.m) {
            HStack {
                FormworkTile(systemName: "mappin")
                Spacer()
                FarmPropStrip(names: ["FarmProp-truck", "FarmProp-marker", "FarmProp-sign"], size: 42)
            }
            Text("Add your first site")
                .font(PCType.title)
                .foregroundStyle(Color.textPrimary)
            Text("PourCast computes pour windows per location — search a city below or use GPS.")
                .font(PCType.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pcCard()
    }

    // MARK: - Sites

    private var siteList: some View {
        VStack(spacing: PCSpacing.s) {
            ForEach(sites.sites) { site in
                SiteRow(
                    site: site,
                    selected: site.id == sites.selectedSiteID,
                    nextBest: forecast.nextBestBlock(for: site, defaults: settings.defaults),
                    calendar: calendar,
                    select: {
                        Haptics.selection()
                        sites.selectedSiteID = site.id
                    },
                    delete: {
                        Haptics.medium()
                        withAnimation(.pc) { sites.delete(site) }
                    }
                )
            }
        }
    }

    // MARK: - Add

    private var addSection: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            Text("Add site")
                .pcCapsLabel()
                .padding(.leading, PCSpacing.xs)

            HStack(spacing: PCSpacing.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                TextField("City or place", text: $query)
                    .font(PCType.body)
                    .foregroundStyle(Color.textPrimary)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(PCSpacing.m)
            .pcTile()

            if searching {
                Text("Searching…")
                    .font(PCType.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.leading, PCSpacing.xs)
            } else if !results.isEmpty {
                ForEach(results) { place in
                    Button {
                        add(place)
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentTeal)
                            Text(place.name)
                                .font(PCType.body)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(String(format: "%.2f, %.2f", place.lat, place.lon))
                                .font(PCType.monoSmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(PCSpacing.m)
                        .pcTile()
                    }
                    .buttonStyle(.pressable)
                }
            } else if !query.isEmpty && !searching && locationFailed {
                Text("No places matched — try the nearest town.")
                    .font(PCType.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.leading, PCSpacing.xs)
            }

            if !app.location.isDenied {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    HStack(spacing: PCSpacing.s) {
                        Image(systemName: "location")
                            .font(.system(size: 12, weight: .medium))
                        Text(locating ? "Locating…" : "Use current location")
                            .font(PCType.body.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentTeal)
                    .padding(PCSpacing.m)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentMuted, in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(locating)
            }
        }
    }

    // MARK: - Actions

    private func search() async {
        searching = true
        locationFailed = false
        results = await app.location.search(city: query)
        locationFailed = results.isEmpty
        searching = false
    }

    private func add(_ place: GeocodedPlace) {
        Haptics.medium()
        let site = Site(id: UUID(), name: place.name, lat: place.lat, lon: place.lon)
        withAnimation(.pc) {
            sites.add(site)
            query = ""
            results = []
        }
        Task { await app.refreshSite(site) }
    }

    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        do {
            let location = try await app.location.currentLocation()
            let name = await app.location.placeName(for: location)
            add(GeocodedPlace(
                name: name,
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude
            ))
        } catch {
            // Denied or unavailable — the search path stays; no nagging.
        }
    }
}

// MARK: - Site row with custom swipe delete

private struct SiteRow: View {
    let site: Site
    let selected: Bool
    let nextBest: (day: Date, block: BestBlock)?
    let calendar: Calendar
    let select: () -> Void
    let delete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var revealed = false

    private let revealWidth: CGFloat = 76

    var body: some View {
        ZStack(alignment: .trailing) {
            // The delete well behind the row — clay, square, no system red.
            Button(action: delete) {
                VStack(spacing: 2) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                    Text("Remove")
                        .font(PCType.footnote)
                }
                .foregroundStyle(Color.surfaceElevated)
                .frame(width: revealWidth - PCSpacing.s)
                .frame(maxHeight: .infinity)
                .background(Color.dangerClay, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
            }
            .buttonStyle(.pressable)
            .opacity(revealed ? 1 : 0)

            row
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base: CGFloat = revealed ? -revealWidth : 0
                            offset = min(0, max(-revealWidth - 12, base + value.translation.width))
                        }
                        .onEnded { value in
                            withAnimation(.pc) {
                                revealed = offset < -revealWidth / 2
                                offset = revealed ? -revealWidth : 0
                            }
                        }
                )
        }
        .animation(.pc, value: revealed)
    }

    private var row: some View {
        Button {
            if revealed {
                withAnimation(.pc) {
                    revealed = false
                    offset = 0
                }
            } else {
                select()
            }
        } label: {
            HStack(spacing: PCSpacing.m) {
                IconTile(
                    systemName: selected ? "mappin.circle.fill" : "mappin",
                    tint: selected ? .accentTeal : .textSecondary
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                        .font(PCType.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(Color.textPrimary)
                    Text(String(format: "%.3f, %.3f", site.lat, site.lon))
                        .font(PCType.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if let nextBest {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(PCFormat.dayLabel(nextBest.day, calendar: calendar).weekday)
                            .pcCapsLabel()
                        Text("\(PCFormat.hour(nextBest.block.start, calendar: calendar)) · \(nextBest.block.score)")
                            .font(PCType.monoSmall)
                            .foregroundStyle(nextBest.block.score >= 80 ? Color.accentTeal : Color.warningOchre)
                    }
                } else {
                    Text("No data")
                        .pcCapsLabel()
                }
            }
            .padding(PCSpacing.m)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                    .strokeBorder(selected ? Color.accentTeal.opacity(0.6) : Color.hairline, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(site.name)\(selected ? ", selected" : "")")
    }
}
