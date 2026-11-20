# Living Town - Design Document (LOCKED V1)

Working title only. Name is not final and must be cleared before any public release.
Status: Design locked by Keith on 2026-11-20. No building before this doc. Building starts from this doc.
Platform target: Godot 4, 3D, single player, offline, free tools only.
Owner: Keith. Built by Neo and the one production team under the team charter.

## 1. The core idea

A city builder where the player does not build the city. The citizens do.

The player is the mayor, indefinitely in V1. The player plots land, zones it, passes bills and laws, sets taxes and incentives, approves or denies citizen requests, and puts public projects out to bid. The player never places a working business, never hires a worker, never sets a price in a shop.

Every business, job, house, debt, success, and failure belongs to a simulated citizen (a Sim). Sims are born, grow up, go to school, work, start businesses, borrow money, fail, recover or do not, grow old, and die. The city that results is the sum of their lives, not the player's construction.

Design test for every feature, now and forever: if the player can directly force an outcome that a Sim should be deciding, the feature is wrong.

## 2. Locked decisions (Keith, 2026-11-20)

1. Realism: as realistic as the team can make it, in systems first (life, money, debt, business, law, supply chains).
2. Time: watchable day by day and able to speed up. System picked by Neo, defined in section 9.
3. Mayor: the player stays mayor indefinitely in V1. Elections, removal, and term limits are designed for later, not built in V1. Approval, happiness, and protest are still tracked in V1.
4. View: 3D. Art is made by the team, procedural and modular, no bought assets required.
5. Scale: start small (about 100 Sims, one neighborhood) but architect from day one to grow as big as performance allows. No system may hard code the starting town size.
6. Debt: Sims carry accurate debt, can file for bankruptcy, and debt is settled accurately at death through the estate. See section 7.
7. Citizen requests: Sims request what the city needs and suggest where they want it. See section 8.
8. Construction: public building and roads are built by contractor companies through competitive bids. Outside companies bid at the start and are usually pricier. Local companies, once Sims found them, can bid too. See section 10.
9. Cost: the game must be buildable and runnable for free. Free engine, local simulation, no servers, no paid AI services, no per Sim cloud brains.

## 3. What the player does (mayor verbs)

- Plot and zone land: residential, commercial, industrial, agricultural, civic, park, mixed.
- Designate a need: mark a zoned area or publish a city need (for example, this town needs a grocery store) with optional incentives, a free or cheap lot, a tax break for a set number of years, a loan guarantee, or a startup grant from the city budget.
- Pass bills and laws: tax rates (income, property, sales, business), minimum wage, business licensing rules, building and health codes, school funding, police and fire funding, healthcare funding, welfare and unemployment support, debt and lending rules within city power, zoning rules, pollution rules.
- Run the city budget: income from taxes and fees, spending on services, city borrowing, city debt service.
- Approve, move, shrink, or deny citizen petitions and requests.
- Put public projects out to bid, review contractor bids, award the contract, live with the result.
- Respond to events: business closures, bankruptcy waves, crime rises, shortages, storms, a major employer failing.
- Watch: follow any Sim, family, business, street, or neighborhood over time. The watch tools are a core feature, not a debug extra.

The player cannot: place a business, hire or fire a Sim, set a shop price, force a Sim to start a business, force a Sim to stay in town, or delete a failing Sim or business.

## 4. The Sim mind (the make or break system)

Sims do not use a cloud language model. Each Sim is a data record with a layered mind that runs locally. Layers, in the order they influence a decision:

### 4.1 Needs
Hunger, energy and sleep, shelter, health, safety, money security, social contact, fun, respect and status, family duty. Each need has a current level, a decay rate, and a personal importance weight. Urgent needs dominate decisions. A Sim who cannot eat does not plan a business.

### 4.2 Personality (8 traits, 0 to 100)
Ambition, risk tolerance, discipline, honesty, sociability, intelligence, greed, kindness.
Rolled at birth, partly inherited from parents, partly shaped by childhood conditions and schooling. Traits bias every major decision. No trait alone decides an outcome, combinations do.

Emergent types the design must produce without hard coded classes:
- The steady worker: low risk, high discipline, low ambition. Keeps other Sims businesses alive for decades.
- The founder: high ambition, high risk, high intelligence or a strong skill. Starts businesses, some work.
- The gambler: high risk, low discipline. Fast rises, hard falls, repeat bankruptcies.
- The grifter: high greed, low honesty. Price gouging, fraud, corner cutting, possible crime career.
- The pillar: high kindness, high sociability. Organizes petitions, helps neighbors, may run for nothing but holds a neighborhood together.
- The drifter: low discipline, low ambition, bad luck or addiction. May contribute little, may become homeless, may recover late in life. The game never deletes or hides these Sims.

### 4.3 Ability
Skills (0 to 100, grow with practice and schooling, fade with disuse): cooking, retail and sales, farming, construction, repair, medicine, teaching, management, driving and logistics, finance, plus a general education level. Health status, age, disability, addiction status, and criminal record are ability factors too. Wanting a job or business and being able to do it are separate checks, and the gap between them is a main story engine.

### 4.4 Money and standing
Cash, bank balance, assets, debts (section 7), credit history and score, reputation with other Sims and with businesses, employment status, business ownership.

### 4.5 Memory and relationships
Each Sim keeps a bounded memory of major events: hired, fired, cheated, helped, robbed, a bad meal, a good employer, a loan denied, a parent dying, a bankruptcy. Memories decay slowly and bias future scoring. Relationships are pairwise and directional: family, friends, rivals, employer and employee, creditor and debtor, with trust and affection values updated by events.

### 4.6 Decision engine (utility scoring)
Decision points: every morning, and on major events (job loss, eviction notice, a city need published, a loan offer, a death in the family, a petition starting nearby).
The Sim lists actions it can actually take, scores each by: need relief, personality fit, ability fit, money effect, risk, memory and relationship effects, and distance and travel cost. The best scoring legal action usually wins, with a small randomness term scaled by risk tolerance so Sims are not robots. Illegal actions (theft, fraud, unlicensed business, tax evasion) enter the list when need or greed is high and honesty and perceived enforcement are low.
Every major decision writes a short plain reason to the Sim history log, so the player can open a Sim and read why he did what he did. This log is a required feature, it is how the player learns the minds are real.

### 4.7 Life stages
- Baby and child (0 to 12): dependent, needs met by caregivers or the city, schooling builds intelligence and skills, childhood conditions shape discipline and health.
- Teen (13 to 17): school continues, part time work possible, risk behavior peaks, may drop out.
- Adult (18 to 64): work, business, housing, partner, children, debt, savings, the main economic engine.
- Senior (65+): retirement if savings, pension, or family allow, health declines, may mentor, sell or hand down a business.
- Death: age, health, accidents, and untreated illness set the risk. Estate settlement runs (section 7.5). Family grief affects needs and decisions.

Birth: couples decide based on housing, money security, age, health, personality, and city conditions. Immigration: new Sims arrive when the town offers housing, jobs or business opportunity, safety, and services, and leave by the same math in reverse. Population is never set directly by the player.

## 5. Businesses (Sim owned, Sim run)

### 5.1 Starting one
A Sim starts a business when all of these are true in his own scoring:
- He sees an opportunity: unmet demand in an area (no grocery in reach, long waits, high prices at a monopoly, a published city need), or a skill he can sell.
- The math can work in his estimate: expected sales against rent, stock, wages, loan payments, taxes, license fees, and supply costs. His estimate can be wrong, optimism scales with risk tolerance and falls with finance skill.
- He can fund it: savings, a bank loan (credit check, section 7), a partner, family money, or a city incentive he qualifies for.
- He can legally open: license, zoning, health and building codes for that business type.
The player publishing a need and offering incentives raises the score. It never guarantees a start, and never guarantees the Sim who takes it is good.

### 5.2 Running one (daily operations)
Each business is a data record owned by one or more Sims, with: cash, bank debt, stock by product, supplier accounts, price list, wage list, staff roster, opening hours, condition and cleanliness, reputation, and a customer history.
Daily, the owner (or a hired manager Sim, using his own management skill) decides: order stock, set or adjust prices, hire, fire, schedule, repair, expand, advertise, borrow, or cut losses.
Customer Sims choose where to shop by price, quality, distance, reputation, habit, and their own budget. Customer service is simulated: staff skill, staff mood, wait time from staffing level, cleanliness, and stock availability produce an experience score per visit, which updates reputation and the customer memory. A rude or short staffed shop bleeds customers to a rival or to the next town.
Failure is normal and required: running out of stock, spoilage, over ordering, underpricing, overpaying wages, debt spiral, owner illness, a better rival opening. Closure runs a wind down: stock sold off, staff laid off (their lives continue), creditors paid in order, owner left with the personal result (section 7).

### 5.3 Business types (V1 slice first, full list is the growth path)
V1 slice: grocery store, farm, construction company, cafe, general store, landlord and rental housing, bank (city chartered, Sim run once the town is big enough, outside bank before that).
Growth path: clinic, pharmacy, school (private), repair shop, factory, warehouse and logistics, trucking, hotel, bar, childcare, funeral home, law office, real estate agency, and more, added as content packs on the same systems.

### 5.4 Supply chains
Every product has a source chain. Example, bread in the grocery: wheat from a farm (local if one exists, imported at higher cost if not), milling (local or imported flour), bakery or grocery baking, trucking or the owner pickup, shelf, customer.
Imports come from outside the city at a markup and with delivery delay, and the markup money leaves the town economy. A local producer undercuts imports, keeps money in town, and creates local jobs, but can fail, creating shortages. Shortages are visible: empty shelves, price spikes, petitions, Sims driving to the next town and spending there.
No product appears by magic. If no chain can supply it, it is not on the shelf.

## 6. Work and housing

Jobs exist only inside real businesses and city services. A Sim applies, the hiring Sim or manager scores skill, reputation, wage ask, reliability history, and distance. Wages are negotiated within a range set by law (minimum wage), market pressure, and the two Sims traits.
Unemployment is a real state with real effects: needs pressure, debt risk, skill fade, petition and crime pressure, and eligibility for city support if the player funds it.
Housing is owned or rented from real owners, including Sim landlords. Rent, condition, overcrowding, eviction for non payment, homelessness (sleeping rough, shelters if the city or a charity Sim provides one), and moving for work or family are all simulated. A house is also an asset and usually a mortgage (section 7).


## 7. Debt, credit, bankruptcy, and death (accurate system, Keith requirement)

### 7.1 Debt records
Every debt is its own record: debtor (Sim or business), creditor (bank, supplier, landlord, city, another Sim), type, original amount, current balance, interest rate, minimum payment, due day, secured by (house, vehicle, equipment, stock, or nothing), and status (current, late 30, late 60, late 90, in collections, charged off, in bankruptcy, discharged, paid).
Interest accrues on schedule. Minimum payments apply. Missing a payment has staged, real consequences, not an instant penalty flag.

### 7.2 Credit history and score
Built only from behavior in this town and any imported history for immigrants: on time payments, utilization of credit limits, defaults, collections, bankruptcies, length of history, and recent applications. Score gates loan approval, interest rates, loan size, rental approval, and some jobs. A young Sim with no history is not a bad Sim, he is an unknown, and lenders treat him that way until he builds a record, for example with a small secured loan or on time rent reporting.

### 7.3 Personal debt versus business debt
A sole proprietor and his business are the same legal pocket. Business failure reaches his house and savings.
An LLC or corporation separates them, if the Sim formed one (cost, paperwork, and advice gate this, finance and management skill affect whether he does). Corporate debt stays with the company, unless he personally guaranteed a loan, which banks will often require from a new founder, closing the loophole the way real banks do.
This distinction must be visible in the Sim panel in plain words, because it decides families futures.

### 7.4 Falling behind, collections, enforcement
Lenders and landlords act in their own interest on a realistic ladder: reminder, late fee, credit report hit, collections calls and letters, wage garnishment for some debts, repossession of a secured vehicle or equipment, foreclosure on a secured house, court judgment. Each step costs the creditor time and money, so small debts are often charged off instead, which still wrecks the debtor score.
Crime and desperation links: a Sim cornered by debt has rising scores for theft, fraud, illegal work, and leaving town at night. None of these are forced, they are scored like everything else.

### 7.5 Bankruptcy (a Sim decision, two main paths)
A Sim files when his own scoring says the debt cannot be repaid in a realistic time, after triggers like job loss, business failure, medical bills, divorce, or a foreclosure notice. Honesty, discipline, desperation, and advice from family or a lawyer Sim shape the choice. Some Sims who should file never do, and struggle for years. Some file too fast. Both are correct behavior for this game.
- Liquidation path (like Chapter 7): a trustee sells non exempt assets, unsecured debts are discharged, secured debts are paid from their collateral or the property is surrendered. The filing stays on the credit record about 10 years. House and business are usually lost. The Sim keeps exempt basics and can rebuild, slowly, at bad rates.
- Repayment plan path (like Chapter 13): the Sim keeps the house and possibly the business, pays a court set share of income for 3 to 5 years, then remaining eligible unsecured debt is discharged. Missing plan payments can convert or dismiss the case.
- Never dischargeable: recent tax debt, child support, and debts from fraud. Student style education debt, if added later, follows the strict real rule in force at design time and is flagged for review before it ships.
Creditors receive what the process gives them and take real losses, which feeds back into bank lending tightness for the whole town. A bankruptcy wave makes the next founders loans harder to get. That feedback loop is required, not optional.

### 7.6 Death and the estate (the accurate rule)
Children do not automatically inherit a parent debt. The estate pays.
At death, the estate is everything the Sim owned, minus what passes directly to a spouse by joint ownership. Creditors are paid from the estate in legal order: funeral and administration, taxes, secured debts from their collateral, then unsecured debts. Heirs receive only what is left. If the estate cannot cover the debts, the remaining debt dies unpaid and creditors take the loss.
Exceptions, all simulated: a co-signed or joint debt becomes the survivor full responsibility. A house with a mortgage can be taken by an heir who assumes, refinances, or sells it, the debt travels with the house, not the person. Shares in a business carry the business debts with the business. A spouse is liable only for joint debts (South Dakota is not a community property state, and the game uses that rule set, noted here so a future state law option can change it deliberately).
A Sim may voluntarily pay a dead parent or spouse bill out of kindness, duty, or family pressure. That is a scored decision, never an automatic transfer.
Gameplay consequence that must work: a Sim who looks rich can die deep in hidden debt and leave his family a shock and an empty estate. The family story continues from there.

### 7.7 City debt
The city borrows the same way, bonds or bank loans for projects, with interest, a credit standing shaped by budget history, and debt service that crowds out services. A town that borrows for everything will feel it for a generation of Sims.

## 8. Citizen requests and petitions (Keith requirement)

Sims tell the mayor what they need, and where they want it.
Generation: unmet needs at neighborhood scale create requests, parents for a school near home, seniors for a clinic near the apartments, workers for housing in a price range that exists nowhere, shoppers for a grocery on their side of town, business owners for a road fix or parking near their street.
Each request record holds: what, why (the real sim data behind it, travel times, wait times, prices, unmet need counts), who started it, signatures gathered over time (sociability, reputation, and how real the need is drive signing), a suggested location (near the affected Sims, on land that fits zoning and budget), and any offers attached (a Sim offering to run it, co-fund it, or donate land).
Mayor responses: approve as asked, approve at a different site, approve a smaller or cheaper version, publish it as a city need with incentives (section 3), or deny with a reason picked from a list Sims can react to.
Consequences: approving where asked grows trust and that area. Moving it can waste the money if Sims still cannot reach it. Denying or ignoring a real need pushes Sims to solve it themselves (a private or even unlicensed version may open), to petition harder, to protest, or to leave town. The request list is the main planning lens of the game and gets a first class screen, sorted by need strength, signatures, and cost.

## 9. Time system (Neo pick, locked)

The simulation tick is one day. Every Sim, business, loan, and city account gets a full daily update at every speed. Speed changes only how much the player watches.
- Pause: planning, zoning, laws, bids, reading Sims and petitions.
- Watch: one day in about 2 minutes of real time. Hourly routines are visualized for Sims near the camera, wake, eat, travel, work, shop, home, sleep.
- Normal: one day every few seconds. A game year in roughly half an hour.
- Fast: one week per step, daily updates still run, visuals sample the results.
- Turbo: one month per step, interrupts on major events the player marks as important (bankruptcy filing of a watched Sim, a major opening or closure, a petition crossing a signature threshold, a death in a watched family, a city budget crisis).
Seasons and weather run on the calendar and affect farming, construction speed, illness, heating costs, and travel. Aging is one year per 365 ticks, no compression tricks, because the daily honesty is the product.

## 10. Public projects and contractor bids

The player never builds directly. A road, school, water plant, clinic, or any civic build runs this pipeline:
1. The player (or an approved petition) defines the project, site, and a budget ceiling.
2. The project goes out to bid for a set number of days.
3. Bidders: outside companies always bid early in a towns life, at a markup, with travel delay, and the money leaving the town economy. Local construction companies bid once Sims have founded them, usually cheaper, hiring locally, money stays in town.
4. Each bid shows: price, duration, quality grade history, crew size, warranty, and the company record (past overruns, late finishes, defects). Bids are generated from the bidding company real state, its crew skills, current workload, greed, and honesty. A dishonest company may low bid and plan change orders, or cut materials.
5. The player awards the contract. Cheapest is a choice, not a default answer.
6. Construction runs in visible stages over the promised time, with weather, supply, and labor effects. Overruns, delays, defects, and kickback offers to city staff are possible events with real paper trails in the project record.
7. Finished quality is a lasting property: a good road lasts, a bad one needs repair in a few years, and the repair is a new bid. The company reputation updates from every job, and Sims remember.

## 11. Laws and bills (how they work)

A law is not a button that sets an outcome. A law changes numbers inside Sim and business scoring, and the town responds over time.
Worked examples the design must reproduce:
- Minimum wage up: worker money security and spending rise, thin margin businesses cut staff, raise prices, or close, teen jobs shrink, petitions shift from wages to prices and unemployment.
- Business tax down with a startup incentive: more founders score a start as worth it, city income falls, services strain unless growth makes it up.
- School funding held high for a decade: the cohort that passes through it reaches adulthood with measurably higher intelligence and skills, and the towns business quality rises a generation later. Cutting it saves money now and costs the town later, after the player has forgotten doing it. The game should remind him, through the Sims.
- Police funding cut: crime scoring rises where need is high, safety needs fall, good businesses and families start leaving, which cuts the tax base, which pressures the budget again.
Every law shows, before passing, a plain estimate of who it hits and its yearly cost or income, and after passing, its real effects are tracked on the city dashboard against that estimate.

## 12. Crime, health, and hard realism

Keith call: as realistic as possible. Included, simulated through the same needs and scoring, never as random decoration:
Crime (theft, burglary, fraud, assault risk in unsafe areas), policing, courts, fines, jail time that removes a Sim from work and family life, a record that follows him.
Health: illness, injury at work, chronic conditions, pregnancy and birth, mental health under sustained need pressure, addiction (alcohol, gambling, drugs) as a scored coping behavior with health, money, and family damage, treatment if the town has it.
Poverty: homelessness, hunger effects on children schooling, utility shutoffs, eviction.
None of this is graphic. It is shown through lives, panels, and outcomes, the way the rest of the game shows everything. Content limits for release (ratings, store rules) get a gate review before any public build, and are flagged here now, not discovered later.

## 13. 3D art plan (team made, procedural, modular)

Style: realistic proportions, clean low poly, good light and shadow, painted and procedural textures. Not photoreal faces. The art serves the simulation, a building must show its state.
- Buildings as modular kits in Godot: foundations, framing, finished shells, roofs, storefronts, signs generated from the real business name, interiors suggested through windows and props. A building visibly ages, gains additions, and shows neglect when its owner is broke.
- Business state is visible: a stocked, lit grocery with customers, against a failing one, dim, sparse shelves seen through glass, a hand lettered sale sign, then boarded.
- Sims: varied height, build, age stages, hair, skin, clothes by job and income, carried items, simple reusable animation sets (walk, work, carry, sit, talk, drive). Age must read at a glance.
- Vehicles: cars, pickups, delivery trucks, farm and construction machines, tied to real trips and jobs, not ambient decoration.
- Construction: sites rise in real stages matched to the contract progress in section 10.
- Land: terrain, roads that wear, lots, farms with crop stages, trees, seasons changing the look of the town.
Art is code and kits first, so a new business type needs a kit variant, not a one off model. No Blender dependency is assumed in V1, models are built procedurally in Godot and from team made meshes and textures. If a later phase adds Blender, it is free and optional.

## 14. Technical architecture (start small, built to scale)

Engine: Godot 4. Language: GDScript for game logic, with the daily simulation written data first so a later move of hot loops to a faster path stays possible.
Core rules, non negotiable from the first commit:
- Sims, businesses, debts, and requests are data records (dictionaries and resources in typed arrays), not scene nodes. The scene tree only shows what the camera is near.
- Tiered simulation: Tier 1, Sims near the camera or on the watch list, full hourly routine visualization. Tier 2, the rest of the active town, full daily decisions, sampled visuals. Tier 3, outside town and background population, statistical only. A Sim tier changes with camera and watch status, his daily truth never does.
- Daily tick is deterministic from a seed plus player actions, so bugs can be replayed and saves can be verified.
- Road network is a graph. Trips are planned on the graph, travel time is computed, only Tier 1 trips are animated in full.
- Economy is double entry in spirit: money moves between accounts, it is never created by a sale screen or deleted by a closure. Imports and exports are the town boundary flows, and the bank and city are real accounts in the same ledger style. This is how debt, estates, and business failure stay accurate.
- Save format is chunked by system (citizens, businesses, finance, city, world), versioned from the first save, so growth does not break old towns.
- Performance budgets are acceptance gates, not hopes: V1 slice must hold its frame rate and tick time at 100 Sims on a modest PC, and the data design must be profiled at 1,000 simulated Sims in a headless stress run before V2 scope is approved.

## 15. Screens and player tools (V1 slice)

- Town view (3D), with time controls and speed interrupts.
- Mayor desk: budget, taxes, laws in force, propose a law, publish a city need with incentives.
- Zoning and plotting tools.
- Requests inbox: petitions with why, who, signatures, suggested site, and response actions.
- Projects and bids screen: define a project, compare bids side by side, award, track build stages and quality.
- Sim panel: needs, traits, skills, job, family, money, debts with plain language status, credit standing, history log with reasons.
- Business panel: owner, staff, stock, prices, reputation, accounts, debts, supplier list.
- City dashboard: population, births, deaths, moves, employment, average income, business openings and closures, bankruptcies, crime, health, happiness by neighborhood, budget versus law estimates.
- Family and town chronicle: a readable running history of major lives and events, generated from the history logs.

## 16. V1 slice scope (the first build, proving the minds)

One neighborhood, about 24 lots, about 100 Sims in about 30 households, generated with families, jobs seeded only by an outside employer and imports so the town must grow its own economy.
Must work in the slice, end to end:
Daily life and aging for a full game year at all speeds. Work, shopping, needs, and memory. One full business loop, a grocery started by a Sim (or failing to start, with the reason visible), supplied by imports and by a local farm if one starts. Debt: a bank or outside lender, mortgages or rent, credit building, at least one realistic path into bankruptcy and one estate settlement at a death. Petitions: at least the grocery and clinic or school request generated from real need, with a suggested site, and mayor responses that change outcomes. Contractors: one road or civic project through outside bids, awarded, built in stages, quality recorded. Mayor: zoning, one tax lever, minimum wage, publishing a need with an incentive, and the budget.
Explicitly not in the slice: elections, multiplayer, crime beyond theft scoring hooks, full law list, most business types, Tier 3 regions.

## 17. Roadmap after the slice proves out

V2: 500 to 1,000 Sims, more neighborhoods, crime and courts, health and clinic play, school cohorts maturing, local construction company founding and bidding against outside firms, LLC and partnership formation in full, business succession and sale.
V3: multiple districts, deeper supply chains and industry, transport and buses, city credit and bonds in full, newspapers and town chronicle publishing, elections designed and playtested as an optional mode.
Beyond: scale testing toward the largest town the architecture honestly supports, stated from profiling, never promised in advance.

## 18. Acceptance gates (nothing ships past a failed gate)

- A headless run of 365 daily ticks completes with no errors, no negative mystery money (ledger balances), and a written summary of births, deaths, jobs, openings, closures, debts, and bankruptcies that a reviewer can sanity check.
- At least one business in the acceptance run was started by a Sim decision, not placed by a tester, and its start reason is readable in its history.
- At least one debt spiral reaches a realistic resolution (repayment, bankruptcy, or estate settlement) with the paper trail intact.
- A petition is generated from real unmet need data, and a mayor response measurably changes what happens next.
- A contract is bid, awarded, and built, and its quality value persists and affects a later repair need.
- Independent acceptance review by a team member who did not write the system under review, with veto, per the one team rule.
- No em dashes and no stock AI phrasing in any player facing text. Plain words, like a person wrote it.

## 19. Risks and honest limits

- Scope is the top risk. This design is larger than any single past project. The slice exists to prove the minds before the town grows. If the slice minds are not fun to watch, growing the town will not fix it, and the team will say so.
- Performance at scale is unproven until profiled. Claims about maximum town size wait for the stress run in section 14.
- Realism has a ratings and store policy surface for crime, addiction, and child outcomes. Gate review before public release, flagged in section 12.
- Name, trademark, and store checks are required before any public listing. The working title is a placeholder.
- Free applies to tools and running the game. It does not make the work small. Time is the real cost, and the roadmap is phased for that reason.

## 20. Open questions (do not block the slice)

- Final name and art accent color.
- How much direct family control, if any, the player gets when following one household (watch only is the V1 answer).
- Whether elections ship as a mode in V3 or stay out.
- Sound and music direction.
- Mod support, if the architecture stays clean enough to allow it cheaply.

End of locked design V1, 2026-11-20.
