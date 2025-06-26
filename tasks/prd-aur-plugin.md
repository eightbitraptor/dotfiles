# Product Requirements Document: Mitamae AUR Plugin

## Introduction/Overview

This document outlines the requirements for a mitamae plugin that provides seamless installation and management of packages from the ArchLinux User Repository (AUR). Currently, recipes exit with errors when AUR packages are needed, requiring manual intervention. This plugin will automate AUR package installation, improving automation workflows and reducing manual setup time for personal dotfile configurations.

## Goals

1. Enable automated installation of AUR packages through mitamae recipes without manual intervention
2. Provide a consistent interface similar to the existing package resource pattern
3. Eliminate recipe exits due to missing AUR packages
4. Improve the overall automation experience for ArchLinux systems
5. Support basic install/remove operations for AUR packages

## User Stories

1. **As a personal user managing dotfiles**, I want to automatically install AUR packages during system setup so that I don't need to manually install them after running mitamae.

2. **As a developer**, I want to define AUR package dependencies in my recipes using a familiar syntax so that I can maintain consistency with other package declarations.

3. **As a system administrator**, I want clear error messages when AUR package builds fail so that I can quickly diagnose and fix issues.

4. **As a recipe author**, I want to replace error-exit patterns with proper AUR package resources so that my recipes complete successfully in automated runs.

## Functional Requirements

1. The plugin must provide an `aur_package` resource that follows mitamae's resource conventions
2. The resource must support the following actions:
   - `:install` (default) - Install the package if not present
   - `:remove` - Remove the package if present
3. The plugin must use `yay` as the AUR helper for package operations
4. The resource must accept the following attributes:
   - `name` - Package name from AUR (required)
   - `action` - Action to perform (optional, defaults to :install)
5. The plugin must check if the package is already installed before attempting installation
6. The plugin must handle package dependencies automatically through yay
7. The plugin must provide clear error messages if:
   - yay is not installed
   - Package build fails
   - Dependencies cannot be resolved
8. The plugin must run yay with appropriate flags to enable non-interactive operation
9. The resource must support notifications (notifies/subscribes) like other mitamae resources
10. The plugin must log installation progress at appropriate verbosity levels

## Non-Goals (Out of Scope)

1. Support for custom PKGBUILDs or local package builds
2. Version pinning or specific version installation
3. Parallel package builds
4. Package caching mechanisms
5. Support for AUR helpers other than yay
6. Advanced build configuration or makepkg flags
7. Conflict resolution beyond what yay provides automatically

## Design Considerations

### Resource Usage Example
```ruby
# Install an AUR package
aur_package 'google-chrome' do
  action :install
end

# Remove an AUR package
aur_package 'outdated-tool' do
  action :remove
end

# With notifications
aur_package 'visual-studio-code-bin' do
  action :install
  notifies :restart, 'service[code-server]'
end
```

### Integration Pattern
- The plugin should be implemented as a mitamae resource definition
- It should be placed in a location where it can be required by recipes
- Existing recipes should be refactored to replace error-exit patterns with aur_package resources

## Technical Considerations

1. **Dependency on yay**: The plugin assumes yay is already installed on the system. Consider adding a check and helpful error message if yay is not found.

2. **User Permissions**: AUR packages typically should not be installed as root. The plugin needs to handle privilege dropping appropriately.

3. **Non-interactive Mode**: Must ensure yay is called with flags like `--noconfirm` to prevent interactive prompts during automated runs.

4. **Exit Codes**: Properly handle and translate yay exit codes to mitamae success/failure states.

5. **Idempotency**: Ensure the resource is idempotent - running it multiple times should not cause errors if the package is already installed.

## Success Metrics

1. **Zero Manual Interventions**: All AUR packages specified in recipes install without requiring user interaction
2. **Reduced Recipe Complexity**: Elimination of conditional logic and error exits related to AUR packages
3. **Consistent Package Management**: AUR packages are managed with the same pattern as official repository packages
4. **Clear Error Reporting**: Failed installations provide actionable error messages
5. **Successful Refactoring**: All existing recipes that require AUR packages are updated to use the new plugin

## Open Questions

1. Should the plugin automatically install yay if it's not present, or should this be a prerequisite documented in the README?
2. What should be the default behavior if a package is already installed but outdated?
3. Should the plugin support any form of version checking or update operations beyond basic install/remove?
4. How should the plugin handle AUR packages that have conflicts with official repository packages?
5. Should there be a dry-run mode for testing which packages would be installed?