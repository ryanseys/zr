# frozen_string_literal: true

require_relative "fixtures"
require_relative "../../lib/zr/record"

module Zr
  # Reads a spec file without compiling anything.
  #
  # A spec example is a program and the expected output from ruby. To run
  # an example costs a zr compile. To read it costs almost nothing, and
  # is enough for questions about the file: what it asserts, whether an
  # expected value still agrees with ruby, how many examples an area has.
  #
  # The reader loads the file into a sandbox: `describe` and `it` collect
  # examples, `zr` records its arguments, and `_(x).must_answer y` records
  # the expected output. Nothing compiles or runs. The sandbox, not the
  # compiler, evaluates a guard that checks the machine.
  module Reader
    ROOT = File.expand_path("../..", __dir__)

    # `given` contains the keywords that the spec file wrote. `kwargs`
    # adds the defaults of the DSL. A tool that rewrites a spec uses
    # `given`, because only there can it tell an explicit `path:` from
    # the default path that this reader adds.
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

    # The object that a spec file is loaded into.
    class Sandbox
      # The real DSL includes the same helper, so a fixture has the same
      # bytes in the spec runner and in the reader.
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

      # A guard that this machine does not meet makes the example skip, as
      # in the real DSL (`Zr::Spec::Guards`). The reader runs no program,
      # so it takes each `needs:` as met; `only:` reads the host.
      def it(name, needs: nil, only: nil, &block)
        @current = Example.new(name: name, about: @about, want: {})
        @seen << @current
        only = Array(only)
        skip("runs only on #{only.join(", ")}") unless only.empty? || only.include?(Reader.platform)
        instance_eval(&block)
      rescue StandardError => e
        @current.want[:error] = e
      end

      # The keywords are explicit, not `**kwargs`, and are the same as the
      # keywords of `Zr::Spec::DSL#zr`. Otherwise the reader accepts a
      # misspelled keyword, and `rake oracle` passes a spec that no run
      # can compile.
      def zr(source, path: nil, argv: [], env: {}, stdin: nil, files: {}, seconds: nil, ruby: [])
        given = { path: path, argv: argv, env: env, stdin: stdin, files: files,
                  seconds: seconds, ruby: ruby }.reject { |k, v| v == DEFAULTS[k] }
        @current.source = source
        @current.given = given
        # Add the default path of the DSL, so that a tool that reads the
        # example sees the path that the run uses.
        @current.kwargs = { path: Reader.path_for(@spec_file) }.merge(given)
        Recorder.new(@current, :result)
      end

      # The default of each keyword. `given` leaves out a value equal to
      # its default, so it contains only what the spec file wrote.
      DEFAULTS = { path: nil, argv: [], env: {}, stdin: nil, files: {},
                   seconds: nil, ruby: [] }.freeze

      # `_(result.stdout)` returns the recorder that `stdout` already
      # gave. `_(zr(...).stdout)` is the same call chain on one line.
      def _(value) = value.is_a?(Recorder) ? value : Recorder.new(@current, value)

      def skip(why = nil)
        @current.want[:skip] = why || ""
        nil
      end

      # Records an expectation. The left side identifies the part of the
      # output. The right side is the value that ruby recorded.
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

        # `must_answer` gives all four parts at once. Its defaults are the
        # values for a part that a recording leaves out: no stderr, and
        # exit status zero.
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

    # Returns the path of a program when its example gives none: the path
    # of the spec file below `test/spec`. For example, an example in
    # `core/fiber/fiber_test.rb` writes its program as
    # `core/fiber/fiber_test.rb`, and a backtrace shows the spec file.
    #
    # Keep the `_test` suffix. Without it, `stdlib/etc/etc_test.rb` would
    # write its program as `etc.rb`, and its `etc.rb` fixture (written
    # after the program) would overwrite it. `Spec.build_and_run` refuses
    # that collision.
    #
    # `Zr::Spec::DSL#default_path` must return the same path, or the path
    # of a program is different in the run and in the oracle.
    # `reader_conformance_test.rb` tests that they agree.
    def path_for(spec_file)
      File.expand_path(spec_file, ROOT).delete_prefix("#{ROOT}/test/spec/")
    end

    # The platform name of this host, as the recordings name it.
    def platform = RUBY_PLATFORM.include?("darwin") ? "macos" : "linux"

    # Returns all examples in a spec file.
    def read(path)
      box = Sandbox.new(path)
      box.instance_eval(File.read(path).sub(/^require "spec_helper"$/, ""), path)
      box.seen
    end
  end
end
