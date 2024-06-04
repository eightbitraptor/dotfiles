package "waybar" do
  action :install
end

dotfiles = {
  ".config/waybar/style.css" => "waybar/style.css",
  ".config/waybar/colors.css" => "waybar/colors.css",
  ".config/waybar/modules/battery.py" => "waybar/battery.py",
}

dotfile_template ".config/waybar/config" do
  source "waybar/config.erb"
  variables(
    modules_left: node.waybar_modules_left,
    modules_center: node.waybar_modules_center,
    modules_right: node.waybar_modules_right
  )
end

dotfile dotfiles
