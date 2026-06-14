#!/usr/bin/env bash
#
# Prints a usable iOS Simulator UDID for xcodebuild destinations.
# Prefers a booted iPhone; otherwise the iPhone on the newest installed
# runtime. Keeps the Makefile destination stable without hard-coding a UDID
# that differs machine to machine.
#
set -euo pipefail

python3 - <<'PY'
import json, re, subprocess

out = subprocess.run(
    ["xcrun", "simctl", "list", "devices", "available", "--json"],
    capture_output=True, text=True,
).stdout
devices = json.loads(out)["devices"]

def runtime_rank(identifier: str):
    m = re.search(r"iOS-(\d+)-(\d+)", identifier)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)

candidates = []
for runtime, devs in devices.items():
    if "iOS" not in runtime:
        continue
    for d in devs:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            booted = d.get("state") == "Booted"
            candidates.append((booted, runtime_rank(runtime), d["udid"]))

# Booted first, then newest runtime.
candidates.sort(key=lambda c: (c[0], c[1]), reverse=True)
print(candidates[0][2] if candidates else "")
PY
