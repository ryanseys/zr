# frozen_string_literal: true

require_relative "prism"

module Zr
  # Prism.parse for the compiler. It uses the parse cache when the parser
  # is zr's port.
  def self.parse(source, **options)
    defined?(Cache::Parse) ? Cache::Parse.parse(source, **options) : Prism.parse(source, **options)
  end
end

# ruby's own prism parses fast enough without a cache, and a binary has no
# cache to write.
require_relative "cache/parse" if Zr::HOSTED && Prism.method(:parse).source_location&.first == File.join(Zr::Library::Layout::EXT, "prism/prism.rb")
