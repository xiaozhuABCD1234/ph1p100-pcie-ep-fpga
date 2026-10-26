import pathlib, subprocess, ctypes, time, json
TC=pathlib.Path(__file__).resolve().parents[1]; D=TC/'tool-help'; D.mkdir(exist_ok=True)
tcl='''foreach c {fix_hold phys_opt set_run_options set_run_option set_option launch_runs} {
 puts "HELP_BEGIN $c"
 if {[catch {help $c} msg]} {puts "HELP_ERROR $msg"}
 puts "HELP_END $c"
}
exit
'''
(D/'help.tcl').write_text(tcl,encoding='ascii')
def target(l):
    b=ctypes.create_unicode_buffer(32768)
    return b.value if ctypes.windll.kernel32.QueryDosDeviceW(l+':',b,len(b)) else None
letter=next(l for l in 'UVWXYZ' if target(l) is None)
subprocess.run(['subst',letter+':',str(D)],check=True,timeout=10)
start=time.time()
try:
    with (D/'native-help.log').open('w',encoding='utf-8') as log:
        p=subprocess.Popen(['D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe','help.tcl'],cwd=letter+':/',stdout=log,stderr=log)
        log.write('OWN_PID='+str(p.pid)+'\n'); log.flush()
        try: rc=p.wait(timeout=300)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=log,stderr=log,timeout=20); p.wait(timeout=20); raise
    print((D/'native-help.log').read_text(encoding='utf-8',errors='replace'))
finally:
    if target(letter)=='\\??\\'+str(D):subprocess.run(['subst',letter+':','/D'],check=True,timeout=10)
