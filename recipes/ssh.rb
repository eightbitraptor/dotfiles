packages = %w{
  openssh
  openssh-clients
}.each do |pname|
  package pname do
    action :install
  end
end

dotfile ".ssh/config" do
  source "ssh/config"
end
