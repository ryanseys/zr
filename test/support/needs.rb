# frozen_string_literal: true

module Zr
  module Test
    # What a test file needs from the runtime, declared in a comment in
    # its first lines:
    #
    #   # zr-test: runtime   it builds a program, without eval support
    #   # zr-test: eval      it builds a program that evals
    #
    # A file without the comment builds no program. A run (`Built`) builds
    # the runtime (and eval support) before the tests only when a file of the run
    # declares that it needs it, so a run of such files starts at once.
    #
    # The guard makes the comment true: in a test whose file does not
    # declare `runtime` or `eval`, the first use of the runtime's lowering
    # or of its cache raises. It raises even when the cache is warm, so a
    # test passes or fails the same way on every machine.
    module Needs
      LEVELS = { none: 0, runtime: 1, eval: 2 }.freeze
      # The comment is in the first lines, after the magic comments.
      HEAD = 10

      module_function

      # The need of the test file at `path`: :none, :runtime or :eval.
      def of(path)
        @of ||= {}
        @of[path] ||= begin
          line = File.foreach(path).first(HEAD).find { |text| text.start_with?("# zr-test:") }
          line ? line.delete_prefix("# zr-test:").strip.to_sym.tap { |need| LEVELS.fetch(need) } : :none
        end
      end

      # The most that any of `files` needs.
      def most(files) = files.map { |file| of(file) }.max_by { |need| LEVELS.fetch(need) } || :none

      # The need of the test that runs now; nil outside a test, where the
      # guard lets everything through.
      def current = @current

      def current=(need)
        @current = need
      end

      # Raises unless the test that runs now declared at least `need`.
      def check!(need, what)
        return if @current.nil? || LEVELS.fetch(@current) >= LEVELS.fetch(need)

        raise "this test uses #{what}: declare `# zr-test: #{need}` in the first lines of its file"
      end

      # Prepended to Runtime: the lowering and the cached tables.
      module RuntimeGuard
        def unit = Needs.check!(:runtime, "the runtime").then { super }

        private

        def cached = Needs.check!(:runtime, "the runtime").then { super }
        def lowered = Needs.check!(:runtime, "the runtime").then { super }
      end

      # Prepended to EvalSupport: its metadata and its lowering.
      module EvalGuard
        private

        def meta = Needs.check!(:eval, "eval support").then { super }
        def lowered = Needs.check!(:eval, "eval support").then { super }
      end

      # Included in Minitest::Test: sets the need from the file that
      # defines the test method.
      module Hook
        def before_setup
          file = method(name).source_location&.first
          Needs.current = file ? Needs.of(file) : :none
          super
        end

        def after_teardown
          super
        ensure
          Needs.current = nil
        end
      end

      def install!
        Runtime.prepend(RuntimeGuard)
        EvalSupport.prepend(EvalGuard)
      end
    end
  end
end
