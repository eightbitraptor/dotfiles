if node.os == "linux"
  packages = %w{
    emacs
    jetbrains-mono-nl-fonts
    jetbrains-mono-fonts
  }

  packages.each do |pname|
    package pname do
      action :install
    end
  end
end

git "Emacs config" do
  repository "git@github.com:eightbitraptor/dotemacs"
  user node.user
  destination "#{node.home_dir}/.emacs.d"
end
