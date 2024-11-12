package "fuzzel" do
  action :install
end

dotfile ".config/fuzzel/fuzzel.ini" do
  source "fuzzel/fuzzel.ini"
end
