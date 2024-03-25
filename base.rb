puts ENV['PATH']

$os = run_command('uname').stdout.strip.downcase
$home_dir = case $os
when "linux"
  run_command("getent passwd #{ENV["SUDO_USER"] || ENV["USER"]}")
    .stdout.split(':')[5].strip
else
  ENV["HOME"]
end
$distro = case $os
when "linux"
  run_command("awk '/^ID=/' /etc/*-release | tr -d 'ID='")
    .stdout.strip
else
  "not-linux"
end

node.reverse_merge!(
  os: $os,
  distro: $distro,
  hostname: run_command('hostname').stdout.split('.').first.downcase.strip,
  user: ENV['SUDO_USER'] || ENV['USER'],
  home_dir: $home_dir,
)

REPO_ROOT   = File.dirname(__FILE__)
RECIPES_DIR = File.expand_path("recipes", REPO_ROOT)
NODES_DIR   = File.expand_path("nodes", REPO_ROOT)
FILES_DIR   = File.expand_path("files", REPO_ROOT)
TEMPLATES_DIR = File.expand_path("templates", REPO_ROOT)

define :include_local_recipe do
  include_recipe "#{RECIPES_DIR}/#{params[:name]}.rb"
end

define :dotfile_template, source: nil, variables: {} do
  template_path = "#{node.home_dir}/#{params[:name]}"
  template_root = File.dirname(template_path)

  directory template_root do
    user node[:user]
  end

  template template_path do
    action :create
    owner node.user
    group node.user
    source "#{TEMPLATES_DIR}/#{params[:source]}"
    variables(**params[:variables])
  end
end

define :dotfile, source: nil, owner: node[:user] do
  links = if params[:name].is_a?(String)
    { params[:name] => params[:source] }
  else
    params[:name]
  end
    
  links.each do |to, from|
    destination = File.expand_path(to, node[:home_dir])
    dest_dir    = File.dirname(destination)
    source      = File.expand_path(from, FILES_DIR)

    directory dest_dir do
      user node[:user]
    end

    link destination do
      to source
      user params[:owner]
      force true
    end
  end
end

define :systemd_service, enable: false do 
  Array(params[:action]).each do |action|
    case action
    when :enable
      execute "systemctl enable #{params[:name]}" do
        not_if "[[ `systemctl is-enabled #{params[:name]}` =~ ^enabled ]]"
      end
    when :start
      execute "systemctl start #{params[:name]}" do
        not_if "[[ `systemctl is-active #{params[:name]}` =~ ^active ]]"
      end
    end
  end
end

define :fisher do
  repo, package = params[:name].split('/')

  execute "fish -c \"fisher install #{params[:name]}\"" do
    user node[:user]
    not_if "test $(cat #{node.home_dir}/.config/fish/fish_plugins | grep #{package} | wc -l) -gt 0"
  end
  user node.user
end

define :pip, use_pipx: false do
  if params[:use_pipx]
    pip = "pipx"
    condition = "pipx list | grep #{params[:name]}"
  else
    pip = "pip3"
    condition = "pip3 show #{params[:name]}"
  end
  
  execute "#{pip} install #{params[:name]}" do
    user node[:user]
    not_if "test $(#{condition} | wc -l) -gt 0"
  end
  user node.user
end

include_recipe "recipes/prelude/#{node.os}.rb"
include_recipe "#{NODES_DIR}/#{node[:hostname]}.rb"
