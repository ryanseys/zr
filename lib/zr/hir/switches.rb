# frozen_string_literal: true

module Zr
  module Hir
    # The ruby switches that change how a program builds: what `zr -n`,
    # `zr -rjson` or `zr --disable-gems` asks for (lib/zr/cli/ruby_options.rb).
    #
    # `prelude` is ruby that runs after the preludes of the build and
    # before the main file's first line: the settings of -w, -I, -r, -E,
    # -s and the others. `verbose` is the $VERBOSE that -W gives when the
    # main file is parsed (nil, false or true): it decides which of that
    # file's parse-time warnings print, as ruby parses after the switches.
    # :runtime (no switches, or a compile at run time) leaves it to $VERBOSE. It is a unit of its own (`Library::Roots::SWITCHES`),
    # so the main file keeps its line numbers. It is part of the runtime,
    # so it can write the globals that ruby makes read-only ($-p, $-l).
    #
    # `command_line` is prism's `command_line` option for the main file:
    # "p", "n", "a", "l" and "x" wrap it in the loop of -n and -p and skip
    # the text before `#!ruby`. `frozen_string_literal` is the default of
    # every file without the magic comment (true or false), or nil for
    # ruby's own default. `gems` is false when rubygems must not load
    # before the program. `inline` is true for -e: such a program has no
    # DATA. `source_encoding` is the encoding of -K, which the main file
    # is read in when it has no magic comment. `debug_frozen_string_literal`
    # (--debug=frozen-string-literal) gives each String literal the place
    # where it was made, which a FrozenError and the chilled warning name.
    # `keep_script_lines` (RubyVM.keep_script_lines at a compile at run
    # time) keeps the spots of an eval's code, so its Locations have a
    # source_range.
    class Switches
      attr_reader :prelude #: String?
      attr_reader :command_line #: String
      attr_reader :frozen_string_literal #: bool?
      attr_reader :gems #: bool
      attr_reader :inline #: bool
      attr_reader :verbose #: bool | Symbol | nil
      attr_reader :source_encoding #: String?
      attr_reader :debug_frozen_string_literal #: bool
      attr_reader :keep_script_lines #: bool

      # @rbs prelude: String?
      # @rbs command_line: String
      # @rbs frozen_string_literal: bool?
      # @rbs gems: bool
      # @rbs inline: bool
      # @rbs verbose: bool | Symbol | nil
      # @rbs source_encoding: String?
      # @rbs debug_frozen_string_literal: bool
      # @rbs keep_script_lines: bool
      # @rbs return: void
      def initialize(prelude: nil, command_line: "", frozen_string_literal: nil, gems: true, inline: false, verbose: :runtime,
                     source_encoding: nil, debug_frozen_string_literal: false, keep_script_lines: false)
        @prelude = prelude
        @source_encoding = source_encoding
        @command_line = command_line
        @frozen_string_literal = frozen_string_literal
        @gems = gems
        @inline = inline
        @verbose = verbose
        @debug_frozen_string_literal = debug_frozen_string_literal
        @keep_script_lines = keep_script_lines
        freeze
      end

      NONE = new

      # The options of `Prism.parse` for a file: `main` is the program's
      # main file.
      #: (bool main) -> Hash[Symbol, untyped]
      def parse_options(main)
        options = {} #: Hash[Symbol, untyped]
        options[:command_line] = command_line if main && !command_line.empty?
        options[:frozen_string_literal] = frozen_string_literal unless frozen_string_literal.nil?
        options[:encoding] = source_encoding if main && source_encoding
        options
      end

      # What a cache key needs: two builds with other switches are other
      # programs.
      #: () -> String
      def key
        [prelude.to_s, command_line, frozen_string_literal.inspect, gems, inline, verbose.inspect, source_encoding.to_s,
         debug_frozen_string_literal, keep_script_lines].join("\0")
      end

      # The part of `key` that shapes the HIR of every file, not only the
      # main one's: the key of a required file's unit (lib/zr/cache/unit.rb).
      #: () -> String
      def unit_key = [frozen_string_literal.inspect, gems, debug_frozen_string_literal, keep_script_lines].join("\0")
    end
  end
end
