# ODCA — One-Dimensional Cellular Automata

An interactive viewer for a four-state, radius-1, count-based cellular
automaton — a reproduction of a design originally written for the 6809E in a
TRS-80 Color Computer.

Each cell is in one of 4 states. A cell's next state depends only on the
*counts* of each state among its 3-cell neighborhood (left, self, right) —
not on which cell holds which state. There are 20 possible count vectors, so
a rule is a table of 20 next states: a rule space of 4²⁰ ≈ 1.1 trillion.

A rule's shareable ID is its 20 next-states as base-4 digits. The lookup
keeps the original's summing trick: weighted states make the plain
neighborhood sum a unique index into the rule table.

## Quick start

```sh
git clone https://github.com/blinkenjim/odca.git
cd odca
python/run odca interesting.odca      # Python: makes its venv on first use (needs python3 >= 3.9)
swift/run odca interesting.odca       # Swift, macOS: builds release on first use (needs Xcode)
```

Either plays the looks kept so far; press `F` for full screen, `q` to
quit. `python/run odca-select my.odca` (or `swift/run odca-select my.odca`)
composes a show of your own. `--help` on either program lists the keys.

## Repository layout

This is a monorepo: the specification and conformance data live at the
root and are shared by every implementation; each implementation lives in
its own directory.

| path | contents |
|------|----------|
| `REQTS.md` | language-independent requirements — the program can be re-created from this document alone |
| `TESTS.md` | normative test plan for all implementations |
| `conformance/vectors.json` | golden engine vectors every implementation must pass |
| `library.json` | the color set pool, shared by both implementations |
| `interesting.odca` | the looks (rule + color set) kept so far — an odca file, playable with `odca interesting.odca` |
| `conformance/` | golden engine vectors and the `--help` texts, byte-identical across implementations |
| `python/` | the reference implementation (Python + pygame); see `python/README.md` |
| `REQ-python.md` | implementation notes for the Python version |
| `swift/` | Swift implementation (macOS, `swift/run odca <file.odca>`); see `swift/README.md` |
| `REQ-swift.md` | implementation notes for the Swift version |

Planned: `cpp/`.

## Versioning

Semantic versioning across the whole code base, with one convention for
the two implementations: Swift is the gallery and leads at **even** minor
versions (2.30.0, 2.34.0, …); Python is the laboratory and catches up on
every special mode at the following **odd** minor (2.17.0, …), skipping
only gallery polish such as display-link pacing. (Before 2.16 the direction was the reverse: Python first at
odd minors, Swift porting at even.) The specification (`REQTS.md`) carries
the version at which its behavior last changed. MAJOR = incompatible
change, MINOR = new or changed behavior, PATCH = fixes and
clarifications. Each implementation exposes its version (Python:
`odca.__version__`; Swift: `ODCAKit.odcaVersion`). Releases are
git-tagged (`v2.0.0`, `v2.1.0`, …).

## Using the programs

There are two programs, sharing the engine and most of the keyboard:

- **`odca <file.odca> [--shuffle] [--fullscreen] [--4 | --2 | --1]`** plays the *looks* in an odca file,
  one after another, looping. A look is a rule with a color set. Every look
  gets two minutes of screen time, re-seeding in place whenever it goes
  boring; then it hands over after a quiet minute or at the next re-seed,
  and the next look grows in from a fresh field below the old rows, which
  keep their colors. `--shuffle` plays each pass in a fresh random order;
  `--fullscreen` opens full screen at once, for unattended runs.
  `N`/`P` (or `n`/`p`) step by hand. The file is never written.
- **`odca-select <file.odca> [--4 | --2 | --1]`** is the workbench that composes them: it
  shows screened random rules, you dress each in a color set, and `s`/`S`
  save the result as a look in the named file (created if missing). `n`/`p`
  cycle through the file's looks and one extra slot holding the unsaved
  rule you were exploring; every step fills the screen with the selected
  look. `X` deletes the look under review; `R` toggles the `n`/`p` order
  between file order and grouped by rule (the screen inverts briefly to
  confirm). The file is written after every change and at exit.

`odca --help` and `odca-select --help` print the flags and keys (the same
text from both implementations). On startup the programs load the previous
rule (from `~/.odca/rule`, random on first run) and initialize all cells to
random contents; `odca-select` on a file with looks then opens on look 1,
and `odca` plays look 1. Rule IDs are printed to the terminal at startup
and whenever the rule changes.

While a program runs, worker processes on all spare cores continuously
generate and screen random rules for possible Wolfram Class IV behavior;
finds are stashed (up to 64, persisted in `~/.odca/candidates`) so `r`
answers instantly. Once the stash is full the workers idle until you
consume candidates.

### Controls

| Key | Action                                       |
|-----|----------------------------------------------|
| r   | new random rule, screened for maybe-Class-IV behavior (ID printed) |
| m   | mutate the rule: one entry changes to a new state |
| u   | undo the last rule change (repeatable)       |
| i   | initialize all cells to random contents      |
| n / p | odca-select: next / previous look, or the unsaved rule, with its colors (every step fills the screen); odca: as N / P |
| s   | odca-select: rewrite the look under review with the color set on screen, or append the screen as a new look when on the unsaved rule; while paused (both programs): run one screenful at 8× speed, then stay paused (press again to queue more) |
| S   | odca-select: append a copy of what is on screen as a new look |
| X   | odca-select: delete the look under review |
| R   | odca-select: toggle the n / p order between file order and grouped by rule (the screen inverts for a quarter second) |
| N / P | odca: next / previous look by hand, with a fresh seed |
| +   | speed up (halve the delay between generations); slower than twice the starting delay (30 generations/s at the default cell size) the scroll is continuous |
| -   | slow down (double the delay between generations) |
| 0-9 | select a color set                           |
| [ / ] | step backward / forward through the whole color set pool (the digits reach only the "hot ten") |
| F   | toggle full screen                           |
| c   | cycle the current color set through its 24 color-to-state arrangements |
| C   | the same cycle in reverse |
| space | pause / resume (while paused, only space, return, `s`, the color keys `c`/`C`/`[`/`]`/digits, the look keys, `F`, and `q` are live); resuming starts a screen counter that prints `screen N` after every screenful |
| return | while paused: single-step one generation, staying paused |
| a   | toggle auto-init: once every row on screen is boring (a producible state extinct with no minority state still alive, a cycle of any period (detected by Brent's algorithm, period printed) or a row repeating one from the last ten screens, or a minority population stagnant for four screens), re-initialize the cells as `i` does; on at startup |
| q   | quit                                         |

The window is resizable, with full screen available through the platform's
own control (the green button on macOS); the grid holds as many whole
cells as fit (4 points on a side by default; `--2` and `--1` on either
program choose smaller cells for the run, and the automaton runs two and
four times as fast so the picture moves at the same speed), centered, and the automaton's width follows the
window, keeping the picture centered while cells appear or vanish at the
edges. A taller window uncovers remembered rows. Swift snaps the window to
whole cells; pygame paints the remainder as thin margins.

The `n`/`p` cycle in `odca-select` includes one extra slot holding the
unsaved rule that was running before browsing began: stepping past the last
look (or back from look 1) returns to it. Pressing `r` or `m` makes the new
rule occupy that unsaved slot and repositions the cycle on it. A file that
already has looks opens on look 1 with the unsaved slot empty until `r` or
`m` fires.

Color sets come from `library.json` at the repository root (shared by every
implementation). **1** is the default set (near-black, off-white, amber,
blue), active at startup; the others are palettes from coolors.co: **0** Mysterious Midnight Magic; **2** Fiery Ice Cream Delight; **3** Golden Autumn Twilight; **4** Midnight Sun Dance; **5** Seaside Serenity; **6** Cherry Blossom Sky; **7** Ocean Sunset Vibes; **8** Jungle Safari Adventure; **9** Mystic Moonlight Shades.
`c` cycles the current set through the 24 ways of assigning its four
colors to the four states, and a look records the arranged colors. The
library is also the pool of every kept color set, reached with `[` and
`]`. Reviewing the pool itself (the 2.x `--colorset-review`) is on hold
until it returns as its own program.

An odca file is JSON: `{"looks": [{"rule": "<20 digits>", "colorset":
"<name>", "colors": ["#RRGGBB", ...]}, ...]}`. `interesting.odca` at the
root holds the looks kept so far; try `odca interesting.odca`.
