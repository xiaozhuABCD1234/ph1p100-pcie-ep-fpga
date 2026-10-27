# Static ownership closure issue

Start in mode2, all slots free, offers0, stateWAIT, no pending/outstanding read.

At one DHI edge request mode1 and publish valid A0. Old held=0 lets active_mode become1; capture makes heldA0=1; the old-mode2 branch simultaneously sets a_offer=1 and a_index=0.

Mode1 consumes and safely releases A0. The source has no non-mode2 clearing of a_offer, so it remains1 while heldA0 and sentA0 return0.

When empty and idle, request mode2. a_desc_valid becomes1 from active_mode==2 && !fault && a_offer even though heldA0=0; ready can transfer the already released identity. B is symmetric.

Source: D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure\T08.dual-local-closure\r1\dual_local_closure.v; SHA256 87bccd0516606f3950ef1e6294687bcc7b600a071f4ac0633e0649885626af8c.

This is a source/control-flow deduction. The13 existing local scenarios did not exercise this mode/publication coincidence; no new simulation was run and no independent r1 verdict is asserted.

Mode/publication acceptance and presentation state lifetime must be made consistent, then the affected transitions need bounded validation on a new source input. Current static authorization permits neither source edits nor experiments.
