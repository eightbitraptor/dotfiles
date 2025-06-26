# Install abcde (A Better CD Encoder)
# On Arch Linux, this is only available from AUR
if node.distro == "arch"
  include_recipe File.expand_path("../recipes/plugins/aur_package.rb", __dir__)
  aur_package "abcde"
else
  package "abcde" do
    action :install
  end
end

dotfile ".abcde.conf" do
  source "abcde/abcde.conf"
end
