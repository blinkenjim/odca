"""The pygame layer's geometry (R-U2, R-U3, R-U8), without a display.

Surfaces and surfarray work without a window, so the frame and the draw are
checked on plain surfaces; the window itself is manual (M-10).
"""

import numpy as np
import pygame
import pytest

from odca.search import CandidateSearch
from odca.session import Session
from odca.store import Store
from odca.viewer import MIN_COLS, MIN_ROWS, Viewer, grid_rect, grid_size


@pytest.fixture
def viewer(tmp_path):
    store = Store(state_dir=tmp_path / "state", library_file=tmp_path / "library.json",
                  candidates_file=tmp_path / "candidates.json")
    session = Session(40, 30, store=store, search=CandidateSearch(workers=0),
                      rng=np.random.default_rng(3))
    session.handle_key("a")  # no re-seeding during the test
    return Viewer(160, 120, 4, session=session)


def test_grid_follows_the_window_in_whole_cells():
    assert grid_size(1200, 800, 4) == (300, 200)
    assert grid_size(1203, 807, 4) == (300, 201)  # the remainder becomes margins
    assert grid_size(10, 10, 4) == (MIN_COLS, MIN_ROWS)  # never below the minimum
    assert grid_rect(1203, 807, 300, 201, 4) == (1, 1, 1200, 804)
    assert grid_rect(1200, 800, 300, 200, 4) == (0, 0, 1200, 800)


def test_frame_shows_the_last_rows_plus_one_with_background_below(viewer):
    s = viewer.session
    bg = s.palette[0]
    frame = viewer.frame()
    assert frame.shape == (31, 40, 3)
    assert tuple(frame[0, 0]) == s.palette[int(s.history[0][0])]  # the seed row on top
    assert (frame[1:] == bg).all()  # nothing remembered yet below it
    s.tick(s.delay * 60)  # 61 rows remembered: the frame is the newest 31
    frame = viewer.frame()
    assert s.visible_start == 30
    assert tuple(frame[-1, 5]) == s.palette[int(s.automaton.cells[5])]
    s.flash_remaining = 0.1  # R-U10: the whole frame inverts, margins included
    assert tuple(viewer.frame()[-1, 5]) == tuple(255 - c for c in s.palette[int(s.automaton.cells[5])])
    assert viewer.background() == tuple(255 - c for c in bg)


def test_draw_centers_the_grid_and_paints_the_margins(viewer):
    s = viewer.session
    s.tick(s.delay * 40)
    screen = pygame.Surface((170, 130))  # 10 spare points each way: 5-point margins
    viewer.draw(screen)
    bg = s.palette[0]
    assert screen.get_at((0, 0))[:3] == bg and screen.get_at((169, 129))[:3] == bg
    assert screen.get_at((2, 64))[:3] == bg and screen.get_at((84, 2))[:3] == bg  # margins
    # Inside the grid every 4x4 block is one history cell of the visible slice.
    row = s.history[s.visible_start + 1]  # scrolled by one full row at this speed
    for col in (0, 17, 39):
        assert screen.get_at((5 + col * 4 + 1, 5 + 1))[:3] == s.palette[int(row[col])]


def test_fit_resizes_the_session_to_the_window(viewer, capsys):
    viewer.fit(1203, 807)
    assert (viewer.session.cols, viewer.session.rows) == (300, 201)
    assert "resized 300x201" in capsys.readouterr().out
    viewer.fit(1203, 807)  # unchanged: nothing printed
    assert capsys.readouterr().out == ""
