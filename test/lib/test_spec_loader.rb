require 'yaml'

module MitamaeTest
  class TestSpecLoader
    include Logging
    include ErrorHandling
    
    attr_reader :specs, :errors
    
    def initialize
      @specs = {}
      @errors = []
      @validator = TestSpecValidator.new
    end
    
    def load_file(file_path)
      log_debug "Loading test spec from: #{file_path}"
      
      safe_execute("load test spec #{file_path}") do
        content = File.read(file_path)
        documents = YAML.load_stream(content)
        
        documents.each_with_index do |doc, index|
          next if doc.nil? || doc.empty?
          
          # Validate the spec
          validation_errors = @validator.validate(doc)
          if validation_errors.any?
            @errors << {
              file: file_path,
              document: index + 1,
              errors: validation_errors
            }
            next
          end
          
          # Create TestSpec instance
          spec = TestSpec.new(doc)
          
          # Check for duplicate names
          if @specs.key?(spec.name)
            @errors << {
              file: file_path,
              document: index + 1,
              errors: ["Duplicate test name: #{spec.name}"]
            }
            next
          end
          
          @specs[spec.name] = spec
          log_debug "Loaded test spec: #{spec.name}"
        end
      end
    rescue StandardError => e
      @errors << {
        file: file_path,
        errors: ["Failed to load file: #{e.message}"]
      }
    end
    
    def load_directory(dir_path, pattern = '**/*_spec.yml')
      log_info "Loading test specs from directory: #{dir_path}"
      
      Dir.glob(File.join(dir_path, pattern)).sort.each do |file|
        load_file(file)
      end
      
      log_info "Loaded #{@specs.size} test specs with #{@errors.size} errors"
    end
    
    def load_specs(paths)
      Array(paths).each do |path|
        if File.directory?(path)
          load_directory(path)
        elsif File.file?(path)
          load_file(path)
        else
          @errors << {
            file: path,
            errors: ["Path does not exist: #{path}"]
          }
        end
      end
    end
    
    def get_spec(name)
      @specs[name]
    end
    
    def all_specs
      @specs.values
    end
    
    def filter_specs(filter)
      @specs.values.select { |spec| filter.matches?(spec) }
    end
    
    def has_errors?
      !@errors.empty?
    end
    
    def error_summary
      return "No errors" if @errors.empty?
      
      summary = ["Test spec loading errors:"]
      @errors.each do |error|
        summary << "  File: #{error[:file]}"
        summary << "  Document: #{error[:document]}" if error[:document]
        error[:errors].each do |msg|
          summary << "    - #{msg}"
        end
      end
      
      summary.join("\n")
    end
    
    def validate_dependencies
      missing_deps = []
      circular_deps = []
      
      # Check for missing dependencies
      @specs.each do |name, spec|
        spec.dependencies.requires.each do |dep|
          unless @specs.key?(dep)
            missing_deps << {
              spec: name,
              missing: dep,
              type: 'requires'
            }
          end
        end
        
        spec.dependencies.before.each do |dep|
          unless @specs.key?(dep)
            missing_deps << {
              spec: name,
              missing: dep,
              type: 'before'
            }
          end
        end
      end
      
      # Check for circular dependencies
      @specs.each do |name, spec|
        visited = Set.new
        path = []
        if has_circular_dependency?(name, visited, path)
          circular_deps << {
            spec: name,
            cycle: path.join(' -> ')
          }
        end
      end
      
      {
        missing: missing_deps,
        circular: circular_deps,
        valid: missing_deps.empty? && circular_deps.empty?
      }
    end
    
    private
    
    def has_circular_dependency?(name, visited, path)
      return false unless @specs.key?(name)
      return true if path.include?(name)
      
      path << name
      spec = @specs[name]
      
      spec.dependencies.requires.each do |dep|
        if has_circular_dependency?(dep, visited, path.dup)
          return true
        end
      end
      
      visited.add(name)
      false
    end
  end
  
  class TestSpecValidator
    REQUIRED_FIELDS = %w[name recipe environment validators].freeze
    VALID_ENVIRONMENT_TYPES = %w[container vm local].freeze
    VALID_VALIDATOR_TYPES = %w[package service configuration_file idempotency functional_test custom].freeze
    
    def validate(spec_data)
      errors = []
      
      # Check required fields
      REQUIRED_FIELDS.each do |field|
        if spec_data[field].nil? || spec_data[field].to_s.empty?
          errors << "Missing required field: #{field}"
        end
      end
      
      # Validate name format
      if spec_data['name']
        unless spec_data['name'].match?(/^[a-zA-Z0-9_-]+$/)
          errors << "Invalid name format. Use only letters, numbers, underscores, and hyphens"
        end
      end
      
      # Validate recipe
      if spec_data['recipe']
        errors.concat(validate_recipe(spec_data['recipe']))
      end
      
      # Validate environment
      if spec_data['environment']
        errors.concat(validate_environment(spec_data['environment']))
      end
      
      # Validate validators
      if spec_data['validators']
        errors.concat(validate_validators(spec_data['validators']))
      end
      
      # Validate options
      if spec_data['options']
        errors.concat(validate_options(spec_data['options']))
      end
      
      errors
    end
    
    private
    
    def validate_recipe(recipe)
      errors = []
      
      unless recipe['path']
        errors << "Recipe must have a path"
      end
      
      if recipe['node_json'] && !recipe['node_json'].is_a?(Hash)
        errors << "Recipe node_json must be a hash"
      end
      
      errors
    end
    
    def validate_environment(env)
      errors = []
      
      unless env['type']
        errors << "Environment must have a type"
      end
      
      if env['type'] && !VALID_ENVIRONMENT_TYPES.include?(env['type'])
        errors << "Invalid environment type: #{env['type']}. Valid types: #{VALID_ENVIRONMENT_TYPES.join(', ')}"
      end
      
      unless env['distribution']
        errors << "Environment must have a distribution"
      end
      
      errors
    end
    
    def validate_validators(validators)
      errors = []
      
      unless validators.is_a?(Array)
        errors << "Validators must be an array"
        return errors
      end
      
      if validators.empty?
        errors << "At least one validator must be specified"
      end
      
      validators.each_with_index do |validator, index|
        unless validator['type']
          errors << "Validator #{index + 1} must have a type"
          next
        end
        
        unless VALID_VALIDATOR_TYPES.include?(validator['type'])
          errors << "Invalid validator type: #{validator['type']}. Valid types: #{VALID_VALIDATOR_TYPES.join(', ')}"
        end
        
        if validator['config'] && !validator['config'].is_a?(Hash)
          errors << "Validator #{index + 1} config must be a hash"
        end
      end
      
      errors
    end
    
    def validate_options(options)
      errors = []
      
      if options['timeout']
        timeout = options['timeout']
        if !timeout.is_a?(Integer) || timeout <= 0 || timeout > 3600
          errors << "Timeout must be between 1 and 3600 seconds"
        end
      end
      
      if options['retries']
        retries = options['retries']
        if !retries.is_a?(Integer) || retries < 0 || retries > 10
          errors << "Retries must be between 0 and 10"
        end
      end
      
      errors
    end
  end
end