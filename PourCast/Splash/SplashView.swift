import SwiftUI

/// Formwork-fill splash, layered like the real thing (back→front):
/// faint tick ruler on the screen's left edge → formwork outline with slight
/// perspective → concrete rising with a two-sine meniscus, gradient body and
/// drifting aggregate → a screed pass once per loop that flattens the wave
/// and leaves a fading sheen — the loop's rhythm anchor → the wordmark, which
/// enters once and then holds still.
///
/// One phase value drives everything (TimelineView(.animation), seamless
/// 2.0s loop, no Timers). Reduce Motion: static filled form, opacity
/// breathing only. Nothing here outlives the view.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wordmarkShown = false

    private static let loopPeriod: Double = 2.0

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            // Layer 1: the app's texture motif, running down the screen edge.
            HStack {
                TickRuler(spacing: 10, majorEvery: 6)
                    .opacity(0.45)
                    .padding(.leading, PCSpacing.s)
                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: PCSpacing.xl) {
                TimelineView(.animation(paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (t.truncatingRemainder(dividingBy: Self.loopPeriod)) / Self.loopPeriod
                    FormworkScene(phase: phase, reduceMotion: reduceMotion)
                }
                .frame(width: 200, height: 200)

                // Layer 5: enters once in the first 400ms, then static.
                VStack(spacing: PCSpacing.s) {
                    Text("PourCast")
                        .font(PCType.display)
                        .tracking(PCType.displayTracking)
                        .foregroundStyle(Color.textPrimary)
                    Text("Pour on the right day.")
                        .font(PCType.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .opacity(wordmarkShown ? 1 : 0)
                .offset(y: wordmarkShown || reduceMotion ? 0 : 8)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.05)) {
                        wordmarkShown = true
                    }
                }
            }
        }
    }
}

/// Layers 2–4, every value a pure function of `phase`.
private struct FormworkScene: View {
    let phase: Double
    let reduceMotion: Bool

    // The screed crosses the form during this slice of the loop.
    private let screedStart = 0.55
    private let screedEnd = 0.85

    var body: some View {
        Canvas { context, size in
            let form = formTrapezoid(in: size)
            drawFill(context: context, form: form)
            drawFormwork(context: context, form: form)
        }
    }

    // MARK: - Geometry: slight perspective (top edge narrower)

    private struct Trapezoid {
        let bottomLeft: CGPoint
        let bottomRight: CGPoint
        let topLeft: CGPoint
        let topRight: CGPoint

        var minY: CGFloat { topLeft.y }
        var maxY: CGFloat { bottomLeft.y }
        var height: CGFloat { maxY - minY }

        func width(atY y: CGFloat) -> (left: CGFloat, right: CGFloat) {
            let f = (y - minY) / height
            let left = topLeft.x + (bottomLeft.x - topLeft.x) * f
            let right = topRight.x + (bottomRight.x - topRight.x) * f
            return (left, right)
        }

        var path: Path {
            var p = Path()
            p.move(to: bottomLeft)
            p.addLine(to: bottomRight)
            p.addLine(to: topRight)
            p.addLine(to: topLeft)
            p.closeSubpath()
            return p
        }
    }

    private func formTrapezoid(in size: CGSize) -> Trapezoid {
        let w: CGFloat = 148
        let h: CGFloat = 172
        let inset: CGFloat = 6 // perspective: top slightly narrower
        let x = (size.width - w) / 2
        let y = (size.height - h) / 2
        return Trapezoid(
            bottomLeft: CGPoint(x: x, y: y + h),
            bottomRight: CGPoint(x: x + w, y: y + h),
            topLeft: CGPoint(x: x + inset, y: y),
            topRight: CGPoint(x: x + w - inset, y: y)
        )
    }

    // MARK: - Phase-derived quantities

    private var angle: Double { phase * 2 * .pi }

    /// Fill level breathes: rises through the first half of the loop, then the
    /// screed pass levels it back down — that's the pour rhythm.
    private var level: Double {
        reduceMotion ? 0.58 : 0.56 + 0.045 * sin(angle - .pi / 2)
    }

    /// 0→1 across the screed slice.
    private var screedProgress: Double {
        guard !reduceMotion, phase > screedStart else { return phase <= screedStart ? 0 : 1 }
        return min((phase - screedStart) / (screedEnd - screedStart), 1)
    }

    /// Waves rebuild after the pass; sheen fades out over the same tail.
    private var tailFade: Double {
        guard phase > screedEnd else { return 1 }
        return max(0, 1 - (phase - screedEnd) / (1 - screedEnd))
    }

    /// Two superimposed sines, flattened behind the screed blade.
    private func meniscus(x: CGFloat, form: Trapezoid, surfaceY: CGFloat, bladeX: CGFloat?) -> CGFloat {
        guard !reduceMotion else { return surfaceY }
        let widths = form.width(atY: surfaceY)
        let f = Double((x - widths.left) / max(widths.right - widths.left, 1))
        let wave1 = 2.8 * sin(f * 2 * .pi * 1.4 + angle)
        let wave2 = 1.4 * sin(f * 2 * .pi * 3.1 - angle * 1.7)

        var amplitude = 1.0
        if let bladeX, x < bladeX {
            // Flat in the screed's wake; waves rebuild through the loop tail,
            // reaching full amplitude exactly at the loop seam.
            amplitude = 0.2 + 0.8 * (1 - tailFade)
        }
        return surfaceY + (wave1 + wave2) * amplitude
    }

    // MARK: - Layer 3: concrete

    private func drawFill(context: GraphicsContext, form: Trapezoid) {
        let surfaceY = form.maxY - form.height * level
        let widths = form.width(atY: surfaceY)

        let bladeX: CGFloat?
        if screedProgress > 0, screedProgress < 1 {
            bladeX = widths.left + (widths.right - widths.left) * screedProgress
        } else if phase > screedEnd {
            bladeX = widths.right // fully passed: whole surface in the wake
        } else {
            bladeX = nil
        }

        // Body of the pour.
        var fill = Path()
        fill.move(to: form.bottomLeft)
        fill.addLine(to: CGPoint(x: widths.left, y: meniscus(x: widths.left, form: form, surfaceY: surfaceY, bladeX: bladeX)))
        let steps = 28
        for i in 0...steps {
            let x = widths.left + (widths.right - widths.left) * CGFloat(i) / CGFloat(steps)
            fill.addLine(to: CGPoint(x: x, y: meniscus(x: x, form: form, surfaceY: surfaceY, bladeX: bladeX)))
        }
        fill.addLine(to: form.bottomRight)
        fill.closeSubpath()

        var inner = context
        if reduceMotion {
            inner.opacity = 0.85 + 0.15 * sin(angle)
        }
        inner.clip(to: form.path)
        inner.fill(
            fill,
            with: .linearGradient(
                Gradient(colors: [Color.accentMuted, Color.accentTeal.opacity(0.45)]),
                startPoint: CGPoint(x: form.bottomLeft.x, y: surfaceY),
                endPoint: CGPoint(x: form.bottomLeft.x, y: form.maxY)
            )
        )

        // Suspended aggregate: 10 dots, varied radii, slow drift with wrap.
        if !reduceMotion {
            for i in 0..<10 {
                let noise = Double(i) * 0.618
                let fx = 0.1 + noise.truncatingRemainder(dividingBy: 1) * 0.8
                let travel = (phase * 0.5 + noise).truncatingRemainder(dividingBy: 1)
                let depth = form.maxY - (form.maxY - surfaceY - 10) * travel - 6
                guard depth > surfaceY + 8 else { continue }
                let wobble = 2.0 * sin(angle + noise * 9)
                let widthsHere = form.width(atY: depth)
                let dotX = widthsHere.left + (widthsHere.right - widthsHere.left) * fx + wobble
                let radius = 1.4 + noise.truncatingRemainder(dividingBy: 0.5) * 3.6
                let dot = CGRect(x: dotX - radius, y: depth - radius, width: radius * 2, height: radius * 2)
                inner.fill(Path(ellipseIn: dot), with: .color(.accentTeal.opacity(0.30)))
            }
        }

        // Layer 4: the screed pass — blade + fading sheen along the wake.
        if !reduceMotion {
            if let bladeX, phase > screedStart {
                // Sheen: a thin highlight lying on the flattened surface.
                let sheenEnd = min(bladeX, widths.right)
                if sheenEnd > widths.left + 2, tailFade > 0.02 {
                    var sheen = Path()
                    sheen.move(to: CGPoint(x: widths.left + 1, y: surfaceY - 0.5))
                    sheen.addLine(to: CGPoint(x: sheenEnd, y: surfaceY - 0.5))
                    inner.stroke(
                        sheen,
                        with: .color(.accentTeal.opacity(0.55 * tailFade)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                }
            }
            if screedProgress > 0, screedProgress < 1 {
                let bladeX = widths.left + (widths.right - widths.left) * screedProgress
                var blade = Path()
                blade.move(to: CGPoint(x: bladeX, y: surfaceY - 13))
                blade.addLine(to: CGPoint(x: bladeX, y: surfaceY + 13))
                context.stroke(blade, with: .color(.accentTeal), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    // MARK: - Layer 2: formwork

    private func drawFormwork(context: GraphicsContext, form: Trapezoid) {
        context.stroke(
            form.path,
            with: .color(.textSecondary.opacity(0.55)),
            lineWidth: 1.5
        )
        // Board ribs following the perspective.
        for i in 1..<4 {
            let f = CGFloat(i) / 4
            let topX = form.topLeft.x + (form.topRight.x - form.topLeft.x) * f
            let bottomX = form.bottomLeft.x + (form.bottomRight.x - form.bottomLeft.x) * f
            var rib = Path()
            rib.move(to: CGPoint(x: topX, y: form.minY))
            rib.addLine(to: CGPoint(x: bottomX, y: form.maxY))
            context.stroke(rib, with: .color(.textSecondary.opacity(0.16)), lineWidth: 1)
        }
        // Side ties at mid-height.
        let midY = form.minY + form.height / 2
        let widths = form.width(atY: midY)
        for x in [widths.left - 7, widths.right + 7] {
            var tie = Path()
            tie.move(to: CGPoint(x: x, y: midY - 9))
            tie.addLine(to: CGPoint(x: x, y: midY + 9))
            context.stroke(tie, with: .color(.textSecondary.opacity(0.4)), lineWidth: 1.5)
        }
    }
}
