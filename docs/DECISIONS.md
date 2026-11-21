# Decisions made while building the V1 slice

Keith gave full permission to make the calls needed to finish. These are the ones that matter, with the reason for each, so anyone can reverse them deliberately.

## Engineering

1. **Godot 4.4.1, GL Compatibility renderer.** It matches the engine of the original web build and is the renderer that runs in browsers. Free.
2. **Rebuilt rather than patched.** The original build shipped only compiled scripts. They were decoded and kept in `docs/recovered_prototype/`. The three systems in them did not line up (the sim engine wrote business intents like "grocery store" while the economy expected "grocery", wages were created from nothing, the ledger only tracked some flows), so the slice was rebuilt as one coherent set of systems that reuse the original names, data and intent.
3. **Money is whole cents in an integer ledger.** Every account sums to exactly zero at all times. The "outside" account is the world beyond the town line and is the only account allowed below zero. This makes "no mystery money" a check that can fail, not a hope.
4. **Systems are static scripts over one data object (`LTWorld`).** No reference cycles, trivial to save, easy to move hot loops to a faster language later as section 14 asks.
5. **Saves are binary chunks per system with a version header.** The first text format lost float precision and a loaded town drifted from the original. Binary keeps the replay exact.
6. **Determinism.** One seeded random generator, arrays in id order, all player actions logged with the day. The acceptance run replays and compares.
7. **Hourly routines are visual only.** The daily tick is the truth. Watch mode derives where a Sim is at each hour from their real job, school, home and the shops they use. This follows section 9 and the tier rule in section 14.
8. **Draw call budget.** Each lot is merged into one mesh with vertex colors (plus one for lit windows), roads are one mesh, trees are one mesh. Sims near the camera are capped at 45.

## Simulation numbers (all in one place in each system, easy to tune)

9. **Prices.** One person-day of groceries costs $8 at the outside supermarket. Wholesale from Valley Wholesale costs 70% of that plus a delivery fee and a 2 day delay (4 in snow or storms). Local farm produce sells to the grocery at about half the retail price. The surplus goes to an outside co-op at a low price.
10. **Business start up costs** are sized to what small town Sims could fund with savings, family money and a bank loan: grocery $32,000, farm $24,000, general store $18,000, construction company $16,000, cafe $15,000. A town of 100 can barely carry a grocery, which is realistic, and is exactly where the mayor's incentives matter.
11. **Founding needs a planning period.** A Sim plans for about three weeks (two if the city published the need) before committing, and writes "started planning" to their history. This stops herd starts on day one and gives the player time to see it coming.
12. **Outside jobs and wages** pay $110 to $170 a day by job and skill. Commuting costs $7 a day in fuel. Local jobs pay a little less but save the drive, so Sims switch when a local job opens.
13. **The city budget** gets property tax (1.5% a year), sales tax (2%), license fees, lot leases, business tax (6% of profit) and state aid ($22 per resident per month, as small US towns receive). The state pays most school costs; the city pays a local share per student. The county sheriff and fire service are contracts. Starting cash is $150,000.
14. **Bank lending tightness** rises with the bank's loss ratio on its loan book and with bankruptcies per 100 people, and relaxes slowly. This is the required feedback loop: a bankruptcy wave raises the credit bar and the rates for the next founders.
15. **Bankruptcy rules (simplified, flagged for review).** Liquidation keeps $7,000 of cash exempt, the trustee takes a 10% fee and pays unsecured creditors pro rata, secured debt in arrears is surrendered, sole proprietor businesses are liquidated. Repayment plans run 36 months under a $3,200 monthly income and 60 above, at 70% of spare income, and are dismissed after three missed payments. Tax, child support and fraud debts are never discharged. The filing blocks new bank credit for two years and weighs on the score for ten.
16. **Estates follow the order in section 7.6.** Joint ownership passes the house to the spouse outside the estate. The mortgage travels with the house. Then funeral and administration, taxes, secured, unsecured. Joint and co-signed debts pass to the survivor. Heirs never inherit debt. Paying a dead relative's bills, including a funeral the estate cannot cover, is a scored choice, never automatic. South Dakota rules: not a community property state. The homestead exemption is simplified to "the house goes to the surviving spouse or heir who takes it".
17. **A church food pantry exists** (funded from outside donations) so a broke household eats something. Without it, early builds starved Sims to death in a few months, which is neither realistic nor the story the design wants. Going to the pantry is logged.
18. **Petitions build slowly.** Nobody organizes in the first two weeks, at most one new petition starts a week, and signatures grow by roughly one or two a day. The first build had three petitions on the mayor's desk by January 3.
19. **Birth and death rates** were tuned against US rates for a town of about 100 (roughly one birth and one death a year, with variation by seed).
20. **Theft is a scoring hook only**, as the slice scope says. Desperate, dishonest Sims may shoplift or steal from a neighbor; police funding sets the chance of being caught; a record follows them into job applications.
21. **Outside contractors** keep the four names from the original prototype, each with its own honesty, greed, skill and crew. Riverbend Contractors low bids and plans change orders; its roads wear out fast. A dishonest bidder may offer the city clerk a kickback, and the clerk's honesty decides.
22. **Town name** "Prairie Hollow" and business names are placeholders.

## Building the full design (second pass)

28. **Nothing in the design is left out.** Keith asked for everything, so the systems the slice deferred are built: the full law list, every business type on the growth path, crime and courts, health and addiction, divorce and child support, the county region, districts, bonds, the bus, the newspaper, elections and sound.
29. **Elections are an optional mode, off by default.** Locked decision 3 says the player stays mayor indefinitely in V1, and section 17 asks for elections as an optional mode. Both hold: turn it on from the Mayor desk. With it on, a challenger runs on the town's real grievances, adults vote on trust and their own lives, and a long run of very low approval can force a recall.
30. **Multiplayer is not built.** The design never designs it, and its platform target is "single player, offline". Building it would contradict a locked decision, so it stays out until Keith designs it.
31. **Direct family control stays watch only**, which is the answer section 20 gives for V1. Following a household is fully supported through the watch list.
32. **Service spending goes through one spend book.** Doctor visits, prescriptions, repairs, child care, tuition, funerals, lawyers, realtor commissions, freight, storage, lodging and bars are paid through `LTServices.spend`, which picks a local Sim run business when one is open and fair, or sends the money out of town. Founders read the book to see what the town lacks.
33. **Large start ups can take outside investors** (factories, banks, hotels and anything over $40,000), who put in money for a share of the owner's draws. Without that, no Sim could ever raise $60,000 to $90,000 alone.
34. **The local bank needs a city charter and at least 120 people.** Its loans replace the outside bank's for new borrowers, its interest income stays in town, and its losses fall on a local owner.
35. **Crime rules.** Theft, burglary, fraud, tax evasion, unlicensed businesses, assault in unsafe places, drug possession and contempt for unpaid child support. Police funding sets detection. Trials come two to five weeks after a charge. A lawyer lowers the chance of conviction and the sentence. First minor offenses get probation; felonies and repeat offenses get jail, which costs a job after ten days. Restitution and fraud debts survive bankruptcy.
36. **Health rules.** Pregnancy lasts about nine months with checkups and six weeks of leave, and an outside employer may not hold the job. Risky jobs (construction, farm, factory, trucking) carry injury risk that skill lowers; a bad injury can leave a lasting disability that rules out heavy work. Long hardship can bring depression, eased by counseling. Drinking, gambling and drugs are scored coping choices with real costs; treatment is a choice pushed by family, discipline, age and city health support, and relapse is possible.
37. **Divorce.** Marriages wear down under money stress, addiction, jail and unhappiness, and build up with kindness. Child support is about 17% of income for one child, more for more, until the youngest is 18, and climbs the same collection ladder as any debt, with contempt charges after three missed months.
38. **The region** runs a slow business cycle (steady, growth, slowdown, recession, recovery) that sets outside hiring, layoffs, export prices and travelers. Six named county employers rise and fall; a failure lays off every town Sim who worked there.
39. **Annexed land** arrives unzoned with a gravel street that must be paved through bids. The exit to the highway and every lot's street are stored, so the graph can grow without breaking paths.
40. **Sound is synthesized in code** at a low sample rate (wind, rain, birds, chimes), so there are no audio files and it runs in the browser. A mute button is in the top bar.
41. **Performance.** Per day caches for market estimates, job seekers, debt stress, safety and open sites keep about 930 Sims near 150 ms per day. What remains is plain per Sim work, the hot loop section 14 expects to move to a faster language later.

## Scope calls

23. **The outside bank** (Prairie State Bank) serves the town until the city charters a local one (item 34).
24. **Schools and clinics exist both ways:** city services built through bids and staffed by city hires, and private Sim run clinics and academies that compete with them.
25. **The independent review gate** in section 18 needs a person who did not write the code. Everything else in that section is automated in `tests/acceptance.gd` and `tests/scenarios.gd`.
