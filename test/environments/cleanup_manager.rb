require 'fileutils'
require 'yaml'
require 'find'

module MitamaeTest
  module Environments
    class CleanupManager
      include Logging
      include ErrorHandling
      
      CLEANUP_STATE_FILE = '.cleanup_state.yml'
      MAX_DISK_USAGE_GB = 10  # Maximum disk usage for test environments
      MAX_AGE_HOURS = 24      # Maximum age for temporary environments
      
      attr_reader :base_work_dir, :resource_limits
      
      def initialize(base_work_dir = nil)
        @base_work_dir = base_work_dir || File.join(Dir.tmpdir, 'mitamae-test')
        @resource_limits = {
          max_disk_usage: MAX_DISK_USAGE_GB * 1024 * 1024 * 1024, # Convert to bytes
          max_age: MAX_AGE_HOURS * 3600, # Convert to seconds
          max_environments: 50
        }
        @cleanup_state = {}
        
        ensure_base_directory
        load_cleanup_state
      end
      
      def cleanup_environment(environment)
        environment_id = environment.respond_to?(:name) ? environment.name : environment.to_s
        log_info "Cleaning up environment: #{environment_id}"
        
        cleanup_stats = {
          environment_id: environment_id,
          started_at: Time.now,
          errors: []
        }
        
        begin
          # Stop environment gracefully
          if environment.respond_to?(:ready?) && environment.ready?
            safe_execute("stop environment") do
              environment.teardown
              cleanup_stats[:environment_stopped] = true
            end
          end
          
          # Clean up environment-specific resources
          cleanup_environment_resources(environment, cleanup_stats)
          
          # Remove from tracking
          remove_from_tracking(environment_id)
          
          cleanup_stats[:completed_at] = Time.now
          cleanup_stats[:success] = true
          
          log_info "Environment cleanup completed: #{environment_id}"
          
        rescue => e
          cleanup_stats[:errors] << e.message
          cleanup_stats[:success] = false
          log_error "Environment cleanup failed: #{environment_id} - #{e.message}"
        end
        
        record_cleanup_operation(cleanup_stats)
        cleanup_stats
      end
      
      def cleanup_all_environments
        log_info "Starting cleanup of all test environments"
        
        cleanup_results = []
        environments = discover_environments
        
        environments.each do |env_info|
          result = cleanup_environment_by_info(env_info)
          cleanup_results << result
        end
        
        # Also clean up orphaned resources
        cleanup_orphaned_resources
        
        log_info "Cleanup completed: #{cleanup_results.size} environments processed"
        cleanup_results
      end
      
      def cleanup_old_environments(max_age_hours = MAX_AGE_HOURS)
        log_info "Cleaning up environments older than #{max_age_hours} hours"
        
        cutoff_time = Time.now - (max_age_hours * 3600)
        old_environments = discover_environments.select do |env_info|
          env_info[:created_at] && env_info[:created_at] < cutoff_time
        end
        
        cleanup_results = []
        old_environments.each do |env_info|
          log_info "Cleaning up old environment: #{env_info[:id]} (#{env_info[:age_hours].round(1)} hours old)"
          result = cleanup_environment_by_info(env_info)
          cleanup_results << result
        end
        
        log_info "Old environment cleanup completed: #{cleanup_results.size} environments cleaned"
        cleanup_results
      end
      
      def enforce_resource_limits
        log_info "Enforcing resource limits"
        
        current_usage = calculate_resource_usage
        actions_taken = []
        
        # Check disk usage
        if current_usage[:disk_usage] > @resource_limits[:max_disk_usage]
          log_warn "Disk usage limit exceeded: #{current_usage[:disk_usage_gb].round(1)}GB > #{@resource_limits[:max_disk_usage] / (1024**3)}GB"
          actions_taken += cleanup_by_disk_usage
        end
        
        # Check environment count
        if current_usage[:environment_count] > @resource_limits[:max_environments]
          log_warn "Environment count limit exceeded: #{current_usage[:environment_count]} > #{@resource_limits[:max_environments]}"
          actions_taken += cleanup_by_age
        end
        
        # Check for very old environments
        actions_taken += cleanup_old_environments(@resource_limits[:max_age] / 3600)
        
        log_info "Resource limit enforcement completed: #{actions_taken.size} actions taken"
        actions_taken
      end
      
      def get_resource_usage
        calculate_resource_usage
      end
      
      def get_environment_list
        discover_environments
      end
      
      def emergency_cleanup
        log_warn "Performing emergency cleanup - removing all test environments"
        
        # Force cleanup all environments
        cleanup_results = cleanup_all_environments
        
        # Remove entire base directory
        if File.exist?(@base_work_dir)
          FileUtils.rm_rf(@base_work_dir)
          log_warn "Removed entire test work directory: #{@base_work_dir}"
        end
        
        # Clean up system resources
        cleanup_system_resources
        
        # Reset tracking state
        @cleanup_state = {}
        save_cleanup_state
        
        log_warn "Emergency cleanup completed"
        cleanup_results
      end
      
      def schedule_periodic_cleanup(interval_hours = 6)
        log_info "Scheduling periodic cleanup every #{interval_hours} hours"
        
        Thread.new do
          loop do
            begin
              log_debug "Running periodic cleanup"
              cleanup_old_environments
              enforce_resource_limits
            rescue => e
              log_error "Periodic cleanup failed: #{e.message}"
            end
            
            sleep(interval_hours * 3600)
          end
        end
      end
      
      def cleanup_statistics
        {
          total_cleanups: @cleanup_state[:operations]&.size || 0,
          last_cleanup: @cleanup_state[:last_cleanup],
          current_usage: calculate_resource_usage,
          resource_limits: @resource_limits,
          environments: discover_environments.size
        }
      end
      
      private
      
      def ensure_base_directory
        FileUtils.mkdir_p(@base_work_dir) unless File.exist?(@base_work_dir)
      end
      
      def load_cleanup_state
        state_file = File.join(@base_work_dir, CLEANUP_STATE_FILE)
        
        if File.exist?(state_file)
          @cleanup_state = YAML.load_file(state_file) || {}
        else
          @cleanup_state = {
            operations: [],
            tracked_environments: {},
            last_cleanup: nil
          }
        end
      end
      
      def save_cleanup_state
        state_file = File.join(@base_work_dir, CLEANUP_STATE_FILE)
        File.write(state_file, YAML.dump(@cleanup_state))
      end
      
      def discover_environments
        environments = []
        
        return environments unless File.exist?(@base_work_dir)
        
        # Look for environment directories
        Dir.glob(File.join(@base_work_dir, '*')).each do |path|
          next unless File.directory?(path)
          
          env_info = analyze_environment_directory(path)
          environments << env_info if env_info
        end
        
        # Also discover running containers
        environments += discover_running_containers
        
        # Discover running VMs
        environments += discover_running_vms
        
        environments
      end
      
      def analyze_environment_directory(path)
        dir_name = File.basename(path)
        return nil unless dir_name.start_with?('mitamae-test')
        
        stat = File.stat(path)
        size = calculate_directory_size(path)
        age = Time.now - stat.mtime
        
        {
          id: dir_name,
          type: :directory,
          path: path,
          created_at: stat.mtime,
          age_hours: age / 3600.0,
          size_bytes: size,
          size_mb: size / (1024.0 * 1024.0)
        }
      end
      
      def discover_running_containers
        containers = []
        
        begin
          # List containers with mitamae-test prefix
          output = `podman ps -a --format="{{.Names}}\t{{.CreatedAt}}\t{{.Status}}" --filter="name=mitamae-test" 2>/dev/null`
          
          output.each_line do |line|
            parts = line.strip.split("\t")
            next if parts.size < 3
            
            name, created_str, status = parts
            created_at = parse_podman_time(created_str)
            age = created_at ? (Time.now - created_at) / 3600.0 : 0
            
            containers << {
              id: name,
              type: :container,
              created_at: created_at,
              age_hours: age,
              status: status,
              running: status.include?('Up')
            }
          end
        rescue => e
          log_debug "Could not discover containers: #{e.message}"
        end
        
        containers
      end
      
      def discover_running_vms
        vms = []
        
        # Look for VM PID files
        pid_pattern = File.join(@base_work_dir, '*', 'mitamae-test-vm-*.pid')
        
        Dir.glob(pid_pattern).each do |pid_file|
          next unless File.exist?(pid_file)
          
          pid = File.read(pid_file).strip
          vm_name = File.basename(pid_file, '.pid')
          
          if process_running?(pid)
            stat = File.stat(pid_file)
            age = (Time.now - stat.mtime) / 3600.0
            
            vms << {
              id: vm_name,
              type: :vm,
              pid: pid,
              pid_file: pid_file,
              created_at: stat.mtime,
              age_hours: age,
              running: true
            }
          else
            # Clean up stale PID file
            FileUtils.rm_f(pid_file)
          end
        end
        
        vms
      end
      
      def cleanup_environment_resources(environment, stats)
        environment_id = environment.respond_to?(:name) ? environment.name : environment.to_s
        
        # Clean up volumes if environment has a volume manager
        if environment.respond_to?(:volume_manager) && environment.volume_manager
          safe_execute("cleanup volumes") do
            environment.volume_manager.cleanup_volumes
            stats[:volumes_cleaned] = true
          end
        end
        
        # Clean up work directory
        work_dir = if environment.respond_to?(:work_dir)
                     environment.work_dir
                   else
                     File.join(@base_work_dir, environment_id)
                   end
        
        if work_dir && File.exist?(work_dir)
          safe_execute("cleanup work directory") do
            FileUtils.rm_rf(work_dir)
            stats[:work_dir_removed] = work_dir
            stats[:disk_freed] = calculate_directory_size(work_dir)
          end
        end
      end
      
      def cleanup_environment_by_info(env_info)
        cleanup_stats = {
          environment_id: env_info[:id],
          type: env_info[:type],
          started_at: Time.now,
          errors: []
        }
        
        begin
          case env_info[:type]
          when :directory
            cleanup_directory_environment(env_info, cleanup_stats)
          when :container
            cleanup_container_environment(env_info, cleanup_stats)
          when :vm
            cleanup_vm_environment(env_info, cleanup_stats)
          end
          
          cleanup_stats[:success] = true
          cleanup_stats[:completed_at] = Time.now
          
        rescue => e
          cleanup_stats[:errors] << e.message
          cleanup_stats[:success] = false
          log_error "Failed to cleanup #{env_info[:type]} #{env_info[:id]}: #{e.message}"
        end
        
        record_cleanup_operation(cleanup_stats)
        cleanup_stats
      end
      
      def cleanup_directory_environment(env_info, stats)
        path = env_info[:path]
        
        if File.exist?(path)
          size_before = calculate_directory_size(path)
          FileUtils.rm_rf(path)
          stats[:disk_freed] = size_before
          log_debug "Removed directory: #{path} (freed #{size_before / (1024*1024)}MB)"
        end
      end
      
      def cleanup_container_environment(env_info, stats)
        container_name = env_info[:id]
        
        # Stop container if running
        if env_info[:running]
          system("podman stop #{container_name} 2>/dev/null")
          stats[:container_stopped] = true
        end
        
        # Remove container
        system("podman rm -f #{container_name} 2>/dev/null")
        stats[:container_removed] = true
        
        log_debug "Cleaned up container: #{container_name}"
      end
      
      def cleanup_vm_environment(env_info, stats)
        vm_name = env_info[:id]
        pid = env_info[:pid]
        
        # Kill VM process
        if process_running?(pid)
          Process.kill('TERM', pid.to_i)
          sleep 2
          
          if process_running?(pid)
            Process.kill('KILL', pid.to_i)
          end
          
          stats[:vm_stopped] = true
        end
        
        # Remove PID file
        FileUtils.rm_f(env_info[:pid_file]) if env_info[:pid_file]
        
        # Remove VM work directory
        vm_work_dir = File.dirname(env_info[:pid_file])
        if File.exist?(vm_work_dir)
          size_before = calculate_directory_size(vm_work_dir)
          FileUtils.rm_rf(vm_work_dir)
          stats[:disk_freed] = size_before
        end
        
        log_debug "Cleaned up VM: #{vm_name}"
      end
      
      def cleanup_orphaned_resources
        log_debug "Cleaning up orphaned resources"
        
        # Clean up orphaned containers
        cleanup_orphaned_containers
        
        # Clean up orphaned VM files
        cleanup_orphaned_vm_files
        
        # Clean up empty directories
        cleanup_empty_directories
      end
      
      def cleanup_orphaned_containers
        begin
          # Remove stopped containers with mitamae-test prefix
          system("podman container prune -f --filter='label=mitamae-test' 2>/dev/null")
        rescue => e
          log_debug "Could not clean orphaned containers: #{e.message}"
        end
      end
      
      def cleanup_orphaned_vm_files
        # Look for VM disk files without corresponding PID files
        disk_pattern = File.join(@base_work_dir, '*', 'mitamae-test-vm-*.qcow2')
        
        Dir.glob(disk_pattern).each do |disk_file|
          vm_name = File.basename(disk_file, '.qcow2')
          pid_file = File.join(File.dirname(disk_file), "#{vm_name}.pid")
          
          unless File.exist?(pid_file)
            log_debug "Removing orphaned VM disk: #{disk_file}"
            FileUtils.rm_f(disk_file)
          end
        end
      end
      
      def cleanup_empty_directories
        Find.find(@base_work_dir) do |path|
          if File.directory?(path) && Dir.empty?(path) && path != @base_work_dir
            FileUtils.rmdir(path)
            log_debug "Removed empty directory: #{path}"
          end
        end
      end
      
      def cleanup_system_resources
        # Clean up any system-wide resources that might be left over
        
        # Clean up network interfaces (if any were created)
        safe_execute("cleanup network resources") do
          system("podman network prune -f 2>/dev/null")
        end
        
        # Clean up volumes
        safe_execute("cleanup volume resources") do
          system("podman volume prune -f 2>/dev/null")
        end
      end
      
      def calculate_resource_usage
        total_disk = 0
        environment_count = 0
        environments = discover_environments
        
        environments.each do |env|
          environment_count += 1
          total_disk += env[:size_bytes] || 0
        end
        
        # Add base directory size
        if File.exist?(@base_work_dir)
          total_disk += calculate_directory_size(@base_work_dir)
        end
        
        {
          disk_usage: total_disk,
          disk_usage_gb: total_disk / (1024.0 ** 3),
          environment_count: environment_count,
          environments: environments
        }
      end
      
      def cleanup_by_disk_usage
        environments = discover_environments.sort_by { |env| env[:size_bytes] || 0 }.reverse
        actions = []
        
        # Remove largest environments first
        environments.first(5).each do |env|
          result = cleanup_environment_by_info(env)
          actions << result
          
          # Check if we're under the limit now
          current_usage = calculate_resource_usage
          break if current_usage[:disk_usage] <= @resource_limits[:max_disk_usage]
        end
        
        actions
      end
      
      def cleanup_by_age
        environments = discover_environments.sort_by { |env| env[:age_hours] || 0 }.reverse
        actions = []
        
        # Remove oldest environments
        environments.first(10).each do |env|
          result = cleanup_environment_by_info(env)
          actions << result
        end
        
        actions
      end
      
      def remove_from_tracking(environment_id)
        @cleanup_state[:tracked_environments]&.delete(environment_id)
        save_cleanup_state
      end
      
      def record_cleanup_operation(stats)
        @cleanup_state[:operations] ||= []
        @cleanup_state[:operations] << stats
        
        # Keep only last 100 operations
        @cleanup_state[:operations] = @cleanup_state[:operations].last(100)
        
        @cleanup_state[:last_cleanup] = Time.now
        save_cleanup_state
      end
      
      def calculate_directory_size(path)
        return 0 unless File.exist?(path)
        
        total_size = 0
        Find.find(path) do |file_path|
          total_size += File.size(file_path) if File.file?(file_path)
        end
        total_size
      end
      
      def process_running?(pid)
        return false unless pid && pid.match?(/^\d+$/)
        
        Process.kill(0, pid.to_i)
        true
      rescue Errno::ESRCH
        false
      end
      
      def parse_podman_time(time_str)
        # Podman time formats can vary, try common patterns
        patterns = [
          '%Y-%m-%d %H:%M:%S %z',
          '%Y-%m-%d %H:%M:%S',
          '%m/%d/%Y %H:%M:%S'
        ]
        
        patterns.each do |pattern|
          begin
            return Time.strptime(time_str, pattern)
          rescue ArgumentError
            next
          end
        end
        
        # Fallback: try to parse as duration (e.g., "2 hours ago")
        if time_str.match(/(\d+)\s+(minute|hour|day)s?\s+ago/)
          duration = $1.to_i
          unit = $2
          
          case unit
          when 'minute'
            return Time.now - (duration * 60)
          when 'hour'
            return Time.now - (duration * 3600)
          when 'day'
            return Time.now - (duration * 86400)
          end
        end
        
        nil
      end
    end
  end
end