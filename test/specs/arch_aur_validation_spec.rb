require_relative '../validators/package_validator'

module MitamaeTest
  module Specs
    class ArchAurValidationSpec
      include TestFramework

      def self.description
        "Arch Linux AUR package validation"
      end

      def self.supported_environments
        ['arch']
      end

      def run_tests(environment)
        return skip_test("Not running on Arch Linux") unless arch_linux?(environment)
        
        test_aur_helper_availability(environment)
        test_aur_package_installation(environment)
        test_mixed_package_types(environment)
      end

      private

      def test_aur_helper_availability(environment)
        test_group "AUR Helper Availability" do
          test_case "AUR Helper Detection" do
            validator = Validators::PackageValidator.new
            
            # Test that we can detect AUR helpers
            aur_helpers = ['yay', 'paru']
            available_helpers = aur_helpers.select do |helper|
              result = environment.execute("which #{helper}")
              result[:exit_code] == 0
            end
            
            assert !available_helpers.empty?, "At least one AUR helper (yay or paru) should be available"
          end
        end
      end

      def test_aur_package_installation(environment)
        test_group "AUR Package Installation" do
          test_case "Common AUR Packages" do
            aur_packages = [
              { name: 'yay', type: :aur },
              { name: 'visual-studio-code-bin', type: :aur },
              { name: 'google-chrome', type: :aur }
            ]
            
            validator = Validators::PackageValidator.new
            validator.validate(environment, packages: aur_packages)
            
            # At least yay should be installed (needed for AUR management)
            yay_errors = validator.errors.select { |e| e.details[:package] == 'yay' }
            assert yay_errors.empty?, "yay AUR helper should be installed"
            
            # Other packages may or may not be installed - just verify detection works
            validator.errors.each do |error|
              assert error.details[:manager] == 'yay' || error.details[:manager] == 'paru',
                     "AUR packages should be validated with proper AUR helper"
            end
          end
        end
      end

      def test_mixed_package_types(environment)
        test_group "Mixed Package Types" do
          test_case "Standard and AUR Packages Together" do
            mixed_packages = [
              'git',                              # Standard package
              'base-devel',                       # Package group
              { name: 'yay', type: :aur },       # AUR package
              { name: 'firefox', type: :standard }, # Explicit standard
              { name: 'discord', type: :aur }     # AUR package
            ]
            
            validator = Validators::PackageValidator.new
            validator.validate(environment, packages: mixed_packages)
            
            # Verify that each package type is handled correctly
            standard_packages = ['git', 'base-devel', 'firefox']
            standard_packages.each do |pkg|
              pkg_errors = validator.errors.select { |e| e.details[:package] == pkg }
              pkg_errors.each do |error|
                assert error.details[:manager] == 'pacman',
                       "Standard package #{pkg} should be validated with pacman"
              end
            end
            
            aur_packages = ['yay', 'discord']
            aur_packages.each do |pkg|
              pkg_errors = validator.errors.select { |e| e.details[:package] == pkg }
              pkg_errors.each do |error|
                assert ['yay', 'paru'].include?(error.details[:manager]),
                       "AUR package #{pkg} should be validated with AUR helper"
              end
            end
          end
        end
      end

      def arch_linux?(environment)
        environment.file_exists?('/etc/arch-release')
      end
    end
  end
end