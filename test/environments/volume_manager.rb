require 'fileutils'
require 'yaml'

module MitamaeTest
  module Environments
    class VolumeManager
      include Logging
      include ErrorHandling
      
      VOLUME_STATE_FILE = '.volume_state.yml'
      
      attr_reader :work_dir, :volumes
      
      def initialize(work_dir)
        @work_dir = work_dir
        @volumes = {}
        @state = {}
        @managed_directories = []
        
        setup_volume_directories
        load_volume_state
      end
      
      def add_recipe_volume(recipe_paths, container_path = '/opt/mitamae/recipes')
        log_debug "Adding recipe volume for #{recipe_paths.size} files"
        
        recipes_dir = File.join(@work_dir, 'volumes', 'recipes')
        FileUtils.mkdir_p(recipes_dir)
        
        # Copy recipe files to managed directory
        recipe_paths.each do |source_path|
          if File.exist?(source_path)
            dest_path = File.join(recipes_dir, File.basename(source_path))
            FileUtils.cp(source_path, dest_path)
            log_debug "Copied recipe: #{source_path} -> #{dest_path}"
          else
            log_warn "Recipe file not found: #{source_path}"
          end
        end
        
        add_volume('recipes', recipes_dir, container_path, readonly: true)
      end
      
      def add_artifact_volume(container_path = '/opt/mitamae/artifacts')
        log_debug "Adding artifact volume"
        
        artifacts_dir = File.join(@work_dir, 'volumes', 'artifacts')
        FileUtils.mkdir_p(artifacts_dir)
        
        add_volume('artifacts', artifacts_dir, container_path, readonly: false)
      end
      
      def add_config_volume(config_files, container_path = '/opt/mitamae/config')
        log_debug "Adding config volume for #{config_files.size} files"
        
        config_dir = File.join(@work_dir, 'volumes', 'config')
        FileUtils.mkdir_p(config_dir)
        
        # Copy config files to managed directory
        config_files.each do |source_path|
          if File.exist?(source_path)
            dest_path = File.join(config_dir, File.basename(source_path))
            FileUtils.cp(source_path, dest_path)
            log_debug "Copied config: #{source_path} -> #{dest_path}"
          else
            log_warn "Config file not found: #{source_path}"
          end
        end
        
        add_volume('config', config_dir, container_path, readonly: true)
      end
      
      def add_logs_volume(container_path = '/var/log/mitamae')
        log_debug "Adding logs volume"
        
        logs_dir = File.join(@work_dir, 'volumes', 'logs')
        FileUtils.mkdir_p(logs_dir)
        
        add_volume('logs', logs_dir, container_path, readonly: false)
      end
      
      def add_cache_volume(container_path = '/var/cache/mitamae')
        log_debug "Adding cache volume"
        
        cache_dir = File.join(@work_dir, 'volumes', 'cache')
        FileUtils.mkdir_p(cache_dir)
        
        add_volume('cache', cache_dir, container_path, readonly: false)
      end
      
      def add_custom_volume(name, host_path, container_path, options = {})
        log_debug "Adding custom volume: #{name}"
        
        # Ensure host path exists
        FileUtils.mkdir_p(host_path) unless File.exist?(host_path)
        
        add_volume(name, host_path, container_path, options)
      end
      
      def get_volume_mounts
        mounts = []
        
        @volumes.each do |name, volume|
          mount_options = volume[:readonly] ? 'ro' : 'rw'
          mount_spec = "#{volume[:host_path]}:#{volume[:container_path]}:#{mount_options}"
          mounts << mount_spec
        end
        
        mounts
      end
      
      def get_volume_paths
        paths = {}
        
        @volumes.each do |name, volume|
          paths[name] = {
            host: volume[:host_path],
            container: volume[:container_path]
          }
        end
        
        paths
      end
      
      def collect_artifacts
        artifacts = {}
        
        if @volumes['artifacts']
          artifacts_dir = @volumes['artifacts'][:host_path]
          
          if File.exist?(artifacts_dir)
            Dir.glob(File.join(artifacts_dir, '**', '*')).each do |file_path|
              next unless File.file?(file_path)
              
              relative_path = file_path.sub("#{artifacts_dir}/", '')
              artifacts[relative_path] = file_path
            end
          end
        end
        
        artifacts
      end
      
      def collect_logs
        logs = {}
        
        # Collect from logs volume
        if @volumes['logs']
          logs_dir = @volumes['logs'][:host_path]
          
          if File.exist?(logs_dir)
            Dir.glob(File.join(logs_dir, '**', '*.log')).each do |log_file|
              relative_path = log_file.sub("#{logs_dir}/", '')
              logs[relative_path] = log_file
            end
          end
        end
        
        # Also collect from other volumes that might contain logs
        @volumes.each do |name, volume|
          next if name == 'logs' # Already handled above
          next if volume[:readonly] # Skip readonly volumes
          
          volume_dir = volume[:host_path]
          next unless File.exist?(volume_dir)
          
          Dir.glob(File.join(volume_dir, '**', '*.log')).each do |log_file|
            relative_path = "#{name}/#{log_file.sub("#{volume_dir}/", '')}"
            logs[relative_path] = log_file
          end
        end
        
        logs
      end
      
      def copy_from_volume(volume_name, source_path, destination)
        volume = @volumes[volume_name]
        raise TestError, "Volume '#{volume_name}' not found" unless volume
        
        full_source_path = File.join(volume[:host_path], source_path)
        
        if File.exist?(full_source_path)
          FileUtils.cp_r(full_source_path, destination)
          log_debug "Copied from volume #{volume_name}: #{source_path} -> #{destination}"
        else
          raise TestError, "File not found in volume: #{full_source_path}"
        end
      end
      
      def copy_to_volume(volume_name, source, destination_path)
        volume = @volumes[volume_name]
        raise TestError, "Volume '#{volume_name}' not found" unless volume
        raise TestError, "Cannot write to readonly volume '#{volume_name}'" if volume[:readonly]
        
        full_destination_path = File.join(volume[:host_path], destination_path)
        destination_dir = File.dirname(full_destination_path)
        
        FileUtils.mkdir_p(destination_dir)
        FileUtils.cp_r(source, full_destination_path)
        
        log_debug "Copied to volume #{volume_name}: #{source} -> #{destination_path}"
      end
      
      def volume_exists?(volume_name)
        @volumes.key?(volume_name)
      end
      
      def volume_size(volume_name)
        volume = @volumes[volume_name]
        return 0 unless volume && File.exist?(volume[:host_path])
        
        calculate_directory_size(volume[:host_path])
      end
      
      def total_volume_size
        total = 0
        
        @volumes.each do |name, volume|
          total += volume_size(name)
        end
        
        total
      end
      
      def cleanup_volumes
        log_info "Cleaning up managed volumes"
        
        # Remove managed directories
        @managed_directories.each do |dir|
          if File.exist?(dir)
            FileUtils.rm_rf(dir)
            log_debug "Removed managed directory: #{dir}"
          end
        end
        
        # Clear state
        @volumes.clear
        @state.clear
        @managed_directories.clear
        
        # Remove state file
        state_file_path = File.join(@work_dir, VOLUME_STATE_FILE)
        FileUtils.rm_f(state_file_path) if File.exist?(state_file_path)
      end
      
      def create_volume_backup(backup_path)
        log_info "Creating volume backup: #{backup_path}"
        
        FileUtils.mkdir_p(File.dirname(backup_path))
        
        volumes_dir = File.join(@work_dir, 'volumes')
        
        if File.exist?(volumes_dir)
          system("tar -czf #{backup_path} -C #{@work_dir} volumes")
          
          if File.exist?(backup_path)
            log_info "Volume backup created: #{backup_path} (#{File.size(backup_path)} bytes)"
            return backup_path
          end
        end
        
        raise TestError, "Failed to create volume backup"
      end
      
      def restore_volume_backup(backup_path)
        return false unless File.exist?(backup_path)
        
        log_info "Restoring volume backup: #{backup_path}"
        
        # Clean up existing volumes first
        cleanup_volumes
        
        # Extract backup
        success = system("tar -xzf #{backup_path} -C #{@work_dir}")
        
        if success
          # Reload volume state
          load_volume_state
          log_info "Volume backup restored successfully"
          true
        else
          log_error "Failed to restore volume backup"
          false
        end
      end
      
      def volume_statistics
        stats = {
          total_volumes: @volumes.size,
          total_size: total_volume_size,
          volumes: {}
        }
        
        @volumes.each do |name, volume|
          stats[:volumes][name] = {
            host_path: volume[:host_path],
            container_path: volume[:container_path],
            readonly: volume[:readonly],
            size: volume_size(name),
            exists: File.exist?(volume[:host_path])
          }
        end
        
        stats
      end
      
      private
      
      def setup_volume_directories
        volumes_base_dir = File.join(@work_dir, 'volumes')
        FileUtils.mkdir_p(volumes_base_dir)
        
        # Create standard volume directories
        %w[recipes artifacts config logs cache].each do |volume_type|
          dir = File.join(volumes_base_dir, volume_type)
          FileUtils.mkdir_p(dir)
        end
      end
      
      def add_volume(name, host_path, container_path, options = {})
        # Ensure host path exists and is absolute
        host_path = File.expand_path(host_path)
        FileUtils.mkdir_p(host_path) unless File.exist?(host_path)
        
        @volumes[name] = {
          host_path: host_path,
          container_path: container_path,
          readonly: options.fetch(:readonly, false),
          created_at: Time.now
        }
        
        # Track managed directories for cleanup
        if host_path.start_with?(@work_dir)
          @managed_directories << host_path
        end
        
        save_volume_state
        
        log_debug "Added volume: #{name} (#{host_path} -> #{container_path})"
      end
      
      def load_volume_state
        state_file_path = File.join(@work_dir, VOLUME_STATE_FILE)
        
        if File.exist?(state_file_path)
          @state = YAML.load_file(state_file_path) || {}
          
          # Restore volumes from state
          if @state[:volumes]
            @state[:volumes].each do |name, volume_data|
              @volumes[name] = volume_data.transform_keys(&:to_sym)
            end
          end
          
          # Restore managed directories
          @managed_directories = @state[:managed_directories] || []
        end
      end
      
      def save_volume_state
        state_file_path = File.join(@work_dir, VOLUME_STATE_FILE)
        
        @state[:volumes] = @volumes
        @state[:managed_directories] = @managed_directories
        @state[:updated_at] = Time.now
        
        File.write(state_file_path, YAML.dump(@state))
      end
      
      def calculate_directory_size(path)
        return 0 unless File.exist?(path)
        
        total_size = 0
        
        Dir.glob(File.join(path, '**', '*')).each do |file_path|
          total_size += File.size(file_path) if File.file?(file_path)
        end
        
        total_size
      end
    end
  end
end