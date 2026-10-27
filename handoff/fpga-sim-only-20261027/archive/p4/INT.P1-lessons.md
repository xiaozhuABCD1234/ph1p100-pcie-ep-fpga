# INT.P1 lessons

- ROOT-01: RAW10 must be repacked from 4x10-bit sample vectors to packed 5-byte words before A+ entrance; direct vector use is not equivalent.
- Good-frame publish must wait for last ROI sample, trailing suffix, CRC and FE verdict; late abort/re-SOF cancels commit.
- Three algorithms remain parallel hardware branches; mode router must not mix Y8 and packed RAW formats.
- Independent source-pixel oracle (raw10_pack.unpack_packed + image_algorithms_ref) confirms content, not only CRC.