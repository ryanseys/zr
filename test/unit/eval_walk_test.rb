# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/zr"

# Which eval road a target carries.
#
# A program that evals carries the compiler, and the compiler's back half
# writes machine code into the running process. A wasm module cannot take
# it: its code is fixed when the engine instantiates it, and WASI hands a
# guest no way to make a second module. So a wasm program carries the
# front end and walks the tree instead (lib/zr/eval/walk.rb), and this
# pins which road each target gets and that the two never share a cache.
class EvalWalkTest < Minitest::Test
  Build = Zr::Hir::Build
  Target = Zr::Target

  def test_a_target_that_writes_its_own_code_carries_the_compiler
    assert_predicate Target::AARCH64_DARWIN, :jits?
    assert_predicate Target::AARCH64_LINUX_MUSL, :jits?
    assert_equal Build::EVAL_ROAD, Build.eval_road_file(Target::AARCH64_DARWIN)
    assert_equal Build::EVAL_ROAD, Build.eval_road_file(Target::AARCH64_LINUX_MUSL)
  end

  def test_a_wasm_program_carries_the_walk
    refute_predicate Target::WASM32_WASI, :jits?
    assert_equal Build::WALK_ROAD, Build.eval_road_file(Target::WASM32_WASI)
  end

  # The walk is checked by running it where the compiler would do, so
  # that its answers can be held against the compiling road's own.
  def test_the_environment_asks_for_the_walk_on_a_target_that_could_compile
    with_env("ZR_EVAL" => "walk") do
      assert_equal Build::WALK_ROAD, Build.eval_road_file(Target::AARCH64_DARWIN)
    end
  end

  # Both roads are lowered over the same runtime, so the digest alone
  # does not tell them apart: a meta of one answering for the other would
  # name units the program does not hold.
  def test_the_two_roads_keep_their_caches_apart
    jit = Zr::Zr.road(Target::AARCH64_DARWIN).send(:meta_path)
    walk = with_env("ZR_EVAL" => "walk") { Zr::Zr::Road.new(Zr::Zr.runtime(Target::AARCH64_DARWIN)).send(:meta_path) }

    refute_equal jit, walk
    assert_includes jit, "-jit.json"
    assert_includes walk, "-walk.json"
  end

  # The walk holds the front end and no backend, and the compiler holds
  # both. Neither file is the other's, and each one names `Zr::Eval`.
  def test_each_road_is_a_file_that_names_the_same_class
    [Build::EVAL_ROAD, Build::WALK_ROAD].each do |path|
      assert_path_exists path
      assert_match(/^\s*class Eval\b/, File.read(path), path)
    end
    refute_equal Build::EVAL_ROAD, Build::WALK_ROAD
  end

  private

  def with_env(overlay)
    was = overlay.to_h { |key, _| [key, ENV[key]] }
    ENV.update(overlay)
    yield
  ensure
    was.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
