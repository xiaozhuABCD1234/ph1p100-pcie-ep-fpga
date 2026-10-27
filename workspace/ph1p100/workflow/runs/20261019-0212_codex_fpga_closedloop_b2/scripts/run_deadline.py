"""Own-child deadline runner. Never controls a process it did not start."""
import argparse, json, os, pathlib, subprocess, sys, time

p = argparse.ArgumentParser()
p.add_argument('--seconds', type=int, required=True)
p.add_argument('--cwd', required=True)
p.add_argument('--log', required=True)
p.add_argument('command', nargs=argparse.REMAINDER)
a = p.parse_args()
cmd = a.command[1:] if a.command[:1] == ['--'] else a.command
log = pathlib.Path(a.log)
log.parent.mkdir(parents=True, exist_ok=True)
t0 = time.time()
with log.open('w', encoding='utf-8') as f:
    f.write(json.dumps({'command': cmd, 'cwd': a.cwd, 'deadline_seconds': a.seconds, 'start': t0})+'\n')
    f.flush()
    proc = subprocess.Popen(cmd, cwd=a.cwd, stdout=f, stderr=subprocess.STDOUT)
    f.write('OWN_PID='+str(proc.pid)+'\n'); f.flush()
    try:
        code = proc.wait(timeout=a.seconds)
        timed_out = False
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], stdout=f, stderr=f, timeout=20)
        code = proc.wait(timeout=20)
        timed_out = True
    f.write(json.dumps({'exit_code': code, 'timed_out': timed_out, 'elapsed_seconds': time.time()-t0})+'\n')
    f.flush()
print(json.dumps({'log': str(log), 'exit_code': code, 'timed_out': timed_out}))
sys.exit(124 if timed_out else code)
