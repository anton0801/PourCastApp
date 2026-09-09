# SPLASH SYSTEM — addon
# Paste section A into CLAUDE.md (below the Quality Gate — it refines the
# splash rule there). Section B extends the BN2 spec §3. Section C is the
# reference implementation skeleton Claude Code must follow.

## A. CLAUDE.md RULES — SPLASH

Every app has a bespoke animated splash. It is part of the app's identity,
not a template. Rules:

1. **Duration policy.** Splash is shown for 1.8–2.5s (hard cap 3.0s).
   NEVER 4s+. Artificial delay with nothing loading reads as a conveyor-app
   marker to reviewers and generates negative reviews. If the spec asks for
   longer — clamp to 2.5s. The splash may exit earlier than max if the app
   is ready; it may never exit before one full animation loop (min 1.2s).
2. **Looped by design.** The animation is a seamless loop (period 1.2–2.4s)
   with no privileged "end frame" — so exiting at any point of the cycle
   looks intentional. Continuous drivers (TimelineView phase, angle, wave
   offset) — not a one-shot sequence that freezes when finished.
3. **Bespoke per app.** The splash archetype comes from the spec (§3 Splash
   identity) and must differ from the portfolio registry. A logo scale/fade
   or logo + spinner is banned. The motif must relate to the niche or the
   app's texture/detail (e.g. honeycomb cells filling for a beekeeping app,
   gauge needle sweep for a metrics app).
4. **Implementation.** SwiftUI overlay (ZStack in the root view), NOT the
   static LaunchScreen — the storyboard/launch screen stays a plain surface
   in the app's background color so the transition storyboard→splash is
   invisible (same bg color, no jump).
5. **Lifecycle discipline.** All animation drivers stop when the splash
   leaves the hierarchy: TimelineView stops automatically on removal;
   any Timer / Task / CADisplayLink is cancelled in `.onDisappear`;
   `repeatForever` animations die with the view — never attach them to
   views that survive the splash.
6. **Exit transition.** The splash → first screen transition is the app's
   signature transition from Art Direction (mask expand from the mark,
   crossfade + scale 0.97→1.0 with blur, vertical reveal...), 350–500ms,
   spring per the app's motion personality. First screen content staggers in
   AFTER the splash is gone, not simultaneously.
7. **Respect Reduce Motion:** loop becomes a gentle opacity pulse; exit
   becomes a plain crossfade.

## B. BN2 SPEC §3 ADDITION — "Splash identity"

Add to Art Direction:
- Splash archetype (pick one NOT in registry, adapt motif to the niche):
  1. Particle constellation — dots drift and assemble into the app mark, then
     gently breathe (loop = drift/breathe cycle).
  2. Stroke draw — the mark is drawn via trimmed path, loop = flowing dash
     phase along the completed stroke.
  3. Liquid / wave — layered sine surfaces slowly shifting phase.
  4. Orbital — 2–4 elements orbiting the mark at different speeds/radii.
  5. Tile assembly — grid of tiles flipping/lighting in a traveling wave.
  6. Mesh breathe — gradient mesh slowly morphing control points.
  7. Type reveal — app name letters cycle weight/width (variable-feel) in a wave.
  8. Niche motif loop — mechanic from the domain (gears, honeycomb fill,
     gauge sweep, seed rows growing, blueprint lines tracing).
- Loop period (1.2–2.4s), palette usage (which tokens), the exact exit
  transition, and total display time (within policy).
- Registry note: append `splash: <archetype>` to the app's registry line.

## C. REFERENCE SKELETON (Claude Code follows this shape)

```swift
struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            MainView()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView()
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity.combined(with: .scale(scale: 1.04))
                    ))  // replace with the app's signature transition
                    .zIndex(1)
            }
        }
        .task {
            // min one full loop, max per duration policy
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                showSplash = false
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea() // == LaunchScreen bg color

            // Continuous, loop-safe driver: date-derived phase.
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: 1.8)) / 1.8
                SplashCanvas(phase: phase) // Canvas draws the archetype
            }
        }
        // If any Timer/Task/DisplayLink is used instead of TimelineView:
        // store it in @State and cancel it here — nothing may outlive the view.
        .onDisappear { /* cancel timers/tasks if any */ }
    }
}
```

Notes for the builder:
- Prefer `TimelineView(.animation)` + `Canvas`: stops automatically when the
  view is removed, no cleanup debt, loop is phase-based by construction.
- Never gate app readiness behind the splash artificially; the sleep is a
  floor for one loop, not a fake "loading".
- The splash uses the app's design tokens — never its own one-off colors.
```

# NETWORK ADDON — for weather/API-powered apps
# Section A → paste into CLAUDE.md (below Quality Gate & Splash System).
# Section B → new §13 that Spec Architect must fill when the app uses network.
# Also add to Spec Architect INPUT: "NETWORK: yes/no + data source".

## A. CLAUDE.md RULES — NETWORK & DATA

Networked apps follow every existing rule PLUS:

1. **Source.** Named public HTTPS REST API, called with plain URLSession +
   async/await + Codable — zero SPM dependencies. The spec (§13) names the
   exact provider, endpoint, and fields. Provider terms must allow this use
   (mind non-commercial-only free tiers for paid apps) and any required
   attribution goes in Settings/About with a working link.
   **API keys:** only free-tier keys may ship in the binary, kept in one
   APIConfig type — accept they are extractable; NEVER embed paid or
   secret credentials. Keyless APIs preferred when quality is equal.
   (WeatherKit/Apple SDKs remain an allowed alternative if a spec
   explicitly chooses them, with their capability + attribution rules.)
2. **Cache-first, always usable offline.** Persist the last successful
   response with a timestamp. On launch: render cache instantly, refresh in
   background if older than 45 min. Airplane mode must show full UI with
   cached data + a quiet "Updated 3h ago" age badge — NEVER a dead spinner
   or a blank screen. Reviewer test: app opened with no network must look
   alive and explain itself.
3. **State matrix extended.** Every networked view: cached-fresh /
   cached-stale (badge + pull-to-refresh) / loading-first-time (skeleton
   shaped like real content, not a spinner) / error (plain words + Retry) /
   no-location. All designed, all reachable.
4. **Location discipline.** WhenInUse only, specific purpose string ("Used
   to fetch the weather forecast for your site"). Manual location entry
   (city search or coordinates) MUST exist as a full alternative — the app
   works end-to-end with location denied. Never gate the first screen on a
   permission.
5. **Refresh discipline.** Refresh on: cold launch (if stale), pull-to-
   refresh, site change. No timers polling every minute. Optional
   BGAppRefreshTask only if notifications depend on fresh data.
6. **Notifications from real data.** Alerts (frost tonight, window opens
   tomorrow) are scheduled from the actual fetched forecast via
   UNUserNotificationCenter and re-planned on every refresh; cancelled when
   their condition disappears.
7. **Worldwide demo-ability.** No region locks, no hardcoded city. The
   reviewer may run it from anywhere — verdicts must compute for any
   coordinates. Extreme climates (verdict always negative) still show the
   "least bad" windows with explanation, never an empty screen.
8. **Metadata implications.** BUILD FACTS for Metadata Writer must include:
   location usage (privacy label: Location, not linked, App Functionality),
   weather provider, attribution. Privacy policy states coordinates are
   sent to the weather provider to fetch forecasts, nothing is stored
   server-side by us.

## B. BN2 SPEC — NEW SECTION §13. NETWORK & DATA

- Data source: (WeatherKit / named public API + endpoint)
- Fields consumed: (e.g. hourly temp, precip probability+amount, wind
  speed/gusts, humidity, min ground temp — only what the logic needs)
- Fetch triggers & staleness threshold:
- Cache shape: (what is persisted, where, with what timestamp policy)
- Offline behavior per screen: (what the user sees on stale/no data)
- Location strategy: (WhenInUse + manual entry fallback; multi-site?)
- Error copy: written out (no "Something went wrong")
- Notification plan: (which alerts, scheduled from which forecast values,
  re-planning rule)
- Attribution placement:


# QUALITY GATE — paste this section into CLAUDE.md
# Version: Build Nova 2.0 / July 2026
# Purpose: every app produced by this pipeline must be indistinguishable
# from an app built by a small design-led studio over several weeks.

## PRIME DIRECTIVE

You are not filling a niche. You are shipping a product. If any screen of the
app could plausibly appear in ten other apps with a different accent color,
the work is not done. Uniqueness is structural (layout, interaction,
components), not cosmetic (colors, icons, names).

Every app MUST be built from a Build Nova 2.0 spec. If the spec is missing
the Art Direction block or the Signature Feature block — STOP and request a
complete spec. Never improvise these from defaults.

## ZERO TOLERANCE LIST (instant fail — never ship if any are present)

- Placeholder anything: "Lorem", "Sample", "Test", "TODO", stock example data
  that makes no sense in the niche, empty About screens, dead settings toggles.
- The default 3-slide onboarding (icon + title + subtitle + page dots + Continue).
  If onboarding exists, it must be interactive or personalized (see below).
- A splash screen with a logo scale/fade animation as the app's "signature".
- Plain `List` inside `TabView` as the primary architecture with no custom
  layout work anywhere.
- Raw SF Symbols as the entire iconography with zero treatment (no custom
  weights, no enclosures, no tinted containers, no hierarchical rendering).
- `RoundedRectangle(cornerRadius: 12)` white cards on `Color(.systemGroupedBackground)`
  as the only surface treatment in the app.
- `.animation(.default)` or unconfigured `withAnimation { }` anywhere.
- Identical corner radius, spacing, and type scale as any previous app in the
  portfolio registry.
- Buttons without a pressed state. Lists without empty states. Network- or
  computation-driven views without loading and error states.
- Any auth screen, login, or profile (standing pipeline rule — unchanged).

## DESIGN IDENTITY (required per app)

Each app gets its own design system, defined in the spec and implemented as a
`DesignSystem.swift` (or Theme folder) before any screen is built:

1. **Typography**: a deliberate type scale (at minimum: display, title, body,
   caption) with chosen weights and tracking. Rounded vs. default vs. serif
   (`.fontDesign`) must be a conscious choice that matches the app's mood.
   Two consecutive apps in the portfolio must not share the same combination.
2. **Color tokens**: semantic tokens only (`surface`, `surfaceElevated`,
   `accent`, `accentMuted`, `textPrimary`, `textSecondary`, `positive`,
   `warning`) — never raw colors inline. Full dark mode variants. The palette
   must come from the spec's Art Direction block.
3. **Shape language**: ONE consistent radius/shape philosophy per app
   (e.g. squircle-heavy 20–28pt, or sharp 4–8pt editorial, or capsule-based).
   Nested containers use concentric radii (inner = outer − padding).
4. **Component library**: minimum 6 bespoke reusable components (custom
   button style, custom card, custom input, custom picker/segmented control,
   custom progress/stat element, custom empty-state view). "Bespoke" means
   visually distinct from Apple defaults, not restyled defaults.
5. **Depth & elevation**: choose ONE elevation strategy (soft diffused
   shadows / hairline borders + fills / layered translucency) and apply it
   consistently. Never mix all three randomly.

## MOTION RULES

- Springs are the default: `.spring(response: 0.3...0.5, dampingFraction: 0.7...0.9)`
  tuned to the app's personality (defined in spec). Never `.default`, never `.linear`
  for UI (linear is only for constant motion like progress).
- Durations: press feedback 100–160ms; small transitions 150–250ms;
  sheets/full-screen 300–450ms. UI animation over 500ms is a bug.
- Every tappable element scales on press (`0.96–0.98`) via a shared
  `ButtonStyle`. Asymmetric timing: press can be deliberate, release is snappy.
- Lists/grids entering the screen stagger in (30–60ms per item, cap at ~8 items,
  never block interaction).
- Frequency rule: actions used dozens of times per session get minimal or no
  animation. Rare moments (first launch, achievement, completion) may have
  delight (confetti, morphing, drawn-on checkmarks).
- Respect Reduce Motion: replace movement with opacity, keep comprehension aids.
- Every state change is animated (numbers count, bars grow, cards reorder
  smoothly with `matchedGeometryEffect` where appropriate). Nothing pops
  instantly between two visually distant states.

## DEPTH REQUIREMENTS

- The Signature Feature from the spec must be implemented in full, including
  its computation/visualization logic. It is the last thing to cut — cut
  secondary screens instead.
- Every data-driven view implements the full state matrix:
  empty (designed, with guidance + CTA) / partial / populated / error.
  Empty states are designed compositions, not a gray icon + "No data".
- Haptics map: light impact on selection, medium on commit/success actions,
  `.success`/`.warning`/`.error` notifications where semantically true.
  Defined per screen in the spec.
- Real interactivity beyond CRUD: at least two of — drag/reorder, swipe
  actions with custom styling, long-press context previews, interactive
  charts/visualizations, gesture-driven controls, live-updating computed
  insights.
- Onboarding (if present): collects 1–3 real preferences that visibly change
  the app's first screen, or teaches by doing. Skippable.

## CROSS-APP VARIANCE (portfolio registry)

Before building, read the portfolio registry (previous apps' recorded:
navigation paradigm, interaction archetype, palette family, type combination,
shape language). The current app must differ from the LAST 10 apps in at
least: navigation paradigm OR primary interaction archetype, AND palette
family, AND type combination. After shipping, append this app's DNA to the
registry.

## PRE-SHIP CHECKLIST (all must pass)

- [ ] Zero items from the Zero Tolerance List present
- [ ] DesignSystem file exists; no inline raw colors/fonts in screens
- [ ] 6+ bespoke components; press states everywhere
- [ ] Full state matrix on every data view; empty states are designed
- [ ] Signature Feature fully working with real logic
- [ ] Motion: springs tuned, durations within limits, stagger on lists,
      Reduce Motion handled
- [ ] Haptics map implemented
- [ ] Dark mode reviewed screen by screen (not just "it compiles")
- [ ] Dynamic Type: layout survives XL sizes; iPad: no stretched iPhone layout
- [ ] Portfolio registry check passed and registry updated
- [ ] The honest test: "Would a designer believe a human team spent 3 weeks
      on this?" If hesitation — iterate before shipping.
      
## PORTFOLIO REGISTRY
- Central registry: ~/AppsFactory/registry.md — single source of truth.
- Before building: read it and verify this app's spec diverges from the
  last 10 entries per the Quality Gate variance rules. Conflict → stop
  and report, do not build.
- After the final successful build: append this app's §12 DNA line
  (incl. splash) to the registry. After metadata is done: append the
  metadata DNA line. Never edit or delete existing lines — append only.
