# ODCA to-do

**YOU ARE HERE (2026-09-04):** Python is at 2.9.0 (auto-init filter
2.3–2.7 reviewed and working; color sets 3–9 provisionally filled with the
first seven of colorsets/candidates.json). Next: (a) the Swift catch-up
release, porting 2.1–2.9 (session layer is already there; auto-init,
paused 's', screen counter, Brent's, color sets are not); (b) decide the
mechanics for auditioning all 45 palettes (colorsets/audition.png) and
finalize slots 3–9; (c) finish the auto-init review of the remaining
saved rules if any are unchecked.

- [x] (2.9.0/2.11.0: slots 0 and 2–9 from colorsets/candidates.json, CoCo
      sets retired; revisit after auditioning all 45) Choose the remaining seven color sets (keys 3–9)
- [ ] Hold-to-run: while paused, holding the Return key resumes the
      animation at a slow rate; releasing Return returns to the paused
      state (extends the single-step of R-K11)
- [x] (2.3.0, key 'a'; the learn-from-'i' idea was dropped) Auto-reinitialize on "uninteresting" states: detect when the ODCA
      has gone uninteresting and re-initialize cell contents as if 'i'
      were pressed. Defining "uninteresting" is the tricky part; one
      approach is to learn from the user's own 'i' presses — infer over
      time what conditions precede them (e.g. if 'i' consistently follows
      certain cell states disappearing from the state vector, use that as
      the re-init trigger). Likely a mode that can be turned on and off.
- [ ] Status region: a small text area at the top of the display showing
      the current rule ID, whether it has been saved, etc.
- [x] (2.1.0) Extract the toolkit-free orchestration from Viewer into a session
      layer (undo stack, interesting-rule cycle, pause/single-step state,
      stash draining, timing arithmetic) behind a thin display abstraction
      (open window, key events, present pixel grid, tick). Do this before
      the first port so every port inherits the boundary as a blueprint.
      Domain interfaces (Rule, Automaton, evaluate) already serve as the
      abstraction over numpy; no array-level abstraction is wanted.
- [ ] Metal (Swift): GPU-parallel rule screening for the background
      search — one thread per automaton, thousands of rules per dispatch;
      the Swift side's first distinctive feature rather than a port.
      Cycle detection stays on the CPU (serial, O(1) per generation).
- [ ] Test the in-app background search end to end (stash filling,
      instant 'r', workers idling when the stash is full, clean exit) —
      not yet exercised by the user.
- [ ] CI matrix (GitHub Actions, ubuntu + macos) running each
      implementation's headless test suite — set up once a second
      implementation exists
- [ ] Background rule-space searcher: a separate program that runs unattended,
      sweeps random rules through the class heuristics, and accumulates a
      shortlist of Class IV candidates. (User has ideas on this — discuss
      before building.)

## Vision (2026-09-04): mathematics as art

ODCA presents patterns that derive from pure mathematics beautifully
enough to make people think about the relationships between mathematics,
nature, aesthetics, and the human condition. Roadmap, roughly in order:

- [ ] Many more color sets (well beyond ten slots) and a way to bind
      color sets to particular ODCA rules.
- [ ] Screensaver mode — ultimately the main way the art is shown: cycle
      through the most beautiful / interesting / thought-provoking
      rule + color set combinations. Cross-fade transitions (transparency)
      between combinations, and perhaps at auto-init.
- [ ] Layered ODCA: let some colors be transparent so another ODCA
      "beneath" shows through; possibly different color sets and even
      different execution rates per layer.
- [ ] Packaging for distribution: Linux, macOS, iPadOS (iOS not ruled out).
- [ ] Open-source license (attribution + share-alike spirit; must be
      compatible with App Store distribution) and copyright notice.

