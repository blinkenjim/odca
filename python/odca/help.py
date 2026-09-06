"""The --help text (R-U9): identical in every implementation, golden copy in
conformance/help.txt.
"""

HELP_TEXT = """\
ODCA: one-dimensional cellular automata as art

usage: odca [--help]
       odca --colorset-review
       odca --screensaver-review <file>
       odca --consistency-check <file>
       odca --screensaver <file> [--sequential]

With no flags, the interactive program: it loads the previous rule, seeds
random cells, and evolves; the terminal reports rule IDs and events.

Modes (one at a time; --screensaver takes precedence over the review flags):
  --colorset-review            review the color set pool: N/P (or [/]) step
                               with wrap, X drops a set and saves at once,
                               digits are disabled, exit saves
  --screensaver-review <file>  compose a screensaver file of rule/color set
                               pairs: N/P step without wrap, s saves the
                               pair under review, S appends the current
                               rule and colors, X deletes; a missing file
                               is created empty
  --consistency-check <file>   screensaver review of an existing file with
                               the pairs viewed grouped by rule
  --screensaver <file>         play an existing screensaver file: pairs in
                               order, looping, two minutes of screen time
                               each, handing over after a quiet minute or
                               at the next re-seed; N/P step by hand

Keys:
  q     quit                            space   pause / resume
  r     new screened random rule        return  single step while paused
  m     mutate one rule entry           s       while paused: one screenful
  u     undo the last rule change       a       toggle auto-init (on at start)
  s     save the rule with its colors   + / -   faster / slower
  n / p next / previous saved rule, with its colors
  i     re-seed the cells
  0-9   color set (the hot ten)         [ / ]   walk the whole color set pool
  c / C arrange colors forward / back   S       save the arrangement to the pool

Files, at the repository root: interesting-rules.json (saved rules with
their colors; itself a screensaver file), colorsets/colorsets.json (the
pool); per user: ~/.odca/ (current rule, candidate stash).
"""
