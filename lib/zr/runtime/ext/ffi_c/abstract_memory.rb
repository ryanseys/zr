# frozen_string_literal: true

# AbstractMemory.c: an address, how many bytes past it can be used,
# whether they can be read and written, and every typed read and write
# of them. A memory object of any class contains these four, which the
# other files reach through the hidden ffi_ methods.
module FFI
  class NullPointerError < RuntimeError; end

  class AbstractMemory
    Primitive.zr_undef_allocator(self)

    MEM_RD = 0x01
    MEM_WR = 0x02
    MEM_SWAP = 0x08
    MEM_EMBED = 0x10
    # LONG_MAX, the size of memory no bound is known for.
    UNBOUNDED = 2**63 - 1
    private_constant :MEM_RD, :MEM_WR, :MEM_SWAP, :MEM_EMBED, :UNBOUNDED

    # A memory op for each native kind: how its bytes pack in this order
    # and swapped, how a value converts to native, and how the native
    # value reads back. The kinds without a pack of their own come after.
    NUMBERS = {
      INT8: ["c", "c", :int_value], UINT8: ["C", "C", :uint_value],
      INT16: ["s", "s>", :int_value], UINT16: ["S", "S>", :uint_value],
      INT32: ["l", "l>", :int_value], UINT32: ["L", "L>", :uint_value],
      INT64: ["q", "q>", :ll_value], UINT64: ["Q", "Q>", :ull_value],
      LONG: ["q", "q>", :long_value], ULONG: ["Q", "Q>", :ulong_value],
      FLOAT32: ["f", "f", :dbl_value], FLOAT64: ["d", "d", :dbl_value],
      LONGDOUBLE: ["d", "d", :longdouble_value], POINTER: ["Q", "Q", :pointer_value], BOOL: ["C", "C", :bool_value]
    }.freeze
    private_constant :NUMBERS

    class << self
      # get_memory_op: whether a memory op reads and writes `kind`.
      def op?(kind)
        Primitive.attr! :hidden
        NUMBERS.key?(kind) || kind == :STRING
      end

      def op_size(kind)
        Primitive.attr! :hidden
        kind == :STRING ? 8 : [0].pack(NUMBERS.fetch(kind)[0]).bytesize
      end
    end

    # The methods of each number kind, with rb_define_method's names for them.
    { int8: :INT8, int16: :INT16, int32: :INT32, int64: :INT64, long: :LONG }.each do |name, kind|
      unsigned = :"U#{kind}"
      [[name, kind], [:"u#{name}", unsigned]].each do |spelled, native|
        define_method(:"put_#{spelled}") { |offset, value| ffi_put(native, FFI.long_value(offset), value) }
        define_method(:"get_#{spelled}") { |offset| ffi_get(native, FFI.long_value(offset)) }
        define_method(:"write_#{spelled}") { |value| ffi_put(native, 0, value) }
        define_method(:"read_#{spelled}") { ffi_get(native, 0) }
        define_method(:"put_array_of_#{spelled}") { |offset, ary| ffi_put_array(native, FFI.long_value(offset), ary) }
        define_method(:"get_array_of_#{spelled}") { |offset, length| ffi_get_array(native, offset, length) }
        define_method(:"write_array_of_#{spelled}") { |ary| ffi_put_array(native, 0, ary) }
        define_method(:"read_array_of_#{spelled}") { |length| ffi_get_array(native, 0, length) }
      end
    end

    { char: :int8, short: :int16, int: :int32, long_long: :int64 }.each do |name, old|
      %w[put_ get_ write_ read_ put_array_of_ get_array_of_ write_array_of_ read_array_of_].each do |prefix|
        alias_method :"#{prefix}#{name}", :"#{prefix}#{old}"
        alias_method :"#{prefix}u#{name}", :"#{prefix}u#{old}"
      end
    end

    [[:float32, :float, :FLOAT32], [:float64, :double, :FLOAT64]].each do |name, short, kind|
      define_method(:"put_#{name}") { |offset, value| ffi_put(kind, FFI.long_value(offset), value) }
      define_method(:"get_#{name}") { |offset| ffi_get(kind, FFI.long_value(offset)) }
      alias_method :"put_#{short}", :"put_#{name}"
      alias_method :"get_#{short}", :"get_#{name}"
      define_method(:"write_#{short}") { |value| ffi_put(kind, 0, value) }
      define_method(:"read_#{short}") { ffi_get(kind, 0) }
      define_method(:"put_array_of_#{name}") { |offset, ary| ffi_put_array(kind, FFI.long_value(offset), ary) }
      define_method(:"get_array_of_#{name}") { |offset, length| ffi_get_array(kind, offset, length) }
      define_method(:"write_array_of_#{short}") { |ary| ffi_put_array(kind, 0, ary) }
      define_method(:"read_array_of_#{short}") { |length| ffi_get_array(kind, 0, length) }
      alias_method :"put_array_of_#{short}", :"put_array_of_#{name}"
      alias_method :"get_array_of_#{short}", :"get_array_of_#{name}"
    end

    def put_pointer(offset, value) = ffi_put(:POINTER, FFI.long_value(offset), value)

    def get_pointer(offset) = ffi_get(:POINTER, FFI.long_value(offset))

    def write_pointer(value) = ffi_put(:POINTER, 0, value)

    def read_pointer = ffi_get(:POINTER, 0)

    def put_array_of_pointer(offset, ary) = ffi_put_array(:POINTER, FFI.long_value(offset), ary)

    def get_array_of_pointer(offset, length) = ffi_get_array(:POINTER, offset, length)

    def write_array_of_pointer(ary) = ffi_put_array(:POINTER, 0, ary)

    def read_array_of_pointer(length) = ffi_get_array(:POINTER, 0, length)

    def get_string(offset, length = nil)
      offset = FFI.long_value(offset)
      length = length.nil? ? ffi_size - offset : FFI.long_value(length)
      ffi_check_read
      ffi_check_bounds(offset, length)
      Primitive.zr_ffi_read(ffi_address + offset, Primitive.zr_ffi_strlen(ffi_address + offset, [length, 2**60].min))
    end

    def get_array_of_string(offset, count = nil)
      offset = FFI.long_value(offset)
      count = FFI.int_value(count) unless count.nil?
      ffi_check_read
      if count
        ffi_check_bounds(offset, count * 8)
        Array.new(count) { |i| FFI.string_at(Primitive.zr_ffi_read(ffi_address + offset + i * 8, 8).unpack1("Q")) }
      else
        ffi_check_bounds(offset, 8)
        strings = []
        while offset < ffi_size - 8
          text = FFI.string_at(Primitive.zr_ffi_read(ffi_address + offset, 8).unpack1("Q"))
          break if text.nil?

          strings << text
          offset += 8
        end
        strings
      end
    end

    def read_array_of_string(*args) = get_array_of_string(0, *args)

    def put_string(offset, str)
      str = FFI.typed(str, ::String)
      offset = FFI.long_value(offset)
      ffi_check_write
      ffi_check_bounds(offset, str.bytesize + 1)
      Primitive.zr_ffi_write(ffi_address + offset, str, 0, str.bytesize)
      self
    end

    def get_bytes(offset, length)
      offset = FFI.long_value(offset)
      length = FFI.long_value(length)
      ffi_check_read
      ffi_check_bounds(offset, length)
      Primitive.zr_ffi_read(ffi_address + offset, length)
    end

    def put_bytes(offset, str, *range)
      raise ArgumentError, wrong_arity(range.size + 2, 2..4) if range.size > 2

      str = FFI.typed(str, ::String)
      offset = FFI.long_value(offset)
      index = range.empty? ? 0 : FFI.long_value(range[0])
      raise RangeError, "index cannot be less than zero" if index.negative?

      length = range.size > 1 ? FFI.long_value(range[1]) : str.bytesize - index
      raise RangeError, "index+length is greater than size of string" if index + length > str.bytesize

      ffi_check_write
      ffi_check_bounds(offset, length)
      Primitive.zr_ffi_write(ffi_address + offset, str, index, length)
      self
    end

    def read_bytes(length) = get_bytes(0, length)

    def write_bytes(*args)
      raise ArgumentError, wrong_arity(args.size + 1, 2..4) unless args.size.between?(1, 3)

      put_bytes(0, *args)
    end

    def get(type_name, offset)
      type = FFI.type_lookup(type_name)
      raise ArgumentError, "undefined type '#{type_name}'" unless type && AbstractMemory.op?(type.ffi_kind)

      ffi_get(type.ffi_kind, FFI.long_value(offset))
    end

    def put(type_name, offset, value)
      type = FFI.type_lookup(type_name)
      raise ArgumentError, "unsupported type '#{type_name}'" unless type && AbstractMemory.op?(type.ffi_kind)

      ffi_put(type.ffi_kind, FFI.long_value(offset), value)
      nil
    end

    def clear
      ffi_check_write
      Primitive.zr_ffi_fill(ffi_address, 0, ffi_size)
      self
    end

    def total = ffi_size

    alias size total

    def type_size = @type_size || 0

    def [](index) = self + (FFI.ulong_value(index) * type_size) % 2**64

    def __copy_from__(src, length)
      Primitive.zr_ffi_copy(ffi_address, FFI.typed(src, AbstractMemory).ffi_address, FFI.int_value(length))
      self
    end

    def freeze
      @flags = ffi_flags & ~MEM_WR
      super
    end

    # The four fields of struct AbstractMemory.
    def ffi_address
      Primitive.attr! :hidden
      @address || 0
    end

    def ffi_size
      Primitive.attr! :hidden
      @size || 0
    end

    def ffi_flags
      Primitive.attr! :hidden
      @flags || (MEM_RD | MEM_WR)
    end

    def ffi_memory(address, size, flags, type_size)
      Primitive.attr! :hidden
      @address = address
      @size = size
      @flags = flags
      @type_size = type_size
      self
    end

    def ffi_swapped?
      Primitive.attr! :hidden
      ffi_flags.anybits?(MEM_SWAP)
    end

    # checkRead, checkWrite and checkBounds.
    def ffi_check_read
      Primitive.attr! :hidden
      ffi_access_error("read") if ffi_flags.nobits?(MEM_RD)
    end

    def ffi_check_write
      Primitive.attr! :hidden
      ffi_access_error("write") if ffi_flags.nobits?(MEM_WR)
    end

    def ffi_access_error(access)
      Primitive.attr! :hidden
      raise ffi_address.zero? ? NullPointerError : RuntimeError, "invalid memory #{access} at address=#{FFI.hex(ffi_address)}"
    end

    def ffi_check_bounds(offset, length)
      Primitive.attr! :hidden
      return unless offset.negative? || length.negative? || offset + length > ffi_size

      raise IndexError, "Memory access offset=#{offset} size=#{length} is out of bounds"
    end

    # The memory op for `kind` reading at `offset`.
    def ffi_get(kind, offset)
      Primitive.attr! :hidden
      return ffi_get_strptr(offset) if kind == :STRING

      directive, swapped, = NUMBERS.fetch(kind)
      size = AbstractMemory.op_size(kind)
      ffi_check_read
      ffi_check_bounds(offset, size)
      FFI.from_native_number(kind, Primitive.zr_ffi_read(ffi_address + offset, size).unpack1(ffi_swapped? ? swapped : directive))
    end

    # The memory op for `kind` writing `value` at `offset`.
    def ffi_put(kind, offset, value)
      Primitive.attr! :hidden
      raise ArgumentError, "Cannot set :string fields" if kind == :STRING

      bytes = ffi_pack(kind, value)
      ffi_check_write
      ffi_check_bounds(offset, bytes.bytesize)
      Primitive.zr_ffi_write(ffi_address + offset, bytes, 0, bytes.bytesize)
      self
    end

    def ffi_pack(kind, value)
      Primitive.attr! :hidden
      directive, swapped, to_native = NUMBERS.fetch(kind)
      [FFI.__send__(to_native, value)].pack(ffi_swapped? ? swapped : directive)
    end

    def ffi_get_array(kind, offset, length)
      Primitive.attr! :hidden
      count = FFI.long_value(length)
      offset = FFI.long_value(offset)
      raise ArgumentError, "negative array size (or size too big)" if count.negative?

      size = AbstractMemory.op_size(kind)
      ffi_check_read if count.positive?
      ffi_check_bounds(offset, count * size)
      Array.new(count) { |i| ffi_get(kind, offset + i * size) }
    end

    # Each value converts and goes in in turn, so the ones before a value
    # that does not convert are written.
    def ffi_put_array(kind, offset, ary)
      Primitive.attr! :hidden
      ary = FFI.typed(ary, ::Array)
      size = AbstractMemory.op_size(kind)
      ffi_check_write if ary.size.positive?
      ffi_check_bounds(offset, ary.size * size)
      bytes = "".b
      begin
        ary.each { |value| bytes << ffi_pack(kind, value) }
      ensure
        Primitive.zr_ffi_write(ffi_address + offset, bytes, 0, bytes.bytesize)
      end
      self
    end

    def ffi_get_strptr(offset)
      Primitive.attr! :hidden
      return nil if ffi_address.zero?

      ffi_check_read
      ffi_check_bounds(offset, 8)
      FFI.string_at(Primitive.zr_ffi_read(ffi_address + offset, 8).unpack1("Q"))
    end
  end

  class << self
    # get_pointer_value: the address that a value represents.
    def pointer_value(value)
      Primitive.attr! :hidden
      case value
      when Pointer then value.ffi_address
      when nil then 0
      when Integer then ull_value(value) % 2**64
      else
        raise ArgumentError, "value is not a pointer" unless value.respond_to?(:to_ptr)

        typed(value.to_ptr, AbstractMemory).ffi_address
      end
    end

    def bool_value(value)
      Primitive.attr! :hidden
      value ? 1 : 0
    end

    # A number that a memory op read, as the ruby value it represents.
    def from_native_number(kind, raw)
      Primitive.attr! :hidden
      case kind
      when :POINTER then Pointer.new_instance(raw)
      when :BOOL then raw.anybits?(1)
      when :LONGDOUBLE then longdouble_new(raw)
      else raw
      end
    end

    # rb_str_new2 of a char *: nil for NULL.
    def string_at(address)
      Primitive.attr! :hidden
      address.zero? ? nil : Primitive.zr_ffi_read(address, Primitive.zr_ffi_strlen(address, nil))
    end
  end
end
