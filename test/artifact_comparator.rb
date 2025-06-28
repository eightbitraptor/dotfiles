require 'diffy'
require 'yaml'
require 'json'

module MitamaeTest
  class ArtifactComparator
    include Logging
    
    DIFF_CONTEXT_LINES = 3
    MAX_DIFF_SIZE = 1024 * 1024 # 1MB
    
    attr_reader :repository
    
    def initialize(repository)
      @repository = repository
    end
    
    def compare(collection1, collection2)
      log_info "Comparing collections: #{collection1[:session_id]} vs #{collection2[:session_id]}"
      
      comparison = {
        collection1: collection_summary(collection1),
        collection2: collection_summary(collection2),
        compared_at: Time.now.iso8601,
        differences: {},
        summary: {},
        recommendations: []
      }
      
      # Compare collection metadata
      comparison[:differences][:metadata] = compare_metadata(collection1, collection2)
      
      # Compare artifacts by type
      comparison[:differences][:artifacts] = compare_artifacts_by_type(collection1, collection2)
      
      # Generate detailed comparison summary
      comparison[:summary] = generate_comparison_summary(comparison[:differences])
      
      # Generate recommendations
      comparison[:recommendations] = generate_recommendations(comparison)
      
      log_info "Collection comparison completed"
      comparison
    end
    
    def compare_artifacts(artifact1, artifact2)
      return { error: "Artifacts have different types" } if artifact1[:artifact_type] != artifact2[:artifact_type]
      
      comparison = {
        artifact1: artifact_summary(artifact1),
        artifact2: artifact_summary(artifact2),
        type: artifact1[:artifact_type],
        differences: {}
      }
      
      # Size comparison
      comparison[:differences][:size] = {
        artifact1_size: artifact1[:file_size],
        artifact2_size: artifact2[:file_size],
        size_diff: artifact2[:file_size] - artifact1[:file_size],
        size_change_percent: calculate_percentage_change(artifact1[:file_size], artifact2[:file_size])
      }
      
      # Content comparison (if both files exist and are reasonable size)
      if should_compare_content?(artifact1, artifact2)
        comparison[:differences][:content] = compare_artifact_content(artifact1, artifact2)
      end
      
      # Hash comparison
      if artifact1[:content_hash] && artifact2[:content_hash]
        comparison[:differences][:hash_match] = artifact1[:content_hash] == artifact2[:content_hash]
      end
      
      comparison
    end
    
    def compare_logs(collection1, collection2)
      log1_artifacts = filter_artifacts_by_type(collection1[:artifacts], 'logs')
      log2_artifacts = filter_artifacts_by_type(collection2[:artifacts], 'logs')
      
      comparison = {
        collection1_logs: log1_artifacts.size,
        collection2_logs: log2_artifacts.size,
        log_differences: {},
        new_logs: [],
        missing_logs: [],
        changed_logs: []
      }
      
      # Find common log names
      log1_names = log1_artifacts.map { |a| a[:name] }.to_set
      log2_names = log2_artifacts.map { |a| a[:name] }.to_set
      
      common_logs = log1_names & log2_names
      comparison[:new_logs] = (log2_names - log1_names).to_a
      comparison[:missing_logs] = (log1_names - log2_names).to_a
      
      # Compare common logs
      common_logs.each do |log_name|
        log1 = log1_artifacts.find { |a| a[:name] == log_name }
        log2 = log2_artifacts.find { |a| a[:name] == log_name }
        
        log_comparison = compare_artifacts(log1, log2)
        
        if has_significant_changes?(log_comparison)
          comparison[:changed_logs] << {
            name: log_name,
            comparison: log_comparison
          }
        end
        
        comparison[:log_differences][log_name] = log_comparison
      end
      
      comparison
    end
    
    def compare_system_state(collection1, collection2)
      state1_artifacts = filter_artifacts_by_type(collection1[:artifacts], 'system_state')
      state2_artifacts = filter_artifacts_by_type(collection2[:artifacts], 'system_state')
      
      comparison = {
        state_files: {},
        significant_changes: [],
        process_changes: nil,
        memory_changes: nil,
        network_changes: nil
      }
      
      # Compare specific system state files
      %w[processes memory network disk].each do |state_type|
        file1 = state1_artifacts.find { |a| a[:name].include?(state_type) }
        file2 = state2_artifacts.find { |a| a[:name].include?(state_type) }
        
        if file1 && file2
          state_comparison = compare_artifacts(file1, file2)
          comparison[:state_files][state_type] = state_comparison
          
          # Extract specific insights
          case state_type
          when 'processes'
            comparison[:process_changes] = analyze_process_changes(file1, file2)
          when 'memory'
            comparison[:memory_changes] = analyze_memory_changes(file1, file2)
          when 'network'
            comparison[:network_changes] = analyze_network_changes(file1, file2)
          end
        end
      end
      
      comparison
    end
    
    def compare_configurations(collection1, collection2)
      config1_artifacts = filter_artifacts_by_type(collection1[:artifacts], 'config_files')
      config2_artifacts = filter_artifacts_by_type(collection2[:artifacts], 'config_files')
      
      comparison = {
        config_differences: {},
        new_configs: [],
        missing_configs: [],
        changed_configs: []
      }
      
      config1_names = config1_artifacts.map { |a| a[:name] }.to_set
      config2_names = config2_artifacts.map { |a| a[:name] }.to_set
      
      common_configs = config1_names & config2_names
      comparison[:new_configs] = (config2_names - config1_names).to_a
      comparison[:missing_configs] = (config1_names - config2_names).to_a
      
      common_configs.each do |config_name|
        config1 = config1_artifacts.find { |a| a[:name] == config_name }
        config2 = config2_artifacts.find { |a| a[:name] == config_name }
        
        config_comparison = compare_artifacts(config1, config2)
        comparison[:config_differences][config_name] = config_comparison
        
        if has_significant_changes?(config_comparison)
          comparison[:changed_configs] << {
            name: config_name,
            comparison: config_comparison
          }
        end
      end
      
      comparison
    end
    
    def generate_diff_report(artifact1, artifact2, format = :html)
      return nil unless should_compare_content?(artifact1, artifact2)
      
      content1 = @repository.get_artifact_content(artifact1[:id])
      content2 = @repository.get_artifact_content(artifact2[:id])
      
      return nil unless content1 && content2
      
      case format
      when :html
        generate_html_diff(content1, content2, artifact1[:name])
      when :unified
        generate_unified_diff(content1, content2, artifact1[:name])
      when :context
        generate_context_diff(content1, content2, artifact1[:name])
      else
        generate_unified_diff(content1, content2, artifact1[:name])
      end
    end
    
    def find_similar_artifacts(target_artifact, collection, similarity_threshold = 0.8)
      similar_artifacts = []
      
      collection[:artifacts].each do |artifact|
        next if artifact[:id] == target_artifact[:id]
        next if artifact[:artifact_type] != target_artifact[:artifact_type]
        
        similarity = calculate_artifact_similarity(target_artifact, artifact)
        
        if similarity >= similarity_threshold
          similar_artifacts << {
            artifact: artifact,
            similarity: similarity
          }
        end
      end
      
      similar_artifacts.sort_by { |sa| -sa[:similarity] }
    end
    
    def analyze_trends(collections)
      return {} if collections.size < 2
      
      trends = {
        size_trend: analyze_size_trend(collections),
        duration_trend: analyze_duration_trend(collections),
        success_rate_trend: analyze_success_rate_trend(collections),
        artifact_count_trend: analyze_artifact_count_trend(collections),
        error_patterns: analyze_error_patterns(collections)
      }
      
      trends[:overall_assessment] = assess_overall_trends(trends)
      trends
    end
    
    private
    
    def collection_summary(collection)
      {
        id: collection[:id],
        session_id: collection[:session_id],
        environment_name: collection[:environment_name],
        success: collection[:success],
        duration: collection[:duration],
        total_size: collection[:total_size],
        artifact_count: collection[:artifact_count],
        created_at: collection[:created_at]
      }
    end
    
    def artifact_summary(artifact)
      {
        id: artifact[:id],
        name: artifact[:name],
        type: artifact[:artifact_type],
        size: artifact[:file_size],
        content_type: artifact[:content_type]
      }
    end
    
    def compare_metadata(collection1, collection2)
      {
        environment_match: collection1[:environment_name] == collection2[:environment_name],
        success_change: collection1[:success] != collection2[:success],
        duration_diff: (collection2[:duration] || 0) - (collection1[:duration] || 0),
        size_diff: (collection2[:total_size] || 0) - (collection1[:total_size] || 0),
        artifact_count_diff: (collection2[:artifact_count] || 0) - (collection1[:artifact_count] || 0),
        time_diff_hours: time_difference_hours(collection1[:created_at], collection2[:created_at])
      }
    end
    
    def compare_artifacts_by_type(collection1, collection2)
      artifacts1_by_type = group_artifacts_by_type(collection1[:artifacts])
      artifacts2_by_type = group_artifacts_by_type(collection2[:artifacts])
      
      all_types = (artifacts1_by_type.keys + artifacts2_by_type.keys).uniq
      type_comparisons = {}
      
      all_types.each do |type|
        type_artifacts1 = artifacts1_by_type[type] || []
        type_artifacts2 = artifacts2_by_type[type] || []
        
        type_comparisons[type] = {
          collection1_count: type_artifacts1.size,
          collection2_count: type_artifacts2.size,
          count_diff: type_artifacts2.size - type_artifacts1.size,
          new_artifacts: find_new_artifacts(type_artifacts1, type_artifacts2),
          missing_artifacts: find_missing_artifacts(type_artifacts1, type_artifacts2),
          changed_artifacts: find_changed_artifacts(type_artifacts1, type_artifacts2)
        }
      end
      
      type_comparisons
    end
    
    def should_compare_content?(artifact1, artifact2)
      return false unless artifact1[:content_type]&.start_with?('text/') || 
                         %w[application/json application/yaml].include?(artifact1[:content_type])
      return false if artifact1[:file_size] > MAX_DIFF_SIZE || artifact2[:file_size] > MAX_DIFF_SIZE
      return false unless File.exist?(artifact1[:file_path]) && File.exist?(artifact2[:file_path])
      
      true
    end
    
    def compare_artifact_content(artifact1, artifact2)
      content1 = @repository.get_artifact_content(artifact1[:id])
      content2 = @repository.get_artifact_content(artifact2[:id])
      
      return { error: "Could not read artifact content" } unless content1 && content2
      
      # Generate diff
      diff = Diffy::Diff.new(content1, content2, context: DIFF_CONTEXT_LINES)
      
      {
        has_changes: !diff.to_s.empty?,
        line_changes: count_line_changes(diff),
        diff_preview: diff.to_s.lines.first(20).join, # First 20 lines of diff
        full_diff_available: true
      }
    end
    
    def generate_html_diff(content1, content2, filename)
      diff = Diffy::Diff.new(content1, content2, include_plus_and_minus_in_html: true)
      
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Diff: #{filename}</title>
          <style>
            body { font-family: monospace; font-size: 12px; }
            .diff { border: 1px solid #ccc; }
            .diff ins { background: #d4edda; text-decoration: none; }
            .diff del { background: #f8d7da; text-decoration: none; }
            .diff .unchanged { color: #666; }
          </style>
        </head>
        <body>
          <h1>Diff: #{filename}</h1>
          <div class="diff">
            #{diff.to_s(:html)}
          </div>
        </body>
        </html>
      HTML
    end
    
    def generate_unified_diff(content1, content2, filename)
      Diffy::Diff.new(content1, content2, source: "#{filename}.old", destination: "#{filename}.new").to_s(:text)
    end
    
    def generate_context_diff(content1, content2, filename)
      Diffy::Diff.new(content1, content2, source: "#{filename}.old", destination: "#{filename}.new").to_s(:context)
    end
    
    def calculate_artifact_similarity(artifact1, artifact2)
      # Simple similarity based on name and size
      name_similarity = string_similarity(artifact1[:name], artifact2[:name])
      
      size_diff = (artifact1[:file_size] - artifact2[:file_size]).abs
      max_size = [artifact1[:file_size], artifact2[:file_size]].max
      size_similarity = max_size > 0 ? 1.0 - (size_diff.to_f / max_size) : 1.0
      
      # Weight name similarity more heavily
      (name_similarity * 0.7) + (size_similarity * 0.3)
    end
    
    def string_similarity(str1, str2)
      # Simple Levenshtein distance-based similarity
      return 1.0 if str1 == str2
      return 0.0 if str1.empty? || str2.empty?
      
      longer = str1.length > str2.length ? str1 : str2
      shorter = str1.length > str2.length ? str2 : str1
      
      distance = levenshtein_distance(longer, shorter)
      similarity = (longer.length - distance).to_f / longer.length
      
      [similarity, 0.0].max
    end
    
    def levenshtein_distance(str1, str2)
      matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1, 0) }
      
      (0..str1.length).each { |i| matrix[i][0] = i }
      (0..str2.length).each { |j| matrix[0][j] = j }
      
      (1..str1.length).each do |i|
        (1..str2.length).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          matrix[i][j] = [
            matrix[i - 1][j] + 1,     # deletion
            matrix[i][j - 1] + 1,     # insertion
            matrix[i - 1][j - 1] + cost # substitution
          ].min
        end
      end
      
      matrix[str1.length][str2.length]
    end
    
    def filter_artifacts_by_type(artifacts, type)
      artifacts.select { |a| a[:artifact_type] == type }
    end
    
    def group_artifacts_by_type(artifacts)
      artifacts.group_by { |a| a[:artifact_type] }
    end
    
    def find_new_artifacts(artifacts1, artifacts2)
      names1 = artifacts1.map { |a| a[:name] }.to_set
      artifacts2.select { |a| !names1.include?(a[:name]) }.map { |a| a[:name] }
    end
    
    def find_missing_artifacts(artifacts1, artifacts2)
      names2 = artifacts2.map { |a| a[:name] }.to_set
      artifacts1.select { |a| !names2.include?(a[:name]) }.map { |a| a[:name] }
    end
    
    def find_changed_artifacts(artifacts1, artifacts2)
      names1 = artifacts1.map { |a| [a[:name], a] }.to_h
      names2 = artifacts2.map { |a| [a[:name], a] }.to_h
      
      common_names = names1.keys & names2.keys
      changed = []
      
      common_names.each do |name|
        artifact1 = names1[name]
        artifact2 = names2[name]
        
        if artifact1[:content_hash] != artifact2[:content_hash] || 
           artifact1[:file_size] != artifact2[:file_size]
          changed << {
            name: name,
            size_change: artifact2[:file_size] - artifact1[:file_size],
            hash_changed: artifact1[:content_hash] != artifact2[:content_hash]
          }
        end
      end
      
      changed
    end
    
    def has_significant_changes?(comparison)
      return true if comparison.dig(:differences, :content, :has_changes)
      return true if comparison.dig(:differences, :size, :size_diff).to_i.abs > 1024 # 1KB threshold
      
      false
    end
    
    def count_line_changes(diff)
      additions = 0
      deletions = 0
      
      diff.each do |line|
        case line[0]
        when '+'
          additions += 1
        when '-'
          deletions += 1
        end
      end
      
      { additions: additions, deletions: deletions, total: additions + deletions }
    end
    
    def analyze_process_changes(file1, file2)
      # This would parse process lists and identify changes
      # For now, return basic file comparison
      {
        processes_changed: file1[:content_hash] != file2[:content_hash],
        size_change: file2[:file_size] - file1[:file_size]
      }
    end
    
    def analyze_memory_changes(file1, file2)
      # This would parse memory information and calculate changes
      {
        memory_changed: file1[:content_hash] != file2[:content_hash],
        size_change: file2[:file_size] - file1[:file_size]
      }
    end
    
    def analyze_network_changes(file1, file2)
      # This would parse network configuration and identify changes
      {
        network_changed: file1[:content_hash] != file2[:content_hash],
        size_change: file2[:file_size] - file1[:file_size]
      }
    end
    
    def calculate_percentage_change(old_value, new_value)
      return 0 if old_value == 0 && new_value == 0
      return 100 if old_value == 0
      
      ((new_value - old_value).to_f / old_value * 100).round(2)
    end
    
    def time_difference_hours(time1, time2)
      return 0 unless time1 && time2
      
      t1 = Time.parse(time1)
      t2 = Time.parse(time2)
      
      ((t2 - t1) / 3600).round(2)
    end
    
    def generate_comparison_summary(differences)
      summary = {
        has_metadata_changes: has_metadata_changes?(differences[:metadata]),
        has_artifact_changes: has_artifact_changes?(differences[:artifacts]),
        significant_changes: [],
        change_categories: []
      }
      
      # Categorize changes
      if differences[:metadata][:success_change]
        summary[:significant_changes] << "Test result changed (success/failure)"
        summary[:change_categories] << "test_result"
      end
      
      if differences[:metadata][:duration_diff].abs > 30 # 30 second threshold
        summary[:significant_changes] << "Execution duration changed significantly"
        summary[:change_categories] << "performance"
      end
      
      if differences[:metadata][:size_diff].abs > 1024 * 1024 # 1MB threshold
        summary[:significant_changes] << "Total artifact size changed significantly"
        summary[:change_categories] << "size"
      end
      
      # Check for new/missing artifacts
      differences[:artifacts].each do |type, type_diff|
        if type_diff[:new_artifacts].any?
          summary[:significant_changes] << "New #{type} artifacts found"
          summary[:change_categories] << "new_artifacts"
        end
        
        if type_diff[:missing_artifacts].any?
          summary[:significant_changes] << "Missing #{type} artifacts"
          summary[:change_categories] << "missing_artifacts"
        end
        
        if type_diff[:changed_artifacts].any?
          summary[:significant_changes] << "Changed #{type} artifacts"
          summary[:change_categories] << "changed_artifacts"
        end
      end
      
      summary[:overall_significance] = assess_overall_significance(summary)
      summary
    end
    
    def generate_recommendations(comparison)
      recommendations = []
      
      summary = comparison[:summary]
      
      if summary[:change_categories].include?("test_result")
        recommendations << {
          type: "investigation",
          priority: "high",
          message: "Test result changed - investigate logs and error traces for root cause"
        }
      end
      
      if summary[:change_categories].include?("performance")
        recommendations << {
          type: "performance",
          priority: "medium", 
          message: "Significant performance change detected - review system state and resource usage"
        }
      end
      
      if summary[:change_categories].include?("new_artifacts")
        recommendations << {
          type: "analysis",
          priority: "low",
          message: "New artifacts detected - review for unexpected outputs or new functionality"
        }
      end
      
      if summary[:change_categories].include?("missing_artifacts")
        recommendations << {
          type: "investigation",
          priority: "medium",
          message: "Missing artifacts detected - check for environment or configuration issues"
        }
      end
      
      recommendations
    end
    
    def has_metadata_changes?(metadata_diff)
      metadata_diff[:success_change] ||
        metadata_diff[:duration_diff].abs > 10 ||
        metadata_diff[:size_diff].abs > 1024
    end
    
    def has_artifact_changes?(artifacts_diff)
      artifacts_diff.any? do |type, type_diff|
        type_diff[:new_artifacts].any? ||
          type_diff[:missing_artifacts].any? ||
          type_diff[:changed_artifacts].any?
      end
    end
    
    def assess_overall_significance(summary)
      return "high" if summary[:change_categories].include?("test_result")
      return "medium" if summary[:change_categories].size >= 3
      return "low" if summary[:significant_changes].any?
      
      "minimal"
    end
    
    # Trend analysis methods
    
    def analyze_size_trend(collections)
      sizes = collections.map { |c| c[:total_size] || 0 }
      calculate_trend(sizes, "Total Size")
    end
    
    def analyze_duration_trend(collections)
      durations = collections.map { |c| c[:duration] || 0 }
      calculate_trend(durations, "Duration")
    end
    
    def analyze_success_rate_trend(collections)
      success_rate = collections.count { |c| c[:success] }.to_f / collections.size * 100
      { current_success_rate: success_rate.round(2) }
    end
    
    def analyze_artifact_count_trend(collections)
      counts = collections.map { |c| c[:artifact_count] || 0 }
      calculate_trend(counts, "Artifact Count")
    end
    
    def analyze_error_patterns(collections)
      failed_collections = collections.select { |c| !c[:success] }
      
      {
        failure_rate: (failed_collections.size.to_f / collections.size * 100).round(2),
        recent_failures: failed_collections.size
      }
    end
    
    def calculate_trend(values, metric_name)
      return {} if values.size < 2
      
      # Simple linear trend calculation
      n = values.size
      x_sum = (0...n).sum
      y_sum = values.sum
      xy_sum = (0...n).map { |i| i * values[i] }.sum
      x2_sum = (0...n).map { |i| i * i }.sum
      
      slope = (n * xy_sum - x_sum * y_sum).to_f / (n * x2_sum - x_sum * x_sum)
      
      trend_direction = if slope > 0.1
                         "increasing"
                       elsif slope < -0.1
                         "decreasing"
                       else
                         "stable"
                       end
      
      {
        metric: metric_name,
        trend: trend_direction,
        slope: slope.round(4),
        current_value: values.last,
        min_value: values.min,
        max_value: values.max,
        average: (values.sum.to_f / values.size).round(2)
      }
    end
    
    def assess_overall_trends(trends)
      concerns = []
      
      if trends[:success_rate_trend][:current_success_rate] < 80
        concerns << "Low success rate"
      end
      
      if trends[:duration_trend][:trend] == "increasing"
        concerns << "Performance degradation"
      end
      
      if trends[:size_trend][:trend] == "increasing"
        concerns << "Increasing artifact sizes"
      end
      
      if concerns.any?
        { status: "concerning", issues: concerns }
      else
        { status: "healthy", issues: [] }
      end
    end
  end
end