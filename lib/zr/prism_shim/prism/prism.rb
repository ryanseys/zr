# frozen_string_literal: true

# prism's C extension in Ruby, for the host. With this directory on the
# load path, the `require "prism/prism"` in prism.rb finds this file
# before an extension bundle (a .rb has priority over a .bundle in the
# same load path entry). A zr binary finds lib/zr/runtime/ext/prism/prism.rb
# the same way.
require_relative "../../runtime/ext/prism/prism"
