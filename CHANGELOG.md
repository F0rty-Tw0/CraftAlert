# Changelog

Player-friendly release notes for Craft Alert.

## [Unreleased]

- On Classic (Era to Mists of Pandaria), Craft Alert now knows your crafting professions and learns your recipes when you open a profession window, Enchanting's craft window on Era and TBC included.
- On Classic, a recipe you learn while playing matches requests by name right away; opening its profession window once stores it for good.
- Your main crafter for a profession now wins ties over the character you're playing.
- Choose the main crafter from a lead card: left-click its Crafters row.
- Settings → Crafters has Mute all and Unmute all for the recipes listed.
- Rebuilding the recipe index after a profession read or a settings change no longer freezes the game for a frame.
- The top of the leads list counts today's requests seen, greeted and replied to (and, on Retail, orders filled); hover it for the last 7 days.
- On Retail, filling a crafting order for someone you greeted in the last day counts as an order filled.
- Back from AFK, one toast says how many requests you could craft came in while you were away and how many of them expired. Left-click it to open the leads, right-click to dismiss it.

- A toast pops up beside the launcher, on the side facing the middle of the screen, when someone in Trade asks for something you can craft. It shows a plain headline ("Wants … — you can craft it"), their whole Trade message with item and recipe links you can hover, and what matched in its tooltip. Left-click to greet them, shift-click to edit the greeting first, ctrl-click for an empty whisper, right-click to dismiss; a click on a link only opens the link. Dragging the toast moves the launcher.
- A leads window lists every open request, newest first, with the same clicks as the toast. Drag it, resize it, close it with Escape.
- Each lead is a card with its details beside it: the customer in their class colour, how long ago they asked, what they want, then their message with hoverable links, what matched, and which of your characters can craft it.
- Your crafters show in their class colour, the one picked for the lead first, with its quality rank.
- Hovering a card shows Greet, Whisper and Dismiss buttons on it.
- Hover a card's name, what it wants, what matched or its crafters for a tooltip with more; hover the rest of the card to see the customer's latest chat line.
- `/ca test` uses your own class when you don't name one.
- The leads window keeps one size for the list and the settings, 600×480 at least; a resize in one view carries over to the other.
- In the settings, the gear on the title bar turns into a back arrow.
- In Settings → Crafters, hovering a recipe shows its name, its profession, which of your characters know it, and whether it is muted.
- The launcher, a ring with your profession's icon (a bell when Craft Alert knows none yet), opens the leads window and shows how many leads are open. It glows when you hover it and pulses when a new lead arrives. It is lit while Craft Alert is listening and dim while it is paused; hover it to see why.
- Key bindings (under Craft Alert): greet the latest lead, dismiss it, show or hide the leads window.
- Settings, opened with the gear on the leads window's title bar or `/ca config`: turn scanning and each channel on or off, pick the alert sound and toast time, set the lead timeout, edit the four greetings with a live preview and a note per profession, edit request words and extra slang, enable, remove or mute your crafters and their recipes, and try a trade line on the Test page.
- Slash commands: `/ca` shows or hides the leads window, `/ca config` opens the settings, `/ca test <a trade line>` tries a trade line (see the `/ca test` note below), and `/ca perf` times the chat scan and reports every minute until you run it again.
- Craft Alert starts by itself when you log in: one chat line says whether it is listening (and in which channels) or why it is paused, another names the professions you still need to open once, and a first install suggests a `/ca test` line to try.
- On every game version, a request that names an armor slot without an armor type ("LF belt", "LF head crafter") now uses the asker's class (enchant requests excepted): a warrior's request alerts only for plate, a mage's only for cloth. On Forever and Classic the class is read as max level (a level 30 hunter counts as mail).
- `/ca test <a trade line>` sends the line through the real path, prints what matched, why, who would answer and the greeting, and makes a real test lead (customer `Test0`, or `Test1` to `Test6` with `x<N>`), so you can try the toast, clicks and keybinds alone. It works only where a real Trade line would (where Trade chat exists, Trade on). Greetings and whispers are dry runs: they print "Test, would ..." and send nothing. `as <class>` sets the test customer's class (`/ca test as warrior LF belt`), and `/ca test reply` fakes the customer's reply. Test leads are dropped at your next login or `/reload`.
- Ignoring someone removes their open leads, also the ones saved from your last session, and their later requests make none.
- Craft Alert turns itself off in any instance (dungeons, raids, battlegrounds, arenas, delves): no scanning, no alerts, the launcher, toast and leads window are hidden, and `/ca` and the key bindings do nothing there. It comes back when you leave.
- The "Only while resting" setting is now "Only where Trade chat exists": Craft Alert listens wherever you have the Trade channel, not just in cities and inns.
- Fixed: Blizzard errors in Mythic+ blamed on Craft Alert ("execution tainted by 'CraftAlert'"). Craft Alert now uses its own tooltip and stays out of Blizzard's.
- Fixed: a linked recipe ("LF [Tailoring: Martyr's Gloves] crafter") did not alert on Retail or Forever. Recipe links now match the recipe they point to.
- "WTC" and "LFRC" are now request words by default, next to "LF", "LFC" and "WTB". Saved word lists are kept as they are; add them in Settings → Keywords if yours lacks them.
- More requests alert: "recraft", "recrafter" and "recrafting" work like "crafter" ("LF recraft ring"), "leg" works like "legs", and "enchs" names Enchanting.
- "/w me" no longer hides a request that says LF, LFC, LFRC, WTB or WTC ("LFC [Spellbreaker's Bracers] /w me"). Lines without one of those still count as ads, and so does "LF work" (but not "LF work order").
- "Trinket" no longer picks a profession on its own: it chose whoever knew the most trinkets, often old alchemist stones over PvP trinkets. Name the trinket instead.
