# frozen_string_literal: true

require 'securerandom'

module MitamaeTest
  module Environments
    # Service class responsible for container lifecycle management
    class ContainerLifecycleService
      include Logging
      include ErrorHandling

      SYSTEMD_READY_STATES = %w[running degraded].freeze

      def initialize(container_manager)
        @container_manager = container_manager
      end

      def setup_container(container)
        log_info "Setting up container environment: #{container.container_name}"
        
        with_retry("container setup", max_attempts: 3) do
          ensure_container_runtime_available
          pull_image_if_needed(container)
          create_container(container)
          start_container(container)
          wait_for_systemd_if_enabled(container)
          configure_container_environment(container)
          container.mark_ready!
        end
        
        log_info "Container environment ready: #{container.container_id}"
      rescue => e
        cleanup_failed_container(container)
        raise TestError, "Failed to setup container: #{e.message}"
      end

      def teardown_container(container)
        return unless container.container_id

        log_info "Tearing down container: #{container.container_name}"

        safe_execute("stop container") do
          @container_manager.stop_container(container.container_id)
        end

        safe_execute("remove container") do
          @container_manager.remove_container(container.container_id)
        end

        container.reset_container_state
        container.mark_not_ready!
      end

      private

      def ensure_container_runtime_available
        unless @container_manager.runtime_available?
          raise TestError, "Container runtime not available. Run bin/test-setup.sh to install dependencies."
        end

        @container_manager.ensure_user_service_running
      end

      def pull_image_if_needed(container)
        return unless container.options[:pull_image]

        log_info "Pulling container image: #{container.image}"
        @container_manager.pull_image(container.image)
      end

      def create_container(container)
        log_debug "Creating container: #{container.container_name}"
        
        container_config = build_container_config(container)
        container_id = @container_manager.create_container(container_config)
        container.set_container_id(container_id)
        
        raise TestError, "Failed to create container" if container_id.empty?
      end

      def build_container_config(container)
        {
          name: container.container_name,
          image: container.image,
          hostname: container.container_name,
          systemd_enabled: container.systemd_enabled?,
          volumes: container.volume_specs,
          ports: container.port_specs,
          environment_vars: container.environment_variables,
          command: determine_container_command(container)
        }
      end

      def determine_container_command(container)
        container.systemd_enabled? ? ['/sbin/init'] : %w[sleep infinity]
      end

      def start_container(container)
        log_debug "Starting container: #{container.container_id}"
        @container_manager.start_container(container.container_id)
      end

      def wait_for_systemd_if_enabled(container)
        return unless container.systemd_enabled?

        log_debug "Waiting for systemd to become ready..."
        sleep 2  # Give systemd time to initialize

        with_retry("systemd readiness", max_attempts: 30, delay: 1) do
          check_systemd_readiness(container)
        end
      end

      def check_systemd_readiness(container)
        result = container.execute("systemctl is-system-running", timeout: 5)
        
        systemd_ready = result[:success] || 
                       SYSTEMD_READY_STATES.any? { |state| result[:stdout].include?(state) }
        
        raise "systemd not ready: #{result[:stdout]}" unless systemd_ready
      end

      def configure_container_environment(container)
        install_base_packages(container)
        create_test_user(container)
      end

      def install_base_packages(container)
        case container.distribution
        when 'arch'
          container.execute("pacman -Sy --noconfirm base-devel git curl wget", timeout: 300)
        when 'fedora'
          container.execute("dnf install -y @development-tools git curl wget", timeout: 300)
        when 'ubuntu', 'debian'
          container.execute("apt-get update && apt-get install -y build-essential git curl wget", timeout: 300)
        end
      end

      def create_test_user(container)
        container.execute("useradd -m -s /bin/bash mitamae || true")
        container.execute("echo 'mitamae ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/mitamae")
      end

      def cleanup_failed_container(container)
        return unless container.container_id

        system("podman rm -f #{container.container_id} 2>/dev/null")
        container.reset_container_state
      end
    end
  end
end