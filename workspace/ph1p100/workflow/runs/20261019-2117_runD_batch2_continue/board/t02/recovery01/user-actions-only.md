# 你只需要照这个做（ChipWatcher 两次采样）

1. 你打开这个文件（若弹 “please ensure that there is only one bit file...” 警告：你点 OK，再重新打开下面这个文件；目录现在只有一个 bit，若再报错就截图发主）：
   `D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.cwc`

2. 如果软件问你要配对的 bit，你选：
   `D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.bit`
   只选文件，不要点下载/烧写。

3. 打开后你应该看到三个实例：`auto_created_cwc1`、`auto_created_cwc2`、`auto_created_cwc3`。界面文字可能略有不同；看不到三个就先截图。

4. 先做 T1：点 `auto_created_cwc1`，点 Add Signals / Watch，把这个实例的信号全部加入，然后点 Instant Trigger。看到数值后截图或导出。

5. 再点 `auto_created_cwc2`，同样 Add Signals / Watch → Instant Trigger → 截图/导出。

6. 再点 `auto_created_cwc3`，同样 Add Signals / Watch → Instant Trigger → 截图/导出。

7. T1 的三张图/导出文件，你保存到：
   `D:\anlogic\runa_runD\t02_ascii_20261019_234035\samples\T1\`
   文件名建议：`T1_cwc1.png`、`T1_cwc2.png`、`T1_cwc3.png`（有导出就同名 `.csv`）。
   同时记下你点第一次 Instant Trigger 的时间（时:分:秒）。

8. 等 25 秒（至少 20 秒），接线和电源都不要动。

9. 做 T2：对 `auto_created_cwc1`、`auto_created_cwc2`、`auto_created_cwc3` 再各做一次 Add Signals / Watch → Instant Trigger → 截图/导出。

10. T2 的文件保存到：
    `D:\anlogic\runa_runD\t02_ascii_20261019_234035\samples\T2\`
    文件名建议：`T2_cwc1.png`、`T2_cwc2.png`、`T2_cwc3.png`（或 `.csv`）。
    记下 T2 第一次点击的时间。

11. 回主这几样：T1/T2 文件路径、操作者名字、T1 时间、T2 时间、中间隔了多少秒、接线/供电有没有动过。可以直接发这一句：
    “T1=__:__:__，T2=__:__:__，间隔__秒；操作者__；接线/供电未动；文件在 D:\anlogic\runa_runD\t02_ascii_20261019_234035\samples\T1 和 T2。”

12. 如果窗口仍打不开、三个实例缺一个、或 Instant Trigger 没有波形：停下，截图错误原文发主。不要重试下载，不要换线，不要改电源/传感器表。

13. 你绝对不能做：不要重新下载；不要点 Flash/Program；不要换线/改电源/改传感器表；不要关 `td.exe` 45416；不要关/重启 `hwserver` 64540；不要开第二个 server。
