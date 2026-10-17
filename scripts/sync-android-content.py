#!/usr/bin/env python3
"""Export the Swift drink catalog and calculation reference cases for Android."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check exports without changing files")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    sources = [
        "Shared/Utilities/DateHelpers.swift",
        "Shared/Utilities/CaffeineFormat.swift",
        "Shared/Utilities/CaffeineClearance.swift",
        "Shared/Utilities/CaffeineInsights.swift",
        "Shared/Utilities/DrinkPresets.swift",
        "scripts/export-android-content.swift",
    ]
    destination = repo / "android/app/src/main/resources"
    with tempfile.TemporaryDirectory(prefix="caffeine-content-") as temporary:
        work = Path(temporary)
        identity = re.search(
            r'^let caffeineOwnSourceBundleID = "[^"]+"$',
            (repo / "Shared/Services/DataService.swift").read_text(),
            re.MULTILINE,
        )
        if identity is None:
            raise SystemExit("Missing canonical source identity")
        stub = work / "SourceIdentity.swift"
        stub.write_text(identity.group() + "\n")
        executable = work / "export"
        print("Compiling the Swift calculation and catalog exporter", flush=True)
        subprocess.run(["swiftc", "-whole-module-optimization", *(str(repo / path) for path in sources), str(stub), "-o", str(executable)], check=True)
        generated = work / "resources"
        subprocess.run([str(executable), str(generated)], check=True)
        hashes = {path: hashlib.sha256((repo / path).read_bytes()).hexdigest() for path in [*sources, "Shared/Services/DataService.swift"]}
        (generated / "swift-content-manifest.json").write_text(json.dumps({"schema": 1, "sources": hashes}, indent=2, sort_keys=True) + "\n")
        for source in sorted(generated.iterdir()):
            target = destination / source.name
            if args.check:
                if not target.exists() or source.read_bytes() != target.read_bytes():
                    raise SystemExit(f"Outdated export: {target.relative_to(repo)}")
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read_bytes())
        print("Swift Android exports match" if args.check else "Swift Android exports updated")


if __name__ == "__main__":
    main()
