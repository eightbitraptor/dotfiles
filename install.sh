#!/bin/sh

. bin/setup.sh

log_level="${EBR_LOG_LEVEL:-info}"

MITAMAE_CMD="./bin/mitamae local base.rb --log-level=$log_level"

if [ ! `which sudo 2>/dev/null` ]; then
  su -c '$MITAMAE_CMD'
elif [ `uname -s` = "Darwin" ]; then
  $MITAMAE_CMD
else
  sudo -E $MITAMAE_CMD
fi
