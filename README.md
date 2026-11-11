# Quest XP Tracker (WoW Forever)

A World of Warcraft addon for **WoW Forever** (interface 16001) that keeps track of the experience reward of every quest in your quest log.

## Features

- **XP bar**: your XP this level (purple), with the XP from all active quests layered on top (green).
- **Summary**: XP needed for the next level, XP from active quests, and whether turning them all in levels you up (and how much spills over).
- **Dropdown quest list** (click the +/- header) with:
  - **Quest**: name and level, coloured by difficulty. Hover for the tooltip, shift-click to link it in chat, click to open it in the quest log.
  - **Zone**: the quest log header the quest is under.
  - **XP**: the reward.
  - **Active / Inactive**: inactive quests are greyed out and don't count towards the total.
- Sort by clicking a column header; "All active" / "None" toggle every quest at once.
- Quest cache and Active/Inactive choices are saved per character.

## Install

Copy the folder into `World of Warcraft\_forever_\Interface\AddOns\` and name it `QuestXPTracker` (the folder name must match the `.toc` file).

## Commands

- `/qxp` or `/questxp`: show or hide the window
- `/qxp reset`: move the window back to the centre
- `/qxp scan`: rescan the quest log
