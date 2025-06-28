module MitamaeTest
  module Reporters
    class Base
      include Plugin
      
      attr_reader :options
      
      def initialize(options = {})
        @options = options
        @results = []
      end
      
      def start_suite(test_suite)
        # Override in subclasses for suite start actions
      end
      
      def start_test(test_spec)
        # Override in subclasses for test start actions
      end
      
      def test_passed(test_spec, results)
        @results << TestResult.new(test_spec, :passed, results)
        report_test_result(@results.last)
      end
      
      def test_failed(test_spec, results)
        @results << TestResult.new(test_spec, :failed, results)
        report_test_result(@results.last)
      end
      
      def test_skipped(test_spec, reason)
        @results << TestResult.new(test_spec, :skipped, [], reason: reason)
        report_test_result(@results.last)
      end
      
      def finish_test(test_spec)
        # Override in subclasses for test finish actions
      end
      
      def finish_suite(test_suite)
        report_summary
      end
      
      def report_test_result(result)
        raise NotImplementedError, "#{self.class} must implement #report_test_result"
      end
      
      def report_summary
        raise NotImplementedError, "#{self.class} must implement #report_summary"
      end
      
      def passed_count
        @results.count { |r| r.status == :passed }
      end
      
      def failed_count
        @results.count { |r| r.status == :failed }
      end
      
      def skipped_count
        @results.count { |r| r.status == :skipped }
      end
      
      def total_count
        @results.size
      end
      
      def success?
        failed_count == 0
      end
      
      def duration
        return 0 if @results.empty?
        @results.sum(&:duration)
      end
    end
    
    class TestResult
      attr_reader :test_spec, :status, :validation_results, :metadata, :start_time, :end_time
      
      def initialize(test_spec, status, validation_results = [], metadata = {})
        @test_spec = test_spec
        @status = status
        @validation_results = validation_results
        @metadata = metadata
        @start_time = metadata[:start_time] || Time.now
        @end_time = metadata[:end_time] || Time.now
      end
      
      def duration
        @end_time - @start_time
      end
      
      def errors
        @validation_results.flat_map { |r| r.respond_to?(:errors) ? r.errors : [] }
      end
      
      def warnings
        @validation_results.flat_map { |r| r.respond_to?(:warnings) ? r.warnings : [] }
      end
      
      def to_h
        {
          test: @test_spec.name,
          status: @status,
          duration: duration,
          errors: errors.map(&:to_h),
          warnings: warnings.map(&:to_h),
          metadata: @metadata
        }
      end
    end
  end
end