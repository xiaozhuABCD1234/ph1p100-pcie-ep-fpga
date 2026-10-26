import subprocess, pathlib, json, sys, datetime
out=pathlib.Path(__file__).resolve().parent
name=sys.argv[1]; target=out/name
assert target.parent==out and target.suffix=='.py'
cmd=[sys.executable,'-B','-X','utf8',str(target)]+sys.argv[2:]
start=datetime.datetime.now(datetime.timezone.utc).isoformat()
try:
    result=subprocess.run(cmd,cwd='D:/fpga/ph1p100',capture_output=True,timeout=300)
    rc=result.returncode; stdout=result.stdout; stderr=result.stderr; timed_out=False
except subprocess.TimeoutExpired as exc:
    rc=-1; stdout=exc.stdout or b''; stderr=exc.stderr or b''; timed_out=True
stem=target.stem+('-after' if 'after' in ' '.join(sys.argv[2:]) else '')
if (out/(stem+'-native-run.json')).exists(): stem+='-attempt2'
(out/(stem+'-stdout.txt')).write_bytes(stdout); (out/(stem+'-stderr.txt')).write_bytes(stderr)
record={'command':cmd,'cwd':'D:/fpga/ph1p100','start_utc':start,'finish_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'deadline_seconds':300,'exit_code':rc,'timed_out':timed_out,'safe_termination':'subprocess.run timeout terminates only this direct child; semantics spawns no children, integrity uses 60-second git subprocess deadlines','stdout_path':str(out/(stem+'-stdout.txt')),'stderr_path':str(out/(stem+'-stderr.txt'))}
(out/(stem+'-native-run.json')).write_text(json.dumps(record,indent=2),encoding='utf-8')
print(stdout.decode('utf-8',errors='replace')); print(stderr.decode('utf-8',errors='replace')); print(json.dumps(record)); sys.exit(rc)
