# Mode ownership closure lessons

- Mode arbitration must include events accepted this cycle. Checking only old held/pending registers permits a publication to acquire an offer in one mode while another mode consumes it.
- Presentation registers require both ownership validity and a consumer-mode lifetime. Clear inactive-mode offer state and require offers/sent/reader state to be empty before changing consumers.
- Preserve valid idle transitions and every incoming pulse when rejecting a conflicting mode request. Do not mask pub or disable switching to satisfy the checker.
- An effective old/new counterexample drives legal ports through consumption and release, then reenters external mode and checks for phantom metadata. A same-checker old fixture and explicit B-route mutation demonstrate rejection without altering frozen evidence.
- Keep conservative wrapper/native accounting, prior overrun and failed/blocked manifests. This is repair1 completion before its first integrated retest, not a new r2 or a replacement verdict.
