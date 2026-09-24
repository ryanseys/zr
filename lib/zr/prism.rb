# frozen_string_literal: true

module Zr
  # Whether ruby itself runs the compiler: ruby finds a prism on its load
  # path, where a zr binary that carries the compiler has prism compiled
  # in and no load path to search.
  HOSTED = !$LOAD_PATH.resolve_feature_path("prism").nil?
end

# The host's prism: the vendored Ruby half of prism 1.9.0
# (vendor/ext/prism/lib) over zr's Ruby port of prism's C
# (runtime/ext/prism/ruby), the same tree a zr binary carries. Both
# directories go ahead of ruby's own prism; prism_backend holds
# prism/prism.rb alone. A process that loaded ruby's prism first keeps
# it: the two answer alike, object for object.
if Zr::HOSTED
  $LOAD_PATH.unshift(File.expand_path("../../vendor/ext/prism/lib", __dir__), File.expand_path("prism_backend", __dir__))
end
require "prism"

module Zr
  # Prism.parse for the compiler: through the parse cache where the parse
  # is the port's.
  def self.parse(source, **options)
    defined?(ParseCache) ? ParseCache.parse(source, **options) : Prism.parse(source, **options)
  end
end

# ruby's own prism parses fast enough without a cache, and a binary has no
# cache to write.
require_relative "parse_cache" if Zr::HOSTED && Prism.method(:parse).source_location&.first == File.expand_path("../../runtime/ext/prism/prism.rb", __dir__)
