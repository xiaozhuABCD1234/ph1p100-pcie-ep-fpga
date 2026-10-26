# INT.P1 round1 lessons

- D1: parenthesized `(crc_latched || crc_ok) && (fe_latched || fe_ok)` to satisfy Verilog if-condition syntax.
- D2: moved `raw_mode` declaration before `u_algo` instance to avoid implicit/explicit wire conflict.
- D3: instantiated `frame_good_publish_cancel` in `integrated_input_processing_top` and connected frame progress/abort signals.
- D4: rewrote `tb_raw10_packer.v` to valid syntax and added packed-data assertion (`40'h3901000000`).
- D5: connected `st_he_published`, `st_he_rejected`, `st_gau_abort` from `img_algo_parallel_top` to internal wires.
- Cleaned `__pycache__` from tool inputs and regenerated manifest `INT.P1-r1-manifest.json`.
- Verified production RTL compile: 0 errors, 0 warnings; TBs pass.