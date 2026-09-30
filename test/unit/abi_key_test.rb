# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"
require "zr/runtime_sources"

# Eval support and a program's units are keyed on the runtime's ABI
# digest, not on its whole digest: a core or kernel body edit that keeps
# the description and the symbol table keeps them. Any change to those
# changes the key.
class AbiKeyTest < Minitest::Test
  TABLE = { "names" => %w[a b c], "sites" => 3, "functions" => %w[f], "data" => %w[d], "description" => "c X 1\n" }.freeze

  def setup
    @dir = Dir.mktmpdir("zr-abi-")
    Zr::Paths.instance_variable_set(:@cache, @dir)
    @target = Zr::Target.default
  end

  def teardown
    Zr::Paths.instance_variable_set(:@cache, nil)
    FileUtils.rm_rf(@dir)
  end

  def abi(**rows)
    digest = rows.hash.to_s(16)
    Zr::Paths.write_atomic(Zr::RuntimeSources.symbols_path(digest), JSON.generate(TABLE.merge(rows.transform_keys(&:to_s))))
    Zr::RuntimeSources.for(@target).abi_digest(digest)
  end

  def test_the_same_table_and_description_give_the_same_key
    assert_equal abi, abi(functions: %w[f g], data: [])
  end

  def test_a_new_name_changes_the_key
    refute_equal abi, abi(names: %w[a b c e])
  end

  def test_an_id_order_change_changes_the_key
    refute_equal abi, abi(names: %w[b a c])
  end

  def test_a_new_site_changes_the_key
    refute_equal abi, abi(sites: 4)
  end

  def test_a_description_change_changes_the_key
    refute_equal abi, abi(description: "c X 2\n")
  end

  def test_no_table_gives_no_key
    assert_nil Zr::RuntimeSources.for(@target).abi_digest("missing")
  end
end
