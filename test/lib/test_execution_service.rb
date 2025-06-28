# frozen_string_literal: true

module MitamaeTest
  # Service class responsible for executing individual test specifications
  class TestExecutionService
    include Logging
    include ErrorHandling

    def initialize(environment_manager, reporter)
      @environment_manager = environment_manager
      @reporter = reporter
    end

    def execute_test(test_spec)
      log_info "Running test: #{test_spec.name}"
      @reporter.start_test(test_spec)

      result = TestResult.new(test_spec)
      result.start

      begin
        return skip_test(test_spec, result) if test_spec.skipped?

        environment = setup_test_environment(test_spec)
        result.environment = environment

        run_test_sequence(test_spec, environment, result)
      rescue StandardError => e
        handle_test_error(test_spec, result, e)
      ensure
        cleanup_test(test_spec, result)
      end

      result
    end

    private

    def skip_test(test_spec, result)
      result.skip(test_spec.skip_message)
      @reporter.test_skipped(test_spec, test_spec.skip_message)
      result
    end

    def setup_test_environment(test_spec)
      @environment_manager.create(
        test_spec.name,
        type: test_spec.environment.type,
        distribution: test_spec.environment.distribution,
        options: test_spec.environment.options
      )
    end

    def run_test_sequence(test_spec, environment, result)
      run_setup_commands(environment, test_spec.setup) unless test_spec.setup.empty?
      execute_recipe(environment, test_spec.recipe)
      
      validator_results = run_validators(environment, test_spec)
      result.validation_results = validator_results

      if validator_results.all?(&:success?)
        result.pass
        @reporter.test_passed(test_spec, validator_results)
      else
        result.fail("Validation failed")
        @reporter.test_failed(test_spec, validator_results)
      end
    end

    def handle_test_error(test_spec, result, error)
      result.error(error)
      @reporter.test_failed(test_spec, [])
      log_error "Test #{test_spec.name} failed with error: #{error.message}"
    end

    def cleanup_test(test_spec, result)
      environment = result.environment
      
      if environment
        run_cleanup_commands(environment, test_spec.cleanup) if should_run_cleanup?(test_spec, result)
        teardown_environment(environment)
      end

      result.finish
      @reporter.finish_test(test_spec)
    end

    def should_run_cleanup?(test_spec, result)
      test_spec.cleanup.always || result.success
    end

    def run_setup_commands(environment, setup_config)
      log_debug "Running setup commands"

      setup_config.packages.each { |package| install_package(environment, package) }
      copy_setup_files(environment, setup_config.files)
      execute_setup_commands(environment, setup_config.commands)
    end

    def copy_setup_files(environment, files)
      files.each do |file_spec|
        environment.copy_file(file_spec['source'], file_spec['destination'])
      end
    end

    def execute_setup_commands(environment, commands)
      commands.each do |command|
        result = environment.execute(command)
        unless result[:exit_code] == 0
          raise TestError.new("Setup command failed: #{command}",
                             details: { output: result[:stderr] })
        end
      end
    end

    def execute_recipe(environment, recipe_config)
      log_debug "Executing recipe: #{recipe_config.path}"

      set_recipe_environment(environment, recipe_config.environment)
      node_file = create_node_json_file(environment, recipe_config.node_json)
      run_mitamae(environment, recipe_config.path, node_file)
    end

    def set_recipe_environment(environment, env_vars)
      env_vars.each do |key, value|
        environment.execute("export #{key}='#{value}'")
      end
    end

    def create_node_json_file(environment, node_json)
      node_file = "/tmp/node_#{Time.now.to_i}.json"
      environment.write_file(node_file, node_json.to_json)
      node_file
    end

    def run_mitamae(environment, recipe_path, node_file)
      mitamae_cmd = "mitamae local --node-json=#{node_file} #{recipe_path}"
      result = environment.execute(mitamae_cmd, timeout: 600)

      unless result[:exit_code] == 0
        raise TestError.new("Recipe execution failed",
                           details: { 
                             command: mitamae_cmd,
                             stdout: result[:stdout],
                             stderr: result[:stderr]
                           })
      end
    end

    def run_validators(environment, test_spec)
      validator_results = []

      test_spec.validators.each do |validator_config|
        validator = create_validator(validator_config)
        
        log_debug "Running validator: #{validator_config.type}"
        
        context = build_validator_context(test_spec, validator_config)
        validator.validate(environment, context)
        validator_results << validator

        break if validator_failed_and_should_stop?(validator, test_spec)
      end

      validator_results
    end

    def build_validator_context(test_spec, validator_config)
      {
        test_spec: test_spec,
        config: validator_config.config
      }.merge(validator_config.config)
    end

    def validator_failed_and_should_stop?(validator, test_spec)
      !validator.success? && !test_spec.options.continue_on_error
    end

    def create_validator(validator_config)
      plugin_manager = PluginManager.instance
      plugin_manager.create_instance(:validator, validator_config.type)
    rescue PluginError => e
      fallback_to_custom_validator(validator_config, plugin_manager)
    end

    def fallback_to_custom_validator(validator_config, plugin_manager)
      if validator_config.type == 'custom' && validator_config.name
        plugin_manager.create_instance(:validator, validator_config.name)
      else
        raise
      end
    end

    def run_cleanup_commands(environment, cleanup_config)
      log_debug "Running cleanup commands"

      cleanup_config.commands.each do |command|
        begin
          environment.execute(command)
        rescue StandardError => e
          log_warn "Cleanup command failed: #{command} - #{e.message}"
        end
      end
    end

    def teardown_environment(environment)
      @environment_manager.destroy(environment)
    rescue StandardError => e
      log_warn "Failed to teardown environment: #{e.message}"
    end

    def install_package(environment, package)
      case environment.distribution
      when 'arch'
        environment.execute("pacman -S --noconfirm #{package}")
      when 'ubuntu', 'debian'
        environment.execute("apt-get install -y #{package}")
      when 'fedora'
        environment.execute("dnf install -y #{package}")
      else
        log_warn "Unknown distribution for package installation: #{environment.distribution}"
      end
    end
  end
end