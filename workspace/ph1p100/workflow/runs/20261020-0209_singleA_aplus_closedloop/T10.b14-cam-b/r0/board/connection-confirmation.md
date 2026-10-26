# T10.b14-cam-b — B camera connection confirmation (board precondition)

- Question (dev-plan §7.0): 第二颗 IMX415 模块是否已物理插在 B 口（MIPI-B: J19/H19, J22/H22, G17/G18, J20/J21, L19/L20; B I2C/control: H13/G13/G20/H20）？
- Answer: **已连接 / confirmed connected**
- Exact user statement relayed by the spawning session (2026-10-25/26 session):
  > 用户已确认第二颗 IMX415 物理连接在 B 口。
  > ("用户已确认第二颗 IMX415 物理连接在 B 口。")
- Effect: board run allowed; exactly 1 SRAM download first, then COM8 150 s.
  If B also shows no pixels the run stops and preserves A/B evidence (no second
  download, no Flash).
