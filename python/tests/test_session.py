"""Session properties (TESTS.md PT-9, PT-10, PT-10a, PT-13, PT-14 and more).

All file access goes to a temp Store; the search never starts workers.
"""

import json

import numpy as np
import pytest

from odca.automaton import Rule
from odca.search import CandidateSearch
from odca.session import HISTORY_DEPTH, INITIAL_DELAY, MAX_DELAY, MIN_COLS, MIN_DELAY, Session
from odca.store import DEFAULT_COLOR_SETS, Store, load_odca_file, save_odca_file
from odca.show import ShowError, load_show

FOUR = [Rule.from_id(d * 20) for d in "0123"]
OUTSIDE = Rule.from_id("01230123012301230123")


@pytest.fixture
def make_store(tmp_path):
    def _make(current=None):
        store = Store(
            state_dir=tmp_path / "state",
            library_file=tmp_path / "library.json",
            candidates_file=tmp_path / "candidates.json",
        )
        if current is not None:
            store.save_rule(current)
        return store

    return _make


def default_pair(rule):
    d = DEFAULT_COLOR_SETS[1]
    return {"rule": rule.id, "colorset": d["name"], "colors": list(d["colors"])}


@pytest.fixture
def odca_file(tmp_path):
    """Write an odca file of the given rules (default colors) and return its path."""
    def _make(rules=(), name="pairs.odca"):
        path = tmp_path / name
        if rules:
            save_odca_file([default_pair(r) for r in rules], path)
        return path

    return _make


def make_session(store, seed=1, **modes):
    return Session(
        32, 16, store=store, search=CandidateSearch(workers=0),
        rng=np.random.default_rng(seed), **modes,
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


def test_cycle_with_unsaved_slot(make_store, odca_file):  # PT-10
    s = make_session(make_store(current=OUTSIDE), select_file=odca_file(FOUR))
    # A non-empty file opens on pair 1 with the unsaved slot empty (R-W1) ...
    assert s.pair_index == 0 and s.unsaved_rule is None and s.rule == FOUR[0]
    s.handle_key("r")  # ... until r fills it (m on a pair is an edit of it, 3.16.0)
    outside = s.rule
    assert s.pair_index is None and s.unsaved_rule == outside
    s.handle_key("n"); assert s.rule == FOUR[0]  # first n -> pair 1
    s.handle_key("p"); assert s.rule == outside  # back to unsaved
    s.handle_key("p"); assert s.rule == FOUR[3]  # wraps to pair n
    s.handle_key("n"); assert s.rule == outside  # past last -> unsaved
    s.handle_key("m")  # on the slot, a mutation replaces the unsaved rule and stays there
    mutant = s.rule
    assert s.pair_index is None and s.unsaved_rule == mutant
    s.handle_key("n"); assert s.rule == FOUR[0]
    s.handle_key("p"); assert s.rule == mutant


def test_cycle_startup_on_first_pair(make_store, odca_file):  # PT-10a
    s = make_session(make_store(current=FOUR[2]), select_file=odca_file(FOUR))
    assert s.pair_index == 0 and s.unsaved_rule is None
    s.handle_key("n"); assert s.rule == FOUR[1]
    s.handle_key("p"); s.handle_key("p"); assert s.rule == FOUR[3]  # wraps with no unsaved stop
    s.handle_key("n"); assert s.rule == FOUR[0]
    s.handle_key("r")  # a fresh rule: the unsaved slot reappears holding it
    fresh = s.rule
    assert s.unsaved_rule == fresh
    s.handle_key("n"); assert s.rule == FOUR[0]
    s.handle_key("p"); assert s.rule == fresh


def test_cycle_empty_file_and_no_file(make_store, odca_file, capsys):  # R-B4
    s = make_session(make_store(current=OUTSIDE), select_file=odca_file())
    assert s.unsaved_rule == OUTSIDE and s.pairs == []
    capsys.readouterr()
    s.handle_key("n")
    assert s.rule == OUTSIDE and "no pairs" in capsys.readouterr().out
    base = make_session(make_store())  # no program: n/p have nothing to cycle
    rule = base.rule
    base.handle_key("n")
    assert base.rule == rule and base.pair_index is None


def test_pause_modality(make_store):  # PT-13
    s = make_session(make_store())
    s.handle_key(" ")
    assert s.paused
    state = (s.rule, s.delay, s.color_set, s.palette, s.pair_index, list(s.automaton.cells))
    for key in "rmuinp+-":
        assert s.handle_key(key) is True
    assert (s.rule, s.delay, s.color_set, s.palette, s.pair_index, list(s.automaton.cells)) == state
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
    s2.handle_key("a")  # pacing test: keep auto-init from re-seeding mid-run
    g0 = s2.automaton.generation
    s2.tick(1.0)  # 1 s at 60 gen/s
    assert s2.automaton.generation == g0 + 60
    s2.handle_key(" ")
    s2.tick(5.0)  # paused: time discarded
    s2.handle_key(" ")
    s2.tick(0.0)  # resume computes exactly one generation, seamlessly (R-K10)
    assert s2.automaton.generation == g0 + 61
    s2.tick(0.0)
    assert s2.automaton.generation == g0 + 61  # and no more without elapsed time


def test_s_saves_nothing_without_a_program(make_store, capsys):  # R-K5
    s = make_session(make_store())
    capsys.readouterr()
    s.handle_key("s")
    assert capsys.readouterr().out == ""


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
    assert "color set Three arrangement 2/24" in capsys.readouterr().out
    for _ in range(23):
        s.handle_key("c")
    assert s.palette == [(0, 0, 0), (0x11, 0x11, 0x11), (0x22, 0x22, 0x22), (0x33, 0x33, 0x33)]  # wrapped
    s.handle_key("c")
    s.handle_key("1")  # switch away and back: arrangement remembered per set
    s.handle_key("3")
    assert s.palette[2] == (0x33, 0x33, 0x33)
    s.handle_key("S")
    assert "saved color set Three" in capsys.readouterr().out
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
ALL_PRODUCIBLE = Rule.from_id("0123" * 5)
# Every neighborhood -> 1 except three 3s -> 3: state 3 is producible but
# any run of 3s shrinks from both ends each generation, so 3 dies out.
KILLS_THREE = Rule([3] + [1] * 19)


def test_auto_init_fires_when_screen_is_boring(make_store, capsys):  # PT-15
    s = make_session(make_store(current=ALL_ZERO))
    assert s.auto_init is True  # on at startup (R-K12)
    capsys.readouterr()
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
    s.handle_key("a")  # turn the mode off
    assert s.auto_init is False and "auto-init off" in capsys.readouterr().out
    for _ in range(40):
        s.tick(1 / 60)
    assert s.automaton.generation == 40
    assert "auto-init" not in capsys.readouterr().out


def test_auto_init_reports_extinction(make_store, capsys):  # PT-16
    s = make_session(make_store(current=KILLS_THREE))
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
    assert out.index("auto-init off") < out.index("auto-init on")
    assert s.auto_init is True


def test_auto_init_via_single_step_while_paused(make_store, capsys):  # R-A4
    s = make_session(make_store(current=ALL_ZERO))
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
    s.handle_key("s")  # unpaused: 's' is the save key, it does not queue
    assert s.screen_remaining == 0


def test_screen_counter_runs_from_resume(make_store, capsys):  # PT-20
    s = make_session(make_store())
    s.tick(100.0)  # before any pause/resume: no counter
    assert s.screen_counter is None and "screen" not in capsys.readouterr().out
    s.handle_key(" ")
    s.handle_key(" ")  # resume starts the counter at 0
    assert s.screen_counter == 0
    s.tick(0.0)  # the seamless-resume generation (R-K10)
    s.tick(s.delay * (s.rows - 2))  # now one generation short of a screenful
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


def test_initial_delay_scales_the_speed_and_the_threshold(make_store):  # PT-25, R-U5, R-U3
    s = make_session(make_store(), initial_delay=INITIAL_DELAY / 4)  # --1: four times the speed
    s.handle_key("a")
    assert s.delay == INITIAL_DELAY / 4
    s.tick(s.delay * s.rows)  # a screenful in a quarter of the default time
    assert s.filled == s.rows + 1 and s.scroll_offset == 1.0  # fast: discrete
    s.handle_key("-")  # twice the initial delay: still discrete
    assert s.delay == INITIAL_DELAY / 2 and s.scroll_offset == 1.0
    s.handle_key("-")  # four times: continuous, though this delay is discrete at the default size
    assert s.delay == INITIAL_DELAY
    s.tick(s.delay / 4)
    assert abs(s.scroll_offset - 0.25) < 1e-9


def test_scroll_offset_semantics(make_store):  # PT-25, R-U3
    from odca.session import SMOOTH_SCROLL_DELAY
    s = make_session(make_store())
    s.handle_key("a")  # keep auto-init from re-seeding during the test
    assert s.history.shape == (1, s.cols)  # the seed row only
    assert s.scroll_offset == 0.0  # filling: no scroll yet
    s.tick(s.delay * s.rows)  # buffer full (seed row + rows generations)
    assert s.filled == s.rows + 1 and s.history.shape == (s.rows + 1, s.cols)
    assert s.scroll_offset == 1.0  # default speed is faster than the threshold: discrete
    for _ in range(2):
        s.handle_key("-")  # 4x the delay: slower than half speed -> continuous
    assert s.delay > SMOOTH_SCROLL_DELAY
    s.tick(s.delay * 0.25)
    assert abs(s.scroll_offset - 0.25) < 1e-9
    s.tick(s.delay * 0.5)
    assert abs(s.scroll_offset - 0.75) < 1e-9
    g = s.automaton.generation
    s.tick(s.delay * 0.3)  # crosses a generation: offset wraps, one row scrolls
    assert s.automaton.generation == g + 1 and abs(s.scroll_offset - 0.05) < 1e-9
    s.handle_key(" ")
    assert s.scroll_offset == 1.0  # paused: newest row shown fully
    s.handle_key(" ")
    s.tick(0.0)  # seamless resume: one generation, offset back to 0
    assert s.automaton.generation == g + 2 and s.scroll_offset == 0.0


# ---------------------------------------------------------------- special modes

def grey(v):
    return ["#%02X%02X%02X" % (v + i, v + i, v + i) for i in range(4)]


def review_store(make_store):
    """Slots 0..9 as S0..S9, one pool-only set, one dropped name, four candidates."""
    store = make_store()
    sets = [{"slot": slot, "name": f"S{slot}", "colors": grey(slot * 10)} for slot in range(10)]
    sets.append({"slot": None, "name": "PoolA", "colors": grey(100)})
    store.save_color_set_file({"sets": sets, "dropped": ["Rejected"]})
    store.candidate_palettes_file.write_text(json.dumps({"palettes": [
        {"index": 0, "name": "S3", "colors": ["#000000"] * 4},
        {"index": 1, "name": "Rejected", "colors": ["#000000"] * 4},
        {"index": 2, "name": "CandB", "colors": ["#0B0B0B", "#0C0C0C", "#0D0D0D", "#0E0E0E"]},
        {"index": 3, "name": "CandC", "colors": ["#1B1B1B", "#1C1C1C", "#1D1D1D", "#1E1E1E"]}]}))
    return store


def rgb(hex_):
    return tuple(int(hex_[i:i + 2], 16) for i in (1, 3, 5))


def test_review_order_and_stepping(make_store, capsys):  # PT-26
    store = review_store(make_store)
    s = make_session(store, review_mode=True)
    assert [e["name"] for e in s.review_entries] == [
        "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S0", "PoolA", "CandB", "CandC"]
    assert s.dropped_names == ["Rejected"]
    assert "review 1/13 S1" in capsys.readouterr().out
    assert s.palette[0] == rgb("#0A0A0A")
    g0 = s.automaton.generation
    s.handle_key("N")
    assert capsys.readouterr().out.strip() == "review 2/13 S2"
    assert s.palette[0] == rgb("#141414")
    assert s.automaton.generation == g0 + s.rows  # R-V7: a screenful at once
    s.handle_key("P")
    s.handle_key("P")  # past the start: wraps to the end
    out = capsys.readouterr().out
    assert "review wrapped" in out and "review 13/13 CandC" in out
    s.handle_key("5")  # digits are disabled in review mode
    assert s.palette[0] == rgb("#1B1B1B")
    s.handle_key("N")  # past the end: wraps to the start
    assert "review wrapped" in capsys.readouterr().out
    assert s.review_index == 0
    s.handle_key(" ")
    s.handle_key("N")  # live while paused
    assert s.review_index == 1
    s.handle_key("]")  # '[' / ']' are synonyms for P / N here (R-K17)
    assert s.review_index == 2
    s.handle_key("[")
    assert s.review_index == 1


def test_review_drop_save_and_slot_rotation(make_store, capsys):  # PT-26
    store = review_store(make_store)
    s = make_session(store, review_mode=True)
    s.handle_key("c")  # arrange S1: preview only, never saved (R-V6)
    s.handle_key("N")
    s.handle_key("X")  # drop S2: advances to S3 and saves at once
    out = capsys.readouterr().out
    assert "dropped S2" in out and "review 2/12 S3" in out
    assert "saved 12 color sets, 2 dropped" in out
    assert store.load_color_set_file()["dropped"] == ["Rejected", "S2"]
    assert s.palette[0] == rgb("#1E1E1E")
    for _ in range(10):
        s.handle_key("N")  # to CandC (last)
    s.handle_key("X")  # drop the last: wraps to the start
    out = capsys.readouterr().out
    assert "dropped CandC" in out and "review wrapped" in out and "review 1/11 S1" in out
    assert "saved 11 color sets, 3 dropped" in out
    s.handle_key("S")  # no binding in review mode
    assert capsys.readouterr().out == ""
    file = store.load_color_set_file()
    assert file["dropped"] == ["Rejected", "S2", "CandC"]
    by_slot = {e["slot"]: e["name"] for e in file["sets"] if e["slot"] is not None}
    assert by_slot == {1: "S1", 2: "S3", 3: "S4", 4: "S5", 5: "S6", 6: "S7", 7: "S8", 8: "S9", 9: "S0", 0: "PoolA"}
    assert [e["name"] for e in file["sets"] if e["slot"] is None] == ["CandB"]
    assert next(e for e in file["sets"] if e["name"] == "S1")["colors"] == grey(10)  # not baked
    again = make_session(store, review_mode=True)
    assert [e["name"] for e in again.review_entries] == [
        "S1", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S0", "PoolA", "CandB"]
    assert again.dropped_names == ["Rejected", "S2", "CandC"]
    again.handle_key("X")  # drop S1; finish() saves at exit
    again.finish()
    assert store.load_color_sets()[1]["name"] == "S3"
    assert store.load_color_set_file()["dropped"][-1] == "S1"


def test_review_keys_inert_outside_review_mode(make_store):  # PT-26
    store = review_store(make_store)
    s = make_session(store)
    assert not s.review_mode
    palette = s.palette
    for k in "NPX":
        s.handle_key(k)
    assert s.palette == palette
    assert store.load_color_set_file()["dropped"] == ["Rejected"]
    s.finish()
    assert len(store.load_color_set_file()["sets"]) == 11
    assert s.pairs == []


def test_select_lifecycle(make_store, odca_file, capsys):  # PT-28
    store = review_store(make_store)
    file = odca_file(name="saver.odca")
    s = make_session(store, select_file=file)
    assert s.select_mode and not s.review_mode and not s.play_mode
    assert not file.exists()  # a missing file is created by the first save or at exit
    assert s.pair_index is None and s.unsaved_rule == s.rule
    assert "odca saver.odca: 0 pairs" in capsys.readouterr().out
    rule0 = s.rule
    s.handle_key("n")
    assert "no pairs" in capsys.readouterr().out

    s.handle_key("3")  # S3 = grey(30)
    s.handle_key("c")  # arranged (0,1,3,2)
    s.handle_key("s")  # on the unsaved slot: s appends, as S would (R-W4)
    out = capsys.readouterr().out
    assert "added pair 1/1" in out and "saved 1 pair to saver.odca" in out
    assert s.pair_index is None  # the position is unchanged
    assert load_odca_file(file) == [
        {"name": "pair-0000", "rule": rule0.id, "colorset": "S3", "colors": ["#1E1E1E", "#1F1F1F", "#212121", "#202020"]}]

    s.handle_key("m")
    rule1 = s.rule
    s.handle_key("]")  # from S3 to S4
    assert "color set S4" in capsys.readouterr().out
    s.handle_key("S")  # append a copy of the screen
    assert len(load_odca_file(file)) == 2 and s.pair_index is None

    g_before = s.automaton.generation
    s.handle_key("n")  # pair 1: rule0, S3 arranged, and a screenful at once
    assert s.pair_index == 0 and s.rule == rule0
    assert s.automaton.generation == 0  # R-W8: a fresh field, scrolled in
    assert [c[0] for c in s.palette] == [0x1E, 0x1F, 0x21, 0x20]
    assert "pair 1/2 pair-0000 S3" in capsys.readouterr().out

    s.handle_key("5")
    s.handle_key("s")  # on a pair: rewrite its color set in place, rule kept
    out = capsys.readouterr().out
    assert "saved pair 1/2" in out and "saved 2 pairs to saver.odca" in out
    saved = load_odca_file(file)
    assert saved[0]["rule"] == rule0.id and saved[0]["colorset"] == "S5" and saved[0]["colors"] == grey(50)
    assert saved[1]["rule"] == rule1.id

    s.handle_key("n")  # pair 2
    assert s.rule == rule1 and s.pair_index == 1
    s.handle_key("n")  # the unsaved slot: the mutant with the set it arrived with
    out = capsys.readouterr().out
    assert "unsaved rule" in out and s.pair_index is None and s.rule == rule1
    s.handle_key("X")  # nothing under review: no-op
    assert len(load_odca_file(file)) == 2
    s.handle_key("p")  # back to pair 2
    s.handle_key("X")  # delete the last: shows the previous
    out = capsys.readouterr().out
    assert "deleted pair 2/2" in out and "saved 1 pair to saver.odca" in out
    assert s.pair_index == 0 and len(load_odca_file(file)) == 1
    s.handle_key("X")
    assert s.pair_index is None and load_odca_file(file) == []
    assert s.unsaved_rule == s.rule  # the rule on screen keeps running as the unsaved rule

    s.finish()  # exit writes the file
    assert load_odca_file(file) == []
    save_odca_file([{"rule": rule1.id, "colorset": "S7", "colors": grey(70)}], file)
    again = make_session(store, select_file=file)
    assert again.pair_index == 0 and again.rule == rule1
    assert again.palette[0] == rgb("#464646")
    again.handle_key("[")  # walks the pool backward from S7
    assert again.palette[0] == rgb("#3C3C3C")  # S6
    again.finish()
    assert load_odca_file(file)[0]["colorset"] == "S7"  # exit rewrites what it loaded


def test_select_keys_inert_elsewhere(make_store):  # PT-28
    s = make_session(review_store(make_store))
    for k in "NPXRsS":
        s.handle_key(k)
    assert s.pairs == [] and not s.grouped


def test_grouped_order_toggle(make_store, odca_file, capsys):  # PT-30
    store = review_store(make_store)
    file = odca_file(name="saver.odca")
    a, b, c = "0" * 20, "1" * 20, "2" * 20
    original = [{"rule": r, "colorset": n, "colors": grey(int(n[1:]) * 10)}
                for r, n in [(a, "S1"), (b, "S2"), (a, "S3"), (c, "S4"), (b, "S5")]]
    save_odca_file(original, file)
    s = make_session(store, select_file=file)
    assert s.view_order == [0, 1, 2, 3, 4] and not s.grouped
    capsys.readouterr()
    s.handle_key("R")  # grouped by rule: A A B B C
    out = capsys.readouterr().out
    assert "pair order grouped by rule" in out and s.grouped
    assert s.view_order == [0, 2, 1, 4, 3]
    assert s.pair_index == 0 and s.view_position == 0  # the pair under review is kept
    assert s.inverted and s.flash_remaining == 0.25  # R-U10
    s.tick(0.1)
    assert s.inverted
    s.handle_key(" ")
    s.tick(0.2)  # the flash ends on the wall clock even while paused
    assert not s.inverted
    s.handle_key(" ")
    s.handle_key("n")
    out = capsys.readouterr().out
    assert "pair 2/5 pair-0002 S3" in out and "rule group" not in out
    s.handle_key("n")
    out = capsys.readouterr().out
    assert "--- rule group 2/3 ---" in out and "pair 3/5 pair-0001 S2" in out
    assert s.pair_index == 1
    s.handle_key("S")  # append a B pair: end of file, grouped with B in the view
    assert len(s.pairs) == 6 and s.view_order == [0, 2, 1, 4, 5, 3] and s.view_position == 2
    s.handle_key("n")
    s.handle_key("n")  # the appended pair, same group: no marker
    out = capsys.readouterr().out
    assert "pair 5/6" in out and "rule group" not in out and s.pair_index == 5
    s.handle_key("n")
    assert "--- rule group 3/3 ---" in capsys.readouterr().out and s.pair_index == 3
    s.handle_key("7")
    s.handle_key("s")
    saved = load_odca_file(file)
    assert [p["colorset"] for p in saved] == ["S1", "S2", "S3", "S7", "S5", "S2"]  # file order kept
    s.handle_key("p")
    s.handle_key("X")  # delete the appended pair: file loses its last entry
    assert [p["colorset"] for p in load_odca_file(file)] == ["S1", "S2", "S3", "S7", "S5"]
    assert s.view_position == 4 and s.pair_index == 3
    s.handle_key("R")  # back to file order, still on S7
    assert "pair order file order" in capsys.readouterr().out
    assert s.view_order == [0, 1, 2, 3, 4] and s.view_position == 3


def test_play_in_order_and_loops(make_store, odca_file, capsys):  # PT-31
    from odca.session import PLAY_TIMEOUT
    store = review_store(make_store)
    file = odca_file(name="saver.odca")
    save_odca_file([{"rule": ALL_ZERO.id, "colorset": "A", "colors": grey(10)},
                    {"rule": ALL_ZERO.id, "colorset": "B", "colors": grey(20)}], file)
    s = make_session(store, show=load_show([file]))
    assert s.play_mode and not s.select_mode and not s.review_mode
    assert s.title == f"ODCA — rule {ALL_ZERO.id}" and s.counter is None  # R-U6, R-O17: no counter outside --longest
    assert s.pair_index == 0 and s.rule == ALL_ZERO
    assert s.palette[0] == rgb("#0A0A0A")
    assert s.automaton.generation == 0
    out = capsys.readouterr().out
    assert "odca saver.odca: 2 pairs" in out and "pair 1/2 A" in out
    assert "(" not in out.split("pair 1/2 A")[1]
    for _ in range(17):
        s.tick(1 / 60)
    assert s.pair_index == 0 and s.automaton.generation == 0  # re-seeded in place
    out = capsys.readouterr().out
    assert "auto-init (repeating (period 1))" in out and "pair 2/2" not in out
    s.handle_key("a")
    s.tick(110)
    assert s.pair_index == 0
    s.handle_key("i")  # grace restarts; the watchdog does not
    assert abs(s.play_elapsed - 110) < 1
    s.handle_key("a")
    for _ in range(5):
        s.handle_key("-")  # ~18 generations in the next tick: the transition leaves old rows on screen
    capsys.readouterr()
    s.tick(10)  # the watchdog expires during this tick; boredom fires within it
    assert s.pair_index == 1
    assert s.play_elapsed < 1
    assert s.palette[0] == rgb("#141414")
    palettes = list(s.row_palettes)
    first_b = palettes.index(1)
    assert palettes[first_b - 1] == 0 and palettes[-1] == 1  # R-X5
    assert s.color(first_b - 1, 0) == rgb("#0A0A0A")
    assert s.palette_table[0] == rgb("#0A0A0A") and s.palette_table[4] == rgb("#141414")
    assert "pair 2/2 B (repeating (period 1))" in capsys.readouterr().out
    s.tick(PLAY_TIMEOUT)  # loops back to pair 1
    assert s.pair_index == 0
    out = capsys.readouterr().out
    assert "pair 1/2 A (repeating (period 1))" in out and "pair 2/2" not in out
    s.tick(1 / 60)
    s.handle_key("N")
    assert s.pair_index == 1 and s.automaton.generation == 0
    assert "pair 2/2 B (next)" in capsys.readouterr().out
    s.handle_key("n")  # n/p are N/P here; wraps
    assert s.pair_index == 0
    s.handle_key(" ")
    s.handle_key("P")  # live while paused; wraps backward
    assert s.pair_index == 1
    assert "pair 2/2 B (previous)" in capsys.readouterr().out
    s.handle_key("n")  # so are n/p in odca (R-X6)
    assert s.pair_index == 0 and s.paused
    s.handle_key("p")
    assert s.pair_index == 1
    assert "pair 2/2 B (previous)" in capsys.readouterr().out
    s.handle_key("s")  # the file is never written by odca
    s.handle_key("S")
    s.handle_key("X")
    assert len(load_odca_file(file)) == 2


def test_play_watchdog_and_grace_period(make_store, odca_file, capsys):  # PT-31
    store = review_store(make_store)
    file = odca_file(name="saver.odca")
    save_odca_file([{"rule": ALL_PRODUCIBLE.id, "colorset": "A", "colors": grey(10)},
                    {"rule": ALL_PRODUCIBLE.id, "colorset": "B", "colors": grey(20)}], file)
    s = make_session(store, show=load_show([file]))
    s.handle_key("a")  # auto-init off: only time sequences now
    for _ in range(50):
        s.handle_key("+")
    capsys.readouterr()
    s.tick(100)
    s.handle_key(" ")
    s.tick(1000)  # paused time counts for nothing
    s.handle_key(" ")
    s.handle_key("i")  # at 100 s: restarts the grace period, not the watchdog
    assert s.since_init == 0 and abs(s.play_elapsed - 100) < 1e-6
    s.tick(20)
    assert s.pair_index == 0
    s.tick(39.5)
    assert s.pair_index == 0
    s.tick(1.0)  # 60 s since the re-seed: transition
    assert s.pair_index == 1
    assert "pair 2/2 B (timeout)" in capsys.readouterr().out
    assert s.play_elapsed == 0
    s.tick(119.5)
    assert s.pair_index == 1
    s.tick(1.0)
    assert s.pair_index == 0


def test_watchdog_and_grace_are_construction_parameters(make_store, odca_file, capsys):  # PT-31, R-X2, R-X3
    store = review_store(make_store)
    file = odca_file(name="saver.odca")
    save_odca_file([{"rule": ALL_PRODUCIBLE.id, "colorset": "A", "colors": grey(10)},
                    {"rule": ALL_PRODUCIBLE.id, "colorset": "B", "colors": grey(20)}], file)
    s = make_session(store, show=load_show([file]), play_timeout=20, play_grace=10)
    s.handle_key("a")  # only the clocks transition
    s.tick(19)
    assert s.pair_index == 0
    s.tick(1.5)  # 20.5 s: the watchdog has expired and the grace period is long satisfied
    assert s.pair_index == 1
    assert "pair 2/2 B (timeout)" in capsys.readouterr().out
    s.tick(15)
    s.handle_key("i")  # 15 s in: the grace period restarts, the watchdog does not
    s.tick(6)  # 21 s: expired, but only 6 s since the re-seed
    assert s.pair_index == 1
    s.tick(4.5)  # 25.5 s: 10.5 s since the re-seed
    assert s.pair_index == 0


def test_play_shuffle_draws_a_fresh_order_of_the_files(make_store, odca_file, capsys):  # PT-36
    store = review_store(make_store)
    files = []
    for name, rules in (("a.odca", (ALL_PRODUCIBLE, FOUR[1])), ("b.odca", (FOUR[2],)), ("c.odca", (ALL_ZERO, FOUR[1], FOUR[2]))):
        files.append(odca_file(rules, name=name))
    show = load_show(files)
    s = make_session(store, show=show, shuffle=True)
    assert s.shuffle
    out = capsys.readouterr().out
    assert "odca a.odca: 2 pairs\nodca b.odca: 1 pairs\nodca c.odca: 3 pairs\n" in out
    assert "playing " in out and out.index("playing ") < out.index("pair 1/")  # R-O13: the first file is announced
    played = [(s.play_segment, s.pair_index)]
    for _ in range(59):  # ten passes of six pairs
        s.handle_key("N")
        played.append((s.play_segment, s.pair_index))
    sizes = [2, 1, 3]
    for p in range(10):
        one_pass = played[6 * p:6 * p + 6]
        order = [seg for seg, i in one_pass if i == 0]  # the files, in the order the pass plays them
        assert sorted(order) == [0, 1, 2]  # every file once
        expected = [(seg, i) for seg in order for i in range(sizes[seg])]
        assert one_pass == expected  # the pairs of a file in file order, the file played whole
    seams = [(played[6 * p - 1][0], played[6 * p][0]) for p in range(1, 10)]
    assert all(a != b for a, b in seams)  # never the same file twice running
    assert len({tuple(seg for seg, i in played[6 * p:6 * p + 6] if i == 0) for p in range(10)}) > 1  # fresh draws
    out = capsys.readouterr().out
    assert out.count("playing ") == 29  # every file entry announced, three per pass (the first read above)
    s.handle_key("P")  # back one within the pass
    assert (s.play_segment, s.pair_index) == played[-2]
    plain = make_session(store, show=show)
    assert not plain.shuffle
    assert plain.play_order == [(0, 0, None), (0, 1, None), (1, 0, None), (2, 0, None), (2, 1, None), (2, 2, None)]  # command-line order
    # One file with pairs among empty ones: it plays on, and shuffling changes nothing that shows.
    empty = odca_file(name="empty.odca")
    empty.write_text('{"pairs": []}')
    s = make_session(store, show=load_show([empty, files[1], empty]), shuffle=True)
    for _ in range(4):
        s.handle_key("N")
    assert (s.play_segment, s.pair_index) == (1, 0)
    # A single file: `playing` is never printed, and every pass is the file's order.
    s = make_session(store, show=load_show([files[2]]), shuffle=True)
    capsys.readouterr()
    for _ in range(6):
        s.handle_key("N")
    out = capsys.readouterr().out
    assert "playing" not in out and s.pair_index == 0


def test_play_shuffle_draws_a_fresh_order_of_a_script_pairs(make_store, odca_file, tmp_path, capsys):  # PT-39
    store = review_store(make_store)
    a, b, c = ALL_PRODUCIBLE, FOUR[1], FOUR[2]  # three distinct rules
    x, y, z = grey(10), grey(20), grey(30)
    pairs = [(a, "X", x), (a, "Y", y), (b, "X'", list(reversed(x))), (b, "Z", z), (c, "Y", y), (c, "Z", z)]
    file = odca_file(name="six.odca")
    save_odca_file([{"rule": r.id, "colorset": n, "colors": cs} for r, n, cs in pairs], file)
    script = tmp_path / "six.play"
    script.write_text("import six.odca\nshuffle\n")
    s = make_session(store, show=load_show([script]))
    assert not s.shuffle  # the script asked, not the command line
    assert "odca six.play: 6 pairs, shuffled" in capsys.readouterr().out  # R-O13
    played = [s.pair_index]
    for _ in range(59):  # ten passes
        s.handle_key("N")
        played.append(s.pair_index)
    for p in range(10):
        assert sorted(played[6 * p:6 * p + 6]) == list(range(6))  # every pass: every pair once
    for i, j in zip(played, played[1:]):  # never the same rule or color set in a row, seams included
        assert pairs[i][0] != pairs[j][0], (i, j)
        assert sorted(pairs[i][2]) != sorted(pairs[j][2]), (i, j)
    s.handle_key("P")  # back one within the pass
    assert s.pair_index == played[-2]
    script.write_text("import six.odca\nplay\n")  # plain play: file order
    plain = make_session(store, show=load_show([script]))
    assert plain.play_order == [(0, i, None) for i in range(6)]
    assert ", shuffled" not in capsys.readouterr().out
    # No order can avoid a repeat: the requirement is dropped and the show goes on.
    save_odca_file([{"rule": a.id, "colorset": "X", "colors": x}, {"rule": a.id, "colorset": "Y", "colors": y}], file)
    script.write_text("import six.odca\nshuffle\n")
    s = make_session(store, show=load_show([script]))
    played = [s.pair_index]
    for _ in range(5):
        s.handle_key("N")
        played.append(s.pair_index)
    assert all(sorted(played[i:i + 2]) == [0, 1] for i in (0, 2, 4))


def test_a_shuffled_script_keeps_its_seam_with_the_other_files(make_store, odca_file, tmp_path, capsys):  # PT-39
    store = review_store(make_store)
    a, b = FOUR[1], FOUR[2]
    x, y = grey(10), grey(20)
    # The plain file ends on rule b with colors y; the shuffled file holds one
    # pair on each, so only b-then-a, y-then-x can open its pass.
    plain_file = odca_file(name="plain.odca")
    save_odca_file([{"rule": b.id, "colorset": "Y", "colors": y}], plain_file)
    shuffled_file = odca_file(name="two.odca")
    save_odca_file([{"rule": b.id, "colorset": "Y", "colors": y},
                    {"rule": a.id, "colorset": "X", "colors": x}], shuffled_file)
    script = tmp_path / "two.play"
    script.write_text("import two.odca\nshuffle\n")
    s = make_session(store, show=load_show([plain_file, script]))
    capsys.readouterr()
    for _ in range(20):
        assert s.play_order[1:] == [(1, 1, None), (1, 0, None)], s.play_order  # the clashing pair never opens the file
        s.handle_key("N")


def test_arrival_uses_the_longest_recorded_seed_at_the_screen_width(make_store, odca_file, tmp_path, capsys):  # PT-42, R-X4
    store = review_store(make_store)
    file = odca_file([ALL_ZERO, ALL_PRODUCIBLE], name="seeded.odca")
    best, second, wrong_width = [3] * 32, [2] * 32, [1] * 33
    save_odca_file(load_odca_file(file), file, seeds={ALL_ZERO.id: {
        32: [{"row": second, "generations": 5, "end": "state 1 extinct"},
             {"row": best, "generations": 9, "end": "survived"}],
        33: [{"row": wrong_width, "generations": 99, "end": "survived"}]}})
    s = make_session(store, show=load_show([file]))
    assert list(s.automaton.cells) == best and s.automaton.generation == 0  # pair 1: its longest seed at 32 cells
    s.handle_key("N")  # pair 2 has no seeds: random
    assert list(s.automaton.cells) != best and len(s.automaton.cells) == 32
    s.handle_key("N")  # back to pair 1: the seed again
    assert list(s.automaton.cells) == best
    s.handle_key("i")  # a manual re-seed is random, as ever
    assert list(s.automaton.cells) != best
    assert s.resize(33, 16)
    s.handle_key("N")
    s.handle_key("N")  # pair 1 at 33 cells: that width's seed
    assert list(s.automaton.cells) == wrong_width
    script = tmp_path / "seeded.play"  # a script show carries the seeds of every file it imports
    script.write_text("import seeded.odca\nplay\n")
    assert list(make_session(store, show=load_show([script])).automaton.cells) == best


def block(threes, width):
    """A block of 3s in a field of 1s under KILLS_THREE: the block loses a cell
    at each edge per generation, so a block of 2k dies at generation k."""
    lead = (width - threes) // 2
    return [1] * lead + [3] * threes + [1] * (width - threes - lead)


def test_longest_plays_the_recorded_seeds_rank_by_rank(make_store, odca_file, capsys):  # PT-44, R-X8, R-O13
    from odca.show import seed_width
    from odca.store import SURVIVED
    store = review_store(make_store)
    file = odca_file(name="seeded.odca")
    a, b, c = KILLS_THREE, ALL_PRODUCIBLE, ALL_ZERO
    save_odca_file([{"rule": a.id, "colorset": "A", "colors": grey(10)},
                    {"rule": b.id, "colorset": "B", "colors": grey(20)},
                    {"rule": c.id, "colorset": "C", "colors": grey(30)}], file, seeds={
        a.id: {32: [{"row": block(16, 32), "generations": 8, "end": "state 3 extinct"},
                    {"row": block(12, 32), "generations": 6, "end": "state 3 extinct"}],
               33: [{"row": block(16, 33), "generations": 8, "end": "state 3 extinct"}]},
        b.id: {32: [{"row": [0] * 32, "generations": 100000, "end": SURVIVED},
                    {"row": [2] * 32, "generations": 5, "end": "state 1 extinct"}]}})
    show = load_show([file])
    with pytest.raises(ShowError) as e:  # two widths: --cells must choose
        seed_width(show)
    assert str(e.value) == "seeds at 32, 33 cells: choose one with --cells"
    assert seed_width(show, 32) == 32
    with pytest.raises(ShowError) as e:
        seed_width(show, 40)
    assert str(e.value) == "no seeds at 40 cells (32, 33)"
    survivors = odca_file(name="survivors.odca")
    save_odca_file([{"rule": b.id, "colorset": "B", "colors": grey(20)}], survivors,
                   seeds={b.id: {32: [{"row": [0] * 32, "generations": 9, "end": SURVIVED}]}})
    with pytest.raises(ShowError) as e:
        seed_width(load_show([survivors]))
    assert str(e.value) == "no seeds to play"  # survivors are not played

    s = make_session(store, show=show, longest=True, play_timeout=1, play_grace=1)
    assert s.longest and s.play_mode
    out = capsys.readouterr().out
    assert "odca seeded.odca: 3 pairs, 3 seeds at 32 cells" in out
    assert "pair 1/3 A, seed 1/2, 8 generations\n" in out
    # Every pair's longest, then every pair's second: A1, B1 (its survivor left out), A2; C has none.
    assert s.play_order == [(0, 0, 0), (0, 1, 0), (0, 0, 1)]
    assert list(s.automaton.cells) == block(16, 32) and s.rule == a
    assert s.title == f"ODCA — rule {a.id}"  # R-U6: the title is the rule's alone
    assert s.counter == "0/8"  # R-O17: the generation counter
    s.tick(s.delay * 3)
    assert s.counter == "3/8"
    for key in "rmuUa":  # the rule keys and auto-init are inert; the color keys are not
        s.handle_key(key)
    assert s.rule == a and s.auto_init and not s.undo_stack
    s.handle_key("2")
    assert s.active_name == "S2"
    assert s.resize(40, 20)  # the width is the seeds'; only the height follows the window
    assert (s.cols, s.rows) == (32, 20)
    assert "resized 32x20" in capsys.readouterr().out
    assert not s.resize(48, 20)
    s.handle_key(" ")  # `i` restarts the seed on screen (once resumed: it is not live while paused, R-K10)
    for _ in range(3):
        s.handle_key("\n")
    assert list(s.automaton.cells) != block(16, 32)
    s.handle_key(" ")
    s.handle_key("i")
    assert list(s.automaton.cells) == block(16, 32) and s.automaton.generation == 0
    # No clocks: with a one-second watchdog and grace period, six quiet seconds
    # (the delay at its slowest, no generation computed) change nothing.
    for _ in range(12):
        s.handle_key("-")
    for _ in range(3):
        s.tick(2)
    assert s.pair_index == 0 and s.automaton.generation == 0
    assert "timeout" not in capsys.readouterr().out
    # The seed plays to its extinction (generation 8), and a screenful (20 rows)
    # past it (R-A2) the next seed takes over: at generation 27; no re-seed in place.
    s.handle_key(" ")
    for _ in range(26):
        s.handle_key("\n")
    assert s.pair_index == 0
    s.handle_key("\n")
    assert s.pair_index == 1
    out = capsys.readouterr().out
    assert "pair 2/3 B, seed 1/1, 5 generations (state 3 extinct)" in out and "auto-init" not in out
    assert list(s.automaton.cells) == [2] * 32 and s.automaton.generation == 0
    s.handle_key("N")  # N and P walk the items, wrapping; the third is A's second seed
    assert "pair 1/3 A, seed 2/2, 6 generations (next)" in capsys.readouterr().out
    assert list(s.automaton.cells) == block(12, 32)
    s.handle_key("n")  # n and p are live while paused in odca, as N and P are (R-X6)
    assert "pair 1/3 A, seed 1/2, 8 generations (next)" in capsys.readouterr().out
    s.handle_key("p")
    assert "seed 2/2, 6 generations (previous)" in capsys.readouterr().out


def test_longest_shuffle_keeps_rules_and_colors_apart(make_store, odca_file):  # PT-44, R-X8
    store = review_store(make_store)
    file = odca_file(name="seeded.odca")
    rules = [ALL_PRODUCIBLE, FOUR[1], FOUR[2]]
    seeds = {r.id: {32: [{"row": [i] * 32, "generations": 9, "end": "x"}, {"row": [3] * 32, "generations": 4, "end": "x"}]}
             for i, r in enumerate(rules)}
    save_odca_file([{"rule": r.id, "colorset": f"S{i}", "colors": grey(10 * i)} for i, r in enumerate(rules)], file, seeds=seeds)
    s = make_session(store, show=load_show([file]), shuffle=True, longest=True)
    played = [(s.pair_index, s.play_order[s.play_position][2])]
    for _ in range(59):
        s.handle_key("N")
        played.append((s.pair_index, s.play_order[s.play_position][2]))
    orders = set()
    for p in range(10):
        one_pass = played[6 * p:6 * p + 6]
        assert sorted(one_pass) == [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)]
        orders.add(tuple(one_pass))
    assert all(x[0] != y[0] for x, y in zip(played, played[1:]))  # never the same pair twice running
    assert len(orders) > 1
    plain = make_session(store, show=load_show([file]), longest=True)
    assert [(i, rank) for _, i, rank in plain.play_order] == [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1)]


def test_select_longest_presents_only_the_pairs_with_seeds(make_store, odca_file, capsys):  # PT-45, R-W9
    from odca.store import load_seeds
    store = review_store(make_store)
    file = odca_file(name="curate.odca")
    a, b, c = ALL_PRODUCIBLE, FOUR[1], ALL_ZERO
    save_odca_file([{"rule": a.id, "colorset": "A", "colors": grey(10)},
                    {"rule": c.id, "colorset": "C", "colors": grey(30)},  # no seeds: not shown
                    {"rule": a.id, "colorset": "A2", "colors": grey(40)},  # shares A's rule and seeds
                    {"rule": b.id, "colorset": "B", "colors": grey(20)}], file, seeds={
        a.id: {32: [{"row": [1] * 32, "generations": 9, "end": "state 2 extinct"}]},
        b.id: {40: [{"row": [2] * 40, "generations": 100000, "end": "survived"}]}})  # any seeds count, any width
    s = make_session(store, select_file=file, select_longest=True)
    out = capsys.readouterr().out
    assert "odca curate.odca: 4 pairs, 3 with seeds" in out and "pair 1/3 pair-0000 A" in out
    assert s.select_longest and s.view_order == [0, 2, 3] and s.pair_index == 0
    assert list(s.automaton.cells) != [1] * 32 or s.cols != 32  # no seeding from the vectors
    s.handle_key("n")
    assert "pair 2/3 pair-0002 A2" in capsys.readouterr().out
    s.handle_key("n")
    s.handle_key("n")  # then the unsaved slot is empty: wraps to the first
    assert "pair 1/3 pair-0000 A" in capsys.readouterr().out
    s.handle_key("R")  # grouped within the shown set
    assert s.view_order == [0, 2, 3]
    s.handle_key("R")
    s.handle_key("2")  # colors change and s saves them in place, as ever
    s.handle_key("s")
    assert "saved pair 1/3" in capsys.readouterr().out
    assert load_odca_file(file)[0]["colorset"] == "S2"
    s.handle_key("S")  # appends a copy on A's rule, which has seeds: shown; the position stays
    assert "added pair 5/5" in capsys.readouterr().out
    assert len(load_odca_file(file)) == 5 and s.view_order == [0, 2, 3, 4] and s.pair_index == 0
    s.handle_key("m")  # a mutation then s: appended on a rule without seeds, not shown, position kept
    s.handle_key("s")
    assert "added pair 6/6" in capsys.readouterr().out
    assert s.pair_index == 0 and s.view_order == [0, 2, 3, 4]
    assert load_seeds(file) == {a.id: {32: [{"row": [1] * 32, "generations": 9, "end": "state 2 extinct"}]},
                                b.id: {40: [{"row": [2] * 40, "generations": 100000, "end": "survived"}]}}
    s.handle_key("u")
    s.handle_key("X")  # deletes A's seeds: both of A's pairs drop out, the file keeps its pairs
    out = capsys.readouterr().out
    assert "deleted seeds of pair 1/4 pair-0000 S2" in out and "pair 1/1 pair-0003 B" in out
    assert s.view_order == [3] and len(load_odca_file(file)) == 6
    assert load_seeds(file) == {b.id: {40: [{"row": [2] * 40, "generations": 100000, "end": "survived"}]}}
    s.handle_key("X")  # the last shown pair: nothing to show, the rule on screen is the unsaved rule
    assert s.view_order == [] and s.pair_index is None and s.unsaved_rule == b
    assert load_seeds(file) == {} and len(load_odca_file(file)) == 6
    s.handle_key("n")
    assert "no pairs" in capsys.readouterr().out
    plain = make_session(store, select_file=file)  # without the flag: every pair, seeds carried through
    assert plain.view_order == list(range(6)) and not plain.select_longest


def test_brackets_walk_the_pool_in_base_mode(make_store, capsys):  # PT-33
    store = review_store(make_store)
    s = make_session(store)
    assert s.active_name == "S1" and s.palette[0] == rgb("#0A0A0A")
    s.handle_key("]")
    assert s.active_name == "S2" and s.color_set == 2
    assert "color set S2" in capsys.readouterr().out
    for _ in range(8):
        s.handle_key("]")
    assert s.active_name == "S0"
    s.handle_key("]")  # beyond the hot ten: the pool
    assert s.active_name == "PoolA" and s.active_set["slot"] is None
    assert s.palette[0] == rgb("#646464")
    s.handle_key("]")  # wraps
    assert s.active_name == "S1"
    s.handle_key("[")
    s.handle_key("[")
    assert s.active_name == "S0"
    s.handle_key("4")
    assert s.active_name == "S4"
    for _ in range(7):
        s.handle_key("]")  # S5 .. S0, PoolA
    assert s.active_name == "PoolA"
    s.handle_key("c")
    s.handle_key("S")  # R-K16 survives only without a program (for the color set tool)
    assert "saved color set PoolA" in capsys.readouterr().out
    entry = next(e for e in store.load_color_set_file()["sets"] if e["name"] == "PoolA")
    assert entry["slot"] is None
    g = grey(100)
    assert entry["colors"] == [g[0], g[1], g[3], g[2]]
    s.handle_key("1")
    assert s.palette[0] == rgb("#0A0A0A")


def test_pair_carries_its_color_set_and_cycle_applies_it(make_store, odca_file, capsys):  # PT-34
    store = review_store(make_store)
    s = make_session(store, select_file=odca_file(name="saver.odca"))
    s.handle_key("3")
    s.handle_key("c")
    rule = s.rule
    capsys.readouterr()
    s.handle_key("S")
    assert "added pair 1/1" in capsys.readouterr().out
    pairs = load_odca_file(s.select_file)
    assert len(pairs) == 1 and pairs[0]["colorset"] == "S3"
    assert pairs[0]["colors"] == ["#1E1E1E", "#1F1F1F", "#212121", "#202020"]
    s.handle_key("m")
    mutant = s.rule
    s.handle_key("7")  # S7 showing with the unsaved (mutant) rule
    assert s.unsaved_set["name"] == "S3"  # captured when the mutant arrived
    s.handle_key("n")
    assert s.rule == rule
    assert [c[0] for c in s.palette] == [0x1E, 0x1F, 0x21, 0x20]
    assert "pair 1/1 pair-0000 S3" in capsys.readouterr().out
    s.handle_key("n")  # back to the unsaved slot: mutant with S3
    assert s.rule == mutant
    assert s.palette[0] == rgb("#1E1E1E")


def test_mutating_a_pair_saves_it_as_a_new_pair(make_store, odca_file, capsys):  # PT-34, R-K3, R-W4
    store = review_store(make_store)
    file = odca_file(rules=[FOUR[0], FOUR[1]], name="saver.odca")
    s = make_session(store, select_file=file)
    assert s.pair_index == 0 and s.unsaved_rule is None
    s.handle_key("3")
    capsys.readouterr()
    s.handle_key("s")  # colors only: the pair is rewritten in place
    assert "saved pair 1/2" in capsys.readouterr().out
    assert load_odca_file(file)[0] == {"name": "pair-0000", "rule": FOUR[0].id, "colorset": "S3", "colors": grey(30)}
    s.handle_key("m")  # pair 1 is now changed: the position stays, the unsaved slot stays empty
    assert s.rule != FOUR[0] and s.pair_index == 0 and s.view_position == 0 and s.unsaved_rule is None
    s.handle_key("u")  # walked back, still on pair 1
    assert s.rule == FOUR[0] and s.pair_index == 0
    s.handle_key("m")
    mutant = s.rule
    s.handle_key("5")
    capsys.readouterr()
    s.handle_key("s")  # a changed pair is saved as a new pair at the end; the kept rule survives
    assert "added pair 3/3" in capsys.readouterr().out
    pairs = load_odca_file(file)
    assert [l["rule"] for l in pairs] == [FOUR[0].id, FOUR[1].id, mutant.id]
    assert pairs[0]["colorset"] == "S3" and pairs[2]["colorset"] == "S5"
    assert s.pair_index == 2 and s.view_position == 2  # and the position moved onto it
    s.handle_key("U")  # nothing to unwind on the new pair
    assert s.rule == mutant
    s.handle_key("7")
    s.handle_key("s")  # colors again: refines the new pair in place
    assert "saved pair 3/3" in capsys.readouterr().out
    assert [l["colorset"] for l in load_odca_file(file)] == ["S3", "ODCA default", "S7"]
    s.handle_key("m")  # a further mutation, discarded by leaving the pair
    s.handle_key("n")
    s.handle_key("p")
    assert s.rule == mutant and s.pair_index == 2
    s.handle_key("r")  # a fresh rule is a new exploration: the unsaved slot, as before
    assert s.pair_index is None and s.unsaved_rule == s.rule
    s.handle_key("m")  # on the unsaved slot the mutant stays there
    assert s.pair_index is None and s.unsaved_rule == s.rule


def test_U_undoes_every_change_since_the_position_moved(make_store, odca_file):  # PT-9, R-K19
    store = review_store(make_store)
    s = make_session(store, select_file=odca_file(rules=[FOUR[0], FOUR[1]], name="saver.odca"))
    depth = len(s.undo_stack)
    for _ in range(3):
        s.handle_key("m")
    assert s.rule != FOUR[0] and len(s.undo_stack) == depth + 3
    s.handle_key("U")  # all three at once, still on pair 1
    assert s.rule == FOUR[0] and s.pair_index == 0 and len(s.undo_stack) == depth
    s.handle_key("U")  # nothing left since arriving here: a no-op
    assert s.rule == FOUR[0] and len(s.undo_stack) == depth
    s.handle_key("n")  # pair 2 (one push); edits here unwind to pair 2, not further
    s.handle_key("m")
    s.handle_key("m")
    s.handle_key("U")
    assert s.rule == FOUR[1] and s.pair_index == 1 and len(s.undo_stack) == depth + 1
    s.handle_key("r")  # the unsaved slot: U unwinds to the rule r brought
    fresh = s.rule
    s.handle_key("m")
    s.handle_key("m")
    assert s.rule != fresh
    s.handle_key("U")
    assert s.rule == fresh and s.pair_index is None and s.unsaved_rule == fresh
    s.handle_key(" ")  # paused: U is not live, like u
    s.handle_key("m")
    assert s.rule == fresh


def test_resize_preserves_center_and_uncovers_history(make_store, capsys):  # PT-32, R-U8
    s = make_session(make_store())
    s.handle_key("a")  # keep auto-init out of the way
    s.tick(s.delay * 40)  # 41 rows remembered, 16 + 1 shown
    assert s.filled == 41 and s.history.shape == (41, 32)
    assert s.visible_start == 41 - 17
    before = s.automaton.cells.copy()
    old_top = s.history[0].copy()
    capsys.readouterr()

    # Narrower: the middle 20 cells survive, in every remembered row.
    assert s.resize(20, 16)
    assert s.cols == 20
    assert list(s.automaton.cells) == list(before[6:26])
    assert list(s.history[0]) == list(old_top[6:26])
    assert s.filled == 41  # history kept
    assert s._boring_streak == 0  # detectors reset
    assert "resized 20x16" in capsys.readouterr().out

    # Wider: the 20 stay centered, older rows padded with 0, the live row with random cells.
    mid = s.automaton.cells.copy()
    assert s.resize(30, 16)
    assert list(s.automaton.cells[5:25]) == list(mid)
    assert list(s.history[0][:5]) == [0, 0, 0, 0, 0]
    assert list(s.history[-1]) == list(s.automaton.cells)
    for _ in range(5):
        s.tick(s.delay)
    assert len(s.automaton.cells) == 30 and s.history.shape[1] == 30

    # Taller: the window uncovers remembered rows instead of showing blank.
    assert s.resize(30, 40)
    assert s.visible_start == max(0, s.filled - 41)
    assert s.scroll_offset == 1.0  # 46 rows remembered > 40: still "full"
    assert not s.resize(30, 40)  # no change: nothing happens
    assert s.resize(1, 0)  # clamped to the minimum
    assert s.cols == MIN_COLS and s.rows == 1


def test_history_depth_is_bounded(make_store):  # PT-32, R-U8
    s = make_session(make_store())
    s.handle_key("a")
    for _ in range(50):
        s.handle_key("+")
    for _ in range(3):
        s.tick(1.0)  # well past the depth (2000 steps per tick cap)
    assert s.history.shape == (HISTORY_DEPTH, 32)
    assert len(s.row_palettes) == HISTORY_DEPTH
    newest = s.history[-1].copy()
    s.tick(s.delay)  # one more: the oldest row leaves, the newest is the live row
    assert s.history.shape == (HISTORY_DEPTH, 32)
    assert list(s.history[-2]) == list(newest)
    assert list(s.history[-1]) == list(s.automaton.cells)


def test_rows_keep_their_colors_through_quick_transitions(make_store, odca_file, capsys):  # PT-31, R-X5
    from odca.session import PALETTE_LIMIT
    store = review_store(make_store)
    file = odca_file(name="saver.odca")
    save_odca_file([{"rule": ALL_ZERO.id, "colorset": n, "colors": grey(v)}
                    for n, v in (("A", 10), ("B", 20), ("C", 30))], file)
    s = make_session(store, show=load_show([file]))
    s.handle_key("a")

    def painted(lo, hi, colors):
        for row in range(lo, hi):
            assert s.color(row, 0) == rgb(colors[int(s.history[row][0])]), row

    for _ in range(3):
        s.tick(s.delay)
    rows_a = s.filled
    s.handle_key("N")  # pair 2, well within the screenful
    for _ in range(3):
        s.tick(s.delay)
    rows_ab = s.filled
    s.handle_key("N")  # pair 3: a third color set on one screen
    for _ in range(3):
        s.tick(s.delay)
    painted(0, rows_a, grey(10))
    painted(rows_a, rows_ab, grey(20))
    painted(rows_ab, s.filled, grey(30))
    assert len(s.palette_table) == 12  # three palettes
    s.handle_key("N")  # back to pair 1: its palette is shared, not duplicated
    s.tick(s.delay)
    assert len(s.palette_table) == 12
    # Many distinct palettes (arrangements of each set) pass the table's limit:
    # it is pruned to what remembered rows still use, and no row changes color.
    for i in range(PALETTE_LIMIT + 10):
        s.handle_key("N")  # the pair shows its baked colors, arrangement 1
        for _ in range(i % 23 + 1):
            s.handle_key("c")  # then a different arrangement each time round
        s.tick(s.delay)
    painted(0, rows_a, grey(10))
    painted(rows_a, rows_ab, grey(20))
    assert 4 * PALETTE_LIMIT < len(s.palette_table) <= 4 * s.filled
