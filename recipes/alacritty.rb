packages = %w{
  alacritty
  jetbrains-mono-nl-fonts
}
  
packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".config/alacritty/alacritty.yml" do
  source "alacritty/alacritty.yml"
end
