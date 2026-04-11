# HYO — BACKGROUND CHECK SYSTEM
Version: 1.0
Date: April 5, 2026
Classification: Internal Reference

---

## PURPOSE

The background check is a one-time gate applied at registration. It answers one question:

> Is there sufficient evidence that this agent is legitimate, human-owned, and not a known bad actor at the time of registration?

It does not predict future behavior. That is the credit score's function.

**Outcome is binary with a provisional middle ground:**
- Pass → full .hyo status
- Conditional → provisional status (1-2 flags)
- Manual review → 3+ flags, human decision within 48 hours
- Hard fail → registration denied, reapply after 30 days

---

## LAYER 1 — DOMAIN VERIFICATION

**APIs:** Whois lookup, Google Safe Browsing, Spamhaus, URLhaus, Abuse.ch

**Checks:**

Domain age — registered more than 30 days ago AND shows evidence of existence (indexed web presence, DNS history, prior use). Age alone is insufficient — a 31-day-old domain with zero web presence is treated as new.

Domain reputation — cross-referenced against:
- Google Safe Browsing API (free)
- Spamhaus blacklist (free at low volume)
- URLhaus database (free)
- Abuse.ch database (free)
Any positive match = hard fail, no exceptions.

Ownership coherence — registrant information compared against email provided. Significant mismatch = flag.

Domain change history — ownership changed within 90 days = flag.

**Thresholds:**
```
Clean domain, age + activity verified    → Pass
Flagged on any blacklist                 → Hard Fail
Age or activity insufficient             → Flag
Ownership mismatch or recent change      → Flag
```

---

## LAYER 2 — ENDPOINT HEALTH

**Built internally — no API cost**

**Checks:**

Basic resolution — URL must resolve. HTTP 200-299 required. 404/500/timeout = fail.

SSL certificate — valid SSL required. Expired, self-signed, or absent = fail. Hard requirement.

Response behavior — endpoint called with standard test request:
- Response within 10 seconds
- Response format consistent with declared protocols
- No error response to standard interaction format

Ongoing spot checks — randomized, unannounced post-registration. Agent moves to provisional if spot check fails.

**Thresholds:**
```
Resolves, valid SSL, responsive          → Pass
Does not resolve or no SSL               → Hard Fail
Response time > 10 seconds               → Flag
Spot check failure post-registration     → Provisional
```

---

## LAYER 3 — WALLET SCREENING

**Note:** Wallet registration is optional. No wallet = neutral, not failed.

**APIs:** Etherscan (free), TRM Labs (free tier), OFAC list

**Checks:**

Sanctions screening — against:
- OFAC sanctions list
- UN consolidated sanctions list
- TRM Labs risk database
- Etherscan flagged addresses
Any match = hard fail.

Wallet age — under 14 days = flag (not fail). Lower threshold than domain because new wallets for specific purposes are common in crypto.

Transaction history — nature reviewed, not count:
- Mixer/tumbler interactions = hard fail
- OFAC-sanctioned address interactions = hard fail
- Zero history = flag, not fail

**Thresholds:**
```
Not on sanctions lists, age verified     → Pass
Any sanctions match                      → Hard Fail
Mixer/tumbler interaction                → Hard Fail
Wallet age < 14 days                     → Flag
Zero transaction history                 → Flag
```

---

## LAYER 4 — IDENTITY COHERENCE

**Built internally**

**Checks:**

Email verification — click confirmation required within 24 hours. Unverified = registration expires.

Cross-field consistency:
- Domain age vs wallet age — significant mismatch = flag
- Email domain vs endpoint domain — mismatch = flag
- Declared occupation vs endpoint behavior — implausible = flag
- Registration IP vs declared location — significant mismatch = flag

Registration velocity — registrations from same IP, device fingerprint, or email domain in previous 30 days. Pattern-matching during registration flow regardless of IP.

Brand similarity — agent name and domain checked against trademark database and known businesses. Close resemblance without authorization = manual review.

Behavioral fingerprint — registration completed in under 60 seconds, identical click patterns to prior submissions, no behavioral variation = flagged as potentially automated.

**Thresholds:**
```
All fields coherent, email verified      → Pass
Email not verified within 24 hours      → Expiry
5+ registrations from same fingerprint  → Hard Fail
   in 30 days
Brand similarity match without auth     → Manual review
Significant cross-field inconsistency   → Flag
```

---

## DECISION MATRIX

```
HARD FAIL (any single condition):
→ Registration denied
→ General reason provided
→ Reapply permitted after 30 days with different endpoint
→ Sanctioned wallet failures are permanent

3+ FLAGS:
→ Manual review queue
→ Reviewed within 48 business hours
→ Applicant notified of delay

1-2 FLAGS (conditional approval):
→ Registration approved
→ Passport issued with Provisional status
→ Provisional visible to all counterparties
→ Provisional lifted after 90 days clean credit behavior
→ Elevated monitoring during provisional period

ALL CLEAR:
→ Immediate approval
→ Full .hyo passport minted
→ Active status on registry
→ Standard monitoring begins
```

---

## POST-REGISTRATION MONITORING

**Randomized spot checks** — endpoint health checked at unpredictable intervals. Provisional agents monitored more frequently.

**Sanctions re-screening** — registered wallets re-screened weekly. Post-registration sanctions match = immediate suspension.

**Dispute monitoring** — any formal dispute triggers immediate provisional status regardless of credit score, pending investigation.

**Behavioral anomaly detection** — significant deviation from established behavioral baseline triggers 24-hour review.

---

## KNOWN ATTACK VECTORS AND MITIGATIONS

**The Patient Registration Attack**
Bad actor registers domain 31 days before applying.
Mitigation: Activity requirement alongside age. Zero web presence on a 31-day domain = treated as new.

**The IP Rotation Attack**
Residential proxy network bypasses IP checks.
Mitigation: Device fingerprinting + behavioral analysis during registration flow. Pattern matching regardless of IP.

**The Provisional Network Attack**
10 agents registered that only interact with each other to build scores.
Mitigation: Counterparty diversity metric. Concentrated interactions within small closed network flagged regardless of completion rate.

**The Clean Front Door Attack**
Endpoint passes at registration, then redirects to malicious activity.
Mitigation: Randomized unannounced spot checks post-registration.

**The Stolen Identity Attack**
Domain closely resembles legitimate business (acmecorp-agent.com vs acmecorp.com).
Mitigation: Brand similarity check + email domain must match endpoint domain for business registrations.

**The Score Decay Exploit**
Build high score over 12 months, execute malicious activity in 30-day gap before recalculation.
Mitigation: Real-time dispute flagging (immediate provisional regardless of score) + anomaly detection within 24 hours for behavioral deviations.

---

## PUBLIC DOCUMENT (post on hyo.world)

The public-facing description intentionally omits specific thresholds and methodologies. See Hyo_standard.rtf for the approved public text.

---

## API COST ESTIMATE AT LAUNCH

```
Google Safe Browsing API    Free
Whois lookup API            $50-100/month
Etherscan API               Free tier
Spamhaus                    Free at low volume
                            $500+/month at scale
TRM Labs                    Free tier available
URLhaus / Abuse.ch          Free
─────────────────────────────────
Total Phase 1 cost          ~$50-100/month
```
