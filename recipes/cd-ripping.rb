# CD Ripping Pipeline Recipe
# Implements comprehensive CD ripping workflow with whipper, beets, and multi-format output
# Supports AccurateRip verification, multi-source metadata, and dual FLAC/MP3 output

# Distribution-specific package mapping
packages = {
  arch: %w[whipper beets python-pip ffmpeg],
  fedora: %w[whipper beets python3-pip ffmpeg],
  void: %w[whipper beets python3-pip ffmpeg]
}

# Install core packages
packages[node.distro.intern].each do |pkg|
  package pkg do
    action :install
  end
end

# Install Python dependencies
pip_packages = %w[
  pylast
  requests
  discogs-client
  whipper-plugin-eaclogger
]

pip_packages.each do |pkg|
  execute "Install #{pkg}" do
    command "pip install --user #{pkg}"
    user node.user
    not_if "pip show #{pkg}"
  end
end

# Create output directories
["/data/flac", "/data/mp3"].each do |dir|
  directory dir do
    owner node.user
    group "mpd"
    mode "755"
  end
end

# Create staging directory
directory "/tmp/whipper-staging" do
  owner node.user
  group node.user
  mode "755"
  recursive true
end

# Create whipper configuration file
dotfile_template ".config/whipper/whipper.conf" do
  source "whipper/whipper.conf.erb"
  variables(
    staging_dir: "/tmp/whipper-staging",
    flac_dir: "/data/flac"
  )
end

# Create beets configuration file
dotfile_template ".config/beets/config.yaml" do
  source "beets/config.yaml.erb"
  variables(
    flac_library: "/data/flac",
    mp3_library: "/data/mp3",
    staging_dir: "/tmp/whipper-staging"
  )
end

# Create main Python ripping script
dotfile_template ".local/bin/rip-cd.py" do
  source "cd-ripping/rip-cd.py.erb"
  variables(
    flac_dir: "/data/flac",
    mp3_dir: "/data/mp3",
    staging_dir: "/tmp/whipper-staging"
  )
end

# Make rip script executable
file File.join(node.home_dir, ".local", "bin", "rip-cd.py") do
  mode "755"
end

# Create helper script for drive offset detection
dotfile_template ".local/bin/detect-drive-offset.sh" do
  source "cd-ripping/detect-drive-offset.sh.erb"
end

# Make offset detection script executable
file File.join(node.home_dir, ".local", "bin", "detect-drive-offset.sh") do
  mode "755"
end

# Create cleanup script
dotfile_template ".local/bin/cleanup-rip-staging.sh" do
  source "cd-ripping/cleanup-rip-staging.sh.erb"
  variables(
    staging_dir: "/tmp/whipper-staging"
  )
end

# Make cleanup script executable
file File.join(node.home_dir, ".local", "bin", "cleanup-rip-staging.sh") do
  mode "755"
end

# Ensure user is in appropriate groups for CD access
case node.distro
when "arch"
  group_add "optical" do
    user node.user
  end
when "fedora"
  group_add "cdrom" do
    user node.user
  end
when "void"
  group_add "cdrom" do
    user node.user
  end
end

# Create systemd service for automatic cleanup (optional)
dotfile_template ".config/systemd/user/rip-cleanup.service" do
  source "cd-ripping/rip-cleanup.service.erb"
  variables(
    cleanup_script: File.join(node.home_dir, ".local", "bin", "cleanup-rip-staging.sh")
  )
end

# Create systemd timer for cleanup
dotfile_template ".config/systemd/user/rip-cleanup.timer" do
  source "cd-ripping/rip-cleanup.timer.erb"
end

# Enable and start cleanup timer
execute "Enable rip cleanup timer" do
  command "systemctl --user enable rip-cleanup.timer"
  user node.user
  not_if "systemctl --user is-enabled rip-cleanup.timer"
end

execute "Start rip cleanup timer" do
  command "systemctl --user start rip-cleanup.timer"
  user node.user
  not_if "systemctl --user is-active rip-cleanup.timer"
end

# Add PATH to include user local bin directory (if not already in modern distributions)
execute "Add user local bin to PATH" do
  command "echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> #{node.home_dir}/.bashrc"
  user node.user
  not_if "grep -q 'export PATH=\"\\$HOME/.local/bin:\\$PATH\"' #{node.home_dir}/.bashrc"
end

# Create README with usage instructions
dotfile_template ".local/bin/CD-RIPPING-README.md" do
  source "cd-ripping/README.md.erb"
  variables(
    flac_dir: "/data/flac",
    mp3_dir: "/data/mp3",
    staging_dir: "/tmp/whipper-staging",
    bin_dir: "~/.local/bin"
  )
end
