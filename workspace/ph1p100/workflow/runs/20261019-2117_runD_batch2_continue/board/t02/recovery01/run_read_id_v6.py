import json,os,subprocess,sys,time,pathlib,shutil
HERE=pathlib.Path(__file__).resolve().parent
RUN=HERE.parents[2]
BW=pathlib.Path("D:/downlaod/bin/bw_commands_prompt.exe")
CMD=HERE/"read_id_v6.bwcmd"
ts=time.strftime("%Y%m%d_%H%M%S")
out=RUN/"board"/"sram"/ts
out.mkdir(parents=True,exist_ok=True)
def listeners():
    txt=subprocess.check_output(["netstat","-ano"],text=True,errors="replace")
    rows=[]
    for line in txt.splitlines():
        if ":5555" in line and "LISTEN" in line.upper():
            rows.append(line.strip())
    return rows
rows=listeners()
res={"timestamp":time.strftime("%Y-%m-%dT%H:%M:%S%z"),"bwcmd":str(CMD),"listeners_5555":rows,"preflight_ok":len(rows)==1,"timed_out":False,"exit_code":None,"elapsed_seconds":None,"log":str(out/"read_id_v6.log")}
if len(rows)!=1:
    res["status"]="preflight_refused_not_exactly_one_5555_listener"
    (out/"result.json").write_text(json.dumps(res,indent=2),encoding="utf-8")
    print(json.dumps(res));sys.exit(3)
# Run from an ASCII working directory; keep logs in the run.
work=pathlib.Path(os.environ.get("TEMP",r"C:\Users\czz\AppData\Local\Temp"))/"opencode"/"t02_readid_v6"
work.mkdir(parents=True,exist_ok=True)
shutil.copyfile(CMD,work/"read_id_v6.bwcmd")
log=(out/"read_id_v6.log").open("w",encoding="utf-8")
p=subprocess.Popen([str(BW),(work/"read_id_v6.bwcmd").as_posix()],cwd=str(work),stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
log.write("OWN_PID="+str(p.pid)+"\n");log.flush()
t0=time.time()
try:
    code=p.wait(timeout=60);timed=False
except subprocess.TimeoutExpired:
    timed=True
    subprocess.run(["taskkill","/PID",str(p.pid),"/T","/F"],capture_output=True,text=True,timeout=20)
    code=p.wait(timeout=20)
log.close()
text=(out/"read_id_v6.log").read_text(encoding="utf-8",errors="replace")
res.update({"timed_out":timed,"exit_code":code,"elapsed_seconds":round(time.time()-t0,3),"ph1p100":("PH1P100" in text),"status":"pass" if (code==0 and not timed and "PH1P100" in text) else "fail","workdir":str(work)})
(out/"result.json").write_text(json.dumps(res,indent=2),encoding="utf-8")
print(json.dumps(res))
sys.exit(0 if res["status"]=="pass" else 1)
