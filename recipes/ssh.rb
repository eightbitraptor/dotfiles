packages = %w{
  openssh
}

if node.distro != "void"
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
