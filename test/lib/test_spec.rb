module MitamaeTest
  class TestSpec
    attr_reader :name, :description, :tags, :recipe, :environment, :validators,
                :dependencies, :setup, :cleanup, :options, :skip_reason
    
    def initialize(spec_data)
      @name = spec_data['name']
      @description = spec_data['description']
      @tags = Array(spec_data['tags'])
      @skip_reason = spec_data['skip']
      
      # Recipe configuration
      @recipe = RecipeConfig.new(spec_data['recipe'])
      
      # Environment configuration
      @environment = EnvironmentConfig.new(spec_data['environment'])
      
      # Dependencies
      @dependencies = DependencyConfig.new(spec_data['dependencies'] || {})
      
      # Setup configuration
      @setup = SetupConfig.new(spec_data['setup'] || {})
      
      # Cleanup configuration
      @cleanup = CleanupConfig.new(spec_data['cleanup'] || {})
      
      # Validators
      @validators = parse_validators(spec_data['validators'] || [])
      
      # Execution options
      @options = ExecutionOptions.new(spec_data['options'] || {})
    end
    
    def skipped?
      return false unless @skip_reason
      
      case @skip_reason
      when Hash
        skip_until_date = @skip_reason['until']
        return Date.today < Date.parse(skip_until_date) if skip_until_date
        true
      else
        true
      end
    end
    
    def skip_message
      return nil unless skipped?
      
      if @skip_reason.is_a?(Hash)
        @skip_reason['reason'] || "Test skipped"
      else
        @skip_reason.to_s
      end
    end
    
    def parallel_group
      @options.parallel_group
    end
    
    def timeout
      @options.timeout
    end
    
    def matches_filter?(filter)
      return true if filter.nil? || filter.empty?
      
      return true if name_matches_filter?(filter)
      return true if tags_match_filter?(filter)
      return false if excluded_by_filter?(filter)
      
      filter.name_pattern.nil? && filter.tags.nil?
    end

    private

    def name_matches_filter?(filter)
      filter.name_pattern && @name.match?(filter.name_pattern)
    end

    def tags_match_filter?(filter)
      filter.tags&.any? && (filter.tags & @tags).any?
    end

    def excluded_by_filter?(filter)
      filter.exclude_tags&.any? && (filter.exclude_tags & @tags).any?
    end
    
    def to_h
      {
        name: @name,
        description: @description,
        tags: @tags,
        recipe: @recipe.to_h,
        environment: @environment.to_h,
        validators: @validators.map(&:to_h),
        dependencies: @dependencies.to_h,
        options: @options.to_h
      }
    end
    
    private
    
    def parse_validators(validator_specs)
      validator_specs.map do |spec|
        ValidatorConfig.new(spec)
      end
    end
  end
  
  class RecipeConfig
    attr_reader :path, :node_json, :data_bags, :environment
    
    def initialize(config)
      @path = config['path']
      @node_json = config['node_json'] || {}
      @data_bags = config['data_bags'] || {}
      @environment = config['environment'] || {}
    end
    
    def to_h
      {
        path: @path,
        node_json: @node_json,
        data_bags: @data_bags,
        environment: @environment
      }
    end
  end
  
  class EnvironmentConfig
    attr_reader :type, :distribution, :options
    
    def initialize(config)
      @type = config['type']
      @distribution = config['distribution']
      @options = config['options'] || {}
    end
    
    def to_h
      {
        type: @type,
        distribution: @distribution,
        options: @options
      }
    end
  end
  
  class DependencyConfig
    attr_reader :requires, :before
    
    def initialize(config)
      @requires = Array(config['requires'])
      @before = Array(config['before'])
    end
    
    def has_dependencies?
      !@requires.empty? || !@before.empty?
    end
    
    def to_h
      {
        requires: @requires,
        before: @before
      }
    end
  end
  
  class SetupConfig
    attr_reader :commands, :files, :packages
    
    def initialize(config)
      @commands = Array(config['commands'])
      @files = Array(config['files'])
      @packages = Array(config['packages'])
    end
    
    def empty?
      @commands.empty? && @files.empty? && @packages.empty?
    end
    
    def to_h
      {
        commands: @commands,
        files: @files,
        packages: @packages
      }
    end
  end
  
  class CleanupConfig
    attr_reader :always, :commands
    
    def initialize(config)
      @always = config['always'] || false
      @commands = Array(config['commands'])
    end
    
    def to_h
      {
        always: @always,
        commands: @commands
      }
    end
  end
  
  class ValidatorConfig
    attr_reader :type, :name, :config
    
    def initialize(spec)
      @type = spec['type']
      @name = spec['name'] || @type
      @config = spec['config'] || {}
    end
    
    def to_h
      {
        type: @type,
        name: @name,
        config: @config
      }
    end
  end
  
  class ExecutionOptions
    attr_reader :timeout, :retries, :continue_on_error, :parallel_group, :resources
    
    def initialize(options)
      @timeout = options['timeout'] || 300
      @retries = options['retries'] || 0
      @continue_on_error = options['continue_on_error'] || false
      @parallel_group = options['parallel_group']
      @resources = ResourceRequirements.new(options['resources'] || {})
    end
    
    def to_h
      {
        timeout: @timeout,
        retries: @retries,
        continue_on_error: @continue_on_error,
        parallel_group: @parallel_group,
        resources: @resources.to_h
      }
    end
  end
  
  class ResourceRequirements
    attr_reader :cpu, :memory, :disk
    
    def initialize(resources)
      @cpu = resources['cpu'] || 1.0
      @memory = parse_memory(resources['memory'] || '512M')
      @disk = parse_disk(resources['disk'] || '1G')
    end
    
    def to_h
      {
        cpu: @cpu,
        memory: @memory,
        disk: @disk
      }
    end
    
    private
    
    def parse_memory(memory_str)
      return memory_str if memory_str.is_a?(Numeric)
      
      case memory_str.upcase
      when /^(\d+)K$/
        $1.to_i * 1024
      when /^(\d+)M$/
        $1.to_i * 1024 * 1024
      when /^(\d+)G$/
        $1.to_i * 1024 * 1024 * 1024
      else
        memory_str.to_i
      end
    end
    
    def parse_disk(disk_str)
      parse_memory(disk_str)  # Same parsing logic
    end
  end
  
  class TestFilter
    attr_reader :name_pattern, :tags, :exclude_tags, :distributions, :environments
    
    def initialize(options = {})
      @name_pattern = options[:name_pattern] ? Regexp.new(options[:name_pattern]) : nil
      @tags = Array(options[:tags])
      @exclude_tags = Array(options[:exclude_tags])
      @distributions = Array(options[:distributions])
      @environments = Array(options[:environments])
    end
    
    def matches?(spec)
      # Check positive filters
      if @name_pattern && !spec.name.match?(@name_pattern)
        return false
      end
      
      if !@tags.empty? && (@tags & spec.tags).empty?
        return false
      end
      
      if !@distributions.empty? && !@distributions.include?(spec.environment.distribution)
        return false
      end
      
      if !@environments.empty? && !@environments.include?(spec.environment.type)
        return false
      end
      
      # Check negative filters
      if !@exclude_tags.empty? && !(@exclude_tags & spec.tags).empty?
        return false
      end
      
      true
    end
  end
end