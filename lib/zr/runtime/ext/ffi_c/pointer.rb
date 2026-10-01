# frozen_string_literal: true

# Pointer.c and MemoryPointer.c: memory at an address, and memory that
# ffi_c allocates. ffi_c frees it when nothing refers to the pointer,
# unless told to keep it.
module FFI
  class Pointer < AbstractMemory
    Primitive.zr_define_alloc(self)

    MEM_RD = 0x01
    MEM_WR = 0x02
    MEM_SWAP = 0x08
    UNBOUNDED = 2**63 - 1
    private_constant :MEM_RD, :MEM_WR, :MEM_SWAP, :UNBOUNDED

    class << self
      # rbffi_Pointer_NewInstance: NULL is the one NULL pointer.
      def new_instance(address)
        Primitive.attr! :hidden
        return NULL if address.zero?

        Primitive.zr_class_build(Pointer).ffi_memory(address, UNBOUNDED, MEM_RD | MEM_WR, 1)
      end

      # Allocated storage a pointer was told not to release, which lives
      # as long as the process.
      def kept
        Primitive.attr! :hidden
        @kept ||= {}.compare_by_identity
      end
    end

    def initialize(*args)
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

      type_size = args.size == 2 ? FFI.size_of(args[0]) : 1
      address = args.last
      case address
      when Integer
        ffi_memory(FFI.ull_value(address) % 2**64, UNBOUNDED, address.zero? ? 0 : ffi_flags, type_size)
      when Pointer
        @parent = address
        ffi_memory(address.ffi_address, address.ffi_size, address.ffi_flags, type_size)
      else
        raise TypeError, "wrong argument type, expected Integer or FFI::Pointer"
      end
    end

    def initialize_copy(other)
      other = FFI.typed(other, Pointer)
      raise RuntimeError, "cannot duplicate unbounded memory area" if other.ffi_size == UNBOUNDED

      @parent = nil
      @flags = MEM_RD | MEM_WR
      ffi_allocate(other.ffi_size, other.type_size)
      Primitive.zr_ffi_copy(ffi_address, other.ffi_address, other.ffi_size)
      self
    end

    def inspect
      name = Primitive.zr_class_path(Primitive.zr_real_class(self))
      text = ffi_size == UNBOUNDED ? "#<#{name} address=#{FFI.hex(ffi_address)}>" : "#<#{name} address=#{FFI.hex(ffi_address)} size=#{ffi_size}>"
      Primitive.zr_obj_form(text)
    end

    alias to_s inspect

    def +(offset)
      offset = FFI.long_value(offset)
      ffi_slice(offset, ffi_size == UNBOUNDED ? UNBOUNDED : ffi_size - offset)
    end

    def slice(offset, length) = ffi_slice(FFI.long_value(offset), FFI.long_value(length))

    def null? = ffi_address.zero?

    def ==(other)
      return ffi_address.zero? if other.nil?

      other.is_a?(Pointer) && ffi_address == other.ffi_address
    end

    def address = ffi_address

    alias to_i address

    def order(*args)
      return ffi_swapped? ? :big : :little if args.empty?
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1)" if args.size > 1

      swap = case args[0]
             when :little then false
             when :big, :network then true
             when Symbol then raise ArgumentError, "unknown byte order"
             else false
             end
      return self unless swap

      slice = ffi_slice(0, ffi_size)
      slice.ffi_memory(slice.ffi_address, slice.ffi_size, slice.ffi_flags | MEM_SWAP, slice.type_size)
    end

    def autorelease=(autorelease)
      Primitive.zr_frozen_error(self) if frozen?

      @autorelease = autorelease ? true : false
      Pointer.kept.delete(@storage) if @autorelease
      Pointer.kept[@storage] = true if !@autorelease && @storage
      autorelease
    end

    def autorelease? = @autorelease || false

    def type_size = @type_size || 0

    def free
      Primitive.zr_frozen_error(self) if frozen?

      if @allocated
        ffi_release
      else
        Warning.warn("#{Primitive.zr_warn_position}warning: calling free on non allocated pointer #{inspect} from #{caller.first}\n") unless $VERBOSE.nil?
      end
      self
    end

    # memptr_malloc: `size` fresh bytes this pointer owns, in bytes whose
    # address is a multiple of eight.
    def ffi_allocate(size, type_size)
      Primitive.attr! :hidden
      ffi_release
      @storage = FFI.storage(size + 7)
      @allocated = true
      @autorelease = true
      ffi_memory((FFI.address_of(@storage) + 7) & ~7, size, ffi_flags, type_size)
    end

    def ffi_release
      Primitive.attr! :hidden
      Pointer.kept.delete(@storage) if @storage
      @storage = nil
      @allocated = false
    end

    # slice: a Pointer over part of this, which keeps this alive.
    def ffi_slice(offset, length)
      Primitive.attr! :hidden
      ffi_check_bounds(offset, length == UNBOUNDED ? 1 : length)
      slice = Primitive.zr_class_build(Pointer).ffi_memory(ffi_address + offset, length, ffi_flags, type_size)
      slice.__send__(:ffi_parent=, self)
      slice
    end

    private

    def ffi_parent=(parent)
      Primitive.attr! :hidden
      @parent = parent
    end
  end

  class Pointer
    NULL = new(0)
  end

  class MemoryPointer < Pointer
    Primitive.zr_define_alloc(self)

    # rbffi_MemoryPointer_NewInstance.
    def self.new_instance(size, count, clear)
      Primitive.attr! :hidden
      pointer = Primitive.zr_class_build(MemoryPointer).ffi_allocate(size * count, size)
      Primitive.zr_ffi_fill(pointer.ffi_address, 0, pointer.ffi_size) if clear && pointer.ffi_size.positive?
      pointer
    end

    def initialize(size, *rest)
      raise ArgumentError, "wrong number of arguments (given #{rest.size + 1}, expected 1..3)" if rest.size > 2

      size = FFI.size_of(size)
      count = rest.empty? ? 1 : FFI.long_value(rest[0])
      clear = rest[1]
      ffi_allocate(size * count, size)
      Primitive.zr_ffi_fill(ffi_address, 0, ffi_size) if (clear.nil? || clear) && ffi_size.positive?
      return self unless block_given?

      begin
        yield self
      ensure
        ffi_release
      end
    end

    def self.from_string(text)
      text = Primitive.zr_str_operand(text)
      pointer = new(1, text.bytesize + 1, false)
      pointer.put_string(0, text)
      pointer
    end
  end
end
