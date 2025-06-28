require 'digest'
require 'json'
require 'fileutils'

module MitamaeTest
  class TestCache
    include Logging
    
    attr_reader :cache_dir
    
    def initialize(cache_dir = nil)
      @cache_dir = cache_dir || default_cache_dir
      @cache_index = {}
      @dirty = false
      
      ensure_cache_directory
      load_cache_index
    end
    
    def get_cached_result(test_spec)
      cache_key = generate_cache_key(test_spec)
      return nil unless cache_valid?(cache_key, test_spec)
      
      cache_file = cache_file_path(cache_key)
      return nil unless File.exist?(cache_file)
      
      begin
        data = JSON.parse(File.read(cache_file), symbolize_names: true)
        log_debug "Cache hit for test: #{test_spec.name}"
        
        CachedResult.new(
          test_spec: test_spec,
          status: data[:status].to_sym,
          duration: data[:duration],
          validation_results: deserialize_validation_results(data[:validation_results]),
          cached_at: Time.parse(data[:cached_at])
        )
      rescue => e
        log_warn "Failed to read cache for #{test_spec.name}: #{e.message}"
        nil
      end
    end
    
    def store_result(test_spec, result)
      cache_key = generate_cache_key(test_spec)
      cache_file = cache_file_path(cache_key)
      
      cache_data = {
        test_name: test_spec.name,
        status: result.status,
        duration: result.duration,
        validation_results: serialize_validation_results(result.validation_results),
        cached_at: Time.now.iso8601,
        metadata: extract_metadata(test_spec)
      }
      
      File.write(cache_file, JSON.pretty_generate(cache_data))
      
      # Update index
      @cache_index[cache_key] = {
        test_name: test_spec.name,
        cached_at: Time.now,
        file_path: cache_file,
        dependencies: extract_dependencies(test_spec)
      }
      
      @dirty = true
      save_cache_index if @dirty
      
      log_debug "Cached result for test: #{test_spec.name}"
    end
    
    def invalidate(test_spec)
      cache_key = generate_cache_key(test_spec)
      cache_file = cache_file_path(cache_key)
      
      if File.exist?(cache_file)
        File.delete(cache_file)
        @cache_index.delete(cache_key)
        @dirty = true
        log_debug "Invalidated cache for test: #{test_spec.name}"
      end
    end
    
    def invalidate_all
      FileUtils.rm_rf(@cache_dir)
      ensure_cache_directory
      @cache_index.clear
      @dirty = true
      save_cache_index
      log_info "Cleared all test cache"
    end
    
    def cache_stats
      total_size = Dir.glob(File.join(@cache_dir, '**/*')).
                      select { |f| File.file?(f) }.
                      sum { |f| File.size(f) }
      
      {
        total_entries: @cache_index.size,
        total_size: total_size,
        oldest_entry: @cache_index.values.map { |v| v[:cached_at] }.min,
        newest_entry: @cache_index.values.map { |v| v[:cached_at] }.max
      }
    end
    
    def prune_old_entries(max_age_days = 7)
      cutoff_time = Time.now - (max_age_days * 24 * 60 * 60)
      pruned_count = 0
      
      @cache_index.each do |key, entry|
        if entry[:cached_at] < cutoff_time
          File.delete(entry[:file_path]) if File.exist?(entry[:file_path])
          @cache_index.delete(key)
          pruned_count += 1
          @dirty = true
        end
      end
      
      save_cache_index if @dirty
      log_info "Pruned #{pruned_count} old cache entries"
      pruned_count
    end
    
    private
    
    def default_cache_dir
      File.join(Framework.instance.root_path, '.mitamae-test-cache')
    end
    
    def ensure_cache_directory
      FileUtils.mkdir_p(@cache_dir) unless File.directory?(@cache_dir)
      FileUtils.mkdir_p(File.join(@cache_dir, 'results'))
    end
    
    def cache_index_path
      File.join(@cache_dir, 'index.json')
    end
    
    def load_cache_index
      return unless File.exist?(cache_index_path)
      
      begin
        data = JSON.parse(File.read(cache_index_path), symbolize_names: true)
        @cache_index = data.transform_values do |entry|
          entry[:cached_at] = Time.parse(entry[:cached_at])
          entry
        end
      rescue => e
        log_warn "Failed to load cache index: #{e.message}"
        @cache_index = {}
      end
    end
    
    def save_cache_index
      return unless @dirty
      
      data = @cache_index.transform_values do |entry|
        entry.merge(cached_at: entry[:cached_at].iso8601)
      end
      
      File.write(cache_index_path, JSON.pretty_generate(data))
      @dirty = false
    end
    
    def generate_cache_key(test_spec)
      # Create a unique key based on test configuration
      key_data = {
        name: test_spec.name,
        recipe_path: test_spec.recipe.path,
        recipe_checksum: file_checksum(test_spec.recipe.path),
        node_json: test_spec.recipe.node_json,
        environment: test_spec.environment.to_h,
        validators: test_spec.validators.map(&:to_h)
      }
      
      Digest::SHA256.hexdigest(key_data.to_json)
    end
    
    def cache_file_path(cache_key)
      File.join(@cache_dir, 'results', "#{cache_key}.json")
    end
    
    def cache_valid?(cache_key, test_spec)
      entry = @cache_index[cache_key]
      return false unless entry
      
      # Check if recipe file has been modified
      recipe_path = test_spec.recipe.path
      if File.exist?(recipe_path)
        recipe_mtime = File.mtime(recipe_path)
        return false if recipe_mtime > entry[:cached_at]
      end
      
      # Check if any dependency files have been modified
      entry[:dependencies].each do |dep_path|
        if File.exist?(dep_path)
          dep_mtime = File.mtime(dep_path)
          return false if dep_mtime > entry[:cached_at]
        end
      end
      
      true
    end
    
    def file_checksum(path)
      return nil unless File.exist?(path)
      Digest::SHA256.file(path).hexdigest
    end
    
    def extract_metadata(test_spec)
      {
        tags: test_spec.tags,
        description: test_spec.description,
        timeout: test_spec.timeout,
        environment_type: test_spec.environment.type,
        distribution: test_spec.environment.distribution
      }
    end
    
    def extract_dependencies(test_spec)
      deps = [test_spec.recipe.path]
      
      # Add any referenced files from setup
      test_spec.setup.files.each do |file_spec|
        deps << file_spec['source'] if file_spec['source']
      end
      
      # Add any custom validator files
      # This would need to be expanded based on your validator implementations
      
      deps.select { |path| File.exist?(path) }
    end
    
    def serialize_validation_results(validators)
      validators.map do |validator|
        {
          type: validator.class.plugin_name,
          success: validator.success?,
          errors: validator.errors.map { |e| error_to_hash(e) },
          warnings: validator.warnings.map { |w| warning_to_hash(w) }
        }
      end
    end
    
    def deserialize_validation_results(data)
      # Return simplified validation results
      # In a real implementation, you might reconstruct the actual validator objects
      data.map do |validator_data|
        MockValidatorResult.new(
          validator_data[:type],
          validator_data[:success],
          validator_data[:errors],
          validator_data[:warnings]
        )
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
  end
  
  class CachedResult
    attr_reader :test_spec, :status, :duration, :validation_results, :cached_at
    
    def initialize(test_spec:, status:, duration:, validation_results:, cached_at:)
      @test_spec = test_spec
      @status = status
      @duration = duration
      @validation_results = validation_results
      @cached_at = cached_at
    end
    
    def success?
      @status == :passed
    end
    
    def from_cache?
      true
    end
  end
  
  class MockValidatorResult
    attr_reader :type, :errors, :warnings
    
    def initialize(type, success, errors, warnings)
      @type = type
      @success = success
      @errors = errors
      @warnings = warnings
    end
    
    def success?
      @success
    end
    
    def class
      OpenStruct.new(plugin_name: @type)
    end
  end
  
  # Cache-aware test runner extension
  module CacheableTestRunner
    def self.prepended(base)
      base.class_eval do
        attr_accessor :cache
      end
    end
    
    def initialize(options = {})
      super
      @cache = options[:cache] || TestCache.new
      @use_cache = options.fetch(:use_cache, true)
      @cache_write = options.fetch(:cache_write, true)
    end
    
    def run_single(test_spec)
      # Try to get cached result first
      if @use_cache
        cached_result = @cache.get_cached_result(test_spec)
        if cached_result
          log_info "Using cached result for: #{test_spec.name}"
          @results << cached_result
          
          # Report the cached result
          @reporter.start_test(test_spec)
          @reporter.report_test_result(cached_result)
          @reporter.finish_test(test_spec)
          
          return cached_result
        end
      end
      
      # Run the test normally
      result = super
      
      # Cache the result if successful
      if @cache_write && result.status == :passed
        @cache.store_result(test_spec, result)
      end
      
      result
    end
  end
end