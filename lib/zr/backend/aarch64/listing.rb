# frozen_string_literal: true

require_relative "registers"
require_relative "assembler"
require_relative "codegen"

module Zr
  module Backend
    module Aarch64
      # The instructions a compile chose, as arm64 text.
      #
      # `Codegen` takes its assembler as an argument, so this class is in
      # place of the encoder. It records every call and forwards it, and it
      # returns the encoder's bytes. Thus the output shows the backend's
      # instruction selection, not a decode of the bytes. `aarch64_test.rb`
      # checks the encoding against the `aarch64` gem.
      #
      # A relocation is part of the selection: a call to a local symbol and
      # a call to an import both assemble to the same `bl`. Thus each
      # relocation is written after its instruction.
      class Listing
        # @rbs @asm: Aarch64::Assembler
        # @rbs @lines: Array[[Integer?, String]]
        # @rbs @at: Integer

        Assembler = Aarch64::Assembler #: singleton(Aarch64::Assembler)
        Register = Aarch64::Registers::Register #: singleton(Aarch64::Registers::Register)

        # A number this size or larger is a bit pattern, so it is written
        # in hex. A smaller number is a count or an offset.
        HEX = 256

        # The listing of `function`, as `Codegen` compiles it.
        #: (IR::Function function, ?defined: Array[String] | Set[String]) -> String
        def self.of(function, defined: [])
          compiler = Codegen.new(function, defined: defined, assembler: self)
          compiler.asm.text(compiler.compile.relocs)
        end

        #: () -> void
        def initialize
          @asm = Assembler.new
          @lines = []
          @at = 0
        end

        #: (String name) -> Aarch64::Assembler::Label
        def make_label(name) = @asm.make_label(name)
        #: [T] () { (Integer) -> T } -> T
        def patch_location(&) = @asm.patch_location(&)
        #: () -> String
        def to_binary = @asm.to_binary

        #: (Aarch64::Assembler::Label label) -> self
        def put_label(label)
          @lines << [nil, "#{label.name}:"]
          @asm.put_label(label)
          self
        end

        # The methods that this class defines by hand. Every other encoder
        # mnemonic is defined below. They are defined, not caught by
        # `method_missing`, because no class here can override it. Also, a
        # defined method makes `respond_to?` return true with no more code.
        OWN = %i[make_label put_label patch_location to_binary b].freeze #: Array[Symbol]

        # `b` alone, or `b.cond` when a condition is given. The generated
        # form reads the condition as a shift amount, and a Symbol has
        # no `to_i`.
        #: (Aarch64::Assembler::target label, ?cond: Symbol?) -> self
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
        #: (?Array[Obj::Reloc] relocs) -> String
        def text(relocs = [])
          at = relocs.group_by { |r| r.offset / 4 }
          @lines.map do |index, line|
            notes = index && at[index]
            notes ? "#{line}#{" " * [1, 34 - line.length].max}; #{notes.map { |r| "#{r.kind} #{r.symbol}" }.join(", ")}" : line
          end.join("\n")
        end

        private

        # Every mnemonic that the backend calls assembles to one word. Thus
        # the index in a relocation is also the index of a recorded line.
        #: (String line) -> void
        def record(line)
          @lines << [@at, line]
          @at += 1
        end

        # The operands in arm64 syntax: a register by name, an address in
        # brackets with its index form, an immediate with a `#`. A memory
        # operand that uses the operands after it takes them from `rest`.
        #: (Array[untyped] args) -> Array[String]
        def operands(args)
          rest = args.dup
          out = [] #: Array[String]
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

        #: (Aarch64::Assembler::address address, Array[untyped] rest) -> String
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
        #: (Hash[Symbol, untyped] options) -> Array[String]
        def modifier(options)
          return [] if options.empty?

          amount = options.fetch(:amount, options.values.first).to_i
          return [] if amount.zero?

          ["#{options.fetch(:shift, options.keys.first)} #{immediate(amount)}"]
        end

        #: (untyped value) -> String
        def immediate(value)
          n = Integer(value)
          return "##{n}" if n.abs < HEX

          format("#%s0x%x", n.negative? ? "-" : "", n.abs)
        end
      end
    end
  end
end
