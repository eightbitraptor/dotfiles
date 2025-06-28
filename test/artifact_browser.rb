require 'webrick'
require 'erb'
require 'json'
require 'uri'
require 'cgi'

module MitamaeTest
  class ArtifactBrowser
    include Logging
    
    DEFAULT_PORT = 8080
    DEFAULT_HOST = 'localhost'
    
    attr_reader :repository, :server, :port, :host
    
    def initialize(repository, port = DEFAULT_PORT, host = DEFAULT_HOST)
      @repository = repository
      @port = port
      @host = host
      @server = nil
      @running = false
    end
    
    def start
      return if @running
      
      log_info "Starting artifact browser on http://#{@host}:#{@port}"
      
      @server = WEBrick::HTTPServer.new(
        Port: @port,
        Host: @host,
        Logger: WEBrick::Log.new(nil, WEBrick::Log::WARN),
        AccessLog: []
      )
      
      setup_routes
      
      @running = true
      
      # Start server in a separate thread
      @server_thread = Thread.new do
        @server.start
      end
      
      # Wait a moment for server to start
      sleep 0.5
      
      log_info "Artifact browser started: http://#{@host}:#{@port}"
      "http://#{@host}:#{@port}"
    end
    
    def stop
      return unless @running
      
      log_info "Stopping artifact browser"
      
      @server&.shutdown
      @server_thread&.join(5) # Wait up to 5 seconds
      
      @running = false
      @server = nil
      @server_thread = nil
      
      log_info "Artifact browser stopped"
    end
    
    def running?
      @running
    end
    
    def url
      @running ? "http://#{@host}:#{@port}" : nil
    end
    
    private
    
    def setup_routes
      # Main dashboard
      @server.mount_proc('/') { |req, res| handle_dashboard(req, res) }
      
      # Collections
      @server.mount_proc('/collections') { |req, res| handle_collections(req, res) }
      @server.mount_proc('/collection') { |req, res| handle_collection_detail(req, res) }
      
      # Artifacts
      @server.mount_proc('/artifact') { |req, res| handle_artifact_detail(req, res) }
      @server.mount_proc('/artifact/content') { |req, res| handle_artifact_content(req, res) }
      @server.mount_proc('/artifact/download') { |req, res| handle_artifact_download(req, res) }
      
      # Search
      @server.mount_proc('/search') { |req, res| handle_search(req, res) }
      
      # Comparisons
      @server.mount_proc('/compare') { |req, res| handle_comparison(req, res) }
      
      # Views
      @server.mount_proc('/views') { |req, res| handle_views(req, res) }
      @server.mount_proc('/view') { |req, res| handle_view_detail(req, res) }
      
      # API endpoints
      @server.mount_proc('/api/collections') { |req, res| handle_api_collections(req, res) }
      @server.mount_proc('/api/search') { |req, res| handle_api_search(req, res) }
      @server.mount_proc('/api/stats') { |req, res| handle_api_stats(req, res) }
      
      # Static assets
      @server.mount_proc('/assets') { |req, res| handle_assets(req, res) }
    end
    
    def handle_dashboard(req, res)
      stats = @repository.get_repository_statistics
      recent_collections = @repository.find_collections({}).first(10)
      
      html = render_template('dashboard', {
        stats: stats,
        recent_collections: recent_collections
      })
      
      serve_html(res, html)
    end
    
    def handle_collections(req, res)
      query = parse_query_params(req.query_string)
      
      filters = {}
      filters[:environment] = query['environment'] if query['environment']
      filters[:success] = query['success'] == 'true' if query['success']
      filters[:date_from] = query['date_from'] if query['date_from']
      filters[:date_to] = query['date_to'] if query['date_to']
      
      collections = @repository.find_collections(filters)
      environments = @repository.get_repository_statistics[:by_environment].keys
      
      html = render_template('collections', {
        collections: collections,
        environments: environments,
        filters: query
      })
      
      serve_html(res, html)
    end
    
    def handle_collection_detail(req, res)
      query = parse_query_params(req.query_string)
      collection_id = query['id']&.to_i
      
      unless collection_id
        serve_error(res, 400, "Collection ID required")
        return
      end
      
      collection = @repository.get_collection(collection_id)
      
      unless collection
        serve_error(res, 404, "Collection not found")
        return
      end
      
      # Group artifacts by type
      artifacts_by_type = collection[:artifacts].group_by { |a| a[:artifact_type] }
      
      html = render_template('collection_detail', {
        collection: collection,
        artifacts_by_type: artifacts_by_type
      })
      
      serve_html(res, html)
    end
    
    def handle_artifact_detail(req, res)
      query = parse_query_params(req.query_string)
      artifact_id = query['id']&.to_i
      
      unless artifact_id
        serve_error(res, 400, "Artifact ID required")
        return
      end
      
      artifact = @repository.get_artifact(artifact_id)
      
      unless artifact
        serve_error(res, 404, "Artifact not found")
        return
      end
      
      # Get artifact content preview
      content_preview = nil
      if artifact[:content_type]&.start_with?('text/') && artifact[:file_size] < 1024 * 1024
        content = @repository.get_artifact_content(artifact_id)
        content_preview = content&.lines&.first(100)&.join if content
      end
      
      html = render_template('artifact_detail', {
        artifact: artifact,
        content_preview: content_preview
      })
      
      serve_html(res, html)
    end
    
    def handle_artifact_content(req, res)
      query = parse_query_params(req.query_string)
      artifact_id = query['id']&.to_i
      format = query['format'] || 'raw'
      
      unless artifact_id
        serve_error(res, 400, "Artifact ID required")
        return
      end
      
      artifact = @repository.get_artifact(artifact_id)
      
      unless artifact
        serve_error(res, 404, "Artifact not found")
        return
      end
      
      content = @repository.get_artifact_content(artifact_id, format.to_sym)
      
      if content
        res['Content-Type'] = artifact[:content_type] || 'text/plain'
        res.body = content.is_a?(String) ? content : content.to_s
      else
        serve_error(res, 500, "Could not read artifact content")
      end
    end
    
    def handle_artifact_download(req, res)
      query = parse_query_params(req.query_string)
      artifact_id = query['id']&.to_i
      
      unless artifact_id
        serve_error(res, 400, "Artifact ID required")
        return
      end
      
      artifact = @repository.get_artifact(artifact_id)
      
      unless artifact
        serve_error(res, 404, "Artifact not found")
        return
      end
      
      unless File.exist?(artifact[:file_path])
        serve_error(res, 404, "Artifact file not found")
        return
      end
      
      res['Content-Type'] = 'application/octet-stream'
      res['Content-Disposition'] = "attachment; filename=\"#{artifact[:name]}\""
      res.body = File.read(artifact[:file_path])
    end
    
    def handle_search(req, res)
      query = parse_query_params(req.query_string)
      search_query = query['q'] || ''
      
      filters = {}
      filters[:environment] = query['environment'] if query['environment']
      filters[:artifact_type] = query['type'] if query['type']
      filters[:success] = query['success'] == 'true' if query['success']
      
      results = []
      if search_query.length >= 2
        results = @repository.search_artifacts(search_query, filters)
      end
      
      # Get filter options
      stats = @repository.get_repository_statistics
      environments = stats[:by_environment].keys
      artifact_types = stats[:by_type].keys
      
      html = render_template('search', {
        query: search_query,
        results: results,
        filters: query,
        environments: environments,
        artifact_types: artifact_types
      })
      
      serve_html(res, html)
    end
    
    def handle_comparison(req, res)
      query = parse_query_params(req.query_string)
      
      if req.request_method == 'POST'
        # Handle comparison request
        collection_id1 = query['collection1']&.to_i
        collection_id2 = query['collection2']&.to_i
        
        if collection_id1 && collection_id2
          comparison = @repository.compare_collections(collection_id1, collection_id2)
          
          html = render_template('comparison_result', {
            comparison: comparison
          })
          
          serve_html(res, html)
          return
        end
      end
      
      # Show comparison form
      collections = @repository.find_collections({}).first(50)
      
      html = render_template('comparison_form', {
        collections: collections
      })
      
      serve_html(res, html)
    end
    
    def handle_views(req, res)
      views = @repository.get_artifact_views
      
      html = render_template('views', {
        views: views
      })
      
      serve_html(res, html)
    end
    
    def handle_view_detail(req, res)
      query = parse_query_params(req.query_string)
      view_id = query['id']
      
      unless view_id
        serve_error(res, 400, "View ID required")
        return
      end
      
      results = @repository.execute_artifact_view(view_id)
      
      unless results
        serve_error(res, 404, "View not found")
        return
      end
      
      html = render_template('view_result', {
        view_id: view_id,
        results: results
      })
      
      serve_html(res, html)
    end
    
    # API endpoints
    
    def handle_api_collections(req, res)
      collections = @repository.find_collections({})
      serve_json(res, collections)
    end
    
    def handle_api_search(req, res)
      query = parse_query_params(req.query_string)
      search_query = query['q'] || ''
      
      results = @repository.search_artifacts(search_query, {})
      serve_json(res, results)
    end
    
    def handle_api_stats(req, res)
      stats = @repository.get_repository_statistics
      serve_json(res, stats)
    end
    
    def handle_assets(req, res)
      # Serve CSS/JS assets inline for simplicity
      asset_name = req.path.split('/').last
      
      case asset_name
      when 'style.css'
        res['Content-Type'] = 'text/css'
        res.body = generate_css
      when 'script.js'
        res['Content-Type'] = 'application/javascript'
        res.body = generate_javascript
      else
        serve_error(res, 404, "Asset not found")
      end
    end
    
    # Template rendering
    
    def render_template(template_name, data = {})
      template_content = get_template(template_name)
      erb = ERB.new(template_content)
      erb.result_with_hash(data.merge(browser: self))
    end
    
    def get_template(name)
      case name
      when 'dashboard'
        dashboard_template
      when 'collections'
        collections_template
      when 'collection_detail'
        collection_detail_template
      when 'artifact_detail'
        artifact_detail_template
      when 'search'
        search_template
      when 'comparison_form'
        comparison_form_template
      when 'comparison_result'
        comparison_result_template
      when 'views'
        views_template
      when 'view_result'
        view_result_template
      else
        "<html><body><h1>Template not found: #{name}</h1></body></html>"
      end
    end
    
    def base_template(title, content)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>#{title} - Mitamae Artifact Browser</title>
          <link rel="stylesheet" href="/assets/style.css">
          <script src="/assets/script.js"></script>
        </head>
        <body>
          <nav class="navbar">
            <div class="nav-brand">
              <a href="/">Mitamae Artifact Browser</a>
            </div>
            <ul class="nav-links">
              <li><a href="/">Dashboard</a></li>
              <li><a href="/collections">Collections</a></li>
              <li><a href="/search">Search</a></li>
              <li><a href="/compare">Compare</a></li>
              <li><a href="/views">Views</a></li>
            </ul>
          </nav>
          <main class="container">
            #{content}
          </main>
        </body>
        </html>
      HTML
    end
    
    def dashboard_template
      base_template('Dashboard', <<~HTML)
        <h1>Artifact Repository Dashboard</h1>
        
        <div class="stats-grid">
          <div class="stat-card">
            <h3>Collections</h3>
            <div class="stat-value"><%= stats[:collections] %></div>
          </div>
          <div class="stat-card">
            <h3>Artifacts</h3>
            <div class="stat-value"><%= stats[:artifacts] %></div>
          </div>
          <div class="stat-card">
            <h3>Total Size</h3>
            <div class="stat-value"><%= format_size(stats[:total_size]) %></div>
          </div>
          <div class="stat-card">
            <h3>Recent Collections</h3>
            <div class="stat-value"><%= stats[:recent_collections] %></div>
          </div>
        </div>
        
        <div class="section">
          <h2>Recent Collections</h2>
          <div class="collection-list">
            <% recent_collections.each do |collection| %>
              <div class="collection-item">
                <div class="collection-header">
                  <h3><a href="/collection?id=<%= collection[:id] %>"><%= collection[:session_id] %></a></h3>
                  <span class="status-badge <%= collection[:success] ? 'success' : 'failure' %>">
                    <%= collection[:success] ? 'Success' : 'Failed' %>
                  </span>
                </div>
                <div class="collection-meta">
                  <span>Environment: <%= collection[:environment_name] %></span>
                  <span>Artifacts: <%= collection[:artifact_count] %></span>
                  <span>Size: <%= format_size(collection[:total_size]) %></span>
                  <span>Created: <%= format_time(collection[:created_at]) %></span>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      HTML
    end
    
    def collections_template
      base_template('Collections', <<~HTML)
        <h1>Artifact Collections</h1>
        
        <form class="filters" method="get">
          <div class="filter-group">
            <label>Environment:</label>
            <select name="environment">
              <option value="">All Environments</option>
              <% environments.each do |env| %>
                <option value="<%= env %>" <%= 'selected' if filters['environment'] == env %>><%= env %></option>
              <% end %>
            </select>
          </div>
          
          <div class="filter-group">
            <label>Status:</label>
            <select name="success">
              <option value="">All</option>
              <option value="true" <%= 'selected' if filters['success'] == 'true' %>>Success</option>
              <option value="false" <%= 'selected' if filters['success'] == 'false' %>>Failed</option>
            </select>
          </div>
          
          <div class="filter-group">
            <label>Date From:</label>
            <input type="date" name="date_from" value="<%= filters['date_from'] %>">
          </div>
          
          <div class="filter-group">
            <label>Date To:</label>
            <input type="date" name="date_to" value="<%= filters['date_to'] %>">
          </div>
          
          <button type="submit">Filter</button>
        </form>
        
        <div class="collection-list">
          <% collections.each do |collection| %>
            <div class="collection-item">
              <div class="collection-header">
                <h3><a href="/collection?id=<%= collection[:id] %>"><%= collection[:session_id] %></a></h3>
                <span class="status-badge <%= collection[:success] ? 'success' : 'failure' %>">
                  <%= collection[:success] ? 'Success' : 'Failed' %>
                </span>
              </div>
              <div class="collection-meta">
                <span>Environment: <%= collection[:environment_name] %></span>
                <span>Duration: <%= collection[:duration]&.round(2) %>s</span>
                <span>Artifacts: <%= collection[:artifact_count] %></span>
                <span>Size: <%= format_size(collection[:total_size]) %></span>
                <span>Created: <%= format_time(collection[:created_at]) %></span>
              </div>
            </div>
          <% end %>
        </div>
      HTML
    end
    
    def collection_detail_template
      base_template("Collection #{collection[:session_id]}", <<~HTML)
        <div class="collection-header">
          <h1>Collection: <%= collection[:session_id] %></h1>
          <span class="status-badge <%= collection[:success] ? 'success' : 'failure' %>">
            <%= collection[:success] ? 'Success' : 'Failed' %>
          </span>
        </div>
        
        <div class="collection-info">
          <div class="info-grid">
            <div><strong>Environment:</strong> <%= collection[:environment_name] %></div>
            <div><strong>Duration:</strong> <%= collection[:duration]&.round(2) %>s</div>
            <div><strong>Total Size:</strong> <%= format_size(collection[:total_size]) %></div>
            <div><strong>Artifact Count:</strong> <%= collection[:artifact_count] %></div>
            <div><strong>Created:</strong> <%= format_time(collection[:created_at]) %></div>
          </div>
        </div>
        
        <div class="artifacts-section">
          <% artifacts_by_type.each do |type, artifacts| %>
            <div class="artifact-type-section">
              <h2><%= type.capitalize %> (<%= artifacts.size %>)</h2>
              <div class="artifact-list">
                <% artifacts.each do |artifact| %>
                  <div class="artifact-item">
                    <div class="artifact-name">
                      <a href="/artifact?id=<%= artifact[:id] %>"><%= artifact[:name] %></a>
                    </div>
                    <div class="artifact-meta">
                      <span>Size: <%= format_size(artifact[:file_size]) %></span>
                      <span>Type: <%= artifact[:content_type] %></span>
                      <a href="/artifact/download?id=<%= artifact[:id] %>" class="download-link">Download</a>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      HTML
    end
    
    def search_template
      base_template('Search Artifacts', <<~HTML)
        <h1>Search Artifacts</h1>
        
        <form class="search-form" method="get">
          <div class="search-input-group">
            <input type="text" name="q" value="<%= query %>" placeholder="Search artifact content..." class="search-input">
            <button type="submit" class="search-button">Search</button>
          </div>
          
          <div class="search-filters">
            <select name="environment">
              <option value="">All Environments</option>
              <% environments.each do |env| %>
                <option value="<%= env %>" <%= 'selected' if filters['environment'] == env %>><%= env %></option>
              <% end %>
            </select>
            
            <select name="type">
              <option value="">All Types</option>
              <% artifact_types.each do |type| %>
                <option value="<%= type %>" <%= 'selected' if filters['type'] == type %>><%= type %></option>
              <% end %>
            </select>
            
            <select name="success">
              <option value="">All Results</option>
              <option value="true" <%= 'selected' if filters['success'] == 'true' %>>Success Only</option>
              <option value="false" <%= 'selected' if filters['success'] == 'false' %>>Failed Only</option>
            </select>
          </div>
        </form>
        
        <% if results.any? %>
          <div class="search-results">
            <h2>Search Results (<%= results.size %>)</h2>
            <% results.each do |result| %>
              <div class="search-result-item">
                <div class="result-header">
                  <h3><a href="/artifact?id=<%= result[:artifact_id] %>"><%= result[:artifact_name] %></a></h3>
                  <span class="result-type"><%= result[:artifact_type] %></span>
                </div>
                <div class="result-meta">
                  <span>Collection: <a href="/collection?id=<%= result[:collection_id] %>"><%= result[:session_id] %></a></span>
                  <span>Environment: <%= result[:environment_name] %></span>
                  <span>Size: <%= format_size(result[:file_size]) %></span>
                </div>
              </div>
            <% end %>
          </div>
        <% elsif query.length >= 2 %>
          <div class="no-results">
            <p>No artifacts found matching your search criteria.</p>
          </div>
        <% end %>
      HTML
    end
    
    def artifact_detail_template
      base_template("Artifact #{artifact[:name]}", <<~HTML)
        <div class="artifact-header">
          <h1><%= artifact[:name] %></h1>
          <span class="artifact-type"><%= artifact[:artifact_type] %></span>
        </div>
        
        <div class="artifact-info">
          <div class="info-grid">
            <div><strong>Type:</strong> <%= artifact[:artifact_type] %></div>
            <div><strong>Content Type:</strong> <%= artifact[:content_type] %></div>
            <div><strong>Size:</strong> <%= format_size(artifact[:file_size]) %></div>
            <div><strong>Created:</strong> <%= format_time(artifact[:created_at]) %></div>
          </div>
          
          <div class="artifact-actions">
            <a href="/artifact/content?id=<%= artifact[:id] %>" class="btn btn-primary">View Content</a>
            <a href="/artifact/download?id=<%= artifact[:id] %>" class="btn btn-secondary">Download</a>
            <a href="/collection?id=<%= artifact[:collection_id] %>" class="btn btn-secondary">View Collection</a>
          </div>
        </div>
        
        <% if content_preview %>
          <div class="content-preview">
            <h2>Content Preview (first 100 lines)</h2>
            <pre class="code-preview"><%= CGI.escapeHTML(content_preview.join) %></pre>
          </div>
        <% end %>
      HTML
    end
    
    # Helper methods
    
    def serve_html(res, html)
      res['Content-Type'] = 'text/html'
      res.body = html
    end
    
    def serve_json(res, data)
      res['Content-Type'] = 'application/json'
      res.body = JSON.pretty_generate(data)
    end
    
    def serve_error(res, status, message)
      res.status = status
      res['Content-Type'] = 'text/html'
      res.body = base_template('Error', "<h1>Error #{status}</h1><p>#{message}</p>")
    end
    
    def parse_query_params(query_string)
      return {} unless query_string
      
      URI.decode_www_form(query_string).to_h
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
    
    def format_time(time_string)
      return 'Unknown' unless time_string
      
      Time.parse(time_string).strftime('%Y-%m-%d %H:%M:%S')
    rescue
      time_string
    end
    
    def generate_css
      <<~CSS
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
          line-height: 1.6;
          color: #333;
          background: #f5f5f5;
        }
        
        .navbar {
          background: #2c3e50;
          color: white;
          padding: 1rem 2rem;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        
        .nav-brand a {
          color: white;
          text-decoration: none;
          font-size: 1.5rem;
          font-weight: bold;
        }
        
        .nav-links {
          display: flex;
          list-style: none;
          gap: 2rem;
        }
        
        .nav-links a {
          color: white;
          text-decoration: none;
          padding: 0.5rem 1rem;
          border-radius: 4px;
          transition: background 0.2s;
        }
        
        .nav-links a:hover {
          background: rgba(255,255,255,0.1);
        }
        
        .container {
          max-width: 1200px;
          margin: 0 auto;
          padding: 2rem;
          background: white;
          min-height: calc(100vh - 80px);
        }
        
        .stats-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 1rem;
          margin: 2rem 0;
        }
        
        .stat-card {
          background: #f8f9fa;
          padding: 1.5rem;
          border-radius: 8px;
          text-align: center;
          border: 1px solid #e9ecef;
        }
        
        .stat-value {
          font-size: 2rem;
          font-weight: bold;
          color: #2c3e50;
          margin-top: 0.5rem;
        }
        
        .collection-list {
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }
        
        .collection-item {
          padding: 1rem;
          border: 1px solid #dee2e6;
          border-radius: 8px;
          background: #fff;
        }
        
        .collection-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.5rem;
        }
        
        .collection-header h3 {
          margin: 0;
        }
        
        .collection-header a {
          color: #007bff;
          text-decoration: none;
        }
        
        .collection-meta {
          display: flex;
          gap: 1rem;
          color: #6c757d;
          font-size: 0.9rem;
        }
        
        .status-badge {
          padding: 0.25rem 0.75rem;
          border-radius: 4px;
          font-size: 0.85rem;
          font-weight: bold;
        }
        
        .status-badge.success {
          background: #d4edda;
          color: #155724;
        }
        
        .status-badge.failure {
          background: #f8d7da;
          color: #721c24;
        }
        
        .filters {
          display: flex;
          gap: 1rem;
          align-items: end;
          margin: 2rem 0;
          padding: 1rem;
          background: #f8f9fa;
          border-radius: 8px;
        }
        
        .filter-group {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        
        .filter-group label {
          font-size: 0.9rem;
          font-weight: 500;
        }
        
        .search-form {
          margin: 2rem 0;
        }
        
        .search-input-group {
          display: flex;
          gap: 0.5rem;
          margin-bottom: 1rem;
        }
        
        .search-input {
          flex: 1;
          padding: 0.75rem;
          border: 1px solid #ced4da;
          border-radius: 4px;
          font-size: 1rem;
        }
        
        .search-button {
          padding: 0.75rem 1.5rem;
          background: #007bff;
          color: white;
          border: none;
          border-radius: 4px;
          cursor: pointer;
        }
        
        .search-filters {
          display: flex;
          gap: 1rem;
        }
        
        .search-filters select {
          padding: 0.5rem;
          border: 1px solid #ced4da;
          border-radius: 4px;
        }
        
        .btn {
          display: inline-block;
          padding: 0.5rem 1rem;
          text-decoration: none;
          border-radius: 4px;
          font-size: 0.9rem;
          text-align: center;
          cursor: pointer;
          border: none;
        }
        
        .btn-primary {
          background: #007bff;
          color: white;
        }
        
        .btn-secondary {
          background: #6c757d;
          color: white;
        }
        
        .artifact-actions {
          display: flex;
          gap: 1rem;
          margin-top: 1rem;
        }
        
        .code-preview {
          background: #f8f9fa;
          padding: 1rem;
          border-radius: 4px;
          overflow-x: auto;
          border: 1px solid #e9ecef;
          font-family: 'Monaco', 'Menlo', monospace;
          font-size: 0.9rem;
        }
        
        .info-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 1rem;
          margin: 1rem 0;
        }
        
        .section {
          margin: 2rem 0;
        }
        
        .artifact-type-section {
          margin: 2rem 0;
        }
        
        .artifact-list {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        
        .artifact-item {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 0.75rem;
          background: #f8f9fa;
          border-radius: 4px;
        }
        
        .artifact-meta {
          display: flex;
          gap: 1rem;
          align-items: center;
          font-size: 0.9rem;
          color: #6c757d;
        }
        
        .download-link {
          color: #007bff;
          text-decoration: none;
          font-size: 0.9rem;
        }
      CSS
    end
    
    def generate_javascript
      <<~JS
        // Simple JavaScript for enhanced functionality
        document.addEventListener('DOMContentLoaded', function() {
          // Auto-refresh functionality for dashboard
          if (window.location.pathname === '/') {
            // Refresh dashboard every 30 seconds
            setTimeout(function() {
              window.location.reload();
            }, 30000);
          }
          
          // Search form enhancements
          const searchForm = document.querySelector('.search-form');
          if (searchForm) {
            const searchInput = searchForm.querySelector('input[name="q"]');
            if (searchInput) {
              // Auto-submit on filter changes
              const filters = searchForm.querySelectorAll('select');
              filters.forEach(function(filter) {
                filter.addEventListener('change', function() {
                  searchForm.submit();
                });
              });
            }
          }
          
          // Collection comparison
          const compareForm = document.querySelector('.comparison-form');
          if (compareForm) {
            const collection1 = compareForm.querySelector('select[name="collection1"]');
            const collection2 = compareForm.querySelector('select[name="collection2"]');
            const submitBtn = compareForm.querySelector('button[type="submit"]');
            
            function updateSubmitButton() {
              if (collection1.value && collection2.value && collection1.value !== collection2.value) {
                submitBtn.disabled = false;
              } else {
                submitBtn.disabled = true;
              }
            }
            
            collection1.addEventListener('change', updateSubmitButton);
            collection2.addEventListener('change', updateSubmitButton);
            updateSubmitButton();
          }
        });
      JS
    end
    
    # Additional template methods would go here...
    def comparison_form_template
      base_template('Compare Collections', '<h1>Comparison form placeholder</h1>')
    end
    
    def comparison_result_template  
      base_template('Comparison Result', '<h1>Comparison result placeholder</h1>')
    end
    
    def views_template
      base_template('Artifact Views', '<h1>Views placeholder</h1>')
    end
    
    def view_result_template
      base_template('View Result', '<h1>View result placeholder</h1>')
    end
  end
end