"""Command-line entry point: python -m odca"""

from .viewer import Viewer


def main():
    Viewer().run()


if __name__ == "__main__":
    main()
