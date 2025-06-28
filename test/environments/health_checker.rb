require 'timeout'
require 'yaml'

module MitamaeTest
  module Environments
    class HealthChecker
      include Logging
      include ErrorHandling
      
      HEALTH_CHECK_TIMEOUT = 30
      READINESS_CHECK_TIMEOUT = 60
      
      # Health check types
      BASIC_CHECKS = %i[connectivity process_running file_system].freeze
      SYSTEMD_CHECKS = %i[systemd_status services_running].freeze
      NETWORK_CHECKS = %i[dns_resolution port_connectivity].freeze
      RESOURCE_CHECKS = %i[memory_usage disk_usage cpu_usage].freeze
      
      attr_reader :environment, :check_config
      
      def initialize(environment, config = {})
        @environment = environment
        @check_config = {
          enabled_checks: config[:enabled_checks] || BASIC_CHECKS,
          timeout: config[:timeout] || HEALTH_CHECK_TIMEOUT,
          retry_attempts: config[:retry_attempts] || 3,
          retry_delay: config[:retry_delay] || 5,
          thresholds: config[:thresholds] || default_thresholds
        }
        @last_check_result = nil
        @check_history = []
      end
      
      def perform_health_check(check_types = nil)
        check_types ||= @check_config[:enabled_checks]
        
        log_debug "Performing health check: #{check_types.join(', ')}"
        
        health_result = {
          environment_id: environment_identifier,
          timestamp: Time.now,
          overall_status: :unknown,
          checks: {},
          errors: [],
          duration: 0
        }
        
        start_time = Time.now
        
        begin
          Timeout.timeout(@check_config[:timeout]) do
            check_types.each do |check_type|
              health_result[:checks][check_type] = perform_individual_check(check_type)
            end
          end
          
          # Determine overall status
          health_result[:overall_status] = calculate_overall_status(health_result[:checks])
          
        rescue Timeout::Error
          health_result[:errors] << "Health check timed out after #{@check_config[:timeout]}s"
          health_result[:overall_status] = :timeout
        rescue => e
          health_result[:errors] << "Health check failed: #{e.message}"
          health_result[:overall_status] = :error
          log_error "Health check failed: #{e.message}"
        end
        
        health_result[:duration] = Time.now - start_time
        
        # Store result
        @last_check_result = health_result
        @check_history << health_result
        @check_history = @check_history.last(50) # Keep last 50 checks
        
        log_health_result(health_result)
        health_result
      end
      
      def perform_readiness_check
        log_debug "Performing readiness check"
        
        readiness_result = {
          environment_id: environment_identifier,
          timestamp: Time.now,
          ready: false,
          checks: {},
          errors: [],
          duration: 0
        }
        
        start_time = Time.now
        
        begin
          Timeout.timeout(READINESS_CHECK_TIMEOUT) do
            # Basic readiness checks
            readiness_result[:checks][:environment_ready] = check_environment_ready
            readiness_result[:checks][:basic_connectivity] = perform_individual_check(:connectivity)
            
            # Wait for systemd if applicable
            if environment.respond_to?(:systemd_enabled) && environment.systemd_enabled
              readiness_result[:checks][:systemd_ready] = wait_for_systemd_ready
            end
            
            # Wait for required services
            if @check_config[:required_services]
              readiness_result[:checks][:required_services] = wait_for_required_services
            end
            
            # Custom readiness checks
            if environment.respond_to?(:custom_readiness_check)
              readiness_result[:checks][:custom] = environment.custom_readiness_check
            end
          end
          
          # All checks must pass for readiness
          readiness_result[:ready] = readiness_result[:checks].values.all? { |check| check[:status] == :healthy }
          
        rescue Timeout::Error
          readiness_result[:errors] << "Readiness check timed out after #{READINESS_CHECK_TIMEOUT}s"
        rescue => e
          readiness_result[:errors] << "Readiness check failed: #{e.message}"
          log_error "Readiness check failed: #{e.message}"
        end
        
        readiness_result[:duration] = Time.now - start_time
        
        log_info "Readiness check completed: #{readiness_result[:ready] ? 'READY' : 'NOT READY'}"
        readiness_result
      end
      
      def wait_for_ready(max_wait_time = 300, check_interval = 10)
        log_info "Waiting for environment to become ready (max #{max_wait_time}s)"
        
        start_time = Time.now
        
        loop do
          readiness_result = perform_readiness_check
          
          if readiness_result[:ready]
            log_info "Environment is ready after #{(Time.now - start_time).round(1)}s"
            return true
          end
          
          elapsed = Time.now - start_time
          if elapsed >= max_wait_time
            log_error "Environment not ready after #{max_wait_time}s timeout"
            return false
          end
          
          log_debug "Environment not ready, waiting #{check_interval}s... (#{elapsed.round(1)}s elapsed)"
          sleep check_interval
        end
      end
      
      def continuous_health_monitoring(interval_seconds = 60)
        log_info "Starting continuous health monitoring (interval: #{interval_seconds}s)"
        
        Thread.new do
          loop do
            begin
              result = perform_health_check
              
              if result[:overall_status] != :healthy
                log_warn "Health check failed: #{result[:overall_status]}"
                handle_unhealthy_environment(result)
              end
              
            rescue => e
              log_error "Health monitoring error: #{e.message}"
            end
            
            sleep interval_seconds
          end
        end
      end
      
      def get_health_status
        return { status: :unknown, message: 'No health checks performed' } unless @last_check_result
        
        {
          status: @last_check_result[:overall_status],
          last_check: @last_check_result[:timestamp],
          checks: @last_check_result[:checks],
          errors: @last_check_result[:errors]
        }
      end
      
      def get_health_history(limit = 10)
        @check_history.last(limit)
      end
      
      def export_health_report(format = :yaml)
        report = {
          environment_id: environment_identifier,
          generated_at: Time.now,
          current_status: get_health_status,
          history: get_health_history,
          configuration: @check_config
        }
        
        case format
        when :yaml
          YAML.dump(report)
        when :json
          JSON.pretty_generate(report)
        else
          report
        end
      end
      
      private
      
      def perform_individual_check(check_type)
        check_result = {
          status: :unknown,
          details: {},
          duration: 0,
          errors: []
        }
        
        start_time = Time.now
        
        begin
          case check_type
          when :connectivity
            check_result = check_connectivity
          when :process_running
            check_result = check_process_running
          when :file_system
            check_result = check_file_system
          when :systemd_status
            check_result = check_systemd_status
          when :services_running
            check_result = check_services_running
          when :dns_resolution
            check_result = check_dns_resolution
          when :port_connectivity
            check_result = check_port_connectivity
          when :memory_usage
            check_result = check_memory_usage
          when :disk_usage
            check_result = check_disk_usage
          when :cpu_usage
            check_result = check_cpu_usage
          else
            check_result[:errors] << "Unknown check type: #{check_type}"
            check_result[:status] = :error
          end
          
        rescue => e
          check_result[:errors] << e.message
          check_result[:status] = :error
        end
        
        check_result[:duration] = Time.now - start_time
        check_result
      end
      
      def check_connectivity
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        result = environment.execute("echo 'connectivity_test'", timeout: 10)
        
        if result[:success] && result[:stdout].strip == 'connectivity_test'
          { status: :healthy, details: { response_time: result[:duration] || 0 } }
        else
          { status: :unhealthy, errors: ["Connectivity test failed: #{result[:stderr]}"] }
        end
      end
      
      def check_process_running
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        # For containers, check if container is running
        if environment.is_a?(Container)
          if environment.container_id
            result = system("podman inspect #{environment.container_id} > /dev/null 2>&1")
            status = result ? :healthy : :unhealthy
            { status: status, details: { container_id: environment.container_id } }
          else
            { status: :error, errors: ['No container ID available'] }
          end
          
        # For VMs, check if VM process is running
        elsif environment.is_a?(VM)
          if environment.vm_process_running?
            { status: :healthy, details: { pid_file: environment.pid_file } }
          else
            { status: :unhealthy, errors: ['VM process not running'] }
          end
          
        else
          { status: :healthy, details: { type: 'unknown environment type' } }
        end
      end
      
      def check_file_system
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        # Check basic file system operations
        test_file = "/tmp/health_check_#{SecureRandom.hex(8)}"
        test_content = "health_check_test"
        
        # Write test
        write_result = environment.execute("echo '#{test_content}' > #{test_file}")
        return { status: :unhealthy, errors: ['Cannot write to filesystem'] } unless write_result[:success]
        
        # Read test
        read_result = environment.execute("cat #{test_file}")
        unless read_result[:success] && read_result[:stdout].strip == test_content
          return { status: :unhealthy, errors: ['Cannot read from filesystem'] }
        end
        
        # Cleanup
        environment.execute("rm -f #{test_file}")
        
        { status: :healthy, details: { test_file: test_file } }
      end
      
      def check_systemd_status
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        result = environment.execute("systemctl is-system-running", timeout: 10)
        
        # systemd returns different states: running, degraded, starting, etc.
        if result[:success] || result[:stdout].include?('running') || result[:stdout].include?('degraded')
          status = result[:stdout].include?('running') ? :healthy : :warning
          { status: status, details: { systemd_state: result[:stdout].strip } }
        else
          { status: :unhealthy, errors: ["systemd not running: #{result[:stdout]}"] }
        end
      end
      
      def check_services_running
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        required_services = @check_config[:required_services] || []
        service_statuses = {}
        all_healthy = true
        
        required_services.each do |service|
          result = environment.execute("systemctl is-active #{service}")
          status = result[:success] && result[:stdout].strip == 'active'
          service_statuses[service] = status
          all_healthy = false unless status
        end
        
        {
          status: all_healthy ? :healthy : :unhealthy,
          details: { services: service_statuses }
        }
      end
      
      def check_dns_resolution
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        test_hosts = @check_config[:test_hosts] || ['google.com', '8.8.8.8']
        resolution_results = {}
        all_resolved = true
        
        test_hosts.each do |host|
          result = environment.execute("nslookup #{host}", timeout: 10)
          resolved = result[:success]
          resolution_results[host] = resolved
          all_resolved = false unless resolved
        end
        
        {
          status: all_resolved ? :healthy : :unhealthy,
          details: { dns_resolution: resolution_results }
        }
      end
      
      def check_port_connectivity
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        test_ports = @check_config[:test_ports] || []
        port_results = {}
        all_reachable = true
        
        test_ports.each do |port_config|
          host = port_config[:host] || 'localhost'
          port = port_config[:port]
          
          result = environment.execute("nc -z #{host} #{port}", timeout: 5)
          reachable = result[:success]
          port_results["#{host}:#{port}"] = reachable
          all_reachable = false unless reachable
        end
        
        {
          status: all_reachable ? :healthy : :unhealthy,
          details: { port_connectivity: port_results }
        }
      end
      
      def check_memory_usage
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        result = environment.execute("free -m | grep '^Mem:'")
        return { status: :error, errors: ['Cannot get memory info'] } unless result[:success]
        
        # Parse memory info: Mem: total used free shared buff/cache available
        parts = result[:stdout].split
        total_mb = parts[1].to_i
        used_mb = parts[2].to_i
        
        usage_percent = (used_mb.to_f / total_mb * 100).round(1)
        threshold = @check_config[:thresholds][:memory_usage_percent]
        
        status = usage_percent > threshold ? :warning : :healthy
        status = :unhealthy if usage_percent > (threshold * 1.5)
        
        {
          status: status,
          details: {
            total_mb: total_mb,
            used_mb: used_mb,
            usage_percent: usage_percent,
            threshold: threshold
          }
        }
      end
      
      def check_disk_usage
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        result = environment.execute("df -h / | tail -1")
        return { status: :error, errors: ['Cannot get disk info'] } unless result[:success]
        
        # Parse disk usage: /dev/sda1 10G 5.0G 4.5G 53% /
        parts = result[:stdout].split
        usage_percent = parts[4].to_i # Remove % sign and convert
        
        threshold = @check_config[:thresholds][:disk_usage_percent]
        
        status = usage_percent > threshold ? :warning : :healthy
        status = :unhealthy if usage_percent > (threshold * 1.2)
        
        {
          status: status,
          details: {
            usage_percent: usage_percent,
            threshold: threshold,
            filesystem: parts[0],
            size: parts[1],
            used: parts[2],
            available: parts[3]
          }
        }
      end
      
      def check_cpu_usage
        return { status: :error, errors: ['Environment not ready'] } unless environment.ready?
        
        # Get 1-minute load average
        result = environment.execute("uptime")
        return { status: :error, errors: ['Cannot get load average'] } unless result[:success]
        
        # Parse: ... load average: 0.50, 0.75, 0.80
        load_match = result[:stdout].match(/load average:\s+([\d.]+)/)
        return { status: :error, errors: ['Cannot parse load average'] } unless load_match
        
        load_1min = load_match[1].to_f
        threshold = @check_config[:thresholds][:cpu_load_1min]
        
        status = load_1min > threshold ? :warning : :healthy
        status = :unhealthy if load_1min > (threshold * 2)
        
        {
          status: status,
          details: {
            load_1min: load_1min,
            threshold: threshold
          }
        }
      end
      
      def check_environment_ready
        {
          status: environment.ready? ? :healthy : :unhealthy,
          details: { ready: environment.ready? }
        }
      end
      
      def wait_for_systemd_ready
        max_attempts = 30
        attempt = 0
        
        while attempt < max_attempts
          result = perform_individual_check(:systemd_status)
          return result if result[:status] == :healthy
          
          attempt += 1
          sleep 2
        end
        
        { status: :unhealthy, errors: ['systemd not ready within timeout'] }
      end
      
      def wait_for_required_services
        return { status: :healthy, details: {} } unless @check_config[:required_services]
        
        max_attempts = 30
        attempt = 0
        
        while attempt < max_attempts
          result = perform_individual_check(:services_running)
          return result if result[:status] == :healthy
          
          attempt += 1
          sleep 2
        end
        
        { status: :unhealthy, errors: ['Required services not ready within timeout'] }
      end
      
      def calculate_overall_status(checks)
        return :error if checks.empty?
        
        statuses = checks.values.map { |check| check[:status] }
        
        return :unhealthy if statuses.include?(:unhealthy)
        return :error if statuses.include?(:error)
        return :warning if statuses.include?(:warning)
        return :timeout if statuses.include?(:timeout)
        
        :healthy
      end
      
      def log_health_result(result)
        status_emoji = {
          healthy: '✅',
          warning: '⚠️',
          unhealthy: '❌',
          error: '💥',
          timeout: '⏰',
          unknown: '❓'
        }
        
        emoji = status_emoji[result[:overall_status]]
        duration = result[:duration].round(2)
        
        log_info "Health check #{emoji} #{result[:overall_status].upcase} (#{duration}s)"
        
        if result[:overall_status] != :healthy
          result[:errors].each { |error| log_error "Health check error: #{error}" }
          
          unhealthy_checks = result[:checks].select { |_, check| check[:status] != :healthy }
          unhealthy_checks.each do |check_name, check|
            log_warn "#{check_name}: #{check[:status]} - #{check[:errors].join(', ')}"
          end
        end
      end
      
      def handle_unhealthy_environment(result)
        # This method can be extended to take corrective actions
        # For now, just log the issue
        log_error "Environment #{environment_identifier} is unhealthy: #{result[:overall_status]}"
        
        # Could implement auto-recovery mechanisms here
        # - Restart services
        # - Clear caches
        # - Recreate environment
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
      
      def default_thresholds
        {
          memory_usage_percent: 80,
          disk_usage_percent: 85,
          cpu_load_1min: 2.0
        }
      end
    end
  end
end