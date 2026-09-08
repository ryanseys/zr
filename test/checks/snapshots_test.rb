# frozen_string_literal: true

require_relative "helper"

# ze0's text for two programs, held so a change to its lowering is a
# reviewed diff rather than a surprise. `ZE0_BLESS=1` rewrites them.
class SnapshotsTest < Minitest::Test
  PROGRAMS = {
    "hello" => "puts \"Hello, world!\"\n",
    "fib" => "def fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\nputs fib(10)\n"
  }.freeze

  PROGRAMS.each do |name, program|
    define_method("test_snapshot_#{name}") do
      path = File.join(ROOT, "test/snapshots/#{name}.clif")
      text = ze0_text(program)
      if ENV["ZE0_BLESS"] == "1"
        File.write(path, text)
        skip "blessed #{path}"
      end
      assert_equal File.read(path), text, "#{path} differs from what ze0 writes now (ZE0_BLESS=1 to accept)"
    end
  end
end
