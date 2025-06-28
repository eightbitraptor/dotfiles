# PRD: Mitamae Testing Strategy

## Introduction/Overview

This PRD defines a comprehensive testing strategy for validating mitamae recipe execution in the dotfiles repository. The current manual testing approach is insufficient for ensuring reliable system provisioning, particularly for complex Wayland compositor configurations and cross-distribution compatibility. This feature will provide automated validation that recipes make expected changes to target systems, with special focus on graphical environment functionality.

## Goals

1. **Automated Validation**: Replace manual container testing with automated test suites that validate recipe execution results
2. **Graphical Environment Testing**: Ensure Wayland compositor configurations (Sway, LabWC) and supporting components work correctly
3. **Cross-Platform Reliability**: Validate recipes work correctly across target distributions with extensible architecture
4. **Repeatable Builds**: Provide consistent, deterministic test environments that run on macOS and Linux hosts
5. **Comprehensive Coverage**: Test all recipe categories including packages, configurations, services, and hardware-specific setups

## User Stories

1. **As a maintainer**, I want to validate that recipes work correctly before merging changes so that I don't break users' systems
2. **As a developer**, I want to test recipe changes locally so that I can iterate quickly without manual container setup
3. **As a developer**, I want to run comprehensive tests locally before committing changes so that I can validate my work privately
4. **As a user**, I want confidence that running recipes won't leave my system in a broken state so that I can safely apply updates

## Functional Requirements

### Core Testing Infrastructure

1. **Test Environment Management**: System must provide isolated, reproducible test environments using containers or VMs
2. **Multi-Distribution Support**: System must support Arch Linux initially with extensible architecture for adding Ubuntu, Fedora, Void Linux
3. **Host Compatibility**: System must run on both macOS and Linux development machines
4. **Clean State Guarantee**: Each test run must start from a known clean state to ensure reproducible results

### Test Categories

5. **Package Management Validation**: System must verify correct installation of standard packages, AUR packages (Arch), and Flatpak applications
6. **Configuration File Testing**: System must validate symlink creation, template rendering, file permissions, and directory structure
7. **Service Management Testing**: System must verify systemd/runit service states, user group membership, and permission assignments
8. **Graphical Environment Validation**: System must test Wayland compositor startup, display configuration, audio pipeline, and desktop component integration
9. **Idempotency Testing**: System must verify that re-running recipes produces no changes when system is already configured

### Test Execution Modes

10. **Fresh Installation Testing**: System must test complete recipe execution on clean systems
11. **Incremental Update Testing**: System must test applying recipe changes to previously configured systems
12. **Manual Execution**: System must support on-demand test execution for development workflow
13. **Local Test Execution**: System must provide comprehensive local test execution with detailed reporting

### Validation Methods

14. **File System Validation**: System must verify file existence, content, permissions, and ownership
15. **Service Status Verification**: System must check systemd/runit service states and process existence  
16. **Package Installation Verification**: System must confirm installed packages match recipe specifications
17. **Functional Testing**: System must validate that configured applications can launch and function correctly
18. **Visual Validation**: System must capture screenshots or perform basic UI interaction testing for graphical components

### Reporting and Debugging

19. **Test Result Reporting**: System must provide detailed pass/fail status with specific failure reasons
20. **Artifact Collection**: System must capture logs, screenshots, and configuration files for debugging failed tests
21. **Execution Logging**: System must provide verbose logging of recipe execution and system state changes

## Non-Goals (Out of Scope)

1. **Performance Testing**: Will not measure recipe execution speed or resource usage optimization
2. **Security Penetration Testing**: Will not test for security vulnerabilities in configurations
3. **User Interface Testing**: Will not test complex user workflows or GUI application functionality
4. **Network-Dependent Testing**: Will not test configurations requiring external network services
5. **Hardware-Specific Testing**: Will not test hardware device compatibility (audio, graphics drivers)
6. **Multi-User Environment Testing**: Will not test configurations in multi-user system scenarios
7. **Remote CI/CD Integration**: Will not implement automated testing in external CI/CD platforms or remote build systems

## Technical Considerations

### Container vs VM Trade-offs

- **Containers (Podman)**: Faster startup, efficient resource usage, but limited systemd/graphical testing capabilities
- **VMs**: Full system isolation, complete systemd support, graphical environment testing, but slower and more resource-intensive
- **Recommendation**: Hybrid approach - containers for basic validation, VMs for graphical/service testing

### Platform Architecture

- **Host Requirements**: Podman or VM solution (QEMU/KVM) with nested virtualization support
- **Base Images**: Official distribution images (archlinux:latest) with systemd and graphical packages pre-installed
- **Artifact Management**: Shared volumes for recipe files and test artifacts

### Integration Points

- **Existing Infrastructure**: Leverage current Containerfile.fedora/void approach but extend with automation
- **Recipe Dependencies**: Must handle recipe interdependencies and execution order
- **Distribution Abstraction**: Design extensible plugin system for adding new distributions

## Success Metrics

1. **Test Coverage**: 95% of recipe functionality covered by automated tests
2. **Detection Rate**: Catch 90% of recipe breaking changes before manual testing
3. **Execution Time**: Complete test suite runs in under 30 minutes for single distribution
4. **False Positive Rate**: Less than 5% of failing tests are due to test infrastructure issues
5. **Development Velocity**: Reduce manual testing time from 2 hours to 15 minutes per change

## Open Questions

1. **Container Privileges**: What level of host privileges are needed for systemd and graphical testing in containers?
2. **Display Server Testing**: How can we validate graphical components on development machines with different display configurations?
3. **AUR Testing Reliability**: How do we handle AUR package availability/build failures in tests?
4. **Test Data Management**: How do we manage test-specific configuration variations and secrets?
5. **Resource Requirements**: What are the minimum host system requirements for running the complete test suite?
6. **Local Resource Management**: How do we optimize resource usage for concurrent test execution on development machines?
7. **Distribution Base Images**: Which specific base images provide the best balance of testing capability and setup time?