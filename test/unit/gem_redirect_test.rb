# frozen_string_literal: true
# zr-test: eval

require "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../../lib/zr/library/ports"

# A gem in the GemSet that has a library eval support also carries
# (lib/zr/program.rb, `gem_redirects`): here an installed json newer than
# ruby's default, which rubygems activates in its place. The json port's C half is shared
# with eval support and requires "json/common", which names eval support's
# copy. The program loads the gem's files, and that require runs the gem's
# file in place of the copy, so one copy loads, as in ruby: no constant is
# initialized twice. A program with eval loads eval support at its first
# eval, which requires its copy of json the same way.
class GemRedirectTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")
  # Newer than the json port's 3.0.2, and in its range.
  NEWER = "3.0.99"

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

  # Runs `source` with a json gem installed in GEM_HOME at a version newer
  # than the port's (and in its range), whose json.rb records each time
  # it runs: a copy of json's Ruby half.
  def run_with_gem(source)
    Dir.mktmpdir("zr-redirect-") do |dir|
      home = File.join(dir, "home")
      gem = File.join(home, "gems", "json-#{NEWER}")
      FileUtils.mkdir_p([gem, File.join(home, "specifications")])
      FileUtils.cp_r(Zr::Library::Ports.lib("json"), File.join(gem, "lib"))
      File.write(File.join(gem, "lib", "json.rb"), "\n($fixture_loads ||= []) << :json\n", mode: "a")
      spec = Gem::Specification.new do |s|
        s.name = "json"
        s.version = NEWER
        s.summary = "test"
        s.authors = ["zr"]
      end
      File.write(File.join(home, "specifications", "json-#{NEWER}.gemspec"), spec.to_ruby)
      program = File.join(dir, "main.rb")
      File.write(program, source)
      answer = Checks.run([EXE, "run", program], env: { "GEM_HOME" => home, "GEM_PATH" => home })
      assert_equal 0, answer.code, answer.stderr
      [answer.stdout, answer.stderr]
    end
  end
end
