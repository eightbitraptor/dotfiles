require 'yaml'
require 'singleton'
require_relative 'error_handler'

module MitamaeTest
  class Configuration
    include Singleton
    
    attr_reader :config
    
    DEFAULT_CONFIG = {
      'test_timeout' => 300,
      'parallel_workers' => 4,
      'environments' => {
        'default' => 'container'
      },
      'distributions' => {
        'default' => 'arch',
        'supported' => ['arch', 'ubuntu', 'debian', 'fedora']
      },
      'logging' => {
        'level' => 'info',
        'format' => 'detailed'
      },
      'paths' => {
        'specs' => 'specs',
        'environments' => 'environments',
        'validators' => 'validators',
        'reports' => 'reports'
      },
      'reporting' => {
        'format' => 'console',
        'save_results' => true
      }
    }.freeze
    
    def initialize
      @config = DEFAULT_CONFIG.dup
      @config_file = nil
    end
    
    def load(config_path = nil)
      @config_file = config_path || find_config_file
      
      if @config_file && File.exist?(@config_file)
        begin
          user_config = YAML.load_file(@config_file)
          deep_merge!(@config, user_config) if user_config
        rescue Psych::SyntaxError => e
          raise ConfigurationError, "Invalid YAML in #{@config_file}: #{e.message}"
        end
      end
      
      validate_config!
      @config
    end
    
    def [](key_path)
      get(key_path)
    end

    def []=(key_path, value)
      set(key_path, value)
    end

    def get(key_path, default = nil)
      keys = key_path.to_s.split('.')
      keys.reduce(@config) do |current_value, key|
        return default unless current_value.is_a?(Hash) && current_value.key?(key)
        current_value[key]
      end
    end
    
    def set(key_path, value)
      keys = key_path.to_s.split('.')
      *path_keys, final_key = keys
      
      target = path_keys.reduce(@config) do |current_target, key|
        current_target[key] ||= {}
        current_target[key]
      end
      
      target[final_key] = value
    end
    
    def reload!
      @config = DEFAULT_CONFIG.dup
      load(@config_file)
    end
    
    private
    
    def find_config_file
      search_paths = [
        'mitamae-test.yml',
        'mitamae-test.yaml',
        '.mitamae-test.yml',
        '.mitamae-test.yaml',
        'config/mitamae-test.yml',
        'test/config.yml'
      ]
      
      search_paths.each do |path|
        full_path = File.join(Framework.instance.root_path, path)
        return full_path if File.exist?(full_path)
      end
      
      nil
    end
    
    def deep_merge!(target, source)
      source.each do |key, value|
        target[key] = case [target[key], value]
                     when [Hash, Hash]
                       deep_merge!(target[key], value)
                       target[key]
                     else
                       value
                     end
      end
    end
    
    def validate_config!
      # Validate required fields
      raise ConfigurationError, "Test timeout must be positive" if get('test_timeout', 0) <= 0
      
      # Validate supported distributions
      supported = get('distributions.supported', [])
      raise ConfigurationError, "No distributions configured" if supported.empty?
      
      default_dist = get('distributions.default')
      unless supported.include?(default_dist)
        raise ConfigurationError, "Default distribution '#{default_dist}' not in supported list"
      end
    end
  end
  
end