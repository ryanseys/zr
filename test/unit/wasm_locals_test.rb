# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/lower"
require_relative "../../lib/zr/native/build"
require_relative "../../test/native/fixtures"

# The wasm backend puts values whose lifetimes do not overlap in one
# local (lib/zr/backend/wasm/locals.rb). This test checks it two ways: a
# separate liveness analysis finds no write to a local that a live value
# uses, and a program with the shape of a known failure runs under
# wasmtime.
#
# The failure: a loop's join block had three parameters, and the first
# was dead. The dead parameter got a local and released it at once, so
# the next parameter got the same local. The jump writes every
# parameter, the dead one last, so it wrote over the live one. The
# kernel's binary search over code ranges (zr_onig_in_code_range_p) then
# returned true for every code point, and `\p{Han}` matched katakana.
class WasmLocalsTest < Minitest::Test
  SEARCH = <<~RUBY
    module Zr::Kern
      sig [Ptr, Word] => Bool
      def in_ranges(ranges, code)
        n = Machine.u32(Machine.load32(ranges, 0))
        data = ranges + 4
        low = 0
        high = n
        while low < high
          x = (low + high) >> 1
          if code > Machine.u32(Machine.load32(data + (x * 8), 4))
            low = x + 1
          else
            high = x
          end
        end
        low < n && code >= Machine.u32(Machine.load32(data + (low * 8), 0))
      end

      # One bit of the status for each code, set when it is in a range.
      sig [I32, Ptr] => I32
      def main(argc, argv)
        ranges = Machine.bytes("\\x03\\x00\\x00\\x00\\x0A\\x00\\x00\\x00\\x14\\x00\\x00\\x00\\x1E\\x00\\x00\\x00\\x28\\x00\\x00\\x00\\x32\\x00\\x00\\x00\\x3C\\x00\\x00\\x00")
        bits = 0
        bits |= 1 if in_ranges(ranges, 5)
        bits |= 2 if in_ranges(ranges, 15)
        bits |= 4 if in_ranges(ranges, 25)
        bits |= 8 if in_ranges(ranges, 35)
        bits |= 16 if in_ranges(ranges, 55)
        bits |= 32 if in_ranges(ranges, 70)
        Machine.i32(bits)
      end
    end
  RUBY

  # 15, 35 and 55 are in [10, 20], [30, 40] and [50, 60].
  IN_RANGES = 2 | 8 | 16

  def test_a_dead_block_parameter_does_not_take_a_live_ones_local
    functions, = Zr::Machine.compile(SEARCH, "search.rb")
    prepared(functions).each { |f| assert_empty clashes(f), f.name }
  end

  def test_the_hand_written_programs_share_locals_without_a_clash
    Zr::Native::Fixtures::NAMES.each do |name|
      functions, = Zr::Native::Fixtures.build(name)
      prepared(functions).each { |f| assert_empty clashes(f), "#{name}: #{f.name}" }
    end
  end

  def test_binary_search_returns_the_expected_bits_under_wasmtime
    skip "wasmtime is not installed" unless Checks.wasmtime?

    functions, data = Zr::Machine.compile(SEARCH, "search.rb")
    Dir.mktmpdir("zr-wasm-locals-") do |dir|
      wasm = File.join(dir, "search.wasm")
      assert_nil Zr::Native::Build.wasm(functions, data, wasm)
      answer = Checks.run(Zr::Harness::Wasmtime.run(wasm), merge: true)
      refute Checks.killed(answer), "wasmtime was killed at #{Checks.killed(answer)}: #{answer.stdout}"
      assert_equal IN_RANGES, answer.code, answer.stdout
    end
  end

  private

  def prepared(functions)
    functions = functions.map { |f| Marshal.load(Marshal.dump(f)) }
    Zr::IR::Passes.inline(functions).each { |f| Zr::IR::Passes.prepare(f) }
  end

  def reads(i)
    out = i.args.select { |a| Zr::IR.value?(a) }
    i.targets&.each { |(_, args)| out.concat(args.select { |a| Zr::IR.value?(a) }) }
    out
  end

  # Every write into a local that another live value uses, found by a
  # separate liveness analysis: Sets iterated to a fixed point, as simple
  # as possible.
  def clashes(f)
    body = Zr::Backend::Wasm::Codegen::Body.new(Zr::Backend::Wasm::Codegen.new([], []), f)
    body.send(:assign)
    # A value with no local (a constant, written where it is read) cannot
    # share a local.
    local = Hash.new { |h, k| h[k] = Object.new }.merge!(body.instance_variable_get(:@local))
    byname = f.blocks.to_h { |b| [b.name, b] }
    live_in = Hash.new { |h, k| h[k] = Set.new }
    loop do
      changed = false
      f.blocks.reverse_each do |b|
        live = Set.new
        (b.insts.last&.targets || []).each { |name, _| live |= live_in[name] }
        b.insts.reverse_each do |i|
          i.results.each { |v| live.delete(v) }
          live.merge(reads(i))
        end
        b.params.each { |v, _| live.delete(v) }
        next if live == live_in[b.name]

        live_in[b.name] = live
        changed = true
      end
      break unless changed
    end
    found = []
    f.blocks.each do |b|
      live = Set.new
      (b.insts.last&.targets || []).each { |name, _| live |= live_in[name] }
      b.insts.reverse_each do |i|
        i.results.each do |v|
          held = live.find { |w| w != v && local[w] == local[v] }
          found << "#{b.name}: #{v} writes the local of live #{held}" if held
          held = reads(i).find { |a| local[a] == local[v] }
          found << "#{b.name}: #{v} takes the local of its argument #{held}" if held
        end
        if i.op == :jump
          name, = i.targets[0]
          params = byname[name].params.map(&:first)
          params.combination(2).each do |p, q|
            found << "#{b.name}: the jump to #{name} writes #{p} and #{q} into one local" if local[p] == local[q]
          end
        end
        i.results.each { |v| live.delete(v) }
        live.merge(reads(i))
      end
      b.params.each do |p, _|
        held = (live - [p]).find { |w| local[w] == local[p] }
        found << "#{b.name}: parameter #{p} takes the local of live #{held}" if held
      end
    end
    found
  end
end
