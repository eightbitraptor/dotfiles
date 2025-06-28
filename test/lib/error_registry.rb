# frozen_string_literal: true

module MitamaeTest
  # Registry for error types and their handling strategies
  class ErrorRegistry
    include Singleton

    def initialize
      @error_mappings = {}
      @recovery_strategies = {}
      register_default_mappings
    end

    def register_error_mapping(source_error_class, target_error_class, recoverable: false)
      @error_mappings[source_error_class] = {
        target_class: target_error_class,
        recoverable: recoverable
      }
    end

    def register_recovery_strategy(error_class, &block)
      @recovery_strategies[error_class] = block
    end

    def map_error(error, context = {})
      mapping = find_error_mapping(error.class)
      
      if mapping
        mapping[:target_class].new(
          error.message,
          details: context.merge(original_error: error.class.name),
          recoverable: mapping[:recoverable]
        )
      else
        Errors::TestError.new(
          error.message,
          details: context.merge(original_error: error.class.name),
          recoverable: false
        )
      end
    end

    def find_recovery_strategy(error_class)
      # Try exact match first
      return @recovery_strategies[error_class] if @recovery_strategies[error_class]
      
      # Try superclass matches
      error_class.ancestors.each do |ancestor_class|
        strategy = @recovery_strategies[ancestor_class]
        return strategy if strategy
      end
      
      nil
    end

    private

    def find_error_mapping(error_class)
      # Try exact match first
      return @error_mappings[error_class] if @error_mappings[error_class]
      
      # Try superclass matches
      error_class.ancestors.each do |ancestor_class|
        mapping = @error_mappings[ancestor_class]
        return mapping if mapping
      end
      
      nil
    end

    def register_default_mappings
      # File system errors
      register_error_mapping(Errno::ENOENT, Errors::ResourceError, recoverable: true)
      register_error_mapping(Errno::EACCES, Errors::ResourceError, recoverable: false)
      register_error_mapping(Errno::EEXIST, Errors::ResourceError, recoverable: true)
      
      # Network errors
      register_error_mapping(Errno::ECONNREFUSED, Errors::NetworkError, recoverable: true)
      register_error_mapping(Errno::EHOSTUNREACH, Errors::NetworkError, recoverable: true)
      register_error_mapping(Errno::ETIMEDOUT, Errors::NetworkError, recoverable: true)
      
      # System errors
      register_error_mapping(SystemCallError, Errors::EnvironmentError, recoverable: true)
      register_error_mapping(Timeout::Error, Errors::TimeoutError, recoverable: true)
      
      # Configuration errors
      register_error_mapping(ArgumentError, Errors::ConfigurationError, recoverable: false)
      register_error_mapping(JSON::ParserError, Errors::InvalidConfigurationError, recoverable: false)
      register_error_mapping(YAML::SyntaxError, Errors::InvalidConfigurationError, recoverable: false)
      
      # Ruby runtime errors
      register_error_mapping(NoMethodError, Errors::ExecutionError, recoverable: false)
      register_error_mapping(NameError, Errors::ExecutionError, recoverable: false)
      register_error_mapping(LoadError, Errors::PluginLoadError, recoverable: false)
      
      register_default_recovery_strategies
    end

    def register_default_recovery_strategies
      # Retry strategy for timeout errors
      register_recovery_strategy(Errors::TimeoutError) do |error|
        sleep(1)
        :retry
      end
      
      # Cleanup strategy for resource errors
      register_recovery_strategy(Errors::ResourceError) do |error|
        # Attempt to clean up and continue
        :continue
      end
      
      # Reconnection strategy for network errors
      register_recovery_strategy(Errors::NetworkError) do |error|
        sleep(2)
        :retry
      end
    end
  end
end