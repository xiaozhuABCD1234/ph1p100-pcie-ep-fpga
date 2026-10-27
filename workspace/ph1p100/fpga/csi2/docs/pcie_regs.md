# PCIe BAR 寄存器表（D4 填实）

> 参考：官方 `D:\TD\work\peripheral\12_pcie_gen2x2\rtl\common\PCIE_REG_TABLE.v`
>      官方 `doc\uart_cmd_file_pcie.txt`（52 条测试命令）

## BAR 布局（当前 IP 配置，与官方 Gen2x2 参考一致）

| BAR | 使能 | 类型 | 大小 | 64bit | 用途 |
|---|---|---|---|---|---|
| BAR0 | ✔ | Memory | 1 MB | ✗ | **寄存器 + 帧数据窗口** |
| BAR1 | ✔ | **IO** | 256 B | — | 测试用 |
| BAR2 | ✔ | Memory | 1 MB | ✔ | 备用 |
| BAR3 | ✗ | — | — | — | BAR2 高 32 位 |
| BAR4 | ✔ | Memory | 1 MB | ✔ | 备用 |
| BAR5 | ✗ | — | — | — | BAR4 高 32 位 |

## BAR0 寄存器映射（D4 自己定义，先占位）

| 偏移 | 名称 | 读写 | 说明 |
|---|---|---|---|
| `0x000` | VER | R | 版本号，如 `0x0001_0000` |
| `0x004` | CNT | R | 递增计数器（用于验证往返） |
| `0x008` | LINK_STATUS | R | {pl_link_up, tl_clk_locked, pll_lock, ...} |
| `0x00C` | FRAME_NUM | R | 当前帧号 |
| `0x010` | FRAME_SIZE | R | 当前帧字节数 |
| `0x014` | CTRL | W | bit0=采集使能, bit1=压缩使能, ... |
| `0x100~` | FRAME_BUF | R | 帧数据窗口（D13 用） |

## 官方 52 条命令里可先对照跑的（D4）

```
cfg0rd / cfg0wr    配置空间读写
memwr  / memrd     BAR 内存读写
iow    / ior       BAR1 IO 读写
```
命令格式：串口发 `41 42 43 44 45 46 FF <cmd> <data>`（"ABCDEF"+FF）
完整清单：`D:\TD\work\peripheral\12_pcie_gen2x2\doc\uart_cmd_file_pcie.txt`
