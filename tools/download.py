#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# ///
import hashlib
import sys
import urllib.request
from pathlib import Path


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv):
    if len(argv) != 3:
        print("usage: download.py <url> <sha256> <target>", file=sys.stderr)
        return 2

    url, expected, target = argv[0], argv[1].lower(), Path(argv[2])
    tmp = target.with_suffix(target.suffix + ".tmp")
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        with urllib.request.urlopen(url) as response, tmp.open("wb") as fh:
            for chunk in iter(lambda: response.read(1024 * 1024), b""):
                fh.write(chunk)
        actual = sha256(tmp)
        if actual != expected:
            print(f"SHA256 mismatch for {target}: got {actual}", file=sys.stderr)
            return 1
        tmp.replace(target)
    finally:
        tmp.unlink(missing_ok=True)
    print(f"{target}: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
