# T08 free-run verification lessons

- Anchor camera generation to absolute predeclared simulator times. Check source SOF/EOF counts and the checked receiver SOF count separately; an oracle that only checks accepted frames can miss source backpressure.
- Freeze and hash the actual candidate closure before reusing it. CRC include files live in different directories; resolve each from the old manifest rather than inferring a shared header directory.
- Resume-at-SOF is a real boundary: enabling the consumer does not free an owned slot on that edge. Derive the first eligible recovery frame from actual release/SOF observations and require every subsequent frame, including two consecutive final good frames.
- Combine per-cycle held-address exclusion with full held-slot snapshots, publication sequence conservation and transferred-byte checks. Any one alone leaves a plausible false success path.
- Compare complete identities across publication, descriptor take, native read and release. A single camera bit mutation may accidentally name another valid tuple; a negative identity case must state precisely why the resulting tuple is unowned.
- Keep the real checked CSI, writer, mailbox and ownership logic visible, and label vendor memory/PCIe and external consumer models. Reduced geometry and free-running packet inputs establish an offline contract, not camera/DDR/PCIe hardware performance.
