#!/usr/bin/env ruby

# Example of using the graphical validators together
# This demonstrates how to validate a complete Wayland desktop environment

require_relative '../lib/test_framework'
require_relative 'graphical_validator'
require_relative 'screenshot_validator'
require_relative 'visual_validator'
require_relative 'headless_display_validator'

module MitamaeTest
  module Examples
    class GraphicalDesktopTest
      include Logging
      
      def initialize(environment, options = {})
        @environment = environment
        @options = options
        @headless = options[:headless] || environment.containerized?
        @compositor = options[:compositor] || 'sway'
      end
      
      def run_full_validation
        log_info "Starting full graphical desktop validation"
        
        results = {
          setup: setup_display_server,
          graphical: validate_graphical_environment,
          visual: validate_visual_appearance,
          screenshots: validate_with_screenshots,
          applications: validate_applications
        }
        
        generate_report(results)
        results
      end
      
      private
      
      def setup_display_server
        return { success: true, message: "Using existing display" } unless @headless
        
        log_info "Setting up headless display server"
        
        validator = HeadlessDisplayValidator.new(
          backend: @options[:backend] || 'wlroots',
          compositor: @compositor,
          resolution: @options[:resolution] || '1920x1080'
        )
        
        if validator.setup_headless_display(@environment)
          # Give the display server time to initialize
          sleep 3
          { success: true, message: "Headless display ready" }
        else
          { success: false, errors: validator.errors }
        end
      end
      
      def validate_graphical_environment
        log_info "Validating graphical environment"
        
        validator = GraphicalValidator.new(
          compositor: @compositor,
          headless: @headless,
          require_xwayland: @options[:require_xwayland]
        )
        
        validator.validate(@environment)
        
        {
          success: validator.success?,
          errors: validator.errors,
          warnings: validator.warnings,
          details: validator.to_h
        }
      end
      
      def validate_visual_appearance
        log_info "Validating visual appearance"
        
        # Create screenshot validator for visual validator to use
        screenshot_validator = ScreenshotValidator.new(
          capture_tool: @headless ? 'grim' : detect_capture_tool,
          output_dir: @options[:screenshot_dir] || '/tmp/mitamae-visual-test'
        )
        
        validator = VisualValidator.new(
          screenshot_validator: screenshot_validator,
          strict: @options[:strict_theme_validation]
        )
        
        # Define applications to test
        applications = [
          {
            name: 'terminal',
            launch: @options[:terminal_cmd] || 'foot',
            window_title: 'foot',
            wait: 2,
            visual_checks: [
              { type: 'has_titlebar' },
              { type: 'minimum_size', width: 800, height: 600 }
            ],
            cleanup: 'pkill -x foot'
          }
        ]
        
        validator.validate(@environment, applications: applications)
        
        {
          success: validator.success?,
          errors: validator.errors,
          warnings: validator.warnings,
          details: validator.to_h
        }
      end
      
      def validate_with_screenshots
        log_info "Running screenshot validation"
        
        validator = ScreenshotValidator.new(
          capture_tool: @headless ? 'grim' : detect_capture_tool,
          compare_tool: 'compare',
          output_dir: @options[:screenshot_dir] || '/tmp/mitamae-screenshots',
          reference_dir: @options[:reference_dir],
          threshold: @options[:diff_threshold] || 0.01
        )
        
        # Define what to capture
        captures = [
          {
            name: 'empty_desktop',
            options: {},
            validate: [
              { type: 'resolution', width: 1920, height: 1080 }
            ]
          },
          {
            name: 'with_terminal',
            setup: [@options[:terminal_cmd] || 'foot &'],
            wait: 2,
            options: {},
            validate: [
              { type: 'contains_text', text: 'user@' } # Assumes terminal shows prompt
            ],
            cleanup: ['pkill -x foot']
          },
          {
            name: 'with_menu',
            setup: ['wtype Super'],  # Open application menu in Sway
            wait: 1,
            options: {},
            cleanup: ['wtype Escape']
          }
        ]
        
        if @options[:reference_dir]
          # Compare against references
          validator.validate(@environment, captures: captures)
        else
          # Just capture current state
          captures.each do |capture|
            perform_capture(validator, capture)
          end
        end
        
        {
          success: validator.success?,
          errors: validator.errors,
          warnings: validator.warnings,
          screenshots: Dir.glob("#{validator.instance_variable_get(:@output_dir)}/*.png")
        }
      end
      
      def validate_applications
        log_info "Validating desktop applications"
        
        applications = @options[:test_applications] || default_test_applications
        results = {}
        
        applications.each do |app|
          log_info "Testing application: #{app[:name]}"
          results[app[:name]] = test_application(app)
        end
        
        {
          success: results.values.all? { |r| r[:success] },
          applications: results
        }
      end
      
      def test_application(app)
        # Launch application
        launch_result = @environment.execute(app[:launch])
        unless launch_result[:exit_code] == 0
          return {
            success: false,
            error: "Failed to launch: #{launch_result[:stderr]}"
          }
        end
        
        # Wait for window
        sleep(app[:wait] || 2)
        
        # Take screenshot
        screenshot_validator = ScreenshotValidator.new(
          capture_tool: @headless ? 'grim' : detect_capture_tool,
          output_dir: @options[:screenshot_dir] || '/tmp/mitamae-app-tests'
        )
        
        screenshot = screenshot_validator.capture_screenshot(
          @environment,
          "app_#{app[:name]}",
          {}
        )
        
        # Run tests
        test_results = {}
        if app[:tests]
          app[:tests].each do |test|
            test_results[test[:name]] = run_app_test(test, screenshot)
          end
        end
        
        # Cleanup
        if app[:cleanup]
          @environment.execute(app[:cleanup])
        end
        
        {
          success: test_results.values.all? { |r| r[:success] },
          screenshot: screenshot,
          tests: test_results
        }
      end
      
      def run_app_test(test, screenshot)
        case test[:type]
        when 'window_exists'
          check_window_exists(test[:window_title])
        when 'screenshot_contains'
          check_screenshot_contains(screenshot, test[:text])
        when 'responds_to_input'
          check_input_response(test[:input], test[:expected])
        else
          { success: false, error: "Unknown test type: #{test[:type]}" }
        end
      end
      
      def check_window_exists(title)
        result = @environment.execute("swaymsg -t get_tree | jq -r '.. | .name?' | grep -F '#{title}'")
        {
          success: result[:exit_code] == 0,
          message: result[:exit_code] == 0 ? "Window found" : "Window not found"
        }
      end
      
      def check_screenshot_contains(screenshot, text)
        return { success: false, error: "No screenshot" } unless screenshot
        
        # Use OCR if available
        result = @environment.execute("which tesseract")
        if result[:exit_code] == 0
          result = @environment.execute("tesseract #{screenshot} - 2>/dev/null | grep -F '#{text}'")
          {
            success: result[:exit_code] == 0,
            message: result[:exit_code] == 0 ? "Text found" : "Text not found"
          }
        else
          { success: false, error: "OCR not available" }
        end
      end
      
      def check_input_response(input, expected)
        # Send input
        result = @environment.execute("wtype '#{input}'")
        return { success: false, error: "Input failed" } unless result[:exit_code] == 0
        
        sleep 1
        
        # Take screenshot and check for expected result
        # This is simplified - real implementation would be more sophisticated
        { success: true, message: "Input sent" }
      end
      
      def detect_capture_tool
        tools = %w[grim wayshot scrot import]
        tools.each do |tool|
          result = @environment.execute("which #{tool}")
          return tool if result[:exit_code] == 0
        end
        'grim'  # Default
      end
      
      def default_test_applications
        [
          {
            name: 'text_editor',
            launch: 'gedit || mousepad || leafpad',
            wait: 3,
            tests: [
              { name: 'window_appears', type: 'window_exists', window_title: 'Untitled' },
              { name: 'has_menu', type: 'screenshot_contains', text: 'File' }
            ],
            cleanup: 'pkill -f "gedit|mousepad|leafpad"'
          },
          {
            name: 'file_manager',
            launch: 'nautilus || thunar || pcmanfm',
            wait: 3,
            tests: [
              { name: 'window_appears', type: 'window_exists', window_title: 'Home' }
            ],
            cleanup: 'pkill -f "nautilus|thunar|pcmanfm"'
          }
        ]
      end
      
      def perform_capture(validator, capture)
        # Setup
        if capture[:setup]
          capture[:setup].each do |cmd|
            @environment.execute(cmd)
          end
        end
        
        # Wait
        sleep(capture[:wait]) if capture[:wait]
        
        # Capture
        validator.capture_screenshot(@environment, capture[:name], capture[:options] || {})
        
        # Cleanup
        if capture[:cleanup]
          capture[:cleanup].each do |cmd|
            @environment.execute(cmd)
          end
        end
      end
      
      def generate_report(results)
        log_info "=" * 60
        log_info "Graphical Desktop Validation Report"
        log_info "=" * 60
        
        results.each do |category, result|
          status = result[:success] ? "PASS" : "FAIL"
          log_info "#{category.to_s.capitalize}: #{status}"
          
          if result[:errors] && !result[:errors].empty?
            log_error "  Errors:"
            result[:errors].each do |error|
              log_error "    - #{error.message}"
            end
          end
          
          if result[:warnings] && !result[:warnings].empty?
            log_warn "  Warnings:"
            result[:warnings].each do |warning|
              log_warn "    - #{warning.message}"
            end
          end
        end
        
        log_info "=" * 60
      end
    end
  end
end

# Example usage:
if __FILE__ == $0
  # This would typically be run from the test runner
  # Here's a standalone example
  
  require_relative '../lib/environments/base'
  
  # Create a mock environment for demonstration
  class LocalEnvironment < MitamaeTest::Environments::Base
    def execute(command, options = {})
      result = `#{command} 2>&1`
      {
        stdout: result,
        stderr: '',
        exit_code: $?.exitstatus
      }
    end
    
    def containerized?
      false
    end
    
    def file_exists?(path)
      File.exist?(path)
    end
    
    def read_file(path)
      File.read(path)
    end
  end
  
  # Run the test
  environment = LocalEnvironment.new('local')
  test = MitamaeTest::Examples::GraphicalDesktopTest.new(
    environment,
    compositor: 'sway',
    headless: true,
    screenshot_dir: '/tmp/graphical-test-screenshots'
  )
  
  results = test.run_full_validation
  
  # Exit with appropriate code
  exit(results.values.all? { |r| r[:success] } ? 0 : 1)
end