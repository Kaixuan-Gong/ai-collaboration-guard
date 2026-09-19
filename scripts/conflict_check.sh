#!/usr/bin/env bash
# Only compares committed snapshots; never checks out files or runs project tests.
# 0=CLEAN, 1=CONFLICT, 2=UNKNOWN/LIMITED. Requires Python 3 and Git >=2.38.
exec python3 - "$@" <<'PY'
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

class Unknown(Exception):
    pass

def main():
    if len(sys.argv) != 3:
        raise Unknown('用法：conflict_check.sh <base-ref> <head-ref>')
    git_exe = shutil.which('git')
    if not git_exe:
        raise Unknown('找不到 Git')
    source = pathlib.Path.cwd()
    with tempfile.TemporaryDirectory(prefix='collaboration-conflict-') as tmp:
        tmp = pathlib.Path(tmp)
        home = tmp / 'home'
        home.mkdir()
        templates = tmp / 'empty-templates'
        templates.mkdir()
        # No inherited GIT_DIR/INDEX/CONFIG_COUNT/CONFIG_PARAMETERS, global drivers,
        # hooks, templates, credential helpers or arbitrary repository environment.
        env = {
            'PATH': os.environ.get('PATH', os.defpath),
            'HOME': str(home), 'XDG_CONFIG_HOME': str(home),
            'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_SYSTEM': os.devnull,
            'GIT_CONFIG_NOSYSTEM': '1', 'GIT_OPTIONAL_LOCKS': '0',
            'GIT_TEMPLATE_DIR': str(templates), 'GIT_TERMINAL_PROMPT': '0',
            'LC_ALL': 'C',
        }
        for key in ('SYSTEMROOT', 'WINDIR'):
            if key in os.environ:
                env[key] = os.environ[key]
        def run(args, cwd=source, codes=(0,)):
            result = subprocess.run(
                [git_exe, '-c', 'core.hooksPath=' + os.devnull,
                 '-c', 'core.fsmonitor=false', '-c', 'maintenance.auto=false', *args],
                cwd=cwd, env=env, capture_output=True, timeout=60)
            if result.returncode not in codes:
                raise Unknown('Git 查询/试合失败（exit=%s）：%s' %
                              (result.returncode, result.stderr.decode('utf-8', 'replace')[:400]))
            return result
        def text(args, cwd=source):
            return run(args, cwd).stdout.decode('utf-8', 'strict').strip()
        if text(['rev-parse', '--is-inside-work-tree']) != 'true':
            raise Unknown('当前目录不是 Git 工作区')
        repo = pathlib.Path(text(['rev-parse', '--show-toplevel']))
        version = text(['--version'])
        match = re.search(r'(\d+)\.(\d+)', version)
        if not match or tuple(map(int, match.groups())) < (2, 38):
            raise Unknown('Git 需要 >=2.38；不使用会运行过滤器的 checkout 降级')
        def resolve(ref):
            return text(['rev-parse', '--verify', '--end-of-options', ref + '^{commit}'])
        base, head = resolve(sys.argv[1]), resolve(sys.argv[2])
        print('BASE_SHA: ' + base)
        print('HEAD_SHA: ' + head)
        source_head = resolve('HEAD')
        index = pathlib.Path(text(['rev-parse', '--git-path', 'index']))
        if not index.is_absolute():
            index = source / index
        index_before = index.read_bytes() if index.exists() else None
        preview = tmp / 'preview'
        run(['clone', '--quiet', '--shared', '--no-checkout', '--template=' + str(templates),
             '--', str(repo), str(preview)])
        # Check committed attributes, including nested files and merge bases, not
        # merely the user's current top-level working-copy .gitattributes.
        bases = text(['merge-base', '--all', base, head], preview).splitlines()
        for sha in set([base, head, *bases]):
            names = run(['ls-tree', '-r', '-z', '--name-only', sha], preview).stdout.split(b'\0')
            for name in names:
                if name and name.split(b'/')[-1] == b'.gitattributes':
                    path = os.fsdecode(name)
                    attributes = run(['show', sha + ':' + path], preview).stdout
                    for line in attributes.splitlines():
                        if not line.lstrip().startswith(b'#') and re.search(rb'\bmerge\s*=', line):
                            print('RESULT: LIMITED（存在 merge 属性；未执行自定义合并策略，不能判定通过）')
                            return 2
        common = pathlib.Path(text(['rev-parse', '--git-common-dir']))
        if not common.is_absolute():
            common = source / common
        info_attrs = common / 'info' / 'attributes'
        if info_attrs.exists() and info_attrs.read_bytes().strip():
            print('RESULT: LIMITED（源仓库有本地属性覆盖，隔离预演未加载它）')
            return 2
        # Let Git calculate all common ancestors. Never force one merge base.
        result = run(['merge-tree', '--write-tree', base, head], preview, (0, 1))
        index_after = index.read_bytes() if index.exists() else None
        if (source_head != resolve('HEAD') or index_before != index_after or
                base != resolve(sys.argv[1]) or head != resolve(sys.argv[2])):
            raise Unknown('检查期间源 HEAD/index 或 base/head 改变，结果已过期')
        print(result.stdout.decode('utf-8', 'replace').strip())
        print('SOURCE_STATE: unchanged')
        if result.returncode == 1:
            print('RESULT: CONFLICT（文本合并冲突；未修改你的工作区）')
            return 1
        print('RESULT: CLEAN（仅标准 Git 文本合并通过，不代表业务逻辑、测试或审批通过）')
        print('SCOPE: committed snapshots; global attributes and custom strategies are not loaded')
        return 0

try:
    sys.exit(main())
except (Unknown, OSError, ValueError, subprocess.TimeoutExpired) as exc:
    print('RESULT: UNKNOWN（%s）' % exc)
    sys.exit(2)
PY
