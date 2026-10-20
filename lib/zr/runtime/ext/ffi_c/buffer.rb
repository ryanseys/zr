# frozen_string_literal: true

# Derived from the C half of the ffi gem (BSD-3-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# Buffer.c: memory for a call's argument. Eight bytes or fewer are kept
# inside the buffer itself.
module FFI
  class Buffer < AbstractMemory
    Primitive.zr_define_alloc(self)

    MEM_RD = 0x01
    MEM_WR = 0x02
    MEM_SWAP = 0x08
    MEM_EMBED = 0x10
    EMBED_MAXLEN = 8
    private_constant :MEM_RD, :MEM_WR, :MEM_SWAP, :MEM_EMBED, :EMBED_MAXLEN

    class << self
      # buffer_alloc_inout: a new buffer set up by Buffer's own initialize,
      # whatever a subclass makes of it.
      def alloc_inout(*args, &block) = Buffer.instance_method(:initialize).bind_call(allocate, *args, &block)

      alias alloc_out alloc_inout
      alias alloc_in alloc_inout
      alias new_in alloc_in
      alias new_out alloc_out
      alias new_inout alloc_inout
    end

    def initialize(size, *rest)
      raise ArgumentError, wrong_arity(rest.size + 1, 1..3) if rest.size > 2

      type_size = FFI.size_of(size)
      size = type_size * (rest.empty? ? 1 : FFI.long_value(rest[0]))
      if size > EMBED_MAXLEN
        @storage = FFI.storage(size + 7)
        ffi_memory((FFI.address_of(@storage) + 7) & ~7, size, ffi_flags, type_size)
        Primitive.zr_ffi_fill(ffi_address, 0, size) if size.positive? && (rest.size < 2 || rest[1])
      else
        @storage = FFI.storage(EMBED_MAXLEN)
        ffi_memory(FFI.address_of(@storage), size, ffi_flags | MEM_EMBED, type_size)
      end
      return self unless block_given?

      begin
        yield self
      ensure
        @storage = nil if ffi_flags.nobits?(MEM_EMBED)
      end
    end

    def initialize_copy(other)
      other = FFI.typed(other, Buffer)
      @parent = nil
      @storage = FFI.storage(other.ffi_size + 7)
      ffi_memory((FFI.address_of(@storage) + 7) & ~7, other.ffi_size, MEM_RD | MEM_WR, other.type_size)
      Primitive.zr_ffi_copy(ffi_address, other.ffi_address, other.ffi_size)
      self
    end

    def order(*args)
      return ffi_swapped? ? :big : :little if args.empty?
      raise ArgumentError, wrong_arity(args.size, 1) if args.size > 1
      return self unless %i[big network].include?(args[0])

      slice = ffi_slice(0, ffi_size)
      slice.ffi_memory(slice.ffi_address, slice.ffi_size, slice.ffi_flags | MEM_SWAP, slice.type_size)
    end

    def inspect = Primitive.zr_obj_form("#<FFI:Buffer:#{FFI.hex(__id__ << 3)} address=#{FFI.hex(ffi_address)} size=#{ffi_size}>")

    alias length total

    def +(offset)
      offset = FFI.long_value(offset)
      ffi_slice(offset, ffi_size - offset)
    end

    def slice(offset, length) = ffi_slice(FFI.long_value(offset), FFI.long_value(length))

    # slice: a Buffer over part of this, which keeps this alive.
    def ffi_slice(offset, length)
      Primitive.attr! :hidden
      ffi_check_bounds(offset, length)
      slice = Primitive.zr_class_build(Buffer).ffi_memory(ffi_address + offset, length, ffi_flags, type_size)
      slice.__send__(:ffi_parent=, self)
      slice
    end

    private

    def ffi_parent=(parent)
      Primitive.attr! :hidden
      @parent = parent
    end
  end
end
