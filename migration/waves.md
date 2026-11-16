# Wave plan

Waves move numbers in order of risk. Each wave has **entry criteria** (you may not start unless all are true) and **exit criteria** (you may not call it done, and may not start the next wave, unless all are true). A wave with unmet criteria does not go ahead because the date is fixed.

| Wave | Numbers | Why this order |
|---|---|---|
| 0 | None (build and test only) | Prove the platform with internal test numbers and a pilot team |
| 1 | CAT Hotline | Low everyday volume. A real number, real carrier path, and a place to prove the CAT switch. |
| 2 | KMH Servicing, KBU Broker, Care Line | Business hours only. Staff are on the floor. Care line needs a supervisor present. |
| 3 | KMH Claims, KMH Assistance | The 24x7 high-stakes lines. Moved only after servicing has been stable. |
| 4 | KRG Claims, KRG Servicing | Regional. Check agent network quality first. Last because they add no new learning. |

## Wave 0: build and test

**Entry:** requirements signed off; compliance review started; carrier contacts named; test numbers allocated.
**Exit:** all test cases for waves 1 to 4 that can run without live customers have passed; roll-back rehearsed with the carrier once on a test number; training complete for the pilot team.

## Wave 1: CAT Hotline

**Entry:** wave 0 exit met; CAT switch tested on a test number; change window booked; no severe weather warning for the window and the 48 hours after.
**Exit (after 5 business days):** no severity 1 or 2 incidents open; calls answered and recorded; call volume and answer rate within the agreed tolerance of the old platform; reports show the right numbers; the CAT switch drilled on the real number outside business peak.

## Wave 2: Servicing, Broker, Care

**Entry:** wave 1 exit met; agents trained and logged in during a dry run; care team lead on the floor; brokers told in writing at least 5 business days before.
**Exit (after 10 business days):** service level within tolerance; verify API p95 under target; no personal data found in a log search; complaints about the change at or below baseline; customer satisfaction not worse than baseline by more than the agreed margin.

## Wave 3: Claims and Assistance

**Entry:** wave 2 exit met; load test at 150% of the busiest hour in the last 12 months passed; DR rehearsal done; overflow and callback proven; incident manager and carrier on call for the window; no severe weather warning.
**Exit (after 15 business days):** same as wave 2, plus a CAT drill on the production claims number, plus one genuine busy day handled.

## Wave 4: Regional

**Entry:** wave 3 exit met; network tests passed from the regional sites.
**Exit:** same as wave 2.

## After wave 4

Hypercare ends only when the business signs it off (see `hypercare.md`). Cisco stays reachable for roll-back and for access to old recordings and reports until a formal decommission decision, which is its own piece of work with its own approval.
