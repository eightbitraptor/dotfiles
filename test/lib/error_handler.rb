require 'singleton'
require 'json'

module MitamaeTest
  module Errors
    # Base error class for all framework errors
    class TestError < StandardError
      attr_reader :details, :recoverable, :error_code
      
      def initialize(message, details: {}, recoverable: false, error_code: nil)
        super(message)
        @details = details
        @recoverable = recoverable
        @error_code = error_code || self.class.default_error_code
      end
      
      def self.default_error_code
        name.split('::').last.downcase
      end
      
      def to_h
        {
          error: self.class.name,
          error_code: @error_code,
          message: message,
          details: @details,
          recoverable: @recoverable,
          backtrace: backtrace&.first(5)
        }
      end
      
      def inspect
        "#<#{self.class.name}: #{message}>"
      end
    end
    
    # Configuration-related errors
    class ConfigurationError < TestError
      def self.default_error_code
        'config_error'
      end
    end
    
    class InvalidConfigurationError < ConfigurationError; end
    class MissingConfigurationError < ConfigurationError; end
    
    # Plugin-related errors  
    class PluginError < TestError
      def self.default_error_code
        'plugin_error'
      end
    end
    
    class PluginLoadError < PluginError; end
    class PluginNotFoundError < PluginError; end
    class PluginInitializationError < PluginError; end
    
    # Environment-related errors
    class EnvironmentError < TestError
      def self.default_error_code
        'environment_error'
      end
    end
    
    class EnvironmentSetupError < EnvironmentError; end
    class EnvironmentTeardownError < EnvironmentError; end
    class ContainerError < EnvironmentError; end
    class NetworkError < EnvironmentError; end
    
    # Validation-related errors
    class ValidationError < TestError
      def self.default_error_code
        'validation_error'
      end
    end
    
    class ValidatorNotFoundError < ValidationError; end
    class ValidationFailureError < ValidationError; end
    
    # Execution-related errors
    class ExecutionError < TestError
      def self.default_error_code
        'execution_error'
      end
    end
    
    class CommandExecutionError < ExecutionError; end
    class RecipeExecutionError < ExecutionError; end
    class TimeoutError < ExecutionError; end
    
    # Dependency-related errors
    class DependencyError < TestError
      def self.default_error_code
        'dependency_error'
      end
    end
    
    class CircularDependencyError < DependencyError; end
    class MissingDependencyError < DependencyError; end
    
    # Resource-related errors
    class ResourceError < TestError
      def self.default_error_code
        'resource_error'
      end
    end
    
    class InsufficientResourcesError < ResourceError; end
    class ResourceCleanupError < ResourceError; end
  end
  
  # Include all error classes in the main namespace for backward compatibility
  include Errors
  
  # Error handler for graceful failure management
  class ErrorHandler
    include Logging
    
    attr_reader :errors, :error_mode
    
    def initialize(error_mode: :fail_fast)
      @errors = []
      @error_mode = error_mode
      @error_callbacks = []
      require_relative 'error_registry'
      @error_registry = ErrorRegistry.instance
    end
    
    def handle_error(error, context: {})
      wrapped_error = wrap_error(error, context)
      @errors << wrapped_error
      
      log_error_details(wrapped_error)
      execute_callbacks(wrapped_error)
      
      case @error_mode
      when :fail_fast
        raise wrapped_error unless wrapped_error.recoverable
      when :continue
        attempt_recovery(wrapped_error)
      when :collect
        # Just collect errors, don't raise
      end
      
      wrapped_error
    end
    
    def wrap(&block)
      block.call
    rescue StandardError => e
      handle_error(e, context: { block: block.source_location })
    end
    
    def add_callback(&block)
      @error_callbacks << block
    end
    
    def register_recovery(error_class, &strategy)
      @error_registry.register_recovery_strategy(error_class, &strategy)
    end
    
    def clear_errors
      @errors.clear
    end
    
    def has_errors?
      !@errors.empty?
    end
    
    def fatal_errors
      @errors.reject(&:recoverable)
    end
    
    def recoverable_errors
      @errors.select(&:recoverable)
    end
    
    def error_summary
      {
        total: @errors.size,
        fatal: fatal_errors.size,
        recoverable: recoverable_errors.size,
        by_type: @errors.group_by(&:class).transform_values(&:size)
      }
    end
    
    private
    
    def wrap_error(error, context)
      return error if error.is_a?(Errors::TestError)
      @error_registry.map_error(error, context)
    end
    
    def log_error_details(error)
      log_error "#{error.class.name}: #{error.message}"
      
      if error.details && !error.details.empty?
        log_debug "Error details: #{error.details.inspect}"
      end
      
      if error.backtrace
        log_debug "Backtrace:"
        error.backtrace.first(5).each { |line| log_debug "  #{line}" }
      end
    end
    
    def execute_callbacks(error)
      @error_callbacks.each do |callback|
        begin
          callback.call(error)
        rescue StandardError => e
          log_warn "Error in error callback: #{e.message}"
        end
      end
    end
    
    def attempt_recovery(error)
      strategy = @error_registry.find_recovery_strategy(error.class)
      
      if strategy && error.recoverable
        begin
          log_info "Attempting recovery for #{error.class.name}"
          result = strategy.call(error)
          log_info "Recovery result: #{result}"
          result
        rescue StandardError => e
          log_error "Recovery failed: #{e.message}"
          raise error
        end
      elsif !error.recoverable
        raise error
      end
    end
  end
  
  # Global error handling mixin
  module ErrorHandling
    def with_error_handling(mode: :fail_fast, &block)
      handler = ErrorHandler.new(error_mode: mode)
      
      begin
        yield handler
      rescue TestError => e
        handler.handle_error(e)
        raise unless mode == :collect
      ensure
        if handler.has_errors? && mode == :collect
          report_collected_errors(handler)
        end
      end
    end
    
    def safe_execute(description, &block)
      begin
        yield
      rescue StandardError => e
        wrapped = TestError.new("Failed to #{description}: #{e.message}",
                               details: { original_error: e.class.name },
                               recoverable: false)
        wrapped.set_backtrace(e.backtrace)
        raise wrapped
      end
    end
    
    private
    
    def report_collected_errors(handler)
      summary = handler.error_summary
      
      if summary[:fatal] > 0
        log_error "#{summary[:fatal]} fatal errors occurred"
        handler.fatal_errors.each { |e| log_error "  - #{e.message}" }
      end
      
      if summary[:recoverable] > 0
        log_warn "#{summary[:recoverable]} recoverable errors occurred"
      end
    end
  end
  
  # Retry mechanism for flaky operations
  class RetryHandler
    include Logging
    
    DEFAULT_OPTIONS = {
      max_attempts: 3,
      base_delay: 1,
      max_delay: 60,
      exponential_backoff: true,
      jitter: true,
      on: [StandardError]
    }.freeze
    
    def initialize(options = {})
      @options = DEFAULT_OPTIONS.merge(options)
    end
    
    def retry_on_failure(&block)
      attempt = 0
      last_error = nil
      
      while attempt < @options[:max_attempts]
        attempt += 1
        
        begin
          log_debug "Attempt #{attempt}/#{@options[:max_attempts]}"
          return yield(attempt)
        rescue *@options[:on] => e
          last_error = e
          
          if attempt < @options[:max_attempts]
            delay = calculate_delay(attempt)
            log_warn "Attempt #{attempt} failed: #{e.message}. Retrying in #{delay}s..."
            sleep(delay)
          else
            log_error "All #{@options[:max_attempts]} attempts failed"
          end
        end
      end
      
      raise last_error
    end
    
    private
    
    def calculate_delay(attempt)
      if @options[:exponential_backoff]
        delay = @options[:base_delay] * (2 ** (attempt - 1))
      else
        delay = @options[:base_delay]
      end
      
      delay = [delay, @options[:max_delay]].min
      
      if @options[:jitter]
        delay = delay * (0.5 + rand * 0.5)
      end
      
      delay
    end
  end
end