require_relative '../artifact_collector'
require_relative '../artifact_repository'
require 'fileutils'
require 'yaml'
require 'json'

module MitamaeTest
  module Environments
    class ArtifactManager
      include Logging
      include ErrorHandling
      
      ARTIFACT_RETENTION_DAYS = 30
      ARTIFACT_STORAGE_LIMIT_GB = 5
      
      attr_reader :base_artifacts_dir, :environment_manager, :collection_configs, :repository
      
      def initialize(environment_manager, base_artifacts_dir = nil)
        @environment_manager = environment_manager
        @base_artifacts_dir = base_artifacts_dir || File.join(Dir.tmpdir, 'mitamae-test-artifacts')
        @collection_configs = {}
        @active_collections = {}
        
        setup_artifacts_directory
        load_artifact_configurations
        
        # Initialize repository
        repository_path = File.join(@base_artifacts_dir, 'repository')
        @repository = ArtifactRepository.new(repository_path)
      end
      
      def collect_test_artifacts(environment_name, test_result = nil, config = {})
        log_info "Collecting artifacts for environment: #{environment_name}"
        
        env_context = @environment_manager.get_environment(environment_name)
        raise TestError, "Environment not found: #{environment_name}" unless env_context
        
        # Create timestamped artifact directory
        timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
        artifact_dir = File.join(@base_artifacts_dir, environment_name, timestamp)
        
        # Merge with environment-specific configuration
        collection_config = merge_collection_config(environment_name, config, test_result)
        
        # Create artifact collector
        collector = ArtifactCollector.new(
          env_context.environment,
          artifact_dir,
          collection_config
        )
        
        # Track active collection
        collection_id = SecureRandom.hex(8)
        @active_collections[collection_id] = {
          environment_name: environment_name,
          collector: collector,
          started_at: Time.now
        }
        
        begin
          # Collect artifacts based on test result
          collection_result = if test_result && test_failed?(test_result)
                               collector.collect_failure_artifacts(test_result)
                             else
                               collector.collect_all_artifacts(test_result)
                             end
          
          # Create browsable index
          if collection_config[:create_browsable_index]
            index_path = collector.create_browsable_index
            collection_result[:browsable_index] = index_path
          end
          
          # Store in repository
          repo_collection_id = store_in_repository(environment_name, collection_result, test_result)
          collection_result[:repository_id] = repo_collection_id
          
          # Register artifact collection
          register_artifact_collection(environment_name, artifact_dir, collection_result)
          
          # Cleanup old artifacts if needed
          if collection_config[:auto_cleanup]
            cleanup_old_artifacts(environment_name)
          end
          
          log_info "Artifact collection completed: #{artifact_dir}"
          collection_result
          
        ensure
          @active_collections.delete(collection_id)
        end
      end
      
      def collect_session_artifacts(test_session, session_result = nil)
        log_info "Collecting artifacts for test session"
        
        session_artifacts = {}
        session_timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
        session_dir = File.join(@base_artifacts_dir, 'sessions', "session-#{session_timestamp}")
        
        # Collect artifacts from each environment in the session
        test_session.environments.each do |env_name, env_context|
          env_artifacts = collect_test_artifacts(env_name, session_result)
          session_artifacts[env_name] = env_artifacts
        end
        
        # Create session-level artifacts
        session_artifacts[:session_summary] = create_session_summary(
          test_session,
          session_result,
          session_dir
        )
        
        # Create consolidated session report
        session_artifacts[:session_report] = create_session_report(
          test_session,
          session_artifacts,
          session_dir
        )
        
        log_info "Session artifact collection completed: #{session_dir}"
        session_artifacts
      end
      
      def get_artifact_history(environment_name, limit = 20)
        env_artifacts_dir = File.join(@base_artifacts_dir, environment_name)
        return [] unless File.exist?(env_artifacts_dir)
        
        collections = []
        
        Dir.glob(File.join(env_artifacts_dir, '*')).sort.reverse.first(limit).each do |collection_dir|
          next unless File.directory?(collection_dir)
          
          metadata_file = File.join(collection_dir, 'collection_metadata.yaml')
          if File.exist?(metadata_file)
            metadata = YAML.load_file(metadata_file)
            collections << {
              collection_dir: collection_dir,
              timestamp: metadata[:timestamp],
              success: metadata[:success],
              artifact_types: metadata[:artifacts]&.keys || [],
              total_size: metadata[:total_size],
              duration: metadata[:duration]
            }
          end
        end
        
        collections
      end
      
      def get_artifact_summary(environment_name = nil)
        if environment_name
          get_environment_artifact_summary(environment_name)
        else
          get_global_artifact_summary
        end
      end
      
      def cleanup_old_artifacts(environment_name = nil, max_age_days = ARTIFACT_RETENTION_DAYS)
        log_info "Cleaning up artifacts older than #{max_age_days} days"
        
        cleanup_dirs = if environment_name
                        [File.join(@base_artifacts_dir, environment_name)]
                      else
                        Dir.glob(File.join(@base_artifacts_dir, '*')).select { |d| File.directory?(d) }
                      end
        
        total_cleaned = 0
        total_size_freed = 0
        
        cleanup_dirs.each do |dir|
          next unless File.exist?(dir)
          
          cleaned, size_freed = cleanup_directory_by_age(dir, max_age_days)
          total_cleaned += cleaned
          total_size_freed += size_freed
        end
        
        log_info "Cleanup completed: #{total_cleaned} collections removed, #{format_size(total_size_freed)} freed"
        { collections_removed: total_cleaned, size_freed: total_size_freed }
      end
      
      def enforce_storage_limits(limit_gb = ARTIFACT_STORAGE_LIMIT_GB)
        log_info "Enforcing artifact storage limit: #{limit_gb}GB"
        
        current_usage = calculate_total_artifact_size
        limit_bytes = limit_gb * 1024 * 1024 * 1024
        
        return { action_needed: false, current_usage: current_usage } if current_usage <= limit_bytes
        
        log_warn "Artifact storage limit exceeded: #{format_size(current_usage)} > #{limit_gb}GB"
        
        # Get all artifact collections sorted by age (oldest first)
        collections = get_all_artifact_collections.sort_by { |c| c[:timestamp] }
        
        removed_collections = 0
        size_freed = 0
        
        collections.each do |collection|
          break if (current_usage - size_freed) <= limit_bytes
          
          collection_size = calculate_directory_size(collection[:path])
          
          if File.exist?(collection[:path])
            FileUtils.rm_rf(collection[:path])
            size_freed += collection_size
            removed_collections += 1
            log_debug "Removed old collection: #{collection[:path]} (#{format_size(collection_size)})"
          end
        end
        
        log_info "Storage limit enforcement: #{removed_collections} collections removed, #{format_size(size_freed)} freed"
        
        {
          action_needed: true,
          initial_usage: current_usage,
          final_usage: current_usage - size_freed,
          collections_removed: removed_collections,
          size_freed: size_freed
        }
      end
      
      def export_artifacts(environment_name, collection_timestamp, format = :tar_gz)
        collection_dir = File.join(@base_artifacts_dir, environment_name, collection_timestamp)
        
        raise TestError, "Artifact collection not found: #{collection_dir}" unless File.exist?(collection_dir)
        
        export_name = "#{environment_name}-#{collection_timestamp}"
        
        case format
        when :tar_gz
          export_path = "#{export_name}.tar.gz"
          system("tar -czf #{export_path} -C #{File.dirname(collection_dir)} #{File.basename(collection_dir)}")
        when :zip
          export_path = "#{export_name}.zip"
          system("zip -r #{export_path} #{collection_dir}")
        else
          raise TestError, "Unsupported export format: #{format}"
        end
        
        if File.exist?(export_path)
          log_info "Artifacts exported: #{export_path} (#{format_size(File.size(export_path))})"
          File.expand_path(export_path)
        else
          raise TestError, "Failed to create export archive"
        end
      end
      
      def compare_artifact_collections(env_name, timestamp1, timestamp2)
        collection1_dir = File.join(@base_artifacts_dir, env_name, timestamp1)
        collection2_dir = File.join(@base_artifacts_dir, env_name, timestamp2)
        
        raise TestError, "Collection 1 not found: #{collection1_dir}" unless File.exist?(collection1_dir)
        raise TestError, "Collection 2 not found: #{collection2_dir}" unless File.exist?(collection2_dir)
        
        comparison = {
          collection1: { timestamp: timestamp1, path: collection1_dir },
          collection2: { timestamp: timestamp2, path: collection2_dir },
          differences: {},
          summary: {}
        }
        
        # Compare metadata
        comparison[:differences][:metadata] = compare_collection_metadata(collection1_dir, collection2_dir)
        
        # Compare log files
        comparison[:differences][:logs] = compare_log_files(collection1_dir, collection2_dir)
        
        # Compare system state
        comparison[:differences][:system_state] = compare_system_state(collection1_dir, collection2_dir)
        
        # Generate summary
        comparison[:summary] = generate_comparison_summary(comparison[:differences])
        
        log_info "Artifact comparison completed: #{timestamp1} vs #{timestamp2}"
        comparison
      end
      
      def create_artifact_report(environment_name = nil, format = :html)
        log_info "Creating artifact report"
        
        report_data = {
          generated_at: Time.now.iso8601,
          environments: {},
          global_summary: get_global_artifact_summary
        }
        
        if environment_name
          report_data[:environments][environment_name] = get_environment_artifact_summary(environment_name)
        else
          # Include all environments
          Dir.glob(File.join(@base_artifacts_dir, '*')).each do |env_dir|
            next unless File.directory?(env_dir)
            
            env_name = File.basename(env_dir)
            next if env_name == 'sessions'
            
            report_data[:environments][env_name] = get_environment_artifact_summary(env_name)
          end
        end
        
        # Generate report in requested format
        case format
        when :html
          create_html_report(report_data, environment_name)
        when :json
          create_json_report(report_data, environment_name)
        when :yaml
          create_yaml_report(report_data, environment_name)
        else
          raise TestError, "Unsupported report format: #{format}"
        end
      end
      
      def search_artifacts(query, filters = {})
        @repository.search_artifacts(query, filters)
      end
      
      def find_collections(filters = {})
        @repository.find_collections(filters)
      end
      
      def get_collection(collection_id)
        @repository.get_collection(collection_id)
      end
      
      def compare_collections(collection_id1, collection_id2)
        @repository.compare_collections(collection_id1, collection_id2)
      end
      
      def start_browser(port = 8080, host = 'localhost')
        require_relative '../artifact_browser'
        
        @browser = ArtifactBrowser.new(@repository, port, host)
        @browser.start
      end
      
      def stop_browser
        @browser&.stop
        @browser = nil
      end
      
      def get_repository_statistics
        @repository.get_repository_statistics
      end
      
      def create_backup(backup_path)
        @repository.create_repository_backup(backup_path)
      end
      
      def restore_backup(backup_path)
        @repository.restore_repository_backup(backup_path)
      end
      
      def cleanup_repository(max_age_days = 30)
        @repository.cleanup_old_collections(max_age_days)
      end
      
      private
      
      def store_in_repository(environment_name, collection_result, test_result)
        # Prepare metadata for repository storage
        metadata = {
          session_id: collection_result[:session_id] || SecureRandom.hex(8),
          environment_id: environment_name,
          timestamp: collection_result[:timestamp] || Time.now.iso8601,
          success: collection_result[:success],
          duration: collection_result[:duration],
          total_size: collection_result[:total_size],
          test_result: test_result
        }
        
        # Store in repository
        @repository.store_artifact_collection(metadata, collection_result[:artifacts] || {})
      end
      
      def setup_artifacts_directory
        FileUtils.mkdir_p(@base_artifacts_dir)
        FileUtils.mkdir_p(File.join(@base_artifacts_dir, 'sessions'))
        FileUtils.mkdir_p(File.join(@base_artifacts_dir, 'reports'))
      end
      
      def load_artifact_configurations
        config_file = File.join(@base_artifacts_dir, 'artifact_configs.yaml')
        
        if File.exist?(config_file)
          @collection_configs = YAML.load_file(config_file) || {}
        else
          @collection_configs = {}
          save_artifact_configurations
        end
      end
      
      def save_artifact_configurations
        config_file = File.join(@base_artifacts_dir, 'artifact_configs.yaml')
        File.write(config_file, YAML.dump(@collection_configs))
      end
      
      def merge_collection_config(environment_name, config, test_result)
        # Start with default configuration
        merged_config = default_artifact_config.dup
        
        # Apply environment-specific configuration
        if @collection_configs[environment_name]
          merged_config.merge!(@collection_configs[environment_name])
        end
        
        # Apply test result specific configuration
        if test_result && test_failed?(test_result)
          merged_config.merge!(failure_artifact_config)
        end
        
        # Apply provided configuration
        merged_config.merge!(config)
        
        merged_config
      end
      
      def default_artifact_config
        {
          artifact_types: [:logs, :system_state, :config_files, :environment_info],
          create_archive: false,
          create_browsable_index: true,
          auto_cleanup: true,
          max_file_size_mb: 50,
          include_binary_files: false,
          generate_report: true
        }
      end
      
      def failure_artifact_config
        {
          artifact_types: ArtifactCollector::ARTIFACT_TYPES,
          create_archive: true,
          include_binary_files: true,
          max_file_size_mb: 100
        }
      end
      
      def test_failed?(test_result)
        return false unless test_result.is_a?(Hash)
        
        test_result[:failed] == true ||
          test_result[:success] == false ||
          (test_result[:exit_code] && test_result[:exit_code] != 0)
      end
      
      def register_artifact_collection(environment_name, artifact_dir, collection_result)
        registry_file = File.join(@base_artifacts_dir, 'artifact_registry.yaml')
        
        registry = if File.exist?(registry_file)
                     YAML.load_file(registry_file) || {}
                   else
                     {}
                   end
        
        registry[environment_name] ||= []
        registry[environment_name] << {
          timestamp: File.basename(artifact_dir),
          path: artifact_dir,
          success: collection_result[:success],
          artifact_types: collection_result[:artifacts]&.keys || [],
          total_size: collection_result[:total_size],
          created_at: Time.now.iso8601
        }
        
        # Keep only last 100 entries per environment
        registry[environment_name] = registry[environment_name].last(100)
        
        File.write(registry_file, YAML.dump(registry))
      end
      
      def get_environment_artifact_summary(environment_name)
        env_dir = File.join(@base_artifacts_dir, environment_name)
        return nil unless File.exist?(env_dir)
        
        collections = get_artifact_history(environment_name)
        total_size = calculate_directory_size(env_dir)
        
        {
          environment_name: environment_name,
          total_collections: collections.size,
          total_size: total_size,
          latest_collection: collections.first,
          oldest_collection: collections.last,
          failed_collections: collections.count { |c| !c[:success] },
          average_collection_size: collections.empty? ? 0 : total_size / collections.size
        }
      end
      
      def get_global_artifact_summary
        total_size = calculate_total_artifact_size
        total_collections = 0
        environment_count = 0
        
        Dir.glob(File.join(@base_artifacts_dir, '*')).each do |env_dir|
          next unless File.directory?(env_dir)
          next if File.basename(env_dir) == 'sessions'
          
          environment_count += 1
          collections = get_artifact_history(File.basename(env_dir))
          total_collections += collections.size
        end
        
        {
          total_environments: environment_count,
          total_collections: total_collections,
          total_size: total_size,
          average_collections_per_env: environment_count > 0 ? total_collections / environment_count : 0,
          storage_usage_percent: (total_size.to_f / (ARTIFACT_STORAGE_LIMIT_GB * 1024 * 1024 * 1024) * 100).round(2)
        }
      end
      
      def get_all_artifact_collections
        collections = []
        
        Dir.glob(File.join(@base_artifacts_dir, '*', '*')).each do |collection_dir|
          next unless File.directory?(collection_dir)
          next if File.basename(File.dirname(collection_dir)) == 'sessions'
          
          metadata_file = File.join(collection_dir, 'collection_metadata.yaml')
          if File.exist?(metadata_file)
            metadata = YAML.load_file(metadata_file)
            collections << {
              path: collection_dir,
              environment: File.basename(File.dirname(collection_dir)),
              timestamp: metadata[:timestamp] || File.mtime(collection_dir),
              size: calculate_directory_size(collection_dir)
            }
          end
        end
        
        collections
      end
      
      def cleanup_directory_by_age(directory, max_age_days)
        cutoff_time = Time.now - (max_age_days * 24 * 3600)
        cleaned_count = 0
        size_freed = 0
        
        Dir.glob(File.join(directory, '*')).each do |collection_dir|
          next unless File.directory?(collection_dir)
          
          if File.mtime(collection_dir) < cutoff_time
            dir_size = calculate_directory_size(collection_dir)
            FileUtils.rm_rf(collection_dir)
            cleaned_count += 1
            size_freed += dir_size
            log_debug "Removed old artifact collection: #{collection_dir}"
          end
        end
        
        [cleaned_count, size_freed]
      end
      
      def calculate_total_artifact_size
        return 0 unless File.exist?(@base_artifacts_dir)
        calculate_directory_size(@base_artifacts_dir)
      end
      
      def calculate_directory_size(path)
        return 0 unless File.exist?(path)
        
        total_size = 0
        Find.find(path) do |file_path|
          total_size += File.size(file_path) if File.file?(file_path)
        end
        total_size
      end
      
      def format_size(bytes)
        units = %w[B KB MB GB TB]
        size = bytes.to_f
        unit_index = 0
        
        while size >= 1024.0 && unit_index < units.length - 1
          size /= 1024.0
          unit_index += 1
        end
        
        "#{size.round(2)} #{units[unit_index]}"
      end
      
      def create_session_summary(test_session, session_result, session_dir)
        FileUtils.mkdir_p(session_dir)
        
        summary = {
          session_id: test_session.session_id,
          environments: test_session.environments.keys,
          session_result: session_result,
          created_at: Time.now.iso8601
        }
        
        summary_file = File.join(session_dir, 'session_summary.yaml')
        File.write(summary_file, YAML.dump(summary))
        
        summary_file
      end
      
      def create_session_report(test_session, session_artifacts, session_dir)
        report_file = File.join(session_dir, 'session_report.html')
        
        html_content = generate_session_report_html(test_session, session_artifacts)
        File.write(report_file, html_content)
        
        report_file
      end
      
      def compare_collection_metadata(dir1, dir2)
        metadata1_file = File.join(dir1, 'collection_metadata.yaml')
        metadata2_file = File.join(dir2, 'collection_metadata.yaml')
        
        return { error: "Metadata files not found" } unless File.exist?(metadata1_file) && File.exist?(metadata2_file)
        
        metadata1 = YAML.load_file(metadata1_file)
        metadata2 = YAML.load_file(metadata2_file)
        
        {
          duration_diff: (metadata2[:duration] || 0) - (metadata1[:duration] || 0),
          size_diff: (metadata2[:total_size] || 0) - (metadata1[:total_size] || 0),
          success_change: metadata1[:success] != metadata2[:success],
          artifact_types_diff: (metadata2[:artifacts]&.keys || []) - (metadata1[:artifacts]&.keys || [])
        }
      end
      
      def compare_log_files(dir1, dir2)
        logs1_dir = File.join(dir1, 'logs')
        logs2_dir = File.join(dir2, 'logs')
        
        return { error: "Log directories not found" } unless File.exist?(logs1_dir) && File.exist?(logs2_dir)
        
        # Simple comparison - could be enhanced with actual diff analysis
        {
          logs1_count: Dir.glob(File.join(logs1_dir, '*')).size,
          logs2_count: Dir.glob(File.join(logs2_dir, '*')).size
        }
      end
      
      def compare_system_state(dir1, dir2)
        state1_dir = File.join(dir1, 'system_state')
        state2_dir = File.join(dir2, 'system_state')
        
        return { error: "System state directories not found" } unless File.exist?(state1_dir) && File.exist?(state2_dir)
        
        # Basic comparison
        {
          state1_files: Dir.glob(File.join(state1_dir, '*')).size,
          state2_files: Dir.glob(File.join(state2_dir, '*')).size
        }
      end
      
      def generate_comparison_summary(differences)
        summary = {
          metadata_changed: differences[:metadata] && !differences[:metadata][:success_change].nil?,
          log_count_changed: differences[:logs] && differences[:logs][:logs1_count] != differences[:logs][:logs2_count],
          system_state_changed: differences[:system_state] && differences[:system_state][:state1_files] != differences[:system_state][:state2_files]
        }
        
        summary[:overall_significant_changes] = summary.values.any?
        summary
      end
      
      def create_html_report(report_data, environment_name)
        report_file = if environment_name
                        File.join(@base_artifacts_dir, 'reports', "#{environment_name}_report.html")
                      else
                        File.join(@base_artifacts_dir, 'reports', 'global_report.html')
                      end
        
        html_content = generate_report_html(report_data, environment_name)
        File.write(report_file, html_content)
        
        log_info "HTML report created: #{report_file}"
        report_file
      end
      
      def create_json_report(report_data, environment_name)
        report_file = if environment_name
                        File.join(@base_artifacts_dir, 'reports', "#{environment_name}_report.json")
                      else
                        File.join(@base_artifacts_dir, 'reports', 'global_report.json')
                      end
        
        File.write(report_file, JSON.pretty_generate(report_data))
        
        log_info "JSON report created: #{report_file}"
        report_file
      end
      
      def create_yaml_report(report_data, environment_name)
        report_file = if environment_name
                        File.join(@base_artifacts_dir, 'reports', "#{environment_name}_report.yaml")
                      else
                        File.join(@base_artifacts_dir, 'reports', 'global_report.yaml')
                      end
        
        File.write(report_file, YAML.dump(report_data))
        
        log_info "YAML report created: #{report_file}"
        report_file
      end
      
      def generate_report_html(report_data, environment_name)
        title = environment_name ? "Artifact Report - #{environment_name}" : "Global Artifact Report"
        
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>#{title}</title>
            <style>
              body { font-family: Arial, sans-serif; margin: 20px; }
              .header { background: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
              .section { margin: 20px 0; }
              .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; }
              .summary-card { background: #fafafa; padding: 15px; border-radius: 5px; border-left: 4px solid #007acc; }
              table { border-collapse: collapse; width: 100%; margin: 15px 0; }
              th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
              th { background-color: #f2f2f2; }
              .environment-section { margin: 30px 0; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
            </style>
          </head>
          <body>
            <div class="header">
              <h1>#{title}</h1>
              <p>Generated: #{report_data[:generated_at]}</p>
            </div>
            
            #{generate_global_summary_html(report_data[:global_summary])}
            #{generate_environments_html(report_data[:environments])}
          </body>
          </html>
        HTML
      end
      
      def generate_session_report_html(test_session, session_artifacts)
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>Test Session Artifacts - #{test_session.session_id}</title>
            <style>
              body { font-family: Arial, sans-serif; margin: 20px; }
              .header { background: #f5f5f5; padding: 15px; border-radius: 5px; }
              .environment { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
            </style>
          </head>
          <body>
            <div class="header">
              <h1>Test Session Artifacts</h1>
              <p><strong>Session ID:</strong> #{test_session.session_id}</p>
              <p><strong>Environments:</strong> #{test_session.environments.keys.join(', ')}</p>
            </div>
            
            #{session_artifacts.map { |env, artifacts| generate_environment_artifacts_html(env, artifacts) }.join}
          </body>
          </html>
        HTML
      end
      
      def generate_global_summary_html(summary)
        <<~HTML
          <div class="section">
            <h2>Global Summary</h2>
            <div class="summary-grid">
              <div class="summary-card">
                <h3>Environments</h3>
                <p>#{summary[:total_environments]}</p>
              </div>
              <div class="summary-card">
                <h3>Total Collections</h3>
                <p>#{summary[:total_collections]}</p>
              </div>
              <div class="summary-card">
                <h3>Storage Usage</h3>
                <p>#{format_size(summary[:total_size])} (#{summary[:storage_usage_percent]}%)</p>
              </div>
            </div>
          </div>
        HTML
      end
      
      def generate_environments_html(environments)
        return "" if environments.empty?
        
        html = "<div class='section'><h2>Environment Details</h2>"
        
        environments.each do |env_name, env_summary|
          html += <<~HTML
            <div class="environment-section">
              <h3>#{env_name}</h3>
              <p><strong>Collections:</strong> #{env_summary[:total_collections]}</p>
              <p><strong>Total Size:</strong> #{format_size(env_summary[:total_size])}</p>
              <p><strong>Failed Collections:</strong> #{env_summary[:failed_collections]}</p>
            </div>
          HTML
        end
        
        html += "</div>"
      end
      
      def generate_environment_artifacts_html(env_name, artifacts)
        return "" if artifacts.is_a?(String) # Skip if it's just a path
        
        <<~HTML
          <div class="environment">
            <h2>#{env_name}</h2>
            <p><strong>Artifact Types:</strong> #{artifacts[:artifacts]&.keys&.join(', ') || 'None'}</p>
            <p><strong>Collection Status:</strong> #{artifacts[:success] ? 'Success' : 'Failed'}</p>
            <p><strong>Total Size:</strong> #{format_size(artifacts[:total_size] || 0)}</p>
          </div>
        HTML
      end
    end
  end
end