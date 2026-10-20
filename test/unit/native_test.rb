# frozen_string_literal: true
# zr-test: on macho

require "test_helper"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/native/link"
require_relative "../../test/native/fixtures"

# Native code from IR written by hand. Each `Native::Fixtures` method
# becomes an object file, links against libSystem only, runs, exits 0,
# and prints `test/native/<name>.out`. No Ruby language feature is in
# the test. Every runtime program depends on this layer.
class NativeTest < Minitest::Test
  # Only a darwin host has Mach-O, libSystem and the darwin JIT.
  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  Zr::Native::Fixtures::NAMES.each do |name|
    define_method("test_#{name}") do
      functions, data = Zr::Native::Fixtures.build(name)
      Dir.mktmpdir("zr-native-") do |dir|
        obj = File.join(dir, "#{name}.o")
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.object(functions, data, obj)
        assert_nil Zr::Native::Link.run([obj], bin)
        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus, "#{name} exited #{$?.exitstatus}"
        assert_equal File.binread(File.join(ROOT, "test/native/#{name}.out")), out
        libs = IO.popen(["otool", "-L", bin], &:read).scan(%r{^\t(\S+)}).flatten
        assert_equal ["/usr/lib/libSystem.B.dylib"], libs
      end
    end
  end

  # A failed fact must be visible: the broken copy exits with the bit of that fact set.
  def test_a_failing_fact_is_visible
    functions, data = Zr::Native::Fixtures.build("arith")
    broken = functions.last.blocks.flat_map(&:insts).find { |i| i.args == [81_985_529_216_486_894] }
    refute_nil broken, "arith no longer names the constant this check breaks"
    broken.args[0] = 81_985_529_216_486_893
    Dir.mktmpdir("zr-native-") do |dir|
      obj = File.join(dir, "bad.o")
      bin = File.join(dir, "bad")
      assert_nil Zr::Native::Build.object(functions, data, obj)
      assert_nil Zr::Native::Link.run([obj], bin)
      IO.popen([bin], &:read)
      # The constant fact is fourth from the end, so three facts follow it.
      assert_equal 8, $?.exitstatus, "the broken fact was not seen"
    end
  end
end
