packages = %w{
  alacritty
}
  
case node.distro
when "fedora"
  packages << "jetbrains-mono-nl-fonts"
when "ubuntu"
  packages << "fonts-jetbrains-mono"
end

packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".config/alacritty/alacritty.toml" do
  source "alacritty/alacritty.toml"
end
