# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/native/cranelift"

# The Cranelift road on hand-written CLIF: each `test/native/<name>.clif`
# (with its `<name>.json` sidecar) becomes an object, links against
# libSystem alone, runs, and prints `<name>.stdout`. Nothing of Ruby is in
# the loop: this is the native floor every runtime program stands on.
class NativeTest < Minitest::Test
  ROAD = Ze0::Native::Cranelift.new(ROOT)

  Dir[File.join(ROOT, "test/native/*.clif")].sort.each do |clif|
    name = File.basename(clif, ".clif")
    define_method("test_native_#{name}") do
      skip "clif2obj is not built (bin/ze0 native build)" unless ROAD.available?

      Dir.mktmpdir("ze0-native-") do |dir|
        obj = File.join(dir, "#{name}.o")
        bin = File.join(dir, name)
        data = clif.sub(/\.clif\z/, ".json")
        assert_nil ROAD.compile(clif, obj, data: File.file?(data) ? data : nil)
        assert_nil ROAD.link([obj], bin)
        out = IO.popen([bin], &:read)
        assert_equal 0, $?.exitstatus
        assert_equal File.binread(clif.sub(/\.clif\z/, ".stdout")), out
        # libSystem and nothing else.
        assert_equal ["/usr/lib/libSystem.B.dylib"], IO.popen(["otool", "-L", bin], &:read).scan(%r{^\t(\S+)})
                                                                                               .flatten
      end
    end
  end
end
