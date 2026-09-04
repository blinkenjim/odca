# ODCA to-do

**YOU ARE HERE (2026-09-03):** resume the review of the auto-init
"boring filter" (versions 2.3.0–2.7.0) against the saved rules in
interesting-rules.txt. Several were checked and behaved correctly at
default speed; continue where you left off. Feature work resumes with
Python 2.9.0 (or the Swift catch-up at 2.8.0).

- [ ] Choose the remaining seven color sets (keys 3–9)
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
