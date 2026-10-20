# frozen_string_literal: true

require_relative "program_case"

module Zr
  module Test
    # Which program tests a run has (`ZR_PROGRAMS`), what each is
    # called, and where its expected output comes from (`ZR_EXPECTED`).
    # It loads no compiler, so `zr-dev test --list` can use it.
    module ProgramSelection
      ROOT = File.expand_path("../programs", __dir__)

      # Where a test's expected output comes from (`ZR_EXPECTED`, which
      # `zr-dev test --record`, `--verify` and `--live` set):
      #
      #   record   ask the reference ruby, and write its files beside the
      #            program first (zr-dev expect)
      #   verify   the files beside the program; a program with none fails
      #   live     ask the reference ruby now; read and write no file
      #
      # With none, a test reads its files, and a program with none asks the
      # reference ruby, as `live` does.
      MODES = %w[record verify live].freeze

      module_function

      def mode
        name = ENV.fetch("ZR_EXPECTED", "")
        return nil if name.empty?
        raise ArgumentError, "ZR_EXPECTED=#{name}: give one of #{MODES.join(", ")}" unless MODES.include?(name)

        name.to_sym
      end

      # The tests below test/programs, or below the paths that `selection`
      # names (`ZR_PROGRAMS=core/gc,lang/blocks`). Each is a directory or a
      # program: below test/programs, below the current directory, or
      # absolute. A program outside test/programs runs in a directory of its
      # own, as `ruby prog.rb` would run in the program's directory. A named
      # program is always a test; a directory gives the programs that have
      # an expected output, or, in any of the `MODES`, every program. A
      # directory with `/*` after it gives its own programs and none of its
      # subdirectories' (`core/array/*`).
      def cases(selection = ENV.fetch("ZR_PROGRAMS", ""), mode: self.mode, base: Dir.pwd)
        paths = selection.split(",").map(&:strip).reject(&:empty?)
        paths = [""] if paths.empty?
        paths.flat_map do |path|
          shallow = path.end_with?("/*")
          path = path.delete_suffix("/*")
          full = locate(path, base) or raise ArgumentError, "ZR_PROGRAMS: no program or directory #{path} below test/programs or here"
          inside = full == ROOT || full.start_with?(File.join(ROOT, ""))
          root = if inside then ROOT
                 elsif File.file?(full) then File.dirname(full)
                 else full
                 end
          Case.under(full, root, every: File.file?(full) || !mode.nil?, shallow: shallow)
        end.uniq
      end

      # The full path of a selected program or directory: below
      # test/programs first, then below `base`. Nil when neither exists.
      def locate(path, base = Dir.pwd)
        [File.expand_path(path, ROOT), File.expand_path(path, base)].find { |full| File.exist?(full) }
      end

      # A test's name: its path below test/programs, or, for a program
      # elsewhere, its path below `base`, else its full path.
      def label(test, base: Dir.pwd)
        return test.rel if test.root == ROOT

        below = Pathname(test.path).relative_path_from(Pathname(base)).to_s
        below.start_with?("../") ? test.path : below
      end
    end
  end
end
