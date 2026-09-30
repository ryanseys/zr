# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../lib/zr/bootstrap/handoff"
require_relative "../../lib/zr/stdlib"

# The compiled compiler, as an installed gem on an Apple Silicon Mac runs
# it: exe/zr builds it from this tree, and it builds programs.
#
# A program that evals links eval support from the cache. Its code has the
# id of each symbol, the runtime's too, and a build with the ledger and one
# without (`rake build:self`, `ZR_LEDGER=0`) give the runtime's names other
# ids. When the object's key had only its files, a build with one table
# linked the object that a build with the other table wrote, and each eval
# read names by the wrong ids (`Zr::Digests.eval_key`, test/unit/eval_key_test.rb).
# This test builds one such program in turn with the compiled compiler,
# with ruby and no ledger, and with the compiled compiler again, all in
# this checkout's one cache.
class BootstrapHandoffE2ETest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  # Not bin/zr: the test never replaces the checkout's own compiled
  # compiler. It stays between runs, so a run builds it again only after a
  # source changes (lib/zr/bootstrap/binary.rb).
  BINARY = File.join(ROOT, "tmp/e2e-compiled/zr")

  # A self-build, and three builds of a program with eval support.
  def self.deadline = 3600

  PROGRAM = <<~RUBY
    require "csv"
    puts CSV::VERSION
    puts eval("[1, 2].sum + 3")
  RUBY

  def setup
    skip "this host cannot run the compiled compiler" unless Zr::Bootstrap::Handoff.runnable?
  end

  # `zr build` in a child with only the environment that this suite
  # started with, and `env` over it.
  def zr_build(program, out, env)
    overlay = { "ZR_BINARY" => BINARY, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLER_SETUP" => nil }.merge(env)
    log, status = Open3.capture2e(Zr::Harness::CleanEnv.env(overlay), RbConfig.ruby, EXE, "build", program, "-o", out,
                                  chdir: ROOT, unsetenv_others: true)
    assert_predicate status, :success?, log
    log
  end

  # exe/zr gives a build to the compiled compiler only while it is
  # current; a self-build that fails leaves the build to ruby, which would
  # hide a fault of the compiled compiler.
  def compiled_took_it!(log)
    refute_includes log, "did not build"
    was = ENV["ZR_BINARY"]
    ENV["ZR_BINARY"] = BINARY
    assert Zr::Bootstrap::Handoff.current?, "the compiled compiler at #{BINARY} is not current:\n#{log}"
  ensure
    ENV["ZR_BINARY"] = was
  end

  def run_binary(out)
    stdout, stderr, status = Open3.capture3(out)
    [stdout, status.success? ? "" : stderr.lines.first(3).join]
  end

  def test_programs_that_eval_run_whichever_compiler_and_ledger_built_them
    expected = "#{Zr::Stdlib::BUNDLED.fetch("csv")}\n6\n"
    Dir.mktmpdir("zr-e2e-compiled-") do |dir|
      program = File.join(dir, "evals.rb")
      File.write(program, PROGRAM)
      {
        "the compiled compiler" => { "ZR_COMPILED" => "1" },
        "ruby without the ledger" => { "ZR_COMPILED" => "0", "ZR_LEDGER" => "0" },
        "the compiled compiler again" => { "ZR_COMPILED" => "1" }
      }.each_with_index do |(who, env), i|
        out = File.join(dir, "evals-#{i}")
        log = zr_build(program, out, env)
        compiled_took_it!(log) if env["ZR_COMPILED"] == "1"

        assert_equal [expected, ""], run_binary(out), "a binary that #{who} built"
      end
      assert_path_exists BINARY, "exe/zr built no compiled compiler"
    end
  end
end
