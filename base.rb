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
    .stdout.strip.gsub('"','')
else
  "not-linux"
end

$git_host = begin
  ENV.fetch("EBR_GIT_HOST")
rescue KeyError
  $stderr.puts "EBR_GIT_HOST not defined, Please configure this to be the internal Git server address"
end

def get_hostname
  run_command("which hostname")
end

$hostname = begin
  run_command("hostname").stdout.split('.').first.downcase.strip
rescue
  run_command("hostnamectl hostname")
end.stdout.split('.').first.downcase.strip

node.reverse_merge!(
  os: $os,
  distro: $distro,
  hostname: $hostname,
  user: ENV['SUDO_USER'] || ENV['USER'],
  home_dir: $home_dir,
  git_host: $git_host,
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

define :personal_git, destination: nil do
  params[:destination] ? params[:destination] : "#{node.home_dir}/git/#{params[:name]}"

  if node.git_host
    git "Personal #{params[:name]} repo" do
      repository "#{node.git_host}/#{params[:name]}.git"
      user node.user
      destination params[:destination]
    end
  else
    MItamae.logger.warn("EBR_GIT_HOST not configured, skipping clone of #{params[:name]}")
  end
end

# TODO: Upstream a fix to specinfra et al. the runit enable check is incorrect
define :void_service, action: :nothing do
  actions = Array(params[:action])
  name = params[:name]

  unless Dir.exists?("/etc/sv/#{name}")
    MItamae.logger.error("Service name #{name} doesn't exist")
  end

  # sort the array, because we want to enable before we start
  actions.sort.each do |action|
    case action
    when :enable
      MItamae.logger.debug("enabling #{name}")
      unless Dir.exists?("/var/service/#{name}")
        system("ln -s /etc/sv/#{name} /var/service/")
      end
    when :start
      MItamae.logger.debug("starting #{name}")
      system("sv up #{name}")
    else
      MItamae.logger.error("void_service, valid actions are :create, :start")
    end
  end
end

define :group_add, user: node.user do
  name = params[:name]
  user = params[:user]

  execute "add #{user} to #{name} group" do
    command "usermod -aG #{name} #{user}"
    not_if "groups #{user} | grep #{name}"
  end
end

include_recipe "recipes/prelude/#{node.os}.rb"
include_recipe "#{NODES_DIR}/#{node[:hostname]}.rb"
