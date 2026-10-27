# 试运行数据与接口约定

范围：纯Python标准库离线工具。复用主目录R10F字段表与另一工作树BPR1核心；本文件冻结trial范围，正式FPGA/RK协议仍待双方确认。新对话规划者在开工时复核来源与SHA，必要调整须留版本差异。

## A：非压缩严格接收

- 外层沿用R10F v1.0、128B小端头、codec_id=0；支持format=0 packed、format=1 u16le，packing分别0/1，valid_bits=10，block_count=1。packed每4样本5B；u16低10位有效，值>1023拒绝。
- 为控制范围，trial接收profile限camera_id为0/1、phase为0..3、bayer_dir=0、flags=0、roi_x=roi_y=0、mode_id=1；镜像/裁剪/其他模式明确报unsupported，不宣称生产支持。phase作为元数据保留，不推断真实相机相位。
- width/height正值，packed宽为4的倍数；上限width=3840、height=2160，载荷上限16MiB；u16可支持非4倍数宽。无行填充，stride严格对应格式，raw_bytes=stride×height；payload_bytes=align32(raw_bytes)，文件精确128+payload_bytes字节，所有填充/保留字节为0。
- 头CRC：清零0x58字段后覆盖128B；raw CRC覆盖有效图像字节；payload CRC覆盖含零填充载荷。先检查头、枚举、容量与精确长度，再解码，全部门槛满足才返回accepted及样本；拒绝返回稳定原因，不能暴露可消费的部分pixels。
- 合法数据至少覆盖已有8×4和64×48 packed/u16样例、全部phase、0/1023极值、无填充/有填充；独立字节锚点可用[0,1,2,1023]→`00 00 00 FF E4`，u16为`00 00 01 00 02 00 FF 03`。
- 异常矩阵覆盖magic/version/header_bytes、codec/format/packing/valid_bits、camera/phase/mode、flags/ROI/方向、保留字节、零/非法/超界几何、stride/raw/payload长度、短头/截断/多余尾字节、三层CRC、非零填充、u16高位。语义注错须重算头CRC，不能全被CRC门槛遮住；不要求每个笛卡尔组合。

## B：隔离压缩adapter

- 仅packed RAW10，几何和phase遵守BPR1限制；不新增算法或自适应选k。导入既有`encode_frame(raw,w,h,phase,k)`、`decode_frame(blob)`，k为0..10，默认2；不直接把压缩payload交非压缩parse_frame。
- BPR1内头固定36B，内层payload_bytes=P仅计行块，精确内封包长N=36+P；外层传输载荷L=align32(N)，总文件128+L；raw_bytes为恢复后的packed原长R。R可以大于L，禁止沿用非压缩R≤L假设。
- 外层头CRC沿用R10F；外层payload CRC覆盖完整BPR1加零填充；外层raw CRC覆盖恢复后的packed RAW。BPR1头CRC覆盖前32B，内层payload/行/原图CRC由既有codec校验。按N截取后解码，N之后仅允许规范零填充；不吞掉额外帧或任意尾部。
- 扩展使用明确trial profile：外层version=1.1、codec_id=`0x31525042`（本地试验标记，不分配正式枚举），format=0、packing=0、valid_bits=10、block_count=height。A仍仅接收v1.0/codec0，B显式识别此tuple；其他共同字段遵循A profile。不能让现有生产解析器误以为兼容。
- 内外width/height/phase/raw_bytes/raw_crc须一致，外层stride描述恢复后的RAW行；camera/session/capture_seq/mode/exposure/gain/timestamps等只在外层携带并往返保留。元数据不证明曝光同步或DMA会话正确。
- 正常回环至少有可压缩平坦帧、强制RAW回退行、同帧混合行、四phase、k边界及固定seed随机帧。包括1920×1平坦帧，验证R>L情形；所有恢复字节100%一致，不承诺压缩收益。
- 异常覆盖内层头/载荷/行损坏、内外元数据矛盾、错误N/P/L、内封包截断、非零对齐/多余尾部、未知扩展tuple；需部分重算外层CRC以触达内层检查。回退/混合行数量由codec返回结果或行头事实证明。

## 可复现与测试边界

未来工具提供统一`run_trial.py`入口（A/B选择、project-root、codec-root、out参数）和独立文件CLI；准确语法由开发者写README。建议复跑形态为`python -B <OUTPUT_DIR>/run_trial.py --task A或B --project-root <PROJECT_ROOT> --codec-root <实际codec工作树> --out <OUTPUT_DIR下新的证据目录>`，当前只是待实现入口，不是实际执行记录。

每次执行校验复用源SHA，显式使用路径，不能靠当前目录碰巧导入同名codec；禁写外部`__pycache__`。输出采用新目录或明确拒绝覆盖，不清理目录。功能测试查内容/拒收，工程测试查版本绑定/标准库/复现/写入边界，系统测试查CLI/元数据/恢复/兼容；都写同一冻结候选的独立报告。

已冻结：离线范围、trial枚举、长度/CRC语义、两批依赖与写范围。待开工复核：已有实现是否新增、Python可用入口、源SHA/dirty状态、最终CLI/API及manifest。正式协议/真实ROI/队友责任待后续；时钟、CDC、RTL、STA、DDR、PCIe硬核、板测、真实吞吐均不适用本次。
