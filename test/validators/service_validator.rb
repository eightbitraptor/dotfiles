require_relative '../lib/validators/base'

module MitamaeTest
  module Validators
    class ServiceValidator < Base
      plugin_name 'service'

      SERVICE_MANAGERS = {
        'systemd' => %w[systemctl],
        'runit' => %w[sv runsv]
      }.freeze

      def validate(environment, context = {})
        clear_results
        
        services = context[:services] || []
        user_groups = context[:user_groups] || []
        
        if services.empty? && user_groups.empty?
          return add_error("No services or user groups specified for validation")
        end

        service_manager = detect_service_manager(environment)
        
        services.each do |service_spec|
          validate_service(environment, service_spec, service_manager)
        end
        
        user_groups.each do |group_spec|
          validate_user_group(environment, group_spec)
        end
      end

      private

      def detect_service_manager(environment)
        # Check for systemd first (most common)
        if execute_command(environment, "which systemctl").success?
          return 'systemd'
        end
        
        # Check for runit
        if execute_command(environment, "which sv").success? || 
           environment.file_exists?('/etc/runit')
          return 'runit'
        end
        
        'unknown'
      end

      def validate_service(environment, service_spec, service_manager)
        service_name = extract_service_name(service_spec)
        expected_state = extract_service_state(service_spec)
        
        case service_manager
        when 'systemd'
          validate_systemd_service(environment, service_name, expected_state)
        when 'runit'
          validate_runit_service(environment, service_name, expected_state)
        else
          add_error("Unknown service manager: #{service_manager}")
        end
      end

      def extract_service_name(service_spec)
        case service_spec
        when String
          service_spec
        when Hash
          service_spec[:name] || service_spec['name']
        else
          service_spec.to_s
        end
      end

      def extract_service_state(service_spec)
        case service_spec
        when Hash
          state = service_spec[:state] || service_spec['state']
          return state.to_sym if state
        end
        
        # Default to enabled/running
        :enabled
      end

      def validate_systemd_service(environment, service_name, expected_state)
        # Check if service exists
        result = execute_command(environment, "systemctl cat #{service_name}")
        unless result.success?
          return add_error("Service #{service_name} does not exist", 
                          { service: service_name, manager: 'systemd' })
        end

        case expected_state
        when :enabled, :running, :active
          validate_systemd_enabled_service(environment, service_name)
        when :disabled, :stopped, :inactive
          validate_systemd_disabled_service(environment, service_name)
        when :masked
          validate_systemd_masked_service(environment, service_name)
        else
          add_error("Unknown service state: #{expected_state}")
        end
      end

      def validate_systemd_enabled_service(environment, service_name)
        # Check if service is enabled
        enabled_result = execute_command(environment, "systemctl is-enabled #{service_name}")
        unless enabled_result.success? && enabled_result.stdout.strip == 'enabled'
          add_error("Service #{service_name} is not enabled", 
                   { service: service_name, manager: 'systemd', expected: 'enabled' })
        end

        # Check if service is active/running
        active_result = execute_command(environment, "systemctl is-active #{service_name}")
        unless active_result.success? && active_result.stdout.strip == 'active'
          add_error("Service #{service_name} is not active", 
                   { service: service_name, manager: 'systemd', expected: 'active' })
        end

        if enabled_result.success? && active_result.success?
          log_info "Service #{service_name} is enabled and active"
        end
      end

      def validate_systemd_disabled_service(environment, service_name)
        # Check if service is disabled
        enabled_result = execute_command(environment, "systemctl is-enabled #{service_name}")
        if enabled_result.success? && enabled_result.stdout.strip == 'enabled'
          add_error("Service #{service_name} should be disabled but is enabled", 
                   { service: service_name, manager: 'systemd', expected: 'disabled' })
        end

        # Check if service is inactive
        active_result = execute_command(environment, "systemctl is-active #{service_name}")
        if active_result.success? && active_result.stdout.strip == 'active'
          add_error("Service #{service_name} should be inactive but is active", 
                   { service: service_name, manager: 'systemd', expected: 'inactive' })
        end

        log_info "Service #{service_name} is properly disabled/inactive"
      end

      def validate_systemd_masked_service(environment, service_name)
        result = execute_command(environment, "systemctl is-enabled #{service_name}")
        
        if result.stdout.strip == 'masked'
          log_info "Service #{service_name} is masked"
        else
          add_error("Service #{service_name} should be masked but is not", 
                   { service: service_name, manager: 'systemd', expected: 'masked' })
        end
      end

      def validate_runit_service(environment, service_name, expected_state)
        service_dir = "/etc/sv/#{service_name}"
        service_link = "/var/service/#{service_name}"
        
        # Check if service directory exists
        unless environment.file_exists?(service_dir)
          return add_error("Runit service #{service_name} directory does not exist", 
                          { service: service_name, manager: 'runit', path: service_dir })
        end

        case expected_state
        when :enabled, :running, :active
          validate_runit_enabled_service(environment, service_name, service_link)
        when :disabled, :stopped, :inactive
          validate_runit_disabled_service(environment, service_name, service_link)
        else
          add_error("Unknown runit service state: #{expected_state}")
        end
      end

      def validate_runit_enabled_service(environment, service_name, service_link)
        # Check if service is linked (enabled)
        unless environment.file_exists?(service_link)
          return add_error("Runit service #{service_name} is not enabled (not linked)", 
                          { service: service_name, manager: 'runit', expected: 'enabled' })
        end

        # Check if service is running
        result = execute_command(environment, "sv status #{service_name}")
        
        if result.success? && result.stdout.include?('run:')
          log_info "Runit service #{service_name} is enabled and running"
        else
          add_error("Runit service #{service_name} is not running", 
                   { service: service_name, manager: 'runit', expected: 'running' })
        end
      end

      def validate_runit_disabled_service(environment, service_name, service_link)
        # Check if service is not linked (disabled)
        if environment.file_exists?(service_link)
          add_error("Runit service #{service_name} should be disabled but is linked", 
                   { service: service_name, manager: 'runit', expected: 'disabled' })
        else
          log_info "Runit service #{service_name} is properly disabled"
        end
      end

      def validate_user_group(environment, group_spec)
        group_name = extract_group_name(group_spec)
        users = extract_group_users(group_spec)
        
        # Check if group exists
        result = execute_command(environment, "getent group #{group_name}")
        
        unless result.success?
          return add_error("Group #{group_name} does not exist", 
                          { group: group_name, type: 'group' })
        end

        group_info = result.stdout.strip
        existing_users = extract_users_from_group_info(group_info)
        
        # Validate users in group
        if users && !users.empty?
          users.each do |username|
            validate_user_in_group(environment, username, group_name, existing_users)
          end
        end

        log_info "Group #{group_name} exists with users: #{existing_users.join(', ')}"
      end

      def extract_group_name(group_spec)
        case group_spec
        when String
          group_spec
        when Hash
          group_spec[:name] || group_spec['name']
        else
          group_spec.to_s
        end
      end

      def extract_group_users(group_spec)
        case group_spec
        when Hash
          users = group_spec[:users] || group_spec['users']
          return Array(users) if users
        end
        
        []
      end

      def extract_users_from_group_info(group_info)
        # Parse group info: groupname:x:gid:user1,user2,user3
        parts = group_info.split(':')
        return [] if parts.length < 4
        
        users_part = parts[3]
        return [] if users_part.empty?
        
        users_part.split(',').map(&:strip)
      end

      def validate_user_in_group(environment, username, group_name, existing_users)
        if existing_users.include?(username)
          log_info "User #{username} is in group #{group_name}"
        else
          add_error("User #{username} is not in group #{group_name}", 
                   { user: username, group: group_name, existing_users: existing_users })
        end
      end
    end
  end
end