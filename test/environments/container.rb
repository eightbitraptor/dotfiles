require_relative '../lib/environments/base'
require_relative '../lib/environments/container_lifecycle_service'
require_relative '../lib/environments/podman_manager'

module MitamaeTest
  module Environments
    class Container < Base
      DEFAULT_IMAGE = 'registry.fedoraproject.org/fedora:latest'
      CONTAINER_PREFIX = 'mitamae-test'
      
      attr_reader :container_id, :image, :distribution, :container_name
      
      def initialize(name, options = {})
        super(name, options)
        @image = options[:image] || DEFAULT_IMAGE
        @distribution = options[:distribution] || 'fedora'
        @container_id = nil
        @volumes = []
        @ports = []
        @environment_vars = {}
        @systemd_enabled = options.fetch(:systemd, true)
        @container_name = "#{CONTAINER_PREFIX}-#{name}-#{SecureRandom.hex(8)}"
        
        @podman_manager = PodmanManager.new
        @lifecycle_service = ContainerLifecycleService.new(@podman_manager)
      end
      
      def setup
        @lifecycle_service.setup_container(self)
      end
      
      def teardown
        @lifecycle_service.teardown_container(self)
      end
      
      def execute(command, timeout: 300, user: 'root')
        raise TestError, "Container not ready" unless ready?
        @podman_manager.execute_in_container(@container_id, command, user: user, timeout: timeout)
      end
      
      def copy_file(source, destination)
        raise TestError, "Container not ready" unless ready?
        @podman_manager.copy_to_container(@container_id, source, destination)
      end
      
      def copy_from_container(source, destination)
        raise TestError, "Container not ready" unless ready?
        @podman_manager.copy_from_container(@container_id, source, destination)
      end
      
      def file_exists?(path)
        result = execute("test -f '#{path}'")
        result[:success]
      end
      
      def read_file(path)
        result = execute("cat '#{path}'")
        raise TestError, "Failed to read file #{path}: #{result[:stderr]}" unless result[:success]
        result[:stdout]
      end
      
      def write_file(path, content)
        # Use heredoc to handle special characters safely
        escaped_content = content.gsub("'", "'\"'\"'")
        result = execute("cat > '#{path}' << 'MITAMAE_EOF'\n#{escaped_content}\nMITAMAE_EOF")
        raise TestError, "Failed to write file #{path}: #{result[:stderr]}" unless result[:success]
      end
      
      def package_installed?(package_name)
        case @distribution
        when 'arch'
          result = execute("pacman -Q #{package_name}")
        when 'fedora'
          result = execute("rpm -q #{package_name}")
        when 'ubuntu', 'debian'
          result = execute("dpkg -l #{package_name}")
        else
          raise TestError, "Package check not implemented for #{@distribution}"
        end
        
        result[:success]
      end
      
      def service_running?(service_name)
        return false unless @systemd_enabled
        
        result = execute("systemctl is-active #{service_name}")
        result[:success] && result[:stdout].strip == 'active'
      end
      
      def add_volume(host_path, container_path, options = {})
        mount_opts = options[:readonly] ? 'ro' : 'rw'
        volume_spec = "#{File.expand_path(host_path)}:#{container_path}:#{mount_opts}"
        @volumes << volume_spec
      end
      
      def add_port(host_port, container_port = nil)
        container_port ||= host_port
        @ports << "#{host_port}:#{container_port}"
      end
      
      def set_environment(key, value)
        @environment_vars[key] = value
      end
      
      def container_ip
        return nil unless @container_id
        @podman_manager.inspect_container(@container_id, '{{.NetworkSettings.IPAddress}}')
      end
      
      def health_check
        return false unless ready?
        
        ping_result = execute("echo 'health check'", timeout: 10)
        return false unless ping_result[:success]
        
        return true unless @systemd_enabled
        
        systemd_result = execute("systemctl is-system-running", timeout: 10)
        systemd_result[:success] || 
          systemd_result[:stdout].include?('running') ||
          systemd_result[:stdout].include?('degraded')
      end

      # Methods for service classes to access internal state
      def systemd_enabled?
        @systemd_enabled
      end

      def volume_specs
        @volumes
      end

      def port_specs
        @ports
      end

      def environment_variables
        @environment_vars
      end

      def set_container_id(container_id)
        @container_id = container_id
      end

      def reset_container_state
        @container_id = nil
      end
      
      # No private methods needed - functionality moved to service classes
    end
  end
end