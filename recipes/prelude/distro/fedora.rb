include_local_recipe "flathub"

%w{
    fontawesome-fonts-all
    jetbrains-mono-fonts-all
}.each do |pname|
  package pname do
    action :install
  end
end
