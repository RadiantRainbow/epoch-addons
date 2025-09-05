# Changelog

## [Unreleased]

### Changed
- **Quest Turn-in Icons Now Enabled by Default** - Changed `enableTurnins` default from false to true
  - Users expect to see where to turn in completed quests
  - This is a core feature that should be on by default
  - Users can still disable it if they prefer

### Added
- **NPC Service Flag Detection in Data Collection** - Automatic detection and capture of NPC service types
  - Detects service NPCs through game events (MERCHANT_SHOW, TAXIMAP_OPENED, PET_STABLE_SHOW, etc.)
  - Automatically calculates correct WotLK flag values for detected services
  - Includes detected services in export comments for verification
  - Supports detection of: Quest Giver, Vendor, Repair, Trainer, Flight Master, Innkeeper, Banker, Auctioneer, Stable Master, Battlemaster
  - Ensures submitted NPC data has proper flag values to prevent service NPC miscategorization

### Fixed
- **Available Quests Toggle Not Working** - Fixed issue where unchecking "Show Available Quests" didn't hide quest exclamation marks
  - The new split settings (enableAvailableWorldMap/enableAvailableMinimap) weren't being checked in ShouldBeHidden()
  - World map and minimap toggles now properly control available quest visibility independently
  - Legacy enableAvailable setting also properly respected for backward compatibility
  
- **QuestieQuest nil spawnList Crash** - Fixed "bad argument #1 to 'next' (table expected, got nil)" error at line 1513
  - Added defensive checks for nil or missing spawnList data in quest objectives
  - Prevents crash when quest objectives have incomplete or corrupted spawn data
  - Fixes SavedVariables generation failure reported by v1.1.4 users
  - Safely handles objectives without spawn locations instead of crashing

- **Data Collection UI/UX Improvements** - Made data collection feature more user-friendly and approachable
  - Added clear red notice text when data collection is enabled explaining that tooltip IDs are automatically forced on
  - Removed intimidating "WARNING" text from developer mode options
  - Changed "DEVELOPER FEATURE ONLY" to friendly "Thank you for contributing!" message
  - Users now clearly understand why tooltip ID options are greyed out when data collection is active

- **GitHub Issue Templates Not Working** - Fixed templates not appearing when creating new issues (PR #1110)
  - Renamed `.github/issue_Template` folder to `.github/ISSUE_TEMPLATE` (all uppercase)  
  - GitHub requires exact uppercase naming for issue templates to be recognized
  - Templates now properly appear when users create new issues

- **Data Collector Tooltip Settings Issues** - Fixed multiple tooltip restoration bugs (PR #1168, PR #1190)
  - Fixed case sensitivity bug: `enableTooltipsNpcID` changed to `enableTooltipsNPCID` throughout codebase  
  - Fixed incorrect function call: `RestoreTooltipIDs()` → `RestoreTooltipSettings()` (PR #1190)
  - Data collector now properly saves and restores NPC tooltip settings when disabled
  - Data collector now initializes immediately when enabled in options
  - Tooltip ID options are now grayed out when data collection is enabled (prevents confusion since data collection forces all IDs on)
  - Added missing QuestieDataCollector module import in options panel

- **Runtime Stub Quest Colors Not Respecting User Settings** - Fixed [Epoch] quests always showing white/gray objectives regardless of color preference
  - Objectives without progress counts (exploration, events) were bypassing user's "Red to Green" color setting
  - Safety checks added for Epoch runtime stubs were incorrectly returning gray instead of respecting tracker color preferences
  - Now properly shows red for incomplete objectives and green for completed when "Red to Green" is selected
  - Fixes GitHub Issue #1135 where users reported white objectives despite having gradient colors enabled

- **CRITICAL: Available Quest Toggle Broken** - Fixed issue where disabling Available Quests caused icons to cluster at service NPCs
  - Quest icons were being drawn but redirected to flight masters, mailboxes, and spirit healers when toggle was off
  - Added proper check in `DrawAvailableQuest` to prevent drawing when `enableAvailable` is false
  - Icons now properly hide when Available Quests is disabled instead of clustering at wrong locations
  - Affected all zones, not just specific areas
  - This fixes the confusing behavior where quest data appeared on unrelated map pins

- **CRITICAL: Minimap Menu Toggles Breaking All Icons** - Fixed Available Quest and Objective toggles disabling ALL map icons
  - Available Quest toggle was incorrectly calling `ToggleNotes()` with its own state, affecting all icons globally
  - Objective toggle had the same bug, turning off all icons when disabled
  - Removed incorrect `ToggleNotes()` calls from both toggles
  - This fixes the issue where toggling these options would completely break icon display
  - Also fixes interaction with Trivial Quest toggle that was causing all icons to disappear

- **CRITICAL: Classic Database Using Wrong NPC Flag Values** - Fixed entire Classic database using Classic WoW 1.x flags instead of WotLK 3.3.5 flags
  - Classic and WotLK use completely different flag values for service NPCs (e.g., STABLEMASTER: Classic=8192 vs WotLK=4194304)
  - Fixed ~480 service NPCs with wrong flag values:
    - 43 Stable Masters (8193 -> 4194305) - were showing as flight masters
    - 14 Spirit Healers (0 -> 16385) - were completely missing
    - 61 Flight Masters (11 -> 8195) - including Gryphon Masters, Wind Rider Masters, Bat Handlers
    - 45 Innkeepers (133/135 -> 65669/65671)
    - 27 Bankers (256-259 -> 131072-131075)
    - 28 Auctioneers (4096 -> 2097152) - were completely missing from lists
    - 24 Battlemasters (2049 -> 1048577) - were not showing properly
    - 258 Repair NPCs (16388/16391 -> 4224/4227) - had wrong categorization
    - 22+ Vendors (6/7 -> 130/131)
  - This fixes stable masters showing as flight masters, spirit healers as vendors, and service NPCs missing entirely
  - Required complete database recompilation after flag fixes
  - Service NPC counts after fixes: 240 Repair, 40 Innkeepers, 35 Spirit Healers, 58 Flight Masters, 41 Stable Masters, 28 Auctioneers, 15 Battlemasters, 27 Bankers

- **Available Quests Disabled by Default** - Fixed Available Quests being OFF by default after fresh install
  - Available quests on map is a core Questie feature and should be enabled by default
  - Changed `enableAvailable` from false to true in QuestieOptionsDefaults
  - New users will now see available quests immediately after installation

## [1.2.0-prerelease2] - 2025-01-04

### Added
- **QuestCompletenessScorer Module** - New data quality validation system for quest submissions
  - Comprehensive scoring algorithm for quest data completeness
  - Validates quest giver, turn-in, objectives, and coordinate accuracy
  - Supports both legacy and live data collection formats
- **Enhanced Data Collection** - Improved quest data capture and validation
- **DATABASE_REFERENCE.md Integration** - Complete database structure documentation for development

### Changed
- **Version Update** - Bumped to 1.2.0-prerelease2 for expanded testing
- **Database Structure Validation** - Enhanced validation for Epoch quest and NPC entries
- **Options and UI Improvements** - Refined tracker and options interface behavior

### Fixed
- **CRITICAL: QuestieMap.lua Nil Value Error** - Fixed "attempt to index local 'minimapDrawCall' (a nil value)" crash at line 341
  - Moved draw call post-processing inside proper if blocks to prevent nil access
  - Prevents crashes when map drawing queues are empty or partially processed
  - Affects both map and minimap icon rendering systems
- **Quest Event Handling** - Improved quest state tracking and event processing
- **Data Collection Accuracy** - Better capture of quest giver and turn-in information
- **Epoch Database Corrections** - Updated quest and NPC data for Project Epoch server

### Added
- **Update Reminder System** - Silent, one-time reminder to help users know about latest releases
  - Shows once per session with 2-second delay to avoid intrusiveness
  - Includes option to disable update reminders in Advanced Options
  - Cleaned up version check and slash commands
  - Helps users stay informed about important fixes and features

### Fixed
- **CRITICAL: QuestieDB.lua StartedBy Nil Value Flood** - Fixed massive error spam in database processing threads
  - Added defensive nil check for `QO.startedBy` before accessing startedBy[1], startedBy[2], startedBy[3]
  - Prevents flood of "attempt to index local 'startedBy' (a nil value)" errors at QuestieDB.lua:1401
  - Quest data with missing startedBy fields now gets safe nil values instead of crashing
  - **This stops the continuous error spam that was flooding users**

- **CRITICAL: Database Corruption Cascade Errors** - Fixed critical errors causing addon initialization failures
  - Added comprehensive defensive checks to `QuestieQuest:PopulateObjective()` function to prevent crashes from corrupted quest data
  - Implemented automatic detection and cleanup of corrupted SavedVariables data during addon initialization
  - Fixed crashes from missing `quest.ObjectiveData`, invalid `objective.Index`, and malformed objective structures
  - Added runtime validation and repair of quest objective properties (`spawnList`, `Update` method, etc.)
  - Prevents cascade errors that were preventing addon loading after database expansion
  - Users with corrupted data will see automatic cleanup messages on first login after this fix
  - **This resolves the "QuestieQuest.lua:71" error chain reported by users**

- **CRITICAL: Corrections Module Initialization Errors** - Fixed "table index is nil" errors during corrections loading
  - Implemented comprehensive hardcoded fallback system for all database tables when not loaded during initialization
  - Fixed multiple functions in `classicQuestFixes.lua`: `Load()` and `LoadFactionFixes()` both get fallback logic
  - Fixed missing `name` key (value 1) that was causing "classicQuestFixes.lua:143" error  
  - Fixed `LoadFactionFixes()` function that was missing fallback logic causing "classicQuestFixes.lua:4128" error
  - Added complete questKeys fallback table with all 30 keys from questDB.lua to all correction functions
  - Added zoneIDs fallback table with 40+ commonly used zones from zoneTables.lua  
  - Added fallback tables for raceIDs, classIDs, sortKeys, factionIDs, and profession keys
  - **Removed scary warning messages** - fallback system now operates silently to avoid user panic
  - **This resolves "questKeys.reputationReward is nil (0 total)", "classicQuestFixes.lua:143", and "classicQuestFixes.lua:4128" errors**

- **QuestLogCache Race Condition Errors** - Fixed "quest doesn't exist in QuestLogCache" errors during quest acceptance  
  - Modified `QuestLogCache.GetQuest()` to return nil gracefully instead of throwing user-visible errors
  - Modified `QuestLogCache.GetQuestObjectives()` to return nil gracefully instead of throwing user-visible errors  
  - Added intelligent logging: only shows debug messages for questId=0 (invalid) or when debug mode enabled
  - Fixed race condition where quest acceptance tries to access cache before it's populated
  - Prevents error spam during quest acceptance for quests not yet in database or cache
  - **Resolves "GetQuest: The quest doesn't exist in QuestLogCache. 0" errors reported in Hinterlands**

- **CRITICAL: WoW 3.3.5 Profession Tracking (Issue #1093)** - Fixed "GetProfessions doesn't exist" crash during profession quest acceptance
  - Replaced incompatible `GetProfessions()` API call with QuestieProfessions module for 3.3.5 compatibility
  - **EXPANDED SCOPE**: Now tracks professions for ALL skill-required quests, not just commission quests
  - Uses `questDB.requiredSkill` database field to detect ANY quest requiring profession skills
  - Fixed crash when accepting herbalism/mining/crafting quests and ALL profession-based quest types
  - Data collector now captures player professions for proper quest requirement validation
  - Uses `GetNumSkillLines()` and `GetSkillLineInfo()` APIs that exist in WoW 3.3.5 instead of post-4.0.1 APIs
  - **Resolves "GetProfessions doesn't exist in QuestieDataCollector.lua" errors for ALL profession quests**

- **Data Collection Debug Message Bypassing User Settings** - Fixed flight master and quest tracking messages showing even when [DATA] messages disabled
  - Fixed `DEFAULT_CHAT_FRAME:AddMessage()` calls bypassing user's debug message preferences
  - All [DATA] messages now properly respect the "Show data collection messages" setting
  - Flight master capture messages now use `DebugMessage()` instead of direct chat output
  - **Resolves users seeing unwanted [DATA] messages despite having them disabled in settings**

- **CRITICAL: Settings Reset on Version Updates** - Fixed user settings reverting to defaults during addon updates
  - Changed AceDB profile initialization to preserve user settings instead of resetting on compatibility issues
  - Map icon disable settings now persist through version updates instead of being re-enabled
  - All custom user preferences (tracker settings, icon scales, etc.) now survive addon updates
  - **Resolves widespread user reports of having to reconfigure settings after each update**

- **CRITICAL: Map Pins Not Showing** - Fixed invisible pins and added comprehensive diagnostics
  - **Enhanced Migration**: Fixed 'custom' icon theme detection that was bypassed by profile resets during version updates
  - **Invalid Theme Protection**: Now detects and fixes any invalid/unknown icon theme names that cause invisible pins
  - **New Diagnostic Command**: Added `/questie diagnose` command to help users identify why pins aren't showing
  - **Complete Settings Check**: Diagnoses addon enabled status, map/minimap icon settings, icon theme issues, and continent filtering
  - **User-Friendly Guidance**: Provides clear instructions on how to fix each identified problem
  - **Automatic Fix**: `/reload` now automatically fixes 'custom' theme and other invalid icon themes
  - **Resolves all user reports of "map pins not showing" with easy troubleshooting**

- **CRITICAL: Settings Reset Every Login (Issue #871)** - Fixed infinite migration loop causing settings to reset constantly
  - **Root Cause**: "Reset Questie" button set migrationVersion=nil, causing migration v1 to run on every login and reset all settings
  - **Fixed Reset Function**: Now properly sets migrationVersion to current version after reset instead of nil
  - **Dynamic Version Tracking**: Added Migration:GetCurrentMigrationVersion() method to prevent hardcoded version numbers
  - **Enhanced Diagnostics**: `/questie diagnose` now shows migration status and warns about pending migrations
  - **User Warnings**: Migration system now detects and warns users stuck in migration loops
  - **Persistent Settings**: User settings will no longer reset every login after using "Reset Questie"
  - **Resolves widespread Issue #871 reports of having to reconfigure settings after every login**

- **Enhanced Version Display & Update Tracking** - Added version visibility and out-of-date indicators
  - **Settings Window Title**: Now shows "Questie v1.2.0" instead of just "Questie" 
  - **Startup Message**: Chat login message now displays current version number
  - **Out-of-Date Indicators**: When users dismiss update prompts, shows "- out of date" in both settings title and startup message
  - **Smart Update Detection**: Automatically clears "out of date" status when user updates to newer version
  - **Version Persistence**: Tracks which version user dismissed to avoid repeated prompts for same version
  - **Improved User Awareness**: Users can easily see their current version and update status at a glance

- **Centralized Version Management** - Eliminated hardcoded version numbers throughout codebase
  - **Single Source of Truth**: All version references now read from Questie.toc file using GetAddOnMetadata()
  - **Eliminated Hardcoded Versions**: Removed outdated hardcoded versions in QuestieVersionCheck (1.1.3) and QuestieDataCollector (1.1.3, 1.1.0)
  - **Dynamic Version Detection**: Version checking, data collection exports, and diagnostics now automatically use current version
  - **Simplified Maintenance**: Only need to update version in one place (TOC file) for releases
  - **Clear Release Process**: Documented process for version management and update detection
  - **Prevents Version Drift**: No more outdated hardcoded versions causing confusion or incorrect behavior

### Fixed
- **CRITICAL: Coordinate System API Failures (Issue #3)** - Fixed coordinate type mismatches causing crashes and positioning errors
  - **API Usage Fix**: Fixed QuestieDataCollector incorrectly calling QuestieCoords.GetPlayerMapPosition() expecting separate x,y values instead of position table
  - **Type Safety**: Eliminated "x=table y=number" coordinate type mismatches that were causing crashes in data collection
  - **Position Accuracy**: Quest objective markers now appear in correct locations instead of failing coordinate validation
  - **Data Collection Stability**: Fixed coordinate comparison failures that were crashing QuestieDataCollector during quest tracking
  - **Map Integration**: Restored proper coordinate handling for quest positioning and map waypoints
  - **This eliminates the coordinate crashes affecting quest data collection and map integration**

- **CRITICAL: Runtime Stub System Logic Errors (Issue #2)** - Fixed incorrect quest prefixes, zones, and levels
  - **Quest Prefix Logic**: Fixed hardcoded ID range check causing Project Epoch's reused TBC quest IDs (11160, 11161) to get [Missing] prefix instead of [Epoch]
  - **Zone Assignment**: Runtime stubs now use actual current zone ID instead of defaulting to 0 (unknown zone)
  - **Quest Levels**: Fixed quest levels defaulting to 0 by extracting actual level from client quest log
  - **Known Quest ID Reuses**: Added explicit handling for Project Epoch quests that reuse TBC quest IDs in different zones
  - Quest 11160 "Banner of the Stonemaul" now correctly shows [Epoch] prefix and Dustwallow Marsh zone instead of [Missing] and Westfall
  - Quest 11161 "The Essence of Enmity" now correctly shows [Epoch] prefix and proper zone/level information
  - **This fixes the systematic misreporting of quest attributes (level, location, faction) for hundreds of quests**

- **CRITICAL: Missing NPC Database Entries (Issue #1)** - Resolved database compilation failures
  - Fixed 10 missing NPC entries in epochNpcDB.lua causing `[CRITICAL] [QuestieDB:GetNPC] rawdata is nil` errors
  - Added NPCs: Mogern Blackeye (45069), Aeromir (45555), High Chief Ungarl (46009), Marwin Shrillwill (46094), Luyua Earthmoon (46130), Ordo Earthmoon (46131), Sasia Forestcrest (46165), Lorespeaker Vanza (46233), Dead Troll (46234), S.J. Erlgadin Jr. (46278)
  - Added placeholder for NPC 46293 pending data collection
  - All NPCs extracted from GitHub quest submissions with complete coordinate and quest relationship data
  - Database compilation now succeeds without CRITICAL lookup errors
  - Quest markers and interactions now work properly for affected quests (27370, 26771, 27314, 27315, 27509, etc.)
  - **This fixes the cascade failures preventing proper quest display and interaction**

### Added
- **Enhanced Quest Data Collection** - Now tracks player class, race, faction, and level information
  - Records player class and race when accepting quests (useful for class/race specific quest analysis)
  - Captures player faction (Alliance/Horde) for faction-specific quest identification
  - Records player level at time of quest acceptance
  - Information appears in exported quest data for GitHub submissions
  - Helps identify quest requirements and availability patterns

## [1.1.3] - 2025-09-03

### Fixed
- **Repository Cleanup** - Removed accidentally included temporary analysis files from release
  - Cleaned up development files that were not intended for distribution
  - Added additional patterns to .gitignore to prevent future inclusion
  - Maintains clean addon package for users

## [1.1.2] - 2025-09-03

### Added
- **Legacy Quest Data Integration** - Massive community quest database expansion
  - Processed 875 GitHub quest submissions from dedicated Project Epoch players  
  - Successfully integrated 173 brand new quest entries into database
  - Updated 4 existing quests with improved data from community submissions
  - Database now contains **757 total Epoch quests** (30% increase from 584)
  - 97% validation success rate on legacy data processing pipeline
  - All quest data syntax-validated and compilation-tested before integration
  - Automated merge system ensures only quality improvements to existing data
  - **Special thanks to every player who submitted quest data over the past week!**

### Fixed
- **Data Collection Export Crashes** - Fixed LibGroupTalents conflict preventing `/qdc export` from working
  - Added pcall protection around export functions to prevent third-party addon conflicts
  - Skada addon's LibGroupTalents-1.0 was causing arithmetic errors when export window opened
  - Export now gracefully handles conflicts and provides helpful error messages
  - Both slash command `/qdc export` and minimap "Export Quest Data" button now protected
- **Coordinate Formatting Crashes in Export** - Fixed "bad argument #2 to 'format' (number expected, got nil)" errors
  - Replaced unsafe string.format coordinate calls with SafeFormatCoords function
  - Fixed multiple locations in FormatQuestExport that could crash with nil coordinates
  - Export now gracefully handles missing coordinate data instead of crashing

## [1.1.1] - 2025-01-03

### Fixed
- **QuestieSlash command error with ClearAllNotes**
  - Fixed incorrect module reference: QuestieMap:ClearAllNotes() → QuestieQuest:ClearAllNotes()
  - Resolves "attempt to call method 'ClearAllNotes' (a nil value)" error during quest refresh
- **Data Collection coordinate formatting crashes**
  - Fixed nil coordinate values causing string.format errors in export window
  - Added SafeFormatCoords() helper function for defensive coordinate handling
  - Prevents "bad argument #2 to 'format' (number expected, got nil)" crashes
  - Graceful fallback messages for missing or invalid coordinate data
- **Enhanced objective tracking improvements from v1.0.68 analysis**
  - Improved progress location tracking with mob kill information
  - Added "Progress locations:" section matching v1.0.68 format
  - Progress entries now show "[55.4, 12.9] in Durotar - Killed Bloodtalon Scythemaw"
  - Enhanced objective type detection: (monster), (item), (area)
  - Better correlation between combat events and quest progress updates
  - Added kill tracking with 5-second correlation window for progress updates
  - Enhanced export format to display detailed objective progress like v1.0.68

### Added
- **Automatic completed quest sync on version updates**
  - Questie now automatically refreshes completed quests from server when updated
  - Fixes stuck quest markers that may appear after updates
  - Runs once per version update via migration system
- **Enhanced completed quest refresh command**
  - `/questie refreshcomplete` now properly queries server for completed quests
  - Clears all map icons and redraws after refresh to fix stuck quest markers
  - Shows progress messages during refresh process
- **New quest completion check command**
  - `/questie checkcomplete <questId>` checks if a quest is marked complete
  - Shows both local database and server status
  - Warns if there's a mismatch between local and server data

### Fixed
- **QuestieMap error with invalid zone IDs**
  - Fixed "No UiMapID for SelfieCamera_SoloModeWorlds" error on addon load
  - Added validation to reject non-numeric zone IDs (frame names from modern WoW)
  - Prevents crashes when other addons pass invalid data to map functions
  - Gracefully handles invalid area IDs without throwing errors
- **Map pin tooltips not showing without ElvUI**
  - Fixed missing QuestieCompat.SetupTooltip call for 3.3.5 clients
  - Restored proper tooltip selection logic from reference version
  - SetupTooltip correctly chooses between GameTooltip and WorldMapTooltip based on context
  - Tooltips now work correctly without requiring ElvUI or other addons
- **Data Collection: [DATA] messages now respect toggle setting**
  - Fixed [DATA] messages showing in chat despite toggle being disabled
  - Converted 11 direct chat messages to use DebugMessage function
  - Important "Epoch quest not in database accepted" messages always show
  - Users can now disable data collection spam while keeping critical notifications
- **Data Collection: Objects incorrectly captured as NPCs**
  - Fixed GUID type detection to properly distinguish NPCs from objects
  - Objects like "Pirate's Treasure" no longer show as "Captured NPC"
  - Corrected GUID byte extraction (positions 5-6 instead of 3-4)
  - Proper identification of GameObject (0x50), Item (0x60), DynamicObject (0x70)
- **CRITICAL: Gnome starting quest bug** - Quest 28725 "Shift into G.E.A.R." now shows mob markers on map
  - Fixed questFlags from 8 to 2 (questFlags=8 prevents map markers from displaying)
  - Added missing quest 28725 (actual gnome quest ID, not 28901 as previously listed)
  - Fixed NPC 46836 (Tinker Captain Whistlescrew) to start/end quest 28725
  - Fixed questFlags for all gnome starting quests (28725, 28901-28903, 28726-28731)
- **Database cleanup and performance** - Removed 43 duplicate quest entries
  - Automated duplicate detection and removal system
  - Cleaner database structure improves loading performance
- **Container name capture for data collection** (Issue #32)
  - Fixed "Unidentified Container" errors when looting ground objects
  - Proper capture of container names like "Sun-Ripened Banana"
  - Removed 5-second timestamp restriction causing data loss
  - Don't overwrite good container data with placeholder names
- **Tracker crashes fixed** - Nil SavedVariables initialization
  - Fixed AutoUntrackedQuests and TrackedQuests nil errors on first run
  - Added runtime initialization for missing SavedVariables fields
  - Defensive nil checks prevent tracker crashes
- **Project Epoch server compatibility**
  - Disabled WotLK database contamination (Project Epoch is Vanilla server using 3.3.5 client)
  - Commented out wotlk*.lua database files in TOC
  - Proper quest count now shows ~4,824 instead of incorrect 7,899
- **Data collection improvements**
  - Fixed turn-in NPC capture by immediately capturing during QUEST_COMPLETE event (matching v1.0.68 working logic)
  - Improved quest ID detection in QUEST_TURNED_IN event for better XP reward capture
  - Fixed missing objectives and XP rewards in quest data export
  - Enhanced quest turn-in tracking for rapid quest completions
  - Fixed quest ID retrieval using position 9 in GetQuestLogTitle (WoW 3.3.5)
  - Fixed objectives showing initial state (0/10) instead of current progress
  - Fixed GetQuestLogQuestText to capture both description and objectives text
  - Implemented ground object/container tracking matching v1.0.68 functionality
- **Flight masters incorrectly categorized as service NPCs**
  - Fixed flight masters being stored in serviceNPCs table instead of flightMasters
  - Flight master count now correctly displays in export summary
  - Proper separation of flight masters from other service NPCs in export
  - Fixed export format to correctly display flight master locations
- **Close and Purge Data button not working in export window**
  - Fixed button to properly clear all collected data using ClearData function
  - Now mirrors `/qdc clear` functionality exactly
  - Clears all data types: quests, service NPCs, mailboxes, flight masters, etc.
  - Added reminder to use /reload to free memory after purging
- **Export data unicode characters causing copy/paste issues**
  - Replaced all unicode symbols with ASCII equivalents for better compatibility
  - Changed ✓/✗ to [x]/[ ] for objectives
  - Changed ▶ to > for section headers
  - Changed ═══ to === for separators
  - Changed • to * for bullet points
  - Changed ⚠️ to WARNING: for alerts
  - Export data now uses only standard ASCII characters
- **Removed zone change coordinate cache debug message**
  - Eliminated spammy "[DATA] Zone changed, invalidating coordinate cache" message
  - Cache invalidation still works, just silently
- **Fixed incomplete objective text for some quests**
  - Added smart extraction of mob names from objectives text when API returns incomplete data
  - Fixes quests like "Panther Mastery" showing just "slain: 0/10" instead of "Panther slain: 0/10"
  - Parses common quest patterns like "Kill 10 Panthers" to extract mob names
  - Works around WoW 3.3.5 API inconsistencies in objective text
- **Innkeeper service priority over vendor**
  - Fixed innkeepers being listed as vendors instead of innkeepers
  - Added detection for innkeeper service through GOSSIP_SHOW event
  - Implemented service priority system (innkeeper > banker > flight_master > trainer > repair > vendor)
  - Vendor service no longer overrides innkeeper identification
  - Services now sorted by importance in exports

### Changed
- **Data collection export format restructured**
  - Service NPCs now appear at the bottom of export for better organization
  - Added clear ══════ separators between each quest for improved readability
  - Flight masters now have their own dedicated section in exports

### Added
- **QuestieDataValidator module** - New validation system for database integrity
  - Validates quest and NPC database structure and field types
  - `/qdc validate` command for on-demand validation
  - Automatic validation during addon initialization
  - Catches database corruption before runtime errors occur
- **Enhanced data collection system** - 28 collection points for comprehensive quest data
  - Flight master tracking for all major cities and zones
  - Ground object/container tracking with improved name capture
  - Duplicate quest detection and cleanup tools
  - Smart merge system for integrating external quest databases
- **Ground object/container tracking** - Captures all interacted objects/containers while questing (herbs, ores, quest objects, etc.)
  - Tracks multiple locations for same object
  - Groups objects by name with all discovered coordinates
  - Exports in GROUND OBJECTS/CONTAINERS section matching v1.0.68 format
- `/qdc rescan` command to recapture missing quest objectives and current progress
- Quest status display in exports (COMPLETED/IN PROGRESS/PARTIAL DATA)
- Progress history tracking for objectives with timestamps and coordinates
- Tooltip hook to capture object names on mouseover before interaction
- Better fallback methods for determining quest ID during turn-in events

## [1.1.0] - 2025-09-01

### Major Features
- **Complete Data Collection System Overhaul**
  - Version control: We will only accept data from v1.1.0 or later
  - Smart detection: Only tracks quests missing from database (skips known quests)
  - Mismatch detection: Identifies database inconsistencies for NPCs, objects, items, coordinates
  - Zone validation: Enhanced accuracy with comprehensive zone tracking
  - Service NPC tracking: Captures vendors, trainers, bankers, mailboxes while questing
  - Developer mode: Toggle to collect ALL quests for testing purposes
  - Coordinate validation: Only flags significant mismatches (>10 units) to reduce false positives
  - Export improvements: Includes database mismatches and coordinate discrepancies in reports
  - XP reward tracking: Captures experience points awarded for quest completion
  - Robust nil handling: All quest events now handle nil questIds properly (WoW 3.3.5 compatibility)

### Critical Fixes
- **Major database structure overhaul**
  - Corrected quest objective structure (nil objectives must be in spellObjective position)
  - Fixed quests 27040, 27041, 27462 compilation errors from incorrect objective structure
  - Removed incorrect database prefixes causing syntax errors
  - Complete syntax validation ensuring database loads without errors

- **Invisible map pins crisis resolved**
  - Fixed "custom" icon theme causing all quest pins to be invisible
  - Disabled custom theme option to prevent user confusion
  - Pins now show correctly with questie/classic themes

- **Tooltip scaling inconsistency fixed**
  - Fixed tooltip size changing with map zoom level
  - Now always uses GameTooltip instead of WorldMapTooltip for consistent sizing
  - Resolves map addon integration issues with scaled tooltips

- **Quest progress not updating in tracker (Issue #467)**
  - Fixed tracker showing 0/10 when quest log shows actual progress (e.g., 3/10)
  - The compatibility layer was only reading 3 parameters from GetQuestLogLeaderBoard instead of 5
  - In WoW 3.3.5, the API returns: description, type, finished, numFulfilled, numRequired
  - Now properly reads numFulfilled and numRequired directly from the API instead of parsing text
- **Quest 1014 "Arugal Must Die" showing in wrong location**
  - Fixed NPC 1938 (Dalar Dawnweaver) incorrectly placed in Tirisfal Glades
  - Corrected to proper location in Silverpine Forest (The Sepulcher)
  - Quest now properly shows at coordinates 44.2, 39.8 in zone 130

- **NPC ID printing twice in tooltips (Issue #469)**
  - Added duplicate detection for NPC ID, Item ID, and Object ID in tooltips
  - Prevents IDs from being added multiple times when tooltip is refreshed
  - Checks existing tooltip lines before adding ID information

- **Service NPC tracking/untracking issues in map dropdown**
  - Fixed untracking not working when unchecking service types (Innkeeper, Banker, etc.)
  - Fixed duplicate NPCs appearing when toggling service tracking on/off
  - Now properly clears all existing frames before spawning new ones to prevent duplicates
  - Ensures complete cleanup of manual frames when untracking service NPCs
- **Objective Color "Red to Green" crashes with Epoch quests (Issue #332)**
  - Fixed nil concatenation error when using colored objectives with Epoch runtime stub quests
  - Added safety checks for nil or zero objective.Needed values (common with Epoch quests)
  - Completed objectives without progress data now properly show green
  - Unknown progress objectives show gray instead of crashing
- **Lua error when turning in commission quests (Issue #428)**
  - Fixed nil value error in QuestieQuest.lua line 1037
  - Added safety check for quests without objectives data (common for commission/Epoch quests)
  - Prevents crash when processing source items for quests lacking database entries

- **Data Collection critical errors fixed**
  - Fixed "QuestieDB was passed as questId" errors from incorrect API syntax
  - Changed QuestieDB:GetQuest() to QuestieDB.GetQuest() (dot notation)
  - Resolves critical errors that were spamming console on initialization
  - Fixed QUEST_ACCEPTED event providing nil questId in WoW 3.3.5
  - Now properly retrieves questId from quest log when event doesn't provide it

### Added
- **New `/qdc questgiver` command (Issue #485)**
  - Manually capture quest giver NPC information for any quest
  - Works similarly to `/qdc turnin` command
  - Target the quest giver NPC and run `/qdc questgiver <questId>`
  - Helps recover missing or incorrect quest giver data
  - Automatically creates quest entry if it doesn't exist
  - Clears "incomplete data" warning when quest giver is captured
- **Profession data capture in QuestieDataCollector**
  - Captures player's profession levels when accepting quests
  - Records current skill rank, max rank, and tier (Apprentice/Journeyman/Expert/Artisan)
  - Helps identify profession requirements for commission quests
  - Displays profession data in quest export for GitHub submissions
- **Full quest text capture**
  - Now captures complete quest description text
  - Captures full objectives text (not just parsed bullet points)
  - Preserves quest narrative for database improvement
  - Included in quest export for better documentation
- **New toggle: Auto Track All Quests on Login**
  - Located in Tracker Settings under Auto Track Quests option
  - When disabled, your manually tracked quest selection persists between sessions
  - When enabled (default), all quests are automatically tracked on login/reload
  - Allows players to maintain their preferred quest tracking without it resetting

## [Unreleased]

## [1.0.70] - 2024-08-31

### Added
- **Object ID capture for quest-starting objects (wanted posters, books, etc.)**
  - Data collector now captures object IDs when accepting quests from interactable objects
  - Export format includes object quest starters with proper database entries
  - Displays object information in quest tracking and export windows

### Fixed
- **Felicia Maline flight master location in Darkshire (Issue #419)**
  - Fixed flight master map pin showing at wrong location
  - Corrected coordinates to proper flight master position (77.4, 44.3)

### Added (from GitHub issues)
- **Commission: Vegan-Friendly Recipe (Issue #416)**
  - First Aid profession quest requiring skill level 75+
  - Properly marked with requiredSkill field for profession filtering
  - Quest giver: Garrison Grader in Tirisfal Glades
  - Turn-in: Private Waldric in Elwynn Forest
- **28 new Epoch quests from GitHub issues #238-261**
  - Complete quest data for The Handmaiden's Fall chain (26714, 26715)
  - Multiple "Fit For A King" quests with different objectives
  - Cross-faction delivery quests with proper NPC locations
  - 11 new custom NPCs for quest givers and turn-ins
- **6 new Epoch quests from GitHub issues #264-267**
  - Silverpine Forest: The Missing Initiate chain (26875, 26877, 26878)
  - Hillsbrad Foothills: A Lost Warrior (26795)
  - Alterac Mountains: Justice Left Undone (26817) - updated with complete data
  - Ashenvale: CHOP! (27030) - Horde event quest

### Fixed
- **Quest 27049 faction flag corrected (Issue #261)**
  - Changed from Alliance (8) to Horde (2) since quest sends players to Orgrimmar
- **96 TBC/WotLK flight masters removed from maps (Issue #262)**
  - Blacklisted all non-existent flight masters (NPCs with IDs 17000+)
  - Fixes Suralais Farwind incorrectly showing at Forest Song in Ashenvale
  - Removes confusing flight path markers for NPCs not present in Project Epoch
- **7 Classic flight masters restored to maps**
  - Fixed incorrect npcFlags overrides that were hiding legitimate flight masters
  - Restored: Jarrodenus (Azshara), Mishellena (Felwood), Bibilfaz Featherwhistle (WPL), Vhulgra (Ashenvale), Khaelyn Steelwing (EPL), Georgia (EPL), Faustron (Moonglade)

## [1.0.69] - 2024-08-31

### Added
- **New Epoch quests from GitHub issues #241-244, #246**
  - The Barrens: Exterminate the Brutes (26856)
    - Added quest giver Ko'gar the Thunderer and target mobs (Razormane Hunters, Thornweavers, and Defenders)
  - The Barrens: Plainstrider Menace (26918)
    - Added quest giver Kodo Wrangler Grish and loot targets (Greater, Ornery, and Elder Plainstriders)
  - Stormwind/Elwynn Forest: Commission for Marshal Haggard (28350)
    - Quest giver: Brother Benjamin in Stormwind (coords adjusted from user data)
    - Turn-in: Marshal Haggard at Eastvale Logging Camp
    - Note: Corrected coordinate inconsistencies in submitted data
  - Darnassus/Westfall: An Old Man's Request (26597)
    - Quest giver/turn-in: Old Man Thistle in Darnassus
    - Kill target: Klaven Mortwake in Westfall
    - Note: NPC 7740 is Gracina Spiritmight in Classic but renamed for Epoch
  - Eastern Plaguelands: Into the Scarlet Enclave (28905 - originally 26769)
    - Quest giver/turn-in: Knight-Commander Entari
    - Kill 12 Scarlet mobs in the Scarlet Enclave
    - Note: Changed to ID 28905 due to duplicate quest ID conflict

### Fixed
- **Duplicate quest ID issue**
  - Quest 26769 was defined twice (Gnarlier Than Thou and Just Desserts)
  - Moved "Just Desserts" part 1 to ID 28904 to resolve conflict

## [1.0.68] - 2024-08-31

### Fixed
- **Shift-click quest tracking in quest log now works correctly**
  - Fixed bug where shift-clicking quests would only track quests with no objectives
  - Fixed auto-tracking mode conflict that prevented shift-click from tracking quests
  - Removed duplicate shift-click handling in AQW_Insert that was overriding the toggle behavior
  - Shift-click now properly toggles tracking for ALL quests (tracks if untracked, untracks if tracked)
  - Maintains compatibility with shift-click to link quest in chat

## [1.0.67] - 2024-08-31

### Fixed
- **Critical Lua error with bitband function**
  - Fixed "attempt to call global 'bitband' (a nil value)" error
  - Added missing bitband imports to AvailableQuests.lua and QuestieQuest.lua
  - Resolves error when accepting quests

## [1.0.66] - 2024-08-31

### Fixed
- **Map icons displaying correctly with borders**
  - Icons now show properly with the new border backgrounds
  - Reverted icon handling to match clean working version
  - Removed all debug code from icon system

### Added
- **11 new Epoch quests from GitHub issues #229-232**
  - Darkshore: The Twilight's Hammer (26202), Welcome to Auberdine (26203), Wanted: Grizzletooth (26208)
  - Darkshore: Commission for Gubber Blump (28064), Commission for Lornan Goldleaf (28521) 
  - Wetlands: Message to Menethil (27021)
  - Ashenvale: Forsaken Looters (27038)
  - The Hinterlands: Parts From Afar (26186)
  - Feralas: Fit For A King (26293), Wanted: Lost Ancient (27335)
  - Duskwood: Updated placeholder for Commission for Watcher Dodds (28476)
  
- **9 NPCs for the new quests**
  - Added quest givers, turn-in NPCs, and target mobs with proper coordinates

## [1.0.65-hotfix2] - 2024-08-31

### Fixed
- **Removed additional debug output**
  - Removed TRACKER DISPLAY debug message from TrackerUtils.lua

## [1.0.65-hotfix] - 2024-08-31

### Fixed
- **Tracker showing random number of quests after login instead of all tracked quests**
  - Removed flawed "corruption detection" logic that incorrectly reset tracked quests
  - Fixed logic that considered having all quests tracked (0 untracked) as corrupted state
  - Added SyncWatchedQuests function to properly initialize tracking state on login
  - Fixed multiple nil reference errors in QuestLogCache and QuestieQuest modules
  - Added defensive checks for uninitialized QuestLogCache.questLog_DO_NOT_MODIFY
  - Fixed undefined tempQuestIDs variable reference in tracker module
  - Fixed syntax error with orphaned code block in QuestLogCache
  - All 25 quests now properly tracked and displayed after login
  - **Hotfix**: Removed all debug print statements that were spamming chat

## [Unreleased]

### Fixed
- **Map icons showing as colored dots instead of proper icons**
  - Added fallback texture handling in UpdateTexture function
  - Ensures icon types are properly converted to texture paths
  - Provides fallback icon when texture is invalid or missing

### Added
- **11 new Epoch quests from GitHub issues #229-232**
  - Darkshore: The Twilight's Hammer (26202), Welcome to Auberdine (26203), Wanted: Grizzletooth (26208)
  - Darkshore: Commission for Gubber Blump (28064), Commission for Lornan Goldleaf (28521) 
  - Wetlands: Message to Menethil (27021)
  - Ashenvale: Forsaken Looters (27038)
  - The Hinterlands: Parts From Afar (26186)
  - Feralas: Fit For A King (26293), Wanted: Lost Ancient (27335)
  - Duskwood: Updated placeholder for Commission for Watcher Dodds (28476)
  
- **9 NPCs for the new quests**
  - Added quest givers, turn-in NPCs, and target mobs with proper coordinates
  
- **Quests requiring two clicks to track**
  - Fixed malformed item objectives in database (e.g., `{{itemId}}` instead of `{{itemId,qty,"name"}}`)
  - Added runtime fix to handle both proper and malformed item objective formats
  - Automatically retrieves item names from database when missing
  - Fixed specific quests: "Stromgarde Badges" (682) and "Hostile Takeover" (213)
  - Runtime fix handles 8000+ malformed entries without requiring database changes

- **Duplicate placeholder quest entries**
  - Removed 25 duplicate placeholder entries that were overwriting real quest data
  - Quest IDs cleaned: 26126, 26277, 26282, 26288, 26292, 26504, 26516, 26518, 26537, 26540, 26541, 26542, 26543, 26570, 26770, 26778, 26780, 26802, 26817, 26942, 27081, 27082, 27273, 28077, 28535
  - Each quest ID now has only one entry with actual data intact

## [1.0.65] - 2024-08-31

### Added
- **Version Check System**: Automatically checks if your Questie version is outdated
  - Notifies players on login if a newer version is available
  - Shows current version vs latest known version
  - Provides direct link to GitHub releases page
  - New slash commands: `/questieversion` or `/qversion` to manually check
  - Can detect newer versions from other players in guild/party/raid
  - Non-intrusive notification system with one-time display per session

### Fixed
- **Stormwind Innkeeper Not Showing on Map**: Fixed Innkeeper Allison not appearing when tracking innkeepers
  - Corrected npcFlags from 66179 to 135 (proper innkeeper flag) in epochNpcDB.lua
  - Fixed display ID from 1003 to 1002 to match Classic database
  - Innkeeper now properly shows on map when innkeeper tracking is enabled
- **Fixed overflow error for Epoch object IDs**
  - Changed object ID 40000057 to 4000057 in epochItemDB.lua to fit within 24-bit limit
  - Fixes issue #193 where QuestieStream.lua would crash with overflow error
  - Epoch object IDs starting with 4000000+ now work correctly
- **Fixed tracker only showing partial quests on login (all quests on reload)**
  - questsWatched was being captured at file load time instead of during initialization
  - Tracker sync was running before QuestiePlayer.currentQuestlog was populated
  - AutoUntrackedQuests cleanup was removing valid quests due to empty quest log
  - Removed erroneous trackerBaseFrame:Hide() that was hiding tracker after init
  - Now waits 1.5 seconds and checks if quest log is populated before cleanup
  - Fixes issue where quests couldn't be manually tracked after login
  - Fixes tracker disappearing completely after initialization
- **Removed debug output from database initialization**
  - Cleaned up temporary debug logging from QuestieInit.lua

### Added
- **Missing Quest Placeholders**: Added 55 placeholder quest entries from GitHub issues #198 and #209
  - Quest IDs: 26126, 26277, 26282, 26285, 26288, 26292, 26332, 26503-26506, 26516, 26518-26520, 26537, 26540-26543, 26570, 26577, 26580, 26582, 26594, 26802, 26817, 27074-27075, 27080-27084, 27114-27116, 27126-27131, 27136, 27141, 27151-27153, 27163-27164, 28072, 28077, 28483, 28535, 28648
  - Enables basic quest tracking functionality even without complete quest data
  - Placeholders can be filled in later when players submit complete quest data
- **New Epoch Quest Data**: Processed 6 GitHub issues adding 5 complete quests
  - Issue #213: Three Dun Morogh G.E.A.R. quests (28725, 28726, 28731)
    - Reassigned to IDs 28901, 28902, 28903 due to ID conflicts
    - "Shift into G.E.A.R." - Kill 10 Underfed Troggs
    - "No Room for Sympathy" - Kill 8 Irradiated Oozes and 4 Infected Gnomes
    - "Encrypted Memorandum" - Speak to Windle Fusespring
    - Updated NPC 46836 (Tinker Captain Whistlescrew) quest relationships
    - Added NPC 46882 (Windle Fusespring) as turn-in NPC
  - Issue #189: "The Perenolde Legacy" (26511) - Alterac Mountains
    - Quest giver: Elysa (2317)
    - Turn-in: Lord Jorach Ravenholdt (6768)
    - Level 38 quest reporting Aliden Perenolde's death
  - Issue #184: "Felicity's Deciphering" (26519) - Alterac Mountains
    - Replaced placeholder with complete quest data
    - Quest giver: Lord Jorach Ravenholdt (6768)
    - Turn-in: Felicity (45526)
    - Level 40 quest to decipher Ensorcelled Parchment
  - Issues #199, #201, #202: Duplicate submissions for quest 26505
    - Quest "Letter to Ravenholdt" already exists with complete data
    - Removed duplicate placeholder entry

### Fixed
- **Database Cleanup**: Removed duplicate quest 26505 placeholder
  - Quest already exists with complete implementation
  - Cleaned up conflicting duplicate entry

## [1.0.64] - 2024-08-30

### Fixed - Major Database Architecture Overhaul
- **CRITICAL FIX: Eliminated WotLK database contamination**
  - Changed database architecture to use Classic as the base instead of WotLK
  - Prevents ~13,000 phantom WotLK quests from appearing in Classic zones
  - Fixes incorrect NPC coordinates (like Stormwind innkeeper being in wrong location)
  - Selectively imports only essential WotLK data (Northrend content and service NPCs)
  - Resolves issues #165 and #175 where non-existent quests were showing

### Added - 45+ New Epoch Quests
- **Processed 12 GitHub issues with quest data submissions**
  - Issue #177: Azshara's Legacy (27094)
  - Issue #176: Rumbles Of The Earth (27049)
  - Issue #174: Batch of 7 quests (Dustwallow, Tanaris, Dun Morogh)
  - Issues #170-173: Complete Azshara's Legacy quest chain
  - Issue #167: Seeking Redemption (26455)
  - Issue #169: Hillsbrad/Alterac quest batch
  - Issues #163, #164, #166: 20+ additional quests across multiple zones
  - All quest data verified for accuracy with corrected zone IDs
  - **NOTE**: Many submissions had incorrect data that required manual fixes

### Changed
- **Data submission policy**: Now only accepting quest data from v1.0.63+ due to collection bugs in older versions

### Fixed
- **Map pins not displaying** - Fixed critical coordinate conversion issue in HereBeDragons
  - Added missing classic zone ID mappings for major cities (Stormwind, Ironforge, Orgrimmar, Thunder Bluff, Darnassus, Undercity)
  - NPCs using classic zone IDs (1519, 1537, 1637, 1638, 1657, 1497) now properly show on maps
  - Fixes issue where innkeepers and other NPCs in major cities weren't showing map pins

### Added
- **Data Collection Enhancement** - Export now includes addon version and timestamp
  - Helps identify if data was collected with buggy or fixed version
  - Shows exact date/time when data was collected or exported
  - Critical for debugging data collection issues
  - Removed emojis from export text as they don't work in plain text submissions
- **Massive Quest Data Import** - Added 100+ quests from user data submissions
  - Issue #162: "Parts From Afar" (26186) - The Hinterlands (final quest data submission!)
  - Issue #160: "Life In Death" (26712) - Duskwood
  - Issue #159: Updated Elwynn Forest quests with complete data (26768, 26771, 26774, 26775, 26794)
  - Issue #151: "Solarsal Report" (27053) - Wetlands
  - Issue #150/149: "Azshara's Legacy" (27091) - Azshara
  - Issue #148: Hillsbrad/Alterac quests (26499, 26540, 26541)
  - Issue #147: Elwynn Forest quests (26768, 26771, 26774, 26775, 26794)
  - Issue #146: "Commission for Verner Osgood" (28573) - Redridge Mountains
  - Issue #145: "Riders In The Night" (26707) - Duskwood
  - Issue #144: "How to Make Friends with a Furbolg" (27082) - Azshara
  - Issue #143: "Ardo's Dirtpaw" (26847) - Redridge Mountains
  - Issue #142: "A Salve for Samantha" (26883) - Stranglethorn Vale
  - Issue #141: "Parts From Afar" (26187) - Ironforge to Hinterlands
  - Issue #140: Silverpine Forest quests (26217, 26873, 26876)
  - Issue #139: "My Friend, The Skullsplitter" (26890) - Westfall/STV
  - Issue #138: Stranglethorn Vale batch (26282, 26291, 26292, 26880, 26885, 26903, 26906, 26907, 26908, 26912, 26915, 26922)
  - Issue #137: Elwynn Forest quests (26784, 26785)
  - Issue #136: "Brewing Brethren" (26782) - Elwynn Forest
  - Issue #135: "Linus Stone Tips" (26781) - Elwynn Forest
  - Issue #134: "How to Make Friends with a Furbolg" (27081) - Azshara variant
  - Issue #133: "My Friend, The Skullsplitter" (26887) - Stranglethorn Vale variant
  - Issue #131: "An End To Dread" (27237) - Swamp of Sorrows
  - Issue #130: "Crazed Carrion" (27243) - Swamp of Sorrows
  - Issue #129: "A Mage's Advice" (26780) - Elwynn Forest
  - Issue #128/120: "A Brother's Disgust" (26779) - Elwynn Forest
  - Issue #127: Multiple quests (26294, 27104, 27322, 27463) - Various zones
  - Issue #126: Teldrassil quests (26455, 26926, 26942, 27266, 27273, 27274, 27276, 27277, 28657)
  - Issue #124: "Demons In Fel Rock" (27483) - Teldrassil
  - Issue #123: "Dark Council" (26516) - Ashenvale
  - Issue #122: "Pilfering the Reef" (26891) - Stranglethorn Vale
  - Issue #121: Silverpine Forest quests (26218, 26872, 26874, 27167, 27195, 27198, 27200)
  - Issue #118: "Find the Brother" (26778) - Elwynn Forest
  - Issue #117: "Waterlogged Journal" (26570) - Duskwood
- **Second Wave Quest Data Import** - Added 75+ additional quests from issues #104-116, #132, #153, #155-156
  - Issue #104-105: Elwynn Forest quests including "Spider Elixir" (26774), "The Soaked Barrel" (26777), "Find the Brother" (26778)
  - Issue #106: "A Mage's Advice" (26780) and "Linus Stone Tips" (26781) - Elwynn Forest
  - Issue #107: "Barroom Blitz" (26689) and starter zone quests - Elwynn Forest
  - Issue #108: Feralas quests including "Bad News Has Horns" (27488) and "The Sacred Flame" chain (27500-27501)
  - Issue #109: "My Sister Isabetta" (27205) - Darkshore
  - Issue #111: Hillsbrad/Desolace quests (26544, 27238, 26542, 26802)
  - Issue #112: "A Temporary Victory" (27000) - Wetlands
  - Issue #113: "Trial of the Willing" (26310) and Barrens quests (27167, 27171)
  - Issue #114: "My Friend, The Skullsplitter" chain (26885, 26886) - Stranglethorn Vale
  - Issue #115: Felwood quests "Legion Paisa" (26148) and "Mementos of the Third War" (27309)
  - Issue #116: Multiple Barrens quests (27166, 27195-27197)
  - Issue #132: "Prismatic Scales" (26287) - Stranglethorn Vale
  - Issue #153: Call to Skirmish quests (26368, 26374, 26376) and "Fresh Water Delivery" (27492)
  - Issue #155: "Wreck of the Kestrel" (26218) and "Azshara's Legacy" (27092)
  - Issue #156: Multiple quests including "Materials of the Light" (26312) and Thousand Needles quests (27489, 27490)
  - Issue #157: "Life In Death" (26711) - Duskwood
  - Issue #158: Westfall quest chain "Homecoming" (26987), "A Stubborn Man" (26988), "Thumbs Up, Man Down" (26989)
  - Added 40+ NPCs with coordinates for quest givers and turn-ins

### Changed
- **Fixed GitHub repository link** (GitHub #161)
  - Updated link from esurm/Questie to trav346/Questie in Advanced settings
  - Fixed all localization strings to use correct repository
- **Reverted Wrath quest database change** 
  - Disabling wotlkQuestDB.lua caused map pins to disappear after database recompile
  - The file must be loaded for the compiler to work properly
  - Will investigate a better solution to reduce memory usage

### Fixed
- **CRITICAL FIX**: Fixed data collection bug causing all quest objectives to be mixed up (GitHub #151)
  - Fixed incorrect WoW 3.3.5 API usage where GetNumQuestLeaderBoards() and GetQuestLogLeaderBoard() were being passed parameters they don't accept
  - This was causing all tracked quests to receive the same objectives from whatever quest was last selected
  - Data collected before this fix may have incorrect objective assignments
- Fixed Lua errors when hovering over invalid quest rewards in the quest log (GitHub #154)
  - Added QuestRewardTooltipFix module to hook and validate SetQuestLogItem calls
  - Prevents crashes with invalid reward indices for Epoch quests with placeholder data
- Fixed incorrect coordinates for "Pillar of Diamond" object (GitHub #119)
  - Corrected coordinates from 83.7,32.9 to 83.9,39.4 for quest "Tremors of the Earth" (717)
- Fixed Fight Promoter NPCs incorrectly showing as innkeeper pins on world map (removed INNKEEPER flag)
- Added defensive checks for Epoch quests incorrectly showing as repeatable (GitHub #90)
  - Added validation to prevent non-repeatable Epoch quests from showing blue exclamation marks
  - Added debug logging to help identify quests with incorrect repeatable flags
  - This fixes an issue where abandoned and retaken quests could show incorrect repeatable icons
- Fixed missing Elwynn Forest starter quests (GitHub #103)
  - Restored "Swiftpaw" quest (26776) and "The Soaked Barrel" quest (26777)
  - These quests were accidentally overwritten by High Isle Fel Elf quests
  - Moved "Fel Elf Slayer" quest to ID 28768 to resolve the conflict
- Fixed overly restrictive level filtering preventing Epoch quests from showing on map (GitHub #103)
  - Increased level range for "Show only quests granting experience" from +4 to +6 levels
  - Made Epoch quests (26000+) use more lenient filtering (+10 levels) due to placeholder level data
  - This resolves issues where Epoch quests weren't visible even with low-level quest display enabled

## [1.0.62] - 2024-11-12

### Added
- **Wetlands and Duskwood Quests** (GitHub #93): Added 10 quests from user data submission
  - Quest 26570: "Waterlogged Journal" (Duskwood)
  - Quest 26723: "Wanted: Plagued Shambler" (Duskwood)
  - Quest 27006: "Eye of Zulumar" (Wetlands)
  - Quest 27009: "Evacuation Report" (Wetlands)
  - Quest 27016: "Drastic Measures" (Wetlands)
  - Quest 27020: "With Friends Like These..." (Wetlands)
  - Plus 3 placeholder quests (27408, 28475, 28476)
  - Added 4 NPCs: Sven Yorgen, Mayor Oakmaster, Scout Barleybrew, Corporal Mountainview

- **Troll Starting Zone Quests** (GitHub #96): Added proper quest names and data
  - Quest 28722: "The Darkspear Tribe" with NPC Joz'jarz (46834)
  - Quest 28723: "Thievin' Crabs" with Amethyst Crab spawns and coordinates
  - Fixed quest giver/turn-in NPCs with accurate coordinates from data collection
  - Added quest objectives for all troll quests

- **Blasted Lands Quests** (GitHub #97): Added 22 quests from user data submission
  - Added quests 26277, 26598-26602, 26614-26619, 26621, 26626, 26628-26632, 27076
  - Added Commission quests 27659 and 28647
  - Added 5 NPCs with coordinates: Nina Lightbrew, Quartermaster Lungertz, Watcher Mahar Ba, Eunna, Spirit of the Exorcist
  - Quest levels range from 50-54

- **Westfall Quests** (GitHub #94): Added 4 quests from user data submission
  - Three "The Killing Fields" quests (26994, 26995, 26996) - levels 10, 12, 14
  - "Commission for Protector Gariel" (28495) - level 5
  - Uses existing classic NPCs: Farmer Furlbrow, Farmer Saldean, Protector Gariel

- **Stranglethorn Vale & Barrens Quests** (GitHub #99): Added 15 quests from user data submission
  - Stranglethorn: Deeg's Lost Pipe (26285), Prismatic Scales (26287), Troll Relic (26290), The Janky Helmet (26904/26905), Commission for Captain Hecklebury Smotts (28073)
  - Barrens quest chain: Finding the Clues (27168) through Nadia's Task (27176) - 9 linked quests
  - Added 13 NPCs including Deeg, Venture Co. Tinkerer, Scooty, Captain Hecklebury Smotts, Mankrik, Shin'Zil, Nadia
  - Quest levels range from 14-43

- **Banana Bonanza Quest Complete Data**: Added full data from collection system
  - Quest 28757 now has quest giver Daz'tiro (46718) and turn-in NPC Azisary (47100)
  - Added Sun-Ripened Banana ground object (188800) with 5 spawn locations from data collection
  - Map pins will now show for quest givers, turn-in NPC, and banana spawn points

### Fixed
- **Quest 26723 Compilation Error**: Fixed incorrect table structure in epochQuestDB.lua
- **Quest 28764 Objectives Error**: Fixed "Second Tablet Read" tooltip error for event/script objectives
- **Export Window UI** (GitHub #89): Improved user experience with step-by-step process
  - Changed to 3-step process: Go to GitHub → Copy Data → Close & Purge
  - Made GitHub URL copyable with EditBox instead of FontString
  - Removed unnecessary "Select All" button as text is pre-selected
- **Troll Quest Names** (GitHub #96): Fixed incorrect quest names
  - Corrected mismatched quest names that were wrongly assigned
  - Removed made-up quest names, using real data from submissions
- **Tracker Nil Description Error**: Fixed tracker crash for quests without Description field
  - Added nil check before accessing quest.Description[1]
  - Provides fallback text for Epoch quests lacking descriptions
- **Data Collection for Epoch Quests**: Fixed Amethyst Crab and other mob data not being collected
  - Now ALL Epoch quests (26000+) are tracked for continuous data improvement
  - Previously only missing or incomplete quests were tracked
- **Quest Completion Notifications**: Simplified formatting
  - Removed double line separators for cleaner appearance
  - Changed hyperlink to simple "Click here to submit quest data"
  - Changed message to "Epoch quest completed!" for clarity
- **Cannot Untrack Epoch Quests** (GitHub #98): Removed all restrictions preventing quest untracking
  - Users can now untrack any quest including Epoch quests
  - Fixed UntrackQuestId, manual toggle, and Shift+Click untracking
  - Data collection happens independently of tracker visibility
- **GetQuestResetTime() Error**: Fixed error spam when API returns -1
  - Added graceful fallback to 24-hour reset when daily quest API unavailable
  - Common on Project Epoch where daily quests may not be implemented
  - No longer shows error message, uses default timing instead
- **Data Collection Debug Messages**: Removed chat spam during objective tracking
  - Disabled "Action: Item collection" and location coordinate messages
  - Progress tracking still works but now operates silently
- **QuestieDB.QueryQuest Nil Error**: Fixed crash when accepting quests before database initialization
  - Added safety checks for uninitialized database functions
  - Gracefully handles early quest acceptance during loading
- **Data Collection After Logout/Login**: Fixed tracking not resuming after relogging
  - Epoch quests now stay tracked even if database isn't ready
  - Events properly re-register after login
  - Objectives populate correctly for quests in progress
- **Developer Options Not Saving** (GitHub #102): Fixed developer options turning back on after restart
  - Tooltip IDs no longer forced on when data collection is disabled
  - Settings now properly persist between sessions

## [1.0.61] - 2025-08-30

### Added
- **Export Button in Minimap Menu**: Added quick access to data export window from Questie minimap dropdown (GitHub #89)
  - Left-click Questie minimap icon shows new "Export Quest Data" option
  - Only appears when data collection is enabled
  - Makes submitting quest data much easier for contributors

- **Missing Troll Starting Zone Quests**: Added 18 troll quests that were mentioned in previous changelog but never actually added
  - Quests 28750-28767 including "The Darkspear Tribe", "Banana Bonanza", etc.
  - All quests now have proper NPC and objective data
  - Fixed issue where quest 28759 wasn't showing on map despite being in quest log

- **Additional Epoch Quests**: Added quests from GitHub issue #91
  - Quest 26282: "The Emerald Dragon..." with NPC Deeg (2488)
  - Quest 26283: "Sasha's Hunt" with NPC Deeg (2488)
  - Quest 26284: "Justice for the Hyals" with NPC Crank Fizzlebub (2498)
  - Quest 26285: "Justice for the Hyals" (turn-in) with NPC Historian Karnik (2916)
  - Quest 26286: "Into the Scarlet Monastery" with NPC Historian Karnik (2916)

### Changed
- **Simplified Data Collection Messages**: Replaced verbose multi-line messages with single notification
  - Changed from 3-line spam with GitHub URL to simple: "Quest not in database. This quest is now being tracked by Data Collector!"
  - Makes data collection less intrusive while still informative
  - Debug messages now properly respect showDataCollectionMessages setting

### Fixed
- **IsComplete Nil Errors**: Fixed multiple crashes when accepting quests
  - Added defensive checks in QuestieMap before calling quest:IsComplete()
  - Runtime stub quests now handled gracefully without crashes
  - Fixed error occurring when accepting troll quest 28760

- **Debug Message Spam**: Fixed debug messages bypassing the showDataCollectionMessages setting
  - All [DEBUG] and [DataCollector Debug] messages now properly controlled by settings
  - Fixed 4 direct chat prints that were ignoring the toggle
  - Debug system now properly centralized through DebugMessage function

## [1.0.60-hotfix2] - 2025-08-30

### Fixed
- **Quest 26768 Data Error**: Fixed "bad argument to rshift" compilation error
  - Corrected object objectives structure from `{nil,{{{objects}}}}` to `{nil,{{objects}}}`
  - Removed extra nesting level that was causing compilation failure
  - Quest "Barrel Down" now loads properly

## [1.0.60-hotfix] - 2025-08-30

### Fixed
- **Load Order Error**: Fixed epochQuestDB.lua causing "attempt to index global QuestieDB (a nil value)" error
  - Added missing QuestieDB import at top of file
  - Other Epoch database files already had proper imports

### Added  
- **Data Collection Message Toggle**: Added setting to control [DATA] message visibility
  - New setting in Advanced tab: "Show Collection Messages" (off by default)
  - `/qdc messages` command to quickly toggle messages on/off
  - Allows silent data collection without chat spam
  - Collection still works even with messages disabled

## [1.0.60] - 2025-08-30

### Fixed

#### Critical Error Fixes
- **AvailableQuests Error**: Fixed "attempt to index local 'npc' (a nil value)" error when quest starters are single IDs instead of tables (Fixes #43, #46, #52)
  - Now properly handles quests with single NPC or GameObject starters
  - Converts single IDs to tables before processing
  - Quest markers now gracefully handle incomplete quest data
- **QuestieTracker Error**: Fixed "IsComplete() nil value" error when tracking malformed quests
  - Added defensive check for quest objects missing the IsComplete method
  - Prevents tracker crash when encountering incomplete quest data
  - Fixed tracker showing completed quests after accepting new ones
  - Fixed tracker not refreshing properly when completing and accepting quests
  - Completed quests are now properly cleaned from QuestiePlayer.currentQuestlog
- **QuestieShutUp Filter**: Fixed chat filter not blocking Questie messages from party members (Fixes #55)
  - Corrected pattern mismatch between filter and actual message format
  - Filter now properly matches locale-specific message formats
- **World Map Tooltips**: Fixed tooltips not showing on vanilla fullscreen world map (merged PR #25 from @virtiz)
  - Tooltips now properly check full parent chain to detect WorldMapFrame ancestry
  - Added SetClampedToScreen to keep tooltips visible at screen edges
- **Object Data Errors**: Fixed "Missing objective data" errors showing table references instead of meaningful descriptions
  - Now silently skips missing data or logs at debug level only
  - Prevents spam for missing object ID 6445625 and similar
- **Critical Map Pin Fix**: Imported WotLK database to fix all service NPC detection
  - Project Epoch was using Classic-era NPC flags (INNKEEPER=128) but needed WotLK flags (INNKEEPER=65536)
  - Fixed version detection to properly identify 3.3.5 client and use correct flag values
  - All service NPCs (innkeepers, bankers, auctioneers, trainers, etc.) now show correctly on maps
- **Stormwind Service NPCs**: Fixed bankers, auctioneers, and weapon master not showing on map
  - Updated 3 bankers (Olivia, Newton, John Burnside) with correct coordinates and flags from WotLK database
  - Updated 3 auctioneers (Chilton, Fitch, Jaxon) with correct coordinates and flags from WotLK database
  - Fixed Woo Ping (weapon master) location from wrong coordinates (57.13,57.71) to correct position (63.88,69.09)
  - All NPCs now use proper service flags (131073 for bankers, 2097152 for auctioneers, 81 for weapon master)
- **Stormwind NPCs**: Restored Innkeeper Allison and Dungar Longdrink (flight master) on map tracker
  - Removed placeholder entries in epochNpcDB.lua that were overriding Classic database
  - NPCs now show with proper names and service flags when tracked
- **Children's Week**: Permanently removed seasonal quest from showing year-round
  - Removed quest 1468 from event system overrides
  - Blacklisted NPCs 14305 (Human Orphan) and 14450 (Orphan Matron Nightingale)
  - Quest will no longer appear even during May 1-7 event dates
- **Quest Database**: Fixed duplicate and incorrect quest entries (Fixes #78, #79, #80, #81)
  - Consolidated duplicate quest entries for quests 26285, 26286, 26287, 26288, 26289, 26292, 26907
  - Removed conflicting epochQuestData stub entries that were overwriting complete quest data
  - Updated quest 26285 "Deeg's Lost Pipe" with proper quest giver and objective data
  - Added missing quest entries 26286-26292 to main database array with proper data structure
  - Added missing NPC 2488 (Deeg) to support "Deeg's Lost Pipe" quest
  - Removed duplicate entry for quest 26987 "Homecoming" with wrong quest giver (NPC 491)
  - Removed incorrect entry for quest 26987 with wrong title "Moving Up"
  - Fixed Innkeeper Allison coordinates in Stormwind (was 60.39,75.28, now 52.62,65.7)
  - Fixed quest 26993 "The Killing Fields" with proper objectives and mob targets (Riverpaw Gnolls and Scouts)
  - Cleaned up quest data integrity in epochQuestDB.lua
#### Data Collection Overhaul
- **Container Names Fixed**: Major fixes to ground object/container tracking (Fixes #32)
  - Fixed container names being lost when they match item names (e.g., "Sun-Ripened Banana") 
  - Fixed container names being overwritten with placeholders like "Unidentified Container"
  - Container names now properly captured from GameTooltip during mouseover
  - Container names preserved even when loot window doesn't show the name
  - Export now includes proper container data for ground object quests
  - Added automatic rescan 1 second after initialization (no more manual `/qdc rescan` needed)
- **Runtime Stub Detection**: Fixed missing quest detection for runtime stubbed quests (Fixes #21)
  - Now properly detects quests created as runtime stubs (e.g., new troll starting zone quests)
  - Removed upper limit on Epoch quest IDs (now tracks all quests 26000+)
  - Fixed detection of [Epoch] prefix in questData.name for placeholder quests
  - Now correctly identifies and tracks quest 28722 "The Darkspear Tribe" and similar new quests
- **Chat Spam Removed**: Fixed [DATA] messages being shown to all users (Fixes #27)
  - All [DATA] tracking messages now only show when debug mode is enabled
  - Removed all alert messages when accepting quests - silently tracks data
  - Important completion notices still show when needed
  - Added helper function to properly handle debug-only messages
- **Export Improvements**: All quest data can now be exported, even incomplete quests
  - Partial data is valuable - shows quest givers, objectives, NPCs even without turn-in
  - Export window now shows [COMPLETE] or [INCOMPLETE] status for each quest
  - Export format clearly indicates if quest data is incomplete
- **Quest Progress Detection**: Enhanced automatic tracking
  - Now detects quest progress from system messages (e.g., "Sun-Ripened Banana: 7/10")
  - Automatically captures container/object data when quest progress is detected
  - Links ground objects to quest objectives for proper map icon placement

#### Map and Tracking Improvements  
- **Map Error Handling**: Fixed error for unknown zones like custom Project Epoch areas
  - Changed hard error to warning for unmapped zones (e.g., areaId 178 "Deeg")
  - Allows addon to continue functioning with custom server zones
- **Map Scaling**: Simplified world map dimension calculations (Fixes #39)
  - Removed unnecessary conditional scaling logic that was never triggered
  - WorldMapButton width consistently returns 1002 in both fullscreen and windowed modes
  - Map icons should now position correctly regardless of map mode
- **Party Tooltips**: Fixed party member quest progress not showing in tooltips
  - Properly access remoteQuestLogs structure for fallback mechanism
  - Shows party progress even when no per-mob tooltip cache exists
- **TomTom Integration**: Fixed TomTom auto-waypoint permanently changing tracker sort
  - TomTom now finds closest quest independently without modifying tracker sort preference
  - User's chosen sort order (proximity, level, etc.) is no longer overridden
- **Quest Item Tracking**: Fixed tracker hiding quests when looting quest items
  - Preserves quest tracking state when items are looted from ground objects
  - Prevents quests from being inadvertently untracked during objective updates
- **Quest Level Filtering**: Fixed quest level filtering and improved usability (Fixes #41)
  - Quests with "[Epoch] Quest XXXXX" placeholder names are now hidden from the map
  - Epoch quests with missing/zero requiredLevel now properly respect level filters
  - Changed "Show only quests granting experience" to hide red quests (5+ levels above player)
  - Now shows green, yellow, and orange quests but hides red quests that clutter the map

### Added
- **Quest Items**: Added 10+ quest items with proper drop sources
  - Raw Springsocket Eel, Pinch of Bone Marrow, Vial of Vulture Blood, Kratok's Horn, Slaver's Records
  - Commission items for various quests
- **WotLK Database**: Imported complete WotLK database files for proper 3.3.5 support
  - Added wotlkQuestDB.lua, wotlkNpcDB.lua, wotlkObjectDB.lua, wotlkItemDB.lua
  - Fixes all service NPC flag detection issues
  - Provides correct NPC data for WotLK expansion content
- **Quest Data**: Added 90+ new Epoch quests from GitHub issues (#71-87)
  - The Hinterlands: 5 Alliance quests including "A Sticky Situation", "Can't Make An Omelette Without...", "Falling Up To Grace", "Parts From Afar", "Stalking the Stalkers"
  - Westfall: 5 Alliance quests including "Hand of Azora" chain, "Homecoming", "The Killing Fields"
  - Silverpine Forest: 2 Horde quests "Lost in the Lake", "Wreck of the Kestrel"
  - Ashenvale: Added quest 27880 "Fight for Warsong Gulch" (level 14 battleground introduction quest)
  - Westfall: Added quest 28495 "Commission for Protector Gariel" (level 5 collection quest)
  - Various zones: 8 Call to Skirmish quests for Thousand Needles, Alterac Mountains, Desolace, Arathi Highlands and other content
  - Hillsbrad Foothills: "Who Likes Apples?", "Fresh Water Delivery", "The Ghost of the Flats", "Threats from Abroad", "To The Hills"
  - Badlands: "Springsocket Eels", "An Old Debt", multiple commission quests
  - Tanaris: "Call to Skirmish" PvP quests
  - Winterspring/EPL: High-level Horde quests including "Nightmare Seeds", "Hero Worship"
  - Desolace: "The Argus Wake" 5-quest chain (42-44)
  - Searing Gorge: Thorium Brotherhood quests
  - Elwynn Forest: "Barroom Blitz" series, commission quests
  - Updated existing quests with complete data: "Arugal Ambush", "The Killing Fields"
- **NPCs**: Added 35+ new NPCs with proper locations
  - The Hinterlands: Truk Wildbeard, Kerr Ironsight, Tizzie Sparkcraft, Chief Engineer Urul, Gryphon Master Stonemace, Gryphon Master Talonaxe
  - Westfall: Karlain, Revil Kost, Quartermaster Lewis
  - Silverpine Forest: Ainslie Yance, Edwin Harly, Dalar Dawnweaver, Kor
  - Ashenvale: Added NPC 44806 "Warsong Gulch Battlemaster" for battleground quest access
  - Hillsbrad/Thousand Needles: Jason Lemieux, Pozzik, Deeg, Commander Strongborn
  - Badlands: Zeemo, Dirk Windrattle, Joakim Sparkroot
  - Searing Gorge: Merida Stoutforge, Bhurind Stoutforge, Grampy Stoutforge, Lookout Captain Lolo Longstriker
  - Desolace: Felicity Perenolde, Zala'thria, Kratok
  - Eastern Plaguelands: Engineer Flikswitch, Harbinger Balthazad
  - Elwynn Forest: Jason Mathers
- **Objects**: Added ground objects for quest item collection
  - Sack of Oats in Westfall (3 spawn points)
  - Fishing Bobber in Stormwind City

### Changed
- **epochStormwindFixes.lua**: Disabled due to causing issues with seasonal NPCs and incorrect positions
  - Was adding 546 NPC entries, many with wrong coordinates or inappropriate seasonal content
  - Service NPCs now properly handled by WotLK database

### Removed
- **POI Markers**: Fixed service NPCs not appearing on Stormwind map (Fixes #42)
  - Added proper npcFlags to flight master, innkeeper, auctioneers, bankers, trainers, and repair vendors
  - Updated epochStormwindFixes.lua with service flags for 30+ NPCs
- **Mailbox Locations**: Fixed misplaced mailboxes throughout Stormwind (Fixes #42)
  - Updated 10 mailbox coordinates based on actual WotLK positions
  - Added mailboxes in Trade District, Cathedral Square, Park District, Mage Quarter, Old Town, and Dwarven District

## [1.0.53] - 2025-08-28

Note: Versions 1.0.54-59 were internal development versions. All changes from those versions are included in v1.0.60 above.

## [1.0.4] - 2025-08-27

### Fixed
- **Party tracking tooltips**: Added fallback mechanism to show party member quest progress when no per-mob tooltip cache exists
- **DataCollector errors**: Fixed questID being passed as table instead of number in multiple locations
  - Added defensive checks in CheckExistingQuests, OnQuestAccepted, and GetQuestIdFromLogIndex
  - Fixed GetQuestsByZoneId iterating over QuestPointers with table keys
  - Added pcall wrapper to gracefully handle errors
  - Note: Requires complete WoW restart to load the fixes (not just /reload)

## [1.0.3] - 2025-08-27

### Fixed
- **Major tracker fix**: Fixed QuestLogCache not populating on initial load causing only 1 quest to show
- Fixed tracker not showing despite having tracked quests
- Fixed tracker UI element not being visible even when functioning correctly
- Fixed manual quest tracking toggle functionality
- Fixed QuestieDB.GetQuest being called with tables instead of quest IDs
- Fixed TrackerUtils handling of non-table quest entries
- Fixed QuestieDataCollector passing invalid questIDs to GetQuest
- Fixed data purge button not actually clearing saved quest data
- Fixed quest 26936 "Northshore Mine" incorrect turn-in NPC (now correctly shows Jasper Greene)

### Added
- Mouse wheel scrolling support for quest tracker
- Debug commands: `/run QuestieTracker:CheckStatus()` and `/run QuestieTracker:ForceScanQuests()`
- Force show tracker command: `/run QuestieTracker:ForceShow()`
- Added 6 Epoch quests with proper data (26926, 26932, 26934, 26936, 26940, 26942)
- Added NPCs: Fergus Kitsapell (45899), Gernal Burch (45902)
- Added items: Case of Ore (62803), Joseph's Journal (62811)

### Changed
- Improved runtime stub creation for Epoch quests
- Enhanced error handling in database queries
- Updated tracker initialization to force update after load

## [1.0.2] - 2025-08-27

### Fixed
- Fixed tracker nil reference bugs with AutoUntrackedQuests
- Added nil checks to prevent "0/0 quests" display issue
- Fixed manual quest tracking not working
- Added safety checks for frame creation failures

### Added
- Map zoom fix module (experimental)

## [1.0.1] - 2025-08-27

### Fixed
- Repository references updated to point to Questie-Epoch
- Version numbering corrected

## [1.0.0] - 2025-08-27

### Initial Release
- Fork of esurm/Questie optimized for Project Epoch
- 600+ Epoch quests in database (IDs 26000-26999)
- Developer mode for community quest data collection
- Real-time capture of NPCs, items, and objective locations
- Batch export functionality for all captured quest data
- Data purge feature after submission
- Read-only export window
- GitHub submission instructions

### Known Issues
- Map zoom causes marker displacement (3.3.5a limitation)
- Many Epoch quests still need validation through gameplay