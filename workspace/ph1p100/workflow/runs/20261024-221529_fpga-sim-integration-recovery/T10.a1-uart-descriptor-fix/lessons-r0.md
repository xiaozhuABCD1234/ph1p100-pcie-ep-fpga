# T10.a1-uart-descriptor-fix round0 lessons

- 两项队列的索引必须显式模2；第三次读写是必要负对照。旧版真实第三次出队读到 xxxxxxxx，不能仅测头两帧。
- 计数应由同一拍真实接受的 push/pop 集中更新。同拍两者都接受时占用保持；旧版第二个非阻塞赋值覆盖第一个，实际 1 变 0。
- admission 使用旧 count。满队列同拍出队也拒新描述符，st_err 递增；修复不偷偷更换容量策略。
- 队列复位测试先证明 active E_OPEN 且 queued=2，复位后检查索引/计数/状态/统计，再以不同ID与不同源字节验新 epoch。
- 必须把计数断言和实际串行字节解析结合。严格 zlib/四CRC/完整源字节/无重复/无尾垃圾共同约束，避免 CASE_PASS/exit0 掩盖数据错误。
- 复跑入口与实际 argv 在 actual-commands.json；旧反例编译成功，分别命中 QUEUE_COUNT_MISMATCH 和 DESCRIPTOR_ORDER_OR_X。综合测试者应在自己的写域独立建库，不复用开发库作为独立重建。
