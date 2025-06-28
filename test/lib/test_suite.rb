module MitamaeTest
  class TestSuite
    include Logging
    
    attr_reader :name, :specs, :results, :status, :start_time, :end_time
    
    def initialize(name = "Test Suite")
      @name = name
      @specs = []
      @results = {}
      @status = :not_started
      @filters = []
      @dependency_resolver = DependencyResolver.new
      @test_runner = nil
    end
    
    def add_spec(spec)
      @specs << spec unless @specs.any? { |s| s.name == spec.name }
    end
    
    def add_specs(specs)
      specs.each { |spec| add_spec(spec) }
    end
    
    def add_filter(filter)
      @filters << filter
    end
    
    def filtered_specs
      return @specs if @filters.empty?
      
      @specs.select do |spec|
        @filters.all? { |filter| filter.matches?(spec) }
      end
    end
    
    def run(options = {})
      @start_time = Time.now
      @status = :running
      
      # Apply filters
      specs_to_run = filtered_specs
      
      if specs_to_run.empty?
        log_warn "No specs match the current filters"
        @status = :completed
        @end_time = Time.now
        return
      end
      
      log_info "Running test suite: #{@name}"
      log_info "Total specs: #{@specs.size}, Filtered: #{specs_to_run.size}"
      
      # Resolve dependencies
      ordered_specs = @dependency_resolver.resolve(specs_to_run)
      
      if @dependency_resolver.errors.any?
        log_error "Dependency resolution failed:"
        @dependency_resolver.errors.each { |error| log_error "  - #{error}" }
        @status = :failed
        @end_time = Time.now
        return
      end
      
      # Create test runner
      @test_runner = TestRunner.new(options)
      
      # Run tests
      begin
        test_results = @test_runner.run(ordered_specs)
        
        # Store results
        test_results.each do |result|
          @results[result.test_spec.name] = result
        end
        
        # Determine overall status
        @status = determine_suite_status
      rescue StandardError => e
        log_error "Test suite failed: #{e.message}"
        @status = :error
        raise
      ensure
        @end_time = Time.now
      end
    end
    
    def rerun_failed(options = {})
      failed_specs = failed_test_specs
      
      return log_info("No failed tests to rerun") if failed_specs.empty?
      
      log_info "Rerunning #{failed_specs.size} failed tests"
      
      runner = TestRunner.new(options)
      rerun_results = runner.run(failed_specs)
      
      update_results(rerun_results)
      @status = determine_suite_status
    end

    private

    def failed_test_specs
      @results.values
              .select { |result| %i[failed error].include?(result.status) }
              .map(&:test_spec)
    end

    def update_results(new_results)
      new_results.each { |result| @results[result.test_spec.name] = result }
    end
    
    def summary
      status_counts = @results.values.group_by(&:status).transform_values(&:count)
      total = @results.size
      passed = status_counts[:passed] || 0
      
      {
        name: @name,
        status: @status,
        total: total,
        passed: passed,
        failed: status_counts[:failed] || 0,
        skipped: status_counts[:skipped] || 0,
        errors: status_counts[:error] || 0,
        duration: duration,
        pass_rate: total.positive? ? (passed.to_f / total * 100).round(2) : 0
      }
    end
    
    def detailed_results
      @results.map do |name, result|
        {
          name: name,
          status: result.status,
          duration: result.duration,
          message: result.message,
          tags: result.test_spec.tags,
          validators: result.validation_results.map do |v|
            {
              type: v.class.plugin_name,
              success: v.success?,
              errors: v.errors.size,
              warnings: v.warnings.size
            }
          end
        }
      end
    end
    
    def failed_tests
      @results.select { |_, result| %i[failed error].include?(result.status) }
    end
    
    def passed_tests
      @results.select { |_, result| result.status == :passed }
    end
    
    def skipped_tests
      @results.select { |_, result| result.status == :skipped }
    end
    
    def duration
      return 0 unless @start_time && @end_time
      @end_time - @start_time
    end
    
    def to_junit_xml
      require 'rexml/document'
      
      doc = REXML::Document.new
      testsuite = doc.add_element('testsuite')
      
      summary_data = summary
      testsuite.add_attribute('name', @name)
      testsuite.add_attribute('tests', summary_data[:total])
      testsuite.add_attribute('failures', summary_data[:failed])
      testsuite.add_attribute('errors', summary_data[:errors])
      testsuite.add_attribute('skipped', summary_data[:skipped])
      testsuite.add_attribute('time', duration.round(3))
      
      @results.each do |name, result|
        testcase = testsuite.add_element('testcase')
        testcase.add_attribute('name', name)
        testcase.add_attribute('classname', result.test_spec.tags.join('.'))
        testcase.add_attribute('time', result.duration.round(3))
        
        case result.status
        when :failed
          failure = testcase.add_element('failure')
          failure.add_attribute('message', result.message || 'Test failed')
          failure.add_text(format_failure_details(result))
        when :error
          error = testcase.add_element('error')
          error.add_attribute('message', result.message || 'Test error')
          error.add_text(result.error&.backtrace&.join("\n") || '')
        when :skipped
          skipped = testcase.add_element('skipped')
          skipped.add_attribute('message', result.message || 'Test skipped')
        end
      end
      
      doc.to_s
    end
    
    private
    
    def determine_suite_status
      return :completed if @results.empty?
      
      statuses = @results.values.map(&:status)
      
      case
      when statuses.include?(:error)
        :error
      when statuses.include?(:failed)
        :failed
      when statuses.all? { |status| %i[passed skipped].include?(status) }
        :passed
      else
        :completed
      end
    end
    
    def format_failure_details(result)
      details = []
      
      result.validation_results.each do |validator|
        next if validator.success?
        
        details << "Validator: #{validator.class.plugin_name}"
        validator.errors.each do |error|
          details << "  ERROR: #{error.message}"
          if error.details && !error.details.empty?
            details << "    Details: #{error.details.inspect}"
          end
        end
      end
      
      details.join("\n")
    end
  end
  
  class TestStatusTracker
    include Singleton
    
    def initialize
      @suites = {}
      @current_suite = nil
    end
    
    def create_suite(name)
      suite = TestSuite.new(name)
      @suites[name] = suite
      @current_suite = suite
      suite
    end
    
    def get_suite(name)
      @suites[name]
    end
    
    def current_suite
      @current_suite
    end
    
    def all_suites
      @suites.values
    end
    
    def overall_summary
      total_specs = 0
      total_passed = 0
      total_failed = 0
      total_skipped = 0
      total_errors = 0
      total_duration = 0
      
      @suites.each do |_, suite|
        summary = suite.summary
        total_specs += summary[:total]
        total_passed += summary[:passed]
        total_failed += summary[:failed]
        total_skipped += summary[:skipped]
        total_errors += summary[:errors]
        total_duration += summary[:duration]
      end
      
      {
        suites: @suites.size,
        total_specs: total_specs,
        passed: total_passed,
        failed: total_failed,
        skipped: total_skipped,
        errors: total_errors,
        duration: total_duration,
        pass_rate: total_specs > 0 ? (total_passed.to_f / total_specs * 100).round(2) : 0
      }
    end
    
    def clear
      @suites.clear
      @current_suite = nil
    end
  end
end