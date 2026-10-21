"""Harmless extraction fixtures; kept in a temporary directory for inspection."""
import io
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


class ExtractTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="black-tide-extractor-"))
        self.script = Path(__file__).resolve().parents[1] / "_tools" / "extract_unitypackage.py"

    def extract(self, path):
        package = self.root / "fixture.unitypackage"
        with tarfile.open(package, "w:gz") as archive:
            for name, value in [("guid/pathname", path.encode()), ("guid/asset", b"fixture")]:
                entry = tarfile.TarInfo(name)
                entry.size = len(value)
                archive.addfile(entry, io.BytesIO(value))
        return subprocess.run([sys.executable, str(self.script), str(package), str(self.root / "out")],
                              capture_output=True, text=True)

    def test_regular_path(self):
        self.assertEqual(self.extract("Assets/Models/item.txt").returncode, 0)
        self.assertEqual((self.root / "out/Assets/Models/item.txt").read_bytes(), b"fixture")

    def test_escape_paths(self):
        for path in ["../outside.txt", "..\\outside.txt", "/outside.txt", "C:/outside.txt",
                     "C:outside.txt", "//server/share/outside.txt", "Assets/../../outside.txt"]:
            with self.subTest(path=path):
                result = self.extract(path)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unsafe asset path", result.stderr)
        self.assertFalse((self.root / "outside.txt").exists())

    def test_windows_separator(self):
        self.assertEqual(self.extract("Assets\\Models\\item.txt").returncode, 0)
        self.assertTrue((self.root / "out/Assets/Models/item.txt").is_file())

    def test_existing_link_cannot_escape(self):
        outside = self.root / "external"
        outside.mkdir()
        output = self.root / "out"
        output.mkdir()
        try:
            (output / "link").symlink_to(outside, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"Symlink privilege unavailable: {error}")
        self.assertNotEqual(self.extract("link/outside.txt").returncode, 0)
        self.assertFalse((outside / "outside.txt").exists())


if __name__ == "__main__":
    unittest.main()
