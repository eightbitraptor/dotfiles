# AUR Package Resource Plugin for Mitamae
# Provides automated installation and removal of packages from the ArchLinux User Repository
#
# Attributes:
#   name   - Package name from AUR (required)
#   action - Action to perform: :install (default) or :remove
#
# Example usage:
#   aur_package 'yay'
#   
#   aur_package 'google-chrome' do
#     action :install
#   end
#
#   aur_package 'outdated-package' do
#     action :remove
#   end

# Custom exception class for AUR package errors
class AurPackageError < StandardError; end

define :aur_package, action: :install do
  # Extract and validate attributes
  package_name = params[:name]
  action = params[:action]
  
  # Validate required attributes
  if package_name.nil? || package_name.empty?
    MItamae.logger.error("Package name is required for aur_package resource")
    raise ArgumentError, "Package name cannot be empty"
  end
  
  # Validate package name format (must be a string and follow package naming conventions)
  unless package_name.is_a?(String)
    MItamae.logger.error("Package name must be a string, got #{package_name.class}")
    raise ArgumentError, "Package name must be a string"
  end
  
  # Validate package name characters (alphanumeric, dash, underscore, plus, dot)
  unless package_name.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._+-]*\z/)
    MItamae.logger.error("Invalid package name format: #{package_name}")
    MItamae.logger.error("Package names must start with alphanumeric and contain only letters, numbers, dash, underscore, plus, or dot")
    raise ArgumentError, "Invalid package name format: #{package_name}"
  end
  
  # Validate action attribute
  valid_actions = [:install, :remove]
  unless valid_actions.include?(action)
    MItamae.logger.error("Invalid action #{action} for aur_package resource. Valid actions are: #{valid_actions.join(', ')}")
    raise ArgumentError, "Invalid action #{action}. Valid actions are: #{valid_actions.join(', ')}"
  end
  
  # Ensure we have a non-root user for AUR operations
  aur_user = node[:user]
  if aur_user.nil? || aur_user == 'root'
    MItamae.logger.error("AUR packages cannot be installed as root. Please ensure node[:user] is set to a non-root user.")
    MItamae.logger.error("Action required: Set node[:user] to a non-root user in your node attributes or configuration")
    raise AurPackageError, "AUR packages must be installed as a non-root user. Current user: #{aur_user || 'nil'}"
  end
  
  # Check if yay is available
  yay_available = system("which yay >/dev/null 2>&1")
  unless yay_available
    MItamae.logger.error("yay is not installed. The aur_package resource requires yay to manage AUR packages.")
    MItamae.logger.error("To install yay:")
    MItamae.logger.error("  1. As a non-root user, run: git clone https://aur.archlinux.org/yay.git")
    MItamae.logger.error("  2. cd yay")
    MItamae.logger.error("  3. makepkg -si")
    MItamae.logger.error("Or install yay-bin from AUR for a pre-compiled version")
    raise AurPackageError, "yay is required for AUR package management but is not installed. Please install yay first."
  end
  
  # Log the action being performed
  MItamae.logger.info("aur_package[#{package_name}] action: #{action} (user: #{aur_user})")
  
  # Check current package status for logging
  package_installed = system("pacman -Q #{package_name} >/dev/null 2>&1")
  
  case action
  when :install
    if package_installed
      MItamae.logger.debug("Package #{package_name} is already installed, skipping")
    else
      MItamae.logger.info("Package #{package_name} is not installed, proceeding with installation")
    end
    
    # Install action implementation (idempotent - skips if already installed)
    execute "aur_package_install_#{package_name}" do
      command <<~CMD
        OUTPUT=$(yay -S #{package_name} --noconfirm --needed --noprogressbar --nocolor 2>&1)
        EXIT_CODE=$?
        echo "$OUTPUT"
        
        # Check for specific error patterns
        if echo "$OUTPUT" | grep -q "could not satisfy dependencies\\|unable to satisfy dependency\\|target not found\\|Dependency.*not found"; then
          echo "" >&2
          echo "ERROR: Dependency resolution failed for #{package_name}" >&2
          echo "The package has unmet dependencies. Possible solutions:" >&2
          echo "  1. Install missing dependencies manually" >&2
          echo "  2. Check if the package is compatible with your system" >&2
          echo "  3. Try updating your package database: yay -Sy" >&2
          echo "" >&2
          
          # Extract dependency information if available
          if echo "$OUTPUT" | grep -q "Dependency.*not found"; then
            echo "Missing dependencies detected:" >&2
            echo "$OUTPUT" | grep "Dependency.*not found" | sed 's/^/  /' >&2
          fi
          
          exit 1
        fi
        
        # Check for conflicts
        if echo "$OUTPUT" | grep -q "conflicting packages\\|are in conflict"; then
          echo "" >&2
          echo "ERROR: Package conflicts detected for #{package_name}" >&2
          echo "The package conflicts with existing packages. Solutions:" >&2
          echo "  1. Remove conflicting packages first" >&2
          echo "  2. Use 'yay -S #{package_name} --overwrite' if appropriate" >&2
          echo "" >&2
          exit 1
        fi
        
        case $EXIT_CODE in
          0)
            # Success
            exit 0
            ;;
          1)
            echo "ERROR: Failed to install AUR package: #{package_name}" >&2
            echo "Exit code 1: General failure - check output above for details" >&2
            exit 1
            ;;
          127)
            echo "ERROR: yay command not found" >&2
            echo "Please ensure yay is installed and in PATH" >&2
            exit 127
            ;;
          *)
            echo "ERROR: yay exited with code $EXIT_CODE while installing #{package_name}" >&2
            echo "Common causes based on exit code:" >&2
            echo "  - Package not found in AUR" >&2
            echo "  - Build dependencies missing" >&2
            echo "  - Compilation errors" >&2
            echo "  - Insufficient disk space or permissions" >&2
            echo "Check the output above for specific error details" >&2
            exit $EXIT_CODE
            ;;
        esac
      CMD
      user aur_user
      not_if "pacman -Q #{package_name} 2>/dev/null"  # Idempotency: skip if package exists
    end
    
  when :remove
    if package_installed
      MItamae.logger.info("Package #{package_name} is installed, proceeding with removal")
    else
      MItamae.logger.debug("Package #{package_name} is not installed, skipping removal")
    end
    
    # Remove action implementation (idempotent - skips if not installed)
    execute "aur_package_remove_#{package_name}" do
      command <<~CMD
        yay -R #{package_name} --noconfirm --noprogressbar --nocolor 2>&1
        EXIT_CODE=$?
        
        case $EXIT_CODE in
          0)
            # Success
            exit 0
            ;;
          1)
            echo "ERROR: Failed to remove AUR package: #{package_name}" >&2
            echo "Exit code 1: General failure - package may be required by others" >&2
            echo "Try 'yay -R #{package_name} --cascade' to remove dependent packages" >&2
            exit 1
            ;;
          127)
            echo "ERROR: yay command not found" >&2
            echo "Please ensure yay is installed and in PATH" >&2
            exit 127
            ;;
          *)
            echo "ERROR: yay exited with code $EXIT_CODE while removing #{package_name}" >&2
            echo "Common causes:" >&2
            echo "  - Package is required by other packages (dependency)" >&2
            echo "  - Permission issues" >&2
            echo "  - Package database corruption" >&2
            echo "Check the output above for specific error details" >&2
            exit $EXIT_CODE
            ;;
        esac
      CMD
      user aur_user
      only_if "pacman -Q #{package_name} 2>/dev/null"  # Idempotency: skip if package doesn't exist
    end
  end
end