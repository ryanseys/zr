# frozen_string_literal: true

require "test_helper"
require "stringio"

# Every runtime file is valid Ruby, and `ruby -wc` gives no warning for
# it. The kernel dialect runs only when zr compiles it, but its syntax
# is ordinary Ruby syntax, so ruby's own parser checks it.
class RuntimeSyntaxTest < Minitest::Test
  FILES = Dir[File.join(ROOT, "runtime/**/*.rb")].sort.freeze

  def test_every_runtime_file_is_found
    assert_operator FILES.size, :>, 300
  end

  def test_every_runtime_file_compiles_without_a_warning
    warned = FILES.filter_map do |path|
      said = compile(path)
      "#{path.delete_prefix("#{ROOT}/")}: #{said}" unless said.empty?
    end

    assert_empty warned
  end

  private

  # What ruby says as it compiles `path` with warnings on.
  def compile(path)
    verbose, stderr = $VERBOSE, $stderr
    $VERBOSE = true
    $stderr = StringIO.new
    RubyVM::InstructionSequence.compile_file(path)
    $stderr.string
  rescue SyntaxError => e
    e.message
  ensure
    $VERBOSE, $stderr = verbose, stderr
  end
end
