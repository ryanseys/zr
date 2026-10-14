# frozen_string_literal: true

require_relative "../../lib/zr/config"
require_relative "../../lib/zr/library/roots"

module Zr
  module Test
    # ruby's report of a program that does not parse, which the host tier
    # prints in place of the run. A binary writes the report itself
    # (`CLI::Refusals.syntax_error_program`), but the host walker may not
    # run syntax_suggest, so here the host ruby writes it.
    module RubySyntaxReport
      # The program that writes the report. It loads zr's own
      # syntax_suggest (vendor/ruby) by its path, as a stock ruby has it:
      # `api` first, so `core_ext` does not require it by name (a second
      # core_ext would wrap the message twice). ruby prints the parse's
      # warnings before the error, so the report has them too. It exits 2
      # when the file parses. The host ruby runs it with its gems, where it
      # finds prism (a bundled gem), and with no autoload of the message
      # decorators, which would load the host's own syntax_suggest.
      PROGRAM = <<~'RUBY'
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

      # ruby's report for `input`, which does not parse, or nil when it
      # parses (then a file that it requires did not).
      #: (String input) -> String?
      def self.of(input)
        argv = [Config.current.host_ruby, "--disable=error_highlight,did_you_mean,syntax_suggest", "-W1",
                "-e", PROGRAM, File.join(Library::Roots.pure, "syntax_suggest"), input]
        out = IO.popen(argv, err: File::NULL, &:read)
        $?.success? ? out : nil
      end
    end
  end
end
