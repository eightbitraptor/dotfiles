node.reverse_merge!(
  mconfig: <<~MCONFIG
    output eDP-1 pos 0 0 scale 1.75
  MCONFIG
)

include_local_recipe "surface_kernel"

include_local_recipe "emacs"
include_local_recipe "vim"
include_local_recipe "sway"
include_local_recipe "fish"

include_local_recipe "mpv"
