## Relevant Files

- `recipes/plugins/aur_package.rb` - Main plugin file containing the AUR package resource definition
- `recipes/plugins/init.rb` - Plugin initialization file to include all plugins
- `recipes/plugins/aur_package_test.rb` - Unit tests for the AUR package resource
- `recipes/prelude/distro/arch.rb` - May need modification to ensure yay is available
- `recipes/sway.rb` - Updated to use aur_package for scenefx-git, swayfx, and light
- `recipes/devel-base.rb` - Updated to use aur_package for rr
- `recipes/abcde.rb` - Updated to use aur_package for abcde
- `README.md` - Documentation updates for the new AUR plugin

### Notes

- The plugin will be implemented as a mitamae resource definition following the existing patterns
- Tests should verify both successful installations and proper error handling
- Consider creating a helper module for common yay operations

## Tasks

- [x] 1.0 Create the AUR package resource plugin structure
  - [x] 1.1 Create the `recipes/plugins/` directory if it doesn't exist
  - [x] 1.2 Create `recipes/plugins/aur_package.rb` with basic resource definition skeleton
  - [x] 1.3 Define the resource name and available actions (:install, :remove)
  - [x] 1.4 Set up attribute definitions for name and action
  - [x] 1.5 Create the basic structure following mitamae's resource conventions

- [x] 2.0 Implement core AUR package installation and removal functionality
  - [x] 2.1 Implement the :install action with package existence check
  - [x] 2.2 Add yay command execution with proper flags (--noconfirm, --needed)
  - [x] 2.3 Handle user permission dropping for non-root execution
  - [x] 2.4 Implement the :remove action with yay removal command
  - [x] 2.5 Add logging for installation/removal progress
  - [x] 2.6 Ensure idempotency for both install and remove actions

- [x] 3.0 Add error handling and validation logic
  - [x] 3.1 Add check for yay availability with helpful error message
  - [x] 3.2 Implement error handling for package build failures
  - [x] 3.3 Add validation for required attributes (package name)
  - [x] 3.4 Handle and translate yay exit codes to mitamae states
  - [x] 3.5 Add error handling for dependency resolution failures
  - [x] 3.6 Implement proper exception raising with clear messages

- [x] 4.0 Refactor existing recipes to use the new AUR package resource
  - [x] 4.1 Search for recipes with AUR package error-exit patterns
  - [x] 4.2 Update identified recipes to use the new aur_package resource
  - [ ] 4.3 Test refactored recipes to ensure they work correctly (skipped - will be done separately)
  - [x] 4.4 Remove conditional logic and manual installation instructions
  - [x] 4.5 Update any recipe documentation or comments as needed

- [ ] 5.0 Create tests and documentation for the plugin
  - [ ] 5.1 Create unit tests for the aur_package resource
  - [ ] 5.2 Test successful package installation scenarios
  - [ ] 5.3 Test package removal scenarios
  - [ ] 5.4 Test error conditions (missing yay, failed builds)
  - [x] 5.5 Update README.md with usage instructions for the AUR plugin
  - [x] 5.6 Document prerequisites (yay installation) and limitations