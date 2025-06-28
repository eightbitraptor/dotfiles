require 'fileutils'
require 'yaml'
require 'json'
require 'digest'
require 'sqlite3'
require 'find'

module MitamaeTest
  class ArtifactRepository
    include Logging
    include ErrorHandling
    
    SCHEMA_VERSION = 1
    INDEX_BATCH_SIZE = 100
    SEARCH_RESULT_LIMIT = 1000
    
    attr_reader :repository_path, :db_path, :config
    
    def initialize(repository_path, config = {})
      @repository_path = File.expand_path(repository_path)
      @config = default_config.merge(config)
      @db_path = File.join(@repository_path, 'artifacts.db')
      @db = nil
      
      initialize_repository
      ensure_database_connection
    end
    
    def store_artifact_collection(collection_metadata, artifact_paths)
      log_info "Storing artifact collection: #{collection_metadata[:session_id]}"
      
      transaction do
        # Store collection metadata
        collection_id = insert_collection(collection_metadata)
        
        # Store individual artifacts
        artifact_paths.each do |artifact_type, type_artifacts|
          next unless type_artifacts.is_a?(Hash)
          
          type_artifacts.each do |artifact_name, artifact_path|
            next unless File.exist?(artifact_path)
            
            artifact_metadata = analyze_artifact(artifact_path, artifact_type, artifact_name)
            insert_artifact(collection_id, artifact_metadata)
          end
        end
        
        # Update collection statistics
        update_collection_stats(collection_id)
        
        # Index artifact content for search
        index_artifact_content(collection_id) if @config[:enable_content_indexing]
        
        log_info "Artifact collection stored: #{collection_id}"
        collection_id
      end
    end
    
    def search_artifacts(query, filters = {})
      log_debug "Searching artifacts: #{query}"
      
      conditions = build_search_conditions(query, filters)
      
      sql = <<~SQL
        SELECT DISTINCT c.*, a.* 
        FROM collections c
        JOIN artifacts a ON c.id = a.collection_id
        #{build_joins(filters)}
        WHERE #{conditions[:where]}
        ORDER BY c.created_at DESC, a.artifact_type, a.name
        LIMIT #{SEARCH_RESULT_LIMIT}
      SQL
      
      results = @db.execute(sql, conditions[:params])
      format_search_results(results)
    end
    
    def find_collections(filters = {})
      conditions = build_collection_filters(filters)
      
      sql = <<~SQL
        SELECT * FROM collections 
        WHERE #{conditions[:where]}
        ORDER BY created_at DESC
      SQL
      
      @db.execute(sql, conditions[:params]).map { |row| format_collection(row) }
    end
    
    def find_artifacts(collection_id = nil, filters = {})
      conditions = build_artifact_filters(filters)
      where_clauses = [conditions[:where]]
      params = conditions[:params]
      
      if collection_id
        where_clauses << "collection_id = ?"
        params << collection_id
      end
      
      sql = <<~SQL
        SELECT * FROM artifacts 
        WHERE #{where_clauses.reject(&:empty?).join(' AND ')}
        ORDER BY artifact_type, name
      SQL
      
      @db.execute(sql, params).map { |row| format_artifact(row) }
    end
    
    def get_collection(collection_id)
      row = @db.get_first_row("SELECT * FROM collections WHERE id = ?", collection_id)
      return nil unless row
      
      collection = format_collection(row)
      collection[:artifacts] = find_artifacts(collection_id)
      collection
    end
    
    def get_artifact(artifact_id)
      row = @db.get_first_row("SELECT * FROM artifacts WHERE id = ?", artifact_id)
      return nil unless row
      
      format_artifact(row)
    end
    
    def compare_collections(collection_id1, collection_id2)
      collection1 = get_collection(collection_id1)
      collection2 = get_collection(collection_id2)
      
      raise TestError, "Collection not found: #{collection_id1}" unless collection1
      raise TestError, "Collection not found: #{collection_id2}" unless collection2
      
      comparison = ArtifactComparator.new(self).compare(collection1, collection2)
      
      # Store comparison result
      comparison_id = store_comparison(collection_id1, collection_id2, comparison)
      comparison[:comparison_id] = comparison_id
      
      comparison
    end
    
    def get_artifact_content(artifact_id, format = :raw)
      artifact = get_artifact(artifact_id)
      return nil unless artifact && File.exist?(artifact[:file_path])
      
      case format
      when :raw
        File.read(artifact[:file_path])
      when :lines
        File.readlines(artifact[:file_path])
      when :json
        JSON.parse(File.read(artifact[:file_path])) if artifact[:content_type] == 'application/json'
      when :yaml
        YAML.load_file(artifact[:file_path]) if artifact[:content_type] == 'application/yaml'
      else
        File.read(artifact[:file_path])
      end
    rescue => e
      log_error "Failed to read artifact content: #{e.message}"
      nil
    end
    
    def create_artifact_view(name, query, filters = {})
      view_id = SecureRandom.hex(8)
      
      view_metadata = {
        id: view_id,
        name: name,
        query: query,
        filters: filters,
        created_at: Time.now.iso8601,
        created_by: ENV['USER'] || 'unknown'
      }
      
      @db.execute(
        "INSERT INTO artifact_views (id, name, query, filters, created_at, created_by) VALUES (?, ?, ?, ?, ?, ?)",
        view_id, name, query, JSON.dump(filters), view_metadata[:created_at], view_metadata[:created_by]
      )
      
      log_info "Created artifact view: #{name} (#{view_id})"
      view_metadata
    end
    
    def get_artifact_views
      @db.execute("SELECT * FROM artifact_views ORDER BY created_at DESC").map do |row|
        {
          id: row[0],
          name: row[1], 
          query: row[2],
          filters: JSON.parse(row[3] || '{}'),
          created_at: row[4],
          created_by: row[5]
        }
      end
    end
    
    def execute_artifact_view(view_id)
      view = @db.get_first_row("SELECT * FROM artifact_views WHERE id = ?", view_id)
      return nil unless view
      
      query = view[2]
      filters = JSON.parse(view[3] || '{}')
      
      search_artifacts(query, filters)
    end
    
    def tag_collection(collection_id, tags)
      tags = Array(tags).map(&:to_s).uniq
      
      # Remove existing tags
      @db.execute("DELETE FROM collection_tags WHERE collection_id = ?", collection_id)
      
      # Add new tags
      tags.each do |tag|
        @db.execute(
          "INSERT INTO collection_tags (collection_id, tag) VALUES (?, ?)",
          collection_id, tag
        )
      end
      
      log_debug "Tagged collection #{collection_id}: #{tags.join(', ')}"
    end
    
    def get_collection_tags(collection_id)
      @db.execute(
        "SELECT tag FROM collection_tags WHERE collection_id = ? ORDER BY tag",
        collection_id
      ).map { |row| row[0] }
    end
    
    def find_collections_by_tag(tag)
      @db.execute(
        "SELECT c.* FROM collections c JOIN collection_tags ct ON c.id = ct.collection_id WHERE ct.tag = ?",
        tag
      ).map { |row| format_collection(row) }
    end
    
    def get_all_tags
      @db.execute("SELECT DISTINCT tag FROM collection_tags ORDER BY tag").map { |row| row[0] }
    end
    
    def export_collection(collection_id, export_path, format = :tar_gz)
      collection = get_collection(collection_id)
      raise TestError, "Collection not found: #{collection_id}" unless collection
      
      export_name = "collection-#{collection_id}-#{Time.now.strftime('%Y%m%d-%H%M%S')}"
      temp_dir = File.join(Dir.tmpdir, "export-#{SecureRandom.hex(8)}")
      
      begin
        # Create temporary export directory
        FileUtils.mkdir_p(temp_dir)
        collection_dir = File.join(temp_dir, export_name)
        FileUtils.mkdir_p(collection_dir)
        
        # Copy artifacts
        collection[:artifacts].each do |artifact|
          next unless File.exist?(artifact[:file_path])
          
          relative_path = File.join(artifact[:artifact_type], artifact[:name])
          dest_path = File.join(collection_dir, relative_path)
          FileUtils.mkdir_p(File.dirname(dest_path))
          FileUtils.cp(artifact[:file_path], dest_path)
        end
        
        # Export metadata
        metadata_file = File.join(collection_dir, 'collection_metadata.yaml')
        File.write(metadata_file, YAML.dump(collection))
        
        # Create archive
        case format
        when :tar_gz
          archive_path = "#{export_path}/#{export_name}.tar.gz"
          system("tar -czf #{archive_path} -C #{temp_dir} #{export_name}")
        when :zip
          archive_path = "#{export_path}/#{export_name}.zip"
          system("cd #{temp_dir} && zip -r #{archive_path} #{export_name}")
        else
          # Just copy the directory
          archive_path = File.join(export_path, export_name)
          FileUtils.cp_r(collection_dir, archive_path)
        end
        
        log_info "Collection exported: #{archive_path}"
        archive_path
        
      ensure
        FileUtils.rm_rf(temp_dir) if File.exist?(temp_dir)
      end
    end
    
    def import_collection(import_path)
      log_info "Importing collection from: #{import_path}"
      
      temp_dir = File.join(Dir.tmpdir, "import-#{SecureRandom.hex(8)}")
      
      begin
        FileUtils.mkdir_p(temp_dir)
        
        # Extract archive if needed
        if import_path.end_with?('.tar.gz')
          system("tar -xzf #{import_path} -C #{temp_dir}")
        elsif import_path.end_with?('.zip')
          system("unzip #{import_path} -d #{temp_dir}")
        else
          FileUtils.cp_r(import_path, temp_dir)
        end
        
        # Find metadata file
        metadata_files = Dir.glob(File.join(temp_dir, '**/collection_metadata.yaml'))
        raise TestError, "No metadata file found in import" if metadata_files.empty?
        
        metadata_file = metadata_files.first
        collection_dir = File.dirname(metadata_file)
        
        # Load metadata
        metadata = YAML.load_file(metadata_file)
        
        # Generate new collection ID to avoid conflicts
        original_id = metadata[:session_id]
        new_id = SecureRandom.hex(8)
        metadata[:session_id] = new_id
        metadata[:imported_at] = Time.now.iso8601
        metadata[:imported_from] = import_path
        metadata[:original_id] = original_id
        
        # Store in repository
        artifact_paths = discover_import_artifacts(collection_dir)
        collection_id = store_artifact_collection(metadata, artifact_paths)
        
        log_info "Collection imported successfully: #{collection_id}"
        collection_id
        
      ensure
        FileUtils.rm_rf(temp_dir) if File.exist?(temp_dir)
      end
    end
    
    def cleanup_old_collections(max_age_days = 30)
      cutoff_date = (Time.now - (max_age_days * 24 * 3600)).iso8601
      
      old_collections = @db.execute(
        "SELECT id, environment_name FROM collections WHERE created_at < ?",
        cutoff_date
      )
      
      cleaned_count = 0
      
      old_collections.each do |collection|
        collection_id = collection[0]
        
        begin
          # Remove from database
          transaction do
            @db.execute("DELETE FROM artifacts WHERE collection_id = ?", collection_id)
            @db.execute("DELETE FROM collection_tags WHERE collection_id = ?", collection_id)
            @db.execute("DELETE FROM artifact_content WHERE collection_id = ?", collection_id)
            @db.execute("DELETE FROM collections WHERE id = ?", collection_id)
          end
          
          cleaned_count += 1
          
        rescue => e
          log_error "Failed to cleanup collection #{collection_id}: #{e.message}"
        end
      end
      
      # Vacuum database
      @db.execute("VACUUM")
      
      log_info "Cleaned up #{cleaned_count} old collections"
      cleaned_count
    end
    
    def get_repository_statistics
      stats = {}
      
      # Collection statistics
      stats[:collections] = @db.get_first_value("SELECT COUNT(*) FROM collections") || 0
      stats[:artifacts] = @db.get_first_value("SELECT COUNT(*) FROM artifacts") || 0
      
      # Size statistics
      stats[:total_size] = @db.get_first_value("SELECT SUM(file_size) FROM artifacts") || 0
      
      # Environment statistics
      env_stats = @db.execute(
        "SELECT environment_name, COUNT(*) FROM collections GROUP BY environment_name"
      ).to_h
      stats[:by_environment] = env_stats
      
      # Type statistics
      type_stats = @db.execute(
        "SELECT artifact_type, COUNT(*) FROM artifacts GROUP BY artifact_type"
      ).to_h
      stats[:by_type] = type_stats
      
      # Time-based statistics
      recent_collections = @db.get_first_value(
        "SELECT COUNT(*) FROM collections WHERE created_at > ?",
        (Time.now - 7 * 24 * 3600).iso8601
      ) || 0
      stats[:recent_collections] = recent_collections
      
      # Tag statistics
      stats[:total_tags] = @db.get_first_value("SELECT COUNT(DISTINCT tag) FROM collection_tags") || 0
      
      stats
    end
    
    def create_repository_backup(backup_path)
      log_info "Creating repository backup: #{backup_path}"
      
      # Create backup directory
      FileUtils.mkdir_p(File.dirname(backup_path))
      
      # Backup database
      db_backup_path = backup_path.sub(/\.[^.]+$/, '_database.db')
      FileUtils.cp(@db_path, db_backup_path)
      
      # Create full backup archive
      system("tar -czf #{backup_path} -C #{File.dirname(@repository_path)} #{File.basename(@repository_path)}")
      
      if File.exist?(backup_path)
        backup_size = File.size(backup_path)
        log_info "Repository backup created: #{backup_path} (#{format_size(backup_size)})"
        backup_path
      else
        raise TestError, "Failed to create repository backup"
      end
    end
    
    def restore_repository_backup(backup_path)
      raise TestError, "Backup file not found: #{backup_path}" unless File.exist?(backup_path)
      
      log_warn "Restoring repository from backup: #{backup_path}"
      
      # Close existing database connection
      @db&.close
      
      # Backup current repository
      current_backup = "#{@repository_path}.backup.#{Time.now.to_i}"
      FileUtils.mv(@repository_path, current_backup) if File.exist?(@repository_path)
      
      begin
        # Extract backup
        parent_dir = File.dirname(@repository_path)
        system("tar -xzf #{backup_path} -C #{parent_dir}")
        
        # Reconnect to database
        ensure_database_connection
        
        log_info "Repository restored successfully from backup"
        
      rescue => e
        # Restore original if backup failed
        if File.exist?(current_backup)
          FileUtils.rm_rf(@repository_path) if File.exist?(@repository_path)
          FileUtils.mv(current_backup, @repository_path)
        end
        
        raise TestError, "Failed to restore repository: #{e.message}"
      ensure
        FileUtils.rm_rf(current_backup) if File.exist?(current_backup)
      end
    end
    
    def close
      @db&.close
      @db = nil
    end
    
    private
    
    def default_config
      {
        enable_content_indexing: true,
        max_content_size: 10 * 1024 * 1024, # 10MB
        index_text_files_only: true,
        auto_vacuum: true,
        journal_mode: 'WAL'
      }
    end
    
    def initialize_repository
      FileUtils.mkdir_p(@repository_path)
      FileUtils.mkdir_p(File.join(@repository_path, 'exports'))
      FileUtils.mkdir_p(File.join(@repository_path, 'backups'))
    end
    
    def ensure_database_connection
      return if @db && !@db.closed?
      
      is_new_db = !File.exist?(@db_path)
      
      @db = SQLite3::Database.new(@db_path)
      configure_database
      
      if is_new_db
        create_database_schema
      else
        migrate_database_if_needed
      end
    end
    
    def configure_database
      @db.execute("PRAGMA journal_mode = #{@config[:journal_mode]}")
      @db.execute("PRAGMA foreign_keys = ON")
      @db.execute("PRAGMA auto_vacuum = INCREMENTAL") if @config[:auto_vacuum]
    end
    
    def create_database_schema
      log_info "Creating artifact repository database schema"
      
      @db.execute_batch(<<~SQL)
        -- Collections table
        CREATE TABLE collections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT UNIQUE NOT NULL,
          environment_name TEXT NOT NULL,
          environment_id TEXT,
          test_result TEXT,
          success BOOLEAN,
          duration REAL,
          total_size INTEGER DEFAULT 0,
          artifact_count INTEGER DEFAULT 0,
          created_at TEXT NOT NULL,
          metadata TEXT
        );
        
        -- Artifacts table
        CREATE TABLE artifacts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          collection_id INTEGER NOT NULL,
          artifact_type TEXT NOT NULL,
          name TEXT NOT NULL,
          file_path TEXT NOT NULL,
          file_size INTEGER DEFAULT 0,
          content_type TEXT,
          content_hash TEXT,
          created_at TEXT NOT NULL,
          metadata TEXT,
          FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
        );
        
        -- Artifact content index for search
        CREATE TABLE artifact_content (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          artifact_id INTEGER NOT NULL,
          collection_id INTEGER NOT NULL,
          content TEXT,
          indexed_at TEXT NOT NULL,
          FOREIGN KEY (artifact_id) REFERENCES artifacts(id) ON DELETE CASCADE,
          FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
        );
        
        -- Collection tags
        CREATE TABLE collection_tags (
          collection_id INTEGER NOT NULL,
          tag TEXT NOT NULL,
          PRIMARY KEY (collection_id, tag),
          FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
        );
        
        -- Artifact views (saved searches)
        CREATE TABLE artifact_views (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          query TEXT,
          filters TEXT,
          created_at TEXT NOT NULL,
          created_by TEXT
        );
        
        -- Comparisons
        CREATE TABLE comparisons (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          collection_id1 INTEGER NOT NULL,
          collection_id2 INTEGER NOT NULL,
          comparison_data TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (collection_id1) REFERENCES collections(id) ON DELETE CASCADE,
          FOREIGN KEY (collection_id2) REFERENCES collections(id) ON DELETE CASCADE
        );
        
        -- Schema version
        CREATE TABLE schema_info (
          version INTEGER NOT NULL
        );
        
        INSERT INTO schema_info (version) VALUES (#{SCHEMA_VERSION});
      SQL
      
      create_database_indexes
    end
    
    def create_database_indexes
      @db.execute_batch(<<~SQL)
        CREATE INDEX idx_collections_created_at ON collections(created_at);
        CREATE INDEX idx_collections_environment ON collections(environment_name);
        CREATE INDEX idx_collections_success ON collections(success);
        CREATE INDEX idx_artifacts_collection_id ON artifacts(collection_id);
        CREATE INDEX idx_artifacts_type ON artifacts(artifact_type);
        CREATE INDEX idx_artifacts_name ON artifacts(name);
        CREATE INDEX idx_artifacts_content_type ON artifacts(content_type);
        CREATE INDEX idx_artifact_content_collection ON artifact_content(collection_id);
        CREATE INDEX idx_collection_tags_tag ON collection_tags(tag);
        CREATE UNIQUE INDEX idx_comparisons_pair ON comparisons(collection_id1, collection_id2);
      SQL
    end
    
    def migrate_database_if_needed
      current_version = @db.get_first_value("SELECT version FROM schema_info") || 0
      
      if current_version < SCHEMA_VERSION
        log_info "Migrating database schema from version #{current_version} to #{SCHEMA_VERSION}"
        # Add migration logic here if needed in the future
      end
    end
    
    def transaction(&block)
      @db.transaction(&block)
    end
    
    def insert_collection(metadata)
      @db.execute(
        <<~SQL,
          INSERT INTO collections (
            session_id, environment_name, environment_id, test_result, 
            success, duration, created_at, metadata
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        metadata[:session_id],
        metadata[:environment_id],
        metadata[:environment_id],
        metadata[:test_result]&.to_json,
        metadata[:success],
        metadata[:duration],
        metadata[:timestamp] || Time.now.iso8601,
        metadata.to_json
      )
      
      @db.last_insert_row_id
    end
    
    def insert_artifact(collection_id, artifact_metadata)
      @db.execute(
        <<~SQL,
          INSERT INTO artifacts (
            collection_id, artifact_type, name, file_path, file_size,
            content_type, content_hash, created_at, metadata
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        collection_id,
        artifact_metadata[:type],
        artifact_metadata[:name],
        artifact_metadata[:file_path],
        artifact_metadata[:file_size],
        artifact_metadata[:content_type],
        artifact_metadata[:content_hash],
        Time.now.iso8601,
        artifact_metadata.to_json
      )
      
      @db.last_insert_row_id
    end
    
    def analyze_artifact(file_path, artifact_type, artifact_name)
      stat = File.stat(file_path)
      content_type = detect_content_type(file_path)
      content_hash = calculate_file_hash(file_path)
      
      {
        type: artifact_type.to_s,
        name: artifact_name.to_s,
        file_path: file_path,
        file_size: stat.size,
        content_type: content_type,
        content_hash: content_hash,
        modified_at: stat.mtime.iso8601
      }
    end
    
    def detect_content_type(file_path)
      case File.extname(file_path).downcase
      when '.txt', '.log'
        'text/plain'
      when '.json'
        'application/json'
      when '.yaml', '.yml'
        'application/yaml'
      when '.html'
        'text/html'
      when '.png'
        'image/png'
      when '.jpg', '.jpeg'
        'image/jpeg'
      else
        # Try to detect by content
        if File.size(file_path) < 1024
          content = File.read(file_path, 1024)
          if content.valid_encoding? && content.ascii_only?
            'text/plain'
          else
            'application/octet-stream'
          end
        else
          'application/octet-stream'
        end
      end
    rescue
      'application/octet-stream'
    end
    
    def calculate_file_hash(file_path)
      Digest::SHA256.file(file_path).hexdigest
    rescue
      nil
    end
    
    def update_collection_stats(collection_id)
      stats = @db.get_first_row(
        "SELECT COUNT(*), SUM(file_size) FROM artifacts WHERE collection_id = ?",
        collection_id
      )
      
      artifact_count = stats[0] || 0
      total_size = stats[1] || 0
      
      @db.execute(
        "UPDATE collections SET artifact_count = ?, total_size = ? WHERE id = ?",
        artifact_count, total_size, collection_id
      )
    end
    
    def index_artifact_content(collection_id)
      return unless @config[:enable_content_indexing]
      
      artifacts = @db.execute(
        "SELECT id, file_path, content_type FROM artifacts WHERE collection_id = ?",
        collection_id
      )
      
      artifacts.each do |artifact|
        artifact_id, file_path, content_type = artifact
        
        next unless should_index_content?(file_path, content_type)
        next if File.size(file_path) > @config[:max_content_size]
        
        begin
          content = File.read(file_path)
          
          @db.execute(
            "INSERT INTO artifact_content (artifact_id, collection_id, content, indexed_at) VALUES (?, ?, ?, ?)",
            artifact_id, collection_id, content, Time.now.iso8601
          )
          
        rescue => e
          log_debug "Failed to index content for artifact #{artifact_id}: #{e.message}"
        end
      end
    end
    
    def should_index_content?(file_path, content_type)
      return false unless @config[:enable_content_indexing]
      
      if @config[:index_text_files_only]
        content_type&.start_with?('text/') || 
          %w[application/json application/yaml].include?(content_type)
      else
        true
      end
    end
    
    def build_search_conditions(query, filters)
      where_clauses = []
      params = []
      
      # Text search in artifact content
      if query && !query.empty?
        where_clauses << "ac.content LIKE ?"
        params << "%#{query}%"
      end
      
      # Environment filter
      if filters[:environment]
        where_clauses << "c.environment_name = ?"
        params << filters[:environment]
      end
      
      # Artifact type filter
      if filters[:artifact_type]
        where_clauses << "a.artifact_type = ?"
        params << filters[:artifact_type]
      end
      
      # Success filter
      if filters.key?(:success)
        where_clauses << "c.success = ?"
        params << filters[:success]
      end
      
      # Date range filter
      if filters[:date_from]
        where_clauses << "c.created_at >= ?"
        params << filters[:date_from]
      end
      
      if filters[:date_to]
        where_clauses << "c.created_at <= ?"
        params << filters[:date_to]
      end
      
      # Tag filter
      if filters[:tag]
        where_clauses << "c.id IN (SELECT collection_id FROM collection_tags WHERE tag = ?)"
        params << filters[:tag]
      end
      
      where_clause = where_clauses.empty? ? "1=1" : where_clauses.join(" AND ")
      
      { where: where_clause, params: params }
    end
    
    def build_joins(filters)
      joins = []
      
      if filters[:query] && !filters[:query].empty?
        joins << "JOIN artifact_content ac ON a.id = ac.artifact_id"
      end
      
      joins.join(" ")
    end
    
    def build_collection_filters(filters)
      where_clauses = []
      params = []
      
      if filters[:environment]
        where_clauses << "environment_name = ?"
        params << filters[:environment]
      end
      
      if filters.key?(:success)
        where_clauses << "success = ?"
        params << filters[:success]
      end
      
      if filters[:date_from]
        where_clauses << "created_at >= ?"
        params << filters[:date_from]
      end
      
      if filters[:date_to]
        where_clauses << "created_at <= ?"
        params << filters[:date_to]
      end
      
      where_clause = where_clauses.empty? ? "1=1" : where_clauses.join(" AND ")
      
      { where: where_clause, params: params }
    end
    
    def build_artifact_filters(filters)
      where_clauses = []
      params = []
      
      if filters[:artifact_type]
        where_clauses << "artifact_type = ?"
        params << filters[:artifact_type]
      end
      
      if filters[:content_type]
        where_clauses << "content_type = ?"
        params << filters[:content_type]
      end
      
      if filters[:name_pattern]
        where_clauses << "name LIKE ?"
        params << "%#{filters[:name_pattern]}%"
      end
      
      where_clause = where_clauses.empty? ? "1=1" : where_clauses.join(" AND ")
      
      { where: where_clause, params: params }
    end
    
    def format_search_results(rows)
      rows.map { |row| format_search_result(row) }
    end
    
    def format_search_result(row)
      # This assumes joined data from collections and artifacts tables
      {
        collection_id: row[0],
        session_id: row[1],
        environment_name: row[2],
        collection_created_at: row[7],
        artifact_id: row[9],
        artifact_type: row[11],
        artifact_name: row[12],
        file_path: row[13],
        file_size: row[14],
        content_type: row[15]
      }
    end
    
    def format_collection(row)
      {
        id: row[0],
        session_id: row[1],
        environment_name: row[2],
        environment_id: row[3],
        test_result: row[4] ? JSON.parse(row[4]) : nil,
        success: row[5],
        duration: row[6],
        total_size: row[7],
        artifact_count: row[8],
        created_at: row[9],
        metadata: row[10] ? JSON.parse(row[10]) : {}
      }
    end
    
    def format_artifact(row)
      {
        id: row[0],
        collection_id: row[1],
        artifact_type: row[2],
        name: row[3],
        file_path: row[4],
        file_size: row[5],
        content_type: row[6],
        content_hash: row[7],
        created_at: row[8],
        metadata: row[9] ? JSON.parse(row[9]) : {}
      }
    end
    
    def store_comparison(collection_id1, collection_id2, comparison_data)
      @db.execute(
        "INSERT INTO comparisons (collection_id1, collection_id2, comparison_data, created_at) VALUES (?, ?, ?, ?)",
        collection_id1, collection_id2, comparison_data.to_json, Time.now.iso8601
      )
      
      @db.last_insert_row_id
    end
    
    def discover_import_artifacts(collection_dir)
      artifacts = {}
      
      Dir.glob(File.join(collection_dir, '*')).each do |type_dir|
        next unless File.directory?(type_dir)
        
        type_name = File.basename(type_dir).to_sym
        artifacts[type_name] = {}
        
        Dir.glob(File.join(type_dir, '*')).each do |artifact_file|
          next unless File.file?(artifact_file)
          
          artifact_name = File.basename(artifact_file).to_sym
          artifacts[type_name][artifact_name] = artifact_file
        end
      end
      
      artifacts
    end
    
    def format_size(bytes)
      return "0 B" if bytes.nil? || bytes == 0
      
      units = %w[B KB MB GB TB]
      size = bytes.to_f
      unit_index = 0
      
      while size >= 1024.0 && unit_index < units.length - 1
        size /= 1024.0
        unit_index += 1
      end
      
      "#{size.round(2)} #{units[unit_index]}"
    end
  end
end