# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"
require "zr/runtime_sources"

# Eval support's code and a program's units are keyed on the runtime's
# ABI digest, not on its whole digest: their code has only the kernel's
# ids, so an edit that keeps the kernel's description and names keeps
# them, whatever it does to the core's names. Eval support's object is
# keyed on the eval digest, which adds the whole table that numbers its
# data.
class AbiKeyTest < Minitest::Test
  TABLE = { "names" => %w[a b c], "sites" => 3, "kernel" => 2, "functions" => %w[f], "data" => %w[d],
            "description" => "c X 1\n" }.freeze

  def setup
    @dir = Dir.mktmpdir("zr-abi-")
    Zr::Session.current.set(:cache, @dir)
    @target = Zr::Target.default
  end

  def teardown
    Zr::Session.current.forget(:cache)
    FileUtils.rm_rf(@dir)
  end

  def digest(**rows)
    digest = rows.hash.to_s(16)
    Zr::Paths.write_atomic(Zr::RuntimeSources.symbols_path(digest), JSON.generate(TABLE.merge(rows.transform_keys(&:to_s))))
    digest
  end

  def abi(**rows) = Zr::RuntimeSources.for(@target).abi_digest(digest(**rows))
  def eval_key(**rows) = Zr::RuntimeSources.for(@target).eval_digest(digest(**rows))

  def test_the_same_table_and_description_give_the_same_key
    assert_equal abi, abi(functions: %w[f g], data: [])
  end

  def test_a_core_name_keeps_the_abi_and_changes_the_eval_digest
    assert_equal abi, abi(names: %w[a b c e])
    refute_equal eval_key, eval_key(names: %w[a b c e])
  end

  def test_a_kernel_name_changes_the_key
    refute_equal abi, abi(names: %w[a e c])
    refute_equal abi, abi(kernel: 3)
  end

  def test_a_kernel_id_order_change_changes_the_key
    refute_equal abi, abi(names: %w[b a c])
  end

  def test_a_new_site_keeps_the_abi_and_changes_the_eval_digest
    assert_equal abi, abi(sites: 4)
    refute_equal eval_key, eval_key(sites: 4)
  end

  def test_a_description_change_changes_the_key
    refute_equal abi, abi(description: "c X 2\n")
  end

  def test_no_table_gives_no_key
    assert_nil Zr::RuntimeSources.for(@target).abi_digest("missing")
    assert_nil Zr::RuntimeSources.for(@target).eval_digest("missing")
  end
end
