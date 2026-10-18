"""Negative controls for the language gate; no provider or backend access."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from check_repository_language import audit, fingerprint


class LanguageGateTests(unittest.TestCase):
    def run_audit(self, files, exceptions=None):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for rel, content in files.items():
                path = root / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            tracked = "\0".join(files).encode("utf-8")
            with patch("check_repository_language.subprocess.check_output", return_value=tracked):
                return audit(root, {"text_exceptions": exceptions or {}, "legacy_paths": []})

    def test_new_chinese_document_is_rejected(self):
        self.assertEqual(self.run_audit({"README.md": "English documentation"})["issues"], [])
        result = self.run_audit({"README.md": "Unreviewed \u4e2d\u6587"})
        self.assertTrue(result["issues"])

    def test_reviewed_literal_does_not_allow_chinese_comments(self):
        path = "ios/Example.swift"
        text = 'let label = "\u4e2d\u6587"\n'
        entry = {path: {"reason": "Localized fixture", "fingerprint": fingerprint(text)}}
        self.assertEqual(self.run_audit({path: text}, entry)["issues"], [])
        changed = text + "// \u4e2d\u6587\n"
        entry[path]["fingerprint"] = fingerprint(changed)
        result = self.run_audit({path: changed}, entry)
        self.assertTrue(any("comment/docstring" in issue for issue in result["issues"]))

    def test_changed_localized_text_requires_review(self):
        path = "ios/Example.swift"
        text = 'let label = "\u4e2d\u6587"'
        entry = {path: {"reason": "Localized fixture", "fingerprint": fingerprint(text)}}
        self.assertTrue(self.run_audit({path: text + '\nlet extra = "\u65b0"'}, entry)["issues"])

    def test_private_files_are_not_opened(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch("check_repository_language.subprocess.check_output", return_value=b"server/private/doubao.json\0.env.example\0"):
                with patch.object(Path, "read_bytes", side_effect=AssertionError("Private file opened")):
                    result = audit(Path(folder), {"text_exceptions": {}, "legacy_paths": []})
        self.assertEqual(result["issues"], [])
        self.assertEqual(sum(result["excluded_files"].values()), 2)

    def test_missing_text_is_not_silently_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch("check_repository_language.subprocess.check_output", return_value=b"README.md\0"):
                result = audit(Path(folder), {"text_exceptions": {}, "legacy_paths": []})
        self.assertTrue(any("unavailable" in issue for issue in result["issues"]))


if __name__ == "__main__":
    unittest.main()
