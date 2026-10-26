# B01 intended probes — no CWC generated

Status: development blocked before production build. This is an RTL probe plan, not a working debugger or physical-map qualification.

| Domain | Instance below u_top | Registers, each 32 bits | Coherence |
|---|---|---|---|
| DDR usr_clk | g_closedloop/u_readback | cl_identity; cl_seq; cl_base; cl_len; cl_session; cl_flags; cl_words; cl_header_crc; cl_payload_crc; cl_pass_count; cl_fail_count; cl_writer_good; cl_writer_bad; cl_fault | Result and writer counters latched together at checker completion; next result replaces entire record |
| cam_a_byte_clk | g_closedloop/u_algo | algo_identity; algo_y8_crc; algo_gau_crc; algo_he_crc; algo_y8_complete; algo_gau_complete; algo_he_complete; algo_rejected; algo_overflow; algo_inbeats | Source domain diagnostic snapshots; three branches terminate independently |
| cam_a_byte_clk | g_closedloop | source_good; source_bad; source_crc; source_header; source_geometry; source_injected | FE delayed 3 camera clocks; full-width source counters retained |
| tl_clk_user | u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark | Existing 9 dbg_mark_word registers | Baseline diagnostic sampling only; not used as ownership or integrity control |

cl_flags bits3:0 = length/payload/header/magic ok; bits15:8 = checker err. Identity DDR=0x434c0101, algorithm=0x414c0101. Complete 1080p requires cl_words=648192, cl_flags=0x0000000f. No cross-domain sample is atomic. CWC generation, actual clock binding, physical BID/ERAM coverage and bit pairing are all NOT_RUN. No safe board entry exists for this partial candidate.
