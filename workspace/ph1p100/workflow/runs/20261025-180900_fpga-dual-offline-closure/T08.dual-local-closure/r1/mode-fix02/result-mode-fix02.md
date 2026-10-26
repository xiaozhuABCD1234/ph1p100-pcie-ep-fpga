# T08 mode-fix02 developer result

This is the existing repair1 pre-submission closure. The original r0 integrated FAIL and blocked static manifest remain unchanged; no r2 or independent r1 verdict is fabricated.

Mode changes now require current-cycle publication absence and truly empty ownership/offer/AR/R/reader state. A rejected mode request is counted without dropping the publication. Presentation state is cleared outside mode2. Valid idle switching remains enabled. Ports, geometry, clock frequency and the rest of the production RTL are unchanged.

|Local check|Outcome|
|---|---|
|old-mode-negative|required marker/ownership or captured-byte oracle satisfied; 2.727s|
|mode-matrix|required marker/ownership or captured-byte oracle satisfied; 2.663s|
|original-edges|required marker/ownership or captured-byte oracle satisfied; 2.457s|
|case16|required marker/ownership or captured-byte oracle satisfied; 33.403s|
|case00|required marker/ownership or captured-byte oracle satisfied; 30.398s|
|case10|required marker/ownership or captured-byte oracle satisfied; 31.081s|
|case11|required marker/ownership or captured-byte oracle satisfied; 31.146s|
|case12|required marker/ownership or captured-byte oracle satisfied; 31.792s|
|case13|required marker/ownership or captured-byte oracle satisfied; 56.533s|
|case14|required marker/ownership or captured-byte oracle satisfied; 59.402s|
|legacy|required marker/ownership or captured-byte oracle satisfied; 25.341s|
|bad-b-negative|required marker/ownership or captured-byte oracle satisfied; 1.603s|

The same legal mode matrix rejects isolated old RTL on publication-mode arbitration and the actual post-release phantom-descriptor trace; the corrected RTL passes. No force of held/FSM state is used. The mode matrix also checks all12 AR-release status combinations, dual publication, routes, stale/duplicate release, take/refill and common reset. The separately aliased B-routing mutant is rejected by the same route assertion. Expected mutant Fatal markers are distinguished from DUT passes and exit0 alone is never sufficient.

Fresh full-top cases cover overlap16, normal0, CRC10, stalled-AR abort11, late-R drain12, permanent-missing-R LOCK/reset13, protected saturation14 and default-disabled legacy. Actual R bytes, frame identity, standard CRC, source pattern and tail zeros are checked; case16 reconstructs accepted AR to final-R intervals and requires both-camera new SOFs and alternate-slot publication, protected whole-frame drop and recovery.

Current window: 17/30 conservative tool calls, 1/2 compiles, 12/12 cases. Historical125 calls/6 compiles/32 cases are retained; cumulative=142/7/44. The r0 overrun and missed old timely handoff are not reclassified by this new actual-modification window. The original tester still has one remaining original-edge attempt.

G0/G1 require original independent tester acceptance. G2/3/4 remain not_run/awaiting_hardware. There was no TD, board, download, Flash, mapping, Git or external-message action. Small offline vectors do not prove dual1080p30 or exposure timing. All previous frozen files and compiled-source inputs show drift0.

Canonical source/compile entry is run_mode_fix.py compile_all with its explicit sources.json; the copied run_t08.py is used only for the unchanged native command utility. Independent testing uses its own allowed output directories, deadline and command harness. sources.f/integration-sources.tcl are integration entries only; they invoke no TD.

Rollback: stop adopting mode-fix02. No production or earlier frozen source was overwritten.
