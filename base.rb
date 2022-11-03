puts ENV['PATH']

node.reverse_merge!(
  os: run_command('uname').stdout.strip.downcase,
  hostname: run_command('hostname').stdout.split('.').first.downcase.strip,
  user: ENV['SUDO_USER'] || ENV['USER'],
  home_dir: run_command("getent passwd #{ENV['SUDO_USER'] || ENV['USER']}")
    .stdout.split(':')[5].strip,
)

REPO_ROOT   = File.dirname(__FILE__)
RECIPES_DIR = File.expand_path("recipes", REPO_ROOT)
NODES_DIR   = File.expand_path("nodes", REPO_ROOT)
FILES_DIR   = File.expand_path("files", REPO_ROOT)

define :include_local_recipe do
  include_recipe "#{RECIPES_DIR}/#{params[:name]}.rb"
end

define :dotfile, source: nil do
  puts params[:name].inspect
  links = if params[:name].is_a?(String)
    { params[:name] => params[:source] }
  else
    params[:name]
  end
    
  puts links.inspect
  links.each do |to, from|
    destination = File.expand_path(to, node[:home_dir])
    source      = File.expand_path(from, FILES_DIR)

    link destination do
      to source
    end
  end
end

include_recipe "#{NODES_DIR}/#{node[:hostname]}.rb"
