#!/usr/bin/env ruby
# frozen_string_literal: true

# Main test orchestration script for mitamae recipe testing
# Coordinates local test execution across environments and validators

require_relative 'lib/test_framework'
require_relative 'lib/test_modes'
require_relative 'lib/interactive_debugger'
require_relative 'lib/notification_system'

module MitamaeTest
  # Main runner class that orchestrates test execution
  class Runner
    include Logging
    include ErrorHandling
    
    def initialize(args = ARGV)
      @args = args
      @options = parse_options(args)
      @framework = Framework.instance
      @error_handler = ErrorHandler.new(error_mode: :fail_fast)
    end

    def run
      if @options[:help]
        show_help
        return 0
      end
      
      configure_framework
      show_banner unless @options[:quiet]
      
      with_error_handling(mode: :fail_fast) do |handler|
        # Set up error callbacks
        handler.add_callback do |error|
          if error.is_a?(ConfigurationError)
            log_error "Configuration problem detected. Check your config file."
          elsif error.is_a?(PluginError)
            log_error "Plugin loading failed. Ensure all dependencies are installed."
          end
        end
        
        # Load configuration with error handling
        safe_execute("load configuration") do
          config = @framework.config
          config.load(@options[:config])
        end
        
        # Configure logging
        config = @framework.config
        log_level = @options[:verbose] ? :debug : config.get('logging.level', :info)
        LogManager.instance.configure(level: log_level)
        
        # Load plugins with retry mechanism
        retry_handler = RetryHandler.new(max_attempts: 2, on: [PluginError])
        retry_handler.retry_on_failure do
          @framework.plugin_manager.load_plugins
        end
        
        # Load test specifications
        loader = TestSpecLoader.new
        spec_paths = @options[:specs] || [File.join(@framework.root_path, 'specs')]
        loader.load_specs(spec_paths)
        
        if loader.has_errors?
          log_error loader.error_summary
          return 3
        end
        
        # Create test suite
        suite = TestSuite.new("Mitamae Test Run")
        suite.add_specs(loader.all_specs)
        
        # Apply filters
        if @options[:filter_options]
          filter = TestFilterBuilder.parse_cli_args(@options[:filter_options])
          suite.add_filter(filter)
        end
        
        # Configure coverage reporting if requested
        coverage_reporter = nil
        if @options[:coverage]
          coverage_reporter = CoverageReporter.new
          coverage_reporter.start_coverage
        end
        
        # Run tests
        runner_options = {
          parallel_workers: config.get('parallel_workers', 4),
          reporter: determine_reporter,
          use_cache: !@options[:no_cache],
          track_history: !@options[:no_history]
        }
        
        suite.run(runner_options)
        
        # Generate coverage report if enabled
        if coverage_reporter
          coverage_reporter.finish_coverage
          
          case @options[:coverage_format]
          when 'html'
            File.write('coverage-report.html', coverage_reporter.to_html)
            log_info "Coverage report saved to: coverage-report.html"
          else
            puts coverage_reporter.generate_report[:summary]
          end
        end
        
        # Display results
        unless @options[:quiet]
          puts "\n" + "="*60
          summary = suite.summary
          puts "Test Run Complete"
          puts "Total: #{summary[:total]}"
          puts "Passed: #{summary[:passed]} (#{summary[:pass_rate]}%)"
          puts "Failed: #{summary[:failed]}"
          puts "Skipped: #{summary[:skipped]}"
          puts "Duration: #{summary[:duration].round(2)}s"
          puts "="*60
        end
        
        # Return appropriate exit code
        suite.status == :passed ? 0 : 1
      end
    rescue TestError => e
      log_fatal "Fatal error: #{e.message}"
      log_debug "Error details: #{e.details}" if e.details && !e.details.empty?
      1
    rescue StandardError => e
      log_fatal "Unexpected error: #{e.message}"
      log_debug e.backtrace.join("\n")
      2
    end

    private

    def parse_options(args)
      options = default_options
      parser = create_option_parser(options)
      
      begin
        parser.parse!(args)
      rescue OptionParser::InvalidOption => e
        puts "Error: #{e.message}"
        puts parser
        exit 1
      end
      
      options
    end

    def default_options
      {
        help: false,
        verbose: false,
        environment: 'container',
        distribution: 'arch',
        config: nil,
        quiet: false,
        specs: [],
        reporter: nil,
        coverage: false,
        coverage_format: nil,
        no_cache: false,
        no_history: false,
        interactive_debug: false,
        notifications: true,
        notification_config: nil,
        filter_options: []
      }
    end

    def configure_general_options(opts, options)
      opts.banner = "Usage: ruby test/runner.rb [OPTIONS]"
      opts.separator ""
      opts.separator "General Options:"
      
      opts.on('-h', '--help', 'Show this help message') { options[:help] = true }
      opts.on('-v', '--verbose', 'Enable verbose output') { options[:verbose] = true }
      opts.on('-q', '--quiet', 'Suppress banner and non-essential output') { options[:quiet] = true }
      opts.on('--config FILE', 'Path to configuration file') { |f| options[:config] = f }
    end

    def configure_test_selection_options(opts, options)
      opts.separator ""
      opts.separator "Test Selection:"
      
      opts.on('--spec PATH', 'Path to test spec file or directory (can be used multiple times)') do |path|
        options[:specs] << path
      end
      opts.on('--tag TAG', 'Run tests with specified tag') { |tag| add_filter_option(options, "--tag=#{tag}") }
      opts.on('--name PATTERN', 'Run tests matching name pattern') { |pattern| add_filter_option(options, "--name=#{pattern}") }
      opts.on('--exclude-tag TAG', 'Exclude tests with specified tag') { |tag| add_filter_option(options, "--exclude-tag=#{tag}") }
    end

    def configure_environment_options(opts, options)
      opts.separator ""
      opts.separator "Environment Options:"
      
      opts.on('--env ENV', %w[container vm local], 'Test environment (container, vm, local)') { |env| options[:environment] = env }
      opts.on('--distro DISTRO', %w[arch ubuntu fedora], 'Target distribution (arch, ubuntu, fedora)') { |distro| options[:distribution] = distro }
    end

    def configure_reporting_options(opts, options)
      opts.separator ""
      opts.separator "Reporting:"
      
      opts.on('--reporter TYPE', %w[console json html aggregated], 'Reporter type') { |type| options[:reporter] = type }
      opts.on('--coverage', 'Enable test coverage reporting') { options[:coverage] = true }
      opts.on('--coverage-format FORMAT', %w[console html], 'Coverage report format') { |format| options[:coverage_format] = format }
    end

    def configure_debugging_options(opts, options)
      opts.separator ""
      opts.separator "Debugging & Notifications:"
      
      opts.on('-d', '--debug', 'Enable interactive debugging for failed tests') { options[:interactive_debug] = true }
      opts.on('--no-notifications', 'Disable completion notifications') { options[:notifications] = false }
      opts.on('--notify-config FILE', 'Path to notification configuration file') { |f| options[:notification_config] = f }
    end

    def configure_performance_options(opts, options)
      opts.separator ""
      opts.separator "Performance & Caching:"
      
      opts.on('--no-cache', 'Disable test result caching') { options[:no_cache] = true }
      opts.on('--no-history', 'Disable test history tracking') { options[:no_history] = true }
      opts.on('--failed', 'Run only previously failed tests') { add_filter_option(options, '--failed') }
      opts.on('--quick', 'Run only quick tests (under 60s)') { add_filter_option(options, '--quick') }
    end

    def add_filter_option(options, filter)
      options[:filter_options] << filter
    end
    
    def configure_framework
      # Set options in configuration
      config = @framework.config
      config.set('environments.default', @options[:environment])
      config.set('distributions.default', @options[:distribution])
    end
    
    def show_banner
      unless @options[:quiet]
        puts "Mitamae Recipe Testing Framework v#{VERSION}"
        puts "=" * 40
        puts
      end
    end

    def show_help
      parser = create_option_parser
      puts parser
      puts ""
      puts "Examples:"
      puts "  # Run all tests"
      puts "  ruby test/runner.rb"
      puts ""
      puts "  # Run tests for specific distribution"
      puts "  ruby test/runner.rb --distro ubuntu"
      puts ""
      puts "  # Run with interactive debugging enabled"
      puts "  ruby test/runner.rb --debug"
      puts ""
      puts "  # Run with coverage reporting"
      puts "  ruby test/runner.rb --coverage --coverage-format html"
      puts ""
      puts "  # Run tests with specific tags"
      puts "  ruby test/runner.rb --tag core --tag packages"
      puts ""
      puts "  # Run specific test spec"
      puts "  ruby test/runner.rb --spec specs/packages_spec.yml"
      puts ""
      puts "  # Rerun failed tests"
      puts "  ruby test/runner.rb --failed"
    end

    def create_option_parser(options = nil)
      require 'optparse'
      options ||= default_options
      
      OptionParser.new do |opts|
        configure_general_options(opts, options)
        configure_test_selection_options(opts, options)
        configure_environment_options(opts, options)
        configure_reporting_options(opts, options)
        configure_debugging_options(opts, options)
        configure_performance_options(opts, options)
      end
    end
  end
end

# Allow direct execution
if __FILE__ == $0
  runner = MitamaeTest::Runner.new
  exit runner.run
end