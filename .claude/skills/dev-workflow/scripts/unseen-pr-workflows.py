#!/usr/bin/env python3
"""Require unseen active PR workflows without assuming that run history is complete.

This recognizes ordinary trigger syntax plus literal and prefix/** path filters.
Unsupported filters stay UNKNOWN until an associated run supplies history.
Unsupported trigger/filter syntax remains unknown; no machine-specific YAML dependency is imported.
"""
import base64
import json
import re
import subprocess
import sys


def api(route, *fields):
    args = ['gh', 'api', route, *fields]
    result = subprocess.run(args, text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise ValueError('workflow declaration evidence unavailable: ' + route)
    return json.loads(result.stdout)


def event_name(value):
    value = value.strip()
    if value[:1] in ['"', "'"]:
        if len(value) < 2 or value[-1] != value[0]:
            raise ValueError('unsupported quoted trigger')
        value = value[1:-1]
    if not re.fullmatch(r'[a-z_]+', value):
        raise ValueError('unsupported trigger syntax')
    return value


def split_unquoted(value, separator):
    """Split ordinary YAML scalars without treating quoted punctuation as syntax."""
    pieces = []
    start = index = 0
    quote = None
    while index < len(value):
        char = value[index]
        if quote:
            if quote == '"' and char == '\\':
                index += 2
                continue
            if char == quote:
                if quote == "'" and value[index:index + 2] == "''":
                    index += 2
                    continue
                quote = None
        elif char in ('"', "'"):
            quote = char
        elif char == separator and (separator != '#' or index == 0 or value[index - 1].isspace()):
            pieces.append(value[start:index])
            if separator == '#':
                return pieces
            start = index + 1
        index += 1
    if quote:
        raise ValueError('unsupported unterminated quoted scalar')
    pieces.append(value[start:])
    return pieces


def requires_pr(text, changed=(), base=""):

    lines = [line.rstrip() for line in text.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    starts = [i for i, line in enumerate(lines) if re.match(r'^(?:on|"on"|\'on\')\s*:', line)]
    if len(starts) != 1:
        raise ValueError('unseen workflow trigger is unknown')
    index = starts[0]
    value = split_unquoted(lines[index], '#')[0].split(':', 1)[1].strip()
    if value:
        if value.startswith('[') and value.endswith(']'):
            events = [event_name(x) for x in split_unquoted(value[1:-1], ',')]
        else:
            events = [event_name(value)]
        return 'pull_request' in events
    block = []
    for line in lines[index + 1:]:
        if not line[:1].isspace():
            break
        block.append(split_unquoted(line, '#')[0])
    if not block:
        raise ValueError('empty workflow trigger')
    indent = min(len(x) - len(x.lstrip()) for x in block)
    events = []
    pr_fields = []
    current = None
    for line in block:
        depth = len(line) - len(line.lstrip())
        if depth == indent:
            key, separator, tail = line.strip().partition(':')
            if not separator:
                raise ValueError('unsupported workflow trigger mapping')
            current = event_name(key)
            events.append(current)
            if current == 'pull_request' and tail.strip() not in ['', '{}']:
                raise ValueError('unsupported inline PR filter')
        elif current == 'pull_request':
            pr_fields.append(line)
    if 'pull_request' not in events:
        return False
    if not pr_fields:
        return True
    filters = {}
    key = None
    for line in pr_fields:
        value = line.strip()
        if value.startswith('- '):
            if key is None:
                raise ValueError('unknown PR filter list')
            filters[key].append(value[2:].strip())
        else:
            key, separator, tail = value.partition(':')
            if not separator:
                raise ValueError('unknown PR filter syntax')
            tail = tail.strip()
            if tail and not (tail.startswith('[') and tail.endswith(']')):
                raise ValueError('unknown PR filter value')
            if key in filters:
                raise ValueError('unsupported duplicate PR filter')
            filters[key] = [x.strip() for x in split_unquoted(tail[1:-1], ',')] if tail else []
    def scalar(value):
        if value.startswith('"'):
            try:
                value = json.loads(value)
            except ValueError as error:
                raise ValueError('unsupported quoted filter') from error
            if not isinstance(value, str):
                raise ValueError('unsupported quoted filter')
        elif value.startswith("'"):
            if len(value) < 2 or not value.endswith("'"):
                raise ValueError('unsupported quoted filter')
            body = value[1:-1]
            if "'" in body.replace("''", ''):
                raise ValueError('unsupported quoted filter')
            value = body.replace("''", "'")
        elif '"' in value or "'" in value:
            raise ValueError('unsupported mixed quoted filter')
        return value
    def match(pattern, value):
        pattern = scalar(pattern)
        if pattern == '**':
            return True
        if pattern.endswith('/**') and not any(c in pattern[:-3] for c in '*?![]+'):
            return value.startswith(pattern[:-3] + '/')
        if not any(c in pattern for c in '*?![]+'):
            return pattern == value
        return None
    unknown = False
    for key, patterns in filters.items():
        if key == 'types':
            continue  # A potential PR event remains required; type omission cannot prove success.
        if key not in ['paths', 'paths-ignore', 'branches', 'branches-ignore'] or not patterns:
            unknown = True
            continue
        values = list(changed) if key.startswith('paths') else [base]
        matches = [[match(pattern, value) for pattern in patterns] for value in values]
        # Unsupported ordered patterns can override an earlier positive match.
        if any(None in row for row in matches):
            unknown = True
            continue
        if key.endswith('-ignore'):
            if values and all(True in row for row in matches):
                return False
            if any(None in row and True not in row for row in matches):
                unknown = True
        else:
            flat = [item for row in matches for item in row]
            if flat and all(item is False for item in flat):
                return False
            if True not in flat:
                unknown = True
    if unknown:
        raise ValueError('unseen PR filter cannot be proven; associated-run evidence required')
    return True


def main():
    try:
        repo, pr, active_path, history_path = sys.argv[1:]
        meta = api(f'repos/{repo}/pulls/{pr}')
        head = meta['head']['sha']
        if not re.fullmatch(r'[0-9a-f]{40}', head):
            raise ValueError('PR head unavailable')
        pages = api(f'repos/{repo}/pulls/{pr}/files?per_page=100', '--paginate', '--slurp')
        count = meta['changed_files']
        if type(count) is not int or count < 0 or not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
            raise ValueError('changed-file inventory count or pages unavailable')
        files = [entry for page in pages for entry in page]
        if len(files) != count:
            raise ValueError('changed-file inventory incomplete (returned ' + str(len(files)) + ', expected ' + str(count) + ')')
        names = [entry['filename'] for entry in files]
        if any(not isinstance(name, str) or not name for name in names) or len(set(names)) != len(names):
            raise ValueError('changed-file inventory malformed or duplicate')
        changed = [name for page in pages for f in page for name in [f['filename'], f.get('previous_filename', '')] if name]
        touched = {name for page in pages for f in page if f['status'] != 'modified'
                   for name in [f['filename'], f.get('previous_filename', '')]}
        with open(history_path) as source:
            seen = set(source.read().splitlines())
        extra = []
        with open(active_path) as source:
            for line in source:
                if not line.strip():
                    continue
                ident, path, name = line.rstrip('\n').split('\t', 2)
                # GitHub-generated Dependabot graph jobs use event=dynamic, not a repository PR declaration.
                # Primary docs: /en/code-security/concepts/supply-chain-security/dependabot-on-actions
                if path == 'dynamic/dependabot/update-graph':
                    continue
                if ident in seen or path in touched or name == 'Vercel':
                    continue
                content = api(f'repos/{repo}/contents/{path}', '-X', 'GET', '-f', f'ref={head}')
                text = base64.b64decode(content['content'], validate=False).decode('utf-8')
                if requires_pr(text, changed, meta['base']['ref']):
                    extra.append(path + '\t' + name)
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        print('required workflows: UNKNOWN — ' + str(error), file=sys.stderr)
        return 2
    for row in extra:
        print(row)
    return 0


if __name__ == '__main__':
    sys.exit(main())
