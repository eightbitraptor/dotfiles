group_add "audio"
group_add "video"

packages = %w{
  pipewire
  wireplumber
  pulseaudio-utils
}

packages.each do |pname|
  package pname do
    action :install
  end
end

pipewire_conf_dest = "#{node.home_dir}/.config/pipewire/pipewire.conf.d"
directory pipewire_conf_dest

link "#{pipewire_conf_dest}/10-wireplumber.conf" do
  to "/usr/share/examples/wireplumber/10-wireplumber.conf"
end

link "#{pipewire_conf_dest}/20-pipewire-pulse.conf" do
  to "/usr/share/examples/pipewire/20-pipewire-pulse.conf"
end

dotfile ".config/service/pipewire" do
  source "user_services/pipewire"
end
