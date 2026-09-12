# frozen_string_literal: true

require_relative "../machine/aarch64"

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
    class Listing
      include Machine::Aarch64::Registers
      Assembler = Machine::Aarch64::Assembler

      # A number this size or larger reads as a bit pattern, so it is
      # written in hex; below it a number is a count or an offset.
      HEX = 256

      def initialize
        @asm = Assembler.new
        @lines = []
      end

      def make_label(name) = @asm.make_label(name)
      def patch_location(&block) = @asm.patch_location(&block)
      def to_binary = @asm.to_binary

      def put_label(label)
        @lines << "#{label.name}:"
        @asm.put_label(label)
      end

      # A word the backend built itself, which carries its own text.
      def <<(word)
        @lines << "  #{word.text}"
        @asm << word
      end

      def method_missing(name, *args, **options)
        @lines << "  #{[name, *operands(args), *modifier(options)].join(" ").sub(" ", " ")}"
        @asm.public_send(name, *args, **options)
      end

      def respond_to_missing?(name, private = false) = @asm.respond_to?(name, private)

      # The listing, one instruction to a line and labels in the first
      # column.
      def text = @lines.join("\n")

      private

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
                 when Registers::Register then a.name.downcase
                 when Assembler::Label then a.name.to_s
                 when Array then memory(a, rest)
                 when Symbol then a.to_s
                 else immediate(a)
                 end
        end
        out.join(", ").then { |s| s.empty? ? [] : [s] }
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
