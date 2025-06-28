require_relative '../lib/validators/base'
require 'json'

module MitamaeTest
  module Validators
    class VisualValidator < Base
      plugin_name 'visual'
      plugin_type :validator
      
      # Visual validation rules
      VALIDATION_RULES = {
        window_decorations: {
          sway: { titlebar: true, borders: true },
          labwc: { titlebar: true, borders: true, shadows: false },
          wayfire: { titlebar: true, borders: true, shadows: true }
        },
        fonts: {
          system: ['sans-serif', 'DejaVu Sans', 'Liberation Sans'],
          monospace: ['monospace', 'DejaVu Sans Mono', 'Liberation Mono'],
          sizes: { min: 8, max: 24, default: 10 }
        },
        themes: {
          gtk: ['Adwaita', 'Arc', 'Breeze'],
          icons: ['Adwaita', 'Papirus', 'breeze'],
          cursors: ['Adwaita', 'breeze_cursors']
        }
      }.freeze
      
      def initialize(options = {})
        super('visual', options)
        @rules = options[:rules] || VALIDATION_RULES
        @strict = options[:strict] || false
        @screenshot_validator = options[:screenshot_validator]
      end
      
      def validate(environment, context = {})
        clear_results
        log_info "Starting visual validation"
        
        validate_display_configuration(environment)
        validate_theme_configuration(environment)
        validate_font_configuration(environment)
        validate_accessibility(environment)
        
        if context[:applications]
          validate_applications(environment, context[:applications])
        end
        
        log_info "Visual validation completed: #{success? ? 'SUCCESS' : 'FAILED'}"
        success?
      end
      
      private
      
      def validate_display_configuration(environment)
        log_debug "Validating display configuration"
        
        # Check display outputs
        outputs = get_display_outputs(environment)
        if outputs.empty?
          add_error("No display outputs detected")
          return
        end
        
        outputs.each do |output|
          validate_output_configuration(environment, output)
        end
        
        # Check multi-monitor setup if applicable
        if outputs.size > 1
          validate_multi_monitor_setup(environment, outputs)
        end
      end
      
      def get_display_outputs(environment)
        outputs = []
        
        # Try wlr-randr for Wayland
        result = execute_command(environment, "which wlr-randr")
        if result.exit_code == 0
          result = execute_command(environment, "wlr-randr --json 2>/dev/null || wlr-randr")
          if result.success?
            if result.stdout.start_with?('{') || result.stdout.start_with?('[')
              # JSON output
              begin
                data = JSON.parse(result.stdout)
                outputs = parse_wlr_randr_json(data)
              rescue JSON::ParserError
                log_warn "Failed to parse wlr-randr JSON output"
              end
            else
              # Text output
              outputs = parse_wlr_randr_text(result.stdout)
            end
          end
        end
        
        # Try swaymsg for Sway
        if outputs.empty?
          result = execute_command(environment, "swaymsg -t get_outputs 2>/dev/null")
          if result.success?
            begin
              outputs = JSON.parse(result.stdout)
            rescue JSON::ParserError
              log_warn "Failed to parse swaymsg output"
            end
          end
        end
        
        # Try xrandr as fallback
        if outputs.empty?
          result = execute_command(environment, "xrandr --current 2>/dev/null")
          if result.success?
            outputs = parse_xrandr_output(result.stdout)
          end
        end
        
        outputs
      end
      
      def parse_wlr_randr_json(data)
        # Handle both single object and array formats
        data = [data] unless data.is_a?(Array)
        data.map do |output|
          {
            name: output['name'],
            enabled: output['enabled'],
            mode: output['current_mode'],
            position: output['position'],
            scale: output['scale'] || 1.0
          }
        end
      end
      
      def parse_wlr_randr_text(text)
        outputs = []
        current_output = nil
        
        text.each_line do |line|
          if line.match(/^(\S+)/)
            current_output = { name: $1, enabled: true }
            outputs << current_output
          elsif current_output && line.match(/(\d+)x(\d+).*?\*/)
            current_output[:mode] = { width: $1.to_i, height: $2.to_i }
          elsif current_output && line.match(/Position:\s*(\d+),(\d+)/)
            current_output[:position] = { x: $1.to_i, y: $2.to_i }
          elsif current_output && line.match(/Scale:\s*([\d.]+)/)
            current_output[:scale] = $1.to_f
          end
        end
        
        outputs
      end
      
      def parse_xrandr_output(text)
        outputs = []
        current_output = nil
        
        text.each_line do |line|
          if line.match(/^(\S+)\s+(connected|disconnected)/)
            name = $1
            connected = $2 == 'connected'
            current_output = { name: name, enabled: connected }
            outputs << current_output if connected
            
            # Parse geometry if present
            if connected && line.match(/(\d+)x(\d+)\+(\d+)\+(\d+)/)
              current_output[:mode] = { width: $1.to_i, height: $2.to_i }
              current_output[:position] = { x: $3.to_i, y: $4.to_i }
            end
          end
        end
        
        outputs
      end
      
      def validate_output_configuration(environment, output)
        log_debug "Validating output: #{output[:name]}"
        
        # Check if output is enabled
        unless output[:enabled]
          add_warning("Output is disabled", { output: output[:name] })
          return
        end
        
        # Validate resolution
        if output[:mode]
          width = output[:mode][:width] || output[:mode]['width']
          height = output[:mode][:height] || output[:mode]['height']
          
          if width && height
            if width < 800 || height < 600
              add_warning("Low resolution detected", 
                         { output: output[:name], 
                           resolution: "#{width}x#{height}" })
            end
          end
        else
          add_error("No mode set for output", { output: output[:name] })
        end
        
        # Validate scaling
        scale = output[:scale] || 1.0
        if scale < 0.5 || scale > 3.0
          add_warning("Unusual scale factor", 
                     { output: output[:name], scale: scale })
        end
      end
      
      def validate_multi_monitor_setup(environment, outputs)
        log_debug "Validating multi-monitor configuration"
        
        # Check for overlapping displays
        outputs.each_with_index do |output1, i|
          outputs[(i+1)..-1].each do |output2|
            if outputs_overlap?(output1, output2)
              add_error("Display overlap detected", 
                       { outputs: [output1[:name], output2[:name]] })
            end
          end
        end
        
        # Check for gaps in display arrangement
        if display_has_gaps?(outputs)
          add_warning("Gaps detected in display arrangement")
        end
      end
      
      def outputs_overlap?(output1, output2)
        return false unless output1[:position] && output2[:position] && 
                           output1[:mode] && output2[:mode]
        
        x1 = output1[:position][:x] || output1[:position]['x'] || 0
        y1 = output1[:position][:y] || output1[:position]['y'] || 0
        w1 = output1[:mode][:width] || output1[:mode]['width'] || 0
        h1 = output1[:mode][:height] || output1[:mode]['height'] || 0
        
        x2 = output2[:position][:x] || output2[:position]['x'] || 0
        y2 = output2[:position][:y] || output2[:position]['y'] || 0
        w2 = output2[:mode][:width] || output2[:mode]['width'] || 0
        h2 = output2[:mode][:height] || output2[:mode]['height'] || 0
        
        !(x1 + w1 <= x2 || x2 + w2 <= x1 || y1 + h1 <= y2 || y2 + h2 <= y1)
      end
      
      def display_has_gaps?(outputs)
        # Simple check - more sophisticated algorithms could be implemented
        false
      end
      
      def validate_theme_configuration(environment)
        log_debug "Validating theme configuration"
        
        # Check GTK theme
        validate_gtk_theme(environment)
        
        # Check Qt theme
        validate_qt_theme(environment)
        
        # Check icon theme
        validate_icon_theme(environment)
        
        # Check cursor theme
        validate_cursor_theme(environment)
      end
      
      def validate_gtk_theme(environment)
        # Check GTK3 settings
        settings_file = "$HOME/.config/gtk-3.0/settings.ini"
        expanded = execute_command(environment, "echo #{settings_file}").stdout.strip
        
        if check_file(environment, expanded) do |content|
          if content.match(/gtk-theme-name\s*=\s*(.+)/)
            theme = $1.strip
            valid_themes = @rules[:themes][:gtk]
            unless valid_themes.include?(theme) || !@strict
              add_warning("Non-standard GTK theme", 
                         { theme: theme, valid: valid_themes })
            end
          else
            add_warning("No GTK theme configured")
          end
        end
        else
          log_debug "No GTK3 settings file found"
        end
        
        # Check environment variable
        result = execute_command(environment, "echo $GTK_THEME")
        gtk_theme_env = result.stdout.strip
        unless gtk_theme_env.empty?
          log_debug "GTK_THEME environment variable: #{gtk_theme_env}"
        end
      end
      
      def validate_qt_theme(environment)
        # Check Qt5 theme
        result = execute_command(environment, "echo $QT_STYLE_OVERRIDE")
        qt_style = result.stdout.strip
        
        if qt_style.empty?
          # Check qt5ct configuration
          config_file = "$HOME/.config/qt5ct/qt5ct.conf"
          expanded = execute_command(environment, "echo #{config_file}").stdout.strip
          
          check_file(environment, expanded) do |content|
            if content.match(/style=(.+)/)
              qt_style = $1.strip
            end
          end
        end
        
        unless qt_style.empty?
          log_debug "Qt theme: #{qt_style}"
        else
          add_warning("No Qt theme configured")
        end
      end
      
      def validate_icon_theme(environment)
        # Check icon theme from GTK settings
        settings_file = "$HOME/.config/gtk-3.0/settings.ini"
        expanded = execute_command(environment, "echo #{settings_file}").stdout.strip
        
        check_file(environment, expanded) do |content|
          if content.match(/gtk-icon-theme-name\s*=\s*(.+)/)
            theme = $1.strip
            valid_themes = @rules[:themes][:icons]
            unless valid_themes.include?(theme) || !@strict
              add_warning("Non-standard icon theme", 
                         { theme: theme, valid: valid_themes })
            end
          end
        end
        
        # Verify icon theme directory exists
        result = execute_command(environment, "ls $HOME/.icons/ /usr/share/icons/ 2>/dev/null | sort -u")
        if result.success?
          available_themes = result.stdout.strip.split("\n")
          log_debug "Available icon themes: #{available_themes.join(', ')}"
        end
      end
      
      def validate_cursor_theme(environment)
        # Check cursor theme
        result = execute_command(environment, "echo $XCURSOR_THEME")
        cursor_theme = result.stdout.strip
        
        if cursor_theme.empty?
          # Check in gtk settings
          settings_file = "$HOME/.config/gtk-3.0/settings.ini"
          expanded = execute_command(environment, "echo #{settings_file}").stdout.strip
          
          check_file(environment, expanded) do |content|
            if content.match(/gtk-cursor-theme-name\s*=\s*(.+)/)
              cursor_theme = $1.strip
            end
          end
        end
        
        unless cursor_theme.empty?
          valid_themes = @rules[:themes][:cursors]
          unless valid_themes.include?(cursor_theme) || !@strict
            add_warning("Non-standard cursor theme", 
                       { theme: cursor_theme, valid: valid_themes })
          end
        else
          log_debug "No cursor theme explicitly configured"
        end
      end
      
      def validate_font_configuration(environment)
        log_debug "Validating font configuration"
        
        # Check fontconfig
        validate_fontconfig(environment)
        
        # Check system fonts
        validate_system_fonts(environment)
        
        # Check font rendering settings
        validate_font_rendering(environment)
      end
      
      def validate_fontconfig(environment)
        # Check user fontconfig
        config_file = "$HOME/.config/fontconfig/fonts.conf"
        expanded = execute_command(environment, "echo #{config_file}").stdout.strip
        
        if check_file(environment, expanded)
          log_debug "User fontconfig found"
          
          # Validate XML
          result = execute_command(environment, "xmllint --noout #{expanded} 2>&1")
          if result.exit_code != 0
            add_error("Invalid fontconfig XML", 
                     { file: expanded, error: result.stdout })
          end
        end
        
        # Check font cache
        result = execute_command(environment, "fc-cache -v 2>&1 | grep 'skipping'")
        if result.success? && !result.stdout.empty?
          add_warning("Font cache issues detected", 
                     { output: result.stdout })
        end
      end
      
      def validate_system_fonts(environment)
        # Check for required font families
        @rules[:fonts][:system].each do |family|
          result = execute_command(environment, "fc-match '#{family}' 2>/dev/null")
          if result.exit_code != 0 || result.stdout.empty?
            add_error("Required font family not available", 
                     { family: family })
          else
            log_debug "Font '#{family}' resolves to: #{result.stdout.strip}"
          end
        end
        
        # Check for monospace fonts
        @rules[:fonts][:monospace].each do |family|
          result = execute_command(environment, "fc-match '#{family}' 2>/dev/null")
          if result.exit_code != 0
            add_warning("Monospace font not available", 
                       { family: family })
          end
        end
      end
      
      def validate_font_rendering(environment)
        # Check for subpixel rendering configuration
        result = execute_command(environment, "xrdb -query 2>/dev/null | grep -i 'rgba\\|hint\\|antialias'")
        if result.success? && !result.stdout.empty?
          log_debug "Font rendering settings: #{result.stdout.strip}"
        end
        
        # Check freetype configuration
        config_file = "/etc/fonts/conf.d/10-hinting-slight.conf"
        if check_file(environment, config_file)
          log_debug "Font hinting configured"
        else
          add_warning("Font hinting not configured")
        end
      end
      
      def validate_accessibility(environment)
        log_debug "Validating accessibility features"
        
        # Check high contrast mode
        result = execute_command(environment, "gsettings get org.gnome.desktop.interface high-contrast 2>/dev/null")
        if result.success?
          high_contrast = result.stdout.strip == 'true'
          log_debug "High contrast mode: #{high_contrast}"
        end
        
        # Check text scaling
        result = execute_command(environment, "gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null")
        if result.success?
          scale = result.stdout.strip.to_f
          if scale > 1.5
            add_warning("High text scaling factor", { scale: scale })
          end
        end
        
        # Check for screen reader
        result = execute_command(environment, "pgrep -x orca")
        if result.exit_code == 0
          log_debug "Screen reader (Orca) is running"
        end
      end
      
      def validate_applications(environment, applications)
        log_debug "Validating application visual appearance"
        
        applications.each do |app|
          validate_application_visual(environment, app)
        end
      end
      
      def validate_application_visual(environment, app)
        name = app[:name]
        log_debug "Validating visual appearance of #{name}"
        
        # Launch application if needed
        if app[:launch]
          result = execute_command(environment, app[:launch])
          if result.exit_code != 0
            add_error("Failed to launch application", 
                     { app: name, error: result.stderr })
            return
          end
          
          # Wait for window
          sleep_time = app[:wait] || 2
          execute_command(environment, "sleep #{sleep_time}")
        end
        
        # Verify window exists
        window_title = app[:window_title] || name
        if verify_window_exists(environment, window_title)
          log_debug "Window found: #{window_title}"
          
          # Take screenshot if validator available
          if @screenshot_validator
            screenshot = @screenshot_validator.capture_screenshot(
              environment, 
              "app_#{name}",
              { window: window_title }
            )
            
            # Run visual checks
            if screenshot && app[:visual_checks]
              run_visual_checks(environment, screenshot, app[:visual_checks])
            end
          end
        else
          add_error("Application window not found", 
                   { app: name, window_title: window_title })
        end
        
        # Cleanup
        if app[:cleanup]
          execute_command(environment, app[:cleanup])
        end
      end
      
      def verify_window_exists(environment, title)
        # Try swaymsg for Sway
        result = execute_command(environment, "swaymsg -t get_tree | grep -q '#{title}'")
        return true if result.exit_code == 0
        
        # Try wmctrl
        result = execute_command(environment, "wmctrl -l | grep -q '#{title}'")
        return true if result.exit_code == 0
        
        # Try xwininfo
        result = execute_command(environment, "xwininfo -name '#{title}' 2>/dev/null")
        return true if result.exit_code == 0
        
        false
      end
      
      def run_visual_checks(environment, screenshot, checks)
        checks.each do |check|
          case check[:type]
          when 'has_titlebar'
            check_titlebar_presence(environment, screenshot)
          when 'has_menu'
            check_menu_presence(environment, screenshot)
          when 'theme_applied'
            check_theme_applied(environment, screenshot, check[:theme])
          when 'minimum_size'
            check_minimum_size(environment, screenshot, check[:width], check[:height])
          end
        end
      end
      
      def check_titlebar_presence(environment, screenshot)
        # Use image analysis to detect titlebar
        # This is a simplified check - real implementation would be more sophisticated
        result = execute_command(environment, 
          "convert #{screenshot} -crop 100%x30+0+0 -colorspace Gray -format '%[mean]' info:")
        
        if result.success?
          mean = result.stdout.strip.to_f
          if mean < 10000 || mean > 55000
            log_debug "Titlebar detected (mean: #{mean})"
          else
            add_warning("Titlebar might be missing", { screenshot: screenshot })
          end
        end
      end
      
      def check_menu_presence(environment, screenshot)
        # Check for menu bar pattern
        # This would need more sophisticated image analysis
        log_debug "Menu presence check not implemented"
      end
      
      def check_theme_applied(environment, screenshot, expected_theme)
        # Check if theme colors are present
        # This would need theme-specific color detection
        log_debug "Theme detection not implemented for #{expected_theme}"
      end
      
      def check_minimum_size(environment, screenshot, min_width, min_height)
        result = execute_command(environment, "identify -format '%wx%h' #{screenshot}")
        if result.success?
          width, height = result.stdout.strip.split('x').map(&:to_i)
          if width < min_width || height < min_height
            add_error("Window too small", 
                     { actual: "#{width}x#{height}", 
                       minimum: "#{min_width}x#{min_height}" })
          end
        end
      end
    end
  end
end

# Register the validator
MitamaeTest::PluginManager.instance.register(:validator, 'visual', MitamaeTest::Validators::VisualValidator)