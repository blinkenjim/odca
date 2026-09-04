"""pygame display layer: window, key translation, pacing, and rendering.

All behavior lives in session.py (the toolkit-free orchestration layer);
this module only opens the window, turns pygame key events into Session
keys, calls Session.tick at the refresh rate, and blits Session.history
through the active color set (Session.palette). See session.py for the controls.
"""

import numpy as np
import pygame

from .session import Session

FPS = 60  # display refresh rate; generation rate is governed by Session.delay

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
    if unicode == "S":  # shift-s: save color set (R-K16)
        return "S"
    if pygame.K_0 <= key <= pygame.K_9:
        return str(key - pygame.K_0)
    return _KEYS.get(key)


class Viewer:
    def __init__(self, width=1200, height=800, cell_size=4, session=None):
        self.cell_size = cell_size
        if session is None:
            session = Session(width // cell_size, height // cell_size)
        self.session = session

    def draw(self, screen):
        palette = np.array(self.session.palette, dtype=np.uint8)
        rgb = palette[self.session.history]  # (rows, cols, 3)
        surf = pygame.surfarray.make_surface(rgb.transpose(1, 0, 2))
        pygame.transform.scale(surf, screen.get_size(), screen)

    def run(self):
        session = self.session
        session.start_search()
        pygame.init()
        screen = pygame.display.set_mode(
            (session.cols * self.cell_size, session.rows * self.cell_size)
        )
        clock = pygame.time.Clock()
        running = True
        while running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN:
                    key = map_key(event.key, event.unicode)
                    if key is not None:
                        running = session.handle_key(key)
            session.tick(clock.tick(FPS) / 1000.0)
            self.draw(screen)
            pygame.display.set_caption(f"ODCA — rule {session.rule_id}")  # R-U6
            pygame.display.flip()
        session.stop_search()
        pygame.quit()
