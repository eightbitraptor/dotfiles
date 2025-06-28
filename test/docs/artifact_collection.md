# Artifact Collection System

The Mitamae Test Framework includes a comprehensive artifact collection system designed to help developers debug failed tests locally. The system automatically collects logs, screenshots, system state, configuration files, and other diagnostic information when tests fail.

## Overview

The artifact collection system consists of several key components:

- **ArtifactCollector**: Core collection engine that gathers various types of artifacts
- **ArtifactManager**: High-level management interface for artifact operations
- **EnvironmentManager Integration**: Seamless integration with test environments
- **CLI Tools**: Command-line utilities for manual artifact collection and management

## Supported Artifact Types

### 1. Logs (`logs`)
- System logs (journal, syslog, dmesg)
- Application logs
- Environment-specific logs
- Test framework logs
- Mitamae execution logs

### 2. Screenshots (`screenshots`)
- Current desktop state (VM environments)
- Existing screenshots from test execution
- Visual state at failure time

### 3. System State (`system_state`)
- Process information (`ps`, `pstree`)
- Memory usage (`free`, `/proc/meminfo`)
- Disk usage (`df`, `lsblk`)
- Network configuration (`ip`, `ss`, `resolv.conf`)
- Environment variables

### 4. Configuration Files (`config_files`)
- System configuration (`/etc/*`)
- User configuration files
- Application-specific configs
- Mitamae recipe configurations

### 5. Package State (`package_state`)
- Installed packages (pacman, apt, dnf, flatpak)
- Package databases
- Repository configurations

### 6. Service State (`service_state`)
- systemd service status
- runit service status (Void Linux)
- Failed services
- Service logs

### 7. Performance Data (`performance_data`)
- System load averages
- CPU information
- I/O statistics
- Resource usage metrics

### 8. Test Output (`test_output`)
- Test execution results
- Mitamae output files
- Recipe execution logs

### 9. Error Traces (`error_traces`)
- Core dumps
- Crash logs
- Stack traces
- Exception information

### 10. Environment Info (`environment_info`)
- Environment metadata
- Container/VM information
- Collection timestamps
- Framework version information

## Usage

### Automatic Collection

Artifacts are automatically collected when tests fail:

```ruby
# During test execution, failures automatically trigger artifact collection
test_result = run_test(recipe_path)

if test_result.failed?
  # Automatically collects comprehensive failure artifacts
  artifacts = environment.collect_failure_artifacts(test_result)
end
```

### Manual Collection

You can manually collect artifacts at any time:

```ruby
# Collect standard artifacts
artifacts = environment.collect_artifacts

# Collect with custom configuration
artifacts = environment.collect_artifacts(test_result, {
  artifact_types: [:logs, :screenshots, :system_state],
  create_archive: true,
  create_browsable_index: true
})

# Collect failure-specific artifacts
artifacts = environment.collect_failure_artifacts(failure_info)
```

### CLI Usage

Use the `collect-artifacts` command-line tool:

```bash
# Collect artifacts from an environment
./test/bin/collect-artifacts collect my-test-env

# Collect with archive and browsable index
./test/bin/collect-artifacts collect my-test-env --archive --index

# Collect failure artifacts (comprehensive)
./test/bin/collect-artifacts collect my-test-env --failure

# List artifact history
./test/bin/collect-artifacts list my-test-env

# Clean up old artifacts
./test/bin/collect-artifacts cleanup my-test-env 7

# Generate HTML report
./test/bin/collect-artifacts report my-test-env html
```

## Configuration

### Default Configuration

```ruby
{
  artifact_types: [:logs, :system_state, :config_files, :environment_info],
  create_archive: false,
  create_browsable_index: true,
  auto_cleanup: true,
  max_file_size_mb: 50,
  include_binary_files: false,
  generate_report: true
}
```

### Failure-Specific Configuration

When a test fails, the system automatically uses enhanced configuration:

```ruby
{
  artifact_types: ALL_ARTIFACT_TYPES,  # Collect everything
  create_archive: true,                # Create compressed archive
  include_binary_files: true,          # Include binary artifacts
  max_file_size_mb: 100               # Larger file size limit
}
```

### Environment-Specific Configuration

You can configure different collection settings per environment:

```ruby
environment_manager = EnvironmentManager.new({
  artifacts_dir: '/path/to/artifacts',
  artifact_configs: {
    'production-test' => {
      artifact_types: [:logs, :config_files],
      create_archive: true
    },
    'debug-env' => {
      artifact_types: ALL_ARTIFACT_TYPES,
      include_binary_files: true
    }
  }
})
```

## Output Structure

Artifacts are organized in a timestamped directory structure:

```
artifacts/
├── environment-name/
│   ├── 20241227-143052/
│   │   ├── logs/
│   │   │   ├── journal.log
│   │   │   ├── syslog
│   │   │   └── dmesg.log
│   │   ├── screenshots/
│   │   │   └── current-20241227-143052.png
│   │   ├── system_state/
│   │   │   ├── processes.txt
│   │   │   ├── memory.txt
│   │   │   └── network.txt
│   │   ├── config_files/
│   │   ├── package_state/
│   │   ├── service_state/
│   │   ├── performance_data/
│   │   ├── test_output/
│   │   ├── error_traces/
│   │   ├── environment_info/
│   │   ├── collection_metadata.yaml
│   │   ├── debugging_report.html
│   │   └── index.html
│   └── 20241227-145234/
└── sessions/
    └── session-20241227-150000/
```

## Artifact Management

### Automatic Cleanup

The system automatically manages artifact storage:

- **Age-based cleanup**: Removes artifacts older than specified days (default: 30)
- **Size-based limits**: Enforces storage limits (default: 5GB)
- **Orphaned resource cleanup**: Removes incomplete or corrupted collections

### Manual Management

```ruby
# Get artifact history
history = environment.get_artifact_history(20)

# Clean up old artifacts
environment.cleanup_old_artifacts(max_age_days: 7)

# Generate reports
report_path = environment.create_artifact_report(:html)

# Export artifacts
archive_path = artifact_manager.export_artifacts(
  'env-name', 
  '20241227-143052', 
  :tar_gz
)
```

### Storage Management

```ruby
# Check storage usage
usage = artifact_manager.get_artifact_summary

# Enforce storage limits
result = artifact_manager.enforce_storage_limits(5) # 5GB limit

# Compare artifact collections
comparison = artifact_manager.compare_artifact_collections(
  'env-name', 
  '20241227-143052', 
  '20241227-145234'
)
```

## Integration with Test Framework

### Test Runner Integration

```ruby
class TestRunner
  def run_test(recipe_path)
    begin
      # Execute test
      result = execute_mitamae_recipe(recipe_path)
      
      if result.failed?
        # Automatically collect failure artifacts
        artifacts = environment.collect_failure_artifacts({
          test_name: File.basename(recipe_path),
          error_message: result.error_message,
          stack_trace: result.stack_trace,
          exit_code: result.exit_code
        })
        
        result.artifacts = artifacts
      end
      
      result
    rescue => e
      # Collect artifacts for unexpected failures
      artifacts = environment.collect_failure_artifacts({
        test_name: File.basename(recipe_path),
        error_message: e.message,
        stack_trace: e.backtrace,
        exception: e.class.name
      })
      
      raise TestFailure.new(e.message, artifacts)
    end
  end
end
```

### Session-Level Collection

For multi-environment test sessions:

```ruby
session = environment_manager.create_test_session(session_config)

begin
  session.provision_all(recipe_paths)
  session_result = run_session_tests(session)
ensure
  # Collect artifacts from all environments in session
  session_artifacts = session.collect_all_artifacts(session_result)
  
  # Generate consolidated session report
  session_report = artifact_manager.create_session_report(
    session, 
    session_artifacts
  )
end
```

## Browsable Reports

The system generates HTML reports for easy browsing of collected artifacts:

### Debugging Report

Each artifact collection includes a `debugging_report.html` with:

- Collection summary and metadata
- Links to all collected artifacts
- Error information (if any)
- Environment information
- Quick navigation to key files

### Artifact Index

The `index.html` provides:

- Overview of all artifact types
- File browser interface
- Search functionality
- Direct links to log files and screenshots

### Session Reports

Session-level reports include:

- Multi-environment comparison
- Consolidated test results
- Cross-environment artifact links
- Session timeline and duration

## Best Practices

### For Developers

1. **Always collect artifacts on test failures** - Use automatic collection
2. **Review debugging reports first** - Start with the HTML summary
3. **Check screenshots for visual tests** - Essential for desktop environment testing
4. **Compare artifact collections** - Use comparison tools to identify changes
5. **Clean up regularly** - Use automatic cleanup or manual cleanup commands

### For CI/CD Integration

1. **Archive artifacts for failed builds** - Export to build artifacts
2. **Set appropriate retention policies** - Balance storage vs debugging needs
3. **Generate JSON reports** - For programmatic analysis
4. **Use session-level collection** - For complex multi-environment tests

### Performance Considerations

1. **Limit artifact types for routine testing** - Only collect essential artifacts
2. **Use failure-specific collection** - Comprehensive collection only on failures
3. **Monitor storage usage** - Implement storage limits and cleanup
4. **Avoid collecting large binary files** - Unless specifically needed

## Troubleshooting

### Common Issues

**Collection timeouts**: Increase timeout in configuration
```ruby
config[:timeout] = 600  # 10 minutes
```

**Large artifact sizes**: Reduce file size limits
```ruby
config[:max_file_size_mb] = 25
```

**Storage space issues**: Implement aggressive cleanup
```ruby
artifact_manager.cleanup_old_artifacts(nil, 3)  # Keep only 3 days
```

**Missing artifacts**: Check environment permissions and paths
```ruby
# Verify environment access
environment.execute("ls -la /var/log")
```

### Debug Collection Issues

Enable debug logging to troubleshoot collection problems:

```ruby
config[:debug] = true
config[:verbose_logging] = true
```

Check collection metadata for error details:

```ruby
metadata = YAML.load_file('collection_metadata.yaml')
puts "Errors: #{metadata[:errors]}"
```

## Future Enhancements

The artifact collection system is designed to be extensible:

- **Custom artifact types**: Add domain-specific collectors
- **Remote storage**: Support for cloud storage backends
- **Real-time monitoring**: Live artifact streaming during test execution
- **Machine learning**: Automated failure pattern detection
- **Integration APIs**: REST API for external tools
- **Advanced visualization**: Interactive dashboards and timelines