"""Session properties (TESTS.md PT-9, PT-10, PT-10a, PT-13, PT-14 and more).

All file access goes to a temp Store; the search never starts workers.
"""

import numpy as np
import pytest

from odca.automaton import Rule
from odca.search import CandidateSearch
from odca.session import INITIAL_DELAY, MAX_DELAY, MIN_DELAY, Session
from odca.store import Store

FOUR = [Rule.from_id(d * 20) for d in "0123"]
OUTSIDE = Rule.from_id("01230123012301230123")


@pytest.fixture
def make_store(tmp_path):
    def _make(saved=(), current=None):
        store = Store(
            state_dir=tmp_path / "state",
            keeper_file=tmp_path / "interesting-rules.txt",
        )
        for rule in saved:
            store.append_interesting(rule)
        if current is not None:
            store.save_rule(current)
        return store

    return _make


def make_session(store, seed=1):
    return Session(
        32, 16, store=store, search=CandidateSearch(workers=0),
        rng=np.random.default_rng(seed),
    )


def test_startup_persists_rule_and_shows_seed_row(make_store):
    s = make_session(make_store(current=OUTSIDE))
    assert s.rule == OUTSIDE
    assert s.store.load_rule() == OUTSIDE
    assert s.filled == 1
    assert list(s.history[0]) == list(s.automaton.cells)


def test_undo_lifo(make_store):  # PT-9
    s = make_session(make_store())
    r0 = s.rule
    assert s.handle_key("m")
    r1 = s.rule
    assert s.handle_key("m")
    s.handle_key("u")
    assert s.rule == r1
    s.handle_key("u")
    assert s.rule == r0
    s.handle_key("u")  # empty stack: no-op
    assert s.rule == r0


def test_cycle_with_unsaved_slot(make_store):  # PT-10
    s = make_session(make_store(saved=FOUR, current=OUTSIDE))
    assert s.interesting_index is None and s.unsaved_rule == OUTSIDE
    s.handle_key("n"); assert s.rule == FOUR[0]  # first n -> 0
    s.handle_key("p"); assert s.rule == OUTSIDE  # back to unsaved
    s.handle_key("p"); assert s.rule == FOUR[3]  # wraps to n-1
    s.handle_key("n"); assert s.rule == OUTSIDE  # past last -> unsaved
    s.handle_key("m")  # new rule occupies the unsaved slot
    mutant = s.rule
    assert s.interesting_index is None and s.unsaved_rule == mutant
    s.handle_key("n"); assert s.rule == FOUR[0]
    s.handle_key("p"); assert s.rule == mutant


def test_cycle_startup_match(make_store):  # PT-10a
    s = make_session(make_store(saved=FOUR, current=FOUR[2]))
    assert s.interesting_index == 2 and s.unsaved_rule is None
    s.handle_key("n"); assert s.rule == FOUR[3]
    s.handle_key("n"); assert s.rule == FOUR[0]  # wraps with no unsaved stop
    s.handle_key("p"); assert s.rule == FOUR[3]
    s.handle_key("m")
    mutant = s.rule
    assert s.unsaved_rule == mutant
    s.handle_key("n"); assert s.rule == FOUR[0]
    s.handle_key("p"); assert s.rule == mutant


def test_cycle_empty_keeper(make_store):  # R-B4
    s = make_session(make_store())
    rule = s.rule
    s.handle_key("n")
    assert s.rule == rule and s.interesting_index is None


def test_pause_modality(make_store):  # PT-13
    s = make_session(make_store(saved=FOUR))
    s.handle_key(" ")
    assert s.paused
    state = (s.rule, s.delay, s.color_set, s.interesting_index, list(s.automaton.cells))
    for key in "rmusinp+-1":
        assert s.handle_key(key) is True
    assert (s.rule, s.delay, s.color_set, s.interesting_index, list(s.automaton.cells)) == state
    s.handle_key(" ")
    assert not s.paused
    s.handle_key("1")
    assert s.color_set == 1  # keys live again
    s.handle_key(" ")
    assert s.handle_key("q") is False  # q still quits while paused


def test_single_step(make_store):  # PT-14
    s = make_session(make_store())
    g0 = s.automaton.generation
    s.handle_key("\n")  # not paused: ignored
    assert s.automaton.generation == g0
    s.handle_key(" ")
    for i in range(1, 4):
        s.handle_key("\n")
        assert s.automaton.generation == g0 + i and s.paused


def test_speed_clamps_and_tick(make_store):  # R-K8, R-U5
    s = make_session(make_store())
    assert s.delay == INITIAL_DELAY
    for _ in range(50):
        s.handle_key("+")
    assert s.delay == MIN_DELAY
    for _ in range(50):
        s.handle_key("-")
    assert s.delay == MAX_DELAY

    s2 = make_session(make_store())
    g0 = s2.automaton.generation
    s2.tick(1.0)  # 1 s at 60 gen/s
    assert s2.automaton.generation == g0 + 60
    s2.handle_key(" ")
    s2.tick(5.0)  # paused: time discarded
    s2.handle_key(" ")
    s2.tick(0.0)
    assert s2.automaton.generation == g0 + 60


def test_save_appends_keeper(make_store):  # R-K5
    s = make_session(make_store(saved=FOUR[:1]))
    s.handle_key("s")
    assert s.store.load_interesting() == [FOUR[0], s.rule]


def test_init_cells_pushes_row(make_store):  # R-K6
    s = make_session(make_store())
    rule = s.rule
    s.handle_key("i")
    assert s.rule == rule and s.filled == 2
    assert s.automaton.generation == 0


def test_undefined_color_set_ignored(make_store):  # R-K9
    s = make_session(make_store())
    s.handle_key("7")
    assert s.color_set == 2
    s.handle_key("0")
    assert s.color_set == 0


ALL_ZERO = Rule.from_id("0" * 20)
# Every neighborhood -> 1 except three 3s -> 3: state 3 is producible but
# any run of 3s shrinks from both ends each generation, so 3 dies out.
KILLS_THREE = Rule([3] + [1] * 19)


def test_auto_init_fires_when_screen_is_boring(make_store, capsys):  # PT-15
    s = make_session(make_store(current=ALL_ZERO))
    assert s.auto_init is False  # off at startup (R-K12)
    s.handle_key("a")
    assert s.auto_init and "auto-init on" in capsys.readouterr().out
    # gen 1 is the first all-zero row; gen 2 onward repeats it. The 16th
    # consecutive boring generation is gen 17, which must trigger.
    for _ in range(16):
        s.tick(1 / 60)
    assert s.automaton.generation == 16
    s.tick(1 / 60)
    assert s.automaton.generation == 0  # re-initialized
    assert "auto-init (repeating)" in capsys.readouterr().out
    assert s.rule == ALL_ZERO  # rule untouched


def test_auto_init_off_does_nothing(make_store, capsys):  # PT-15
    s = make_session(make_store(current=ALL_ZERO))
    for _ in range(40):
        s.tick(1 / 60)
    assert s.automaton.generation == 40
    assert "auto-init" not in capsys.readouterr().out


def test_auto_init_reports_extinction(make_store, capsys):  # PT-16
    s = make_session(make_store(current=KILLS_THREE))
    s.handle_key("a")
    fired = False
    for _ in range(200):
        before = s.automaton.generation
        s.tick(1 / 60)
        if s.automaton.generation < before:
            fired = True
            break
    assert fired
    assert "auto-init (state 3 extinct)" in capsys.readouterr().out


def test_boring_count_resets_on_rule_change_and_toggle_prints(make_store, capsys):  # PT-17
    s = make_session(make_store(current=ALL_ZERO))
    for _ in range(10):
        s.tick(1 / 60)
    assert s._boring_streak > 0
    s.handle_key("m")
    assert s._boring_streak == 0
    s.handle_key("a")
    s.handle_key("a")
    out = capsys.readouterr().out
    assert "auto-init on" in out and "auto-init off" in out
    assert s.auto_init is False


def test_auto_init_via_single_step_while_paused(make_store, capsys):  # R-A4
    s = make_session(make_store(current=ALL_ZERO))
    s.handle_key("a")
    s.handle_key(" ")
    for _ in range(17):
        s.handle_key("\n")
    assert s.automaton.generation == 0 and s.paused
    assert "auto-init (repeating)" in capsys.readouterr().out
