# INT.P3 Lessons

- 双路 A/B 接入采用帧粒度身份调度，防止串帧/混路：仅一个描述符在 o_valid/o_ready 期间被呈现，通道在 release 身份匹配前保持 busy。
- B 路优先通过 b_priority 支持；A 路通过 a_enable 门控，b20 有效结果到达前可只推进 B 路，避免全线等待。
- 释放必须携带完整身份（camera_id/slot/epoch/session/capture_seq）；不匹配计数 st_rejected，不释放所有权，避免覆盖。
- A 路真实 b20 时序结果尚未取得；本包实现 A 路接口并门控，标记待 b20 有效结果，不声称 A 上板通过。
- G2 综合/STA/CDC/资源与 G3/G4 板测延后至 INT.P4/条件具备时。