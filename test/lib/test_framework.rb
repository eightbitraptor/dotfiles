# frozen_string_literal: true

# Core test framework module for mitamae recipe testing
# Provides foundational classes and utilities for the testing system

require_relative 'version'
require 'singleton'

module MitamaeTest
  # Framework configuration and initialization
  class Framework
    include Singleton
    
    attr_accessor :root_path

    def initialize
      @root_path = detect_root_path
      @initialized = false
    end

    def initialize!
      return if @initialized
      
      setup_load_paths
      load_core_components
      @initialized = true
    end
    
    def setup_load_paths
      lib_path = File.join(@root_path, 'lib')
      $LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)
    end
    
    def config
      Configuration.instance
    end
    
    def logger
      LogManager.instance.logger
    end
    
    def plugin_manager
      PluginManager.instance
    end
    
    private
    
    def detect_root_path
      # Try to find the test directory
      current = File.expand_path('../..', __dir__)
      
      # Look for the test directory marker files
      while current != '/'
        if File.exist?(File.join(current, 'runner.rb')) ||
           File.exist?(File.join(current, 'lib', 'test_framework.rb'))
          return current
        end
        current = File.dirname(current)
      end
      
      # Default to parent of lib directory
      File.expand_path('../..', __dir__)
    end
    
    def load_core_components
      require_relative 'logging'
      require_relative 'configuration'
      require_relative 'plugin_manager'
      require_relative 'error_handler'
      
      # Load base classes
      require_relative 'environments/base'
      require_relative 'validators/base'
      require_relative 'reporters/base'
      
      # Load validation framework
      require_relative 'validation_aggregator'
      
      # Load built-in validators
      require_relative 'validators/configuration_file_validator'
      require_relative 'validators/idempotency_validator'
      require_relative 'validators/functional_test_validator'
      
      # Load test execution framework
      require_relative 'test_spec'
      require_relative 'test_spec_loader'
      require_relative 'test_runner'
      require_relative 'dependency_resolver'
      require_relative 'test_suite'
      require_relative 'test_filter_builder'
      
      # Load reporting and analysis
      require_relative 'reporters/enhanced_console_reporter'
      require_relative 'reporters/detailed_html_reporter'
      require_relative 'test_cache'
      require_relative 'coverage_reporter'
      require_relative 'test_history'
      
      # Register built-in validators
      register_builtin_validators
      
      # Apply extensions
      apply_framework_extensions
    end
    
    def register_builtin_validators
      pm = PluginManager.instance
      
      # Register validators
      pm.register(:validator, :configuration_file, Validators::ConfigurationFileValidator)
      pm.register(:validator, :idempotency, Validators::IdempotencyValidator)
      pm.register(:validator, :functional_test, Validators::FunctionalTestValidator)
      
      # Register the aggregated reporter
      pm.register(:reporter, :aggregated, AggregatedReporter)
      
      # Register enhanced reporters
      pm.register(:reporter, :enhanced_console, Reporters::EnhancedConsoleReporter)
      pm.register(:reporter, :detailed_html, Reporters::DetailedHtmlReporter)
    end
    
    def apply_framework_extensions
      # Apply test runner extensions
      TestRunner.prepend(CacheableTestRunner)
      TestRunner.prepend(HistoricalTestRunner)
    end
  end
end

# Auto-initialize when required
MitamaeTest::Framework.instance.initialize!