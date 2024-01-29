if set -q ALACRITTY_LOG
  cat ~/.cache/wal/sequences
end

# set -Ux QT_IM_MODULE fcitx
set -Ux XMODIFIERS @im=fcitx
# set -Ux GTK_IM_MODULE fcitx

set fish_greeting
if status is-interactive
    # Commands to run in interactive sessions can go here
end

direnv hook fish | source

source /usr/local/share/chruby/chruby.fish

chruby 3.3.0

#status --is-interactive; and ~/.rbenv/bin/rbenv init - fish | source
