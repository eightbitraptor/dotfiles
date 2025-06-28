require 'set'

module MitamaeTest
  class CoverageReporter
    include Logging
    
    attr_reader :coverage_data
    
    def initialize
      @coverage_data = {
        recipes: {},
        resources: {},
        attributes: {},
        files: {},
        packages: {},
        services: {},
        validators: {}
      }
      @start_time = nil
      @end_time = nil
    end
    
    def start_coverage
      @start_time = Time.now
      log_debug "Starting coverage collection"
    end
    
    def record_test_execution(test_spec, result)
      # Record recipe coverage
      record_recipe_coverage(test_spec.recipe.path, test_spec, result)
      
      # Record resource coverage based on validators
      result.validation_results.each do |validator|
        record_validator_coverage(validator, test_spec)
      end
      
      # Record attribute usage
      record_attribute_coverage(test_spec.recipe.node_json)
      
      # Record environment coverage
      record_environment_coverage(test_spec.environment)
    end
    
    def finish_coverage
      @end_time = Time.now
      analyze_coverage
    end
    
    def generate_report
      {
        summary: generate_summary,
        recipe_coverage: analyze_recipe_coverage,
        resource_coverage: analyze_resource_coverage,
        attribute_coverage: analyze_attribute_coverage,
        validator_coverage: analyze_validator_coverage,
        uncovered_items: find_uncovered_items,
        metrics: calculate_metrics,
        generated_at: Time.now
      }
    end
    
    def to_html
      report = generate_report
      create_coverage_html(report)
    end
    
    def to_json
      JSON.pretty_generate(generate_report)
    end
    
    private
    
    def record_recipe_coverage(recipe_path, test_spec, result)
      @coverage_data[:recipes][recipe_path] ||= {
        tests: [],
        passed: 0,
        failed: 0,
        resources: Set.new,
        attributes: Set.new
      }
      
      data = @coverage_data[:recipes][recipe_path]
      data[:tests] << test_spec.name
      
      if result.status == :passed
        data[:passed] += 1
      else
        data[:failed] += 1
      end
      
      # Extract resources from recipe (would need actual parsing)
      # For now, we'll infer from validators
      result.validation_results.each do |validator|
        case validator.class.plugin_name
        when :package
          data[:resources].add('package')
        when :service
          data[:resources].add('service')
        when :configuration_file
          data[:resources].add('file')
          data[:resources].add('template')
        end
      end
    end
    
    def record_validator_coverage(validator, test_spec)
      validator_name = validator.class.plugin_name
      
      @coverage_data[:validators][validator_name] ||= {
        total_runs: 0,
        passed: 0,
        failed: 0,
        tests: Set.new,
        errors: []
      }
      
      data = @coverage_data[:validators][validator_name]
      data[:total_runs] += 1
      data[:tests].add(test_spec.name)
      
      if validator.success?
        data[:passed] += 1
      else
        data[:failed] += 1
        data[:errors] += validator.errors.map(&:message)
      end
      
      # Record specific coverage based on validator type
      case validator_name
      when :package
        record_package_coverage(validator)
      when :service
        record_service_coverage(validator)
      when :configuration_file
        record_file_coverage(validator)
      end
    end
    
    def record_package_coverage(validator)
      # Extract package names from validator config
      packages = extract_packages_from_validator(validator)
      
      packages.each do |package|
        @coverage_data[:packages][package] ||= {
          tested: 0,
          validators: Set.new
        }
        
        @coverage_data[:packages][package][:tested] += 1
        @coverage_data[:packages][package][:validators].add(validator.class.plugin_name)
      end
    end
    
    def record_service_coverage(validator)
      # Extract service names from validator config
      services = extract_services_from_validator(validator)
      
      services.each do |service|
        @coverage_data[:services][service] ||= {
          tested: 0,
          validators: Set.new
        }
        
        @coverage_data[:services][service][:tested] += 1
        @coverage_data[:services][service][:validators].add(validator.class.plugin_name)
      end
    end
    
    def record_file_coverage(validator)
      # Extract file paths from validator config
      files = extract_files_from_validator(validator)
      
      files.each do |file|
        @coverage_data[:files][file] ||= {
          tested: 0,
          types: Set.new
        }
        
        @coverage_data[:files][file][:tested] += 1
        @coverage_data[:files][file][:types].add('configuration')
      end
    end
    
    def record_attribute_coverage(node_json)
      flatten_attributes(node_json).each do |attr_path|
        @coverage_data[:attributes][attr_path] ||= 0
        @coverage_data[:attributes][attr_path] += 1
      end
    end
    
    def record_environment_coverage(environment)
      key = "#{environment.type}/#{environment.distribution}"
      @coverage_data[:environments] ||= {}
      @coverage_data[:environments][key] ||= 0
      @coverage_data[:environments][key] += 1
    end
    
    def extract_packages_from_validator(validator)
      # This would need to inspect the validator's configuration
      # For now, return empty array
      []
    end
    
    def extract_services_from_validator(validator)
      []
    end
    
    def extract_files_from_validator(validator)
      []
    end
    
    def flatten_attributes(hash, prefix = '')
      paths = []
      
      hash.each do |key, value|
        path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        
        if value.is_a?(Hash)
          paths.concat(flatten_attributes(value, path))
        else
          paths << path
        end
      end
      
      paths
    end
    
    def analyze_coverage
      # Perform analysis on collected data
    end
    
    def generate_summary
      total_recipes = @coverage_data[:recipes].size
      tested_recipes = @coverage_data[:recipes].count { |_, data| data[:tests].any? }
      
      total_validators = @coverage_data[:validators].size
      passing_validators = @coverage_data[:validators].count { |_, data| 
        data[:passed] > 0 && data[:failed] == 0 
      }
      
      {
        total_recipes: total_recipes,
        tested_recipes: tested_recipes,
        recipe_coverage: total_recipes > 0 ? (tested_recipes.to_f / total_recipes * 100).round(2) : 0,
        total_validators_used: total_validators,
        passing_validators: passing_validators,
        total_packages_tested: @coverage_data[:packages].size,
        total_services_tested: @coverage_data[:services].size,
        total_files_tested: @coverage_data[:files].size,
        duration: @end_time ? @end_time - @start_time : 0
      }
    end
    
    def analyze_recipe_coverage
      @coverage_data[:recipes].map do |path, data|
        {
          path: path,
          test_count: data[:tests].size,
          tests: data[:tests],
          pass_rate: data[:tests].any? ? (data[:passed].to_f / data[:tests].size * 100).round(2) : 0,
          resources_covered: data[:resources].to_a,
          attributes_used: data[:attributes].size
        }
      end
    end
    
    def analyze_resource_coverage
      resource_types = {}
      
      @coverage_data[:recipes].each do |_, data|
        data[:resources].each do |resource|
          resource_types[resource] ||= 0
          resource_types[resource] += 1
        end
      end
      
      resource_types.map do |type, count|
        {
          type: type,
          usage_count: count,
          recipes: @coverage_data[:recipes].select { |_, d| d[:resources].include?(type) }.keys
        }
      end
    end
    
    def analyze_attribute_coverage
      @coverage_data[:attributes].map do |path, count|
        {
          path: path,
          usage_count: count,
          frequency: 'high' # Would calculate based on total tests
        }
      end.sort_by { |a| -a[:usage_count] }
    end
    
    def analyze_validator_coverage
      @coverage_data[:validators].map do |name, data|
        {
          name: name,
          total_runs: data[:total_runs],
          success_rate: data[:total_runs] > 0 ? (data[:passed].to_f / data[:total_runs] * 100).round(2) : 0,
          test_count: data[:tests].size,
          common_errors: data[:errors].group_by(&:itself).transform_values(&:count).sort_by { |_, v| -v }.first(5)
        }
      end
    end
    
    def find_uncovered_items
      uncovered = {
        recipes: find_uncovered_recipes,
        resources: find_uncovered_resources,
        validators: find_unused_validators
      }
      
      uncovered
    end
    
    def find_uncovered_recipes
      # Would scan the recipes directory and compare with tested recipes
      []
    end
    
    def find_uncovered_resources
      # Would analyze recipes to find resources not covered by tests
      []
    end
    
    def find_unused_validators
      all_validators = PluginManager.instance.list(:validator)
      used_validators = @coverage_data[:validators].keys
      
      all_validators - used_validators
    end
    
    def calculate_metrics
      {
        avg_tests_per_recipe: calculate_avg_tests_per_recipe,
        avg_validators_per_test: calculate_avg_validators_per_test,
        most_tested_recipes: find_most_tested_recipes,
        least_tested_recipes: find_least_tested_recipes,
        validator_effectiveness: calculate_validator_effectiveness
      }
    end
    
    def calculate_avg_tests_per_recipe
      return 0 if @coverage_data[:recipes].empty?
      
      total_tests = @coverage_data[:recipes].sum { |_, data| data[:tests].size }
      (total_tests.to_f / @coverage_data[:recipes].size).round(2)
    end
    
    def calculate_avg_validators_per_test
      # Would need to track this during execution
      3.5 # Placeholder
    end
    
    def find_most_tested_recipes
      @coverage_data[:recipes]
        .sort_by { |_, data| -data[:tests].size }
        .first(5)
        .map { |path, data| { path: path, test_count: data[:tests].size } }
    end
    
    def find_least_tested_recipes
      @coverage_data[:recipes]
        .select { |_, data| data[:tests].any? }
        .sort_by { |_, data| data[:tests].size }
        .first(5)
        .map { |path, data| { path: path, test_count: data[:tests].size } }
    end
    
    def calculate_validator_effectiveness
      @coverage_data[:validators].map do |name, data|
        effectiveness = data[:failed] > 0 ? 
          (data[:failed].to_f / data[:total_runs] * 100).round(2) : 0
        
        {
          validator: name,
          effectiveness: effectiveness,
          classification: effectiveness > 10 ? 'high' : effectiveness > 5 ? 'medium' : 'low'
        }
      end
    end
    
    def create_coverage_html(report)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Mitamae Test Coverage Report</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .metric { 
              display: inline-block; 
              margin: 10px; 
              padding: 20px; 
              background: #f0f0f0; 
              border-radius: 8px;
            }
            .metric-value { font-size: 2em; font-weight: bold; }
            .metric-label { color: #666; }
            table { border-collapse: collapse; width: 100%; margin: 20px 0; }
            th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
            th { background: #f0f0f0; }
            .coverage-bar { 
              width: 100px; 
              height: 20px; 
              background: #e0e0e0; 
              position: relative;
              border-radius: 3px;
              overflow: hidden;
            }
            .coverage-fill { 
              height: 100%; 
              background: #4caf50;
              transition: width 0.3s ease;
            }
            .uncovered { background: #ffeb3b; }
            .low-coverage { background: #ff9800; }
          </style>
        </head>
        <body>
          <h1>Test Coverage Report</h1>
          
          <div class="metrics">
            <div class="metric">
              <div class="metric-value">#{report[:summary][:recipe_coverage]}%</div>
              <div class="metric-label">Recipe Coverage</div>
            </div>
            <div class="metric">
              <div class="metric-value">#{report[:summary][:tested_recipes]}/#{report[:summary][:total_recipes]}</div>
              <div class="metric-label">Recipes Tested</div>
            </div>
            <div class="metric">
              <div class="metric-value">#{report[:summary][:total_validators_used]}</div>
              <div class="metric-label">Validators Used</div>
            </div>
          </div>
          
          <h2>Recipe Coverage</h2>
          <table>
            <thead>
              <tr>
                <th>Recipe</th>
                <th>Tests</th>
                <th>Pass Rate</th>
                <th>Resources</th>
              </tr>
            </thead>
            <tbody>
              #{report[:recipe_coverage].map { |r| recipe_row_html(r) }.join}
            </tbody>
          </table>
          
          <h2>Validator Effectiveness</h2>
          <table>
            <thead>
              <tr>
                <th>Validator</th>
                <th>Runs</th>
                <th>Success Rate</th>
                <th>Effectiveness</th>
              </tr>
            </thead>
            <tbody>
              #{report[:validator_coverage].map { |v| validator_row_html(v) }.join}
            </tbody>
          </table>
          
          <p>Generated at: #{report[:generated_at]}</p>
        </body>
        </html>
      HTML
    end
    
    def recipe_row_html(recipe)
      <<~ROW
        <tr>
          <td>#{recipe[:path]}</td>
          <td>#{recipe[:test_count]}</td>
          <td>
            <div class="coverage-bar">
              <div class="coverage-fill" style="width: #{recipe[:pass_rate]}%"></div>
            </div>
            #{recipe[:pass_rate]}%
          </td>
          <td>#{recipe[:resources_covered].join(', ')}</td>
        </tr>
      ROW
    end
    
    def validator_row_html(validator)
      <<~ROW
        <tr>
          <td>#{validator[:name]}</td>
          <td>#{validator[:total_runs]}</td>
          <td>#{validator[:success_rate]}%</td>
          <td>#{validator[:common_errors].any? ? validator[:common_errors].first[0] : 'N/A'}</td>
        </tr>
      ROW
    end
  end
end