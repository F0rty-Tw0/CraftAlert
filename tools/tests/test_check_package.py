"""Tests for tools/check_package.py on small zips built in a temp dir.

Run:  python -m unittest tools.tests.test_check_package
"""

import contextlib
import io
import os
import tempfile
import unittest
import zipfile

from tools import check_package

TOC = """## Interface: 120105
## Title: Craft Alert

Core/Constants.lua
# a comment line
UI/LeadsWindow.lua
Bootstrap.lua
"""

COMPLETE = [
    "CraftAlert/CraftAlert.toc",
    "CraftAlert/Bindings.xml",
    "CraftAlert/Core/Constants.lua",
    "CraftAlert/UI/LeadsWindow.lua",
    "CraftAlert/Bootstrap.lua",
]


class CheckPackageTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.dir = temp.name
        self.toc = os.path.join(self.dir, "CraftAlert.toc")
        with open(self.toc, "w", encoding="utf-8") as handle:
            handle.write(TOC)

    def build_zip(self, names):
        path = os.path.join(self.dir, "CraftAlert.zip")
        with zipfile.ZipFile(path, "w") as archive:
            for name in names:
                info = zipfile.ZipInfo()
                # Set after construction: ZipInfo(name) turns "\" into "/" on Windows.
                info.filename = name
                archive.writestr(info, "")
        return path

    def run_main(self, zip_path):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = check_package.main([zip_path, "--toc", self.toc])
        return code, stdout.getvalue(), stderr.getvalue()

    def test_complete_package_passes(self):
        zip_path = self.build_zip(COMPLETE)

        self.assertEqual(check_package.check_package(zip_path, self.toc), ([], []))
        code, stdout, _ = self.run_main(zip_path)
        self.assertEqual(code, 0)
        self.assertIn("OK:", stdout)

    def test_directory_entries_are_ignored(self):
        zip_path = self.build_zip(["CraftAlert/", "CraftAlert/Core/"] + COMPLETE)

        self.assertEqual(check_package.check_package(zip_path, self.toc), ([], []))

    def test_missing_toc_file_fails(self):
        zip_path = self.build_zip([name for name in COMPLETE if not name.endswith("LeadsWindow.lua")])

        self.assertEqual(check_package.check_package(zip_path, self.toc), (["CraftAlert/UI/LeadsWindow.lua"], []))
        code, _, stderr = self.run_main(zip_path)
        self.assertEqual(code, 1)
        self.assertIn("missing: CraftAlert/UI/LeadsWindow.lua", stderr)
        self.assertIn("1 missing, 0 extra", stderr)

    def test_missing_bindings_fails(self):
        zip_path = self.build_zip([name for name in COMPLETE if not name.endswith("Bindings.xml")])

        self.assertEqual(check_package.check_package(zip_path, self.toc), (["CraftAlert/Bindings.xml"], []))

    def test_extra_file_fails(self):
        zip_path = self.build_zip(COMPLETE + ["CraftAlert/tests/test_matcher.lua"])

        self.assertEqual(check_package.check_package(zip_path, self.toc), ([], ["CraftAlert/tests/test_matcher.lua"]))
        code, _, stderr = self.run_main(zip_path)
        self.assertEqual(code, 1)
        self.assertIn("extra: CraftAlert/tests/test_matcher.lua", stderr)

    def test_backslash_paths_are_normalised(self):
        zip_path = self.build_zip([name.replace("/", "\\") for name in COMPLETE])

        # Python's zip reader fixes "\" itself only on Windows; CI (Linux) sees them raw.
        with open(zip_path, "rb") as handle:
            self.assertIn(b"CraftAlert\\Core\\Constants.lua", handle.read())
        self.assertEqual(check_package.check_package(zip_path, self.toc), ([], []))

    def test_init_lua_stub_is_extra(self):
        zip_path = self.build_zip(COMPLETE + ["CraftAlert/Core/init.lua"])

        self.assertEqual(check_package.check_package(zip_path, self.toc), ([], ["CraftAlert/Core/init.lua"]))

    def test_init_lua_stub_is_extra_even_when_the_toc_lists_it(self):
        with open(self.toc, "a", encoding="utf-8") as handle:
            handle.write("UI/init.lua\n")
        zip_path = self.build_zip(COMPLETE + ["CraftAlert/UI/init.lua"])

        self.assertEqual(check_package.check_package(zip_path, self.toc), ([], ["CraftAlert/UI/init.lua"]))

    def test_unreadable_zip_fails_with_a_message(self):
        not_a_zip = os.path.join(self.dir, "broken.zip")
        with open(not_a_zip, "w", encoding="utf-8") as handle:
            handle.write("not a zip")

        code, _, stderr = self.run_main(not_a_zip)
        self.assertEqual(code, 1)
        self.assertIn("cannot read package", stderr)


if __name__ == "__main__":
    unittest.main()
