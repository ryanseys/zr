# frozen_string_literal: true

require "test_helper"
require "open3"
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
      assert_equal "#!#{RbConfig.ruby} -W:no-experimental", lines.first
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

  # Under RUBY_BOX the twin's ruby makes boxes of its own, quietly: the
  # program keeps the variable and prints the notice itself.
  def test_the_twin_keeps_the_box_notice_of_its_own_ruby_quiet
    in_cache do |dir|
      exe = launcher(dir, "puts ENV.fetch('RUBY_BOX')")
      out, err, status = Open3.capture3({ "RUBY_BOX" => "1" }, Runner.pinned_launcher(exe))
      assert_predicate status, :success?, err
      assert_equal ["1\n", ""], [out, err]
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

  def test_the_twin_keeps_the_cache_that_zr_was_given_as_a_flag
    in_cache do |dir|
      exe = launcher(dir, "puts ARGV.inspect, ENV.key?('ZR_CACHE')")
      out = IO.popen([Runner.pinned_launcher(exe), "-e", "1", unsetenv_others: true], &:read)
      assert_equal "#{["--cache-dir=#{File.join(dir, "cache")}", "-e", "1"].inspect}\nfalse\n", out,
                   "the flag goes before the words; the program's environment gets no setting"
    end
  end

  def test_each_ruby_and_cache_gets_its_own_twin
    in_cache do |dir|
      exe = launcher(dir, "")
      plain = Runner.pinned_launcher(exe, flags: [])
      refute_equal plain, Runner.pinned_launcher(exe, flags: ["--cache-dir=/elsewhere"])
      refute_equal plain, Runner.pinned_launcher(exe, ruby: "/opt/other/ruby", flags: [])
      assert_equal "#!/opt/other/ruby -W:no-experimental", File.readlines(Runner.pinned_launcher(exe, ruby: "/opt/other/ruby", flags: []), chomp: true).first
      refute_includes File.read(plain), "ARGV", "no flags, no words added"
    end
  end

  def test_a_twin_named_ruby_is_a_twin_of_its_own
    in_cache do |dir|
      exe = launcher(dir, "puts File.basename($PROGRAM_NAME)")
      ruby = Runner.pinned_launcher(exe, flags: [], name: "ruby")
      assert_equal "ruby", File.basename(ruby)
      refute_equal Runner.pinned_launcher(exe, flags: []), ruby
      assert_equal "ruby\n", IO.popen([ruby], &:read), "the program reads the name it ran under"
    end
  end

  def test_a_program_that_zr_runs_as_ruby_gets_a_ruby_twin
    in_cache do
      was = $PROGRAM_NAME
      $PROGRAM_NAME = Runner.pinned_launcher(Runner::EXE, name: "ruby")
      assert_equal "ruby", File.basename(Runner.program_env["ZR_RUBY"])
    ensure
      $PROGRAM_NAME = was
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
      assert_equal Runner::HOME, Runner.program_env["ZR_HOME"]
      $PROGRAM_NAME = File.join(File.dirname(Runner::EXE), "zr-dev")
      refute Runner.program_env.key?("ZR_RUBY"), "only zr itself names a ruby"
      refute Runner.program_env.key?("ZR_HOME"), "only zr itself names a home"
    ensure
      $PROGRAM_NAME = was
    end
  end

  # zr's home is its ruby tree, laid out as an installed ruby's prefix, so
  # a program that zr runs has an RbConfig::TOPDIR, rubylibdir and gem
  # directory that exist.
  def test_the_home_is_an_installed_ruby_layout
    assert_equal File.realpath(Runner::HOME), Runner::HOME
    assert File.file?(File.join(Runner::HOME, "lib/ruby/#{Zr::RUBY_LIB_VERSION}/fileutils.rb"))
    assert File.directory?(File.join(Runner::HOME, "lib/ruby/gems/#{Zr::RUBY_LIB_VERSION}/specifications"))
  end

  # A child ruby runs the steps, since a test must not move this
  # process's directory.
  def test_a_lost_directory_is_left_for_the_build_and_given_back_to_the_program
    Zr::Paths.tmpdir("zr-runner-") do |dir|
      gone = File.join(dir, "gone")
      Dir.mkdir(gone)
      script = <<~RUBY
        require "zr/cli/runner"
        Dir.chdir(ARGV[0])
        Dir.rmdir(ARGV[0])
        Zr::CLI::Runner.keep_lost_cwd
        puts Dir.pwd
        Zr::CLI::Runner.program_env
        begin
          Dir.pwd
        rescue Errno::ENOENT => e
          puts e.class
        end
      RUBY
      out = IO.popen([RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script, gone], &:read)
      assert_equal "/\nErrno::ENOENT\n", out, "zr builds from /, and the program is back in the lost directory"
    end
  end

  def test_a_directory_that_is_there_stays
    out = IO.popen([RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e",
                    "require 'zr/cli/runner'; Zr::CLI::Runner.keep_lost_cwd; Zr::CLI::Runner.program_env; puts Dir.pwd"],
                   chdir: __dir__, &:read)
    assert_equal "#{File.realpath(__dir__)}\n", out
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
