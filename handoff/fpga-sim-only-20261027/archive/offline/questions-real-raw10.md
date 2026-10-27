第三项还缺合格实拍输入。请提供：
1. 至少1帧传感器实拍RAW10或u16原文件的准确路径；若要有限图集结果，给至少3帧不同画面。
2. 文件的采集设备/原始来源及可使用依据，W/H、stride、packed RAW10或u16大小端/有效10bit/移位说明、ROI与Bayer相位（未知请明确）。
3. 已有的独立像素正确性依据或证据路径，例如可对照的原始传感器输出与解包检查记录。当前b18仅证明历史抓取/解码，sensor_pixel_oracle_verified=false，不能替代这项。

不用手工生成SHA或填JSON；拿到原文件及格式/来源后，恢复流程可生成哈希、输入配置并核对证据。现有工具支持每次明确00/10/11模式，未知相位只用00；需要phase0处理收益时另核对RGGB/相位规范化证据。
准确结构及恢复说明：D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T04.real-raw10-benchmark/README.md；全部成果与恢复文本：D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/handoff.md。

