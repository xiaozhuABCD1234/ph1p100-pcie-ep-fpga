"""Run only a caller-owned child process, with a wall deadline and saved result."""
import contextlib, json, pathlib, subprocess, time

@contextlib.contextmanager
def mapped_project(root):
    root=pathlib.Path(root).resolve()
    drive=pathlib.Path('T:/')
    if drive.exists(): raise RuntimeError('T: occupied; will not replace an existing mapping')
    subprocess.run(['subst','T:',str(root)],check=True,timeout=10)
    try:
        assert drive.resolve()==root
        yield drive
    finally:
        # Removes only this process-owned drive alias, never a project file.
        subprocess.run(['subst','T:','/d'],check=True,timeout=10)

def run(argv, cwd, log, seconds):
    log=pathlib.Path(log);log.parent.mkdir(parents=True,exist_ok=True)
    started=time.time()
    with log.open('w',encoding='utf-8') as output:
        p=subprocess.Popen([str(x) for x in argv],cwd=str(cwd),stdout=output,stderr=subprocess.STDOUT)
        timed_out=False
        try: code=p.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            timed_out=True
            subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True,timeout=30)
            code=p.wait(timeout=30)
    result=dict(argv=[str(x) for x in argv],cwd=str(cwd),pid=p.pid,deadline_seconds=seconds,
                started_epoch=started,elapsed_seconds=time.time()-started,exit_code=code,timed_out=timed_out,log=str(log))
    log.with_suffix(log.suffix+'.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    if timed_out or code: raise RuntimeError(result)
    return result
