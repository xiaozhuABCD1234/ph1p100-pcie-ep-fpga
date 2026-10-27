"""Tester's independent hand-calculation harness for T10.ss-verdict-r1 (round 0).

Does NOT import the developer's model/calc.py or test_calc.py.  Every formula below is
re-implemented from fpga-design-guide.md sections 2.3, 4.1-4.6 and compared with the
frozen candidate CSV/JSON values.  Only stdlib is used.

Inputs are read-only:
  P1 out/steady-state.json (A1 measured anchor)
  candidate inputs/frozen-inputs.json (constants / contract values)
  candidate out/*.csv, out/summary.json, verdict-r1.md
Output: JSON summary on stdout + <this dir>/independent_handcalc.json
"""
import csv
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = "D:/fpga/ph1p100/workflow/runs/20261025-233401_fpga-steady-state-reverdict"
R0 = os.path.join(RUN, "T10.ss-verdict-r1", "r0")
P1 = os.path.join(RUN, "T10.ss-steady-anchor", "r0", "out", "steady-state.json")
TOUCHED = [0]
FAILS = []


def ck(name, cond, detail=""):
    TOUCHED[0] += 1
    if not cond:
        FAILS.append(name)
        print("FAIL  %s  %s" % (name, detail))


def near(a, b, tol):
    return abs(float(a) - float(b)) <= tol


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def read_csv(name):
    path = os.path.join(R0, "out", name)
    with open(path, "r", encoding="utf-8", newline="") as fh:
        rdr = csv.DictReader(fh)
        return list(rdr)


def main():
    p1 = load_json(P1)
    frozen = load_json(os.path.join(R0, "inputs", "frozen-inputs.json"))
    CLK = float(p1["clock_hz"])                      # 187.5e6
    RAW = 1920 * 1080 * 5 // 4                       # 2,592,000 B/frame (20B/32B packing)
    FPS = 30.0
    DEM = RAW * FPS / 1e6                            # 77.76 MB/s
    DEM25 = 1.25 * DEM                               # 97.20 MB/s
    MB = 1e6

    # ---------------------------------------------------------------- A1 (P1 measured)
    s_ss = float(p1["S_ss"])
    c1 = RAW * CLK / s_ss / MB
    fps1 = CLK / s_ss
    m10 = 100.0 * (c1 / DEM - 1.0)
    m125 = 100.0 * (c1 / DEM25 - 1.0)
    f0_1 = s_ss * 30.0 / MB
    f25_1 = s_ss * 37.5 / MB
    print("A1: C=%.10f fps=%.10f m0=%.10f m25=%.10f f0=%.6f f25=%.6f"
          % (c1, fps1, m10, m125, f0_1, f25_1))
    ck("A1 C_ss = 103.9009 MB/s", near(c1, 103.90087941618823, 1e-9), c1)
    ck("A1 fps = 40.0852", near(fps1, 40.085215824146694, 1e-9), fps1)
    ck("A1 margin_0 = +33.6174%", near(m10, 33.61738608048896, 1e-9), m10)
    ck("A1 margin_25 = +6.8939%", near(m125, 6.893908864391185, 1e-9), m125)
    ck("A1 f_req_0 = 140.326 MHz", near(f0_1, 140.32605, 1e-9), f0_1)
    ck("A1 f_req_25 = 175.408 MHz", near(f25_1, 175.4075625, 1e-9), f25_1)
    ck("A1 startup = 2,088,899 and startup_pct = 44.6581%",
       p1["startup"] == 2088899 and near(p1["startup_pct"], 44.65811586658357, 1e-9))

    # ---------------------------------------------------------------- A2 / A3 (assumed)
    comp_cpb = 355261.0 / 153600.0                   # 2.3128971354166667 c/B
    # A3 frozen anchor definition: P2's frozen rand cpb is 1.051296875 (a rounded value);
    # the exact primitive ratio 161,479/153,600 = 1.051295573 differs by ~1.3e-6 c/B
    # (3.375 cycles/frame, 0.0001%).  The plan freezes A3 = 3,151,346.5, so test the frozen
    # definition here and flag the inherited rounding separately below.
    rand_cpb = 1.051296875
    rand_cpb_exact = 161479.0 / 153600.0
    a2_cyc = comp_cpb * RAW + 426385.0               # 6,421,414.375
    a3_cyc = rand_cpb * RAW + 426385.0               # 3,151,346.5 (frozen definition)
    a3_cyc_exact = rand_cpb_exact * RAW + 426385.0   # 3,151,343.125 (primitive strip ratio)
    a2_c = RAW * CLK / a2_cyc / MB
    a3_c = RAW * CLK / a3_cyc / MB
    a2_m0 = 100.0 * (a2_c / DEM - 1.0)
    a2_m25 = 100.0 * (a2_c / DEM25 - 1.0)
    a3_m0 = 100.0 * (a3_c / DEM - 1.0)
    a3_m25 = 100.0 * (a3_c / DEM25 - 1.0)
    print("A2: cyc=%.3f C=%.7f m0=%.6f m25=%.6f" % (a2_cyc, a2_c, a2_m0, a2_m25))
    print("A3: cyc=%.3f C=%.7f m0=%.6f m25=%.6f" % (a3_cyc, a3_c, a3_m0, a3_m25))
    ck("A2 cycles = 6,421,414.375", near(a2_cyc, 6421414.375, 1e-9), a2_cyc)
    ck("A2 C_ss = 75.6843 MB/s", near(a2_c, 75.68426075914155, 1e-6), a2_c)
    ck("A2 margin_0 = -2.6694%", near(a2_m0, -2.669417748017555, 1e-6), a2_m0)
    ck("A2 margin_25 = -22.1355%", near(a2_m25, -22.135534198414042, 1e-6), a2_m25)
    ck("A3 cycles = 3,151,346.5", near(a3_cyc, 3151346.5, 1e-9), a3_cyc)
    ck("A3 inherited cpb rounding is immaterial (<1e-3 cycles/B; <0.001% cycles)",
       abs(rand_cpb - rand_cpb_exact) <= 1.4e-6
       and abs(a3_cyc - a3_cyc_exact) / a3_cyc < 1e-5,
       (rand_cpb - rand_cpb_exact, a3_cyc - a3_cyc_exact))
    ck("A3 C_ss = 154.2198 MB/s", near(a3_c, 154.21979144470467, 1e-6), a3_c)
    ck("A3 margins +98.3279% / +58.6623%",
       near(a3_m0, 98.32792109658521, 1e-6) and near(a3_m25, 58.66233687726816, 1e-6))

    # ------------------------------------------------------- gate thresholds / fps
    c_at_6250k = RAW * CLK / 6250000.0 / MB
    c_at_5000k = RAW * CLK / 5000000.0 / MB
    fps25_a1 = CLK / (1.25 * s_ss)
    fps25_a2 = CLK / (1.25 * a2_cyc)
    ck("S=6.25M -> 77.76 MB/s (0% boundary)", near(c_at_6250k, 77.76, 1e-12), c_at_6250k)
    ck("S=5.0M -> 97.20 MB/s (25% boundary)", near(c_at_5000k, 97.2, 1e-12), c_at_5000k)
    ck("25% max fps A1 = 32.068", near(fps25_a1, 32.068172659317355, 1e-6), fps25_a1)
    ck("25% max fps A2 = 23.359", near(fps25_a2, 23.35933974047579, 1e-6), fps25_a2)

    # --------------------------------------------------------------- 1080p tier shift
    tiers = [0, 426385, 1000000]
    tier_cycles = [s_ss + (t - 426385) for t in tiers]
    tier_c = [RAW * CLK / cyc / MB for cyc in tier_cycles]
    tier_m25 = [100.0 * (c / DEM25 - 1.0) for c in tier_c]
    print("tiers cycles=%s C=%s m25=%s" % (tier_cycles, tier_c, tier_m25))
    ck("tier cycles 4,251,150 / 4,677,535 / 5,251,150",
       tier_cycles == [4251150.0, 4677535.0, 5251150.0], tier_cycles)
    ck("tier G25 +17.6152% / +6.8939% / -4.7828%",
       near(tier_m25[0], 17.615233525046172, 1e-6)
       and near(tier_m25[1], 6.893908864391185, 1e-6)
       and near(tier_m25[2], -4.782761871209162, 1e-6), tier_m25)

    # ------------------------------------------------------------------------- DDR
    d_total = RAW * 30.0 * 2 / MB                    # 155.52
    rw = d_total * 1.6
    rr = rw
    cmp_total = 2594706.0 + 44.0                     # 2,594,750 B worst stored
    sw = cmp_total * 30.0 * 2 / MB
    sr = sw
    ddr = rw + rr + sw + sr
    gate = 1.25 * ddr
    p1333 = 1333e6 * 32 / 8 / MB
    p1600 = 1600e6 * 32 / 8 / MB
    print("DDR: D=%.6f rw=%.6f sw=%.6f total=%.6f gate=%.6f p1333=%.1f p1600=%.1f"
          % (d_total, rw, sw, ddr, gate, p1333, p1600))
    ck("DDR total = 809.034 MB/s", near(ddr, 809.034, 1e-9), ddr)
    ck("DDR gate = 1,011.2925 MB/s", near(gate, 1011.2925, 1e-9), gate)
    ck("DDR peak 1333 = 5,332 / 1600 = 6,400",
       near(p1333, 5332, 1e-9) and near(p1600, 6400, 1e-9))
    ck("required_eff 1333 = 15.1732%", near(100 * ddr / p1333, 15.173180795198801, 1e-9))
    ck("gate_eff 1333 = 18.9665%", near(100 * gate / p1333, 18.966475993998504, 1e-9))
    ck("required_eff 1600 = 12.6412%", near(100 * ddr / p1600, 12.641156250000002, 1e-9))
    ck("gate_eff 1600 = 15.8014%", near(100 * gate / p1600, 15.8014453125, 1e-9))

    # ------------------------------------------------------------------------ UART
    t40k = 40032.0 / 11520.0
    tframe_payload = 2594706.0 / 11520.0
    tframe_total = 2594750.0 / 11520.0
    print("UART: 40032B=%.10f s  frame payload=%.10f s  frame total=%.10f s"
          % (t40k, tframe_payload, tframe_total))
    ck("UART 40,032 B @11,520 B/s = 3.475 s", near(t40k, 3.475, 1e-12), t40k)
    ck("UART 2,594,706 B = 225.235 s", near(tframe_payload, 225.23489583333333, 1e-9))
    ck("UART 104.25x / 6,757x frame period",
       near(t40k / (1 / 30.0), 104.25, 1e-9) and near(tframe_payload / (1 / 30.0), 6757.046875, 1e-9))
    ck("sim sink 18.75 MB/s; export ideal 400,320 cycles; tail 480,930 constant; sink_limited=false",
       near(18750000 / 11520, 1627.6041666666667, 1e-9) and 40032 * 10 == 400320
       and p1["export_tail"][1:] == [480930] * 4 and p1["sink_limited"] is False
       and p1["c_excl_export_MBps"] == p1["capacity_MBps"])

    # ------------------------------------------------------ candidate CSV agreement
    anchors = {r["anchor_id"]: r for r in read_csv("content-anchors.csv")}
    ck("CSV A1 C/margins match hand calc",
       near(anchors["A1"]["capacity_MBps"], c1, 1e-6)
       and near(anchors["A1"]["margin_G0_pct"], m10, 2e-3)
       and near(anchors["A1"]["margin_G25_pct"], m125, 2e-3))
    ck("CSV A2 C/margins match hand calc",
       near(anchors["A2"]["capacity_MBps"], a2_c, 1e-6)
       and near(anchors["A2"]["margin_G0_pct"], a2_m0, 2e-3)
       and near(anchors["A2"]["margin_G25_pct"], a2_m25, 2e-3)
       and near(anchors["A2"]["cycles_per_frame"], a2_cyc, 1e-3))
    ck("CSV A3 C/margins match hand calc",
       near(anchors["A3"]["capacity_MBps"], a3_c, 1e-6)
       and near(anchors["A3"]["margin_G0_pct"], a3_m0, 2e-3)
       and near(anchors["A3"]["margin_G25_pct"], a3_m25, 2e-3))
    ck("CSV A4 not a throughput anchor",
       anchors["A4"]["is_throughput_anchor"] == "false"
       and anchors["A4"]["gate_G0"] == "not_applicable")

    scen = read_csv("scenarios.csv")
    s30 = [r for r in scen if r["scenario_id"] == "1920x1080-30fps-c1s1-187.5MHz"][0]
    ck("CSV 1080p30 c1s1 = 103.9009 MB/s, +33.6174%/+6.8939%, gates pass/pass",
       near(s30["capacity_chain_MBps"], c1, 1e-6)
       and near(s30["margin_chain_pct"], m10, 2e-3)
       and near(s30["margin_gate25_pct"], m125, 2e-3)
       and s30["gate_G0"] == "pass" and s30["gate_G25"] == "pass"
       and near(s30["cycles_chain_per_frame"], s_ss, 1e-3))

    over = read_csv("overhead-sensitivity.csv")
    o30 = sorted([r for r in over if r["scenario_id"] == "1920x1080-30fps-c1s1-187.5MHz"],
                 key=lambda r: float(r["tier_cycles"]))
    ck("CSV overhead 1080p30 tiers = 4,251,150 / 4,677,535 / 5,251,150",
       [float(r["cycles_chain_per_frame"]) for r in o30] == tier_cycles,
       [r["cycles_chain_per_frame"] for r in o30])
    ck("CSV overhead 1080p30 G25 tiers pass/pass/fail",
       [r["gate_G25"] for r in o30] == ["pass", "pass", "fail"]
       and [r["applies"] for r in o30] == ["true", "true", "true"])

    ddr_csv = [r for r in read_csv("ddr-budget.csv") if r["case_id"] == "dual_1080p30_main"][0]
    ck("CSV DDR main row matches hand calc",
       near(ddr_csv["ddr_total_MBps"], ddr, 1e-6)
       and near(ddr_csv["ddr_gate_25_MBps"], gate, 1e-6)
       and near(ddr_csv["required_eff_1333_pct"], 15.173180795198801, 2e-3)
       and near(ddr_csv["gate_eff_1333_pct"], 18.966475993998504, 2e-3)
       and near(ddr_csv["required_eff_1600_pct"], 12.641156250000002, 2e-3)
       and near(ddr_csv["gate_eff_1600_pct"], 15.8014453125, 2e-3)
       and near(ddr_csv["peak_main_1333_MBps"], 5332, 1e-9)
       and near(ddr_csv["peak_fallback_1600_MBps"], 6400, 1e-9))

    # report values (spot check the rendered strings)
    with open(os.path.join(R0, "verdict-r1.md"), "r", encoding="utf-8") as fh:
        report = fh.read()
    for s in ("103.9009", "+33.6174%", "+6.8939%", "75.6843", "-2.6694%", "-22.1355%",
              "154.2198", "4,251,150", "5,251,150", "+17.6152%", "-4.7828%",
              "809.034", "15.1732%", "18.9665%", "12.6412%", "15.8014%",
              "3.475", "225.235", "32.068", "23.359", "480,930", "sink_limited=false"):
        ck("report string %s" % s, s in report)

    summary = load_json(os.path.join(R0, "out", "summary.json"))
    ck("summary A1/A2/A3 margins match hand calc",
       near(summary["anchors"]["A1"]["margin_0_pct"], m10, 1e-6)
       and near(summary["anchors"]["A2"]["margin_0_pct"], a2_m0, 1e-6)
       and near(summary["anchors"]["A3"]["capacity_MBps"], a3_c, 1e-6)
       and near(summary["ddr_main"]["ddr_total_MBps"], ddr, 1e-6)
       and near(summary["uart"]["export_s_payload"], t40k, 1e-9)
       and near(summary["max_fps_25pct"]["A1"], fps25_a1, 1e-6)
       and near(summary["max_fps_25pct"]["A2"], fps25_a2, 1e-6))

    out = {
        "checks": TOUCHED[0],
        "failures": FAILS,
        "verdict": "PASS" if not FAILS else "FAIL",
        "hand_values": {
            "A1": {"cycles": s_ss, "capacity_MBps": c1, "fps": fps1,
                   "margin_0_pct": m10, "margin_25_pct": m125,
                   "f_req_0_MHz": f0_1, "f_req_25_MHz": f25_1},
            "A2": {"cycles": a2_cyc, "capacity_MBps": a2_c,
                   "margin_0_pct": a2_m0, "margin_25_pct": a2_m25},
            "A3": {"cycles": a3_cyc, "capacity_MBps": a3_c,
                   "margin_0_pct": a3_m0, "margin_25_pct": a3_m25},
            "tiers_1080p": {"cycles": tier_cycles, "capacity_MBps": tier_c,
                            "margin_25_pct": tier_m25},
            "ddr": {"total_MBps": ddr, "gate_MBps": gate,
                    "required_eff_1333_pct": 100 * ddr / p1333,
                    "gate_eff_1333_pct": 100 * gate / p1333,
                    "required_eff_1600_pct": 100 * ddr / p1600,
                    "gate_eff_1600_pct": 100 * gate / p1600},
            "uart": {"s_40032B": t40k, "s_frame_payload": tframe_payload,
                     "s_frame_total": tframe_total},
            "max_fps_25pct": {"A1": fps25_a1, "A2": fps25_a2},
        },
    }
    with open(os.path.join(HERE, "independent_handcalc.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
        fh.write("\n")
    print("\n%d checks, %d failures" % (TOUCHED[0], len(FAILS)))
    print("INDEPENDENT_HANDCALC=%s" % out["verdict"])
    return 0 if not FAILS else 1


if __name__ == "__main__":
    raise SystemExit(main())
