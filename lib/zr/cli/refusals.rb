# frozen_string_literal: true

require_relative "../version"
require_relative "../config"
require_relative "../refused"
require_relative "../paths"

module Zr
  module CLI
    # The ways that zr says no, with exit status 3 (`CLI::REFUSED`): a
    # ruby that zr does not run on, a target that this host cannot build for
    # or run, and a program that zr does not support. The test harness
    # counts this status separately from zr's defects.
    module Refusals
      TARGET_NAMES = { "aarch64-apple-darwin" => "macOS on Apple Silicon" }.freeze

      # The page that lists what zr supports, for the user who reads a
      # refusal.
      SUPPORT = "#{DOCS_URL}/reference/support.md".freeze

      module_function

      # Why this compiler must not build on a ruby of `version`, or nil
      # when it runs there.
      #: (?String version) -> String?
      def host_refusal(version = RUBY_VERSION)
        return if Zr.supported_ruby?(version)

        "zr #{VERSION} runs on ruby #{RUBY_MINIMUM} or later. Install ruby #{RUBY_PIN}: #{DOCS_URL}/how-to/install.md"
      end

      # A note for a ruby that zr runs on but is not tested with (another
      # series than RUBY), or nil.
      #: (?String version) -> String?
      def host_note(version = RUBY_VERSION)
        return if Zr.tested_ruby?(version) || !Zr.supported_ruby?(version)

        "zr #{VERSION} is tested with ruby #{RUBY_PIN}; this is ruby #{version}"
      end

      # Stops a build on a ruby that zr does not run on, before it reads
      # the program. Warns once on a ruby that it is not tested with.
      #: (?String version) -> void
      def pinned!(version = RUBY_VERSION)
        if (note = host_note(version))
          warn "zr: warning: #{note}"
          return
        end
        return unless (why = host_refusal(version))

        warn "zr: #{why}"
        exit REFUSED
      end

      # Refuses a build that this host cannot make for `target`, before the
      # compile starts. zr's own Mach-O linker builds an
      # aarch64-apple-darwin binary on any host, but only that host can run
      # it. A cross toolchain builds a binary that only its target host
      # runs.
      #: (String input, String verb, String? emit, Target target, ?chosen: bool) -> void
      def refuse(input, verb, emit, target, chosen: true)
        why = target.refusal(emit)
        if why.nil? && verb == "run" && emit.nil? && !target.runs_here?
          why = "#{foreign(target, chosen)} To run the program here, use 'zr run --emit wasm #{input}'."
        end
        if why.nil? && verb == "build" && emit.nil? && !chosen && !target.runs_here?
          warn "zr: #{foreign(target, chosen)} Give --emit wasm for a module that runs here with wasmtime."
        end
        return unless why

        warn "zr: #{input}: #{why}"
        exit REFUSED
      end

      # The words for a native target that this host cannot run. `chosen`
      # is false when the build took the default target, not a --target.
      #: (Target target, bool chosen) -> String
      def foreign(target, chosen)
        what = "this computer cannot run #{target.triple} binaries."
        return what if chosen

        "#{what} zr builds one for #{TARGET_NAMES.fetch(target.triple, target.triple)}."
      end

      # What `zr` prints when it refuses a program: the message, then for a
      # form of Ruby, the source line with a caret and the page that lists
      # what zr supports.
      #: (Refused error) -> String
      def refusal_report(error)
        lines = ["zr: #{error.message}"] #: Array[String?]
        if error.form
          lines << error.excerpt if error.excerpt
          lines << "zr: #{SUPPORT} lists what zr supports"
        end
        lines.join("\n")
      end

      # ruby's report of a syntax error, as its error_print writes it: the
      # message's first line after `prefix` (the script's name, or the
      # program's for -c) and the class, then the lines that show where.
      #: (String prefix, Exception error) -> String
      def syntax_text(prefix, error)
        first, rest = error.message.split("\n", 2)
        "#{prefix}: #{first} (#{error.class})\n#{rest}\n"
      end

      # The parse's warnings, as ruby prints them as it parses `input`:
      # none under -W0 (`verbose` nil), and those of the -w level only
      # under -w (`verbose` true).
      #: (Prism::ParseResult result, String input, bool | Symbol | nil verbose) -> String
      def warning_lines(result, input, verbose)
        return "" if verbose.nil?

        shown = Paths.shown(input)
        result.warnings.filter_map do |w|
          "#{shown}:#{w.location.start_line}: warning: #{w.message}\n" if w.level == :default || verbose == true
        end.join
      end

      # The warnings that ruby prints before its report of `source` (the
      # program `input`), which does not parse; nil when `source` parses,
      # so a file that it requires did not.
      #: (String input, String source, Hir::Switches switches) -> String?
      def syntax_warnings(input, source, switches)
        require_relative "../parse"
        result = Zr.parse(source, filepath: input, **switches.parse_options(true))
        warning_lines(result, input, switches.verbose) unless result.errors.empty?
      end

      # The program that ends as ruby does for a script that does not
      # parse, after the -r requires ran: the parse's warnings (`warned`),
      # then the error as error_print writes it, through
      # SyntaxError#detailed_message, which syntax_suggest (and the
      # program) may extend. The api of syntax_suggest is required here, as
      # its detailed_message requires it by a name that the build cannot
      # see.
      #: (String input, SyntaxError error, String warned) -> String
      def syntax_error_program(input, error, warned)
        <<~RUBY
          # syntax_suggest's decorator requires its search as it runs.
          # The binary carries the search; running it now would load the
          # decorator before the first display, which ruby does not.
          require "syntax_suggest/api" if false
          error = SyntaxError.new(#{error.message.inspect})
          error.instance_variable_set(:@path, #{input.inspect})
          $stderr.write(#{warned.inspect}, #{input.inspect}, ": ", error.detailed_message(highlight: false), "\n")
          exit 1
        RUBY
      end
    end
  end
end
