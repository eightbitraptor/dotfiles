require 'timeout'

module MitamaeTest
  module Validators
    class FunctionalTestValidator < Base
      plugin_name :functional_test
      plugin_type :validator
      
      def validate(environment, context = {})
        clear_results
        
        applications = context[:applications] || []
        
        log_info "Running functional tests for #{applications.size} applications"
        
        applications.each do |app_spec|
          validate_application(environment, app_spec)
        end
        
        log_info "Functional test validation complete: #{success? ? 'PASSED' : 'FAILED'}"
        self
      end
      
      private
      
      def validate_application(environment, app_spec)
        name = app_spec[:name]
        log_debug "Testing application: #{name}"
        
        # Check if application can be launched
        if app_spec[:command]
          test_command_execution(environment, app_spec)
        end
        
        # Check if service is running (for daemon applications)
        if app_spec[:service]
          test_service_status(environment, app_spec)
        end
        
        # Check network endpoints
        if app_spec[:endpoints]
          test_network_endpoints(environment, app_spec)
        end
        
        # Check process behavior
        if app_spec[:process_check]
          test_process_behavior(environment, app_spec)
        end
        
        # Run custom test scripts
        if app_spec[:test_script]
          run_custom_test_script(environment, app_spec)
        end
        
        # Check graphical applications
        if app_spec[:graphical]
          test_graphical_application(environment, app_spec)
        end
      end
      
      def test_command_execution(environment, app_spec)
        name = app_spec[:name]
        command = app_spec[:command]
        timeout = app_spec[:timeout] || 10
        
        log_debug "Testing command execution: #{command}"
        
        # Test basic execution
        result = execute_command(environment, command, timeout: timeout)
        
        if app_spec[:expect_success] != false && !result.success?
          add_error("Application failed to execute: #{name}",
                   details: { 
                     command: command,
                     exit_code: result.exit_code,
                     stderr: result.stderr.lines.first(5).join
                   })
          return
        end
        
        # Check expected output
        if app_spec[:expected_output]
          pattern = Regexp.new(app_spec[:expected_output])
          unless result.stdout.match?(pattern) || result.stderr.match?(pattern)
            add_error("Application output doesn't match expected pattern: #{name}",
                     details: { 
                       expected: app_spec[:expected_output],
                       actual_stdout: result.stdout.lines.first(3).join,
                       actual_stderr: result.stderr.lines.first(3).join
                     })
          end
        end
        
        # Check version if specified
        if app_spec[:version_check]
          check_application_version(environment, app_spec)
        end
      end
      
      def test_service_status(environment, app_spec)
        service_name = app_spec[:service]
        
        # Check if service is active
        result = execute_command(environment, "systemctl is-active #{service_name}")
        
        if result.stdout.strip != "active"
          # Try to get more info about why it's not active
          status_result = execute_command(environment, "systemctl status #{service_name}")
          
          add_error("Service is not active: #{service_name}",
                   details: {
                     state: result.stdout.strip,
                     status: status_result.stdout.lines.first(10).join
                   })
          return
        end
        
        # Check if service is enabled
        if app_spec[:check_enabled]
          enabled_result = execute_command(environment, "systemctl is-enabled #{service_name}")
          if enabled_result.stdout.strip != "enabled"
            add_warning("Service is not enabled: #{service_name}")
          end
        end
        
        # Check service logs for errors
        if app_spec[:check_logs]
          check_service_logs(environment, service_name)
        end
      end
      
      def test_network_endpoints(environment, app_spec)
        endpoints = Array(app_spec[:endpoints])
        
        endpoints.each do |endpoint|
          case endpoint[:type]
          when :http, :https
            test_http_endpoint(environment, endpoint)
          when :tcp
            test_tcp_endpoint(environment, endpoint)
          when :unix
            test_unix_socket(environment, endpoint)
          end
        end
      end
      
      def test_http_endpoint(environment, endpoint)
        url = endpoint[:url]
        expected_code = endpoint[:expected_code] || 200
        timeout = endpoint[:timeout] || 5
        
        # Use curl to test HTTP endpoint
        curl_cmd = "curl -s -o /dev/null -w '%{http_code}' --connect-timeout #{timeout} '#{url}'"
        result = execute_command(environment, curl_cmd, timeout: timeout + 2)
        
        if result.success?
          actual_code = result.stdout.strip.to_i
          if actual_code != expected_code
            add_error("HTTP endpoint returned unexpected status: #{url}",
                     details: { expected: expected_code, actual: actual_code })
          end
        else
          add_error("Failed to connect to HTTP endpoint: #{url}",
                   details: { error: result.stderr })
        end
        
        # Test response content if specified
        if endpoint[:expected_content]
          content_result = execute_command(environment, "curl -s '#{url}'", timeout: timeout)
          if content_result.success?
            unless content_result.stdout.include?(endpoint[:expected_content])
              add_error("HTTP response missing expected content: #{url}")
            end
          end
        end
      end
      
      def test_tcp_endpoint(environment, endpoint)
        host = endpoint[:host] || 'localhost'
        port = endpoint[:port]
        timeout = endpoint[:timeout] || 5
        
        # Test TCP connection
        nc_cmd = "timeout #{timeout} nc -z #{host} #{port}"
        result = execute_command(environment, nc_cmd)
        
        unless result.success?
          add_error("TCP port not accessible: #{host}:#{port}")
        end
      end
      
      def test_unix_socket(environment, endpoint)
        socket_path = endpoint[:path]
        
        # Check if socket exists
        unless environment.file_exists?(socket_path)
          add_error("Unix socket not found: #{socket_path}")
          return
        end
        
        # Check if it's actually a socket
        result = execute_command(environment, "test -S '#{socket_path}'")
        unless result.success?
          add_error("Path exists but is not a socket: #{socket_path}")
        end
        
        # Test connection if command provided
        if endpoint[:test_command]
          test_result = execute_command(environment, endpoint[:test_command])
          unless test_result.success?
            add_error("Unix socket test failed: #{socket_path}")
          end
        end
      end
      
      def test_process_behavior(environment, app_spec)
        process_check = app_spec[:process_check]
        
        # Start the process
        if process_check[:start_command]
          start_result = execute_command(environment, process_check[:start_command])
          unless start_result.success?
            add_error("Failed to start process: #{app_spec[:name]}")
            return
          end
          
          # Wait for process to stabilize
          sleep(process_check[:startup_delay] || 2)
        end
        
        # Check process is running
        if process_check[:process_name]
          pgrep_result = execute_command(environment, "pgrep -f '#{process_check[:process_name]}'")
          unless pgrep_result.success?
            add_error("Process not found: #{process_check[:process_name]}")
          end
        end
        
        # Check resource usage
        if process_check[:check_resources]
          check_process_resources(environment, process_check)
        end
        
        # Stop the process if we started it
        if process_check[:stop_command]
          stop_result = execute_command(environment, process_check[:stop_command])
          unless stop_result.success?
            add_warning("Failed to stop process cleanly: #{app_spec[:name]}")
          end
        end
      end
      
      def run_custom_test_script(environment, app_spec)
        script_path = app_spec[:test_script]
        timeout = app_spec[:test_timeout] || 60
        
        unless environment.file_exists?(script_path)
          add_error("Test script not found: #{script_path}")
          return
        end
        
        # Make script executable
        execute_command(environment, "chmod +x '#{script_path}'")
        
        # Run the test script
        result = execute_command(environment, script_path, timeout: timeout)
        
        unless result.success?
          add_error("Test script failed: #{script_path}",
                   details: {
                     exit_code: result.exit_code,
                     output: result.output.lines.last(20).join
                   })
        end
        
        # Parse test output if format specified
        if app_spec[:test_output_format]
          parse_test_output(result.stdout, app_spec[:test_output_format])
        end
      end
      
      def test_graphical_application(environment, app_spec)
        name = app_spec[:name]
        
        # Check if X server is available
        x_check = execute_command(environment, "xset q", timeout: 2)
        unless x_check.success?
          add_warning("X server not available, skipping graphical tests for #{name}")
          return
        end
        
        # Try to launch with timeout
        launch_cmd = app_spec[:graphical][:launch_command] || app_spec[:command]
        
        # Run in background and check if it stays running
        test_cmd = "timeout 5 #{launch_cmd} & sleep 2 && pgrep -f '#{launch_cmd}'"
        result = execute_command(environment, test_cmd)
        
        if result.success?
          # Kill the test process
          execute_command(environment, "pkill -f '#{launch_cmd}'")
        else
          add_error("Graphical application failed to start: #{name}")
        end
      end
      
      def check_application_version(environment, app_spec)
        version_cmd = app_spec[:version_check][:command]
        expected_version = app_spec[:version_check][:expected]
        
        result = execute_command(environment, version_cmd)
        if result.success?
          actual_version = result.stdout.strip
          
          if expected_version.is_a?(Regexp)
            unless actual_version.match?(expected_version)
              add_error("Version mismatch: #{app_spec[:name]}",
                       details: { expected: expected_version.to_s, actual: actual_version })
            end
          elsif expected_version.is_a?(String)
            unless actual_version.include?(expected_version)
              add_error("Version mismatch: #{app_spec[:name]}",
                       details: { expected: expected_version, actual: actual_version })
            end
          end
        else
          add_error("Failed to check version: #{app_spec[:name]}")
        end
      end
      
      def check_service_logs(environment, service_name)
        # Check recent logs for errors
        log_cmd = "journalctl -u #{service_name} -n 100 --no-pager"
        result = execute_command(environment, log_cmd)
        
        if result.success?
          error_patterns = [
            /error/i,
            /fail/i,
            /crash/i,
            /fatal/i,
            /panic/i
          ]
          
          error_lines = result.stdout.lines.select do |line|
            error_patterns.any? { |pattern| line.match?(pattern) }
          end
          
          if error_lines.any?
            add_warning("Service logs contain errors: #{service_name}",
                       details: { sample_errors: error_lines.first(5).map(&:strip) })
          end
        end
      end
      
      def check_process_resources(environment, process_check)
        process_name = process_check[:process_name]
        
        # Get process info
        ps_cmd = "ps aux | grep -E '#{process_name}' | grep -v grep"
        result = execute_command(environment, ps_cmd)
        
        if result.success?
          result.stdout.lines.each do |line|
            parts = line.split(/\s+/)
            next if parts.size < 11
            
            cpu_usage = parts[2].to_f
            mem_usage = parts[3].to_f
            
            if process_check[:max_cpu] && cpu_usage > process_check[:max_cpu]
              add_warning("High CPU usage for #{process_name}: #{cpu_usage}%")
            end
            
            if process_check[:max_memory] && mem_usage > process_check[:max_memory]
              add_warning("High memory usage for #{process_name}: #{mem_usage}%")
            end
          end
        end
      end
      
      def parse_test_output(output, format)
        case format
        when :tap
          # Parse TAP (Test Anything Protocol) output
          tap_errors = []
          output.lines.each do |line|
            if line =~ /^not ok \d+ - (.+)$/
              tap_errors << $1
            end
          end
          
          if tap_errors.any?
            add_error("Custom tests failed",
                     details: { failed_tests: tap_errors })
          end
          
        when :junit
          # Would parse JUnit XML format
          # For now, just check for basic success indicators
          if output.include?('<failure') || output.include?('<error')
            add_error("JUnit tests reported failures")
          end
        end
      end
    end
  end
end