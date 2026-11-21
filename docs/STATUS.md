# Status against the locked design

Everything the design document describes is built, including what section 16 left out of the slice and what sections 17 and 20 schedule for later. Two things are deliberately not built, with the reason: multiplayer (the design never designs it and its platform target is single player, offline) and direct family control (section 20 answers "watch only"). See `docs/DECISIONS.md`.

Checks: `tests/acceptance.gd` (the section 18 gates) and `tests/scenarios.gd` (every system beyond the slice) both pass. Reports are in `reports/`.

## Section by section

| Section | What is built |
|---|---|
| 1, 2 Core idea, locked decisions | The player never places, hires, prices or deletes. Every mayor verb goes through one logged action path. The player stays mayor unless they turn on the optional elections mode. |
| 3 Mayor verbs | Plot new land (annex rows into new districts), zone, publish needs with four incentive kinds, 20 laws, budget, bank loans and bonds, five petition responses, bids and awards, the watch list. |
| 4.1 to 4.5 The Sim mind | Ten needs, eight traits, ten skills plus education, money and standing, bounded memory, directional relationships, mentoring between generations. |
| 4.6 Decisions | Utility scoring with a risk scaled random term, weekly and on events, with a plain reason in the history for every major decision. Illegal choices (theft, burglary, fraud, tax evasion, skipping a license, drugs) enter when need or greed is high and honesty and enforcement are low. |
| 4.7 Life stages | Pregnancy, birth, childhood, school (public, county or private), teen risk and dropouts, adulthood, marriage, divorce, retirement, business hand down or sale, death and estates, arrivals and departures, leaving town at night under debt. |
| 5 Businesses | 21 types: grocery, farm, cafe, general store, construction, landlord, clinic, pharmacy, private school, repair shop, factory, warehouse, trucking, motel, tavern, child care, funeral home, law office, realty, mill, bakery, plus a city chartered local bank. Founding with savings, family loans, partners, bank loans, city incentives and outside investors. LLC or sole proprietor. Daily operations, pricing, hiring, layoffs, health inspections, closure wind downs. |
| 5.4 Supply chains | Farm to mill to bakery to grocery; farm produce to grocery and cafe; factory goods to the general store; imports with markup, freight (a local trucking firm hauls if one exists) and delay (a local warehouse shortens it); regional shortages; exports. |
| 6 Work and housing | Jobs at businesses, the city and named county employers; minimum wage; unemployment support; injuries and disability; rent with yearly reviews under a city cap; eviction; relatives and shelters; homelessness; renters buying homes; private apartment building at the zoned density. |
| 7 Debt | Every field of 7.1, the full collection ladder with a city cap on late fees, credit scores, sole proprietor versus LLC with personal guarantees, both bankruptcy paths, estates in legal order, child support and fraud restitution that survive bankruptcy, city bank loans and bonds, a bank tightness feedback loop, a local bank whose losses fall on a local owner. |
| 8 Petitions | Generated from real numbers, signatures over time, suggested sites, Sim offers, five responses with consequences, protests, recalls in elections mode. |
| 9 Time | Five speeds with interrupts, seasons and weather affecting farming, construction, illness, heating, travel, storms and fires. |
| 10 Projects | All seven steps, honest and dishonest bidders, change orders, kickback offers with a paper trail, warranty repairs, the building code's quality floor, quality that sets the next repair, paving annexed streets. |
| 11 Laws | Minimum wage, four taxes, school, police, fire and health funding, welfare and shelter, license fees, building code, health code, pollution rules, zoning density, rent cap, late fee cap, bus service, bank charter. Each shows an estimate before passing and tracked results after. |
| 12 Crime and health | Police detection, courts with optional lawyers, fines, jail that costs jobs and strains families, probation, records that follow job applications; illness, injuries, pregnancy, depression and counseling, addiction to alcohol, gambling or drugs with treatment and relapse; utility shutoffs; shelters. Nothing graphic. |
| 13 Art | Procedural kits for every building type with visible state, signs from real names, Sims by age, work and income, commuter cars, delivery trucks marked with the real hauler, the county bus, tractors, excavators, smoke when a factory pollutes, construction stages, road wear, seasons. |
| 14 Architecture | Data records, tiered simulation (Tier 1 drawn, Tier 2 full daily truth, Tier 3 the statistical county), deterministic replay, a growable road graph, the ledger, versioned chunked saves (version 2). |
| 15 Screens | Town view; Mayor desk; zoning in the lot inspector; Requests; Projects and bids; People; Business; City dashboard (charts, the county, where money is spent, health, courts, districts, laws versus estimates, roads); News (the weekly Prairie Hollow Ledger and the chronicle); Help; inspectors for Sims, businesses, lots, petitions, projects and debts. |
| 17 Roadmap items | Built now: more neighborhoods (annexing), crime and courts, health and clinic play, school cohorts, local construction bidding, LLCs and partnerships, succession and sale, districts, deeper supply chains, transport (bus), city bonds, the newspaper, elections as an optional mode. |
| 20 Open questions | Sound: procedural ambience and chimes. Family control: watch only. Mod support: business types, laws and outside employers are data tables in one place each, ready for a data file loader later. Name and accent color: still Keith's call. |

## Performance (headless, this build machine)

- About 100 Sims: a few milliseconds per daily tick, plus about 20 ms to refresh the UI.
- About 930 Sims on 168 lots with every system on: about 150 ms per day on average, about 290 ms worst (`reports/stress_summary.txt`). Normal speed allows 3,000 ms per day.
- Rendering: about 150 draw calls for the starting town. Not yet measured on a real "modest PC", which section 14 requires before that gate is closed.
