两项仿真均已完成并通过独立验收，四个工作包全部首轮 PASS。

- [双路同步 I2C／生产数据路径仿真](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T08.sync-production-sim-r0-integrated.md)通过。
- [写入中复位、坏帧和溢出恢复仿真](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T10.a1-recovery-sim-r0-integrated.md)的20项用例通过，88包校验正确，恢复最慢10,042个A1周期。

为完成验证，修正了描述符队列和中止跨时钟域两处问题，均仅在run隔离副本中；未写回生产或上板。复位瞬间仍有旧读请求未完成的边界尚未覆盖。文件见[交付索引](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/delivery-index.md)。
