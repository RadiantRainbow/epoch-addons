# CRITICAL DATABASE MERGE PLAN - REVIEW BEFORE EXECUTING

## Current Situation (BROKEN)
- **epochQuestDB.lua**: 1,287 quests (139 vanilla, 1,136 custom Epoch)
- **wotlkQuestDB.lua**: 9,085 vanilla quests
- **PROBLEM**: Epoch database blocking vanilla quests like 445
- **PUBLIC RELEASE**: v1.2.0 is live with this bug

## The Safe Fix Plan

### Step 1: Create Complete Backups
```bash
cp epochQuestDB.lua epochQuestDB_BACKUP_BEFORE_MERGE.lua
cp epochNpcDB.lua epochNpcDB_BACKUP_BEFORE_MERGE.lua
cp ../../Database/Wotlk/wotlkQuestDB.lua wotlkQuestDB_BACKUP_BEFORE_MERGE.lua
cp ../../Database/Wotlk/wotlkNpcDB.lua wotlkNpcDB_BACKUP_BEFORE_MERGE.lua
```

### Step 2: Extract ONLY Custom Epoch Quests (ID 25000+)
```python
# Extract quests 25000+ from epochQuestDB
# These are the ONLY quests we want to keep
# DO NOT touch any quest with ID < 25000
```

### Step 3: Append Custom Quests to WotLK Database
```python
# Add the 1,136 custom Epoch quests to END of wotlkQuestDB.lua
# Do NOT overwrite anything
# Just append
```

### Step 4: Disable Epoch Database
```lua
-- In epochQuestDB.lua, comment out the entire file
-- Or rename to epochQuestDB.lua.disabled
```

### Step 5: Test Critical Quests
- [ ] Quest 445 appears (was missing)
- [ ] Quest 605 (Singing Blue Shards) still correct
- [ ] Quest 26901 (Shark Fin Stew) still works
- [ ] Custom Epoch quest (like 26000+) still works

## What This Fixes
1. ✅ All missing vanilla quests restored (like 445)
2. ✅ Custom Epoch content preserved
3. ✅ No data loss
4. ✅ Proper database hierarchy

## Risks & Mitigation
- **Risk**: Breaking working quests
  - **Mitigation**: Only moving 25000+ IDs, not touching vanilla
- **Risk**: Lua syntax errors
  - **Mitigation**: Validate syntax before release
- **Risk**: Lost custom quest data
  - **Mitigation**: Complete backups first

## Emergency Rollback
If ANYTHING goes wrong:
```bash
cp epochQuestDB_BACKUP_BEFORE_MERGE.lua epochQuestDB.lua
cp wotlkQuestDB_BACKUP_BEFORE_MERGE.lua ../../Database/Wotlk/wotlkQuestDB.lua
```

## DO NOT PROCEED WITHOUT:
1. [ ] Full backups created
2. [ ] Understanding this plan
3. [ ] Testing environment ready
4. [ ] Prepared for emergency rollback

---
**Current public has a broken v1.2.0** - This needs a v1.2.1 hotfix ASAP