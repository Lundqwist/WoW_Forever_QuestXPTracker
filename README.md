# Quest XP Tracker (WoW Forever)

A World of Warcraft addon for **WoW Forever** (interface 16001) that keeps track of the experience reward of every quest in your quest log.

## Features

- **XP bar**: your XP this level (purple), with the XP from all active quests layered on top (green).
- **Summary**: XP needed for the next level, XP from active quests, and whether turning them all in levels you up (and how much spills over).
- **Dropdown quest list** (click the +/- header), grouped by zone:
  - **Zone headers** show how many quests are active, the zone's active XP, and fold or unfold on click. Their button makes the whole zone active or inactive.
  - **Quest**: name and level, coloured by difficulty. Hover for the tooltip, shift-click to link it in chat, click to open it in the quest log.
  - **XP**: the reward.
  - **Active / Inactive**: inactive quests are greyed out and don't count towards the total.
- Sort by clicking a column header (zones and the quests inside them); "All active" / "None" toggle every quest at once.
- **Minimap button** with a "Qxp" icon: left-click shows/hides the window, right-click folds the list, drag to move it around the minimap. The tooltip shows the summary.
- **Titan Panel plugin** "Qxp" (through LibDataBroker): shows active quest XP / XP needed, with the same tooltip and clicks. Any other LDB display works too.
- Quest cache, Active/Inactive choices, folded zones and button position are saved per character.

## Install

Copy the folder into `World of Warcraft\_forever_\Interface\AddOns\` and name it `QuestXPTracker` (the folder name must match the `.toc` file).

## Commands

- `/qxp` or `/questxp`: show or hide the window
- `/qxp reset`: move the window back to the centre
- `/qxp scan`: rescan the quest log
- `/qxp minimap`: show or hide the minimap button

## License

[MIT](LICENSE) © 2026 Bjarne Lundqwist
