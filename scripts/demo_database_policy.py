"""Snapshot the reviewed Demo reset opt-in without reading database credentials."""

import os
from pathlib import Path
import sys


def resolve_activation(value: str) -> bool:
    """Only an explicit true enables remote reset; an unset flag is disabled."""
    if value in {"", "false"}:
        return False
    if value == "true":
        return True
    raise ValueError("DEMO_DATABASE_RESET_ENABLED must be unset, 'false', or 'true'.")


def main() -> int:
    try:
        enabled = resolve_activation(os.environ.get("DEMO_DATABASE_RESET_ENABLED", ""))
        output = os.environ.get("GITHUB_OUTPUT", "")
        if not output:
            raise ValueError("GitHub Actions output file is required.")
        with Path(output).open("a", encoding="utf-8") as stream:
            stream.write(f"enabled={str(enabled).lower()}\n")
        summary = os.environ.get("GITHUB_STEP_SUMMARY", "")
        if summary:
            message = (
                "Enabled: the dedicated Demo reset must succeed before main publication. "
                "All target, credential, permission and isolation checks remain required."
                if enabled else
                "Disabled: this workflow will skip the remote Demo database reset. "
                "Existing database-independent publication may continue after all required "
                "checks and builds succeed. This does not verify or initialize a remote Demo."
            )
            with Path(summary).open("a", encoding="utf-8") as stream:
                stream.write(f"\n### Demo database reset\n\n{message}\n")
        return 0
    except ValueError as error:
        # These messages are fixed; never echo arbitrary variable values or paths.
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    except OSError:
        print("ERROR: Unable to write Demo database activation decision.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
