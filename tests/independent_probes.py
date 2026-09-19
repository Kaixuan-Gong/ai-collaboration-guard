"""Independent acceptance probes. Operates only in disposable local Git fixtures."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]).resolve()
real_git = shutil.which('git')
real_bash = shutil.which('bash')
if not real_git or not real_bash:
    raise SystemExit('Git and Bash are required')
failures = []

def check(name, condition, details=''):
    print(('PASS' if condition else 'FAIL') + ': ' + name)
    if not condition:
        print(details[-2500:])
        failures.append(name)

with tempfile.TemporaryDirectory(prefix='collab-independent-') as temp:
    root = pathlib.Path(temp)
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('GIT_', 'GH_')):
            del env[key]
    env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull,
               GIT_CONFIG_NOSYSTEM='1', GIT_TERMINAL_PROMPT='0',
               GIT_AUTHOR_NAME='Fixture', GIT_COMMITTER_NAME='Fixture',
               GIT_AUTHOR_EMAIL='fixture@example.invalid', GIT_COMMITTER_EMAIL='fixture@example.invalid')
    empty = root / 'empty-template'
    empty.mkdir()
    env['GIT_TEMPLATE_DIR'] = str(empty)
    scripts = root / 'snapshot'
    shutil.copytree(source / 'scripts', scripts)
    fakebin = root / 'bin'
    fakebin.mkdir()
    gh = fakebin / 'gh'
    gh.write_text('#!/bin/sh\nexit 127\n', encoding='utf-8')
    gh.chmod(0o755)
    env['PATH'] = str(fakebin) + os.pathsep + env['PATH']

    def git(*args, cwd=None, accept=(0,)):
        out = subprocess.run([real_git, *args], cwd=cwd or root, env=env,
                             text=True, capture_output=True, timeout=30)
        if out.returncode not in accept:
            raise RuntimeError(f'Fixture failed: git {args}: {out.stderr}')
        return out.stdout.strip()

    def script(name, *args, cwd, extra_env=None):
        e = env.copy()
        e.update(extra_env or {})
        return subprocess.run([real_bash, str(scripts / name), *args],
                              cwd=cwd, env=e, text=True, capture_output=True, timeout=30)

    remote = root / 'remote.git'
    work = root / 'work'
    git('init', '--bare', '-b', 'main', str(remote))
    git('init', '-b', 'main', str(work))
    (work / 'note.txt').write_text('baseline\n', encoding='utf-8')
    git('add', '--', 'note.txt', cwd=work)
    git('commit', '-m', 'baseline', cwd=work)
    git('remote', 'add', 'origin', str(remote), cwd=work)
    git('push', '-u', 'origin', 'main', cwd=work)
    git('remote', 'set-head', 'origin', 'main', cwd=work)

    out = script('remote_check.sh', '--base', 'origin/main', cwd=work)
    check('Missing authenticated PR capability cannot report overall OK',
          out.returncode == 2 and 'STATUS: UNKNOWN' in out.stdout and 'STATUS: OK' not in out.stdout,
          f'exit={out.returncode}\n{out.stdout}\n{out.stderr}')

    out = script('preflight.sh', '--help', 'unexpected', cwd=work)
    check('Preflight rejects excess arguments even after --help', out.returncode == 2,
          f'exit={out.returncode}\n{out.stdout}')

    git('switch', '-c', 'topic', cwd=work)
    git('push', '-u', 'origin', 'topic', cwd=work)
    git('update-ref', '-d', 'refs/heads/topic', cwd=remote)
    before = git('rev-parse', 'HEAD', cwd=work)
    out = script('safe_sync.sh', cwd=work)
    check('Deleted remote branch with stale local tracking ref is not synchronized',
          out.returncode != 0 and '同步完成' not in out.stdout,
          f'exit={out.returncode}\n{out.stdout}\n{out.stderr}')
    check('Deleted-ref check preserves HEAD', before == git('rev-parse', 'HEAD', cwd=work))

    git('switch', 'main', cwd=work)
    wrapper = fakebin / 'git'
    wrapper.write_text('#!/usr/bin/env python3\nimport os,sys\n'
                       'if "status" in sys.argv[1:]: sys.exit(77)\n'
                       f'os.execv({real_git!r}, [{real_git!r}] + sys.argv[1:])\n', encoding='utf-8')
    wrapper.chmod(0o755)
    before = git('rev-parse', 'HEAD', cwd=work)
    before_note = (work / 'note.txt').read_bytes()
    index = work / '.git' / 'index'
    index_before = index.read_bytes()
    for name in ('safe_sync.sh', 'preflight.sh'):
        out = script(name, cwd=work)
        check(name + ' refuses git status failure', out.returncode == 2,
              f'exit={out.returncode}\n{out.stdout}\n{out.stderr}')
    check('Failed status checks preserve HEAD, file bytes and index bytes',
          before == git('rev-parse', 'HEAD', cwd=work)
          and before_note == (work / 'note.txt').read_bytes()
          and index_before == index.read_bytes())

    wrapper.unlink()
    git('remote', 'set-url', 'origin', 'https://github.com/fixture/example.repo.git', cwd=work)
    git('config', 'url.' + str(remote) + '.insteadOf', 'https://github.com/fixture/example.repo.git', cwd=work)
    gh.write_text('#!/bin/sh\nexit 0\n', encoding='utf-8')
    out = script('remote_check.sh', '--base', 'origin/main', cwd=work)
    check('Empty successful API stdout remains UNKNOWN rather than empty PR list',
          out.returncode == 2 and 'STATUS: UNKNOWN' in out.stdout, out.stdout)
    gh.write_text('#!/bin/sh\nif [ "$1" = api ]; then printf "[]"; fi\nexit 0\n', encoding='utf-8')
    out = script('remote_check.sh', '--base', 'origin/main', cwd=work)
    check('Valid empty PR array and dotted repository URL are accepted',
          out.returncode == 0 and 'PR_STATUS: none' in out.stdout, out.stdout)

    # A failure specifically at the second pre-merge status read must stop.
    other = root / 'other'
    git('clone', str(remote), str(other))
    (other / 'second.txt').write_text('remote update\n', encoding='utf-8')
    git('add', '--', 'second.txt', cwd=other)
    git('commit', '-m', 'remote advance', cwd=other)
    git('push', 'origin', 'main', cwd=other)
    counter = root / 'status-count'
    wrapper.write_text('#!/usr/bin/env python3\nimport os,sys,pathlib\n'
                      f'p=pathlib.Path({str(counter)!r})\n'
                      'if "status" in sys.argv[1:]:\n'
                      ' n=int(p.read_text())+1 if p.exists() else 1\n'
                      ' p.write_text(str(n))\n'
                      ' if n==2: sys.exit(77)\n'
                      f'os.execv({real_git!r}, [{real_git!r}] + sys.argv[1:])\n', encoding='utf-8')
    wrapper.chmod(0o755)
    before = git('rev-parse', 'HEAD', cwd=work)
    out = script('safe_sync.sh', cwd=work)
    check('Second status failure cannot merge a remote commit',
          out.returncode == 2 and before == git('rev-parse', 'HEAD', cwd=work), out.stdout)
    wrapper.unlink()
    git('switch', '-c', 'left', cwd=work)
    (work / 'note.txt').write_text('left\n', encoding='utf-8')
    git('add', '--', 'note.txt', cwd=work)
    git('commit', '-m', 'left', cwd=work)
    git('switch', '-c', 'right', 'main', cwd=work)
    (work / 'note.txt').write_text('right\n', encoding='utf-8')
    git('add', '--', 'note.txt', cwd=work)
    git('commit', '-m', 'right', cwd=work)
    sentinel = root / 'merge-driver-must-not-run'
    injected = {'GIT_CONFIG_COUNT': '2', 'GIT_CONFIG_KEY_0': 'merge.default',
                'GIT_CONFIG_VALUE_0': 'probe', 'GIT_CONFIG_KEY_1': 'merge.probe.driver',
                'GIT_CONFIG_VALUE_1': 'touch ' + str(sentinel)}
    out = script('conflict_check.sh', 'left', 'right', cwd=work, extra_env=injected)
    check('Environment-injected merge driver is not executed; real conflict remains',
          out.returncode == 1 and not sentinel.exists() and 'RESULT: CONFLICT' in out.stdout,
          out.stdout + out.stderr)
    (work / 'nested').mkdir()
    (work / 'nested' / '.gitattributes').write_text('*.txt merge=probe\n', encoding='utf-8')
    git('add', '--', 'nested/.gitattributes', cwd=work)
    git('commit', '-m', 'nested attributes', cwd=work)
    out = script('conflict_check.sh', 'main', 'right', cwd=work, extra_env=injected)
    check('Committed nested custom merge attributes are LIMITED and nonzero',
          out.returncode == 2 and 'RESULT: LIMITED' in out.stdout and not sentinel.exists(), out.stdout)

print(f'Independent probes: {len(failures)} failure(s)')
sys.exit(bool(failures))
