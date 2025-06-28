require_relative '../lib/validators/base'

module MitamaeTest
  module Validators
    class GraphicalValidator < Base
      plugin_name 'graphical'
      plugin_type :validator
      
      SUPPORTED_COMPOSITORS = %w[sway labwc wayfire hikari river].freeze
      WAYLAND_ENV_VARS = %w[WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP].freeze
      
      def initialize(options = {})
        super('graphical', options)
        @compositor = options[:compositor]
        @headless = options[:headless] || false
        @virtual_display = options[:virtual_display] || 'wayland-1'
      end
      
      def validate(environment, context = {})
        clear_results
        log_info "Starting graphical environment validation"
        
        validate_wayland_environment(environment)
        validate_compositor(environment) if @compositor
        validate_display_server(environment)
        validate_graphics_stack(environment)
        
        log_info "Graphical validation completed: #{success? ? 'SUCCESS' : 'FAILED'}"
        success?
      end
      
      private
      
      def validate_wayland_environment(environment)
        log_debug "Checking Wayland environment variables"
        
        WAYLAND_ENV_VARS.each do |var|
          result = execute_command(environment, "echo $#{var}")
          if result.stdout.strip.empty?
            add_warning("Environment variable #{var} is not set", 
                       { variable: var, headless: @headless })
          else
            log_debug "#{var}: #{result.stdout.strip}"
          end
        end
        
        # Check for Wayland display socket
        if @headless
          socket_path = "/tmp/.X11-unix/#{@virtual_display}"
        else
          result = execute_command(environment, 'echo $XDG_RUNTIME_DIR')
          runtime_dir = result.stdout.strip
          socket_path = "#{runtime_dir}/wayland-0" unless runtime_dir.empty?
        end
        
        if socket_path && !socket_path.empty?
          result = execute_command(environment, "test -S #{socket_path} && echo 'exists'")
          if result.stdout.strip != 'exists'
            add_error("Wayland display socket not found", 
                     { socket_path: socket_path, headless: @headless })
          end
        end
      end
      
      def validate_compositor(environment)
        log_debug "Validating compositor: #{@compositor}"
        
        unless SUPPORTED_COMPOSITORS.include?(@compositor)
          add_warning("Unknown compositor: #{@compositor}", 
                     { compositor: @compositor, supported: SUPPORTED_COMPOSITORS })
        end
        
        # Check if compositor is installed
        result = execute_command(environment, "which #{@compositor}")
        if result.exit_code != 0
          add_error("Compositor '#{@compositor}' not found in PATH", 
                   { compositor: @compositor })
          return
        end
        
        # Check if compositor is running (non-headless only)
        unless @headless
          result = execute_command(environment, "pgrep -x #{@compositor}")
          if result.exit_code != 0
            add_error("Compositor '#{@compositor}' is not running", 
                     { compositor: @compositor })
          end
        end
        
        # Validate compositor-specific configuration
        validate_compositor_config(environment)
      end
      
      def validate_compositor_config(environment)
        case @compositor
        when 'sway'
          validate_sway_config(environment)
        when 'labwc'
          validate_labwc_config(environment)
        end
      end
      
      def validate_sway_config(environment)
        config_paths = [
          '$HOME/.config/sway/config',
          '/etc/sway/config'
        ]
        
        config_found = false
        config_paths.each do |path|
          expanded_path = execute_command(environment, "echo #{path}").stdout.strip
          if check_file(environment, expanded_path)
            config_found = true
            log_debug "Found Sway config at: #{expanded_path}"
            
            # Validate config syntax
            result = execute_command(environment, "sway -C -c #{expanded_path}")
            if result.exit_code != 0
              add_error("Sway configuration has syntax errors", 
                       { config_path: expanded_path, errors: result.stderr })
            end
            break
          end
        end
        
        unless config_found
          add_warning("No Sway configuration found", 
                     { searched_paths: config_paths })
        end
      end
      
      def validate_labwc_config(environment)
        config_paths = [
          '$HOME/.config/labwc/rc.xml',
          '/etc/labwc/rc.xml'
        ]
        
        config_found = false
        config_paths.each do |path|
          expanded_path = execute_command(environment, "echo #{path}").stdout.strip
          if check_file(environment, expanded_path)
            config_found = true
            log_debug "Found LabWC config at: #{expanded_path}"
            
            # Basic XML validation
            result = execute_command(environment, "xmllint --noout #{expanded_path}")
            if result.exit_code != 0
              add_error("LabWC configuration has XML errors", 
                       { config_path: expanded_path, errors: result.stderr })
            end
            break
          end
        end
        
        unless config_found
          add_warning("No LabWC configuration found", 
                     { searched_paths: config_paths })
        end
      end
      
      def validate_display_server(environment)
        log_debug "Checking display server status"
        
        # Check for Xwayland if not pure Wayland
        result = execute_command(environment, "pgrep -x Xwayland")
        xwayland_running = result.exit_code == 0
        
        if @options[:require_xwayland] && !xwayland_running
          add_error("Xwayland is required but not running")
        elsif xwayland_running
          log_debug "Xwayland is running"
        end
        
        # Check for virtual display in headless mode
        if @headless
          validate_headless_display(environment)
        end
      end
      
      def validate_headless_display(environment)
        # Check for wlroots headless backend
        result = execute_command(environment, "echo $WLR_BACKENDS")
        if result.stdout.strip.empty? || !result.stdout.include?('headless')
          add_warning("WLR_BACKENDS not set for headless mode", 
                     { current_value: result.stdout.strip })
        end
        
        # Check for virtual framebuffer
        result = execute_command(environment, "which wlr-randr")
        if result.exit_code == 0
          # Check virtual outputs
          result = execute_command(environment, "wlr-randr")
          if result.exit_code == 0 && result.stdout.empty?
            add_error("No virtual outputs detected in headless mode")
          end
        else
          log_debug "wlr-randr not available for output detection"
        end
      end
      
      def validate_graphics_stack(environment)
        log_debug "Validating graphics stack"
        
        # Check for Mesa/graphics drivers
        result = execute_command(environment, "glxinfo -B 2>/dev/null || eglinfo 2>/dev/null")
        if result.exit_code != 0
          add_warning("Unable to query graphics information", 
                     { headless: @headless })
        else
          log_debug "Graphics stack appears functional"
        end
        
        # Check for required libraries
        libs = ['libwayland-client.so', 'libwayland-server.so', 'libEGL.so']
        libs.each do |lib|
          result = execute_command(environment, "ldconfig -p | grep #{lib}")
          if result.exit_code != 0
            add_error("Required library not found: #{lib}", 
                     { library: lib })
          end
        end
        
        # Check for GPU access in containers
        if environment.containerized?
          validate_container_gpu_access(environment)
        end
      end
      
      def validate_container_gpu_access(environment)
        # Check for DRI device access
        result = execute_command(environment, "test -d /dev/dri && echo 'exists'")
        if result.stdout.strip != 'exists'
          add_error("No GPU device access in container (/dev/dri missing)")
        else
          # Check for render nodes
          result = execute_command(environment, "ls /dev/dri/renderD*")
          if result.exit_code != 0
            add_error("No render nodes available in container")
          end
        end
      end
    end
  end
end

# Register the validator
MitamaeTest::PluginManager.instance.register(:validator, 'graphical', MitamaeTest::Validators::GraphicalValidator)