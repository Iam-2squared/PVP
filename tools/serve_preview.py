#!/usr/bin/env python3
"""Serve a Godot Web export with gzip, WebAssembly MIME and isolation headers."""

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from functools import partial
import gzip
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import re
import tempfile
import zlib


GZIP_SUFFIXES = {".wasm", ".pck", ".js"}
CHUNK_SIZE = 1024 * 1024
Q_VALUE = re.compile(r"(?:0(?:\.\d{0,3})?|1(?:\.0{0,3})?)\Z")


def _signature(stat):
    # ctime/inode also catch replacements and writes which preserve mtime/size.
    return (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)


def _digest(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _matching_gzip_digest(source, compressed):
    """Validate an existing sidecar once at startup, without trusting its date."""
    digest = hashlib.sha256()
    try:
        with source.open("rb") as original, gzip.open(compressed, "rb") as encoded:
            while True:
                chunk = original.read(CHUNK_SIZE)
                if encoded.read(CHUNK_SIZE) != chunk:
                    return None
                if not chunk:
                    return digest.hexdigest()
                digest.update(chunk)
    except (OSError, EOFError, zlib.error):
        return None


@dataclass(frozen=True)
class GzipAsset:
    source_signature: tuple
    compressed_signature: tuple
    source_digest: str
    compressed_digest: str

    def is_current(self, source, compressed):
        try:
            return (_signature(source.stat()) == self.source_signature
                    and _signature(compressed.stat()) == self.compressed_signature)
        except OSError:
            return False


def prepare_gzip_asset(source):
    """Atomically prepare a reproducible sidecar; an unwritable cache is optional."""
    source = Path(source)
    compressed = source.with_name(source.name + ".gz")
    temporary = None
    try:
        before = source.stat()
        source_digest = None
        validated_signature = None
        if compressed.is_file() and compressed.stat().st_mtime_ns >= before.st_mtime_ns:
            validated_signature = _signature(compressed.stat())
            source_digest = _matching_gzip_digest(source, compressed)
        if source_digest is None:
            digest = hashlib.sha256()
            with tempfile.NamedTemporaryFile(
                prefix="." + source.name + ".", suffix=".gz.tmp",
                dir=source.parent, delete=False,
            ) as target:
                temporary = Path(target.name)
                # Neither the source filename nor the current time enters gzip.
                with source.open("rb") as original, gzip.GzipFile(
                    filename="", mode="wb", fileobj=target, compresslevel=6, mtime=0,
                ) as encoded:
                    for chunk in iter(lambda: original.read(CHUNK_SIZE), b""):
                        digest.update(chunk)
                        encoded.write(chunk)
            if _signature(source.stat()) != _signature(before):
                return None
            os.chmod(temporary, before.st_mode & 0o777)
            os.utime(temporary, ns=(before.st_atime_ns, before.st_mtime_ns))
            os.replace(temporary, compressed)
            temporary = None
            source_digest = digest.hexdigest()
            validated_signature = None
        compressed_before = compressed.stat()
        if validated_signature is not None and _signature(compressed_before) != validated_signature:
            return None
        compressed_digest = _digest(compressed)
        if (_signature(source.stat()) != _signature(before)
                or _signature(compressed.stat()) != _signature(compressed_before)):
            return None
        return GzipAsset(
            _signature(before), _signature(compressed_before),
            source_digest, compressed_digest,
        )
    except OSError:
        # Export directories may be read-only. The unchanged original still works.
        return None
    finally:
        if temporary is not None:
            try:
                temporary.unlink()
            except OSError:
                pass


def prepare_gzip_assets(directory):
    assets = {}
    for source in sorted(Path(directory).rglob("*")):
        if source.is_file() and source.suffix.lower() in GZIP_SUFFIXES:
            asset = prepare_gzip_asset(source)
            if asset is not None:
                assets[source.resolve()] = asset
    return assets


def encoding_qualities(header):
    """Parse coding q-values; explicit exclusions override wildcard offers."""
    values = {}
    for item in (header or "").split(","):
        parts = item.strip().lower().split(";")
        coding = parts[0].strip()
        if not coding:
            continue
        quality = 1.0
        seen_q = False
        for parameter in parts[1:]:
            key, separator, value = parameter.strip().partition("=")
            if key.strip() != "q":
                continue
            value = value.strip()
            if seen_q or not separator or not Q_VALUE.fullmatch(value):
                quality = 0.0
                break
            seen_q = True
            quality = float(value)
        # Contradictory duplicate offers are handled conservatively.
        values[coding] = min(values.get(coding, quality), quality)
    return values


def choose_encoding(header, gzip_available):
    qualities = encoding_qualities(header)
    gzip_quality = qualities.get("gzip", qualities.get("*", 0.0))
    identity_quality = qualities.get("identity", 0.0 if qualities.get("*") == 0 else 1.0)
    # An explicitly preferred identity wins; otherwise offered gzip saves bytes.
    if (gzip_available and gzip_quality > 0
            and ("identity" not in qualities or gzip_quality >= identity_quality)):
        return "gzip"
    return "identity" if identity_quality > 0 else None


def _etag_matches(header, etag):
    return any(tag.strip() == "*" or tag.strip().removeprefix("W/") == etag.removeprefix("W/")
               for tag in header.split(","))


class PreviewHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
    }

    def __init__(self, *args, gzip_assets=None, **kwargs):
        self.gzip_assets = gzip_assets or {}
        self._vary_encoding = False
        super().__init__(*args, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        if self._vary_encoding:
            self.send_header("Vary", "Accept-Encoding")
        super().end_headers()

    def send_head(self):
        self._vary_encoding = False
        translated = self.translate_path(self.path)
        source = Path(translated)
        if source.is_dir() or translated.endswith(os.sep):
            return super().send_head()
        self._vary_encoding = source.suffix.lower() in GZIP_SUFFIXES
        compressed = source.with_name(source.name + ".gz")
        asset = self.gzip_assets.get(source.resolve())
        if asset is not None and not asset.is_current(source, compressed):
            asset = None
        encoding = choose_encoding(self.headers.get("Accept-Encoding"), asset is not None)
        if encoding is None:
            self.send_error(406, "No acceptable content encoding is available")
            return None
        selected = compressed if encoding == "gzip" else source
        stream = None
        try:
            if encoding == "gzip":
                try:
                    stream = selected.open("rb")
                    stat = os.fstat(stream.fileno())
                    source_stat = source.stat()
                    if (_signature(source_stat) != asset.source_signature
                            or _signature(stat) != asset.compressed_signature):
                        stream.close()
                        stream = None
                except OSError:
                    if stream is not None:
                        stream.close()
                        stream = None
            if stream is None:
                if encoding == "gzip":
                    asset = None
                encoding = choose_encoding(self.headers.get("Accept-Encoding"), False)
                if encoding is None:
                    self.send_error(406, "No acceptable content encoding is available")
                    return None
                stream = source.open("rb")
                stat = source_stat = os.fstat(stream.fileno())
            if asset is not None and _signature(source_stat) != asset.source_signature:
                asset = None
        except OSError:
            if stream is not None:
                stream.close()
            self.send_error(404, "File not found")
            return None
        try:
            if asset is not None:
                digest = asset.compressed_digest if encoding == "gzip" else asset.source_digest
                etag = '"sha256-' + digest + '-' + encoding + '"'
            else:
                etag = 'W/"%x-%x-%x-identity"' % (stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
            not_modified = False
            if "If-None-Match" in self.headers:
                not_modified = _etag_matches(self.headers["If-None-Match"], etag)
            elif "If-Modified-Since" in self.headers:
                try:
                    since = parsedate_to_datetime(self.headers["If-Modified-Since"])
                    if since.tzinfo is None:
                        since = since.replace(tzinfo=timezone.utc)
                    modified = datetime.fromtimestamp(source_stat.st_mtime, timezone.utc).replace(microsecond=0)
                    not_modified = modified <= since
                except (TypeError, ValueError, OverflowError):
                    pass
            self.send_response(304 if not_modified else 200)
            self.send_header("ETag", etag)
            self.send_header("Last-Modified", self.date_time_string(source_stat.st_mtime))
            if encoding == "gzip":
                self.send_header("Content-Encoding", "gzip")
            if not not_modified:
                self.send_header("Content-Type", self.guess_type(str(source)))
                self.send_header("Content-Length", str(stat.st_size))
            self.end_headers()
            if not_modified:
                stream.close()
                return None
            return stream
        except BaseException:
            stream.close()
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--directory", type=Path, default=Path("build/web"))
    parser.add_argument("--prepare-only", action="store_true", help="Prepare gzip sidecars without starting HTTP")
    args = parser.parse_args()
    directory = args.directory.resolve()
    if not (directory / "index.html").is_file():
        parser.error(f"No index.html in {directory}. Export the Web preset first.")
    assets = prepare_gzip_assets(directory)
    print(f"Prepared {len(assets)} gzip assets", flush=True)
    if args.prepare_only:
        return
    server = ThreadingHTTPServer(
        (args.bind, args.port), partial(PreviewHandler, directory=str(directory), gzip_assets=assets)
    )
    print(f"Kingdom preview: http://{args.bind}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
