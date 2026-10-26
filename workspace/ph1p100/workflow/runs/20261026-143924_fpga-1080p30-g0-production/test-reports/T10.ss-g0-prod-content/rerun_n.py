"""Tester-owned independent full-size 4-frame rerun of the N (natural) class.

Own vlib/vlog/vsim invocation (does NOT reuse the developer's run_content.py or
its work library). Read-only on the frozen candidate; all outputs land under
test-reports/T10.ss-g0-prod-content/sim/.
"""
import hashlib, json, os, shutil, subprocess, time

RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
SIM = os.path.join(OUT, "sim")
BIN = r"D:\intelFPGA\18.1\modelsim_ase\win32aloem"
INI = r"D:\intelFPGA\18.1\modelsim_ase\modelsim.ini"

os.makedirs(SIM, exist_ok=True)
shutil.copyfile(INI, os.path.join(SIM, "modelsim.ini"))   # tool config, not a shared library
n = 1
while os.path.isdir(os.path.join(SIM, "lib%d" % n)):
    n += 1                                   # never delete: fresh dir each attempt
LIBNAM = "work_t%d" % n
LIBDIR = os.path.join(SIM, LIBNAM)
os.makedirs(LIBDIR)
open(os.path.join(LIBDIR, "_tester_owned.txt"), "w").write("tester-owned library\n")

SRC = os.path.join(RUN, "src")
FILES = ["a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v", "camera_a1_uart_top.v",
         "cam_diag_mailbox.v", "a1_frame_top.v", "a1_deflate_core.v", "p2_ddr_bridge.v",
         "a1_ddr_arb2.v", "capture_async_fifo.v", "p2_paxi_model_b11.v", "a1_ddr_model.v",
         "tb_ss_4run.v"]
paths = [os.path.join(SRC, f) for f in FILES]
src_sha = {f: hashlib.sha256(open(p, "rb").read()).hexdigest() for f, p in zip(FILES, paths)}

log = os.path.join(SIM, "vsim-tester-n.log")
stat = os.path.join(SIM, "tester-n.stats")
evt = os.path.join(SIM, "tester-n.evt")
hdr = os.path.join(SIM, "tester-n.hdr")
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


run([os.path.join(BIN, "vlib.exe"), LIBNAM], 300, "vlib")
rc = run([os.path.join(BIN, "vlog.exe"), "-sv", "-work", LIBNAM,
          "+define+SIMULATION"] + paths, 900, "vlog")

argv = [os.path.join(BIN, "vsim.exe"), "-c", "-lib", LIBNAM, "-l", log,
        "tb_ss_4run",
        "+STAT=" + stat, "+EVT=" + evt, "+HDR=" + hdr,
        "+RAW40=" + os.path.join(RUN, "content", "raw40_n.hex"),
        "-do", "run -all; quit -f",
        "-gMAX_CYCLES=48000000", "-gCAPTURE=0", "-gSINK=1", "-gPACING=0", "-gFRAMES=4", "-gCONTENT=2"]
run(argv, 2700, "vsim_n")

out = dict(rec=rec, files={k: dict(path=p, exists=os.path.exists(p),
                                  bytes=os.path.getsize(p) if os.path.exists(p) else 0)
                           for k, p in (("log", log), ("stats", stat), ("evt", evt), ("hdr", hdr))})
if os.path.exists(log):
    lines = open(log, encoding="utf-8", errors="replace").read().splitlines()
    key = [l for l in lines if any(k in l for k in ("SS_META", "SS_EVT", "SS_PACE", "SS_STALL",
                                                    "SS_RAW_MATCH", "SS_STATS", "B11_FULL",
                                                    "Errors:", "Fatal"))]
    out["key_lines"] = key
    out["log_sha256"] = hashlib.sha256(open(log, "rb").read()).hexdigest()
json.dump(out, open(os.path.join(OUT, "evidence-tester-rerun-n.json"), "w"), indent=2)
print("\n".join(out.get("key_lines", [])))
print(json.dumps(out["files"], indent=1))
