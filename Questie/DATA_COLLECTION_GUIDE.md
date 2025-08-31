# Questie Data Collection - Simple Guide

## Don't Want to Help? No Problem!
Just use Questie normally! The addon works great for tracking quests, finding NPCs, and showing objectives on your map. You don't need to do anything special.

## Want to Help Make Questie Better? Here's How!

### What Is Data Collection?
Project Epoch has 600+ custom quests that Questie doesn't know about yet. When you play with data collection ON, Questie learns about these quests and you can share that info to help everyone.

### Quick Start (3 Easy Steps)

#### 1. Turn It On
Type in chat: `/qdc enable`

You'll see: **"[Questie] Data collection ENABLED"**

#### 2. Play Normally
Just quest like you always do! Questie quietly records:
- Where quest givers are standing
- What mobs you need to kill
- Where quest items drop
- Where to turn in quests

You'll see green messages like:
- **"[DATA] Quest Giver: Guard Thomas"** - Found a quest giver!
- **"[DATA] Quest item dropped from Wolf"** - Learned where items come from!

#### 3. Share Your Data (When Done with a Quest)
Type: `/qdc export 12345` (replace 12345 with the quest ID)

This opens a window with the quest data. Click "Copy" and paste it on GitHub.

---

## What to Expect While Collecting

### Good Messages (Green = Working!)
- **"Quest Giver: [Name]"** - Captured who gives the quest
- **"Quest Turn-in: [Name]"** - Captured who you turn it in to
- **"Tracked quest mob"** - Found an enemy for the quest
- **"Quest item dropped"** - Learned where items come from

### Normal Messages (Brown = Info)
- **"Tracked mob at [location]"** - Recording enemy positions
- **"Interacted with object"** - Found a clickable quest object

### Warning Messages (Red = Incomplete)
If you see **"WARNING: INCOMPLETE DATA"** it means you already had the quest when you turned collection on. To fix: abandon the quest and pick it up again.

---

## Common Commands

- `/qdc status` - Check if it's on or off
- `/qdc show` - See all quests you've collected
- `/qdc export 12345` - Get data for quest 12345
- `/qdc clear` - Delete all collected data (careful!)
- `/qdc disable` - Turn off collection

---

## Submitting to GitHub (Easy!)

1. **Finish the quest completely** (accept → do objectives → turn in)
2. **Export it**: `/qdc export [questID]`
3. **Copy the text** from the window that pops up
4. **Go to**: https://github.com/trav346/Questie/issues/new
5. **Title**: "Quest Data: [Quest Name]"
6. **Paste** your data and click "Submit new issue"

That's it! You've helped make Questie better for everyone!

---

## Tips for Best Results

### DO:
- ✅ Accept quests with collection ON (so we know who gives them)
- ✅ Target or mouseover enemies (records their locations)  
- ✅ Loot everything (links items to mobs)
- ✅ Complete the whole quest before exporting

### DON'T WORRY ABOUT:
- ❌ Perfect data - some info is better than none!
- ❌ Duplicates - we can handle those
- ❌ Small quests - every quest helps
- ❌ Making mistakes - it's all helpful

---

## FAQ

**Q: Does this slow down my game?**
A: Nope! It's super lightweight.

**Q: Can I turn it off mid-quest?**
A: Yes! Type `/qdc disable` anytime.

**Q: What if I mess up?**
A: No worries! Any data helps. We can fix things later.

**Q: Do I need to collect every quest?**
A: No! Even one quest helps. Do what you enjoy.

**Q: What if the quest is already in Questie?**
A: If it shows "[Epoch]" in the name, we need data for it!

---

## You're Awesome!
Every quest you submit helps thousands of players. Thank you for making Project Epoch better! 🎮