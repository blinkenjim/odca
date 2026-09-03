# ODCA — One-Dimensional Cellular Automata

An interactive viewer for a four-state, radius-1, count-based cellular
automaton — a reproduction of a design originally written for the 6809E in a
TRS-80 Color Computer.

Each cell is in one of 4 states. A cell's next state depends only on the
*counts* of each state among its 3-cell neighborhood (left, self, right) —
not on which cell holds which state. There are 20 possible count vectors, so
a rule is a table of 20 next states: a rule space of 4²⁰ ≈ 1.1 trillion.

A rule's shareable ID is its 20 next-states as base-4 digits. The lookup
keeps the original's summing trick: states weighted 0, 1, 4, 16 make the
plain neighborhood sum a unique index into the rule table.

## Setup

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Run

```sh
.venv/bin/python -m odca
```

On startup the program loads its previous rule (from `~/.odca/rule`, random
on first run) and initializes all cells to random contents. Rule IDs are
printed to the terminal at startup and whenever a new random rule is
generated, so you can note down and revisit interesting ones.

While the program runs, worker processes on all spare cores continuously
generate and screen random rules; maybe-Class-IV finds are stashed so `r`
answers instantly. The stash (up to 64 rules) persists across runs in
`~/.odca/candidates`; once it is full the workers idle until you consume
candidates.

## Controls

| Key | Action                                       |
|-----|----------------------------------------------|
| r   | new random rule, screened for maybe-Class-IV behavior (ID printed) |
| m   | mutate the rule: one entry changes to a new state |
| u   | undo the last rule change (repeatable)       |
| s   | save the current rule to interesting-rules.txt |
| i   | initialize all cells to random contents      |
| +   | speed up (halve the delay between generations) |
| -   | slow down (double the delay between generations) |
| 0-9 | select a color set                           |
| q   | quit                                         |

Color sets: **0** is CoCo color set 0 (green, yellow, blue, red), **1** is
CoCo color set 1 (buff, cyan, magenta, orange), **2** is the default set
(near-black, off-white, amber, blue). Keys 3–9 are reserved for color sets
yet to be chosen.

## Tests

```sh
.venv/bin/python -m pytest
```
