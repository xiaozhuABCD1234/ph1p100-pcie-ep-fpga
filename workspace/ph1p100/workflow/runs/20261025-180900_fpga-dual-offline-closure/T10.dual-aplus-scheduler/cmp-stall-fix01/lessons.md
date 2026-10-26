# CMP correction lessons

A combinational priority choice is not an offer lifetime. Reserve the chosen slot before exposing valid, keep it READY through stall, and change it only at take/reset. Existing metadata arrays suffice when ownership prevents overwrite.

At take/refill exclude the just-taken slot using actual presented identity. A real commit on that edge may wait one cycle; it must remain READY and not be dropped.

The old counterexample uses real encoding, legitimate ACK and legitimate later input, with no internal slot-state forces. Compare every metadata field during stall and decode bytes by exposed source identity.

Keep old failed sources/evidence immutable and use a private library. New nominal CMP cases do not renew original faults3/3.
