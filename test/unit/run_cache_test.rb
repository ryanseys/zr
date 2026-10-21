# frozen_string_literal: true
# zr-test: eval

require "test_helper"
require "tmpdir"
require "zr/cache/run"
require "zr/gem_set"
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

  def cache = Zr::Cache::Run.new(@main, target: Zr::Target.default, digest: Zr::Runtime.for.digest, link: [])

  def inline(switches)
    Zr::Cache::Run.new("-e", source: "puts 4\n", switches: switches, target: Zr::Target.default, digest: Zr::Runtime.for.digest, link: [])
  end

  # `zr run` of the program in a child, with each build phase on stderr.
  def zr_run = Checks.run([RbConfig.ruby, File.join(ROOT, "bin/zr"), "run", @main], env: { "ZR_TIMING" => "1" }, chdir: @work)

  # How the `zr run` of `answer` ended, and all that it wrote to stderr.
  def ended(answer)
    how = Checks.killed(answer) || (answer.signal && "signal #{answer.signal}") || "status #{answer.code}"
    "the run ended with #{how}:\n#{answer.stderr}"
  end

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

  # A hit runs only the binary that zr kept: another file in its place
  # is a miss, even with the same name and mode.
  def test_a_replaced_binary_is_a_miss
    build_and_keep
    kept = cache.hit
    File.write("#{kept}.new", "#!/bin/sh\necho replaced\n")
    File.chmod(0o755, "#{kept}.new")
    File.rename("#{kept}.new", kept)

    assert_nil cache.hit
  end

  # A new mtime alone makes the hit read the binary's hash, which is the
  # same, so it still hits.
  def test_a_touched_binary_still_hits
    build_and_keep
    kept = cache.hit
    File.utime(Time.now + 60, Time.now + 60, kept)

    assert_equal kept, cache.hit
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

    assert_nil program.sources
    assert_nil cache.hit
  end

  # A program with eval support compiles a file that its require finds
  # as it runs, so a file that appears later changes what the same
  # binary does, as it changes what ruby does.
  def test_a_program_with_eval_keeps_its_binary_past_a_require_left_for_the_run_time
    File.write(@main, %(eval("1")\nbegin; require_relative "later"; rescue LoadError; puts 0; end\nputs Later.v if defined?(Later)\n))
    program = build_and_keep
    kept = cache.hit

    assert_equal [@main], program.sources.keys
    assert_equal "0\n", `#{kept}`
    File.write(File.join(@work, "later.rb"), "module Later; def self.v = 2; end\n")
    assert_equal "2\n", `#{kept}`
  end

  # The files of both gem sets are still there, so only the key tells
  # the two builds apart.
  def test_a_build_with_other_gems_is_a_miss
    build_and_keep
    gems = Zr::GemSet.new([Zr::GemSet::Entry.new(name: "dep", version: "2.0.0", source: "Gemfile.lock", roots: [@work], refusal: nil)])

    other = Zr::Cache::Run.new(@main, target: Zr::Target.default, digest: Zr::Runtime.for.digest, link: [], gems: gems)

    assert_nil other.hit
  end

  # A build with `--allow-runtime-require` leaves an unanswered require
  # to raise when it runs, and a plain `zr run` must refuse it, so the
  # gate is part of the key.
  def test_a_build_with_another_require_gate_is_a_miss
    build_and_keep
    gated = Zr::Cache::Run.new(@main, target: Zr::Target.default, digest: Zr::Runtime.for.digest, link: [], gate: false)

    assert cache.hit
    assert_nil gated.hit
  end

  # A program from -e has no file: the key holds its text and its ruby
  # switches, so the same words run the kept binary, and other switches
  # do not.
  def test_a_program_with_no_file_is_found_by_its_text
    switches = Zr::Hir::Switches.new(inline: true)
    program = Zr::Native::Build.lower("puts 4\n", "-e", Zr::BuildOptions.new(switches: switches), sources: true)
    out = File.join(@work, "program")
    why = Zr::Native::Build.program(program, out, work: @work)
    raise why if why

    inline(switches).keep(out, program, File.join(@work, "build"))
    kept = inline(switches).hit

    assert kept
    assert_equal "4\n", `#{kept}`
    assert_nil inline(Zr::Hir::Switches.new(inline: true, prelude: "$VERBOSE = true\n")).hit
  end

  # In place of a script that does not parse, the build makes the program
  # that reports it. The cache keeps that one under the script's own
  # bytes: a second run builds nothing, and an edit builds again.
  def test_a_script_that_does_not_parse_is_kept_until_it_changes
    File.write(@main, "p (\n")
    first = zr_run

    assert_equal 1, first.code, ended(first)
    assert_includes first.stderr, "hir built"
    second = zr_run

    assert_equal 1, second.code, ended(second)
    refute_includes second.stderr, "hir built"
    assert_equal first.stderr.lines.grep_v(/\Azr: /), second.stderr.lines.grep_v(/\Azr: /)
    File.write(@main, "p [\n")

    assert_includes zr_run.stderr, "hir built"
  end

  def test_the_list_of_sources_names_every_file
    program = build_and_keep

    assert_equal [@main, @dep].sort, program.sources.keys.sort
  end
end
