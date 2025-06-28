# frozen_string_literal: true

require 'open3'
require 'timeout'

module MitamaeTest
  module Environments
    # Service class responsible for Podman container operations
    class PodmanManager
      include Logging

      SYSTEMD_OPTS = %w[
        --systemd=true
        --tmpfs=/tmp
        --tmpfs=/run
        --tmpfs=/run/lock
        --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro
        --cap-add=SYS_ADMIN
      ].freeze

      def runtime_available?
        system('command -v podman > /dev/null 2>&1')
      end

      def ensure_user_service_running
        return if ENV['USER'] == 'root'

        unless system('systemctl --user is-active podman.socket > /dev/null 2>&1')
          log_warn "Podman socket not running. Starting user service..."
          system('systemctl --user start podman.socket')
        end
      end

      def pull_image(image_name)
        run_podman_command(%w[pull], image_name)
      end

      def create_container(config)
        cmd_args = build_create_command(config)
        result = run_podman_command(cmd_args)
        result[:stdout].strip
      end

      def start_container(container_id)
        run_podman_command(%w[start], container_id)
      end

      def stop_container(container_id)
        run_podman_command(%w[stop], container_id)
      end

      def remove_container(container_id)
        run_podman_command(%w[rm -f], container_id)
      end

      def execute_in_container(container_id, command, user: 'root', timeout: 300)
        cmd_args = %w[exec]
        cmd_args << "--user=#{user}" if user
        cmd_args += [container_id, 'bash', '-c', command]

        result = run_podman_command(cmd_args, timeout: timeout)
        
        {
          exit_code: result[:exit_code],
          stdout: result[:stdout],
          stderr: result[:stderr],
          success: result[:exit_code] == 0
        }
      end

      def copy_to_container(container_id, source, destination)
        run_podman_command(%w[cp], source, "#{container_id}:#{destination}")
      end

      def copy_from_container(container_id, source, destination)
        run_podman_command(%w[cp], "#{container_id}:#{source}", destination)
      end

      def inspect_container(container_id, format = nil)
        cmd_args = %w[inspect]
        cmd_args += ["--format=#{format}"] if format
        cmd_args << container_id

        result = run_podman_command(cmd_args)
        result[:stdout].strip if result[:success]
      end

      private

      def build_create_command(config)
        cmd_args = %w[create]
        cmd_args << "--name=#{config[:name]}"
        cmd_args << "--hostname=#{config[:hostname]}"

        add_systemd_options(cmd_args) if config[:systemd_enabled]
        add_volumes(cmd_args, config[:volumes])
        add_ports(cmd_args, config[:ports])
        add_environment_variables(cmd_args, config[:environment_vars])
        
        cmd_args << config[:image]
        cmd_args.concat(config[:command])
        
        cmd_args
      end

      def add_systemd_options(cmd_args)
        cmd_args.concat(SYSTEMD_OPTS)
      end

      def add_volumes(cmd_args, volumes)
        volumes.each { |volume| cmd_args += %W[--volume #{volume}] }
      end

      def add_ports(cmd_args, ports)
        ports.each { |port| cmd_args += %W[--publish #{port}] }
      end

      def add_environment_variables(cmd_args, env_vars)
        env_vars.each { |key, value| cmd_args += %W[--env #{key}=#{value}] }
      end

      def run_podman_command(args, timeout: 300)
        cmd = ['podman'] + args.flatten.map(&:to_s)
        log_debug "Running: #{cmd.join(' ')}"

        stdout, stderr, status = Open3.capture3(*cmd, timeout: timeout)

        result = {
          exit_code: status.exitstatus,
          stdout: stdout,
          stderr: stderr,
          success: status.success?
        }

        log_command_failure(cmd, stderr) unless result[:success]
        result
      rescue Timeout::Error
        raise TestError, "Podman command timed out after #{timeout}s: #{cmd.join(' ')}"
      end

      def log_command_failure(cmd, stderr)
        log_error "Podman command failed: #{cmd.join(' ')}"
        log_error "STDERR: #{stderr}" unless stderr.empty?
      end
    end
  end
end