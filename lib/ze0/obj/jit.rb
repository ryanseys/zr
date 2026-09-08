# frozen_string_literal: true

require "fiddle"
require_relative "model"

module Ze0
  module Obj
    # Loads an `Obj::Unit` into this process: code into a `MAP_JIT` mapping
    # written under `pthread_jit_write_protect_np`, data into a writable
    # mapping placed within reach of the code, relocations applied here,
    # imports resolved with `dlsym`. Answers the address of every symbol.
    #
    # A `bl` reaches 128 MB, and libSystem is not that close, so each
    # imported function gets a stub in the code region that jumps through
    # an absolute address. Under CRuby this is Fiddle; the runtime's own
    # loader is the same steps over the same libSystem calls.
    class JIT
      PROT_READ = 1
      PROT_WRITE = 2
      PROT_EXEC = 4
      MAP_PRIVATE = 2
      MAP_ANON = 0x1000
      MAP_JIT = 0x800
      PAGE = 16_384
      # `ldr x16, [pc, #8]; br x16; .quad address`
      STUB = [0x58000050, 0xD61F0200].pack("L<2")

      attr_reader :symbols

      def self.load(unit)
        new.place(unit)
      end

      def initialize
        @lib = Fiddle::Handle::DEFAULT
        @mmap = Fiddle::Function.new(@lib["mmap"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_LONG], Fiddle::TYPE_VOIDP)
        @protect = Fiddle::Function.new(@lib["pthread_jit_write_protect_np"], [Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
        @invalidate = Fiddle::Function.new(@lib["sys_icache_invalidate"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T], Fiddle::TYPE_VOID)
        @symbols = {}
      end

      def place(unit)
        code = layout(unit.functions, 16)
        imports = unit.imports
        stubs = imports.each_with_index.to_h { |name, i| [name, code[:size] + (i * 16)] }
        code_size = align(code[:size] + (imports.size * 16), PAGE)
        data = layout(unit.data, 16)
        got = imports.each_with_index.to_h { |name, i| [name, data[:size] + (i * 8)] }
        data_size = align(data[:size] + (imports.size * 8), PAGE)

        code_base = map(code_size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_JIT, 0)
        data_base = map(data_size, PROT_READ | PROT_WRITE, 0, code_base + code_size)
        reach = (data_base - code_base).abs
        raise "the data mapping is #{reach} bytes from the code, past adrp's reach" if reach >= (1 << 32)

        code[:at].each { |f, off| @symbols[f.name] = code_base + off }
        data[:at].each { |d, off| @symbols[d.name] = data_base + off }
        addresses = imports.to_h { |name| [name, @lib[name]] }
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

        Fiddle::Pointer.new(data_base)[0, bytes.bytesize] = bytes
        @protect.call(0)
        Fiddle::Pointer.new(code_base)[0, text.bytesize] = text
        @protect.call(1)
        @invalidate.call(code_base, text.bytesize)
        @symbols
      end

      private

      def layout(items, item_align)
        at = []
        size = 0
        items.each do |item|
          size = align(size, [item.align, item_align].max)
          at << [item, size]
          size += item.size
        end
        { at: at, size: size }
      end

      def align(n, a)
        (n + a - 1) & ~(a - 1)
      end

      def map(size, prot, flags, hint)
        p = @mmap.call(hint, size, prot, MAP_PRIVATE | MAP_ANON | flags, -1, 0).to_i
        raise "mmap failed" if p == -1 || p.zero?

        p
      end

      # `item`'s bytes with every relocation applied, for the item at `base`.
      def patched(item, base, addresses, data_base, got)
        bytes = item.bytes.b.dup
        item.relocs.each do |r|
          place = base + r.offset
          target =
            if @symbols.key?(r.symbol) && !addresses.key?(r.symbol) then @symbols[r.symbol]
            elsif %i[got_page21 got_pageoff12].include?(r.kind) then data_base + got.fetch(r.symbol)
            elsif r.kind == :branch26 then @symbols.fetch(r.symbol)
            else addresses.fetch(r.symbol)
            end
          target += r.addend
          case r.kind
          when :abs64
            bytes[r.offset, 8] = [target].pack("Q<")
          when :branch26
            patch(bytes, r.offset) { |w| (w & ~0x3FFFFFF) | (((target - place) >> 2) & 0x3FFFFFF) }
          when :page21, :got_page21
            delta = ((target & ~0xFFF) - (place & ~0xFFF)) >> 12
            patch(bytes, r.offset) { |w| (w & ~0x60FFFFE0) | ((delta & 3) << 29) | (((delta >> 2) & 0x7FFFF) << 5) }
          when :pageoff12
            patch(bytes, r.offset) { |w| (w & ~(0xFFF << 10)) | ((target & 0xFFF) << 10) }
          when :got_pageoff12
            patch(bytes, r.offset) { |w| (w & ~(0xFFF << 10)) | (((target & 0xFFF) >> 3) << 10) }
          else raise ArgumentError, "no way to apply a #{r.kind} relocation"
          end
        end
        bytes
      end

      def patch(bytes, offset)
        word = bytes[offset, 4].unpack1("L<")
        bytes[offset, 4] = [yield(word)].pack("L<")
      end
    end
  end
end
