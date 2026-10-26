# 保留的实际失败与修正

1. build_baseline.py首次退出1：FileNotFoundError WinError3，restore-check/tracked下叠加旧trial深路径超过Windows普通路径限制。原zip/bundle已经完成且保留；未删除未覆盖。将恢复目录改为新的restore-check-v2并用扩展路径，第二次退出0，3107项SHA一致。失败目录仍保留，未纳入候选文件逐项清单，因为它仅为未完成校验副本。
2. build_package.py首轮SyntaxError：Python3.11不允许f-string表达式内backslash。package-build.log保留。改为可信静态模板中的loc()替换。第二轮因regex额外双花括号未找到源证据，package-build-02.log保留；修正为匹配实际赋值后第三/四轮package_created=true。未更改生产输入。
3. Verilator原生--version exit -1073741511，输出空；Perl和MSYS脚本--version各exit127，输出Command Failed ulimit...exec /mingw64/bin/verilator_bin --version。只做工具查询，未安装/修复/构建；不作为当前DUT失败。未进一步重试。
