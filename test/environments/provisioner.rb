require 'fileutils'
require 'yaml'
require 'digest'

module MitamaeTest
  module Environments
    class Provisioner
      include Logging
      include ErrorHandling
      
      PROVISION_LOCK_FILE = '.provision_lock'
      PROVISION_STATE_FILE = '.provision_state.yml'
      
      attr_reader :environment, :config, :work_dir
      
      def initialize(environment, config = {})
        @environment = environment
        @config = config
        @work_dir = File.join(Dir.tmpdir, 'mitamae-test-provision', environment.name)
        @provision_id = SecureRandom.hex(16)
        @state = {}
        
        setup_work_directory
      end
      
      def provision_environment
        log_info "Provisioning environment: #{environment.name}"
        
        with_provision_lock do
          load_provision_state
          
          # Check if we can reuse existing environment
          if can_reuse_environment?
            log_info "Reusing existing environment (state matches)"
            return restore_environment
          end
          
          # Clean up any existing state
          cleanup_existing_environment
          
          # Create fresh environment
          create_fresh_environment
          
          # Save provision state
          save_provision_state
          
          log_info "Environment provisioning complete: #{environment.name}"
        end
      end
      
      def cleanup_environment
        log_info "Cleaning up environment: #{environment.name}"
        
        with_provision_lock do
          # Cleanup environment
          safe_execute("environment cleanup") do
            environment.cleanup if environment.respond_to?(:cleanup)
          end
          
          # Remove state files
          cleanup_state_files
          
          # Remove work directory
          FileUtils.rm_rf(@work_dir) if File.exist?(@work_dir)
          
          log_info "Environment cleanup complete: #{environment.name}"
        end
      end
      
      def environment_ready?
        return false unless environment.ready?
        return false unless provision_state_valid?
        
        # Verify environment health
        environment.health_check if environment.respond_to?(:health_check)
      end
      
      def provision_with_recipe_files(recipe_paths)
        log_info "Provisioning with recipe files: #{recipe_paths.join(', ')}"
        
        # Calculate recipe file checksums for state tracking
        recipe_checksums = calculate_recipe_checksums(recipe_paths)
        @state[:recipe_checksums] = recipe_checksums
        
        # Setup shared volumes for recipe files
        setup_recipe_volumes(recipe_paths)
        
        # Provision environment
        provision_environment
        
        # Copy recipe files into environment
        copy_recipe_files(recipe_paths)
        
        log_info "Recipe file provisioning complete"
      end
      
      def create_snapshot(name)
        return nil unless environment.respond_to?(:create_snapshot)
        
        log_info "Creating environment snapshot: #{name}"
        snapshot_id = environment.create_snapshot(name)
        
        # Save snapshot info to state
        @state[:snapshots] ||= {}
        @state[:snapshots][name] = {
          id: snapshot_id,
          created_at: Time.now.to_s,
          provision_id: @provision_id
        }
        
        save_provision_state
        snapshot_id
      end
      
      def restore_snapshot(name)
        return false unless @state[:snapshots] && @state[:snapshots][name]
        return false unless environment.respond_to?(:restore_snapshot)
        
        log_info "Restoring environment snapshot: #{name}"
        snapshot_info = @state[:snapshots][name]
        
        success = environment.restore_snapshot(snapshot_info[:id])
        if success
          log_info "Snapshot restored successfully: #{name}"
        else
          log_error "Failed to restore snapshot: #{name}"
        end
        
        success
      end
      
      def list_snapshots
        @state[:snapshots] || {}
      end
      
      def add_shared_volume(host_path, container_path, options = {})
        @config[:volumes] ||= []
        @config[:volumes] << {
          host_path: File.expand_path(host_path),
          container_path: container_path,
          options: options
        }
      end
      
      def set_environment_variable(key, value)
        @config[:environment_vars] ||= {}
        @config[:environment_vars][key] = value
      end
      
      def provision_state
        @state.dup
      end
      
      private
      
      def setup_work_directory
        FileUtils.mkdir_p(@work_dir)
        
        # Create directories for different types of data
        %w[recipes artifacts logs snapshots state].each do |dir|
          FileUtils.mkdir_p(File.join(@work_dir, dir))
        end
      end
      
      def with_provision_lock
        lock_file = File.join(@work_dir, PROVISION_LOCK_FILE)
        
        # Simple file-based locking for provisioning operations
        if File.exist?(lock_file)
          lock_age = Time.now - File.mtime(lock_file)
          if lock_age > 1800 # 30 minutes - assume stale lock
            log_warn "Removing stale provision lock (#{lock_age}s old)"
            FileUtils.rm_f(lock_file)
          else
            raise TestError, "Another provisioning operation is in progress"
          end
        end
        
        File.write(lock_file, Process.pid.to_s)
        
        begin
          yield
        ensure
          FileUtils.rm_f(lock_file)
        end
      end
      
      def load_provision_state
        state_file = File.join(@work_dir, 'state', PROVISION_STATE_FILE)
        
        if File.exist?(state_file)
          @state = YAML.load_file(state_file) || {}
        else
          @state = {}
        end
      end
      
      def save_provision_state
        state_file = File.join(@work_dir, 'state', PROVISION_STATE_FILE)
        
        @state[:provision_id] = @provision_id
        @state[:provisioned_at] = Time.now.to_s
        @state[:environment_type] = environment.class.name
        @state[:environment_options] = environment.options
        @state[:config_checksum] = calculate_config_checksum
        
        File.write(state_file, YAML.dump(@state))
      end
      
      def can_reuse_environment?
        return false unless @state[:provision_id]
        return false unless environment.ready?
        
        # Check if configuration has changed
        current_checksum = calculate_config_checksum
        return false unless @state[:config_checksum] == current_checksum
        
        # Check if environment is healthy
        if environment.respond_to?(:health_check)
          return false unless environment.health_check
        end
        
        log_debug "Environment can be reused (checksums match)"
        true
      end
      
      def provision_state_valid?
        return false unless @state[:provision_id]
        return false unless @state[:provisioned_at]
        
        # Check if state is too old (older than 24 hours)
        provisioned_at = Time.parse(@state[:provisioned_at])
        age = Time.now - provisioned_at
        
        if age > 86400 # 24 hours
          log_debug "Provision state is too old (#{age}s)"
          return false
        end
        
        true
      end
      
      def cleanup_existing_environment
        log_debug "Cleaning up existing environment state"
        
        # Stop and remove existing environment
        safe_execute("cleanup existing environment") do
          environment.teardown if environment.ready?
        end
        
        # Clear snapshots if supported
        if environment.respond_to?(:clear_snapshots)
          environment.clear_snapshots
        end
        
        # Reset state
        @state = {}
      end
      
      def create_fresh_environment
        log_debug "Creating fresh environment"
        
        # Apply configuration to environment
        apply_configuration_to_environment
        
        # Setup environment
        environment.setup
        
        # Verify environment is ready
        unless environment.ready?
          raise TestError, "Environment setup completed but environment is not ready"
        end
        
        # Run health check
        if environment.respond_to?(:health_check)
          unless environment.health_check
            raise TestError, "Environment health check failed after setup"
          end
        end
      end
      
      def restore_environment
        log_debug "Restoring existing environment"
        
        # Verify environment is still ready
        unless environment.ready?
          raise TestError, "Existing environment is not ready"
        end
        
        # Run health check
        if environment.respond_to?(:health_check)
          unless environment.health_check
            log_warn "Environment health check failed - will recreate"
            return create_fresh_environment
          end
        end
        
        log_debug "Existing environment restored successfully"
      end
      
      def apply_configuration_to_environment
        # Apply volumes
        if @config[:volumes] && environment.respond_to?(:add_volume)
          @config[:volumes].each do |volume|
            environment.add_volume(
              volume[:host_path],
              volume[:container_path],
              volume[:options]
            )
          end
        end
        
        # Apply environment variables
        if @config[:environment_vars] && environment.respond_to?(:set_environment)
          @config[:environment_vars].each do |key, value|
            environment.set_environment(key, value)
          end
        end
        
        # Apply ports
        if @config[:ports] && environment.respond_to?(:add_port)
          @config[:ports].each do |port_mapping|
            environment.add_port(port_mapping[:host], port_mapping[:container])
          end
        end
      end
      
      def calculate_config_checksum
        config_data = {
          environment_class: environment.class.name,
          environment_options: environment.options,
          provisioner_config: @config
        }
        
        Digest::SHA256.hexdigest(config_data.to_yaml)
      end
      
      def calculate_recipe_checksums(recipe_paths)
        checksums = {}
        
        recipe_paths.each do |path|
          if File.exist?(path)
            content = File.read(path)
            checksums[path] = Digest::SHA256.hexdigest(content)
          else
            log_warn "Recipe file not found: #{path}"
            checksums[path] = nil
          end
        end
        
        checksums
      end
      
      def setup_recipe_volumes(recipe_paths)
        recipes_dir = File.join(@work_dir, 'recipes')
        FileUtils.mkdir_p(recipes_dir)
        
        # Add recipe directory as a shared volume
        add_shared_volume(recipes_dir, '/opt/mitamae/recipes', readonly: true)
      end
      
      def copy_recipe_files(recipe_paths)
        recipes_dir = File.join(@work_dir, 'recipes')
        
        recipe_paths.each do |path|
          if File.exist?(path)
            dest_path = File.join(recipes_dir, File.basename(path))
            FileUtils.cp(path, dest_path)
            log_debug "Copied recipe file: #{path} -> #{dest_path}"
          else
            log_warn "Recipe file not found: #{path}"
          end
        end
      end
      
      def cleanup_state_files
        state_dir = File.join(@work_dir, 'state')
        FileUtils.rm_rf(state_dir) if File.exist?(state_dir)
      end
    end
  end
end