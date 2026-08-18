# Design brief — Edgar's storm-flight to the lighthouse

> Captured verbatim 2026-08-18 so it is never lost again (the prior version of
> this scene was — see LESSONS.md "Commit AND push together"). This is the
> creative spec for the landing-page hero rebuild; the original is unrecoverable
> from git, so this is a fresh build, not a restore.

## The scene (author's words)

> Edgar begins perched and sleepy, but as the rot gauge fills and drift is
> detected, a storm that has been brewing erupts and rain and lightning harrow
> his journey as he flies fearless through the storm to reach the lighthouse,
> the beam of which is emitting at a constant interval and guiding his flight
> despite the increasingly hostile environment of the storm.

## How it maps to the system (why this scene is *true*, not decoration)

The landing page should dramatize the actual mechanics of ContextSynapse, so the
animation is the product's thesis, not an ornament:

| Beat | Project mechanic |
|---|---|
| Edgar perched, sleepy | `RavenState.dormant`/`.perched` — low rot, no drift |
| Rot gauge fills | `RotScore` rising toward the cauterize threshold (0.82) |
| Drift detected → storm erupts | `tDrift` crossing threshold; `.watching`→`.stirring`→`.alarmed` |
| Rain + lightning harrow the journey | escalating rot/drift as hostile environment |
| Edgar flies fearless toward the lighthouse | the anchor pulling context back on course |
| Beam emitting at a constant interval, guiding | the lighthouse floor (`DecayConstants.lighthouseFloor`) — a steady, earned signal that never rots |

## Build notes (for the next session)

- Base: current `site/public/index.html` (23KB; the richest committed scene —
  static raven + static lighthouse glow + `blink`/`caret`/`drift` idle anims).
- Add: a flight path (Edgar arcs from perch toward the beam), a storm layer
  (rain streaks + intermittent lightning), and a **constant-interval** beam
  sweep (the guidance signal — regular, unbroken by the storm).
- Prefer Canvas/WebGL for rain/lightning/flight over hand-authored SVG paths.
- Respect `prefers-reduced-motion` (the current scene already gates its idle
  animations); provide a calm fallback.
- **Commit + push the moment it looks right** — this scene's whole history is a
  lesson in not doing that.
- Palette continuity: amber (#f0b445) = lighthouse beam; cyan = Edgar/system
  (per DECISIONS 2026-07-15).
