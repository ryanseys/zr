# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zlib"
require_relative "../support/harness/kernel_host"
require_relative "../support/harness/kernel_jit"

# Each pure def of the kernel gives the same answer as machine code and
# on CRuby. A def is pure when it takes and returns numbers only, and it
# and its callees read no memory, static, import or layout, and have no
# loop (an argument outside a loop's domain can run it forever). Such a def is
# a function of its arguments, so the two answers must be equal for any
# argument; edge values and random ones (with a fixed seed) stand in for
# any. A difference is a form whose meaning differs between a binary and
# CRuby that the lowering does not refuse yet.
class KernelPureTest < Minitest::Test
  NUMBERS = %w[Word I32 I8 Bool F64].freeze
  IMPURE = %i[load64 load32 load8 store64 store32 store8 slot static extern gates gates_set gates_enter bytes addr id].freeze
  CASES = 40

  # Arguments in the kernel's domain: a plain operator does not overflow,
  # and a shift is by less than the width (`ZR_KERNEL_CHECKED` checks
  # both). So the values are small and not negative (a count, an index, a
  # byte), and an answer that CRuby gives outside the result's range is an
  # argument outside the def's domain.
  WORDS = [0, 1, 2, 7, 8, 31, 32, 48, 57, 63, 65, 97, 127, 128, 255, 256, 4095, 65_535].freeze
  BYTES = [0, 1, -1, 7, 32, 48, 57, 65, 90, 97, 122, 127, -128].freeze
  FLOATS = [0.0, -0.0, 1.0, -1.0, 0.5, 1.5, -2.5, 3.0e-308, 5.0e-324, 1.0e300, -1.0e300,
            Float::INFINITY, -Float::INFINITY, Float::NAN].freeze

  # The pure defs of the darwin kernel, and one kernel file of them with
  # the constants they read, as machine code and on CRuby.
  def self.unit
    files = Zr::RuntimeSources.for(Zr::Target::AARCH64_DARWIN).kernel_files
    lower = Zr::Machine::Lower.new(files.map { |f| [File.read(f), f] }, Zr::Machine::Symbols.new).declare_files
    defs = pure_defs(lower)
    path = File.join(Dir.mktmpdir("zr-pure-"), "pure.rb")
    File.write(path, source(lower, defs))
    { defs: defs, jit: Zr::Harness::KernelJIT.new(path), host: Zr::Harness::KernelHost.new(path) }
  end

  #: (Zr::Machine::Lower lower) -> Array[Zr::Machine::Def]
  def self.pure_defs(lower)
    defs = lower.declared_defs
    calls = {}
    pure = defs.select do |name, d|
      found = []
      clean = d.params.all? { |_, type| NUMBERS.include?(type) } && NUMBERS.include?(d.ret) && clean?(d.node.body, found)
      calls[name] = found
      clean
    end.keys
    # A def is pure only when each def it calls is.
    loop do
      impure = pure.select { |name| calls[name].any? { |callee| !pure.include?(callee) } }
      break if impure.empty?

      pure -= impure
    end
    pure.sort.map { |name| defs.fetch(name) }
  end

  # Whether `node` uses only arithmetic, pure intrinsics and calls of
  # defs, which it adds to `calls`.
  def self.clean?(node, calls)
    return true if node.nil?
    return false if node.is_a?(Prism::WhileNode) || node.is_a?(Prism::UntilNode)

    if node.is_a?(Prism::CallNode)
      receiver = node.receiver
      if receiver.nil?
        calls << node.name.to_s
      elsif receiver.is_a?(Prism::ConstantReadNode)
        return false unless receiver.name == :Machine && !IMPURE.include?(node.name)
      end
    end
    node.compact_child_nodes.all? { |child| clean?(child, calls) }
  end

  # One kernel file of `defs`, each with its type, and the constants that
  # they read, folded.
  def self.source(lower, defs)
    consts = lower.declared_consts.to_set
    names = Set.new
    defs.each { |d| constants(d.node, consts, names) }
    lines = names.sort.map { |name| "  #{name} = #{lower.const_for(name)}\n" }
    defs.each do |d|
      lines << "\n  #: #{Zr::Machine.rbs_type(d.params.map(&:last), d.ret)}\n  #{d.node.slice}\n"
    end
    "module Zr::Kern\n#{lines.join}end\n"
  end

  def self.constants(node, consts, into)
    into << node.name.to_s if node.is_a?(Prism::ConstantReadNode) && consts.include?(node.name.to_s)
    node.compact_child_nodes.each { |child| constants(child, consts, into) }
  end

  def test_each_pure_def_answers_as_machine_code_does
    unit = self.class.unit
    names = unit[:defs].map(&:name)

    assert_operator names.size, :>=, 30
    assert_includes names, "zr_floor_div"
    assert_includes names, "zr_float_cmp"
    differ = unit[:defs].flat_map do |d|
      rng = Random.new(Zlib.crc32(d.name))
      CASES.times.filter_map do
        args = d.params.map { |_, type| argument(type, rng) }
        expected = begin
          answer = unit[:host].call(d.name.to_sym, *args)
          next unless in_range?(answer, d.ret)

          normal(answer, d.ret)
        rescue StandardError
          # CRuby raises where the machine gives a value (a division by
          # zero): an argument that the def does not take.
          next
        end
        got = normal(unit[:jit].call(d.name, *args.map { |a| native(a) }), d.ret)
        "#{d.name}(#{args.map(&:inspect).join(", ")}): CRuby #{expected.inspect}, machine #{got.inspect}" unless got == expected
      end
    end

    assert_empty differ.first(20), "#{differ.size} answers differ"
  end

  private

  def argument(type, rng)
    case type
    when "Word", "I32" then rng.rand < 0.6 ? WORDS.sample(random: rng) : rng.rand(0..64)
    when "I8" then rng.rand < 0.6 ? BYTES.sample(random: rng) : rng.rand(-128...128)
    when "Bool" then rng.rand < 0.5
    else rng.rand < 0.6 ? FLOATS.sample(random: rng) : (rng.rand - 0.5) * (10**rng.rand(-20..20))
    end
  end

  # Whether CRuby's answer fits the def's result type.
  def in_range?(value, type)
    bits = { "Word" => 64, "I32" => 32, "I8" => 8 }[type] or return true
    value.between?(-(1 << (bits - 1)), (1 << (bits - 1)) - 1)
  end

  # The argument as Fiddle passes it: a Bool is a byte.
  def native(arg)
    case arg
    when true then 1
    when false then 0
    else arg
    end
  end

  # An answer in one form for both: a Bool as 0 or 1, an F64 as its bits
  # (so -0.0 is not 0.0 and NaN equals NaN).
  def normal(value, type)
    case type
    when "Bool" then [true, 1].include?(value) ? 1 : 0
    when "F64" then value.nan? ? :nan : [value].pack("G")
    else value
    end
  end
end
