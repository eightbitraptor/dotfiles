module MitamaeTest
  class TestFilterBuilder
    def initialize
      @filters = []
    end
    
    def with_name(pattern)
      @filters << NameFilter.new(pattern)
      self
    end
    
    def with_tags(*tags)
      @filters << TagFilter.new(tags.flatten, :include)
      self
    end
    
    def without_tags(*tags)
      @filters << TagFilter.new(tags.flatten, :exclude)
      self
    end
    
    def with_distribution(*distributions)
      @filters << DistributionFilter.new(distributions.flatten)
      self
    end
    
    def with_environment(*environments)
      @filters << EnvironmentFilter.new(environments.flatten)
      self
    end
    
    def modified_since(timestamp)
      @filters << ModifiedSinceFilter.new(timestamp)
      self
    end
    
    def failed_only
      @filters << StatusFilter.new(:failed)
      self
    end
    
    def quick_tests(max_duration = 60)
      @filters << DurationFilter.new(max_duration)
      self
    end
    
    def build
      CompositeFilter.new(@filters)
    end
    
    # Convenience class methods
    class << self
      def parse_cli_args(args)
        builder = new
        
        args.each do |arg|
          case arg
          when /^--tag=(.+)$/
            builder.with_tags($1.split(','))
          when /^--name=(.+)$/
            builder.with_name($1)
          when /^--dist=(.+)$/
            builder.with_distribution($1.split(','))
          when /^--env=(.+)$/
            builder.with_environment($1.split(','))
          when '--failed'
            builder.failed_only
          when '--quick'
            builder.quick_tests
          when /^--exclude-tag=(.+)$/
            builder.without_tags($1.split(','))
          end
        end
        
        builder.build
      end
      
      def from_config(config)
        builder = new
        
        builder.with_name(config['name_pattern']) if config['name_pattern']
        builder.with_tags(*config['tags']) if config['tags']
        builder.without_tags(*config['exclude_tags']) if config['exclude_tags']
        builder.with_distribution(*config['distributions']) if config['distributions']
        builder.with_environment(*config['environments']) if config['environments']
        
        builder.build
      end
    end
  end
  
  # Base filter class
  class BaseFilter
    def matches?(spec)
      raise NotImplementedError
    end
  end
  
  # Filter by test name pattern
  class NameFilter < BaseFilter
    def initialize(pattern)
      @pattern = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
    end
    
    def matches?(spec)
      spec.name.match?(@pattern)
    end
  end
  
  # Filter by tags
  class TagFilter < BaseFilter
    def initialize(tags, mode = :include)
      @tags = Set.new(tags)
      @mode = mode
    end
    
    def matches?(spec)
      spec_tags = Set.new(spec.tags)
      
      case @mode
      when :include
        !(@tags & spec_tags).empty?
      when :exclude
        (@tags & spec_tags).empty?
      else
        true
      end
    end
  end
  
  # Filter by distribution
  class DistributionFilter < BaseFilter
    def initialize(distributions)
      @distributions = Set.new(distributions)
    end
    
    def matches?(spec)
      @distributions.include?(spec.environment.distribution)
    end
  end
  
  # Filter by environment type
  class EnvironmentFilter < BaseFilter
    def initialize(environments)
      @environments = Set.new(environments)
    end
    
    def matches?(spec)
      @environments.include?(spec.environment.type)
    end
  end
  
  # Filter by modification time (for development workflow)
  class ModifiedSinceFilter < BaseFilter
    def initialize(timestamp)
      @timestamp = timestamp
    end
    
    def matches?(spec)
      # Check if recipe file was modified since timestamp
      recipe_path = spec.recipe.path
      return true unless File.exist?(recipe_path)
      
      File.mtime(recipe_path) > @timestamp
    end
  end
  
  # Filter by previous test status
  class StatusFilter < BaseFilter
    def initialize(status)
      @status = status
      @tracker = TestStatusTracker.instance
    end
    
    def matches?(spec)
      # Check if this test failed in the last run
      current_suite = @tracker.current_suite
      return true unless current_suite
      
      result = current_suite.results[spec.name]
      return true unless result
      
      case @status
      when :failed
        result.status == :failed || result.status == :error
      when :passed
        result.status == :passed
      else
        true
      end
    end
  end
  
  # Filter by expected duration
  class DurationFilter < BaseFilter
    def initialize(max_duration)
      @max_duration = max_duration
    end
    
    def matches?(spec)
      # Use configured timeout as proxy for duration
      spec.timeout <= @max_duration
    end
  end
  
  # Composite filter that combines multiple filters
  class CompositeFilter < BaseFilter
    def initialize(filters)
      @filters = filters
    end
    
    def matches?(spec)
      @filters.all? { |filter| filter.matches?(spec) }
    end
    
    def empty?
      @filters.empty?
    end
  end
  
  # Predefined filter sets for common scenarios
  module FilterPresets
    def self.development
      TestFilterBuilder.new
        .with_environment('local')
        .quick_tests(120)
        .build
    end
    
    def self.ci_quick
      TestFilterBuilder.new
        .with_tags('critical', 'core')
        .quick_tests(300)
        .build
    end
    
    def self.ci_full
      TestFilterBuilder.new
        .without_tags('experimental', 'slow')
        .build
    end
    
    def self.distribution(dist)
      TestFilterBuilder.new
        .with_distribution(dist)
        .build
    end
    
    def self.smoke_test
      TestFilterBuilder.new
        .with_tags('smoke')
        .quick_tests(60)
        .build
    end
  end
end