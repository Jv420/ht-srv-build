#!/usr/bin/env python3
from pathlib import Path
import base64
import json
import lzma

root = Path(__file__).resolve().parents[1]
payload_dir = root / "tools" / "payload"
payload = "".join(path.read_text(encoding="ascii").strip() for path in sorted(payload_dir.glob("chunk-*.txt")))
data = json.loads(lzma.decompress(base64.b64decode(payload)).decode("utf-8"))

for relative_path, content in data.items():
    target = (root / relative_path).resolve()
    if root not in target.parents and target != root:
        raise RuntimeError(f"Onveilig pad geweigerd: {relative_path}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8", newline="\n")

print(f"{len(data)} losse HexTactics-bestanden aangemaakt.")
