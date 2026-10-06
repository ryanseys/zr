# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/cli/runner"

# The zr that a program's RbConfig.ruby names: like a ruby binary, it
# starts with any environment, since a test of ruby runs it with none.
class RunnerTest < Minitest::Test
  Runner = Zr::CLI::Runner

  def test_the_twin_names_this_ruby_and_loads_the_launcher
    in_cache do |dir|
      exe = launcher(dir, "puts :ran")
      twin = Runner.pinned_launcher(exe)
      lines = File.readlines(twin, chomp: true)
      assert_equal "#!#{RbConfig.ruby}", lines.first
      assert_includes lines, "load #{File.realpath(exe).dump}"
      assert File.executable?(twin), "the twin runs as a command"
      assert_equal "zr", File.basename(twin), "the twin still reads as zr"
    end
  end

  def test_one_twin_serves_each_launcher
    in_cache do |dir|
      exe = launcher(dir, "")
      twin = Runner.pinned_launcher(exe)
      File.write(twin, "#!/bin/sh\n# kept\n")
      assert_equal twin, Runner.pinned_launcher(exe), "the same launcher reuses its twin"
      assert_equal "# kept", File.readlines(twin, chomp: true).last, "and leaves it as it is"
      refute_equal twin, Runner.pinned_launcher(launcher(dir, "", name: "other/zr")), "another launcher gets its own twin"
    end
  end

  def test_the_twin_starts_with_no_environment
    in_cache do |dir|
      exe = launcher(dir, "puts ENV.to_h.inspect, __FILE__")
      out = IO.popen([{ "A" => "B" }, Runner.pinned_launcher(exe), unsetenv_others: true], &:read)
      assert_predicate $?, :success?
      env, file = out.lines(chomp: true)
      assert_includes env, '"A" => "B"'
      refute_includes env, '"PATH"', "the twin needs no PATH to find ruby"
      assert_equal File.realpath(exe), file
    end
  end

  def test_with_no_cache_to_write_to_the_launcher_stands
    Zr::Paths.tmpdir("zr-runner-") do |dir|
      blocked = File.join(dir, "file")
      File.write(blocked, "")
      exe = launcher(dir, "")
      with_env("ZR_CACHE" => blocked) { assert_equal File.realpath(exe), Runner.pinned_launcher(exe) }
    end
  end

  def test_a_program_that_zr_runs_gets_the_twin_as_its_ruby
    in_cache do
      was = $PROGRAM_NAME
      $PROGRAM_NAME = Runner::EXE
      assert_equal Runner.pinned_launcher(Runner::EXE), Runner.program_env["ZR_RUBY"]
      $PROGRAM_NAME = File.join(File.dirname(Runner::EXE), "zr-dev")
      refute Runner.program_env.key?("ZR_RUBY"), "only zr itself names a ruby"
    ensure
      $PROGRAM_NAME = was
    end
  end

  private

  def in_cache
    Zr::Paths.tmpdir("zr-runner-") do |dir|
      with_env("ZR_CACHE" => File.join(dir, "cache")) { yield dir }
    end
  end

  def launcher(dir, body, name: "exe/zr")
    path = File.join(dir, name)
    Zr::Paths.mkdir_p(File.dirname(path))
    File.write(path, "#!/usr/bin/env ruby\n#{body}\n")
    path
  end
end
