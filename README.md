# Rainy's IW4x Trickshot Mod Menu

A private-match IW4x/MW2 trickshot mod menu built around bot control, trickshot setup, lobby tools, and quality-of-life features.

This menu was made for private match trickshotting, bot-based practice, and offline/IW4x modding fun.

## Disclaimer

Use of this mod menu in online/public matches may result in your IW4x account being banned or restricted. This menu was designed for private match trickshotting against bots and may support other players joining your private lobby. It should not be used in public matches or on servers you do not own or administer.

Only use this menu in private matches, offline sessions, or dedicated servers where you have permission and all players understand that mods are being used.

## Included

* Rainy's IW4x Trickshot Mod Menu GSC files
* Bot Warfare support files
* Bot waypoint data
* Modified Bot Warfare script installation mod 'z_svr_bots.iwd
* Private match trickshot/lobby/bot tools

## Requirements

* A working IW4x installation (see this repo for instructions: https://github.com/iw4x/launcher)
* Call of Duty: Modern Warfare 2 game files properly set up for IW4x
* 7-Zip, WinRAR, or another archive tool
* Basic knowledge of where your IW4x folder is located

## Installation

1. Download the latest release from the Releases section.
2. Extract the downloaded `.zip` file.
3. Open the extracted folder.
4. Copy the contents of the `mod-files` folder into the correct IW4x folder.
5. Launch IW4x.
6. Start a private match.
7. Open the menu using the listed controls.

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

Some features can be triggered without opening the menu.

| Action                   | Input                       |
| ------------------------ | --------------------------- |
| Toggle Auto Refill Ammo  | Prone + D-pad Up            |
| Save Position            | Prone + D-pad Down          |
| Load Position            | Crouch + D-pad Down         |
| Can Swap Bind            | Standing + D-pad Up         |
| Toggle UFO Mode          | Standing + ADS + D-pad Down |
| Toggle TS Aimbot         | Crouch + D-pad Up           |
| Spawn Trickshot Platform | Crouch + D-pad Left         |

Some quick binds only work when the related feature is enabled from the menu first.


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

## Known Notes/Bugs

* Some custom maps may not support bots correctly.
* Some maps may crash with high bot counts.
* If bots do not move, the map may be missing proper bot/waypoint support.
* This menu is intended for private matches, not public cheating.
* Bots climb ladders weirdly. I believe this is from some edits I did for "Bot Combat" in the mod files, but plan to fix this in future release.

## Credits

* Rainy / Rylee Cobb - IW4x menu development, edits, testing, organization, and release
* Vapour Scripts - original menu resources, tutorials, and modding references
* Bot Warfare creator/community - bot system, waypoint/scriptdata foundation, and related bot support
* IW4x community - client, documentation, testing knowledge, and modding resources

## License

This project is released for learning, private match use, and community modding. Do not sell this menu or claim the work of credited creators as your own.
