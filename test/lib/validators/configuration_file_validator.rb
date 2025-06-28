require 'yaml'
require 'fileutils'

module MitamaeTest
  module Validators
    class ConfigurationFileValidator < Base
      plugin_name :configuration_file
      plugin_type :validator
      
      def validate(environment, context = {})
        clear_results
        
        config = context[:config] || {}
        files_to_validate = config[:files] || []
        
        log_info "Validating #{files_to_validate.size} configuration files"
        
        files_to_validate.each do |file_spec|
          validate_file(environment, file_spec)
        end
        
        log_info "Configuration file validation complete: #{success? ? 'PASSED' : 'FAILED'}"
        self
      end
      
      private
      
      def validate_file(environment, file_spec)
        path = file_spec[:path]
        
        log_debug "Validating: #{path}"
        
        # Check file existence
        unless environment.file_exists?(path)
          if file_spec[:required] != false
            add_error("Required file not found: #{path}")
          else
            add_warning("Optional file not found: #{path}")
          end
          return
        end
        
        # Validate based on type
        case file_spec[:type]
        when :symlink
          validate_symlink(environment, file_spec)
        when :template
          validate_template(environment, file_spec)
        when :regular
          validate_regular_file(environment, file_spec)
        else
          validate_regular_file(environment, file_spec)
        end
        
        # Always validate permissions if specified
        validate_permissions(environment, file_spec) if file_spec[:permissions]
      end
      
      def validate_symlink(environment, file_spec)
        path = file_spec[:path]
        target = file_spec[:target]
        
        # Check if it's actually a symlink
        result = execute_command(environment, "test -L '#{path}'")
        unless result.success?
          add_error("Expected symlink but found regular file: #{path}")
          return
        end
        
        # Check symlink target
        if target
          actual_target = execute_command(environment, "readlink '#{path}'")
          if actual_target.success?
            actual = actual_target.stdout.strip
            if actual != target && !actual.end_with?(target)
              add_error("Symlink target mismatch for #{path}",
                       details: { expected: target, actual: actual })
            end
          else
            add_error("Failed to read symlink target: #{path}")
          end
        end
        
        # Check if target exists
        target_exists = execute_command(environment, "test -e '#{path}'")
        unless target_exists.success?
          add_warning("Symlink target does not exist: #{path}")
        end
      end
      
      def validate_template(environment, file_spec)
        path = file_spec[:path]
        
        # Read file content
        begin
          content = environment.read_file(path)
        rescue => e
          add_error("Failed to read template file: #{path}", 
                   details: { error: e.message })
          return
        end
        
        # Check for required content patterns
        if file_spec[:required_content]
          Array(file_spec[:required_content]).each do |pattern|
            regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
            unless content.match?(regex)
              add_error("Required content pattern not found in #{path}",
                       details: { pattern: pattern.to_s })
            end
          end
        end
        
        # Check for forbidden content
        if file_spec[:forbidden_content]
          Array(file_spec[:forbidden_content]).each do |pattern|
            regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
            if content.match?(regex)
              add_error("Forbidden content pattern found in #{path}",
                       details: { pattern: pattern.to_s })
            end
          end
        end
        
        # Validate template syntax if specified
        validate_template_syntax(environment, file_spec, content) if file_spec[:syntax]
      end
      
      def validate_regular_file(environment, file_spec)
        path = file_spec[:path]
        
        # Check it's not a symlink
        result = execute_command(environment, "test -L '#{path}'")
        if result.success?
          add_error("Expected regular file but found symlink: #{path}")
          return
        end
        
        # Check content if specified
        if file_spec[:content_match] || file_spec[:content_regex]
          begin
            content = environment.read_file(path)
            
            if file_spec[:content_match] && content != file_spec[:content_match]
              add_error("File content mismatch: #{path}",
                       details: { size_expected: file_spec[:content_match].size,
                                size_actual: content.size })
            end
            
            if file_spec[:content_regex]
              regex = Regexp.new(file_spec[:content_regex])
              unless content.match?(regex)
                add_error("Content does not match expected pattern: #{path}")
              end
            end
          rescue => e
            add_error("Failed to validate file content: #{path}",
                     details: { error: e.message })
          end
        end
        
        # Check file size if specified
        if file_spec[:max_size]
          size_result = execute_command(environment, "stat -c %s '#{path}' 2>/dev/null || stat -f %z '#{path}'")
          if size_result.success?
            size = size_result.stdout.strip.to_i
            if size > file_spec[:max_size]
              add_error("File exceeds maximum size: #{path}",
                       details: { max_size: file_spec[:max_size], actual_size: size })
            end
          end
        end
      end
      
      def validate_permissions(environment, file_spec)
        path = file_spec[:path]
        expected_perms = file_spec[:permissions]
        
        # Get current permissions
        stat_cmd = "stat -c '%a %U %G' '#{path}' 2>/dev/null || stat -f '%Lp %Su %Sg' '#{path}'"
        result = execute_command(environment, stat_cmd)
        
        unless result.success?
          add_error("Failed to check permissions: #{path}")
          return
        end
        
        parts = result.stdout.strip.split
        actual_mode = parts[0]
        actual_owner = parts[1]
        actual_group = parts[2]
        
        # Check mode
        if expected_perms[:mode]
          expected_mode = expected_perms[:mode].to_s
          if actual_mode != expected_mode
            add_error("Permission mode mismatch: #{path}",
                     details: { expected: expected_mode, actual: actual_mode })
          end
        end
        
        # Check owner
        if expected_perms[:owner] && actual_owner != expected_perms[:owner]
          add_error("Owner mismatch: #{path}",
                   details: { expected: expected_perms[:owner], actual: actual_owner })
        end
        
        # Check group
        if expected_perms[:group] && actual_group != expected_perms[:group]
          add_error("Group mismatch: #{path}",
                   details: { expected: expected_perms[:group], actual: actual_group })
        end
      end
      
      def validate_template_syntax(environment, file_spec, content)
        case file_spec[:syntax]
        when :yaml
          begin
            YAML.safe_load(content)
          rescue Psych::SyntaxError => e
            add_error("Invalid YAML syntax: #{file_spec[:path]}",
                     details: { error: e.message.lines.first })
          end
        when :json
          begin
            require 'json'
            JSON.parse(content)
          rescue JSON::ParserError => e
            add_error("Invalid JSON syntax: #{file_spec[:path]}",
                     details: { error: e.message })
          end
        when :shell
          # Basic shell syntax check
          result = execute_command(environment, "bash -n", timeout: 5)
          environment.write_file('/tmp/syntax_check.sh', content)
          result = execute_command(environment, "bash -n /tmp/syntax_check.sh")
          unless result.success?
            add_error("Invalid shell syntax: #{file_spec[:path]}",
                     details: { error: result.stderr })
          end
        end
      end
    end
  end
end