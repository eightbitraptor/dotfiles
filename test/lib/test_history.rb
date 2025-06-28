require 'json'
require 'fileutils'

module MitamaeTest
  class TestHistory
    include Logging
    
    attr_reader :history_dir
    
    def initialize(history_dir = nil)
      @history_dir = history_dir || default_history_dir
      @current_run = nil
      ensure_history_directory
    end
    
    def start_run(suite_name = nil)
      @current_run = {
        id: generate_run_id,
        suite_name: suite_name || 'Test Run',
        start_time: Time.now,
        end_time: nil,
        tests: {},
        summary: {},
        environment: capture_environment,
        git_info: capture_git_info
      }
      
      log_info "Started history tracking for run: #{@current_run[:id]}"
    end
    
    def record_test_result(test_spec, result)
      return unless @current_run
      
      @current_run[:tests][test_spec.name] = {
        status: result.status,
        duration: result.duration,
        tags: test_spec.tags,
        validators: result.validation_results.map { |v| 
          {
            name: v.class.plugin_name,
            success: v.success?,
            error_count: v.errors.size,
            warning_count: v.warnings.size
          }
        },
        timestamp: Time.now
      }
    end
    
    def finish_run(summary = {})
      return unless @current_run
      
      @current_run[:end_time] = Time.now
      @current_run[:summary] = calculate_summary.merge(summary)
      
      save_run(@current_run)
      
      # Keep reference for comparison
      previous_run_id = @current_run[:id]
      @current_run = nil
      
      previous_run_id
    end
    
    def get_run(run_id)
      run_file = File.join(@history_dir, 'runs', "#{run_id}.json")
      return nil unless File.exist?(run_file)
      
      JSON.parse(File.read(run_file), symbolize_names: true)
    end
    
    def list_runs(limit = 10)
      runs = Dir.glob(File.join(@history_dir, 'runs', '*.json'))
               .map { |f| File.basename(f, '.json') }
               .sort
               .reverse
               .first(limit)
      
      runs.map { |run_id| get_run_summary(run_id) }
    end
    
    def compare_runs(run_id1, run_id2)
      run1 = get_run(run_id1)
      run2 = get_run(run_id2)
      
      return nil unless run1 && run2
      
      {
        run1: summarize_run(run1),
        run2: summarize_run(run2),
        comparison: {
          duration_change: calculate_duration_change(run1, run2),
          status_changes: calculate_status_changes(run1, run2),
          new_failures: find_new_failures(run1, run2),
          fixed_tests: find_fixed_tests(run1, run2),
          performance_changes: calculate_performance_changes(run1, run2),
          flaky_tests: find_flaky_tests(run1, run2)
        }
      }
    end
    
    def get_test_history(test_name, limit = 10)
      history = []
      
      list_runs(limit).each do |run_summary|
        run = get_run(run_summary[:id])
        next unless run && run[:tests][test_name]
        
        test_data = run[:tests][test_name]
        history << {
          run_id: run[:id],
          run_date: run[:start_time],
          status: test_data[:status],
          duration: test_data[:duration],
          validator_results: test_data[:validators]
        }
      end
      
      history
    end
    
    def analyze_trends(days = 7)
      cutoff_time = Time.now - (days * 24 * 60 * 60)
      recent_runs = list_runs(100).select { |r| Time.parse(r[:start_time]) > cutoff_time }
      
      {
        total_runs: recent_runs.size,
        success_rate_trend: calculate_success_rate_trend(recent_runs),
        duration_trend: calculate_duration_trend(recent_runs),
        flaky_tests: identify_flaky_tests(recent_runs),
        consistently_failing: identify_consistent_failures(recent_runs),
        performance_regression: identify_performance_regressions(recent_runs)
      }
    end
    
    def generate_history_report
      recent_runs = list_runs(20)
      
      {
        summary: {
          total_runs: count_total_runs,
          date_range: get_date_range,
          most_recent_run: recent_runs.first
        },
        trends: analyze_trends(7),
        test_stability: analyze_test_stability,
        performance_metrics: calculate_performance_metrics,
        generated_at: Time.now
      }
    end
    
    private
    
    def default_history_dir
      File.join(Framework.instance.root_path, '.mitamae-test-history')
    end
    
    def ensure_history_directory
      FileUtils.mkdir_p(@history_dir) unless File.directory?(@history_dir)
      FileUtils.mkdir_p(File.join(@history_dir, 'runs'))
      FileUtils.mkdir_p(File.join(@history_dir, 'reports'))
    end
    
    def generate_run_id
      Time.now.strftime('%Y%m%d_%H%M%S_') + SecureRandom.hex(4)
    end
    
    def capture_environment
      {
        ruby_version: RUBY_VERSION,
        platform: RUBY_PLATFORM,
        mitamae_version: capture_mitamae_version,
        hostname: Socket.gethostname,
        user: ENV['USER']
      }
    end
    
    def capture_git_info
      return {} unless system('git rev-parse --git-dir > /dev/null 2>&1')
      
      {
        branch: `git rev-parse --abbrev-ref HEAD`.strip,
        commit: `git rev-parse HEAD`.strip,
        dirty: !`git status --porcelain`.strip.empty?
      }
    rescue
      {}
    end
    
    def capture_mitamae_version
      `mitamae version 2>/dev/null`.strip
    rescue
      'unknown'
    end
    
    def calculate_summary
      return {} unless @current_run && @current_run[:tests]
      
      tests = @current_run[:tests].values
      
      {
        total_tests: tests.size,
        passed: tests.count { |t| t[:status] == :passed },
        failed: tests.count { |t| t[:status] == :failed },
        skipped: tests.count { |t| t[:status] == :skipped },
        errors: tests.count { |t| t[:status] == :error },
        total_duration: tests.sum { |t| t[:duration] || 0 }
      }
    end
    
    def save_run(run_data)
      run_file = File.join(@history_dir, 'runs', "#{run_data[:id]}.json")
      File.write(run_file, JSON.pretty_generate(run_data))
      
      # Update index
      update_history_index(run_data)
      
      log_debug "Saved run history: #{run_data[:id]}"
    end
    
    def update_history_index(run_data)
      index_file = File.join(@history_dir, 'index.json')
      index = File.exist?(index_file) ? JSON.parse(File.read(index_file)) : { 'runs' => [] }
      
      index['runs'].unshift({
        'id' => run_data[:id],
        'suite_name' => run_data[:suite_name],
        'start_time' => run_data[:start_time].iso8601,
        'summary' => run_data[:summary]
      })
      
      # Keep only last 100 entries in index
      index['runs'] = index['runs'].first(100)
      
      File.write(index_file, JSON.pretty_generate(index))
    end
    
    def get_run_summary(run_id)
      index_file = File.join(@history_dir, 'index.json')
      return nil unless File.exist?(index_file)
      
      index = JSON.parse(File.read(index_file), symbolize_names: true)
      index[:runs].find { |r| r[:id] == run_id }
    end
    
    def summarize_run(run)
      {
        id: run[:id],
        suite_name: run[:suite_name],
        start_time: run[:start_time],
        duration: run[:end_time] ? Time.parse(run[:end_time]) - Time.parse(run[:start_time]) : 0,
        summary: run[:summary]
      }
    end
    
    def calculate_duration_change(run1, run2)
      duration1 = run1[:summary][:total_duration] || 0
      duration2 = run2[:summary][:total_duration] || 0
      
      {
        absolute: duration2 - duration1,
        percentage: duration1 > 0 ? ((duration2 - duration1) / duration1.to_f * 100).round(2) : 0
      }
    end
    
    def calculate_status_changes(run1, run2)
      changes = {}
      
      all_tests = (run1[:tests].keys + run2[:tests].keys).uniq
      
      all_tests.each do |test_name|
        status1 = run1[:tests][test_name]&.dig(:status)
        status2 = run2[:tests][test_name]&.dig(:status)
        
        if status1 != status2
          changes[test_name] = {
            from: status1,
            to: status2
          }
        end
      end
      
      changes
    end
    
    def find_new_failures(run1, run2)
      run2[:tests].select do |name, data|
        old_status = run1[:tests][name]&.dig(:status)
        new_status = data[:status]
        
        old_status == :passed && [:failed, :error].include?(new_status)
      end.keys
    end
    
    def find_fixed_tests(run1, run2)
      run2[:tests].select do |name, data|
        old_status = run1[:tests][name]&.dig(:status)
        new_status = data[:status]
        
        [:failed, :error].include?(old_status) && new_status == :passed
      end.keys
    end
    
    def calculate_performance_changes(run1, run2)
      changes = []
      
      run2[:tests].each do |name, data|
        next unless run1[:tests][name]
        
        duration1 = run1[:tests][name][:duration] || 0
        duration2 = data[:duration] || 0
        
        next if duration1 == 0
        
        change_pct = ((duration2 - duration1) / duration1.to_f * 100).round(2)
        
        if change_pct.abs > 20 # Significant change threshold
          changes << {
            test: name,
            old_duration: duration1,
            new_duration: duration2,
            change_percentage: change_pct
          }
        end
      end
      
      changes.sort_by { |c| -c[:change_percentage].abs }
    end
    
    def find_flaky_tests(run1, run2)
      # Tests that changed status but not due to obvious reasons
      status_changes = calculate_status_changes(run1, run2)
      
      status_changes.select do |_, change|
        # Consider flaky if status changed between passed/failed
        # (not including skipped or new tests)
        [:passed, :failed].include?(change[:from]) && 
        [:passed, :failed].include?(change[:to])
      end.keys
    end
    
    def calculate_success_rate_trend(runs)
      runs.map do |run|
        summary = run[:summary]
        total = summary[:total_tests] || 0
        passed = summary[:passed] || 0
        
        {
          run_id: run[:id],
          date: run[:start_time],
          success_rate: total > 0 ? (passed.to_f / total * 100).round(2) : 0
        }
      end
    end
    
    def calculate_duration_trend(runs)
      runs.map do |run|
        {
          run_id: run[:id],
          date: run[:start_time],
          duration: run[:summary][:total_duration] || 0
        }
      end
    end
    
    def identify_flaky_tests(runs)
      test_results = {}
      
      runs.each do |run_summary|
        run = get_run(run_summary[:id])
        next unless run
        
        run[:tests].each do |name, data|
          test_results[name] ||= []
          test_results[name] << data[:status]
        end
      end
      
      # Find tests with inconsistent results
      test_results.select do |name, statuses|
        unique_statuses = statuses.uniq
        unique_statuses.size > 1 && unique_statuses.include?(:passed) && unique_statuses.include?(:failed)
      end.map do |name, statuses|
        {
          test: name,
          failure_rate: (statuses.count(:failed).to_f / statuses.size * 100).round(2),
          recent_statuses: statuses.last(5)
        }
      end
    end
    
    def identify_consistent_failures(runs)
      test_results = {}
      
      runs.each do |run_summary|
        run = get_run(run_summary[:id])
        next unless run
        
        run[:tests].each do |name, data|
          test_results[name] ||= []
          test_results[name] << data[:status]
        end
      end
      
      # Find tests that always fail
      test_results.select do |name, statuses|
        statuses.all? { |s| [:failed, :error].include?(s) }
      end.keys
    end
    
    def identify_performance_regressions(runs)
      return [] if runs.size < 2
      
      regressions = []
      test_durations = {}
      
      # Collect duration history
      runs.each do |run_summary|
        run = get_run(run_summary[:id])
        next unless run
        
        run[:tests].each do |name, data|
          test_durations[name] ||= []
          test_durations[name] << {
            run_id: run[:id],
            duration: data[:duration] || 0
          }
        end
      end
      
      # Analyze for regressions
      test_durations.each do |name, durations|
        next if durations.size < 3
        
        recent = durations.first(3).map { |d| d[:duration] }.sum / 3.0
        baseline = durations.last(3).map { |d| d[:duration] }.sum / 3.0
        
        next if baseline == 0
        
        increase_pct = ((recent - baseline) / baseline * 100).round(2)
        
        if increase_pct > 50 # 50% increase threshold
          regressions << {
            test: name,
            baseline_duration: baseline.round(2),
            recent_duration: recent.round(2),
            increase_percentage: increase_pct
          }
        end
      end
      
      regressions.sort_by { |r| -r[:increase_percentage] }
    end
    
    def count_total_runs
      Dir.glob(File.join(@history_dir, 'runs', '*.json')).size
    end
    
    def get_date_range
      runs = list_runs(1000)
      return {} if runs.empty?
      
      {
        first_run: runs.last[:start_time],
        last_run: runs.first[:start_time]
      }
    end
    
    def analyze_test_stability
      # Analyze last 20 runs
      runs = list_runs(20)
      test_statuses = {}
      
      runs.each do |run_summary|
        run = get_run(run_summary[:id])
        next unless run
        
        run[:tests].each do |name, data|
          test_statuses[name] ||= { passed: 0, failed: 0, total: 0 }
          test_statuses[name][:total] += 1
          
          if data[:status] == :passed
            test_statuses[name][:passed] += 1
          elsif [:failed, :error].include?(data[:status])
            test_statuses[name][:failed] += 1
          end
        end
      end
      
      # Calculate stability scores
      test_statuses.map do |name, stats|
        stability_score = stats[:total] > 0 ? 
          (stats[:passed].to_f / stats[:total] * 100).round(2) : 0
        
        {
          test: name,
          stability_score: stability_score,
          run_count: stats[:total],
          classification: classify_stability(stability_score)
        }
      end.sort_by { |t| t[:stability_score] }
    end
    
    def classify_stability(score)
      case score
      when 95..100 then 'stable'
      when 80..94 then 'mostly_stable'
      when 50..79 then 'flaky'
      else 'unstable'
      end
    end
    
    def calculate_performance_metrics
      runs = list_runs(10)
      
      durations = runs.map { |r| r[:summary][:total_duration] || 0 }.select { |d| d > 0 }
      
      return {} if durations.empty?
      
      {
        avg_duration: (durations.sum / durations.size.to_f).round(2),
        min_duration: durations.min,
        max_duration: durations.max,
        trend: durations.size >= 3 ? calculate_trend(durations) : 'insufficient_data'
      }
    end
    
    def calculate_trend(values)
      # Simple trend detection
      recent = values.first(3).sum / 3.0
      older = values.last(3).sum / 3.0
      
      change_pct = older > 0 ? ((recent - older) / older * 100).round(2) : 0
      
      if change_pct > 10
        'increasing'
      elsif change_pct < -10
        'decreasing'
      else
        'stable'
      end
    end
  end
  
  # Extension for test runner to integrate history
  module HistoricalTestRunner
    def self.prepended(base)
      base.class_eval do
        attr_accessor :history
      end
    end
    
    def initialize(options = {})
      super
      @history = options[:history] || TestHistory.new
      @track_history = options.fetch(:track_history, true)
    end
    
    def run(test_specs)
      @history.start_run if @track_history
      
      results = super
      
      if @track_history
        run_id = @history.finish_run
        log_info "Test run history saved: #{run_id}"
      end
      
      results
    end
    
    def run_single(test_spec)
      result = super
      
      @history.record_test_result(test_spec, result) if @track_history
      
      result
    end
  end
end