packages = %w{
  labwc
  ulauncher
  feh
}

packages.each do
  package _1 do
    action :install
  end
end

dotfiles = {
  ".config/labwc/menu.xml" => "labwc/menu.xml",
  ".config/labwc/rc.xml" => "labwc/rc.xml",
  ".config/labwc/autostart" => "labwc/autostart",
  ".config/labwc/environment" => "labwc/environment",
}
