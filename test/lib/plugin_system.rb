# frozen_string_literal: true

require 'singleton'
require 'forwardable'
require 'set'

module MitamaeTest
  # Enhanced plugin system with lazy loading and dependency resolution
  class PluginSystem
    include Singleton
    extend Forwardable

    attr_reader :registry

    def initialize
      @registry = PluginRegistry.new
      @loader = PluginLoader.new
      @dependency_resolver = PluginDependencyResolver.new(@registry)
      @loaded_plugins = Set.new
    end

    def load_plugin(identifier, lazy: true)
      return if @loaded_plugins.include?(identifier)

      if lazy
        @registry.register_lazy(identifier)
      else
        plugin_class = @loader.load(identifier)
        @registry.register_eager(identifier, plugin_class)
      end

      @loaded_plugins.add(identifier)
    end

    def get_plugin(type, name)
      @dependency_resolver.resolve(type, name)
    end

    def create_instance(type, name, *args, **kwargs)
      plugin_class = get_plugin(type, name)
      
      if kwargs.empty?
        plugin_class.new(*args)
      else
        plugin_class.new(*args, **kwargs)
      end
    end

    def load_plugin_directory(directory, pattern: '**/*.rb')
      @loader.load_directory(directory, pattern: pattern) do |file_path|
        load_plugin(file_path, lazy: true)
      end
    end

    def configure_plugin(type, name, &configuration_block)
      @registry.add_configuration(type, name, configuration_block)
    end

    def plugin_metadata(type, name)
      @registry.metadata(type, name)
    end

    def available_plugins(type = nil)
      if type
        @registry.plugins_by_type(type)
      else
        @registry.all_plugins
      end
    end

    def reset!
      @registry.clear
      @loaded_plugins.clear
    end

    # Delegation methods for backward compatibility
    def register(type, name, plugin_class, metadata: {})
      @registry.register(type, name, plugin_class, metadata: metadata)
    end

    def registered?(type, name)
      @registry.registered?(type, name)
    end

    def plugin_names(type)
      @registry.plugin_names(type)
    end

    def plugin_types
      @registry.plugin_types
    end
  end

  # Registry for storing plugin information with lazy loading support
  class PluginRegistry
    def initialize
      @plugins = {}
      @lazy_plugins = {}
      @configurations = {}
      @metadata = {}
    end

    def register(type, name, plugin_class, metadata: {})
      @plugins[type] ||= {}
      @plugins[type][name] = plugin_class
      @metadata[plugin_key(type, name)] = metadata
    end

    def register_lazy(type, name, load_proc, metadata: {})
      @lazy_plugins[type] ||= {}
      @lazy_plugins[type][name] = load_proc
      @metadata[plugin_key(type, name)] = metadata.merge(lazy: true)
    end

    def register_eager(type, name, plugin_class, metadata: {})
      register(type, name, plugin_class, metadata: metadata.merge(lazy: false))
    end

    def get(type, name)
      # Try eager-loaded plugins first
      if @plugins.dig(type, name)
        return @plugins[type][name]
      end

      # Try lazy-loaded plugins
      load_proc = @lazy_plugins.dig(type, name)
      if load_proc
        plugin_class = load_proc.call
        register(type, name, plugin_class)
        @lazy_plugins[type].delete(name)
        return plugin_class
      end

      raise PluginNotFoundError, "Plugin '#{name}' of type '#{type}' not found"
    end

    def registered?(type, name)
      @plugins.dig(type, name) || @lazy_plugins.dig(type, name)
    end

    def plugin_names(type)
      eager_names = @plugins[type]&.keys || []
      lazy_names = @lazy_plugins[type]&.keys || []
      (eager_names + lazy_names).uniq
    end

    def plugin_types
      (@plugins.keys + @lazy_plugins.keys).uniq
    end

    def plugins_by_type(type)
      plugin_names(type).map { |name| [name, metadata(type, name)] }.to_h
    end

    def all_plugins
      plugin_types.map { |type| [type, plugins_by_type(type)] }.to_h
    end

    def metadata(type, name)
      @metadata[plugin_key(type, name)] || {}
    end

    def add_configuration(type, name, configuration_block)
      @configurations[plugin_key(type, name)] = configuration_block
    end

    def get_configuration(type, name)
      @configurations[plugin_key(type, name)]
    end

    def clear
      @plugins.clear
      @lazy_plugins.clear
      @configurations.clear
      @metadata.clear
    end

    private

    def plugin_key(type, name)
      "#{type}:#{name}"
    end
  end

  # Handles loading plugins from files and directories
  class PluginLoader
    def initialize
      @load_paths = []
      @loaded_files = Set.new
    end

    def add_load_path(path)
      @load_paths << path unless @load_paths.include?(path)
    end

    def load(identifier)
      case identifier
      when String
        load_from_file(identifier)
      when Class
        identifier
      when Proc
        identifier.call
      else
        raise PluginLoadError, "Cannot load plugin from #{identifier.class}"
      end
    end

    def load_directory(directory, pattern: '**/*.rb')
      return unless File.directory?(directory)

      Dir.glob(File.join(directory, pattern)).each do |file_path|
        next if @loaded_files.include?(file_path)

        begin
          require file_path
          @loaded_files.add(file_path)
          yield file_path if block_given?
        rescue LoadError => e
          raise PluginLoadError, "Failed to load plugin file #{file_path}: #{e.message}"
        rescue StandardError => e
          raise PluginError, "Error loading plugin from #{file_path}: #{e.message}"
        end
      end
    end

    private

    def load_from_file(file_path)
      # Try absolute path first
      if File.exist?(file_path)
        require file_path
        return find_plugin_class_in_file(file_path)
      end

      # Try load paths
      @load_paths.each do |load_path|
        full_path = File.join(load_path, file_path)
        if File.exist?(full_path)
          require full_path
          return find_plugin_class_in_file(full_path)
        end
      end

      raise PluginLoadError, "Plugin file not found: #{file_path}"
    end

    def find_plugin_class_in_file(file_path)
      # This is a simplified approach - in a real implementation,
      # you might want to track which classes are defined when loading a file
      base_name = File.basename(file_path, '.rb')
      class_name = base_name.split('_').map(&:capitalize).join

      # Try to find the class in various namespaces
      [
        "MitamaeTest::Validators::#{class_name}",
        "MitamaeTest::Environments::#{class_name}",
        "MitamaeTest::Reporters::#{class_name}",
        "MitamaeTest::#{class_name}"
      ].each do |full_class_name|
        begin
          return Object.const_get(full_class_name)
        rescue NameError
          next
        end
      end

      raise PluginLoadError, "Could not find plugin class in #{file_path}"
    end
  end

  # Resolves plugin dependencies and handles circular dependencies
  class PluginDependencyResolver
    def initialize(registry)
      @registry = registry
      @resolution_stack = []
    end

    def resolve(type, name)
      plugin_key = "#{type}:#{name}"
      
      if @resolution_stack.include?(plugin_key)
        raise CircularDependencyError, "Circular dependency detected: #{@resolution_stack.join(' -> ')} -> #{plugin_key}"
      end

      @resolution_stack.push(plugin_key)
      
      begin
        plugin_class = @registry.get(type, name)
        resolve_dependencies(plugin_class) if plugin_class.respond_to?(:dependencies)
        plugin_class
      ensure
        @resolution_stack.pop
      end
    end

    private

    def resolve_dependencies(plugin_class)
      return unless plugin_class.respond_to?(:dependencies)

      plugin_class.dependencies.each do |dependency|
        case dependency
        when Hash
          dependency.each { |dep_type, dep_name| resolve(dep_type, dep_name) }
        when String
          # Assume it's a validator if no type specified
          resolve(:validator, dependency)
        else
          raise DependencyError, "Invalid dependency format: #{dependency}"
        end
      end
    end
  end

  # Enhanced plugin base module with metadata and configuration support
  module PluginBase
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def plugin_name(name = nil)
        @plugin_name = name if name
        @plugin_name || self.name.split('::').last.downcase
      end

      def plugin_type(type = nil)
        @plugin_type = type if type
        @plugin_type
      end

      def plugin_version(version = nil)
        @plugin_version = version if version
        @plugin_version || '1.0.0'
      end

      def plugin_description(description = nil)
        @plugin_description = description if description
        @plugin_description
      end

      def requires(*deps)
        @dependencies ||= []
        @dependencies.concat(deps)
      end

      def dependencies
        @dependencies || []
      end

      def auto_register(type: nil, name: nil)
        registration_type = type || plugin_type
        registration_name = name || plugin_name
        
        raise PluginError, "Cannot auto-register: type not specified" unless registration_type
        
        PluginSystem.instance.registry.register(
          registration_type,
          registration_name,
          self,
          metadata: {
            version: plugin_version,
            description: plugin_description,
            dependencies: dependencies
          }
        )
      end
    end

    def plugin_configuration
      type = self.class.plugin_type
      name = self.class.plugin_name
      config_block = PluginSystem.instance.registry.get_configuration(type, name)
      config_block&.call(self)
    end
  end
end