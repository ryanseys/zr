# frozen_string_literal: true

# prism's C extension in Ruby for the host: with this directory on the
# load path, prism.rb's `require "prism/prism"` finds this file before
# any extension bundle (a .rb wins over a .bundle on any load path), as a
# zr binary finds runtime/ext/prism/prism.rb.
require_relative "../../../../runtime/ext/prism/prism"
