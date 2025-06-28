require_relative '../lib/environments/base'

module MitamaeTest
  module Environments
    class VM < Base
      VM_PREFIX = 'mitamae-test-vm'
      DEFAULT_MEMORY = '2048'
      DEFAULT_DISK_SIZE = '20G'
      DEFAULT_ARCH = 'x86_64'
      VNC_PORT_BASE = 5900
      SSH_PORT_BASE = 2222
      
      # Common cloud image URLs
      CLOUD_IMAGES = {
        'arch' => 'https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2',
        'ubuntu' => 'https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img',
        'fedora' => 'https://download.fedoraproject.org/pub/fedora/linux/releases/39/Cloud/x86_64/images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2',
        'debian' => 'https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2'
      }.freeze
      
      attr_reader :vm_name, :pid_file, :monitor_socket, :vnc_port, :ssh_port, :disk_path
      
      def initialize(name, options = {})
        super(name, options)
        @vm_name = "#{VM_PREFIX}-#{name}-#{SecureRandom.hex(8)}"
        @distribution = options[:distribution] || 'arch'
        @memory = options[:memory] || DEFAULT_MEMORY
        @disk_size = options[:disk_size] || DEFAULT_DISK_SIZE
        @arch = options[:arch] || DEFAULT_ARCH
        @graphical = options.fetch(:graphical, false)
        @vnc_port = find_free_port(VNC_PORT_BASE)
        @ssh_port = find_free_port(SSH_PORT_BASE)
        
        # File paths
        @work_dir = File.join(Dir.tmpdir, 'mitamae-test', @vm_name)
        @disk_path = File.join(@work_dir, "#{@vm_name}.qcow2")
        @pid_file = File.join(@work_dir, "#{@vm_name}.pid")
        @monitor_socket = File.join(@work_dir, "#{@vm_name}-monitor.sock")
        @cloud_init_iso = File.join(@work_dir, 'cloud-init.iso')
        
        # SSH configuration
        @ssh_key_path = File.join(@work_dir, 'id_rsa')
        @ssh_user = 'mitamae'
        @ssh_timeout = 30
        
        # VM state
        @qemu_process = nil
        @ssh_available = false
      end
      
      def setup
        log_info "Setting up VM environment: #{@vm_name}"
        
        with_retry("VM setup", max_attempts: 3) do
          ensure_qemu_available
          create_work_directory
          setup_ssh_keys
          prepare_base_image
          create_cloud_init_config
          start_vm
          wait_for_ssh
          configure_environment
          mark_ready!
        end
        
        log_info "VM environment ready: #{@vm_name} (SSH: localhost:#{@ssh_port}#{@graphical ? ", VNC: localhost:#{@vnc_port}" : ""})"
      rescue => e
        cleanup_on_failure
        raise TestError, "Failed to setup VM: #{e.message}"
      end
      
      def teardown
        return unless File.exist?(@pid_file)
        
        log_info "Shutting down VM: #{@vm_name}"
        
        # Try graceful shutdown first
        safe_execute("graceful VM shutdown") do
          execute("sudo poweroff", timeout: 30)
          sleep 5
        end
        
        # Force kill if still running
        safe_execute("force VM shutdown") do
          if File.exist?(@pid_file)
            pid = File.read(@pid_file).strip
            Process.kill('TERM', pid.to_i) if pid.match?(/^\d+$/)
            sleep 2
            Process.kill('KILL', pid.to_i) if process_exists?(pid)
          end
        end
        
        # Cleanup files
        safe_execute("cleanup VM files") do
          FileUtils.rm_rf(@work_dir) if File.exist?(@work_dir)
        end
        
        mark_not_ready!
      end
      
      def execute(command, timeout: 300, user: nil)
        raise TestError, "VM not ready" unless ready?
        
        user ||= @ssh_user
        ssh_cmd = build_ssh_command(user, command)
        
        stdout, stderr, status = Open3.capture3(*ssh_cmd, timeout: timeout)
        
        {
          exit_code: status.exitstatus,
          stdout: stdout,
          stderr: stderr,
          success: status.success?
        }
      rescue Timeout::Error
        raise TestError, "SSH command timed out after #{timeout}s: #{command}"
      end
      
      def copy_file(source, destination)
        raise TestError, "VM not ready" unless ready?
        
        scp_cmd = [
          'scp', '-o', 'StrictHostKeyChecking=no',
          '-o', 'UserKnownHostsFile=/dev/null',
          '-o', 'LogLevel=quiet',
          '-i', @ssh_key_path,
          '-P', @ssh_port.to_s,
          source, "#{@ssh_user}@localhost:#{destination}"
        ]
        
        system(*scp_cmd) or raise TestError, "Failed to copy file: #{source} -> #{destination}"
      end
      
      def copy_from_vm(source, destination)
        raise TestError, "VM not ready" unless ready?
        
        scp_cmd = [
          'scp', '-o', 'StrictHostKeyChecking=no',
          '-o', 'UserKnownHostsFile=/dev/null',
          '-o', 'LogLevel=quiet',
          '-i', @ssh_key_path,
          '-P', @ssh_port.to_s,
          "#{@ssh_user}@localhost:#{source}", destination
        ]
        
        system(*scp_cmd) or raise TestError, "Failed to copy file from VM: #{source} -> #{destination}"
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
        # Create temporary file and copy it
        temp_file = File.join(Dir.tmpdir, "mitamae-#{SecureRandom.hex(8)}")
        File.write(temp_file, content)
        
        begin
          copy_file(temp_file, path)
        ensure
          FileUtils.rm_f(temp_file)
        end
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
        result = execute("systemctl is-active #{service_name}")
        result[:success] && result[:stdout].strip == 'active'
      end
      
      def take_screenshot(filename = nil)
        return nil unless @graphical
        
        filename ||= File.join(@work_dir, "screenshot-#{Time.now.strftime('%Y%m%d-%H%M%S')}.png")
        
        # Use QEMU monitor to take screenshot
        monitor_cmd = "screendump #{filename}"
        result = send_monitor_command(monitor_cmd)
        
        File.exist?(filename) ? filename : nil
      end
      
      def health_check
        return false unless ready?
        
        # Check if VM process is running
        return false unless vm_process_running?
        
        # Check SSH connectivity
        result = execute("echo 'health check'", timeout: 10)
        result[:success]
      end
      
      def vm_ip
        # For port-forwarded setup, we connect via localhost
        'localhost'
      end
      
      def vnc_display
        @graphical ? "localhost:#{@vnc_port - VNC_PORT_BASE}" : nil
      end
      
      private
      
      def ensure_qemu_available
        qemu_cmd = qemu_system_command
        result = system("command -v #{qemu_cmd} > /dev/null 2>&1")
        raise TestError, "QEMU not available (#{qemu_cmd}). Run bin/test-setup.sh to install dependencies." unless result
        
        # Check for KVM support on Linux
        if RUBY_PLATFORM.include?('linux')
          kvm_available = File.exist?('/dev/kvm') && File.readable?('/dev/kvm')
          log_warn "KVM not available - VM will run slower" unless kvm_available
        end
      end
      
      def create_work_directory
        FileUtils.mkdir_p(@work_dir)
      end
      
      def setup_ssh_keys
        unless File.exist?(@ssh_key_path)
          system("ssh-keygen -t rsa -N '' -f #{@ssh_key_path} -q")
          raise TestError, "Failed to generate SSH key" unless File.exist?(@ssh_key_path)
        end
      end
      
      def prepare_base_image
        base_image_url = CLOUD_IMAGES[@distribution]
        raise TestError, "Unsupported distribution: #{@distribution}" unless base_image_url
        
        base_image_name = File.basename(base_image_url)
        base_image_path = File.join(@work_dir, base_image_name)
        
        # Download base image if not present
        unless File.exist?(base_image_path)
          log_info "Downloading base image for #{@distribution}..."
          system("curl -L -o #{base_image_path} #{base_image_url}")
          raise TestError, "Failed to download base image" unless File.exist?(base_image_path)
        end
        
        # Create working disk from base image
        log_debug "Creating VM disk from base image..."
        system("qemu-img create -f qcow2 -F qcow2 -b #{base_image_path} #{@disk_path} #{@disk_size}")
        raise TestError, "Failed to create VM disk" unless File.exist?(@disk_path)
      end
      
      def create_cloud_init_config
        # Create cloud-init configuration for automated setup
        public_key = File.read("#{@ssh_key_path}.pub").strip
        
        user_data = <<~YAML
          #cloud-config
          users:
            - name: #{@ssh_user}
              groups: sudo
              shell: /bin/bash
              sudo: ['ALL=(ALL) NOPASSWD:ALL']
              ssh_authorized_keys:
                - #{public_key}
          
          package_update: true
          package_upgrade: true
          
          packages:
            - curl
            - wget
            - git
            - build-essential
          
          runcmd:
            - systemctl enable ssh
            - systemctl start ssh
            - echo 'VM setup complete' > /var/log/cloud-init-complete
        YAML
        
        # Write cloud-init files
        user_data_file = File.join(@work_dir, 'user-data')
        meta_data_file = File.join(@work_dir, 'meta-data')
        
        File.write(user_data_file, user_data)
        File.write(meta_data_file, "instance-id: #{@vm_name}\nlocal-hostname: #{@vm_name}\n")
        
        # Create cloud-init ISO
        system("genisoimage -output #{@cloud_init_iso} -volid cidata -joliet -rock #{user_data_file} #{meta_data_file}")
        raise TestError, "Failed to create cloud-init ISO" unless File.exist?(@cloud_init_iso)
      end
      
      def start_vm
        log_debug "Starting VM: #{@vm_name}"
        
        qemu_cmd = build_qemu_command
        log_debug "QEMU command: #{qemu_cmd.join(' ')}"
        
        # Start QEMU process in background
        @qemu_process = Process.spawn(*qemu_cmd, 
                                      out: File.join(@work_dir, 'qemu.log'),
                                      err: File.join(@work_dir, 'qemu.log'),
                                      pgroup: true)
        
        # Write PID file
        File.write(@pid_file, @qemu_process.to_s)
        
        # Give VM time to start
        sleep 5
        
        # Check if process is still running
        unless vm_process_running?
          raise TestError, "VM failed to start - check #{File.join(@work_dir, 'qemu.log')}"
        end
      end
      
      def wait_for_ssh
        log_debug "Waiting for SSH to become available..."
        
        with_retry("SSH availability", max_attempts: 60, delay: 5) do
          test_cmd = build_ssh_command(@ssh_user, 'echo "ssh ready"')
          result = system(*test_cmd, out: '/dev/null', err: '/dev/null')
          raise "SSH not ready" unless result
        end
        
        @ssh_available = true
        log_debug "SSH is available"
      end
      
      def configure_environment
        log_debug "Configuring VM environment..."
        
        # Wait for cloud-init to complete
        execute("cloud-init status --wait", timeout: 300)
        
        # Install distribution-specific packages
        case @distribution
        when 'arch'
          execute("sudo pacman -Sy --noconfirm base-devel git curl wget", timeout: 300)
        when 'fedora'
          execute("sudo dnf install -y @development-tools git curl wget", timeout: 300)
        when 'ubuntu', 'debian'
          execute("sudo apt-get update && sudo apt-get install -y build-essential git curl wget", timeout: 300)
        end
        
        # Ensure sudo works without password
        execute("sudo -n true", timeout: 10)
      end
      
      def cleanup_on_failure
        if @qemu_process
          begin
            Process.kill('TERM', @qemu_process)
            sleep 2
            Process.kill('KILL', @qemu_process) if process_exists?(@qemu_process)
          rescue
            # Ignore errors during cleanup
          end
        end
        
        FileUtils.rm_rf(@work_dir) if File.exist?(@work_dir)
      end
      
      def build_qemu_command
        cmd = [qemu_system_command]
        
        # Basic VM configuration
        cmd += ['-name', @vm_name]
        cmd += ['-m', @memory]
        cmd += ['-smp', '2']
        
        # Enable KVM if available
        if RUBY_PLATFORM.include?('linux') && File.exist?('/dev/kvm')
          cmd += ['-enable-kvm']
        end
        
        # Storage
        cmd += ['-drive', "file=#{@disk_path},format=qcow2,if=virtio"]
        cmd += ['-drive', "file=#{@cloud_init_iso},format=raw,if=virtio"]
        
        # Network with port forwarding
        netdev = "user,id=net0,hostfwd=tcp::#{@ssh_port}-:22"
        cmd += ['-netdev', netdev]
        cmd += ['-device', 'virtio-net-pci,netdev=net0']
        
        # Graphics
        if @graphical
          cmd += ['-vnc', ":#{@vnc_port - VNC_PORT_BASE}"]
          cmd += ['-device', 'virtio-vga']
        else
          cmd += ['-nographic']
        end
        
        # Monitor socket
        cmd += ['-monitor', "unix:#{@monitor_socket},server,nowait"]
        
        # Misc options
        cmd += ['-daemonize']
        cmd += ['-pidfile', @pid_file]
        
        cmd
      end
      
      def build_ssh_command(user, command)
        [
          'ssh', '-o', 'StrictHostKeyChecking=no',
          '-o', 'UserKnownHostsFile=/dev/null',
          '-o', 'LogLevel=quiet',
          '-o', "ConnectTimeout=#{@ssh_timeout}",
          '-i', @ssh_key_path,
          '-p', @ssh_port.to_s,
          "#{user}@localhost", command
        ]
      end
      
      def send_monitor_command(command)
        return unless File.exist?(@monitor_socket)
        
        # Connect to QEMU monitor socket and send command
        begin
          socket = UNIXSocket.new(@monitor_socket)
          socket.puts(command)
          response = socket.read
          socket.close
          response
        rescue => e
          log_error "Failed to send monitor command: #{e.message}"
          nil
        end
      end
      
      def vm_process_running?
        return false unless File.exist?(@pid_file)
        
        pid = File.read(@pid_file).strip
        return false unless pid.match?(/^\d+$/)
        
        process_exists?(pid)
      end
      
      def process_exists?(pid)
        Process.kill(0, pid.to_i)
        true
      rescue Errno::ESRCH
        false
      end
      
      def find_free_port(base_port)
        (base_port..base_port + 1000).each do |port|
          begin
            server = TCPServer.new('localhost', port)
            server.close
            return port
          rescue Errno::EADDRINUSE
            next
          end
        end
        
        raise TestError, "Could not find free port starting from #{base_port}"
      end
      
      def qemu_system_command
        case @arch
        when 'x86_64'
          'qemu-system-x86_64'
        when 'aarch64'
          'qemu-system-aarch64'
        else
          raise TestError, "Unsupported architecture: #{@arch}"
        end
      end
    end
  end
end