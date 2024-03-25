include_local_recipe "prelude/shared"

# TODO: the ruby-dev recipe installs bear but is Linux only.
# TODO: pipx is only necessary because dev messes up the python
#       install on the work mac.
PACKAGES = %w{ 
  mg
  git
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
