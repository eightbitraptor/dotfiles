package "wofi" do
  action :install
end

dotfile ".config/wofi/style.css" do
  source "wofi/style.css"
end
