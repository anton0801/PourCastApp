import SwiftUI
import Charts

// The four walkthrough scenes: live miniatures assembled from the app's real
// components and the real WindowEngine. All values here are presentation
// content local to these views — nothing is written to any store.

// MARK: - Shared scaffold

private struct SceneScaffold<Stage: View>: View {
    let kicker: String
    let title: String
    let caption: String
    @ViewBuilder let stage: () -> Stage

    var body: some View {
        VStack(alignment: .leading, spacing: PCSpacing.l) {
            VStack(alignment: .leading, spacing: PCSpacing.xs) {
                Text(kicker)
                    .pcCapsLabel()
                Text(title)
                    .font(PCType.title)
                    .foregroundStyle(Color.textPrimary)
            }
            stage()
            Text(caption)
                .font(PCType.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, PCSpacing.s)
    }
}

// MARK: - Scene 1: Verdicts, not weather (interactive frost drag)

struct SceneVerdictFlip: View {
    let active: Bool

    @State private var frostGone = false
    @State private var markerDrag: CGSize = .zero
    @State private var markerFlying = false

    private let calendar = Calendar.current
    private let anchor: Date
    private let clearHours: [HourF]
    private let coldHours: [HourF]

    init(active: Bool) {
        self.active = active
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        anchor = start

        var clear: [HourF] = []
        var cold: [HourF] = []
        for i in 0..<(6 * 24) {
            let date = start.addingTimeInterval(Double(i) * 3600)
            let hourOfDay = Double(i % 24)
            let temp = 16 + 5 * sin((hourOfDay - 9) / 24 * 2 * .pi)
            clear.append(HourF(date: date, tempC: temp, precipProb: 5, precipMM: 0, windKMH: 10, humidity: 55))
            // The frost night: day+2, 01:00–05:00.
            let isFrostHour = (i / 24 == 2) && (1...5).contains(i % 24)
            cold.append(HourF(date: date, tempC: isFrostHour ? -3 : temp, precipProb: 5, precipMM: 0, windKMH: 10, humidity: 55))
        }
        clearHours = clear
        coldHours = cold
    }

    private var week: [DayVerdicts] {
        WindowEngine.week(
            hours: frostGone ? clearHours : coldHours,
            defaults: .initial,
            now: anchor,
            calendar: calendar
        )
    }

    var body: some View {
        let week = self.week
        let focus = week.count > 1 ? week[1] : week[0]
        let best = focus.candidates.max { $0.score < $1.score }

        SceneScaffold(
            kicker: "Verdicts, not weather",
            title: "Frost kills pours you can't see",
            caption: "PourCast reads the forecast and tells you when concrete is safe to pour."
        ) {
            VStack(alignment: .leading, spacing: PCSpacing.m) {
                VerdictCard(
                    title: PCFormat.dayLabel(focus.day, calendar: calendar).weekday,
                    verdict: best?.verdict ?? .noGo,
                    reason: frostGone
                        ? "Clean pour, clean 48h cure. Book the truck."
                        : "Frost enters the cure two nights out — −60.",
                    score: best?.score,
                    staleLine: nil
                )

                ZStack(alignment: .topLeading) {
                    VStack(spacing: PCSpacing.s) {
                        ForEach(Array(week.dropFirst().prefix(3).enumerated()), id: \.element.id) { index, day in
                            DayRow(day: day, calendar: calendar, collapseChip: true)
                                .staggerIn(index: index)
                        }
                    }

                    if !markerFlying {
                        frostMarker
                    }
                }

                HStack(spacing: PCSpacing.xs) {
                    Image(systemName: frostGone ? "arrow.uturn.backward" : "hand.draw")
                        .font(.system(size: 10, weight: .medium))
                    if frostGone {
                        Button("Put the frost back") { restoreFrost() }
                            .buttonStyle(.pressable)
                            .font(PCType.footnote.weight(.semibold))
                            .foregroundStyle(Color.accentTeal)
                    } else {
                        Text("Drag the frost off the week")
                            .font(PCType.footnote)
                    }
                }
                .foregroundStyle(Color.textSecondary)
            }
            .animation(.pc, value: frostGone)
        }
    }

    /// Sits over the frost night on the second visible row.
    private var frostMarker: some View {
        GeometryReader { geo in
            let rowHeight: CGFloat = 58
            let barStart: CGFloat = 40 + PCSpacing.m
            let barWidth = geo.size.width - barStart - 54 - PCSpacing.m
            IconTile(systemName: "snowflake", tint: .dangerClay, fill: .dangerMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                        .strokeBorder(Color.dangerClay.opacity(0.5), lineWidth: 1)
                )
                .offset(
                    x: barStart + barWidth * 0.13 + markerDrag.width,
                    y: rowHeight + PCSpacing.s + 14 + markerDrag.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            markerDrag = value.translation
                        }
                        .onEnded { value in
                            let distance = hypot(value.translation.width, value.translation.height)
                            if distance > 60 {
                                Haptics.medium()
                                withAnimation(.pc) {
                                    markerFlying = true
                                    frostGone = true
                                }
                            } else {
                                withAnimation(.pc) { markerDrag = .zero }
                            }
                        }
                )
                .accessibilityLabel("Frost marker. Drag away to remove frost from the forecast.")
        }
        .frame(height: 0)
    }

    private func restoreFrost() {
        Haptics.selection()
        markerDrag = .zero
        withAnimation(.pc) {
            markerFlying = false
            frostGone = false
        }
    }
}

// MARK: - Scene 2: Proof, one tap deep (chart draw-in + scrub)

struct SceneChartProof: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clockStart: Date?
    @State private var userScrub: Date?

    private let calendar = Calendar.current
    private let anchor: Date
    private let hours: [HourF]
    private let penalties: [Penalty]

    init(active: Bool) {
        self.active = active
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        anchor = start

        var series: [HourF] = []
        for i in 0..<30 {
            let date = start.addingTimeInterval(Double(i) * 3600)
            var temp = 14 + 7 * sin((Double(i) - 9) / 24 * 2 * .pi)
            let rainy = (13...16).contains(i)
            if (4...6).contains(i) { temp = 3 }
            series.append(HourF(
                date: date,
                tempC: temp,
                precipProb: rainy ? 80 : 5,
                precipMM: rainy ? 1.6 : 0,
                windKMH: 12,
                humidity: 60
            ))
        }
        hours = series
        penalties = [
            Penalty(kind: .rain, hour: start.addingTimeInterval(14 * 3600), points: 40),
            Penalty(kind: .marginalCold, hour: start.addingTimeInterval(5 * 3600), points: 10, tempC: 3),
        ]
    }

    var body: some View {
        SceneScaffold(
            kicker: "Proof, one tap deep",
            title: "Every verdict shows its hours",
            caption: "Every verdict is backed by the hours that caused it — scrub the chart and the penalty lights up."
        ) {
            TimelineView(.animation(paused: !active)) { timeline in
                let elapsed = clockStart.map { timeline.date.timeIntervalSince($0) } ?? 0
                stage(elapsed: elapsed)
            }
            .onChange(of: active) { isActive in
                if isActive, clockStart == nil { clockStart = Date() }
            }
            .onAppear {
                if active, clockStart == nil { clockStart = Date() }
            }
        }
    }

    private func scrubDate(elapsed: Double) -> Date? {
        if let userScrub { return userScrub }
        guard !reduceMotion else { return nil }
        // Auto-sweep once after the draw-in, coming to rest on the rain hour.
        guard elapsed > 1.1 else { return nil }
        let f = min((elapsed - 1.1) / 1.6, 1)
        let index = Int((f * 14).rounded())
        return anchor.addingTimeInterval(Double(index) * 3600)
    }

    @ViewBuilder
    private func stage(elapsed: Double) -> some View {
        let drawProgress: CGFloat = reduceMotion ? 1 : CGFloat(min(elapsed / 0.9, 1))
        let scrub = scrubDate(elapsed: elapsed)

        VStack(alignment: .leading, spacing: PCSpacing.m) {
            readout(scrub: scrub)

            HStack(alignment: .top, spacing: PCSpacing.xs) {
                TickRuler()
                    .frame(height: 150)
                chart(scrub: scrub)
                    .frame(height: 150)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(width: geo.size.width * drawProgress)
                        }
                    }
            }
            .padding(PCSpacing.m)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )

            ForEach(penalties) { penalty in
                Button {
                    Haptics.selection()
                    withAnimation(.pc) { userScrub = penalty.hour }
                } label: {
                    PenaltyRow(penalty: penalty, unit: .celsius, calendar: calendar)
                        .overlay(
                            RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                                .strokeBorder(
                                    scrub == penalty.hour ? Color.accentTeal : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                }
                .buttonStyle(.pressable)
            }
            .animation(.pc, value: scrub)
        }
    }

    private func readout(scrub: Date?) -> some View {
        HStack(spacing: PCSpacing.m) {
            if let scrub, let hour = hours.first(where: { $0.date == scrub }) {
                Text(PCFormat.hour(hour.date, calendar: calendar))
                    .font(PCType.mono)
                    .foregroundStyle(Color.textPrimary)
                Label(PCFormat.temperature(hour.tempC, unit: .celsius), systemImage: "thermometer.medium")
                Label("\(PCFormat.percent(hour.precipProb)) · \(PCFormat.precip(hour.precipMM))", systemImage: "cloud.rain")
                Spacer()
                if let penalty = penalties.first(where: { $0.hour == scrub }) {
                    Text("−\(penalty.points)")
                        .font(PCType.mono)
                        .foregroundStyle(Color.dangerClay)
                }
            } else {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12, weight: .medium))
                Text("Drag across the chart")
                    .font(PCType.footnote)
                Spacer()
            }
        }
        .font(PCType.monoSmall)
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, PCSpacing.m)
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pcTile()
        .animation(.pc, value: scrub)
    }

    private func chart(scrub: Date?) -> some View {
        let tempLow = (hours.map(\.tempC).min() ?? 0) - 2
        let tempSpan = max((hours.map(\.tempC).max() ?? 20) + 2 - tempLow, 1)

        return Chart {
            ForEach(hours, id: \.date) { hour in
                BarMark(
                    x: .value("Hour", hour.date),
                    y: .value("Precip", hour.precipMM / 2 * 0.3),
                    width: .fixed(4)
                )
                .foregroundStyle(Color.warningOchre.opacity(0.75))
            }
            ForEach(hours, id: \.date) { hour in
                LineMark(
                    x: .value("Hour", hour.date),
                    y: .value("Temp", 0.32 + (hour.tempC - tempLow) / tempSpan * 0.68)
                )
                .foregroundStyle(Color.accentTeal)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            ForEach(penalties) { penalty in
                RuleMark(x: .value("Penalty", penalty.hour!))
                    .foregroundStyle(Color.dangerClay.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, spacing: 2) {
                        Image(systemName: penalty.symbol)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.dangerClay)
                    }
            }
            if let scrub {
                RuleMark(x: .value("Scrub", scrub))
                    .foregroundStyle(Color.textPrimary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1.05)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(PCFormat.hour(date, calendar: calendar))
                            .font(PCType.monoSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - geo[proxy.plotAreaFrame].minX
                                guard let date: Date = proxy.value(atX: x) else { return }
                                var components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                                components.minute = 0
                                guard let snapped = calendar.date(from: components),
                                      hours.contains(where: { $0.date == snapped })
                                else { return }
                                if snapped != userScrub {
                                    userScrub = snapped
                                    Haptics.selection()
                                }
                            }
                    )
            }
        }
    }
}

// MARK: - Scene 3: Guarded for 48 hours (scripted cure watch)

struct SceneCureGuard: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clockStart: Date?
    @State private var hapticsTask: Task<Void, Never>?

    private let anchor: Date
    private let watchedPour: Pour
    private let frostRisk: Violation

    /// Script: the 48h rail fills over this many seconds.
    private let fillDuration: Double = 3.4

    init(active: Bool) {
        self.active = active
        var calendar = Calendar.current
        calendar.timeZone = .current
        let start = calendar.date(bySetting: .minute, value: 0, of: Date()) ?? Date()
        anchor = start
        // Local to this scene — never persisted, never in any store.
        watchedPour = Pour(
            siteID: UUID(),
            start: start,
            element: .slab,
            mix: .standard,
            protection: .covering
        )
        frostRisk = Violation(
            kind: .frost,
            hour: start.addingTimeInterval(31 * 3600),
            cureHour: 31,
            tempC: -3
        )
    }

    var body: some View {
        SceneScaffold(
            kicker: "Guarded for 48 hours",
            title: "The pour isn't done when the truck leaves",
            caption: "Log a pour and PourCast watches its cure — new risks in the forecast become alerts before they land."
        ) {
            TimelineView(.animation(paused: !active || reduceMotion)) { timeline in
                let elapsed = clockStart.map { timeline.date.timeIntervalSince($0) } ?? 0
                stage(elapsed: reduceMotion ? fillDuration + 1 : elapsed)
            }
            .onChange(of: active) { isActive in
                if isActive { startScript() } else { stopScript() }
            }
            .onAppear {
                if active { startScript() }
            }
            .onDisappear { stopScript() }
        }
    }

    @ViewBuilder
    private func stage(elapsed: Double) -> some View {
        let filledHours = min(elapsed / fillDuration, 1) * 48
        let pinShown = filledHours >= 31
        let cured = filledHours >= 48

        VStack(alignment: .leading, spacing: PCSpacing.m) {
            MiniNotificationBanner(
                title: "Frost forecast — cover the slab tonight",
                shown: pinShown
            )

            ZStack {
                VStack(alignment: .leading, spacing: PCSpacing.s) {
                    HStack {
                        IconTile(systemName: watchedPour.element.symbol)
                        Text("Slab · logged at pour time")
                            .font(PCType.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("h\(Int(filledHours))")
                            .font(PCType.mono)
                            .foregroundStyle(Color.textSecondary)
                    }
                    ProgressRail(
                        pour: watchedPour,
                        risks: pinShown ? [frostRisk] : [],
                        elapsedHoursOverride: filledHours
                    )
                }
                .pcCard()

                stamp(cured: cured)
            }
        }
        .animation(.pc, value: pinShown)
    }

    @ViewBuilder
    private func stamp(cured: Bool) -> some View {
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
            .background(Color.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous))
            .rotationEffect(.degrees(-4))
            .scaleEffect(reduceMotion ? 1 : (cured ? 1 : 1.3))
            .opacity(cured ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.25) : .pc, value: cured)
    }

    /// Haptics ride the same script timeline; the Task dies with the scene.
    private func startScript() {
        guard clockStart == nil else { return }
        clockStart = Date()
        guard !reduceMotion else { return }
        hapticsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(fillDuration / 48 * 31 * 1_000_000_000))
            guard !Task.isCancelled else { return }
            Haptics.warning()
            try? await Task.sleep(nanoseconds: UInt64(fillDuration / 48 * 17 * 1_000_000_000))
            guard !Task.isCancelled else { return }
            Haptics.success()
        }
    }

    private func stopScript() {
        hapticsTask?.cancel()
        hapticsTask = nil
    }
}

/// A notification, in miniature — slides in from the top of the scene.
struct MiniNotificationBanner: View {
    let title: String
    let shown: Bool

    var body: some View {
        HStack(spacing: PCSpacing.m) {
            IconTile(systemName: "snowflake", tint: .dangerClay, fill: .dangerMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text("PourCast · now")
                    .pcCapsLabel()
                Text(title)
                    .font(PCType.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
        }
        .padding(PCSpacing.m)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .offset(y: shown ? 0 : -24)
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(!shown)
    }
}

// MARK: - Scene 4: Set up your crew (the consequential questions)

struct SceneCrewSetup: View {
    let active: Bool
    let done: () -> Void

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sites: SiteStore

    @State private var element: ElementType = .slab
    @State private var mix: MixType = .standard
    @State private var protection: ProtectionType = .none
    @State private var step = 0
    @State private var seeded = false
    @State private var locating = false
    @State private var searchShown = false
    @State private var query = ""
    @State private var results: [GeocodedPlace] = []
    @State private var searchFailed = false

    var body: some View {
        SceneScaffold(
            kicker: "Set up your crew",
            title: "Three answers tune every verdict",
            caption: "Change any of these later in Pour setup — verdicts recompute instantly."
        ) {
            VStack(alignment: .leading, spacing: PCSpacing.l) {
                ruleCard

                SegmentTileGroup(title: "What do you pour most?", options: ElementType.allCases, selection: $element) {
                    advance(past: 0)
                }
                if step >= 1 {
                    SegmentTileGroup(title: "Which mix?", options: MixType.allCases, selection: $mix) {
                        advance(past: 1)
                    }
                    .transition(.opacity.combined(with: .offset(y: 12)))
                }
                if step >= 2 {
                    SegmentTileGroup(title: "Can you cover it?", options: ProtectionType.allCases, selection: $protection) {
                        advance(past: 2)
                    }
                    .transition(.opacity.combined(with: .offset(y: 12)))
                }

                if step >= 3 || searchShown {
                    ctaSection
                        .transition(.opacity.combined(with: .offset(y: 12)))
                }

                Button("Skip for now") {
                    commitDefaults()
                    done()
                }
                .buttonStyle(.pressable)
                .font(PCType.footnote)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            element = settings.defaults.element
            mix = settings.defaults.mix
            protection = settings.defaults.protection
        }
    }

    private func advance(past question: Int) {
        guard step == question else { return }
        withAnimation(.pc) { step = question + 1 }
    }

    // MARK: - The live rule line

    private var ruleCard: some View {
        HStack(alignment: .top, spacing: PCSpacing.m) {
            IconTile(systemName: "thermometer.medium")
            Text(ruleLine)
                .font(PCType.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(PCSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pcCard()
        .animation(.pc, value: ruleLine)
    }

    private var ruleLine: String {
        let range = WindowEngine.mixRange(mix: mix, protection: protection)
        let low = Int(range.lowerBound)
        let high = Int(range.upperBound)
        var line: String
        switch mix {
        case .standard:
            line = "Standard mix: pours allowed \(low)–\(high)°C."
        case .rapidSet:
            line = "Rapid-set: pours allowed from \(low)°C."
        case .winter:
            line = protection == .none
                ? "Winter mix needs cover — unprotected it scores as standard (\(low)°C floor)."
                : "Winter mix: pours allowed down to \(low)°C."
        }
        if protection == .blankets {
            line += " Blankets soften frost: threshold −2°C, half penalty."
        }
        if element == .slab {
            line += " Slabs get the strictest rain and heat rules."
        }
        return line
    }

    // MARK: - Completing this IS finishing onboarding

    @ViewBuilder
    private var ctaSection: some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            if !searchShown {
                Button {
                    Haptics.medium()
                    commitDefaults()
                    Task { await resolveSite() }
                } label: {
                    Text(locating ? "Finding your site…" : "Show my week")
                }
                .buttonStyle(.pcPrimary)
                .disabled(locating)
            } else {
                Text("Where's the site?")
                    .pcCapsLabel()
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
                }
                .padding(PCSpacing.m)
                .pcTile()

                ForEach(results) { place in
                    Button {
                        addSite(place)
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentTeal)
                            Text(place.name)
                                .font(PCType.body)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .padding(PCSpacing.m)
                        .pcTile()
                    }
                    .buttonStyle(.pressable)
                }
                if searchFailed {
                    Text("No places matched — try the nearest town.")
                        .font(PCType.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func commitDefaults() {
        settings.defaults.element = element
        settings.defaults.mix = mix
        settings.defaults.protection = protection
    }

    private func resolveSite() async {
        if sites.selected != nil {
            done()
            await app.refreshIfStale()
            return
        }
        guard !app.location.isDenied else {
            withAnimation(.pc) { searchShown = true }
            return
        }
        locating = true
        do {
            let location = try await app.location.currentLocation()
            let name = await app.location.placeName(for: location)
            let site = Site(id: UUID(), name: name, lat: location.coordinate.latitude, lon: location.coordinate.longitude)
            sites.add(site)
            locating = false
            done()
            await app.refresh()
        } catch {
            locating = false
            withAnimation(.pc) { searchShown = true }
        }
    }

    private func search() async {
        searchFailed = false
        results = await app.location.search(city: query)
        searchFailed = results.isEmpty
    }

    private func addSite(_ place: GeocodedPlace) {
        Haptics.medium()
        let site = Site(id: UUID(), name: place.name, lat: place.lat, lon: place.lon)
        sites.add(site)
        done()
        Task { await app.refresh() }
    }
}
