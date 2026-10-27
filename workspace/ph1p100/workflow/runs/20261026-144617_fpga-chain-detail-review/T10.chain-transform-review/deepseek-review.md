# DeepSeek辅助复核

只向官方worker发送W/H、4800B块、stored成本与CMP字数；一轮completed、无操作请求，因此没有pending call_id需要resume。worker不访问文件，不承担最终判断。

拒绝其“每像素5字节”、偶数H中间公式、968bit约31字及从宽松上界推断实际stored溢出的表述。968bit约3.78个256bit字；worker给出的2,594,841B只是逐块独立max pad的宽松上界，不能称全stored实际长度。精确offset选择条件成立时用ceil累计成本归纳得到raw+5B+6=2,594,706B；全stored每块自然字节对齐。

Codex另从真实RTL识别obits/opq_bit_off尚未证明相等的问题，见F04。此问题并非worker发现，也不使用worker的错误推断充作缺陷。小见证自行编写并以zlib/严格解码/边界公式交叉核验；最终验收由独立综合测试者完成。
