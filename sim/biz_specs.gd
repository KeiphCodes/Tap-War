class_name LTBizSpecs
extends RefCounted
## What each kind of business needs in its building to run, the way the trade
## really builds them.
##
## rooms:  [key, label, share of the floor, "f" customer side or "b" back of house]
## unit/per/serve: the room that sets how many customers a day (per = sq ft for
##         one seat, bay, exam room, child; serve = customers per unit a day)
## limits: other rooms that can be the bottleneck: [room, sq ft per customer a day, what it is]
## flex:   [customer room, work room] an owner can trade floor between
## equip:  what goes in, at installed prices: [label, dollars, room]
## code:   what the codes require before the doors open:
##         [requirement, authority, law that enforces it, from what level]
##         law "" means always (state and federal rules the city cannot waive)
## make:   for producers, what the place turns out

const ADA: Array = ["Accessible entrance and an accessible restroom", "ADA", "", 0]
const EXITS: Array = ["Two exits, lighted exit signs, emergency lights, fire extinguishers", "Fire code", "building_code", 0]
const ALARM: Array = ["Fire alarm system", "Fire code", "building_code", 1]
const SPRINK: Array = ["Automatic fire sprinklers", "Fire code", "building_code", 2]

const SPECS: Dictionary = {
	"grocery": {
		"rooms": [["sales", "Sales floor", 0.6, "f"], ["checkout", "Checkout lanes", 0.06, "f"], ["deli", "Deli and meat counter", 0.06, "f"], ["stock", "Stockroom and receiving", 0.13, "b"], ["cooler", "Walk in cooler and freezer", 0.07, "b"], ["office", "Office and cash room", 0.03, "b"], ["rest", "Restrooms", 0.03, "b"], ["break", "Break room", 0.02, "b"]],
		"unit": "sales", "per": 22.0, "serve": 1.0, "limits": [["checkout", 2.0, "checkout lanes"], ["stock", 4.5, "stockroom"]], "flex": ["sales", "stock"],
		"equip": [["Refrigerated cases and freezer cases", 42000, "sales"], ["Walk in cooler and freezer boxes with compressors", 28000, "cooler"], ["Gondola shelving", 18000, "sales"], ["Three checkout counters with registers and scales", 15000, "checkout"], ["Deli slicer, meat saw and display case", 9000, "deli"], ["Pallet jack and stockroom racks", 5000, "stock"], ["Safe", 3000, "office"]],
		"code": [["Food establishment permit and inspection", "Health code", "health_code", 0], ["Hand sinks and a three compartment sink at the deli", "Health code", "health_code", 0], ["Cold holding at 41 degrees with thermometers in every case", "Health code", "health_code", 1], ["Certified food protection manager on staff", "Health code", "health_code", 2], ADA, EXITS, ALARM, SPRINK],
	},
	"general_store": {
		"rooms": [["sales", "Sales floor", 0.66, "f"], ["checkout", "Counter", 0.05, "f"], ["stock", "Stockroom", 0.19, "b"], ["office", "Office", 0.05, "b"], ["rest", "Restroom", 0.05, "b"]],
		"unit": "sales", "per": 22.0, "serve": 1.0, "limits": [["stock", 6.0, "stockroom"]], "flex": ["sales", "stock"],
		"equip": [["Shelving and display racks", 11000, "sales"], ["Glass front cooler", 6000, "sales"], ["Counter, register and card reader", 5000, "checkout"], ["Stockroom racks and hand truck", 3000, "stock"], ["Security cameras", 3000, "office"], ["Safe", 2000, "office"]],
		"code": [["Retail food permit for packaged food", "Health code", "health_code", 1], ADA, EXITS, ALARM, SPRINK],
	},
	"pharmacy": {
		"rooms": [["sales", "Front store", 0.5, "f"], ["consult", "Patient consultation room", 0.05, "f"], ["rx", "Prescription department", 0.2, "b"], ["stock", "Stockroom", 0.13, "b"], ["office", "Office", 0.06, "b"], ["rest", "Restroom", 0.06, "b"]],
		"unit": "sales", "per": 18.0, "serve": 1.0, "limits": [["rx", 5.0, "prescription department"]], "flex": ["sales", "rx"],
		"equip": [["Prescription counter, fill stations and shelving", 12000, "rx"], ["Locked narcotics safe (Schedule II)", 4000, "rx"], ["Medication refrigerator with temperature log", 3000, "rx"], ["Pharmacy software and label printers", 9000, "rx"], ["Front store shelving", 7000, "sales"], ["Registers", 3000, "sales"], ["Security system", 2000, "office"]],
		"code": [["State board of pharmacy license and a licensed pharmacist on duty", "State license", "", 0], ["DEA registration and a locked safe for controlled drugs", "DEA", "", 0], ["Private counseling area", "State license", "", 0], ["Pharmacy refrigerator kept 36 to 46 degrees", "Health code", "health_code", 1], ADA, EXITS, ALARM, SPRINK],
	},
	"outfitter": {
		"rooms": [["sales", "Sales floor", 0.58, "f"], ["fitting", "Fitting room", 0.04, "f"], ["rental", "Rental and repair shop", 0.2, "b"], ["stock", "Stockroom", 0.14, "b"], ["rest", "Restroom", 0.04, "b"]],
		"unit": "sales", "per": 25.0, "serve": 1.0, "limits": [["rental", 8.0, "rental shop"]], "flex": ["sales", "rental"],
		"equip": [["Display racks and wall slat", 8000, "sales"], ["Rental canoes, kayaks and life jackets", 9000, "rental"], ["Repair bench and tools", 3000, "rental"], ["Gun and ammunition cases (locked)", 3000, "sales"], ["Register", 2000, "sales"]],
		"code": [["Federal firearms license if it sells guns", "ATF", "", 0], ADA, EXITS, ALARM],
	},
	"cafe": {
		"rooms": [["dining", "Dining room", 0.55, "f"], ["counter", "Counter and host stand", 0.04, "f"], ["kitchen", "Kitchen cook line and prep", 0.2, "b"], ["dish", "Dish room", 0.05, "b"], ["cooler", "Walk in cooler", 0.04, "b"], ["dry", "Dry storage", 0.04, "b"], ["rest", "Restrooms", 0.06, "f"], ["office", "Office", 0.02, "b"]],
		"unit": "dining", "per": 15.0, "serve": 3.0, "seat": true, "limits": [["kitchen", 1.8, "kitchen"]], "flex": ["dining", "kitchen"],
		"equip": [["Range, griddle and fryers on the cook line", 16000, "kitchen"], ["Type I hood with fire suppression", 0, "kitchen"], ["Walk in cooler", 12000, "cooler"], ["Commercial dishwasher", 7000, "dish"], ["Three compartment sink and hand sinks", 4000, "dish"], ["Grease trap", 5000, "kitchen"], ["Espresso machine and coffee brewers", 9000, "counter"], ["Reach in coolers and prep tables", 8000, "kitchen"], ["Tables, chairs and booths", 9000, "dining"]],
		"code": [["Food service permit and opening inspection", "Health code", "health_code", 0], ["Type I hood and automatic fire suppression over the fryers", "Fire code", "", 0], ["Grease trap on the kitchen drain", "Sewer rules", "", 0], ["Hand sinks at every station and a three compartment sink", "Health code", "health_code", 0], ["Restrooms for customers sized to the seats", "Plumbing code", "building_code", 0], ["Certified food protection manager", "Health code", "health_code", 1], ["Allergen notice on the menu", "Health code", "health_code", 2], ADA, EXITS, SPRINK],
	},
	"bar": {
		"rooms": [["dining", "Barroom and tables", 0.6, "f"], ["bar", "Bar and back bar", 0.08, "f"], ["kitchen", "Kitchen", 0.12, "b"], ["cooler", "Keg cooler", 0.06, "b"], ["rest", "Restrooms", 0.1, "f"], ["office", "Office", 0.04, "b"]],
		"unit": "dining", "per": 15.0, "serve": 3.0, "seat": true, "limits": [["bar", 0.6, "bar"]], "flex": ["dining", "bar"],
		"equip": [["Bar, back bar and underbar sinks", 12000, "bar"], ["Draft system and keg cooler", 10000, "cooler"], ["Ice machine", 4000, "bar"], ["Glass washer", 3000, "bar"], ["Fryer and flat top for bar food", 6000, "kitchen"], ["Type I hood with fire suppression", 0, "kitchen"], ["Tables, stools and booths", 8000, "dining"], ["Point of sale and cameras", 4000, "office"]],
		"code": [["State liquor license", "State license", "", 0], ["Food service permit for the kitchen", "Health code", "health_code", 0], ["Type I hood and fire suppression", "Fire code", "", 0], ["Posted occupant load and a door that opens outward", "Fire code", "building_code", 0], ["Restrooms sized to the occupant load", "Plumbing code", "building_code", 0], ADA, EXITS, SPRINK],
	},
	"bakery": {
		"rooms": [["counter", "Retail counter and cases", 0.28, "f"], ["bake", "Bake room with ovens", 0.42, "b"], ["proof", "Mixing and proofing", 0.1, "b"], ["stock", "Flour and dry storage", 0.1, "b"], ["dish", "Dish and pot sink", 0.05, "b"], ["rest", "Restroom", 0.05, "f"]],
		"unit": "counter", "per": 10.0, "serve": 1.0, "limits": [["bake", 13.0, "bake room"]], "flex": ["counter", "bake"],
		"equip": [["Deck oven and convection oven", 22000, "bake"], ["Spiral mixer and 60 quart mixer", 12000, "proof"], ["Proofing cabinet", 5000, "proof"], ["Sheeter and bench tables", 6000, "bake"], ["Display cases", 7000, "counter"], ["Walk in cooler", 6000, "stock"], ["Three compartment sink", 2000, "dish"]],
		"code": [["Food establishment permit", "Health code", "health_code", 0], ["Hand sinks and a three compartment sink", "Health code", "health_code", 0], ["Ventilation over the ovens", "Mechanical code", "building_code", 0], ["Labels with ingredients and allergens", "Health code", "health_code", 1], ADA, EXITS, ALARM],
	},
	"clinic": {
		"rooms": [["wait", "Waiting room", 0.16, "f"], ["reception", "Reception and records", 0.06, "f"], ["exam", "Exam rooms", 0.38, "b"], ["proc", "Procedure room", 0.07, "b"], ["lab", "Lab and X ray", 0.09, "b"], ["nurse", "Nurse station", 0.07, "b"], ["steril", "Sterilization and soiled utility", 0.04, "b"], ["office", "Doctor offices", 0.07, "b"], ["rest", "Restrooms", 0.06, "f"]],
		"unit": "exam", "per": 110.0, "serve": 16.0, "count": true, "limits": [["wait", 2.8, "waiting room"]], "flex": ["exam", "wait"],
		"equip": [["Exam tables, lights and wall diagnostics in every room", 32000, "exam"], ["Digital X ray", 55000, "lab"], ["Lab analyzers and centrifuge", 20000, "lab"], ["Autoclave sterilizer", 6000, "steril"], ["Crash cart and defibrillator", 6000, "nurse"], ["Vaccine refrigerator with alarm", 4000, "nurse"], ["Records software", 15000, "reception"], ["Waiting room seating", 4000, "wait"]],
		"code": [["Medical licenses for the doctors and nurses", "State license", "", 0], ["Lead lined X ray room and a state radiation permit", "State license", "", 0], ["CLIA certificate for the lab", "Federal", "", 0], ["Sharps and medical waste contract", "Health code", "health_code", 0], ["Hand sink in every exam room", "Health code", "health_code", 0], ["Patient privacy (HIPAA) for records", "Federal", "", 0], ADA, EXITS, ALARM, SPRINK],
	},
	"repair_shop": {
		"rooms": [["bays", "Service bays", 0.68, "f"], ["wait", "Customer waiting and counter", 0.08, "f"], ["parts", "Parts room", 0.1, "b"], ["tools", "Tool and tire storage", 0.06, "b"], ["office", "Office", 0.04, "b"], ["rest", "Restroom", 0.04, "f"]],
		"unit": "bays", "per": 450.0, "serve": 5.0, "count": true, "limits": [["parts", 12.0, "parts room"]], "flex": ["bays", "parts"],
		"equip": [["Two post lifts, one for each bay", 15000, "bays"], ["Air compressor and air lines", 5000, "bays"], ["Tire changer and wheel balancer", 9000, "bays"], ["Alignment rack", 9000, "bays"], ["Scan tools and diagnostics", 6000, "bays"], ["Used oil tank and parts washer", 3000, "bays"], ["Exhaust hose system", 3000, "bays"]],
		"code": [["Oil water separator on the floor drains", "EPA", "pollution_rule", 0], ["Used oil and coolant recycling", "EPA", "pollution_rule", 0], ["Vehicle exhaust ventilation in the bays", "Mechanical code", "building_code", 0], ["Lifts inspected every year (ANSI)", "OSHA", "", 0], ["Eyewash station", "OSHA", "", 0], ADA, EXITS, ALARM],
	},
	"construction": {
		"rooms": [["shop", "Shop", 0.55, "b"], ["yard", "Covered material storage", 0.15, "b"], ["tools", "Tool crib", 0.12, "b"], ["office", "Office and plan room", 0.12, "f"], ["rest", "Restroom", 0.06, "b"]],
		"unit": "", "per": 0.0,
		"equip": [["Work truck and trailer", 25000, "yard"], ["Table saw, chop saw and compressor", 6000, "shop"], ["Nail guns and hand tools", 5000, "tools"], ["Scaffolding and ladders", 5000, "yard"], ["Estimating software", 4000, "office"]],
		"code": [["State contractor license and bond", "State license", "", 0], ["General liability and workers comp insurance", "State license", "", 0], ["Fall protection and safety training", "OSHA", "", 0], ["Dust collection at the saws", "OSHA", "", 1], EXITS],
	},
	"childcare": {
		"rooms": [["class", "Classrooms", 0.5, "f"], ["infant", "Infant room with cribs", 0.12, "f"], ["kitchen", "Kitchen", 0.08, "b"], ["diaper", "Diaper changing and child restrooms", 0.1, "b"], ["office", "Office and sick room", 0.11, "f"], ["stor", "Storage", 0.05, "b"], ["rest", "Staff restroom", 0.04, "b"]],
		"unit": "class", "per": 35.0, "serve": 1.0,
		"equip": [["Cribs, cots and mats", 5000, "infant"], ["Child sized tables, chairs and cubbies", 6000, "class"], ["Toys, books and learning materials", 5000, "class"], ["Commercial dishwasher and refrigerator", 4000, "kitchen"], ["Diaper changing stations with sinks", 3000, "diaper"], ["Door security and cameras", 2000, "office"]],
		"code": [["State child care license", "State license", "", 0], ["35 square feet of floor per child and staff ratios (1 to 4 infants)", "State license", "", 0], ["Background checks on every worker", "State license", "", 0], ["Fenced outdoor play area, 75 square feet per child", "State license", "", 0], ["Child sized toilets and hand sinks", "Health code", "health_code", 0], ["Fire drills every month and a fire alarm", "Fire code", "", 0], ADA, EXITS, SPRINK],
	},
	"private_school": {
		"rooms": [["class", "Classrooms", 0.55, "f"], ["gym", "Gym and lunchroom", 0.18, "f"], ["library", "Library", 0.06, "f"], ["kitchen", "Warming kitchen", 0.04, "b"], ["office", "Office and nurse", 0.07, "f"], ["rest", "Restrooms", 0.07, "b"], ["stor", "Storage and custodian", 0.03, "b"]],
		"unit": "class", "per": 30.0, "serve": 1.0,
		"equip": [["Desks, chairs and whiteboards", 14000, "class"], ["Computers and projectors", 12000, "class"], ["Library books and shelves", 5000, "library"], ["Gym equipment and lunch tables", 6000, "gym"], ["Warming kitchen and refrigerator", 3000, "kitchen"]],
		"code": [["State registration as a nonpublic school", "State license", "", 0], ["Fire alarm, drills and a posted evacuation plan", "Fire code", "", 0], ["Lunch program food permit", "Health code", "health_code", 1], ADA, EXITS, SPRINK],
	},
	"law_office": {
		"rooms": [["offices", "Attorney offices", 0.5, "b"], ["reception", "Reception", 0.17, "f"], ["conf", "Conference room", 0.18, "f"], ["files", "File room", 0.08, "b"], ["rest", "Restroom", 0.07, "b"]],
		"unit": "", "per": 0.0,
		"equip": [["Desks and conference table", 6000, "offices"], ["Computers and case software", 5000, "offices"], ["Fireproof locked file cabinets", 2000, "files"], ["Copier and scanner", 2000, "files"]],
		"code": [["State bar license", "State license", "", 0], ["Client trust (IOLTA) account at a bank", "State license", "", 0], ["Locked files for client privacy", "State license", "", 0], ADA, EXITS],
	},
	"real_estate": {
		"rooms": [["offices", "Agent desks", 0.5, "b"], ["reception", "Reception", 0.25, "f"], ["conf", "Closing room", 0.15, "f"], ["rest", "Restroom", 0.1, "b"]],
		"unit": "", "per": 0.0,
		"equip": [["Desks and closing table", 4000, "offices"], ["Computers and listing service", 3000, "offices"], ["Window listing displays", 1000, "reception"]],
		"code": [["State real estate broker license", "State license", "", 0], ["Escrow trust account for deposits", "State license", "", 0], ADA, EXITS],
	},
	"bank": {
		"rooms": [["lobby", "Lobby", 0.3, "f"], ["teller", "Teller line", 0.14, "f"], ["vault", "Vault and safe deposit", 0.1, "b"], ["offices", "Loan offices", 0.26, "f"], ["ops", "Operations and count room", 0.1, "b"], ["rest", "Restrooms", 0.06, "b"], ["break", "Break room", 0.04, "b"]],
		"unit": "", "per": 0.0,
		"equip": [["Vault door and vault (UL rated)", 80000, "vault"], ["Safe deposit boxes", 20000, "vault"], ["Teller line with cash recyclers", 30000, "teller"], ["ATM", 40000, "lobby"], ["Alarm, cameras and holdup buttons", 15000, "ops"], ["Core banking system", 15000, "ops"]],
		"code": [["State or federal bank charter", "Bank regulators", "", 0], ["FDIC deposit insurance", "FDIC", "", 0], ["Security officer, alarms and cameras (Bank Protection Act)", "Federal", "", 0], ADA, EXITS, ALARM, SPRINK],
	},
	"hotel": {
		"rooms": [["rooms", "Guest rooms", 0.7, "b"], ["lobby", "Lobby and front desk", 0.1, "f"], ["breakfast", "Breakfast room", 0.06, "f"], ["laundry", "Laundry", 0.06, "b"], ["house", "Housekeeping and linen", 0.04, "b"], ["office", "Office", 0.02, "b"], ["mech", "Mechanical room", 0.02, "b"]],
		"unit": "rooms", "per": 330.0, "serve": 1.0, "count": true, "limits": [["laundry", 25.0, "laundry"]],
		"equip": [["Beds, furniture and TVs for every room", 60000, "rooms"], ["Commercial washers and dryers", 18000, "laundry"], ["Housekeeping carts and linen", 8000, "house"], ["Key card locks", 12000, "rooms"], ["Breakfast bar equipment", 8000, "breakfast"], ["Property management system", 6000, "lobby"]],
		"code": [["Lodging license and inspection", "Health code", "health_code", 0], ["Smoke alarm in every guest room", "Fire code", "", 0], ["Accessible guest rooms with roll in shower", "ADA", "", 0], ["Breakfast food permit", "Health code", "health_code", 1], ADA, EXITS, ALARM, SPRINK],
	},
	"funeral_home": {
		"rooms": [["chapel", "Chapel", 0.36, "f"], ["view", "Visitation rooms", 0.2, "f"], ["arrange", "Arrangement room", 0.07, "f"], ["prep", "Preparation room", 0.12, "b"], ["garage", "Hearse garage", 0.12, "b"], ["office", "Office", 0.06, "b"], ["rest", "Restrooms", 0.07, "f"]],
		"unit": "", "per": 0.0,
		"equip": [["Embalming table and equipment", 9000, "prep"], ["Ventilation for the preparation room", 7000, "prep"], ["Hearse", 30000, "garage"], ["Chapel seating and sound", 8000, "chapel"], ["Casket display", 6000, "arrange"]],
		"code": [["State funeral director and embalmer licenses", "State license", "", 0], ["Preparation room with its own ventilation and eyewash", "OSHA", "", 0], ["FTC price list for families", "Federal", "", 0], ADA, EXITS, ALARM],
	},
	"farm": {
		"rooms": [["machine", "Machine shed", 0.46, "b"], ["grain", "Grain bins and feed storage", 0.24, "b"], ["shop", "Farm shop", 0.15, "b"], ["chem", "Locked chemical and fertilizer room", 0.05, "b"], ["office", "Farm office", 0.06, "f"], ["rest", "Washroom", 0.04, "b"]],
		"unit": "", "per": 0.0, "make": "crops and livestock",
		"equip": [["Tractor", 65000, "machine"], ["Planter and tillage tools", 25000, "machine"], ["Grain bin with dryer and auger", 30000, "grain"], ["Hay equipment", 15000, "machine"], ["Livestock fencing and waterers", 10000, "machine"], ["Shop welder and tools", 5000, "shop"]],
		"code": [["Pesticide applicator certification", "State license", "", 0], ["Manure management plan", "EPA", "pollution_rule", 1], ["Grain bin safety (lockout and lifelines)", "OSHA", "", 0]],
	},
	"factory": {
		"rooms": [["floor", "Production floor", 0.58, "b"], ["raw", "Raw materials", 0.12, "b"], ["finished", "Finished goods and shipping", 0.12, "b"], ["qc", "Quality control lab", 0.04, "b"], ["maint", "Maintenance shop", 0.05, "b"], ["office", "Offices", 0.05, "f"], ["locker", "Break room, lockers and restrooms", 0.04, "b"]],
		"unit": "", "per": 0.0, "make": "manufactured goods",
		"equip": [["Production line machines", 260000, "floor"], ["Overhead crane", 40000, "floor"], ["Forklifts", 35000, "finished"], ["Dust and fume collection", 30000, "floor"], ["Compressed air system", 15000, "maint"], ["Quality control instruments", 12000, "qc"], ["Pallet racking", 8000, "raw"]],
		"code": [["Air permit for emissions", "EPA", "pollution_rule", 0], ["Machine guarding and lockout tagout", "OSHA", "", 0], ["Hazard communication and eyewash", "OSHA", "", 0], ["Stormwater permit", "EPA", "pollution_rule", 1], EXITS, ALARM, ["Automatic fire sprinklers", "Fire code", "", 0]],
	},
	"warehouse": {
		"rooms": [["racks", "Racked storage", 0.76, "b"], ["dock", "Shipping and receiving", 0.14, "b"], ["charge", "Forklift charging", 0.03, "b"], ["office", "Office", 0.04, "f"], ["rest", "Break room and restrooms", 0.03, "b"]],
		"unit": "", "per": 0.0, "make": "storage and shipping",
		"equip": [["Pallet racking", 25000, "racks"], ["Electric forklifts and chargers", 26000, "charge"], ["Dock levelers", 6000, "dock"], ["Inventory scanners and software", 3000, "office"]],
		"code": [["High piled storage permit", "Fire code", "building_code", 1], ["Rack anchoring and load signs", "OSHA", "", 0], ["Forklift operator training", "OSHA", "", 0], EXITS, ["Automatic fire sprinklers", "Fire code", "", 0]],
	},
	"trucking": {
		"rooms": [["shop", "Truck service bay", 0.55, "b"], ["dispatch", "Dispatch office", 0.18, "f"], ["lounge", "Driver lounge and showers", 0.13, "b"], ["parts", "Parts room", 0.09, "b"], ["rest", "Restroom", 0.05, "b"]],
		"unit": "", "per": 0.0, "make": "freight hauled",
		"equip": [["Tractor trailer rig", 160000, "shop"], ["Second trailer", 40000, "shop"], ["Heavy truck lift and tools", 25000, "shop"], ["Electronic logging devices", 5000, "dispatch"], ["Fuel tank with containment", 20000, "shop"]],
		"code": [["USDOT number and operating authority", "FMCSA", "", 0], ["Commercial driver licenses and drug testing", "FMCSA", "", 0], ["Electronic logs for driver hours", "FMCSA", "", 0], ["Spill containment around the fuel tank", "EPA", "pollution_rule", 0], ["Oil water separator in the bay", "EPA", "pollution_rule", 1], EXITS],
	},
	"mill": {
		"rooms": [["mill", "Milling floor", 0.42, "b"], ["receive", "Grain receiving pit and bins", 0.24, "b"], ["bag", "Bagging and warehouse", 0.16, "b"], ["dust", "Dust collection room", 0.05, "b"], ["office", "Office and scale", 0.09, "f"], ["rest", "Restroom", 0.04, "b"]],
		"unit": "", "per": 0.0, "make": "flour and feed",
		"equip": [["Roller mill and hammer mill", 90000, "mill"], ["Grain bins and bucket elevator", 50000, "receive"], ["Truck scale", 25000, "office"], ["Bagging line", 20000, "bag"], ["Dust collector with explosion vents", 15000, "dust"]],
		"code": [["Combustible dust plan and explosion venting", "OSHA", "", 0], ["Grain handling safety (lockout, permits for bin entry)", "OSHA", "", 0], ["Food facility registration for flour", "FDA", "health_code", 0], ["Air permit for dust", "EPA", "pollution_rule", 1], EXITS, ALARM],
	},
	"marina": {
		"rooms": [["store", "Ship store and bait", 0.38, "f"], ["service", "Boat service shop", 0.32, "b"], ["office", "Harbor office", 0.1, "f"], ["shower", "Restrooms and showers", 0.2, "f"]],
		"unit": "", "per": 0.0, "make": "slip rentals, fuel and service",
		"equip": [["Floating docks and boat slips", 45000, "service"], ["Fuel dock with pumps", 25000, "service"], ["Boat lift or travel hoist", 12000, "service"], ["Pump out station", 5000, "service"], ["Store shelving and bait tanks", 3000, "store"]],
		"code": [["Fuel dock spill plan and containment", "EPA", "pollution_rule", 0], ["Sewage pump out for boats", "Clean Water Act", "", 0], ["State permit for docks in the water", "State license", "", 0], ["Life rings and ladders on the docks", "Coast Guard", "", 0], ADA, EXITS],
	},
	"campground": {
		"rooms": [["office", "Office and camp store", 0.4, "f"], ["bath", "Bathhouse with showers", 0.45, "f"], ["laundry", "Laundry", 0.15, "f"]],
		"unit": "", "per": 0.0, "make": "campsite nights",
		"equip": [["Campsites with fire rings and tables", 20000, "office"], ["RV hookups: water, power and sewer", 25000, "office"], ["Dump station", 6000, "office"], ["Washers and dryers", 4000, "laundry"], ["Showers and water heaters", 5000, "bath"]],
		"code": [["State campground license", "Health code", "health_code", 0], ["Tested drinking water", "Health code", "", 0], ["Septic system sized for the sites", "Health code", "", 0], ["Toilets and showers for every so many sites", "Health code", "health_code", 1], ADA],
	},
	"guide_service": {
		"rooms": [["gear", "Gear room", 0.5, "b"], ["office", "Booking office", 0.3, "f"], ["rest", "Restroom", 0.2, "b"]],
		"unit": "", "per": 0.0, "make": "guided trips",
		"equip": [["Boat with motor and trailer", 18000, "gear"], ["Canoes, paddles and life jackets", 6000, "gear"], ["First aid kits and satellite messengers", 2000, "gear"], ["Booking computer", 1000, "office"]],
		"code": [["State outfitter and guide license", "State license", "", 0], ["Wilderness first aid and CPR for guides", "State license", "", 0], ["Permit to guide on public land", "Forest Service", "", 0], ["Liability insurance", "State license", "", 0]],
	},
	"sawmill": {
		"rooms": [["saw", "Saw line", 0.42, "b"], ["logs", "Covered log deck", 0.2, "b"], ["planer", "Planer and grading", 0.15, "b"], ["kiln", "Dry kiln", 0.12, "b"], ["shop", "Saw filing shop", 0.05, "b"], ["office", "Office and scale", 0.06, "f"]],
		"unit": "", "per": 0.0, "make": "lumber",
		"equip": [["Headrig saw and carriage", 120000, "saw"], ["Edger and trimmer", 60000, "saw"], ["Planer", 50000, "planer"], ["Dry kiln", 60000, "kiln"], ["Log loader", 45000, "logs"], ["Sawdust collection and burner", 15000, "saw"]],
		"code": [["Machine guarding and lockout tagout", "OSHA", "", 0], ["Hearing protection program", "OSHA", "", 0], ["Dust control and fire watch for sawdust", "Fire code", "building_code", 0], ["Air permit for the burner", "EPA", "pollution_rule", 0], EXITS],
	},
	"quarry": {
		"rooms": [["shop", "Crusher maintenance shop", 0.5, "b"], ["scale", "Scale house", 0.15, "f"], ["lab", "Aggregate testing lab", 0.1, "b"], ["office", "Office", 0.15, "f"], ["change", "Change house", 0.1, "b"]],
		"unit": "", "per": 0.0, "make": "gravel and crushed stone",
		"equip": [["Crusher and screens", 250000, "shop"], ["Wheel loader", 150000, "shop"], ["Haul truck", 120000, "shop"], ["Truck scale", 30000, "scale"], ["Water spray for dust", 15000, "shop"], ["Testing sieves and lab", 10000, "lab"]],
		"code": [["Mine safety registration and inspections", "MSHA", "", 0], ["State mining permit and reclamation bond", "State license", "mining", 0], ["Blasting license", "ATF", "", 0], ["Dust control", "EPA", "pollution_rule", 0], ["Stormwater permit", "EPA", "pollution_rule", 1]],
	},
	"gold_mine": {
		"rooms": [["mill", "Mill and processing", 0.45, "b"], ["assay", "Assay lab", 0.1, "b"], ["shop", "Maintenance shop", 0.25, "b"], ["dry", "Change house and showers", 0.1, "b"], ["office", "Mine office", 0.1, "f"]],
		"unit": "", "per": 0.0, "make": "gold",
		"equip": [["Headframe, hoist and shaft", 1500000, "mill"], ["Crushing and grinding mill", 900000, "mill"], ["Gravity and flotation circuit", 500000, "mill"], ["Underground loaders and drills", 450000, "shop"], ["Assay furnace and lab", 80000, "assay"], ["Ventilation fans", 70000, "shop"]],
		"code": [["Mine safety registration, inspections four times a year", "MSHA", "", 0], ["State mining permit and reclamation bond", "State license", "mining", 0], ["Tailings dam permit", "State license", "", 0], ["Water discharge permit", "EPA", "pollution_rule", 0], ["Mine rescue team and refuge chambers", "MSHA", "", 0], ["Explosives license", "ATF", "", 0]],
	},
}


static func of(btype: String) -> Dictionary:
	return SPECS.get(btype, {})


## The code rules that apply to this business under the town's laws today.
static func code_for(w: LTWorld, btype: String) -> Array:
	var out: Array = []
	for c in of(btype).get("code", []):
		var law: String = str(c[2])
		if law == "" or w == null or float(w.city["laws"].get(law, 1.0)) >= float(c[3]):
			out.append([str(c[0]), str(c[1])])
	return out


## The equipment, priced so it adds up to what the owner budgeted for it.
static func equipment(btype: String, budget_dollars: float) -> Array:
	var items: Array = of(btype).get("equip", [])
	var t: float = 0.0
	for it in items:
		t += float(it[1])
	var out: Array = []
	for it in items:
		var price: int = 0 if float(it[1]) == 0.0 else int(roundf(budget_dollars * float(it[1]) / maxf(1.0, t) / 100.0) * 100.0)
		out.append([str(it[0]), price, str(it[2])])
	return out
