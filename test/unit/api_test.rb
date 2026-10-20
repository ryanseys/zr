# frozen_string_literal: true
# zr-test: eval

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr"
require_relative "../../lib/zr/cli"

# `Zr.build` (lib/zr/api.rb): the build of `zr build`, from Ruby, with
# errors in place of exit statuses (docs/reference/ruby-api.md).
class ApiTest < Minitest::Test
  def setup
    @dir = File.realpath(Dir.mktmpdir("zr-api-"))
    @app = File.join(@dir, "app.rb")
    File.write(@app, "puts 1 + 2\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_an_object_build_gives_its_result
    result = Zr.build(@app, out: File.join(@dir, "app.o"), emit: :obj, diagnostics: nil)

    assert_equal File.join(@dir, "app.o"), result.path
    assert_equal Zr::Target.default.triple, result.target
    assert_equal :obj, result.emit
    assert_operator File.size(result.path), :>, 0
  end

  def test_a_program_that_does_not_parse_raises
    File.write(@app, "p (\n")
    error = assert_raises(Zr::InvalidProgram) { Zr.build(@app, out: File.join(@dir, "app.o"), emit: :obj, diagnostics: nil) }

    assert_kind_of Zr::Error, error
    assert_equal @app, error.file
    refute_path_exists File.join(@dir, "app.o")
  end

  # A form that zr refuses raises its Refused, with the place and the form.
  def test_a_refused_form_raises_with_its_place
    refused = Zr::Refused.unsupported("a form", file: @app, line: 1, column: 1)
    command = Zr::CLI.command("build")
    error = stub_method(command, :lower!, ->(*, **) { raise refused }) do
      assert_raises(Zr::Refused) { Zr.build(@app, out: File.join(@dir, "app.o"), emit: :obj, diagnostics: nil) }
    end

    assert_kind_of Zr::Error, error
    assert_equal [@app, 1, "a form"], [error.file, error.line, error.form]
  end

  # The settings come from `settings:`, never from ENV.
  def test_settings_are_checked_and_env_is_not_read
    assert_raises(Zr::Config::Invalid) { Zr.build(@app, out: File.join(@dir, "a"), settings: { jobs: "x" }) }
    assert_raises(ArgumentError) { Zr.build(@app, out: File.join(@dir, "a"), settings: { nonsense: 1 }) }
    assert_raises(ArgumentError) { Zr.build(@app, out: File.join(@dir, "a"), settings: { run_cache: false }) }

    with_env("ZR_JOBS" => "x") do
      assert Zr.build(@app, out: File.join(@dir, "app.o"), emit: :obj, diagnostics: nil)
    end
  end

  # Each line that the build prints goes to the diagnostics, not to
  # stderr, and the process's own settings are back after it.
  def test_diagnostics_take_the_lines_and_the_settings_come_back
    before = Zr::Config.current.fingerprint
    lines = []
    assert_silent do
      Zr.build(@app, out: File.join(@dir, "app.o"), emit: :obj, settings: { verify: true }, diagnostics: ->(line) { lines << line })
    end

    assert_equal before, Zr::Config.current.fingerprint
  end

  # One build in a process at a time.
  def test_two_threads_build_one_after_the_other
    active = 0
    most = 0
    lock = Mutex.new
    build = lambda do |*|
      lock.synchronize { most = [most, active += 1].max }
      sleep 0.05
      lock.synchronize { active -= 1 }
      Zr::Result.new(path: "", target: "", emit: :obj, warnings: [], gems: [])
    end
    stub_method(Zr::API, :build, build) do
      Array.new(2) { Thread.new { Zr.build(source: "p 1", out: File.join(@dir, "x"), diagnostics: nil) } }.each(&:join)
    end

    assert_equal 1, most
  end
end
