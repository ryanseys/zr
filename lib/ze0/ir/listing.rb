# frozen_string_literal: true

require_relative "../machine/aarch64"
require_relative "arm64"

module Ze0
  module IR
    # The instructions a compile chose, as arm64 text.
    #
    # `IR::Arm64` takes its assembler as an argument, so this stands in
    # for the encoder: it records every call and forwards it, and the
    # bytes it answers are the encoder's own. What it renders is therefore
    # the backend's selection, not a reading of the bytes back. The
    # encoding itself is a separate question, and `aarch64_test.rb` holds
    # it to the `aarch64` gem.
    #
    # A relocation is part of the selection -- a call to a symbol this
    # link defines and a call to an import assemble to the same `bl` -- so
    # each is written after the instruction that carries it.
    class Listing
      Assembler = Machine::Aarch64::Assembler
      Register = Machine::Aarch64::Registers::Register

      # A number this size or larger reads as a bit pattern, so it is
      # written in hex; below it a number is a count or an offset.
      HEX = 256

      # The listing of `function`, as `IR::Arm64` compiles it.
      def self.of(function, defined: [])
        compiler = Arm64.new(function, defined: defined, assembler: self)
        compiler.asm.text(compiler.compile.relocs)
      end

      def initialize
        @asm = Assembler.new
        @lines = []
        @at = 0
      end

      def make_label(name) = @asm.make_label(name)
      def patch_location(&block) = @asm.patch_location(&block)
      def to_binary = @asm.to_binary

      def put_label(label)
        @lines << [nil, "#{label.name}:"]
        @asm.put_label(label)
        self
      end

      # A word the backend built itself, which carries its own text.
      def <<(word)
        record("  #{word.text}")
        @asm << word
        self
      end

      # The methods this class answers itself; every other mnemonic the
      # encoder has is defined below. They are defined rather than caught
      # by `method_missing`, which no class here may override -- and a
      # defined method answers `respond_to?` without being asked to.
      OWN = %i[make_label put_label patch_location to_binary << b].freeze

      # `b` alone, or `b.cond` when a condition is named. The generated
      # form would read the condition as a shift amount, and a Symbol has
      # no `to_i`.
      def b(label, cond: nil)
        record("  #{cond ? "b.#{cond}" : "b"} #{operands([label]).first}")
        @asm.b(label, cond: cond)
        self
      end

      (Assembler.instance_methods(false) - OWN).each do |mnemonic|
        define_method(mnemonic) do |*args, **options|
          parts = operands(args) + modifier(options)
          record("  #{[mnemonic, parts.join(", ")].join(" ").rstrip}")
          @asm.public_send(mnemonic, *args, **options)
          self
        end
      end

      # The listing, one instruction to a line, labels in the first
      # column, and each relocation beside the instruction it patches.
      def text(relocs = [])
        at = relocs.group_by { |r| r.offset / 4 }
        @lines.map do |index, line|
          notes = index && at[index]
          notes ? "#{line}#{" " * [1, 34 - line.length].max}; #{notes.map { |r| "#{r.kind} #{r.symbol}" }.join(", ")}" : line
        end.join("\n")
      end

      private

      # Every mnemonic the backend calls assembles to exactly one word, so
      # the index a relocation names counts the recorded lines.
      def record(line)
        @lines << [@at, line]
        @at += 1
      end

      # The operands as arm64 writes them: a register by name, an address
      # in brackets with whichever index form follows it, an immediate
      # with a `#`. `rest` is consumed by a memory operand that reaches
      # past itself.
      def operands(args)
        rest = args.dup
        out = []
        until rest.empty?
          a = rest.shift
          out << case a
                 when Register then a.name.downcase
                 when Assembler::Label then a.name.to_s
                 when Array then memory(a, rest)
                 when Symbol then a.to_s
                 else immediate(a)
                 end
        end
        out
      end

      def memory(address, rest)
        base, off = address
        at = base.name.downcase
        case rest.first
        when :! then rest.shift && "[#{at}, #{immediate(off)}]!"
        when Integer then "[#{at}], #{immediate(rest.shift)}"
        else off.to_i.zero? ? "[#{at}]" : "[#{at}, #{immediate(off)}]"
        end
      end

      # `lsl: 12` is a shifted immediate; `shift:`/`amount:` is a shifted
      # register operand. A shift of nothing is not written.
      def modifier(options)
        return [] if options.empty?

        amount = options.fetch(:amount, options.values.first).to_i
        return [] if amount.zero?

        ["#{options.fetch(:shift, options.keys.first)} #{immediate(amount)}"]
      end

      def immediate(value)
        n = Integer(value)
        n.abs >= HEX ? format("#%s0x%x", n.negative? ? "-" : "", n.abs) : "##{n}"
      end
    end
  end
end
