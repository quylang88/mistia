#!/usr/bin/env python3
"""Source/artifact freshness tests; fixtures never mutate the workspace."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
GENERATOR = pathlib.Path("Scripts/generate-android-investment-unit-fold.swift")
SOURCE = pathlib.Path("Mistia/Shared/CoreLogic/InvestmentLogic.swift")
OUTPUT = pathlib.Path("android/core/model/src/main/java/vn/com/quyln/mistia/core/model/SwiftInvestmentUnitFold.generated.kt")
MANIFEST = pathlib.Path("docs/android/investment-unit-fold.generated.json")


class InvestmentUnitFoldFreshnessTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mistia-unit-fold-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        for path in (GENERATOR, SOURCE, OUTPUT, MANIFEST):
            destination = self.root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / path, destination)
        result = self.check()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def check(self):
        return subprocess.run(
            ["swift", str(ROOT / GENERATOR), "--check", "--root", str(self.root)],
            capture_output=True, text=True, check=False,
        )

    def assert_stale(self):
        result = self.check()
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("Stale", result.stderr)

    def test_unchanged_corpus_is_valid(self):
        self.assertEqual(0, self.check().returncode)

    def test_generated_fold_edit_is_rejected(self):
        with (self.root / OUTPUT).open("a") as out:
            out.write("\n// stale output\n")
        self.assert_stale()

    def test_swift_unit_helper_change_is_rejected(self):
        path = self.root / SOURCE
        path.write_text(path.read_text().replace(
            "nonisolated enum InvestmentUnitLabel {",
            "nonisolated enum InvestmentUnitLabel {\n    // changed helper\n",
        ))
        self.assert_stale()

    def test_generator_change_is_rejected(self):
        with (self.root / GENERATOR).open("a") as out:
            out.write("\n// changed generator\n")
        self.assert_stale()


if __name__ == "__main__":
    unittest.main()
