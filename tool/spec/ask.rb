# frozen_string_literal: true

require_relative "../spec"
require_relative "../oracle"

module Zr
  module Dev
    class Specs
      # Runs a program that is not yet in a spec file with ruby, and prints
      # its output as an assertion.
      #
      # The rule is that nobody writes an expected output by hand. This tool
      # runs the program as `zr-dev oracle` does, with the same path,
      # normalization and environment as the example will have. It prints
      # the output in the form of the assertion to paste.
      #
      #   zr-dev spec ask test/spec/core/thread/thread_test.rb frag.rb
      #   zr-dev spec ask test/spec/stdlib/etc/etc_test.rb frag.rb -n "reads a group"
      #
      # `-n` uses the keywords of an existing example, for a program that
      # needs that example's `files:` or `argv:`.
      class Ask < Command
        summary "What ruby answers for a candidate program, as an assertion"
        usage "<spec file> <program.rb> [-n SENTENCE]"
        host_ruby!

        def options(o) = o.on("-n SENTENCE", "borrow the keywords of this example") { |v| @borrow = v }

        def run(argv)
          spec_file, program = argv
          fail!("give a spec file and a program") unless spec_file && program

          Dev.reader!
          kwargs = { path: Reader.path_for(spec_file) }
          if @borrow
            from = Reader.read(spec_file).find { |e| e.name == @borrow }
            fail!("no example named #{@borrow.inspect} in #{spec_file}") unless from

            kwargs = from.kwargs
          end
          example = Reader::Example.new(name: "ask", source: File.read(program), kwargs: kwargs, want: {})
          answer = Oracle.answer(example) or fail!("ruby did not finish")
          puts assertion(answer)
        end

        # The assertion for an output, in the form that the suite uses.
        def assertion(answer)
          tail = []
          tail << "stderr: #{dump(answer.stderr)}" unless answer.stderr.empty?
          tail << "status: #{answer.code}" unless answer.code.zero?
          tail << "signal: #{answer.signal.inspect}" if answer.signal
          head = "_(result).must_answer"
          body = answer.stdout
          return "#{head} #{dump(body)}#{tail.empty? ? "" : ", #{tail.join(", ")}"}" unless body.include?("\n")

          "#{head} <<~'OUT'#{tail.empty? ? "" : ", #{tail.join(", ")}"}\n" \
            "#{body.lines.map { |l| "  #{l}" }.join}OUT"
        end

        # A literal with the escapes that the suite uses. `inspect` is not
        # correct here, because it changes UTF-8 output into `\u` escapes.
        def dump(bytes)
          out = bytes.dup.force_encoding(Encoding::UTF_8)
          out = bytes unless out.valid_encoding?
          %("#{out.gsub("\\", "\\\\\\\\").gsub('"', '\"').gsub("\n", '\n').gsub("\t", '\t').gsub("\e", '\e')}")
        end
      end
    end
  end
end
