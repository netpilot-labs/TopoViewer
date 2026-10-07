#!/usr/bin/env python3
"""Prove required jobs for a successful PR workflow run; unknown workflows require all jobs."""
import json
import subprocess
import sys

REQUIRED = {
    ('lz-networks/NetPilot-2-Backend', '.github/workflows/agents_service.yml'): ['Unit Tests', 'Lint & Type Check'],
    ('lz-networks/NetPilot-2-Frontend', '.github/workflows/test.yml'): ['Test & Type Check', 'Test Coverage'],
    ('lz-networks/netpilot-marketing', '.github/workflows/ci.yml'): ['Lint, Type Check & Build'],
    ('netpilot-labs/containerlab-mcp', '.github/workflows/test.yml'): ['lint', 'security', 'type-check', 'unit-tests', 'integration-tests'],
    ('netpilot-labs/containerlab-mcp', '.github/workflows/cloud-release.yml'): ['build', 'tools-list'],
    ('netpilot-labs/containerlab-mcp', '.github/workflows/onprem-bundle.yml'): ['build', 'install-test', 'install-test-connector-only', 'install-test-connector-bundle'],
    ('netpilot-labs/TopoViewer', '.github/workflows/ci.yml'): ['Go (gofmt, build, vet, test)', 'JS syntax (non-vendored)'],
}


def check(repo, path, head, pages):
    if not isinstance(pages, list) or any(not isinstance(p, dict) or not isinstance(p.get('jobs'), list) for p in pages):
        raise ValueError('unreadable job inventory')
    jobs = [job for page in pages for job in page['jobs']]
    if not jobs or any(not isinstance(job, dict) or not isinstance(job.get('name'), str) for job in jobs):
        raise ValueError('missing or malformed job inventory')
    required = REQUIRED.get((repo, path), [job['name'] for job in jobs])
    for name in required:
        matches = [job for job in jobs if job['name'] == name]
        if len(matches) != 1:
            return f'required job missing or duplicated: {name}'
        job = matches[0]
        if job.get('head_sha') != head or job.get('status') != 'completed' or job.get('conclusion') != 'success':
            return f'required job not successful on head: {name}'
    return None


def main(argv):
    if len(argv) != 4:
        raise SystemExit('usage: ci-jobs.py <owner/repo> <run-id> <workflow-path> <head>')
    repo, run, path, head = argv
    if not run.isdigit():
        raise SystemExit('invalid run id')
    result = subprocess.run(['gh', 'api', f'repos/{repo}/actions/runs/{run}/jobs?per_page=100', '--paginate', '--slurp'], text=True, capture_output=True)
    try:
        if result.returncode:
            raise ValueError('cannot read workflow jobs')
        problem = check(repo, path, head, json.loads(result.stdout))
    except (ValueError, TypeError, KeyError) as error:
        print(str(error))
        return 2
    if problem:
        print(problem)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
