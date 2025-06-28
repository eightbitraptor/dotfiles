require 'erb'
require 'json'
require 'time'
require 'cgi'

module MitamaeTest
  module Reporters
    class DetailedHtmlReporter < Base
      def initialize(options = {})
        super
        @output_file = options[:output_file] || 'test-report.html'
        @include_assets = options[:include_assets] != false
        @show_code = options[:show_code] != false
        @theme = options[:theme] || 'light'
        @test_details = []
        @start_time = nil
        @end_time = nil
      end
      
      def start_suite(test_suite)
        super
        @start_time = Time.now
        @suite_name = test_suite.is_a?(String) ? test_suite : test_suite.name
      end
      
      def finish_suite(test_suite)
        super
        @end_time = Time.now
        generate_html_report
      end
      
      def report_test_result(result)
        test_detail = {
          name: result.test_spec.name,
          description: result.test_spec.description,
          status: result.status,
          duration: result.duration,
          start_time: result.start_time,
          end_time: result.end_time,
          tags: result.test_spec.tags,
          recipe: {
            path: result.test_spec.recipe.path,
            node_json: result.test_spec.recipe.node_json
          },
          environment: {
            type: result.test_spec.environment.type,
            distribution: result.test_spec.environment.distribution
          },
          validators: extract_validator_details(result.validation_results),
          error: result.error ? {
            message: result.error.message,
            backtrace: result.error.backtrace&.first(10)
          } : nil
        }
        
        @test_details << test_detail
      end
      
      def report_summary
        # Handled in generate_html_report
      end
      
      private
      
      def extract_validator_details(validators)
        validators.map do |validator|
          {
            name: validator.class.plugin_name || validator.class.name,
            success: validator.success?,
            errors: validator.errors.map { |e| error_to_hash(e) },
            warnings: validator.warnings.map { |w| warning_to_hash(w) }
          }
        end
      end
      
      def error_to_hash(error)
        {
          message: error.message,
          details: error.details,
          level: error.level
        }
      end
      
      def warning_to_hash(warning)
        {
          message: warning.message,
          details: warning.details,
          level: warning.level
        }
      end
      
      def generate_html_report
        template = create_html_template
        
        # Prepare data for template
        report_data = {
          title: "Mitamae Test Report - #{@suite_name}",
          generated_at: Time.now,
          start_time: @start_time,
          end_time: @end_time,
          duration: duration,
          summary: calculate_summary,
          tests: @test_details,
          charts_data: prepare_charts_data,
          theme: @theme
        }
        
        # Generate HTML
        html = ERB.new(template, trim_mode: '-').result(binding)
        
        # Write to file
        File.write(@output_file, html)
        log_info "HTML report generated: #{@output_file}"
      end
      
      def calculate_summary
        total = @test_details.size
        passed = @test_details.count { |t| t[:status] == :passed }
        failed = @test_details.count { |t| t[:status] == :failed }
        skipped = @test_details.count { |t| t[:status] == :skipped }
        errors = @test_details.count { |t| t[:status] == :error }
        
        {
          total: total,
          passed: passed,
          failed: failed,
          skipped: skipped,
          errors: errors,
          success_rate: total > 0 ? (passed.to_f / total * 100).round(2) : 0,
          avg_duration: total > 0 ? (@test_details.sum { |t| t[:duration] } / total).round(2) : 0,
          total_duration: duration
        }
      end
      
      def prepare_charts_data
        {
          status_distribution: {
            passed: @test_details.count { |t| t[:status] == :passed },
            failed: @test_details.count { |t| t[:status] == :failed },
            skipped: @test_details.count { |t| t[:status] == :skipped },
            error: @test_details.count { |t| t[:status] == :error }
          },
          duration_distribution: calculate_duration_distribution,
          tag_performance: calculate_tag_performance,
          validator_success_rates: calculate_validator_success_rates
        }
      end
      
      def calculate_duration_distribution
        buckets = { '<1s' => 0, '1-5s' => 0, '5-10s' => 0, '10-30s' => 0, '>30s' => 0 }
        
        @test_details.each do |test|
          duration = test[:duration]
          if duration < 1
            buckets['<1s'] += 1
          elsif duration < 5
            buckets['1-5s'] += 1
          elsif duration < 10
            buckets['5-10s'] += 1
          elsif duration < 30
            buckets['10-30s'] += 1
          else
            buckets['>30s'] += 1
          end
        end
        
        buckets
      end
      
      def calculate_tag_performance
        tag_stats = {}
        
        @test_details.each do |test|
          test[:tags].each do |tag|
            tag_stats[tag] ||= { passed: 0, failed: 0, total: 0, duration: 0 }
            tag_stats[tag][:total] += 1
            tag_stats[tag][:duration] += test[:duration]
            
            if test[:status] == :passed
              tag_stats[tag][:passed] += 1
            elsif [:failed, :error].include?(test[:status])
              tag_stats[tag][:failed] += 1
            end
          end
        end
        
        tag_stats.transform_values do |stats|
          stats[:success_rate] = stats[:total] > 0 ? 
            (stats[:passed].to_f / stats[:total] * 100).round(2) : 0
          stats[:avg_duration] = stats[:total] > 0 ? 
            (stats[:duration] / stats[:total]).round(2) : 0
          stats
        end
      end
      
      def calculate_validator_success_rates
        validator_stats = {}
        
        @test_details.each do |test|
          test[:validators].each do |validator|
            name = validator[:name]
            validator_stats[name] ||= { passed: 0, failed: 0, total: 0 }
            validator_stats[name][:total] += 1
            
            if validator[:success]
              validator_stats[name][:passed] += 1
            else
              validator_stats[name][:failed] += 1
            end
          end
        end
        
        validator_stats.transform_values do |stats|
          stats[:success_rate] = stats[:total] > 0 ? 
            (stats[:passed].to_f / stats[:total] * 100).round(2) : 0
          stats
        end
      end
      
      def create_html_template
        <<~HTML
          <!DOCTYPE html>
          <html lang="en" data-theme="<%= report_data[:theme] %>">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title><%= report_data[:title] %></title>
            #{include_styles}
            #{include_scripts}
          </head>
          <body>
            <div class="container">
              <!-- Header -->
              <header>
                <h1><%= report_data[:title] %></h1>
                <div class="report-meta">
                  <span>Generated: <%= report_data[:generated_at].strftime('%Y-%m-%d %H:%M:%S') %></span>
                  <span>Duration: <%= format_duration(report_data[:duration]) %></span>
                </div>
              </header>
              
              <!-- Summary Cards -->
              <section class="summary-section">
                <div class="summary-cards">
                  <div class="summary-card total">
                    <div class="card-value"><%= report_data[:summary][:total] %></div>
                    <div class="card-label">Total Tests</div>
                  </div>
                  <div class="summary-card passed">
                    <div class="card-value"><%= report_data[:summary][:passed] %></div>
                    <div class="card-label">Passed</div>
                  </div>
                  <div class="summary-card failed">
                    <div class="card-value"><%= report_data[:summary][:failed] %></div>
                    <div class="card-label">Failed</div>
                  </div>
                  <div class="summary-card skipped">
                    <div class="card-value"><%= report_data[:summary][:skipped] %></div>
                    <div class="card-label">Skipped</div>
                  </div>
                  <div class="summary-card success-rate">
                    <div class="card-value"><%= report_data[:summary][:success_rate] %>%</div>
                    <div class="card-label">Success Rate</div>
                  </div>
                </div>
              </section>
              
              <!-- Charts -->
              <section class="charts-section">
                <div class="charts-grid">
                  <div class="chart-container">
                    <h3>Test Status Distribution</h3>
                    <canvas id="statusChart"></canvas>
                  </div>
                  <div class="chart-container">
                    <h3>Duration Distribution</h3>
                    <canvas id="durationChart"></canvas>
                  </div>
                  <div class="chart-container">
                    <h3>Tag Performance</h3>
                    <canvas id="tagChart"></canvas>
                  </div>
                  <div class="chart-container">
                    <h3>Validator Success Rates</h3>
                    <canvas id="validatorChart"></canvas>
                  </div>
                </div>
              </section>
              
              <!-- Filters -->
              <section class="filters-section">
                <h2>Test Results</h2>
                <div class="filters">
                  <input type="text" id="searchInput" placeholder="Search tests..." class="search-input">
                  <select id="statusFilter" class="filter-select">
                    <option value="">All Statuses</option>
                    <option value="passed">Passed</option>
                    <option value="failed">Failed</option>
                    <option value="skipped">Skipped</option>
                    <option value="error">Error</option>
                  </select>
                  <select id="tagFilter" class="filter-select">
                    <option value="">All Tags</option>
                    <% all_tags = report_data[:tests].flat_map { |t| t[:tags] }.uniq.sort %>
                    <% all_tags.each do |tag| %>
                      <option value="<%= tag %>"><%= tag %></option>
                    <% end %>
                  </select>
                </div>
              </section>
              
              <!-- Test Results -->
              <section class="tests-section">
                <% report_data[:tests].each_with_index do |test, index| %>
                  <div class="test-card <%= test[:status] %>" data-test-index="<%= index %>">
                    <div class="test-header" onclick="toggleTestDetails(<%= index %>)">
                      <div class="test-status <%= test[:status] %>">
                        <%= status_icon(test[:status]) %>
                      </div>
                      <div class="test-info">
                        <h3 class="test-name"><%= CGI.escapeHTML(test[:name]) %></h3>
                        <div class="test-meta">
                          <span class="test-duration"><%= format_duration(test[:duration]) %></span>
                          <% test[:tags].each do |tag| %>
                            <span class="test-tag"><%= tag %></span>
                          <% end %>
                        </div>
                      </div>
                      <div class="test-expand">▼</div>
                    </div>
                    
                    <div class="test-details" id="test-details-<%= index %>" style="display: none;">
                      <!-- Test Configuration -->
                      <div class="detail-section">
                        <h4>Configuration</h4>
                        <div class="detail-grid">
                          <div class="detail-item">
                            <span class="detail-label">Recipe:</span>
                            <code><%= test[:recipe][:path] %></code>
                          </div>
                          <div class="detail-item">
                            <span class="detail-label">Environment:</span>
                            <span><%= test[:environment][:type] %> / <%= test[:environment][:distribution] %></span>
                          </div>
                          <% if test[:description] %>
                            <div class="detail-item">
                              <span class="detail-label">Description:</span>
                              <span><%= CGI.escapeHTML(test[:description]) %></span>
                            </div>
                          <% end %>
                        </div>
                      </div>
                      
                      <!-- Node JSON -->
                      <% if test[:recipe][:node_json] && !test[:recipe][:node_json].empty? %>
                        <div class="detail-section">
                          <h4>Node Attributes</h4>
                          <pre class="code-block"><%= JSON.pretty_generate(test[:recipe][:node_json]) %></pre>
                        </div>
                      <% end %>
                      
                      <!-- Validators -->
                      <div class="detail-section">
                        <h4>Validators</h4>
                        <% test[:validators].each do |validator| %>
                          <div class="validator-result <%= validator[:success] ? 'success' : 'failure' %>">
                            <div class="validator-header">
                              <span class="validator-status">
                                <%= validator[:success] ? '✓' : '✗' %>
                              </span>
                              <span class="validator-name"><%= validator[:name] %></span>
                            </div>
                            
                            <% if validator[:errors].any? %>
                              <div class="validator-errors">
                                <% validator[:errors].each do |error| %>
                                  <div class="error-item">
                                    <span class="error-icon">✗</span>
                                    <span class="error-message"><%= CGI.escapeHTML(error[:message]) %></span>
                                    <% if error[:details] && !error[:details].empty? %>
                                      <div class="error-details">
                                        <pre><%= JSON.pretty_generate(error[:details]) %></pre>
                                      </div>
                                    <% end %>
                                  </div>
                                <% end %>
                              </div>
                            <% end %>
                            
                            <% if validator[:warnings].any? %>
                              <div class="validator-warnings">
                                <% validator[:warnings].each do |warning| %>
                                  <div class="warning-item">
                                    <span class="warning-icon">⚠</span>
                                    <span class="warning-message"><%= CGI.escapeHTML(warning[:message]) %></span>
                                  </div>
                                <% end %>
                              </div>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                      
                      <!-- Error Details -->
                      <% if test[:error] %>
                        <div class="detail-section error-section">
                          <h4>Error Details</h4>
                          <div class="error-message"><%= CGI.escapeHTML(test[:error][:message]) %></div>
                          <% if test[:error][:backtrace] %>
                            <pre class="error-backtrace"><%= test[:error][:backtrace].join("\n") %></pre>
                          <% end %>
                        </div>
                      <% end %>
                      
                      <!-- Timeline -->
                      <div class="detail-section">
                        <h4>Timeline</h4>
                        <div class="timeline">
                          <div class="timeline-item">
                            <span class="timeline-label">Started:</span>
                            <span><%= test[:start_time].strftime('%H:%M:%S.%L') %></span>
                          </div>
                          <div class="timeline-item">
                            <span class="timeline-label">Completed:</span>
                            <span><%= test[:end_time].strftime('%H:%M:%S.%L') %></span>
                          </div>
                          <div class="timeline-item">
                            <span class="timeline-label">Duration:</span>
                            <span><%= format_duration(test[:duration]) %></span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </section>
              
              <!-- Footer -->
              <footer>
                <p>Generated by Mitamae Test Framework</p>
                <p>Report created at <%= report_data[:generated_at].strftime('%Y-%m-%d %H:%M:%S') %></p>
              </footer>
            </div>
            
            #{include_chart_scripts(report_data)}
          </body>
          </html>
        HTML
      end
      
      def include_styles
        if @include_assets
          <<~CSS
            <style>
              #{File.read(File.join(__dir__, '..', '..', 'assets', 'report.css'))}
            </style>
          CSS
        else
          '<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/normalize/8.0.1/normalize.min.css">'
        end
      end
      
      def include_scripts
        <<~SCRIPTS
          <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
          <script>
            #{File.read(File.join(__dir__, '..', '..', 'assets', 'report.js'))}
          </script>
        SCRIPTS
      end
      
      def include_chart_scripts(data)
        <<~SCRIPTS
          <script>
            // Initialize charts with data
            const chartsData = #{data[:charts_data].to_json};
            
            // Status distribution chart
            new Chart(document.getElementById('statusChart'), {
              type: 'doughnut',
              data: {
                labels: Object.keys(chartsData.status_distribution),
                datasets: [{
                  data: Object.values(chartsData.status_distribution),
                  backgroundColor: ['#4caf50', '#f44336', '#ff9800', '#9c27b0']
                }]
              },
              options: {
                responsive: true,
                maintainAspectRatio: false
              }
            });
            
            // Duration distribution chart
            new Chart(document.getElementById('durationChart'), {
              type: 'bar',
              data: {
                labels: Object.keys(chartsData.duration_distribution),
                datasets: [{
                  label: 'Number of Tests',
                  data: Object.values(chartsData.duration_distribution),
                  backgroundColor: '#2196f3'
                }]
              },
              options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                  y: {
                    beginAtZero: true,
                    ticks: {
                      stepSize: 1
                    }
                  }
                }
              }
            });
            
            // Tag performance chart
            const tagData = chartsData.tag_performance;
            const tagLabels = Object.keys(tagData);
            const tagSuccessRates = tagLabels.map(tag => tagData[tag].success_rate);
            
            new Chart(document.getElementById('tagChart'), {
              type: 'bar',
              data: {
                labels: tagLabels,
                datasets: [{
                  label: 'Success Rate (%)',
                  data: tagSuccessRates,
                  backgroundColor: tagSuccessRates.map(rate => 
                    rate >= 80 ? '#4caf50' : rate >= 50 ? '#ff9800' : '#f44336'
                  )
                }]
              },
              options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                  y: {
                    beginAtZero: true,
                    max: 100
                  }
                }
              }
            });
            
            // Validator success rates chart
            const validatorData = chartsData.validator_success_rates;
            const validatorLabels = Object.keys(validatorData);
            const validatorRates = validatorLabels.map(v => validatorData[v].success_rate);
            
            new Chart(document.getElementById('validatorChart'), {
              type: 'horizontalBar',
              data: {
                labels: validatorLabels,
                datasets: [{
                  label: 'Success Rate (%)',
                  data: validatorRates,
                  backgroundColor: '#9c27b0'
                }]
              },
              options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                  x: {
                    beginAtZero: true,
                    max: 100
                  }
                }
              }
            });
          </script>
        SCRIPTS
      end
      
      def status_icon(status)
        case status
        when :passed then '✓'
        when :failed then '✗'
        when :skipped then '⊘'
        when :error then '!'
        else '?'
        end
      end
      
      def format_duration(seconds)
        if seconds < 1
          "#{(seconds * 1000).round}ms"
        elsif seconds < 60
          "#{seconds.round(2)}s"
        else
          minutes = (seconds / 60).to_i
          secs = (seconds % 60).round
          "#{minutes}m #{secs}s"
        end
      end
    end
  end
end