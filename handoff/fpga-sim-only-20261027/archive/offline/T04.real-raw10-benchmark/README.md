# T04 真实 RAW10 收益基准准备

真实收益结果为 `blocked`。没有合格的真实 RAW10 输入，`real_sample_count=0`、`ratio=null`。合成对照通过只说明本软件工具的定向检查通过。根编码器与严格 DEFLATE parser 均只读；未运行 TD、硬件、下载或 RK 工作。

输入入口是 `inputs/real-inputs.json`；结构见 `inputs/input-schema.json`。当前 samples 为空，后续恢复须新建输入配置和新结果目录，不覆盖本次冻结件。输入文件支持绝对路径或相对配置文件目录的路径。每个样本必须给原始文件 SHA、规范化 packed RAW10 SHA、来源类别、content_id、W/H/stride、ROI、Bayer 相位、来源/设备/格式/许可依据。

`packed_raw10` 必须 W%4=0，stride=W*5/4，每组四像素按 MIPI RAW10 的四个高8位字节和一个低2位拼接字节存储。`u16` 必须 stride=W*2，并明确 `normalization.byte_order=little|big`、`valid_bits=10`、`right_shift=0..6`；右移丢弃的位必须全0，移位后每像素必须<=1023。工具不猜测字节序、不截低8位、不推断行padding、不执行隐式ROI裁切。文件已是所声明的ROI；ROI必须在源几何内，宽高必须等于输入宽高。

`mode` 每次运行唯一，含 prep/pred=0|1；pred=1要求prep=1。未知相位和非RGGB相位仅允许 mode=00。phase0 预处理只接受 RGGB 及可追溯的 `phase_evidence`，任何上游相位规范化须在该证据和 format_basis 中说明。输入W<=1920符合参考编码器每两行<=4800B的块限制；最大规范化帧64MiB，最多32样本。

真实样本 `category=sensor_capture` 的 provenance 还必须是 source_kind=sensor_capture、sensor_pixel_oracle_verified=true，并有 pixel_oracle：method、reviewer、correctness_basis、evidence_path、evidence_sha256、normalized_raw_sha256、review_decision=qualified。独立像素正确性证据须逐样本绑定规范化RAW SHA。代码验证声明、文件与SHA的相互一致性；声明真实性、实拍来源、正确性依据是否充分由原规划/独立测试复核，SHA和可逆压缩不能自行证明传感器像素正确。

b18 交接样例只登记为 historical_control：其原始抓取真实，但 expected.json 明示 sensor_pixel_oracle_verified=false、物理相位unknown。它不进入 real-summary。本次未重跑其解码；未读取T03/T08活动日志。N/L、CONTENT=2、ramp、随机和常量生成像素都不是实拍。

在本包目录执行（路径含空格时为Python完整路径加引号）：

```powershell
& 'C:\Program Files\Python311\python.exe' -B benchmark.py --config inputs/real-inputs.json --output local/real-benchmark
```

上述是本次已执行的空输入入口，返回码3是预期 blocked。首次运行生成目录后，重放请另选不存在的输出目录，例如 local/recheck-empty-01；工具拒绝覆盖原输出。有效输入但有拒绝项时返回码2；至少一个合格真实样本且无拒绝项时返回码0，语义为软件测量完成，不是独立验收PASS。

合成控制可执行入口：

```powershell
& 'C:\Program Files\Python311\python.exe' -B verify_controls.py controls-recheck-01
```

必须选新目录名。该入口生成 packed、u16 LE、u16 BE+shift6、噪声/常量控制，运行00/10/11与奇数尾行逆变换，验证拒绝与分类门。结果标签始终 synthetic_control；历史分类负对照也是合成payload，只检验排除逻辑。它不替代真实b18历史解码。

输出 benchmark.json 及分开的 real-summary.csv、synthetic-controls.csv、historical-controls.csv。每帧包括 raw/zlib/A1U1/dma字节数、三种 raw/传输字节比率、44B头与4096对齐开销、stored_blocks/block_count与stored_raw_bytes/raw_bytes两种回退比例、四CRC、源/解码SHA和逐字节差异数。汇总严格用总字节相除，每个输入在当前唯一模式只统计一次；三幅以上且content_id至少三种才可称有限真实图集，一幅仅单样本。内容不同仍由来源证据复核，content_id文本不能自行证明。

A1U1由本工具按原44B格式离线组装，不使用a1_ref的A1T1 record。独立flat-index逆变换不调用编码器inverse_frame；严格parser和Python zlib均核对DEFLATE长度/EOF/尾部。回退两比例来自独立strict parser的stored_bytes，并与编码器block_sizes/type交叉核对。dma_bytes=align_up(44+zlib_bytes,4096)是离线参考布局，不能混同当前硬件align_up(zlib_bytes,4096)描述符。工具结果不表明FPGA吞吐或H-only/A+H收益。

准确恢复条件：原规划提供至少一份原始实拍RAW10（或声明清楚的u16容器）及上述逐样本证据；三幅内容不同才恢复为有限图集测量。新配置从本schema编写，创建新round输入/输出后由原规划续此开发角色，不修改manifest-r0绑定的任何件。原规划也可单独决定是否安排有限工具核验；当前不得申请真实收益PASS。
