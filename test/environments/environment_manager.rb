require_relative 'container'
require_relative 'vm'
require_relative 'provisioner'
require_relative 'volume_manager'
require_relative 'cleanup_manager'
require_relative 'health_checker'
require_relative 'isolation_manager'
require_relative 'artifact_manager'

module MitamaeTest
  module Environments
    class EnvironmentManager
      include Logging
      include ErrorHandling
      
      attr_reader :isolation_manager, :cleanup_manager, :artifact_manager, :active_environments
      
      def initialize(config = {})
        @config = config
        @base_work_dir = config[:work_dir] || File.join(Dir.tmpdir, 'mitamae-test')
        @max_concurrent = config[:max_concurrent] || 4
        @default_timeout = config[:timeout] || 300
        
        @isolation_manager = IsolationManager.new(@base_work_dir, @max_concurrent)
        @cleanup_manager = CleanupManager.new(@base_work_dir)
        @artifact_manager = ArtifactManager.new(self, config[:artifacts_dir])
        @active_environments = {}
        @environment_registry = {}
        
        setup_signal_handlers
      end
      
      def create_environment(type, name, options = {})
        log_info "Creating #{type} environment: #{name}"
        
        # Validate environment type
        environment_class = get_environment_class(type)
        raise TestError, "Unsupported environment type: #{type}" unless environment_class
        
        # Create isolated environment
        isolated_env = @isolation_manager.create_isolated_environment(
          environment_class,
          name,
          options.merge(environment_type: type)
        )
        
        # Create provisioner
        provisioner = Provisioner.new(isolated_env, options[:provisioner] || {})
        
        # Create volume manager
        volume_manager = VolumeManager.new(isolated_env.work_dir)
        
        # Create health checker
        health_checker = HealthChecker.new(isolated_env, options[:health_check] || {})
        
        # Wrap everything in an environment context
        env_context = EnvironmentContext.new(
          isolated_env,
          provisioner,
          volume_manager,
          health_checker,
          self
        )
        
        # Register environment
        register_environment(name, env_context)
        
        log_info "Environment created successfully: #{name} (#{type})"
        env_context
      end
      
      def get_environment(name)
        @active_environments[name]
      end
      
      def destroy_environment(name)
        log_info "Destroying environment: #{name}"
        
        env_context = @active_environments[name]
        return false unless env_context
        
        # Cleanup environment
        cleanup_stats = @cleanup_manager.cleanup_environment(env_context.environment)
        
        # Destroy isolated environment
        @isolation_manager.destroy_isolated_environment(name)
        
        # Unregister environment
        unregister_environment(name)
        
        log_info "Environment destroyed: #{name}"
        cleanup_stats
      end
      
      def provision_environment(name, recipe_paths = [])
        env_context = get_environment(name)
        raise TestError, "Environment not found: #{name}" unless env_context
        
        log_info "Provisioning environment: #{name}"
        
        # Setup volumes for recipes
        if recipe_paths.any?
          env_context.volume_manager.add_recipe_volume(recipe_paths)
        end
        
        # Setup standard volumes
        env_context.volume_manager.add_artifact_volume
        env_context.volume_manager.add_logs_volume
        env_context.volume_manager.add_cache_volume
        
        # Apply volume configuration to provisioner
        volume_mounts = env_context.volume_manager.get_volume_mounts
        volume_mounts.each do |mount_spec|
          host_path, container_path, options = mount_spec.split(':')
          readonly = options == 'ro'
          env_context.provisioner.add_shared_volume(host_path, container_path, readonly: readonly)
        end
        
        # Provision with recipes
        if recipe_paths.any?
          env_context.provisioner.provision_with_recipe_files(recipe_paths)
        else
          env_context.provisioner.provision_environment
        end
        
        # Wait for environment to be ready
        unless env_context.health_checker.wait_for_ready
          raise TestError, "Environment failed to become ready: #{name}"
        end
        
        log_info "Environment provisioned successfully: #{name}"
        env_context
      end
      
      def list_environments
        @active_environments.keys
      end
      
      def get_environment_status(name)
        env_context = get_environment(name)
        return nil unless env_context
        
        {
          name: name,
          type: env_context.environment.class.name,
          ready: env_context.environment.ready?,
          health: env_context.health_checker.get_health_status,
          isolation: env_context.environment.isolation_info,
          volumes: env_context.volume_manager.volume_statistics
        }
      end
      
      def get_all_environment_status
        status = {}
        @active_environments.each do |name, _|
          status[name] = get_environment_status(name)
        end
        status
      end
      
      def cleanup_all_environments
        log_info "Cleaning up all environments"
        
        environments_to_cleanup = @active_environments.keys.dup
        cleanup_results = []
        
        environments_to_cleanup.each do |name|
          result = destroy_environment(name)
          cleanup_results << { name: name, result: result }
        end
        
        # Perform isolation manager cleanup
        @isolation_manager.cleanup_all_environments
        
        # Perform cleanup manager cleanup
        @cleanup_manager.cleanup_all_environments
        
        log_info "All environments cleaned up"
        cleanup_results
      end
      
      def enforce_resource_limits
        @cleanup_manager.enforce_resource_limits
      end
      
      def get_resource_usage
        isolation_stats = @isolation_manager.get_isolation_statistics
        cleanup_stats = @cleanup_manager.get_resource_usage
        
        {
          isolation: isolation_stats,
          cleanup: cleanup_stats,
          active_environments: @active_environments.size,
          registry_size: @environment_registry.size
        }
      end
      
      def start_periodic_cleanup(interval_hours = 6)
        @cleanup_manager.schedule_periodic_cleanup(interval_hours)
      end
      
      def collect_artifacts(environment_name, test_result = nil, config = {})
        @artifact_manager.collect_test_artifacts(environment_name, test_result, config)
      end
      
      def collect_failure_artifacts(environment_name, test_failure)
        config = { 
          artifact_types: ArtifactCollector::ARTIFACT_TYPES,
          create_archive: true,
          create_browsable_index: true 
        }
        @artifact_manager.collect_test_artifacts(environment_name, test_failure, config)
      end
      
      def get_artifact_history(environment_name, limit = 20)
        @artifact_manager.get_artifact_history(environment_name, limit)
      end
      
      def cleanup_old_artifacts(environment_name = nil, max_age_days = 7)
        @artifact_manager.cleanup_old_artifacts(environment_name, max_age_days)
      end
      
      def create_artifact_report(environment_name = nil, format = :html)
        @artifact_manager.create_artifact_report(environment_name, format)
      end
      
      def emergency_cleanup
        log_warn "Performing emergency cleanup of all environments"
        
        # Stop all active environments immediately
        @active_environments.each do |name, env_context|
          safe_execute("emergency stop #{name}") do
            env_context.environment.teardown if env_context.environment.ready?
          end
        end
        
        # Clear registries
        @active_environments.clear
        @environment_registry.clear
        
        # Delegate to managers
        @isolation_manager.cleanup_all_environments
        @cleanup_manager.emergency_cleanup
        
        log_warn "Emergency cleanup completed"
      end
      
      def create_test_session(session_config)
        log_info "Creating test session with #{session_config[:environments].size} environments"
        
        session = TestSession.new(session_config, self)
        
        # Create all environments for the session
        session_config[:environments].each do |env_config|
          env_context = create_environment(
            env_config[:type],
            env_config[:name],
            env_config[:options] || {}
          )
          
          session.add_environment(env_config[:name], env_context)
        end
        
        log_info "Test session created successfully"
        session
      end
      
      private
      
      def get_environment_class(type)
        case type.to_sym
        when :container
          Container
        when :vm
          VM
        else
          nil
        end
      end
      
      def register_environment(name, env_context)
        @active_environments[name] = env_context
        @environment_registry[name] = {
          created_at: Time.now,
          type: env_context.environment.class.name,
          slot: env_context.environment.slot
        }
      end
      
      def unregister_environment(name)
        @active_environments.delete(name)
        @environment_registry.delete(name)
      end
      
      def setup_signal_handlers
        # Handle cleanup on exit signals
        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            log_warn "Received #{signal} signal, cleaning up environments..."
            cleanup_all_environments
            exit(0)
          end
        end
      end
    end
    
    # Context wrapper for environment with associated managers
    class EnvironmentContext
      attr_reader :environment, :provisioner, :volume_manager, :health_checker, :manager
      
      def initialize(environment, provisioner, volume_manager, health_checker, manager)
        @environment = environment
        @provisioner = provisioner
        @volume_manager = volume_manager
        @health_checker = health_checker
        @manager = manager
      end
      
      def name
        @environment.name
      end
      
      def ready?
        @environment.ready?
      end
      
      def execute(command, **options)
        @environment.execute(command, **options)
      end
      
      def copy_file(source, destination)
        @environment.copy_file(source, destination)
      end
      
      def health_check
        @health_checker.perform_health_check
      end
      
      def collect_artifacts(test_result = nil, config = {})
        @manager.collect_artifacts(name, test_result, config)
      end
      
      def collect_failure_artifacts(test_failure)
        @manager.collect_failure_artifacts(name, test_failure)
      end
      
      def collect_logs
        @volume_manager.collect_logs
      end
      
      def get_artifact_history(limit = 20)
        @manager.get_artifact_history(name, limit)
      end
      
      def create_snapshot(name)
        @provisioner.create_snapshot(name)
      end
      
      def restore_snapshot(name)
        @provisioner.restore_snapshot(name)
      end
      
      def cleanup
        @manager.destroy_environment(name)
      end
    end
    
    # Test session for managing multiple environments
    class TestSession
      include Logging
      
      attr_reader :config, :environments, :manager, :session_id
      
      def initialize(config, manager)
        @config = config
        @manager = manager
        @environments = {}
        @session_id = SecureRandom.hex(8)
      end
      
      def add_environment(name, env_context)
        @environments[name] = env_context
      end
      
      def get_environment(name)
        @environments[name]
      end
      
      def provision_all(recipe_paths = [])
        log_info "Provisioning all session environments"
        
        @environments.each do |name, env_context|
          @manager.provision_environment(name, recipe_paths)
        end
      end
      
      def health_check_all
        results = {}
        
        @environments.each do |name, env_context|
          results[name] = env_context.health_check
        end
        
        results
      end
      
      def collect_all_artifacts(session_result = nil)
        @manager.artifact_manager.collect_session_artifacts(self, session_result)
      end
      
      def collect_environment_artifacts(env_name, test_result = nil, config = {})
        env_context = @environments[env_name]
        return nil unless env_context
        
        env_context.collect_artifacts(test_result, config)
      end
      
      def collect_all_logs
        logs = {}
        
        @environments.each do |name, env_context|
          logs[name] = env_context.collect_logs
        end
        
        logs
      end
      
      def cleanup_session
        log_info "Cleaning up test session: #{@session_id}"
        
        @environments.each do |name, env_context|
          env_context.cleanup
        end
        
        @environments.clear
      end
      
      def session_status
        {
          session_id: @session_id,
          environments: @environments.keys,
          status: @environments.transform_values { |env| env.ready? }
        }
      end
    end
  end
end