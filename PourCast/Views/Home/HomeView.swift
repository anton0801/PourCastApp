import SwiftUI

enum Route: Hashable {
    case day(Date)
    case cureWatch(UUID)
    case sites
    case settings
    case pourSetup
}

/// S1 — the verdict timeline. One vertical scroll: hero → 7 day rows →
/// cure watch → footer. No tab bar; everything else pushes from here.
struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var forecast: ForecastStore
    @EnvironmentObject private var sites: SiteStore
    @EnvironmentObject private var pourStore: PourStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var path = NavigationPath()
    @State private var showLogPour = false
    @State private var selectedDayID: Date?
    @State private var pullProgress: Double = 0
    @State private var pullArmed = false
    @AppStorage("pc.lastHeroVerdict") private var lastHeroVerdict = ""

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if sizeClass == .regular {
                    twoColumn
                } else {
                    timeline
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PourCast")
                        .font(PCType.navWordmark)
                        .tracking(-0.3)
                        .foregroundStyle(Color.textPrimary)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        path.append(Route.sites)
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .accessibilityLabel("Sites")
                    Button {
                        path.append(Route.settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
        }
        .tint(.accentTeal)
        .sheet(isPresented: $showLogPour) {
            LogPourSheet(plannedStart: nil)
        }
        .task {
            #if DEBUG
            handleDebugRoute()
            #endif
            await app.refreshIfStale()
            syncHeroHaptic()
        }
    }

    #if DEBUG
    /// Screenshot/QA hook: SIMCTL_CHILD_PC_ROUTE=day2 etc. Debug builds only.
    private func handleDebugRoute() {
        switch ProcessInfo.processInfo.environment["PC_ROUTE"] {
        case "today":
            if let today = forecast.week.first { path.append(Route.day(today.id)) }
        case "day2":
            if forecast.week.count > 1 { path.append(Route.day(forecast.week[1].id)) }
        case "sites":
            path.append(Route.sites)
        case "settings":
            path.append(Route.settings)
        case "setup":
            path.append(Route.pourSetup)
        case "logpour":
            showLogPour = true
        case "cure":
            if let pour = pourStore.pours.first { path.append(Route.cureWatch(pour.id)) }
        default:
            break
        }
    }
    #endif

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .day(let id):
            WindowDetailView(dayID: id)
        case .cureWatch(let id):
            CureWatchView(pourID: id)
        case .sites:
            SitesView()
        case .settings:
            SettingsView()
        case .pourSetup:
            PourSetupView()
        }
    }

    // MARK: - iPad: timeline left, inline detail right

    private var twoColumn: some View {
        HStack(spacing: 0) {
            timeline
                .frame(width: 420)
            Rectangle()
                .fill(Color.hairline)
                .frame(width: 1)
                .ignoresSafeArea(edges: .vertical)
            detailPane
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedDayID, forecast.week.contains(where: { $0.id == id }) {
            WindowDetailView(dayID: id)
                .id(id)
        } else {
            VStack(spacing: PCSpacing.m) {
                FormworkOutline()
                    .frame(height: 64)
                Text("Select a day to see the proof")
                    .font(PCType.body)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - The timeline scroll

    private var timeline: some View {
        ScrollView {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PullOffsetKey.self,
                    value: geo.frame(in: .named("home")).minY
                )
            }
            .frame(height: 0)

            VStack(alignment: .leading, spacing: PCSpacing.l) {
                sections
            }
            .padding(.horizontal, PCSpacing.l)
            .padding(.top, PCSpacing.s)
            .padding(.bottom, PCSpacing.xl)
        }
        .coordinateSpace(name: "home")
        .onPreferenceChange(PullOffsetKey.self, perform: handlePull)
        .overlay(alignment: .top) {
            if forecast.isRefreshing || pullProgress > 0.08 {
                RefreshTicks(progress: pullProgress, spinning: forecast.isRefreshing)
                    .padding(.top, PCSpacing.xs)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        if sites.selected == nil {
            NoSiteCard { path.append(Route.sites) }
        } else if forecast.week.isEmpty {
            if let error = forecast.lastError, !forecast.isRefreshing {
                ErrorCard(
                    error: error,
                    retry: { Task { await refreshNow() } },
                    openSettings: { path.append(Route.settings) }
                )
            } else {
                SkeletonHome()
            }
        } else {
            if let error = forecast.lastError {
                ErrorBanner(
                    error: error,
                    retry: { Task { await refreshNow() } },
                    openSettings: { path.append(Route.settings) }
                )
            }
            heroSection
            weekSection
            cureSection
            footer
        }
    }

    // MARK: - Hero

    private struct Hero {
        let verdict: VerdictClass
        let reason: String
        let score: Int?
    }

    private var hero: Hero? {
        let week = forecast.week
        guard let today = week.first else { return nil }

        if let best = today.candidates.max(by: { $0.score < $1.score }) {
            switch best.verdict {
            case .go:
                let block = today.best.map { PCFormat.hourRange($0.start, $0.end, calendar: calendar) }
                    ?? PCFormat.hour(best.start, calendar: calendar)
                return Hero(verdict: .go, reason: "Best window \(block). Conditions hold through the 48h cure.", score: best.score)
            case .caution, .noGo:
                if let top = best.penalties.filter({ $0.points > 0 }).max(by: { $0.points < $1.points }) {
                    let when = top.hour.map { " \(PCFormat.weekdayHour($0, calendar: calendar))" } ?? ""
                    return Hero(verdict: best.verdict, reason: "\(top.title)\(when) · −\(top.points). Tap for the breakdown.", score: best.score)
                }
                return Hero(verdict: best.verdict, reason: "Cure extends past the forecast — tap for the breakdown.", score: best.score)
            }
        }

        // Workday over (or no candidates today) — point at the next window.
        if let next = week.dropFirst().compactMap({ day in day.best.map { (day, $0) } }).first {
            let (day, block) = next
            let weekday = PCFormat.dayLabel(day.day, calendar: calendar).weekday
            let verdict: VerdictClass = block.score >= 80 ? .go : (block.score >= 50 ? .caution : .noGo)
            return Hero(
                verdict: verdict,
                reason: "Workday over. Next window \(weekday) \(PCFormat.hourRange(block.start, block.end, calendar: calendar)) · \(block.score).",
                score: nil
            )
        }

        // Extreme climate: everything NO-GO — name the dominant cause.
        return Hero(verdict: .noGo, reason: dominantCauseLine(week: week), score: nil)
    }

    private func dominantCauseLine(week: [DayVerdicts]) -> String {
        var pointsByKind: [Penalty.Kind: Int] = [:]
        for day in week {
            for candidate in day.candidates {
                for penalty in candidate.penalties where penalty.points > 0 {
                    pointsByKind[penalty.kind, default: 0] += penalty.points
                }
            }
        }
        guard let dominant = pointsByKind.max(by: { $0.value < $1.value }) else {
            return "No workable window in the next 7 days."
        }
        let cause: String
        switch dominant.key {
        case .frost, .tempHardFail: cause = "cold"
        case .rain: cause = "rain"
        case .hotWindy: cause = "heat and wind"
        case .marginalCold: cause = "marginal cold"
        case .horizon: cause = "the short forecast"
        }
        return "No workable window this week — \(cause) rules out every day. Least-bad blocks still shown below."
    }

    @ViewBuilder
    private var heroSection: some View {
        if let hero {
            Button {
                openToday()
            } label: {
                ZStack(alignment: .topTrailing) {
                    VerdictCard(
                        title: heroTitle,
                        verdict: hero.verdict,
                        reason: hero.reason,
                        score: hero.score,
                        staleLine: forecast.isVeryStale(sites.selectedSiteID)
                            ? "Verdicts based on old data — pull to refresh." : nil
                    )
                    FarmPropStrip(
                        names: ["FarmProp-chicken", "FarmProp-birds", "FarmProp-barn", "FarmProp-hay"],
                        size: 30
                    )
                    .padding(PCSpacing.s)
                }
            }
            .buttonStyle(.pressable)
            .animation(.pc, value: hero.verdict)
        }
    }

    private var heroTitle: String {
        let label = PCFormat.dayLabel(Date(), calendar: calendar)
        return "Today · \(label.weekday) \(label.day)"
    }

    // MARK: - Week

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            Text("This week")
                .pcCapsLabel()
                .padding(.leading, PCSpacing.xs)

            HStack(alignment: .top, spacing: PCSpacing.xs) {
                TickRuler()
                VStack(spacing: PCSpacing.s) {
                    ForEach(Array(forecast.week.enumerated()), id: \.element.id) { index, day in
                        Button {
                            open(day: day)
                        } label: {
                            DayRow(day: day, calendar: calendar)
                        }
                        .buttonStyle(.pressable)
                        .staggerIn(index: index)
                    }
                }
            }
        }
    }

    // MARK: - Cure watch

    private var cureSection: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            HStack {
                Text("Cure watch")
                    .pcCapsLabel()
                Spacer()
                if !pourStore.active.isEmpty || !pourStore.history.isEmpty {
                    Button {
                        showLogPour = true
                    } label: {
                        HStack(spacing: PCSpacing.xs) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Log pour")
                                .font(PCType.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentTeal)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, PCSpacing.xs)

            if pourStore.active.isEmpty && pourStore.history.isEmpty {
                EmptyPoursCard { showLogPour = true }
            } else {
                ForEach(pourStore.active) { pour in
                    Button {
                        path.append(Route.cureWatch(pour.id))
                    } label: {
                        activeCard(for: pour)
                    }
                    .buttonStyle(.pressable)
                }
                ForEach(pourStore.history.prefix(2)) { pour in
                    Button {
                        path.append(Route.cureWatch(pour.id))
                    } label: {
                        activeCard(for: pour)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private func activeCard(for pour: Pour) -> some View {
        ActivePourCard(
            pour: pour,
            siteName: sites.sites.first { $0.id == pour.siteID }?.name ?? "Site",
            risks: pourStore.upcomingRisks(for: pour, caches: forecast.caches),
            calendar: calendar,
            celebrate: { pourStore.markCelebrated(pour) }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            HStack {
                Button {
                    path.append(Route.sites)
                } label: {
                    HStack(spacing: PCSpacing.xs) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10, weight: .medium))
                        Text(sites.selected?.name ?? "Site")
                            .pcCapsLabel(.textPrimary)
                    }
                }
                .buttonStyle(.pressable)
                Spacer()
                AgeBadge(fetchedAt: forecast.cache(for: sites.selectedSiteID)?.fetchedAt)
            }
            Text(settings.weatherSource == .weatherKit ? "\u{F8FF} Weather" : "Weather data by OpenWeatherMap")
                .font(PCType.footnote)
                .foregroundStyle(Color.textSecondary)
            FarmPropStrip(names: ["FarmProp-wheat", "FarmProp-fence"], size: 26)
        }
        .padding(.top, PCSpacing.s)
    }

    // MARK: - Actions

    private func open(day: DayVerdicts) {
        if sizeClass == .regular {
            withAnimation(.pc) { selectedDayID = day.id }
        } else {
            path.append(Route.day(day.id))
        }
    }

    private func openToday() {
        if let today = forecast.week.first {
            open(day: today)
        }
    }

    private func refreshNow() async {
        let changed = await refreshAndReportChange()
        if changed { Haptics.medium() }
    }

    private func handlePull(_ offset: CGFloat) {
        pullProgress = max(0, min(Double(offset) / 80, 1))
        guard sites.selected != nil else { return }

        if offset > 80, !forecast.isRefreshing, !pullArmed {
            pullArmed = true
            Task { await pullRefresh() }
        } else if offset < 10 {
            pullArmed = false
        }
    }

    private func pullRefresh() async {
        let changed = await refreshAndReportChange()
        // Refresh success → light; verdict flip → medium.
        if changed {
            Haptics.medium()
        } else if forecast.lastError == nil {
            Haptics.light()
        }
    }

    /// Refreshes and returns whether the hero verdict changed.
    private func refreshAndReportChange() async -> Bool {
        let before = hero?.verdict.rawValue ?? ""
        await app.refresh()
        let after = hero?.verdict.rawValue ?? ""
        lastHeroVerdict = after
        return !before.isEmpty && before != after
    }

    /// Cold open: medium haptic if the verdict moved since last session.
    private func syncHeroHaptic() {
        let word = hero?.verdict.rawValue ?? ""
        if !lastHeroVerdict.isEmpty, !word.isEmpty, word != lastHeroVerdict {
            Haptics.medium()
        }
        if !word.isEmpty { lastHeroVerdict = word }
    }
}

private struct PullOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
