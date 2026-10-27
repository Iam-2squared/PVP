#!/usr/bin/env python3
"""Install only Godot's small, single-threaded Web export templates.

Uses the official godot-builds release and HTTP byte ranges instead of fetching
the complete, multi-platform export archive. No third-party Python packages.
"""

import argparse
import io
import json
from pathlib import Path
import urllib.request
import zipfile


class RemoteZip(io.RawIOBase):
    def __init__(self, url: str, size: int):
        self.url = url
        self.size = size
        self.position = 0
        self.cache = {}
        self.transferred = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = (
            offset if whence == 0 else
            self.position + offset if whence == 1 else
            self.size + offset
        )
        return self.position

    def read(self, size=-1):
        if size < 0:
            size = self.size - self.position
        start = self.position
        end = min(self.size, start + size)
        self.position = end
        if start == end:
            return b""
        for (cached_start, cached_end), data in self.cache.items():
            if cached_start <= start and cached_end >= end:
                return data[start - cached_start:end - cached_start]
        request = urllib.request.Request(
            self.url, headers={"Range": f"bytes={start}-{end - 1}"}
        )
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status != 206:
                raise RuntimeError("Download server does not support byte ranges")
            data = response.read()
        if len(data) != end - start:
            raise RuntimeError("Incomplete byte-range download")
        self.transferred += len(data)
        if len(data) < 1_000_000:
            self.cache[(start, end)] = data
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="4.6.3")
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    version = args.version
    api = (
        "https://api.github.com/repos/godotengine/godot-builds/releases/tags/"
        f"{version}-stable"
    )
    with urllib.request.urlopen(api, timeout=30) as response:
        release = json.load(response)
    archive_name = f"Godot_v{version}-stable_export_templates.tpz"
    asset = next(item for item in release["assets"] if item["name"] == archive_name)
    destination = args.destination or (
        Path.home() / ".local/share/godot/export_templates" / f"{version}.stable"
    )
    destination.mkdir(parents=True, exist_ok=True)
    remote = RemoteZip(asset["browser_download_url"], asset["size"])
    with zipfile.ZipFile(remote) as archive:
        for filename in ("web_nothreads_release.zip", "web_nothreads_debug.zip"):
            output = destination / filename
            data = archive.read(f"templates/{filename}")
            # Check that the selected export template is itself a complete ZIP.
            with zipfile.ZipFile(io.BytesIO(data)) as template:
                if template.testzip() is not None:
                    raise RuntimeError(f"Invalid template: {filename}")
            output.write_bytes(data)
            print(f"Installed {filename} ({len(data):,} bytes)")
    print(f"Downloaded {remote.transferred:,} bytes from the official archive.")
    print(f"Templates: {destination}")


if __name__ == "__main__":
    main()
