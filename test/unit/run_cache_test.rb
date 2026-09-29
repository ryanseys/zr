# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zr/run_cache"
require "zr/native/build"

# `zr run` keeps each binary it builds. A second run with the same
# sources runs the kept binary; an edit to the program or to a file it
# requires is a miss, as is a require that stays for the run time.
class RunCacheTest < Minitest::Test
  def setup
    skip "a native link on this host only" unless Zr::Target.default.link
    @work = File.realpath(Dir.mktmpdir("zr-run-cache-"))
    @main = File.join(@work, "main.rb")
    @dep = File.join(@work, "dep.rb")
    File.write(@main, %(require_relative "dep"\nputs Dep.v\n))
    File.write(@dep, "module Dep; def self.v = 1; end\n")
  end

  def teardown
    FileUtils.rm_rf(@work) if @work
  end

  def cache = Zr::RunCache.new(@main, target: Zr::Target.default, digest: Zr.runtime.digest, link: [])

  def build_and_keep
    program = Zr::Native::Build.lower(File.read(@main), @main, sources: true)
    out = File.join(@work, "program")
    why = Zr::Native::Build.program(program, out, work: @work)
    raise why if why

    cache.keep(out, program, File.join(@work, "build"))
    program
  end

  def test_a_second_run_finds_the_binary
    build_and_keep
    kept = cache.hit

    assert kept
    assert_equal "1\n", `#{kept}`
  end

  def test_an_edit_to_a_required_file_is_a_miss
    build_and_keep
    File.write(@dep, "module Dep; def self.v = 2; end\n")

    assert_nil cache.hit
  end

  def test_an_edit_to_the_program_is_a_miss
    build_and_keep
    File.write(@main, File.read(@main) + "puts 3\n")

    assert_nil cache.hit
  end

  def test_a_require_left_for_the_run_time_keeps_nothing
    File.write(@main, %(begin; require_relative "later"; rescue LoadError; end\nputs 1\n))
    program = build_and_keep

    assert_empty program.sources
    assert_nil cache.hit
  end

  def test_the_list_of_sources_names_every_file
    program = build_and_keep

    assert_equal [@main, @dep].sort, program.sources.keys.sort
  end
end
