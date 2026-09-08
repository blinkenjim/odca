# ODCA release notes

Written for the person who runs this thing, not for a changelog robot.
Newest first. The commit history and the version notes at the top of
`REQTS.md` carry the fine grain; this file says what changed for your
hands and what to try.

## 3.24.0 (Swift) and 3.25.0 (Python) — 2026-09-07

Un-asked, as you put it: `n` and `p` in `odca-select` no longer blast a
screenful of the new look onto the screen. They re-seed the cells and
the look grows in from a fresh field below the old rows, exactly as a
transition does in `odca`. The old rows recolor at once, as everything
in the workbench does. The screen fill on navigation dates from 2.24.1
and is withdrawn from the spec; the dormant color set review keeps its
own fill.

## 3.22.0 (Swift) and 3.23.0 (Python) — 2026-09-07

The 3.16.0 model was a mistake, and it cost you a rule (recovered from
git into `swift/saver.odca`, see below). Now: `m` on a look under
review marks the look as changed. You stay on it, the mutant shows in
its colors, `u` and `U` walk it back, `n` and `p` drop it, and `s` or
`S` save the screen as a new look at the end of the file. A kept rule is
never overwritten by a mutation. After `s` the position moves onto the
new look, so a further digit and `s` refine its colors in place; `S`
leaves the position where it was, as always. `s` on an unmutated look
still rewrites its colors in place.

## 3.20.0 (Swift) and 3.21.0 (Python) — 2026-09-07

`--3`, beside the others: 3-point cells, 400 × 266 of them in the
default window (800 is not a multiple of 3, so a 1-point margin top and
bottom), and the starting speed scales with the cell as before, three
quarters of the default delay. Everything downstream was already
written in terms of the cell size, so this is the flag, the help text,
and the spec.

## 3.18.0 (Swift) and 3.19.0 (Python) — 2026-09-06

`U` undoes every rule change since you arrived where you are: on a look
under review, back to the look as recorded; on the unsaved slot, back to
the rule `r` brought; in `odca`, back to the look as it started playing.
One key, however many `m` presses it took. `u` still walks back one at a
time, and `U` after `u` unwinds what is left. Both help texts list it.

## 3.16.0 (Swift) and 3.17.0 (Python) — 2026-09-06

Your `s` report. It was the spec, not a bug: `m` used to move you to
the unsaved slot, where `s` appends. Now `m` on a look under review is
an edit of that look: you stay on it, the mutation shows in its colors,
`s` rewrites the look in place with the mutated rule and whatever colors
are on screen, `u` walks the mutation back, and `n` or `p` drop it.
`r` still moves to the unsaved slot, since a fresh rule is a new
exploration rather than an edit; `m` on the unsaved slot stays there.
In the grouped order a look whose rule changed joins its new rule's
group on `s`. The `u` wrinkle on the list now only concerns `r`.

## 3.14.0 (Swift) and 3.15.0 (Python) — 2026-09-06

`odca --watchdog SECONDS --grace SECONDS`, whole seconds, either or
both, on `odca` only. The defaults stay 120 and 60, so nothing changes
until you pass them:

```
python/run odca interesting.odca --watchdog 20 --grace 10
```

A missing value, a fraction, or zero is a usage error. When you settle
on new defaults, the places that hold the old numbers are listed in
`REQ-swift.md` and `REQ-python.md`: two constants per side, the help
text, the spec, the README bullet.

## 3.12.0 (Swift) and 3.13.0 (Python) — 2026-09-06

The shuffle constraints you described. `odca --shuffle` still plays
every look once per pass in a fresh random order; now no rule and no
color set (the same four colors in any arrangement) ever follows itself,
across the seam between passes too. Each pass is drawn and tested, and
redrawn whole on a failure, up to a hundred times; a file that allows
no such order, like two looks on one rule, then plays the draw as it is.
Nothing is printed when that happens. You said ten draws; the test file
of six looks, every rule and color set twice over, passes a draw one
time in twelve (60 of the 720 orders), so ten would have let a repeat
through on two passes in five. A hundred costs nothing and misses one
pass in six thousand. `--shuffle` had existed since 3.0.0 with
only the weakest rule, never reopening on the look just played; that is
now covered by the stronger one.

## 3.10.0 (Swift) and 3.11.0 (Python) — 2026-09-06

The tweak: the starting speed follows the cell size. `--2` starts at
twice the generations per second of `--4`, `--1` at four times, so the
picture moves at about the same speed in points whatever the cell. `+`
and `-` work from there, and the point where the scroll turns continuous
moves with it (twice the starting delay). `--4` is unchanged.

## 3.8.0 (Swift) and 3.9.0 (Python) — 2026-09-06

The side path: `--4`, `--2`, `--1` on both programs, both sides, choose
the cell size for the run. `--4` is what you had. `--2` puts four times
the cells in the same window, `--1` sixteen, and the picture stays crisp
at every size, in full screen included. Points, never device pixels, so
on this Retina Mac a 1-point cell is still a 2 × 2 block. Two of the
flags at once is a usage error.

Things that scale with it, by design: the automaton is wider, the
boring detectors look at more rows (they count screenfuls), and the
history is deeper on screen. Things to watch: at `--1` the Swift frame
loop does 960,000 cells per refresh in the default window and 1.5
million full screen; if it stutters at 120 Hz, that is the place to
look. Python's frame is numpy and the GPU scales it, so it should not
care.

## 3.6.0 (Swift) and 3.7.0 (Python) — 2026-09-06

Two small things you asked for.

`F` toggles full screen, in both programs, on both sides, also while
paused. It leaves a full screen you entered with the green button too.
The Pi now has a way in and out of full screen without a window manager
shortcut. Both help texts list it.

Run straight out of a fresh clone: `python/run odca interesting.odca`
makes the venv and installs everything on first use, then runs the
program; `swift/run odca interesting.odca` builds release on first use,
then runs the binary. Both take the program name first (`odca` or
`odca-select`) and pass the rest through; file paths are relative to
where you are, not to the script. The root README opens with them. No
version for the wrappers themselves; they are tooling.

## 3.4.0 (Swift) and 3.5.0 (Python) — 2026-09-06

Step two for the portrait installation: `odca <file> --fullscreen` opens
full screen at launch, pointer hidden, no hand needed. Leaving it is the
platform's own control as before (the green button or its shortcut on
the Mac; on the Pi, whatever the window manager offers, or `q`).
`odca-select` does not take the flag. Help text updated on both sides.

That is all this release does. Kiosk mode, which would also lock the
keyboard, stays on the list. Step three, the boring detector windows on
a 480-row screen, waits for the Pi.

## 3.2.0 (Swift) and 3.3.0 (Python) — 2026-09-06

Your complaint after the 3.1.1 test: pressing `N` in `odca` recolored
the whole screen. The old design kept two palettes and swapped between
them, so the second color change within one screenful reused the
palette the oldest rows were still wearing; the spec even called that an
accepted limitation. Withdrawn. Every row now remembers the color set it
was painted with, for as long as it is remembered at all, so blue stays
blue no matter how many looks you step through. `odca-select` still
recolors the whole screen at once, as you want it to.

Spec 3.2.0 (R-X5), both implementations, same session. The Swift
version leads at 3.2.0 and Python follows at 3.3.0 as the convention
says, in two commits.

## 3.1.1 (Python) — 2026-09-06

The GPU display path, first of the three steps you agreed to for the
portrait installation. Nothing looks different on purpose. Under the
hood, the frame that leaves Python is now one small texture, one texel
per cell, and SDL's renderer (Metal on the Mac, OpenGL ES on the Pi)
scales it to the window and presents it in step with the display's
refresh. The per-frame software scale that grew with the window is gone,
and vsync is on, so the picture should be steadier on the Pi and scroll
at 120 Hz on a ProMotion Mac. The same renderer will carry layers, blend
modes, and the overlay band when they come.

What to try on the Mac: the usual drag, the green button, and `+` up to
top speed, watching for anything that stutters or tears. If SDL refuses
vsync somewhere, the viewer falls back to the old 60 Hz timer and says
nothing, so a Pi test later should also note whether it feels smoother.

## 3.1.0 (Python) — 2026-09-06

Window parity. The pygame window resizes, full screen works through the
platform's own control (the green button on macOS; whatever the window
manager offers on the Pi), and the pointer hides in full screen. As on the
Swift side, the grid holds as many whole 4-point cells as fit, the
picture stays centered while cells appear or vanish at the edges, a
taller window uncovers up to 2048 remembered rows, and the animation
freezes during the drag with no burst afterwards. Where the Swift window
snaps to whole cells, pygame cannot, so a thin margin in the background
color takes the remainder.

Two things to know:

- On macOS the OS stretches the picture while you hold the drag; it snaps
  to the new grid the moment you let go. That is SDL, not us.
- There is no keyboard full screen toggle. On the Pi that means the
  window manager's maximize or full screen shortcut. A key for it is on
  the list, since it needs a binding on both sides.

Also fixed: `R` in the Python `odca-select` was read as `r`, so the
grouped order was unreachable there. It works now.

Spec unchanged at 3.0.0; PT-32 now runs on both sides. Python has 100
tests.

## 3.0.1 (Swift) — 2026-09-06

3.0.0's Swift programs printed their startup lines and opened no window.
Cause: AppKit treats an unknown command-line argument as a document to
open, and SwiftUI then withholds the default window expecting a document
window to take its place. 2.x never passed a file on the command line,
so it never hit this. Fixed by telling AppKit not to treat arguments as
documents before the app starts. Python was unaffected. No behavior
change otherwise; the spec stays at 3.0.0.

## 3.0.0 — 2026-09-06

### The one-line version

There is no longer one program with flags. There are two programs, and
both take a file: `odca <file.odca>` plays a show, `odca-select
<file.odca>` builds one.

### What you type now

| You used to type | Now type |
|---|---|
| `odca` (just watching) | `odca-select some.odca` — there is no fileless mode any more |
| `odca --screensaver show.json` | `odca show.odca` |
| `odca --screensaver-review show.json` | `odca-select show.odca` |
| `odca --consistency-check show.json` | `odca-select show.odca`, then press `R` |
| `odca --colorset-review` | nothing yet; on hold until it becomes its own program |

Swift, from `swift/`: `swift run -c release odca ../interesting.odca`
(release build, or it stutters).

Python, from `python/`: after the one-time setup below, `.venv/bin/odca
../interesting.odca`. The old `python -m odca` still works and means the
player; `python -m odca.select` is the workbench.

Python setup changed. The stock macOS pip is too old to install the new
`pyproject.toml`, so it is now three lines:

```
python3 -m venv .venv
.venv/bin/pip install --upgrade pip setuptools
.venv/bin/pip install -e '.[test]'
```

Your MacPorts 3.14 would skip the middle line, but pygame has no 3.14
wheel yet, so stay on the stock 3.9 for now.

### Your files moved

- `interesting-rules.json` is now `interesting.odca` at the repo root.
  Same 28 saved rules with their colors, now called *looks*, under a
  `looks` key instead of `pairs`. The old file name is gone and the old
  key is not read.
- `colorsets/colorsets.json` is now `library.json` at the repo root. Same
  content. The candidates and screenshots stay in `colorsets/`.
- Any 2.x screensaver files you made by hand or with the review mode
  need their `pairs` key renamed to `looks` and, by convention, a `.odca`
  extension. Nothing else in them changes.
- `~/.odca/` is untouched: current rule and candidate stash as before.

### What the keys do in odca-select

Most of the keyboard is what it was. The differences:

- `n` / `p` cycle the file's looks plus one extra slot for the unsaved
  rule you were exploring. Every step fills the screen with the selected
  look, so navigation never shows a recolored old picture.
- `s` on a look rewrites that look's color set to the one on screen and
  keeps its rule. `s` on the unsaved rule appends the screen as a new
  look, exactly as `S` would. Either way the file is written at once.
- `S` always appends a copy of what is on screen.
- `X` deletes the look under review. On the unsaved rule it does nothing.
- `R` toggles the `n`/`p` order between file order and grouped by rule.
  The screen inverts for a quarter second to tell you it happened. This
  is the old consistency check, now a key.
- `N` and `P` do nothing here; they belong to the player.
- `S` no longer bakes an arrangement into the library. That job moves to
  the future color set tool. Looks record arranged colors, so nothing is
  lost.
- The file is also written when you quit, so a brand new file name
  produces a file even if you saved nothing.

A file that already has looks opens on look 1. The unsaved slot stays
empty until you press `r` or `m`.

### What the keys do in odca

Unchanged from 2.x screensaver mode, with two additions: `n`/`p` work as
`N`/`P`, and `s`, `S`, `X`, `R` do nothing. The player never writes the
file.

`--shuffle` plays each pass in a fresh random order and never opens a
pass on the look that closed the previous one. That is the whole shuffle
so far; the constraints you said you would describe are waiting on you.

### Try this first

```
cd swift
swift run -c release odca-select ../show.odca
```

Press `n` a few times to see the looks, `r` for fresh rules, digits and
`[` `]` for colors, `S` to keep one. Quit, then:

```
swift run -c release odca ../show.odca --shuffle
```

To seed a show from everything you have kept so far, copy
`interesting.odca` to a new name and open it with odca-select. Delete
with `X`, reorder by deleting and re-appending.

### What to watch for

- `u` restores the rule only. The color set on screen and the `n`/`p`
  position stay where they were, so after an undo the screen can show a
  look's rule while the cycle points elsewhere. You agreed to leave this;
  it is on the list.
- The inversion flash is the first display cue of its kind. If a quarter
  second is too short or too long, say so; it is one constant.
- `odca` alone, with no file, prints a usage line and exits. That is
  deliberate: there is no fileless mode.

### Parked, on the list

Color set review as its own program (`odca-colors`?), baking arrangements
with it. The shuffle constraints. Kiosk mode. The key-binding rethink,
which this release made more urgent, not less. The script language, whose
first nouns now exist as odca files and the library.

### Under the hood, for when you care

Both implementations changed together, so the even/odd version dance is
suspended for this one release and resumes after. Swift is now three
targets: ODCAKit, a shared ODCAUI, and the two executables. The help
texts live once each in `conformance/` and both implementations must
match them byte for byte, as must their writers for `library.json` and
odca files. Python has 93 tests, Swift 55.
