#!/usr/bin/env python3
"""Synthetic GitHub API fixtures; no network, credentials or Android build."""

from copy import deepcopy
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock
from urllib.error import HTTPError, URLError


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "candidate_checks", ROOT / "tools/require_candidate_checks.py"
)
gate = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = gate
spec.loader.exec_module(gate)
SHA = "a1" * 20
OTHER_SHA = "b2" * 20
CONTEXT = gate.Context("owner/repo", 123, gate.CANDIDATE_BRANCH, SHA)
WORKFLOW_IDS = {"diagnostics.yml": 10, "ios-compile.yml": 20}


def run_fixture(filename, *, run_id=None, number=1, attempt=1,
                status="completed", conclusion="success", **changes):
    workflow_id = WORKFLOW_IDS[filename]
    run = {
        "id": run_id or workflow_id * 100,
        "run_number": number,
        "run_attempt": attempt,
        "workflow_id": workflow_id,
        "name": gate.REQUIRED_WORKFLOWS[filename],
        "path": f".github/workflows/{filename}",
        "head_sha": SHA,
        "head_branch": CONTEXT.branch,
        "event": "pull_request",
        "repository": {"id": CONTEXT.repository_id, "full_name": CONTEXT.repository},
        "head_repository": {"id": CONTEXT.repository_id, "full_name": CONTEXT.repository},
        "status": status,
        "conclusion": conclusion,
    }
    run.update(changes)
    return run


class FakeClock:
    def __init__(self):
        self.now = 0
        self.sleeps = []
        self.on_sleep = lambda: None

    def time(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds
        self.on_sleep()


class FakeAPI:
    def __init__(self):
        self.sha = SHA
        self.runs = {filename: [run_fixture(filename)] for filename in WORKFLOW_IDS}
        self.details = {}
        self.calls = []
        self.on_get = lambda path: None
        self.identities = {
            filename: {"id": workflow_id, "path": f".github/workflows/{filename}",
                       "name": gate.REQUIRED_WORKFLOWS[filename], "state": "active"}
            for filename, workflow_id in WORKFLOW_IDS.items()
        }

    def get(self, path, params=None):
        self.calls.append((path, params))
        self.on_get(path)
        prefix = f"/repos/{CONTEXT.repository}"
        if path.startswith(f"{prefix}/git/ref/heads/"):
            return {"ref": f"refs/heads/{CONTEXT.branch}",
                    "object": {"type": "commit", "sha": self.sha}}
        for filename, workflow_id in WORKFLOW_IDS.items():
            if path == f"{prefix}/actions/workflows/{filename}":
                return deepcopy(self.identities[filename])
            if path == f"{prefix}/actions/workflows/{workflow_id}/runs":
                if params != {"branch": CONTEXT.branch, "head_sha": SHA, "per_page": 100}:
                    raise AssertionError("Run query was not bound to exact branch/SHA")
                return {"total_count": len(self.runs[filename]),
                        "workflow_runs": deepcopy(self.runs[filename])}
        if path.startswith(f"{prefix}/actions/runs/"):
            run_id = int(path.rsplit("/", 1)[1])
            if run_id in self.details:
                return deepcopy(self.details[run_id])
            for runs in self.runs.values():
                for run in runs:
                    if run["id"] == run_id:
                        return deepcopy(run)
        raise AssertionError(f"Unexpected API path: {path}")


class CandidateGateTests(unittest.TestCase):
    def setUp(self):
        self.api = FakeAPI()
        self.clock = FakeClock()
        self.messages = []

    def wait(self, timeout=2):
        gate.wait_for_checks(self.api, CONTEXT, timeout=timeout, poll_interval=1,
                             clock=self.clock.time, sleep=self.clock.sleep,
                             log=self.messages.append)

    def test_both_exact_sha_workflows_succeed(self):
        self.wait()
        self.assertEqual(self.clock.sleeps, [])
        self.assertEqual(len(self.messages), 2)
        self.assertTrue(all(SHA in message for message in self.messages))

    def test_workflow_dispatch_is_allowed(self):
        self.api.runs["ios-compile.yml"][0]["event"] = "workflow_dispatch"
        self.wait()

    def test_github_workflow_path_ref_suffix_is_allowed(self):
        self.api.runs["diagnostics.yml"][0]["path"] += "@refs/pull/42/merge"
        self.wait()

    def test_pending_then_success(self):
        run = self.api.runs["ios-compile.yml"][0]
        run.update(status="in_progress", conclusion=None)
        self.clock.on_sleep = lambda: run.update(status="completed", conclusion="success")
        self.wait()
        self.assertEqual(self.clock.sleeps, [1])

    def test_missing_then_arriving_run(self):
        self.api.runs["diagnostics.yml"] = []
        self.clock.on_sleep = lambda: self.api.runs.update(
            {"diagnostics.yml": [run_fixture("diagnostics.yml")]})
        self.wait()
        self.assertEqual(self.clock.sleeps, [1])

    def test_missing_run_times_out(self):
        self.api.runs["diagnostics.yml"] = []
        with self.assertRaisesRegex(gate.GateError, "missing or unfinished"):
            self.wait()
        self.assertEqual(self.clock.now, 2)

    def test_pending_run_times_out(self):
        self.api.runs["diagnostics.yml"][0].update(status="queued", conclusion=None)
        with self.assertRaises(gate.GateError):
            self.wait()
        self.assertEqual(self.clock.now, 2)

    def test_stale_head_rejected_before_run_lookup(self):
        self.api.sha = OTHER_SHA
        with self.assertRaisesRegex(gate.GateError, "stale build"):
            self.wait()
        self.assertFalse(any(path.endswith("/runs") for path, _ in self.api.calls))

    def test_head_changes_while_waiting(self):
        self.api.runs["ios-compile.yml"] = []
        self.clock.on_sleep = lambda: setattr(self.api, "sha", OTHER_SHA)
        with self.assertRaisesRegex(gate.GateError, "stale build"):
            self.wait()

    def test_head_changes_just_before_gate_opens(self):
        def change_head(path):
            if path.endswith("/actions/runs/2000"):
                self.api.sha = OTHER_SHA
        self.api.on_get = change_head
        with self.assertRaisesRegex(gate.GateError, "stale build"):
            self.wait()

    def test_every_non_success_terminal_conclusion_is_rejected(self):
        for conclusion in ["failure", "cancelled", "timed_out", "skipped", "neutral",
                           "action_required", "stale", "startup_failure", None]:
            with self.subTest(conclusion=conclusion):
                self.api = FakeAPI()
                self.api.runs["diagnostics.yml"][0]["conclusion"] = conclusion
                with self.assertRaisesRegex(gate.GateError, "did not succeed"):
                    self.wait()

    def test_wrong_sha_branch_event_identity_and_repository_rejected(self):
        changes = [
            {"head_sha": OTHER_SHA}, {"head_branch": "main"},
            {"event": "push"}, {"event": "pull_request_target"},
            {"workflow_id": 99}, {"name": "Lookalike Diagnostics"},
            {"path": ".github/workflows/unrelated.yml"},
            {"repository": {"id": 999, "full_name": CONTEXT.repository}},
            {"head_repository": {"id": 456, "full_name": "fork/repo"}},
            {"run_attempt": None}, {"run_number": 0}, {"id": True},
        ]
        for change in changes:
            with self.subTest(change=change):
                self.api = FakeAPI()
                self.api.runs["diagnostics.yml"][0].update(change)
                with self.assertRaises(gate.GateError):
                    self.wait()

    def test_wrong_workflow_registration_or_disabled_workflow_rejected(self):
        for change in [{"name": "Other"}, {"path": "other.yml"}, {"state": "disabled_manually"}, {"id": 0}]:
            with self.subTest(change=change):
                self.api = FakeAPI()
                self.api.identities["diagnostics.yml"].update(change)
                with self.assertRaises(gate.GateError):
                    self.wait()

    def test_newer_failed_run_cannot_fall_back_to_old_success(self):
        self.api.runs["diagnostics.yml"].append(run_fixture(
            "diagnostics.yml", run_id=1001, number=2, conclusion="failure"))
        with self.assertRaisesRegex(gate.GateError, "did not succeed"):
            self.wait()

    def test_newer_pending_run_cannot_fall_back_to_old_success(self):
        self.api.runs["diagnostics.yml"].append(run_fixture(
            "diagnostics.yml", run_id=1001, number=2, status="queued", conclusion=None))
        with self.assertRaisesRegex(gate.GateError, "missing or unfinished"):
            self.wait()

    def test_successful_newer_run_can_supersede_old_failure(self):
        self.api.runs["diagnostics.yml"][0]["conclusion"] = "failure"
        self.api.runs["diagnostics.yml"].append(run_fixture(
            "diagnostics.yml", run_id=1001, number=2))
        self.wait()

    def test_newer_attempt_pending_cannot_reuse_listed_success(self):
        self.api.details[1000] = run_fixture(
            "diagnostics.yml", attempt=2, status="in_progress", conclusion=None)
        with self.assertRaisesRegex(gate.GateError, "missing or unfinished"):
            self.wait()

    def test_newer_attempt_failure_cannot_reuse_listed_success(self):
        self.api.details[1000] = run_fixture("diagnostics.yml", attempt=2, conclusion="failure")
        with self.assertRaisesRegex(gate.GateError, "did not succeed"):
            self.wait()

    def test_newer_successful_attempt_is_allowed(self):
        self.api.details[1000] = run_fixture("diagnostics.yml", attempt=2)
        self.wait()

    def test_detail_attempt_cannot_be_older_than_list_attempt(self):
        self.api.runs["diagnostics.yml"][0]["run_attempt"] = 2
        self.api.details[1000] = run_fixture("diagnostics.yml", attempt=1)
        with self.assertRaisesRegex(gate.GateError, "Stale or inconsistent"):
            self.wait()

    def test_rerun_starts_during_final_recheck(self):
        detail_reads = 0
        def start_rerun(path):
            nonlocal detail_reads
            if path.endswith("/actions/runs/1000"):
                detail_reads += 1
                if detail_reads >= 2:
                    self.api.details[1000] = run_fixture(
                        "diagnostics.yml", attempt=2, status="queued", conclusion=None)
        self.api.on_get = start_rerun
        with self.assertRaisesRegex(gate.GateError, "missing or unfinished"):
            self.wait()

    def test_newer_run_starts_during_final_recheck(self):
        lists = 0
        def start_new_run(path):
            nonlocal lists
            if path.endswith("/actions/workflows/10/runs"):
                lists += 1
                if lists == 2:
                    self.api.runs["diagnostics.yml"].append(run_fixture(
                        "diagnostics.yml", run_id=1001, number=2,
                        status="queued", conclusion=None))
        self.api.on_get = start_new_run
        with self.assertRaisesRegex(gate.GateError, "missing or unfinished"):
            self.wait()

    def test_listed_failure_cannot_be_overridden_by_stale_success_detail(self):
        self.api.runs["diagnostics.yml"][0]["conclusion"] = "failure"
        self.api.details[1000] = run_fixture("diagnostics.yml")
        with self.assertRaisesRegex(gate.GateError, "did not succeed"):
            self.wait()

    def test_duplicate_run_list_rejected(self):
        self.api.runs["diagnostics.yml"] *= 2
        with self.assertRaisesRegex(gate.GateError, "Duplicate"):
            self.wait()

    def test_unknown_state_or_premature_conclusion_rejected(self):
        for changes in [{"status": "unknown"}, {"status": "queued", "conclusion": "success"}]:
            with self.subTest(changes=changes):
                self.api = FakeAPI()
                self.api.runs["diagnostics.yml"][0].update(changes)
                with self.assertRaisesRegex(gate.GateError, "Unexpected run state"):
                    self.wait()

    def test_incomplete_run_list_rejected(self):
        original = self.api.get
        def get(path, params=None):
            result = original(path, params)
            if path.endswith("/runs"):
                result["total_count"] += 1
            return result
        self.api.get = get
        with self.assertRaisesRegex(gate.GateError, "Incomplete"):
            self.wait()

    def test_api_error_fails_closed_without_poll_retry(self):
        self.api.get = Mock(side_effect=gate.GateError("GitHub API HTTP 403"))
        with self.assertRaisesRegex(gate.GateError, "403"):
            self.wait()
        self.assertEqual(self.clock.sleeps, [])

    def test_timeout_cannot_exceed_hard_cap(self):
        with self.assertRaisesRegex(gate.GateError, "bounded polling"):
            self.wait(gate.MAX_WAIT_SECONDS + 1)


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            "GITHUB_REPOSITORY": CONTEXT.repository,
            "GITHUB_REPOSITORY_ID": str(CONTEXT.repository_id),
            "GITHUB_SHA": SHA,
            "GITHUB_REF": f"refs/heads/{CONTEXT.branch}",
            "GITHUB_EVENT_NAME": "push",
            "GITHUB_WORKFLOW_SHA": SHA,
            "GITHUB_WORKFLOW_REF": f"{CONTEXT.repository}/{gate.BUILD_WORKFLOW}@refs/heads/{CONTEXT.branch}",
        }

    def test_valid_context(self):
        self.assertEqual(gate.context_from_environment(self.env, SHA), CONTEXT)

    def test_wrong_checkout_rejected(self):
        with self.assertRaisesRegex(gate.GateError, "Checkout HEAD"):
            gate.context_from_environment(self.env, OTHER_SHA)

    def test_missing_or_mismatched_context_rejected(self):
        for key, value in [("GITHUB_REPOSITORY", "bad/path/extra"), ("GITHUB_REPOSITORY_ID", ""),
                           ("GITHUB_SHA", "bad"), ("GITHUB_REF", "refs/heads/main"),
                           ("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_WORKFLOW_SHA", OTHER_SHA),
                           ("GITHUB_WORKFLOW_REF", "wrong")]:
            with self.subTest(key=key):
                env = dict(self.env, **{key: value})
                with self.assertRaises(gate.GateError):
                    gate.context_from_environment(env, SHA)


class HTTPClientTests(unittest.TestCase):
    def test_unexpected_host_or_missing_token_rejected(self):
        for token, host in [("", "https://api.github.com"), ("ephemeral", "https://example.com")]:
            with self.assertRaises(gate.GateError):
                gate.GitHubAPI(token, api_url=host, deadline=10, clock=lambda: 0)

    def test_http_and_transport_errors_are_closed_and_redacted(self):
        for error in [HTTPError("https://api.github.com", 403, "secret body", None, None),
                      URLError("secret body"), TimeoutError("secret body")]:
            with self.subTest(error=error):
                api = gate.GitHubAPI("ephemeral", deadline=10, clock=lambda: 0)
                api.opener = Mock()
                api.opener.open.side_effect = error
                with self.assertRaises(gate.GateError) as raised:
                    api.get("/repos/owner/repo/test")
                self.assertNotIn("secret body", str(raised.exception))
                self.assertEqual(api.opener.open.call_count, 1)

    def test_expired_deadline_prevents_request(self):
        api = gate.GitHubAPI("ephemeral", deadline=10, clock=lambda: 11)
        api.opener = Mock()
        with self.assertRaisesRegex(gate.GateError, "Timed out"):
            api.get("/repos/owner/repo/test")
        api.opener.open.assert_not_called()

    def test_redirects_are_never_followed(self):
        with self.assertRaisesRegex(gate.GateError, "redirected"):
            gate.NoRedirects().redirect_request(None, None, 302, "redirect", {}, "https://other.test")


class WorkflowWiringTests(unittest.TestCase):
    def test_candidate_gate_precedes_all_android_work(self):
        workflow = (ROOT / ".github/workflows/android-tasks-test.yml").read_text()
        self.assertIn("needs: candidate-prerequisites", workflow)
        self.assertIn("needs.candidate-prerequisites.result == 'success'", workflow)
        self.assertIn("${{ !cancelled() &&", workflow)
        self.assertIn("timeout-minutes: 45", workflow)
        self.assertIn("ref: ${{ github.sha }}", workflow)
        preflight = workflow.index("python3 tools/require_candidate_checks.py --timeout-seconds 30")
        self.assertLess(preflight, workflow.index("Install Flutter stable"))
        self.assertLess(preflight, workflow.index("Configure persistent Android signing"))
        # Both jobs need only read access; the build preflight is candidate-only.
        self.assertEqual(workflow.count("actions: read"), 2)
        self.assertIn("actions: read", workflow.split("  build:")[0])
        self.assertIn("actions: read", workflow.split("  build:")[1])
        self.assertNotIn("--head-only", workflow)
        self.assertIn("if: github.ref == 'refs/heads/" + gate.CANDIDATE_BRANCH + "'",
                      workflow.split("Revalidate exact-head checks before Android work")[1].split("Install Flutter stable")[0])

    def test_prerequisite_path_filters_cover_gate_changes(self):
        for filename in gate.REQUIRED_WORKFLOWS:
            workflow = (ROOT / ".github/workflows" / filename).read_text()
            for changed in [".github/workflows/android-tasks-test.yml", "tools/require_candidate_checks.py",
                            "tools/tests/test_candidate_checks.py"]:
                self.assertIn(f"      - '{changed}'", workflow)
        diagnostics = (ROOT / ".github/workflows/diagnostics.yml").read_text()
        self.assertIn("run: python3 tools/tests/test_candidate_checks.py", diagnostics)


if __name__ == "__main__":
    unittest.main()
