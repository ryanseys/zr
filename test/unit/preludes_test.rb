# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/hir"

# The files a program carries ahead of its own first line: rbconfig,
# the compiler, rubygems, the normalizer, the pretty printer, the file
# that arms `binding.irb`, and the syntax tree translator. Each stands
# under a loader flag, and `Hir::Build.preludes` reads the ones the
# flags ask for.
#
# The loader here is a stand-in. What these rows pin is the walk over
# the table -- its order, and that it goes again -- and building the
# real thing would read irb's 73 files to ask one question.
class PreludesTest < Minitest::Test
  Build = Ze0::Hir::Build

  # A loader that answers the flags it was given and keeps what each
  # prelude asked it to read. Reading the file that arms irb turns
  # `evals?` on, which is what irb does: it requires fileutils, and
  # fileutils writes ninety of its methods with `module_eval`.
  class Loader
    FLAGS = %i[configures? evals? gems? normalizes? pretty_prints? irbs? asts?].freeze

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

  def test_a_loader_that_asks_for_nothing_carries_nothing
    assert_empty preludes(Loader.new)
  end

  def test_each_flag_brings_its_own_file
    assert_equal ["rbconfig"], preludes(Loader.new(configures?: true))
    assert_equal ["ze0/eval"], preludes(Loader.new(evals?: true))
    assert_equal ["ze0/normalizer"], preludes(Loader.new(normalizes?: true))
    assert_equal ["ze0/pretty_printer"], preludes(Loader.new(pretty_prints?: true))
    assert_equal ["ze0/syntax_tree"], preludes(Loader.new(asts?: true))
  end

  # rubygems reads rbconfig as it boots, so it can never stand first.
  def test_the_order_is_the_table_s_and_not_the_order_the_flags_turned_on
    asked = preludes(Loader.new(asts?: true, gems?: true, configures?: true))

    assert_equal %w[rbconfig rubygems bundled_gems ze0/syntax_tree], asked
  end

  # What the bug was: the flags were read once, before any prelude had
  # been, so a program whose only eval came from a prelude's own files
  # left the compiler out -- and `binding.irb` then stopped in fileutils
  # with "class_eval with a string is not implemented yet".
  def test_a_prelude_that_evals_brings_the_compiler_with_it
    loader = Loader.new(irbs?: true)
    asked = preludes(loader)

    assert_includes loader.read, Build::IRB_SESSION
    assert_equal %w[ze0/eval ze0/irb_session], asked
  end

  private

  # The features `loader` asks for, in the order the program loads them.
  def preludes(loader) = Build.preludes(loader, Ze0::Target.default).map(&:feature)
end
