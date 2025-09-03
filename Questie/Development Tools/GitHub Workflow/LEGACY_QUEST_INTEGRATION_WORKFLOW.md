# Legacy Quest Data Integration Workflow

**Successfully completed: September 2, 2025**

This document outlines the complete workflow for processing GitHub quest submissions and integrating them into the Questie database. This process was successfully used to integrate 173 new quests from 875 community submissions.

## Overview

The workflow consists of 5 main stages:
1. **GitHub Issue Download** - Download all quest submissions from GitHub
2. **Legacy Data Processing** - Extract and validate quest data from submissions
3. **Data Parsing & Validation** - Parse Lua data and validate structure
4. **Database Backup & Merge** - Safely integrate validated data
5. **Compilation Testing** - Verify syntax and database integrity

## Stage 1: GitHub Issue Download

**Script**: `github_issue_downloader.py`

```bash
python github_issue_downloader.py
```

**What it does:**
- Downloads all GitHub issues from repository
- Filters for quest submission issues (by title patterns)
- Saves issue content to individual files
- Closes processed quest submission issues while preserving bug reports

**Success metrics:**
- Downloaded 875 quest submissions  
- Closed 397 quest issues, kept 31 bug/feature reports

## Stage 2: Legacy Data Processing

**Script**: `legacy_processor.py`

```bash
python legacy_processor.py
```

**Purpose**: Extract quest data from legacy v1.0.68 submissions with relaxed validation

**Key features:**
- Separate validation flow for legacy submissions (40+ score vs 70+ for modern)
- Extracts quest metadata, database entries, and validation scores
- Handles different submission formats from older versions
- Generates `validated_legacy_data/` directory with processed submissions

**Success metrics:**
- Processed 295/298 legacy submissions (99% success rate)
- Generated 213 unique quest files for parsing

## Stage 3: Data Parsing & Validation

**Script**: `legacy_data_parser.py`

```bash
python legacy_data_parser.py
```

**Critical parsing fixes applied:**
- Fixed DATABASE ENTRIES regex: `r'DATABASE ENTRIES:\s*(.*?)$'` → `r'DATABASE ENTRIES:\s*(.*)'`
- Enhanced quest data quality validation
- Zone ID corrections (85 → 1519 for Stormwind)
- Semantic validation of quest names, levels, NPCs

**Success metrics:**
- Extracted 465 unique quests from 851 valid entries (97% validation success)
- Generated `validated_quest_updates_20250902_215843.lua` with all validated data

## Stage 4: Database Backup & Merge

**Backup creation:**
```bash
python create_backup.py
```

**Merge script**: `merge_legacy_data.py`

```bash  
python merge_legacy_data.py
```

**Intelligent merge logic:**
- Only adds NEW quests not in database
- Only updates existing quests if legacy data is clearly better
- Preserves existing good data, doesn't downgrade quality
- Creates comprehensive merge log with detailed statistics

**Success metrics:**
- Created backup at `Database/Epoch/Backups/pre_legacy_merge_20250902_215954`
- Added 173 new quests + updated 4 existing quests
- Database grew from 584 to 757 quests total

## Stage 5: Compilation Testing & Syntax Fixes

**Syntax validation:**
```bash
cd "/Users/travisheryford/Library/CloudStorage/Dropbox/WoW Interfaces/epoch/AddOns/Questie/Database/Epoch"
luac -p epochQuestDB.lua
```

**Critical fixes applied:**
- Fixed multi-line string syntax errors at lines 133 and 149
- Converted multi-line quest descriptions to single-line format
- All syntax errors resolved for successful compilation

**Success metrics:**
- Database passes luac syntax validation with no errors
- 757 quest entries, 765 total lines
- Ready for in-game compilation testing

## Key Learnings & Best Practices

### 1. Separate Legacy Flow is Essential
Legacy submissions from v1.0.68 required different validation criteria (40+ score vs 70+) due to format differences and data collection bugs in older versions.

### 2. Regex Patterns Need Careful Testing
The initial DATABASE ENTRIES regex was too restrictive, causing 0 quest extraction. The fix from `(.*?)$` to `(.*)` was critical for success.

### 3. Intelligent Merge Logic Prevents Data Degradation
Conservative merge approach:
- Don't update if current data looks more complete
- Update if legacy has real name and current is placeholder  
- Update if legacy data is significantly more detailed (>20% longer)

### 4. Syntax Validation is Mandatory
Multi-line strings in quest descriptions caused compilation errors. All merged data must pass `luac -p` validation.

### 5. Comprehensive Backups Are Critical
Full database backup with timestamp and detailed info file enables safe rollback if issues arise.

## File Structure

```
Development Tools/GitHub Workflow/
├── github_issue_downloader.py      # Stage 1: Download issues
├── legacy_processor.py             # Stage 2: Process legacy data  
├── legacy_data_parser.py           # Stage 3: Parse and validate
├── merge_legacy_data.py            # Stage 4: Merge into database
├── create_backup.py                # Backup creation utility
├── github_issues/                  # Downloaded issue files
├── validated_legacy_data/          # Processed submissions
└── LEGACY_QUEST_INTEGRATION_WORKFLOW.md  # This document
```

## Results Summary

**From 875 GitHub submissions to 173 new quests:**

| Stage | Input | Output | Success Rate |
|-------|-------|--------|--------------|
| Download | 875 GitHub issues | 875 files | 100% |
| Legacy Processing | 298 legacy submissions | 295 valid | 99% |
| Data Parsing | 851 valid entries | 465 unique quests | 97% |
| Database Merge | 465 candidates | 177 integrated (173 new + 4 updated) | Smart merge |
| Final Database | 584 original quests | 757 total quests | 30% growth |

**Community Impact:**
- 173 brand new quests added to database
- 30% increase in total quest coverage  
- Recognition for all 875+ community contributors
- Established sustainable workflow for future integrations

## Future Usage

This workflow can be re-run for future quest submission batches:

1. Modify `github_issue_downloader.py` date filters for new submissions
2. Run all stages in sequence
3. Test compilation in-game before committing
4. Update README and CHANGELOG with new statistics
5. Create proper git commit with community recognition

**Note**: This workflow was specifically designed for legacy v1.0.68 submissions. Future submissions from v1.1.1+ should use the standard validation pipeline with 70+ score threshold.