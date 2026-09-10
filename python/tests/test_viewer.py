"""The pygame layer's geometry (R-U2, R-U3, R-U8), without a display.

The frame is checked as an array; the draw is checked by rendering to a
hidden window under SDL's dummy video driver and reading the pixels back,
which exercises the real renderer path (software renderer here, the GPU
in use). The window itself is manual (M-10).
"""

import os

import numpy as np
import pygame
import pytest
from pygame._sdl2.video import Renderer, Window

from odca.search import CandidateSearch
from odca.session import Session
from odca.store import Store
from odca.viewer import Viewer, grid_rect, grid_size


@pytest.fixture
def viewer(tmp_path):
    store = Store(state_dir=tmp_path / "state", library_file=tmp_path / "library.json",
                  candidates_file=tmp_path / "candidates.json")
    session = Session(40, 30, store=store, search=CandidateSearch(workers=0),
                      rng=np.random.default_rng(3))
    session.handle_key("a")  # no re-seeding during the test
    return Viewer(160, 120, 4, session=session)


@pytest.fixture
def renderer(viewer):
    """A software renderer on a hidden dummy-driver window, 163 x 123.

    Depends on `viewer` so this tears down first and can release the
    viewer's texture before the display quits: letting pytest free the
    texture afterwards segfaulted the run (order of SDL teardown).
    """
    os.environ["SDL_VIDEODRIVER"] = "dummy"
    pygame.display.init()
    window = Window("test", size=(163, 123), hidden=True)
    yield Renderer(window, accelerated=0)
    viewer._texture = None
    pygame.display.quit()


def test_grid_follows_the_window_in_whole_cells():
    assert grid_size(1200, 800, 4) == (300, 200)
    assert grid_size(1203, 807, 4) == (300, 201)  # the remainder becomes margins
    assert grid_size(10, 10, 4) == (40, 30)  # never below the minimum window, 160 x 120
    assert grid_size(10, 10, 2) == (80, 60)
    assert grid_size(1200, 800, 2) == (600, 400) and grid_size(1200, 800, 1) == (1200, 800)  # --2, --1
    assert grid_size(1200, 800, 3) == (400, 266) and grid_rect(1200, 800, 400, 266, 3) == (0, 1, 1200, 798)  # --3
    assert grid_rect(1201, 801, 1200, 800, 1) == (0, 0, 1200, 800)
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


def test_draw_centers_the_grid_and_paints_the_margins(viewer, renderer):
    s = viewer.session
    s.tick(s.delay * 40)
    viewer.fit(163, 123)  # 3 spare points each way: 1-point margins, the grid still 40 x 30
    assert (s.cols, s.rows) == (40, 30)
    viewer.draw(renderer)
    screen = renderer.to_surface()
    bg = s.palette[0]
    assert screen.get_at((0, 0))[:3] == bg and screen.get_at((162, 122))[:3] == bg
    assert screen.get_at((0, 64))[:3] == bg and screen.get_at((84, 0))[:3] == bg  # margins
    # Inside the grid every 4x4 block is one history cell of the visible slice.
    row = s.history[s.visible_start + 1]  # scrolled by one full row at this speed
    for col in (0, 17, 39):
        assert screen.get_at((1 + col * 4 + 1, 1 + 1))[:3] == s.palette[int(row[col])]
    # The grid changes size: the texture follows it.
    viewer.fit(163 + 8, 123)
    assert s.cols == 42
    viewer.draw(renderer)
    assert viewer._texture.width == 42


def test_fit_resizes_the_session_to_the_window(viewer, capsys):
    viewer.fit(1203, 807)
    assert (viewer.session.cols, viewer.session.rows) == (300, 201)
    assert "resized 300x201" in capsys.readouterr().out
    viewer.fit(1203, 807)  # unchanged: nothing printed
    assert capsys.readouterr().out == ""


def test_F_toggles_full_screen_by_window_size(viewer, monkeypatch):  # R-K18, R-U2
    monkeypatch.setattr(pygame.display, "get_desktop_sizes", lambda: [(1512, 982)])
    calls = []

    class FakeWindow:
        size = (1200, 800)

        def set_fullscreen(self, desktop=False):
            calls.append(("full", desktop))
            self.size = (1512, 945)  # a notched display's Space: shorter than the desktop

        def set_windowed(self):
            calls.append(("windowed",))
            self.size = (1200, 800)

    window = FakeWindow()
    viewer.toggle_full_screen(window)
    assert viewer.is_full_screen(*window.size)
    viewer.toggle_full_screen(window)  # and back, judged by the size, not by memory
    assert not viewer.is_full_screen(*window.size)
    assert calls == [("full", True), ("windowed",)]


def test_terminal_status_clears_the_counter_before_a_line():  # R-O17
    import io
    from odca.viewer import TerminalStatus
    out = io.StringIO()
    status = TerminalStatus(out)
    status.show("12/40")
    assert out.getvalue() == "\r\x1b[K12/40" and status.shown
    print("pair 2/3 B", file=status)  # an ordinary line clears the counter first
    assert out.getvalue() == "\r\x1b[K12/40\r\x1b[Kpair 2/3 B\n" and not status.shown
    status.show("13/40")
    status.show("14/40")  # redrawn in place, nothing cleared in between
    assert out.getvalue().endswith("\r\x1b[K13/40\r\x1b[K14/40")
    assert status.isatty() == out.isatty()  # everything else passes through


def test_fit_to_width_keeps_the_aspect():  # PT-44, R-X8
    from odca.viewer import fit_to_width, is_whole
    factor, rows = fit_to_width(1920, 1080, 600, 2)
    assert abs(factor - 1.6) < 1e-12 and rows == 337 and not is_whole(factor)  # 1080 / 3.2
    assert fit_to_width(1200, 800, 600, 2) == (1.0, 400) and is_whole(1.0)
    assert fit_to_width(600, 50, 600, 2) == (0.5, 50)  # scaled down
    assert fit_to_width(600, 0, 600, 2)[1] == 1  # one row at least


def test_render_counter_is_yellow_with_a_black_outline():  # R-U11
    from odca.viewer import COUNTER_OUTLINE_WIDTH, render_counter
    pygame.font.init()
    surface = render_counter("12/40", pygame.font.Font(None, 40))
    pixels = {tuple(surface.get_at((x, y)))[:3] for x in range(surface.get_width()) for y in range(surface.get_height())
              if surface.get_at((x, y))[3] > 0}
    assert (255, 255, 0) in pixels and (0, 0, 0) in pixels  # yellow glyphs and black around them
    plain = pygame.font.Font(None, 40).render("12/40", True, (255, 255, 0))
    assert surface.get_width() == plain.get_width() + 2 * COUNTER_OUTLINE_WIDTH  # room for the outline
    assert surface.get_height() == plain.get_height() + 2 * COUNTER_OUTLINE_WIDTH


def test_natural_size_follows_the_cell_and_the_fixed_width(viewer):  # R-U12
    session = viewer.session
    assert Viewer(1200, 800, 2, session=session).natural_size() == (1200, 800)
    assert Viewer(1200, 800, 3, session=session).natural_size() == (1200, 798)  # whole cells
    fixed = Viewer(1200, 800, 2, session=session, fixed_cols=540)
    assert fixed.natural_size() == (1080, 800) and fixed.is_natural(1080, 800) and not fixed.is_natural(1200, 800)
