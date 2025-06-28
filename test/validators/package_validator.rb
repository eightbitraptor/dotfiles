require_relative '../lib/validators/base'

module MitamaeTest
  module Validators
    class PackageValidator < Base
      plugin_name 'package'

      DISTRIBUTION_PACKAGE_MANAGERS = {
        'arch' => { standard: 'pacman', aur: 'yay' },
        'fedora' => { standard: 'dnf' },
        'void' => { standard: 'xbps-query' },
        'ubuntu' => { standard: 'dpkg' },
        'debian' => { standard: 'dpkg' }
      }.freeze

      def validate(environment, context = {})
        clear_results
        
        packages = context[:packages] || []
        return add_error("No packages specified for validation") if packages.empty?

        distribution = detect_distribution(environment)
        return add_error("Unsupported distribution: #{distribution}") unless supported_distribution?(distribution)

        packages.each do |package_spec|
          validate_package(environment, package_spec, distribution)
        end
      end

      private

      def detect_distribution(environment)
        # Check for distribution-specific files
        return 'arch' if environment.file_exists?('/etc/arch-release')
        return 'fedora' if environment.file_exists?('/etc/fedora-release')
        return 'void' if environment.file_exists?('/etc/void-release')
        return 'ubuntu' if check_file(environment, '/etc/os-release') { |content| content.include?('ID=ubuntu') }
        return 'debian' if check_file(environment, '/etc/os-release') { |content| content.include?('ID=debian') }
        
        'unknown'
      end

      def supported_distribution?(distribution)
        DISTRIBUTION_PACKAGE_MANAGERS.key?(distribution)
      end

      def validate_package(environment, package_spec, distribution)
        package_name = extract_package_name(package_spec)
        package_type = extract_package_type(package_spec)

        case package_type
        when :standard
          validate_standard_package(environment, package_name, distribution)
        when :aur
          validate_aur_package(environment, package_name, distribution)
        when :flatpak
          validate_flatpak_package(environment, package_name, distribution)
        else
          add_error("Unknown package type for: #{package_spec}")
        end
      end

      def extract_package_name(package_spec)
        case package_spec
        when String
          package_spec
        when Hash
          package_spec[:name] || package_spec['name']
        else
          package_spec.to_s
        end
      end

      def extract_package_type(package_spec)
        case package_spec
        when Hash
          type = package_spec[:type] || package_spec['type']
          return type.to_sym if type
        end
        
        # Default to standard package
        :standard
      end

      def validate_standard_package(environment, package_name, distribution)
        case distribution
        when 'arch'
          validate_pacman_package(environment, package_name)
        when 'fedora'
          validate_dnf_package(environment, package_name)
        when 'void'
          validate_xbps_package(environment, package_name)
        when 'ubuntu', 'debian'
          validate_dpkg_package(environment, package_name)
        end
      end

      def validate_pacman_package(environment, package_name)
        result = execute_command(environment, "pacman -Q #{package_name}")
        
        if result.success?
          version = result.stdout.strip.split.last
          log_info "Package #{package_name} installed: #{version}"
        else
          add_error("Package #{package_name} not installed", 
                   { package: package_name, distribution: 'arch', manager: 'pacman' })
        end
      end

      def validate_dnf_package(environment, package_name)
        result = execute_command(environment, "dnf list installed #{package_name}")
        
        if result.success?
          log_info "Package #{package_name} installed"
        else
          add_error("Package #{package_name} not installed", 
                   { package: package_name, distribution: 'fedora', manager: 'dnf' })
        end
      end

      def validate_xbps_package(environment, package_name)
        result = execute_command(environment, "xbps-query -l | grep '^ii #{package_name}'")
        
        if result.success?
          log_info "Package #{package_name} installed"
        else
          add_error("Package #{package_name} not installed", 
                   { package: package_name, distribution: 'void', manager: 'xbps' })
        end
      end

      def validate_dpkg_package(environment, package_name)
        result = execute_command(environment, "dpkg -l #{package_name}")
        
        if result.success? && result.stdout.include?('ii')
          log_info "Package #{package_name} installed"
        else
          add_error("Package #{package_name} not installed", 
                   { package: package_name, distribution: 'debian/ubuntu', manager: 'dpkg' })
        end
      end

      def validate_aur_package(environment, package_name, distribution)
        return add_error("AUR packages only supported on Arch Linux") unless distribution == 'arch'
        
        # Check if package is available via AUR helper (yay/paru)
        aur_helper = detect_aur_helper(environment)
        return add_error("No AUR helper found (yay/paru required)") unless aur_helper
        
        result = execute_command(environment, "#{aur_helper} -Q #{package_name}")
        
        if result.success?
          version = result.stdout.strip.split.last
          log_info "AUR package #{package_name} installed: #{version}"
        else
          add_error("AUR package #{package_name} not installed", 
                   { package: package_name, distribution: 'arch', manager: aur_helper })
        end
      end

      def detect_aur_helper(environment)
        %w[yay paru].find do |helper|
          execute_command(environment, "which #{helper}").success?
        end
      end

      def validate_flatpak_package(environment, package_name, distribution)
        # Check if flatpak is available
        result = execute_command(environment, "which flatpak")
        return add_error("Flatpak not available on system") unless result.success?
        
        # Check if package is installed
        result = execute_command(environment, "flatpak list | grep #{package_name}")
        
        if result.success?
          log_info "Flatpak package #{package_name} installed"
        else
          add_error("Flatpak package #{package_name} not installed", 
                   { package: package_name, distribution: distribution, manager: 'flatpak' })
        end
      end
    end
  end
end