#!/usr/bin/env python3
"""Real jj operation-head and placeholder regression tests; all state is temporary."""
from pathlib import Path
import os
import subprocess
import tempfile

collector = Path(__file__).resolve().parents[1] / 'collect-jj-events.sh'
with tempfile.TemporaryDirectory(prefix='jj-collector-boundaries-') as temp:
    root = Path(temp)
    repo = root / 'repo'
    subprocess.run(['jj', 'git', 'init', '--colocate', str(repo)], check=True, capture_output=True)

    def jj(*args):
        return subprocess.check_output(['jj', *args], cwd=repo, text=True, stderr=subprocess.DEVNULL).strip()

    jj('config', 'set', '--repo', 'user.email', 'collector@example.invalid')
    jj('new')  # New working copy has the test author.
    calls = root / 'calls'
    cli = root / 'cli'
    cli.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$TEST_CALLS"\n')
    cli.chmod(0o700)
    env = dict(os.environ, CONTEXT_SYNAPSE_BIN=str(cli),
               CONTEXT_SYNAPSE_HOME=str(root / 'home'), TEST_CALLS=str(calls))
    state = root / 'state'

    def poll(*args):
        return subprocess.run(['bash', str(collector), str(repo), str(state), *args],
                              env=env, capture_output=True, text=True)

    assert poll('--initialize').returncode == 0
    jj('new')
    placeholder = jj('--ignore-working-copy', '--at-op', '@', 'log', '-r', '@-',
                     '--no-graph', '-T', 'change_id')
    jj('new')
    assert poll().returncode == 0
    assert not calls.exists(), 'Empty undescribed placeholders must not be recorded'
    jj('edit', placeholder)
    (repo / 'work.txt').write_text('real fixture work\n')
    jj('commit', '-m', 'fixture work')
    assert poll().returncode == 0
    assert len(calls.read_text().splitlines()) == 1, 'Previously empty change must remain eligible'
    assert poll().returncode == 0
    assert len(calls.read_text().splitlines()) == 1
    print('PASS: empty undescribed changes excluded, same change recorded after receiving content')

    base = jj('--ignore-working-copy', '--at-op', '@', 'op', 'log', '-n', '1',
              '--no-graph', '-T', 'id')
    jj('--at-op', base, 'new', '-m', 'operation branch one')
    jj('--at-op', base, 'new', '-m', 'operation branch two')
    head_dir = repo / '.jj/repo/op_heads/heads'
    op_dir = repo / '.jj/repo/op_store/operations'
    assert head_dir.is_dir() and op_dir.is_dir(), 'Unsupported jj store layout; no passing result'
    heads_before = {p.name: p.read_bytes() for p in head_dir.iterdir() if p.is_file()}
    ops_before = {p.name for p in op_dir.iterdir() if p.is_file()}
    assert len(heads_before) == 2, 'Probe invalid: divergence was not created'
    seen_before = (state / 'seen').read_bytes()
    calls_before = calls.read_bytes()
    result = poll()
    assert result.returncode != 0, 'Diverged heads must fail the poll'
    heads_after = {p.name: p.read_bytes() for p in head_dir.iterdir() if p.is_file()}
    ops_after = {p.name for p in op_dir.iterdir() if p.is_file()}
    assert heads_after == heads_before, 'Poll changed operation heads'
    assert ops_after == ops_before, 'Poll wrote an operation'
    assert (state / 'seen').read_bytes() == seen_before
    assert calls.read_bytes() == calls_before
    assert not (state / 'lock').exists(), 'Normal failed poll must release its lock'
    print(f'PASS: genuinely divergent heads retained ({len(heads_after)}); operation count unchanged '
          f'({len(ops_after)}); no event or seen write')
