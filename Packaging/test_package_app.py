import tempfile
import unittest
from pathlib import Path
from package_app import publish_app


class StableAppNameTests(unittest.TestCase):
    def test_successive_publications_keep_name_and_previous_build(self):
        with tempfile.TemporaryDirectory(prefix="stefi-package-test-") as scratch:
            root = Path(scratch)
            source = root / "source" / "SteFi.app"
            source.mkdir(parents=True)
            (source / "fixture").write_text("first")
            dist = root / "dist"
            dist.mkdir()
            final = dist / "SteFi.app"
            publish_app(source, final)
            self.assertEqual((final / "fixture").read_text(), "first")
            (source / "fixture").write_text("second")
            publish_app(source, final)
            self.assertEqual((final / "fixture").read_text(), "second")
            backups = list((dist / "archive").glob("*/SteFi.app"))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / "fixture").read_text(), "first")

    def test_symlink_is_not_replaced(self):
        with tempfile.TemporaryDirectory(prefix="stefi-package-test-") as scratch:
            root = Path(scratch)
            source = root / "source"
            source.mkdir()
            final = root / "SteFi.app"
            final.symlink_to(source, target_is_directory=True)
            with self.assertRaises(RuntimeError):
                publish_app(source, final)
            self.assertTrue(final.is_symlink())


if __name__ == "__main__":
    unittest.main()
