# lessons-r0 — T10.ah-a-plus-h-r2（A+H 原型，round0，kill）

只记可复用的根因/触发/修正/验证入口。

## 1. bench 通过 ≠ 调度改动等价（本任务主教训）

- 触发：在 H-only core 上加“2-position literal 扫描 + ≤16 bit 双符号 packer”（纯调度改动）。
- 现象：`comp`/`rand`（153,600 B、32 blocks）8b/16b 四组全部逐字节等价 + zlib 独立解码通过，
  但真实 1080p 内容（2,592,000 B/帧、540 blocks）`stream_len` 变短：N 1,677,912→1,665,923、L 2,156,868→2,153,391。
- 结论：**合成向量不是调度等价性的判据**。任何改变扫描/插入时机的改动，必须至少在真实内容的 1 帧上比
  `stream_len`/逐帧 caps（或直接比 token 流），再谈 4 帧。
- 观测签名（供下一轮定位）：literals 505,140→519,055、matches 397,627→401,672、fixed/stored 457/83→464/76，
  即“更多更短的匹配 + 更少 stored”。指向 htab 插入 epoch 漂移（成对提交时 `p+2` 提前一拍写入），
  但**本轮未证实**；次生现象是 A1U1 头 36..43 字节（stream_crc/header_crc）呈 X，来源亦未定位。

## 2. 双符号 packer 本身是安全的（可复用）

- 两个 8-bit literal 合成一个 16-bit `p0` 符号：`p0_nbits=16`、`p1_pshift ≤ 23 bit`、`ctot ≤ 23`、
  `nbw=2`、`cacc` 余 ≤7 bit，且 `pbit_off` 不变（16 mod 8 = 0）。**无需改 3 级 packer、无需加宽输出口**。
- 低字节=流中第一个字节（`{litcode1[7:0], litcode[7:0]}`），位序与逐符号追加一致。

## 3. 便宜闸门顺序与 kill 预算

- probe（620 s）先给出 N1 增益 92,707 < 100,000，已足够判“增益不足”；但**等价性只能由真实内容 4 帧暴露**，
  因此 4 帧仍要跑。最优做法：N4 先跑、看 `exp_bytes`/caps，再决定 L4（本轮 N/L 并发，省墙钟但多花一次 L4 预算）。
- 4 帧并发（2×~29 min，共用同一 `work` 库）只影响墙钟，不影响确定性周期计数（两次均 `exp/enc/exported=4`、`vec_bad=0`）。

## 4. 结构代价要显式记账（本轮未测）

- 把 htab 从“1 个寄存器读口 + 寄存器旁路”改成“2 个组合读口 + 2 个写口”，并给 bm_a 增加一次组合读：
  仿真可行且更简单（lane A 无需旁路，lane B 只需同拍 p+1 旁路），但 ERAM 读口/写口与组合读锥代价
  **未测**；任何实现资格都要 re-pipeline + TD/STA，不能由本任务推断。

## 5. 并发会话/记录去重

- 同一条长仿真可能被两个会话各记一条（一条带 run_tool 的 rc/seconds，一条只有墙钟估算、rc=null）。
  用 caps/log 时间戳与同一个 `exp/enc` 计数确认是同一进程；预算按 `rc!=null` 的记录求和（本轮 4,177.3 s），
  不要把全部记录相加（会得到 8,296 s 的重复计数）。

## 6. Windows/ModelSim 工具坑

- `Start-Process -ArgumentList` 传含引号的长参数会被重新切分导致子进程参数绑定失败（rc=1 且无产物）。
  改用 `Start-Job` + 参数数组（或写死参数的包装 .ps1）可靠。
- probe 的 `B11_FULL_TIMEOUT cycles=13300001` 是 export 后伪影（H-only 已记录）；4 帧才是 stall 判据。
- 4 帧 `.frm`/`.hdr` 是被动监视器的文本 dump（每行一个 hex 字节），头字节 36..43 若为 `xx` 要当作
  “X 观测”单独登记，不能当整数 CRC 用。

## 7. 计数差异（可解释、不影响字节）

- `stat_literals` 在 abort/stored 块内可与 H 差几个：成对提交可能把 H 守卫触发点的 literal 提前打包。
  bench 上 comp 差 0、rand 差 −20（均 byte-exact），probe N 多 +13,915（与 §1 的流不等价同源）。
- `rem_blk` 在本 core 中只喂 `rem_next_r`，不参与任何判定；成对提交时按 2 递减即可。
