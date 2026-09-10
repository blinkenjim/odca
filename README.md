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

Either plays the pairs kept so far; press `F` for full screen, `q` to
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
| `interesting.odca` | the pairs (rule + color set) kept so far — an odca file, playable with `odca interesting.odca` |
| `conformance/` | golden engine vectors, the `--help` texts, and the play script cases (`scripts/`), byte-identical across implementations |
| `script/` | the play script grammar (`show.l`, `show.y`) and `regen`, which generates the C parser into both implementations |
| `python/` | the reference implementation (Python + pygame-ce); see `python/README.md` |
| `REQ-python.md` | implementation notes for the Python version |
| `swift/` | Swift implementation (macOS, `swift/run odca <file>`); see `swift/README.md` |
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

There are three programs sharing one engine, two of them sharing most of
the keyboard:

- **`odca <file> [<file> ...] [--shuffle] [--fullscreen] [--4 | --3 | --2 | --1] [--watchdog N] [--grace N]`** plays a *show*: the
  *pairs* of one or more files, one after another, looping. A pair is a
  rule with a color set; a file is a play script (below) or an odca
  file, which plays as a script that imports it. Every pair gets two
  minutes of screen time, re-seeding in place whenever it goes boring;
  then it hands over after a quiet minute or at the next re-seed, and
  the next pair grows in from a fresh field below the old rows, which
  keep their colors. The files play in turn, each its pairs in order;
  `--shuffle` draws a fresh order of the files each pass (never the same
  file twice running) and leaves the pairs within a file in the order
  its script asks for;
  `--fullscreen` opens full screen at once, for unattended runs;
  `--watchdog` and `--grace` set the two clocks in whole seconds (120 and
  60 by default).
  `N`/`P` (or `n`/`p`) step by hand. No file is written.
- **`odca <file.odca> [<file.odca> ...] --longest [--shuffle] [--cells N]`**
  plays the seeds `odca-evolve` recorded instead: for every pair with
  seeds at the width, its longest-lived seed, then every pair's second
  longest, and so on, looping; each runs to the extinction that was
  measured, with no watchdog. Seeds that survived the cap are left out,
  so a rule with nothing but survivors drops out of the show. The window
  opens as wide as the seeds, and the picture is scaled to whatever
  width the window or screen has, cells staying square. The generation
  count stands in the lower-left corner, yellow on black; `o` hides it.
  A double-click on the title bar of a resized window returns it to its
  natural size; on a window already that size it zooms as usual.
  `--shuffle` mixes the seeds under the usual no-repeat rule; `--cells`
  picks the width when the files record more than one. The rule keys do
  nothing; `i` restarts the seed on screen.
- **`odca-evolve <file.odca> --cells N --time SECONDS [--cap N]`** (Swift
  only, for now) searches each rule in the file for the starting rows
  that keep it alive longest at a width of N cells: random rows evolved
  until a state dies out, the ten longest-lived kept and written back
  into the file, `--time` seconds per rule, every processor at work. It
  opens no window. `odca` then starts a pair from its best seed whenever
  the file has one for exactly the width on screen. A recorded row that
  outlives the cap (100000 generations by default) is kept as `survived`.
- **`odca-select <file.odca> [--longest] [--4 | --3 | --2 | --1]`** is the workbench that composes them: it
  shows screened random rules, you dress each in a color set, and `s`/`S`
  save the result as a pair in the named file (created if missing). `n`/`p`
  cycle through the file's pairs and one extra slot holding the unsaved
  rule you were exploring; every step re-seeds the cells and the selected
  pair scrolls in from a fresh field, as a transition does in `odca`. `X`
  deletes the pair under review; `R` toggles the `n`/`p` order
  between file order and grouped by rule (the screen inverts briefly to
  confirm). The file is written after every change and at exit.
  `--longest` presents only the pairs whose rule has seeds, for curating
  what `odca --longest` plays: `X` then deletes the rule's seeds rather
  than the pair, and a pair saved on a rule without seeds (`s` after
  `m`, or `S` after `r`) is kept in the file but not shown.

A **play script** (`.play`) says what to play, one statement per line,
`#` for comments:

```
# my-show.play
import interesting.odca        # relative to the script's directory
import "sunday pairs.odca"     # quote a name with spaces
shuffle                        # every pair imported above, once each
```

`play` plays them in the order they were imported. `shuffle` says the
same thing but draws a fresh order each pass, in which no rule and no
color set follows itself, the seam between passes included, so nothing
repeats where the eye would notice. A script says one of the two, and
one of them ends its imports.

`odca my-show.play` plays it; `odca a.play b.play c.odca --shuffle`
plays three files in a fresh order each pass. A script that never says
`play` plays nothing, and the first error (a misspelled statement, a
missing import) stops `odca` with the line and column before any window
opens. That is the whole language so far, `import`, `play`, and `shuffle`; it
grows by increments (see
`REQTS.md` R-X7 and `TO-DO.md`). The parser is one C program generated
by flex and bison from `script/` and shared by both implementations.

`--help` on any of the three prints its flags and keys (the same text
from both implementations). On startup the programs load the previous
rule (from `~/.odca/rule`, random on first run) and initialize all cells to
random contents; `odca-select` on a file with pairs then opens on pair 1,
and `odca` plays pair 1. Rule IDs are printed to the terminal at startup
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
| m   | mutate the rule: one entry changes to a new state (in odca-select on a pair: the pair is changed, and `s`/`S` save the mutant as a new pair, never over the kept rule; `u`/`U` walk it back, `n`/`p` drop it) |
| u   | undo the last rule change (repeatable)       |
| U   | undo every rule change since arriving on the current pair or rule, at once |
| i   | initialize all cells to random contents      |
| n / p | odca-select: next / previous pair, or the unsaved rule, with its colors (every step re-seeds and scrolls the pair in); odca: as N / P |
| s   | odca-select: rewrite the pair under review's colors in place, or append the screen as a new pair (moving onto it) when its rule was mutated, or when on the unsaved rule; while paused (both programs): run one screenful at 8× speed, then stay paused (press again to queue more) |
| S   | odca-select: append a copy of what is on screen as a new pair |
| X   | odca-select: delete the pair under review |
| R   | odca-select: toggle the n / p order between file order and grouped by rule (the screen inverts for a quarter second) |
| N / P | odca: next / previous pair by hand, with a fresh seed |
| +   | speed up (halve the delay between generations); slower than twice the starting delay (60 generations/s at the default cell size) the scroll is continuous |
| -   | slow down (double the delay between generations) |
| 0-9 | select a color set                           |
| [ / ] | step backward / forward through the whole color set pool (the digits reach only the "hot ten") |
| F   | toggle full screen                           |
| c   | cycle the current color set through its 24 color-to-state arrangements |
| C   | the same cycle in reverse |
| space | pause / resume (while paused, only space, return, `s`, the color keys `c`/`C`/`[`/`]`/digits, the pair keys, `F`, and `q` are live); resuming starts a screen counter that prints `screen N` after every screenful |
| return | while paused: single-step one generation, staying paused |
| a   | toggle auto-init: once every row on screen is boring (a producible state extinct with no minority state still alive, a cycle of any period (detected by Brent's algorithm, period printed) or a row repeating one from the last ten screens, or a minority population stagnant for four screens), re-initialize the cells as `i` does; on at startup |
| q   | quit                                         |

The window is resizable, with full screen available through the platform's
own control (the green button on macOS); the grid holds as many whole
cells as fit (2 points on a side by default; `--4`, `--3`, and `--1` on
either program choose another size for the run, and the automaton's
speed follows the cell so the picture moves at the same speed), centered, and the automaton's width follows the
window, keeping the picture centered while cells appear or vanish at the
edges. A taller window uncovers remembered rows. Swift snaps the window to
whole cells; pygame paints the remainder as thin margins.

The `n`/`p` cycle in `odca-select` includes one extra slot holding the
unsaved rule that was running before browsing began: stepping past the last
pair (or back from pair 1) returns to it. Pressing `r` or `m` makes the new
rule occupy that unsaved slot and repositions the cycle on it. A file that
already has pairs opens on pair 1 with the unsaved slot empty until `r` or
`m` fires.

Color sets come from `library.json` at the repository root (shared by every
implementation). **1** is the default set (near-black, off-white, amber,
blue), active at startup; the others are palettes from coolors.co: **0** Mysterious Midnight Magic; **2** Fiery Ice Cream Delight; **3** Golden Autumn Twilight; **4** Midnight Sun Dance; **5** Seaside Serenity; **6** Cherry Blossom Sky; **7** Ocean Sunset Vibes; **8** Jungle Safari Adventure; **9** Mystic Moonlight Shades.
`c` cycles the current set through the 24 ways of assigning its four
colors to the four states, and a pair records the arranged colors. The
library is also the pool of every kept color set, reached with `[` and
`]`. Reviewing the pool itself (the 2.x `--colorset-review`) is on hold
until it returns as its own program.

An odca file is JSON: `{"pairs": [{"rule": "<20 digits>", "colorset":
"<name>", "colors": ["#RRGGBB", ...]}, ...]}`, plus a `seeds` section by
rule and width once `odca-evolve` has written one. `interesting.odca` at the
root holds the pairs kept so far; try `odca interesting.odca`.
