# frozen_string_literal: true
# zr-test: eval

require "test_helper"
require "open3"
require "fileutils"
require "tmpdir"
require_relative "../../lib/zr/library/ports"

# A gem in the GemSet that has a library eval support also carries
# (lib/zr/program.rb, `gem_redirects`). The json port's C half is shared
# with eval support and requires "json/common", which names eval support's
# copy. The program loads the gem's files, and that require runs the gem's
# file in place of the copy, so one copy loads, as in ruby: no constant is
# initialized twice. A program with eval loads eval support at its first
# eval, which requires its copy of json the same way.
class GemRedirectTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  def test_the_ports_require_runs_the_gems_file
    out, err = run_with_gem(<<~RUBY)
      require "json"
      p $fixture_loads
      p JSON.generate([1])
    RUBY

    assert_equal "[:json]\n\"[1]\"\n", out
    refute_includes err, "already initialized"
  end

  def test_eval_supports_require_runs_the_gems_file
    out, err = run_with_gem(<<~RUBY)
      p eval("1 + 1")
      require "json"
      p $fixture_loads
      p JSON.generate([1])
    RUBY

    assert_equal "2\n[:json]\n\"[1]\"\n", out
    refute_includes err, "already initialized"
  end

  private

  # Runs `source` with `--gem jsonfix=<dir>`: a copy of json's Ruby half
  # whose json.rb records each time it runs.
  def run_with_gem(source)
    Dir.mktmpdir("zr-redirect-") do |dir|
      gem = File.join(dir, "jsonfix")
      FileUtils.cp_r(Zr::Library::Ports.lib("json"), gem)
      File.write(File.join(gem, "json.rb"), "\n($fixture_loads ||= []) << :json\n", mode: "a")
      program = File.join(dir, "main.rb")
      File.write(program, source)
      out, err, status = Open3.capture3(EXE, "run", "--gem", "jsonfix=#{gem}", program)
      assert_predicate status, :success?, err
      [out, err]
    end
  end
end
