packages = %w{
  alacritty
  jetbrains-mono-nl-fonts
}
  
packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".config/alacritty/alacritty.toml" do
  source "alacritty/alacritty.toml"
end
