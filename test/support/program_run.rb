# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "program_case"
require_relative "harness/normalize"
require_relative "harness/child"
require_relative "harness/reference"

module Zr
  module Test
    # Runs one program test (`Case`) in a new directory: with ruby, which
    # gives the expected output, or with zr, which builds a binary and runs
    # it. Both runs get the same directory, arguments, environment and
    # input, and the same normalization of their output (absolute paths
    # of the run directory, and object addresses), so the two answers
    # can be compared byte for byte.
    module ProgramRun
      module_function

      # Makes a new run directory with `test`'s program and files, yields
      # the run directory and the program's full path, and removes it.
      def within(test)
        Dir.mktmpdir("zr-program-") do |work|
          # On macOS, `/var` is a link to `/private/var`, and a program
          # prints the resolved path. The normalization must see the same
          # bytes.
          run = File.join(File.realpath(work), "run")
          rb = File.join(run, test.rel)
          FileUtils.mkdir_p(File.dirname(rb))
          File.binwrite(rb, test.source)
          copy_files(test.files, run) if test.files
          yield run, rb
        end
      end

      # Copies the tree under `from` into `run`. A link inside it stays a
      # link; `from` itself may be a link (a shared fixture).
      def copy_files(from, run) = FileUtils.cp_r(File.join(from, "."), run)

      # What `ruby` answers for `test`. `ruby` is the command, `env` the
      # environment that it needs (the reference ruby's gems).
      def ruby(test, ruby:, env: {})
        within(test) do |run, rb|
          gems = test.gems.flat_map { |name, version| Harness::Reference.port_load_path(name, version).flat_map { ["-I", _1] } }
          argv = [*ruby, *gems, *test.ruby_options, test.rel, *test.args]
          out, = Harness::Child.run(argv, cwd: run, stdin: test.stdin, env: env.merge(test.env),
                                          seconds: Harness::Child::SECONDS * 2, megabytes: Harness::Child::RUN_MB)
          out.code.is_a?(Integer) ? Harness::Normalize.answer(out, rb, run) : nil
        end
      end

      # The answer that `test` expects on `platform`.
      def expected(test, platform)
        code, signal = test.status
        Harness::Answer.new(test.stdout(platform), test.stderr, code, signal)
      end
    end
  end
end
