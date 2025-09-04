# Release Workflow - Questie Project Epoch

## Branch Strategy

### `master` branch (Development)
- **Purpose**: Active development, bug fixes, feature work
- **Stability**: May contain experimental or untested code
- **Usage**: All development work happens here
- **Auto-push**: Yes, development changes pushed automatically

### `release` branch (Production) 
- **Purpose**: Stable releases for end users
- **Stability**: Only tested, stable code
- **Usage**: Addon managers track this branch for auto-updates
- **Auto-push**: **NO** - Only pushed when explicitly approved for release

## New Workflow Process

### Daily Development (Master Branch)
1. All development work continues on `master`
2. Bug fixes, feature additions, Issue #2, Issue #3 work
3. Version bumps happen on `master` first
4. **Auto-push to master continues as normal**

### Release Process (Release Branch)
1. **Testing Phase**: Test changes thoroughly on `master`
2. **User Approval**: User explicitly says "release this" or "push to release"
3. **Release Merge**:
   ```bash
   git checkout release
   git merge master
   git push origin release
   ```
4. **Tag Release** (optional):
   ```bash
   git tag v1.1.4
   git push origin v1.1.4
   ```

## Claude's Behavior Rules

### ✅ AUTO-PUSH (No Permission Needed)
- **Master branch**: All development work
- Bug fixes, feature additions, Issue investigations
- CHANGELOG updates, version bumps
- Database fixes, code improvements

### ❌ REQUIRE EXPLICIT APPROVAL
- **Release branch**: Never push automatically
- Must hear: "release this", "push to release", "merge to release"
- Wait for explicit user instruction

### 🤖 How I'll Ask for Release
When master has significant changes ready for users:
- "Master has Issue #2 fixes ready. Should I merge to release branch?"
- "Version 1.1.5 is stable on master. Release to users?"
- **I will NOT push to release without permission**

## User Benefits
- **Addon managers** can track `origin/release` for stable updates
- **Development speed** maintained on master
- **Release control** - you decide when users get updates
- **Rollback safety** - release branch can be reverted if needed

## Current Status
- ✅ Release branch created with Issue #1 fixes (v1.1.4)
- ✅ Master and release branches currently identical
- ✅ Next development continues on master
- ✅ Users can point addon managers to `release` branch

## Addon Manager Setup for Users
Users should configure their addon managers to track:
- **Repository**: `https://github.com/trav346/Questie-Epoch`
- **Branch**: `release` (not master)
- **Auto-update**: Enabled

This ensures they get stable releases while development continues rapidly on master.