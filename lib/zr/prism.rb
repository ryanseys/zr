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
# directories go ahead of ruby's own prism. prism_backend contains only
# prism/prism.rb. A process that loaded ruby's prism first keeps it,
# because both return the same objects.
if Zr::HOSTED
  $LOAD_PATH.unshift(File.expand_path("../../vendor/ext/prism/lib", __dir__), File.expand_path("prism_backend", __dir__))
end
require "prism"

module Zr
  # Prism.parse for the compiler. It uses the parse cache when the parser
  # is zr's port.
  def self.parse(source, **options)
    defined?(ParseCache) ? ParseCache.parse(source, **options) : Prism.parse(source, **options)
  end
end

# ruby's own prism parses fast enough without a cache, and a binary has no
# cache to write.
require_relative "parse_cache" if Zr::HOSTED && Prism.method(:parse).source_location&.first == File.expand_path("../../runtime/ext/prism/prism.rb", __dir__)
