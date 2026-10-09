# frozen_string_literal: true

require_relative "library/ports"
require_relative "line_cursor"

# The host's prism: the vendored Ruby part of prism 1.9.0
# (vendor/ruby, Zr::Library::Ports.lib) on top of zr's Ruby port of prism's C
# (lib/zr/runtime/ext/prism/ruby). A zr binary links in the same tree. Both
# directories go ahead of ruby's own prism. prism_shim contains only
# prism/prism.rb. A process that loaded ruby's prism first keeps it,
# because both return the same objects. The paths are literal, so zr
# sees them when it compiles zr (`Library::Ports.lib("prism")` names the first;
# prism_test.rb checks that they agree).
$LOAD_PATH.unshift(File.expand_path("../../vendor/ruby/lib/ruby/gems/4.0.0/gems/prism-1.9.0/lib", __dir__),
                   File.expand_path("prism_shim", __dir__))
require "prism"

Prism::Source.prepend(Zr::LineCursor)
