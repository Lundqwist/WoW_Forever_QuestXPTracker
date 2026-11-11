<p align="center"><img src="https://raw.githubusercontent.com/Lundqwist/WoW_Forever_QuestXPTracker/main/Media/logo.png" alt="Quest XP Tracker" width="180"></p>

# Quest XP Tracker

**Track the XP of every quest in your log, see how close it gets you to your next level, and spot the quest items you no longer need.**

Made for **WoW Forever**. Type `/qxp`, click the **Qxp** minimap button or use the **Qxp** plugin on Titan Panel.

---

## How far do my quests take me?

The XP bar at the top shows the XP you have this level in **purple**. On top of it, in **green**, is where you'll be once you turn in every active quest. Underneath, the addon does the maths for you:

```
Level 23:  12,345 / 40,000 XP  (30%)
XP needed for level 24:  27,655  (level 23 needs 40,000 XP in total)
XP from active quests:  31,200  (78% of this level)
Enough to level up!  3,545 XP over into level 24
```

Not enough yet? It tells you exactly how much is missing:

```
Still short after turning them all in:  8,420 XP
```

![Main window](https://raw.githubusercontent.com/Lundqwist/WoW_Forever_QuestXPTracker/main/Media/screenshots/main-window.png)

## Every quest, grouped by zone

Open the dropdown list to see every quest in your log, grouped under its zone. Each zone shows how many of its quests are active and how much XP they're worth together.

```
[-] Elwynn Forest  (3/4)                     1,240   [ Mixed  ]
       [7] Kobold Candles                       450   [ Active ]
       [8] Gold Dust Exchange                   420   [ Active ]
       [9] Princess Must Die!                   370   [ Active ]
       [10] The Fargodeep Mine                  290   [Inactive]
[+] Westfall  (5/5)                          4,860   [ Active ]
```

- **Quest names** are coloured by difficulty, the same way the game colours them.
- **Hover** a quest for its tooltip. **Click** it to open it in the quest log, **shift-click** to link it in chat.
- **Active / Inactive**: switch off quests you're not going to do (an elite quest, a dungeon you'll skip). They're greyed out and no longer count towards the total.
- The **zone button** switches a whole zone at once. **All active** and **None** switch every quest.
- **Click a zone** to fold it, **click a column header** to sort by name, XP or Active.

The title bar also shows how full your log is, from green to yellow to red:

```
Quests 37/40
```

## Quest items: keep or bin?

The **Items** window docks to the right of the main window and lists the quest items in your bags, plus any other item a quest objective asks for. Each item shows the quest that uses it:

```
[Linen Cloth] x4
  > Bundle of Cloth

[Rolf's Corpse] x1
  > Rolf and Vort  (+1)

[A Mysterious Message]
  Starts: The Missing Diplomat

[Gold Pickup Schedule]          <- big red cross over the icon
  No longer needed
```

Items that **no quest in your log needs any more** get a **big red cross**, a red row and the text "No longer needed". They're listed first, so you can clear some bag space before your next trip to town.

![Quest items window](https://raw.githubusercontent.com/Lundqwist/WoW_Forever_QuestXPTracker/main/Media/screenshots/items-window.png)

## Look it up on Wowhead

**Right-click** any quest or item to get its Wowhead (Forever) link in a small box, already selected:

```
https://www.wowhead.com/forever/quest=783
```

Press **Ctrl+C** to copy it (the box closes by itself), then paste it into your browser. Addons can't open a web browser themselves, so this is the quickest way there.

![Wowhead link box](https://raw.githubusercontent.com/Lundqwist/WoW_Forever_QuestXPTracker/main/Media/screenshots/wowhead-link.png)

## Minimap button and Titan Panel

<img src="https://raw.githubusercontent.com/Lundqwist/WoW_Forever_QuestXPTracker/main/Media/logo.png" alt="Qxp icon" width="48" align="left">

The **Qxp** minimap button and the **Qxp** Titan Panel plugin show the same summary when you hover them:

```
Quest XP Tracker
Quest log                      37/40
Level 23              12,345 / 40,000
Needed to level               27,655
Active quests (11/12)      31,200 XP
Enough to level! 3,545 XP over.
Quest items          6  (2 not needed)
```

On Titan Panel the plugin's text shows the XP from active quests / the XP you need, for example **31,200 / 27,655 XP**. It turns green once your quests are enough to level.

- **Left-click**: show or hide the window
- **Right-click**: fold or unfold the quest list
- **Drag** the minimap button to move it around the minimap

Any other LibDataBroker display shows the plugin too.

![Titan Panel plugin](https://raw.githubusercontent.com/Lundqwist/WoW_Forever_QuestXPTracker/main/Media/screenshots/titan-panel.png)

## Make it your size

Drag the grip in the **bottom-right corner** of either window to resize it. The columns follow the width and the list follows the height. Sizes, position, folded zones and your Active/Inactive choices are saved for each character.

## Commands

| Command | What it does |
|---|---|
| `/qxp` or `/questxp` | Show or hide the window |
| `/qxp items` | Show or hide the quest items window |
| `/qxp minimap` | Show or hide the minimap button |
| `/qxp scan` | Rescan the quest log and your bags |
| `/qxp reset` | Move the window back to the centre and reset both window sizes |

## Good to know

- An item counts as used if a quest objective names it, or if it's the quest's usable item (the one shown next to the quest in the tracker). An item that's only handed in at the end, and isn't named in any objective, can wrongly get a red cross. Check the tooltip before you delete anything.
- XP rewards are the values the game reports for your current level. Quests far below your level give less.
- The quest list pauses while you're in combat and catches up as soon as combat ends.
- At max level the bar shows your level and the total quest XP only.

## Source and bugs

The addon is open source under the MIT license: [github.com/Lundqwist/WoW_Forever_QuestXPTracker](https://github.com/Lundqwist/WoW_Forever_QuestXPTracker). Bug reports and ideas are welcome under Issues. If you get an error, please include the text from BugSack or BugGrabber.
