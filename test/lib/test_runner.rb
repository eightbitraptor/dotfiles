require 'thread'
require 'concurrent'
require_relative 'test_execution_service'
require_relative 'test_orchestration_service'

module MitamaeTest
  class TestRunner
    include Logging
    include ErrorHandling
    
    attr_reader :results, :status
    
    def initialize(options = {})
      @options = options
      @results = Concurrent::Array.new
      @status = :not_started
      @aggregator = ValidationAggregator.new
      @parallel_workers = options[:parallel_workers] || detect_optimal_workers
      @reporter = create_reporter(options[:reporter])
      @environment_manager = EnvironmentManager.new
      @orchestration_service = TestOrchestrationService.new(
        parallel_workers: @parallel_workers,
        reporter: @reporter,
        aggregator: @aggregator
      )
    end
    
    def run(test_specs)
      @status = :running
      @aggregator.start
      @reporter.start_suite(test_specs)
      
      begin
        test_results = @orchestration_service.run_tests(test_specs, @environment_manager)
        @results.concat(test_results)
        @status = determine_overall_status
      rescue StandardError => e
        log_error "Test run failed: #{e.message}"
        @status = :error
        raise
      ensure
        @aggregator.finish
        @reporter.finish_suite(test_specs)
        cleanup_environments
      end
      
      @results
    end
    
    def run_single(test_spec)
      execution_service = TestExecutionService.new(@environment_manager, @reporter)
      result = execution_service.execute_test(test_spec)
      @results << result
      result
    end
    
    private

    def determine_overall_status
      @results.all?(&:success) ? :passed : :failed
    end
    
    def detect_optimal_workers
      cpu_count = Concurrent.processor_count
      [cpu_count - 1, 1].max
    end
    
    def create_reporter(reporter_config)
      reporter_type = reporter_config || :console
      
      case reporter_type
      when :aggregated
        AggregatedReporter.new(format: :console)
      when :json
        AggregatedReporter.new(format: :json, output_file: 'test-results.json')
      when :html
        AggregatedReporter.new(format: :html, output_file: 'test-results.html')
      else
        ConsoleReporter.new
      end
    end
    
    def cleanup_environments
      @environment_manager.cleanup_all
    end
  end
  
  class TestResult
    attr_accessor :test_spec, :status, :message, :validation_results, 
                  :start_time, :end_time, :environment, :error
    
    def initialize(test_spec)
      @test_spec = test_spec
      @status = :pending
      @validation_results = []
    end
    
    def start
      @start_time = Time.now
      @status = :running
    end
    
    def finish
      @end_time = Time.now
    end
    
    def pass
      @status = :passed
    end
    
    def fail(message)
      @status = :failed
      @message = message
    end
    
    def skip(reason)
      @status = :skipped
      @message = reason
    end
    
    def error(exception)
      @status = :error
      @error = exception
      @message = exception.message
    end
    
    def success
      @status == :passed
    end
    
    def success?
      success
    end
    
    def duration
      return 0 unless @start_time && @end_time
      @end_time - @start_time
    end
    
    def to_h
      {
        test: @test_spec.name,
        status: @status,
        message: @message,
        duration: duration,
        start_time: @start_time,
        end_time: @end_time,
        validation_results: @validation_results.map(&:to_h),
        error: @error&.message
      }
    end
  end
  
  # Simple console reporter
  class ConsoleReporter < Reporters::Base
    def report_test_result(result)
      status_icon = case result.status
                   when :passed then '✓'
                   when :failed then '✗'
                   when :skipped then '⊘'
                   when :error then '!'
                   else '?'
                   end
      
      status_color = case result.status
                    when :passed then "\e[32m"  # green
                    when :failed, :error then "\e[31m"  # red
                    when :skipped then "\e[33m"  # yellow
                    else "\e[0m"
                    end
      
      reset_color = "\e[0m"
      
      puts "#{status_color}#{status_icon}#{reset_color} #{result.test_spec.name} (#{result.duration.round(2)}s)"
      
      if result.message && result.status != :passed
        puts "  #{result.message}"
      end
    end
    
    def report_summary
      puts "\n" + "="*60
      puts "Test Summary"
      puts "="*60
      puts "Total: #{total_count}"
      puts "Passed: #{passed_count}"
      puts "Failed: #{failed_count}"
      puts "Skipped: #{skipped_count}"
      puts "Duration: #{duration.round(2)}s"
      puts "="*60
    end
  end
  
  # Placeholder for environment manager
  class EnvironmentManager
    def initialize
      @environments = {}
    end
    
    def create(name, type:, distribution:, options: {})
      # This would create actual environment instances
      # For now, return a mock environment
      MockEnvironment.new(name, type, distribution, options)
    end
    
    def destroy(environment)
      # Cleanup environment
    end
    
    def cleanup_all
      # Cleanup all environments
    end
  end
  
  # Mock environment for testing
  class MockEnvironment
    attr_reader :name, :type, :distribution, :options
    
    def initialize(name, type, distribution, options)
      @name = name
      @type = type
      @distribution = distribution
      @options = options
    end
    
    def execute(command, timeout: nil)
      { stdout: '', stderr: '', exit_code: 0 }
    end
    
    def file_exists?(path)
      true
    end
    
    def read_file(path)
      ''
    end
    
    def write_file(path, content)
      true
    end
    
    def copy_file(source, dest)
      true
    end
  end
end