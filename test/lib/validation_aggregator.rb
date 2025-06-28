require 'json'
require 'time'
require 'cgi'

module MitamaeTest
  class ValidationAggregator
    include Logging
    
    attr_reader :results, :start_time, :end_time
    
    def initialize
      @results = []
      @validators_run = []
      @start_time = nil
      @end_time = nil
    end
    
    def start
      @start_time = Time.now
      log_info "Starting validation aggregation at #{@start_time}"
    end
    
    def add_result(validator, test_spec = nil)
      result = {
        validator: validator.class.plugin_name || validator.class.name,
        test_spec: test_spec&.name || 'unnamed',
        success: validator.success?,
        errors: validator.errors.map(&:to_h),
        warnings: validator.warnings.map(&:to_h),
        timestamp: Time.now,
        duration: nil
      }
      
      if validator.respond_to?(:duration)
        result[:duration] = validator.duration
      end
      
      @results << result
      @validators_run << validator.class.plugin_name unless @validators_run.include?(validator.class.plugin_name)
      
      log_debug "Added result from #{result[:validator]}: #{result[:success] ? 'PASS' : 'FAIL'}"
    end
    
    def finish
      @end_time = Time.now
      log_info "Finished validation aggregation at #{@end_time}"
    end
    
    def summary
      {
        total_validations: @results.size,
        passed: @results.count { |r| r[:success] },
        failed: @results.count { |r| !r[:success] },
        total_errors: @results.sum { |r| r[:errors].size },
        total_warnings: @results.sum { |r| r[:warnings].size },
        validators_used: @validators_run,
        duration: duration,
        start_time: @start_time,
        end_time: @end_time
      }
    end
    
    def detailed_report
      {
        summary: summary,
        by_validator: group_by_validator,
        by_test_spec: group_by_test_spec,
        all_errors: all_errors,
        all_warnings: all_warnings,
        timeline: create_timeline
      }
    end
    
    def success?
      @results.all? { |r| r[:success] }
    end
    
    def duration
      return 0 unless @start_time && @end_time
      @end_time - @start_time
    end
    
    def to_json
      JSON.pretty_generate(detailed_report)
    end
    
    def to_html
      report = detailed_report
      
      html = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Mitamae Test Results - #{@start_time&.strftime('%Y-%m-%d %H:%M:%S')}</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
            .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
            h1 { color: #333; }
            .summary { background: #e8f4f8; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
            .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; }
            .summary-item { text-align: center; }
            .summary-value { font-size: 2em; font-weight: bold; }
            .pass { color: #4caf50; }
            .fail { color: #f44336; }
            .warn { color: #ff9800; }
            table { width: 100%; border-collapse: collapse; margin: 20px 0; }
            th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
            th { background: #f0f0f0; font-weight: bold; }
            tr:hover { background: #f5f5f5; }
            .error { background: #ffebee; }
            .warning { background: #fff3e0; }
            .success { background: #e8f5e9; }
            .details { margin: 10px 0; padding: 10px; background: #f5f5f5; border-radius: 3px; font-family: monospace; font-size: 0.9em; }
            .timeline { margin: 20px 0; }
            .timeline-item { margin: 10px 0; padding: 10px; border-left: 3px solid #2196f3; }
            .accordion { cursor: pointer; padding: 10px; background: #f0f0f0; border: none; width: 100%; text-align: left; }
            .accordion:hover { background: #e0e0e0; }
            .panel { padding: 0 10px; display: none; }
            .panel.show { display: block; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Mitamae Test Results</h1>
            <p>Generated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}</p>
            
            #{generate_summary_html(report[:summary])}
            #{generate_errors_html(report[:all_errors])}
            #{generate_warnings_html(report[:all_warnings])}
            #{generate_validator_results_html(report[:by_validator])}
            #{generate_timeline_html(report[:timeline])}
          </div>
          
          <script>
            document.querySelectorAll('.accordion').forEach(button => {
              button.addEventListener('click', () => {
                const panel = button.nextElementSibling;
                panel.classList.toggle('show');
              });
            });
          </script>
        </body>
        </html>
      HTML
      
      html
    end
    
    def to_console
      report = detailed_report
      summary = report[:summary]
      
      output = []
      output << "\n" + "="*60
      output << "MITAMAE TEST RESULTS"
      output << "="*60
      output << "Duration: #{format_duration(summary[:duration])}"
      output << "Total Tests: #{summary[:total_validations]}"
      output << "Passed: #{summary[:passed]} (#{percentage(summary[:passed], summary[:total_validations])}%)"
      output << "Failed: #{summary[:failed]} (#{percentage(summary[:failed], summary[:total_validations])}%)"
      output << ""
      
      if summary[:total_errors] > 0
        output << "ERRORS (#{summary[:total_errors]}):"
        output << "-"*40
        report[:all_errors].each do |error|
          output << "  [#{error[:validator]}] #{error[:message]}"
          if error[:details] && !error[:details].empty?
            output << "    Details: #{error[:details].inspect}"
          end
        end
        output << ""
      end
      
      if summary[:total_warnings] > 0
        output << "WARNINGS (#{summary[:total_warnings]}):"
        output << "-"*40
        report[:all_warnings].each do |warning|
          output << "  [#{warning[:validator]}] #{warning[:message]}"
        end
        output << ""
      end
      
      output << "BY VALIDATOR:"
      output << "-"*40
      report[:by_validator].each do |validator, stats|
        status = stats[:failed] > 0 ? "FAIL" : "PASS"
        output << sprintf("  %-20s %s (P:%d F:%d E:%d W:%d)", 
                         validator, 
                         status,
                         stats[:passed],
                         stats[:failed],
                         stats[:errors],
                         stats[:warnings])
      end
      
      output << "="*60
      output << ""
      
      output.join("\n")
    end
    
    private
    
    def group_by_validator
      grouped = {}
      
      @results.each do |result|
        validator = result[:validator]
        grouped[validator] ||= {
          total: 0,
          passed: 0,
          failed: 0,
          errors: 0,
          warnings: 0,
          test_specs: []
        }
        
        grouped[validator][:total] += 1
        grouped[validator][:passed] += 1 if result[:success]
        grouped[validator][:failed] += 1 unless result[:success]
        grouped[validator][:errors] += result[:errors].size
        grouped[validator][:warnings] += result[:warnings].size
        grouped[validator][:test_specs] << result[:test_spec]
      end
      
      grouped
    end
    
    def group_by_test_spec
      grouped = {}
      
      @results.each do |result|
        spec = result[:test_spec]
        grouped[spec] ||= {
          validators: [],
          passed: 0,
          failed: 0,
          errors: [],
          warnings: []
        }
        
        grouped[spec][:validators] << result[:validator]
        grouped[spec][:passed] += 1 if result[:success]
        grouped[spec][:failed] += 1 unless result[:success]
        grouped[spec][:errors].concat(result[:errors])
        grouped[spec][:warnings].concat(result[:warnings])
      end
      
      grouped
    end
    
    def all_errors
      @results.flat_map do |result|
        result[:errors].map do |error|
          error.merge(
            validator: result[:validator],
            test_spec: result[:test_spec]
          )
        end
      end
    end
    
    def all_warnings
      @results.flat_map do |result|
        result[:warnings].map do |warning|
          warning.merge(
            validator: result[:validator],
            test_spec: result[:test_spec]
          )
        end
      end
    end
    
    def create_timeline
      @results.map do |result|
        {
          time: result[:timestamp],
          validator: result[:validator],
          test_spec: result[:test_spec],
          success: result[:success],
          error_count: result[:errors].size,
          warning_count: result[:warnings].size
        }
      end.sort_by { |item| item[:time] }
    end
    
    def generate_summary_html(summary)
      <<~HTML
        <div class="summary">
          <h2>Summary</h2>
          <div class="summary-grid">
            <div class="summary-item">
              <div class="summary-value">#{summary[:total_validations]}</div>
              <div>Total Tests</div>
            </div>
            <div class="summary-item">
              <div class="summary-value pass">#{summary[:passed]}</div>
              <div>Passed</div>
            </div>
            <div class="summary-item">
              <div class="summary-value fail">#{summary[:failed]}</div>
              <div>Failed</div>
            </div>
            <div class="summary-item">
              <div class="summary-value fail">#{summary[:total_errors]}</div>
              <div>Errors</div>
            </div>
            <div class="summary-item">
              <div class="summary-value warn">#{summary[:total_warnings]}</div>
              <div>Warnings</div>
            </div>
            <div class="summary-item">
              <div class="summary-value">#{format_duration(summary[:duration])}</div>
              <div>Duration</div>
            </div>
          </div>
        </div>
      HTML
    end
    
    def generate_errors_html(errors)
      return "" if errors.empty?
      
      rows = errors.map do |error|
        details = error[:details] ? "<div class='details'>#{CGI.escapeHTML(error[:details].to_json)}</div>" : ""
        <<~ROW
          <tr class="error">
            <td>#{error[:validator]}</td>
            <td>#{error[:test_spec]}</td>
            <td>
              #{CGI.escapeHTML(error[:message])}
              #{details}
            </td>
          </tr>
        ROW
      end.join
      
      <<~HTML
        <h2>Errors</h2>
        <table>
          <thead>
            <tr>
              <th>Validator</th>
              <th>Test Spec</th>
              <th>Message</th>
            </tr>
          </thead>
          <tbody>
            #{rows}
          </tbody>
        </table>
      HTML
    end
    
    def generate_warnings_html(warnings)
      return "" if warnings.empty?
      
      rows = warnings.map do |warning|
        <<~ROW
          <tr class="warning">
            <td>#{warning[:validator]}</td>
            <td>#{warning[:test_spec]}</td>
            <td>#{CGI.escapeHTML(warning[:message])}</td>
          </tr>
        ROW
      end.join
      
      <<~HTML
        <h2>Warnings</h2>
        <table>
          <thead>
            <tr>
              <th>Validator</th>
              <th>Test Spec</th>
              <th>Message</th>
            </tr>
          </thead>
          <tbody>
            #{rows}
          </tbody>
        </table>
      HTML
    end
    
    def generate_validator_results_html(by_validator)
      sections = by_validator.map do |validator, stats|
        status_class = stats[:failed] > 0 ? 'fail' : 'pass'
        <<~SECTION
          <button class="accordion">
            #{validator} - 
            <span class="#{status_class}">
              #{stats[:failed] > 0 ? 'FAILED' : 'PASSED'}
            </span>
            (#{stats[:passed]}/#{stats[:total]} passed)
          </button>
          <div class="panel">
            <p>Errors: #{stats[:errors]}, Warnings: #{stats[:warnings]}</p>
            <p>Test Specs: #{stats[:test_specs].uniq.join(', ')}</p>
          </div>
        SECTION
      end.join
      
      <<~HTML
        <h2>Results by Validator</h2>
        #{sections}
      HTML
    end
    
    def generate_timeline_html(timeline)
      items = timeline.map do |item|
        status = item[:success] ? 'success' : 'fail'
        <<~ITEM
          <div class="timeline-item #{status}">
            <strong>#{item[:time].strftime('%H:%M:%S')}</strong> - 
            #{item[:validator]} (#{item[:test_spec]}) - 
            #{item[:success] ? 'PASS' : 'FAIL'}
            #{item[:error_count] > 0 ? "(#{item[:error_count]} errors)" : ''}
            #{item[:warning_count] > 0 ? "(#{item[:warning_count]} warnings)" : ''}
          </div>
        ITEM
      end.join
      
      <<~HTML
        <h2>Execution Timeline</h2>
        <div class="timeline">
          #{items}
        </div>
      HTML
    end
    
    def format_duration(seconds)
      return "0s" unless seconds
      
      if seconds < 60
        "#{seconds.round(1)}s"
      else
        minutes = (seconds / 60).to_i
        secs = (seconds % 60).round
        "#{minutes}m #{secs}s"
      end
    end
    
    def percentage(part, whole)
      return 0 if whole == 0
      ((part.to_f / whole) * 100).round(1)
    end
  end
  
  # Convenience reporter that uses the aggregator
  class AggregatedReporter < Reporters::Base
    plugin_name :aggregated
    plugin_type :reporter
    
    def initialize(options = {})
      super
      @aggregator = ValidationAggregator.new
      @format = options[:format] || :console
      @output_file = options[:output_file]
    end
    
    def start_suite(test_suite)
      @aggregator.start
    end
    
    def finish_suite(test_suite)
      @aggregator.finish
      output_report
    end
    
    def report_test_result(result)
      # Extract validator results from test result
      if result.validation_results.respond_to?(:each)
        result.validation_results.each do |validator|
          @aggregator.add_result(validator, result.test_spec)
        end
      end
    end
    
    def report_summary
      # Summary is handled by aggregator
    end
    
    private
    
    def output_report
      report_content = case @format
                      when :json
                        @aggregator.to_json
                      when :html
                        @aggregator.to_html
                      else
                        @aggregator.to_console
                      end
      
      if @output_file
        File.write(@output_file, report_content)
        log_info "Report saved to: #{@output_file}"
      else
        puts report_content if @format == :console
      end
    end
  end
end