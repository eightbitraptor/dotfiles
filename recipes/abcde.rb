if node.distro == "arch"
  aur_package_notify "abcde"
else
  package "abcde" do
    action :install
  end
end

dotfile ".abcde.conf" do
  source "abcde/abcde.conf"
end
