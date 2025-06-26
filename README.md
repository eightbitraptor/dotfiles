# Dotfiles (mitamae)

Inspired by [K0kubun's dotfiles](https://github.com/k0kubun/dotfiles) I
transitioned to using [mitamae](https://github.com/itamae-kitchen/mitamae) to
manage my dotfiles.

## Usage

```
git clone git@github.com:eightbitraptor.com/dotfiles-mitamae ~/.dotfiles
cd ~/.dotfiles 
./install.sh
```

## Debugging 

```
EBR_LOG_LEVEL=debug ./install.sh
```

There's a `Containerfile` in the repo, so if you don't want to test on your
local machine then you can build this using

```
podman build .
```

But bear in mind that systemd stuff won't work in a container.

## Structure

### base.rb

Contains glue code and custom definitions that make most of this structure work
together. Also configures the `prelude` recipes - these are OS specific recipes
that should run on every machine of a particular OS. They should do basic OS
specific config that is guaranteed to be needed on every machine of that type.

As a general rule, try not to add new code to the preludes.

### nodes

* `senjougahara` - Development Desktop, Fedora 37.
* `fern` - Personal Laptop, Thinkpad X1 Carbon gen 6, i7-8550U, Void Linux.
* `miyoshi` - Work laptop, Macbook Pro M3, macOS
* `spin` - A basic editing environment when used with [Spin, Shopify's internal
  cloud dev
  env](https://shopify.engineering/shopifys-cloud-development-journey)

### recipes

Individual recipes go here, I try and keep them as single purpose as possible,
hence `sway`, `emacs`, `vim` etc.

#### AUR Package Plugin (Arch Linux)

For Arch Linux systems, there's a custom `aur_package` resource that handles AUR (Arch User Repository) packages automatically. This replaces the old pattern of exiting with manual installation instructions.

**Prerequisites:**
- `yay` must be installed on the system (see installation instructions below)
- Must run as a non-root user (configured via `node[:user]`)
- Arch Linux system with access to the AUR

**Installing yay:**
If yay is not installed, you can install it manually:
```bash
# As a non-root user:
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

**Usage:**

```ruby
# Include the plugin (only needed on Arch)
if node.distro == "arch"
  include_recipe File.expand_path("../recipes/plugins/aur_package.rb", __dir__)
end

# Install an AUR package
aur_package 'google-chrome'

# Remove an AUR package
aur_package 'outdated-package' do
  action :remove
end

# The resource supports notifications like other mitamae resources
aur_package 'visual-studio-code-bin' do
  action :install
  notifies :restart, 'service[code-server]'
end
```

**Features:**
- Automatic dependency resolution via yay
- Idempotent operations (safe to run multiple times)
- Comprehensive error handling with helpful messages
- Exit code translation for better debugging
- Validates package names and user permissions

**Error Handling:**
The plugin provides clear error messages for common issues:
- Missing yay installation (with installation instructions)
- Build failures (with common causes)
- Dependency resolution failures
- Running as root (not allowed for AUR)

**Limitations:**
- No support for specific package versions (always installs latest)
- No support for custom PKGBUILD files
- Cannot specify makepkg flags or build options
- No parallel package installation
- No built-in caching of built packages
- Only supports yay as the AUR helper (not paru, trizen, etc.)
- Cannot handle interactive prompts (runs with --noconfirm)

**Troubleshooting:**
- If a package fails to build, check the yay output for specific errors
- For dependency issues, try updating the package database: `yay -Sy`
- For persistent failures, try installing the package manually with yay to see interactive prompts
- Ensure your user has sudo privileges for package installation

### files

Associated with recipes, convention is to put files in a subdirectory according
to their recipe, so `files/git/gitconfig` etc.

### templates

Follow the same convention as files

