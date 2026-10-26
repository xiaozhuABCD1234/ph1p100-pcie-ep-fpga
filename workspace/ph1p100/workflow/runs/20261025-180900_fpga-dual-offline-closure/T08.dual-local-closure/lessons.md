# T08 round0 lessons

- R10F session is header word4; word6 is mode_id. Bind descriptor identity against the frozen writer header definition, and clear every sticky extended checker flag at each new start.
- cl_pub_valid is a pulse in DHI. Separate per-camera/per-slot mailboxes accept simultaneous pulses; ready/valid is applied only after the pulse has been safely stored. A/B release routing must be tested independently with wrong-camera, stale-epoch and duplicate identities.
- A checker abort does not revoke an offered or accepted AXI request. Keep the registered AR skid, count all expected R beats, drain before release, and retain ownership in LOCK when a response never returns. Recovery requires common DDR reset to clear both the model queue and ownership.
- Preserve the frozen b10 read_mask and transaction timeout when giving sync control exclusive use of the same real I2C. Standby and stop expected read values must follow their safe initialization overrides. Pin-only read memory is separate from DUT expectations.
- Regeneration must always start from verified immutable inputs. Reusing a previously patched local closedloop file duplicated expectation port connections; compile logs retained the error and the generator was corrected.
- The A/B sync role transaction counts differ. Check the exact request-to-pin byte sequence for each camera; do not impose the A count on B. Model readback emits 49 actual random reads per camera.
- A low-risk DeepSeek pure byte-checker proposal saved repetitive parsing work. It had no project tools or pending operations, and was independently checked with a W16H3 vector and nine rejected corruptions before use. It does not replace integrated acceptance.
- Small offline cases and static default-size bounds cannot be reused as production G2, exposure synchronization, board recovery or dual-1080p30 throughput evidence.
