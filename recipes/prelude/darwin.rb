include_local_recipe "git"

unless node.hostname == "spin"
  personal_git "scripts" do
    destination "#{node.home_dir}/.scripts"
  end
end

# TODO: the ruby-dev recipe installs bear but is Linux only.
# TODO: pipx is only necessary because dev messes up the python
#       install on the work mac.
PACKAGES = %w{ 
  mg
  htop
  tig
  bear
  pipx
}

PACKAGES.each do |pkg|
  package(pkg) { action :install }
end

pip "compdb" do
  use_pipx true
end
