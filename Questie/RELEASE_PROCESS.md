# Release Process for Questie-Epoch

## Overview
This project uses GitHub Actions for automated releases based on changelog entries.

## Prerequisites
- Ensure all changes are committed and pushed to master
- Update CHANGELOG.md with all changes under the `[Unreleased]` section

## Release Steps

### 1. Update CHANGELOG.md
Move changes from `[Unreleased]` to a new version section:
```markdown
## [Unreleased]

(becomes)

## [1.0.5] - 2025-08-29

### Fixed
- List of fixes...

### Added
- List of additions...

### Changed
- List of changes...
```

### 2. Update Version in Questie.toc
```lua
## Version: 1.0.5
```

### 3. Commit Version Bump
```bash
git add CHANGELOG.md Questie.toc
git commit -m "Prepare release v1.0.5"
git push
```

### 4. Create Release via GitHub Actions
1. Go to [Actions tab](https://github.com/trav346/Questie-Epoch/actions)
2. Select "Create Release" workflow
3. Click "Run workflow"
4. Enter version number (e.g., `1.0.5`)
5. Click "Run workflow"

The action will:
- Create a git tag
- Generate GitHub release with changelog content
- Create and attach a zip file of the addon

## Manual Release (Alternative)
If GitHub Actions aren't available:

```bash
# Tag the release
git tag -a v1.0.5 -m "Release version 1.0.5"
git push origin v1.0.5

# Create release on GitHub UI
# 1. Go to Releases page
# 2. Click "Create release"
# 3. Select the tag
# 4. Copy relevant CHANGELOG.md section to description
# 5. Attach addon zip file
```

## Changelog Format Guidelines

### Categories
- **Added** - New features
- **Changed** - Changes to existing functionality
- **Deprecated** - Features that will be removed
- **Removed** - Removed features
- **Fixed** - Bug fixes
- **Security** - Security fixes

### Writing Good Changelog Entries
- Start with the component affected in **bold**
- Be specific about what changed
- Include PR numbers and contributor credits where applicable
- Group related changes together

### Example Entry
```markdown
### Fixed
- **World Map Tooltips**: Fixed tooltips not showing on vanilla fullscreen map (PR #25 by @virtiz)
  - Tooltips now properly check full parent chain
  - Added screen clamping for edge cases
```

## Version Numbering
We use semantic versioning: MAJOR.MINOR.PATCH

- **MAJOR** (1.x.x): Breaking changes or major rewrites
- **MINOR** (x.1.x): New features, significant improvements
- **PATCH** (x.x.1): Bug fixes, minor improvements

For Project Epoch specific changes, we're currently in 1.0.x series.