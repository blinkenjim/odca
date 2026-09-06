"""The --help texts (R-U9): identical in every implementation; golden copies in
conformance/help-odca.txt and conformance/help-odca-select.txt.
"""

HELP_ODCA = """\
odca: one-dimensional cellular automata as art

usage: odca <file.odca> [--shuffle] [--fullscreen]
       odca --help

Plays the looks in an odca file, one at a time, looping. A look is a rule
with a color set; odca-select composes them. Each look gets two minutes of
screen time, re-seeding in place whenever it goes boring; then it hands
over after a quiet minute or at the next re-seed, and the next look grows
in from a fresh field below the old rows, which keep their colors.

  --shuffle     play the looks in random order instead of file order (each
                pass is a fresh shuffle that does not repeat the last look)
  --fullscreen  open the window full screen, for unattended runs; the
                platform's own control leaves it, as it entered it before

Keys:
  q     quit                            space   pause / resume
  N / P next / previous look by hand    return  single step while paused
  i     re-seed the cells               s       while paused: one screenful
  a     toggle auto-init (on at start)  + / -   faster / slower
  r     new screened random rule        m       mutate one rule entry
  u     undo the last rule change       n / p   as N / P
  0-9   color set (the hot ten)         [ / ]   walk the whole color set pool
  c / C arrange colors forward / back

Files: the odca file named on the command line is read only; color sets
come from library.json at the repository root; ~/.odca/ holds the current
rule and the candidate stash.
"""

HELP_ODCA_SELECT = """\
odca-select: compose looks for odca

usage: odca-select <file.odca>
       odca-select --help

Shows random rules that passed the maybe-Class-IV screen, lets you dress
each in a color set, and collects the results as looks in the named odca
file, which is created if it does not exist. The file is written after
every change and at exit. Looks already in the file are reached with n and
p, which cycle through them and one extra slot holding the unsaved rule
you were exploring; every step fills the screen with the selected look.

Keys:
  q     quit                            space   pause / resume
  r     new screened random rule        return  single step while paused
  m     mutate one rule entry           s       while paused: one screenful
  u     undo the last rule change       a       toggle auto-init (on at start)
  i     re-seed the cells               + / -   faster / slower
  n / p next / previous look, or the unsaved rule
  s     rewrite the look under review with the color set on screen;
        on the unsaved rule, append the screen as a new look (as S)
  S     append a copy of what is on screen as a new look
  X     delete the look under review
  R     toggle the order of n / p: file order, or grouped by rule
        (the screen inverts briefly to confirm)
  0-9   color set (the hot ten)         [ / ]   walk the whole color set pool
  c / C arrange colors forward / back

Files: the odca file named on the command line; color sets come from
library.json at the repository root; ~/.odca/ holds the current rule and
the candidate stash.
"""
