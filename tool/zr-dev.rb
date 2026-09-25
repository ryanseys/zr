#!/usr/bin/env ruby
# frozen_string_literal: true

# zr-dev: the tools that work on a zr checkout. `zr-dev help` lists them,
# and `zr-dev <command> --help` gives the options of one.
#
#   ruby tool/zr-dev.rb gen unicode        under ruby, from any directory
#   bin/zr-dev gen unicode                 the same tools, compiled by zr
#                                          (`rake build:tools`)
require_relative "commands"

exit Zr::Dev.start(ARGV)
