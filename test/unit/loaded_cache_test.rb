# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/cache/loaded"
require_relative "../../lib/zr/obj/model"

# A running program keeps the code of each file and eval string that it
# compiles (lib/zr/cache/loaded.rb). A hit needs every file that the
# compile read, and every gvar alias that it asked about, to be as it was.
class LoadedCacheTest < Minitest::Test
  def setup
    @dir = File.realpath(Dir.mktmpdir("zr-loaded-cache-"))
    Zr::Session.current.set(:cache, File.join(@dir, "cache"))
    @dep = File.join(@dir, "dep.rb")
    File.write(@dep, "DEP = 1\n")
  end

  def teardown
    Zr::Session.current.forget(:cache)
    FileUtils.rm_rf(@dir)
  end

  def test_a_kept_entry_comes_back
    cache = loaded
    cache.keep(key, entry)

    taken = cache.take(key, no_aliases)

    assert_equal "zr_load_top", taken.top
    assert_equal ["zr_load_top"], taken.unit.data.map(&:name)
  end

  def test_an_edit_to_a_file_the_compile_read_is_a_miss
    cache = loaded
    cache.keep(key, entry)
    File.write(@dep, "DEP = 2\n")

    assert_nil cache.take(key, no_aliases)
  end

  def test_a_file_the_compile_read_that_is_gone_is_a_miss
    cache = loaded
    cache.keep(key, entry)
    File.delete(@dep)

    assert_nil cache.take(key, no_aliases)
  end

  def test_another_answer_of_a_gvar_alias_is_a_miss
    cache = loaded
    cache.keep(key, entry(aliases: { "$x": nil }))

    assert_nil cache.take(key, ->(_name) { :$y })
  end

  def test_the_same_answer_of_a_gvar_alias_is_a_hit
    cache = loaded
    cache.keep(key, entry(aliases: { "$x": :$y }))

    assert cache.take(key, ->(_name) { :$y })
  end

  def test_another_compiler_is_a_miss
    loaded.keep(key, entry)

    other = Zr::Cache::Loaded.new("another compiler")

    assert_nil other.take(other.key("file", "/app/lib.rb", "x = 1\n", false), no_aliases)
  end

  def test_each_input_of_the_key_counts
    cache = loaded

    keys = [cache.key("file", "/app/lib.rb", "x = 1\n", false), cache.key("file", "/app/lib.rb", "x = 1\n", true),
            cache.key("file", "/app/other.rb", "x = 1\n", false), cache.key("file", "/app/lib.rb", "x = 2\n", false),
            cache.key("eval", "/app/lib.rb", "x = 1\n", false)]

    assert_equal keys.size, keys.uniq.size
  end

  def test_the_cache_is_off_under_code_cache_0
    Zr::Config.with(ZR_CODE_CACHE: "0") { assert_nil Zr::Cache::Loaded.for("stamp") }
  end

  def test_verify_mode_shows
    Zr::Config.with(ZR_CODE_CACHE: "verify") { assert_predicate Zr::Cache::Loaded.for("stamp"), :verify? }
  end

  private

  def loaded = Zr::Cache::Loaded.new("stamp")

  def key = loaded.key("file", "/app/lib.rb", "x = 1\n", false)

  def no_aliases = ->(_name) {}

  def entry(aliases: {})
    unit = Zr::Obj::Unit.new
    unit.data << Zr::Obj::Datum.new("zr_load_top", :data_const, "\0".b * 8, relocs: [Zr::Obj::Reloc.new(0, :symid, "x")], align: 8)
    Zr::Cache::Loaded::Entry.new(unit, "zr_load_top", "", { @dep => Digest::SHA256.hexdigest(File.binread(@dep)) }, aliases, nil)
  end
end
