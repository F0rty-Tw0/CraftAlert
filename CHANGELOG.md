# Changelog

Player-friendly release notes for Craft Alert.

## [Unreleased]

- A toast pops up when someone in Trade asks for something you can craft: left-click to greet them, shift-click to edit the greeting first, ctrl-click for an empty whisper, right-click to dismiss. Drag it anywhere; it remembers the spot.
- A leads window lists every open request, newest first, with the same clicks as the toast. Drag it, resize it, close it with Escape.
- A small bell button opens the leads window and shows how many leads are open. It is lit while Craft Alert is listening and dim while it is paused; hover it to see why.
- Key bindings (under Craft Alert): greet the latest lead, dismiss it, show or hide the leads window.
- A settings window (Esc → Options → AddOns → Craft Alert, then "Open Craft Alert settings"): turn scanning and each channel on or off, pick the alert sound and toast time, set the lead timeout, edit the four greetings with a live preview and a note per profession, edit request words and extra slang, enable, remove or mute your crafters and their recipes, and try a trade line on the Test page.
- Slash commands: `/ca` shows or hides the leads window, `/ca config` opens the settings, `/ca test <a trade line>` shows what Craft Alert would do with that line (what matched, why, who would answer, the greeting), and `/ca perf` times the chat scan and reports every minute until you run it again.
- Craft Alert starts by itself when you log in: one chat line says whether it is listening (and in which channels) or why it is paused, another names the professions you still need to open once, and a first install suggests a `/ca test` line to try.
- On every game version, a request that names an armor slot without an armor type ("LF belt", "LF head crafter") now uses the asker's class (enchant requests excepted): a warrior's request alerts only for plate, a mage's only for cloth. On Forever and Classic the class is read as max level (a level 30 hunter counts as mail).
- `/ca test <a trade line>` sends the line through the real path and makes a real test lead (customer `Test0`, or `Test1` to `Test6` with `x<N>`), so you can try the toast, clicks and keybinds alone. It works only where a real Trade line would (in a city or inn, Trade on). Greetings and whispers are dry runs: they print "Test, would ..." and send nothing. `as <class>` sets the test customer's class (`/ca test as warrior LF belt`), and `/ca test reply` fakes the customer's reply. Test leads are never saved.
- Ignoring someone removes their open leads, and their later requests make none.
