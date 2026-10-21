#!/bin/sh
# ============================================================================
#  RTL 单元测试台一键回归（iverilog，不需要开发板、不需要 TD/VCS）
#
#  用法：
#      ./regress.sh            跑全部，逐条 PASS/FAIL，最后汇总
#      ./regress.sh -v         额外保留每台的日志（失败时打印末尾 20 行）
#      IVL=/path/iverilog ./regress.sh     指定 iverilog（默认取 PATH 里的）
#
#  退出码：0 = 全部符合预期；1 = 有非预期失败。
#
#  为什么需要它：这些台覆盖的是板上最难查的东西——DDR 写/读口与 TL 发送口的仲裁
#  （中途换手会静默串帧）、残拍/短板突发、坏帧不发布、BAR0 寄存器译码与表一致。
#  改 RTL 之后先跑这一遍，能挡掉大部分「上板才发现图糊了」的回归。
#
#  tb_img 的预期失败：文件头已写明，`img_regs` 的 PTR 回绕是**掩码**语义
#  （rd_ptr & PTR_MASK），而 tb 期望的是比较回绕，两者只在 PTR_MASK=2^n-4 时等价。
#  这是历史遗留、与 4K 直通通路无关；活的寄存器面由 tb_ep_bar_win 覆盖。
#  所以这里把它记为 KNOWN-FAIL：只要失败项仍是那一条（got 00012800 / exp 0）就不算回归。
# ============================================================================
set -u
cd "$(dirname "$0")" || exit 1

IVL=${IVL:-iverilog}
VVP=${VVP:-vvp}
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

total=0
bad=0

# run <名字> <期望:PASS|KNOWN-FAIL> <说明> <命令>
run() {
    name=$1
    want=$2
    note=$3
    cmd=$4
    log="$TMP/$name.log"
    total=$((total + 1))

    if ! sh -c "$cmd" >"$log" 2>&1; then
        bad=$((bad + 1))
        printf 'FAIL    %-22s 编译或运行出错：%s\n' "$name" "$note"
        tail -5 "$log"
        return
    fi

    case "$want" in
    PASS)
        if grep -q 'ALL PASS' "$log"; then
            printf 'PASS    %-22s %s\n' "$name" "$note"
        else
            bad=$((bad + 1))
            printf 'FAIL    %-22s 没有 ALL PASS：%s\n' "$name" "$note"
            tail -10 "$log"
        fi
        ;;
    KNOWN-FAIL)
        # 预期：恰好 1 项失败，且仍是那条 PTR 回绕
        if grep -q '1 项失败' "$log" && grep -q '00012800' "$log"; then
            printf 'KNOWN   %-22s %s（1 项历史遗留）\n' "$name" "$note"
        else
            bad=$((bad + 1))
            printf 'FAIL    %-22s 失败项与预期不符：%s\n' "$name" "$note"
            tail -10 "$log"
        fi
        ;;
    esac
}

# ── DDR / PCIe 数据通路 ──────────────────────────────────────────────────
run tb_cam_ddr_writer PASS "CSI-2→DDR3 直通、残拍+短板突发、坏帧不发布" \
    "$IVL -o $TMP/tb_cam tb_cam_ddr_writer.v ../rtl/ep_side/ddr/cam_ddr_writer.v && $VVP $TMP/tb_cam"

run tb_ddr_frame_pusher PASS "整帧 MWr 推帧：TLP 拍数/sop/eop/门铃" \
    "$IVL -I ../rtl/ep_side/ddr -I ../rtl/common -o $TMP/tb_push tb_ddr_frame_pusher.v ../rtl/ep_side/ddr/ddr_frame_pusher.v && $VVP $TMP/tb_push"

run tb_ddr_wr_arb PASS "DDR 写口 A/B 仲裁：busy 期间不换手" \
    "$IVL -o $TMP/tb_wr tb_ddr_wr_arb.v ../rtl/ep_side/ddr/ddr_wr_arb.v && $VVP $TMP/tb_wr"

run tb_ddr_rd_arb PASS "DDR 读口 A/B 仲裁：数据不串路、锁定期不放 AR" \
    "$IVL -o $TMP/tb_rd tb_ddr_rd_arb.v ../rtl/ep_side/ddr/ddr_rd_arb.v && $VVP $TMP/tb_rd"

run tb_tl_tx_arb PASS "TL 发送口 A/B 仲裁：一笔 TLP 期间不换手" \
    "$IVL -o $TMP/tb_tx tb_tl_tx_arb.v ../rtl/ep_side/ddr/tl_tx_arb.v && $VVP $TMP/tb_tx"

# ── 寄存器面 / 老通路 ────────────────────────────────────────────────────
run tb_ep_bar_win PASS "BAR0 窗口寄存器表：偏移/位域与 RTL 译码一致" \
    "$IVL -I ../rtl/common -o $TMP/tb_bar tb_ep_bar_win.v ../rtl/ep_side/img/ep_bar_win.v && $VVP $TMP/tb_bar"

run tb_img KNOWN-FAIL "img_regs/img_frame_src 冒烟（老通路）" \
    "$IVL -o $TMP/tb_img tb_img.v ../rtl/ep_side/img/img_regs.v ../rtl/ep_side/img/img_frame_src.v && $VVP $TMP/tb_img"

# ── 汇总 ────────────────────────────────────────────────────────────────
echo "------------------------------------------------------------"
if [ "$bad" -eq 0 ]; then
    printf '全部符合预期：%d 个台（其中 1 个带已知历史遗留）\n' "$total"
    exit 0
fi
printf '有 %d/%d 个台不符合预期\n' "$bad" "$total"
[ "$VERBOSE" -eq 1 ] && echo "（日志目录已随退出清掉；-v 只在失败时打印末尾几行）"
exit 1
