"""Exercise packaging lifecycle without changing macOS file associations."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest


COMMAND_STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
root = pathlib.Path(os.environ["PACKAGING_FIXTURE"])
command = pathlib.Path(sys.argv[0]).name
with (root / "events").open("a") as stream:
    stream.write(json.dumps([command, *sys.argv[1:]]) + "\n")
if command == "swiftc":
    destination = pathlib.Path(sys.argv[sys.argv.index("-o") + 1])
    shutil.copyfile(root / "helper-stub.py", destination)
    destination.chmod(0o755)
elif command in ("hdiutil", "pkgbuild"):
    if command == "hdiutil":
        print("disk-image progress details")
        assert sys.argv[1] == "create"
        source = pathlib.Path(sys.argv[sys.argv.index("-srcfolder") + 1])
        shutil.copyfile(source / ".DS_Store", root / "packaged-layout.dsstore")
        assert (source / "Applications").is_symlink()
        assert os.readlink(source / "Applications") == "/Applications"
    (root / "default").write_text("com.apple.dt.Xcode")
    if os.environ.get("FAIL_PACKAGE"):
        print("simulated disk-image failure", file=sys.stderr)
        sys.exit(9)
    pathlib.Path(sys.argv[-1]).write_text("new package")
elif command in ("open", "osascript"):
    sys.exit(93)
'''

HELPER_STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["PACKAGING_FIXTURE"])
mode, snapshot, bundle_id = sys.argv[1:4]
with (root / "events").open("a") as stream:
    stream.write(json.dumps([mode]) + "\n")
snapshot = pathlib.Path(snapshot)
if mode == "snapshot":
    current = (root / "default").read_text()
    snapshot.write_text(json.dumps([current] if current == bundle_id else []))
else:
    if os.environ.get("FAIL_RESTORE"):
        sys.exit(7)
    saved = json.loads(snapshot.read_text())
    if saved:
        (root / "default").write_text(saved[0])
'''


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="aropyt-packaging-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        repository = Path(__file__).resolve().parents[2]
        shutil.copyfile(repository / "package.sh", self.root / "package.sh")
        shutil.copytree(repository / "Scripts", self.root / "Scripts")
        resources = self.root / "Sources/AropytEditor/Resources"
        resources.mkdir(parents=True)
        with (resources / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "com.aropyt.AropytEditor",
                          "CFBundleShortVersionString": "0.2.1"}, stream)
        (resources / "AropytEditor.icns").write_bytes(b"icon")
        build = self.root / ".build/release"
        bundle = build / "AropytEditor_AropytEditor.bundle"
        bundle.mkdir(parents=True)
        (bundle / "marked.umd.js").write_text("preview")
        (build / "AropytEditor").write_text("binary")
        self.app = self.root / "dist/AropytEditor.app"
        self.app.mkdir(parents=True)
        (self.app / "obsolete-resource").write_text("stale")
        self.inode = self.app.stat().st_ino
        (self.root / "dist/keep-other-release.dmg").write_text("old release")
        (self.root / "helper-stub.py").write_text(HELPER_STUB)
        (self.root / "default").write_text("com.aropyt.AropytEditor")
        commands = self.root / "bin"
        commands.mkdir()
        for command in ["swift", "swiftc", "codesign", "hdiutil", "pkgbuild", "open", "osascript"]:
            executable = commands / command
            executable.write_text(COMMAND_STUB)
            executable.chmod(0o755)
        temporary = self.root / "tmp"
        temporary.mkdir()
        self.environment = dict(os.environ, PACKAGING_FIXTURE=str(self.root),
                                TMPDIR=str(temporary), PATH=f"{commands}:{os.environ['PATH']}")

    def package(self, mode="dmg", **environment):
        return subprocess.run(["bash", "package.sh", mode], cwd=self.root,
                              env=dict(self.environment, **environment),
                              capture_output=True, text=True, timeout=30)

    def events(self):
        return [json.loads(line) for line in (self.root / "events").read_text().splitlines()]

    def test_repeated_packaging_keeps_app_identity_and_existing_default(self):
        for mode in ["dmg", "dmg", "pkg"]:
            with self.subTest(mode=mode):
                result = self.package(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("disk-image progress details", result.stdout + result.stderr)
                self.assertEqual(self.app.stat().st_ino, self.inode)
                self.assertFalse((self.app / "obsolete-resource").exists())
                self.assertEqual((self.root / "default").read_text(), "com.aropyt.AropytEditor")
                self.assertEqual((self.root / f"dist/Aropyt-0.2.1.{mode}").read_text(), "new package")
                self.assertTrue((self.root / "dist/keep-other-release.dmg").exists())
                self.assertEqual(list((self.root / "tmp").glob("aropyt-package.*")), [])
        events = self.events()
        self.assertEqual(sum(event[0] == "snapshot" for event in events), 3)
        self.assertEqual(sum(event[0] == "restore" for event in events), 3)
        signing = next(event for event in events if event[0] == "codesign" and "--sign" in event)
        self.assertIn('=designated => identifier "com.aropyt.AropytEditor"', signing)
        self.assertEqual(signing[signing.index("--identifier") + 1], "com.aropyt.AropytEditor")

    def test_failed_packaging_restores_default_and_keeps_previous_package(self):
        output = self.root / "dist/Aropyt-0.2.1.dmg"
        output.write_text("previous package")
        result = self.package(FAIL_PACKAGE="1")
        self.assertEqual(result.returncode, 9)
        self.assertIn("simulated disk-image failure", result.stderr)
        self.assertEqual((self.root / "default").read_text(), "com.aropyt.AropytEditor")
        self.assertEqual(output.read_text(), "previous package")
        self.assertEqual(list((self.root / "tmp").glob("aropyt-package.*")), [])

    def test_other_default_application_is_kept(self):
        (self.root / "default").write_text("com.apple.dt.Xcode")
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "default").read_text(), "com.apple.dt.Xcode")

    def test_restore_failure_is_reported_as_failure(self):
        result = self.package(FAIL_RESTORE="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("未能恢复", result.stderr)
        self.assertEqual(list((self.root / "tmp").glob("aropyt-package.*")), [])

    def test_dmg_carries_original_layout_without_finder_script(self):
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stderr)
        command = next(event for event in self.events() if event[0] == "hdiutil")
        self.assertEqual(command[1], "create")
        self.assertFalse(any(event[0] in ("open", "osascript") for event in self.events()))
        data = (self.root / "packaged-layout.dsstore").read_bytes()
        self.assertEqual(data[:8], b"\x00\x00\x00\x01Bud1")

        def record(filename, code):
            # Locate a known record in this fixed, single-node layout template.
            marker = struct.pack(">I", len(filename)) + filename.encode("utf-16be") + code
            start = data.index(marker) + len(marker)
            kind = data[start:start + 4]
            if kind == b"blob":
                length = struct.unpack_from(">I", data, start + 4)[0]
                return data[start + 8:start + 8 + length]
            self.assertEqual(kind, b"type")
            return data[start + 4:start + 8]

        window = plistlib.loads(record(".", b"bwsp"))
        self.assertEqual(window["WindowBounds"], "{{10, 60}, {560, 340}}")
        self.assertFalse(window["ShowToolbar"])
        self.assertFalse(window["ShowStatusBar"])
        self.assertFalse(window["ShowSidebar"])
        self.assertEqual(record(".", b"icvl"), b"icnv")
        icons = plistlib.loads(record(".", b"icvp"))
        self.assertEqual(icons["iconSize"], 100)
        self.assertEqual(icons["arrangeBy"], "none")
        self.assertEqual(struct.unpack_from(">II", record("AropytEditor.app", b"Iloc")), (140, 170))
        self.assertEqual(struct.unpack_from(">II", record("Applications", b"Iloc")), (420, 170))


if __name__ == "__main__":
    unittest.main()
