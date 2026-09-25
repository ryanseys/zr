# frozen_string_literal: true

require_relative "../spec"

module Zr
  module Dev
    class Specs
      # The format rules for a spec file. None of them change the meaning of
      # an example. A tool that knows about `zr` and `must_answer` checks them
      # better than a general linter.
      module Style
        # Wide enough for a table row, and narrow enough to read next to
        # another file.
        COLUMNS = 120

        # The tags whose body is ruby's output. The tools here must not change
        # it: a trailing space in the output is a byte that ruby wrote.
        ANSWERS = %w[OUT ERR LINUX WASI].freeze

        # A program is `RUBY`, its stdout is `OUT`, its stderr is `ERR`, and
        # the output on a given platform uses the platform name.
        #
        # `PROGRAM` is also a program tag. A `<<~` terminator can be indented,
        # so a program that contains `eval <<~RUBY ... RUBY` would end an outer
        # `RUBY` heredoc too early. Eight examples need it (for example,
        # `core/object/formatting_test.rb`, which defines a method with `eval`).
        TAGS = %w[RUBY PROGRAM OUT ERR LINUX WASI].freeze

        # Sentences that a generator writes into more than one file on purpose,
        # as they are written in the source. `zr-dev spec dispatch`
        # (`tool/spec/dispatch.rb`) writes this one into six files, one for
        # each class it tests. Each file's `describe` gives the class, so the
        # sentence does not need it.
        GENERATED = ["subclass sees only the calls ruby makes"].map(&:inspect).freeze

        # Where the DSL opens a heredoc: the program, its stdout, its stderr,
        # and the output for a given platform. Only these. A program under
        # test can open its own heredoc (`eval(<<~SRC)`, a Gemfile, a PEM), and
        # an expected output can contain heredoc text (as the Ripper examples
        # do). These rules do not apply to those.
        OPENS = /(?:\bzr\(|\bmust_answer |\b(?:stderr|linux|wasi): )<<[-~]'?([A-Z_]+)/

        module_function

        # Yields each line of a spec file with the tag of the DSL heredoc that
        # contains it, or nil for the file's own code. All the rules below use
        # this one method, so that they cannot disagree.
        def each_line(path)
          open = []
          File.readlines(path).each_with_index do |line, i|
            yield line, i + 1, open.first
            if open.any?
              # A `<<~` terminator can be indented, so match the tag only.
              open.shift if line.match?(/\A\s*#{open.first}\s*\z/)
            else
              # One line can open two heredocs: `must_answer <<~'OUT', stderr:
              # <<~'ERR'`. Ruby reads their bodies in the order of the openers.
              open = line.scan(OPENS).flatten
            end
          end
        end

        # The sentences of one file's examples, as `{name => [line, ...]}`.
        # This ignores an `it` inside a program under test (for example, in an
        # rspec suite).
        def sentences(path)
          found = Hash.new { |h, k| h[k] = [] }
          each_line(path) do |line, n, inside|
            next if inside
            (name = line[/\A\s*it ("(?:[^"\\]|\\.)*") do\n?\z/, 1]) && found[name] << n
          end
          found
        end

        # Finds a sentence that two FILES use. The rule in `faults` checks for
        # duplicates in one file; this checks across files. Thus a sentence in
        # a failure report or a `-n` filter identifies only one example.
        def crossed(paths)
          seen = {}
          paths.flat_map do |path|
            sentences(path).filter_map do |name, lines|
              next if GENERATED.include?(name)

              first = (seen[name] ||= path)
              [path, lines.first, "#{name} is also #{Dev.rel(first)}"] unless first.equal?(path)
            end
          end
        end

        # Every complaint about one file, as `[line, why]`.
        def faults(path)
          out = []
          each_line(path) do |line, n, inside|
            out << [n, "trailing whitespace"] if line.rstrip != line.chomp && !ANSWERS.include?(inside)

            # Inside a DSL heredoc, the lines are the program under test or its
            # output. A change to their width would change the example. Only the
            # file's own code has a width limit.
            next if inside

            out << [n, "#{line.chomp.size} columns, over #{COLUMNS}"] if line.chomp.size > COLUMNS
            line.scan(/(?:\bzr\(|\bmust_answer |\b(?:stderr|linux|wasi): )<<([-~])('?)([A-Z_]+)/) do |squiggly, quote, tag|
              out << [n, "heredoc <<#{squiggly}#{tag}: use <<~"] if squiggly != "~"
              out << [n, "heredoc #{tag}: not one of #{TAGS.join(", ")}"] unless TAGS.include?(tag)
              # In an interpolating heredoc, each `#{}` in the program runs in
              # the test, not in the program. That is almost never intended.
              out << [n, "heredoc <<~#{tag}: quote the tag, or #\{\} in the program runs"] if quote.empty?
            end
          end
          # Two examples in one file with the same sentence. Minitest accepts
          # both (it numbers the methods it defines), so nothing fails. But a
          # failure report then gives a sentence that matches two examples.
          sentences(path).reject { |_, lines| lines.one? }
                         .each { |name, lines| lines.drop(1).each { |n| out << [n, "#{name} is also line #{lines.first}"] } }
          out
        end
      end

      class Check < Tool
        summary "The formatting conventions"

        def run(argv)
          files = files(argv)
          faults = files.flat_map { |f| Style.faults(f).map { |n, why| "#{Dev.rel(f)}:#{n}: #{why}" } }
          # Only across the files given to this run. A run on one directory
          # cannot see a sentence outside it.
          faults += Style.crossed(files).map { |f, n, why| "#{Dev.rel(f)}:#{n}: #{why}" }
          faults.each { |line| warn line }
          puts format("%d file(s) checked, %d fault(s)", files.size, faults.size)
          faults.empty?
        end
      end

      class Tidy < Tool
        summary "Fix what check reports that is safe to fix"

        def run(argv)
          changed = 0
          lines = 0
          files(argv).each do |file|
            was = File.read(file)
            # Change only lines that contain only whitespace. A line with
            # text and a trailing space can be in a string that the program
            # prints, where the space is part of the output. A
            # whitespace-only line is a blank line in all places, and `<<~`
            # ignores it when it removes indentation.
            now = was.gsub(/^[ \t]+$/, "")
            # A comment line with only spaces after the `#`. In a program,
            # the space has no effect. In an expected output it could
            # matter, so run `zr-dev oracle` after this tool.
            now = now.gsub(/^([ \t]*#)[ \t]+$/, '\\1')
            next if now == was

            File.write(file, now)
            changed += 1
            lines += was.lines.count { |l| l.match?(/^[ \t]+$/) }
          end
          puts format("%d file(s) tidied, %d blank line(s) emptied", changed, lines)
          puts "now run: zr-dev oracle <path> -- the program text changed, so ruby is the judge"
        end
      end
    end
  end
end
