### THIS REPO WILL BE ON HIATUS UNTIL WE FIND OUT IF THE SERVER WILL PERSIST.

### ☕ Support Development
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support%20Development-orange?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/trav346)

If you find this version of Questie with data collection helpful, consider [buying me a coffee](https://buymeacoffee.com/trav346) to support continued development!

---

# Questie for Project Epoch v1.2.2

**An actively maintained version of Questie for Project Epoch with enhanced data collection capabilities.**

## 🎯 Major Database Expansion
**1,346 Epoch Quests!**
- The Epoch quest database has grown to 1,346 custom epoch quests!
- Processed well over a thousand community submissions from GitHub. Thank you to everyone who has and is continuing to submit!
- **Top Contributors:**
  1. BluePiru - 68 submissions 🥇
  2. Lightshard86 - 63 submissions 🥈
  3. fleekx - 43 submissions 🥉
  4. MikeDelta95 - 41 submissions
  5. mijagaming08-png - 40 submissions

## ⚠️ Important: Ongoing Database Maintenance
**This is a living project with continuous improvements!**
- **Database maintenance is ongoing** - We're constantly updating and improving quest data
- **Bugs may still exist** - Some quests may display incorrectly or have missing information
- **Your reports matter** - Please submit bug reports via [GitHub Issues](https://github.com/trav346/Questie-Epoch/releases/latest)
- **Be patient** - Project Epoch has modified thousands of vanilla quests, and we're working through them systematically
- **Help us imporove!** - Enable data collection (`/qdc enable`) to automatically contribute to database improvements

## 🗺️ New Features

### Level-Appropriate Quest Filtering
- **Fixed bug** Map now only shows quests you can realistically obtain and complete
- **FIxed Bug** Most erroneous quests should no longer appear in wrong locations or for inappropriate levels
- **Fixed Bug** Cleaner map with only relevant quests for your level

### Smart Quest Data Export
- **Automatic Pagination**: Large submissions automatically split into multiple pages
- **Character Counter**: Shows real-time usage (e.g., "45.2k/59.0k chars")
- **Smart Slicing**: Respects GitHub's 65,536 character limit
- **Unified Interface**: All exports use the same modern staged window

### Quest Completeness Indicators (What Those [Brackets] Mean)
**You might see these labels in front of quest names in your tracker. Here's what they mean:**

- **[EpochDB Missing]**: This quest doesn't exist in our database yet. Questie is doing its best to track it for you, but we don't have information about where to go or what to do. The quest will still work in-game, but Questie can't show you map markers or objectives.

- **[EpochDB Minimal]**: We know this quest exists and its name, but that's about it. We don't know where the quest giver is or what you need to do. You can still complete the quest normally, but Questie can't guide you.

- **[EpochDB Partial]**: We have some information about this quest (like who gives it or some objectives), but we're missing important details. You might see some map markers, but they could be incomplete or incorrect.

**Why do these exist?** Project Epoch has thousands of custom quests that aren't in the original WoW database. When you pick up a quest we don't know about, Questie creates a temporary placeholder (called a "runtime stub") so it can at least track your progress. As players submit data, these quests get upgraded from Missing → Minimal → Partial → Complete.

## 📦 Installation

### **Automatic Installation (Recommended)**
1. **Download**: Get the latest release from [GitHub Releases](https://github.com/trav346/Questie-Epoch/releases)
2. **Extract**: Unzip the downloaded file
3. **Install**: Copy the `Questie` folder to your WoW AddOns directory:
   ```
   /Interface/AddOns/Questie
   ```

## 🚀 Getting Started

### **Basic Usage**
**Enable Data Collection**: Type `/qdc enable` to help improve quest database, or don't. No sweat!
3. **Accept Quests**: Quest objectives will automatically appear on map and minimap
4. **Track Progress**: Watch your progress update in real-time as you complete objectives
5. **Turn In**: Quest completion markers guide you to turn-in NPCs

### **Essential Commands**
```
/questie                    - Open main settings
/questie refreshcomplete    - Refresh completed quests from server
/qdc enable                 - Enable data collection 
/qdc export                 - Export data for GitHub submission
```

## 🔧 Data Collection System

**Help improve Questie for everyone by enabling data collection!**

### **What It Does**
- **Automatic Detection**: Identifies quests missing from the database
- **Real-time Tracking**: Records quest objectives, NPCs, and locations as you play
- **Progress Logging**: Captures where objectives are completed with detailed information
- **No Performance Impact**: Lightweight system that doesn't affect gameplay

### **How to Contribute**
1. **Play Normally**: Accept and complete quests as usual
2. **Export Data**: Use `/qdc export` when quest is complete
3. **Submit to GitHub**: Create issue at [GitHub Issues](https://github.com/trav346/Questie-Epoch/issues)
4. **Help the Community**: Your data helps everyone get better quest information

### **Known Compatibility**
- ✅ For map zooming you'll want to get https://warperia.com/addon-wotlk/magnify/
- ✅ For waypoint arrow support you'll want to get https://warperia.com/addon-wotlk/tomtom/
- ⚠️ If you use Leatrix Plus you may encounter frame drops. This is still being researched, but you can try to disable minimap buttons as a workaround.

## 🐛 Known Issues & Troubleshooting

### **Common Issues**
- **Quest Markers Missing**: Some Project Epoch quests have incomplete data - enable data collection to help fix this
- **Quests show up that don't exist**: Project Epoch has modified lots of vanilla quests that exist in Questie's Vanilla database. This is an ongoing process of cleanup. Please bear with me through updates
- **Incorrect quest information**: Database validation is ongoing - please report specific issues via GitHub
- **NPCs in wrong locations**: Some NPCs may show outdated positions - your reports help us fix these

### **Getting Help**
1. **Check Issues**: Browse [GitHub Issues](https://github.com/trav346/Questie/issues) for known problems
2. **Enable Debug**: Use `/console scriptErrors 1` to see detailed error information  
3. **Report Bugs**: Create detailed issue reports with steps to reproduce
4. **Discord Support**: Join Project Epoch Discord for community help


## 🙏 Credits & Support

### **Special Thanks**
- **@esurm**
- **@desizt**
- **@Bennylavaa**
- **Top Quest Contributors**: BluePiru, Lightshard86, fleekx, MikeDelta95, mijagaming08-png
- **All GitHub Contributors**: Every quest submission helped build our database

### **Support Development**
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support%20Development-orange?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/trav346)


If you find this enhanced version of Questie helpful, consider [buying me a coffee](https://buymeacoffee.com/trav346) to support continued development and maintenance!


