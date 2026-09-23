#!/usr/bin/env python3
"""Compile the real app model into an isolated save/build workflow check."""

from pathlib import Path
import argparse
import platform
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--real-tex", action="store_true", help="Also compile a temporary article using the installed TeX engine")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    sources = sorted(
        path
        for path in (root / "TEXnologia").rglob("*.swift")
        if path.name != "TEXnologiaApp.swift"
        and "TestSuites" not in path.parts
        and not path.name.endswith("Tests.swift")
    )
    architecture = "arm64" if platform.machine() == "arm64" else "x86_64"
    with tempfile.TemporaryDirectory(prefix="texnologia-compile-workflow-") as directory:
        executable = Path(directory) / "verify-compile-workflow"
        command = [
            "xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
            "-target", f"{architecture}-apple-macosx14.0",
            "-module-name", "TEXnologiaCompileWorkflow",
            *map(str, sources),
            str(root / "scripts" / "verify_compile_workflow.swift"),
            "-o", str(executable),
        ]
        subprocess.run(command, cwd=root, check=True, timeout=180)
        run_command = [str(executable)] + (["--real-tex"] if arguments.real_tex else [])
        subprocess.run(run_command, cwd=root, check=True, timeout=90)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print(f"Compile workflow verification failed with exit code {error.returncode}.", file=sys.stderr)
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("Compile workflow verification timed out.", file=sys.stderr)
        sys.exit(1)
