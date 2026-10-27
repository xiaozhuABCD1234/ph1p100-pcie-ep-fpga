# T03.rk-align-freeze 首次验收收束

原规划核读 dev-result 和三份完整报告，round0 三维 PASS，实际修复0轮，blocked=[]。唯一manifest=`candidate-manifest.json`，SHA256=`9662167a4af6fcea43a76491a9507b191552fa52209648147de02f91cfd877c5`。

功能独立检查230项、原84项夹具实际复跑通过；工程独立全量恢复2838 tracked+41 untracked+228回退文件=3107项并逐项SHA，git bundle verify/clone/fsck与17refs保留通过；系统逐源核对两层128B/单槽授权/RK必改、固定上游168+24文件及回退身份。动态main-log初始与稳定重取字节分开记录，不拼单一快照。system首次raw-blob换行诊断7项不等已用实际git archive逐字节复核归因为LF/CRLF，原失败输出保留，没有修复生产输入。

局部G0/G1通过；本包G2/G3/G4/G5事前不适用，正式双方签收、真实RTL/最终时序、DMA实收及板稳仍未完成。T03父任务继续active，不将子包PASS冒充G0双方签收；T07/T11父任务不置done。

初查仿真入口没有发现iverilog，Verilator3个入口失败。原规划从现有runner查到`D:/intelFPGA/18.1/modelsim_ase/win32aloem`，且Get-Command实际定位vsim/vlog于此。因此下一开发先验证已有ModelSim；不安装新工具、不改外部环境、不把此前未搜索ModelSim当缺工具阻塞。

下一派发：T07.rk-align-backend，新的唯一开发，新的三测试；后端目录/manifest独立，保留本包254项冻结产物原字节。硬件接入仅PnP枚举，不等于JTAG器件或RK已识别；正式SRAM板测独占窗口由下游system任务执行。
