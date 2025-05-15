%w{
  imagemagick
  btop
  base-devel
}.each do |pname|
  package pname do
    action :install
  end
end

  git "Emacs config" do
    repository emacs_repo
    user node.user
    destination emacs_destination
    only_if "test `git -o StrictHostKeyChecking=No -T git@github.com` -eq 0"
  end
