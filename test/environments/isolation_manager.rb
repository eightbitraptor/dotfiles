require 'thread'
require 'digest'
require 'yaml'

module MitamaeTest
  module Environments
    class IsolationManager
      include Logging
      include ErrorHandling
      
      ISOLATION_STATE_FILE = '.isolation_state.yml'
      DEFAULT_MAX_CONCURRENT = 4
      PORT_RANGE_START = 10000
      PORT_RANGE_SIZE = 1000
      
      attr_reader :base_work_dir, :max_concurrent_environments, :active_environments
      
      def initialize(base_work_dir = nil, max_concurrent = DEFAULT_MAX_CONCURRENT)
        @base_work_dir = base_work_dir || File.join(Dir.tmpdir, 'mitamae-test-isolation')
        @max_concurrent_environments = max_concurrent
        @active_environments = {}
        @port_allocations = {}
        @resource_semaphore = Mutex.new
        @environment_slots = Mutex.new
        @isolation_state = {}
        
        # Resource pools
        @available_ports = (PORT_RANGE_START...(PORT_RANGE_START + PORT_RANGE_SIZE)).to_a
        @used_ports = Set.new
        @network_namespaces = {}
        
        setup_isolation_directory
        load_isolation_state
      end
      
      def create_isolated_environment(environment_class, name, options = {})
        log_info "Creating isolated environment: #{name}"
        
        isolation_config = allocate_isolation_resources(name, options)
        
        # Create environment with isolation configuration
        env_options = options.merge(isolation_config[:environment_options])
        environment = environment_class.new(name, env_options)
        
        # Wrap environment with isolation
        isolated_env = IsolatedEnvironment.new(
          environment,
          isolation_config,
          self
        )
        
        # Register the environment
        register_environment(name, isolated_env, isolation_config)
        
        log_info "Isolated environment created: #{name} (slot #{isolation_config[:slot]})"
        isolated_env
      end
      
      def destroy_isolated_environment(name_or_env)
        name = name_or_env.is_a?(String) ? name_or_env : name_or_env.name
        
        log_info "Destroying isolated environment: #{name}"
        
        @resource_semaphore.synchronize do
          env_info = @active_environments[name]
          return false unless env_info
          
          # Cleanup environment
          safe_execute("cleanup isolated environment") do
            env_info[:environment].cleanup_isolation
          end
          
          # Release resources
          release_isolation_resources(env_info[:isolation_config])
          
          # Unregister environment
          unregister_environment(name)
          
          log_info "Isolated environment destroyed: #{name}"
          true
        end
      end
      
      def list_active_environments
        @active_environments.keys
      end
      
      def get_environment_info(name)
        @active_environments[name]
      end
      
      def wait_for_available_slot(timeout = 300)
        log_debug "Waiting for available environment slot"
        
        start_time = Time.now
        
        loop do
          return true if @active_environments.size < @max_concurrent_environments
          
          elapsed = Time.now - start_time
          if elapsed >= timeout
            log_error "Timeout waiting for available environment slot"
            return false
          end
          
          sleep 1
        end
      end
      
      def cleanup_all_environments
        log_info "Cleaning up all isolated environments"
        
        environments_to_cleanup = @active_environments.keys.dup
        
        environments_to_cleanup.each do |name|
          destroy_isolated_environment(name)
        end
        
        # Clean up any orphaned resources
        cleanup_orphaned_resources
        
        log_info "All isolated environments cleaned up"
      end
      
      def get_isolation_statistics
        {
          active_environments: @active_environments.size,
          max_concurrent: @max_concurrent_environments,
          available_slots: @max_concurrent_environments - @active_environments.size,
          port_allocations: @port_allocations.size,
          available_ports: @available_ports.size,
          resource_usage: calculate_resource_usage
        }
      end
      
      def allocate_port_range(count = 10)
        @resource_semaphore.synchronize do
          return nil if @available_ports.size < count
          
          allocated_ports = @available_ports.shift(count)
          allocated_ports.each { |port| @used_ports.add(port) }
          
          allocated_ports
        end
      end
      
      def release_port_range(ports)
        @resource_semaphore.synchronize do
          ports.each do |port|
            @used_ports.delete(port)
            @available_ports << port
          end
          
          @available_ports.sort!
        end
      end
      
      def create_network_namespace(name)
        return false unless RUBY_PLATFORM.include?('linux')
        
        namespace_name = "mitamae-test-#{name}"
        
        @resource_semaphore.synchronize do
          return false if @network_namespaces[name]
          
          # Create network namespace
          success = system("ip netns add #{namespace_name} 2>/dev/null")
          
          if success
            @network_namespaces[name] = namespace_name
            log_debug "Created network namespace: #{namespace_name}"
            true
          else
            false
          end
        end
      end
      
      def destroy_network_namespace(name)
        return false unless RUBY_PLATFORM.include?('linux')
        
        @resource_semaphore.synchronize do
          namespace_name = @network_namespaces[name]
          return false unless namespace_name
          
          # Destroy network namespace
          system("ip netns delete #{namespace_name} 2>/dev/null")
          @network_namespaces.delete(name)
          
          log_debug "Destroyed network namespace: #{namespace_name}"
          true
        end
      end
      
      private
      
      def setup_isolation_directory
        FileUtils.mkdir_p(@base_work_dir)
        
        # Create isolation-specific directories
        %w[environments network config logs].each do |subdir|
          FileUtils.mkdir_p(File.join(@base_work_dir, subdir))
        end
      end
      
      def load_isolation_state
        state_file = File.join(@base_work_dir, ISOLATION_STATE_FILE)
        
        if File.exist?(state_file)
          @isolation_state = YAML.load_file(state_file) || {}
          
          # Restore port allocations
          if @isolation_state[:port_allocations]
            @port_allocations = @isolation_state[:port_allocations]
            @used_ports = Set.new(@port_allocations.values.flatten)
            @available_ports -= @used_ports.to_a
          end
        end
      end
      
      def save_isolation_state
        state_file = File.join(@base_work_dir, ISOLATION_STATE_FILE)
        
        @isolation_state.merge!({
          port_allocations: @port_allocations,
          active_environments: @active_environments.keys,
          updated_at: Time.now
        })
        
        File.write(state_file, YAML.dump(@isolation_state))
      end
      
      def allocate_isolation_resources(name, options)
        @resource_semaphore.synchronize do
          # Wait for available slot
          unless wait_for_available_slot
            raise TestError, "No available environment slots"
          end
          
          # Allocate unique slot ID
          slot_id = find_available_slot
          
          # Allocate port range
          port_count = options[:port_count] || 10
          allocated_ports = allocate_port_range(port_count)
          raise TestError, "Cannot allocate required ports" unless allocated_ports
          
          # Create isolated work directory
          work_dir = File.join(@base_work_dir, 'environments', "#{name}-#{slot_id}")
          FileUtils.mkdir_p(work_dir)
          
          # Generate unique identifiers
          unique_suffix = Digest::SHA256.hexdigest("#{name}-#{slot_id}-#{Time.now.to_f}")[0..7]
          
          isolation_config = {
            slot: slot_id,
            name: name,
            unique_suffix: unique_suffix,
            work_dir: work_dir,
            allocated_ports: allocated_ports,
            environment_options: generate_environment_options(name, slot_id, allocated_ports, options)
          }
          
          # Store port allocation
          @port_allocations[name] = allocated_ports
          
          save_isolation_state
          isolation_config
        end
      end
      
      def release_isolation_resources(isolation_config)
        # Release ports
        if isolation_config[:allocated_ports]
          release_port_range(isolation_config[:allocated_ports])
          @port_allocations.delete(isolation_config[:name])
        end
        
        # Clean up work directory
        if isolation_config[:work_dir] && File.exist?(isolation_config[:work_dir])
          FileUtils.rm_rf(isolation_config[:work_dir])
        end
        
        # Destroy network namespace if created
        destroy_network_namespace(isolation_config[:name])
        
        save_isolation_state
      end
      
      def generate_environment_options(name, slot_id, allocated_ports, base_options)
        env_options = base_options.dup
        
        # Generate unique container/VM name
        if env_options[:container_name] || base_options[:environment_type] == :container
          env_options[:container_name] = "mitamae-test-#{name}-#{slot_id}"
        end
        
        if env_options[:vm_name] || base_options[:environment_type] == :vm
          env_options[:vm_name] = "mitamae-test-vm-#{name}-#{slot_id}"
        end
        
        # Assign unique ports
        if allocated_ports && allocated_ports.size >= 2
          env_options[:ssh_port] = allocated_ports[0]
          env_options[:vnc_port] = allocated_ports[1] if allocated_ports.size > 1
          
          # Additional ports for services
          env_options[:service_ports] = allocated_ports[2..-1] if allocated_ports.size > 2
        end
        
        # Isolation-specific environment variables
        env_options[:environment_vars] ||= {}
        env_options[:environment_vars].merge!({
          'MITAMAE_TEST_SLOT' => slot_id.to_s,
          'MITAMAE_TEST_NAME' => name,
          'MITAMAE_TEST_ISOLATED' => 'true'
        })
        
        env_options
      end
      
      def find_available_slot
        (1..@max_concurrent_environments).each do |slot|
          slot_in_use = @active_environments.values.any? { |env| env[:isolation_config][:slot] == slot }
          return slot unless slot_in_use
        end
        
        raise TestError, "No available slots (max: #{@max_concurrent_environments})"
      end
      
      def register_environment(name, environment, isolation_config)
        @environment_slots.synchronize do
          @active_environments[name] = {
            environment: environment,
            isolation_config: isolation_config,
            created_at: Time.now,
            slot: isolation_config[:slot]
          }
        end
      end
      
      def unregister_environment(name)
        @environment_slots.synchronize do
          @active_environments.delete(name)
        end
      end
      
      def cleanup_orphaned_resources
        log_debug "Cleaning up orphaned isolation resources"
        
        # Clean up orphaned network namespaces
        if RUBY_PLATFORM.include?('linux')
          existing_namespaces = `ip netns list 2>/dev/null`.split("\n").map(&:strip)
          mitamae_namespaces = existing_namespaces.select { |ns| ns.start_with?('mitamae-test-') }
          
          mitamae_namespaces.each do |ns|
            # Check if this namespace is still in use
            in_use = @network_namespaces.values.include?(ns)
            unless in_use
              system("ip netns delete #{ns} 2>/dev/null")
              log_debug "Cleaned up orphaned namespace: #{ns}"
            end
          end
        end
        
        # Clean up orphaned directories
        environments_dir = File.join(@base_work_dir, 'environments')
        if File.exist?(environments_dir)
          Dir.glob(File.join(environments_dir, '*')).each do |env_dir|
            next unless File.directory?(env_dir)
            
            env_name = File.basename(env_dir).split('-')[0]
            unless @active_environments.key?(env_name)
              FileUtils.rm_rf(env_dir)
              log_debug "Cleaned up orphaned environment directory: #{env_dir}"
            end
          end
        end
      end
      
      def calculate_resource_usage
        total_disk = 0
        total_memory = 0
        
        @active_environments.each do |name, env_info|
          work_dir = env_info[:isolation_config][:work_dir]
          
          if File.exist?(work_dir)
            total_disk += calculate_directory_size(work_dir)
          end
          
          # Estimate memory usage (this is a rough estimate)
          total_memory += 512 * 1024 * 1024 # 512MB per environment
        end
        
        {
          disk_usage_bytes: total_disk,
          disk_usage_mb: total_disk / (1024.0 * 1024.0),
          estimated_memory_mb: total_memory / (1024.0 * 1024.0)
        }
      end
      
      def calculate_directory_size(path)
        return 0 unless File.exist?(path)
        
        total_size = 0
        Find.find(path) do |file_path|
          total_size += File.size(file_path) if File.file?(file_path)
        end
        total_size
      end
    end
    
    # Wrapper class for isolated environments
    class IsolatedEnvironment
      include Logging
      
      attr_reader :environment, :isolation_config, :isolation_manager
      
      def initialize(environment, isolation_config, isolation_manager)
        @environment = environment
        @isolation_config = isolation_config
        @isolation_manager = isolation_manager
      end
      
      # Delegate most methods to the wrapped environment
      def method_missing(method, *args, **kwargs, &block)
        @environment.send(method, *args, **kwargs, &block)
      end
      
      def respond_to_missing?(method, include_private = false)
        @environment.respond_to?(method, include_private) || super
      end
      
      # Override specific methods for isolation
      def name
        @isolation_config[:name]
      end
      
      def slot
        @isolation_config[:slot]
      end
      
      def work_dir
        @isolation_config[:work_dir]
      end
      
      def allocated_ports
        @isolation_config[:allocated_ports]
      end
      
      def cleanup_isolation
        log_debug "Cleaning up isolation for environment: #{name}"
        
        # Cleanup the wrapped environment
        @environment.cleanup if @environment.respond_to?(:cleanup)
        
        # Perform isolation-specific cleanup
        if @isolation_config[:work_dir] && File.exist?(@isolation_config[:work_dir])
          FileUtils.rm_rf(@isolation_config[:work_dir])
        end
        
        log_debug "Isolation cleanup complete for: #{name}"
      end
      
      def isolation_info
        {
          name: name,
          slot: slot,
          work_dir: work_dir,
          allocated_ports: allocated_ports,
          environment_type: @environment.class.name
        }
      end
    end
  end
end