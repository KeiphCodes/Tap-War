# V1 slice status against the locked design

Legend: **Done** works end to end in the slice. **Simplified** works, with a simpler rule than the full design. **Later** is out of the slice by design (section 16) or listed for V2 and V3 (section 17).

## Section 16, the slice must haves

| Must have | Status | Where it shows |
|---|---|---|
| One neighborhood, about 24 lots, about 100 Sims in about 30 households, jobs only from outside employers and imports at the start | Done | `LTWorld.default_config`, `LTPeople.generate_town` |
| Daily life and aging for a full year at all speeds | Done | five speeds, full tick at every speed |
| Work, shopping, needs, memory | Done | `people.gd`, `economy.gd` |
| A grocery started by a Sim (or failing to start, with the reason visible), supplied by imports and by a local farm if one starts | Done | founding plans, "looked and decided against it" logs, Valley Wholesale plus local produce |
| A bank or outside lender, mortgages or rent, credit building | Done | Prairie State Bank, mortgages, rent, on time rent starts a credit file |
| At least one realistic path into bankruptcy and one estate settlement | Done | natural runs, plus scenario gates in `tests/acceptance.gd` |
| Grocery and clinic or school petitions from real need, with a suggested site, and responses that change outcomes | Done | Requests tab, gate 4 compares against a control run |
| One road or civic project through outside bids, awarded, built in stages, quality recorded | Done | Projects tab, gate 5 compares two contractors |
| Mayor: zoning, a tax lever, minimum wage, publishing a need with an incentive, the budget | Done | Mayor tab, lot inspector |

## Section by section

| Section | Status | Notes |
|---|---|---|
| 1, 2 Core idea and locked decisions | Done | The player cannot place, hire, price or delete. Every mayor verb goes through `apply_action`. |
| 3 Mayor verbs | Done | Zoning, needs with four incentive kinds, nine laws, budget, city borrowing, five petition responses, bids and awards, watch list. Building and health codes, licensing rules and pollution rules are Later. |
| 4.1 Needs | Done | Ten needs with personal weights. Urgent needs block business plans. |
| 4.2 Personality | Done | Eight traits, inherited and shaped by schooling. The six types emerge and are named in the Sim panel, not hard coded. |
| 4.3 Ability | Done | Ten skills plus education, growth with practice and school, fade with disuse. Disability and addiction are Later. |
| 4.4, 4.5 Money, memory, relationships | Done | Bounded memory with decay, directional relationships with trust and affection. |
| 4.6 Decision engine | Done | Utility scoring with a randomness term scaled by risk tolerance, decision points weekly and on events (a published need, a denied petition). Every major decision logs a plain reason. |
| 4.7 Life stages, birth, immigration | Done | Babies to seniors, school, dropouts, retirement, couples deciding on children, arrivals and departures scored from the town's pull and each household's push and ties. |
| 5.1 Starting a business | Done | Opportunity, the Sim's own optimistic estimate, funding (savings, family loans, bank, city grant or guarantee), legal checks (zoning, license). |
| 5.2 Running one | Simplified | Stock, prices, wages, staff, condition, cleanliness, reputation, customer experience and memory are simulated daily. Opening hours and per visit wait times are folded into one experience score. |
| 5.3 Business types | Done for the slice | Grocery, farm, cafe, general store, construction company, landlord and rental housing. The bank is outside (Later: city chartered local bank). |
| 5.4 Supply chains | Simplified | Groceries and meals use local farm produce first and imports for the rest, with markup and delay. Milling, bakeries and trucking are folded into wholesale. |
| 6 Work and housing | Done | Jobs only in businesses, the city and outside employers, minimum wage, unemployment support, rent, eviction, relatives taking families in, homelessness, moving out, mortgages, foreclosure, private apartment building. |
| 7.1 to 7.4 Debt records and collections | Done | Every field in 7.1, the full late ladder, late fees, collections, judgment and garnishment, repossession, foreclosure, small debts charged off. |
| 7.2 Credit score | Done | From on time payments, lates, collections, charge offs, utilization, history length, inquiries, bankruptcy. No history is "unknown", not bad. |
| 7.3 Sole proprietor vs LLC | Done | Shown in plain words in the Sim and business panels. Banks require personal guarantees from new LLC founders. |
| 7.5 Bankruptcy | Simplified | Both paths, a Sim decision with pride, advice and desperation. Rules simplified, listed in DECISIONS item 15, flagged for review. |
| 7.6 Estates | Done | Legal order, joint and co-signed debts, mortgage travels with the house, business shares carry their debts, voluntary payment as a scored choice, the "looked rich, died in debt" shock. |
| 7.7 City debt | Done | Bank loans with a credit rating from debt service and late payments. Bonds are Later. |
| 8 Petitions | Done | Generated from real data with the numbers in the text, starters chosen by personality, signatures over time, suggested sites, offers from Sims, five responses, consequences including protests and Sims solving it themselves. |
| 9 Time | Done | Pause, Watch, Normal, Fast, Turbo with interrupts. Seasons and weather affect farming, construction, illness, heating and travel. |
| 10 Projects and bids | Done | All seven steps, including dishonest low bids, change orders, kickback offers with a paper trail, warranty repairs, and quality that sets the next repair. |
| 11 Laws | Done | Estimate before passing, tracked results after, on the City tab. |
| 12 Crime and health | Simplified | Theft hook, illness, chronic conditions, medical debt, clinic as a service. Courts, jail, addiction and mental health are Later (V2). |
| 13 Art | Done for the slice | Procedural kits, signs from real business names, visible states (lit and stocked, SALE and dim, boarded), seasons, Sims by age and work, commuter cars, delivery trucks, construction stages, road wear. |
| 14 Architecture | Done | Data records, tiered visuals (Tier 3 regions Later), determinism, road graph, ledger, chunked versioned saves, profiled at about 1,000 Sims. |
| 15 Screens | Done | Town view, Mayor desk, zoning (lot inspector), Requests inbox, Projects and bids, Sim panel, Business panel, City dashboard with charts, Chronicle. |
| 18 Acceptance gates | Done except the human review | `reports/acceptance_summary.txt` |

## Performance (headless, this build machine)

- 100 Sims: about 5 ms per daily tick, plus about 20 ms to refresh the UI.
- About 930 Sims on 168 lots: about 75 ms per daily tick on average, 136 ms worst (see `reports/stress_summary.txt`). Normal speed allows 3,000 ms per day.
- Rendering: about 150 draw calls for the starting town. In a software rendered headless browser it runs slowly because that renderer draws on the CPU; on a normal GPU it should hold a smooth frame rate, but this has not yet been measured on a real "modest PC", which section 14 requires before the gate can be called closed.
