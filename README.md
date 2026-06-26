# Rainy's IW4x .GSC Trickshot Mod Menu

A private-match IW4x/MW2 .GSC trickshot mod menu built around bot control, trickshot setup, lobby tools, and quality-of-life features.

Rainy's IW4x .GSC Trickshot Mod Menu was created for players who still enjoy private match trickshotting on MW2/IW4x and want a cleaner way to set up shots, control bots, manage lobbies, and experiment with classic mod menu features. The menu is designed primarily around controller use, bot-based practice, and private/offline sessions.

This project includes the main trickshot menu, modified Bot Warfare support files, and waypoint data, to make bot-based private matches easier to get running. The goal of this release is to give the IW4x trickshot/modding community something useful to play with, learn from, and build on.

![Rainy's IW4x .GSC Trickshot Mod Menu - Main Menu](./screenshots/main-menu.png)

## Disclaimer

Use of this mod menu in online/public matches may result in your IW4x account being banned or restricted. This menu was designed for private match trickshotting against bots and may support other players joining your private lobby. It should not be used in public matches or on servers you do not own or administer.

Only use this menu in private matches, offline sessions, or dedicated servers where you have permission and all players understand that mods are being used.

## Included

* Rainy's IW4x Trickshot Mod Menu GSC files
* Bot Warfare support files
* Bot waypoint data
* Modified Bot Warfare script installation mod 'z_svr_bots.iwd'
* Private match trickshot/lobby/bot tools

## Requirements

* A working IW4x installation (see this repo for instructions: https://github.com/iw4x/launcher)
* Call of Duty: Modern Warfare 2 game files properly set up for IW4x
* 7-Zip, WinRAR, or another archive tool
* Basic knowledge of where your IW4x folder is located

## Installation

1. Download the latest release from the Releases section.
2. Extract the downloaded .zip file.
3. Open the extracted folder, then open the mod-files folder.
4. Copy these three items from inside mod-files:
    * scripts
    * scriptdata
    * z_svr_bots.iwd
5. Paste those three items into your MW2/IW4x userraw folder.
    Example location: MW2 Folder/userraw/

[!NOTE]
If you do not see a userraw folder, launch IW4x and start a private match at least once. This should generate the folder.

Do not copy the entire mod-files folder into userraw. Only copy the three items listed above: scripts, scriptdata, and z_svr_bots.iwd.

6. Launch IW4x.
7. Start a private match.
8. If installed correctly, you should see the “Welcome to Rainy’s Mod Menu” text appear on screen.
9. Open the menu with ADS + Melee.

Userraw Folder Note

If you do not see a userraw folder, launch IW4x and start a private match at least once. This should generate the folder.

Do not copy the entire mod-files folder into userraw. Only copy the three items listed above: scripts, scriptdata, and z_svr_bots.iwd.

![Rainy's IW4x .GSC Trickshot Mod Menu - Welcome Screen](./screenshots/welcome-screen.png)

## Menu Navigation

This menu was designed primarily with controller use in mind, but keyboard/mouse players can still use it as long as the required IW4x actions are properly bound.

### Basic Controls

| Action        | Input                        |
| ------------- | ---------------------------- |
| Open Menu     | ADS + Melee                  |
| Close Menu    | ADS + Melee                  |
| Navigate Up   | D-pad Up / `+actionslot 1`   |
| Navigate Down | D-pad Down / `+actionslot 2` |
| Select Option | Use                          |
| Go Back       | Melee                        |

> [!NOTE]
> The full on-screen menu is host-only. Other players can join the private match, but the host controls the main mod menu. The host can give certain quick mods to other players through the Player Options submenu. Other players can use the Can Swap bind, Auto Refill Ammo bind, and Save/Load Position binds by default, but additional features must be enabled or given by the host.

## Quick Binds

Some features can be triggered without having to open the menu (these are called quick binds).

| Action                   | Input                       |
| ------------------------ | --------------------------- |
| Toggle Auto Refill Ammo  | Prone + D-pad Up            |
| Save Position            | Prone + D-pad Down          |
| Load Position            | Crouch + D-pad Down         |
| Can Swap Bind            | Standing + D-pad Up         |
| Toggle UFO Mode          | Standing + ADS + D-pad Down |
| Toggle TS Aimbot         | Crouch + D-pad Up           |
| Spawn Trickshot Platform | Crouch + D-pad Left         |

All quick binds should be enabled for the host by default, however most are toggelable within the menu if you want them turned OFF.


### Controller Notes

Controller is the recommended way to use this menu. The menu was built around controller-style navigation for trickshotting, especially D-pad movement and stance-based quick binds.

### Keyboard/Mouse Notes

Keyboard/mouse users can use the menu, but may need to manually bind the action slot commands used for menu navigation.

Example binds:

```cfg
bind UPARROW "+actionslot 1"
bind DOWNARROW "+actionslot 2"
bind LEFTARROW "+actionslot 3"
```

ADS, Melee, and Use must also be bound normally in your IW4x controls.

Note: The menu itself does not automatically force keyboard binds. You may need to set binds manually through the IW4x console or config.

## Features

* Trickshot-focused menu layout
* Fast Last support
* Save and Load Position
* UFO Mode
* Forge Mode
* Infinite Care Package toggle
* Auto Refill Ammo
* Bot control options
* Passive/Moving bot controls
* Bring Bots to Crosshair
* Bring Bots to Me
* Bot team and difficulty options
* Lobby health options
* Friendly Fire toggle
* Trickshot Only Damage toggle
* Restart Game and End Game options
* Weapon and camo menus
* Wallbang/trickshot aimbot options for private use
* Additional quality-of-life tools, private match utilities, and smaller menu features not listed here

![Rainy's IW4x .GSC Trickshot Mod Menu - Main Menu](./screenshots/trickshot-mods.png)

## Known Notes/Bugs

* Some custom maps may not support bots correctly.
* Some maps may crash with high bot counts.
* If bots do not move, the map may be missing proper bot/waypoint support.
* This menu is intended for private matches, not public cheating.
* Bots climb ladders weirdly. I believe this is from some edits I did for "Bot Combat" in the mod files, but plan to fix this in a future release.

## Credits

* **Rainy City** - IW4x .GSC trickshot menu development, edits, testing, organization, and release.
* **SyndiShanX** - creator of the **Synergy MW2 GSC Menu**. Portions of this project were adapted from or directly based on Synergy MW2 GSC Menu code, including some submenu structure and implementation patterns. Synergy was also a major learning reference for IW4x/GSC menu structure, dvars, functions, and general implementation.
* **ineedbots / Bot Warfare** - creator/community behind Bot Warfare, including the bot system, waypoint/scriptdata foundation, and related bot support used for this setup.
* **IW4x community** - client, documentation, testing knowledge, and modding resources.

## License

This project is released under the **GNU General Public License v3.0**.

This menu is open source for learning, private match use, and community modding. You are free to study, modify, redistribute, and build from this project as long as you follow the GPLv3 license terms and keep derivative work open source under a compatible license.

Some portions of this project were adapted from GPLv3-licensed projects, including Synergy MW2 GSC Menu. Do not sell this menu or claim the work of credited creators as your own.
