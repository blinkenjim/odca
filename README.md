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

## Repository layout

This is a monorepo: the specification and conformance data live at the
root and are shared by every implementation; each implementation lives in
its own directory.

| path | contents |
|------|----------|
| `REQTS.md` | language-independent requirements — the program can be re-created from this document alone |
| `TESTS.md` | normative test plan for all implementations |
| `conformance/vectors.json` | golden engine vectors every implementation must pass |
| `interesting-rules.txt` | the shared collection of saved rules (`rule <id>` per line) |
| `python/` | the reference implementation (Python + pygame); see `python/README.md` |
| `REQ-python.md` | implementation notes for the Python version |
| `swift/` | Swift/SwiftUI implementation (macOS); see `swift/README.md` |
| `REQ-swift.md` | implementation notes for the Swift version |

Planned: `cpp/`.

## Versioning

Semantic versioning across the whole code base, with one convention for
the two implementations: new work is developed in Python first at **odd**
minor versions (2.1.0, 2.3.0, …) and ported to Swift at the following
**even** minor (2.2.0, 2.4.0, …), so an even release means both
implementations agree on features. The specification (`REQTS.md`) carries
the version at which its behavior last changed. MAJOR = incompatible
change, MINOR = new or changed behavior, PATCH = fixes and
clarifications. Each implementation exposes its version (Python:
`odca.__version__`; Swift: `ODCAKit.odcaVersion`). Releases are
git-tagged (`v2.0.0`, `v2.1.0`, …).

## Using the program

On startup the program loads its previous rule (from `~/.odca/rule`, random
on first run) and initializes all cells to random contents. Rule IDs are
printed to the terminal at startup and whenever the rule changes.

While the program runs, worker processes on all spare cores continuously
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
| s   | save the current rule to interesting-rules.txt; while paused: run one screenful at 8× speed, then stay paused (press again to queue more) |
| n   | next saved interesting rule (first press: rule 0) |
| p   | previous saved interesting rule (first press: last rule) |
| i   | initialize all cells to random contents      |
| +   | speed up (halve the delay between generations); below 30 generations/s the scroll is continuous |
| -   | slow down (double the delay between generations) |
| 0-9 | select a color set                           |
| c   | cycle the current color set through its 24 color-to-state arrangements |
| C   | the same cycle in reverse |
| S   | save the current color set (with its arrangement) to colorsets/colorsets.json |
| space | pause / resume (while paused, only space, return, `s`, the color keys `c`/`C`/`S`/digits, and `q` are live); resuming starts a screen counter that prints `screen N` after every screenful |
| return | while paused: single-step one generation, staying paused |
| a   | toggle auto-init: once every row on screen is boring (a producible state extinct with no minority state still alive, a cycle of any period (detected by Brent's algorithm, period printed) or a row repeating one from the last ten screens, or a minority population stagnant for four screens), re-initialize the cells as `i` does; on at startup |
| q   | quit                                         |

The `n`/`p` cycle includes one extra slot holding the unsaved rule that was
running before browsing began: stepping past the last saved rule (or back
from rule 0) returns to it. Pressing `r` or `m` makes the new rule occupy
that unsaved slot and repositions the cycle on it. If the rule loaded at
startup is itself a saved rule, the cycle starts positioned on it (and the
unsaved slot stays empty until `r`/`m`), so `n` and `p` step to its
neighbors rather than appearing to do nothing.

Color sets are loaded from `colorsets/colorsets.json` (shared by every
implementation). **1** is the default set (near-black, off-white, amber,
blue), active at startup; the others are palettes from coolors.co: **0** Ocean Sunset Vibes; **2** Meadow Sunflower Glow; **3** Candy Floss Dreams; **4** Fiery Ice Cream Delight; **5** Golden Autumn Twilight; **6** Midnight Sun Dance; **7** Seaside Serenity; **8** Cherry Blossom Sky; **9** Cotton Candy Skies.
`c` cycles the current set through the 24 ways of assigning its four
colors to the four states; `S` saves the current arrangement to the file.
The file is also the pool of every kept color set; a hidden review mode
(`--colorset-review`, Swift for now) steps through the whole pool with
`N`/`P` and drops sets with `X`, saving as it goes. A second hidden mode,
`--screensaver-review <file>`, composes a screensaver file of rule and
color set pairs: `N`/`P` step through pairs, `[`/`]` walk the pool, `s`
saves the pair under review, `S` appends a new one, `X` deletes.
`--consistency-check <file>` is the same mode on an existing file with the
pairs viewed grouped by rule (file order is untouched), for judging
whether a rule's color sets are too alike.

**Screensaver mode** (`--screensaver <file>`, Swift for now) plays a
screensaver file pair by pair in order, looping: each pair runs until the
boring detector would re-initialize, or for 60 seconds, then the next
pair starts from a fresh field.
