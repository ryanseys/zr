# frozen_string_literal: true

require_relative "model"
require_relative "patch"
require_relative "../bytes"
require_relative "relocs/aarch64"
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
    # A `host` makes the system calls: `JIT::Fiddle` under CRuby, or the
    # runtime's own host, which calls the same libSystem functions.
    class JIT
      MAP_ANON_PRIVATE = 0x1002
      MAP_FIXED = 0x10
      MAP_JIT = 0x800
      PAGE = 16_384
      # `ldr x16, [pc, #8]; br x16; .quad address`
      STUB = [0x58000050, 0xD61F0200].pack("L<2")

      attr_reader :symbols

      def self.load(unit, host: self.host)
        new(host).place(unit)
      end

      # The host for system calls: the runtime's host in a zr program, or
      # Fiddle under CRuby (where no runtime is linked).
      def self.host
        if Host.compiled?
          require_relative "../runtime/lib/zr/obj/jit/runtime"
          Runtime.new
        else
          require_relative "jit/fiddle"
          Fiddle.new
        end
      end

      def initialize(host)
        @host = host
        @symbols = {}
      end

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
        # it by hint; the kernel then uses the free hole. A host with no
        # reservation maps by hint only. This checks the reach in both cases.
        if (base = @host.reserve(code_size + data_size))
          data_base = map(data_size, exec: false, at: base + code_size)
          @host.release(base, code_size)
          code_base = map(code_size, exec: true, near: base)
        else
          code_base = map(code_size, exec: true)
          data_base = map(data_size, exec: false, near: code_base + code_size)
        end
        reach = (data_base - code_base).abs
        raise "the data mapping is #{reach} bytes from the code, past adrp's reach" if reach >= (1 << 32)

        code[:at].each { |f, off| @symbols[f.name] = code_base + off }
        data[:at].each { |d, off| @symbols[d.name] = data_base + off }
        addresses = imports.to_h { |name| [name, @host.symbol(name)] }
        stubs.each { |name, off| @symbols[name] = code_base + off }

        text = +"".b
        code[:at].each do |f, off|
          text << ("\0" * (off - text.bytesize)).b
          text << patched(f, code_base + off, addresses, data_base, got)
        end
        imports.each do |name|
          text << ("\0" * (stubs[name] - text.bytesize)).b
          text << STUB << [addresses[name]].pack("Q<")
        end
        bytes = +"".b
        data[:at].each do |d, off|
          bytes << ("\0" * (off - bytes.bytesize)).b
          bytes << (d.section == :bss ? ("\0" * d.size).b : patched(d, data_base + off, addresses, data_base, got))
        end
        imports.each do |name|
          bytes << ("\0" * (got[name] - bytes.bytesize)).b
          bytes << [addresses[name]].pack("Q<")
        end

        @host.write_data(data_base, bytes)
        @host.write_code(code_base, text)
        @symbols
      end

      private

      def layout(items, item_align) = Patch.layout(items, item_align)

      def map(size, exec:, at: nil, near: 0)
        @host.map(size, exec: exec, at: at, near: near) or raise "mmap of #{size} bytes failed"
      end

      # Returns the bytes of `item` at `base`, with all relocations applied.
      # A symbol that this unit defines uses its own address, unless it is
      # also an import. An import uses its GOT slot for a GOT relocation,
      # its stub for a call, and its address for all other relocations.
      def patched(item, base, addresses, data_base, got)
        Patch.apply(item, base, Relocs::Aarch64) do |r|
          if @symbols.key?(r.symbol) && !addresses.key?(r.symbol) then @symbols[r.symbol]
          elsif %i[got_page21 got_pageoff12].include?(r.kind) then data_base + got.fetch(r.symbol)
          elsif r.kind == :branch26 then @symbols.fetch(r.symbol)
          else addresses.fetch(r.symbol)
          end
        end
      end
    end
  end
end
