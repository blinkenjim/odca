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
            colorsets_file=tmp_path / "colorsets.json",
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
    state = (s.rule, s.delay, s.color_set, s.palette, s.interesting_index, list(s.automaton.cells))
    for key in "rmuinp+-":
        assert s.handle_key(key) is True
    assert (s.rule, s.delay, s.color_set, s.palette, s.interesting_index, list(s.automaton.cells)) == state
    s.handle_key("7")  # undefined slot: still a no-op while paused
    assert s.color_set == 1
    palette = s.palette
    s.handle_key("c")  # colors are live while paused (R-K10)
    assert s.palette != palette
    s.handle_key("S")
    assert s.store.load_color_sets()[1]["colors"][2] == "#409CFF"  # saved the arrangement
    s.store.save_color_sets({**s.color_sets, 4: {"name": "Four", "colors": ["#010101"] * 4}})
    s2 = make_session(s.store)
    s2.handle_key(" ")
    s2.handle_key("4")  # defined slot switches while paused
    assert s2.paused and s2.color_set == 4
    s.handle_key(" ")
    assert not s.paused
    s.handle_key("+")
    assert s.delay == state[1] / 2  # keys live again
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


def test_default_only_when_no_color_sets_file(make_store):  # R-K9, R-P4
    s = make_session(make_store())  # temp store: no colorsets.json
    assert s.color_set == 1 and set(s.color_sets) == {1}
    assert s.palette == [(0x12, 0x12, 0x18), (0xEB, 0xEB, 0xE1), (0xFF, 0xA1, 0x36), (0x40, 0x9C, 0xFF)]
    s.handle_key("7")
    assert s.color_set == 1  # undefined slot: no-op


def test_color_sets_load_from_file(make_store):  # R-U4, R-P4
    store = make_store()
    store.save_color_sets({0: {"name": "Zero", "colors": ["#000000", "#111111", "#222222", "#333333"]},
                           5: {"name": "Five", "colors": ["#AAAAAA", "#BBBBBB", "#CCCCCC", "#DDDDDD"]}})
    s = make_session(store)
    assert set(s.color_sets) == {0, 1, 5}  # file slots plus the built-in default
    for d in "0123456789":
        before = s.color_set
        s.handle_key(d)
        assert s.color_set == (int(d) if int(d) in (0, 1, 5) else before)
    s.handle_key("5")
    assert s.palette[0] == (0xAA, 0xAA, 0xAA)


def test_cycle_arrangements_and_save(make_store, capsys):  # PT-23, PT-24
    from odca.session import ARRANGEMENTS
    store = make_store()
    base = ["#000000", "#111111", "#222222", "#333333"]
    store.save_color_sets({3: {"name": "Three", "colors": base}})
    s = make_session(store)
    s.handle_key("3")
    assert len(ARRANGEMENTS) == 24 and ARRANGEMENTS[0] == (0, 1, 2, 3)
    s.handle_key("c")
    assert s.palette == [(0, 0, 0), (0x11, 0x11, 0x11), (0x33, 0x33, 0x33), (0x22, 0x22, 0x22)]  # (0,1,3,2)
    assert "color set 3 arrangement 2/24" in capsys.readouterr().out
    for _ in range(23):
        s.handle_key("c")
    assert s.palette == [(0, 0, 0), (0x11, 0x11, 0x11), (0x22, 0x22, 0x22), (0x33, 0x33, 0x33)]  # wrapped
    s.handle_key("c")
    s.handle_key("1")  # switch away and back: arrangement remembered per slot
    s.handle_key("3")
    assert s.palette[2] == (0x33, 0x33, 0x33)
    s.handle_key("S")
    assert "saved color set 3 Three" in capsys.readouterr().out
    assert store.load_color_sets()[3]["colors"] == ["#000000", "#111111", "#333333", "#222222"]
    s.handle_key("c")  # arrangement index restarted from the saved base
    assert "arrangement 2/24" in capsys.readouterr().out
    assert s.palette == [(0, 0, 0), (0x11, 0x11, 0x11), (0x22, 0x22, 0x22), (0x33, 0x33, 0x33)]
    s.handle_key("C")  # reverse: back to the saved arrangement
    assert "arrangement 1/24" in capsys.readouterr().out
    assert s.palette == [(0, 0, 0), (0x11, 0x11, 0x11), (0x33, 0x33, 0x33), (0x22, 0x22, 0x22)]
    s.handle_key("C")  # wraps backward to 24
    assert "arrangement 24/24" in capsys.readouterr().out
    s.handle_key(" ")
    s.handle_key("C")  # live while paused too
    assert "arrangement 23/24" in capsys.readouterr().out


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
    assert "auto-init (repeating (period 1))" in capsys.readouterr().out
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
    assert "auto-init (repeating (period 1))" in capsys.readouterr().out


def test_extinction_waits_for_living_minority(make_store):  # R-A1 refinement
    s = make_session(make_store(current=Rule.from_id("0123" * 5)))  # all 4 producible
    two = np.array([2, 3] * 16, dtype=np.uint8)  # states 0 and 1 extinct
    s._observe(two)
    assert s._boring_streak == 1 and s._boring_reason == "states 0, 1 extinct"
    s._reset_boredom()
    lone = two.copy()
    lone[5] = 1  # state 1 alive as a minority (1 of 32 cells): not boring yet
    s._observe(lone)
    assert s._boring_streak == 0 and s._boring_reason is None
    s._reset_boredom()
    many = two.copy()
    many[:7] = 1  # state 1 at 22%: a real population, so 0's extinction counts
    s._observe(many)
    assert s._boring_streak == 1 and s._boring_reason == "state 0 extinct"


def _rows_with_minority(rng, n, count):
    """Random 2/3 backgrounds (never repeating) carrying exactly `count` state-1 cells."""
    for _ in range(n):
        row = rng.integers(2, 4, 32).astype(np.uint8)
        row[rng.choice(32, count, replace=False)] = 1
        yield row


def test_stagnant_minority_is_boring_after_four_screens(make_store):  # PT-18
    from odca.session import STAGNATION_SCREENS
    s = make_session(make_store(current=Rule.from_id("0123" * 5)))
    rng = np.random.default_rng(3)
    window = STAGNATION_SCREENS * s.rows
    rows = list(_rows_with_minority(rng, window + 10, 2))
    for row in rows[: window - 1]:
        s._observe(row)
    assert s._boring_streak == 0  # window not yet full: nothing is boring
    for row in rows[window - 1 : window + 6]:
        s._observe(row)
    assert s._boring_streak == 7 and s._boring_reason == "stagnant"


def test_changing_minority_is_not_stagnant(make_store):  # PT-18
    from odca.session import STAGNATION_SCREENS
    s = make_session(make_store(current=Rule.from_id("0123" * 5)))
    rng = np.random.default_rng(4)
    window = STAGNATION_SCREENS * s.rows
    for g in range(window + 20):
        row = next(_rows_with_minority(rng, 1, 1 if g % 2 else 3))  # 1 and 3: both minorities, swing 1.0
        s._observe(row)
        assert s._boring_streak == 0 and s._boring_reason is None


def test_paused_s_zips_one_screenful(make_store):  # PT-19
    from odca.session import SCREEN_SPEEDUP
    s = make_session(make_store())
    s.handle_key(" ")
    g0 = s.automaton.generation
    s.handle_key("s")
    assert s.screen_remaining == s.rows and s.paused
    fast = s.delay / SCREEN_SPEEDUP
    s.tick(fast * 4.5)  # paced at one eighth the delay: 4 generations
    assert s.automaton.generation == g0 + 4 and s.screen_remaining == s.rows - 4
    s.tick(10.0)  # plenty of time, but only the rest of the screenful runs
    assert s.automaton.generation == g0 + s.rows and s.screen_remaining == 0
    assert s.paused
    s.tick(10.0)  # nothing more happens while paused
    assert s.automaton.generation == g0 + s.rows


def test_paused_s_queues_and_space_cancels(make_store):  # PT-19
    s = make_session(make_store())
    s.handle_key(" ")
    s.handle_key("s")
    s.handle_key("s")
    assert s.screen_remaining == 2 * s.rows
    s.handle_key(" ")  # resume cancels the queued screenfuls
    assert not s.paused and s.screen_remaining == 0
    s.handle_key("s")  # unpaused: 's' saves, does not queue
    assert s.screen_remaining == 0 and s.store.load_interesting() == [s.rule]


def test_screen_counter_runs_from_resume(make_store, capsys):  # PT-20
    s = make_session(make_store())
    s.tick(100.0)  # before any pause/resume: no counter
    assert s.screen_counter is None and "screen" not in capsys.readouterr().out
    s.handle_key(" ")
    s.handle_key(" ")  # resume starts the counter at 0
    assert s.screen_counter == 0
    s.tick(s.delay * (s.rows - 1))  # one generation short of a screenful
    assert s.screen_counter == 0 and "screen" not in capsys.readouterr().out
    s.tick(s.delay * 1)
    assert s.screen_counter == 1 and "screen 1" in capsys.readouterr().out
    s.tick(s.delay * (2 * s.rows))  # two more screenfuls while running
    assert s.screen_counter == 3 and "screen 3" in capsys.readouterr().out
    s.handle_key(" ")  # pause: counter keeps its value and keeps counting
    s.handle_key("s")
    s.tick(100.0)  # zipped screenful counts too
    assert s.screen_counter == 4 and "screen 4" in capsys.readouterr().out
    for _ in range(s.rows):
        s.handle_key("\n")  # single steps count too
    assert s.screen_counter == 5
    s.handle_key(" ")  # resume again: restart from 0
    assert s.screen_counter == 0


def test_repetition_window_spans_ten_screens(make_store):  # R-A1
    from odca.session import REPEAT_SCREENS
    s = make_session(make_store(current=Rule.from_id("0123" * 5)))
    rng = np.random.default_rng(9)
    rows = [rng.integers(0, 4, 32).astype(np.uint8) for _ in range(REPEAT_SCREENS * s.rows)]
    for row in rows:
        s._observe(row)  # all distinct, all four states present: nothing boring
    assert s._boring_streak == 0
    s._observe(rows[0])  # recurs exactly REPEAT_SCREENS screens later: still in window
    assert s._boring_streak == 1 and s._boring_reason == "repeating"
    s._reset_boredom()
    for row in rows:
        s._observe(row)
    s._observe(rng.integers(0, 4, 32).astype(np.uint8))  # pushes rows[0] out of the window
    s._observe(rows[0])
    assert s._boring_streak == 0  # forgotten: beyond ten screens


def _distinct_rows(rng, n):
    """n distinct random rows, each containing all four states (no extinction)."""
    rows = []
    seen = set()
    while len(rows) < n:
        row = rng.integers(0, 4, 32).astype(np.uint8)
        row[:4] = [0, 1, 2, 3]
        if row.tobytes() not in seen:
            seen.add(row.tobytes()); rows.append(row)
    return rows


def test_brent_finds_period_beyond_the_window(make_store, capsys):  # PT-22
    from odca.session import REPEAT_SCREENS
    s = make_session(make_store(current=Rule.from_id("0123" * 5)))
    rng = np.random.default_rng(12)
    period = 3 * REPEAT_SCREENS * s.rows  # far longer than the repetition window
    transient, cycle = _distinct_rows(rng, 37), _distinct_rows(rng, period)
    for row in transient:
        s._observe(row)
    g = 0
    while s.cycle_period is None and g < 10 * period:
        s._observe(cycle[g % period]); g += 1
    assert s.cycle_period == period
    assert f"cycle period {period}" in capsys.readouterr().out
    assert s._boring_reason == f"repeating (period {period})"
    s._observe(cycle[g % period])
    assert s._boring_streak >= 2  # every generation is boring from now on
    s.handle_key("m")  # rule change resets the detector
    assert s.cycle_period is None and s._brent_snapshot is None


def test_brent_short_period_exact(make_store, capsys):  # PT-22
    s = make_session(make_store(current=Rule.from_id("0123" * 5)))
    rng = np.random.default_rng(13)
    cycle = _distinct_rows(rng, 7)
    for g in range(200):
        s._observe(cycle[g % 7])
    assert s.cycle_period == 7
