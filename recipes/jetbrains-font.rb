# https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip

release_path = "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"

case node.distro
when "fedora"
  package "jetbrains-mono-nl-fonts" do
    action :install
  end
when "ubuntu"
  package "fonts-jetbrains-mono" do
    action :install
  end
when "void"
  package "unzip" do
    action :install
  end

  execute "Downloading JetBrains Mono" do
    command "wget -O jbmono.zip #{release_path}"
    cwd "/tmp"
    not_if "test -e /usr/share/fonts/JetBrains-Mono"
  end

  execute "Extract JetBrains Mono" do
    command "unzip /tmp/jbmono.zip -d jbmono"
    cwd "/tmp"
    not_if "test -e /usr/share/fonts/JetBrains-Mono"
  end

  execute "install JetBrains Mono" do
    command "cp -r /tmp/jbmono/fonts/ttf /usr/share/fonts/JetBrains-Mono"
    not_if "test -e /usr/share/fonts/JetBrains-Mono"
  end

  execute "Refresh font cache" do
    command "fc-cache"
    not_if "test -e /usr/share/fonts/JetBrains-Mono"
  end
end
