# frozen_string_literal: true

module Zr
  # Whether ruby itself runs the compiler. Ruby finds prism on its load
  # path. A zr binary that includes the compiler has prism compiled in
  # and no load path.
  HOSTED = !$LOAD_PATH.resolve_feature_path("prism").nil?
end

# The host's prism: the vendored Ruby part of prism 1.9.0
# (vendor/ext/prism/lib) on top of zr's Ruby port of prism's C
# (runtime/ext/prism/ruby). A zr binary links in the same tree. Both
# directories go ahead of ruby's own prism. prism_shim contains only
# prism/prism.rb. A process that loaded ruby's prism first keeps it,
# because both return the same objects.
if Zr::HOSTED
  $LOAD_PATH.unshift(File.expand_path("../../vendor/ext/prism/lib", __dir__), File.expand_path("prism_shim", __dir__))
end
require "prism"
