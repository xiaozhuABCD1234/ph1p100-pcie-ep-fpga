#!/usr/bin/env python
"""T01.tool-A controlled experiment runner for the DDR1333 IpTool generation entry.

Every attempt runs in a fresh, private copy of the frozen 190248 preparation package
(created by `new-dir`, with all occurrences of the frozen directory name mechanically
re-targeted to the new directory and round-trip verified). Records for every attempt:

  argv, cwd, pid, started/ended, timeout_seconds, exit_code, timed_out, killed pids,
  stdout/stderr (file + bytes + sha256), monitor.jsonl samples (process tree, CPU,
  windows, output file growth), artifact list (relpath + bytes + sha256), input
  before/after diff, installation/validation/temp tree before/after diff, process
  state of IpTool/td before/after.

Hard rules enforced in code:
  * never delete files or directories; never write outside the experiment directory;
  * every attempt gets its own fresh directory (mkdir exist_ok=False);
  * timeouts really kill the process tree (taskkill /T /F + Stop-Process leftovers);
  * export path must stay inside the experiment directory (unless --raw is used).

Subcommands:
  new-dir    create D:/TD/work/csi2/_validation/ddr1333_cli_<YYYYmmdd_HHMMSS>[_N]
  run        run one IpTool attempt inside an experiment dir, recording everything
  gui-probe  start the private-copy GUI launcher, record window/process evidence,
             take a screenshot, then kill the tree (no clicks; Generate not pressed)
  verify     parameter/pin/artifact checks of a generated instance (success branch)
  list       summarize attempt status of an experiment dir
"""
from __future__ import annotations

import argparse
import ctypes
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path

VALIDATION = Path('D:/TD/work/csi2/_validation')
FROZEN = VALIDATION / 'ddr1333_ip_20261015_190248'
FROZEN_NAME = 'ddr1333_ip_20261015_190248'
FROZEN_MANIFEST_SHA = 'a94f894870c2c065c316c2679d64bdc5b48622ca751bc8cba77ad9224679bd64'
IPTOOL = 'D:/downlaod/bin/IpTool.exe'
TD_CLI = 'D:/downlaod/bin/td_commands_prompt.exe'
TD_ROOT = 'D:/downlaod'
DEVICE = 'PH1P100SBG484'
DEFAULT_COMP = 'ddrmc_1333'
GOLDEN_ADC = Path('D:/TD/work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/golden_adc/ap115v2_ddr3_x32.adc')
INSTALL_ANCHORS = {
    'D:/downlaod/bin/IpTool.exe':
        'DA9E765EE1AF39594BC546224BA79CF84EAD5700C7BDDFE4A6FCC7BF95A3DE46',
    'D:/downlaod/bin/td_commands_prompt.exe':
        '79EC56674F8F7B889E25E11BDCA91F7D64C24BA0DE99E80680248F00B4F87190',
    'D:/downlaod/ip/depot/MIS_DDRF6F1D0P0_1.2/Component.xml':
        'FEB4F5BC5771CF9B8F816296754AB0BA9088CA9FFAFC9F001F9C1C50CBD5E543',
    'D:/downlaod/ip/depot/MIS_DDRF6F1D0P0_1.2/Dependency.tcl':
        'CD927834C559A6962E97159AE0C01CCA666C9E66B6C2CBBC7BCECB4C0B119623',
}
SKIP_FROM_FROZEN = ['preparation.json', 'preparation_manifest.json', 'binding_preflight.log']


def now_iso() -> str:
    return datetime.datetime.now().isoformat()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(p: Path) -> str:
    return sha256_bytes(p.read_bytes())


def write_json(p: Path, obj) -> None:
    p.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def ps_json(script: str, timeout: int = 60):
    wrapped = ("[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; "
               "$ErrorActionPreference='SilentlyContinue';\n" + script)
    r = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', wrapped],
                       capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
    text = r.stdout.decode('utf-8', errors='replace').strip()
    if not text:
        return None
    return json.loads(text)


def process_list():
    return ps_json("Get-Process IpTool,td -ErrorAction SilentlyContinue | "
                   "Select-Object Id,ProcessName,CPU,StartTime | ConvertTo-Json -Compress") or []


def scan_tree(root: Path, exclude_prefixes=()) -> dict:
    out = {}
    root = Path(root)
    if not root.exists():
        return out
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = Path(dirpath).relative_to(root)
        dirnames[:] = [d for d in dirnames
                       if not any(str(rel_dir / d).startswith(e) for e in exclude_prefixes)]
        for name in filenames:
            rel = rel_dir / name
            if any(str(rel).startswith(e) for e in exclude_prefixes):
                continue
            st = (Path(dirpath) / name).stat()
            out[str(rel).replace('\\', '/')] = [st.st_size, st.st_mtime_ns]
    return out


def listing_digest(entries: dict) -> str:
    lines = [f'{k}\t{v[0]}\t{v[1]}\n' for k, v in sorted(entries.items())]
    return sha256_bytes(''.join(lines).encode('utf-8'))


def temp_scan() -> dict:
    tmp = Path(os.environ.get('TEMP', 'C:/Users/czz/AppData/Local/Temp'))
    return scan_tree(tmp)


def anchors_now() -> dict:
    result = {}
    for p, expected in INSTALL_ANCHORS.items():
        path = Path(p)
        actual = sha256_file(path).upper() if path.exists() else 'MISSING'
        result[p] = {'sha256': actual, 'unchanged': actual == expected}
    return result


def env_snapshot(exp: Path) -> dict:
    snap = {
        'taken_at': now_iso(),
        'install_bin': scan_tree(Path('D:/downlaod/bin')),
        'install_depot': scan_tree(Path('D:/downlaod/ip/depot')),
        'validation_root': scan_tree(VALIDATION, exclude_prefixes=(exp.name,)),
        'test_tree': scan_tree(Path('D:/TD/work/test')),
        'temp': temp_scan(),
        'anchors': anchors_now(),
    }
    return snap


def env_diff(before: dict, after: dict) -> dict:
    result = {}
    for key in ('install_bin', 'install_depot', 'validation_root', 'test_tree', 'temp'):
        b, a = before[key], after[key]
        added = sorted(set(a) - set(b))
        removed = sorted(set(b) - set(a))
        changed = sorted(k for k in set(a) & set(b) if a[k] != b[k])
        result[key] = {
            'before_count': len(b), 'after_count': len(a),
            'before_listing_sha256': listing_digest(b),
            'after_listing_sha256': listing_digest(a),
            'added': added[:200], 'added_total': len(added),
            'removed': removed[:200], 'removed_total': len(removed),
            'changed': changed[:200], 'changed_total': len(changed),
        }
    result['anchors_after'] = after['anchors']
    return result


# ---------------------------------------------------------------- new-dir

def cmd_new_dir(args) -> None:
    manifest = json.loads((FROZEN / 'preparation_manifest.json').read_bytes())
    assert sha256_file(FROZEN / 'preparation_manifest.json') == FROZEN_MANIFEST_SHA, 'frozen manifest sha mismatch'
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    name = f'ddr1333_cli_{ts}' + (f'_{args.suffix}' if args.suffix is not None else '')
    out = VALIDATION / name
    out.mkdir(parents=True, exist_ok=False)
    assert out.is_dir() and out.name.startswith('ddr1333_cli_')
    retargeted = []
    copied = {}
    for rel, frozen_sha in sorted(manifest.items()):
        if rel in SKIP_FROM_FROZEN:
            continue
        src = FROZEN / rel
        data = src.read_bytes()
        assert sha256_bytes(data) == frozen_sha, rel
        if FROZEN_NAME in rel or FROZEN_NAME.encode() in data:
            new_data = data.replace(FROZEN_NAME.encode(), name.encode())
            assert new_data.replace(name.encode(), FROZEN_NAME.encode()) == data, rel
            retargeted.append({'path': rel, 'occurrences': data.count(FROZEN_NAME.encode()),
                               'frozen_sha256': frozen_sha, 'retargeted_sha256': sha256_bytes(new_data)})
        else:
            new_data = data
        dest = out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(new_data)
        copied[rel] = sha256_bytes(new_data)
    (out / 'output').mkdir(exist_ok=True)
    (out / '_retained').mkdir(exist_ok=True)
    (out / 'attempts').mkdir(exist_ok=True)
    extra_sources = []
    for src in (args.extra_source or []):
        srcp = Path(src)
        assert srcp.is_dir(), src
        dest = out / 'source' / srcp.name
        if dest.exists():
            dest = out / 'source' / (srcp.name + '_extra')
        assert not dest.exists(), dest
        count = 0
        for pth in sorted(srcp.rglob('*')):
            assert not (getattr(pth.lstat(), 'st_file_attributes', 0) & 0x400), pth
            if pth.is_file():
                q = dest / pth.relative_to(srcp)
                q.parent.mkdir(parents=True, exist_ok=True)
                q.write_bytes(pth.read_bytes())
                assert sha256_file(q) == sha256_file(pth), pth
                count += 1
        extra_sources.append({'from': srcp.as_posix(), 'to': dest.relative_to(out).as_posix(),
                              'files': count, 'policy': 'read-only byte-identical copy, no edits'})
    variants = []
    if args.plain_depot:
        guard = (out / 'manual_binding_guard.tcl').as_posix()
        marker = f'source {{{guard}}}\n'.encode()
        touched = []
        for rel in ('depot/Dependency.tcl',
                    'depot/PH1P_DDRMC_IP/Other/plugin_end.tcl',
                    'depot/PH1P_DDRPHY_IP/Other/plugin_end.tcl'):
            p = out / rel
            data = p.read_bytes()
            assert marker in data, rel
            new = data.replace(marker, b'')
            p.write_bytes(new)
            copied[rel] = sha256_bytes(new)
            touched.append({'path': rel, 'before_sha256': sha256_bytes(data),
                            'after_sha256': sha256_bytes(new), 'removed_guard_sources': 1})
        variants.append({
            'kind': 'strip_manual_binding_guard_sources',
            'rule': 'remove exactly the prepended "source {<dir>/manual_binding_guard.tcl}" line; no other bytes changed',
            'files': touched,
        })
    record = {
        'schema': 1,
        'created_at': now_iso(),
        'experiment_dir': out.as_posix(),
        'frozen_source': FROZEN.as_posix(),
        'frozen_manifest_sha256': FROZEN_MANIFEST_SHA,
        'frozen_entries': len(manifest),
        'copied_files': len(copied),
        'retarget': {
            'from': FROZEN_NAME, 'to': name,
            'rule': 'exact ASCII substring replace in copied bytes; round-trip verified',
            'files': retargeted,
        },
        'runner': 'tools/td/run_ddr1333_ipgen.py',
        'variants': variants,
        'extra_sources': extra_sources,
        'entry_status_note': ('The real IpTool generation-entry state is established only by the attempts '
                              'recorded under attempts/ of this directory and summarized in '
                              'docs/evidence/ddr1333_iptool_cli_<date>.json. No inferred status is recorded here.'),
        'hardware_download': False,
    }
    write_json(out / 'experiment.json', record)
    files = {p.relative_to(out).as_posix(): sha256_file(p)
             for p in sorted(out.rglob('*')) if p.is_file()}
    write_json(out / 'experiment_manifest.json',
               {'created_at': now_iso(), 'files': files})
    print(out.as_posix())
    print(f'copied={len(copied)} retargeted={len(retargeted)}')


# ---------------------------------------------------------------- run

def assert_exp_dir(exp: Path) -> None:
    exp = Path(exp)
    assert exp.is_dir(), exp
    assert exp.parent == VALIDATION, exp
    assert exp.name.startswith('ddr1333_cli_'), exp
    assert (exp / 'experiment.json').is_file(), 'not a runner-created experiment dir'


def verify_inputs(exp: Path) -> dict:
    man = json.loads((exp / 'experiment_manifest.json').read_bytes())
    recorded = man['files']
    current = {}
    for rel in recorded:
        p = exp / rel
        current[rel] = sha256_file(p) if p.is_file() else 'MISSING'
    changed = sorted(r for r in recorded if current[r] != recorded[r])
    # new files created anywhere below depot/source after preparation
    extras = []
    for sub in ('depot', 'source'):
        for p in sorted((exp / sub).rglob('*')):
            if p.is_file():
                rel = p.relative_to(exp).as_posix()
                if rel not in recorded:
                    extras.append(rel)
    return {'recorded': len(recorded), 'changed': changed, 'new_under_inputs': extras}


def build_tree_sample(root_pid: int):
    script = f'''
$all = Get-CimInstance Win32_Process
$tree = @()
$frontier = @({root_pid})
while ($frontier.Count -gt 0) {{
    $next = @()
    foreach ($p in $frontier) {{
        $kids = @($all | Where-Object {{ $_.ParentProcessId -eq $p }})
        foreach ($k in $kids) {{
            $tree += [pscustomobject]@{{pid=$k.ProcessId; ppid=$k.ParentProcessId; name=$k.Name; cmd=$k.CommandLine}}
            $next += $k.ProcessId
        }}
    }}
    $frontier = $next
}}
$cpu = @()
foreach ($t in $tree) {{
    $g = Get-Process -Id $t.pid -ErrorAction SilentlyContinue
    if ($g) {{ $cpu += [pscustomobject]@{{pid=$g.Id; cpu=$g.CPU; ws=$g.WorkingSet64}} }}
}}
$rootProc = Get-Process -Id {root_pid} -ErrorAction SilentlyContinue
[pscustomobject]@{{
    tree=@($tree); cpu=@($cpu);
    rootAlive=[bool]$rootProc; rootCpu=$rootProc.CPU; rootWs=$rootProc.WorkingSet64
}} | ConvertTo-Json -Depth 6 -Compress
'''
    try:
        return ps_json(script, timeout=30)
    except Exception as e:  # monitoring must never abort the attempt
        return {'error': repr(e)}


user32 = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

_kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
_kernel32.CreateToolhelp32Snapshot.restype = ctypes.c_void_p
_kernel32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
_kernel32.Process32First.restype = wintypes.BOOL
_kernel32.Process32First.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
_kernel32.Process32Next.restype = wintypes.BOOL
_kernel32.Process32Next.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
_kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
_kernel32.FreeConsole.restype = wintypes.BOOL
_kernel32.AttachConsole.restype = wintypes.BOOL
_kernel32.AttachConsole.argtypes = [wintypes.DWORD]
_kernel32.CreateFileW.restype = ctypes.c_void_p
_kernel32.CreateFileW.argtypes = [ctypes.c_wchar_p, wintypes.DWORD, wintypes.DWORD,
                                  ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p]
_kernel32.GetConsoleScreenBufferInfo.restype = wintypes.BOOL
_kernel32.ReadConsoleOutputCharacterW.restype = wintypes.BOOL

TH32CS_SNAPPROCESS = 0x2


class PROCESSENTRY32(ctypes.Structure):
    _fields_ = [
        ('dwSize', wintypes.DWORD), ('cntUsage', wintypes.DWORD), ('th32ProcessID', wintypes.DWORD),
        ('th32DefaultHeapID', ctypes.c_void_p), ('th32ModuleID', wintypes.DWORD),
        ('cntThreads', wintypes.DWORD), ('th32ParentProcessID', wintypes.DWORD),
        ('pcPriClassBase', ctypes.c_long), ('dwFlags', wintypes.DWORD),
        ('szExeFile', ctypes.c_char * 260),
    ]


class _COORD(ctypes.Structure):
    _fields_ = [('X', ctypes.c_short), ('Y', ctypes.c_short)]


class _SMALL_RECT(ctypes.Structure):
    _fields_ = [('Left', ctypes.c_short), ('Top', ctypes.c_short),
                ('Right', ctypes.c_short), ('Bottom', ctypes.c_short)]


class _CSBI(ctypes.Structure):
    _fields_ = [('dwSize', _COORD), ('dwCursorPosition', _COORD), ('wAttributes', ctypes.c_ushort),
                ('srWindow', _SMALL_RECT), ('dwMaximumWindowSize', _COORD)]


def process_snapshot() -> dict:
    """pid -> {ppid, name} using Toolhelp32 (fast, no subprocess)."""
    result = {}
    snap = _kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if not snap or snap == ctypes.c_void_p(-1).value:
        return result
    try:
        entry = PROCESSENTRY32()
        entry.dwSize = ctypes.sizeof(PROCESSENTRY32)
        ok = _kernel32.Process32First(snap, ctypes.byref(entry))
        while ok:
            result[entry.th32ProcessID] = {'ppid': entry.th32ParentProcessID,
                                           'name': entry.szExeFile.decode('latin1')}
            ok = _kernel32.Process32Next(snap, ctypes.byref(entry))
    finally:
        _kernel32.CloseHandle(snap)
    return result


def read_console_text(pid: int):
    """Attach to the target pid's console and dump its screen buffer text. Returns str or None."""
    if not _kernel32.FreeConsole():
        pass  # no console attached to us: fine
    if not _kernel32.AttachConsole(pid):
        return None
    try:
        h = _kernel32.CreateFileW('CONOUT$', 0x80000000 | 0x40000000, 0x3, None, 3, 0, None)
        if not h or h == ctypes.c_void_p(-1).value:
            return None
        try:
            csbi = _CSBI()
            if not _kernel32.GetConsoleScreenBufferInfo(ctypes.c_void_p(h), ctypes.byref(csbi)):
                return None
            width = max(1, csbi.dwSize.X)
            height = max(1, csbi.dwSize.Y)
            buf = ctypes.create_unicode_buffer(width * height + 1)
            n = wintypes.DWORD(0)
            ok = _kernel32.ReadConsoleOutputCharacterW(ctypes.c_void_p(h), buf, width * height,
                                                       _COORD(0, 0), ctypes.byref(n))
            if not ok:
                return None
            rows = (n.value + width - 1) // width
            lines = []
            for r in range(rows):
                lines.append(''.join(buf[r * width:(r + 1) * width]).rstrip())
            while lines and not lines[-1]:
                lines.pop()
            return '\n'.join(lines)
        finally:
            _kernel32.CloseHandle(ctypes.c_void_p(h))
    finally:
        _kernel32.FreeConsole()


def window_info(hwnd) -> dict:
    length = user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    cls = ctypes.create_unicode_buffer(256)
    user32.GetClassNameW(hwnd, cls, 256)
    wpid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(wpid))
    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return {'pid': wpid.value, 'hwnd': int(hwnd), 'title': buf.value, 'class': cls.value,
            'visible': bool(user32.IsWindowVisible(hwnd)),
            'enabled': bool(user32.IsWindowEnabled(hwnd)),
            'rect': [rect.left, rect.top, rect.right, rect.bottom]}


def window_tree(hwnd) -> list:
    children = []

    def cb(chwnd, lparam):
        children.append(window_info(chwnd))
        return True

    user32.EnumChildWindows(hwnd, WNDENUMPROC(cb), 0)
    children.sort(key=lambda w: (w['class'], w['title']))
    return children


def capture_window(hwnd: int, path: Path) -> None:
    script = f'''
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinShoter {{
  [StructLayout(LayoutKind.Sequential)] public struct RECT {{ public int Left; public int Top; public int Right; public int Bottom; }}
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
}}
"@
$hwnd = [IntPtr]{hwnd}
$r = New-Object WinShoter+RECT
[WinShoter]::GetWindowRect($hwnd, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
if ($w -le 0 -or $h -le 0) {{ "ZERO" }} else {{
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [WinShoter]::PrintWindow($hwnd, $hdc, 2) | Out-Null
  $g.ReleaseHdc($hdc)
  $bmp.Save('{path.as_posix()}', [System.Drawing.Imaging.ImageFormat]::Png)
  "OK"
}}
'''
    subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
                   capture_output=True, timeout=60, stdin=subprocess.DEVNULL)


def windows_for_pids(pids) -> list:
    result = []

    def cb(hwnd, lparam):
        wpid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(wpid))
        if wpid.value in pids:
            length = user32.GetWindowTextLengthW(hwnd)
            buf = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buf, length + 1)
            cls = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, cls, 256)
            result.append({'pid': wpid.value, 'hwnd': int(hwnd), 'title': buf.value,
                           'class': cls.value, 'visible': bool(user32.IsWindowVisible(hwnd))})
        return True

    user32.EnumWindows(WNDENUMPROC(cb), 0)
    return result


def out_stats(exp: Path) -> dict:
    n = 0
    total = 0
    for p in (exp / 'output').rglob('*'):
        if p.is_file():
            n += 1
            total += p.stat().st_size
    return {'files': n, 'bytes': total}


def pids_alive(pids) -> list:
    if not pids:
        return []
    ids = ','.join(str(p) for p in sorted(pids))
    try:
        r = ps_json(f"Get-Process -Id {ids} -ErrorAction SilentlyContinue | Select-Object Id | ConvertTo-Json -Compress", timeout=30)
    except Exception:
        return []
    if r is None:
        return []
    if isinstance(r, dict):
        r = [r]
    return [x['Id'] for x in r]


def kill_tree(root_pid: int) -> dict:
    pids = [root_pid]
    sample = build_tree_sample(root_pid)
    if sample and 'tree' in sample:
        pids += [t['pid'] for t in sample['tree']]
    subprocess.run(['taskkill.exe', '/PID', str(root_pid), '/T', '/F'],
                   capture_output=True, timeout=30, stdin=subprocess.DEVNULL)
    for pid in pids:
        subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command',
                        f'Stop-Process -Id {pid} -Force -ErrorAction SilentlyContinue'],
                       capture_output=True, timeout=30, stdin=subprocess.DEVNULL)
    time.sleep(1.5)
    check = build_tree_sample(root_pid)
    alive = []
    if check and 'rootAlive' in check and check['rootAlive']:
        alive.append(root_pid)
    if check and 'tree' in check:
        alive += [t['pid'] for t in check['tree']]
    return {'killed_pids': sorted(set(pids)), 'alive_after_kill': alive}


def cmd_run(args) -> None:
    exp = Path(args.dir)
    assert_exp_dir(exp)
    assert not (exp / 'attempts' / args.name).exists(), 'attempt name exists; use a fresh name'
    attempt_dir = exp / 'attempts' / args.name
    attempt_dir.mkdir(parents=True, exist_ok=False)

    if args.raw:
        argv = list(args.raw)
    else:
        extra = args.extra or []
        gen = args.gen or (exp / 'depot/Component.xml').as_posix()
        user = args.user or (exp / 'source/ddrmc_x32/ddrmc_x32.xml').as_posix()
        export = args.export or (exp / 'output').as_posix()
        assert Path(export).resolve().is_relative_to(exp.resolve()), 'export path must stay inside experiment dir'
        if args.form == 'default':
            argv = [IPTOOL, TD_ROOT] + extra + ['-gen', gen, '-device', DEVICE,
                                                '-export_to', export, '-comp', args.comp,
                                                '-use_value', args.use_value or 'default']
        else:
            argv = [IPTOOL, TD_ROOT] + extra + ['-user', user, '-gen', gen, '-device', DEVICE,
                                                '-export_to', export, '-comp', args.comp,
                                                '-use_value', args.use_value or 'copy']
    for token in argv:
        assert not any(c in token for c in '\r\n'), token

    inputs_before = verify_inputs(exp)
    assert not inputs_before['changed'], inputs_before
    env_before = env_snapshot(exp)
    procs_before = process_list()

    stdout_path = attempt_dir / 'stdout.log'
    stderr_path = attempt_dir / 'stderr.log'
    monitor_path = attempt_dir / 'monitor.jsonl'
    started = now_iso()
    t0 = time.monotonic()
    with open(stdout_path, 'wb') as fo, open(stderr_path, 'wb') as fe:
        p = subprocess.Popen(argv, cwd=str(exp), stdout=fo, stderr=fe, stdin=subprocess.DEVNULL)
        pid = p.pid
        samples = []
        timed_out = False
        kill_record = None
        last_stats = None
        known_pids = {pid}
        window_union = []
        seen_window_keys = set()
        captured_hwnds = set()
        console_captures = {}
        dialog_captures = []
        child_events = {}
        parent_exit_at = None
        fast_last = -999.0
        post_last = -999.0
        with open(monitor_path, 'a', encoding='utf-8') as fm:
            last_ps = 0.0
            while True:
                rc = p.poll()
                t = time.monotonic() - t0
                if rc is not None and parent_exit_at is None:
                    parent_exit_at = t
                if t - fast_last >= (0.15 if t < 10 else 0.4):
                    fast_last = t
                    try:
                        proc_map = process_snapshot()
                    except Exception:
                        proc_map = {}
                    for k, v in proc_map.items():
                        if k != pid and v['ppid'] in known_pids:
                            known_pids.add(k)
                            child_events.setdefault(k, {'pid': k, 'ppid': v['ppid'], 'name': v['name'],
                                                        'first_seen': now_iso(), 'last_seen': now_iso(),
                                                        'cmdline': None, 'cmdline_attempts': 0,
                                                        'console_samples': []})
                    for k, ev in child_events.items():
                        if k in proc_map:
                            ev['last_seen'] = now_iso()
                            if ev['cmdline'] is None and ev['cmdline_attempts'] < 3:
                                ev['cmdline_attempts'] += 1
                                try:
                                    cmd = ps_json(f'(Get-CimInstance Win32_Process -Filter "ProcessId={k}").CommandLine | ConvertTo-Json -Compress', timeout=20)
                                except Exception:
                                    cmd = None
                                if isinstance(cmd, str) and cmd:
                                    ev['cmdline'] = cmd
                            if len(ev['console_samples']) < 12:
                                try:
                                    text = read_console_text(k)
                                except Exception:
                                    text = None
                                if text:
                                    fp = attempt_dir / f'console_{k}_{len(ev["console_samples"])}.txt'
                                    fp.write_text(text, encoding='utf-8')
                                    ev['console_samples'].append({'file': fp.name, 'bytes': fp.stat().st_size,
                                                                  'sha256': sha256_file(fp), 'at': now_iso()})
                wins = windows_for_pids(known_pids)
                for w in wins:
                    key = (w['pid'], w['hwnd'], w['title'])
                    if key not in seen_window_keys:
                        seen_window_keys.add(key)
                        window_union.append({**w, 'first_seen_at': now_iso(),
                                             'elapsed_s': round(t, 1)})
                    is_console = w['class'] == 'ConsoleWindowClass'
                    if w['visible'] and (w['title'] or is_console):
                        if is_console:
                            n = console_captures.get(w['hwnd'], 0)
                            if n < 6:
                                console_captures[w['hwnd']] = n + 1
                                png = attempt_dir / f"console_{w['hwnd']}_{n}.png"
                                try:
                                    capture_window(w['hwnd'], png)
                                    dialog_captures.append({'hwnd': w['hwnd'], 'title': w['title'],
                                                            'class': w['class'], 'elapsed_s': round(t, 1),
                                                            'file': png.name,
                                                            'bytes': png.stat().st_size if png.is_file() else 0})
                                except Exception as e:
                                    dialog_captures.append({'hwnd': w['hwnd'], 'title': w['title'],
                                                            'elapsed_s': round(t, 1), 'error': repr(e)})
                        elif w['hwnd'] not in captured_hwnds:
                            captured_hwnds.add(w['hwnd'])
                            png = attempt_dir / f"win_{w['hwnd']}.png"
                            try:
                                capture_window(w['hwnd'], png)
                                dialog_captures.append({'hwnd': w['hwnd'], 'title': w['title'],
                                                        'class': w['class'], 'elapsed_s': round(t, 1),
                                                        'file': png.name,
                                                        'bytes': png.stat().st_size if png.is_file() else 0})
                            except Exception as e:
                                dialog_captures.append({'hwnd': w['hwnd'], 'title': w['title'],
                                                        'elapsed_s': round(t, 1), 'error': repr(e)})
                stats = out_stats(exp)
                need_ps = (t - last_ps) >= (2.5 if t < 10 else (0.8 if t < 30 else (3.0 if t < 180 else 6.0)))
                if need_ps or rc is not None:
                    last_ps = t
                    sample = build_tree_sample(pid)
                    if sample and 'tree' in sample:
                        known_pids |= {x['pid'] for x in sample['tree']}
                    row = {
                        'at': now_iso(), 'elapsed_s': round(t, 1), 'alive': rc is None,
                        'tree': sample.get('tree', []) if sample else [],
                        'cpu': sample.get('cpu', []) if sample else [],
                        'rootCpu': sample.get('rootCpu') if sample else None,
                        'windows': wins,
                        'output': stats,
                    }
                    samples.append(row)
                    fm.write(json.dumps(row, ensure_ascii=False) + '\n')
                    fm.flush()
                last_stats = stats
                if rc is not None:
                    # parent has exited: keep watching descendants (children may
                    # continue generation/reporting) until they die or the grace ends
                    candidate = known_pids - {pid}
                    if not candidate:
                        break
                    if t >= parent_exit_at + args.post_parent_wait:
                        kill_record = kill_tree(pid)
                        row = {'at': now_iso(), 'elapsed_s': round(t, 1), 'alive': False,
                               'post_parent': True, 'grace_exhausted_kill': kill_record,
                               'windows': wins, 'output': stats}
                        samples.append(row)
                        fm.write(json.dumps(row, ensure_ascii=False) + '\n')
                        fm.flush()
                        break
                    if t - post_last >= 0.9:
                        post_last = t
                        alive = pids_alive(candidate)
                        row = {'at': now_iso(), 'elapsed_s': round(t, 1), 'alive': False,
                               'post_parent': True, 'descendants_alive': alive,
                               'windows': wins, 'output': stats}
                        samples.append(row)
                        fm.write(json.dumps(row, ensure_ascii=False) + '\n')
                        fm.flush()
                        if not alive:
                            break
                elif t >= args.timeout:
                    timed_out = True
                    kill_record = kill_tree(pid)
                    try:
                        rc = p.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        rc = None
                    break
                time.sleep(0.15 if t < 10 else 0.4)
    ended = now_iso()
    duration = round(time.monotonic() - t0, 2)

    inputs_after = verify_inputs(exp)
    env_after = env_snapshot(exp)
    procs_after = process_list()

    artifacts = {}
    for pth in sorted(exp.rglob('*')):
        if pth.is_file():
            rel = pth.relative_to(exp).as_posix()
            if rel.startswith(f'attempts/{args.name}/'):
                continue
            artifacts[rel] = {'bytes': pth.stat().st_size, 'sha256': sha256_file(pth)}

    result = {
        'attempt': args.name,
        'note': args.note or '',
        'argv': argv,
        'cwd': exp.as_posix(),
        'pid': pid,
        'started': started,
        'ended': ended,
        'duration_seconds': duration,
        'timeout_seconds': args.timeout,
        'post_parent_wait_seconds': args.post_parent_wait,
        'exit_code': rc,
        'timed_out': timed_out,
        'kill': kill_record,
        'stdout': {'file': 'stdout.log', 'bytes': stdout_path.stat().st_size,
                   'sha256': sha256_file(stdout_path)},
        'stderr': {'file': 'stderr.log', 'bytes': stderr_path.stat().st_size,
                   'sha256': sha256_file(stderr_path)},
        'monitor_jsonl_sha256': sha256_file(monitor_path),
        'samples': len(samples),
        'output_last': last_stats,
        'windows_seen': window_union,
        'dialog_captures': dialog_captures,
        'child_events': list(child_events.values()),
        'child_processes_seen': sorted({(t['name'], t['cmd']) for s in samples for t in s.get('tree', [])},
                                       key=lambda x: str(x)),
        'processes_before': procs_before,
        'processes_after': procs_after,
        'inputs_before': inputs_before,
        'inputs_after': inputs_after,
        'env_diff': env_diff(env_before, env_after),
        'artifacts': artifacts,
        'hardware_download': False,
    }
    write_json(attempt_dir / 'result.json', result)
    print(json.dumps({'attempt': args.name, 'exit_code': rc, 'timed_out': timed_out,
                      'duration_s': duration, 'output_files': (last_stats or {}).get('files', 0),
                      'output_bytes': (last_stats or {}).get('bytes', 0)}))


# ---------------------------------------------------------------- gui-probe

def cmd_gui_probe(args) -> None:
    exp = Path(args.dir)
    assert_exp_dir(exp)
    attempt_dir = exp / 'attempts' / args.name
    attempt_dir.mkdir(parents=True, exist_ok=False)
    launcher = exp / 'open_ddr1333_gui.cmd'
    assert launcher.is_file(), 'retargeted launcher missing'
    text = launcher.read_text('ascii')
    for token in (exp.as_posix(), (exp / 'depot').as_posix(), (exp / 'output').as_posix()):
        assert token in text, token
    env_before = env_snapshot(exp)
    procs_before = process_list()
    started = now_iso()
    t0 = time.monotonic()
    p = subprocess.Popen(['cmd.exe', '/c', str(launcher)], cwd=str(exp),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         stdin=subprocess.DEVNULL,
                         creationflags=subprocess.CREATE_NEW_CONSOLE)
    pid = p.pid
    samples = []
    with open(attempt_dir / 'monitor.jsonl', 'a', encoding='utf-8') as fm:
        while time.monotonic() - t0 < args.wait:
            sample = build_tree_sample(pid)
            pids = {pid}
            if sample and 'tree' in sample:
                pids |= {x['pid'] for x in sample['tree']}
            wins = windows_for_pids(pids)
            row = {'at': now_iso(), 'elapsed_s': round(time.monotonic() - t0, 1),
                   'tree': sample.get('tree', []) if sample else [], 'windows': wins,
                   'output': out_stats(exp)}
            samples.append(row)
            fm.write(json.dumps(row, ensure_ascii=False) + '\n')
            fm.flush()
            time.sleep(2.5)
    trees = []
    for w in (samples[-1]['windows'] if samples else []):
        if w['visible'] and w['title']:
            trees.append({'top': w, 'children': window_tree(w['hwnd'])[:400]})
    captures = []
    seen_hwnds = set()
    for tr in trees:
        w = tr['top']
        if w['hwnd'] in seen_hwnds:
            continue
        seen_hwnds.add(w['hwnd'])
        out_png = attempt_dir / f"win_{w['hwnd']}.png"
        try:
            capture_window(w['hwnd'], out_png)
            captures.append({'hwnd': w['hwnd'], 'title': w['title'], 'file': out_png.name,
                             'bytes': out_png.stat().st_size if out_png.is_file() else 0})
        except Exception as e:
            captures.append({'hwnd': w['hwnd'], 'title': w['title'], 'error': repr(e)})
    shot = attempt_dir / 'screen.png'
    try:
        ps_json(f'''Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save('{shot.as_posix()}', [System.Drawing.Imaging.ImageFormat]::Png)
"SAVED"''', timeout=60)
    except Exception as e:
        (attempt_dir / 'screen_error.txt').write_text(repr(e), encoding='utf-8')
    kill_record = kill_tree(pid)
    ended = now_iso()
    env_after = env_snapshot(exp)
    marker = exp / 'gui_depot_binding.log'
    result = {
        'attempt': args.name,
        'kind': 'gui-probe (launcher started, no click performed, Generate not pressed)',
        'launcher': launcher.as_posix(),
        'launcher_sha256': sha256_file(launcher),
        'wait_seconds': args.wait,
        'pid': pid,
        'started': started,
        'ended': ended,
        'killed': kill_record,
        'samples': samples,
        'final_window_tree': trees,
        'window_captures': captures,
        'binding_marker_present': marker.is_file(),
        'binding_marker_content': marker.read_text('utf-8', errors='replace') if marker.is_file() else None,
        'output_last': out_stats(exp),
        'processes_before': procs_before,
        'processes_after': process_list(),
        'env_diff': env_diff(env_before, env_after),
        'hardware_download': False,
    }
    write_json(attempt_dir / 'result.json', result)
    print(json.dumps({'attempt': args.name, 'windows_seen': [w['title'] for s in samples for w in s['windows']],
                      'binding_marker': result['binding_marker_present']}))


# ---------------------------------------------------------------- verify helpers

def parse_pins(p: Path) -> dict:
    result = {}
    for line in p.read_text(errors='replace').splitlines():
        if line.lstrip().startswith('#'):
            continue
        m = re.search(r'set_ippin_assignment\s+\{([^}]+)\}\s+\{[^}]*LOCATION\s*=\s*(\w+)', line)
        if m:
            name = m.group(1).strip()
            if re.fullmatch(r'ddr_(?:ck_[pn]|[rc]as_n|we_n|cs_n|cke|odt|reset_n)\[0\]', name):
                name = name[:-3]
            result[name] = m.group(2)
    return result


def cmd_verify(args) -> None:
    exp = Path(args.dir)
    assert_exp_dir(exp)
    comp = args.comp
    base = exp / 'output' / comp
    report = {'experiment': exp.as_posix(), 'comp': comp, 'checked_at': now_iso(), 'checks': {}}
    report['checks']['output_dir_exists'] = base.is_dir()
    if not base.is_dir():
        write_json(exp / 'verify_report.json', report)
        print(json.dumps(report['checks']))
        return
    required = ['Design.xml', 'DesignConfiguration.xml', f'{comp}.xml', f'{comp}.v',
                f'.params_{comp}.txt', f'.ports_{comp}.txt']
    present = {r: (base / r).is_file() and (base / r).stat().st_size > 0 for r in required}
    report['checks']['required_files'] = present
    for sub in ('src/rtl', 'src/adc', 'src/sdc'):
        d = base / sub
        n = len([x for x in d.rglob('*')]) if d.is_dir() else 0
        report['checks'][f'{sub}_files'] = n
    logs = [x.name for x in base.glob('*.log')]
    report['checks']['logs'] = logs
    # parameter values found in generated text files
    params = {}
    for key, pattern in {
        'PH1P_DDR_SPEED_1333.00': r'PH1P_DDR_SPEED[^\n]{0,40}?1333\.00',
        'PH1P_SPEED_BIN_DDR3-1333J': r'DDR3-1333J',
        'CWL_7': r'(?m)^\s*(?:localparam\s+)?CWL\s*[:=]?\s*7\b|\bCWL\b[^\n]{0,20}?\b7\b',
        'CL_10': r'(?m)^\s*(?:localparam\s+)?CL\s*[:=]?\s*10\b|\bCL\b[^\n]{0,20}?\b10\b',
    }.items():
        hits = []
        for p in base.rglob('*'):
            if p.is_file() and p.suffix.lower() in ('.v', '.vh', '.sv', '.txt', '.xml', '.tcl', '.sdc', '.log', '.params', '.ports'):
                try:
                    t = p.read_text(errors='replace')
                except Exception:
                    continue
                for m in re.finditer(pattern, t):
                    hits.append({'file': p.relative_to(base).as_posix(), 'snippet': t[max(0, m.start()-40):m.end()+40].replace('\n', ' ')})
                    if len(hits) >= 8:
                        break
            if len(hits) >= 8:
                break
        params[key] = hits
    report['checks']['param_hits'] = params
    # pin comparison against golden
    adc_files = list(base.rglob('*.adc'))
    pin_report = []
    golden = parse_pins(GOLDEN_ADC)
    for adc in adc_files:
        actual = parse_pins(adc)
        pin_report.append({'adc': adc.relative_to(base).as_posix(), 'pins': len(actual),
                           'matched': sum(1 for k, v in actual.items() if golden.get(k) == v),
                           'mismatch_against_golden': {k: [v, golden.get(k)] for k, v in actual.items() if golden.get(k) not in (None, v)}})
    report['checks']['pin_comparison'] = pin_report
    report['checks']['adc_path_reference'] = [
        {'file': p.relative_to(base).as_posix()}
        for p in base.rglob('*') if p.is_file() and p.suffix.lower() in ('.txt', '.log', '.tcl', '.xml')
        for _ in [0] if 'input_pins.adc' in p.read_text(errors='replace')]
    write_json(exp / 'verify_report.json', report)
    print(json.dumps(report['checks'], indent=1)[:2000])


def cmd_variant(args) -> None:
    exp = Path(args.dir)
    assert_exp_dir(exp)
    touched = []
    kinds = []
    if args.plain_depot:
        kinds.append('strip_manual_binding_guard_sources')
        guard = (exp / 'manual_binding_guard.tcl').as_posix()
        marker = f'source {{{guard}}}\n'.encode()
        for rel in ('depot/Dependency.tcl',
                    'depot/PH1P_DDRMC_IP/Other/plugin_end.tcl',
                    'depot/PH1P_DDRPHY_IP/Other/plugin_end.tcl'):
            p = exp / rel
            data = p.read_bytes()
            assert marker in data, rel
            new = data.replace(marker, b'')
            p.write_bytes(new)
            touched.append({'path': rel, 'before_sha256': sha256_bytes(data),
                            'after_sha256': sha256_bytes(new), 'removed_guard_sources': 1})
    if args.adc_to_local:
        kinds.append('map_external_adc_path_to_local_input_pins')
        old = 'F:/al_data/F9P_PH1P100/08_ddr3_ddrmc_cal_x32_1066mbps/golden_adc/ap115v2_ddr3_x32.adc'
        new = (exp / 'input_pins.adc').as_posix()
        for p in sorted((exp / 'source').rglob('*')):
            if p.is_file():
                data = p.read_bytes()
                if old.encode() in data:
                    nb = data.replace(old.encode(), new.encode())
                    p.write_bytes(nb)
                    touched.append({'path': p.relative_to(exp).as_posix(),
                                    'before_sha256': sha256_bytes(data),
                                    'after_sha256': sha256_bytes(nb),
                                    'replacements': data.count(old.encode())})
        assert touched, 'adc-to-local: no file contained the external ADC path'
    if not kinds:
        raise SystemExit('variant: nothing selected')
    man = json.loads((exp / 'experiment_manifest.json').read_bytes())
    for t in touched:
        man['files'][t['path']] = t['after_sha256']
    rec = json.loads((exp / 'experiment.json').read_bytes())
    rec.setdefault('variants', []).append({
        'created_at': now_iso(),
        'kind': '+'.join(kinds),
        'note': args.note,
        'files': touched,
        'rule': 'byte-level recorded edits only; nothing else changed',
    })
    write_json(exp / 'experiment.json', rec)
    man['files']['experiment.json'] = sha256_file(exp / 'experiment.json')
    write_json(exp / 'experiment_manifest.json', man)
    print(json.dumps(touched, indent=1))


def cmd_list(args) -> None:
    exp = Path(args.dir)
    assert_exp_dir(exp)
    rows = []
    for att in sorted((exp / 'attempts').iterdir()):
        r = att / 'result.json'
        if r.is_file():
            d = json.loads(r.read_bytes())
            rows.append({'name': att.name, 'exit': d.get('exit_code'), 'timed_out': d.get('timed_out'),
                         'duration_s': d.get('duration_seconds'), 'files': (d.get('output_last') or {}).get('files', 0),
                         'bytes': (d.get('output_last') or {}).get('bytes', 0)})
    print(json.dumps(rows, indent=1))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest='cmd', required=True)

    p = sub.add_parser('new-dir')
    p.add_argument('--suffix', type=int, default=None)
    p.add_argument('--plain-depot', action='store_true',
                   help='variant: remove the prepended manual_binding_guard source line (recorded in experiment.json)')
    p.add_argument('--extra-source', action='append', default=[], metavar='DIR',
                   help='copy an additional read-only directory into source/<basename> (e.g. a tool-made IP instance); recorded in experiment.json')
    p.set_defaults(fn=cmd_new_dir)

    p = sub.add_parser('run')
    p.add_argument('--dir', required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--timeout', type=int, default=600)
    p.add_argument('--post-parent-wait', dest='post_parent_wait', type=int, default=90,
                   help='after the parent exits, keep watching descendants for this many seconds')
    p.add_argument('--note', default='')
    p.add_argument('--form', choices=['default', 'copy'], default='copy')
    p.add_argument('--extra', action='append', default=[])
    p.add_argument('--gen', default=None)
    p.add_argument('--user', default=None)
    p.add_argument('--export', default=None)
    p.add_argument('--comp', default=DEFAULT_COMP)
    p.add_argument('--use-value', dest='use_value', default=None)
    p.add_argument('--raw', nargs=argparse.REMAINDER, default=None)
    p.set_defaults(fn=cmd_run)

    p = sub.add_parser('gui-probe')
    p.add_argument('--dir', required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--wait', type=int, default=40)
    p.set_defaults(fn=cmd_gui_probe)

    p = sub.add_parser('verify')
    p.add_argument('--dir', required=True)
    p.add_argument('--comp', default=DEFAULT_COMP)
    p.set_defaults(fn=cmd_verify)

    p = sub.add_parser('variant')
    p.add_argument('--dir', required=True)
    p.add_argument('--plain-depot', action='store_true')
    p.add_argument('--adc-to-local', action='store_true',
                   help='replace the external F:/al_data... golden ADC path with this dir\'s input_pins.adc (recorded)')
    p.add_argument('--note', default='')
    p.set_defaults(fn=cmd_variant)

    p = sub.add_parser('list')
    p.add_argument('--dir', required=True)
    p.set_defaults(fn=cmd_list)

    args = ap.parse_args()
    args.fn(args)


if __name__ == '__main__':
    main()
