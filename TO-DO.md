# ODCA to-do

**YOU ARE HERE (2026-09-04):** Python 2.15.0 and Swift 2.18.0 have feature
parity (auto-init on by default; continuous scrolling below 30 gen/s) (the Swift catch-up ported auto-init with all detectors and
Brent's, paused 's' and the screen counter, and file-backed color sets
with c/C/S). Next: (a) audition all 45 palettes (colorsets/audition.png)
and finalize the slots; (b) the vision items below, starting with the
declarative screensaver script design.

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
nature, aesthetics, and the human condition. Behaviors are part of the
art too, not only colors: the auto-init filter — what counts as boring,
and how and when to re-initialize — is a curated choice about what the
viewer sees. Roadmap, roughly in order:

- [ ] Many more color sets (well beyond ten slots) and a way to bind
      color sets to particular ODCA rules.
- [ ] Screensaver mode — ultimately the main way the art is shown: cycle
      through the most beautiful / interesting / thought-provoking
      rule + color set combinations. Cross-fade transitions (transparency)
      between combinations, and perhaps at auto-init.
- [ ] Layered ODCA: let some colors be transparent so another ODCA
      "beneath" shows through; possibly different color sets and even
      different execution rates per layer.
- [ ] Scriptable screensaver mode (the interactive mode absorbs the same
      ability): a declarative, not procedural, script language that can
      intermix ODCA rules (the interesting ones), specify how rules
      interact via transparency layering, choose transition effects, and
      assign probabilities to rules, color sets, and intermixes so that
      interesting sequences emerge naturally rather than being fixed.
      Design the language before building; it will shape the layering
      and transition work above. A starting observation: the language's
      first nouns already exist — the interesting-rules keeper file and
      the color sets file — and its first events are the auto-init
      reasons (`extinct`, `repeating (period N)`, `stagnant`). A
      declarative script that says

          when this rule goes stagnant,
          cross-fade to something from this weighted pool

      would be describing behavior the program already has the
      vocabulary for. The rules run; the filter listens; the script
      decides what the eye sees next.
- [ ] Native macOS screensaver (.saver bundle, built on the ScreenSaver
      framework — ScreenSaverView — or whatever Apple currently provides):
      installed through the OS mechanism, selectable as the active system
      screensaver, and activated by macOS when needed. Power-aware: on
      battery, run in a low-power state (drastically slowed, background
      Class IV hunter paused, etc.); on charger, full speed or a bit
      faster. Shares ODCAKit and the screensaver-mode script with the app.
- [ ] Plain macOS app with a screensaver mode: generates the same
      displays the same way, from the same script, with no need to
      install anything as a screensaver. Separate delivery target from
      the .saver bundle.
- [ ] Packaging for distribution: Linux, macOS, iPadOS (iOS not ruled out).
- [ ] Open-source license (attribution + share-alike spirit; must be
      compatible with App Store distribution) and copyright notice.

