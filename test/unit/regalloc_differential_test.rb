# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/backend/aarch64"
require_relative "../../lib/ze0/ir/passes"
require_relative "../../lib/ze0/ir/interp"
require_relative "../../lib/ze0/obj/jit/fiddle"

# The register allocator, held to the road that allocates nothing.
#
# A seeded generator writes small functions over the integer
# operations, comparisons, selects, block parameters, a loop and calls
# to a callee in the same unit -- the shapes that put a value in a
# register across a call, or across a back edge -- and each runs three
# ways: through `IR::Interp`, and through the JIT with every value
# allocated and with every value in its frame home. The three must
# agree. A failure prints the seed and the function, and `ZE0_SEED=`
# runs that seed again.
#
# A probe takes four integers and a double, and its callee three
# integers in an order the probe picks: the argument registers are
# in the allocator's pool, so a parameter may be homed in another's
# arrival register, an argument in another's, and a float's home may
# be a register an integer had yet to leave (the case that reached a
# spec before it reached this test).
class RegallocDifferentialTest < Minitest::Test
  COUNT = Integer(ENV.fetch("ZE0_DIFFERENTIAL", 500))
  CALLEE = "probe_callee"
  OPS = %i[iadd isub imul band bor bxor ishl ushr sshr sdiv udiv srem urem].freeze
  CONDS = Ze0::IR::Inst::CONDS

  def setup
    skip "needs an aarch64-apple-darwin host" unless Ze0::Target::AARCH64_DARWIN.native?
  end

  def test_allocated_and_unallocated_code_answer_as_the_interpreter_does
    seed = Integer(ENV.fetch("ZE0_SEED") { Random.new_seed % (1 << 31) })
    rng = Random.new(seed)
    functions = [callee] + COUNT.times.map { |n| generate(rng, "probe_#{n}") }
    functions.each { |f| Ze0::IR::Passes.prepare(f, strict: true) }
    interp = Ze0::IR::Interp.new(functions)
    allocated = loaded(functions, allocate: true)
    spilled = loaded(functions, allocate: false)
    functions.drop(1).each do |f|
      args = [rng.rand(-100..100), rng.rand(-100..100), rng.rand(-100..100), rng.rand(-100..100), rng.rand(-100..100).to_f]
      # The interpreter takes a double as its bits; Fiddle takes the Float.
      want = word(interp.answer(f.name, args.map { |a| a.is_a?(Float) ? [a].pack("E").unpack1("Q<") : a }))
      assert_equal want, word(allocated.fetch(f.name).call(*args)), "seed #{seed}: #{f.name}#{args.inspect} allocated\n#{dump(f)}"
      assert_equal want, word(spilled.fetch(f.name).call(*args)), "seed #{seed}: #{f.name}#{args.inspect} spilled\n#{dump(f)}"
    end
  end

  private

  # The 64-bit word: the interpreter answers it unsigned, Fiddle signed.
  def word(n) = n & 0xFFFF_FFFF_FFFF_FFFF

  # The functions loaded into this process, each callable by name.
  def loaded(functions, allocate:)
    unit = Ze0::Backend::Aarch64.unit(functions.map(&:dup), [], allocate: allocate)
    symbols = Ze0::Obj::JIT.load(unit, host: Ze0::Obj::JIT::Fiddle.new)
    functions.to_h do |f|
      types = f.params.map { |t| t == "f64" ? Fiddle::TYPE_DOUBLE : Fiddle::TYPE_LONG }
      [f.name, Fiddle::Function.new(symbols.fetch(f.name), types, Fiddle::TYPE_LONG)]
    end
  end

  # `probe_callee(x, y, z) = x * 3 + y * 5 + z * 7 + 1`, in the unit
  # beside the probes.
  def callee
    f = Ze0::IR::Function.new(CALLEE, %w[i64 i64 i64], "i64")
    x, y, z = f.args
    sum = f.iadd(f.imul(x, f.iconst("i64", 3)), f.imul(y, f.iconst("i64", 5)))
    f.ret(f.iadd(f.iadd(sum, f.imul(z, f.iconst("i64", 7))), f.iconst("i64", 1)))
    f
  end

  # A function of four i64 arguments and an f64 one, read as its bits:
  # a run of operations, a loop of a few passes carrying two values, a
  # run more, and an answer.
  def generate(rng, name)
    f = Ze0::IR::Function.new(name, %w[i64 i64 i64 i64 f64], "i64")
    callee = f.callee(CALLEE, %w[i64 i64 i64], "i64")
    *ints, double = f.args
    pool = ints + [f.bitcast("i64", double)]
    rng.rand(2..6).times { pool << operation(f, rng, pool, callee) }

    header, (acc, carry, i) = f.block(%w[i64 i64 i64])
    body = f.label
    done = f.label
    f.jump(header, [pool.sample(random: rng), pool.sample(random: rng), f.iconst("i64", 0)])
    f.switch(header)
    f.brif(f.icmp("slt", i, f.iconst("i64", rng.rand(1..4))), body, done)
    f.switch(body)
    inner = pool + [acc, carry]
    rng.rand(1..4).times { inner << operation(f, rng, inner, callee) }
    f.jump(header, [inner.sample(random: rng), inner.sample(random: rng), f.iadd(i, f.iconst("i64", 1))])
    f.switch(done)
    # The header's parameters reach here: the loop's last values.
    pool.push(acc, carry)
    rng.rand(0..3).times { pool << operation(f, rng, pool, callee) }
    f.ret(pool.sample(random: rng))
    f
  end

  # One instruction over values in `pool`, or a constant, answering
  # an i64 value.
  def operation(f, rng, pool, callee)
    a = pool.sample(random: rng)
    b = rng.rand < 0.25 ? f.iconst("i64", rng.rand(-8..8)) : pool.sample(random: rng)
    case rng.rand(10)
    when 0..5 then f.binop(OPS.sample(random: rng), a, b)
    when 6 then f.uextend("i64", f.icmp(CONDS.sample(random: rng), a, b))
    when 7 then f.csel(f.icmp(CONDS.sample(random: rng), a, b), pool.sample(random: rng), pool.sample(random: rng))
    else f.call_val(callee, [a, pool.sample(random: rng), pool.sample(random: rng)])
    end
  end

  def dump(f)
    f.blocks.map do |b|
      lines = b.insts.map do |i|
        "    #{i.results.join(', ')}#{' = ' unless i.results.empty?}#{i.op}#{".#{i.type}" if i.type}#{".#{i.cond}" if i.cond} " \
          "#{i.args.join(', ')}#{" -> #{i.targets.map { |t, args| "#{t}(#{args.join(', ')})" }.join(' | ')}" if i.targets}#{" #{i.callee}" if i.callee}"
      end
      ["  #{b.name}(#{b.params.map { |v, t| "#{v}: #{t}" }.join(', ')}):", *lines].join("\n")
    end.join("\n")
  end
end
