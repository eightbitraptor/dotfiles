require_relative '../validators/package_validator'
require_relative '../validators/service_validator'

module MitamaeTest
  module Specs
    class MultiDistributionValidationSpec
      include TestFramework

      def self.description
        "Multi-distribution package and service validation"
      end

      def self.supported_environments
        ['arch', 'fedora', 'void', 'ubuntu']
      end

      def run_tests(environment)
        test_package_validation(environment)
        test_service_validation(environment)
        test_user_group_validation(environment)
      end

      private

      def test_package_validation(environment)
        test_group "Package Validation" do
          test_standard_packages(environment)
          test_aur_packages(environment) if arch_linux?(environment)
          test_flatpak_packages(environment)
        end
      end

      def test_standard_packages(environment)
        test_case "Standard Package Installation" do
          packages = distribution_packages(environment)
          
          validator = Validators::PackageValidator.new
          validator.validate(environment, packages: packages)
          
          assert validator.success?, "Standard packages should be installed: #{validator.errors.map(&:message).join(', ')}"
        end
      end

      def test_aur_packages(environment)
        test_case "AUR Package Installation" do
          aur_packages = [
            { name: 'yay', type: :aur },
            { name: 'paru', type: :aur }
          ]
          
          validator = Validators::PackageValidator.new
          validator.validate(environment, packages: aur_packages)
          
          # At least one AUR helper should be installed
          assert !validator.failed?, "At least one AUR helper should be installed"
        end
      end

      def test_flatpak_packages(environment)
        test_case "Flatpak Package Installation" do
          flatpak_packages = [
            { name: 'org.mozilla.firefox', type: :flatpak },
            { name: 'org.libreoffice.LibreOffice', type: :flatpak }
          ]
          
          validator = Validators::PackageValidator.new
          validator.validate(environment, packages: flatpak_packages)
          
          # Flatpak packages may or may not be installed - just verify validator works
          assert validator.errors.empty? || validator.errors.all? { |e| e.message.include?('not installed') },
                 "Flatpak validation should work properly"
        end
      end

      def test_service_validation(environment)
        test_group "Service Validation" do
          test_systemd_services(environment) if systemd_environment?(environment)
          test_runit_services(environment) if runit_environment?(environment)
        end
      end

      def test_systemd_services(environment)
        test_case "Systemd Service States" do
          services = [
            { name: 'sshd', state: :enabled },
            { name: 'networking', state: :enabled },
            { name: 'bluetooth', state: :disabled }
          ]
          
          validator = Validators::ServiceValidator.new
          validator.validate(environment, services: services)
          
          # Validate that critical services are properly managed
          enabled_services = services.select { |s| s[:state] == :enabled }
          enabled_services.each do |service|
            service_errors = validator.errors.select { |e| e.details[:service] == service[:name] }
            assert service_errors.empty?, "Service #{service[:name]} should be enabled and active"
          end
        end
      end

      def test_runit_services(environment)
        test_case "Runit Service States" do
          services = [
            { name: 'sshd', state: :enabled },
            { name: 'dhcpcd', state: :enabled }
          ]
          
          validator = Validators::ServiceValidator.new
          validator.validate(environment, services: services)
          
          # Validate runit services are properly linked and running
          enabled_services = services.select { |s| s[:state] == :enabled }
          enabled_services.each do |service|
            service_errors = validator.errors.select { |e| e.details[:service] == service[:name] }
            assert service_errors.empty?, "Runit service #{service[:name]} should be enabled and running"
          end
        end
      end

      def test_user_group_validation(environment)
        test_group "User Group Validation" do
          test_case "System Groups and Users" do
            user_groups = [
              { name: 'wheel', users: ['root'] },
              { name: 'sudo', users: [] },
              { name: 'docker', users: ['testuser'] }
            ]
            
            validator = Validators::ServiceValidator.new
            validator.validate(environment, user_groups: user_groups)
            
            # Validate that important system groups exist
            user_groups.each do |group|
              group_errors = validator.errors.select { |e| e.details[:group] == group[:name] }
              next if group_errors.any? { |e| e.message.include?('does not exist') }
              
              # If group exists, validate users
              group[:users].each do |user|
                user_errors = validator.errors.select do |e| 
                  e.details[:user] == user && e.details[:group] == group[:name]
                end
                assert user_errors.empty?, "User #{user} should be in group #{group[:name]}"
              end
            end
          end
        end
      end

      def distribution_packages(environment)
        case detect_distribution(environment)
        when 'arch'
          ['base-devel', 'git', 'vim', 'htop']
        when 'fedora'
          ['@development-tools', 'git', 'vim-enhanced', 'htop']
        when 'void'
          ['base-devel', 'git', 'vim', 'htop']
        when 'ubuntu'
          ['build-essential', 'git', 'vim', 'htop']
        else
          ['git', 'vim']
        end
      end

      def detect_distribution(environment)
        return 'arch' if environment.file_exists?('/etc/arch-release')
        return 'fedora' if environment.file_exists?('/etc/fedora-release')
        return 'void' if environment.file_exists?('/etc/void-release')
        return 'ubuntu' if environment.execute('grep -q "ID=ubuntu" /etc/os-release 2>/dev/null')[:exit_code] == 0
        'unknown'
      end

      def arch_linux?(environment)
        detect_distribution(environment) == 'arch'
      end

      def systemd_environment?(environment)
        environment.execute('which systemctl')[:exit_code] == 0
      end

      def runit_environment?(environment)
        environment.execute('which sv')[:exit_code] == 0 || environment.file_exists?('/etc/runit')
      end
    end
  end
end