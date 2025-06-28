require_relative 'error_handler'
require_relative 'logging'
require 'io/console'
require 'readline'

module MitamaeTest
  # Interactive debugging system for failed tests
  class InteractiveDebugger
    include Logging
    
    attr_reader :test_result, :environment, :artifacts, :session_id
    
    def initialize(test_result, environment, artifacts = {})
      @test_result = test_result
      @environment = environment
      @artifacts = artifacts
      @session_id = SecureRandom.hex(8)
      @debug_commands = setup_debug_commands
      @continue_execution = false
      
      log_info "Interactive debugger started for failed test: #{test_result.test_name}"
    end
    
    # Main debugging loop
    def start_debugging
      display_failure_summary
      display_available_artifacts
      
      puts "\n" + "="*60
      puts "INTERACTIVE DEBUGGER"
      puts "Type 'help' for available commands, 'quit' to exit"
      puts "="*60
      
      loop do
        command_input = prompt_for_command
        break if handle_command(command_input)
      end
      
      log_info "Interactive debugging session ended"
      @continue_execution
    end
    
    private
    
    def setup_debug_commands
      {
        'help' => method(:show_help),
        'h' => method(:show_help),
        'summary' => method(:show_failure_summary),
        's' => method(:show_failure_summary),
        'logs' => method(:show_logs),
        'l' => method(:show_logs),
        'artifacts' => method(:list_artifacts),
        'a' => method(:list_artifacts),
        'view' => method(:view_artifact),
        'v' => method(:view_artifact),
        'shell' => method(:start_shell),
        'sh' => method(:start_shell),
        'env' => method(:show_environment_info),
        'e' => method(:show_environment_info),
        'recipe' => method(:show_recipe_info),
        'r' => method(:show_recipe_info),
        'retry' => method(:retry_test),
        'rerun' => method(:retry_test),
        'fix' => method(:suggest_fixes),
        'f' => method(:suggest_fixes),
        'compare' => method(:compare_with_baseline),
        'c' => method(:compare_with_baseline),
        'export' => method(:export_debug_session),
        'x' => method(:export_debug_session),
        'continue' => method(:continue_execution),
        'cont' => method(:continue_execution),
        'quit' => method(:quit_debugger),
        'q' => method(:quit_debugger),
        'exit' => method(:quit_debugger)
      }
    end
    
    def prompt_for_command
      begin
        Readline.readline("debug> ", true)&.strip
      rescue Interrupt
        puts "\nUse 'quit' to exit the debugger"
        ""
      end
    end
    
    def handle_command(input)
      return true if input.nil? || input.empty?
      
      parts = input.split(/\s+/)
      command = parts[0].downcase
      args = parts[1..-1]
      
      if @debug_commands.key?(command)
        begin
          result = @debug_commands[command].call(args)
          return result if result == :quit || result == :continue
        rescue => e
          puts "Error executing command '#{command}': #{e.message}"
          log_error "Debug command error: #{e.message}"
        end
      else
        puts "Unknown command: #{command}. Type 'help' for available commands."
      end
      
      false
    end
    
    # Command implementations
    def show_help(args = [])
      puts <<~HELP
        
        Interactive Debugger Commands:
        
        General:
          help, h              Show this help message
          summary, s           Show failure summary and details
          quit, q, exit        Exit the debugger
          continue, cont       Continue test execution (skip remaining failures)
        
        Artifacts & Logs:
          artifacts, a         List available artifacts
          logs, l [type]       Show logs (all, mitamae, system, error)
          view, v <artifact>   View specific artifact content
          export, x [path]     Export debug session for sharing
        
        Environment:
          env, e               Show environment information
          shell, sh            Start interactive shell in test environment
          recipe, r            Show recipe information and execution details
        
        Analysis:
          fix, f               Suggest potential fixes for the failure
          compare, c           Compare with baseline or previous successful run
          retry, rerun         Retry the failed test interactively
        
        Examples:
          logs mitamae         Show mitamae execution logs
          view system_state    View system state artifact
          shell                Start shell for manual investigation
          fix                  Get automated fix suggestions
      HELP
    end
    
    def show_failure_summary(args = [])
      puts "\n" + "="*50
      puts "FAILURE SUMMARY"
      puts "="*50
      
      puts "Test: #{@test_result.test_name}"
      puts "Status: #{@test_result.status}"
      puts "Duration: #{@test_result.duration}s"
      puts "Environment: #{@environment.name} (#{@environment.type})"
      
      if @test_result.error_message
        puts "\nError Message:"
        puts "  #{@test_result.error_message}"
      end
      
      if @test_result.details && @test_result.details[:validation_failures]
        puts "\nValidation Failures:"
        @test_result.details[:validation_failures].each do |failure|
          puts "  • #{failure[:validator]}: #{failure[:message]}"
        end
      end
      
      if @test_result.details && @test_result.details[:mitamae_output]
        puts "\nMitamae Output (last 10 lines):"
        output_lines = @test_result.details[:mitamae_output].split("\n")
        output_lines.last(10).each do |line|
          puts "  #{line}"
        end
      end
    end
    
    def show_logs(args = [])
      log_type = args.first || 'all'
      
      case log_type.downcase
      when 'mitamae'
        show_mitamae_logs
      when 'system'
        show_system_logs
      when 'error'
        show_error_logs
      when 'all'
        show_all_logs
      else
        puts "Unknown log type: #{log_type}. Available: all, mitamae, system, error"
      end
    end
    
    def show_mitamae_logs
      if @artifacts[:logs] && @artifacts[:logs][:mitamae_log]
        puts "\n" + "="*50
        puts "MITAMAE EXECUTION LOG"
        puts "="*50
        
        log_content = File.read(@artifacts[:logs][:mitamae_log])
        puts log_content
      else
        puts "No mitamae logs available in artifacts"
      end
    end
    
    def show_system_logs
      if @artifacts[:logs] && @artifacts[:logs][:system_log]
        puts "\n" + "="*50
        puts "SYSTEM LOGS"
        puts "="*50
        
        log_content = File.read(@artifacts[:logs][:system_log])
        # Show last 50 lines for readability
        lines = log_content.split("\n")
        puts lines.last(50).join("\n")
      else
        puts "No system logs available in artifacts"
      end
    end
    
    def show_error_logs
      if @artifacts[:logs] && @artifacts[:logs][:error_log]
        puts "\n" + "="*50
        puts "ERROR LOGS"
        puts "="*50
        
        log_content = File.read(@artifacts[:logs][:error_log])
        puts log_content
      else
        puts "No error logs available in artifacts"
      end
    end
    
    def show_all_logs
      show_mitamae_logs
      show_system_logs
      show_error_logs
    end
    
    def list_artifacts(args = [])
      puts "\n" + "="*50
      puts "AVAILABLE ARTIFACTS"
      puts "="*50
      
      if @artifacts.empty?
        puts "No artifacts collected for this test"
        return
      end
      
      @artifacts.each do |category, artifacts|
        puts "\n#{category.to_s.upcase}:"
        
        if artifacts.is_a?(Hash)
          artifacts.each do |name, path|
            size = File.exist?(path) ? format_file_size(File.size(path)) : "missing"
            puts "  #{name}: #{path} (#{size})"
          end
        else
          puts "  #{artifacts}"
        end
      end
      
      puts "\nUse 'view <artifact_name>' to examine specific artifacts"
    end
    
    def view_artifact(args = [])
      artifact_name = args.first
      
      unless artifact_name
        puts "Usage: view <artifact_name>"
        puts "Use 'artifacts' to see available artifacts"
        return
      end
      
      artifact_path = find_artifact_path(artifact_name)
      
      unless artifact_path
        puts "Artifact '#{artifact_name}' not found"
        list_artifacts
        return
      end
      
      unless File.exist?(artifact_path)
        puts "Artifact file does not exist: #{artifact_path}"
        return
      end
      
      puts "\n" + "="*50
      puts "ARTIFACT: #{artifact_name}"
      puts "Path: #{artifact_path}"
      puts "Size: #{format_file_size(File.size(artifact_path))}"
      puts "="*50
      
      # Determine how to display the artifact
      content_type = detect_content_type(artifact_path)
      
      case content_type
      when :text
        display_text_artifact(artifact_path)
      when :image
        display_image_artifact(artifact_path)
      when :binary
        display_binary_artifact(artifact_path)
      end
    end
    
    def start_shell(args = [])
      puts "\n" + "="*50
      puts "INTERACTIVE SHELL"
      puts "Starting shell in test environment..."
      puts "Type 'exit' to return to debugger"
      puts "="*50
      
      if @environment.type == 'container'
        result = @environment.execute_interactive('bash -l')
      elsif @environment.type == 'vm'
        result = @environment.execute_interactive('bash -l')
      else
        # Local environment
        system('bash -l')
      end
      
      puts "\nReturned to interactive debugger"
    end
    
    def show_environment_info(args = [])
      puts "\n" + "="*50
      puts "ENVIRONMENT INFORMATION"
      puts "="*50
      
      puts "Name: #{@environment.name}"
      puts "Type: #{@environment.type}"
      puts "Distribution: #{@environment.distribution}"
      puts "Status: #{@environment.status}"
      
      if @environment.respond_to?(:container_id)
        puts "Container ID: #{@environment.container_id}"
      end
      
      if @environment.respond_to?(:vm_id)
        puts "VM ID: #{@environment.vm_id}"
      end
      
      # Show environment variables
      if @artifacts[:environment_info]
        puts "\nEnvironment Variables (key ones):"
        env_content = File.read(@artifacts[:environment_info][:env_vars])
        env_content.split("\n").select { |line| 
          line.match(/^(PATH|HOME|USER|SHELL|TERM)=/) 
        }.each do |line|
          puts "  #{line}"
        end
      end
      
      # Show system info
      if @artifacts[:environment_info]
        puts "\nSystem Information:"
        system_info = File.read(@artifacts[:environment_info][:system_info])
        puts "  #{system_info.strip}"
      end
    end
    
    def show_recipe_info(args = [])
      puts "\n" + "="*50
      puts "RECIPE INFORMATION"
      puts "="*50
      
      if @test_result.test_spec
        spec = @test_result.test_spec
        puts "Recipe Path: #{spec.recipe_path}"
        puts "Recipe Name: #{spec.name}"
        puts "Tags: #{spec.tags.join(', ')}" if spec.tags
        puts "Environment: #{spec.environment_type}"
        puts "Distribution: #{spec.distribution}"
        
        if spec.node_attributes
          puts "\nNode Attributes:"
          spec.node_attributes.each do |key, value|
            puts "  #{key}: #{value}"
          end
        end
        
        if spec.validators
          puts "\nValidators:"
          spec.validators.each do |validator|
            puts "  • #{validator[:type]}: #{validator[:config]}"
          end
        end
      end
      
      if @test_result.details && @test_result.details[:recipe_execution]
        execution = @test_result.details[:recipe_execution]
        puts "\nExecution Details:"
        puts "  Duration: #{execution[:duration]}s"
        puts "  Resources Updated: #{execution[:resources_updated]&.length || 0}"
        puts "  Resources Skipped: #{execution[:resources_skipped]&.length || 0}"
        
        if execution[:resources_updated]&.any?
          puts "\n  Updated Resources:"
          execution[:resources_updated].each do |resource|
            puts "    • #{resource}"
          end
        end
      end
    end
    
    def retry_test(args = [])
      puts "\n" + "="*50
      puts "RETRY TEST"
      puts "="*50
      
      puts "Retrying failed test with current environment state..."
      
      # This would integrate with the test runner to retry the specific test
      # For now, we'll simulate the retry process
      
      puts "Would retry test: #{@test_result.test_name}"
      puts "In environment: #{@environment.name}"
      puts "\nNote: This would re-execute the test with the same environment"
      puts "Use the shell command to make manual fixes first if needed"
    end
    
    def suggest_fixes(args = [])
      puts "\n" + "="*50
      puts "AUTOMATED FIX SUGGESTIONS"
      puts "="*50
      
      suggestions = analyze_failure_for_fixes
      
      if suggestions.empty?
        puts "No automated fix suggestions available for this failure type"
        puts "Try using 'shell' to investigate manually"
      else
        suggestions.each_with_index do |suggestion, index|
          puts "\n#{index + 1}. #{suggestion[:title]}"
          puts "   #{suggestion[:description]}"
          
          if suggestion[:commands]
            puts "   Commands to try:"
            suggestion[:commands].each do |cmd|
              puts "     #{cmd}"
            end
          end
          
          if suggestion[:references]
            puts "   References:"
            suggestion[:references].each do |ref|
              puts "     • #{ref}"
            end
          end
        end
      end
    end
    
    def compare_with_baseline(args = [])
      puts "\n" + "="*50
      puts "BASELINE COMPARISON"
      puts "="*50
      
      # This would integrate with the artifact repository to find baseline
      puts "Searching for baseline or previous successful run..."
      puts "Would compare current artifacts with:"
      puts "  • Last successful run of this test"
      puts "  • Baseline environment snapshot"
      puts "  • Expected system state"
      
      puts "\nNote: Full comparison feature requires artifact repository integration"
    end
    
    def export_debug_session(args = [])
      export_path = args.first || "debug_session_#{@session_id}.tar.gz"
      
      puts "\n" + "="*50
      puts "EXPORT DEBUG SESSION"
      puts "="*50
      
      puts "Exporting debug session to: #{export_path}"
      
      # Create temporary directory for export
      export_dir = "/tmp/debug_export_#{@session_id}"
      FileUtils.mkdir_p(export_dir)
      
      begin
        # Copy artifacts
        if !@artifacts.empty?
          artifacts_dir = File.join(export_dir, 'artifacts')
          FileUtils.mkdir_p(artifacts_dir)
          
          @artifacts.each do |category, files|
            category_dir = File.join(artifacts_dir, category.to_s)
            FileUtils.mkdir_p(category_dir)
            
            if files.is_a?(Hash)
              files.each do |name, path|
                if File.exist?(path)
                  FileUtils.cp(path, File.join(category_dir, name.to_s))
                end
              end
            end
          end
        end
        
        # Create debug session info
        session_info = {
          session_id: @session_id,
          test_name: @test_result.test_name,
          failure_time: Time.now.iso8601,
          environment: {
            name: @environment.name,
            type: @environment.type,
            distribution: @environment.distribution
          },
          test_result: @test_result.to_h,
          artifacts: @artifacts
        }
        
        File.write(File.join(export_dir, 'session_info.json'), JSON.pretty_generate(session_info))
        
        # Create README
        readme_content = <<~README
          # Debug Session Export
          
          Session ID: #{@session_id}
          Test: #{@test_result.test_name}
          Export Time: #{Time.now}
          
          ## Contents:
          - session_info.json: Test failure details and metadata
          - artifacts/: Collected artifacts organized by category
          
          ## Usage:
          Extract this archive and examine the artifacts to debug the test failure.
          The session_info.json contains the complete test result and environment details.
        README
        
        File.write(File.join(export_dir, 'README.md'), readme_content)
        
        # Create tar.gz archive
        system("cd #{File.dirname(export_dir)} && tar -czf #{export_path} #{File.basename(export_dir)}")
        
        puts "Debug session exported successfully!"
        puts "Archive contains:"
        puts "  • Test failure details"
        puts "  • Environment information"
        puts "  • Collected artifacts"
        puts "  • Debug session metadata"
        
      ensure
        FileUtils.rm_rf(export_dir)
      end
    end
    
    def continue_execution(args = [])
      puts "Continuing test execution..."
      @continue_execution = true
      :continue
    end
    
    def quit_debugger(args = [])
      puts "Exiting debugger..."
      :quit
    end
    
    # Helper methods
    def display_failure_summary
      puts "\n" + "="*60
      puts "TEST FAILURE DETECTED"
      puts "="*60
      puts "Test: #{@test_result.test_name}"
      puts "Error: #{@test_result.error_message}" if @test_result.error_message
      puts "Duration: #{@test_result.duration}s"
    end
    
    def display_available_artifacts
      if @artifacts && !@artifacts.empty?
        puts "\nArtifacts collected: #{@artifacts.keys.join(', ')}"
        
        # Show key artifacts
        if @artifacts[:logs]
          puts "  Logs: #{@artifacts[:logs].keys.join(', ')}"
        end
        
        if @artifacts[:screenshots]
          puts "  Screenshots: #{@artifacts[:screenshots].keys.join(', ')}"
        end
      else
        puts "\nNo artifacts collected for this failure"
      end
    end
    
    def find_artifact_path(artifact_name)
      @artifacts.each do |category, artifacts|
        if artifacts.is_a?(Hash)
          if artifacts.key?(artifact_name.to_sym)
            return artifacts[artifact_name.to_sym]
          end
          
          # Try partial matches
          matching_key = artifacts.keys.find { |key| key.to_s.include?(artifact_name) }
          return artifacts[matching_key] if matching_key
        end
      end
      nil
    end
    
    def detect_content_type(file_path)
      case File.extname(file_path).downcase
      when '.png', '.jpg', '.jpeg', '.gif', '.bmp'
        :image
      when '.log', '.txt', '.yml', '.yaml', '.json', '.rb', '.sh', '.conf'
        :text
      else
        # Check if file is text-like
        if system("file '#{file_path}' | grep -q text", out: File::NULL, err: File::NULL)
          :text
        else
          :binary
        end
      end
    end
    
    def display_text_artifact(file_path)
      content = File.read(file_path)
      
      if content.length > 10000
        puts "File is large (#{format_file_size(content.length)}). Showing first 100 lines:"
        puts content.split("\n").first(100).join("\n")
        puts "\n... (truncated, use shell to view full file)"
      else
        puts content
      end
    end
    
    def display_image_artifact(file_path)
      puts "Image file: #{file_path}"
      puts "Size: #{format_file_size(File.size(file_path))}"
      
      # Try to open with system viewer
      if system("which open > /dev/null 2>&1") # macOS
        puts "Opening with system viewer..."
        system("open '#{file_path}'")
      elsif system("which xdg-open > /dev/null 2>&1") # Linux
        puts "Opening with system viewer..."
        system("xdg-open '#{file_path}'")
      else
        puts "Use your system's image viewer to open: #{file_path}"
      end
    end
    
    def display_binary_artifact(file_path)
      puts "Binary file: #{file_path}"
      puts "Size: #{format_file_size(File.size(file_path))}"
      puts "Use 'shell' command and appropriate tools to examine this file"
      
      # Show file type info
      file_info = `file '#{file_path}'`.strip
      puts "File type: #{file_info}"
    end
    
    def format_file_size(bytes)
      units = ['B', 'KB', 'MB', 'GB']
      size = bytes.to_f
      unit_index = 0
      
      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end
      
      "#{size.round(1)} #{units[unit_index]}"
    end
    
    def analyze_failure_for_fixes
      suggestions = []
      
      # Analyze based on error patterns
      error_message = @test_result.error_message&.downcase || ""
      
      # Package-related errors
      if error_message.include?("package") || error_message.include?("yay") || error_message.include?("pacman")
        suggestions << {
          title: "Package Installation Issue",
          description: "The test failed during package installation. This might be due to missing repositories, network issues, or conflicting packages.",
          commands: [
            "pacman -Sy  # Update package database",
            "pacman -S --needed base-devel  # Install build tools",
            "yay --version  # Check AUR helper",
            "ping -c 3 archlinux.org  # Check network connectivity"
          ],
          references: [
            "Arch Linux package management: https://wiki.archlinux.org/title/Pacman",
            "AUR troubleshooting: https://wiki.archlinux.org/title/Arch_User_Repository"
          ]
        }
      end
      
      # Service-related errors
      if error_message.include?("service") || error_message.include?("systemctl") || error_message.include?("systemd")
        suggestions << {
          title: "Service Management Issue",
          description: "The test failed when managing services. This could be due to systemd issues, missing service files, or dependency problems.",
          commands: [
            "systemctl daemon-reload  # Reload systemd configuration",
            "systemctl status <service>  # Check service status",
            "journalctl -u <service>  # View service logs",
            "systemctl --failed  # List failed services"
          ],
          references: [
            "systemd troubleshooting: https://wiki.archlinux.org/title/Systemd",
            "Service management: https://www.freedesktop.org/software/systemd/man/systemctl.html"
          ]
        }
      end
      
      # File/permission errors
      if error_message.include?("permission") || error_message.include?("access") || error_message.include?("denied")
        suggestions << {
          title: "Permission Issue",
          description: "The test failed due to permission problems. This might be due to incorrect file ownership, missing sudo privileges, or SELinux/AppArmor restrictions.",
          commands: [
            "ls -la /path/to/file  # Check file permissions",
            "sudo chown user:group /path/to/file  # Fix ownership",
            "sudo chmod 644 /path/to/file  # Fix permissions",
            "whoami  # Check current user"
          ],
          references: [
            "File permissions: https://wiki.archlinux.org/title/File_permissions_and_attributes"
          ]
        }
      end
      
      # Configuration errors
      if error_message.include?("config") || error_message.include?("syntax") || error_message.include?("invalid")
        suggestions << {
          title: "Configuration Error",
          description: "The test failed due to configuration issues. This could be syntax errors, missing configuration sections, or invalid values.",
          commands: [
            "# Check configuration file syntax",
            "# Validate configuration against schema",
            "# Compare with working configuration",
            "# Check for typos or missing sections"
          ],
          references: [
            "Configuration validation tools for your specific service"
          ]
        }
      end
      
      # Network-related errors
      if error_message.include?("network") || error_message.include?("connection") || error_message.include?("timeout")
        suggestions << {
          title: "Network Connectivity Issue",
          description: "The test failed due to network problems. This could be DNS resolution, firewall rules, or service availability.",
          commands: [
            "ping -c 3 8.8.8.8  # Test internet connectivity",
            "nslookup domain.com  # Test DNS resolution",
            "curl -I https://domain.com  # Test HTTP connectivity",
            "netstat -tlnp  # Check listening ports"
          ],
          references: [
            "Network troubleshooting: https://wiki.archlinux.org/title/Network_configuration"
          ]
        }
      end
      
      # If no specific suggestions, provide general debugging advice
      if suggestions.empty?
        suggestions << {
          title: "General Debugging Steps",
          description: "No specific pattern detected. Try these general debugging approaches.",
          commands: [
            "# Check system logs: journalctl -xe",
            "# Verify environment: env | grep -E '(PATH|HOME|USER)'",
            "# Check disk space: df -h",
            "# Check memory: free -h",
            "# Review mitamae logs in detail"
          ],
          references: [
            "General system troubleshooting",
            "Mitamae documentation: https://github.com/itamae-kitchen/mitamae"
          ]
        }
      end
      
      suggestions
    end
  end
  
  # Extension to integrate interactive debugging with test runner
  module DebuggableTestRunner
    def self.prepended(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      def enable_interactive_debugging(enabled = true)
        @interactive_debugging_enabled = enabled
      end
      
      def interactive_debugging_enabled?
        @interactive_debugging_enabled ||= false
      end
    end
    
    def handle_test_failure(test_result, environment, artifacts = {})
      # Call original failure handling
      super if defined?(super)
      
      # Start interactive debugging if enabled
      if self.class.interactive_debugging_enabled? && 
         ENV['MITAMAE_TEST_INTERACTIVE'] != 'false' &&
         STDIN.tty? && STDOUT.tty?
        
        debugger = InteractiveDebugger.new(test_result, environment, artifacts)
        continue_execution = debugger.start_debugging
        
        # Return whether to continue with other tests
        continue_execution
      else
        false
      end
    end
  end
end