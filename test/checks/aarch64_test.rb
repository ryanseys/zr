# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/ir/arm64"
require_relative "../../lib/ze0/machine/stub"

# The encoder, held to the `aarch64` gem. The gem is generated from the
# ARM specification, so it is the authority on what an instruction
# encodes to; it is not a dependency, because it builds its own methods
# with `class_eval` on strings and so cannot load in a program that has
# no eval yet. Every function of the runtime assembles through both and
# must give the same bytes.
class Aarch64Test < Minitest::Test
  Aarch64 = Ze0::Machine::Aarch64

  # The gem's assembler, taking our registers: the one emitter drives
  # both, so a difference is the encoding and nothing else.
  class Gem
    NAMES = { [true, true] => :SP, [false, true] => :WSP, [true, false] => :XZR, [false, false] => :WZR }.freeze

    def initialize
      @asm = AArch64::Assembler.new
    end

    def method_missing(name, *args, **options, &block)
      @asm.public_send(name, *args.map { |a| translate(a) }, **options, &block)
    end

    def respond_to_missing?(name, private = false) = @asm.respond_to?(name, private)

    private

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
      unit = Ze0::Machine.unit(Ze0::Zr::KERNEL + [File.join(ROOT, "test/rt/puts.rb")], symbols: symbols)
      functions, = Ze0::Zr.core(unit, symbols)
      unit.functions + functions
    end
  end

  def test_the_runtime_encodes_as_the_gem_does
    require "aarch64"
    functions = self.class.runtime
    names = functions.map(&:name)
    functions.each do |f|
      ours = Ze0::IR::Arm64.new(f, defined: names).compile
      theirs = Ze0::IR::Arm64.new(f, defined: names, assembler: Gem).compile
      assert_equal theirs.bytes.unpack("H*"), ours.bytes.unpack("H*"), "#{f.name} encodes differently"
      assert_equal theirs.relocs, ours.relocs, "#{f.name} relocates differently"
    end
    assert_operator functions.size, :>, 3000
  end

  def test_the_stack_switch_stub_encodes_as_the_gem_does
    require "aarch64"
    ours = Ze0::Machine::Stub.switch
    theirs = Ze0::Machine::Stub.switch(assembler: Gem)
    assert_equal theirs.bytes.unpack("H*"), ours.bytes.unpack("H*")
  end
end
