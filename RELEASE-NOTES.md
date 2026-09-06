# ODCA release notes

Written for the person who runs this thing, not for a changelog robot.
Newest first. The commit history and the version notes at the top of
`REQTS.md` carry the fine grain; this file says what changed for your
hands and what to try.

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
