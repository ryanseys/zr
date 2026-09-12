# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/native/ruby"
require_relative "../../lib/ze0/native/link"

# The native road on hand-written CLIF: each `test/native/<name>.clif`
# (with its `<name>.json` sidecar, when one exists) becomes an object,
# links against libSystem alone, runs, exits 0, and prints
# `<name>.stdout`. Nothing of Ruby-the-language is in the loop: this is
# the native floor every runtime program stands on.
class NativeTest < Minitest::Test
  Dir[File.join(ROOT, "test/native/*.clif")].sort.each do |clif|
    name = File.basename(clif, ".clif")
    define_method("test_#{name}") do
      Dir.mktmpdir("ze0-native-") do |dir|
        obj = File.join(dir, "#{name}.o")
        bin = File.join(dir, name)
        data = clif.sub(/\.clif\z/, ".json")
        assert_nil Ze0::Native::Ruby.compile(clif, obj, data: File.file?(data) ? data : nil)
        assert_nil Ze0::Native::Link.run([obj], bin)
        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus, "#{name} exited #{$?.exitstatus}"
        assert_equal File.binread(clif.sub(/\.clif\z/, ".stdout")), out
        libs = IO.popen(["otool", "-L", bin], &:read).scan(%r{^\t(\S+)}).flatten
        assert_equal ["/usr/lib/libSystem.B.dylib"], libs
      end
    end
  end

  # A fact that fails must show: the broken copy exits with its bit set.
  def test_a_failing_fact_is_visible
    Dir.mktmpdir("ze0-native-") do |dir|
      bad = File.join(dir, "bad.clif")
      File.write(bad, File.read(File.join(ROOT, "test/native/arith.clif")).sub("81985529216486894", "81985529216486893"))
      obj = File.join(dir, "bad.o")
      bin = File.join(dir, "bad")
      assert_nil Ze0::Native::Ruby.compile(bad, obj)
      assert_nil Ze0::Native::Link.run([obj], bin)
      IO.popen([bin], &:read)
      assert_equal 2, $?.exitstatus, "the broken fact was not seen"
    end
  end
end
