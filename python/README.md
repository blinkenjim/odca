# ODCA — Python reference implementation

See the repository root `README.md` for what ODCA is and how to use it,
`../REQTS.md` for the specification, and `../REQ-python.md` for
implementation notes.

All commands below run from this `python/` directory.

## Setup

```sh
python3 -m venv .venv
.venv/bin/pip install --upgrade pip setuptools
.venv/bin/pip install -e '.[test]'
```

The editable install puts both programs on the venv's path. (The pip that
ships with a stock macOS Python is too old for the editable install of a
`pyproject.toml` project, hence the upgrade first.)

## Run

```sh
.venv/bin/odca ../interesting.odca            # play a file of looks (--shuffle, --fullscreen optional)
.venv/bin/odca-select ../my-looks.odca        # compose looks into a file
```

`--help` on either prints its flags and keys. `python -m odca` is the
player, `python -m odca.select` the workbench, for running without the
install.

The window is resizable; full screen is the platform's own control (the
green button on macOS). The picture stays centered while cells appear or
vanish at the edges, a taller window uncovers older rows, and the pointer
hides in full screen. Drawing goes through SDL's renderer, so the GPU
scales the picture and paces it to the display's refresh where it can.

## Tests

```sh
.venv/bin/python -m pytest
```

This runs the unit and property tests plus the conformance runner
(`tests/test_conformance.py`), which checks the engine against the shared
golden vectors in `../conformance/vectors.json`.
