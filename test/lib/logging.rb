require 'logger'
require 'singleton'

module MitamaeTest
  class LogManager
    include Singleton
    
    LEVELS = {
      debug: Logger::DEBUG,
      info: Logger::INFO,
      warn: Logger::WARN,
      error: Logger::ERROR,
      fatal: Logger::FATAL
    }.freeze
    
    attr_reader :logger, :level
    
    def initialize
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
      @level = :info
      @outputs = [STDOUT]
      configure_formatter
    end
    
    def configure(level: nil, format: nil, outputs: nil)
      self.level = level if level
      self.format = format if format
      add_outputs(outputs) if outputs
    end
    
    def level=(new_level)
      new_level = new_level.to_sym if new_level.is_a?(String)
      
      unless LEVELS.key?(new_level)
        raise ArgumentError, "Invalid log level: #{new_level}"
      end
      
      @level = new_level
      @logger.level = LEVELS[new_level]
    end
    
    def format=(format_type)
      @format_type = format_type
      configure_formatter
    end
    
    def add_output(output)
      case output
      when String
        @outputs << File.open(output, 'a')
      when IO
        @outputs << output
      else
        raise ArgumentError, "Invalid output type: #{output.class}"
      end
      
      recreate_logger
    end
    
    def add_outputs(outputs)
      Array(outputs).each { |output| add_output(output) }
    end
    
    def debug(message = nil, &block)
      @logger.debug(message, &block)
    end
    
    def info(message = nil, &block)
      @logger.info(message, &block)
    end
    
    def warn(message = nil, &block)
      @logger.warn(message, &block)
    end
    
    def error(message = nil, &block)
      @logger.error(message, &block)
    end
    
    def fatal(message = nil, &block)
      @logger.fatal(message, &block)
    end
    
    def with_context(context)
      old_formatter = @logger.formatter
      @logger.formatter = create_context_formatter(context)
      yield
    ensure
      @logger.formatter = old_formatter
    end
    
    def silence
      old_level = @logger.level
      @logger.level = Logger::FATAL + 1
      yield
    ensure
      @logger.level = old_level
    end
    
    private
    
    def recreate_logger
      if @outputs.size == 1
        @logger = Logger.new(@outputs.first)
      else
        # Create a multi-output logger
        @logger = Logger.new(MultiIO.new(*@outputs))
      end
      
      @logger.level = LEVELS[@level]
      configure_formatter
    end
    
    def configure_formatter
      @logger.formatter = case @format_type
      when :simple
        simple_formatter
      when :detailed
        detailed_formatter
      when :json
        json_formatter
      else
        detailed_formatter
      end
    end
    
    def simple_formatter
      proc do |severity, datetime, progname, msg|
        "#{severity[0]}: #{msg}\n"
      end
    end
    
    def detailed_formatter
      proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} -- #{msg}\n"
      end
    end
    
    def json_formatter
      require 'json'
      proc do |severity, datetime, progname, msg|
        {
          timestamp: datetime.iso8601,
          level: severity,
          message: msg,
          program: progname
        }.to_json + "\n"
      end
    end
    
    def create_context_formatter(context)
      proc do |severity, datetime, progname, msg|
        base = @logger.formatter.call(severity, datetime, progname, msg).chomp
        "#{base} [#{context}]\n"
      end
    end
  end
  
  # Multi-output IO class for logging to multiple destinations
  class MultiIO
    def initialize(*targets)
      @targets = targets
    end
    
    def write(*args)
      @targets.each { |t| t.write(*args) }
    end
    
    def close
      @targets.each(&:close)
    end
    
    def flush
      @targets.each(&:flush)
    end
  end
  
  # Convenience module for including logging in classes
  module Logging
    def logger
      LogManager.instance.logger
    end
    
    def log_debug(message = nil, &block)
      LogManager.instance.debug(message, &block)
    end
    
    def log_info(message = nil, &block)
      LogManager.instance.info(message, &block)
    end
    
    def log_warn(message = nil, &block)
      LogManager.instance.warn(message, &block)
    end
    
    def log_error(message = nil, &block)
      LogManager.instance.error(message, &block)
    end
    
    def log_fatal(message = nil, &block)
      LogManager.instance.fatal(message, &block)
    end
  end
end