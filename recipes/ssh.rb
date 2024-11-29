packages = if node.distro == "ubuntu"
  %w{openssh-server}
else
  %w{openssh}
end

if node.distro == "fedora"
  packages << "openssh-clients"
end

packages.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".ssh/config" do
  source "ssh/config"
end
