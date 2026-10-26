# lessons.md — T11.runC-sim-campaign（P3，开发写）

- L1（断言口径）: 破坏 word0（magic）会连带破坏头 CRC——若未同步重算 word22，hdr_crc_ok 也为 0（status 0x0132 而非 0x013A）。要单项隔离 magic，必须用独立 oracle 重算头 CRC 后再发布。下次写此类预期值先推一遍检查链交叉影响。
- L2（激励落在覆盖域内）: 载荷 CRC 破坏字必须在 [32, 32+P/4) 内；P=64 时破坏 word 48（尾部填充区）不会被检出（payload CRC 不覆盖尾填充）——首轮曾因此漏检。
- L3（TB 挂接方式）: 新 TB 经 run_sim.ps1 -TbFiles 直接编译，不必改 sim/compile_checked.f（该清单只列 RTL 依赖）；减少对冻结清单的写入面。
- L4（集成固有延迟）: o_* 调试字为 tl 域两级同步（最长 ~2-3 tl 周期），断言前需 ≥3 个 tl 边沿稳定窗；对逐帧精确 CRC 比对尤其重要（否则会读到上一帧值造成假象）。
- L5（预算与自纠）: 编译笔误与断言口径错属于开发内自纠，应在 dev-notes 如实登记、不冒称"零失败"；vlog 的既有警告（pcie_ep_engine.v RDGN）须与本次变更区分，避免误报为回归。