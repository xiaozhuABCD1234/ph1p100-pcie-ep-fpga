# lessons-r0 -- T10.b20-a-timing

## L1. The b19 abort cone was retiming-induced; registering the drain teardown helps but does not buy much margin

b19's `-0.098 ns` path (`a1_abort_reg -> smem.addrb`) existed because the raw
`abort` selected the abort branch, so every drain register (and every
hold-through register) got an abort mux in its D cone; with `rtl retiming on`
that mux landed in the ERAM address cone.

Moving only the drain teardown onto a registered `abort_d` gave:

| stage | b19 | b20 |
|---|---|---|
| synth WNS | +0.127 | **+0.204** |
| routed WNS | -0.098 (10 listed / 11 QoR viol) | **+0.012 (0 viol)** |

So the targeted repair bought ~0.11 ns routed -- enough to get to zero violations,
not enough for the +0.05 target. Reusable rule: a +0.077 ns synthesis gain is worth
~+0.11 ns routed *on this path*, and synthesis-to-route loss on the b20 worst path
was ~0.19 ns. Plan the next attempt on a different, non-abort cone (the core
`sdata_ptr -> state_reg` path is now the limiter at +0.012).

## L2. Enforce the route precondition inside the build TCL, not after the fact

`01_build.tcl` now stops before `launch_runs phy_1` when `syn_wns < 0.127`
(`P2_SYN_NO_GAIN_STOP`) and prints `P2_SYN_ROUTE_PRECONDITION_OK`. This costs one
line and prevents burning the single route attempt on a candidate that cannot
reach the routed target. b20 printed `SWNS=0.204`, so route was allowed.

## L3. A netlist cone walk must treat `oqa` as a flop output

`PH1P_PHY_LSLICE` exposes `ofa`/`ofb` (LUT) and `oqa`/`oqb` (registered) outputs.
A walk that only stops at `oqb` crosses registers and invents paths (it reported
48 false hits on b20 while stopping correctly on b19 only by luck of which FF
output pin the signal used). Even with correct boundaries a LUT-agnostic walk
over-approximates (it ignores the LUT INIT function), so it must be reported as an
upper bound, never as "no path" proof. Use the routed STA path list for the gate.

## L4. `routed_timing.rpt` repeats group sections; the first summary is not the worst

The b19 report contains later `ddr_user -> ddr_user` sections with `-0.008 ns / 1
violated endpoint` that the first summary (`+0.007 / 0`) hides; the QoR table says
`11 violated S-EP`, not 10. Parse the QoR count and take the **min WNS / max
violated endpoints across all sections** per group (implemented in
`r0/check_timing_b20.py`). b20 is clean under the strict reading as well
(0 violations, all groups positive).

## L5. This host has no `HKLM ...\SERIALCOMM` key

`Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\SERIALCOMM` throws
`PathNotFound`; the FTDI VCP still enumerates as `USB Serial Port (COM8)` and is
listed by `[System.IO.Ports.SerialPort]::GetPortNames()`. A preflight that requires
the registry value blocks a healthy board. Use FTDI PnP + port list + an
open/close of COM8.

## L6. The USB device can vanish between the standalone preflight and the board run

At 22:00 the FTDI `0403:6042` and COM8 were present (COM8 opened/closed cleanly);
at 22:17 the same preflight found no VID_0403 device at all and COM8 gone (a stale
`jtagserver` was still running). The board script re-runs the preflight itself, so
the loss cost 0 downloads and 0 captures -- correct, but it means a board result
cannot be assumed from an earlier successful preflight. Have the operator connect
and power the board immediately before the single-shot run.

## L7. Testbench module copy needs the module *and* the marker renamed

Copying `tb_b19_camsel.sv`/`tb_b19_status_v6.v` into the b20 package and renaming
only the module left `B19_*` markers; the driver gates on `B20_*`. Rename the
`$display` prefixes with the module (or grep the driver markers). The b19-named
originals are kept as `*.stale` for diff reference.

## L8. A 300 s capture is not needed to prove the board is absent

Preflight is a single-shot gate: `FTDI_PRESENT=0` at board time ends the run with
`board=blocked`, `downloads=0`, `captures=0`. Do not spend the download or the
300 s capture window on a missing cable, and do not claim A is dead from it.
