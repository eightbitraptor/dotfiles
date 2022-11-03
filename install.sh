#!/usr/bin/env bash

set -e

source bin/setup.sh

log_level="${EBR_LOG_LEVEL:-info}"

if [[ `uname -s` == "Darwin" ]]; then
  ./bin/mitamae local "base.rb" --log-level=$log_level
else
  sudo -E ./bin/mitamae local "base.rb" --log-level=$log_level
fi

