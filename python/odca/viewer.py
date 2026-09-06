"""pygame display layer: window, key translation, pacing, and rendering.

All behavior lives in session.py (the toolkit-free orchestration layer);
this module only opens the window, turns pygame key events into Session
keys, calls Session.tick at the refresh rate, and blits the visible slice
of Session.history through the two-bank palette (Session.palette8,
Session.row_banks), inverted during a flash. The window is resizable
(R-U2): the grid holds as many whole cells as fit, centered, with the
margins in the background color, and follows the window through
Session.resize (R-U8). See session.py for the controls and programs.
"""

import numpy as np
import pygame

from .session import Session

FPS = 60  # display refresh rate; generation rate is governed by Session.delay
MIN_COLS, MIN_ROWS = 40, 30  # the smallest grid: 160 x 120 points at cell 4 (R-U2)

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
    if unicode in ("S", "C", "N", "P", "X", "R", "[", "]"):  # shifted / review / pool keys
        return unicode
    if pygame.K_0 <= key <= pygame.K_9:
        return str(key - pygame.K_0)
    return _KEYS.get(key)


def grid_size(width, height, cell):
    """Whole cells that fit a window of the given size, at least the minimum (R-U2)."""
    return max(MIN_COLS, width // cell), max(MIN_ROWS, height // cell)


def grid_rect(width, height, cols, rows, cell):
    """(x, y, w, h) of the grid in a window: centered, the remainder split
    into margins (R-U2). A window below the minimum crops the grid."""
    w, h = cols * cell, rows * cell
    return (width - w) // 2, (height - h) // 2, w, h


class Viewer:
    def __init__(self, width=1200, height=800, cell_size=4, session=None):
        self.cell_size = cell_size
        self.width, self.height = width, height
        if session is None:
            session = Session(*grid_size(width, height, cell_size))
        self.session = session

    def background(self):
        """The margin color: state 0 of the active set, inverted during a flash."""
        bg = self.session.palette[0]
        return tuple(255 - c for c in bg) if self.session.inverted else tuple(bg)

    def frame(self):
        """The rows + 1 history rows the display shows, as an RGB array:
        filled rows from the top, background below until the buffer fills."""
        session = self.session
        palette8 = np.array(session.palette8, dtype=np.uint8)  # two banks of four (R-X5)
        start = session.visible_start
        shown = session.history[start:]
        banks = session.row_banks[start:]
        rgb = np.empty((session.rows + 1, session.cols, 3), dtype=np.uint8)
        rgb[:] = session.palette[0]
        rgb[:len(shown)] = palette8[banks[:, None].astype(np.int64) * 4 + shown]
        if session.inverted:  # R-U10: a brief inversion as a mode cue
            rgb = 255 - rgb
        return rgb

    def draw(self, screen):
        session = self.session
        cell = self.cell_size
        surf = pygame.surfarray.make_surface(self.frame().transpose(1, 0, 2))
        x, y, w, h = grid_rect(screen.get_width(), screen.get_height(),
                               session.cols, session.rows, cell)
        scaled = pygame.transform.scale(surf, (w, h + cell))
        screen.fill(self.background())
        # R-U3: the image is one row taller than the grid; scroll_offset says
        # how far into the top row the view is (continuous at slow speeds).
        # The grid rectangle clips the slide so it never paints the margins.
        screen.set_clip(pygame.Rect(x, y, w, h))
        screen.blit(scaled, (x, y - int(round(session.scroll_offset * cell))))
        screen.set_clip(None)

    def fit(self, width, height):
        """Follow the window: as many whole cells as fit (R-U8)."""
        self.width, self.height = width, height
        self.session.resize(*grid_size(width, height, self.cell_size))

    @staticmethod
    def is_full_screen(width, height):
        """Full screen, whether entered by pygame or by the platform's own
        control. SDL does not flag the latter (a macOS full screen Space), so
        a window as wide as a desktop and nearly as tall counts: on a notched
        display the Space stops short of the desktop height by the notch."""
        if pygame.display.is_fullscreen():
            return True
        return any(width >= dw and height >= 0.9 * dh for dw, dh in pygame.display.get_desktop_sizes())

    def run(self):
        session = self.session
        session.start_search()
        pygame.init()
        screen = pygame.display.set_mode((self.width, self.height), pygame.RESIZABLE)
        clock = pygame.time.Clock()
        title = None
        running = True
        while running:
            resized = False
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN:
                    key = map_key(event.key, event.unicode)
                    if key is not None:
                        running = session.handle_key(key)
                elif event.type in (pygame.VIDEORESIZE, pygame.WINDOWSIZECHANGED):
                    resized = True  # a drag, a full screen change, or a programmatic size
            dt = clock.tick(FPS) / 1000.0
            if resized:
                screen = pygame.display.get_surface()
                self.fit(screen.get_width(), screen.get_height())
                pygame.mouse.set_visible(not self.is_full_screen(self.width, self.height))  # R-U2
                dt = 0.0  # R-U8: frozen while resizing; time resumes now, no catch-up
            session.tick(dt)
            self.draw(screen)
            new_title = f"ODCA — rule {session.rule_id}"  # R-U6
            if new_title != title:
                pygame.display.set_caption(new_title)
                title = new_title
            pygame.display.flip()
        session.finish()  # odca-select writes its file; review saves (R-V5)
        session.stop_search()
        pygame.quit()
