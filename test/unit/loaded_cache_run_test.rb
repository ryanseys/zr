# frozen_string_literal: true
# zr-test: eval

require "test_helper"
require "tmpdir"
require "zr/native/build"

# A program that compiles a file or an eval's string as it runs keeps the
# code in its cache (lib/zr/cache/loaded.rb), and its next run takes it
# from there. Each run must print what a compile prints, also after an
# edit to a file that the kept code was compiled from.
class LoadedCacheRunTest < Minitest::Test
  # The file comes from ARGV, so the build leaves its load for the run
  # time; its require_relative compiles in with it.
  MAIN = <<~'RUBY'
    load ARGV.fetch(0)
    puts Lib.value
    eval("def twice(x) = x * 2", binding, "(made)", 1)
    puts twice(Lib.value)
    puts eval("[__FILE__, __LINE__]", binding, "(where)", 7).inspect
  RUBY

  def setup
    skip "a native link on this host only" unless Zr::Target.default.link
    @dir = File.realpath(Dir.mktmpdir("zr-loaded-run-"))
    @lib = File.join(@dir, "lib.rb")
    @dep = File.join(@dir, "dep.rb")
    File.write(@lib, %(require_relative "dep"\nmodule Lib; def self.value = DEP + 1; end\n))
    File.write(@dep, "DEP = 20\n")
    main = File.join(@dir, "main.rb")
    File.write(main, MAIN)
    @bin = File.join(@dir, "main")
    program = Zr::Native::Build.lower(MAIN, main)
    why = Zr::Native::Build.program(program, @bin, work: @dir)
    raise why if why
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_a_second_run_takes_the_kept_code
    first = run_main
    kept = entries

    assert_equal "21\n42\n[\"(where)\", 7]\n", first
    refute_empty kept
    assert_equal first, run_main
    assert_equal kept, entries
  end

  def test_an_edit_to_a_file_the_kept_code_read_compiles_again
    run_main
    File.write(@dep, "DEP = 1\n")

    assert_equal "2\n4\n[\"(where)\", 7]\n", run_main
  end

  def test_kept_code_is_the_code_of_a_new_compile
    run_main

    assert_equal "21\n42\n[\"(where)\", 7]\n", run_main("ZR_CODE_CACHE" => "verify")
  end

  def test_no_code_is_kept_under_code_cache_0
    run_main("ZR_CODE_CACHE" => "0")

    assert_empty entries
  end

  private

  def run_main(env = {})
    out = IO.popen({ "ZR_CACHE" => cache, **env }, [@bin, @lib], err: %i[child out], &:read)
    assert_predicate $?, :success?, out
    out
  end

  def cache = File.join(@dir, "cache")

  def entries = Dir[File.join(cache, "store/loaded/**/*.marshal")].sort
end
