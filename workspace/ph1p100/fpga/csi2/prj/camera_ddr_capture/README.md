# 相机真实帧DDR校验候选

本目录记录本机候选状态，工程由根目录 `tools/td/prepare_camera_ddr_capture.py` 创建到独立D盘目录。它组合已验证的相机/1080p60依赖与 `../ddr_frame_probe/vendor/` 原生DDR依赖，不覆盖活动相机工程。

源码入口是 `../../src/cam/` 和 `../../src/mem/`。A路960×540灰度帧经258位带标记异步FIFO、单token缓冲、三帧DDR后端，再逐字节读回校验CRC32；HDMI仍读原ERAM。写入DDR的每帧包含16200个图像字和一个元数据字，每字256位。

从仓库根目录准备独立工程：

```powershell
& 'C:\Program Files\Python311\python.exe' -X utf8 tools/td/prepare_camera_ddr_capture.py --phy-strategy TimingHigh
```

然后切换到命令输出的D盘目录，执行：

```powershell
& 'D:\downlaod\bin\td_commands_prompt.exe' './build.tcl'
```

这一步只综合、布线与报告。最终setup/hold/period、双向Gray skew、实际Q/LUT同步边界、异常目标、输入哈希及例外核验后，才运行独立bitgen门禁；返回码0不代表全部通过。TD应从工程根目录执行ASCII路径的Tcl，否则相对IP XML可能找不到。

本机位置、bit状态见 `LOCAL_STATE.json`。完整证据见根目录 `docs/evidence/camera_ddr_capture_20261011.json`；用户操作见 `docs/相机DDR真实帧_操作与预期_2026-10-11.md`。225520候选已获用户画面与状态灯预期反馈通过，表示至少一个完整真实灰度帧的CRC/元数据校验通过；没有持续计数或独立下载日志。绿色亮点仍在像素突变处出现，后续定位；HDMI仍读ERAM，DDR显示尚未实现。DDR电气裕量及持续稳定性尚未建立。
