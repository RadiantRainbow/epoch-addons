### ☕ Support Development
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support%20Development-orange?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/trav346)

If you find this version of Questie with data collection helpful, consider [buying me a coffee](https://buymeacoffee.com/trav346) to support continued development!

---

### How to Install
1. Download the latest release here https://github.com/trav346/Questie-Epoch/releases
2. Extract the Questie folder into your AddOns folder

---

### 📝 Want to Help? Easy Data Collection!

**⚠️ IMPORTANT: Only submit data collected with Questie v1.0.63 or newer!**
- Older versions had collection bugs that produce incorrect data
- Your export will show the version - if it's older than v1.0.63, please update first

**Quick Start:**
1. **Update to latest version** (v1.0.63+)
2. Type `/qdc enable` to turn on collection - this should persist through log in/out
3. Quest normally - Questie automatically detects if a quest is not in the database and begins collecting data for it!
4. **NEW**: Left-click Questie minimap icon → "Export Quest Data" for quick access!
5. Share on [GitHub](https://github.com/trav346/Questie-Epoch/issues/new)

**Not feeling up to it?** No problem! Just use Questie normally. `/qdc disable`

## v1.0.68 - Latest Release

### Quest Tracking Fixes

**Fixed:**
- **Shift-click quest tracking now works properly**
  - Fixed issue where shift-clicking quests in quest log would only track quests with no objectives
  - Fixed auto-tracking mode preventing shift-click from tracking (only untracking worked)
  - Shift-click now correctly toggles tracking for ALL quests in both manual and auto-track modes
  - Maintains shift-click to link quest in chat functionality

## v1.0.67

### Critical Bug Fixes

**Fixed:**
- **Critical Lua error with bitband function**
  - Fixed "attempt to call global 'bitband' (a nil value)" error that occurred when accepting quests
  - Added missing bitband imports to AvailableQuests.lua and QuestieQuest.lua

## v1.0.66

### Map Icons & Quest Data

**Fixed:**
- **Map icons displaying correctly with borders**
  - Icons now show properly with background borders for better visibility
  - Reverted icon handling to stable version

**New Content:**
- **11 new Epoch quests added** from GitHub issues #229-232
  - Darkshore, Wetlands, Ashenvale, Hinterlands, Feralas, and Duskwood quests
  - Added 9 corresponding NPCs with proper coordinates

## v1.0.63

### Critical Map Pin Fix

**Major Fix:**
- **Map pins now display properly in all major cities!** 
  - Fixed coordinate conversion failure that prevented NPCs from showing on maps
  - Added missing classic zone ID mappings for Stormwind, Ironforge, Orgrimmar, Thunder Bluff, Darnassus, and Undercity
  - Innkeepers, trainers, vendors, and all other NPCs now properly appear on city maps

## v1.0.61

### Quality of Life Improvements & Bug Fixes

**New Features:**
- **Export Button in Minimap Menu**: Quick access to data export (left-click Questie icon)
- **Cleaner Data Collection**: Single-line notifications instead of spam
- **Silent Debug Mode**: All debug messages now respect your settings

**Critical Fixes:**
- Fixed IsComplete nil errors when accepting quests
- Fixed debug messages bypassing toggle settings
- Actually added the 18 troll starting zone quests that were "added" in v1.0.56
- Added 5 more Epoch quests from issue #91

## v1.0.60-hotfix2

### Massive Update: 300+ Quests Added, and Critical Errors Fixed!

**Hotfix2 Updates:**
- Fixed quest 26768 "Barrel Down" compilation error
- Fixed load order error causing crashes on startup
- Added toggle for [DATA] messages - collect silently without chat spam! (`/qdc messages`)

#### All Runtime Errors Fixed
- **No More Crashes**: Fixed AvailableQuests and QuestieTracker nil errors
- **Chat Filter Working**: QuestieShutUp now properly blocks party spam
- **Map Errors Gone**: Custom Project Epoch zones no longer cause errors
- **Data Collector Silent**: No more chat spam - silently tracks quest data

####  All Service NPCs Now Working!
- **WotLK Database Imported**: Fixed version detection for 3.3.5 client
- **All Cities Fixed**: Innkeepers, bankers, auctioneers, trainers show everywhere
- **Stormwind Fully Functional**: All service NPCs at correct Project Epoch locations. Let me know if I missed any.
- **No More Placeholders**: Removed 274 "[Epoch] NPC XXXXX" entries

####  300+ New Quests Added (GitHub Issues #32-87)
This release combines all quest additions from versions 1.0.56 through 1.0.60:

**Starting Zones Complete:**
- **Gnome**: 18 quests with complete NPC data
- **Troll/Orc**: 21 quests including "The Darkspear Tribe", "Banana Bonanza"
- **Human**: Hunter training, Tattered Letter, Soaked Barrel chains

**Major Quest Chains:**
- **Duskwood**: Riders In The Night, Life In Death, Until Death Do Us Part chains
- **Westfall**: Barroom Blitz chain, Hand of Azora chain, The Killing Fields
- **Ironforge Airfield**: Complete 10-quest chain with proper NPCs
- **The Hinterlands**: 11 Alliance quests including "A Sticky Situation" series
- **Desolace**: "The Argus Wake" 5-quest chain (42-44)

**PvP Content:**
- **Ashenvale**: "Fight for Warsong Gulch" battleground introduction
- **Multiple Zones**: 8 "Call to Skirmish" quests for world PvP

**Level 1-60 Coverage:**
- Elwynn Forest, Darkshore, Stranglethorn Vale, Hillsbrad Foothills
- The Barrens, Stonetalon Mountains, Thousand Needles, Mulgore
- Arathi Highlands, Badlands, Swamp of Sorrows, Tanaris
- Winterspring, Eastern Plaguelands, Searing Gorge

#### 🛠️ Major Fixes Since v1.0.56

**Container Collection Fixed:**
- Sun-Ripened Banana containers now properly identified
- Ground object quests show accurate map pins
- Auto-rescan after reload - no manual commands needed

**Quest Tracking Improvements:**
- TomTom no longer changes your tracker sort preference
- Completed quests properly removed from tracker
- Quest items don't cause tracking to break

**Database Cleanup:**
- Fixed duplicate quest entries
- Removed conflicting stub entries
- Updated 100+ quests with complete data

#### 📝 Children's Week Removed
- Seasonal quest no longer shows year-round
- NPCs properly blacklisted

---

## 💡 Known Issues

- Some Epoch quests still have placeholder data - please use /qdc enable to help collect data
- Map icons may not appear for quests with incomplete NPC/object data
- Project Epoch has modified numerous vanilla quests to be cross-faction, causing conflicts with the original database
- Modified vanilla quests may trigger "missing quest" alerts even though they exist (due to significant changes from original)

---

  🙏 Contributors

  Special thanks to:
  - @Bennylavaa for testing and bug reports
  - @desizt and @esurm for the original data collection system
  - All players submitting quest data through GitHub

  ---
