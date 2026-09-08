"""The --help texts (R-U9): identical in every implementation; golden copies in
conformance/help-odca.txt and conformance/help-odca-select.txt.
"""

HELP_ODCA = """\
odca: one-dimensional cellular automata as art

usage: odca <file.odca> [--shuffle] [--fullscreen] [--4 | --3 | --2 | --1]
            [--watchdog SECONDS] [--grace SECONDS]
       odca --help

Plays the pairs in an odca file, one at a time, looping. A pair is a rule
with a color set; odca-select composes them. Each pair gets two minutes of
screen time, re-seeding in place whenever it goes boring; then it hands
over after a quiet minute or at the next re-seed, and the next pair grows
in from a fresh field below the old rows, which keep their colors.

  --shuffle     play the pairs in random order instead of file order: each
                pass is a fresh shuffle of all of them in which no rule and
                no color set follows itself, the seam between passes included
                (a file too small to allow that plays a plain shuffle)
  --fullscreen  open the window full screen, for unattended runs; the
                platform's own control leaves it, as it entered it before
  --4 / --3 / --2 / --1
                cells 4, 3, 2 (the default), or 1 points on a side
                (pixels, in the Python version)
  --watchdog SECONDS
                a pair's screen time before it may hand over: whole
                seconds, 120 by default
  --grace SECONDS
                no hand-over within this long of a re-seed: whole seconds,
                60 by default

Keys:
  q     quit                            space   pause / resume
  N / P next / previous pair by hand    return  single step while paused
  i     re-seed the cells               s       while paused: one screenful
  a     toggle auto-init (on at start)  + / -   faster / slower
  r     new screened random rule        m       mutate one rule entry
  u     undo the last rule change       n / p   as N / P
  U     undo every change since arriving on this pair or rule
  0-9   color set (the hot ten)         [ / ]   walk the whole color set pool
  c / C arrange colors forward / back
  F     toggle full screen (also while paused)

Files: the odca file named on the command line is read only; color sets
come from library.json at the repository root; ~/.odca/ holds the current
rule and the candidate stash.
"""

HELP_ODCA_SELECT = """\
odca-select: compose pairs for odca

usage: odca-select <file.odca> [--4 | --3 | --2 | --1]
       odca-select --help

Shows random rules that passed the maybe-Class-IV screen, lets you dress
each in a color set, and collects the results as pairs in the named odca
file, which is created if it does not exist. The file is written after
every change and at exit. Pairs already in the file are reached with n and
p, which cycle through them and one extra slot holding the unsaved rule
you were exploring; every step re-seeds the cells, and the selected pair
scrolls in from a fresh field below the old rows, as in odca.

  --4 / --3 / --2 / --1
                cells 4, 3, 2 (the default), or 1 points on a side
                (pixels, in the Python version)

Keys:
  q     quit                            space   pause / resume
  r     new screened random rule        return  single step while paused
  m     mutate one rule entry           s       while paused: one screenful
  u     undo the last rule change       a       toggle auto-init (on at start)
  U     undo every change since arriving on this pair or rule
  i     re-seed the cells               + / -   faster / slower
  n / p next / previous pair, or the unsaved rule
  s     rewrite the pair under review's colors in place; after m (its rule
        changed) append the screen as a new pair at the end and move onto
        it, never overwriting a kept rule; on the unsaved rule, append (as S)
  S     append a copy of what is on screen as a new pair
  X     delete the pair under review
  R     toggle the order of n / p: file order, or grouped by rule
        (the screen inverts briefly to confirm)
  0-9   color set (the hot ten)         [ / ]   walk the whole color set pool
  c / C arrange colors forward / back
  F     toggle full screen (also while paused)

Files: the odca file named on the command line; color sets come from
library.json at the repository root; ~/.odca/ holds the current rule and
the candidate stash.
"""
