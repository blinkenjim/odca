# The play script parser (REQTS R-X7): generated C from script/ (see
# script/regen), built into a shared library that odca/show.py loads
# through ctypes. Needs a C compiler and nothing else; pyproject.toml
# holds the rest of the metadata.
from setuptools import Extension, setup

setup(ext_modules=[Extension(
    "odca._show",
    sources=["odca/cshow/show.lex.c", "odca/cshow/show.tab.c"],
    include_dirs=["odca/cshow", "odca/cshow/include"],
)])
