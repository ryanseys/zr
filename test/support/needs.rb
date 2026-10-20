# frozen_string_literal: true

module Zr
  module Test
    # What a test file needs from the runtime, declared in a comment in
    # its first lines:
    #
    #   # zr-test: runtime   it builds a program, without eval support
    #   # zr-test: eval      it builds a program that evals
    #   # zr-test: on macho  it tests what one kind of host has (KINDS)
    #
    # A file without the first two builds no program. A run (`Built`) builds
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

      # The kinds of host that `# zr-test: on KIND...` names, each with
      # whether a target is one. A file names the kinds whose tests it
      # has; CI runs it in each lane whose target is one of them
      # (.github/scripts/lanes.rb), and its tests still skip on another
      # host.
      KINDS = {
        macho: ->(target) { target.object_format == :macho },
        elf: ->(target) { target.object_format == :elf },
        glibc: ->(target) { target.libc == :glibc },
        musl: ->(target) { target.libc == :musl },
        wasm: ->(target) { target.object_format == :wasm },
        aarch64: ->(target) { target.arch == :aarch64 },
        x86_64: ->(target) { target.arch == :x86_64 },
        "native-link": ->(target) { !target.link.nil? },
      }.freeze

      # The `# zr-test:` words in the first lines of the file at `path`.
      def words(path)
        @words ||= {}
        @words[path] ||= File.foreach(path).first(HEAD).filter_map do |line|
          line.delete_prefix("# zr-test:").split.map(&:to_sym) if line.start_with?("# zr-test:")
        end
      end

      # The need of the test file at `path`: :none, :runtime or :eval.
      def of(path)
        @of ||= {}
        @of[path] ||= words(path).find { |line| line.first != :on }&.first&.tap { |need| LEVELS.fetch(need) } || :none
      end

      # The kinds of host that the file at `path` names (KINDS), or [].
      def on(path)
        kinds = words(path).find { |line| line.first == :on }&.drop(1) || []
        kinds.each { |kind| KINDS.fetch(kind) { raise ArgumentError, "#{path}: no kind of host #{kind} (Needs::KINDS)" } }
      end

      # Whether `target` is one of the kinds that the file at `path` names.
      def on?(path, target) = on(path).any? { |kind| KINDS.fetch(kind).call(target) }

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
