# frozen_string_literal: true

require_relative "model"
require_relative "../bytes"
require_relative "relocs/aarch64"
require_relative "relocs/x86_64"
require_relative "../paths"

module Zr
  module Obj
    # Loads an `Obj::Unit` into this process. It writes code into a
    # `MAP_JIT` mapping under `pthread_jit_write_protect_np`, and data into
    # a writable mapping within reach of the code. It applies relocations
    # and resolves imports with `dlsym`. Returns the address of every symbol.
    #
    # A `bl` reaches 128 MB, and libSystem is farther away. Thus each
    # imported function gets a stub in the code region that jumps through
    # an absolute address.
    #
    # Its `syscalls` make the system calls: `JIT::Fiddle` under CRuby (the
    # tests), or `JIT::Runtime`, the runtime's own, in a zr program that
    # evals (`Eval`). Each calls the same libSystem functions.
    class JIT
      # @rbs @syscalls: _Syscalls
      # @rbs @stub: String
      # @rbs @relocs: untyped

      MAP_ANON_PRIVATE = 0x1002
      MAP_FIXED = 0x10
      MAP_JIT = 0x800
      PAGE = 16_384
      # Each architecture's import stub, which the absolute address
      # follows: `ldr x16, [pc, #8]; br x16` and `jmp [rip + 0]`.
      STUBS = { aarch64: [0x58000050, 0xD61F0200].pack("L<2"), x86_64: "\xFF\x25\0\0\0\0".b }.freeze #: Hash[Symbol, String]
      # The relocations of each architecture's code.
      RELOCS = { aarch64: Relocs::Aarch64, x86_64: Relocs::X86_64 }.freeze #: Hash[Symbol, untyped]

      attr_reader :symbols #: Hash[String, Integer]

      # Not `Kernel#load`: this loads a unit, with `syscalls` for its system
      # calls, and `arch` its machine code's architecture.
      #: (Unit unit, syscalls: _Syscalls, arch: Symbol) -> Hash[String, Integer]
      def self.load(unit, syscalls:, arch:) = new(syscalls, arch).place(unit)

      #: (_Syscalls syscalls, Symbol arch) -> void
      def initialize(syscalls, arch)
        @syscalls = syscalls
        @stub = STUBS.fetch(arch)
        @relocs = RELOCS.fetch(arch)
        @symbols = {}
      end

      #: (Unit unit) -> Hash[String, Integer]
      def place(unit)
        code = layout(unit.functions, 16)
        imports = unit.imports
        stubs = imports.each_with_index.to_h { |name, i| [name, code[:size] + (i * 16)] }
        code_size = [Bytes.align(code[:size] + (imports.size * 16), PAGE), PAGE].max
        data = layout(unit.data, 16)
        got = imports.each_with_index.to_h { |name, i| [name, data[:size] + (i * 8)] }
        data_size = [Bytes.align(data[:size] + (imports.size * 8), PAGE), PAGE].max

        # One reservation contains both parts, so the data is within adrp
        # reach of the code. With only a hint, the kernel can put the data
        # anywhere, and in a busy process it does. The data is mapped at its
        # address in the reservation. A MAP_JIT mapping cannot use
        # MAP_FIXED (EINVAL), so this releases the code part first and maps
        # it by hint; the kernel then uses the free hole. Syscalls with no
        # reservation maps by hint only. This checks the reach in both cases.
        if (base = @syscalls.reserve(code_size + data_size))
          data_base = map(data_size, exec: false, at: base + code_size)
          @syscalls.release(base, code_size)
          code_base = map(code_size, exec: true, near: base)
        else
          code_base = map(code_size, exec: true)
          data_base = map(data_size, exec: false, near: code_base + code_size)
        end
        reach = (data_base - code_base).abs
        raise "the data mapping is #{reach} bytes from the code, past adrp's reach" if reach >= (1 << 32)

        code[:at].each { |f, off| @symbols[f.name] = code_base + off }
        data[:at].each { |d, off| @symbols[d.name] = data_base + off }
        addresses = imports.to_h { |name| [name, @syscalls.symbol(name) || raise("this process has no symbol #{name}")] }
        stubs.each { |name, off| @symbols[name] = code_base + off }

        text = +"".b
        code[:at].each do |f, off|
          Bytes.pad(text, off)
          text << patched(f, code_base + off, addresses, data_base, got)
        end
        imports.each do |name|
          Bytes.pad(text, stubs[name])
          text << @stub << [addresses[name]].pack("Q<")
        end
        bytes = +"".b
        data[:at].each do |d, off|
          Bytes.pad(bytes, off)
          bytes << (d.section == :bss ? ("\0" * d.size).b : patched(d, data_base + off, addresses, data_base, got))
        end
        imports.each do |name|
          Bytes.pad(bytes, got[name])
          bytes << [addresses[name]].pack("Q<")
        end

        @syscalls.write_data(data_base, bytes)
        @syscalls.write_code(code_base, text)
        @symbols
      end

      private

      # Places `items` one after another. Each item uses the larger of its
      # own alignment and `least`. Returns the offset of each item and the
      # total size.
      #: [T < ::Zr::Obj::_Placeable] (Array[T] items, Integer least) -> { at: Array[[T, Integer]], size: Integer }
      def layout(items, least)
        # Steep cannot name the method's `T` in a local's type.
        at = [] #: Array[untyped]
        size = 0
        items.each do |item|
          size = Bytes.align(size, [item.align, least].max)
          at << [item, size]
          size += item.size
        end
        { at: at, size: size }
      end

      #: (Integer size, exec: bool, ?at: Integer?, ?near: Integer) -> Integer
      def map(size, exec:, at: nil, near: 0)
        @syscalls.map(size, exec: exec, at: at, near: near) or raise "mmap of #{size} bytes failed"
      end

      # Returns the bytes of `item` at `base`, with all relocations applied.
      # `abs64` is the same in all formats; `Relocs::Aarch64` and
      # `Relocs::X86_64` hold the instruction relocations.
      # @rbs item: Code | Datum
      # @rbs base: Integer
      # @rbs addresses: Hash[String, Integer]
      # @rbs data_base: Integer
      # @rbs got: Hash[String, Integer]
      # @rbs return: String
      def patched(item, base, addresses, data_base, got)
        bytes = item.bytes.b
        item.relocs.each do |r|
          target = target_of(r, addresses, data_base, got) + r.addend.to_i
          if r.kind == :abs64
            bytes[r.offset, 8] = [target].pack("Q<")
          elsif @relocs.handles?(r.kind)
            @relocs.patch(bytes, r, target, base + r.offset)
          else
            raise ArgumentError, "no way to apply a #{r.kind} relocation"
          end
        end
        bytes
      end

      # The address that `r` refers to. A symbol that this unit defines uses
      # its own address, unless it is also an import. An import uses its GOT
      # slot for a GOT relocation, its stub for a call, and its address for
      # all other relocations.
      #: (Reloc r, Hash[String, Integer] addresses, Integer data_base, Hash[String, Integer] got) -> Integer
      def target_of(r, addresses, data_base, got)
        if @symbols.key?(r.symbol) && !addresses.key?(r.symbol) then @symbols.fetch(r.symbol)
        elsif %i[got_page21 got_pageoff12 gotpcrel].include?(r.kind) then data_base + got.fetch(r.symbol)
        elsif r.kind == :branch26 || r.kind == :plt32 then @symbols.fetch(r.symbol)
        else addresses.fetch(r.symbol)
        end
      end
    end
  end
end
