# ODCA to-do

**YOU ARE HERE (2026-09-05):** Swift 2.34.0, Python 2.17.0: at par on
every special mode. The color set pool is reviewed (30 kept, 16 dropped).
Both have the two workshop modes (`--colorset-review`,
`--screensaver-review <file>` with `--consistency-check <file>`) and the
first study of the art itself: `--screensaver <file>` plays pairs
sequentially, two minutes each (re-seeding in place when boring, then
handing over after a quiet minute or at the next re-seed), rows keeping
their colors across transitions, N/P by hand. Python skips only the gallery
polish (display-link pacing, resizable window, pointer hiding). Next:
compose and watch screensaver files; then the vision items below, starting
with the declarative script design.

- [x] (2.9.0/2.11.0: slots 0 and 2–9 from colorsets/candidates.json, CoCo
      sets retired; revisit after auditioning all 45) Choose the remaining seven color sets (keys 3–9)
- [ ] "Most interesting of the interesting" score, layered on the 'r'
      screen: (1) how much the cell population's state census varies
      over time — homogeneous rules barely vary, interesting ones swing as
      minorities grow and shrink; (2) mean time-to-boredom from random
      seeds — how many generations, averaged over several seeds, before
      the auto-init detector fires (capped; chaotic never-boring rules
      must be excluded by the existing entropy test, not rewarded).
      Notes: census variance is the positive form of the stagnation
      detector's signal and a cousin of the classifier's input-entropy
      variance (rule-table usage vs. population; the census is closer to
      what the eye sees). Time-to-boredom reuses the exact judgment the
      art uses, hence the more powerful metric, but costs thousands of
      generations per seed: a second stage after the cheap screen, or
      the unattended searcher's job (and later the GPU batch). Build
      first as an offline scorer in the Python lab (2.17.0), rank the
      saved rules and the candidate stash, and check the ranking against
      taste (the vein and glider rules should top it, the stripes rule
      sink) before the score gets any say over 'r'. Caveat (user,
      2026-09-04): long life is not the path to interest by itself — some
      rules are boring after a screenful or two yet *very* interesting
      while alive ("fireworks"). Treat survival and intensity-while-alive
      as separate dimensions; never let time-to-boredom alone sink a
      high-variance rule. Equal screen time with in-place re-seeding
      (2.30.0) already suits fireworks: they go off many times per turn.
- [x] DECIDED (2026-09-05): Python is the laboratory / workbench, Swift the
      gallery (gold-standard smoothness, packaging, tvOS). Python still gets
      every *special mode* because the modes are the workbench; it does not
      chase the gallery polish (display-link pacing, resizable / full-screen
      window, pointer hiding). The odd/even convention stands with the
      direction inverted: Swift leads at even minors, Python ports at odd.
- [x] Python catch-up (2.17.0, 2026-09-05): the pool and active-set model
      with `[`/`]`, arrangements by name and `S` by name; color set review
      (`--colorset-review`); screensaver review and consistency check
      (`--screensaver-review`, `--consistency-check`) with the screen-fill
      on steps; screensaver play (`--screensaver`, watchdog and grace, rows
      keeping their colors, N/P); saved presentations applied by n/p.
      Pygame's window stays fixed-size (resizable optional, not done);
      smoothness is not a goal.
- [ ] Kiosk / public sub-mode for screensaver mode: ignore the keyboard,
      or expose a reduced, safe set of keys (no quitting, nothing that can
      leave the app in a messed-up state) for installations where the
      keyboard is reachable by the public.
- [ ] Key bindings are getting hard to remember and inconsistent across
      modes (normal, color-set review, screensaver review each overload
      s/S/X/N/P). Rethink them as a whole: a consistent scheme, maybe a
      help key or on-screen hint, and a single table in REQTS.
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
- [ ] tvOS app: screensaver mode only, always full screen, one bundled
      screensaver file (and the color set pool) as read-only resources; no
      keyboard assumed — Siri Remote play/pause pauses, swipes step N/P —
      but a paired keyboard works as in screensaver mode. ODCAKit needs no
      changes; the UIKit view mirrors AutomatonView (CALayer +
      CADisplayLink). Needs an Xcode project (XcodeGen), the Developer
      Program, signing, TestFlight, then App Store review; the license must
      be settled first (App Store terms). Agreed order: (1) settle the
      license — a decision, not code; (2) build the tvOS app and run it in
      the simulator — no account needed, and it shows whether the art
      holds up on a big screen; (3) Developer Program membership and the
      one-time Xcode sign-in / device pairing on the user's side;
      (4) TestFlight on the user's own Apple TV; (5) App Store submission,
      artifacts and answers prepared in advance, the web forms walked
      through together.
- [ ] Run straight out of a fresh clone, both sides (user, 2026-09-05).
      Today Python needs a venv and a pip install by hand, and Swift needs
      the toolchain and `swift run` from the right directory. Aim for one
      obvious command per side that works on a new Mac with nothing else
      set up: e.g. a `run` script (or Makefile target) that creates the venv
      and installs requirements on first use, a `swift run` wrapper or
      documented one-liner, and a README quick start at the root that shows
      both. The Swift wrapper must build release: the debug build is choppy
      on any Mac (confirmed on an M1 Ultra, 2026-09-05; the per-frame pixel
      loop is unoptimized), so `swift run -c release odca` is the command.
      Check the Python version floor (3.9 on a stock Mac) and pygame's
      wheel availability on Apple silicon. Precursor to packaging.
- [ ] Packaging for distribution: Linux, macOS, iPadOS (iOS not ruled out).
- [ ] Open-source license (attribution + share-alike spirit; must be
      compatible with App Store distribution) and copyright notice.

