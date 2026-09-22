# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"

# `ZR_GC_TRACE=1` makes a binary's collector print one line to stderr a
# collection, as it ends; without it the collector prints nothing. The
# lines carry heap sizes no recording could pin, so the check is a
# shape: one line a collection, each of the documented form, the last
# one the major that `GC.start` asked for. A unit test and not a spec
# because the boot's own collections print before any program code
# runs, and a spec holds stderr to a literal.
class GcTraceTest < Minitest::Test
  SHAPE = /\Azr_gc \d+ (major( old| every| short)?|minor)( asked| malloc| room)( pressed)? heap \d+ live \d+ -> \d+ malloced \d+ of \d+ MB mark \d+ sweep \d+ ms\z/

  PROGRAM = <<~'RUBY'
    GC.start
    kept = Array.new(50_000) { |i| [i] }
    GC.start
    puts kept.size, GC.count
  RUBY

  def test_every_collection_prints_one_line_under_zr_gc_trace
    Dir.mktmpdir("ze0-gc-trace-") do |dir|
      rb = File.join(dir, "trace.rb")
      File.write(rb, PROGRAM)
      bin = File.join(dir, "trace")
      assert_nil Ze0::Native::Build.program(Ze0::Zr.program(PROGRAM, rb), bin, work: dir)

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

  def capture(env, bin)
    Dir.mktmpdir("ze0-gc-trace-err-") do |dir|
      err = File.join(dir, "err")
      out = IO.popen(env, [bin], err: [err, "w"], &:read)
      assert_equal 0, $?.exitstatus, "exited #{$?.exitstatus}: #{out}#{File.read(err)}"
      [out, File.read(err)]
    end
  end
end
