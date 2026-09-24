# frozen_string_literal: true

require "support/rt_programs"

# The kernel core: each `test/rt/<name>.rb` is a hand-written toplevel
# in the dialect, linked beside the runtime into a binary, and prints
# `<name>.stdout` (stderr folded in) and exits with `<name>.exit` (0
# when absent), plain and with a collection at every allocation.
#
# The same programs go through the wasm road in `wasm_test.rb`, so a
# failure there is the wasm backend's and a failure here is the aarch64
# one's.
class RtTest < Minitest::Test
  RtPrograms::FILES.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      want, status = RtPrograms.expected(rb)
      program = RtPrograms.compile(rb)
      Dir.mktmpdir("zr-rt-") do |dir|
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.program(program, bin, work: dir)
        [{}, { "ZR_GC_STRESS" => "1" }].each do |env|
          out = IO.popen(env, [bin], err: %i[child out], &:read)
          assert_equal status, $?.exitstatus, "#{name} (#{env}) exited #{$?.exitstatus}: #{out}"
          assert_equal want, out
        end
      end
    end
  end
end
