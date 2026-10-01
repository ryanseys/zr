#!/usr/bin/env ruby
# frozen_string_literal: true

# zr-dev: the tools that work on a zr checkout. `zr-dev help` lists them,
# and `zr-dev <command> --help` gives the options of one.
#
#   bin/zr-dev gen unicode                 the binstub of this file
#   ruby tool/zr-dev.rb gen unicode        the same, from any directory
require_relative "commands"

exit Zr::Dev.start(ARGV)
