#!/bin/bash
# Test dependency installation script for mitamae testing framework
# Installs Podman and QEMU dependencies on development machines

set -euo pipefail

echo "Mitamae Testing Framework - Dependency Setup"
echo "============================================="

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
else
    echo "Error: Unsupported OS: $OSTYPE"
    exit 1
fi

echo "Detected OS: $OS"

# Check for Podman
if command -v podman &> /dev/null; then
    echo "✓ Podman already installed: $(podman --version)"
else
    echo "Installing Podman..."
    case $OS in
        macos)
            if command -v brew &> /dev/null; then
                brew install podman
            else
                echo "Error: Homebrew required for macOS Podman installation"
                exit 1
            fi
            ;;
        linux)
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y podman
            elif command -v pacman &> /dev/null; then
                sudo pacman -S podman
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y podman
            else
                echo "Error: Unsupported Linux distribution"
                exit 1
            fi
            ;;
    esac
fi

# Check for QEMU (for VM testing)
if command -v qemu-system-x86_64 &> /dev/null; then
    echo "✓ QEMU already installed"
else
    echo "Installing QEMU..."
    case $OS in
        macos)
            if command -v brew &> /dev/null; then
                brew install qemu
            else
                echo "Warning: QEMU installation skipped (Homebrew required)"
            fi
            ;;
        linux)
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils
            elif command -v pacman &> /dev/null; then
                sudo pacman -S qemu-desktop
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y qemu-system-x86 qemu-img
            else
                echo "Warning: QEMU installation skipped (unsupported distribution)"
            fi
            ;;
    esac
fi

echo
echo "Setup complete! Testing framework dependencies ready."
echo "Usage: ruby test/runner.rb --help"