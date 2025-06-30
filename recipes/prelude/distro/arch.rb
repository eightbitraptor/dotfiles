%w{
  imagemagick
  btop
  base-devel
  python-pipx
  
}.each do |pname|
  package pname do
    action :install
  end
end

fonts = %w{
  noto-fonts
  noto-fonts-emoji
  noto-fonts-cjk
  noto-fonts-extra
  ttf-jetbrains-mono-nerd
  ttf-jetbrains-mono
  ttf-font-awesome
}.each do |f|
  package f do
    action :install
  end
end

git "yay pkgbuild" do
  repository "https://aur.archlinux.org/yay.git"
  user node.user
  destination "/tmp/yay-build"
end

execute "build and install yay" do
  command "makepkg -si --noconfirm"
  user node.user
  cwd "/tmp/yay-build"
  not_if "pacman -Q yay"
end

# Include AUR package plugin for Arch Linux
if node.distro == "arch"
  include_recipe File.expand_path("../recipes/plugins/aur_package.rb", __dir__)
end

