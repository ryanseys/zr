# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/native/build"

# With `ZR_GC_TRACE=1`, the collector of a binary prints one line to
# stderr at the end of each collection. Without it, the collector prints
# nothing. The lines contain heap sizes that change, so the test checks
# the form: one line for each collection, each in the documented form,
# and the last one is the major collection from `GC.start`. This is a
# unit test and not a spec, because collections during boot print before
# the program runs, and a spec compares stderr exactly.
class GcTraceTest < Minitest::Test
  SHAPE = /\Azr_gc \d+ (major( old| every| short)?|minor)( asked| malloc| room)( pressed)? heap \d+ live \d+ -> \d+ malloced \d+ of \d+ MB mark \d+ sweep \d+ ms\z/

  PROGRAM = <<~'RUBY'
    GC.start
    kept = Array.new(50_000) { |i| [i] }
    GC.start
    puts kept.size, GC.count
  RUBY

  def test_every_collection_prints_one_line_under_zr_gc_trace
    Dir.mktmpdir("zr-gc-trace-") do |dir|
      rb = File.join(dir, "trace.rb")
      File.write(rb, PROGRAM)
      bin = File.join(dir, "trace")
      assert_nil Zr::Native::Build.program(Zr::Program.build(PROGRAM, rb), bin, work: dir)

      out, err = capture({}, bin)
      assert_equal "", err, "the collector printed with no ZR_GC_TRACE"
      assert_equal "50000", out.lines.first.chomp

      out, err = capture({ "ZR_GC_TRACE" => "1" }, bin)
      lines = err.lines(chomp: true)
      assert_equal out.lines.last.to_i, lines.size, "one line a collection"
      lines.each { |line| assert_match SHAPE, line }
      assert_includes lines.last, " major asked "
    end
  end

  # `[stdout, stderr]` of `bin` under `env`, run with the limits of the
  # tests (`Checks.run`).
  def capture(env, bin)
    answer = Checks.run([bin], env: env)
    assert_equal 0, answer.code, "exited #{Checks.killed(answer) || answer.code}: #{answer.stdout}#{answer.stderr}"
    [answer.stdout, answer.stderr]
  end
end
