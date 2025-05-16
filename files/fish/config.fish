if status --is-interactive && test -f ~/.cache/wal/sequences
  cat ~/.cache/wal/sequences
end

# set -Ux QT_IM_MODULE fcitx
set -Ux XMODIFIERS @im=fcitx
# set -Ux GTK_IM_MODULE fcitx

set fish_greeting
if status is-interactive
    # Commands to run in interactive sessions can go here
end

switch (uname)
  case Linux
    source /usr/local/share/chruby/chruby.fish
  case Darwin
    set -x HOMEBREW_NO_AUTO_UPDATE 1
end

# commands which require binaries installed by homebrew need to come after this
# line.
if test -f /opt/homebrew/bin/brew
  /opt/homebrew/bin/brew shellenv | source
end

if test -f /opt/dev/dev.fish
  source /opt/dev/dev.fish
end

chruby 3.4.4

#status --is-interactive; and ~/.rbenv/bin/rbenv init - fish | source
alias claude="/Users/mattvh/.claude/local/claude"
