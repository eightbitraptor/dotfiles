require 'singleton'
require_relative 'error_handler'
require_relative 'plugin_system'

module MitamaeTest
  # Backward-compatible facade for the new plugin system
  class PluginManager
    include Singleton
    
    def initialize
      @plugin_system = PluginSystem.instance
    end
    
    # Backward compatibility methods
    def plugins
      @plugin_system.available_plugins
    end
    
    def register(type, name, klass)
      @plugin_system.registry.register(type, name, klass)
    end
    
    def get(type, name)
      @plugin_system.get_plugin(type, name)
    end
    
    def list(type)
      @plugin_system.plugin_names(type)
    end
    
    def load_plugins(plugin_dir = nil)
      plugin_dirs = [plugin_dir].compact
      plugin_dirs << File.join(Framework.instance.root_path, 'plugins')
      plugin_dirs << File.join(Framework.instance.root_path, 'lib', 'plugins')
      
      plugin_dirs.each do |dir|
        @plugin_system.load_plugin_directory(dir) if File.directory?(dir)
      end
    end
    
    def load_plugin(file_path)
      @plugin_system.load_plugin(file_path, lazy: false)
    end
    
    def create_instance(type, name, *args, **kwargs)
      @plugin_system.create_instance(type, name, *args, **kwargs)
    end

    # New enhanced methods
    def configure_plugin(type, name, &block)
      @plugin_system.configure_plugin(type, name, &block)
    end

    def plugin_metadata(type, name)
      @plugin_system.plugin_metadata(type, name)
    end

    def available_plugins(type = nil)
      @plugin_system.available_plugins(type)
    end
    
    # DSL for plugin registration
    def self.register_distribution(name, &block)
      klass = Class.new(Distributions::Base)
      klass.class_eval(&block) if block_given?
      instance.register(:distribution, name, klass)
    end
    
    def self.register_environment(name, &block)
      klass = Class.new(Environments::Base)
      klass.class_eval(&block) if block_given?
      instance.register(:environment, name, klass)
    end
    
    def self.register_validator(name, &block)
      klass = Class.new(Validators::Base)
      klass.class_eval(&block) if block_given?
      instance.register(:validator, name, klass)
    end
    
    def self.register_reporter(name, &block)
      klass = Class.new(Reporters::Base)
      klass.class_eval(&block) if block_given?
      instance.register(:reporter, name, klass)
    end
  end
  
  
  # Backward compatibility alias
  Plugin = PluginBase
end