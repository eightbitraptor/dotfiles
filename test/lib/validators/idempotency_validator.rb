module MitamaeTest
  module Validators
    class IdempotencyValidator < Base
      plugin_name :idempotency
      plugin_type :validator
      
      def validate(environment, context = {})
        clear_results
        
        recipe_path = context[:recipe_path]
        mitamae_options = context[:mitamae_options] || {}
        node_json = context[:node_json] || {}
        
        unless recipe_path
          add_error("No recipe path provided for idempotency validation")
          return self
        end
        
        log_info "Validating idempotency for recipe: #{recipe_path}"
        
        # First run - apply the recipe
        first_run = run_mitamae(environment, recipe_path, mitamae_options, node_json, "first run")
        unless first_run[:success]
          add_error("First mitamae run failed", 
                   details: { exit_code: first_run[:exit_code], 
                            stderr: first_run[:stderr] })
          return self
        end
        
        # Capture state after first run
        first_state = capture_system_state(environment, context)
        
        # Second run - should be idempotent
        second_run = run_mitamae(environment, recipe_path, mitamae_options, node_json, "second run")
        unless second_run[:success]
          add_error("Second mitamae run failed",
                   details: { exit_code: second_run[:exit_code],
                            stderr: second_run[:stderr] })
          return self
        end
        
        # Check for changes in second run
        if second_run[:changes_made]
          add_error("Recipe is not idempotent - changes detected on second run",
                   details: { changes: parse_mitamae_changes(second_run[:output]) })
        end
        
        # Capture state after second run
        second_state = capture_system_state(environment, context)
        
        # Compare states
        state_differences = compare_states(first_state, second_state)
        if state_differences.any?
          add_error("System state changed during idempotent run",
                   details: { differences: state_differences })
        end
        
        # Third run with dry-run to detect potential changes
        dry_run = run_mitamae(environment, recipe_path, 
                             mitamae_options.merge(dry_run: true), 
                             node_json, "dry run check")
        
        if dry_run[:changes_detected]
          add_warning("Dry run detected potential changes after convergence",
                     details: { potential_changes: parse_mitamae_changes(dry_run[:output]) })
        end
        
        log_info "Idempotency validation complete: #{success? ? 'PASSED' : 'FAILED'}"
        self
      end
      
      private
      
      def run_mitamae(environment, recipe_path, options, node_json, run_description)
        log_debug "Executing mitamae #{run_description}"
        
        # Build mitamae command
        cmd_parts = ["mitamae", "local"]
        
        # Add options
        cmd_parts << "--dry-run" if options[:dry_run]
        cmd_parts << "--log-level=#{options[:log_level] || 'info'}"
        cmd_parts << "--color=false"
        
        # Add node JSON if provided
        if node_json && !node_json.empty?
          node_file = "/tmp/node_#{Time.now.to_i}.json"
          environment.write_file(node_file, node_json.to_json)
          cmd_parts << "--node-json=#{node_file}"
        end
        
        cmd_parts << recipe_path
        
        command = cmd_parts.join(" ")
        result = execute_command(environment, command, timeout: 300)
        
        output = result.stdout + result.stderr
        
        {
          success: result.success?,
          exit_code: result.exit_code,
          output: output,
          stdout: result.stdout,
          stderr: result.stderr,
          changes_made: detect_changes_in_output(output),
          changes_detected: detect_dryrun_changes(output)
        }
      end
      
      def detect_changes_in_output(output)
        # Detect actual changes in mitamae output
        change_indicators = [
          /\[INFO\].*created$/,
          /\[INFO\].*updated$/,
          /\[INFO\].*changed$/,
          /\[INFO\].*deleted$/,
          /\[INFO\].*modified$/,
          /diff:/,
          /^\+[^+]/,  # Added lines in diff
          /^-[^-]/    # Removed lines in diff
        ]
        
        change_indicators.any? { |pattern| output.match?(pattern) }
      end
      
      def detect_dryrun_changes(output)
        # Detect potential changes in dry-run output
        dryrun_indicators = [
          /\(dry-run\)/,
          /would create/,
          /would update/,
          /would change/,
          /would delete/
        ]
        
        dryrun_indicators.any? { |pattern| output.match?(pattern) }
      end
      
      def parse_mitamae_changes(output)
        changes = []
        
        output.each_line do |line|
          # Extract resource changes
          if line =~ /\[INFO\].*?(\w+)\[([^\]]+)\].*?(created|updated|changed|deleted|modified)/
            changes << {
              resource_type: $1,
              resource_name: $2,
              action: $3
            }
          end
        end
        
        changes
      end
      
      def capture_system_state(environment, context)
        state = {}
        
        # Capture package state
        if context[:check_packages]
          state[:packages] = capture_package_state(environment)
        end
        
        # Capture service state
        if context[:check_services]
          state[:services] = capture_service_state(environment)
        end
        
        # Capture file state
        if context[:check_files]
          files = Array(context[:check_files])
          state[:files] = capture_file_state(environment, files)
        end
        
        # Capture process state
        if context[:check_processes]
          state[:processes] = capture_process_state(environment)
        end
        
        state
      end
      
      def capture_package_state(environment)
        # Try different package managers
        managers = {
          apt: "dpkg -l | grep '^ii' | awk '{print $2\":\"$3}'",
          yum: "rpm -qa --queryformat '%{NAME}:%{VERSION}-%{RELEASE}\n'",
          pacman: "pacman -Q | sed 's/ /:/'",
          apk: "apk list --installed | sed 's/-/:/'",
        }
        
        managers.each do |manager, command|
          result = execute_command(environment, command)
          if result.success?
            return result.stdout.lines.map(&:strip).sort
          end
        end
        
        []
      end
      
      def capture_service_state(environment)
        # Try systemctl first
        result = execute_command(environment, "systemctl list-units --type=service --all --no-legend")
        if result.success?
          services = {}
          result.stdout.each_line do |line|
            parts = line.strip.split(/\s+/, 5)
            next if parts.size < 4
            
            name = parts[0].sub(/\.service$/, '')
            services[name] = {
              loaded: parts[1],
              active: parts[2],
              sub: parts[3]
            }
          end
          return services
        end
        
        # Fall back to service command
        result = execute_command(environment, "service --status-all 2>&1")
        if result.success?
          services = {}
          result.stdout.each_line do |line|
            if line =~ /\[\s*([\+\-\?])\s*\]\s+(.+)/
              status = case $1
                      when '+' then 'running'
                      when '-' then 'stopped'
                      else 'unknown'
                      end
              services[$2.strip] = { status: status }
            end
          end
          return services
        end
        
        {}
      end
      
      def capture_file_state(environment, files)
        file_states = {}
        
        files.each do |file_path|
          if environment.file_exists?(file_path)
            # Get file metadata
            stat_cmd = "stat -c '%a:%U:%G:%s:%Y' '#{file_path}' 2>/dev/null || " \
                      "stat -f '%Lp:%Su:%Sg:%z:%m' '#{file_path}'"
            result = execute_command(environment, stat_cmd)
            
            if result.success?
              parts = result.stdout.strip.split(':')
              
              # Calculate checksum
              checksum_result = execute_command(environment, "sha256sum '#{file_path}' | cut -d' ' -f1")
              checksum = checksum_result.success? ? checksum_result.stdout.strip : nil
              
              file_states[file_path] = {
                exists: true,
                mode: parts[0],
                owner: parts[1],
                group: parts[2],
                size: parts[3].to_i,
                mtime: parts[4].to_i,
                checksum: checksum
              }
            end
          else
            file_states[file_path] = { exists: false }
          end
        end
        
        file_states
      end
      
      def capture_process_state(environment)
        result = execute_command(environment, "ps aux --no-headers")
        if result.success?
          processes = result.stdout.lines.map do |line|
            parts = line.strip.split(/\s+/, 11)
            {
              user: parts[0],
              command: parts[10]
            }
          end.select { |p| p[:command] && !p[:command].include?('ps aux') }
          
          # Group by command for easier comparison
          processes.group_by { |p| p[:command].split.first }
                  .transform_values(&:count)
        else
          {}
        end
      end
      
      def compare_states(state1, state2)
        differences = []
        
        # Compare each state component
        [:packages, :services, :files, :processes].each do |component|
          next unless state1[component] && state2[component]
          
          case component
          when :packages
            added = state2[component] - state1[component]
            removed = state1[component] - state2[component]
            
            differences << { type: :packages, added: added } if added.any?
            differences << { type: :packages, removed: removed } if removed.any?
            
          when :services
            state1[component].each do |name, state|
              if state2[component][name] != state
                differences << {
                  type: :service,
                  name: name,
                  before: state,
                  after: state2[component][name]
                }
              end
            end
            
          when :files
            state1[component].each do |path, state|
              if state2[component][path] != state
                differences << {
                  type: :file,
                  path: path,
                  changes: diff_file_state(state, state2[component][path])
                }
              end
            end
            
          when :processes
            state1[component].each do |cmd, count|
              new_count = state2[component][cmd] || 0
              if new_count != count
                differences << {
                  type: :process,
                  command: cmd,
                  before: count,
                  after: new_count
                }
              end
            end
          end
        end
        
        differences
      end
      
      def diff_file_state(state1, state2)
        changes = []
        
        [:mode, :owner, :group, :size, :checksum].each do |attr|
          if state1[attr] != state2[attr]
            changes << { attribute: attr, before: state1[attr], after: state2[attr] }
          end
        end
        
        changes
      end
    end
  end
end