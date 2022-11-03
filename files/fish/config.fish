if set -q ALACRITTY_LOG
  cat ~/.cache/wal/sequences
end

set fish_greeting
if status is-interactive
    # Commands to run in interactive sessions can go here
end

source /usr/local/share/chruby/chruby.fish

direnv hook fish | source
