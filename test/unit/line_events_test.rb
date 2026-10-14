# frozen_string_literal: true

require "test_helper"
require "coverage"
require "tmpdir"
require "zr/hir"

# The lines that carry a :line event, which TracePoint fires and line
# coverage counts (lib/zr/hir/build/coverage.rb). Each case compares the
# lines that zr's build gives events with the lines of CRuby's own
# compile of the same source (Coverage.line_stub).
class LineEventsTest < Minitest::Test
  CASES = {
    value_on_the_next_line: "x =\n  1.to_s\nx\n",
    array_of_calls: "y = [\n  1.to_s,\n  2\n]\n",
    static_array: "z = [\n  1,\n  2\n]\n",
    array_of_strings: "w = [\n  \"a\",\n  \"b\"\n]\n",
    frozen_array_of_strings: "# frozen_string_literal: true\nw = [\n  \"a\",\n  \"b\"\n]\n",
    hash_with_a_call: "v = {\n  a: 1.to_s,\n}\n",
    hash_with_a_static_first_pair: "v = {\n  \"a\" => nil,\n  \"b\" => 2.to_s\n}\n",
    hash_with_a_splat: "h = {}\nv = {\n  **h\n}\n",
    plain_heredoc: "u = <<~T\n  plain\n    more\nT\n",
    heredoc_with_code_first: "u = <<~T\n  \#{1}\nT\n",
    heredoc_with_text_first: "u = <<~T\n  text\n  \#{1}\nT\n",
    receiver_on_the_next_line: "s = !\n  nil.to_a\n",
    include_on_a_static_array: "a = 1\nb = [1,\n  2].include?(a)\n",
    include_on_an_array_of_calls: "a = 1\nc = [a.to_s,\n  2].include?(a)\n",
    case_with_no_subject: "def f(a)\n  case\n  when a == 1\n    :one\n  end\nend\n",
    case_with_a_literal_test: "v = case\n    when false then 1\n    when 1 > 0 then 2\n    end\n",
    literal_if: "r = if true\n  1.to_s\nelse\n  2.to_s\nend\n",
    literal_modifier: ":a\n1.to_s if false\n:b.to_s\n",
    literal_if_as_a_class_body_value: "class C\n  if false\n    def x; end\n  end\nend\n",
    and_false: "a = 1\nif a and false\n  p 1\nend\n",
    or_true: "a = 1\nif a or true\n  p 2\nelse\n  p 3\nend\n",
    false_and_a_call: "a = 1\nif false && a.to_s\n  p 1\nend\na\n",
    true_or_a_call: "a = 1\nunless true || a.to_s\n  p 1\nend\na\n",
    true_and_a_call: "a = 1\nif true &&\n    a.to_s\n  p 1\nend\n",
    false_or_a_call: "a = 1\nx = if false ||\n    a.to_s\n  p 1\nend\n",
    nested_if_in_an_expression: "def f\n  :a.to_s +\n    if @x\n      @x\n    else\n      ''\n    end\nend\n",
    if_as_a_written_value: "def f\n  @y ||=\n    if defined?(@z) && @z\n      1\n    end\nend\n",
    self_assignment: "a = 1\na = a\n@x = @x\n",
    elsif_after_a_silent_body: "def f(a)\n  if a\n    3\n  elsif a.nil?\n    4\n  end\n  nil\nend\n",
    when_after_a_silent_body: "def f(a)\n  case a\n  when 1\n    3\n  when 2\n    5\n  end\n  nil\nend\n",
    rescued_body_keeps_its_value: "begin\n  1.to_s\n  :kept\nrescue\n  nil\nend\n",
    statements_on_one_line_after_nothing: "begin; 1.to_s if false; nil.to_a; rescue; end\n",
    parentheses_after_nothing: "w = (if true then \"yes\" else \"no\" end; \"after\")\n",
    begin_blocks: "BEGIN { puts 1 }\nBEGIN {\n  puts 2\n}\nputs 3\n",
    ensure_of_a_block: "def f\n  [1].map do |w|\n    w.to_s\n  ensure\n    nil\n  end\nend\n",
    ensure_of_a_method: "def f\n  1.to_s\nensure\n  nil\nend\n",
    ensure_then_a_statement: "def f\n  begin\n    1.to_s\n  ensure\n    nil\n  end\n  2.to_s\nend\n",
    ensure_last_in_a_method: "def f\n  begin\n    1.to_s\n  ensure\n    nil\n  end\nend\n",
    ensure_in_a_written_value: "def f\n  x = begin\n    1.to_s\n  ensure\n    nil\n  end\n  x\nend\n",
    ensure_of_a_block_statement: "def f\n  [1].each do |w|\n    w.to_s\n  ensure\n    nil\n  end\n  2.to_s\nend\n",
    ensure_of_two_silent_statements: "def f\n  1.to_s\nensure\n  nil\n  :a\nend\n",
    ensure_with_code: "def f\n  1.to_s\nensure\n  nil\n  2.to_s\nend\n",
    ensure_at_the_top_level: "begin\n  1.to_s\nensure\n  nil\nend\n",
    ensure_after_a_rescue: "def f\n  1.to_s\nrescue\n  2\nensure\n  nil\nend\n",
    ensure_of_a_module: "module M\n  1.to_s\nensure\n  1\nend\n",
    ensure_of_a_class: "class C\n  1.to_s\nensure\n  1\nend\n",
    ensure_of_a_singleton_class: "class << self\n  1.to_s\nensure\n  1\nend\n",
    ensure_of_a_lambda: "f = -> do\n  1.to_s\nensure\n  nil\nend\n",
    guarded_class: "class A\n  def b = 1\nend if 1.to_s\n"
  }.freeze

  CASES.each do |name, source|
    define_method(:"test_#{name}") do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{name}.rb")
        File.write(path, source)

        assert_equal ruby_lines(path), zr_lines(path, source), source
      end
    end
  end

  private

  def ruby_lines(path) = Coverage.line_stub(path).each_with_index.filter_map { |v, i| i + 1 if v }

  def zr_lines(path, source)
    Zr::Hir.build(source, path, Zr::BuildOptions.new(trace: true), program: false).coverable.fetch(path).last.uniq.sort
  end
end
