"""Alternate, less-enthusiastic CLI.

Same session, but the engine treats each answer with caution, forces a
minimum number of questions, demands higher confidence before stopping, and
favours real hand-curated dishes over procedurally-generated near-duplicates.

Run:  python3 cli_conservative.py
"""

from __future__ import annotations

import sys

from cli import main

if __name__ == "__main__":
    try:
        main(style="conservative", max_questions=14, min_questions=6)
    except (KeyboardInterrupt, EOFError):
        print("\nBye.")
        sys.exit(0)
