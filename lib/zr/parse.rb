# frozen_string_literal: true

require_relative "binary"
require_relative "library/ports"
require_relative "line_cursor"

# The host's prism: the vendored Ruby part of zr's prism port
# (vendor/ruby, Zr::Library::Ports.lib) on top of zr's Ruby port of prism's C
# (lib/zr/runtime/ext/prism/ruby). A zr binary links in the same tree. Both
# directories go ahead of ruby's own prism. prism_shim contains only
# prism/prism.rb. A process that loaded ruby's prism first keeps it,
# because both return the same objects. The paths are literal, so zr
# sees them when it compiles zr (`Library::Ports.lib("prism")` names the first;
# prism_test.rb checks that they agree). A binary that carries the compiler
# found them when it was built, and its program sees ruby's load path.
$LOAD_PATH.unshift(File.expand_path("../../vendor/ruby/lib/ruby/gems/4.1.0+5/gems/prism-1.9.0/lib", __dir__),
                   File.expand_path("prism_shim", __dir__)) unless Zr::Binary.running?
require "prism"

Prism::Source.prepend(Zr::LineCursor)

module Zr
  # Whether a parse here wants the parse cache: on zr's port of prism, and
  # not in a binary. Ruby's own prism parses fast enough without a cache,
  # and a binary has no cache to write.
  PARSE_CACHE = !Binary.running? && Prism.method(:parse).source_location&.first == File.join(Library::Layout::EXT, "prism/prism.rb")

  # Prism.parse for the compiler, through the parse cache when there is
  # one.
  #: (String source, **untyped options) -> Prism::ParseResult
  def self.parse(source, **options)
    cache = parse_cache
    cache ? cache.parse(source, **options) : Prism.parse(source, **options)
  end

  # The parse cache (`Cache::Parse`), or nil. A process that loaded it
  # (the server, a compiled compiler) uses it; otherwise the first parse
  # that wants it (`PARSE_CACHE`) loads it.
  #: () -> singleton(Cache::Parse)?
  def self.parse_cache
    return Cache::Parse if defined?(Cache::Parse)
    return unless PARSE_CACHE

    require_relative "cache/parse"
    Cache::Parse
  end
end
