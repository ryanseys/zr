# frozen_string_literal: true

require "test_helper"
require "prism"

# A program carries one back end of eval: the compiler or the
# interpreter (`Library::Roots.eval_file`). The runtime calls each back
# end through `Zr::Eval.current`, so each one must answer every method
# that the runtime calls. A method that only one back end defines is a
# NoMethodError in a program that carries the other one. The test reads
# the files with Prism: the back ends call `Primitive`, so they load only
# in a binary.
class EvalBackendsTest < Minitest::Test
  LIB = File.join(ROOT, "lib/zr")

  # The files of each back end: the base class, then the back end's own.
  # The runtime files that only one back end's programs carry call only
  # that back end.
  BACK_ENDS = {
    "compiler" => [%w[eval.rb eval/compiler.rb], %w[forms.rb]],
    "interpreter" => [%w[eval.rb eval/interpreter.rb], %w[interpreter_file.rb interpreter_forms.rb]]
  }.freeze

  # The runtime files of one back end.
  OWN = BACK_ENDS.values.flat_map { |_, own| own.map { |name| File.join(LIB, "runtime/lib/zr/eval", name) } }.freeze

  BACK_ENDS.each do |name, (files, own)|
    define_method(:"test_the_#{name}_answers_each_method_that_the_runtime_calls") do
      defined = files.flat_map { |file| instance_methods(File.join(LIB, file)) }
      runtime = Dir[File.join(LIB, "runtime/**/*.rb")] - OWN + own.map { |file| File.join(LIB, "runtime/lib/zr/eval", file) }

      assert_empty called(runtime) - defined, "#{name} lacks these methods of Zr::Eval.current"
    end
  end

  private

  # The methods that the runtime `files` call on `Zr::Eval.current`.
  def called(files)
    files.flat_map do |file|
      calls = [] #: Array[Symbol]
      Prism.parse_file(file).value.breadth_first_search do |node|
        calls << node.name if node.is_a?(Prism::CallNode) && current?(node.receiver)
        false
      end
      calls
    end.uniq.sort
  end

  # Whether `node` is `Zr::Eval.current` or `::Zr::Eval.current`.
  def current?(node)
    node.is_a?(Prism::CallNode) && node.name == :current && node.receiver.respond_to?(:full_name) && node.receiver.full_name.end_with?("Zr::Eval")
  end

  # The instance methods that `file` defines, at any depth.
  def instance_methods(file)
    names = [] #: Array[Symbol]
    Prism.parse_file(file).value.breadth_first_search do |node|
      names << node.name if node.is_a?(Prism::DefNode) && node.receiver.nil?
      false
    end
    names
  end
end
