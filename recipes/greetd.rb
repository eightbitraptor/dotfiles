packages = %w{
  greetd
  gtkgreet
}

packages.each do |pname|
  package pname do
    action :install
  end
end

remote_file "/etc/greetd/config.toml" do
  source "#{FILES_DIR}/greetd/config.toml"
  owner "_greeter"
end

remote_file "/etc/greetd/sway_config" do
  source "#{FILES_DIR}/greetd/greetd-sway-config"
  owner "_greeter"
end

remote_file "/etc/greetd/gtk.css" do
  source "#{FILES_DIR}/greetd/gtk.css"
  owner "_greeter"
end

file "/etc/greetd/environments" do
  content node.greetd_environments
  owner "_greeter"
end

group_add "_seatd" do
  user "_greeter"
end

void_service "greetd" do
  action :enable
end
