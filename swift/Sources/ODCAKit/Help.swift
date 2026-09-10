/// The --help texts (R-U9): identical in every implementation; golden copies in
/// conformance/help-odca.txt and conformance/help-odca-select.txt. Each literal
/// carries one extra empty line because a multi-line literal drops the final break.
public let helpOdca = """
odca: one-dimensional cellular automata as art

usage: odca <file> [<file> ...] [--shuffle] [--fullscreen]
            [--4 | --3 | --2 | --1] [--watchdog SECONDS] [--grace SECONDS]
       odca <file.odca> [<file.odca> ...] --longest [--shuffle] [--cells N]
            [--fullscreen] [--4 | --3 | --2 | --1]
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
                plays to the extinction that was measured, with no
                watchdog; seeds that survived the cap are left out, so a
                rule with nothing but survivors is left out. The window
                opens as wide as the seeds, and the picture is scaled to
                the width it has, cells staying square. With --shuffle
                the seeds play in a
                fresh random order each pass in which no rule and no
                color set follows itself. r, m, u, U, and a do nothing;
                i restarts the seed on screen
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

public let helpOdcaSelect = """
odca-select: compose pairs for odca

usage: odca-select <file.odca> [--longest] [--4 | --3 | --2 | --1]
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

public let helpOdcaEvolve = """
odca-evolve: search an odca file's rules for their longest-lived seeds

usage: odca-evolve <file.odca> --cells N --time SECONDS [--cap N]
                   [--parity [--limit N]]
       odca-evolve --help

For every distinct rule in the file, in order, spends the time budget
drawing random rows of N cells and evolving each, in wrap mode, until a
state the rule can produce has died out with no other state left in a
minority (the extinction that makes odca re-seed), or a cycle of any
period is confirmed (as odca's own detector confirms one), or the cap. The
ten longest-lived rows are kept, merged with any the file already holds
for that rule and width, and written back to the file as the budget runs
out; then the next rule, and after the last the first again, round trip
after round trip until Ctrl-C. Every processor works at once, each on
rows of its own. odca plays a pair from its longest-lived seed when the file
holds one for exactly the width on screen.

  --cells N       the width of the rows, in cells (3 or more)
  --time SECONDS  the budget per rule, in whole seconds
  --cap N         a row still alive after this many generations counts as
                  having survived and stops there; 100000 by default. Once
                  a rule's ten are all survivors its turn ends early
  --parity        a rule far ahead gives up its turn: when its shortest
                  recorded lifetime at this width, times 0.9, outlives the
                  longest of some other rule of the file, it is skipped
                  with a line saying so, and the time goes to the rules
                  behind; decided for the whole round trip as it starts
                  and announced (how many rules, how many skipped, how
                  many run), each running rule's line then giving its
                  place among those that run
  --limit N       with --parity: at most N rules give up their turn per
                  round trip, those furthest ahead; 0, the default, is no
                  limit

Output: a line as each round trip begins (and the parity plan after it),
a line as each rule is taken up, a line for every row that joins the ten
(its generations, its rank, how it ended), and when the rule is done a
line of the ten's ages in generations, longest first, comma separated;
each line opens with the time then left on the rule as hh:mm:ss, and on
a terminal that time is counted down in place, followed by the rows
tested per second over the last ten seconds. Ctrl-C writes what the
current rule has so far and exits.

Files: the odca file is rewritten with its pairs unchanged and a seeds
section by rule and width; nothing under ~/.odca is touched, and no
window opens.

"""
