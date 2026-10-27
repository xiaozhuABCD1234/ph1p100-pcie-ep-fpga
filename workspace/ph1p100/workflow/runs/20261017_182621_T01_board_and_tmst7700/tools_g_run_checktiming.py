# G follow-up runner: execute the TMST-7700 detail tcl on the private project copy.
# Records: argv, cwd, start/end, exit code, log file; kills the process tree on timeout.
import subprocess, sys, datetime
from pathlib import Path

TD_CLI = Path('D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe')
copy_dir = Path(sys.argv[1])
run_dir = Path(sys.argv[2])
script_name = sys.argv[3]
timeout = int(sys.argv[4]) if len(sys.argv) > 4 else 900
log_name = sys.argv[5] if len(sys.argv) > 5 else 'tmst7700_detail_1333_run.txt'

log_path = run_dir / log_name
command = [str(TD_CLI).replace('\\', '/'), './' + script_name]
print('[runner] argv=', command)
print('[runner] cwd=', copy_dir)
print('[runner] log=', log_path)
print('[runner] started_at=', datetime.datetime.now().astimezone().isoformat(), flush=True)

with log_path.open('wb') as stream:
    proc = subprocess.Popen(command, cwd=copy_dir, stdout=stream, stderr=subprocess.STDOUT,
                            creationflags=getattr(subprocess, 'CREATE_NEW_PROCESS_GROUP', 0))
    exit_code = None
    try:
        exit_code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        kill = subprocess.run(['taskkill', '/F', '/T', '/PID', str(proc.pid)],
                              capture_output=True, timeout=120)
        print('[runner] TIMEOUT; taskkill rc=', kill.returncode, flush=True)
        try:
            proc.wait(timeout=60)
        except subprocess.TimeoutExpired:
            proc.kill()

print('[runner] exit_code=', exit_code)
print('[runner] ended_at=', datetime.datetime.now().astimezone().isoformat())
text = log_path.read_text(errors='replace')
print('==== tail of log (last 3000 chars) ====')
print(text[-3000:])
