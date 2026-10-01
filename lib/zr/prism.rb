# frozen_string_literal: true

require_relative "ports"

module Zr
  # Whether ruby itself runs the compiler. Ruby finds prism on its load
  # path. A zr binary that includes the compiler has prism compiled in
  # and no load path.
  HOSTED = !$LOAD_PATH.resolve_feature_path("prism").nil?
end

# The host's prism: the vendored Ruby part of prism 1.9.0
# (vendor/ruby, Zr::Ports.lib) on top of zr's Ruby port of prism's C
# (lib/zr/runtime/ext/prism/ruby). A zr binary links in the same tree. Both
# directories go ahead of ruby's own prism. prism_shim contains only
# prism/prism.rb. A process that loaded ruby's prism first keeps it,
# because both return the same objects. The paths are literal, so zr
# sees them when it compiles zr (`Ports.lib("prism")` names the first;
# prism_test.rb checks that they agree).
$LOAD_PATH.unshift(File.expand_path("../../vendor/ruby/lib/ruby/gems/4.0.0/gems/prism-1.9.0/lib", __dir__),
                   File.expand_path("prism_shim", __dir__))
require "prism"

module Zr
  # prism finds the line of a byte offset with a binary search over the
  # line starts. The builder asks once or more for each node (5% of a
  # warm build of bundler), and reads the nodes mostly in source order.
  # So the line of the last answer, or the line after it, is almost
  # always the answer, and a binary search is left for the rest. The
  # answer is the same as prism's.
  module LineCursor
    private

    def find_line(byte_offset)
      return super if frozen?

      starts = offsets
      at = @zr_line || 0
      if starts[at] <= byte_offset
        after = at + 1
        return at if after == starts.length || byte_offset < starts[after]
        return @zr_line = after if after + 1 == starts.length || byte_offset < starts[after + 1]
      end
      @zr_line = super
    end
  end
end
Prism::Source.prepend(Zr::LineCursor)
