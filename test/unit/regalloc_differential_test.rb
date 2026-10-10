# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/backend/aarch64"
require_relative "../../lib/zr/ir/passes"
require_relative "../../lib/zr/ir/interp"
require_relative "../../lib/zr/obj/jit/fiddle"

# Checks the register allocator against code that allocates no registers.
#
# A seeded generator writes small functions with integer operations,
# comparisons, selects, block parameters, a loop, and calls to a callee
# in the same unit. These shapes keep a value in a register across a
# call or across a back edge. Each function runs three ways: through
# `IR::Interp`, through the JIT with every value allocated, and through
# the JIT with every value in its frame home. The three results must be
# the same. A failure prints the seed and the function, and `ZR_SEED=`
# runs that seed again.
#
# A probe takes four integers and a double, and its callee takes three
# integers in an order that the probe selects. The argument registers
# are in the allocator's pool. Thus a parameter can have its home in the
# arrival register of another parameter, an argument can too, and the
# home of a float can be a register that an integer has not left yet.
class RegallocDifferentialTest < Minitest::Test
  COUNT = Integer(ENV.fetch("ZR_DIFFERENTIAL", 500))
  CALLEE = "probe_callee"
  OPS = %i[iadd isub imul band bor bxor ishl ushr sshr sdiv udiv srem urem].freeze
  CONDS = Zr::IR::Inst::CONDS

  def setup
    skip "needs an aarch64 host" unless Zr::Target.host_triple.start_with?("aarch64")
  end

  def test_allocated_and_spilled_code_match_the_interpreter
    seed = Integer(ENV.fetch("ZR_SEED") { Random.new_seed % (1 << 31) })
    rng = Random.new(seed)
    functions = [callee] + Array.new(COUNT) { |n| generate(rng, "probe_#{n}") }
    functions.each { |f| Zr::IR::Passes.prepare(f, strict: true) }
    interp = Zr::IR::Interp.new(functions)
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

  # The 64-bit word: the interpreter returns it unsigned, Fiddle signed.
  def word(n) = n & 0xFFFF_FFFF_FFFF_FFFF

  # The functions loaded into this process, each callable by name.
  def loaded(functions, allocate:)
    unit = Zr::Backend::Aarch64.unit(functions.map(&:dup), [], allocate: allocate)
    symbols = Zr::Obj::JIT.load(unit, host: Zr::Obj::JIT::Fiddle.new)
    functions.to_h do |f|
      types = f.params.map { |t| t == "f64" ? Fiddle::TYPE_DOUBLE : Fiddle::TYPE_LONG }
      [f.name, Fiddle::Function.new(symbols.fetch(f.name), types, Fiddle::TYPE_LONG)]
    end
  end

  # `probe_callee(x, y, z) = x * 3 + y * 5 + z * 7 + 1`, in the same unit
  # as the probes.
  def callee
    f = Zr::IR::Function.new(CALLEE, %w[i64 i64 i64], "i64")
    x, y, z = f.args
    sum = f.iadd(f.imul(x, f.iconst("i64", 3)), f.imul(y, f.iconst("i64", 5)))
    f.ret(f.iadd(f.iadd(sum, f.imul(z, f.iconst("i64", 7))), f.iconst("i64", 1)))
    f
  end

  # A function of four i64 arguments and an f64 argument (read as its
  # bits): some operations, a loop of a few iterations that passes two
  # values between iterations, more operations, and a return value.
  def generate(rng, name)
    f = Zr::IR::Function.new(name, %w[i64 i64 i64 i64 f64], "i64")
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

  # One instruction on values in `pool`, or on a constant, that returns
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
        "    #{i.results.join(", ")}#{" = " unless i.results.empty?}#{i.op}#{".#{i.type}" if i.type}#{".#{i.cond}" if i.cond} " \
          "#{i.args.join(", ")}#{" -> #{i.targets.map { |t, args| "#{t}(#{args.join(", ")})" }.join(" | ")}" if i.targets}" \
          "#{" #{i.callee}" if i.callee}"
      end
      ["  #{b.name}(#{b.params.map { |v, t| "#{v}: #{t}" }.join(", ")}):", *lines].join("\n")
    end.join("\n")
  end
end
