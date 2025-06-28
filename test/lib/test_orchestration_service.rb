# frozen_string_literal: true

module MitamaeTest
  # Service class responsible for orchestrating parallel and sequential test execution
  class TestOrchestrationService
    include Logging
    include ErrorHandling

    def initialize(parallel_workers:, reporter:, aggregator:)
      @parallel_workers = parallel_workers
      @reporter = reporter
      @aggregator = aggregator
      @execution_service = nil
    end

    def run_tests(test_specs, environment_manager)
      @execution_service = TestExecutionService.new(environment_manager, @reporter)
      
      log_info "Starting test run with #{test_specs.size} specs"
      log_info "Parallel workers: #{@parallel_workers}"

      spec_groups = group_specs_by_execution_strategy(test_specs)
      results = []

      spec_groups.each do |group_name, specs|
        group_results = execute_spec_group(group_name, specs)
        results.concat(group_results)
      end

      results
    end

    private

    def group_specs_by_execution_strategy(specs)
      groups = { sequential: [] }

      specs.each do |spec|
        if spec.parallel_group
          groups[spec.parallel_group] ||= []
          groups[spec.parallel_group] << spec
        else
          groups[:sequential] << spec
        end
      end

      groups
    end

    def execute_spec_group(group_name, specs)
      if group_name == :sequential || @parallel_workers == 1
        run_sequential_tests(specs)
      else
        run_parallel_tests(specs, group_name)
      end
    end

    def run_sequential_tests(specs)
      log_debug "Running #{specs.size} specs sequentially"
      
      specs.map do |spec|
        @execution_service.execute_test(spec)
      end
    end

    def run_parallel_tests(specs, group_name)
      log_debug "Running #{specs.size} specs in parallel group: #{group_name}"

      thread_pool = Concurrent::FixedThreadPool.new(@parallel_workers)
      futures = create_test_futures(specs, thread_pool)
      
      wait_for_completion(futures)
      results = collect_results(futures)
      
      ensure_pool_shutdown(thread_pool)
      results
    end

    def create_test_futures(specs, thread_pool)
      specs.map do |spec|
        Concurrent::Future.execute(executor: thread_pool) do
          @execution_service.execute_test(spec)
        end
      end
    end

    def wait_for_completion(futures)
      futures.each(&:wait)
    end

    def collect_results(futures)
      results = []
      
      futures.each do |future|
        if future.rejected?
          log_error "Parallel execution failed: #{future.reason}"
        else
          results << future.value
        end
      end
      
      results
    end

    def ensure_pool_shutdown(thread_pool)
      thread_pool.shutdown
      thread_pool.wait_for_termination
    end
  end
end