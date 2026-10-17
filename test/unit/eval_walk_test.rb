# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../support/interpreter_world"

# The tree-walking interpreter, which runs eval in a wasm program
# (lib/zr/eval/interpreter/tree.rb), checked against CRuby's own eval. It runs
# on CRuby over the plain Ruby World of test/support/interpreter_world.rb, so
# these tests build nothing.
class EvalWalkTest < Minitest::Test
  World = Zr::Test::InterpreterWorld

  # A string's value walked and evaluated by ruby, each in a binding that
  # `setup` gives the same locals, or the error each raises.
  def assert_walks_like_ruby(source, setup = "")
    ruby = outcome { eval_in(setup) { |b| eval(source, b) } }
    walked = outcome { eval_in(setup) { |b| World.eval(source, b) } }

    ruby.nil? ? assert_nil(walked, source) : assert_equal(ruby, walked, source)
  end

  def test_return_leaves_the_method_that_called_eval
    assert_equal 7, World.in_method { World.eval("return 7; 8", binding) }
    assert_equal 9, World.in_method { [1].each { World.eval("return 9", binding) }
                                      10 }
  end

  def test_return_in_a_method_of_the_string_leaves_that_method
    assert_walks_like_ruby("def twice(x) = (return x * 2; 0); twice(4)")
  end

  def test_last_match_is_the_frame_s
    assert_walks_like_ruby("'ab' =~ /(b)/; [$~[0], $1, $&, $`, $', $+]")
    assert_walks_like_ruby("$~ && $~[0]", "'zz' =~ /z/")
    assert_walks_like_ruby("'x' =~ /y/; $~")
    assert_walks_like_ruby("'abc'.gsub(/(b)/) { $1.upcase }")
    assert_walks_like_ruby("'a1b2'.scan(/\\d/) { $~[0] }.then { $~[0] }")
    assert_walks_like_ruby("case 'hello' when /l+/ then $~[0] end")
    assert_walks_like_ruby("[$_, ($_ = 'line'), $_]")
  end

  def test_a_match_in_the_string_sets_the_caller_s_match
    b = binding
    World.eval("'cd' =~ /d/", b)

    assert_equal "d", $~[0]
  end

  def test_a_method_of_the_string_keeps_its_own_match
    assert_walks_like_ruby("def m = ('q' =~ /q/; $~[0]); 'r' =~ /r/; [m, $~[0]]")
  end

  def test_a_match_data_is_the_only_value_of_last_match
    assert_walks_like_ruby("$~ = 1")
  end

  def test_regexp_literal_is_one_frozen_object_per_site
    assert_walks_like_ruby("[/a/.frozen?, 2.times.map { /a/ }.uniq.size]")
    assert_walks_like_ruby('[1, 2].map { |i| /a#{i}/o.source }')
  end

  def test_module_nesting
    assert_empty World.eval("Module.nesting", TOPLEVEL_BINDING)
    assert_equal [Enumerable, Comparable], World.eval("Module.nesting", binding, nesting: [Comparable, Enumerable])
  end

  def test_super_reaches_the_method_that_called_eval
    parent = Class.new { def greet(name) = "hi #{name}" }
    child = Class.new(parent) { def greet(name) = World.eval("super", binding) + "!" }

    assert_equal "hi bo!", child.new.greet("bo")
  end

  def test_super_outside_a_method
    error = assert_raises(NoMethodError) { World.eval("super", TOPLEVEL_BINDING) }
    assert_equal "super called outside of method", error.message
    assert_walks_like_ruby("super")
    assert_walks_like_ruby("defined?(super)")
  end

  def test_defined_forms
    assert_walks_like_ruby("[defined?($1), defined?($~), defined?(String)]", "'a' =~ /(a)/")
    assert_walks_like_ruby("[defined?($2), defined?(@x), defined?([].size)]", "'a' =~ /(a)/")
    assert_walks_like_ruby("o = Struct.new(:a).new(1); defined?(o.a = 2)")
  end

  def test_binding_holds_the_string_s_locals
    assert_walks_like_ruby("y = 1; b = binding; [b.local_variable_get(:y), b.local_variable_get(:x)]", "x = 2")
  end

  # A method that the string defines has its own self and locals: its
  # binding has none of the caller's.
  def test_binding_in_a_method_of_the_string_is_that_method_s
    source = "def probe(a) = (b = a + 1; binding); s = probe(1); [s.local_variables.sort, s.local_variable_get(:b), s.receiver.equal?(self)]"
    assert_walks_like_ruby(source, "x = 2")
    assert_walks_like_ruby("o = Object.new; def o.probe = binding; s = o.probe; [s.local_variables, s.receiver.equal?(o)]", "x = 2")
  end

  def test_binding_in_a_class_body_of_the_string_has_its_self_and_locals
    assert_walks_like_ruby("b = class WalkedBody; k = 1; binding; end; [b.local_variables, b.receiver.name.split('::').last]", "x = 2")
  end

  def test_dir_is_the_given_file_s
    assert_walks_like_ruby("__dir__")
    assert_equal "/tmp/x", World.eval("__dir__", binding, file: "/tmp/x/y.rb")
  end

  # A string that names Coverage gets a counter on each branch, which the
  # walker counts through World
  # (test/programs/stdlib/coverage/coverage_of_eval_counts_the_lines_and_branches_that_the_walker_runs.rb).
  def test_a_string_that_names_coverage_walks_its_branches
    assert_walks_like_ruby("Coverage if false; x = 2; x > 1 ? :big : :small")
    assert_walks_like_ruby("Coverage if false; case 3 when 1 then :one else :other end")
  end

  def test_autoload_declares_on_the_lexical_module
    World.eval("autoload :EvalWalkTestWalked, 'eval_walk_test_walked'", TOPLEVEL_BINDING)

    assert_equal "eval_walk_test_walked", Object.autoload?(:EvalWalkTestWalked)
  ensure
    Object.send(:remove_const, :EvalWalkTestWalked) if Object.autoload?(:EvalWalkTestWalked)
  end

  def test_defined_of_a_literal_tests_each_part_as_the_compiler_does
    assert_walks_like_ruby("[defined?([1, 2]), defined?([nope]), defined?([1, *nope]), defined?([String, Nope]), defined?([@unset])]")
    assert_walks_like_ruby("[defined?({ a: nope }), defined?({ **nope }), defined?([[1, [$stdout]]]), defined?([$no_such_gvar])]")
    assert_walks_like_ruby("@set = 1; [defined?([@set, size]), defined?({ k: 1, **{} })]")
  end

  def test_a_multiple_assignment_stages_its_send_targets_before_the_value
    source = "log = []; o = Struct.new(:a, :b).new; f = ->(t) { log << t; o }; " \
             "f.(:r1).a, f.(:r2).b = (log << :rhs; [1, 2]); [log, o.a, o.b]"
    assert_walks_like_ruby(source)
    assert_walks_like_ruby("h = {}; k = ->(x) { (@keys ||= []) << x; x }; h[k.(1)], h[k.(2)] = :a, :b; [h, @keys]")
    assert_walks_like_ruby("o = nil; r = begin; raise e; rescue => o&.x; :rescued; end; [o, r]")
    assert_walks_like_ruby("m = Module.new; s = -> { (@at ||= []) << :scope; m }; s.()::K, z = 1, 2; [m::K, z, @at]")
  end

  def test_a_require_that_the_build_resolves_runs_at_run_time
    Dir.mktmpdir do |dir|
      path = File.join(dir, "walked_feature.rb")
      File.write(path, "$walked_feature = ($walked_feature || 0) + 1\n")
      source = "[require(#{path.inspect}), require(#{path.inspect}), $walked_feature, load(#{path.inspect}), $walked_feature]"
      assert_equal [true, false, 1, true, 2], World.eval(source, binding)
    ensure
      $walked_feature = nil
    end
  end

  private

  # Runs the block with a fresh binding where `setup` ran.
  def eval_in(setup)
    b = binding
    eval(setup, b)
    yield b
  end

  def outcome
    yield
  rescue StandardError => e
    [e.class, e.message]
  end
end
