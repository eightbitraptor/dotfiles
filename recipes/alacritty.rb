include_local_recipe "jetbrains-font"

packages = %w{
  alacritty
}

packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".config/alacritty/alacritty.toml" do
  source "alacritty/alacritty.toml"
end
