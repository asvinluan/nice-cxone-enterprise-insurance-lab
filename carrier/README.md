# Carrier and telephony notes

The carrier is the real control point of a contact centre migration. This note lists what to agree, in plain words. Names and numbers are fictional.

## What the carrier does for you

- Owns the phone numbers and decides which platform each number rings.
- Provides SIP trunks to the CXone platform (or an equivalent path) and, during migration, keeps the old Cisco trunks working.
- Provides session border control, number translation, call recording hooks if used, and fault support.

## Agree before wave 1

| Topic | Agree | Why |
|---|---|---|
| Change windows | Dates, lead times, who can approve, emergency path | A missed window moves the whole plan |
| Number control | Per-number re-point, both directions | This is the roll-back |
| Roll-back time | A written maximum, rehearsed on a test number | The plan is worth only the rehearsed time |
| Capacity | Concurrent calls per trunk group, with headroom for CAT events | Surge is when trunks fail |
| Codecs and media | Supported codecs, DTMF method (RFC 2833/4733), packet time | Keypad capture depends on DTMF working |
| Caller line identification | Which CLI is presented on transfers and callbacks | Privacy and trust |
| Emergency numbers | Not routed through this contact centre; make sure no flow offers to call 000 on the caller's behalf | Safety |
| Resilience | Two diverse paths, two data centres if possible | A single trunk is a single point of failure |
| Fault support | 24x7 line, named contacts, severity definitions | CAT events do not wait for business hours |
| Reporting | Call detail records, trunk utilisation, failure causes | Needed for incident review and capacity |
| Security | Fraud controls, toll-fraud limits, access to the portal, who can change numbers | A number change is a powerful action |
| Evidence | Change tickets and CDRs retained | Auditors ask for them |

## CAT and surge

Ask the carrier what happens to your trunks when the whole region is calling at once. Ask for a surge plan: temporary capacity, call gapping, and a pre-recorded announcement option at the carrier edge if the platform is overloaded.
