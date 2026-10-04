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
    # DATA.
    class Switches
      attr_reader :prelude #: String?
      attr_reader :command_line #: String
      attr_reader :frozen_string_literal #: bool?
      attr_reader :gems #: bool
      attr_reader :inline #: bool
      attr_reader :verbose #: bool | Symbol | nil

      #: (?prelude: String?, ?command_line: String, ?frozen_string_literal: bool?, ?gems: bool, ?inline: bool, ?verbose: bool | Symbol | nil) -> void
      def initialize(prelude: nil, command_line: "", frozen_string_literal: nil, gems: true, inline: false, verbose: :runtime)
        @prelude = prelude
        @command_line = command_line
        @frozen_string_literal = frozen_string_literal
        @gems = gems
        @inline = inline
        @verbose = verbose
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
        options
      end

      # What a cache key needs: two builds with other switches are other
      # programs.
      #: () -> String
      def key = [prelude.to_s, command_line, frozen_string_literal.inspect, gems, inline, verbose.inspect].join("\0")
    end
  end
end
