require 'time'

module MitamaeTest
  module Reporters
    class EnhancedConsoleReporter < Base
      COLORS = {
        reset: "\e[0m",
        bold: "\e[1m",
        dim: "\e[2m",
        underline: "\e[4m",
        red: "\e[31m",
        green: "\e[32m",
        yellow: "\e[33m",
        blue: "\e[34m",
        magenta: "\e[35m",
        cyan: "\e[36m",
        white: "\e[37m",
        bright_red: "\e[91m",
        bright_green: "\e[92m",
        bright_yellow: "\e[93m",
        bright_blue: "\e[94m"
      }.freeze
      
      STATUS_SYMBOLS = {
        passed: '✓',
        failed: '✗',
        skipped: '⊘',
        error: '!',
        running: '⟳',
        pending: '◯'
      }.freeze
      
      def initialize(options = {})
        super
        @use_colors = options.fetch(:colors, true)
        @verbose = options.fetch(:verbose, false)
        @show_timings = options.fetch(:show_timings, true)
        @show_validators = options.fetch(:show_validators, true)
        @show_progress = options.fetch(:show_progress, true)
        @current_test = nil
        @test_count = 0
        @total_tests = 0
        @start_time = nil
        @failures = []
        @errors = []
        @slow_tests = []
        @slow_threshold = options.fetch(:slow_threshold, 10.0)
        clear_line
      end
      
      def start_suite(test_suite)
        super
        @start_time = Time.now
        @total_tests = test_suite.is_a?(Array) ? test_suite.size : test_suite.specs.size
        
        puts header("Mitamae Test Suite", :blue)
        puts "#{dim('Tests:')} #{@total_tests}"
        puts "#{dim('Time:')} #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
        puts divider
      end
      
      def start_test(test_spec)
        super
        @current_test = test_spec
        @test_count += 1
        
        if @show_progress
          progress = "#{@test_count}/#{@total_tests}"
          print "\r#{clear_line}#{dim("[#{progress}]")} #{color(:cyan, 'Running:')} #{test_spec.name}..."
        end
      end
      
      def test_passed(test_spec, results)
        super
        duration = calculate_duration(test_spec)
        
        if duration > @slow_threshold
          @slow_tests << { spec: test_spec, duration: duration }
        end
        
        if @show_progress
          print_test_result(test_spec, :passed, duration, results)
        end
      end
      
      def test_failed(test_spec, results)
        super
        duration = calculate_duration(test_spec)
        @failures << { spec: test_spec, results: results, duration: duration }
        
        if @show_progress
          print_test_result(test_spec, :failed, duration, results)
        end
      end
      
      def test_skipped(test_spec, reason)
        super
        
        if @show_progress
          print_test_result(test_spec, :skipped, 0, [], reason)
        end
      end
      
      def report_test_result(result)
        # Already handled in specific methods above
      end
      
      def finish_suite(test_suite)
        super
        print "\r#{clear_line}"
        puts divider
        
        # Show failures and errors
        if @failures.any? || @errors.any?
          show_failures_and_errors
        end
        
        # Show slow tests
        if @slow_tests.any? && @show_timings
          show_slow_tests
        end
        
        # Show summary
        show_summary
        
        # Show tips if there were failures
        if failed_count > 0
          show_debugging_tips
        end
      end
      
      def report_summary
        # Handled in finish_suite
      end
      
      private
      
      def print_test_result(test_spec, status, duration, results, skip_reason = nil)
        print "\r#{clear_line}"
        
        # Status icon and name
        icon = color_status(STATUS_SYMBOLS[status], status)
        name = test_spec.name
        
        # Duration
        duration_str = @show_timings ? dim(" (#{format_duration(duration)})") : ""
        
        # Tags
        tags_str = test_spec.tags.any? ? dim(" [#{test_spec.tags.join(', ')}]") : ""
        
        puts "#{icon} #{name}#{tags_str}#{duration_str}"
        
        # Show validator details if verbose or failed
        if (@verbose || status == :failed) && @show_validators && results.any?
          results.each do |validator|
            print_validator_result(validator)
          end
        end
        
        # Show skip reason
        if status == :skipped && skip_reason
          puts "  #{dim('└─')} #{color(:yellow, skip_reason)}"
        end
      end
      
      def print_validator_result(validator)
        icon = validator.success? ? color(:green, '✓') : color(:red, '✗')
        name = validator.class.plugin_name || validator.class.name
        
        puts "  #{dim('├─')} #{icon} #{name}"
        
        if !validator.success? || @verbose
          # Show errors
          validator.errors.each do |error|
            puts "  #{dim('│')}   #{color(:red, '✗')} #{error.message}"
            if error.details && !error.details.empty? && @verbose
              error.details.each do |key, value|
                puts "  #{dim('│')}     #{dim("#{key}:")} #{value}"
              end
            end
          end
          
          # Show warnings
          validator.warnings.each do |warning|
            puts "  #{dim('│')}   #{color(:yellow, '⚠')} #{warning.message}"
          end
        end
      end
      
      def show_failures_and_errors
        puts header("Failures and Errors", :red)
        
        @failures.each_with_index do |failure, index|
          spec = failure[:spec]
          results = failure[:results]
          
          puts "#{color(:red, "#{index + 1})")} #{spec.name}"
          puts "   #{dim("Path:")} #{spec.recipe.path}"
          puts "   #{dim("Tags:")} #{spec.tags.join(', ')}" if spec.tags.any?
          
          results.each do |validator|
            next if validator.success?
            
            puts "   #{dim("Validator:")} #{validator.class.plugin_name}"
            validator.errors.each do |error|
              puts "     #{color(:red, '✗')} #{error.message}"
              if error.details && !error.details.empty?
                pretty_print_details(error.details, 6)
              end
            end
          end
          
          puts
        end
      end
      
      def show_slow_tests
        puts header("Slow Tests", :yellow)
        
        @slow_tests.sort_by { |t| -t[:duration] }.first(5).each do |test|
          puts "  #{color(:yellow, format_duration(test[:duration]))} - #{test[:spec].name}"
        end
        
        puts
      end
      
      def show_summary
        total_duration = Time.now - @start_time
        
        puts header("Summary", :blue)
        
        # Status breakdown
        status_line = []
        status_line << color(:green, "#{passed_count} passed") if passed_count > 0
        status_line << color(:red, "#{failed_count} failed") if failed_count > 0
        status_line << color(:yellow, "#{skipped_count} skipped") if skipped_count > 0
        
        puts status_line.join(', ')
        
        # Success rate
        if total_count > 0
          success_rate = (passed_count.to_f / total_count * 100).round(1)
          rate_color = success_rate >= 80 ? :green : success_rate >= 50 ? :yellow : :red
          puts "#{dim('Success rate:')} #{color(rate_color, "#{success_rate}%")}"
        end
        
        # Timing
        puts "#{dim('Total time:')} #{format_duration(total_duration)}"
        
        if @slow_tests.any?
          avg_duration = @results.map { |r| r.duration }.sum / @results.size.to_f
          puts "#{dim('Average test time:')} #{format_duration(avg_duration)}"
        end
      end
      
      def show_debugging_tips
        puts
        puts header("Debugging Tips", :cyan)
        
        tips = [
          "Run with --verbose to see detailed validator output",
          "Use --name=PATTERN to run specific tests",
          "Add --tag=TAG to filter by test tags",
          "Check test logs in reports/ directory",
          "Use --reporter=html for detailed HTML report"
        ]
        
        tips.each do |tip|
          puts "  #{color(:cyan, '→')} #{tip}"
        end
      end
      
      def pretty_print_details(details, indent = 4)
        details.each do |key, value|
          spaces = ' ' * indent
          if value.is_a?(Hash)
            puts "#{spaces}#{dim("#{key}:")}"
            pretty_print_details(value, indent + 2)
          elsif value.is_a?(Array)
            puts "#{spaces}#{dim("#{key}:")}"
            value.each { |item| puts "#{spaces}  - #{item}" }
          else
            puts "#{spaces}#{dim("#{key}:")} #{value}"
          end
        end
      end
      
      def calculate_duration(test_spec)
        result = @results.find { |r| r.test_spec.name == test_spec.name }
        result ? result.duration : 0
      end
      
      def format_duration(seconds)
        if seconds < 1
          "#{(seconds * 1000).round}ms"
        elsif seconds < 60
          "#{seconds.round(1)}s"
        else
          minutes = (seconds / 60).to_i
          secs = (seconds % 60).round
          "#{minutes}m #{secs}s"
        end
      end
      
      def color(color_name, text)
        return text unless @use_colors
        "#{COLORS[color_name]}#{text}#{COLORS[:reset]}"
      end
      
      def color_status(text, status)
        color_map = {
          passed: :green,
          failed: :red,
          skipped: :yellow,
          error: :bright_red,
          running: :blue,
          pending: :dim
        }
        
        color(color_map[status] || :white, text)
      end
      
      def bold(text)
        @use_colors ? "#{COLORS[:bold]}#{text}#{COLORS[:reset]}" : text
      end
      
      def dim(text)
        @use_colors ? "#{COLORS[:dim]}#{text}#{COLORS[:reset]}" : text
      end
      
      def header(text, color_name = :white)
        "\n#{color(color_name, bold(text))}"
      end
      
      def divider
        dim('─' * 60)
      end
      
      def clear_line
        "\r\e[K"
      end
    end
  end
end