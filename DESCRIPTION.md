# Farsight

**Play WoW Forever across several monitors.** The 3D world stays on one screen, and your map, bags, chat and other windows get the rest.

Farsight lets you divide your extra screens into zones and drop a window into each one. The window is moved there, sized to fill the zone, and can be kept open so Escape and NPC windows no longer close it.

---

## What you need

Farsight has two parts:

1. **This addon**, which arranges everything inside the game.
2. **The Farsight Launcher**, a small Windows program that stretches the WoW window across the monitors you pick and tells the addon where each screen is. Download it here: **[github.com/womcraft/Farsight/releases](https://github.com/womcraft/Farsight/releases/latest)** (the source code is there too)

The launcher is Windows only. If you stretch the WoW window with another tool, the addon also works without the launcher: type `/farsight` and enter your screens by hand.

---

## Features

- 🖥️ **Any monitor setup:** stacked, side by side, three screens or more. Screens with different resolutions work.
- 🎮 **Game screen:** pick which screen shows the 3D world. The world is drawn only there, in the right proportions.
- 🧩 **Zones:** split each screen into zones with ready-made layouts, or draw your own cuts with the mouse.
- 🪟 **Any window in any zone:** world map, bags, chat tabs, character, vendor, mail, bank, auction house and about thirty more. Windows of other addons that are open are listed too (for example the Questie tracker), and "Pick any window with the mouse" catches the rest.
- 📐 **Automatic sizing:** each window is scaled to fit its zone, stretched to fill it, or left at its own size. You choose per zone.
- 📌 **Keep open:** pinned windows are not closed by Escape, NPC windows or the game menu. Your own key and the X button still close them. Closing the bags and the map on Escape is built into WoW, so Farsight runs a small script that hides them just before the game handles the key and opens them again right after. The same script works for WoW's own map and for OpenMap's map.
- 🗺️ **Map always open:** an optional setting keeps the map up even while you talk to an NPC or vendor.
- 🎒 **Bags that fill the zone:** switch between one combined bag and separate bags stacked in the zone. With separate bags, B opens and closes all of them together.
- 💬 **Chat in zones:** put each chat tab (General, Combat Log, your own tabs) in its own zone.
- 📊 **Info panel:** a built-in panel with clock, level and XP, XP per hour, gold, free bag slots, durability, kills and FPS. Its text grows with the zone.
- 📊 **Quest panel:** every quest in your log with its objectives, spread over as many columns as make the text largest in its zone. A quest is never split between columns. Point at a quest to highlight it, click it to open it in the quest log. Its background is transparent by default; both panels can be switched between transparent and solid in the options or the zone menu.
- 🎛️ **Action bars and unit frames in zones:** put action bars, the player, target and party frames, the minimap, the quest tracker and buffs in zones too. A zone can hold several bars: tick more than one in the zone menu and they are stacked edge to edge with no gap. Click a ticked bar again to take it out. Each zone can also set **Bar direction**: horizontal, vertical, or auto (whichever makes the bars biggest in the zone). This changes the bar in your Edit Mode layout; WoW's preset layouts cannot be changed, so Farsight first copies yours to a new layout named "Farsight". A bar that is switched off in WoW is switched on when you put it in a zone, and off again when you take it out.
- 🖐️ **Free windows:** keep a window in a place of its own without a zone. Drag it, resize it with the mouse wheel, and it stays there.
- 👋 **First-start guide:** the first time, Farsight asks what you want on your other screen and sets it up in one click.
- 🔗 **Share layouts:** export a profile as text and import one from a friend.
- 🗂️ **Layout profiles:** save several layouts and switch between them, or let Farsight switch automatically for cities, dungeons and the open world.
- 🔧 **Auto-calibrate:** one click sets the game area and UI scale from your screen resolutions.

---

## Getting started

1. Install the addon and download the launcher.
2. Start the launcher. Click the screens WoW should cover and right-click the one that should show the game.
3. Press **Start**, then start WoW from Battle.net as usual. The launcher stretches the window.
4. In game, Farsight asks what you want on your other screen. Pick one of the ready-made setups and you are done.
5. To change it, type `/farsight layout`. Click a zone's tab to choose its window, and click **Zones** for another split.
6. Drag the yellow lines to resize zones. Click **Draw a cut**, turn the line with the mouse wheel and click in a zone to split it.

Not sure which screen is which? Click **Identify screens** in the launcher and a number appears on each one.

---

## Layout mode

Open it with `/farsight layout` or a left-click on the minimap button.

| Control | What it does |
|---|---|
| **Zone tab** | Choose the window for that zone, set its size mode, turn Keep open on or off, split or remove the zone |
| **Zones** | Start from a ready-made split of the screen |
| **Draw a cut** | Click in a zone to split it where the line is. The mouse wheel turns the line between vertical and horizontal |
| **Yellow lines** | Drag to resize zones |
| **Margins** | Keep space free at the screen edges, for example for action bars |
| **Profile** | Switch, create, delete, export or import layout profiles and set automatic switching |
| **Free window** | Keep a window in a place of its own: drag its handle, mouse wheel to resize, right-click to release |
| **Game screen** | Make that screen the one that shows the 3D world |

---

## Commands

| Command | Description |
|---|---|
| `/farsight` | Open the options window |
| `/farsight layout` | Open layout mode |
| `/farsight auto` | Auto-calibrate: game area, UI scale and UI placement back to automatic |
| `/farsight profile <name>` | Switch layout profile. Without a name it lists them |
| `/farsight next` | Switch to the next layout profile |
| `/farsight info` | Show or hide the info panel |
| `/farsight quests` | Show or hide the quest panel |
| `/farsight welcome` | Show the first-start guide again |
| `/farsight on` / `off` | Enable or disable Farsight |
| `/farsight status` | Show what Farsight knows about your screens |
| `/farsight reset` | Clear the layout |
| `/farsight debug` | Print what the addon does to chat |

---

## Works with other addons

Farsight needs no other addon. The options window shows which of these it found and how it works with them.

- **MoveAny:** windows you put in a Farsight zone follow Farsight. MoveAny's saved position and size for those windows are set aside, and come back if you take the window out of its zone. Everything else stays under MoveAny's control. A window you just put in a zone may need one `/reload` before MoveAny lets go of it.
- **OpenMap:** the map can be stretched to fill its zone. Without OpenMap, WoW's own map keeps its shape and is scaled to fit.
- **Action bars and unit frames with MoveAny:** if MoveAny moves a bar or frame, turn that element off in MoveAny before you put it in a Farsight zone.
- **Without either:** Farsight moves, sizes and keeps open every window you put in a zone by itself.

---

## Good to know

- Made for **WoW Forever**.
- Farsight pauses itself when the WoW window is not stretched, so the game looks normal if you start it without the launcher.
- Windows can only be moved outside combat. Changes made in combat are applied when combat ends.
- WoW closes the map when an NPC or vendor window opens, and Farsight opens it again afterwards. The setting **Keep the map open beside NPC, vendor and other windows too** stops that. It is marked experimental: if the map ever refuses to close in combat, turn it off.
- WoW's combined bag is always 10 slots wide, so it stays small in a tall, narrow zone. Use **Separate bags** for those zones.
- Key bindings for layout mode, next profile, the info panel and the options window are in WoW's key binding settings under Farsight.
- To go back to normal WoW, click **Restore normal WoW** in the launcher with the game closed.

---

## Something looks wrong?

- **Zoomed in, or the world on every screen:** type `/farsight auto`, or click **Auto-calibrate** in the launcher and type `/reload`.
- **A window does not follow its zone:** if you use MoveAny, type `/reload` once.
- **Anything else:** type `/farsight status` and `/farsight debug` and include what they print when you report the problem.
