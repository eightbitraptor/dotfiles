#!/usr/bin/env bash

set -e

source bin/setup.sh

sudo -E ./bin/mitamae local "base.rb" --log-level=debug

