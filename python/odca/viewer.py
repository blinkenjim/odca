"""pygame display layer: window, key translation, pacing, and rendering.

All behavior lives in session.py (the toolkit-free orchestration layer);
this module only opens the window, turns pygame key events into Session
keys, calls Session.tick at the refresh rate, and blits Session.history
through the active color set. See session.py for the controls.
"""

import numpy as np
import pygame

from .session import Session

# Color sets bound to the number keys (R-U4); each maps states 0-3 to RGB,
# state 0 the background. CoCo colors follow the usual MC6847 VDG
# approximations; slots 3-9 come from colorsets/candidates.json.
COLOR_SETS = [
    np.array(  # 0: CoCo color set 0
        [(0x07, 0xFF, 0x00), (0xFF, 0xFF, 0x00), (0x3B, 0x08, 0xFF), (0xCC, 0x00, 0x3B)],
        dtype=np.uint8,
    ),
    np.array(  # 1: CoCo color set 1
        [(0xFF, 0xFF, 0xFF), (0x07, 0xE3, 0x99), (0xFF, 0x1C, 0xFF), (0xFF, 0x81, 0x00)],
        dtype=np.uint8,
    ),
    np.array(  # 2: default
        [(18, 18, 24), (235, 235, 225), (255, 161, 54), (64, 156, 255)],
        dtype=np.uint8,
    ),
    np.array(  # 3: Meadow Sunflower Glow (coolors.co)
        [(0xD6, 0xE0, 0xA2), (0xF6, 0xF4, 0xD5), (0xCF, 0xDE, 0xC0), (0xE5, 0xA0, 0x7F)],
        dtype=np.uint8,
    ),
    np.array(  # 4: Candy Floss Dreams (coolors.co)
        [(0xF2, 0xAA, 0xA1), (0xF9, 0xF3, 0xDF), (0xC4, 0xF0, 0xE6), (0xB7, 0xD8, 0xDF)],
        dtype=np.uint8,
    ),
    np.array(  # 5: Fiery Ice Cream Delight (coolors.co)
        [(0x10, 0x2F, 0x47), (0xC5, 0x3A, 0x32), (0xE7, 0x85, 0x31), (0xF3, 0xC1, 0x5F)],
        dtype=np.uint8,
    ),
    np.array(  # 6: Golden Autumn Twilight (coolors.co)
        [(0x4D, 0x9C, 0xB9), (0x11, 0x2F, 0x45), (0xF4, 0xBA, 0x41), (0xEC, 0x8B, 0x33)],
        dtype=np.uint8,
    ),
    np.array(  # 7: Midnight Sun Dance (coolors.co)
        [(0x04, 0x15, 0x23), (0x2E, 0x60, 0x6B), (0xFC, 0xED, 0xD4), (0xEE, 0x84, 0x32)],
        dtype=np.uint8,
    ),
    np.array(  # 8: Seaside Serenity (coolors.co)
        [(0xE8, 0xEC, 0xEF), (0x30, 0x4B, 0x74), (0x6C, 0x95, 0xB7), (0xAC, 0xCD, 0xEE)],
        dtype=np.uint8,
    ),
    np.array(  # 9: Cherry Blossom Sky (coolors.co)
        [(0x2B, 0x2D, 0x40), (0x8F, 0x99, 0xAC), (0xEE, 0xF2, 0xF4), (0xDC, 0x3C, 0x44)],
        dtype=np.uint8,
    ),
]

FPS = 60  # display refresh rate; generation rate is governed by Session.delay

_KEYS = {
    pygame.K_q: "q",
    pygame.K_a: "a",
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


def map_key(key):
    """Translate a pygame key code to a Session key, or None if unbound."""
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
        palette = COLOR_SETS[self.session.color_set]
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
                    key = map_key(event.key)
                    if key is not None:
                        running = session.handle_key(key)
            session.tick(clock.tick(FPS) / 1000.0)
            self.draw(screen)
            pygame.display.set_caption(f"ODCA — rule {session.rule_id}")  # R-U6
            pygame.display.flip()
        session.stop_search()
        pygame.quit()
