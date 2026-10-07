# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# The files that a program includes before its own first line: rbconfig,
# the compiler, rubygems, the normalizer, the pretty printer, the file
# that enables `binding.irb`, and the syntax tree translator. Each file
# has a loader flag, and `Hir::Build.preludes` reads the files whose
# flags are set.
#
# The loader here is a stub. These tests check the loop over the table:
# its order, and that it runs again. The real loader reads the 73 files
# of irb to check one fact.
class PreludesTest < Minitest::Test
  Build = Zr::Hir::Build

  # A loader that returns the flags it was given and records each file
  # that a prelude reads. Reading the file that enables irb sets `evals?`,
  # as irb does: it requires fileutils, and fileutils defines ninety of
  # its methods with `module_eval`.
  class Loader
    FLAGS = %i[configures? evals? gems? lazy_gems? normalizes? pretty_prints? irbs? asts?].freeze

    attr_reader :read

    def initialize(**flags)
      @flags = flags
      @read = []
    end

    FLAGS.each { |flag| define_method(flag) { @flags.fetch(flag, false) } }

    def add(path) = take(path)
    def hidden(path) = take(path)
    def resolve(_kind, feature, root) = File.join(root, "#{feature}.rb")

    private

    def take(path)
      @read << path
      @flags[:evals?] = true if path == Build::IRB_SESSION
      @read.size
    end
  end

  def test_preludes_are_empty_when_no_flag_is_set
    assert_empty preludes(Loader.new)
  end

  def test_each_flag_brings_its_own_file
    assert_equal ["rbconfig"], preludes(Loader.new(configures?: true))
    assert_equal ["zr/eval"], preludes(Loader.new(evals?: true))
    assert_equal ["zr/normalizer"], preludes(Loader.new(normalizes?: true))
    assert_equal ["zr/pretty_printer"], preludes(Loader.new(pretty_prints?: true))
    assert_equal ["zr/syntax_tree"], preludes(Loader.new(asts?: true))
  end

  # rubygems reads rbconfig when it boots, so rubygems can never be first.
  def test_preludes_follow_table_order_not_flag_order
    asked = preludes(Loader.new(asts?: true, gems?: true, configures?: true))

    assert_equal %w[rbconfig rubygems bundled_gems zr/gem_manifest zr/syntax_tree], asked
  end

  # A program that compiles at run time, and boots no rubygems, gets
  # rubygems' names as autoloads that the main file makes, so the program
  # sees them as it sees ruby's.
  def test_a_program_that_compiles_at_run_time_gets_rubygems_names_as_autoloads
    asked = preludes(Loader.new(evals?: true, lazy_gems?: true))

    assert_equal ["zr/eval", "autoload Gem zr/rubygems", "autoload RUBYGEMS_ACTIVATION_MONITOR zr/rubygems"], asked
  end

  # The only eval of a program can come from the files of a prelude, so
  # the loop reads the flags again after each prelude. If it does not, the
  # compiler is not included, and `binding.irb` stops in fileutils with
  # "class_eval with a string is not implemented yet".
  def test_a_prelude_that_evals_brings_the_compiler_with_it
    loader = Loader.new(irbs?: true)
    asked = preludes(loader)

    assert_includes loader.read, Build::IRB_SESSION
    assert_equal %w[zr/eval zr/irb_session], asked
  end

  private

  # The features that `loader` reads, in the order the program loads them,
  # and each autoload that the main file makes.
  def preludes(loader)
    Build.preludes(loader, Zr::Target.default).map do |node|
      node.is_a?(Zr::Hir::Send) ? "#{node.name} #{node.args.map(&:value).join(" ")}" : node.feature
    end
  end
end
