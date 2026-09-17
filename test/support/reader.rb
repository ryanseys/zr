# frozen_string_literal: true

module Ze0
  # Reads a spec file without compiling anything.
  #
  # A spec example is a program and the answer ruby gave for it. Running
  # one costs a ze0 compile; reading one costs nothing, and reading is
  # enough for every question that is about the file rather than about
  # the compiler -- what a file asserts, whether a literal is still
  # ruby's word, how many examples an area holds.
  #
  # The file is loaded against a stand-in world: `describe` and `it`
  # collect, `ze0` records what it was handed, and `_(x).must_answer y`
  # records the answer. Nothing compiles, nothing runs, and a guard that
  # asks about the machine is answered here rather than by the compiler.
  module Reader
    Example = Struct.new(:name, :source, :kwargs, :want, keyword_init: true)

    # The world a spec file is loaded into.
    class Sandbox
      attr_reader :seen

      def initialize = @seen = []

      def describe(_name, &block) = instance_eval(&block)

      def it(name, &block)
        @current = Example.new(name: name, want: {})
        @seen << @current
        instance_eval(&block)
      rescue StandardError => e
        @current.want[:error] = e
      end

      def ze0(source, **kwargs)
        @current.source = source
        @current.kwargs = kwargs
        Recorder.new(@current, :result)
      end

      # `_(result.stdout)` hands back the stream the chain already
      # named; `_(ze0(...).stdout)` is the same chain in one line.
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

    # Every example a spec file holds.
    def read(path)
      box = Sandbox.new
      box.instance_eval(File.read(path).sub(/^require "spec_helper"$/, ""), path)
      box.seen
    end
  end

  # The guards a spec's examples ask about the machine. The real ones
  # live in `test/support/spec.rb`, which loads the whole compiler; a
  # reader that compiles nothing answers them itself.
  module Spec
    def self.platform = "macos"
    def self.need?(_name) = true
  end
end
