module MitamaeTest
  module Environments
    class Base
      include Plugin
      include Logging
      include ErrorHandling
      
      attr_reader :name, :options
      
      def initialize(name, options = {})
        @name = name
        @options = options
        @setup_complete = false
        @error_handler = ErrorHandler.new(error_mode: :fail_fast)
      end
      
      def setup
        raise NotImplementedError, "#{self.class} must implement #setup"
      end
      
      def teardown
        raise NotImplementedError, "#{self.class} must implement #teardown"
      end
      
      def execute(command, timeout: nil)
        raise NotImplementedError, "#{self.class} must implement #execute"
      end
      
      def copy_file(source, destination)
        raise NotImplementedError, "#{self.class} must implement #copy_file"
      end
      
      def file_exists?(path)
        raise NotImplementedError, "#{self.class} must implement #file_exists?"
      end
      
      def read_file(path)
        raise NotImplementedError, "#{self.class} must implement #read_file"
      end
      
      def write_file(path, content)
        raise NotImplementedError, "#{self.class} must implement #write_file"
      end
      
      def package_installed?(package_name)
        raise NotImplementedError, "#{self.class} must implement #package_installed?"
      end
      
      def service_running?(service_name)
        raise NotImplementedError, "#{self.class} must implement #service_running?"
      end
      
      def ready?
        @setup_complete
      end
      
      def cleanup
        safe_execute("cleanup environment") do
          teardown if ready?
        end
      rescue TestError => e
        log_error "Failed to cleanup environment: #{e.message}"
        # Don't re-raise cleanup errors
      end
      
      def with_retry(description, options = {}, &block)
        retry_handler = RetryHandler.new(options)
        retry_handler.retry_on_failure do |attempt|
          log_debug "#{description} (attempt #{attempt})"
          yield
        end
      end
      
      protected
      
      def mark_ready!
        @setup_complete = true
      end
      
      def mark_not_ready!
        @setup_complete = false
      end
    end
  end
end