# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"

# Tests which kind of eval support each target includes.
#
# On most targets, eval support is the eval compiler (JIT). Its backend
# writes machine code into the running process. A wasm module cannot do
# this: its code is fixed when the engine instantiates it, and WASI gives
# a guest no way to make a second module. Thus a wasm program includes
# the front end and the tree-walking interpreter (lib/zr/eval/walk.rb).
# The two kinds must never share a cache.
class EvalInterpreterTest < Minitest::Test
  Build = Zr::Hir::Build
  Target = Zr::Target

  def test_jit_target_uses_eval_compiler
    assert_predicate Target::AARCH64_DARWIN, :jits?
    assert_predicate Target::AARCH64_LINUX_MUSL, :jits?
    assert_equal Build::EVAL_COMPILER, Build.eval_file(Target::AARCH64_DARWIN)
    assert_equal Build::EVAL_COMPILER, Build.eval_file(Target::AARCH64_LINUX_MUSL)
  end

  def test_wasm_target_uses_tree_walking_interpreter
    refute_predicate Target::WASM32_WASI, :jits?
    assert_equal Build::EVAL_INTERPRETER, Build.eval_file(Target::WASM32_WASI)
  end

  # The tests can run the tree-walking interpreter on a JIT target. Thus
  # its output can be compared with the output of the eval compiler.
  def test_zr_eval_walk_selects_interpreter_on_jit_target
    with_env("ZR_EVAL" => "walk") do
      assert_equal Build::EVAL_INTERPRETER, Build.eval_file(Target::AARCH64_DARWIN)
    end
  end

  # Both kinds are lowered against the same runtime, so the digest alone
  # does not make them different. If the meta file of one is used for the
  # other, it refers to units that the program does not contain.
  def test_compiler_and_interpreter_use_different_caches
    jit = Zr.eval_support(Target::AARCH64_DARWIN).send(:meta_path)
    walk = with_env("ZR_EVAL" => "walk") { Zr::EvalSupport.new(Zr.runtime(Target::AARCH64_DARWIN)).send(:meta_path) }

    refute_equal jit, walk
    assert_includes jit, "-jit.json"
    assert_includes walk, "-walk.json"
  end

  # The interpreter contains the front end and no backend. The compiler
  # contains both. They are different files, and each defines `Zr::Eval`.
  def test_compiler_and_interpreter_files_define_eval_class
    [Build::EVAL_COMPILER, Build::EVAL_INTERPRETER].each do |path|
      assert_path_exists path
      assert_match(/^\s*class Eval\b/, File.read(path), path)
    end
    refute_equal Build::EVAL_COMPILER, Build::EVAL_INTERPRETER
  end
end
