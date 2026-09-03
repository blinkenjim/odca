"""ODCA — four-state count-based one-dimensional cellular automata."""

from .automaton import Automaton, Rule

__version__ = "1.3.0"  # implements spec (REQTS.md) 1.3
__all__ = ["Automaton", "Rule"]
