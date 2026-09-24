# frozen_string_literal: true

require "support/runtime_programs"

# Each `test/runtime/<name>.rb` is a toplevel written by hand in the
# machine dialect. It is linked with the runtime into a binary, which
# must print `<name>.out` (stdout and stderr together) and exit with
# `<name>.status` (0 when there is none), both normally and with a
# collection at every allocation.
#
# wasm_test.rb builds the same programs as modules, so a failure there
# is the wasm backend's, and a failure here is the aarch64 backend's.
class RuntimeTest < Minitest::Test
  Zr::Test::RuntimePrograms::FILES.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      want, status = Zr::Test::RuntimePrograms.expected(rb)
      program = Zr::Test::RuntimePrograms.compile(rb)
      Dir.mktmpdir("zr-runtime-") do |dir|
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
