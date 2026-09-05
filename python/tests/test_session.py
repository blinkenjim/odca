"""Session properties (TESTS.md PT-9, PT-10, PT-10a, PT-13, PT-14 and more).

All file access goes to a temp Store; the search never starts workers.
"""

import json

import numpy as np
import pytest

from odca.automaton import Rule
from odca.search import CandidateSearch
from odca.session import INITIAL_DELAY, MAX_DELAY, MIN_DELAY, Session
from odca.store import Store, load_screensaver, save_screensaver

FOUR = [Rule.from_id(d * 20) for d in "0123"]
OUTSIDE = Rule.from_id("01230123012301230123")


@pytest.fixture
def make_store(tmp_path):
    def _make(saved=(), current=None):
        store = Store(
            state_dir=tmp_path / "state",
            keeper_file=tmp_path / "interesting-rules.txt",
            colorsets_file=tmp_path / "colorsets.json",
            candidates_file=tmp_path / "candidates.json",
        )
        for rule in saved:
            store.append_interesting(rule)
        if current is not None:
            store.save_rule(current)
        return store

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
    s.handle_key("s")  # unpaused: 's' saves, does not queue
    assert s.screen_remaining == 0 and s.store.load_interesting() == [s.rule]


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


def test_scroll_offset_semantics(make_store):  # PT-25, R-U3
    from odca.session import SMOOTH_SCROLL_DELAY
    s = make_session(make_store())
    s.handle_key("a")  # keep auto-init from re-seeding during the test
    assert s.history.shape == (s.rows + 1, s.cols)
    assert s.scroll_offset == 0.0  # filling: no scroll yet
    s.tick(s.delay * s.rows)  # buffer full (seed row + rows generations)
    assert s.filled == s.rows + 1
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


def test_screensaver_review_lifecycle(make_store, tmp_path, capsys):  # PT-28
    store = review_store(make_store)
    file = tmp_path / "saver.json"
    s = make_session(store, screensaver_file=file)
    assert s.screensaver_mode and not s.review_mode
    assert load_screensaver(file) == []  # a new, empty file was created
    assert s.pair_index is None
    assert "screensaver saver.json: 0 pairs" in capsys.readouterr().out
    rule0 = s.automaton.rule
    s.handle_key("N")
    assert capsys.readouterr().out == ""
    s.handle_key("s")
    assert "no pair under review" in capsys.readouterr().out

    s.handle_key("3")  # S3 = grey(30)
    s.handle_key("c")  # arranged (0,1,3,2)
    s.handle_key("S")  # append pair 1; position unchanged
    out = capsys.readouterr().out
    assert "added pair 1/1" in out and "saved 1 pair to saver.json" in out
    assert s.pair_index is None
    saved = load_screensaver(file)
    assert saved == [{"rule": rule0.id, "colorset": "S3", "colors": ["#1E1E1E", "#1F1F1F", "#212121", "#202020"]}]

    s.handle_key("m")
    rule1 = s.automaton.rule
    s.handle_key("]")  # from S3 to S4
    assert "color set S4" in capsys.readouterr().out
    s.handle_key("S")
    assert len(load_screensaver(file)) == 2

    g_before = s.automaton.generation
    s.handle_key("N")  # activates pair 1: rule0, S3 arranged, and a screenful at once
    assert s.pair_index == 0
    assert s.automaton.rule == rule0
    assert s.automaton.generation == g_before + s.rows  # R-W8
    assert [c[0] for c in s.palette] == [0x1E, 0x1F, 0x21, 0x20]
    assert "screensaver 1/2 S3" in capsys.readouterr().out
    s.handle_key("P")  # no wrap at the start
    assert "screensaver end" in capsys.readouterr().out
    assert s.pair_index == 0

    s.handle_key("5")
    s.handle_key("s")  # save in place
    out = capsys.readouterr().out
    assert "saved pair 1/2" in out and "saved 2 pairs to saver.json" in out
    saved = load_screensaver(file)
    assert saved[0]["colorset"] == "S5" and saved[0]["colors"] == grey(50)
    assert saved[1]["rule"] == rule1.id

    s.handle_key("N")
    assert s.automaton.rule == rule1
    s.handle_key("N")
    assert "screensaver end" in capsys.readouterr().out
    s.handle_key("X")  # delete the last: shows the previous
    out = capsys.readouterr().out
    assert "deleted pair 2/2" in out and "saved 1 pair to saver.json" in out
    assert s.pair_index == 0
    assert len(load_screensaver(file)) == 1
    s.handle_key("X")
    assert s.pair_index is None
    assert load_screensaver(file) == []

    save_screensaver([{"rule": rule1.id, "colorset": "S7", "colors": grey(70)}], file)
    again = make_session(store, screensaver_file=file)
    assert again.pair_index == 0 and again.automaton.rule == rule1
    assert again.palette[0] == rgb("#464646")
    again.handle_key("[")  # walks the pool backward from S7
    assert again.palette[0] == rgb("#3C3C3C")  # S6


def test_consistency_check_groups_by_rule_for_view_only(make_store, tmp_path, capsys):  # PT-30
    store = review_store(make_store)
    file = tmp_path / "saver.json"
    a, b, c = "0" * 20, "1" * 20, "2" * 20
    original = [{"rule": r, "colorset": n, "colors": grey(int(n[1:]) * 10)}
                for r, n in [(a, "S1"), (b, "S2"), (a, "S3"), (c, "S4"), (b, "S5")]]
    save_screensaver(original, file)
    s = make_session(store, screensaver_file=file, group_by_rule=True)
    assert s.view_order == [0, 2, 1, 4, 3]  # A A B B C
    out = capsys.readouterr().out
    assert "--- rule group 1/3 ---" in out and "screensaver 1/5 S1" in out
    s.handle_key("N")
    out = capsys.readouterr().out
    assert "screensaver 2/5 S3" in out and "rule group" not in out
    s.handle_key("N")
    out = capsys.readouterr().out
    assert "--- rule group 2/3 ---" in out and "screensaver 3/5 S2" in out
    assert s.pair_index == 1
    s.handle_key("S")  # append a B pair: end of file, grouped with B in the view
    assert len(s.pairs) == 6
    assert s.view_order == [0, 2, 1, 4, 5, 3]
    assert s.view_position == 2
    s.handle_key("N")
    s.handle_key("N")  # the appended pair, same group: no marker
    out = capsys.readouterr().out
    assert "screensaver 5/6" in out and "rule group" not in out
    assert s.pair_index == 5
    s.handle_key("N")
    assert "--- rule group 3/3 ---" in capsys.readouterr().out
    assert s.pair_index == 3
    s.handle_key("7")
    s.handle_key("s")
    saved = load_screensaver(file)
    assert [p["colorset"] for p in saved] == ["S1", "S2", "S3", "S7", "S5", "S2"]
    assert saved[5]["rule"] == b
    s.handle_key("P")
    s.handle_key("X")  # delete the appended pair: file loses its last entry
    saved = load_screensaver(file)
    assert [p["colorset"] for p in saved] == ["S1", "S2", "S3", "S7", "S5"]
    assert s.view_position == 4 and s.pair_index == 3


def test_screensaver_plays_pairs_in_order_and_loops(make_store, tmp_path, capsys):  # PT-31
    from odca.session import PLAY_TIMEOUT
    store = review_store(make_store)
    file = tmp_path / "saver.json"
    save_screensaver([{"rule": ALL_ZERO.id, "colorset": "A", "colors": grey(10)},
                      {"rule": ALL_ZERO.id, "colorset": "B", "colors": grey(20)}], file)
    s = make_session(store, play_file=file)
    assert s.play_mode and not s.screensaver_mode and not s.review_mode
    assert s.pair_index == 0 and s.automaton.rule == ALL_ZERO
    assert s.palette[0] == rgb("#0A0A0A")
    assert s.automaton.generation == 0
    out = capsys.readouterr().out
    assert "screensaver saver.json: 2 pairs" in out and "screensaver 1/2 A" in out
    assert "(" not in out.split("screensaver 1/2 A")[1]
    for _ in range(17):
        s.tick(1 / 60)
    assert s.pair_index == 0 and s.automaton.generation == 0  # re-seeded in place
    out = capsys.readouterr().out
    assert "auto-init (repeating (period 1))" in out and "screensaver 2/2" not in out
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
    banks = list(s.row_banks)
    first_b = banks.index(1)
    assert banks[first_b - 1] == 0 and banks[-1] == 1  # R-X5
    assert s.color(first_b - 1, 0) == rgb("#0A0A0A")
    assert s.palette8[0] == rgb("#0A0A0A") and s.palette8[4] == rgb("#141414")
    assert "screensaver 2/2 B (repeating (period 1))" in capsys.readouterr().out
    s.tick(PLAY_TIMEOUT)  # loops back to pair 1
    assert s.pair_index == 0
    out = capsys.readouterr().out
    assert "screensaver 1/2 A (repeating (period 1))" in out and "screensaver 2/2" not in out
    s.tick(1 / 60)
    s.handle_key("N")
    assert s.pair_index == 1 and s.automaton.generation == 0
    assert "screensaver 2/2 B (next)" in capsys.readouterr().out
    s.handle_key("N")  # wraps
    assert s.pair_index == 0
    s.handle_key(" ")
    s.handle_key("P")  # live while paused; wraps backward
    assert s.pair_index == 1
    assert "screensaver 2/2 B (previous)" in capsys.readouterr().out


def test_screensaver_watchdog_and_grace_period(make_store, tmp_path, capsys):  # PT-31
    store = review_store(make_store)
    file = tmp_path / "saver.json"
    save_screensaver([{"rule": ALL_PRODUCIBLE.id, "colorset": "A", "colors": grey(10)},
                      {"rule": ALL_PRODUCIBLE.id, "colorset": "B", "colors": grey(20)}], file)
    s = make_session(store, play_file=file)
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
    assert "screensaver 2/2 B (timeout)" in capsys.readouterr().out
    assert s.play_elapsed == 0
    s.tick(119.5)
    assert s.pair_index == 1
    s.tick(1.0)
    assert s.pair_index == 0


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
    s.handle_key("S")
    assert "saved color set PoolA" in capsys.readouterr().out
    entry = next(e for e in store.load_color_set_file()["sets"] if e["name"] == "PoolA")
    assert entry["slot"] is None
    g = grey(100)
    assert entry["colors"] == [g[0], g[1], g[3], g[2]]
    s.handle_key("1")
    assert s.palette[0] == rgb("#0A0A0A")


def test_saved_rule_carries_its_color_set_and_cycle_applies_it(make_store, capsys):  # PT-34
    store = review_store(make_store)
    s = make_session(store)
    s.handle_key("3")
    s.handle_key("c")
    rule = s.automaton.rule
    capsys.readouterr()
    s.handle_key("s")
    assert f"saved rule {rule.id} S3" in capsys.readouterr().out
    pairs = store.load_interesting_pairs()
    assert len(pairs) == 1 and pairs[0]["colorset"] == "S3"
    assert pairs[0]["colors"] == ["#1E1E1E", "#1F1F1F", "#212121", "#202020"]
    s.handle_key("m")
    mutant = s.automaton.rule
    s.handle_key("7")  # S7 showing with the unsaved (mutant) rule
    assert s.unsaved_set["name"] == "S3"  # captured when the mutant arrived
    s.handle_key("n")
    assert s.automaton.rule == rule
    assert [c[0] for c in s.palette] == [0x1E, 0x1F, 0x21, 0x20]
    assert "interesting 1/1 S3" in capsys.readouterr().out
    s.handle_key("n")  # back to the unsaved slot: mutant with S3
    assert s.automaton.rule == mutant
    assert s.palette[0] == rgb("#1E1E1E")
