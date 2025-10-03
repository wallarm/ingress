#!/usr/bin/env python3
"""Generate a SLSA v1 provenance predicate for the published image."""

from __future__ import annotations

import json
import os
import sys


def require(name: str) -> str:
    value = os.environ.get(name)
    if value is None:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def main() -> None:
    output_path = require("PROVENANCE_PREDICATE")
    # Use the actual GitLab instance URL (configurable via CI_SERVER_URL or default)
    gitlab_url = os.environ.get("CI_SERVER_URL", "https://gl.wallarm.com")
    
    # Generate only the predicate content - cosign will wrap it in the in-toto statement
    predicate = {
        "buildDefinition": {
            "buildType": f"{gitlab_url}/wallarm-node/node-nginx/pipeline",
            "externalParameters": {
                "ref": require("CI_COMMIT_REF_NAME"),
                "build_kind": require("X_CI_BUILD_KIND"),
                "source": {
                    "uri": f"{gitlab_url}/{require('CI_PROJECT_PATH')}",
                    "digest": {"sha256": require("CI_COMMIT_SHA")},
                },
                "trigger": os.environ.get("CI_PIPELINE_SOURCE", "unknown"),
                "commit_title": os.environ.get("CI_COMMIT_TITLE", ""),
            },
            "internalParameters": {
                "entryPoint": ".gitlab-ci.yml",
                "pipeline_id": require("CI_PIPELINE_ID"),
                "job_id": os.environ.get("CI_JOB_ID", ""),
                "job_name": os.environ.get("CI_JOB_NAME", ""),
                "runner_id": os.environ.get("CI_RUNNER_ID", ""),
                "runner_description": os.environ.get("CI_RUNNER_DESCRIPTION", ""),
            },
            "resolvedDependencies": [],
        },
        "runDetails": {
            "builder": {
                "id": (
                    f"{gitlab_url}/{require('CI_PROJECT_PATH')}/-/"
                    f"pipelines/{require('CI_PIPELINE_ID')}"
                ),
                "version": {
                    "gitlab": os.environ.get("CI_SERVER_VERSION", "18.2.1-ee"),
                    "gitlab_runner": os.environ.get("CI_RUNNER_VERSION", "unknown"),
                },
            },
            "metadata": {
                "invocationId": require("CI_PIPELINE_ID"),
                "startedOn": os.environ.get("CI_PIPELINE_CREATED_AT", require("BUILD_FINISHED")),
                "finishedOn": require("BUILD_FINISHED"),
                "project": {
                    "id": os.environ.get("CI_PROJECT_ID", ""),
                    "name": os.environ.get("CI_PROJECT_NAME", ""),
                    "namespace": os.environ.get("CI_PROJECT_NAMESPACE", ""),
                    "visibility": os.environ.get("CI_PROJECT_VISIBILITY", ""),
                },
                "commit": {
                    "sha": require("CI_COMMIT_SHA"),
                    "short_sha": os.environ.get("CI_COMMIT_SHORT_SHA", ""),
                    "branch": os.environ.get("CI_COMMIT_BRANCH", ""),
                    "tag": os.environ.get("CI_COMMIT_TAG", ""),
                    "author": os.environ.get("CI_COMMIT_AUTHOR", ""),
                    "timestamp": os.environ.get("CI_COMMIT_TIMESTAMP", ""),
                },
            },
        },
    }

    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(predicate, fh, indent=2)
        fh.write("\n")
    
    # Debug: print the structure to stderr for troubleshooting
    print(f"Provenance predicate written to: {output_path}", file=sys.stderr)
    print(f"Top-level keys: {list(predicate.keys())}", file=sys.stderr)


if __name__ == "__main__":
    main()
