packages = %w{
  fcitx5
  fcitx5-qt
  fcitx5-gtk
  fcitx5-configtool

  # Japanese language IM
  fcitx5-mozc
}

packages.each do |pkg|
  package pkg do
    action :install
  end
end

