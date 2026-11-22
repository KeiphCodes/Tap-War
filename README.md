# Living Town (working title)

A city builder where the player does not build the city. The citizens do.

You are the mayor of Prairie Hollow, a town of about 100 people. You zone land, pass laws, set taxes, answer petitions, publish city needs with incentives, and put public projects out to bid. Every business, job, house, debt, success and failure belongs to a simulated citizen (a Sim). Every big decision a Sim makes is written in their history with the reason, so you can open anyone and read why they did what they did.

This repository builds everything in `docs/Living_Town_design_document.md` (locked 2026-11-20), not only the V1 slice: 21 Sim run business types and a city chartered local bank, supply chains from farm to mill to bakery to grocery, crime with police, courts and jail, pregnancy, injuries, depression and addiction with treatment, divorce and child support, the full law list, city bonds, a county bus, annexing new land into new districts, the county economy around town with its booms, recessions and failing employers, storms and fires, a weekly town newspaper, optional elections, and procedural sound. Built in Godot 4.4.1. What is done, what is simplified, and what waits for V2 is listed in `docs/STATUS.md`. Every judgment call made while building it is in `docs/DECISIONS.md`.

## Game modes

Start a new town from the **New town** button (it also opens when the game starts):

- **Found a town:** you won the lottery ($250,000 hard, $1,000,000, or $5,000,000 easy) and bought open prairie with one county road running edge to edge. Nothing else is laid out. Use **Draw road** to lay straight streets anywhere on the survey grid (write the contract, press Go live, and contractors bid to build them) and **Plot lots** to mark lots beside your roads in any zone. Population: 1, and that's you, living in a camper until the mayor's house is built. Settlers come on their own, buy residential lots, and build their own homes. At 25 residents the town incorporates and city taxes and services begin.
- **Contracts and lot details:** every road you draw and project you start is a draft until you press **Go live**; contractors only bid after that. Tap a planned road (in Look, or with Draw road) to write its contract before it is signed: name, surface, width, sidewalks, streetlights, deadline and late penalty, and budget ceiling. Each choice changes the price, the schedule, the quality and how the street wears. Tap a city lot to set its zone, asking price and name, or hold it for the city; lots plotted in one stroke can be changed together.
- **Prairie Hollow:** start as mayor of a town of about 100 people with no grocery, school or clinic.
- Either way, choose **permanent mayor** or **elected mayor** (win the first vote after incorporation, then every four years, and watch out for recalls).
- Optionally run on the **real calendar**, starting today. Time stops whenever the game is closed. **Live** runs one game second per real second, and **Today** fast forwards (only forward) until the town's date and clock match yours, then keeps running live.
- **Milestones** on the Mayor desk track the town's big moments, from the mayor's house to 1,000 residents.

For now the player is a permanent resident with no needs of their own: the only goal is running the town well. Set your name, pronouns, age, hometown and color when you start, and change them (or rename the town) any time with **Edit your profile** on the Mayor tab.

Odds are realistic: weather follows the eastern South Dakota climate month by month, damaging storms reach town once or twice a year and mostly hurt run down or cheaply built buildings, house fires and other events happen at real US rates, and owners carry insurance. `tests/realism.gd` measures every rate against real figures.

## Play it

- **Online:** https://keiphcodes.github.io/Tap-War/ (published from `main` by CI).

- **In a browser:** open the exported web build (`build/web/index.html`) through any static web server, for example `python3 -m http.server -d build/web 8000` and then http://localhost:8000. The build uses the single threaded web template, so it runs on plain static hosting such as GitHub Pages with no special headers.
- **In the editor:** install Godot 4.4.1 (free), open this folder as a project, press Play.

Controls: the camera glides rather than jumps and stays over the map. Right drag turns it, middle drag or Shift plus left drag moves it, the wheel zooms, W A S D or the arrows move, Q and E turn. Click a lot or a Sim to inspect it. Every name in any panel is a link. On a touch screen, drag with one finger and pinch with two. Zoom in to street level to see the Sims and hear the town (weather, traffic, building sites, voices); zoomed out is a quiet planning map.

Time: **Pause** to plan. **Watch** runs one day in about two minutes and shows Sims near the camera walking, driving and working their real day. **Normal** runs a day every few seconds. **Fast** and **Turbo** jump a week or a month and stop on events that matter (a bankruptcy, a business opening or closing, a petition reaching the mayor's desk, bids arriving, a budget crisis, a death in a family you watch). Every speed runs the full daily simulation.

## Run the checks

```
godot --headless --import                      # once, builds the class cache
godot --headless --script tests/acceptance.gd  # section 18 gates, writes reports/acceptance_summary.txt
godot --headless --script tests/scenarios.gd   # every system beyond the slice, writes reports/scenario_summary.txt
godot --headless --script tests/ui_smoke.gd    # plays the real scene, opens every tab and inspector
godot --headless --script tests/stress.gd      # about 1,000 Sims, writes reports/stress_summary.txt
godot --headless --script tests/realism.gd     # every random rate against real US and South Dakota figures
godot --headless --script tests/seed_scan.gd   # one line per seed, for calibration
```

The acceptance run plays 365 days and checks: the ledger balances every day, a Sim started a business with a readable reason, a debt spiral resolved with its paper trail, a petition came from real need data and the mayor's answer changed the outcome (compared against a control run on the same seed), a contract was bid, built in stages and its quality set the next repair date (compared against a run that picked a better contractor), replay from seed plus the action log is exact, a save on day 180 loads and finishes identical, no em dashes in generated text, and forced scenario checks of estate order and bankruptcy rules. The latest results are in `reports/`.

## How it is built

```
sim/            the whole simulation, plain data, no scene nodes
  world.gd        LTWorld: every record, the daily tick, player actions, save and load
  ledger.gd       integer cent ledger, money only moves by transfer, sums to zero
  people.gd       Sims: generation, needs, decisions with reasons, life stages, family, moving
  economy.gd      businesses: market reading, founding, supply chains, customers, hiring, closing
  finance.gd      debts, collections ladder, credit scores, bank, bankruptcy, estates, city debt
  civic.gd        laws and estimates, budget, city services and jobs, petitions, published needs
  projects.gd     public projects, contractor bids, construction stages, quality, private builds
  services.gd     the other 15 business types, the service spend book, supply chains, the local bank
  region.gd       Tier 3: the county economy, outside employers, shortages, storms
  health.gd       pregnancy, work injuries, depression, addiction and treatment
  justice.gd      crime, police detection, courts, fines, jail, records, health inspections
  family.gd       divorce, child support, mentoring, business succession and sale, home buying
  geography.gd    lots, road graph and travel times, weather, road wear
  calendar.gd, money.gd, report.gd
town/           the 3D view, built procedurally from the data (no bought or external assets)
ui/             the mayor's desk, charts, procedural sound
tests/          acceptance, stress and calibration runs
docs/           the design document, decisions, status, and the recovered original prototype
```

Rules kept from the first line of code: Sims and everything else are data records, not nodes. The daily tick is deterministic from a seed plus logged player actions. The road network is a graph. Money is double entry in spirit, imports and outside wages are the town boundary flows. Saves are chunked by system and versioned. No system hard codes the town size: `tests/stress.gd` runs the same code on a 168 lot town.

## About the original build

The zip that started this work contained only a compiled web export. Its scripts were decoded from the export's binary token format and are kept, unchanged apart from lost comments, in `docs/recovered_prototype/` for reference. The new code reuses their names, data and intent, but the systems were rebuilt so they fit together (the old sim engine and economy used different business names and money was only partly tracked).

The working title, town name and art are placeholders. Name, trademark and store checks are required before any public release, as the design document says.
