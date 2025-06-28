require_relative '../lib/validators/base'

module MitamaeTest
  module Validators
    class HeadlessDisplayValidator < Base
      plugin_name 'headless_display'
      plugin_type :validator
      
      HEADLESS_BACKENDS = {
        'wlroots' => {
          env_var: 'WLR_BACKENDS',
          value: 'headless',
          package: 'wlroots'
        },
        'xvfb' => {
          command: 'Xvfb',
          package: 'xvfb',
          display: ':99'
        },
        'weston' => {
          command: 'weston',
          args: '--backend=headless-backend.so',
          package: 'weston'
        },
        'cage' => {
          command: 'cage',
          args: '-d',
          package: 'cage'
        }
      }.freeze
      
      def initialize(options = {})
        super('headless_display', options)
        @backend = options[:backend] || 'wlroots'
        @display = options[:display] || 'wayland-1'
        @resolution = options[:resolution] || '1920x1080'
        @depth = options[:depth] || 24
      end
      
      def validate(environment, context = {})
        clear_results
        log_info "Starting headless display validation"
        
        validate_container_requirements(environment) if environment.containerized?
        validate_backend_installation(environment)
        validate_display_server(environment)
        validate_virtual_outputs(environment)
        validate_input_injection(environment)
        
        log_info "Headless display validation completed: #{success? ? 'SUCCESS' : 'FAILED'}"
        success?
      end
      
      def setup_headless_display(environment)
        log_info "Setting up headless display with #{@backend}"
        
        case @backend
        when 'wlroots'
          setup_wlroots_headless(environment)
        when 'xvfb'
          setup_xvfb(environment)
        when 'weston'
          setup_weston_headless(environment)
        when 'cage'
          setup_cage_headless(environment)
        else
          add_error("Unknown headless backend: #{@backend}")
          false
        end
      end
      
      private
      
      def validate_container_requirements(environment)
        log_debug "Validating container requirements for headless display"
        
        # Check for /dev/dri access (for Mesa)
        result = execute_command(environment, "test -d /dev/dri && echo 'exists'")
        if result.stdout.strip != 'exists'
          add_warning("/dev/dri not available - software rendering only")
          
          # Check for software rendering support
          validate_software_rendering(environment)
        else
          # Check for render nodes
          result = execute_command(environment, "ls /dev/dri/")
          if result.success?
            devices = result.stdout.strip.split("\n")
            log_debug "Available DRI devices: #{devices.join(', ')}"
          end
        end
        
        # Check for required capabilities
        check_container_capabilities(environment)
        
        # Validate cgroups for GPU access
        check_cgroup_devices(environment)
      end
      
      def validate_software_rendering(environment)
        # Check for llvmpipe/swrast
        result = execute_command(environment, "glxinfo -B 2>/dev/null | grep -i 'renderer\\|llvmpipe\\|swrast'")
        if result.success? && !result.stdout.empty?
          log_debug "Software rendering available: #{result.stdout.strip}"
        else
          # Check if mesa is installed
          result = execute_command(environment, "ldconfig -p | grep -i 'libGL.so\\|libEGL.so'")
          if result.exit_code != 0
            add_error("No OpenGL libraries found for software rendering")
          end
        end
        
        # Set environment for software rendering
        execute_command(environment, "export LIBGL_ALWAYS_SOFTWARE=1")
        execute_command(environment, "export GALLIUM_DRIVER=llvmpipe")
      end
      
      def check_container_capabilities(environment)
        # Check for SYS_ADMIN capability (needed for some operations)
        result = execute_command(environment, "capsh --print 2>/dev/null | grep -i sys_admin")
        if result.exit_code != 0
          log_debug "SYS_ADMIN capability not available"
        end
        
        # Check user namespace
        result = execute_command(environment, "cat /proc/self/uid_map")
        if result.success? && result.stdout.empty?
          add_warning("User namespaces might not be properly configured")
        end
      end
      
      def check_cgroup_devices(environment)
        # Check if we can access GPU devices through cgroups
        result = execute_command(environment, "cat /sys/fs/cgroup/devices/devices.list 2>/dev/null | grep -E 'c 226:\\*|c 195:\\*'")
        if result.success? && !result.stdout.empty?
          log_debug "GPU device access allowed in cgroup"
        else
          log_debug "No explicit GPU device access in cgroup"
        end
      end
      
      def validate_backend_installation(environment)
        log_debug "Validating #{@backend} backend installation"
        
        backend_info = HEADLESS_BACKENDS[@backend]
        unless backend_info
          add_error("Invalid backend: #{@backend}")
          return
        end
        
        if backend_info[:command]
          result = execute_command(environment, "which #{backend_info[:command]}")
          if result.exit_code != 0
            add_error("#{@backend} not installed", 
                     { command: backend_info[:command], 
                       package: backend_info[:package] })
          end
        end
        
        # Backend-specific validation
        case @backend
        when 'wlroots'
          validate_wlroots_installation(environment)
        when 'xvfb'
          validate_xvfb_installation(environment)
        when 'weston'
          validate_weston_installation(environment)
        end
      end
      
      def validate_wlroots_installation(environment)
        # Check for wlroots library
        result = execute_command(environment, "ldconfig -p | grep libwlroots")
        if result.exit_code != 0
          add_error("wlroots library not found")
        else
          version = extract_library_version(result.stdout)
          log_debug "wlroots version: #{version}" if version
        end
        
        # Check for headless backend support
        result = execute_command(environment, "echo $WLR_BACKENDS")
        if result.stdout.strip.empty?
          add_warning("WLR_BACKENDS not set for headless operation")
        end
      end
      
      def validate_xvfb_installation(environment)
        # Check Xvfb version
        result = execute_command(environment, "Xvfb -version 2>&1")
        if result.success? || result.stderr.include?('Xvfb')
          log_debug "Xvfb available: #{result.stderr.strip}"
        end
        
        # Check for xvfb-run wrapper
        result = execute_command(environment, "which xvfb-run")
        if result.exit_code == 0
          log_debug "xvfb-run wrapper available"
        end
      end
      
      def validate_weston_installation(environment)
        # Check Weston version
        result = execute_command(environment, "weston --version 2>&1")
        if result.success? || result.stderr.include?('weston')
          version = result.stderr.strip
          log_debug "Weston version: #{version}"
          
          # Check for headless backend
          result = execute_command(environment, "weston --help 2>&1 | grep headless")
          if result.exit_code != 0
            add_error("Weston headless backend not available")
          end
        end
      end
      
      def validate_display_server(environment)
        log_debug "Validating display server status"
        
        case @backend
        when 'wlroots', 'weston', 'cage'
          validate_wayland_display(environment)
        when 'xvfb'
          validate_x11_display(environment)
        end
      end
      
      def validate_wayland_display(environment)
        # Check WAYLAND_DISPLAY
        result = execute_command(environment, "echo $WAYLAND_DISPLAY")
        display = result.stdout.strip
        
        if display.empty?
          add_warning("WAYLAND_DISPLAY not set")
          display = @display
        end
        
        # Check for socket
        runtime_dir = execute_command(environment, "echo $XDG_RUNTIME_DIR").stdout.strip
        if runtime_dir.empty?
          runtime_dir = "/tmp"
        end
        
        socket_path = "#{runtime_dir}/#{display}"
        result = execute_command(environment, "test -S #{socket_path} && echo 'exists'")
        if result.stdout.strip != 'exists'
          add_warning("Wayland socket not found", 
                     { socket: socket_path, display: display })
        end
      end
      
      def validate_x11_display(environment)
        # Check DISPLAY
        result = execute_command(environment, "echo $DISPLAY")
        display = result.stdout.strip
        
        if display.empty?
          add_warning("DISPLAY not set")
          display = HEADLESS_BACKENDS['xvfb'][:display]
        end
        
        # Check if X server is running
        result = execute_command(environment, "xdpyinfo -display #{display} 2>&1 | head -1")
        if result.exit_code != 0
          add_warning("X server not accessible", 
                     { display: display, error: result.stderr })
        else
          log_debug "X server info: #{result.stdout.strip}"
        end
      end
      
      def validate_virtual_outputs(environment)
        log_debug "Validating virtual display outputs"
        
        case @backend
        when 'wlroots'
          validate_wlroots_outputs(environment)
        when 'xvfb'
          validate_xvfb_screen(environment)
        when 'weston'
          validate_weston_outputs(environment)
        end
      end
      
      def validate_wlroots_outputs(environment)
        # Use wlr-randr to check outputs
        result = execute_command(environment, "which wlr-randr")
        if result.exit_code == 0
          result = execute_command(environment, "wlr-randr")
          if result.success?
            outputs = parse_wlr_randr_output(result.stdout)
            if outputs.empty?
              add_error("No virtual outputs detected")
            else
              outputs.each do |output|
                log_debug "Virtual output: #{output[:name]} @ #{output[:mode]}"
              end
            end
          else
            add_warning("Unable to query outputs with wlr-randr")
          end
        else
          # Try to create a virtual output
          create_virtual_output(environment)
        end
      end
      
      def validate_xvfb_screen(environment)
        display = HEADLESS_BACKENDS['xvfb'][:display]
        result = execute_command(environment, "xdpyinfo -display #{display} | grep 'dimensions:'")
        
        if result.success?
          if result.stdout.match(/dimensions:\s+(\d+x\d+)/)
            resolution = $1
            log_debug "Xvfb screen resolution: #{resolution}"
            
            if resolution != @resolution
              add_warning("Screen resolution mismatch", 
                         { expected: @resolution, actual: resolution })
            end
          end
        end
        
        # Check color depth
        result = execute_command(environment, "xdpyinfo -display #{display} | grep 'depth of root'")
        if result.success? && result.stdout.match(/depth of root.*?(\d+)/)
          depth = $1.to_i
          if depth != @depth
            add_warning("Color depth mismatch", 
                       { expected: @depth, actual: depth })
          end
        end
      end
      
      def validate_weston_outputs(environment)
        # Check weston-info if available
        result = execute_command(environment, "which weston-info")
        if result.exit_code == 0
          result = execute_command(environment, "weston-info 2>/dev/null")
          if result.success?
            log_debug "Weston outputs: #{result.stdout}"
          end
        end
      end
      
      def validate_input_injection(environment)
        log_debug "Validating input injection capabilities"
        
        # Check for input simulation tools
        tools = {
          'wtype' => 'Wayland keyboard input',
          'ydotool' => 'Generic input injection',
          'wlrctl' => 'wlroots control',
          'xdotool' => 'X11 input injection'
        }
        
        available_tools = []
        tools.each do |tool, description|
          result = execute_command(environment, "which #{tool}")
          if result.exit_code == 0
            available_tools << tool
            log_debug "Input tool available: #{tool} (#{description})"
          end
        end
        
        if available_tools.empty?
          add_error("No input injection tools available")
        end
        
        # Check for virtual input devices
        if available_tools.include?('ydotool')
          validate_ydotool_setup(environment)
        end
      end
      
      def validate_ydotool_setup(environment)
        # Check if ydotoold is running
        result = execute_command(environment, "pgrep -x ydotoold")
        if result.exit_code != 0
          add_warning("ydotoold daemon not running")
          
          # Try to start it
          result = execute_command(environment, "ydotoold --socket-path /tmp/.ydotool_socket 2>&1 &")
          if result.exit_code == 0
            log_debug "Started ydotoold daemon"
          end
        end
        
        # Check for socket
        result = execute_command(environment, "test -S /tmp/.ydotool_socket && echo 'exists'")
        if result.stdout.strip != 'exists'
          add_warning("ydotool socket not available")
        end
      end
      
      def setup_wlroots_headless(environment)
        log_debug "Setting up wlroots headless backend"
        
        # Set environment variables
        execute_command(environment, "export WLR_BACKENDS=headless")
        execute_command(environment, "export WLR_LIBINPUT_NO_DEVICES=1")
        execute_command(environment, "export WAYLAND_DISPLAY=#{@display}")
        
        # Start a compositor with headless backend
        compositor = @options[:compositor] || 'sway'
        cmd = "#{compositor} -d 2>&1 &"
        
        result = execute_command(environment, cmd)
        if result.exit_code == 0
          # Wait for startup
          execute_command(environment, "sleep 2")
          
          # Create virtual output
          create_virtual_output(environment)
          true
        else
          add_error("Failed to start headless compositor", 
                   { compositor: compositor, error: result.stderr })
          false
        end
      end
      
      def setup_xvfb(environment)
        log_debug "Setting up Xvfb"
        
        display = HEADLESS_BACKENDS['xvfb'][:display]
        width, height = @resolution.split('x')
        
        cmd = "Xvfb #{display} -screen 0 #{@resolution}x#{@depth} -ac +extension GLX +render -noreset 2>&1 &"
        
        result = execute_command(environment, cmd)
        if result.exit_code == 0
          execute_command(environment, "export DISPLAY=#{display}")
          execute_command(environment, "sleep 2")
          
          # Verify it's running
          result = execute_command(environment, "xdpyinfo -display #{display} >/dev/null 2>&1")
          if result.exit_code == 0
            log_debug "Xvfb started successfully"
            true
          else
            add_error("Xvfb failed to start properly")
            false
          end
        else
          add_error("Failed to start Xvfb", { error: result.stderr })
          false
        end
      end
      
      def setup_weston_headless(environment)
        log_debug "Setting up Weston headless"
        
        width, height = @resolution.split('x')
        
        cmd = "weston --backend=headless-backend.so"
        cmd += " --width=#{width} --height=#{height}"
        cmd += " --socket=#{@display}"
        cmd += " 2>&1 &"
        
        result = execute_command(environment, cmd)
        if result.exit_code == 0
          execute_command(environment, "export WAYLAND_DISPLAY=#{@display}")
          execute_command(environment, "sleep 3")
          true
        else
          add_error("Failed to start Weston headless", { error: result.stderr })
          false
        end
      end
      
      def setup_cage_headless(environment)
        log_debug "Setting up cage headless"
        
        cmd = "cage -d -s -- true 2>&1 &"
        
        result = execute_command(environment, cmd)
        if result.exit_code == 0
          execute_command(environment, "sleep 2")
          true
        else
          add_error("Failed to start cage", { error: result.stderr })
          false
        end
      end
      
      def create_virtual_output(environment)
        # Try to create a virtual output using wlr-randr
        result = execute_command(environment, "which wlr-randr")
        if result.exit_code == 0
          cmd = "wlr-randr --create-headless"
          result = execute_command(environment, cmd)
          
          if result.exit_code == 0
            log_debug "Created virtual headless output"
            
            # Configure resolution
            cmd = "wlr-randr --output HEADLESS-1 --mode #{@resolution}"
            execute_command(environment, cmd)
          else
            log_warn "Failed to create virtual output: #{result.stderr}"
          end
        end
      end
      
      def parse_wlr_randr_output(text)
        outputs = []
        current_output = nil
        
        text.each_line do |line|
          if line.match(/^(\S+)/)
            current_output = { name: $1 }
            outputs << current_output
          elsif current_output && line.match(/(\d+)x(\d+)/)
            current_output[:mode] = "#{$1}x#{$2}"
          end
        end
        
        outputs
      end
      
      def extract_library_version(ldconfig_output)
        if ldconfig_output.match(/\.so\.(\d+(?:\.\d+)*)/)
          $1
        end
      end
    end
  end
end

# Register the validator
MitamaeTest::PluginManager.instance.register(:validator, 'headless_display', MitamaeTest::Validators::HeadlessDisplayValidator)