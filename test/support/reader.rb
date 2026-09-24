# frozen_string_literal: true

require_relative "fixtures"
require_relative "../../lib/zr/record"

module Zr
  # Reads a spec file without compiling anything.
  #
  # A spec example is a program and the answer ruby gave for it. Running
  # one costs a zr compile; reading one costs nothing, and reading is
  # enough for every question that is about the file rather than about
  # the compiler -- what a file asserts, whether a literal is still
  # ruby's word, how many examples an area holds.
  #
  # The file is loaded against a stand-in world: `describe` and `it`
  # collect, `zr` records what it was handed, and `_(x).must_answer y`
  # records the answer. Nothing compiles, nothing runs, and a guard that
  # asks about the machine is answered here rather than by the compiler.
  module Reader
    ROOT = File.expand_path("../..", __dir__)

    # `given` is what the spec file wrote; `kwargs` is that with the
    # defaults the DSL would have filled in. A tool that rewrites a spec
    # reasons about `given` -- it is the only place an explicit `path:`
    # can be told apart from one this reader supplied.
    class Example < ::Zr::Record
      FIELDS = %i[name about source kwargs given want].freeze
      attr_accessor :name, :about, :source, :kwargs, :given, :want

      def initialize(name: nil, about: nil, source: nil, kwargs: nil, given: nil, want: nil)
        @name = name
        @about = about
        @source = source
        @kwargs = kwargs
        @given = given
        @want = want
      end

      def to_a = [@name, @about, @source, @kwargs, @given, @want]
    end

    # The world a spec file is loaded into.
    class Sandbox
      # The same helper the real DSL has, so a spec file that reads a
      # fixture reads the same bytes on both roads.
      include Fixtures

      attr_reader :seen

      def initialize(spec_file = nil)
        @seen = []
        @spec_file = spec_file
      end

      def describe(name, &block)
        @about = name
        instance_eval(&block)
      end

      def it(name, &block)
        @current = Example.new(name: name, about: @about, want: {})
        @seen << @current
        instance_eval(&block)
      rescue StandardError => e
        @current.want[:error] = e
      end

      # The keys are named rather than swept up in `**kwargs`, and they
      # are `Zr::Spec::DSL#zr`'s keys exactly. A reader that took
      # anything would record a misspelled keyword happily, and
      # `rake oracle` would pass a spec that no run could compile.
      def zr(source, path: nil, argv: [], env: {}, stdin: nil, files: {}, seconds: nil, ruby: [])
        given = { path: path, argv: argv, env: env, stdin: stdin, files: files,
                  seconds: seconds, ruby: ruby }.reject { |k, v| v == DEFAULTS[k] }
        @current.source = source
        @current.given = given
        # The default the DSL would have filled in, filled in here, so
        # that what reads the example sees the path the run would use.
        @current.kwargs = { path: Reader.path_for(@spec_file) }.merge(given)
        Recorder.new(@current, :result)
      end

      # What each keyword means when an example does not name it, so
      # `given` holds what was written and nothing else.
      DEFAULTS = { path: nil, argv: [], env: {}, stdin: nil, files: {},
                   seconds: nil, ruby: [] }.freeze

      # `_(result.stdout)` hands back the stream the chain already
      # named; `_(zr(...).stdout)` is the same chain in one line.
      def _(value) = value.is_a?(Recorder) ? value : Recorder.new(@current, value)

      def skip(why = nil)
        @current.want[:skip] = why || ""
        nil
      end

      # The left side says which part of the answer, the right side is
      # what ruby recorded.
      class Recorder
        def initialize(example, value)
          @example = example
          @value = value
        end

        def stdout = Recorder.new(@example, :stdout)
        def stderr = Recorder.new(@example, :stderr)
        def status = Recorder.new(@example, :status)
        def signal = Recorder.new(@example, :signal)

        def must_equal(want)
          @example.want[@value] = want
          want
        end

        # `must_answer` says all four parts at once, and its defaults
        # are what a recording means by leaving a section out: no
        # stderr, and a status of zero.
        def must_answer(stdout, stderr: "", status: 0, signal: nil, linux: nil, wasi: nil)
          @example.want[:stdout] = stdout
          @example.want[:stderr] = stderr
          @example.want[:status] = status
          @example.want[:signal] = signal
          @example.want[:elsewhere] = { "linux" => linux, "wasi" => wasi }.compact
          self
        end
      end
    end

    module_function

    # The name a program answers to when its example does not name one:
    # the spec file's own path under `test/spec`, so an example in
    # `core/fiber/fiber_test.rb` writes its program as
    # `core/fiber/fiber_test.rb` and a backtrace names the file the
    # example is written in.
    #
    # The `_test` stays on purpose. `core/fiber/fiber.rb` reads better
    # but collides: `stdlib/etc/etc_test.rb` hands its programs an
    # `etc.rb` of their own, `files:` is written after the program, and
    # the fixture would land on top of it. `Spec.build_and_run` refuses
    # that collision now, and this name does not walk into it.
    #
    # It was the example's sentence, slugified, and that coupled two
    # things that have no business being coupled: a sentence could hold
    # no apostrophe, comma or `#`, because it had to survive being made
    # into a filename. It is the file now, so a sentence is free to be a
    # sentence, and renaming one cannot move a program.
    #
    # `Zr::Spec::DSL#default_path` is the other caller, and the two must
    # agree or a program's own path differs between the run and the
    # oracle. `reader_conformance_test.rb` holds them together.
    def path_for(spec_file)
      File.expand_path(spec_file, ROOT).delete_prefix("#{ROOT}/test/spec/")
    end

    # Every example a spec file holds.
    def read(path)
      box = Sandbox.new(path)
      box.instance_eval(File.read(path).sub(/^require "spec_helper"$/, ""), path)
      box.seen
    end
  end
end
