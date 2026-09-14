# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/native/build"
require_relative "../../lib/ze0/native/link"
require_relative "../../test/native/fixtures"

# The native floor, on IR written by hand: each `Native::Fixtures` method
# becomes an object, links against libSystem alone, runs, exits 0, and
# prints `test/native/<name>.stdout`. Nothing of Ruby-the-language is in
# the loop: this is the ground every runtime program stands on.
class NativeTest < Minitest::Test
  # Mach-O, libSystem and the darwin JIT: only a darwin host has them.
  def setup
    skip "needs an aarch64-apple-darwin host" unless Ze0::Target::AARCH64_DARWIN.native?
  end

  Ze0::Native::Fixtures::NAMES.each do |name|
    define_method("test_#{name}") do
      functions, data = Ze0::Native::Fixtures.build(name)
      Dir.mktmpdir("ze0-native-") do |dir|
        obj = File.join(dir, "#{name}.o")
        bin = File.join(dir, name)
        assert_nil Ze0::Native::Build.object(functions, data, obj)
        assert_nil Ze0::Native::Link.run([obj], bin)
        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus, "#{name} exited #{$?.exitstatus}"
        assert_equal File.binread(File.join(ROOT, "test/native/#{name}.stdout")), out
        libs = IO.popen(["otool", "-L", bin], &:read).scan(%r{^\t(\S+)}).flatten
        assert_equal ["/usr/lib/libSystem.B.dylib"], libs
      end
    end
  end

  # A fact that fails must show: the broken copy exits with its bit set.
  def test_a_failing_fact_is_visible
    functions, data = Ze0::Native::Fixtures.build("arith")
    broken = functions.last.blocks.flat_map(&:insts).find { |i| i.args == [81_985_529_216_486_894] }
    refute_nil broken, "arith no longer names the constant this check breaks"
    broken.args[0] = 81_985_529_216_486_893
    Dir.mktmpdir("ze0-native-") do |dir|
      obj = File.join(dir, "bad.o")
      bin = File.join(dir, "bad")
      assert_nil Ze0::Native::Build.object(functions, data, obj)
      assert_nil Ze0::Native::Link.run([obj], bin)
      IO.popen([bin], &:read)
      assert_equal 2, $?.exitstatus, "the broken fact was not seen"
    end
  end
end
