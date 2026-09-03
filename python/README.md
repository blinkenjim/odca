# ODCA — Python reference implementation

See the repository root `README.md` for what ODCA is and how to use it,
`../REQTS.md` for the specification, and `../REQ-python.md` for
implementation notes.

All commands below run from this `python/` directory.

## Setup

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Run

```sh
.venv/bin/python -m odca
```

## Tests

```sh
.venv/bin/python -m pytest
```

This runs the unit and property tests plus the conformance runner
(`tests/test_conformance.py`), which checks the engine against the shared
golden vectors in `../conformance/vectors.json`.
