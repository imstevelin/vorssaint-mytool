#!/usr/bin/env python3
"""Exercise real Git conflict previews and ensure assessment preserves checkout state."""
import datetime as dt
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("assessment", Path(__file__).resolve().parents[1] / "Tools/check-upstream.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AssessmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        (self.repo / "shared file.txt").write_text("base\n")
        self.commit("base")
        self.base = self.git("rev-parse", "HEAD")
        self.state = {"upstream_commit": self.base, "integrated_on": "2026-10-01"}
        self.git("branch", "upstream")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True, stderr=subprocess.DEVNULL).strip()

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-qm", message)

    def assess(self):
        return MODULE.assess(self.repo, "main", "upstream", self.state, dt.date(2026, 10, 18))

    def test_no_pending_is_not_overdue(self):
        report = self.assess()
        self.assertEqual(report["pending_commits"], 0)
        self.assertEqual(report["conflict_files"], [])
        self.assertEqual(report["priority_reasons"], [])

    def test_conflict_preview_preserves_dirty_index_and_files(self):
        (self.repo / "shared file.txt").write_text("fork\n")
        self.commit("fork")
        self.git("switch", "-q", "upstream")
        (self.repo / "shared file.txt").write_text("official\n")
        self.commit("official")
        self.git("switch", "-q", "main")
        (self.repo / "staged.txt").write_text("staged\n")
        self.git("add", "staged.txt")
        (self.repo / "shared file.txt").write_text("dirty user work\n")
        before = (self.git("status", "--porcelain"), self.git("write-tree"), self.git("rev-parse", "HEAD"))
        report = self.assess()
        after = (self.git("status", "--porcelain"), self.git("write-tree"), self.git("rev-parse", "HEAD"))
        self.assertEqual(before, after)
        self.assertEqual((self.repo / "shared file.txt").read_text(), "dirty user work\n")
        self.assertEqual(report["conflict_files"], ["shared file.txt"])
        self.assertEqual(report["overlapping_files"], ["shared file.txt"])
        self.assertEqual(report["pending_commits"], 1)
        self.assertTrue(report["dirty_worktree"])
        self.assertEqual(len(report["priority_reasons"]), 1)

    def test_clean_merge_does_not_report_non_conflicting_changes(self):
        self.git("switch", "-q", "upstream")
        (self.repo / "new.txt").write_text("new feature\n")
        self.commit("feature")
        self.git("switch", "-q", "main")
        report = self.assess()
        self.assertEqual(report["conflict_files"], [])
        self.assertEqual(report["upstream_changed_files"], 1)

    def test_rejects_baseline_not_integrated_into_fork(self):
        self.git("switch", "-q", "upstream")
        (self.repo / "new.txt").write_text("new\n")
        self.commit("new")
        self.state["upstream_commit"] = self.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(RuntimeError, "not an ancestor"):
            self.assess()

    def test_threshold_50_triggers_without_waiting_14_days(self):
        self.git("switch", "-q", "upstream")
        for _ in range(50):
            self.git("commit", "--allow-empty", "-qm", "upstream")
        self.state["integrated_on"] = "2026-10-18"
        report = self.assess()
        self.assertEqual(report["pending_commits"], 50)
        self.assertEqual(report["priority_reasons"], ["At least 50 pending commits"])


if __name__ == "__main__":
    unittest.main()
