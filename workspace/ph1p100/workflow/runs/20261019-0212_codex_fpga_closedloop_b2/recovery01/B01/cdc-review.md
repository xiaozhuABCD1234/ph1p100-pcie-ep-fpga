# B01 CDC/reset review — bound to failed routed attempt3

| Added path | Source | Destination | Implementation/constraint |
|---|---|---|---|
| Writer cl_pub_valid + seq/base/len/session | DDR usr_clk writer publication | DDR usr_clk reader | Same-domain registered tuple at fully responded good publication; no sampled multi-bit CDC |
| Reader cl_release[1:0] | DDR usr_clk read/drain completion | DDR usr_clk A writer protection | Same domain; enabled only by static CLOSEDLOOP_EN; legacy pusher A/B toggles remain separate |
| Reader AXI request/response | DDR usr_clk | DDR controller AXI usr_clk | Same clock; request skid holds VALID/address through abort/timeout until handshake; accepted response count drains before release |
| ROI FIFO, algorithm branches and sinks | cam_a_byte_clk | cam_a_byte_clk | Same source clock/reset; ready does not feed CSI or RAW writer; no new clock or multi-bit control CDC |
| One-shot internal abort and source counters | cam_a_byte_clk | writer/algorithm camera inputs, same clock | One cycle after SOF; source electrical good remains independent; no sensor/I2C change |
| Added ChipWatcher probes | Each source domain | Generated watcher for that domain | Require final CWC clock/instance verification and BID mapping; cross-domain snapshots are never claimed atomic |

DDR reset is the controller IP's ddrphy_rst_n; reader, AXI outstanding accounting and writer ownership reset together. A permanently missing response retains ownership and locks until this bus reset. Camera reset is the existing CSI w_a_rst_out; algorithm config and source-domain diagnostic state reset together. No PCIe link_up reset gates the added DDR/camera diagnostics. Existing link-independent dbg_por_rst on the TL snapshot remains untouched.

The closedloop SDC is byte-identical to the protected debug SDC: original sys20ns/camera lane1.333ns/divide4/tl/IP-derived clocks and existing asynchronous groups remain. No new false_path, multicycle or relaxed period is introduced. This static CDC review must be tied to the final implementation, clock report and actual CWC domains before G2 can pass.

Protocol cross-check: early master RREADY is legal. A compliant registered slave responds after AR acceptance; same-edge combinatorial AR-to-R response is excluded by the AXI input/output combinatorial-path rule. The outstanding credit is registered on the accepted AR edge before the first legal response edge. This follows ARM IHI0022H A3.1/A3.3, not an added DUT limitation: [official AMBA AXI specification](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf). No speculative protocol change was made during the active physical build.

Final attempt3 confirms the three clock-domain probe bindings above. Final STA fails; this static CDC table grants no G2 acceptance. See manual-engineering-review.md and engineering/attempt3/critical-paths.json.
