#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# ///
import gzip
import hashlib
import io
import sys
import tarfile
from pathlib import Path


def site_tar(files):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for path in files:
            data = path.read_bytes()
            info = tarfile.TarInfo(f"./{path.name}")
            info.size = len(data)
            info.mode = path.stat().st_mode & 0o777
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "wheel"
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def main(argv):
    if len(argv) < 2:
        print("usage: mksite.py <out.tgz> <file> ...", file=sys.stderr)
        return 2

    out = Path(argv[0])
    files = [Path(item) for item in argv[1:]]
    gz = gzip.compress(site_tar(files), mtime=0)
    out.write_bytes(gz)
    (out.parent / "SHA256").write_text(f"SHA256 ({out.name}) = {hashlib.sha256(gz).hexdigest()}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
