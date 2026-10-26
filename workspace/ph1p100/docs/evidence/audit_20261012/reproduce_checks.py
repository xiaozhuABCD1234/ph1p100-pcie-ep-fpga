"""Read-only arithmetic and test-pattern checks for the 2026-10-12 review.

Run from any directory with Python 3. No third-party dependencies.
The mutation below is a memory equivalence calculation, NOT an RTL simulation.
"""
import json
import zlib


def main():
    capacity_words = 1 << 16
    frame_bytes = 960 * 540
    original = bytes((13 + j) & 255 for j in range(frame_bytes))
    mutated = b"".join(
        original[(offset & ~(1 << 4)) * 32:(offset & ~(1 << 4)) * 32 + 32]
        for offset in range(frame_bytes // 32)
    )
    assert original == mutated
    rows = []
    for name, size in [
        ("preview_GRAY8", frame_bytes),
        ("1080p_GRAY8", 1920 * 1080),
        ("1080p_RAW10", 1920 * 1080 * 10 // 8),
        ("1080p_RAW12", 1920 * 1080 * 12 // 8),
        ("4K_RAW10", 3840 * 2160 * 10 // 8),
    ]:
        words = size // 32 + 1
        rows.append(dict(
            format=name, frame_bytes=size, words_including_footer=words,
            fits_16bit_word_offset=words <= capacity_words,
            dual_30fps_MBps=size * 60 / 1e6,
            ddr_2R2S_raw_fallback_MBps=size * 60 * 4 / 1e6,
            six_raw_slots_MiB=size * 6 / 2**20,
        ))
    print(json.dumps(dict(
        bandwidths_are_requirements_not_measurements=True,
        formats=rows,
        pattern_mutation=dict(
            method="memory-only equivalence; no mutated RTL simulation",
            forced_zero_address_bit=4,
            payload_identical=original == mutated,
            original_crc32=f"{zlib.crc32(original):08x}",
            mutated_crc32=f"{zlib.crc32(mutated):08x}",
            unique_addresses=len({offset & ~(1 << 4) for offset in range(frame_bytes // 32)}),
            footer_word_offset=frame_bytes // 32,
            footer_address_bit4=(frame_bytes // 32 >> 4) & 1,
        ),
    ), indent=2))


if __name__ == "__main__":
    main()
