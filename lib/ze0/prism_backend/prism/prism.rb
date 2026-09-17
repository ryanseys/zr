# frozen_string_literal: true

# prism's C extension in Ruby: with this directory on the load path, the
# prism gem's `require "prism/prism"` finds this file before the
# extension's bundle (a .rb wins over a .bundle on any load path), and the
# gem runs on ze0's port of prism's C (rt/ext/prism/ruby) alone.
require_relative "../../../../rt/ext/prism/ruby/init"
