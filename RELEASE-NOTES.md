# ODCA release notes

Written for the person who runs this thing, not for a changelog robot.
Newest first. The commit history and the version notes at the top of
`REQTS.md` carry the fine grain; this file says what changed for your
hands and what to try.

## 3.48.1 (Swift) — 2026-09-10

The `--longest` window now opens at the seeds' width every time. The
Mac restores a window's last frame on its own, so after an ordinary
run that left the window wider, the fixed-width show came up between
black bars; the width is now set outright when the window appears,
the height as restored.

## 3.48.0 (Swift, spec) and 3.49.0 (Python) — 2026-09-10

The `--longest` generation counter moves from the title to the
terminal, where the user wanted it: `1234/5947` redrawn in place below
the last line five times a second, stepping aside whenever a pair or
rule line is printed. It shows only when standard output is a
terminal; piped or logged output stays clean. The title is the rule's
alone again.

## 3.46.0 (Swift, spec) and 3.47.0 (Python) — 2026-09-10

Under `--longest` the window title counts generations: `ODCA — rule
<id> — 1234/5947`, the generation on screen over the seed's recorded
lifetime, refreshed five times a second. (Moved to the terminal in
3.48.0.)

## 3.44.0 (Swift, spec) and 3.45.0 (Python) — 2026-09-10

The player plays what `odca-evolve` found. **`odca my.odca --longest`**
plays the recorded seeds instead of random rows: for every pair with
seeds at the width, its longest-lived seed, then every pair's second
longest, and so on, looping. Each seed runs to the extinction that was
measured (a screenful past it, as the detector always has), and the
next takes over; there is no watchdog, so a ten-thousand-generation
seed gets its ten thousand generations. Seeds that survived the cap are
left out (a row that never dies is not interesting almost by
definition), so a rule with nothing but survivors drops out of the
show, and a file with no playable seed is refused. `--shuffle` mixes
the seeds under the usual rule, no rule or color set twice running.

The window is as wide as the seeds and opens that wide: drag it wider
and black bars appear either side, narrower and the middle shows; `F`
and `--fullscreen` do the same on the whole screen. Only the height
follows the window. When a file records seeds at more than one width,
`--cells N` says which. The rule keys `r`, `m`, `u`, `U`, and `a` do
nothing; `i` restarts the seed on screen; colors, speed, pause, and
`n`/`p` work as ever. The lines read `pair 3/28 pair-0002 Ocean Sunset
Vibes, seed 1/10, 4821 generations`, and the entry line says how many
seeds each file brings at the width.

Both implementations, so the Pi can play what the Mac found.

## 3.42.1 (Swift, spec) — 2026-09-09

The countdown's `seeds/s` is now the rate over the last ten seconds
rather than the average since the rule began. The average crept upward
for the whole run (the user noticed): the rows still in flight, one per
processor, sat as a deficit that faded like 1/t, so the number lagged
the search long after it had settled. The recent rate settles within
ten seconds and then holds.

## 3.42.0 (Swift, spec) — 2026-09-09

The countdown now shows how fast the search is going: after the time
left, the rows tested per second so far on the rule, `00:04:59  1234
seeds/s`. It starts at 0 and settles within a few seconds. Long-lived
rules and wide rows bring it down; that is the search working, not
stalling.

## 3.40.1 (Swift, spec) — 2026-09-09

The countdown now starts at the left margin, in the same column as the
times that open the status lines, instead of two spaces in.

## 3.40.0 (Swift, spec) — 2026-09-09

When `odca-evolve` finishes a rule it prints the ages of the ten rows
it kept, longest first, as bare numbers on one line, before writing the
file and taking up the next rule, so the run's log shows at a glance
what each rule came to:

```
00:00:00 4821, 3990, 2210, 1877, 1502, 1490, 1233, 980, 971, 640
```

## 3.38.1 (Swift, spec) — 2026-09-09

`odca-evolve` tidies its terminal. The countdown reads `00:04:59` and
counts down without a word after it, and every line it prints, the
rule lines and the `kept` lines, opens with the time then left on the
rule in the same `hh:mm:ss`, so the lines compare with each other and
with the countdown:

```
00:05:00 rule 33233022210132010013 (1/28): 600 cells
00:04:29 kept 4821 generations, rank 1 (state 3 extinct)
```

(3.38.0, minutes earlier, opened the lines with the time of day; a
misreading, corrected here.)

## 3.37.0 (Python) — 2026-09-09

The Python player catches up with the seeds. `odca` opens a pair from
its longest-lived recorded seed when the file has one for exactly the
width on screen, `odca-select` carries a file's `seeds` section through
untouched, and scripts pass along the seeds of the files they import.
The file is written in the same bytes from either side. `odca-evolve`
itself is still Swift-only; run it on the Mac, and the Pi will play
what it finds.

## 3.36.0 (Swift, spec) — 2026-09-09

A third program, and the first side path: **`odca-evolve`** looks for
the starting rows that keep a rule alive longest.

```
odca-evolve my-pairs.odca --cells 600 --time 300
```

For each rule in the file it spends five minutes (here) drawing random
rows of 600 cells and evolving each until a state dies out, the
extinction that makes `odca` re-seed, then keeps the ten longest-lived
and writes them into the file. Every processor works at once. It
prints a line as each rule comes up, a line each time a row joins the
ten (`kept 4821 generations, rank 2 (state 3 extinct)`), and on a
terminal a countdown ticking in place. Ctrl-C writes what the current
rule has and stops. Runs add up: a second run starts from the ten
already in the file and only ever improves them. A row that outlives
the cap, 100000 generations by default (`--cap`), is kept as
`survived`, which is the most interesting thing it can find.

The payoff is in the player: **`odca` now starts a pair from its
longest-lived seed** whenever the file records one for exactly the
width on screen, so a pair you have searched lives its whole two
minutes instead of re-seeding. Every other start, `i` or auto-init, is
random as before. Scripts pass the seeds of the files they import.

The file gains a `seeds` section, by rule and width; `odca-select`
carries it through untouched when it rewrites the file. Boring, for
this program, means extinction only: a row that settles into a cycle
with every state alive counts as immortal. That is deliberate and may
widen later.

Swift only for now; the Python player catches up next, and a Python
search is a later decision. The Swift package grew a target for the
program, and command-line parsing moved into the kit so it needs no
AppKit. The conformance vectors are at 1.1 with `lifetimes`, so any
implementation of the search must measure exactly the same numbers.

## 3.35.0 (Python) — 2026-09-09

The Python version now depends on **pygame-ce**, the community fork,
instead of upstream pygame. Nothing about the program changes; this is
about being installable.

Upstream pygame has published no wheel since Python 3.13. On a machine
whose `python3` is newer, pip falls back to building it from C source,
which needs the SDL development headers, and the install dies in fifty
lines of someone else's build log. That is what a fresh clone did on
Ubuntu with Python 3.14. The fork ships wheels for 3.14 and 3.15, and
carries a newer SDL besides, 2.32 against 2.28, which is the layer the
GPU display path runs on.

`import pygame` is unchanged everywhere, the renderer path included, so
no code moved. **One thing to know:** both packages install a module
named `pygame` and cannot share a virtual environment. An existing
checkout needs its venv rebuilt rather than upgraded:

```sh
rm -rf python/.venv
python/run odca interesting.odca      # builds it again, about a minute
```

`python/run` now says what went wrong when an install fails, with the
end of pip's own output and the three things that actually cause it: no
wheel for this Python, no C compiler for the script parser, or an old
venv holding upstream pygame. Wheels still lag a brand-new Python by a
release or two, and the message says to build the venv with an older
`python3` when that is the trouble.

## 3.32.0 (Swift) and 3.33.0 (Python) — 2026-09-08

Two small corrections to yesterday's pair.

`shuffle` is a statement of its own, not a word after `play`: both are
verbs, and a script says one of them about the pairs it imported. So
the script reads

```
import interesting.odca
shuffle
```

and `play shuffle` is now a syntax error. A script says `play` or
`shuffle`, at most once, never both, and gets told which it repeated:
`shuffle after play`, `play given twice`. Error messages listing
several possibilities now read `expecting import, play or shuffle`
rather than stringing `or` between every pair.

The Python program sets line buffering on its output, as the Swift one
already did, so `odca show.play > log` writes each line as it happens
instead of holding them in a buffer. `PYTHONUNBUFFERED=1` is no longer
needed to watch a piped run.

## 3.30.0 (Swift) and 3.31.0 (Python) — 2026-09-08

The script's second word: `play shuffle` (renamed to `shuffle` in
3.32.0; read it that way below).

```
import interesting.odca
play shuffle
```

`play` alone plays what the script imported in import order. `play
shuffle` draws a fresh order for every pass, under the old constraints:
no rule and no color set follows itself, the seam between passes
included, so you never see the same rule twice running or the same four
colors in a different arrangement. It draws up to a hundred times and
then gives up and plays the last draw, so a file that allows no such
order (all one rule, say) still plays.

The seam is honest across files: in `odca plain.odca fancy.play`, the
first pair of the shuffled script is checked against the last pair of
the file before it, not just against its own.

The two shuffles are now clearly different things. `--shuffle` on the
command line orders the *files*; the script statement orders *its own
pairs*. They compose. The entry line says which files are shuffled:
`odca my-show.play: 28 pairs, shuffled`.

`import`, `play`, and `shuffle` are reserved words now, so a file
actually named `shuffle` has to be quoted.

## 3.28.0 (Swift) and 3.29.0 (Python) — 2026-09-08

The show script begins. `odca` now plays a *show*: one or more files on
the command line, each a play script or an odca file. A play script is
a text file, `.play` by convention, one statement per line, `#` for
comments:

```
import interesting.odca      # relative to the script's own directory
import "sunday pairs.odca"   # quote a name with spaces
play                         # every pair imported above, in order
```

That is the whole language for now: `import` and `play`. An odca file
on the command line plays as a script that imports it, so `odca
interesting.odca` does what it did. Several files play in turn, each
its pairs in order, looping; `--shuffle` now draws a fresh order of the
*files* each pass, never the same file twice running, and leaves the
pairs inside a file in their order. The old pair-level shuffle is gone
with it; `odca one.odca --shuffle` plays file order until a script
statement for shuffling arrives. New messages: `odca <file>: <n> pairs`
per file at entry, and `playing <file>` at every change of file in a
show of two or more.

Errors in a script stop the program before any window opens, with the
line and column: `error: show.play:2:6: syntax error, unexpected word
now, expecting end of line`; `error: show.play:1: cannot read a.odca`.

Under the hood: one flex/bison grammar in `script/` generates a C
parser that both implementations compile and use (`script/regen`; the
generated C is checked in, so a clone needs neither tool). The Python
install now compiles it, which needs a C compiler; `python/run` rebuilds
when the parser changes. Golden cases in `conformance/scripts/` pin the
parser's output byte for byte on both sides.

## 3.26.0 (Swift) and 3.27.0 (Python) — 2026-09-08

Two changes to get out of the way before the scripting starts.

"Look" is gone; the thing is a *pair* again, everywhere: the spec, the
help texts, the messages (`pair 3/28 pair-0002 Ocean Sunset Vibes`,
`saved 28 pairs to ...`), and the file, whose array key is `pairs`. Old
files with a `looks` key still load; they are written back with the
new key. `interesting.odca` is converted.

Pairs have names now, which the scripting needs. `odca-select` names
every unnamed pair when it loads a file (`pair-0000` onward, in file
order) and every pair it appends (one past the highest number in the
file, so a deleted number is never reused), and writes the names at the
next save or at exit. Four digits, five once you pass `pair-9999`. Run
`odca-select` once on each of your files to get them named; `odca`
never writes, so it shows whatever names a file has.

`--2` is the default cell size. The delay table stays as it was, so a
plain run is exactly what `--2` was yesterday: 600 × 400 cells in the
default window, 1/120 s between generations to start. `--4` is what the
default used to be. Because the boring detectors count screenfuls, they
now look at twice as many rows; say if the resets feel late.

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
