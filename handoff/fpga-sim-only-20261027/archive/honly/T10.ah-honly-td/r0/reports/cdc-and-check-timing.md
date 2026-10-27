# cdc-and-check-timing - T10.ah-honly-td

**not_run.** `check_timing` / `report_check_timing` and `report_cdc` are only issued by
`02_route.tcl` after a routed database exists. There is no database, so no CDC report,
no unconstrained-path report, no generated-clock/loop report exists.

Design intent (from the frozen sources, read-only): single clock domain `clk`
(`a1_frame_top` ports + `a1_ah_eng_top`), asynchronous active-low `rst_n`, no CDC
structures and no asynchronous FIFO inside the block. `clk_uart` belongs to the
UART-export subsystem that this block-level top does **not** instantiate. The SDC has
exactly one `create_clock` and no exceptions.

Known, recorded gap that would have applied to a successful run: block-level I/O are
left unconstrained (internal SoC ports, not package pins), so I/O timing is not covered
by this flow. That gap is documented, not "fixed" by fabricated I/O constraints.

Status: unconstrained/CDC **evidence absent**, not "clean".