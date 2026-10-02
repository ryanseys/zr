# frozen_string_literal: true

require_relative "../version"
require_relative "../config"
require_relative "../refused"

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

      # The program that writes ruby's report of a syntax error. It loads
      # zr's own syntax_suggest (vendor/ruby) by its path, as a stock ruby
      # 4.0.7 has it: `api` first, so `core_ext` does not require it by name
      # (a second core_ext would wrap the message twice). ruby prints the
      # parse's warnings before the error, so the report has them too. It
      # exits 2 when the file parses.
      SYNTAX_REPORT = <<~'RUBY'
        syntax_suggest, input = ARGV
        require File.join(syntax_suggest, "api")
        require File.join(syntax_suggest, "core_ext")
        warned = +""
        sink = Object.new
        sink.define_singleton_method(:write) { |*parts| warned << parts.join }
        $stderr = sink
        begin
          RubyVM::InstructionSequence.compile_file(input)
        rescue SyntaxError => e
          error = e
        ensure
          # syntax_suggest writes to $stderr as it builds the message.
          $stderr = STDERR
        end
        exit 2 unless error
        print warned, input, ": ", error.detailed_message(highlight: false), "\n"
      RUBY

      module_function

      # Why this compiler must not build on a ruby of `version`, or nil
      # when it runs there.
      def host_refusal(version = RUBY_VERSION)
        return if Zr.supported_ruby?(version)

        "zr #{VERSION} runs on ruby #{RUBY} or a later 4.0 release. " \
          "Install ruby #{RUBY}: #{DOCS_URL}/how-to/install.md"
      end

      # A note for a ruby that zr runs on but is not tested with, or nil.
      def host_note(version = RUBY_VERSION)
        return if version == RUBY || !Zr.supported_ruby?(version)

        "zr #{VERSION} is tested with ruby #{RUBY}; this is ruby #{version}"
      end

      # Stops a build on a ruby that zr does not run on, before it reads
      # the program. Warns once on a ruby that it is not tested with.
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
      def foreign(target, chosen)
        what = "this computer cannot run #{target.triple} binaries."
        return what if chosen

        "#{what} zr builds one for #{TARGET_NAMES.fetch(target.triple, target.triple)}."
      end

      # What `zr` prints when it refuses a program: the message, then for a
      # form of Ruby, the source line with a caret and the page that lists
      # what zr supports.
      def refusal_report(error)
        lines = ["zr: #{error.message}"]
        if error.form
          lines << error.excerpt if error.excerpt
          lines << "zr: #{SUPPORT} lists what zr supports"
        end
        lines.join("\n")
      end

      # ruby's report for `input`, which does not parse, or nil when it
      # parses (then a file that it requires did not). The host ruby writes
      # it, without gems, so no other version of syntax_suggest is loaded.
      def syntax_report(input)
        require_relative "../library/roots"
        argv = [Config.current.host_ruby, "--disable-gems", "-e", SYNTAX_REPORT, File.join(Library::Roots.pure, "syntax_suggest"), input]
        out = IO.popen(argv, err: File::NULL, &:read)
        $?.success? ? out : nil
      end
    end
  end
end
