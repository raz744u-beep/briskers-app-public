#!/usr/bin/env python3
"""Fail-closed, read-only GitHub CI gate for the isolated performance candidate.

Only the standard ephemeral GITHUB_TOKEN is used. No dependencies, dispatches,
reruns, credentials, signing material, or writes to GitHub are needed. A missing
run may arrive later, but only the newest run's current attempt can pass.
"""

import argparse
from dataclasses import dataclass
import json
import os
import re
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener


CANDIDATE_BRANCH = "feature/vin-photo-ocr-safe-barcode-20261021"
BUILD_WORKFLOW = ".github/workflows/android-debug.yml"
REQUIRED_WORKFLOWS = {
    "diagnostics.yml": "Briskers Diagnostics",
    "ios-compile.yml": "Briskers iOS compile check",
}
ALLOWED_EVENTS = {"pull_request", "workflow_dispatch"}
PENDING_STATUSES = {"queued", "in_progress", "waiting", "pending", "requested"}
MAX_WAIT_SECONDS = 2400
REQUEST_TIMEOUT_SECONDS = 15


class GateError(RuntimeError):
    """A condition that must prevent Android build/signing."""


@dataclass(frozen=True)
class Context:
    repository: str
    repository_id: int
    branch: str
    sha: str


def positive_integer(value, label):
    if type(value) is not int or value < 1:
        raise GateError(f"Missing or invalid {label}")
    return value


def context_from_environment(env, checkout_sha):
    repository = env.get("GITHUB_REPOSITORY", "")
    sha = env.get("GITHUB_SHA", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise GateError("Invalid GitHub repository")
    if not re.fullmatch(r"[0-9a-f]{40}", sha) or checkout_sha != sha:
        raise GateError("Checkout HEAD must equal the exact GITHUB_SHA")
    if env.get("GITHUB_REF") != f"refs/heads/{CANDIDATE_BRANCH}":
        raise GateError("This gate is restricted to the isolated candidate branch")
    if env.get("GITHUB_EVENT_NAME") not in {"push", "workflow_dispatch"}:
        raise GateError("Unexpected Android workflow event")
    workflow_ref = f"{repository}/{BUILD_WORKFLOW}@refs/heads/{CANDIDATE_BRANCH}"
    if env.get("GITHUB_WORKFLOW_REF") != workflow_ref:
        raise GateError("Unexpected Android workflow identity/ref")
    if env.get("GITHUB_WORKFLOW_SHA") != sha:
        raise GateError("Android workflow definition must be at GITHUB_SHA")
    try:
        repository_id = int(env.get("GITHUB_REPOSITORY_ID", ""))
    except ValueError as error:
        raise GateError("Invalid GitHub repository ID") from error
    positive_integer(repository_id, "repository ID")
    return Context(repository, repository_id, CANDIDATE_BRANCH, sha)


class NoRedirects(HTTPRedirectHandler):
    # Never forward the ephemeral token to another location, even on redirects.
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise GateError("GitHub API redirected; refusing to continue")


class GitHubAPI:
    def __init__(self, token, *, api_url="https://api.github.com", deadline,
                 clock=time.monotonic):
        if api_url != "https://api.github.com" or not token:
            raise GateError("Expected GitHub.com API and ephemeral GITHUB_TOKEN")
        self.token = token
        self.api_url = api_url
        self.deadline = deadline
        self.clock = clock
        self.opener = build_opener(NoRedirects())

    def get(self, path, params=None):
        remaining = self.deadline - self.clock()
        if remaining <= 0:
            raise GateError("Timed out waiting for required checks")
        if not path.startswith("/repos/") or "?" in path or "#" in path:
            raise GateError("Invalid GitHub API path")
        url = self.api_url + path
        if params:
            url += "?" + urlencode(params)
        request = Request(url, headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self.token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "briskers-candidate-ci-gate",
            "Cache-Control": "no-cache",
        })
        try:
            with self.opener.open(
                request, timeout=min(REQUEST_TIMEOUT_SECONDS, remaining)
            ) as response:
                if response.status != 200:
                    raise GateError("Unexpected GitHub API response status")
                result = json.load(response)
        except HTTPError as error:
            raise GateError(f"GitHub API HTTP {error.code}; refusing to continue") from error
        except (URLError, TimeoutError, OSError, ValueError) as error:
            # Do not echo response bodies, headers or authentication values.
            raise GateError("GitHub API request/JSON failed; refusing to continue") from error
        if self.clock() >= self.deadline:
            raise GateError("Timed out waiting for required checks")
        if not isinstance(result, dict):
            raise GateError("Unexpected GitHub API response shape")
        return result


def require_current_head(api, context):
    ref = api.get(
        f"/repos/{context.repository}/git/ref/heads/{quote(context.branch, safe='')}"
    )
    target = ref.get("object")
    if (ref.get("ref") != f"refs/heads/{context.branch}"
            or not isinstance(target, dict)
            or target.get("type") != "commit"
            or target.get("sha") != context.sha):
        raise GateError("Candidate branch head changed or is invalid; refusing stale build")


def workflow_identity(api, context, filename, name):
    workflow = api.get(f"/repos/{context.repository}/actions/workflows/{filename}")
    if (workflow.get("path") != f".github/workflows/{filename}"
            or workflow.get("name") != name
            or workflow.get("state") != "active"):
        raise GateError(f"Unexpected or inactive required workflow: {filename}")
    return positive_integer(workflow.get("id"), f"{filename} workflow ID")


def validate_run(run, context, filename, name, workflow_id):
    if not isinstance(run, dict):
        raise GateError(f"Malformed run for {filename}")
    # GitHub may append @ref to path (including PR merge refs). Workflow ID and
    # path identify the workflow; source repository, branch and SHA are separate.
    path = run.get("path")
    if not isinstance(path, str) or path.split("@", 1)[0] != f".github/workflows/{filename}":
        raise GateError(f"Wrong workflow path for {filename}")
    if (run.get("workflow_id") != workflow_id or run.get("name") != name
            or run.get("head_sha") != context.sha
            or run.get("head_branch") != context.branch
            or run.get("event") not in ALLOWED_EVENTS):
        raise GateError(f"Wrong workflow, commit, branch or event for {filename}")
    for field in ("repository", "head_repository"):
        repository = run.get(field)
        if (not isinstance(repository, dict)
                or repository.get("full_name") != context.repository
                or repository.get("id") != context.repository_id):
            raise GateError(f"Wrong {field} for {filename}")
    for field in ("id", "run_number", "run_attempt"):
        positive_integer(run.get(field), f"{filename} {field}")
    status, conclusion = run.get("status"), run.get("conclusion")
    if status == "completed":
        if conclusion != "success":
            raise GateError(f"{filename} attempt {run['run_attempt']} did not succeed: {conclusion}")
        return True
    if status not in PENDING_STATUSES or conclusion is not None:
        raise GateError(f"Unexpected run state for {filename}: {status}/{conclusion}")
    return False


def latest_run(api, context, filename, name, workflow_id):
    result = api.get(
        f"/repos/{context.repository}/actions/workflows/{workflow_id}/runs",
        {"branch": context.branch, "head_sha": context.sha, "per_page": 100},
    )
    runs = result.get("workflow_runs")
    count = result.get("total_count")
    # Refuse incomplete/truncated lists rather than accidentally choosing an old
    # success. An isolated candidate should have far fewer than 100 runs/SHA.
    if (not isinstance(runs, list) or type(count) is not int
            or count != len(runs) or len(runs) > 100):
        raise GateError(f"Incomplete run list for {filename}")
    if not runs:
        return None
    # Validate identities for all results, but do not treat a superseded failure
    # as the outcome of a newer run. The live detail endpoint supplies that state.
    ids = set()
    for run in runs:
        identity = dict(run) if isinstance(run, dict) else {}
        identity.update(status="queued", conclusion=None)
        validate_run(identity, context, filename, name, workflow_id)
        if run["id"] in ids:
            raise GateError(f"Duplicate run ID for {filename}")
        ids.add(run["id"])
    candidate = max(runs, key=lambda run: (run["run_number"], run["id"]))
    # A known failure cannot be overridden by a contradictory detail response.
    # Rerun after GitHub reports the new attempt rather than reuse stale green.
    validate_run(candidate, context, filename, name, workflow_id)
    detail = api.get(f"/repos/{context.repository}/actions/runs/{candidate['id']}")
    succeeded = validate_run(detail, context, filename, name, workflow_id)
    if (detail["id"] != candidate["id"]
            or detail["run_number"] != candidate["run_number"]
            or detail["run_attempt"] < candidate["run_attempt"]):
        raise GateError(f"Stale or inconsistent run attempt for {filename}")
    return detail if succeeded else None


def wait_for_checks(api, context, *, timeout=MAX_WAIT_SECONDS, poll_interval=20,
                    clock=time.monotonic, sleep=time.sleep, log=print):
    if not 0 < timeout <= MAX_WAIT_SECONDS or not 0 < poll_interval <= 60:
        raise GateError("Invalid bounded polling configuration")
    deadline = clock() + timeout
    identities = {
        filename: workflow_identity(api, context, filename, name)
        for filename, name in REQUIRED_WORKFLOWS.items()
    }
    while clock() < deadline:
        require_current_head(api, context)
        successful = {}
        for filename, name in REQUIRED_WORKFLOWS.items():
            run = latest_run(api, context, filename, name, identities[filename])
            if run is not None:
                successful[filename] = run
        if len(successful) == len(REQUIRED_WORKFLOWS):
            # Re-list both workflows and re-read the current attempts. Neither
            # a fresh run nor a rerun may inherit the earlier green result.
            unchanged = True
            for filename, previous in successful.items():
                current = latest_run(api, context, filename,
                                     REQUIRED_WORKFLOWS[filename], identities[filename])
                if current is None:
                    unchanged = False
                    continue
                if (current["run_number"] < previous["run_number"]
                        or (current["id"] == previous["id"]
                            and current["run_attempt"] < previous["run_attempt"])):
                    raise GateError(f"Stale final run attempt for {filename}")
                unchanged &= (current["id"] == previous["id"]
                              and current["run_attempt"] == previous["run_attempt"])
            require_current_head(api, context)
            if unchanged and clock() < deadline:
                for filename, run in successful.items():
                    log(f"Verified {filename}: run {run['id']}, attempt {run['run_attempt']}, SHA {context.sha}")
                return
        remaining = deadline - clock()
        if remaining <= 0:
            break
        log(f"Waiting for both required current-SHA checks ({int(remaining)}s remaining)")
        sleep(min(poll_interval, remaining))
    raise GateError("Timed out: required current-SHA checks are missing or unfinished")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout-seconds", type=int, default=MAX_WAIT_SECONDS)
    args = parser.parse_args()
    try:
        if not 0 < args.timeout_seconds <= MAX_WAIT_SECONDS:
            raise GateError("Timeout must be between 1 and 2400 seconds")
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
        subprocess.run(["git", "diff", "--quiet", "HEAD", "--"], check=True)
        context = context_from_environment(os.environ, sha)
        api = GitHubAPI(os.environ.get("GITHUB_TOKEN", ""),
                        api_url=os.environ.get("GITHUB_API_URL", ""),
                        deadline=time.monotonic() + args.timeout_seconds)
        wait_for_checks(api, context, timeout=args.timeout_seconds)
    except (GateError, subprocess.CalledProcessError) as error:
        print(f"ERROR: Candidate build gate closed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
