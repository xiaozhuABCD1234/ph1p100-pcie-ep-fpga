# Final engineering review — failed routed candidate

Final-review-complete: true
G2-pass: false
Engineering-result SHA256: 13b429503a98c3743d484a4357f75da0d705dfaf729099332131f11fa6572c2d

Actual attempt3 imported attempt2's unchanged routed checkpoint SHA f36c1811bf0773223490ea315b829e1b007e177d1b802a436deca4c0031aaf0b, completed the native post-route stage, exported DB/report/bit/BID and ran setup_debugger -prj. Native command exit0 means completion, not timing acceptance.

Final confidence Routed, both corners, original187.547MHz camera clock retained. SWNS=-0.766ns/STNS=-38.113ns/HWNS=-0.075ns/HTNS=-1.242ns; camera setup and DDR/camera/TL hold fail. All resource categories within device capacity (lut28259/71680, reg39950/143360, ERAM200/300, DSP14/220). Real gray/Gaussian/HE retained in final area; CRC diagnostic outputs are not disconnected. CWC coverage check0fail, native bit identical to cw/compiled.bit, no source drift. Native clocks are ['u_top/g_closedloop$u_algo/clk', 'u_top/u_ddr3_mc_0/ph1p_ddrmc_wrapper/dhi_clk', 'u_top/u_uart/u_uart_cdc/core_clk']; probes retain512/480/288 bits in three domains. Cross-domain samples remain non-atomic.

STA coverage97.71%. Native check_timing shows no invalid constraints/combinational loops/no-path exceptions, but retains PLL-lock/TL-CE root-clock findings, local-clock/dummy-pad and no-I/O-delay findings. Their raw report is frozen; no new waiver or coverage PASS is claimed. Closedloop SDC remains byte-identical to the protected debug SDC. New controls/probes remain same-domain as cdc-review.md, but that static analysis does not override final timing failure.

Exact negative setup/hold endpoints are critical-paths.json. The placed residual path was gray m_valid -> demosaic row-buffer enable; a future correction should evaluate a genuinely elastic RGB/sideband boundary and native hold-fix, then rerun affected numerical/abort/stall/service tests and final physical checks. No such extra RTL correction or fourth TD run was performed under the exhausted budget.

Independent integrated round0 and G3 have not started. The produced bit/CWC is archived as rejected, not eligible for SRAM entry. User presence creates no missing developer GUI action; the blocker is actual G2 and exhausted production attempts.
