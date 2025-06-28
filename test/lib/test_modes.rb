require_relative 'error_handler'
require_relative 'logging'

module MitamaeTest
  # Test mode management for different execution scenarios
  class TestModes
    include Logging
    
    # Available test modes
    MODES = {
      fresh: 'Fresh installation - clean environment with no existing state',
      incremental: 'Incremental update - apply changes to existing configured state',
      idempotent: 'Idempotency check - run twice to ensure no changes on second run',
      rollback: 'Rollback test - test ability to revert changes',
      validation: 'Validation only - check current state without applying changes'
    }.freeze
    
    attr_reader :mode, :environment, :configuration
    
    def initialize(mode, environment, configuration = {})
      unless MODES.key?(mode.to_sym)
        raise TestError, "Unknown test mode: #{mode}. Available modes: #{MODES.keys.join(', ')}"
      end
      
      @mode = mode.to_sym
      @environment = environment
      @configuration = configuration
      @snapshots = {}
      
      debug "Initialized test mode: #{@mode}"
    end
    
    # Execute test in the specified mode
    def execute(test_spec)
      log_info "Executing test '#{test_spec.name}' in #{@mode} mode"
      
      case @mode
      when :fresh
        execute_fresh_mode(test_spec)
      when :incremental
        execute_incremental_mode(test_spec)
      when :idempotent
        execute_idempotent_mode(test_spec)
      when :rollback
        execute_rollback_mode(test_spec)
      when :validation
        execute_validation_mode(test_spec)
      else
        raise TestError, "Unhandled test mode: #{@mode}"
      end
    end
    
    private
    
    # Fresh installation mode - start with clean environment
    def execute_fresh_mode(test_spec)
      log_info "Starting fresh installation test"
      
      # Ensure clean environment state
      @environment.reset_to_clean_state
      
      # Take initial snapshot for comparison
      initial_state = capture_system_state('fresh_initial')
      
      # Execute the recipe
      result = execute_recipe(test_spec)
      
      # Take final snapshot
      final_state = capture_system_state('fresh_final')
      
      # Validate changes
      validate_fresh_installation(initial_state, final_state, test_spec)
      
      result
    end
    
    # Incremental update mode - apply changes to existing state
    def execute_incremental_mode(test_spec)
      log_info "Starting incremental update test"
      
      # Restore or create existing state
      if @configuration[:baseline_snapshot]
        @environment.restore_snapshot(@configuration[:baseline_snapshot])
      else
        # Run baseline setup if no snapshot provided
        setup_baseline_state(test_spec)
      end
      
      # Take pre-update snapshot
      pre_state = capture_system_state('incremental_pre')
      
      # Execute the recipe
      result = execute_recipe(test_spec)
      
      # Take post-update snapshot
      post_state = capture_system_state('incremental_post')
      
      # Validate incremental changes
      validate_incremental_update(pre_state, post_state, test_spec)
      
      result
    end
    
    # Idempotency mode - run twice to ensure no changes on second run
    def execute_idempotent_mode(test_spec)
      log_info "Starting idempotency test (double execution)"
      
      # Ensure clean environment
      @environment.reset_to_clean_state
      
      # First execution
      log_info "First execution (initial setup)"
      first_result = execute_recipe(test_spec)
      first_state = capture_system_state('idempotent_first')
      
      # Second execution
      log_info "Second execution (idempotency check)"
      second_result = execute_recipe(test_spec)
      second_state = capture_system_state('idempotent_second')
      
      # Validate idempotency
      validate_idempotency(first_state, second_state, first_result, second_result, test_spec)
      
      # Return combined result
      combine_idempotent_results(first_result, second_result)
    end
    
    # Rollback mode - test ability to revert changes
    def execute_rollback_mode(test_spec)
      log_info "Starting rollback test"
      
      # Take initial snapshot
      initial_state = capture_system_state('rollback_initial')
      
      # Execute the recipe
      log_info "Applying recipe changes"
      recipe_result = execute_recipe(test_spec)
      applied_state = capture_system_state('rollback_applied')
      
      # Attempt rollback
      log_info "Attempting rollback"
      rollback_result = execute_rollback(test_spec)
      final_state = capture_system_state('rollback_final')
      
      # Validate rollback
      validate_rollback(initial_state, applied_state, final_state, test_spec)
      
      combine_rollback_results(recipe_result, rollback_result)
    end
    
    # Validation mode - check current state without applying changes
    def execute_validation_mode(test_spec)
      log_info "Starting validation-only test"
      
      # Capture current state
      current_state = capture_system_state('validation_current')
      
      # Run validators without executing recipe
      validation_results = []
      test_spec.validators.each do |validator_config|
        validator = create_validator(validator_config)
        result = validator.validate(current_state)
        validation_results << result
      end
      
      # Combine validation results
      combine_validation_results(validation_results, test_spec)
    end
    
    # Execute mitamae recipe
    def execute_recipe(test_spec)
      log_info "Executing mitamae recipe: #{test_spec.recipe_path}"
      
      recipe_runner = RecipeRunner.new(@environment, test_spec)
      recipe_runner.execute
    end
    
    # Execute rollback (inverse of recipe)
    def execute_rollback(test_spec)
      if test_spec.rollback_recipe
        log_info "Executing rollback recipe: #{test_spec.rollback_recipe}"
        rollback_spec = test_spec.dup
        rollback_spec.recipe_path = test_spec.rollback_recipe
        execute_recipe(rollback_spec)
      else
        # Try to auto-generate rollback
        log_info "No explicit rollback recipe, attempting automatic rollback"
        auto_rollback(test_spec)
      end
    end
    
    # Capture system state snapshot
    def capture_system_state(label)
      log_debug "Capturing system state: #{label}"
      
      state = {
        timestamp: Time.now,
        label: label,
        packages: capture_package_state,
        services: capture_service_state,
        files: capture_file_state,
        users: capture_user_state,
        environment: capture_environment_state
      }
      
      @snapshots[label] = state
      state
    end
    
    def capture_package_state
      # Capture installed packages and versions
      @environment.execute('dpkg -l 2>/dev/null || rpm -qa 2>/dev/null || pacman -Q 2>/dev/null || true')
    end
    
    def capture_service_state
      # Capture service states
      @environment.execute('systemctl list-units --type=service --all 2>/dev/null || sv status /etc/service/* 2>/dev/null || true')
    end
    
    def capture_file_state
      # Capture key file checksums and permissions
      files = @configuration[:monitored_files] || []
      file_states = {}
      
      files.each do |file_path|
        if @environment.file_exists?(file_path)
          file_states[file_path] = {
            checksum: @environment.file_checksum(file_path),
            permissions: @environment.file_permissions(file_path),
            owner: @environment.file_owner(file_path)
          }
        end
      end
      
      file_states
    end
    
    def capture_user_state
      # Capture user and group information
      {
        users: @environment.execute('getent passwd'),
        groups: @environment.execute('getent group')
      }
    end
    
    def capture_environment_state
      # Capture environment variables and system info
      {
        env_vars: @environment.execute('env | sort'),
        system_info: @environment.execute('uname -a'),
        distribution: @environment.detect_distribution
      }
    end
    
    # Validation methods for different modes
    def validate_fresh_installation(initial_state, final_state, test_spec)
      log_info "Validating fresh installation changes"
      
      changes = compare_states(initial_state, final_state)
      
      # Validate expected changes occurred
      test_spec.expected_changes.each do |change_type, expectations|
        validate_expected_changes(changes, change_type, expectations)
      end
      
      # Validate no unexpected changes
      validate_no_unexpected_changes(changes, test_spec.allowed_changes || {})
    end
    
    def validate_incremental_update(pre_state, post_state, test_spec)
      log_info "Validating incremental update changes"
      
      changes = compare_states(pre_state, post_state)
      
      # Should only see incremental changes, not full reconfiguration
      validate_incremental_changes(changes, test_spec)
    end
    
    def validate_idempotency(first_state, second_state, first_result, second_result, test_spec)
      log_info "Validating idempotency (no changes on second run)"
      
      changes = compare_states(first_state, second_state)
      
      # Should be no changes between first and second execution
      if changes[:packages][:added].any? || changes[:packages][:removed].any? ||
         changes[:files][:modified].any? || changes[:services][:changed].any?
        raise ValidationError, "Idempotency violation: Changes detected on second execution"
      end
      
      # Both executions should report success
      unless first_result.success? && second_result.success?
        raise ValidationError, "Idempotency test failed: One or both executions failed"
      end
      
      log_info "Idempotency validated: No changes on second execution"
    end
    
    def validate_rollback(initial_state, applied_state, final_state, test_spec)
      log_info "Validating rollback to initial state"
      
      # Compare final state to initial state
      differences = compare_states(initial_state, final_state)
      
      # Should be minimal differences (some changes may not be fully reversible)
      validate_rollback_completeness(differences, test_spec.rollback_tolerance || {})
    end
    
    # State comparison and change detection
    def compare_states(state1, state2)
      {
        packages: compare_package_states(state1[:packages], state2[:packages]),
        services: compare_service_states(state1[:services], state2[:services]),
        files: compare_file_states(state1[:files], state2[:files]),
        users: compare_user_states(state1[:users], state2[:users])
      }
    end
    
    def compare_package_states(packages1, packages2)
      # Parse package lists and find differences
      pkgs1 = parse_package_list(packages1)
      pkgs2 = parse_package_list(packages2)
      
      {
        added: pkgs2.keys - pkgs1.keys,
        removed: pkgs1.keys - pkgs2.keys,
        updated: pkgs2.select { |name, version| pkgs1[name] && pkgs1[name] != version }.keys
      }
    end
    
    def compare_service_states(services1, services2)
      # Parse service lists and find state changes
      svcs1 = parse_service_list(services1)
      svcs2 = parse_service_list(services2)
      
      {
        started: svcs2.select { |name, state| state == 'active' && svcs1[name] != 'active' }.keys,
        stopped: svcs2.select { |name, state| state != 'active' && svcs1[name] == 'active' }.keys,
        changed: svcs2.select { |name, state| svcs1[name] && svcs1[name] != state }.keys
      }
    end
    
    def compare_file_states(files1, files2)
      all_files = (files1.keys + files2.keys).uniq
      
      {
        created: files2.keys - files1.keys,
        deleted: files1.keys - files2.keys,
        modified: all_files.select do |file|
          files1[file] && files2[file] && 
          (files1[file][:checksum] != files2[file][:checksum] ||
           files1[file][:permissions] != files2[file][:permissions])
        end
      }
    end
    
    def compare_user_states(users1, users2)
      # Parse user/group lists and find changes
      u1 = parse_user_list(users1[:users])
      u2 = parse_user_list(users2[:users])
      g1 = parse_group_list(users1[:groups])
      g2 = parse_group_list(users2[:groups])
      
      {
        users_added: u2.keys - u1.keys,
        users_removed: u1.keys - u2.keys,
        groups_added: g2.keys - g1.keys,
        groups_removed: g1.keys - g2.keys
      }
    end
    
    # Helper parsing methods
    def parse_package_list(package_output)
      packages = {}
      package_output.each_line do |line|
        # Handle different package manager formats
        if line.match(/^ii\s+(\S+)\s+(\S+)/) # dpkg
          packages[$1] = $2
        elsif line.match(/^(\S+)-([^-]+)-\d+/) # rpm
          packages[$1] = $2
        elsif line.match(/^(\S+)\s+(\S+)/) # pacman
          packages[$1] = $2
        end
      end
      packages
    end
    
    def parse_service_list(service_output)
      services = {}
      service_output.each_line do |line|
        if line.match(/^\s*(\S+)\.service\s+\S+\s+\S+\s+(\S+)/) # systemctl
          services[$1] = $2
        elsif line.match(/^(\S+):\s*(\S+)/) # sv status
          services[$1] = $2
        end
      end
      services
    end
    
    def parse_user_list(user_output)
      users = {}
      user_output.each_line do |line|
        parts = line.strip.split(':')
        users[parts[0]] = parts[2] if parts.length >= 3 # uid
      end
      users
    end
    
    def parse_group_list(group_output)
      groups = {}
      group_output.each_line do |line|
        parts = line.strip.split(':')
        groups[parts[0]] = parts[2] if parts.length >= 3 # gid
      end
      groups
    end
    
    # Result combination methods
    def combine_idempotent_results(first_result, second_result)
      TestResult.new(
        success: first_result.success? && second_result.success?,
        message: "Idempotency test: First run #{first_result.success? ? 'passed' : 'failed'}, Second run #{second_result.success? ? 'passed' : 'failed'}",
        details: {
          first_run: first_result.to_h,
          second_run: second_result.to_h,
          idempotent: first_result.success? && second_result.success?
        }
      )
    end
    
    def combine_rollback_results(recipe_result, rollback_result)
      TestResult.new(
        success: recipe_result.success? && rollback_result.success?,
        message: "Rollback test: Recipe #{recipe_result.success? ? 'applied' : 'failed'}, Rollback #{rollback_result.success? ? 'succeeded' : 'failed'}",
        details: {
          recipe_execution: recipe_result.to_h,
          rollback_execution: rollback_result.to_h,
          rollback_successful: rollback_result.success?
        }
      )
    end
    
    def combine_validation_results(validation_results, test_spec)
      success = validation_results.all?(&:success?)
      
      TestResult.new(
        success: success,
        message: "Validation test: #{validation_results.count(&:success?)}/#{validation_results.length} validators passed",
        details: {
          validations: validation_results.map(&:to_h),
          overall_success: success
        }
      )
    end
    
    # Baseline state setup for incremental mode
    def setup_baseline_state(test_spec)
      if test_spec.baseline_recipe
        log_info "Setting up baseline state with recipe: #{test_spec.baseline_recipe}"
        baseline_spec = test_spec.dup
        baseline_spec.recipe_path = test_spec.baseline_recipe
        execute_recipe(baseline_spec)
      else
        log_warn "No baseline recipe specified for incremental mode"
      end
    end
    
    # Auto-rollback attempt (limited capability)
    def auto_rollback(test_spec)
      log_info "Attempting automatic rollback"
      
      # This is a simplified rollback - in practice, this would need
      # sophisticated state tracking and reversal logic
      rollback_actions = []
      
      # Try to restore from snapshot if available
      if @snapshots['rollback_initial']
        log_info "Attempting to restore initial state"
        @environment.restore_snapshot(@snapshots['rollback_initial'])
      else
        log_warn "No initial snapshot available for automatic rollback"
      end
      
      TestResult.new(
        success: true,
        message: "Automatic rollback attempted (limited capability)",
        details: { actions: rollback_actions }
      )
    end
    
    # Additional validation helpers
    def validate_expected_changes(changes, change_type, expectations)
      case change_type
      when :packages
        validate_package_expectations(changes[:packages], expectations)
      when :services
        validate_service_expectations(changes[:services], expectations)
      when :files
        validate_file_expectations(changes[:files], expectations)
      end
    end
    
    def validate_package_expectations(package_changes, expectations)
      expectations[:should_install]&.each do |pkg|
        unless package_changes[:added].include?(pkg)
          raise ValidationError, "Expected package '#{pkg}' to be installed, but it wasn't"
        end
      end
      
      expectations[:should_remove]&.each do |pkg|
        unless package_changes[:removed].include?(pkg)
          raise ValidationError, "Expected package '#{pkg}' to be removed, but it wasn't"
        end
      end
    end
    
    def validate_service_expectations(service_changes, expectations)
      expectations[:should_start]&.each do |svc|
        unless service_changes[:started].include?(svc)
          raise ValidationError, "Expected service '#{svc}' to be started, but it wasn't"
        end
      end
      
      expectations[:should_stop]&.each do |svc|
        unless service_changes[:stopped].include?(svc)
          raise ValidationError, "Expected service '#{svc}' to be stopped, but it wasn't"
        end
      end
    end
    
    def validate_file_expectations(file_changes, expectations)
      expectations[:should_create]&.each do |file|
        unless file_changes[:created].include?(file)
          raise ValidationError, "Expected file '#{file}' to be created, but it wasn't"
        end
      end
      
      expectations[:should_modify]&.each do |file|
        unless file_changes[:modified].include?(file)
          raise ValidationError, "Expected file '#{file}' to be modified, but it wasn't"
        end
      end
    end
    
    def validate_no_unexpected_changes(changes, allowed_changes)
      # Check for unexpected package installations
      unexpected_packages = changes[:packages][:added] - (allowed_changes[:packages] || [])
      if unexpected_packages.any?
        log_warn "Unexpected packages installed: #{unexpected_packages.join(', ')}"
      end
      
      # Check for unexpected service changes
      unexpected_services = changes[:services][:changed] - (allowed_changes[:services] || [])
      if unexpected_services.any?
        log_warn "Unexpected service changes: #{unexpected_services.join(', ')}"
      end
    end
    
    def validate_incremental_changes(changes, test_spec)
      # Incremental changes should be minimal and targeted
      max_package_changes = test_spec.incremental_limits[:max_package_changes] || 10
      max_service_changes = test_spec.incremental_limits[:max_service_changes] || 5
      
      total_package_changes = changes[:packages][:added].length + 
                             changes[:packages][:removed].length + 
                             changes[:packages][:updated].length
      
      if total_package_changes > max_package_changes
        raise ValidationError, "Too many package changes for incremental update: #{total_package_changes} > #{max_package_changes}"
      end
      
      if changes[:services][:changed].length > max_service_changes
        raise ValidationError, "Too many service changes for incremental update: #{changes[:services][:changed].length} > #{max_service_changes}"
      end
    end
    
    def validate_rollback_completeness(differences, tolerance)
      # Check rollback tolerance
      max_remaining_packages = tolerance[:max_remaining_packages] || 0
      max_remaining_files = tolerance[:max_remaining_files] || 0
      
      remaining_packages = differences[:packages][:added].length
      remaining_files = differences[:files][:created].length
      
      if remaining_packages > max_remaining_packages
        log_warn "Rollback incomplete: #{remaining_packages} packages remain (tolerance: #{max_remaining_packages})"
      end
      
      if remaining_files > max_remaining_files
        log_warn "Rollback incomplete: #{remaining_files} files remain (tolerance: #{max_remaining_files})"
      end
    end
  end
  
  # Recipe runner for executing mitamae recipes
  class RecipeRunner
    include Logging
    
    def initialize(environment, test_spec)
      @environment = environment
      @test_spec = test_spec
    end
    
    def execute
      log_info "Executing recipe: #{@test_spec.recipe_path}"
      
      # Prepare mitamae command
      cmd = build_mitamae_command
      
      # Execute mitamae
      start_time = Time.now
      result = @environment.execute(cmd)
      end_time = Time.now
      
      # Parse mitamae output
      parse_mitamae_result(result, end_time - start_time)
    end
    
    private
    
    def build_mitamae_command
      cmd = ['mitamae', 'local']
      
      # Add node attributes if specified
      if @test_spec.node_attributes
        cmd << '--node-json' << write_node_json(@test_spec.node_attributes)
      end
      
      # Add data bags if specified
      if @test_spec.data_bags
        cmd << '--data-bags-path' << prepare_data_bags(@test_spec.data_bags)
      end
      
      # Add other options
      cmd << '--log-level' << (@test_spec.log_level || 'info')
      cmd << '--dry-run' if @test_spec.dry_run
      
      # Add recipe path
      cmd << @test_spec.recipe_path
      
      cmd.join(' ')
    end
    
    def write_node_json(attributes)
      json_file = '/tmp/mitamae_node.json'
      @environment.write_file(json_file, attributes.to_json)
      json_file
    end
    
    def prepare_data_bags(data_bags)
      data_bags_dir = '/tmp/mitamae_data_bags'
      @environment.execute("mkdir -p #{data_bags_dir}")
      
      data_bags.each do |bag_name, bag_data|
        bag_dir = File.join(data_bags_dir, bag_name)
        @environment.execute("mkdir -p #{bag_dir}")
        
        bag_data.each do |item_name, item_data|
          item_file = File.join(bag_dir, "#{item_name}.json")
          @environment.write_file(item_file, item_data.to_json)
        end
      end
      
      data_bags_dir
    end
    
    def parse_mitamae_result(output, duration)
      success = output.include?('INFO : Completed successfully') || 
                output.include?('mitamae run completed successfully')
      
      # Parse mitamae output for resource changes
      resources_updated = output.scan(/INFO : (\w+)\[.*?\] updated/).map(&:first)
      resources_skipped = output.scan(/INFO : (\w+)\[.*?\] skipped/).map(&:first)
      
      TestResult.new(
        success: success,
        message: success ? "Recipe executed successfully" : "Recipe execution failed",
        details: {
          duration: duration,
          output: output,
          resources_updated: resources_updated,
          resources_skipped: resources_skipped,
          mitamae_success: success
        }
      )
    end
  end
  
  # Test result wrapper
  class TestResult
    attr_reader :success, :message, :details
    
    def initialize(success:, message:, details: {})
      @success = success
      @message = message
      @details = details
    end
    
    def success?
      @success
    end
    
    def to_h
      {
        success: @success,
        message: @message,
        details: @details
      }
    end
  end
end