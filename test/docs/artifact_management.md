# Artifact Management System

The Mitamae Test Framework includes a comprehensive artifact management system for local storage, analysis, and collaboration. Building on the artifact collection foundation, this system provides developers with powerful tools for browsing, searching, comparing, and managing test artifacts locally.

## Overview

The artifact management system consists of several integrated components:

- **ArtifactRepository**: SQLite-based storage with full-text search and metadata indexing
- **ArtifactComparator**: Advanced comparison and diff analysis between collections
- **ArtifactBrowser**: Web-based interface for browsing and analyzing artifacts
- **ArtifactManagerCLI**: Command-line tools for comprehensive artifact management
- **Integration Layer**: Seamless integration with environment management system

## Core Features

### 1. Repository Storage

The system uses SQLite for efficient storage and querying:

```ruby
# Initialize repository
repository = ArtifactRepository.new('/path/to/repository')

# Store artifact collection
collection_id = repository.store_artifact_collection(metadata, artifact_paths)

# Search artifacts
results = repository.search_artifacts('error', {
  environment: 'production',
  artifact_type: 'logs'
})
```

### 2. Advanced Search

Full-text search across artifact content with filters:

- **Content Search**: Search inside log files, config files, and text artifacts
- **Metadata Filters**: Filter by environment, type, success status, date range
- **Saved Views**: Create and reuse complex search queries
- **Fuzzy Matching**: Find similar artifacts across collections

### 3. Collection Comparison

Compare artifacts between different test runs:

```ruby
# Compare two collections
comparison = repository.compare_collections(collection_id1, collection_id2)

# Generate detailed diff reports
diff_html = comparator.generate_diff_report(artifact1, artifact2, :html)

# Analyze trends over time
trends = comparator.analyze_trends(collections)
```

### 4. Web Browser Interface

Interactive web interface for artifact exploration:

```ruby
# Start browser
browser = ArtifactBrowser.new(repository, 8080)
url = browser.start

# Access via: http://localhost:8080
```

Features:
- **Dashboard**: Overview of repository statistics and recent collections
- **Collection Browser**: Navigate through collections with filtering
- **Artifact Viewer**: View artifact content with syntax highlighting
- **Search Interface**: Full-text search with real-time filtering
- **Comparison Tools**: Side-by-side collection comparison
- **Trend Analysis**: Visual representation of changes over time

## Command-Line Interface

The `artifact-manager` CLI provides comprehensive management capabilities:

### Repository Management

```bash
# Initialize new repository
artifact-manager init

# Show repository statistics
artifact-manager stats

# Create backup
artifact-manager backup /path/to/backup.tar.gz

# Restore from backup
artifact-manager restore /path/to/backup.tar.gz

# Clean up old collections
artifact-manager cleanup 30  # Remove collections older than 30 days
```

### Collection Management

```bash
# List collections
artifact-manager list collections 20

# Show collection details
artifact-manager show collection 123

# Import collection from file
artifact-manager import /path/to/collection.tar.gz

# Export collection
artifact-manager export 123 /export/path tar_gz

# Tag collections
artifact-manager tag add 123 production critical
artifact-manager tag find production
```

### Search and Analysis

```bash
# Search artifact content
artifact-manager search "connection refused" --environment=prod

# Compare collections
artifact-manager compare 123 124 html

# Analyze trends
artifact-manager trends production 50

# Create saved view
artifact-manager view create "prod-errors" "error" --environment=production
```

### Web Interface

```bash
# Start web browser on default port (8080)
artifact-manager browse

# Start on custom port and host
artifact-manager browse 9090 0.0.0.0
```

## Integration with Test Framework

### Automatic Collection Storage

When integrated with the environment manager, artifacts are automatically stored in the repository:

```ruby
# Environment manager automatically stores collections
env_context = environment_manager.create_environment(:container, 'test-env')
test_result = run_test(recipe_path)

if test_result.failed?
  # Automatically collected and stored in repository
  artifacts = env_context.collect_failure_artifacts(test_result)
  repository_id = artifacts[:repository_id]
end
```

### Session-Level Management

For multi-environment tests:

```ruby
session = environment_manager.create_test_session(config)
session_result = run_session_tests(session)

# Collect artifacts from all environments
session_artifacts = session.collect_all_artifacts(session_result)

# Automatically stored with cross-environment correlation
```

## Advanced Features

### 1. Artifact Views

Create reusable search queries for common analysis patterns:

```ruby
# Create view for production errors
view = repository.create_artifact_view(
  'production-errors',
  'error OR exception OR failed',
  { environment: 'production', success: false }
)

# Execute view
results = repository.execute_artifact_view(view[:id])
```

### 2. Collection Tagging

Organize collections with tags for easy categorization:

```ruby
# Tag collections
repository.tag_collection(collection_id, ['production', 'regression', 'critical'])

# Find tagged collections
collections = repository.find_collections_by_tag('regression')

# Get all tags
tags = repository.get_all_tags
```

### 3. Trend Analysis

Analyze changes over time across multiple collections:

```ruby
collections = repository.find_collections({ environment: 'production' })
trends = comparator.analyze_trends(collections)

# Results include:
# - Size trends
# - Duration trends
# - Success rate trends
# - Error patterns
# - Overall assessment
```

### 4. Artifact Similarity

Find similar artifacts across collections:

```ruby
similar = comparator.find_similar_artifacts(
  target_artifact,
  collection,
  similarity_threshold: 0.8
)
```

### 5. Import/Export

Share collections between repositories:

```ruby
# Export collection
archive_path = repository.export_collection(
  collection_id,
  '/export/path',
  :tar_gz
)

# Import collection  
new_collection_id = repository.import_collection(archive_path)
```

## Storage and Performance

### Database Schema

The system uses SQLite with optimized schema:

- **Collections Table**: Stores collection metadata
- **Artifacts Table**: Individual artifact information
- **Artifact Content**: Full-text searchable content
- **Collection Tags**: Tag associations
- **Artifact Views**: Saved searches
- **Comparisons**: Cached comparison results

### Indexing Strategy

- Full-text search indexes on artifact content
- B-tree indexes on frequently queried fields
- Composite indexes for complex queries
- Automatic index maintenance

### Performance Optimizations

- **Lazy Loading**: Content loaded on demand
- **Batch Operations**: Efficient bulk operations
- **Connection Pooling**: Optimized database access
- **Incremental Vacuum**: Automatic space reclamation
- **Content Limits**: Configurable size limits for indexing

## Configuration

### Repository Configuration

```ruby
repository = ArtifactRepository.new(path, {
  enable_content_indexing: true,
  max_content_size: 10 * 1024 * 1024,  # 10MB
  index_text_files_only: true,
  auto_vacuum: true,
  journal_mode: 'WAL'
})
```

### Environment Variables

```bash
# Set repository location
export MITAMAE_ARTIFACT_REPO="/path/to/repository"

# Enable debug logging
export DEBUG=1
```

### Integration Configuration

```ruby
environment_manager = EnvironmentManager.new({
  artifacts_dir: '/path/to/artifacts',
  artifact_configs: {
    'production' => {
      enable_content_indexing: true,
      create_browsable_index: true,
      auto_cleanup: false
    },
    'development' => {
      enable_content_indexing: false,
      auto_cleanup: true
    }
  }
})
```

## Web Interface Details

### Dashboard

- Repository statistics and health metrics
- Recent collections with status indicators
- Quick access to search and compare functions
- Resource usage and storage information

### Collection Browser

- Filterable list of all collections
- Environment, status, and date range filters
- Sortable columns with search functionality
- Batch operations on selected collections

### Artifact Viewer

- Syntax-highlighted content viewing
- Download and export capabilities
- Metadata display with technical details
- Related artifact suggestions

### Search Interface

- Real-time search with auto-complete
- Advanced filtering options
- Search result highlighting
- Export search results

### Comparison Tools

- Side-by-side collection comparison
- Diff visualization with syntax highlighting
- Change summary and impact analysis
- Downloadable comparison reports

## Security Considerations

### Data Protection

- Repository files are stored locally
- No sensitive data is transmitted over network
- Local web interface binds to localhost by default
- Optional authentication for multi-user setups

### Content Filtering

- Configurable content indexing limits
- Binary file exclusion from indexing
- Sensitive pattern detection and filtering
- Automatic cleanup of old data

## Troubleshooting

### Common Issues

**Large repository size**:
```bash
# Check repository statistics
artifact-manager stats

# Clean up old collections
artifact-manager cleanup 7

# Analyze disk usage
du -sh ~/.mitamae/artifacts/
```

**Search performance issues**:
```bash
# Rebuild search index
artifact-manager rebuild-index

# Check database integrity
artifact-manager verify
```

**Browser connection issues**:
```bash
# Check if port is available
netstat -an | grep 8080

# Start on different port
artifact-manager browse 9090
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
DEBUG=1 artifact-manager search "test query"
```

### Repository Maintenance

```bash
# Verify repository integrity
artifact-manager verify

# Rebuild search indexes
artifact-manager rebuild-index

# Optimize database
artifact-manager optimize

# Export diagnostics
artifact-manager diagnostics > debug.log
```

## API Reference

### Repository API

```ruby
# Core operations
repository.store_artifact_collection(metadata, artifacts)
repository.search_artifacts(query, filters)
repository.find_collections(filters)
repository.get_collection(id)

# Management operations
repository.compare_collections(id1, id2)
repository.tag_collection(id, tags)
repository.create_artifact_view(name, query, filters)
repository.export_collection(id, path, format)
repository.import_collection(path)

# Maintenance operations
repository.cleanup_old_collections(days)
repository.get_repository_statistics()
repository.create_repository_backup(path)
repository.restore_repository_backup(path)
```

### Comparator API

```ruby
# Comparison operations
comparator.compare(collection1, collection2)
comparator.compare_artifacts(artifact1, artifact2)
comparator.generate_diff_report(artifact1, artifact2, format)

# Analysis operations
comparator.find_similar_artifacts(target, collection, threshold)
comparator.analyze_trends(collections)
comparator.compare_logs(collection1, collection2)
comparator.compare_system_state(collection1, collection2)
```

### Browser API

```ruby
# Browser control
browser.start()
browser.stop()
browser.running?
browser.url

# Access endpoints
# GET  /                    - Dashboard
# GET  /collections         - Collection list
# GET  /collection?id=123   - Collection detail
# GET  /search?q=query      - Search interface
# POST /compare             - Collection comparison
# GET  /api/stats           - Statistics API
```

## Future Enhancements

The artifact management system is designed for extensibility:

- **Real-time Monitoring**: Live artifact streaming during test execution
- **Machine Learning**: Automated failure pattern detection
- **Cloud Storage**: Support for remote storage backends
- **Team Collaboration**: Multi-user repositories with sharing
- **Advanced Analytics**: Predictive analysis and alerting
- **Integration APIs**: REST API for external tool integration
- **Custom Visualizations**: Pluggable chart and graph components

## Best Practices

### For Developers

1. **Regular Cleanup**: Use automatic cleanup or manual cleanup commands
2. **Meaningful Tags**: Tag collections for easy organization
3. **Use Saved Views**: Create views for common search patterns
4. **Compare Strategically**: Compare similar test runs for insights
5. **Monitor Storage**: Keep an eye on repository size and performance

### For Teams

1. **Shared Repository**: Use network-accessible repository for team collaboration
2. **Tagging Conventions**: Establish consistent tagging strategies
3. **Regular Backups**: Automate repository backups
4. **Search Training**: Train team members on effective search techniques
5. **Trend Analysis**: Regular trend analysis for continuous improvement

### Performance Tips

1. **Limit Content Indexing**: Index only necessary content types
2. **Use Filters**: Apply filters to narrow search scope
3. **Regular Maintenance**: Run periodic optimization
4. **Monitor Resources**: Track disk and memory usage
5. **Archive Old Data**: Export and remove very old collections

The artifact management system provides a comprehensive solution for debugging, analysis, and collaboration around mitamae test artifacts, making it easier for developers to diagnose issues and improve their infrastructure automation.