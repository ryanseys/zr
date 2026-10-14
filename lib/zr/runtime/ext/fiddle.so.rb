# frozen_string_literal: true

Object.send(:native_module, :Fiddle)

# `fiddle.so`: the C part of the fiddle gem (1.1.8), in ruby over the ffi
# gem. Each section represents the C file in its heading and follows the
# order in which Init_fiddle defines things: fiddle.c, function.c,
# closure.c, handle.c, pointer.c, pinned.c and memory_view.c.
# conversions.c is in Fiddle::Native, with the libc calls and the rules
# that CRuby's NUM2INT, NUM2DBL and StringValueCStr follow, so that a bad
# argument raises the same error as the C extension.
#
# Addresses go between the classes as Integers, and FFI::Pointer reads
# and writes the memory at those addresses. Three things that the C
# extension does are not possible over ffi. This file comes as close as it can:
#
# * A String has no address that a Ruby program can see. Fiddle::Pointer[string]
#   copies the string into native memory, and copies changes back and forth
#   when fiddle reads or writes through the pointer or passes it to a C
#   function (see Native::Mirror).
# * A Ruby object has no address either. Fiddle.dlwrap encodes nil, true,
#   false, small Integers and Floats as CRuby does, and gives any other
#   object an address from a table, which Fiddle.dlunwrap reads back.
# * The C structs behind Pointer, Handle, Closure, Pinned and MemoryView
#   are in one hidden instance variable, @__fiddle__, which inspect omits.
require "ffi"

module Fiddle
  # The libc calls, the type table, and CRuby's conversions of arguments.
  # It is private: the C extension defines nothing of the kind.
  module Native
    extend FFI::Library
    ffi_lib FFI::Library::LIBC

    attach_function :calloc, [:size_t, :size_t], :pointer
    attach_function :realloc, [:pointer, :size_t], :pointer
    attach_function :free, [:pointer], :void
    attach_function :dlopen, [:string, :int], :pointer
    attach_function :dlclose, [:pointer], :int
    attach_function :dlsym, [:pointer, :string], :pointer
    attach_function :dlerror, [], :string
    attach_function :fdopen, [:int, :string], :pointer
    attach_function :fcntl, [:int, :int], :int

    ADDRESS_BITS = FFI::Type::Builtin::POINTER.size * 8
    ADDRESS_MASK = (1 << ADDRESS_BITS) - 1

    LINUX = RUBY_PLATFORM.include?("linux")
    WINDOWS = RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)

    # C's plain char is unsigned on ARM and POWER Linux, and signed elsewhere.
    CHAR_SIGNED = !(RUBY_PLATFORM.match?(/\A(aarch64|arm|powerpc|ppc|s390)/) && LINUX)

    # FFI_DEFAULT_ABI, and the ABIs ffi_prep_cif accepts on this machine.
    DEFAULT_ABI, VALID_ABIS =
      if RUBY_PLATFORM.match?(/\A(x86_64|amd64)/) && !WINDOWS
        [2, 2..4]
      else
        [1, 1..2]
      end

    # RTLD_DEFAULT and RTLD_NEXT, the pseudo-handles of <dlfcn.h>.
    RTLD_DEFAULT = LINUX ? 0 : -2
    RTLD_NEXT = -1

    # The VALUEs of CRuby's special constants, on a 64-bit build.
    QFALSE = 0
    QNIL = 4
    QTRUE = 20
    QUNDEF = 36

    # libffi's status codes, which fiddle's error messages include.
    FFI_BAD_ABI = 2
    FFI_BAD_ARGTYPE = 3

    module_function

    # -- addresses ----------------------------------------------------------

    # An address as C's unsigned pointer.
    def unsigned(address) = address & ADDRESS_MASK

    # An address as PTR2NUM returns it: a signed long.
    def signed(address)
      address &= ADDRESS_MASK
      address[ADDRESS_BITS - 1] == 1 ? address - (1 << ADDRESS_BITS) : address
    end

    # Truncates an Integer to a C integer of `bits` bits.
    def wrap(value, bits, signed)
      value &= (1 << bits) - 1
      signed && value[bits - 1] == 1 ? value - (1 << bits) : value
    end

    def memory(address) = FFI::Pointer.new(unsigned(address))

    def read_bytes(address, length)
      return "".b if length.zero?
      return ("\0" * length).b if unsigned(address).zero?

      memory(address).get_bytes(0, length).force_encoding(Encoding::BINARY)
    end

    def write_bytes(address, bytes)
      memory(address).put_bytes(0, bytes, 0, bytes.bytesize) unless bytes.empty?
    end

    # rb_str_new_cstr: the bytes up to the first NUL.
    def read_cstring(address)
      raise ArgumentError, "NULL pointer given" if unsigned(address).zero?

      memory(address).get_string(0).force_encoding(Encoding::BINARY)
    end

    # Zeroed memory, or NoMemoryError. ruby_xmalloc (`checked`) refuses a
    # size with the sign bit set before it tries; ruby_xcalloc just fails.
    def allocate(size, checked:)
      size = unsigned(size)
      raise NoMemoryError, "too large allocation size" if checked && size[ADDRESS_BITS - 1] == 1

      address = calloc(1, size).address
      raise NoMemoryError, "failed to allocate memory" if address.zero? && size.positive?

      address
    end

    def reallocate(address, size)
      size = unsigned(size)
      raise NoMemoryError, "too large allocation size" if size[ADDRESS_BITS - 1] == 1

      result = realloc(memory(address), size).address
      raise NoMemoryError, "failed to allocate memory" if result.zero? && size.positive?

      result
    end

    # Calls the C function at `function`, a free function, with `address`.
    def call_free_function(function, address)
      if unsigned(function) == RUBY_FREE_ADDRESS
        free(memory(address))
      else
        function(unsigned(function), [:pointer], :void, false).call(memory(address))
      end
    end

    # -- ffi functions ------------------------------------------------------

    @functions = {}
    @variadics = {}

    # The FFI::Function that calls the C function at `address` with the
    # given ffi types. One exists for each address and signature.
    def function(address, params, result, blocking)
      @functions[[address, params, result, blocking]] ||=
        FFI::Function.new(result, params, FFI::Pointer.new(address), blocking: blocking)
    end

    # The FFI::VariadicInvoker that calls the variadic C function at
    # `address`, whose fixed arguments have the given ffi types.
    def variadic(address, fixed, result, blocking)
      @variadics[[address, fixed, result, blocking]] ||=
        FFI::VariadicInvoker.new(FFI::Pointer.new(address),
                                 [*fixed.map { |type| FFI.find_type(type) }, FFI::Type::Builtin::VARARGS],
                                 FFI.find_type(result),
                                 { convention: :default, type_map: nil, enums: nil, blocking: blocking })
    end

    # -- per-object state ---------------------------------------------------

    # The C struct behind a fiddle object, in a slot no program sees. An
    # object that skipped initialize gets a zeroed struct, as allocate
    # gives in C.
    def state(object, type)
      Primitive.zr_hidden_get(object, :__fiddle__) ||
        (object.frozen? ? type.new : Primitive.zr_hidden_set(object, :__fiddle__, type.new))
    end

    def reset_state(object, type) = Primitive.zr_hidden_set(object, :__fiddle__, type.new)

    # -- conversions.c ------------------------------------------------------

    TYPE_NAMES = {
      void: 0, voidp: 1, char: 2, short: 3, int: 4, long: 5, long_long: 6,
      int8_t: 2, int16_t: nil, int32_t: nil, int64_t: nil,
      float: 7, double: 8, variadic: 9, const_string: 10,
      size_t: nil, ssize_t: nil, ptrdiff_t: nil, intptr_t: nil, uintptr_t: nil, bool: 11
    }

    # rb_fiddle_type_ensure: a type as its Integer, from a Symbol or String
    # that is its name or from any object with to_int.
    def type_ensure(type)
      original = type
      unless type.is_a?(Symbol)
        string = check_string_type(type)
        type = string.to_sym unless string.nil?
      end
      if type.is_a?(Symbol)
        value = TYPE_NAMES[type]
        return value unless value.nil?

        type = original
      end
      to_int(type)
    end

    SIGNED_FFI_TYPES = { 2 => :int8, 3 => :int16, 4 => :int32, 5 => :long, 6 => :int64 }
    UNSIGNED_FFI_TYPES = { 2 => :uint8, 3 => :uint16, 4 => :uint32, 5 => :ulong, 6 => :uint64 }
    OTHER_FFI_TYPES = { 0 => :void, 1 => :pointer, 7 => :float, 8 => :double, 10 => :pointer, 11 => :bool }

    # rb_fiddle_int_to_ffi_type: the ffi type of a fiddle type. A negative
    # type is the unsigned form of its absolute value.
    def ffi_type(type)
      signed = type >= 0
      type = type.abs
      (signed ? SIGNED_FFI_TYPES : UNSIGNED_FFI_TYPES)[type] || OTHER_FFI_TYPES[type] ||
        raise(RuntimeError, "unknown type #{type}")
    end

    # rb_fiddle_value_to_generic: an argument in the form ffi passes for
    # `type`. `keep` contains native memory that must outlive the call.
    def to_native(type, value, keep)
      case type
      when 0 then 0
      when 1 then FFI::Pointer.new(num2ulong(Kernel.Integer(value)))
      when 2
        if value.instance_of?(String) && value.bytesize == 1
          wrap(value.getbyte(0), 8, true)
        else
          wrap(num2int(value), 8, true)
        end
      when -2 then wrap(num2uint(value), 8, false)
      when 3 then wrap(num2int(value), 16, true)
      when -3 then wrap(num2uint(value), 16, false)
      when 4 then num2int(value)
      when -4 then wrap(num2uint(value), 32, false)
      when 5 then num2long(value)
      when -5 then num2ulong(value)
      when 6 then num2ll(value)
      when -6 then num2ull(value)
      when 7, 8 then num2dbl(value)
      when 10
        return FFI::Pointer::NULL if value.nil?

        string = FFI::MemoryPointer.from_string(string_value_cstr(value))
        keep << string
        string
      when 11 then value ? true : false
      else raise RuntimeError, "unknown type #{type}"
      end
    end

    # rb_fiddle_generic_to_value: a C result, which ffi read as `type`, as
    # the Ruby value that fiddle returns.
    def from_native(type, value)
      case type
      when 0 then nil
      when 1 then Fiddle.const_get(:Pointer).__send__(:[], signed(value.address))
      when 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 11 then value
      when 7, 8 then value.to_f
      when 10 then value.null? ? nil : read_cstring(value.address)
      else raise RuntimeError, "unknown type #{type}"
      end
    end

    # The ffi type a variadic argument of this ffi type passes as. libffi
    # refuses float and any integer narrower than int.
    def variadic_ffi_type(type)
      raise RuntimeError, "error creating CIF #{FFI_BAD_ARGTYPE}" if type == :float || FFI.find_type(type).size < FFI.find_type(:int).size

      type
    end

    def check_abi(abi, message)
      raise RuntimeError, "#{message} #{FFI_BAD_ABI}" unless VALID_ABIS.cover?(abi)
    end

    # -- CRuby's own conversions (numeric.c, bignum.c, string.c) -----------

    LONG_MIN = -(1 << 63)
    LONG_MAX = (1 << 63) - 1
    ULONG_LIMIT = 1 << 64
    INT_MIN = -(1 << 31)
    INT_MAX = (1 << 31) - 1
    UINT_MAX = (1 << 32) - 1

    # rb_to_int
    def to_int(value)
      return value if value.is_a?(Integer)
      raise TypeError, no_implicit_conversion(value, "Integer") unless value.respond_to?(:to_int, true)

      result = value.__send__(:to_int)
      return result if result.is_a?(Integer)

      raise TypeError, cant_convert_gives(value, "Integer", :to_int, result)
    end

    # rb_check_string_type
    def check_string_type(value)
      return value if value.is_a?(String)
      return nil unless value.respond_to?(:to_str, true)

      result = value.__send__(:to_str)
      return result if result.nil? || result.is_a?(String)

      raise TypeError, cant_convert_gives(value, "String", :to_str, result)
    end

    # StringValue
    def string_value(value)
      string = check_string_type(value)
      raise TypeError, no_implicit_conversion(value, "String") if string.nil?

      string
    end

    # StringValueCStr
    def string_value_cstr(value)
      string = string_value(value)
      raise ArgumentError, "string contains null byte" if string.b.include?("\0")

      string
    end

    # Check_Type(value, T_ARRAY)
    def check_array(value)
      raise TypeError, "wrong argument type #{conversion_name(value)} (expected Array)" unless value.is_a?(Array)

      value
    end

    def float_out_of_range(value, type)
      raise RangeError, "float #{format('%-.10g', value)} out of range of #{type}"
    end

    # NUM2LONG
    def num2long(value)
      loop do
        case value
        when nil then raise TypeError, no_implicit_conversion(value, "Integer")
        when Integer
          raise RangeError, "bignum too big to convert into 'long'" unless value.between?(LONG_MIN, LONG_MAX)

          return value
        when Float
          return value.to_i if value < 1 << 63 && value >= LONG_MIN

          float_out_of_range(value, "integer")
        else value = to_int(value)
        end
      end
    end

    # NUM2INT
    def num2int(value)
      value = num2long(value)
      return value if value.between?(INT_MIN, INT_MAX)

      raise RangeError, "integer #{value} too #{value.negative? ? 'small' : 'big'} to convert to 'int'"
    end

    # rb_num2ulong_internal: the unsigned long, and whether it wrapped from
    # a negative number.
    def num2ulong_internal(value)
      loop do
        case value
        when nil then raise TypeError, "no implicit conversion of nil into Integer"
        when Integer
          raise RangeError, "bignum too big to convert into 'unsigned long'" if value.abs >= ULONG_LIMIT
          raise RangeError, "bignum out of range of unsigned long" if value < LONG_MIN

          return [unsigned(value), value.negative?]
        when Float
          return [unsigned(value.to_i), value <= -1.0] if value < ULONG_LIMIT && value >= LONG_MIN

          float_out_of_range(value, "integer")
        else value = to_int(value)
        end
      end
    end

    # NUM2ULONG
    def num2ulong(value) = num2ulong_internal(value)[0]

    # NUM2UINT
    def num2uint(value)
      number, negative = num2ulong_internal(value)
      if negative
        raise RangeError, "integer #{signed(number)} too small to convert to 'unsigned int'" if number < ULONG_LIMIT + INT_MIN
      elsif number > UINT_MAX
        raise RangeError, "integer #{number} too big to convert to 'unsigned int'"
      end
      number
    end

    # NUM2LL
    def num2ll(value)
      loop do
        case value
        when nil, String, true, false then raise TypeError, no_implicit_conversion(value, "Integer")
        when Integer
          raise RangeError, "bignum too big to convert into 'long long'" unless value.between?(LONG_MIN, LONG_MAX)

          return value
        when Float
          return value.to_i if value < 1 << 63 && value >= LONG_MIN

          float_out_of_range(value, "long long")
        else value = to_int(value)
        end
      end
    end

    # NUM2ULL
    def num2ull(value)
      loop do
        case value
        when nil then raise TypeError, "no implicit conversion of nil into Integer"
        when Integer
          raise RangeError, "bignum too big to convert into 'unsigned long long'" if value.abs >= ULONG_LIMIT
          raise RangeError, "bignum out of range of unsigned long long" if value < LONG_MIN

          return unsigned(value)
        when Float
          return unsigned(value.to_i) if value < ULONG_LIMIT && value >= LONG_MIN

          float_out_of_range(value, "unsigned long long")
        else value = to_int(value)
        end
      end
    end

    # NUM2DBL
    def num2dbl(value)
      case value
      when Float then value
      when Integer, Rational then value.to_f
      when nil, true, false, Symbol, String then raise TypeError, no_implicit_conversion(value, "Float")
      else
        raise TypeError, cant_convert(value, "Float") unless value.respond_to?(:to_f, true)

        result = value.__send__(:to_f)
        return result if result.is_a?(Float)

        raise TypeError, cant_convert_gives(value, "Float", :to_f, result)
      end
    end

    # rb_error_arity
    def check_arity(given, min, max)
      return if given >= min && (max.nil? || given <= max)

      expected = if max.nil? then "#{min}+"
                 elsif min == max then min.to_s
                 else "#{min}..#{max}"
                 end
      raise ArgumentError, "wrong number of arguments (given #{given}, expected #{expected})"
    end

    # -- Ruby objects as VALUEs ---------------------------------------------

    FIXNUM_MIN = -(1 << 62)
    FIXNUM_MAX = (1 << 62) - 1
    @addresses = {}.compare_by_identity
    @objects = {}
    @next_address = 0x10_0000_0000

    # The VALUE of a Ruby object: CRuby's encoding for the immediates, and
    # an address from a table for all other objects. The table keeps the
    # object, so its address stays valid for the life of the process.
    def value_to_address(object)
      case object
      when false then QFALSE
      when nil then QNIL
      when true then QTRUE
      else
        return (object << 1) | 1 if object.is_a?(Integer) && object.between?(FIXNUM_MIN, FIXNUM_MAX)

        flonum = object.is_a?(Float) ? flonum_address(object) : nil
        return flonum unless flonum.nil?

        @addresses[object] ||= begin
          address = @next_address
          @next_address += 40
          @objects[address] = object
          address
        end
      end
    end

    # The Ruby object at a VALUE that value_to_address returned.
    def address_to_value(address)
      address = signed(address)
      return address >> 1 if address.odd?

      value = unsigned(address)
      case value
      when QFALSE then false
      when QNIL then nil
      when QTRUE then true
      else
        return flonum_value(value) if value & 3 == 2

        raise ArgumentError, "no Ruby object at 0x#{value.to_s(16)}" unless @objects.key?(value)

        @objects[value]
      end
    end

    # rb_float_new_inline: a flonum's VALUE, or nil when the Float would
    # live on the heap.
    def flonum_address(float)
      bits = [float].pack("D").unpack1("Q")
      return signed(0x8000000000000002) if bits.zero?
      return nil if bits == 0x3000000000000000 || !(3..4).cover?((bits >> 60) & 7)

      signed((((bits << 3) | (bits >> 61)) & ADDRESS_MASK & ~1) | 2)
    end

    def flonum_value(value)
      return 0.0 if value == 0x8000000000000002

      bits = (2 - (value >> 63)) | (value & ~3)
      bits = ((bits >> 3) | (bits << 61)) & ADDRESS_MASK
      [bits].pack("Q").unpack1("D")
    end
  end
  private_constant :Native

  # -- fiddle.c -------------------------------------------------------------

  class Error < StandardError
  end

  remove_const(:DLError) if const_defined?(:DLError, false)

  class DLError < Error
  end

  # The C types, whose values Init_fiddle defines. They are listed in the
  # order that CRuby's Fiddle::Types.constants returns.
  module Types
    # The C integer type as wide as a pointer, which size_t, ssize_t,
    # ptrdiff_t and intptr_t are.
    pointer_wide = if FFI.find_type(:pointer).size == FFI.find_type(:int).size then 4
                   elsif FFI.find_type(:pointer).size == FFI.find_type(:long).size then 5
                   else 6
                   end

    FLOAT = 7
    DOUBLE = 8
    VARIADIC = 9
    CONST_STRING = 10
    SIZE_T = -pointer_wide
    SSIZE_T = pointer_wide
    PTRDIFF_T = pointer_wide
    INTPTR_T = pointer_wide
    UINTPTR_T = -pointer_wide
    BOOL = 11
    VOID = 0
    VOIDP = 1
    CHAR = 2
    UCHAR = -2
    SHORT = 3
    USHORT = -3
    INT = 4
    UINT = -4
    LONG = 5
    ULONG = -5
    LONG_LONG = 6
    ULONG_LONG = -6
    INT8_T = CHAR
    UINT8_T = -INT8_T
    INT16_T = FFI.find_type(:short).size == 2 ? SHORT : INT
    UINT16_T = -INT16_T
    INT32_T = FFI.find_type(:int).size == 4 ? INT : LONG
    UINT32_T = -INT32_T
    INT64_T = FFI.find_type(:long).size == 8 ? LONG : LONG_LONG
    UINT64_T = -INT64_T
  end

  # The symbol names rb_fiddle_type_ensure accepts for the aliased types.
  Native::TYPE_NAMES.update(int16_t: Types::INT16_T, int32_t: Types::INT32_T, int64_t: Types::INT64_T,
                            size_t: Types::SIZE_T, ssize_t: Types::SSIZE_T, ptrdiff_t: Types::PTRDIFF_T,
                            intptr_t: Types::INTPTR_T, uintptr_t: Types::UINTPTR_T)
  Native::TYPE_NAMES.freeze

  builtin = FFI::Type::Builtin
  pointer_size = builtin::POINTER.size
  pointer_align = builtin::POINTER.alignment

  ALIGN_VOIDP = pointer_align
  ALIGN_CHAR = builtin::CHAR.alignment
  ALIGN_SHORT = builtin::SHORT.alignment
  ALIGN_INT = builtin::INT.alignment
  ALIGN_LONG = builtin::LONG.alignment
  ALIGN_LONG_LONG = builtin::LONG_LONG.alignment
  ALIGN_INT8_T = builtin::INT8.alignment
  ALIGN_INT16_T = builtin::INT16.alignment
  ALIGN_INT32_T = builtin::INT32.alignment
  ALIGN_INT64_T = builtin::INT64.alignment
  ALIGN_FLOAT = builtin::FLOAT.alignment
  ALIGN_DOUBLE = builtin::DOUBLE.alignment
  ALIGN_SIZE_T = pointer_align
  ALIGN_SSIZE_T = pointer_align
  ALIGN_PTRDIFF_T = pointer_align
  ALIGN_INTPTR_T = pointer_align
  ALIGN_UINTPTR_T = pointer_align
  ALIGN_BOOL = builtin::BOOL.alignment

  WINDOWS = Native::WINDOWS

  SIZEOF_VOIDP = pointer_size
  SIZEOF_CHAR = builtin::CHAR.size
  SIZEOF_UCHAR = builtin::UCHAR.size
  SIZEOF_SHORT = builtin::SHORT.size
  SIZEOF_USHORT = builtin::USHORT.size
  SIZEOF_INT = builtin::INT.size
  SIZEOF_UINT = builtin::UINT.size
  SIZEOF_LONG = builtin::LONG.size
  SIZEOF_ULONG = builtin::ULONG.size
  SIZEOF_LONG_LONG = builtin::LONG_LONG.size
  SIZEOF_ULONG_LONG = builtin::ULONG_LONG.size
  SIZEOF_INT8_T = builtin::INT8.size
  SIZEOF_UINT8_T = builtin::UINT8.size
  SIZEOF_INT16_T = builtin::INT16.size
  SIZEOF_UINT16_T = builtin::UINT16.size
  SIZEOF_INT32_T = builtin::INT32.size
  SIZEOF_UINT32_T = builtin::UINT32.size
  SIZEOF_INT64_T = builtin::INT64.size
  SIZEOF_UINT64_T = builtin::UINT64.size
  SIZEOF_FLOAT = builtin::FLOAT.size
  SIZEOF_DOUBLE = builtin::DOUBLE.size
  SIZEOF_SIZE_T = pointer_size
  SIZEOF_SSIZE_T = pointer_size
  SIZEOF_PTRDIFF_T = pointer_size
  SIZEOF_INTPTR_T = pointer_size
  SIZEOF_UINTPTR_T = pointer_size
  SIZEOF_CONST_STRING = pointer_size
  SIZEOF_BOOL = builtin::BOOL.size

  # The address of the function that frees what Pointer.malloc allocates.
  # The C extension returns ruby_xfree. This runtime allocates with libc,
  # so it returns libc's free.
  Native::RUBY_FREE_ADDRESS = Native.unsigned(Native.dlsym(FFI::Pointer.new(Native.unsigned(Native::RTLD_DEFAULT)), "free").address)
  RUBY_FREE = Native.signed(Native::RUBY_FREE_ADDRESS)

  BUILD_RUBY_PLATFORM = RUBY_PLATFORM

  module_function

  # call-seq: Fiddle.dlwrap(val)
  #
  # The address of the Ruby object +val+.
  def dlwrap(val) = Native.value_to_address(val)

  # call-seq: Fiddle.dlunwrap(addr)
  #
  # The Ruby object at the address +addr+.
  def dlunwrap(addr) = Native.address_to_value(Native.num2ulong(addr))

  # call-seq: Fiddle.malloc(size)
  #
  # Allocates +size+ zeroed bytes and returns their address.
  def malloc(size) = Native.signed(Native.allocate(Native.num2ulong(size), checked: false))

  # call-seq: Fiddle.realloc(addr, size)
  #
  # Resizes the memory at +addr+ to +size+ bytes and returns its address,
  # which can be different from +addr+.
  def realloc(addr, size)
    address = Native.num2ulong(addr)
    Native.signed(Native.reallocate(address, Native.num2ulong(size)))
  end

  # call-seq: Fiddle.free(addr)
  #
  # Frees the memory at +addr+.
  def free(addr)
    Native.free(Native.memory(Native.num2ulong(addr)))
    nil
  end

  Qtrue = Native::QTRUE
  Qfalse = Native::QFALSE
  Qnil = Native::QNIL
  Qundef = Native::QUNDEF

  # -- function.c -----------------------------------------------------------

  class Function
    # function.c sets these instance variables where a program sees them.
    Primitive.attr! :ivars

    DEFAULT = Native::DEFAULT_ABI

    # call-seq:
    #    new(ptr, args, ret_type, abi = DEFAULT, name: nil, need_gvl: false)
    #
    # A C function at the address +ptr+, which takes arguments of the types
    # +args+ and returns +ret_type+.
    def initialize(*argv, name: nil, need_gvl: false)
      Native.check_arity(argv.size, 3, 4)
      ptr, args, ret_type, abi = argv
      @closure = ptr
      name = -name if name.instance_of?(String)
      @name = name
      @need_gvl = need_gvl

      ptr = Kernel.Integer(ptr)
      Native.num2ulong(ptr)
      abi = abi.nil? ? DEFAULT : Native.num2int(abi)
      ret_type = Native.num2int(Native.type_ensure(ret_type))
      Native.ffi_type(ret_type)

      Native.check_array(args)
      variadic = false
      arg_types = []
      args.each_with_index do |arg_type, i|
        arg_type = Native.num2int(Native.type_ensure(arg_type))
        if arg_type == Types::VARIADIC
          raise ArgumentError, "Fiddle::TYPE_VARIADIC must be the last argument type: #{args}" if i != args.size - 1

          variadic = true
          break
        end
        Native.ffi_type(arg_type)
        arg_types << arg_type
      end

      @ptr = ptr
      @argument_types = arg_types.freeze
      @return_type = ret_type
      @abi = abi
      @is_variadic = variadic
      nil
    end

    # call-seq: call(*args)
    #
    # Calls the C function with +args+. A variadic function takes its fixed
    # arguments, then a type and a value for each further argument.
    def call(*args)
      fixed_types = @argument_types
      variadic = @is_variadic
      fixed = fixed_types.size
      if variadic
        Native.check_arity(args.size, fixed, nil)
        raise ArgumentError, "variadic arguments must be type and value pairs: #{args}" if (args.size - fixed).odd?
      else
        Native.check_arity(args.size, fixed, fixed)
      end

      types = fixed_types.dup
      values = args.first(fixed)
      args.drop(fixed).each_slice(2) do |type, value|
        type = Native.num2int(Native.type_ensure(type))
        Native.ffi_type(type)
        types << type
        values << value
      end
      return_type = @return_type
      ffi_result = Native.ffi_type(return_type)
      ffi_params = types.map { |type| Native.ffi_type(type) }
      Native.check_abi(@abi, "error creating CIF")
      ffi_params[fixed..].each { |type| Native.variadic_ffi_type(type) } if variadic
      # A void argument passes nothing that libffi reads. ffi has no void
      # argument, so a zero int is used in its place.
      ffi_params.map! { |type| type == :void ? :int32 : type }

      keep = []
      mirrors = []
      pointer_class = Fiddle.const_get(:Pointer)
      native_values = types.each_with_index.map do |type, i|
        value = values[i]
        if type == Types::VOIDP
          if value.nil?
            value = 0
          else
            mirrors << Native::Mirror.of(value) if value.is_a?(Pointer)
            unless value.instance_of?(pointer_class) && value.singleton_methods.empty?
              value = pointer_class.__send__(:[], value)
              keep << value
              mirrors << Native::Mirror.of(value) if value.is_a?(Pointer)
            end
            value = Kernel.Integer(value)
          end
        end
        Native.to_native(type, value, keep)
      end
      mirrors.compact!
      mirrors.each(&:refresh)

      address = Native.unsigned(@ptr)
      blocking = !@need_gvl
      result =
        if variadic
          invoker = Native.variadic(address, ffi_params.first(fixed), ffi_result, blocking)
          invoker.invoke(ffi_params.map { |type| FFI.find_type(type) }, native_values)
        else
          Native.function(address, ffi_params, ffi_result, blocking).call(*native_values)
        end
      errno = FFI.errno
      Fiddle.__send__(:last_error=, errno)
      mirrors.each(&:flush)

      Native.from_native(@return_type, result)
    end
  end

  # -- closure.c ------------------------------------------------------------

  class Closure
    # closure.c sets @ctype and @args where a program sees them.
    Primitive.attr! :ivars

    # call-seq: new(ret, args, abi = Fiddle::DEFAULT)
    #
    # A C function that calls this object's #call, which returns +ret+ and
    # takes arguments of the types +args+.
    def initialize(*argv)
      state = Native.reset_state(self, Native::ClosureState)
      Native.check_arity(argv.size, 2, 3)
      ret, args, abi = argv
      abi = Function::DEFAULT if argv.size == 2

      Native.check_array(args)
      ffi_params = []
      normalized = args.map do |arg|
        arg = Native.type_ensure(arg)
        ffi_params << Native.ffi_type(Native.num2int(arg))
        arg
      end
      normalized.freeze

      ret = Native.type_ensure(ret)
      @ctype = ret
      @args = normalized

      Native.check_abi(Native.num2int(abi), "error prepping CIF")
      ffi_result = Native.ffi_type(Native.num2int(ret))
      ffi_params.delete(:void)
      closure = self
      state.function = FFI::Function.new(ffi_result, ffi_params) { |*raw| Native::ClosureState.invoke(closure, state, raw) }
      nil
    rescue Exception
      state.freed = true
      raise
    end

    # call-seq: to_i
    #
    # The address of this closure.
    def to_i
      state = Native.state(self, Native::ClosureState)
      raise ArgumentError, "already freed: #{inspect}" if state.freed

      state.function.nil? ? 0 : Native.signed(state.function.address)
    end

    # call-seq: free
    #
    # Frees this closure. Doing so twice does nothing.
    def free
      state = Native.state(self, Native::ClosureState)
      unless state.freed
        state.function&.free
        state.function = nil
        state.freed = true
      end
      nil
    end

    # call-seq: freed?
    #
    # Whether this closure was freed.
    def freed? = Native.state(self, Native::ClosureState).freed
  end

  module Native
    # The C struct behind a Closure: its ffi function.
    class ClosureState
      attr_accessor :function, :freed, :result

      def initialize
        @freed = false
      end

      # with_gvl_callback: converts what C passed, calls the closure, and
      # converts what it returned.
      def self.invoke(closure, state, raw)
        arg_types = closure.instance_variable_get(:@args)
        params = []
        arg_types.each_with_index do |type, i|
          type = Native.num2int(type)
          if type == Types::VOID
            params.clear
            break
          end
          params << argument(type, raw[i])
        end

        result = closure.__send__(:call, *params)
        type = Native.num2int(closure.instance_variable_get(:@ctype))
        convert_result(type, result, state)
      end

      def self.argument(type, value)
        case type
        when 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 11 then value
        when 7, 8 then value.to_f
        when 1 then Fiddle.const_get(:Pointer).__send__(:[], Native.signed(value.address))
        when 10 then Native.read_cstring(value.address)
        else raise RuntimeError, "closure args: #{type}"
        end
      end

      def self.convert_result(type, value, state)
        case type
        when 0 then nil
        when 2 then Native.wrap(Native.num2int(value), 8, true)
        when 3 then Native.wrap(Native.num2int(value), 16, true)
        when 4 then Native.num2int(value)
        when -2 then Native.wrap(Native.num2uint(value), 8, false)
        when -3 then Native.wrap(Native.num2uint(value), 16, false)
        when -4 then Native.wrap(Native.num2uint(value), 32, false)
        when 5 then Native.num2long(value)
        when -5 then Native.num2ulong(value)
        when 6 then Native.num2ll(value)
        when -6 then Native.num2ull(value)
        when 1 then FFI::Pointer.new(Native.num2ulong(value))
        when 7, 8 then Native.num2dbl(value)
        when 10
          # C returns the String's own bytes, which the callback must keep
          # alive. The closure keeps the copy that it returns until its next call.
          state.result = FFI::MemoryPointer.from_string(Native.string_value_cstr(value))
        when 11 then value ? true : false
        else raise RuntimeError, "closure retval: #{type}"
        end
      end
    end
  end

  # -- handle.c -------------------------------------------------------------

  class Handle
    RTLD_GLOBAL = FFI::DynamicLibrary::RTLD_GLOBAL
    RTLD_LAZY = FFI::DynamicLibrary::RTLD_LAZY
    RTLD_NOW = FFI::DynamicLibrary::RTLD_NOW

    # call-seq:
    #    new(library = nil, flags = Fiddle::RTLD_LAZY | Fiddle::RTLD_GLOBAL)
    #
    # Opens +library+ with +flags+; nil opens the program and the libraries
    # it has loaded. With a block, yields the handle and closes it after.
    def initialize(*args)
      Native.check_arity(args.size, 0, 2)
      state = Native.state(self, Native::HandleState)
      lib, flag = args
      path = lib.nil? ? nil : Native.string_value_cstr(lib)
      flags = args.size == 2 ? Native.num2int(flag) : RTLD_LAZY | RTLD_GLOBAL

      address = Native.dlopen(path, flags).address
      if address.zero?
        error = Native.dlerror
        raise DLError, error unless error.nil?
      end
      Native.dlclose(Native.memory(state.address)) if state.address != 0 && state.open && state.enable_close
      state.address = address
      state.open = true
      state.enable_close = false
      ObjectSpace.define_finalizer(self, state.finalizer) unless state.finalizer_defined
      state.finalizer_defined = true

      if block_given?
        begin
          yield self
        ensure
          Native::HandleState.close(state)
        end
      end
      nil
    end

    # call-seq: close
    #
    # Closes this handle. Closing it twice raises Fiddle::DLError.
    def close = Native::HandleState.close(Native.state(self, Native::HandleState))

    # call-seq: enable_close
    #
    # Makes garbage collection of this handle call dlclose().
    def enable_close
      Native.state(self, Native::HandleState).enable_close = true
      nil
    end

    # call-seq: disable_close
    #
    # Keeps garbage collection of this handle from calling dlclose().
    def disable_close
      Native.state(self, Native::HandleState).enable_close = false
      nil
    end

    # call-seq: close_enabled?
    #
    # Whether garbage collection of this handle calls dlclose().
    def close_enabled? = Native.state(self, Native::HandleState).enable_close

    # call-seq: to_i
    #
    # The address of this handle.
    def to_i = Native.signed(Native.state(self, Native::HandleState).address)

    # call-seq: to_ptr
    #
    # This handle as a Fiddle::Pointer.
    def to_ptr = Native::PointerState.pointer(Native.state(self, Native::HandleState).address, wrap0: self)

    # call-seq: sym(name)
    #
    # The address of the symbol +name+.
    def sym(name)
      state = Native.state(self, Native::HandleState)
      raise DLError, "closed handle" unless state.open

      Native::HandleState.sym(state.address, name)
    end
    alias [] sym

    # call-seq: sym_defined?(name)
    #
    # The address of the symbol +name+, or nil when there is none.
    def sym_defined?(name)
      state = Native.state(self, Native::HandleState)
      raise DLError, "closed handle" unless state.open

      address = Native::HandleState.find(state.address, name)
      address.zero? ? nil : Native.signed(address)
    end

    # call-seq: file_name
    #
    # The file this handle opened, where the system can tell.
    def file_name
      return nil unless Native::LINUX

      Native::HandleState.linux_file_name(Native.state(self, Native::HandleState).address)
    end

    class << self
      # call-seq: sym(name)
      #
      # The address of the symbol +name+, searched for with RTLD_NEXT.
      def sym(name) = Native::HandleState.sym(Native.unsigned(Native::RTLD_NEXT), name)
      alias [] sym

      # call-seq: sym_defined?(name)
      #
      # The address of the symbol +name+ with RTLD_NEXT, or nil.
      def sym_defined?(name)
        address = Native::HandleState.find(Native.unsigned(Native::RTLD_NEXT), name)
        address.zero? ? nil : Native.signed(address)
      end
    end
  end

  module Native
    # The C struct behind a Handle: the value that dlopen returned, whether
    # the handle is open, and whether garbage collection closes it.
    class HandleState
      attr_accessor :address, :open, :enable_close, :finalizer_defined

      def initialize
        @address = 0
        @open = false
        @enable_close = false
      end

      def self.predefined(address)
        handle = Handle.allocate
        state = Native.state(handle, self)
        state.address = Native.unsigned(address)
        state.open = true
        handle.freeze
      end

      def self.close(state)
        raise DLError, "dlclose() called too many times" unless state.open

        result = Native.dlclose(Native.memory(state.address))
        state.open = false
        raise DLError, Native.dlerror.to_s unless result.zero?

        result
      end

      # fiddle_handle_find_func: the symbol's address, or 0.
      def self.find(address, name)
        name = Native.string_value_cstr(name)
        Native.dlerror
        found = Native.dlsym(Native.memory(address), name).address
        Native.dlerror.nil? ? found : 0
      end

      def self.sym(address, name)
        found = find(address, name)
        raise DLError, "unknown symbol \"#{name}\"" if found.zero?

        Native.signed(found)
      end

      # dlinfo(RTLD_DI_LINKMAP) and the link map's l_name.
      def self.linux_file_name(address)
        @dlinfo ||= Native.function(Native.unsigned(Native.dlsym(Native.memory(Native::RTLD_DEFAULT), "dlinfo").address),
                                    [:pointer, :int, :pointer], :int, true)
        link_map = FFI::MemoryPointer.new(:pointer)
        result = @dlinfo.call(Native.memory(address), 2, link_map)
        map = link_map.get_pointer(0)
        raise DLError, "could not get handle file name: #{Native.dlerror}" if result != 0 || map.null?

        map.get_pointer(FFI::Type::Builtin::POINTER.size).get_string(0)
      end

      # dlclose() at garbage collection, when the handle requests it.
      def finalizer
        proc do
          Native.dlclose(Native.memory(@address)) if @address != 0 && @open && @enable_close
        end
      end
    end
  end

  class Handle
    NEXT = Native::HandleState.predefined(Native::RTLD_NEXT)
    DEFAULT = Native::HandleState.predefined(Native::RTLD_DEFAULT)
  end

  # -- pointer.c ------------------------------------------------------------

  class Pointer
    class << self
      # call-seq:
      #    Fiddle::Pointer.malloc(size, freefunc = nil)  => fiddle pointer instance
      #    Fiddle::Pointer.malloc(size, freefunc) { |pointer| ... } => ...
      #
      # Allocates +size+ zeroed bytes. +freefunc+ frees them once: at garbage
      # collection, at call_free, or when the block ends.
      def malloc(*args)
        Native.check_arity(args.size, 1, 2)
        size = Native.num2long(args[0])
        free, wrap = args.size == 2 ? Native::PointerState.freefunc(args[1]) : [nil, nil]
        address = Native.allocate(size, checked: true)
        pointer = Native::PointerState.pointer(address, size: size, free: free, wrap1: wrap, klass: self)
        return pointer unless block_given?
        raise ArgumentError, "a free function must be supplied to Fiddle::Pointer.malloc when it is called with a block" if free.nil?

        begin
          yield pointer
        ensure
          Native.state(pointer, Native::PointerState).release
        end
      end

      # call-seq:
      #    Fiddle::Pointer[val]  => cptr
      #    to_ptr(val)           => cptr
      #
      # The pointer behind +val+: a FILE* for an IO, the bytes of a String,
      # the value of +val+.to_ptr, or the address that +val+ converts to.
      def to_ptr(val)
        wrap = val
        if val.is_a?(IO)
          pointer = Native::PointerState.pointer(Native::PointerState.stdio_file(val))
        elsif val.is_a?(String)
          mirror = Native::Mirror.for(val)
          pointer = Native::PointerState.pointer(mirror.address, size: val.bytesize)
          wrap = mirror
        elsif val.respond_to?(:to_ptr, true)
          pointer = val.__send__(:to_ptr)
          raise DLError, "to_ptr should return a Fiddle::Pointer object" unless pointer.is_a?(Pointer)

          wrap = nil
        else
          number = Kernel.Integer(val)
          wrap = nil if number.equal?(val)
          pointer = Native::PointerState.pointer(Native.num2ulong(number))
        end
        Native.state(pointer, Native::PointerState).wrap0 = wrap unless wrap.nil?
        pointer
      end
      alias [] to_ptr

      # call-seq:
      #    Fiddle::Pointer.read(address, len)  => string
      #
      # The +len+ bytes at +address+.
      def read(address, len)
        address = Native.num2ulong(address)
        Native.read_bytes(address, Native.num2ulong(len))
      end

      # call-seq:
      #    Fiddle::Pointer.write(address, str)
      #
      # Writes the bytes of +str+ at +address+.
      def write(addr, str)
        bytes = Native.string_value(str)
        Native.write_bytes(Native.num2ulong(addr), bytes.b)
        str
      end
    end

    # call-seq:
    #    Fiddle::Pointer.new(address)       => fiddle_cptr
    #    new(address, size)                 => fiddle_cptr
    #    new(address, size, freefunc)       => fiddle_cptr
    #
    # A pointer to +address+, with an optional +size+ and a +freefunc+ that
    # garbage collection calls.
    def initialize(*args)
      Native.check_arity(args.size, 1, 3)
      state = Native.state(self, Native::PointerState)
      ptr = args[0]
      number = Kernel.Integer(ptr)
      wrap = number.equal?(ptr) ? nil : ptr
      address = Native.num2ulong(number)
      length = args.size >= 2 ? Native.num2long(args[1]) : 0
      free, free_wrap = args.size == 3 ? Native::PointerState.freefunc(args[2]) : [nil, nil]

      unless address.zero?
        Native.call_free_function(state.free, state.address) if state.address != 0 && state.free && !state.freed
        state.wrap0 = wrap
        state.wrap1 = free_wrap
        state.address = address
        state.size = length
        state.free = free
        state.watch(self)
      end
      nil
    end

    # call-seq: free=(function)
    #
    # Sets the function that frees this pointer's memory.
    def free=(val)
      state = Native.state(self, Native::PointerState)
      state.free, state.wrap1 = Native::PointerState.freefunc(val)
      state.watch(self)
      nil
    end

    # call-seq: free => Fiddle::Function
    #
    # The function that frees this pointer's memory, or nil.
    def free
      free = Native.state(self, Native::PointerState).free
      free.nil? ? nil : Function.new(Native.signed(free), [Types::VOIDP], Types::VOID)
    end

    # call-seq: call_free => nil
    #
    # Calls the free function, once. Does nothing without one.
    def call_free
      Native.state(self, Native::PointerState).release
      nil
    end

    # call-seq: freed? => bool
    #
    # Whether the free function was called.
    def freed? = Native.state(self, Native::PointerState).freed

    # call-seq: to_i
    #
    # The address that this pointer contains.
    def to_i = Native.signed(Native.state(self, Native::PointerState).address)
    alias to_int to_i

    # call-seq: to_value
    #
    # The Ruby object at this pointer's address.
    def to_value = Native.address_to_value(Native.state(self, Native::PointerState).address)

    # call-seq: ptr
    #
    # The pointer this pointer points to, like C's * operator.
    def ptr
      state = Native.state(self, Native::PointerState)
      state.refresh
      Native::PointerState.pointer(Native.memory(state.address).get_pointer(0).address)
    end
    alias +@ ptr

    # call-seq: ref
    #
    # A pointer to this pointer, like C's & operator. Writes through it
    # change the address that this pointer contains.
    def ref = Native::PointerState.pointer(Native.state(self, Native::PointerState).cell_address)
    alias -@ ref

    # call-seq: null?
    #
    # Whether this pointer is NULL.
    def null? = Native.state(self, Native::PointerState).address.zero?

    # call-seq:
    #    ptr.to_s        => string
    #    ptr.to_s(len)   => string
    #
    # The bytes up to the first NUL, or +len+ bytes.
    def to_s(*args)
      Native.check_arity(args.size, 0, 1)
      state = Native.state(self, Native::PointerState)
      state.refresh
      return Native.read_cstring(state.address) if args.empty?

      Native::PointerState.read_string(state.address, Native.num2int(args[0]))
    end

    # call-seq:
    #    ptr.to_str        => string
    #    ptr.to_str(len)   => string
    #
    # This pointer's +size+ bytes, or +len+ bytes.
    def to_str(*args)
      Native.check_arity(args.size, 0, 1)
      state = Native.state(self, Native::PointerState)
      state.refresh
      length = args.empty? ? state.size : Native.num2int(args[0])
      Native::PointerState.read_string(state.address, length)
    end

    # call-seq: inspect
    #
    # This pointer's class, address, size and free function.
    def inspect
      state = Native.state(self, Native::PointerState)
      object = Kernel.instance_method(:to_s).bind_call(self)[/0x\h+(?=>\z)/]
      format("#<%s:%s ptr=0x%016x size=%d free=0x%016x>",
             self.class, object, state.address, state.size, state.free || 0)
    end

    # call-seq:
    #    ptr == other    => true or false
    #    ptr.eql?(other) => true or false
    #
    # Whether +other+ is a pointer to the same address.
    def ==(other)
      return false unless other.is_a?(Pointer)

      Native.state(self, Native::PointerState).address == Native.state(other, Native::PointerState).address
    end
    alias eql? ==

    # call-seq:
    #    ptr <=> other   => -1, 0, 1, or nil
    #
    # Compares the addresses, or returns nil when +other+ is not a pointer.
    def <=>(other)
      return nil unless other.is_a?(Pointer)

      Native.signed(Native.state(self, Native::PointerState).address) <=>
        Native.signed(Native.state(other, Native::PointerState).address)
    end

    # call-seq:
    #    ptr + n   => new cptr
    #
    # A pointer +n+ bytes further on.
    def +(other)
      state = Native.state(self, Native::PointerState)
      offset = Native.num2long(other)
      Native::PointerState.pointer(state.address + offset, size: state.size - offset)
    end

    # call-seq:
    #    ptr - n   => new cptr
    #
    # A pointer +n+ bytes back.
    def -(other)
      state = Native.state(self, Native::PointerState)
      offset = Native.num2long(other)
      Native::PointerState.pointer(state.address - offset, size: state.size + offset)
    end

    # call-seq:
    #    ptr[index]                -> an_integer
    #    ptr[start, length]        -> a_string
    #
    # The byte at +index+, or +length+ bytes from +start+.
    def [](*args)
      state = Native.state(self, Native::PointerState)
      raise DLError, "NULL pointer dereference" if state.address.zero?

      Native.check_arity(args.size, 1, 2)
      state.refresh
      offset = Native.num2ulong(args[0])
      if args.size == 1
        byte = Native.memory(state.address + offset).get_uint8(0)
        Native.wrap(byte, 8, Native::CHAR_SIGNED)
      else
        Native.read_bytes(state.address + offset, Native.num2ulong(args[1]))
      end
    end

    # call-seq:
    #    ptr[index]         = int                    ->  int
    #    ptr[start, length] = string or cptr or addr ->  string or dl_cptr or addr
    #
    # Sets the byte at +index+, or copies +length+ bytes to +start+ from a
    # string, a pointer, or an address.
    def []=(*args)
      state = Native.state(self, Native::PointerState)
      raise DLError, "NULL pointer dereference" if state.address.zero?

      Native.check_arity(args.size, 2, 3)
      state.refresh
      offset = Native.num2ulong(args[0])
      if args.size == 2
        byte = Native.num2uint(args[1]) & 0xff
        Native.memory(state.address + offset).put_uint8(0, byte)
      else
        length = Native.num2ulong(args[1])
        source = args[2]
        bytes =
          if source.is_a?(String)
            source.b.byteslice(0, length).ljust(length, "\0")
          elsif source.is_a?(Pointer)
            source_state = Native.state(source, Native::PointerState)
            source_state.refresh
            Native.read_bytes(source_state.address, length)
          else
            Native.read_bytes(Native.num2ulong(source), length)
          end
        Native.write_bytes(state.address + offset, bytes)
      end
      state.flush
      args.last
    end

    # call-seq: size=(size)
    #
    # Sets the size of this pointer.
    def size=(size)
      Native.state(self, Native::PointerState).size = Native.num2long(size)
    end

    # call-seq: size
    #
    # The size of this pointer.
    def size = Native.state(self, Native::PointerState).size
  end

  module Native
    # The C struct behind a Pointer: its address, size and free function,
    # whether that function ran, and the two objects the pointer keeps
    # alive (wrap0 for the memory, wrap1 for the free function).
    class PointerState
      attr_accessor :size, :free, :freed, :wrap0, :wrap1

      def initialize
        @address = 0
        @size = 0
        @free = nil
        @freed = false
      end

      # A new Fiddle::Pointer, which skips initialize, as rb_fiddle_ptr_new2 does.
      def self.pointer(address, size: 0, free: nil, wrap0: nil, wrap1: nil, klass: Fiddle::Pointer)
        pointer = klass.allocate
        state = Native.reset_state(pointer, self)
        state.address = address
        state.size = size
        state.free = free
        state.wrap0 = wrap0
        state.wrap1 = wrap1
        state.watch(pointer)
        pointer
      end

      # get_freefunc: the address of a free function, and the object that
      # gave it when that was no Integer.
      def self.freefunc(func)
        return [nil, nil] if func.nil?

        number = Kernel.Integer(func)
        address = Native.num2ulong(number)
        [address.zero? ? nil : address, number.equal?(func) ? nil : func]
      end

      # rb_str_new(ptr, len)
      def self.read_string(address, length)
        raise ArgumentError, "negative string size (or size too big)" if length.negative?

        Native.read_bytes(address, length)
      end

      # rb_io_stdio_file: the FILE* of an IO.
      def self.stdio_file(io)
        fd = io.fileno
        @stdio ||= ObjectSpace::WeakKeyMap.new
        return @stdio[io] if @stdio.key?(io)

        address =
          if fd <= 2 && [STDIN, STDOUT, STDERR][fd].equal?(io)
            name = LINUX ? %w[stdin stdout stderr][fd] : %w[__stdinp __stdoutp __stderrp][fd]
            variable = Native.dlsym(Native.memory(RTLD_DEFAULT), name)
            variable.null? ? 0 : variable.get_pointer(0).address
          else
            flags = Native.fcntl(fd, 3)
            append = flags & (LINUX ? 0x400 : 0x8) != 0
            mode = case flags & 3
                   when 0 then "r"
                   when 1 then append ? "a" : "w"
                   else append ? "a+" : "r+"
                   end
            Native.fdopen(fd, mode).address
          end
        @stdio[io] = address
      end

      # The address, which lives in native memory once #ref has handed out
      # a pointer to it.
      def address = @cell ? @cell.get_pointer(0).address : @address

      def address=(value)
        @address = Native.unsigned(value)
        @cell&.put_pointer(0, FFI::Pointer.new(@address))
      end

      # The native cell that contains the address, for a pointer to it.
      def cell_address
        unless @cell
          @cell = FFI::MemoryPointer.new(:pointer)
          @cell.put_pointer(0, FFI::Pointer.new(@address))
        end
        @cell.address
      end

      # fiddle_ptr_free_ptr: calls the free function once.
      def release
        address = self.address
        return if address.zero? || @free.nil? || @freed

        @freed = true
        Native.call_free_function(@free, address)
      end

      # Frees the memory at garbage collection, as the C struct's dfree does.
      def watch(pointer)
        return if @watched || @free.nil?

        @watched = true
        ObjectSpace.define_finalizer(pointer, finalizer)
      end

      # A proc made here keeps this state and not the pointer, because a
      # finalizer must not reach the pointer.
      def finalizer = proc { release }

      # The copy of a String that this pointer contains. It is updated
      # before a read, and copied back after a write.
      def refresh = Mirror.of_state(self)&.refresh
      def flush = Mirror.of_state(self)&.flush
    end

    # The native copy of a String that Fiddle::Pointer[string] points to.
    # C points into the String itself; ruby cannot, so the copy follows
    # the String: changes to the String reach the copy before fiddle reads
    # it or passes it to C, and changes to the copy reach the String after
    # fiddle writes to it or C returns.
    class Mirror
      @mirrors = ObjectSpace::WeakMap.new

      # The mirror of `string`, so that one String has one address.
      def self.for(string)
        mirror = @mirrors[string]
        return mirror unless mirror.nil?

        @mirrors[string] = new(string)
      end

      # The mirror of a pointer, directly or through the pointer it was
      # made from.
      def self.of(pointer) = of_state(Native.state(pointer, PointerState))

      def self.of_state(state)
        wrap = state.wrap0
        wrap.is_a?(Fiddle::Pointer) && Native.state(wrap, PointerState).address == state.address ? of(wrap) : (wrap if wrap.is_a?(Mirror))
      end

      attr_reader :address

      def initialize(string)
        @string = string
        @capacity = string.bytesize + 1
        @memory = FFI::MemoryPointer.new(:char, @capacity)
        @address = @memory.address
        @snapshot = nil
        refresh
      end

      # Copies the String into native memory when the String has changed.
      def refresh
        return if @snapshot && @string.frozen?

        bytes = @string.b
        return if bytes == @snapshot

        length = [bytes.bytesize, @capacity - 1].min
        @memory.put_bytes(0, bytes, 0, length)
        @memory.put_uint8(length, 0)
        @snapshot = bytes.byteslice(0, length)
      end

      # Copies native memory into the String when C has changed it.
      def flush
        bytes = @memory.get_bytes(0, @snapshot.bytesize)
        return if bytes == @snapshot

        @snapshot = bytes
        @string.replace(bytes.force_encoding(@string.encoding)) unless @string.frozen?
      end
    end
  end

  NULL = Native::PointerState.pointer(0)

  # -- pinned.c -------------------------------------------------------------

  class Pinned
    # call-seq:
    #    Fiddle::Pinned.new(object)      => pinned_object
    #
    # A reference that keeps +object+ from moving.
    def initialize(ref)
      Native.state(self, Native::PinnedState).ref = ref
      nil
    end

    # call-seq: ref
    #
    # The object this instance pins.
    def ref
      state = Native.state(self, Native::PinnedState)
      raise ClearedReferenceError, "`ref` called on a cleared object" if state.cleared?

      state.ref
    end

    # call-seq: clear
    #
    # Drops the reference.
    def clear
      Native.state(self, Native::PinnedState).ref = false
      self
    end

    # call-seq: cleared?
    #
    # Whether the reference was dropped.
    def cleared? = Native.state(self, Native::PinnedState).cleared?
  end

  module Native
    # The C struct behind a Pinned: the VALUE it contains. A cleared one
    # contains 0, which is the VALUE of false, so pinning false reads as cleared.
    class PinnedState
      attr_accessor :ref

      def initialize
        @ref = false
      end

      def cleared? = @ref.equal?(false)
    end
  end

  class ClearedReferenceError < Error
  end

  # -- memory_view.c --------------------------------------------------------

  # A byte view of a Fiddle::Pointer, the one class here that exports
  # memory: other objects have no memory view to give.
  class MemoryView
    # call-seq: export(target) { |memory_view| ... }
    #
    # Yields a view of +target+ and releases it after.
    def self.export(target)
      view = new(target)
      begin
        raise LocalJumpError, "no block given" unless block_given?

        yield view
      ensure
        Native.state(view, Native::MemoryViewState).release
      end
    end

    # call-seq: new(target)
    #
    # A view of the memory of +target+.
    def initialize(target)
      state = Native.state(self, Native::MemoryViewState)
      pointer_state = target.is_a?(Pointer) ? Native.state(target, Native::PointerState) : nil
      if pointer_state.nil? || pointer_state.address.zero? || pointer_state.size.zero?
        state.obj = nil
        raise ArgumentError, "Unable to get a memory view from #{target.inspect}"
      end
      state.obj = target
      state.address = pointer_state.address
      state.byte_size = pointer_state.size
      nil
    end

    # call-seq: release
    #
    # Releases the view.
    def release
      Native.state(self, Native::MemoryViewState).release
      nil
    end

    def obj = Native.state(self, Native::MemoryViewState).obj
    def byte_size = viewed(&:byte_size)
    def readonly? = viewed { true }
    def format = viewed { nil }
    def item_size = viewed { 1 }
    def ndim = viewed { 1 }
    def shape = viewed { nil }
    def strides = viewed { nil }
    def sub_offsets = viewed { nil }

    # call-seq: [](index)
    #
    # The byte at +index+.
    def [](*indices)
      viewed do |state|
        raise IndexError, "wrong number of index (#{indices.size} for 1)" if indices.size != 1

        state.pointer_state.refresh
        Native.memory(state.address + Native.num2long(indices[0])).get_uint8(0)
      end
    end

    # call-seq: to_s
    #
    # The viewed bytes, as a frozen binary String. C's String shares the
    # memory; this one contains a copy.
    def to_s
      state = Native.state(self, Native::MemoryViewState)
      return "".b.freeze if state.obj.nil?

      state.pointer_state.refresh
      Native.read_bytes(state.address, state.byte_size).freeze
    end

    private

    def viewed
      state = Native.state(self, Native::MemoryViewState)
      state.obj.nil? ? nil : yield(state)
    end
  end

  module Native
    # The C struct behind a MemoryView: the viewed object and its bytes.
    class MemoryViewState
      attr_accessor :obj, :address, :byte_size

      def pointer_state = Native.state(@obj, PointerState)

      def release
        return if @obj.nil?

        @obj = nil
        @byte_size = 0
      end
    end
  end
end
