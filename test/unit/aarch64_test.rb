# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/backend/aarch64/codegen"
require_relative "../../lib/ze0/backend/aarch64/stub"

# The encoder, held to the `aarch64` gem. The gem is generated from the
# ARM specification, so it is the authority on what an instruction
# encodes to; it is not a dependency, because it builds its own methods
# with `class_eval` on strings and so cannot load in a program that has
# no eval yet. Every function of the runtime assembles through both and
# must give the same bytes.
class Aarch64Test < Minitest::Test
  Aarch64 = Ze0::Backend::Aarch64

  # The gem's assembler, taking our registers: the one emitter drives
  # both, so a difference is the encoding and nothing else. The gem has
  # no SIMD&FP registers, so an instruction on a double takes the word
  # the ARM specification gives it, in the place of a `nop` the gem
  # assembles to keep the positions.
  class Gem
    NAMES = { [true, true] => :SP, [false, true] => :WSP, [true, false] => :XZR, [false, false] => :WZR }.freeze
    FLOAT3 = { fadd: 0x1E602800, fsub: 0x1E603800, fmul: 0x1E600800, fdiv: 0x1E601800 }.freeze
    FLOAT2 = { fneg: 0x1E614000, fabs: 0x1E60C000, fsqrt: 0x1E61C000, frintm: 0x1E654000,
               frintp: 0x1E64C000, frintz: 0x1E65C000, frintn: 0x1E644000 }.freeze

    def initialize
      @asm = AArch64::Assembler.new
      @count = 0
      @floats = []
    end

    def make_label(name) = @asm.make_label(name)
    def put_label(label) = @asm.put_label(label)
    def patch_location(&block) = @asm.patch_location(&block)

    def to_binary
      words = @asm.to_binary.unpack("L<*")
      @floats.each { |index, word| words[index] = word }
      words.pack("L<*")
    end

    def method_missing(name, *args, **options, &block)
      if args.flatten.any? { |a| a.is_a?(Aarch64::Registers::Register) && a.float? }
        @floats << [@count, float_word(name, args)]
        @asm.nop
      else
        @asm.public_send(name, *args.map { |a| translate(a) }, **options, &block)
      end
      @count += 1
      self
    end

    def respond_to_missing?(name, private = false) = @asm.respond_to?(name, private)

    private

    # The word of an instruction on doubles, as the specification's
    # encoding diagrams read.
    def float_word(name, args)
      d, n, m = args
      case name
      when :fmov
        return 0x1E604000 | n.to_i << 5 | d.to_i if d.float? && n.float?

        (d.float? ? 0x9E670000 : 0x9E660000) | n.to_i << 5 | d.to_i
      when :fcmp then 0x1E602000 | n.to_i << 16 | d.to_i << 5
      when :scvtf then (n.wide? ? 0x9E620000 : 0x1E620000) | n.to_i << 5 | d.to_i
      when :fcvtzs then 0x9E780000 | n.to_i << 5 | d.to_i
      when :ldr, :str then (name == :ldr ? 0xFD400000 : 0xFD000000) | (n[1].to_i / 8) << 10 | n[0].to_i << 5 | d.to_i
      when :ldp, :stp then (name == :ldp ? 0x6D400000 : 0x6D000000) | ((m[1].to_i / 8) & 0x7F) << 15 | n.to_i << 10 | m[0].to_i << 5 | d.to_i
      else
        FLOAT3.key?(name) ? FLOAT3.fetch(name) | m.to_i << 16 | n.to_i << 5 | d.to_i : FLOAT2.fetch(name) | n.to_i << 5 | d.to_i
      end
    end

    def translate(value)
      case value
      when Aarch64::Registers::Register then register(value)
      when Array then value.map { |v| translate(v) }
      else value
      end
    end

    def register(r)
      return AArch64::Registers.const_get(NAMES.fetch([r.wide?, r.sp?])) if r.to_i == 31

      AArch64::Registers.const_get(:"#{r.wide? ? "X" : "W"}#{r.to_i}")
    end
  end

  def self.runtime
    @runtime ||= begin
      symbols = Ze0::Machine::Symbols.new
      unit = Ze0::Machine.unit(Ze0::Zr.kernel_files + [File.join(ROOT, "test/rt/puts.rb")], symbols: symbols)
      functions, = Ze0::Zr.core(unit, symbols)
      unit.functions + functions
    end
  end

  def test_the_runtime_encodes_as_the_gem_does
    require "aarch64"
    functions = self.class.runtime
    names = functions.map(&:name).to_set
    functions.each do |f|
      ours = Ze0::Backend::Aarch64::Codegen.new(f, defined: names).compile
      theirs = Ze0::Backend::Aarch64::Codegen.new(f, defined: names, assembler: Gem).compile
      assert_equal theirs.bytes.unpack("H*"), ours.bytes.unpack("H*"), "#{f.name} encodes differently"
      assert_equal theirs.relocs, ours.relocs, "#{f.name} relocates differently"
    end
    assert_operator functions.size, :>, 3000
  end

  def test_the_stack_switch_stub_encodes_as_the_gem_does
    require "aarch64"
    ours = Ze0::Backend::Aarch64::Stub.switch
    theirs = Ze0::Backend::Aarch64::Stub.switch(assembler: Gem)
    assert_equal theirs.bytes.unpack("H*"), ours.bytes.unpack("H*")
  end
end
