# Who does what

R = does the work, A = answerable, C = consulted, I = informed.

| Activity | Insurer ops | Insurer risk/compliance | Carrier | NICE (platform) | Integrator / engineer |
|---|---|---|---|---|---|
| Requirements and call flows | A | C | I | C | R |
| Studio scripts | C | C | I | I | A/R |
| Integration API and AWS build | I | C | I | I | A/R |
| Phone numbers and routing | C | I | A/R | I | C |
| SIP trunks, SBC, carrier QoS | I | I | A/R | C | C |
| CXone platform availability | I | I | I | A/R | C |
| Recording policy and retention | A | R | C | C | C |
| Security testing | C | A | C | C | R |
| Material provider register and notices | C | A/R | C | C | I |
| Incident command | A | C | R | R | R |
| Regulator notifications | C | A/R | I | I | I |
| Training | A/R | I | I | C | C |
| Cutover decisions (go/no-go, roll-back) | A | C | R | I | R |

The point of a table like this: when something fails at 2 a.m., nobody should be reading it for the first time.
