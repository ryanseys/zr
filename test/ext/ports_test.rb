# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# A gem that zr ports (json, stringio) runs its own C extension when the
# build gives it to `--native-ext`: the extension's bundle, not the port,
# is what `require` loads, as in ruby.
class CExtPortsTest < Minitest::Test
  PROGRAM = <<~'RUBY'
    require "json"
    require "stringio"
    p $LOADED_FEATURES.grep(%r{/(json/ext/parser|json/ext/generator|stringio)\.bundle\z}).map { File.basename(_1) }.sort
    p JSON.parse('{"a":[1,2.5,null]}'), JSON.generate({ "b" => "é" })
    io = StringIO.new(+"one\ntwo\n")
    p io.gets, io.read, io.eof?
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  def test_the_gems_own_c_runs_in_place_of_the_port
    skip "json and stringio are not installed in this ruby" unless Zr::Test::CExt.installed("json") && Zr::Test::CExt.installed("stringio")

    dir = File.join(Zr::Test::CExt::DIR, "ports")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "prog.rb")
    File.write(path, PROGRAM)
    env = Zr::Test::CExt::UNBUNDLED
    ruby = Zr::Test::CExt.run(env, RbConfig.ruby, path)
    built = Zr::Test::CExt.run(env, File.join(Zr::Test::CExt::ROOT, "bin", "zr"), "build", "--native-ext", "json,stringio", path, "-o",
                               path.delete_suffix(".rb"))
    zr = built.status.zero? ? Zr::Test::CExt.run(env, path.delete_suffix(".rb")) : built

    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
  end
end
