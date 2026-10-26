"""Tester-owned independent round1 full-size 4-frame rerun (N, new TB, own library).

Read-only on the frozen candidate. Own vlib/vlog/vsim, own library dir, own logs.
Hard timeout 2700 s enforced by subprocess.timeout.
"""
import hashlib, json, os, shutil, subprocess, time

RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
SIM = os.path.join(OUT, "sim")
BIN = r"D:\intelFPGA\18.1\modelsim_ase\win32aloem"
INI = r"D:\intelFPGA\18.1\modelsim_ase\modelsim.ini"

os.makedirs(SIM, exist_ok=True)
shutil.copyfile(INI, os.path.join(SIM, "modelsim.ini"))
n = 1
while os.path.isdir(os.path.join(SIM, "lib%d" % n)):
    n += 1
LIBNAM = "work_r1_%d" % n
os.makedirs(os.path.join(SIM, LIBNAM))
open(os.path.join(SIM, LIBNAM, "_tester_owned.txt"), "w").write("tester-owned round1 library\n")

SRC = os.path.join(RUN, "src")
FILES = ["a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v", "camera_a1_uart_top.v",
         "cam_diag_mailbox.v", "a1_frame_top.v", "a1_deflate_core.v", "p2_ddr_bridge.v",
         "a1_ddr_arb2.v", "capture_async_fifo.v", "p2_paxi_model_b11.v", "a1_ddr_model.v",
         "tb_ss_4run_wd.v"]
paths = [os.path.join(SRC, f) for f in FILES]
src_sha = {f: hashlib.sha256(open(p, "rb").read()).hexdigest() for f, p in zip(FILES, paths)}

log = os.path.join(SIM, "vsim-tester-n-r1.log")
stat = os.path.join(SIM, "tester-n-r1.stats")
evt = os.path.join(SIM, "tester-n-r1.evt")
hdr = os.path.join(SIM, "tester-n-r1.hdr")
for p in (log, stat, evt, hdr):
    if os.path.exists(p):
        os.remove(p)
rec = {"src_sha256": src_sha, "library": LIBNAM, "commands": []}


def run(argv, timeout, tag):
    t0 = time.time()
    try:
        pr = subprocess.run(argv, cwd=SIM, capture_output=True, text=True, timeout=timeout)
        rc, to = pr.returncode, False
        tail = (pr.stdout or "")[-1500:] + (pr.stderr or "")[-800:]
    except subprocess.TimeoutExpired:
        rc, to = 124, True
        tail = "TIMEOUT after %ss" % timeout
    sec = round(time.time() - t0, 1)
    rec["commands"].append(dict(tag=tag, argv=argv, rc=rc, seconds=sec, timed_out=to, tail=tail))
    print(tag, "rc=", rc, "s=", sec, "timeout=", to, flush=True)
    return rc


t_all = time.time()
run([os.path.join(BIN, "vlib.exe"), LIBNAM], 300, "vlib")
run([os.path.join(BIN, "vlog.exe"), "-sv", "-work", LIBNAM, "+define+SIMULATION"] + paths, 900, "vlog")
run([os.path.join(BIN, "vsim.exe"), "-c", "-lib", LIBNAM, "-l", log, "tb_ss_4run",
     "+STAT=" + stat, "+EVT=" + evt, "+HDR=" + hdr,
     "+RAW40=" + os.path.join(RUN, "content", "raw40_n.hex"),
     "-do", "run -all; quit -f",
     "-gMAX_CYCLES=60000000", "-gCAPTURE=0", "-gSINK=1", "-gPACING=0", "-gFRAMES=4", "-gCONTENT=2"],
    2700, "vsim_n_r1")
rec["total_seconds"] = round(time.time() - t_all, 1)

out = dict(rec=rec, files={k: dict(path=p, bytes=os.path.getsize(p) if os.path.exists(p) else None)
                           for k, p in (("log", log), ("stats", stat), ("evt", evt), ("hdr", hdr))})
if os.path.exists(log):
    lines = open(log, encoding="utf-8", errors="replace").read().splitlines()
    out["key_lines"] = [l for l in lines if any(k in l for k in (
        "SS_META", "SS_EVT", "SS_PACE", "SS_STALL", "SS_RAW_MATCH", "SS_STATS", "B11_FULL",
        "Errors:", "Fatal"))]
    out["log_sha256"] = hashlib.sha256(open(log, "rb").read()).hexdigest()
for k in ("evt", "hdr", "stats"):
    p = out["files"][k]["path"]
    if os.path.exists(p):
        out["files"][k]["sha256"] = hashlib.sha256(open(p, "rb").read()).hexdigest()
json.dump(out, open(os.path.join(OUT, "evidence-tester-rerun-n-r1.json"), "w"), indent=2)
print("\n".join(out.get("key_lines", [])))
print(json.dumps(out["files"], indent=1))
print("total", rec["total_seconds"], "s")
