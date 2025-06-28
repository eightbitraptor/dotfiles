require_relative '../lib/validators/base'
require 'fileutils'
require 'tmpdir'

module MitamaeTest
  module Validators
    class ScreenshotValidator < Base
      plugin_name 'screenshot'
      plugin_type :validator
      
      CAPTURE_TOOLS = {
        'grim' => { package: 'grim', wayland: true },
        'scrot' => { package: 'scrot', wayland: false },
        'import' => { package: 'imagemagick', wayland: false },
        'wayshot' => { package: 'wayshot', wayland: true },
        'flameshot' => { package: 'flameshot', wayland: true }
      }.freeze
      
      COMPARE_TOOLS = {
        'compare' => { package: 'imagemagick' },
        'perceptualdiff' => { package: 'perceptualdiff' },
        'pixelmatch' => { package: 'npm', command: 'npx pixelmatch' }
      }.freeze
      
      def initialize(options = {})
        super('screenshot', options)
        @capture_tool = options[:capture_tool] || detect_capture_tool
        @compare_tool = options[:compare_tool] || 'compare'
        @output_dir = options[:output_dir] || '/tmp/mitamae-screenshots'
        @threshold = options[:threshold] || 0.01  # 1% difference threshold
        @reference_dir = options[:reference_dir]
        @headless = options[:headless] || false
      end
      
      def validate(environment, context = {})
        clear_results
        log_info "Starting screenshot validation"
        
        validate_capture_tools(environment)
        validate_compare_tools(environment)
        
        if @reference_dir
          validate_against_references(environment, context)
        else
          capture_current_state(environment, context)
        end
        
        log_info "Screenshot validation completed: #{success? ? 'SUCCESS' : 'FAILED'}"
        success?
      end
      
      def capture_screenshot(environment, name, options = {})
        ensure_output_directory(environment)
        
        filename = "#{name}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.png"
        filepath = File.join(@output_dir, filename)
        
        case @capture_tool
        when 'grim'
          capture_with_grim(environment, filepath, options)
        when 'wayshot'
          capture_with_wayshot(environment, filepath, options)
        when 'scrot'
          capture_with_scrot(environment, filepath, options)
        when 'import'
          capture_with_import(environment, filepath, options)
        else
          add_error("Unknown capture tool: #{@capture_tool}")
          return nil
        end
        
        # Verify screenshot was created
        result = execute_command(environment, "test -f #{filepath} && echo 'exists'")
        if result.stdout.strip == 'exists'
          log_debug "Screenshot saved: #{filepath}"
          filepath
        else
          add_error("Failed to create screenshot", { filepath: filepath })
          nil
        end
      end
      
      def compare_screenshots(environment, reference, current, name)
        case @compare_tool
        when 'compare'
          compare_with_imagemagick(environment, reference, current, name)
        when 'perceptualdiff'
          compare_with_perceptualdiff(environment, reference, current, name)
        when 'pixelmatch'
          compare_with_pixelmatch(environment, reference, current, name)
        else
          add_error("Unknown compare tool: #{@compare_tool}")
          false
        end
      end
      
      private
      
      def detect_capture_tool
        # Prefer Wayland-native tools
        %w[grim wayshot scrot import].first
      end
      
      def validate_capture_tools(environment)
        log_debug "Validating capture tool: #{@capture_tool}"
        
        tool_info = CAPTURE_TOOLS[@capture_tool]
        unless tool_info
          add_error("Invalid capture tool: #{@capture_tool}")
          return
        end
        
        result = execute_command(environment, "which #{@capture_tool}")
        if result.exit_code != 0
          add_error("Capture tool '#{@capture_tool}' not found", 
                   { tool: @capture_tool, package: tool_info[:package] })
        end
        
        # Check if tool supports current display server
        if tool_info[:wayland]
          result = execute_command(environment, "echo $WAYLAND_DISPLAY")
          if result.stdout.strip.empty? && !@headless
            add_warning("#{@capture_tool} requires Wayland but WAYLAND_DISPLAY not set")
          end
        end
      end
      
      def validate_compare_tools(environment)
        log_debug "Validating compare tool: #{@compare_tool}"
        
        tool_info = COMPARE_TOOLS[@compare_tool]
        unless tool_info
          add_error("Invalid compare tool: #{@compare_tool}")
          return
        end
        
        command = tool_info[:command] || @compare_tool
        result = execute_command(environment, "which #{command.split.first}")
        if result.exit_code != 0
          add_error("Compare tool '#{@compare_tool}' not found", 
                   { tool: @compare_tool, package: tool_info[:package] })
        end
      end
      
      def ensure_output_directory(environment)
        execute_command(environment, "mkdir -p #{@output_dir}")
      end
      
      def capture_with_grim(environment, filepath, options = {})
        cmd = "grim"
        cmd += " -g '#{options[:geometry]}'" if options[:geometry]
        cmd += " -s #{options[:scale]}" if options[:scale]
        cmd += " -o #{options[:output]}" if options[:output]
        cmd += " #{filepath}"
        
        if @headless
          cmd = "WLR_BACKENDS=headless #{cmd}"
        end
        
        result = execute_command(environment, cmd, timeout: 5000)
        if result.exit_code != 0
          add_error("Failed to capture with grim", 
                   { command: cmd, error: result.stderr })
        end
      end
      
      def capture_with_wayshot(environment, filepath, options = {})
        cmd = "wayshot"
        cmd += " --stdout" if options[:stdout]
        cmd += " -o #{options[:output]}" if options[:output]
        cmd += " #{filepath}"
        
        result = execute_command(environment, cmd, timeout: 5000)
        if result.exit_code != 0
          add_error("Failed to capture with wayshot", 
                   { command: cmd, error: result.stderr })
        end
      end
      
      def capture_with_scrot(environment, filepath, options = {})
        cmd = "scrot"
        cmd += " -s" if options[:select]
        cmd += " -u" if options[:focused]
        cmd += " #{filepath}"
        
        # Set DISPLAY for X11 tools in headless mode
        if @headless
          cmd = "DISPLAY=:99 #{cmd}"
        end
        
        result = execute_command(environment, cmd, timeout: 5000)
        if result.exit_code != 0
          add_error("Failed to capture with scrot", 
                   { command: cmd, error: result.stderr })
        end
      end
      
      def capture_with_import(environment, filepath, options = {})
        cmd = "import"
        cmd += " -window #{options[:window]}" if options[:window]
        cmd += " -window root" unless options[:window]
        cmd += " #{filepath}"
        
        if @headless
          cmd = "DISPLAY=:99 #{cmd}"
        end
        
        result = execute_command(environment, cmd, timeout: 5000)
        if result.exit_code != 0
          add_error("Failed to capture with import", 
                   { command: cmd, error: result.stderr })
        end
      end
      
      def compare_with_imagemagick(environment, reference, current, name)
        diff_file = File.join(@output_dir, "diff_#{name}.png")
        
        # Use compare with metrics
        cmd = "compare -metric AE -fuzz #{@threshold * 100}% #{reference} #{current} #{diff_file} 2>&1"
        result = execute_command(environment, cmd)
        
        # ImageMagick compare returns 1 if images differ
        if result.exit_code == 0
          log_debug "Screenshots match for #{name}"
          true
        else
          pixels_different = result.stdout.strip.to_i
          if pixels_different > 0
            # Get image dimensions for percentage calculation
            dim_result = execute_command(environment, "identify -format '%wx%h' #{current}")
            if dim_result.success?
              width, height = dim_result.stdout.strip.split('x').map(&:to_i)
              total_pixels = width * height
              diff_percentage = (pixels_different.to_f / total_pixels) * 100
              
              if diff_percentage > (@threshold * 100)
                add_error("Screenshot mismatch for #{name}", 
                         { difference: "#{diff_percentage.round(2)}%",
                           threshold: "#{@threshold * 100}%",
                           diff_image: diff_file })
                false
              else
                log_debug "Screenshot difference within threshold for #{name}: #{diff_percentage.round(2)}%"
                true
              end
            else
              add_error("Failed to get image dimensions", { image: current })
              false
            end
          else
            true
          end
        end
      end
      
      def compare_with_perceptualdiff(environment, reference, current, name)
        cmd = "perceptualdiff #{reference} #{current} -threshold #{@threshold * 100}"
        result = execute_command(environment, cmd)
        
        if result.exit_code == 0
          log_debug "Screenshots match for #{name}"
          true
        else
          add_error("Screenshot mismatch for #{name}", 
                   { output: result.stdout })
          false
        end
      end
      
      def compare_with_pixelmatch(environment, reference, current, name)
        diff_file = File.join(@output_dir, "diff_#{name}.png")
        threshold = (@threshold * 255).to_i
        
        cmd = "npx pixelmatch #{reference} #{current} #{diff_file} #{threshold}"
        result = execute_command(environment, cmd)
        
        if result.exit_code == 0
          pixels_different = result.stdout.strip.to_i
          if pixels_different == 0
            log_debug "Screenshots match for #{name}"
            true
          else
            add_error("Screenshot mismatch for #{name}", 
                     { pixels_different: pixels_different,
                       diff_image: diff_file })
            false
          end
        else
          add_error("Failed to compare screenshots", 
                   { error: result.stderr })
          false
        end
      end
      
      def validate_against_references(environment, context)
        log_info "Validating against reference screenshots"
        
        # Get list of reference screenshots
        result = execute_command(environment, "find #{@reference_dir} -name '*.png' -type f")
        if result.exit_code != 0
          add_error("Failed to find reference screenshots", 
                   { directory: @reference_dir })
          return
        end
        
        references = result.stdout.strip.split("\n")
        if references.empty?
          add_warning("No reference screenshots found", 
                     { directory: @reference_dir })
          return
        end
        
        # Compare each reference
        references.each do |reference|
          name = File.basename(reference, '.png')
          log_debug "Validating screenshot: #{name}"
          
          # Capture current screenshot
          current = capture_screenshot(environment, name, context[:capture_options] || {})
          next unless current
          
          # Compare with reference
          compare_screenshots(environment, reference, current, name)
        end
      end
      
      def capture_current_state(environment, context)
        log_info "Capturing current desktop state"
        
        # Define what to capture based on context
        captures = context[:captures] || default_captures
        
        captures.each do |capture|
          name = capture[:name]
          options = capture[:options] || {}
          
          log_debug "Capturing: #{name}"
          
          # Wait if specified
          if capture[:wait]
            execute_command(environment, "sleep #{capture[:wait]}")
          end
          
          # Execute setup commands if specified
          if capture[:setup]
            capture[:setup].each do |cmd|
              execute_command(environment, cmd)
            end
          end
          
          # Capture screenshot
          filepath = capture_screenshot(environment, name, options)
          
          if filepath && capture[:validate]
            # Run custom validation
            validate_capture(environment, filepath, capture[:validate])
          end
          
          # Cleanup
          if capture[:cleanup]
            capture[:cleanup].each do |cmd|
              execute_command(environment, cmd)
            end
          end
        end
      end
      
      def default_captures
        [
          { name: 'desktop', options: {} },
          { name: 'terminal', 
            setup: ['wtype "echo test"', 'wtype Return'],
            wait: 1,
            options: {} }
        ]
      end
      
      def validate_capture(environment, filepath, validations)
        validations.each do |validation|
          case validation[:type]
          when 'contains_text'
            validate_ocr_text(environment, filepath, validation[:text])
          when 'color_present'
            validate_color_present(environment, filepath, validation[:color])
          when 'resolution'
            validate_resolution(environment, filepath, validation[:width], validation[:height])
          end
        end
      end
      
      def validate_ocr_text(environment, filepath, expected_text)
        # Use tesseract if available
        result = execute_command(environment, "which tesseract")
        if result.exit_code == 0
          result = execute_command(environment, "tesseract #{filepath} - 2>/dev/null")
          if result.success?
            if result.stdout.include?(expected_text)
              log_debug "Found expected text: #{expected_text}"
            else
              add_warning("Expected text not found in screenshot", 
                         { expected: expected_text, file: filepath })
            end
          end
        else
          log_debug "OCR validation skipped (tesseract not available)"
        end
      end
      
      def validate_color_present(environment, filepath, color)
        # Convert color to RGB if needed
        cmd = "convert #{filepath} -format '%c' histogram:info: | grep -i '#{color}'"
        result = execute_command(environment, cmd)
        
        if result.exit_code == 0 && !result.stdout.empty?
          log_debug "Found color #{color} in screenshot"
        else
          add_warning("Color not found in screenshot", 
                     { color: color, file: filepath })
        end
      end
      
      def validate_resolution(environment, filepath, expected_width, expected_height)
        result = execute_command(environment, "identify -format '%wx%h' #{filepath}")
        if result.success?
          actual = result.stdout.strip
          expected = "#{expected_width}x#{expected_height}"
          if actual == expected
            log_debug "Resolution matches: #{actual}"
          else
            add_error("Resolution mismatch", 
                     { expected: expected, actual: actual, file: filepath })
          end
        end
      end
    end
  end
end

# Register the validator
MitamaeTest::PluginManager.instance.register(:validator, 'screenshot', MitamaeTest::Validators::ScreenshotValidator)