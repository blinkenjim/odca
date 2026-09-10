"""pygame display layer: window, key translation, pacing, and rendering.

All behavior lives in session.py (the toolkit-free orchestration layer);
this module only opens the window, turns pygame key events into Session
keys, calls Session.tick once per refresh, and shows the visible slice of
Session.history through the per-row palette table (Session.palette_table,
Session.row_palettes), inverted during a flash. Drawing goes through SDL's
renderer (pygame._sdl2.video): the frame is one small texture, one texel
per cell, that the GPU scales to the grid and presents in step with the
display's refresh (R-U5). The window is resizable (R-U2): the grid holds as
many whole cells as fit, centered, with the margins in the background
color, and follows the window through Session.resize (R-U8). See
session.py for the controls and programs.
"""

import os
import sys

import numpy as np

os.environ.setdefault("SDL_RENDER_SCALE_QUALITY", "0")  # nearest: crisp cells, no smoothing
import pygame  # noqa: E402
from pygame._sdl2.video import Renderer, Texture, Window  # noqa: E402

from .session import Session  # noqa: E402

FPS = 60  # refresh cap when the display cannot pace us (no vsync)
COUNTER_INTERVAL = 0.2  # the generation counter on the terminal refreshes five times a second (R-O17)
VSYNC_FPS_CAP = 240  # with vsync the display paces; this only bounds a runaway loop
MIN_WINDOW = (160, 120)  # the smallest window in pixels, whatever the cell size (R-U2)

_KEYS = {
    pygame.K_q: "q",
    pygame.K_a: "a",
    pygame.K_c: "c",
    pygame.K_r: "r",
    pygame.K_m: "m",
    pygame.K_u: "u",
    pygame.K_s: "s",
    pygame.K_i: "i",
    pygame.K_n: "n",
    pygame.K_p: "p",
    pygame.K_PLUS: "+",
    pygame.K_EQUALS: "+",  # unshifted '+' on US layouts (R-K8)
    pygame.K_KP_PLUS: "+",
    pygame.K_MINUS: "-",
    pygame.K_KP_MINUS: "-",
    pygame.K_SPACE: " ",
    pygame.K_RETURN: "\n",
    pygame.K_KP_ENTER: "\n",
}


def map_key(key, unicode=""):
    """Translate a pygame key code (plus typed character) to a Session key."""
    if unicode in ("S", "C", "N", "P", "X", "R", "U", "[", "]"):  # shifted / review / pool keys
        return unicode
    if pygame.K_0 <= key <= pygame.K_9:
        return str(key - pygame.K_0)
    return _KEYS.get(key)


class TerminalStatus:
    """Standard output with one line redrawn in place (R-O17): the --longest
    generation counter on a terminal. Installed as sys.stdout for the run,
    it clears that line before any ordinary write, so the session's status
    lines never collide with it."""

    def __init__(self, stream):
        self.stream = stream
        self.shown = False

    def show(self, text):
        """Draw the in-place line: carriage return, erase to the end, the text, no newline."""
        self.stream.write("\r\x1b[K" + text)
        self.stream.flush()
        self.shown = True

    def write(self, text):
        if self.shown:
            self.stream.write("\r\x1b[K")
            self.shown = False
        return self.stream.write(text)

    def flush(self):
        self.stream.flush()

    def __getattr__(self, name):
        return getattr(self.stream, name)


def fit_to_width(width, height, cols, cell):
    """--longest (R-X8): the grid stretched to the window's width with its
    aspect kept: (factor, rows), the on-screen cell being cell * factor
    pixels and rows how many such rows fit the height (at least one)."""
    factor = width / (cols * cell)
    return factor, max(1, int(height / (cell * factor)))


def is_whole(factor):
    """A whole-number factor keeps every cell the same size under nearest
    scaling; otherwise linear filtering avoids uneven cells (R-X8)."""
    return abs(factor - round(factor)) < 1e-9


def grid_size(width, height, cell):
    """Whole cells that fit a window of the given size, at least the minimum window's (R-U2)."""
    return max(MIN_WINDOW[0] // cell, width // cell), max(MIN_WINDOW[1] // cell, height // cell)


def grid_rect(width, height, cols, rows, cell):
    """(x, y, w, h) of the grid in a window: centered, the remainder split
    into margins (R-U2). A window below the minimum crops the grid."""
    w, h = cols * cell, rows * cell
    return (width - w) // 2, (height - h) // 2, w, h


class Viewer:
    def __init__(self, width=1200, height=800, cell_size=2, session=None, fullscreen=False, fixed_cols=None):
        self.cell_size = cell_size
        self.width, self.height = width, height
        self.fullscreen = fullscreen  # open full screen at launch (--fullscreen, R-U2)
        self.fixed_cols = fixed_cols  # --longest (R-X8): the grid is this wide whatever the window
        self.factor = 1.0  # R-X8: the grid's scale, the window's width over the grid's natural width
        self._smooth = False  # the texture's filter: linear for a fractional factor
        if session is None:
            session = Session(*grid_size(width, height, cell_size))
        self.session = session
        self._texture = None  # one texel per cell, rows + 1 tall; remade when the grid changes

    def background(self):
        """The margin color: state 0 of the active set, inverted during a
        flash; black under --longest (R-X8), where the margins are bars."""
        if self.fixed_cols is not None:
            return (0, 0, 0)
        bg = self.session.palette[0]
        return tuple(255 - c for c in bg) if self.session.inverted else tuple(bg)

    def frame(self):
        """The rows + 1 history rows the display shows, as an RGB array:
        filled rows from the top, background below until the buffer fills."""
        session = self.session
        table = np.array(session.palette_table, dtype=np.uint8)  # (palette, state) -> RGB (R-X5)
        start = session.visible_start
        shown = session.history[start:]
        palettes = session.row_palettes[start:]
        rgb = np.empty((session.rows + 1, session.cols, 3), dtype=np.uint8)
        rgb[:] = session.palette[0]
        rgb[:len(shown)] = table[palettes[:, None].astype(np.int64) * 4 + shown]
        if session.inverted:  # R-U10: a brief inversion as a mode cue
            rgb = 255 - rgb
        return rgb

    def draw(self, renderer):
        """Compose one frame on the renderer (present() is the caller's)."""
        session = self.session
        cell = self.cell_size * self.factor  # R-X8: the on-screen cell, scaled under --longest
        size = (session.cols, session.rows + 1)
        smooth = self.fixed_cols is not None and not is_whole(self.factor)
        if self._texture is None or (self._texture.width, self._texture.height) != size or smooth != self._smooth:
            # SDL reads the scale-quality hint when the texture is made: nearest
            # for a whole-number factor, linear for a fractional one (R-X8).
            os.environ["SDL_RENDER_SCALE_QUALITY"] = "1" if smooth else "0"
            self._texture = Texture(renderer, size, streaming=True)
            self._smooth = smooth
        self._texture.update(pygame.surfarray.make_surface(self.frame().transpose(1, 0, 2)))
        if self.fixed_cols is None:
            x, y, w, h = grid_rect(self.width, self.height, session.cols, session.rows, self.cell_size)
        else:  # R-X8: the grid spans the width; the rows are centered in the height
            w, h = self.width, int(round(session.rows * cell))
            x, y = 0, (self.height - h) // 2
        renderer.draw_color = self.background() + (255,)
        renderer.clear()
        # R-U3: the texture is one row taller than the grid; scroll_offset says
        # how far into the top row the view is (continuous at slow speeds).
        # The viewport is the grid rectangle, so the slide never paints the margins.
        renderer.set_viewport(pygame.Rect(x, y, w, h))
        self._texture.draw(dstrect=pygame.Rect(0, -int(round(session.scroll_offset * cell)), w, int(round(h + cell))))
        renderer.set_viewport(None)

    def toggle_full_screen(self, window):
        """`F` (R-K18): leave full screen if in it, by either route, else enter
        it at the desktop's size; the size change that follows refits the grid."""
        if self.is_full_screen(*window.size):
            window.set_windowed()
        else:
            window.set_fullscreen(desktop=True)

    def fit(self, width, height):
        """Follow the window: as many whole cells as fit (R-U8); under
        --longest the grid is stretched to the width, aspect kept, and the
        rows are counted in scaled cells (R-X8)."""
        self.width, self.height = width, height
        if self.fixed_cols is None:
            self.session.resize(*grid_size(width, height, self.cell_size))
        else:
            self.factor, rows = fit_to_width(width, height, self.fixed_cols, self.cell_size)
            self.session.resize(self.fixed_cols, rows)

    @staticmethod
    def is_full_screen(width, height):
        """Full screen is the platform's own control, which SDL does not flag
        (a macOS full screen Space), so a window as wide as a desktop and
        nearly as tall counts: on a notched display the Space stops short of
        the desktop height by the notch."""
        return any(width >= dw and height >= 0.9 * dh for dw, dh in pygame.display.get_desktop_sizes())

    def run(self):
        session = self.session
        session.start_search()
        pygame.init()
        window = Window("ODCA", size=(self.width, self.height), resizable=True,
                        fullscreen_desktop=self.fullscreen)  # the desktop's size, no mode change
        try:
            renderer, cap = Renderer(window, vsync=True), VSYNC_FPS_CAP  # the display paces (R-U5)
        except pygame.error:
            renderer, cap = Renderer(window), FPS  # no vsync here: a timer paces
        self.fit(*window.size)  # a full screen window is already not the default size
        pygame.mouse.set_visible(not self.is_full_screen(*window.size))  # R-U2
        clock = pygame.time.Clock()
        title = None
        since_counter = float("inf")
        # R-O17: the counter is drawn in place on a terminal only; the wrapper
        # clears it before any line the session prints.
        status = TerminalStatus(sys.stdout) if session.longest and sys.stdout.isatty() else None
        if status is not None:
            sys.stdout = status
        running = True
        while running:
            resized = False
            for event in pygame.event.get():
                if event.type in (pygame.QUIT, pygame.WINDOWCLOSE):
                    running = False
                elif event.type == pygame.KEYDOWN:
                    if event.unicode == "F":  # R-K18 (shift-f): a window key, live in every mode and while paused
                        self.toggle_full_screen(window)
                        continue
                    key = map_key(event.key, event.unicode)
                    if key is not None:
                        running = session.handle_key(key)
                elif event.type in (pygame.VIDEORESIZE, pygame.WINDOWSIZECHANGED):
                    resized = True  # a drag, a full screen change, or a programmatic size
            dt = clock.tick(cap) / 1000.0
            if resized:
                self.fit(*window.size)
                pygame.mouse.set_visible(not self.is_full_screen(*window.size))  # R-U2
                dt = 0.0  # R-U8: frozen while resizing; time resumes now, no catch-up
            session.tick(dt)
            self.draw(renderer)
            new_title = session.title  # R-U6
            if new_title != title:
                window.title = new_title
                title = new_title
            since_counter += dt
            if since_counter >= COUNTER_INTERVAL and status is not None and session.counter is not None:
                since_counter = 0.0
                status.show(session.counter)  # R-O17: five times a second
            renderer.present()  # blocks until the refresh when vsync is on
        if status is not None:
            print("", end="")  # clears the counter line (a write) before the prompt returns
            sys.stdout = status.stream
        session.finish()  # odca-select writes its file; review saves (R-V5)
        session.stop_search()
        pygame.quit()
