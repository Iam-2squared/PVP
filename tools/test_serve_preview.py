#!/usr/bin/env python3
"""Verify real gzip HTTP responses using only small temporary export fixtures."""

from functools import partial
import gzip
import hashlib
import http.client
from http.server import ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from threading import Thread
import time
import unittest
from unittest.mock import patch

import serve_preview


class QuietHandler(serve_preview.PreviewHandler):
    def log_message(self, *args):
        pass


class PreviewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pvp-gzip-test-")
        self.directory = Path(self.temporary.name)
        (self.directory / "index.html").write_text("<!doctype html><title>fixture</title>")
        self.contents = {
            "index.wasm": b"\x00asm\x01\x00\x00\x00" + bytes(range(256)) * 256,
            "index.pck": b"GDPC" + b"unchanged voxel world\x00\xff" * 2048,
            "index.js": b"const original = 'all graphics stay the same';\n" * 1024,
        }
        for name, data in self.contents.items():
            (self.directory / name).write_bytes(data)
        self.assets = serve_preview.prepare_gzip_assets(self.directory)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), partial(
            QuietHandler, directory=str(self.directory), gzip_assets=self.assets))
        self.thread = Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temporary.cleanup()

    def request(self, name="index.pck", *, encoding="gzip", headers=None, method="GET"):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=5)
        try:
            connection.putrequest(method, "/" + name, skip_accept_encoding=True)
            if encoding is not None:
                connection.putheader("Accept-Encoding", encoding)
            for key, value in (headers or {}).items():
                connection.putheader(key, value)
            connection.endheaders()
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def assert_isolated(self, headers):
        self.assertEqual(headers["Cross-Origin-Opener-Policy"], "same-origin")
        self.assertEqual(headers["Cross-Origin-Embedder-Policy"], "require-corp")
        self.assertEqual(headers["Vary"], "Accept-Encoding")

    def test_get_head_mime_and_exact_original_bytes(self):
        for name, original in self.contents.items():
            with self.subTest(name=name):
                status, headers, body = self.request(name)
                self.assertEqual(status, 200)
                self.assertEqual(headers["Content-Encoding"], "gzip")
                self.assert_isolated(headers)
                self.assertEqual(int(headers["Content-Length"]), len(body))
                self.assertLess(len(body), len(original))
                self.assertEqual(gzip.decompress(body), original)
                self.assertEqual(hashlib.sha256(gzip.decompress(body)).digest(), hashlib.sha256(original).digest())
                expected_mime = QuietHandler.extensions_map.get(Path(name).suffix)
                if expected_mime:
                    self.assertEqual(headers["Content-Type"], expected_mime)
                else:
                    self.assertIn("javascript", headers["Content-Type"])
                head_status, head_headers, head_body = self.request(name, method="HEAD")
                self.assertEqual(head_status, 200)
                self.assertEqual(head_body, b"")
                for key in ("Content-Length", "Content-Type", "Content-Encoding", "ETag", "Last-Modified"):
                    self.assertEqual(head_headers[key], headers[key])
                self.assert_isolated(head_headers)

    def test_accept_encoding_q_values_over_http(self):
        cases = [
            (None, False), ("", False), ("identity", False), ("br, deflate", False),
            ("gzip", True), ("GZip; Q=1", True), ("gzip;q=0.4", True),
            ("*;q=0.5", True), ("gzip;q=0", False),
            ("gzip;q=0, *;q=1", False), ("gzip;q=0.4, identity;q=1", False),
            ("gzip;q=1, identity;q=0", True), ("gzip;q=0.2, identity;q=0.1", True),
            ("gzip;q=0.000", False), ("gzip;q=2", False),
            ("gzip;q=invalid", False), ("gzip;q=0.1234", False),
            ("gzip;q=0, gzip;q=1", False),
        ]
        for offer, encoded in cases:
            with self.subTest(offer=offer):
                status, headers, body = self.request(encoding=offer)
                self.assertEqual(status, 200)
                self.assertEqual(headers.get("Content-Encoding") == "gzip", encoded)
                self.assertEqual(gzip.decompress(body) if encoded else body, self.contents["index.pck"])
                self.assert_isolated(headers)
        status, _, _ = self.request(encoding="gzip;q=0, identity;q=0")
        self.assertEqual(status, 406)

    def test_conditional_get_and_head_and_representation_etags(self):
        _, original, _ = self.request()
        for conditional in (
            {"If-None-Match": original["ETag"]},
            {"If-None-Match": "W/" + original["ETag"]},
            {"If-None-Match": '"other", ' + original["ETag"]},
            {"If-None-Match": "*"},
            {"If-Modified-Since": original["Last-Modified"]},
        ):
            with self.subTest(conditional=conditional):
                status, headers, body = self.request(headers=conditional)
                self.assertEqual(status, 304)
                self.assertEqual(body, b"")
                self.assertEqual(headers["ETag"], original["ETag"])
                self.assertEqual(headers["Content-Encoding"], "gzip")
                self.assert_isolated(headers)
        status, _, body = self.request(method="HEAD", headers={"If-None-Match": original["ETag"]})
        self.assertEqual((status, body), (304, b""))
        status, _, _ = self.request(headers={"If-None-Match": '"different"', "If-Modified-Since": original["Last-Modified"]})
        self.assertEqual(status, 200)  # If-None-Match takes precedence.
        status, raw, body = self.request(encoding="identity", headers={"If-None-Match": original["ETag"]})
        self.assertEqual(status, 200)
        self.assertEqual(body, self.contents["index.pck"])
        self.assertNotEqual(raw["ETag"], original["ETag"])
        status, headers, body = self.request(encoding="identity", headers={"If-None-Match": raw["ETag"]})
        self.assertEqual((status, body), (304, b""))
        self.assertNotIn("Content-Encoding", headers)

    def test_changed_source_or_gzip_never_uses_old_sidecar(self):
        _, old_headers, _ = self.request()
        source = self.directory / "index.pck"
        old_stat = source.stat()
        changed = self.contents["index.pck"][:-1] + b"!"
        source.write_bytes(changed)
        os.utime(source, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))
        status, headers, body = self.request(headers={"If-None-Match": old_headers["ETag"]})
        self.assertEqual((status, body), (200, changed))
        self.assertNotIn("Content-Encoding", headers)
        self.assertEqual(int(headers["Content-Length"]), len(changed))
        status, headers, body = self.request(method="HEAD")
        self.assertEqual((status, body), (200, b""))
        self.assertEqual(int(headers["Content-Length"]), len(changed))
        compressed = self.directory / "index.wasm.gz"
        compressed.write_bytes(gzip.compress(b"incorrect cached data", mtime=0))
        status, headers, body = self.request("index.wasm")
        self.assertEqual((status, body), (200, self.contents["index.wasm"]))
        self.assertNotIn("Content-Encoding", headers)
        # Simulate a cache disappearing just after the per-request stat check.
        (self.directory / "index.js.gz").unlink()
        with patch.object(serve_preview.GzipAsset, "is_current", return_value=True):
            status, headers, body = self.request("index.js")
        self.assertEqual((status, body), (200, self.contents["index.js"]))
        self.assertNotIn("Content-Encoding", headers)

    def test_preparation_is_reproducible_and_rejects_stale_or_corrupt_gzip(self):
        source = self.directory / "index.pck"
        compressed = self.directory / "index.pck.gz"
        first = compressed.read_bytes()
        self.assertEqual(first[4:8], b"\x00\x00\x00\x00")
        compressed.unlink()
        self.assertIsNotNone(serve_preview.prepare_gzip_asset(source))
        self.assertEqual(compressed.read_bytes(), first)
        self.assertEqual(source.read_bytes(), self.contents["index.pck"])
        source.write_bytes(self.contents["index.pck"] + b"new original")
        newer = time.time_ns() + 2_000_000_000
        os.utime(source, ns=(newer, newer))
        self.assertIsNotNone(serve_preview.prepare_gzip_asset(source))
        self.assertEqual(gzip.decompress(compressed.read_bytes()), source.read_bytes())
        self.assertGreaterEqual(compressed.stat().st_mtime_ns, source.stat().st_mtime_ns)
        compressed.write_bytes(b"not a gzip file")
        future = newer + 2_000_000_000
        os.utime(compressed, ns=(future, future))
        self.assertIsNotNone(serve_preview.prepare_gzip_asset(source))
        self.assertEqual(gzip.decompress(compressed.read_bytes()), source.read_bytes())
        # A newer, valid gzip for the wrong original must also be rebuilt.
        compressed.write_bytes(gzip.compress(b"wrong original", mtime=0))
        os.utime(compressed, ns=(future, future))
        self.assertIsNotNone(serve_preview.prepare_gzip_asset(source))
        self.assertEqual(gzip.decompress(compressed.read_bytes()), source.read_bytes())
        same = compressed.read_bytes()
        self.assertIsNotNone(serve_preview.prepare_gzip_asset(source))
        self.assertEqual(compressed.read_bytes(), same)

    def test_atomic_failure_and_readonly_directory_fall_back_to_raw(self):
        source = self.directory / "index.js"
        compressed = self.directory / "index.js.gz"
        compressed.unlink()
        with patch.object(serve_preview.os, "replace", side_effect=PermissionError("read-only export")):
            self.assertIsNone(serve_preview.prepare_gzip_asset(source))
        self.assertEqual(source.read_bytes(), self.contents["index.js"])
        self.assertFalse(compressed.exists())
        self.assertEqual(list(self.directory.glob("*.gz.tmp")), [])
        status, headers, body = self.request("index.js")
        self.assertEqual((status, body), (200, self.contents["index.js"]))
        self.assertNotIn("Content-Encoding", headers)
        readonly = self.directory / "readonly"
        readonly.mkdir()
        locked = readonly / "locked.pck"
        locked.write_bytes(self.contents["index.pck"])
        readonly.chmod(0o555)
        try:
            if os.access(readonly, os.W_OK):
                # Root can bypass mode bits; still exercise the same OS failure.
                with patch.object(serve_preview.tempfile, "NamedTemporaryFile", side_effect=PermissionError("read-only export")):
                    self.assertEqual(serve_preview.prepare_gzip_assets(readonly), {})
            else:
                self.assertEqual(serve_preview.prepare_gzip_assets(readonly), {})
            status, headers, body = self.request("readonly/locked.pck")
            self.assertEqual((status, body), (200, self.contents["index.pck"]))
            self.assertNotIn("Content-Encoding", headers)
        finally:
            readonly.chmod(0o755)

    def test_prepare_only_works_as_a_single_standalone_file(self):
        standalone = self.directory / "serve.py"
        shutil.copyfile(serve_preview.__file__, standalone)
        for name in self.contents:
            (self.directory / (name + ".gz")).unlink()
        process = subprocess.run([sys.executable, str(standalone), "--directory", str(self.directory), "--prepare-only"],
                                 cwd=self.directory, capture_output=True, text=True, timeout=10)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn("Prepared 3 gzip assets", process.stdout)
        self.assertNotIn("Kingdom preview:", process.stdout)
        for name, original in self.contents.items():
            self.assertEqual(gzip.decompress((self.directory / (name + ".gz")).read_bytes()), original)
            self.assertEqual((self.directory / name).read_bytes(), original)


if __name__ == "__main__":
    unittest.main(verbosity=2)
