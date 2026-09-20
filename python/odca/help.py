"""The --help texts (R-U9): identical in every implementation; golden copies in
conformance/help-odca.txt and conformance/help-odca-select.txt.
"""

HELP_ODCA = """\
odca: one-dimensional cellular automata as art

usage: odca <file> [<file> ...] [--shuffle] [--fullscreen]
            [--4 | --3 | --2 | --1] [--watchdog SECONDS] [--grace SECONDS]
            [-x N | --experiment N]
       odca <file.odca> [<file.odca> ...] --longest [--shuffle] [--cells N]
            [--play-survivors] [--fullscreen] [--4 | --3 | --2 | --1]
            [-x N | --experiment N]
       odca --help

Plays a show. Each file is a play script (below) or an odca file of
pairs, which plays as a script that imports it and plays it. A pair is a
rule with a color set; odca-select composes them. Each pair gets two
minutes of screen time, re-seeding in place whenever it goes boring; then
it hands over after a quiet minute or at the next re-seed, and the next
pair grows in from a fresh field below the old rows, which keep their
colors. The files play in turn, each its pairs in order, looping.

  --shuffle     play the files in random order instead of command-line
                order: a fresh draw each pass, never the same file twice
                running; the pairs within a file keep their order unless
                its script says shuffle
  --fullscreen  open the window full screen, for unattended runs; the
                platform's own control leaves it, as it entered it before
  -x N / --experiment N
                run an experimental rule class instead of the ODCA (R-M12).
                Every one but 0 brings the grandparent -- each cell's own
                state two generations back -- into the rule, which makes it
                a second-order automaton:
                  0  the ODCA itself, 20 entries; no grandparent
                  1  the grandparent picks among four sub-rules for each
                     count vector, 80 entries; four equal columns is a
                     case-0 rule, so this is a strict superset
                  2  Fredkin's form, next = rule[counts] - grandparent,
                     mod 4, the same 20 entries and so the same rule IDs.
                     Reversible: nothing ever dies out for good
                  3  the grandparent counted as a fourth cell, order-blind
                     like the rest: 35 entries
                The rules a file names are ODCA rules, so under an
                experiment the show's pairs keep their colors and the rule
                on screen is a fresh experimental one, r for another.

  --4 / --3 / --2 / --1
                cells 4, 3, 2 (the default), or 1 points on a side
                (pixels, in the Python version)
  --watchdog SECONDS
                a pair's screen time before it may hand over: whole
                seconds, 120 by default
  --grace SECONDS
                no hand-over within this long of a re-seed: whole seconds,
                60 by default
  --longest     play the seeds odca-evolve recorded instead: for every
                pair with seeds at the width, its longest-lived seed, then
                every pair's second longest, and so on, looping; each
                plays to the end that was measured, an extinction or a
                confirmed cycle, with no watchdog; seeds that survived
                the cap are left out, so a
                rule with nothing but survivors is left out. The window
                opens as wide as the seeds, and the picture is scaled to
                the width it has, cells staying square. With --shuffle
                the seeds play in a
                fresh random order each pass in which no rule and no
                color set follows itself. r, m, u, U, and a do nothing;
                i restarts the seed on screen
  --play-survivors
                with --longest: play the seeds that survived the cap too,
                each for the generations it was measured for. Such a seed
                has no measured end to play to, so it holds the screen for
                as long as the cap ran -- which is the point when a rule is
                worth watching because it does not die
  --cells N     with --longest: which width's seeds, when the files
                record more than one

Play scripts (.play): one statement per line; # starts a comment.
  import <file>   the pairs of an odca file, in order; the name is
                  relative to the script, and quoted if it contains a
                  space or is a keyword
  play            play every pair imported above, once, in that order
  shuffle         the same, in a fresh order each pass, in which no
                  rule and no color set follows itself

One of play and shuffle ends a script's imports; a script with neither
plays nothing.

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
  o     show / hide the generation count on screen (--longest; also paused)

Files: the files named on the command line and the odca files they
import are read only; color sets come from library.json at the repository
root; ~/.odca/ holds the current rule and the candidate stash.
"""

HELP_ODCA_SELECT = """\
odca-select: compose pairs for odca

usage: odca-select <file.odca> [--longest] [--4 | --3 | --2 | --1]
                   [-x N | --experiment N]
       odca-select --help

Shows random rules that passed the maybe-Class-IV screen, lets you dress
each in a color set, and collects the results as pairs in the named odca
file, which is created if it does not exist. The file is written after
every change and at exit. Pairs already in the file are reached with n and
p, which cycle through them and one extra slot holding the unsaved rule
you were exploring; every step re-seeds the cells, and the selected pair
scrolls in from a fresh field below the old rows, as in odca.

  --longest     present only the pairs whose rule has seeds recorded by
                odca-evolve (any width, survivors included), for curating
                what odca --longest plays: n and p cycle those; s rewrites
                a pair's colors as ever; X deletes the rule's seeds, not
                the pair, and every pair on that rule leaves the cycle; S
                still appends a copy of the screen, and s after m a new
                pair, saved but not shown when its rule has no seeds (the
                position stays). Nothing is seeded from the recorded rows.

  -x N / --experiment N
                run an experimental rule class instead of the ODCA (R-M12).
                Every one but 0 brings the grandparent -- each cell's own
                state two generations back -- into the rule, which makes it
                a second-order automaton:
                  0  the ODCA itself, 20 entries; no grandparent
                  1  the grandparent picks among four sub-rules for each
                     count vector, 80 entries; four equal columns is a
                     case-0 rule, so this is a strict superset
                  2  Fredkin's form, next = rule[counts] - grandparent,
                     mod 4, the same 20 entries and so the same rule IDs.
                     Reversible: nothing ever dies out for good
                  3  the grandparent counted as a fourth cell, order-blind
                     like the rest: 35 entries
                An experiment draws unscreened rules (the screen reads an
                ODCA table), and none of them is saved to the file: a rule
                ID of 80 or 35 digits is not an odca rule ID.

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
