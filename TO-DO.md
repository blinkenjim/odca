# ODCA to-do

**YOU ARE HERE (2026-09-09):** Spec 3.32.0, Swift 3.32.0, Python
3.35.0. Python 3.35.0 (today) swaps upstream `pygame` for `pygame-ce`:
the user's fresh clone on Ubuntu with Python 3.14 could not install,
because upstream has shipped no wheel since 3.13 and the source build
wants SDL headers; the fork has wheels through 3.15 and a newer SDL
(2.32), `import pygame` is unchanged, and `python/run` now explains a
failed install. An existing `.venv` must be removed, not upgraded, as
the two cannot share one. Awaiting the user's word that Ubuntu and the
Pi are happy. Before that, spec 3.32.0: the show script has `import <file>`, `play`, and `shuffle`
(R-X7; the user, 2026-09-08: "the shuffle is a verb, so it's not `play
shuffle` but simply `shuffle`" — both words are verbs, a script says
one of them). Python now line-buffers its output as Swift does. `odca` plays a show of one or more files, each a play script
(`.play`, `#` comments) or an odca file, which plays as a script that
imports it. `--shuffle` on the command line draws the order of the
*files* per pass (never the same file twice running); `shuffle` in
a script draws the order of *its own pairs* per pass, under the 3.12.0
constraints (no rule and no color set follows itself, seams across
files included, a hundred draws then the last one). The parser is one
flex/bison grammar in `script/` (`script/regen`) generating C that is
checked in beside both implementations (`swift/Sources/CShow`, a
SwiftPM C target; `python/odca/cshow`, compiled by `setup.py` at
install and loaded through ctypes) and emits JSON;
`conformance/scripts/` pins its output byte for byte. Errors stop
`odca` before any window, with line and column. The language grows by
experimentation (user, 2026-09-08); the next statements are the user's
call, `watchdog N` / `grace N` being the obvious candidates. Before this, 3.26.0 / 3.27.0: "look" is "pair" throughout, pairs
are named `pair-NNNN` by odca-select, and `--2` is the default cell
size. Before that, 3.24.0 /
3.25.0: `n`/`p` in odca-select re-seed and scroll the pair in, as odca's
transitions do (the 2.24.1 screen fill withdrawn as jarring). Before
that, 3.22.0 / 3.23.0: a mutated pair is saved as a new pair, never over the kept rule
(the 3.16.0 in-place model overwrote one of the user's best rules; it
was recovered from git). Pending at the next change: `--2` as the
default cell size (item below). Before that, 3.20.0 / 3.21.0: `--3`
joins the cell size flags. Before that (2026-09-06),
3.18.0 / 3.19.0: `U` undoes every rule change since the position last
moved (R-K19). Before that, 3.16.0 / 3.17.0: `m` on a pair under review is an
edit of it, recorded in place by `s` (the user found `s` appending after
`m`). Before that, 3.14.0 /
3.15.0: `odca --watchdog SECONDS --grace SECONDS` (defaults still 120 /
60; the user will change them later, and REQ-swift / REQ-python list the
places that hold the numbers). Before that, 3.12.0 / 3.13.0: the shuffle
constraints (no rule or color set follows itself,
seams included; a hundred draws then a plain shuffle). Before that, 3.10.0 /
3.11.0: cell size flags `--4` / `--2` / `--1` on both programs (the
user's "fun side path"), with the starting speed doubling per halving of
the cell; the user thinks `--2` "might end up being the sweet spot" but
`--4` stays the default for now. The user reports the Python version "almost
indistinguishable" from Swift on the M5 MacBook Pro; Pi testing on hold.
Before that, 3.6.0 / 3.7.0: `F` toggles full screen (R-K18), and
`python/run` / `swift/run` run either program straight out of a fresh
clone. The user's stated heading
after these: the layers mode ("where we're headed"); the color set tool
can wait. Before that, 3.4.0 / 3.5.0:
`odca --fullscreen`, step two of three for the portrait installation
(step three, the detector windows on a 480-row screen, waits for the
user's Pi). Before that, 3.2.0 / 3.3.0: rows keep their colors for good in `odca` (per-row palette table; the
two-bank limitation is gone), after the user saw `N` recolor the whole
screen. The 3.1.1 test verdict on the Mac: "velvety smooth at slow
speeds and blasts the frames out at high speed". Before that, Python
3.1.1 moved drawing onto SDL's
renderer: one texel per cell, GPU scaling, vsync pacing — the first of
three agreed steps toward the portrait art installation (next: launching
full screen unattended, then the boring detector windows on a 480-row
screen); the Pi is away, so the Mac is the test bed. Before it, Python
3.1.0 brought the pygame window to parity with Swift's: resizable, full screen through the platform's own
control, centered grid with margins for the remainder, a 2048-row history
that a taller window uncovers, frozen during the drag, pointer hidden in
full screen (a heuristic, since SDL does not flag a macOS full screen
Space). It also fixed `R` in the Python odca-select, which had been read
as `r`. 3.0.x before it: one program became two (`odca <file.odca>
[--shuffle]` plays, `odca-select <file.odca>` composes; keeper file
`interesting.odca`, color set pool `library.json`; color set review on
hold until it becomes its own program); Swift 3.0.1 fixed the missing
window. The user ran the Python player on a Raspberry Pi 5 (1 GB) with a
few display glitches; the GPU / vsync experiment is an item below. Next:
use odca-select to build a show and watch it, the shuffle constraints,
the color set tool, and the vision items, starting with the declarative
script design.

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
      Pygame's window stayed fixed-size then (now its own item below);
      smoothness is not a goal.
- [x] (3.0.0: the keeper file *is* an odca file, `interesting.odca`;
      `odca-select interesting.odca` or a copy of it is the seed) Seed a
      screensaver file from the keeper file (user question, 2026-09-05).
- [x] (3.1.0, 2026-09-06) Python window parity (user, 2026-09-06, after
      the first odca test): a resizable pygame window with full screen,
      following R-U2/R-U8 as Swift does (grid of whole cells, picture kept
      centered while cells appear or vanish at the edges, deep history so
      a taller window uncovers older rows, frozen during a live resize,
      pointer hidden in full screen). Reversed the 2026-09-05 decision that
      the resizable window was Swift-only polish; display-link pacing
      stays out of scope. PT-32 applies to Python too.
- [x] (3.6.0/3.7.0, 2026-09-06: `F`, R-K18) Keyboard full screen toggle
      (from 3.1.0): pygame has no green button on Linux, so the Pi relied
      on the window manager.
- [ ] Pi display glitches (user, 2026-09-06: a Pi 5 with 1 GB "did well,
      but I saw a few display glitches"). Untested hypotheses: tearing
      from an unsynced blit, or dropped frames from the per-frame scale.
      First experiment: `set_mode(..., vsync=1)` (accepted by SDL 2.28 on
      macOS; unknown on the Pi, so guard with a fallback). Second: draw
      through `pygame._sdl2.video` (`Renderer` + streaming `Texture`),
      which is the GPU path with vsync and keeps the resizable window;
      the frame then uploads once per refresh instead of being scaled on
      the CPU. Needs the Pi to decide; ask what the glitches look like
      (horizontal tears vs stutters).
- [ ] Art installation target (user, 2026-09-06): `odca` full screen on a
      1080p monitor in portrait, 1080 wide by 1920 tall, most likely on
      the Pi 5. At cell 4 that is a 270 x 480 grid: a narrow automaton
      and a tall screen. Implications to settle: (1) DONE 3.4.0/3.5.0:
      `odca --fullscreen`; (2) the screenful-based windows (R-A1,
      R-K13/14, R-X) scale with `rows` = 480, so repetition looks back
      4800 rows and stagnation 1920 — check the detectors still fire at
      the right moment on a tall screen, or size those windows in cells
      rather than screens (parked, user, 2026-09-06; needs no Pi: the
      detectors are functions of `rows`, so a headless 270 x 480 Session
      gives exact time-to-boredom per pair, and a 480-row screen fits a
      Mac at 2-point cells through `Viewer(cell_size=2)`, which the
      command line does not expose); (3) whether 4 px cells are right on a 1080-wide
      portrait panel viewed from gallery distance (`--2` / `--1` exist
      since 3.8.0/3.9.0; the choice itself waits for the panel); (4) the display
      rotation is the OS's job; (5) the Pi stutters (user, 2026-09-06:
      "stutters more than tears"): at 1080 x 1920 the CPU path scales two
      million pixels per frame, the strongest reason yet for the GPU
      display path above; also the background search takes cpu_count - 1
      workers (three of the Pi's four cores) until the stash fills, and
      each worker process carries a numpy import, which on 1 GB matters —
      consider fewer workers, or none, in play mode on small machines.
- [x] (3.26.0/3.27.0, 2026-09-08; the delay table kept, so a plain run
      is the old `--2`) Make `--2` the default cell size at the next
      change (user, 2026-09-07: "a nice intermediate size" of `--3`, then
      "at the next change, let's make --2 the default"). Places: `ViewerModel.cellSize`
      and `chooseCellSize`'s fallback (Swift); `cli.cell_size`'s fallback,
      `cli.run(cell=)`, `Viewer(cell_size=)` (Python); the help texts
      ("cells 4 (the default)"); R-U2 ("4 by default", "`--4` names the
      default", the 300 × 200 default grid and the 40 × 30 minimum, which
      become 600 × 400 and 80 × 60); R-U5 if the speed rule is re-based;
      TESTS PT-35 / M-13; the README paragraph; `test_viewer`'s
      `grid_size` cases. Open question for the user: does the default
      speed stay 1/60 s at the new default cell (so `--4` becomes slower,
      `--1` twice as fast as today) or does the cell-to-delay table stay
      as it is (so the default run becomes 1/120 s, today's `--2`)?
- [ ] New watchdog / grace defaults (user, 2026-09-06: 20 and 10 were
      the first values named; "we will be changing them later"). Places:
      `Session.playTimeout` / `playGrace` (Swift), `PLAY_TIMEOUT` /
      `PLAY_GRACE` (Python), the help text prose ("two minutes", "a quiet
      minute") and the flag descriptions, R-X2 / R-X3, the README bullet,
      PT-31's literal seconds in TESTS.md and both PT-31 tests.
- [ ] Window size and position memory for pygame (R-U2 "may"): SDL has no
      frame autosave; would be a file under `~/.odca/`.
- [x] (3.12.0/3.13.0, 2026-09-06: no rule or color set, in any
      arrangement, follows itself, seams included; a hundred draws then a
      plain shuffle) Shuffle constraints for `odca --shuffle` (user,
      2026-09-05: "subject to certain constraints which I'll describe
      later"). 3.0.0 shipped the minimum: a fresh permutation per pass that
      never opens on the pair that closed the previous pass.
- [ ] Color set tool: color set review (REQTS 4b, on hold, no program binds
      it in 3.0.0) returns as its own executable (`odca-colors`?) once the
      color set workflow is taken up again; baking an arrangement into the
      library (R-K16, `S` until 3.0.0) belongs to it too. The session code
      and tests are kept alive meanwhile.
- [ ] `u` restores the rule only: the color set on screen and the n/p
      position stay where they were, so after an undo the screen can show a
      pair's rule while the cycle points elsewhere (noted 2026-09-05; the
      user agreed to leave it). Since 3.16.0 this only arises after `r`:
      `m` on a pair keeps the position, so `u` there is clean. Revisit
      with the key-binding rethink.
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
      different execution rates per layer. Scriptable blend modes between
      layers (user, 2026-09-06), not only alpha. Note for the Pi: layers
      that share the cell grid can be composed at cell resolution (tens of
      thousands of cells, one numpy expression) and scaled once, so plain
      alpha layering is cheap on the CPU; per-pixel blend modes on the
      full window and the final scale are what want the GPU. See the
      display path item below.
- [ ] Overlay band (user, 2026-09-06): white text over a smoke-gray,
      semi-transparent background across the top of the screen, for the
      screensaver (what it says is open: rule, pair, script state).
      pygame can do it on the CPU (a font surface and an alpha blit of a
      full-width band are a fraction of a millisecond, even on a Pi 5);
      on Swift it is a CATextLayer over the grid layer. Belongs to the
      script design: the band is a scripted element, not a key.
- [x] (3.1.1, 2026-09-06; Pi untested, the user's Pi is away) GPU display
      path for Python (user, 2026-09-06, anticipating layers, blend modes,
      and the overlay on a Pi 5): render through SDL's renderer
      (`pygame._sdl2.video` `Renderer` + a streaming `Texture`, one texel
      per cell) so the GPU scales and presents with vsync; each future
      layer and the overlay becomes another texture with SDL's blend
      modes (blend, add, modulate, multiply) for free; the automaton stays
      in numpy. Swift already has this through CALayer compositing. Agreed
      order (user, 2026-09-06): this, then launching full screen
      unattended, then the detector windows on a tall screen.
- [x] Data flow to match the workflow (user, 2026-09-05; the jq merge of
      two pair files was the last straw). DONE in 3.0.0, with the design
      revised in discussion before building:
      - `library.json` at the repo root holds the color sets only (the
        former colorsets.json content: sets with optional slots, dropped
        names). JSON, not sqlite: git-diffable, no dependency, the
        byte-identical two-writer discipline already exists.
      - Pairs (rule + color set name + arranged colors) live in *odca
        files* (`.odca`, JSON `{"pairs": [...]}`), one per show, named on
        the command line; `interesting.odca` replaces interesting-rules.json.
        Pairs are self-contained, so a file plays without the library.
      - Rules are NOT named (user reversal, 2026-09-05): the 20-digit ID
        stays; if names are ever needed they will be programmatic
        (rule001, pair001).
      - Two programs instead of flags: `odca <file.odca> [--shuffle]` plays,
        `odca-select <file.odca>` composes (n/p over the file's pairs, s/S
        save, X delete, R grouped order). Color set review is on hold.
      - Scripts stay text files (below); until the language exists an odca
        file is the show.
- [ ] Blast key (user, 2026-09-08: "What was the key to blast a screenful
      of rows onto the display? I'd like to resurrect that feature"):
      there never was one — the screen fill was what `n`/`p` did in
      odca-select from 2.24.1 to 3.24.0. Proposed `b`, a screenful at
      once in every mode (R-K20); awaiting the user's word.
- [ ] Scriptable screensaver mode (the interactive mode absorbs the same
      ability). In progress since 3.28.0: play scripts (`import`,
      `play`, `shuffle`; R-X7) on a flex/bison C parser shared by both
      implementations (`script/`), grown by experimentation, one
      statement at a time; candidates next: `watchdog N` and `grace N`,
      then pools, events, and transitions. The vision, as
      first written: a declarative, not procedural, script language that can
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
- [x] (2026-09-06: `python/run` and `swift/run`, program name first,
      root README quick start) Run straight out of a fresh clone, both sides (user, 2026-09-05).
      Today Python needs a venv and a pip install by hand, and Swift needs
      the toolchain and `swift run` from the right directory. Aim for one
      obvious command per side that works on a new Mac with nothing else
      set up: e.g. a `run` script (or Makefile target) that creates the venv
      and installs requirements on first use, a `swift run` wrapper or
      documented one-liner, and a README quick start at the root that shows
      both. 3.0.0 did the Python half's packaging (`pyproject.toml` with
      console scripts; the stock pip needs `pip install --upgrade pip
      setuptools` first). The user's MacPorts Python 3.14 at /opt/local/bin
      would skip that upgrade, but pygame publishes no 3.14 wheel yet
      (checked 2026-09-06), so stock 3.9 stays the documented path until
      it does. The Swift wrapper must build release: the debug build is choppy
      on any Mac (confirmed on an M1 Pro, 2026-09-05; the per-frame pixel
      loop is unoptimized), so `swift run -c release odca` is the command.
      Check the Python version floor (3.9 on a stock Mac) and pygame's
      wheel availability on Apple silicon. Precursor to packaging.
- [ ] Packaging for distribution: Linux, macOS, iPadOS (iOS not ruled out).
- [ ] Open-source license (attribution + share-alike spirit; must be
      compatible with App Store distribution) and copyright notice.

