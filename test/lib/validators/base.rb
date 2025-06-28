module MitamaeTest
  module Validators
    class Base
      include Plugin
      include Logging
      include ErrorHandling
      
      attr_reader :name, :options, :errors, :warnings
      
      def initialize(name = nil, options = {})
        @name = name || self.class.plugin_name
        @options = options
        @errors = []
        @warnings = []
        @error_handler = ErrorHandler.new(error_mode: :collect)
      end
      
      def validate(environment, context = {})
        raise NotImplementedError, "#{self.class} must implement #validate"
      end
      
      def success?
        @errors.empty?
      end
      
      def failed?
        !success?
      end
      
      def add_error(message, details = {})
        @errors << ValidationResult.new(:error, message, details)
      end
      
      def add_warning(message, details = {})
        @warnings << ValidationResult.new(:warning, message, details)
      end
      
      def clear_results
        @errors.clear
        @warnings.clear
      end
      
      def results
        @errors + @warnings
      end
      
      def to_h
        {
          name: @name,
          success: success?,
          errors: @errors.map(&:to_h),
          warnings: @warnings.map(&:to_h)
        }
      end
      
      protected
      
      def execute_command(environment, command, timeout: nil)
        with_error_handling(mode: :continue) do |handler|
          result = environment.execute(command, timeout: timeout)
          CommandResult.new(result[:stdout], result[:stderr], result[:exit_code])
        end
      rescue TestError => e
        log_warn "Command execution failed: #{e.message}"
        CommandResult.new('', e.message, -1)
      end
      
      def check_file(environment, path, &block)
        if environment.file_exists?(path)
          content = environment.read_file(path)
          yield content if block_given?
          true
        else
          false
        end
      end
    end
    
    class ValidationResult
      attr_reader :level, :message, :details
      
      def initialize(level, message, details = {})
        @level = level
        @message = message
        @details = details
        @timestamp = Time.now
      end
      
      def to_h
        {
          level: @level,
          message: @message,
          details: @details,
          timestamp: @timestamp
        }
      end
    end
    
    class CommandResult
      attr_reader :stdout, :stderr, :exit_code
      
      def initialize(stdout, stderr, exit_code)
        @stdout = stdout
        @stderr = stderr
        @exit_code = exit_code
      end
      
      def success?
        @exit_code == 0
      end
      
      def output
        @stdout + @stderr
      end
    end
  end
end