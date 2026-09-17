# frozen_string_literal: true

# The host's prism: the prism gem's Ruby half over ze0's Ruby port of
# prism's C (rt/ext/prism/ruby), in place of the gem's C extension, so the
# compiler parses with the code a ze0 binary carries. The directory holds
# prism/prism.rb alone, so it hides nothing else on the load path. A
# process that loaded the C extension first keeps it: the two answer
# alike, object for object. A ze0 binary that carries the compiler finds
# no prism on its load path, since it has prism compiled in, and leaves
# the load path as it is.
$LOAD_PATH.unshift(File.expand_path("prism_backend", __dir__)) if $LOAD_PATH.resolve_feature_path("prism")
require "prism"

module Ze0
  # Prism.parse for the compiler: through the parse cache where the parse
  # is the port's.
  def self.parse(source, **options)
    defined?(ParseCache) ? ParseCache.parse(source, **options) : Prism.parse(source, **options)
  end
end

# The C extension parses fast enough without a cache, and the compiler a
# binary carries has neither the port nor a cache to write.
require_relative "parse_cache" if Prism.method(:parse).source_location&.first == File.expand_path("../../rt/ext/prism/ruby/init.rb", __dir__)
