import SwiftUI
import Charts

/// S2 — prove the verdict. Hourly chart with pour/cure bands and a snapping
/// scrub readout; the penalty list below matches the scrub hours 1:1.
struct WindowDetailView: View {
    let dayID: Date

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var forecast: ForecastStore
    @EnvironmentObject private var sites: SiteStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var selectedStart: Date?
    @State private var scrubDate: Date?
    @State private var bandProgress: CGFloat = 0
    @State private var showLogPour = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { .current }

    private var day: DayVerdicts? {
        forecast.week.first { $0.id == dayID }
    }

    private var candidate: WindowScore? {
        guard let day else { return nil }
        if let selectedStart, let picked = day.candidates.first(where: { $0.start == selectedStart }) {
            return picked
        }
        if let blockStart = day.best?.start,
           let inBlock = day.candidates.filter({ $0.start >= blockStart }).max(by: { $0.score < $1.score }) {
            return inBlock
        }
        return day.candidates.max(by: { $0.score < $1.score })
    }

    var body: some View {
        Group {
            if let day, let candidate {
                content(day: day, candidate: candidate)
            } else {
                VStack(spacing: PCSpacing.m) {
                    FormworkOutline()
                        .frame(height: 64)
                    Text("This day rolled off the forecast.")
                        .font(PCType.body)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: PCSpacing.s) {
                    Text(navTitle)
                        .font(PCType.navTitle)
                        .foregroundStyle(Color.textPrimary)
                    FarmPropStrip(names: ["FarmProp-tractor", "FarmProp-windmill", "FarmProp-crate"], size: 21)
                }
            }
        }
        .sheet(isPresented: $showLogPour) {
            LogPourSheet(plannedStart: candidate?.start)
        }
        .onAppear {
            if reduceMotion {
                bandProgress = 1
            } else {
                bandProgress = 0
                withAnimation(.easeOut(duration: 0.45).delay(0.15)) {
                    bandProgress = 1
                }
            }
        }
    }

    private var navTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return formatter.string(from: dayID)
    }

    private func content(day: DayVerdicts, candidate: WindowScore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PCSpacing.l) {
                header(candidate: candidate)
                readoutRow(candidate: candidate)
                chartCard(candidate: candidate)
                candidatePicker(day: day, candidate: candidate)
                penaltySection(candidate: candidate)
                planButton(candidate: candidate)
            }
            .padding(.horizontal, PCSpacing.l)
            .padding(.vertical, PCSpacing.m)
        }
    }

    // MARK: - Header

    private func header(candidate: WindowScore) -> some View {
        HStack(alignment: .center, spacing: PCSpacing.m) {
            // The one sanctioned capsule: the verdict badge.
            Text(candidate.verdict.word)
                .font(PCType.capsLabel)
                .tracking(PCType.capsTracking)
                .foregroundStyle(candidate.verdict.color)
                .padding(.horizontal, PCSpacing.m)
                .padding(.vertical, PCSpacing.xs)
                .overlay(Capsule().strokeBorder(candidate.verdict.color, lineWidth: 1.5))

            Text("Pour \(PCFormat.hourRange(candidate.start, candidate.start.addingTimeInterval(4 * 3600), calendar: calendar))")
                .font(PCType.body)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(candidate.score)")
                    .font(PCType.monoDisplay)
                    .foregroundStyle(Color.textPrimary)
                Text("/100")
                    .pcCapsLabel()
            }

            if forecast.isStale(sites.selectedSiteID) {
                AgeBadge(fetchedAt: forecast.cache(for: sites.selectedSiteID)?.fetchedAt)
            }
        }
    }

    // MARK: - Scrub readout (fixed height — follows the finger)

    private func readoutRow(candidate: WindowScore) -> some View {
        let hour = scrubDate.flatMap { date in chartHours.first { $0.date == date } }
        return HStack(spacing: PCSpacing.m) {
            if let hour {
                Text(PCFormat.weekdayHour(hour.date, calendar: calendar))
                    .font(PCType.mono)
                    .foregroundStyle(Color.textPrimary)
                Group {
                    Label(PCFormat.temperature(hour.tempC, unit: settings.unit), systemImage: "thermometer.medium")
                    Label("\(PCFormat.percent(hour.precipProb)) · \(PCFormat.precip(hour.precipMM))", systemImage: "cloud.rain")
                    Label(PCFormat.wind(hour.windKMH), systemImage: "wind")
                }
                .font(PCType.monoSmall)
                .foregroundStyle(Color.textSecondary)
                .labelStyle(.titleAndIcon)
                Spacer()
                if let penalty = candidate.penalties.first(where: { $0.hour == hour.date }) {
                    Text("−\(penalty.points)")
                        .font(PCType.mono)
                        .foregroundStyle(Color.dangerClay)
                }
            } else {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12, weight: .medium))
                Text("Drag across the chart to read any hour")
                    .font(PCType.footnote)
                Spacer()
            }
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, PCSpacing.m)
        .frame(height: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pcTile()
        .animation(.pc, value: scrubDate)
    }

    // MARK: - Chart

    private var chartHours: [HourF] {
        guard let cache = forecast.cache(for: sites.selectedSiteID) else { return [] }
        let domainEnd = dayID.addingTimeInterval(72 * 3600)
        return cache.hours.filter { $0.date >= dayID && $0.date < domainEnd }
    }

    private func chartCard(candidate: WindowScore) -> some View {
        let hours = chartHours
        let tempLow = (hours.map(\.tempC).min() ?? 0) - 2
        let tempHigh = (hours.map(\.tempC).max() ?? 30) + 2
        let tempSpan = max(tempHigh - tempLow, 1)
        let maxPrecip = max(hours.map(\.precipMM).max() ?? 0, 2)
        let maxWind = max(hours.map(\.windKMH).max() ?? 0, 40)

        // Normalized composition: temp 0.30…1.0, wind area 0…0.45, precip bars 0…0.30.
        func tempY(_ value: Double) -> Double { 0.30 + (value - tempLow) / tempSpan * 0.70 }

        return HStack(alignment: .top, spacing: PCSpacing.xs) {
            TickRuler()
                .frame(height: 220)

            Chart {
                ForEach(hours, id: \.date) { hour in
                    AreaMark(
                        x: .value("Hour", hour.date),
                        y: .value("Wind", hour.windKMH / maxWind * 0.45)
                    )
                    .foregroundStyle(Color.textSecondary.opacity(0.14))
                    .interpolationMethod(.monotone)
                }
                ForEach(hours, id: \.date) { hour in
                    BarMark(
                        x: .value("Hour", hour.date),
                        y: .value("Precip", hour.precipMM / maxPrecip * 0.30),
                        width: .fixed(3)
                    )
                    .foregroundStyle(Color.warningOchre.opacity(0.75))
                }
                ForEach(hours, id: \.date) { hour in
                    LineMark(
                        x: .value("Hour", hour.date),
                        y: .value("Temp", tempY(hour.tempC))
                    )
                    .foregroundStyle(Color.accentTeal)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }

                // Freezing line, when visible in range.
                if tempLow < 0 {
                    RuleMark(y: .value("Freezing", tempY(0)))
                        .foregroundStyle(Color.dangerClay.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                // Penalty hours — weather glyphs live ONLY here.
                ForEach(candidate.penalties.filter { $0.hour != nil }, id: \.id) { penalty in
                    RuleMark(x: .value("Penalty", penalty.hour!))
                        .foregroundStyle(Color.dangerClay.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            Image(systemName: penalty.symbol)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.dangerClay)
                        }
                }

                if let scrubDate {
                    RuleMark(x: .value("Scrub", scrubDate))
                        .foregroundStyle(Color.textPrimary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...1.05)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 12)) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.hairline)
                    AxisValueLabel(anchor: .top) {
                        if let date = value.as(Date.self) {
                            let hour = calendar.component(.hour, from: date)
                            Text(hour == 0
                                 ? PCFormat.dayLabel(date, calendar: calendar).weekday
                                 : PCFormat.hour(date, calendar: calendar))
                                .font(PCType.monoSmall)
                                .foregroundStyle(hour == 0 ? Color.textPrimary : Color.textSecondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    bandsAndGesture(proxy: proxy, geo: geo, candidate: candidate)
                }
            }
            .frame(height: 220)
        }
        .padding(PCSpacing.m)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PCShape.cardRadius, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .opacity(forecast.isStale(sites.selectedSiteID) ? 0.8 : 1)
        .accessibilityLabel("Hourly forecast chart with pour and cure windows")
    }

    @ViewBuilder
    private func bandsAndGesture(proxy: ChartProxy, geo: GeometryProxy, candidate: WindowScore) -> some View {
        let plotFrame = geo[proxy.plotAreaFrame]
        let pourStart = proxy.position(forX: candidate.start)
        let pourEnd = proxy.position(forX: candidate.start.addingTimeInterval(4 * 3600))
        let cureEnd = proxy.position(forX: min(candidate.start.addingTimeInterval(48 * 3600), chartHours.last?.date ?? candidate.start))

        ZStack(alignment: .topLeading) {
            if let pourStart, let pourEnd, let cureEnd {
                BandsCanvas(
                    progress: bandProgress,
                    pourStart: pourStart + plotFrame.minX,
                    pourEnd: pourEnd + plotFrame.minX,
                    cureEnd: cureEnd + plotFrame.minX,
                    plotFrame: plotFrame
                )
                .allowsHitTesting(false)
            }

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = value.location.x - plotFrame.minX
                            guard let date: Date = proxy.value(atX: x) else { return }
                            var snapped = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                            snapped.minute = 0
                            guard let snappedDate = calendar.date(from: snapped),
                                  chartHours.contains(where: { $0.date == snappedDate })
                            else { return }
                            if snappedDate != scrubDate {
                                scrubDate = snappedDate
                                Haptics.selection()
                            }
                        }
                )
        }
    }

    // MARK: - Candidate picker: every scoreable start hour of the day

    private func candidatePicker(day: DayVerdicts, candidate: WindowScore) -> some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            Text("Start hour")
                .pcCapsLabel()
                .padding(.leading, PCSpacing.xs)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PCSpacing.s) {
                    ForEach(day.candidates) { option in
                        let selected = option.start == candidate.start
                        Button {
                            Haptics.selection()
                            withAnimation(.pc) {
                                selectedStart = option.start
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(PCFormat.hour(option.start, calendar: calendar))
                                    .font(PCType.monoSmall)
                                Text("\(option.score)")
                                    .font(PCType.mono)
                            }
                            .foregroundStyle(selected ? Color.surfaceElevated : option.verdict.color)
                            .padding(.horizontal, PCSpacing.m)
                            .padding(.vertical, PCSpacing.s)
                            .background(
                                selected ? option.verdict.color : Color.surfaceElevated,
                                in: RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: PCShape.innerRadius, style: .continuous)
                                    .strokeBorder(selected ? Color.clear : option.verdict.color.opacity(0.5), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Start \(PCFormat.hour(option.start, calendar: calendar)), score \(option.score)")
                    }
                }
                .padding(.horizontal, PCSpacing.xs)
            }
        }
    }

    // MARK: - Penalty list (matches scrub hours 1:1)

    private func penaltySection(candidate: WindowScore) -> some View {
        VStack(alignment: .leading, spacing: PCSpacing.s) {
            Text("Against this window")
                .pcCapsLabel()
                .padding(.leading, PCSpacing.xs)

            if candidate.penalties.isEmpty {
                NoPenaltyRow()
            } else {
                ForEach(candidate.penalties) { penalty in
                    Button {
                        if let hour = penalty.hour {
                            withAnimation(.pc) { scrubDate = hour }
                            Haptics.selection()
                        }
                    } label: {
                        PenaltyRow(penalty: penalty, unit: settings.unit, calendar: calendar)
                    }
                    .buttonStyle(.pressable)
                    .disabled(penalty.hour == nil)
                }
            }
        }
    }

    // MARK: - Plan pour

    @ViewBuilder
    private func planButton(candidate: WindowScore) -> some View {
        let inPast = candidate.start <= Date()
        Button {
            Haptics.medium()
            Task {
                await app.planner.schedulePourReminder(at: candidate.start, calendar: calendar)
            }
            showLogPour = true
        } label: {
            Text(inPast
                 ? "Log pour at \(PCFormat.hour(candidate.start, calendar: calendar))"
                 : "Plan pour at \(PCFormat.hour(candidate.start, calendar: calendar))")
        }
        .buttonStyle(.pcPrimary)
        .padding(.top, PCSpacing.s)
    }
}

/// The pour/cure bands, drawn with the screed-wipe: a 2px teal front sweeps
/// left→right revealing the bands. Animatable so withAnimation drives it.
private struct BandsCanvas: View, Animatable {
    var progress: CGFloat
    let pourStart: CGFloat
    let pourEnd: CGFloat
    let cureEnd: CGFloat
    let plotFrame: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let revealX = plotFrame.minX + (cureEnd - plotFrame.minX) * progress

            // Cure band: diagonal hatch, clipped to the revealed portion.
            let cureRect = CGRect(
                x: pourStart, y: plotFrame.minY,
                width: max(min(cureEnd, revealX) - pourStart, 0), height: plotFrame.height
            )
            if cureRect.width > 0 {
                var hatch = context
                hatch.clip(to: Path(cureRect))
                var lines = Path()
                var x = cureRect.minX - plotFrame.height
                while x < cureRect.maxX {
                    lines.move(to: CGPoint(x: x, y: cureRect.maxY))
                    lines.addLine(to: CGPoint(x: x + plotFrame.height, y: cureRect.minY))
                    x += 10
                }
                hatch.stroke(lines, with: .color(.accentTeal.opacity(0.10)), lineWidth: 3)
            }

            // Pour window: solid teal wash + edge rules.
            let pourRect = CGRect(
                x: pourStart, y: plotFrame.minY,
                width: max(min(pourEnd, revealX) - pourStart, 0), height: plotFrame.height
            )
            if pourRect.width > 0 {
                context.fill(Path(pourRect), with: .color(.accentTeal.opacity(0.12)))
                var edges = Path()
                edges.move(to: CGPoint(x: pourRect.minX, y: pourRect.minY))
                edges.addLine(to: CGPoint(x: pourRect.minX, y: pourRect.maxY))
                context.stroke(edges, with: .color(.accentTeal.opacity(0.5)), lineWidth: 1)
            }

            // The screed front itself, while sweeping.
            if progress > 0.01, progress < 0.99, revealX > pourStart {
                var front = Path()
                front.move(to: CGPoint(x: revealX, y: plotFrame.minY))
                front.addLine(to: CGPoint(x: revealX, y: plotFrame.maxY))
                context.stroke(front, with: .color(.accentTeal), lineWidth: 2)
            }
        }
    }
}
