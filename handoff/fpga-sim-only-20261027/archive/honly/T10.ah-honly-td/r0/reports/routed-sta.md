# routed-sta - T10.ah.honly-td

**not_run.** No place & route was attempted.

Reason: `syn_1` aborted at elaboration (`HDL-8007`, multiple drivers on `cmem_lo`), so
`a1_ah_Runs/syn_1/a1_ah_gate.db` does not exist. `02_route.tcl` guards on that file and
would have exited with `AH_ROUTE_NO_GATE_DB`; invoking it would have consumed a route
attempt without producing evidence, so it was not called.

Route quota: **0 of 2 used**. No 187.5 MHz routed WNS/hold/TNS, no violated-endpoint
count, no QoR, no clock-utilization, no check_timing, no report_cdc - none of these
measurements exist for this DUT revision.

Gate status: `routed WNS >= 0` / `hold >= 0` / `NUM_FEPS = 0` are **not evaluated**
(no data). This must not be reported as either pass or fail on timing; the failure that
is established is upstream of timing (see `synth-187.5.md`).