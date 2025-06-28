require 'fileutils'
require 'json'
require 'yaml'
require 'digest'
require 'find'

module MitamaeTest
  class ArtifactCollector
    include Logging
    include ErrorHandling
    
    ARTIFACT_TYPES = %i[
      logs
      screenshots
      system_state
      config_files
      package_state
      service_state
      performance_data
      test_output
      error_traces
      environment_info
    ].freeze
    
    COMPRESSION_FORMATS = %i[gzip tar_gz zip].freeze
    MAX_ARTIFACT_SIZE_MB = 500
    MAX_COLLECTION_TIME_SECONDS = 300
    
    attr_reader :environment, :output_dir, :collection_config, :collected_artifacts
    
    def initialize(environment, output_dir, config = {})
      @environment = environment
      @output_dir = File.expand_path(output_dir)
      @collection_config = default_config.merge(config)
      @collected_artifacts = {}
      @collection_metadata = {}
      @start_time = nil
      
      ensure_output_directory
    end
    
    def collect_all_artifacts(test_result = nil)
      log_info "Starting comprehensive artifact collection"
      @start_time = Time.now
      
      collection_session = {
        session_id: SecureRandom.hex(8),
        timestamp: @start_time,
        environment_id: environment_identifier,
        test_result: test_result,
        artifacts: {},
        errors: []
      }
      
      begin
        Timeout.timeout(MAX_COLLECTION_TIME_SECONDS) do
          ARTIFACT_TYPES.each do |artifact_type|
            next unless @collection_config[:artifact_types].include?(artifact_type)
            
            log_debug "Collecting #{artifact_type} artifacts"
            
            begin
              artifacts = collect_artifact_type(artifact_type, test_result)
              collection_session[:artifacts][artifact_type] = artifacts
              @collected_artifacts[artifact_type] = artifacts
            rescue => e
              error_msg = "Failed to collect #{artifact_type}: #{e.message}"
              collection_session[:errors] << error_msg
              log_error error_msg
            end
          end
        end
        
        # Generate collection summary
        collection_session[:duration] = Time.now - @start_time
        collection_session[:total_size] = calculate_total_size
        collection_session[:success] = collection_session[:errors].empty?
        
        # Save collection metadata
        save_collection_metadata(collection_session)
        
        # Create collection archive if requested
        if @collection_config[:create_archive]
          archive_path = create_collection_archive(collection_session[:session_id])
          collection_session[:archive_path] = archive_path
        end
        
        # Generate debugging report
        report_path = generate_debugging_report(collection_session)
        collection_session[:report_path] = report_path
        
        log_info "Artifact collection completed: #{collection_session[:artifacts].size} types, #{format_size(collection_session[:total_size])}"
        collection_session
        
      rescue Timeout::Error
        error_msg = "Artifact collection timed out after #{MAX_COLLECTION_TIME_SECONDS}s"
        collection_session[:errors] << error_msg
        collection_session[:timed_out] = true
        log_error error_msg
        collection_session
        
      rescue => e
        error_msg = "Artifact collection failed: #{e.message}"
        collection_session[:errors] << error_msg
        log_error error_msg
        collection_session
      end
    end
    
    def collect_failure_artifacts(test_failure)
      log_info "Collecting failure-specific artifacts"
      
      # Enhanced collection for failures
      failure_config = @collection_config.dup
      failure_config[:artifact_types] = ARTIFACT_TYPES # Collect everything for failures
      failure_config[:create_archive] = true
      failure_config[:generate_report] = true
      
      old_config = @collection_config
      @collection_config = failure_config
      
      begin
        collection_result = collect_all_artifacts(test_failure)
        
        # Add failure-specific information
        collect_failure_context(test_failure, collection_result)
        
        collection_result
      ensure
        @collection_config = old_config
      end
    end
    
    # Individual artifact collection methods
    
    def collect_logs
      log_debug "Collecting log artifacts"
      logs_dir = File.join(@output_dir, 'logs')
      FileUtils.mkdir_p(logs_dir)
      
      logs = {}
      
      # System logs
      logs.merge!(collect_system_logs(logs_dir))
      
      # Application logs
      logs.merge!(collect_application_logs(logs_dir))
      
      # Environment-specific logs
      logs.merge!(collect_environment_logs(logs_dir))
      
      # Test framework logs
      logs.merge!(collect_test_logs(logs_dir))
      
      logs
    end
    
    def collect_screenshots
      return {} unless environment.respond_to?(:take_screenshot)
      
      log_debug "Collecting screenshot artifacts"
      screenshots_dir = File.join(@output_dir, 'screenshots')
      FileUtils.mkdir_p(screenshots_dir)
      
      screenshots = {}
      
      # Take current screenshot
      screenshot_path = environment.take_screenshot(
        File.join(screenshots_dir, "current-#{timestamp_string}.png")
      )
      
      if screenshot_path && File.exist?(screenshot_path)
        screenshots[:current] = screenshot_path
        log_debug "Screenshot captured: #{screenshot_path}"
      end
      
      # Collect any existing screenshots from environment
      if environment.respond_to?(:work_dir) && environment.work_dir
        existing_screenshots = Dir.glob(File.join(environment.work_dir, '**', '*.png'))
        existing_screenshots.each_with_index do |screenshot, index|
          dest_path = File.join(screenshots_dir, "existing-#{index}.png")
          FileUtils.cp(screenshot, dest_path)
          screenshots["existing_#{index}".to_sym] = dest_path
        end
      end
      
      screenshots
    end
    
    def collect_system_state
      log_debug "Collecting system state artifacts"
      state_dir = File.join(@output_dir, 'system_state')
      FileUtils.mkdir_p(state_dir)
      
      state_info = {}
      
      # Process information
      state_info[:processes] = collect_process_info(state_dir)
      
      # Memory information
      state_info[:memory] = collect_memory_info(state_dir)
      
      # Disk information
      state_info[:disk] = collect_disk_info(state_dir)
      
      # Network information
      state_info[:network] = collect_network_info(state_dir)
      
      # Environment variables
      state_info[:environment_vars] = collect_environment_vars(state_dir)
      
      state_info
    end
    
    def collect_config_files
      log_debug "Collecting configuration file artifacts"
      config_dir = File.join(@output_dir, 'config_files')
      FileUtils.mkdir_p(config_dir)
      
      configs = {}
      
      # Common configuration paths to collect
      config_paths = [
        '/etc/hosts',
        '/etc/resolv.conf',
        '/etc/passwd',
        '/etc/group',
        '/etc/os-release',
        '/etc/systemd/system',
        '/home/*/.bashrc',
        '/home/*/.zshrc',
        '/home/*/.config',
        '/root/.bashrc'
      ]
      
      config_paths.each do |pattern|
        collect_config_pattern(pattern, config_dir, configs)
      end
      
      configs
    end
    
    def collect_package_state
      log_debug "Collecting package state artifacts"
      packages_dir = File.join(@output_dir, 'package_state')
      FileUtils.mkdir_p(packages_dir)
      
      packages = {}
      
      # Detect package manager and collect appropriate information
      if command_exists?('pacman')
        packages.merge!(collect_pacman_state(packages_dir))
      end
      
      if command_exists?('apt')
        packages.merge!(collect_apt_state(packages_dir))
      end
      
      if command_exists?('dnf') || command_exists?('yum')
        packages.merge!(collect_dnf_state(packages_dir))
      end
      
      if command_exists?('flatpak')
        packages.merge!(collect_flatpak_state(packages_dir))
      end
      
      packages
    end
    
    def collect_service_state
      log_debug "Collecting service state artifacts"
      services_dir = File.join(@output_dir, 'service_state')
      FileUtils.mkdir_p(services_dir)
      
      services = {}
      
      # systemd services
      if command_exists?('systemctl')
        services.merge!(collect_systemd_state(services_dir))
      end
      
      # runit services (for Void Linux)
      if File.exist?('/etc/runit')
        services.merge!(collect_runit_state(services_dir))
      end
      
      services
    end
    
    def collect_performance_data
      log_debug "Collecting performance data artifacts"
      perf_dir = File.join(@output_dir, 'performance_data')
      FileUtils.mkdir_p(perf_dir)
      
      performance = {}
      
      # System load and uptime
      performance[:load] = collect_load_info(perf_dir)
      
      # CPU information
      performance[:cpu] = collect_cpu_info(perf_dir)
      
      # I/O statistics
      performance[:io] = collect_io_info(perf_dir)
      
      performance
    end
    
    def collect_test_output
      log_debug "Collecting test output artifacts"
      test_dir = File.join(@output_dir, 'test_output')
      FileUtils.mkdir_p(test_dir)
      
      test_output = {}
      
      # Look for test output files in environment
      if environment.respond_to?(:work_dir) && environment.work_dir
        test_files = Dir.glob(File.join(environment.work_dir, '**', '*test*'))
        test_files.each do |file|
          next unless File.file?(file)
          
          relative_path = file.sub("#{environment.work_dir}/", '')
          dest_path = File.join(test_dir, File.basename(file))
          
          safe_copy_file(file, dest_path)
          test_output[relative_path] = dest_path
        end
      end
      
      test_output
    end
    
    def collect_error_traces
      log_debug "Collecting error trace artifacts"
      errors_dir = File.join(@output_dir, 'error_traces')
      FileUtils.mkdir_p(errors_dir)
      
      errors = {}
      
      # Collect core dumps
      core_dumps = find_core_dumps
      core_dumps.each_with_index do |dump, index|
        dest_path = File.join(errors_dir, "core_dump_#{index}")
        safe_copy_file(dump, dest_path)
        errors["core_dump_#{index}".to_sym] = dest_path
      end
      
      # Collect crash logs
      crash_logs = find_crash_logs
      crash_logs.each_with_index do |log, index|
        dest_path = File.join(errors_dir, "crash_log_#{index}.log")
        safe_copy_file(log, dest_path)
        errors["crash_log_#{index}".to_sym] = dest_path
      end
      
      errors
    end
    
    def collect_environment_info
      log_debug "Collecting environment information artifacts"
      env_dir = File.join(@output_dir, 'environment_info')
      FileUtils.mkdir_p(env_dir)
      
      env_info = {
        environment_type: environment.class.name,
        collection_time: Time.now.iso8601,
        collector_version: MitamaeTest::VERSION
      }
      
      # Environment-specific information
      if environment.respond_to?(:container_id)
        env_info[:container_id] = environment.container_id
        env_info[:container_info] = collect_container_info
      end
      
      if environment.respond_to?(:vm_name)
        env_info[:vm_name] = environment.vm_name
        env_info[:vm_info] = collect_vm_info
      end
      
      # Save environment info
      info_path = File.join(env_dir, 'environment_info.yaml')
      File.write(info_path, YAML.dump(env_info))
      
      { environment_info: info_path }
    end
    
    # Utility methods
    
    def cleanup_old_artifacts(max_age_days = 7)
      log_info "Cleaning up artifacts older than #{max_age_days} days"
      
      return unless File.exist?(@output_dir)
      
      cutoff_time = Time.now - (max_age_days * 24 * 3600)
      cleaned_count = 0
      
      Dir.glob(File.join(@output_dir, '*')).each do |path|
        if File.directory?(path) && File.mtime(path) < cutoff_time
          FileUtils.rm_rf(path)
          cleaned_count += 1
          log_debug "Removed old artifact directory: #{path}"
        end
      end
      
      log_info "Cleaned up #{cleaned_count} old artifact directories"
      cleaned_count
    end
    
    def get_artifact_summary
      return {} if @collected_artifacts.empty?
      
      summary = {
        collection_time: @start_time,
        artifact_types: @collected_artifacts.keys,
        total_files: 0,
        total_size: calculate_total_size,
        output_directory: @output_dir
      }
      
      @collected_artifacts.each do |type, artifacts|
        summary[:total_files] += artifacts.size if artifacts.is_a?(Hash)
      end
      
      summary
    end
    
    def create_browsable_index
      log_debug "Creating browsable artifact index"
      
      index_path = File.join(@output_dir, 'index.html')
      
      html_content = generate_html_index
      File.write(index_path, html_content)
      
      log_info "Browsable artifact index created: #{index_path}"
      index_path
    end
    
    private
    
    def collect_artifact_type(artifact_type, test_result)
      case artifact_type
      when :logs
        collect_logs
      when :screenshots
        collect_screenshots
      when :system_state
        collect_system_state
      when :config_files
        collect_config_files
      when :package_state
        collect_package_state
      when :service_state
        collect_service_state
      when :performance_data
        collect_performance_data
      when :test_output
        collect_test_output
      when :error_traces
        collect_error_traces
      when :environment_info
        collect_environment_info
      else
        {}
      end
    end
    
    def collect_system_logs(logs_dir)
      logs = {}
      
      # Journal logs (systemd)
      if command_exists?('journalctl')
        journal_file = File.join(logs_dir, 'journal.log')
        execute_and_save("journalctl --no-pager -n 1000", journal_file)
        logs[:journal] = journal_file
      end
      
      # Syslog
      syslog_paths = ['/var/log/syslog', '/var/log/messages']
      syslog_paths.each do |path|
        if file_exists_in_env?(path)
          dest_path = File.join(logs_dir, File.basename(path))
          copy_from_environment(path, dest_path)
          logs[File.basename(path).to_sym] = dest_path
        end
      end
      
      # Kernel logs
      if command_exists?('dmesg')
        dmesg_file = File.join(logs_dir, 'dmesg.log')
        execute_and_save("dmesg", dmesg_file)
        logs[:dmesg] = dmesg_file
      end
      
      logs
    end
    
    def collect_application_logs(logs_dir)
      logs = {}
      
      # Common application log directories
      log_paths = [
        '/var/log/*.log',
        '/tmp/*.log',
        '/home/*/.local/share/*/logs/*',
        '/root/.local/share/*/logs/*'
      ]
      
      log_paths.each do |pattern|
        collect_log_pattern(pattern, logs_dir, logs)
      end
      
      logs
    end
    
    def collect_environment_logs(logs_dir)
      logs = {}
      
      # Environment-specific logs
      if environment.respond_to?(:volume_manager)
        env_logs = environment.volume_manager.collect_logs
        env_logs.each do |name, log_path|
          dest_path = File.join(logs_dir, "env_#{name}")
          safe_copy_file(log_path, dest_path)
          logs["env_#{name}".to_sym] = dest_path
        end
      end
      
      logs
    end
    
    def collect_test_logs(logs_dir)
      logs = {}
      
      # Look for mitamae-specific logs
      mitamae_patterns = [
        '/tmp/mitamae*.log',
        '/var/log/mitamae*.log',
        '/home/*/mitamae*.log'
      ]
      
      mitamae_patterns.each do |pattern|
        collect_log_pattern(pattern, logs_dir, logs)
      end
      
      logs
    end
    
    def collect_process_info(state_dir)
      processes_file = File.join(state_dir, 'processes.txt')
      execute_and_save("ps auxf", processes_file)
      
      # Also collect process tree
      pstree_file = File.join(state_dir, 'process_tree.txt')
      execute_and_save("pstree -p", pstree_file) if command_exists?('pstree')
      
      { processes: processes_file, process_tree: pstree_file }
    end
    
    def collect_memory_info(state_dir)
      memory_file = File.join(state_dir, 'memory.txt')
      execute_and_save("free -h && cat /proc/meminfo", memory_file)
      
      { memory: memory_file }
    end
    
    def collect_disk_info(state_dir)
      disk_file = File.join(state_dir, 'disk.txt')
      execute_and_save("df -h && lsblk", disk_file)
      
      { disk: disk_file }
    end
    
    def collect_network_info(state_dir)
      network_file = File.join(state_dir, 'network.txt')
      commands = [
        "ip addr show",
        "ip route show",
        "ss -tuln",
        "cat /etc/resolv.conf"
      ]
      
      execute_and_save(commands.join(" && "), network_file)
      
      { network: network_file }
    end
    
    def collect_environment_vars(state_dir)
      env_file = File.join(state_dir, 'environment_vars.txt')
      execute_and_save("env | sort", env_file)
      
      { environment_vars: env_file }
    end
    
    def collect_pacman_state(packages_dir)
      packages = {}
      
      # Installed packages
      installed_file = File.join(packages_dir, 'pacman_installed.txt')
      execute_and_save("pacman -Q", installed_file)
      packages[:pacman_installed] = installed_file
      
      # Package database
      db_file = File.join(packages_dir, 'pacman_database.txt')
      execute_and_save("pacman -Ss | head -1000", db_file)
      packages[:pacman_database] = db_file
      
      packages
    end
    
    def collect_apt_state(packages_dir)
      packages = {}
      
      # Installed packages
      installed_file = File.join(packages_dir, 'apt_installed.txt')
      execute_and_save("dpkg -l", installed_file)
      packages[:apt_installed] = installed_file
      
      # Package sources
      sources_file = File.join(packages_dir, 'apt_sources.txt')
      copy_from_environment("/etc/apt/sources.list", sources_file) if file_exists_in_env?("/etc/apt/sources.list")
      packages[:apt_sources] = sources_file
      
      packages
    end
    
    def collect_dnf_state(packages_dir)
      packages = {}
      
      # Installed packages
      installed_file = File.join(packages_dir, 'dnf_installed.txt')
      execute_and_save("rpm -qa", installed_file)
      packages[:dnf_installed] = installed_file
      
      packages
    end
    
    def collect_flatpak_state(packages_dir)
      packages = {}
      
      # Installed flatpaks
      flatpak_file = File.join(packages_dir, 'flatpak_installed.txt')
      execute_and_save("flatpak list", flatpak_file)
      packages[:flatpak_installed] = flatpak_file
      
      packages
    end
    
    def collect_systemd_state(services_dir)
      services = {}
      
      # Service status
      status_file = File.join(services_dir, 'systemd_status.txt')
      execute_and_save("systemctl list-units --type=service", status_file)
      services[:systemd_status] = status_file
      
      # Failed services
      failed_file = File.join(services_dir, 'systemd_failed.txt')
      execute_and_save("systemctl list-units --failed", failed_file)
      services[:systemd_failed] = failed_file
      
      services
    end
    
    def collect_runit_state(services_dir)
      services = {}
      
      # Runit service status
      if File.exist?('/etc/runit/runsvdir')
        runit_file = File.join(services_dir, 'runit_status.txt')
        execute_and_save("sv status /etc/service/*", runit_file)
        services[:runit_status] = runit_file
      end
      
      services
    end
    
    def collect_load_info(perf_dir)
      load_file = File.join(perf_dir, 'load.txt')
      execute_and_save("uptime && cat /proc/loadavg", load_file)
      
      { load: load_file }
    end
    
    def collect_cpu_info(perf_dir)
      cpu_file = File.join(perf_dir, 'cpu.txt')
      execute_and_save("cat /proc/cpuinfo && lscpu", cpu_file)
      
      { cpu: cpu_file }
    end
    
    def collect_io_info(perf_dir)
      io_file = File.join(perf_dir, 'io.txt')
      execute_and_save("iostat", io_file) if command_exists?('iostat')
      
      { io: io_file }
    end
    
    def collect_failure_context(test_failure, collection_result)
      return unless test_failure
      
      failure_dir = File.join(@output_dir, 'failure_context')
      FileUtils.mkdir_p(failure_dir)
      
      # Save test failure information
      failure_info = {
        failure_time: Time.now.iso8601,
        test_name: test_failure[:test_name],
        error_message: test_failure[:error_message],
        stack_trace: test_failure[:stack_trace],
        exit_code: test_failure[:exit_code]
      }
      
      failure_file = File.join(failure_dir, 'test_failure.yaml')
      File.write(failure_file, YAML.dump(failure_info))
      
      collection_result[:failure_context] = failure_file
    end
    
    def collect_container_info
      return {} unless environment.respond_to?(:container_id)
      
      container_info = {}
      
      # Container inspection
      if system("podman inspect #{environment.container_id} > /dev/null 2>&1")
        inspect_output = `podman inspect #{environment.container_id}`
        container_info[:inspect] = JSON.parse(inspect_output)
      end
      
      # Container logs
      if system("podman logs #{environment.container_id} > /dev/null 2>&1")
        container_info[:logs] = `podman logs #{environment.container_id}`
      end
      
      container_info
    end
    
    def collect_vm_info
      return {} unless environment.respond_to?(:vm_name)
      
      vm_info = {
        vm_name: environment.vm_name,
        pid_file: environment.pid_file,
        vnc_port: environment.vnc_port,
        ssh_port: environment.ssh_port
      }
      
      # VM process information
      if File.exist?(environment.pid_file)
        pid = File.read(environment.pid_file).strip
        vm_info[:pid] = pid
        vm_info[:process_running] = system("kill -0 #{pid} 2>/dev/null")
      end
      
      vm_info
    end
    
    # Helper methods
    
    def ensure_output_directory
      FileUtils.mkdir_p(@output_dir)
    end
    
    def environment_identifier
      if environment.respond_to?(:name)
        environment.name
      elsif environment.respond_to?(:container_id)
        environment.container_id
      elsif environment.respond_to?(:vm_name)
        environment.vm_name
      else
        environment.object_id.to_s
      end
    end
    
    def default_config
      {
        artifact_types: ARTIFACT_TYPES,
        create_archive: false,
        compression_format: :gzip,
        max_file_size_mb: 50,
        include_binary_files: false,
        generate_report: true
      }
    end
    
    def command_exists?(command)
      result = environment.execute("command -v #{command}", timeout: 5)
      result[:success]
    end
    
    def file_exists_in_env?(path)
      result = environment.execute("test -f '#{path}'", timeout: 5)
      result[:success]
    end
    
    def execute_and_save(command, output_file)
      result = environment.execute(command, timeout: 30)
      
      content = if result[:success]
                  result[:stdout]
                else
                  "Command failed: #{command}\nSTDERR: #{result[:stderr]}"
                end
      
      File.write(output_file, content)
      output_file
    end
    
    def copy_from_environment(source_path, dest_path)
      if environment.respond_to?(:copy_from_container)
        environment.copy_from_container(source_path, dest_path)
      elsif environment.respond_to?(:copy_from_vm)
        environment.copy_from_vm(source_path, dest_path)
      else
        # Fallback: read file content and write locally
        content = environment.read_file(source_path)
        File.write(dest_path, content)
      end
    rescue => e
      log_warn "Failed to copy #{source_path}: #{e.message}"
    end
    
    def safe_copy_file(source, destination)
      return unless File.exist?(source)
      return if File.size(source) > (@collection_config[:max_file_size_mb] * 1024 * 1024)
      
      FileUtils.cp(source, destination)
    rescue => e
      log_warn "Failed to copy file #{source}: #{e.message}"
    end
    
    def collect_log_pattern(pattern, logs_dir, logs_hash)
      result = environment.execute("find #{File.dirname(pattern)} -name '#{File.basename(pattern)}' 2>/dev/null", timeout: 10)
      
      if result[:success]
        result[:stdout].split("\n").each_with_index do |log_path, index|
          log_path = log_path.strip
          next if log_path.empty?
          
          dest_path = File.join(logs_dir, "#{File.basename(pattern, '.*')}_#{index}.log")
          copy_from_environment(log_path, dest_path)
          logs_hash["#{File.basename(pattern)}_#{index}".to_sym] = dest_path
        end
      end
    end
    
    def collect_config_pattern(pattern, config_dir, configs_hash)
      result = environment.execute("find #{File.dirname(pattern)} -path '#{pattern}' 2>/dev/null", timeout: 10)
      
      if result[:success]
        result[:stdout].split("\n").each_with_index do |config_path, index|
          config_path = config_path.strip
          next if config_path.empty?
          
          # Create subdirectory structure
          relative_path = config_path.sub('/', '')
          dest_path = File.join(config_dir, relative_path)
          FileUtils.mkdir_p(File.dirname(dest_path))
          
          copy_from_environment(config_path, dest_path)
          configs_hash[relative_path.gsub('/', '_').to_sym] = dest_path
        end
      end
    end
    
    def find_core_dumps
      dumps = []
      
      # Common core dump locations
      dump_patterns = [
        '/tmp/core*',
        '/var/tmp/core*',
        '/core*',
        '/home/*/core*'
      ]
      
      dump_patterns.each do |pattern|
        result = environment.execute("find #{File.dirname(pattern)} -name '#{File.basename(pattern)}' 2>/dev/null", timeout: 10)
        
        if result[:success]
          dumps += result[:stdout].split("\n").map(&:strip).reject(&:empty?)
        end
      end
      
      dumps
    end
    
    def find_crash_logs
      logs = []
      
      # Common crash log patterns
      crash_patterns = [
        '/var/log/*crash*',
        '/tmp/*crash*',
        '/var/crash/*'
      ]
      
      crash_patterns.each do |pattern|
        result = environment.execute("find #{File.dirname(pattern)} -name '#{File.basename(pattern)}' 2>/dev/null", timeout: 10)
        
        if result[:success]
          logs += result[:stdout].split("\n").map(&:strip).reject(&:empty?)
        end
      end
      
      logs
    end
    
    def calculate_total_size
      return 0 unless File.exist?(@output_dir)
      
      total_size = 0
      Find.find(@output_dir) do |path|
        total_size += File.size(path) if File.file?(path)
      end
      total_size
    end
    
    def format_size(bytes)
      units = %w[B KB MB GB TB]
      size = bytes.to_f
      unit_index = 0
      
      while size >= 1024.0 && unit_index < units.length - 1
        size /= 1024.0
        unit_index += 1
      end
      
      "#{size.round(2)} #{units[unit_index]}"
    end
    
    def timestamp_string
      Time.now.strftime('%Y%m%d-%H%M%S')
    end
    
    def save_collection_metadata(collection_session)
      metadata_file = File.join(@output_dir, 'collection_metadata.yaml')
      File.write(metadata_file, YAML.dump(collection_session))
    end
    
    def create_collection_archive(session_id)
      archive_name = "artifacts-#{session_id}-#{timestamp_string}"
      
      case @collection_config[:compression_format]
      when :gzip
        archive_path = "#{archive_name}.tar.gz"
        system("tar -czf #{archive_path} -C #{File.dirname(@output_dir)} #{File.basename(@output_dir)}")
      when :zip
        archive_path = "#{archive_name}.zip"
        system("zip -r #{archive_path} #{@output_dir}")
      else
        archive_path = "#{archive_name}.tar"
        system("tar -cf #{archive_path} -C #{File.dirname(@output_dir)} #{File.basename(@output_dir)}")
      end
      
      File.expand_path(archive_path)
    end
    
    def generate_debugging_report(collection_session)
      report_path = File.join(@output_dir, 'debugging_report.html')
      
      html_content = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Mitamae Test Debugging Report</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .header { background: #f5f5f5; padding: 15px; border-radius: 5px; }
            .section { margin: 20px 0; }
            .artifact-list { background: #fafafa; padding: 10px; border-radius: 3px; }
            .error { color: red; }
            .success { color: green; }
            .artifact-link { display: block; margin: 5px 0; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background-color: #f2f2f2; }
          </style>
        </head>
        <body>
          <div class="header">
            <h1>Mitamae Test Debugging Report</h1>
            <p><strong>Environment:</strong> #{collection_session[:environment_id]}</p>
            <p><strong>Collection Time:</strong> #{collection_session[:timestamp]}</p>
            <p><strong>Duration:</strong> #{collection_session[:duration]&.round(2)}s</p>
            <p><strong>Total Size:</strong> #{format_size(collection_session[:total_size])}</p>
            <p class="#{collection_session[:success] ? 'success' : 'error'}">
              <strong>Status:</strong> #{collection_session[:success] ? 'SUCCESS' : 'FAILED'}
            </p>
          </div>
          
          #{generate_artifacts_section(collection_session)}
          #{generate_errors_section(collection_session)}
          #{generate_summary_section(collection_session)}
        </body>
        </html>
      HTML
      
      File.write(report_path, html_content)
      report_path
    end
    
    def generate_html_index
      # This would generate a comprehensive browsable index
      # Implementation would be similar to generate_debugging_report
      # but focused on navigation and artifact browsing
      "<html><body><h1>Artifact Index</h1><p>Placeholder for browsable index</p></body></html>"
    end
    
    def generate_artifacts_section(collection_session)
      return "" if collection_session[:artifacts].empty?
      
      html = "<div class='section'><h2>Collected Artifacts</h2>"
      
      collection_session[:artifacts].each do |type, artifacts|
        html += "<h3>#{type.to_s.humanize}</h3>"
        html += "<div class='artifact-list'>"
        
        if artifacts.is_a?(Hash)
          artifacts.each do |name, path|
            relative_path = path.sub(@output_dir + '/', '') if path.is_a?(String)
            html += "<a href='#{relative_path}' class='artifact-link'>#{name}</a>"
          end
        else
          html += "<p>#{artifacts}</p>"
        end
        
        html += "</div>"
      end
      
      html += "</div>"
    end
    
    def generate_errors_section(collection_session)
      return "" if collection_session[:errors].empty?
      
      html = "<div class='section'><h2>Collection Errors</h2><ul>"
      
      collection_session[:errors].each do |error|
        html += "<li class='error'>#{error}</li>"
      end
      
      html += "</ul></div>"
    end
    
    def generate_summary_section(collection_session)
      html = "<div class='section'><h2>Collection Summary</h2>"
      html += "<table>"
      html += "<tr><th>Metric</th><th>Value</th></tr>"
      html += "<tr><td>Artifact Types</td><td>#{collection_session[:artifacts].keys.join(', ')}</td></tr>"
      html += "<tr><td>Total Files</td><td>#{count_total_files(collection_session[:artifacts])}</td></tr>"
      html += "<tr><td>Collection Duration</td><td>#{collection_session[:duration]&.round(2)}s</td></tr>"
      html += "<tr><td>Archive Created</td><td>#{collection_session[:archive_path] ? 'Yes' : 'No'}</td></tr>"
      html += "</table>"
      html += "</div>"
    end
    
    def count_total_files(artifacts)
      total = 0
      artifacts.each do |_, artifact_data|
        total += artifact_data.size if artifact_data.is_a?(Hash)
      end
      total
    end
  end
end