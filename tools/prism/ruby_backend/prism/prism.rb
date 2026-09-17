# frozen_string_literal: true

# The Ruby backend in place of prism's C extension, for a host ruby: with
# this directory on the load path, the gem's `require "prism/prism"` finds
# this file before the extension's bundle (a .rb wins over a .bundle on any
# load path), and the gem runs on the Ruby port alone.
require_relative "../../../../rt/ext/prism/ruby/init"
