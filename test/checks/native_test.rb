# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/native/cranelift"
require_relative "../../lib/ze0/native/ruby"

# The native roads on hand-written CLIF: each `test/native/<name>.clif`
# (with its `<name>.json` sidecar, when one exists) becomes an object,
# links against libSystem alone, runs, exits 0, and prints
# `<name>.stdout`. The Ruby road always runs; the Cranelift road runs when
# `clif2obj` is built, and the two must agree. Nothing of Ruby-the-language
# is in the loop: this is the native floor every runtime program stands on.
class NativeTest < Minitest::Test
  ROADS = { ruby: Ze0::Native::Ruby.new(ROOT), cranelift: Ze0::Native::Cranelift.new(ROOT) }.freeze

  Dir[File.join(ROOT, "test/native/*.clif")].sort.each do |clif|
    name = File.basename(clif, ".clif")
    ROADS.each do |label, road|
      define_method("test_#{label}_#{name}") do
        skip "clif2obj is not built (bin/ze0 native build)" unless road.available?

        Dir.mktmpdir("ze0-native-") do |dir|
          obj = File.join(dir, "#{name}.o")
          bin = File.join(dir, name)
          data = clif.sub(/\.clif\z/, ".json")
          assert_nil road.compile(clif, obj, data: File.file?(data) ? data : nil)
          assert_nil road.link([obj], bin)
          out = IO.popen([bin], &:read)
          assert_equal 0, $?.exitstatus, "#{name} on the #{label} road exited #{$?.exitstatus}"
          assert_equal File.binread(clif.sub(/\.clif\z/, ".stdout")), out
          libs = IO.popen(["otool", "-L", bin], &:read).scan(%r{^\t(\S+)}).flatten
          assert_equal ["/usr/lib/libSystem.B.dylib"], libs
        end
      end
    end
  end

  # A fact that fails must show: the broken copy exits with its bit set.
  def test_a_failing_fact_is_visible
    Dir.mktmpdir("ze0-native-") do |dir|
      bad = File.join(dir, "bad.clif")
      File.write(bad, File.read(File.join(ROOT, "test/native/arith.clif")).sub("81985529216486894", "81985529216486893"))
      ROADS.each do |label, road|
        next unless road.available?

        obj = File.join(dir, "#{label}.o")
        bin = File.join(dir, label.to_s)
        assert_nil road.compile(bad, obj)
        assert_nil road.link([obj], bin)
        IO.popen([bin], &:read)
        assert_equal 2, $?.exitstatus, "the #{label} road did not see the broken fact"
      end
    end
  end
end
