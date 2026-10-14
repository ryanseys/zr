# frozen_string_literal: true

# What every file of the C part shares: ruby's C conversions (NUM2INT and
# the related macros) with the words their errors use, native memory that
# the collector frees with the object that owns it, and libffi's ffi_type.
module FFI
  class << self
    # NUM2INT.
    def int_value(value)
      Primitive.attr! :hidden
      Integer.send(:int_operand, value)
    end

    # NUM2LONG.
    def long_value(value)
      Primitive.attr! :hidden
      Primitive.zr_index_operand_m(value)
    end

    # NUM2ULONG: a value from -2**63 up to 2**64 - 1, which C reads as
    # unsigned.
    def ulong_value(value, type = "unsigned long")
      Primitive.attr! :hidden
      case value
      when Integer
        raise RangeError, "bignum too big to convert into '#{type}'" if value.abs >= 2**64
        raise RangeError, "bignum out of range of #{type}" if value < -2**63

        value
      when Float
        raise RangeError, "float #{format("%-.10g", value)} out of range of integer" unless value >= -2**63 && value < 2**64

        value.truncate
      else
        raise TypeError, "no implicit conversion of nil into Integer" if value.nil?

        Primitive.zr_index_operand_m(value)
      end
    end

    # NUM2UINT: as NUM2ULONG, then within the range of an unsigned int.
    def uint_value(value)
      Primitive.attr! :hidden
      number = ulong_value(value)
      raise RangeError, "integer #{number} too small to convert to 'unsigned int'" if number < -2**31
      raise RangeError, "integer #{number} too big to convert to 'unsigned int'" if number >= 2**32

      number
    end

    # NUM2LL.
    def ll_value(value)
      Primitive.attr! :hidden
      case value
      when Integer
        raise RangeError, "bignum too big to convert into 'long long'" unless value.between?(-2**63, 2**63 - 1)

        value
      when Float
        raise RangeError, "float #{format("%-.10g", value)} out of range of long long" unless value >= -2**63 && value < 2**63

        value.truncate
      when nil, true, false, String then raise TypeError, no_implicit_conversion(value, "Integer")
      else Primitive.zr_index_operand_m(value)
      end
    end

    # NUM2ULL.
    def ull_value(value)
      Primitive.attr! :hidden
      case value
      when Integer
        raise RangeError, "bignum too big to convert into 'unsigned long long'" if value.abs >= 2**64
        raise RangeError, "bignum out of range of unsigned long long" if value < -2**63

        value
      when Float
        raise RangeError, "float #{format("%-.10g", value)} out of range of unsigned long long" unless value >= -2**63 && value < 2**64

        value.truncate
      else ulong_value(value)
      end
    end

    # NUM2DBL.
    def dbl_value(value)
      Primitive.attr! :hidden
      case value
      when Float then value
      when Integer, Rational then value.to_f
      when nil, true, false, Symbol, String then raise TypeError, no_implicit_conversion(value, "Float")
      else
        raise TypeError, cant_convert(value, "Float") unless value.respond_to?(:to_f, true)

        float = value.__send__(:to_f)
        raise TypeError, cant_convert_gives(value, "Float", :to_f, float) unless float.is_a?(Float)

        float
      end
    end

    # rbffi_longdouble_new: a long double as a BigDecimal when bigdecimal
    # loads, and as a Float when it does not. Here a long double is a
    # double.
    def longdouble_new(value)
      Primitive.attr! :hidden
      @big_decimal = begin
        require "bigdecimal"
        true
      rescue Exception
        false
      end if @big_decimal.nil?
      @big_decimal ? BigDecimal(format("%.35e", value)) : value
    end

    # rbffi_num2longdouble.
    def longdouble_value(value)
      Primitive.attr! :hidden
      return value if value.is_a?(Float)
      return Float(value.to_s("E")) if Object.const_defined?(:BigDecimal) && value.is_a?(BigDecimal)

      dbl_value(value)
    end

    # StringValueCStr.
    def cstr_value(value)
      Primitive.attr! :hidden
      text = Primitive.zr_str_operand(value)
      raise ArgumentError, "string contains null byte" if text.include?("\0")

      text
    end

    # TypedData_Get_Struct and Check_Type: `value` itself, when it is
    # the type that the C part expects.
    def typed(value, klass, expected = klass.name)
      Primitive.attr! :hidden
      return value if value.is_a?(klass)

      raise TypeError, "wrong argument type #{__send__(:conversion_name, value)} (expected #{expected})"
    end

    # Bytes that the collector frees when nothing refers to them: the
    # String keeps them, and its bytes never move while no write goes through it.
    def storage(size)
      Primitive.attr! :hidden
      raise NoMemoryError, "failed to allocate memory" if size.negative?

      "\0".b * size
    end

    def address_of(storage)
      Primitive.attr! :hidden
      Primitive.zr_ffi_str_addr(storage)
    end

    # A native address as C's %p writes it inside ruby.
    def hex(address)
      Primitive.attr! :hidden
      format("0x%016x", address & 0xffff_ffff_ffff_ffff)
    end

    def _async_cb_dispatcher_atfork_child = nil
  end

  # The typedefs that a program adds, kept separate from TypeDefs.
  module_function def custom_typedefs = @custom_typedefs ||= {}

  # libffi's ffi_type: a size, an alignment, a kind and, for an aggregate,
  # its elements, laid out in native memory for libffi to read. A builtin
  # one is libffi's own; one ffi_c makes lives as long as this does.
  class FFIType
    VOID = 0
    FLOAT = 2
    DOUBLE = 3
    STRUCT = 13

    attr_reader :address, :size, :alignment, :code, :elements

    # One of libffi's scalars, by the name libffi gives it: one object a
    # name, as libffi has one ffi_type.
    def self.builtin(name, code, size)
      (@builtins ||= {})[name] ||= new(Primitive.zr_ffi_type("ffi_type_#{name}"), code, size, size, nil, nil)
    end

    # An aggregate over `elements`, which a nil ends early, as libffi's
    # element list ends at a NULL.
    def self.aggregate(size, alignment, elements)
      header = FFI.storage(24)
      new(FFI.address_of(header), STRUCT, size, alignment, elements, header).update(size, alignment, elements)
    end

    def initialize(address, code, size, alignment, elements, header)
      @address = address
      @code = code
      @size = size
      @alignment = alignment
      @elements = elements
      @header = header
    end

    # The fields libffi reads, written again over a new element list.
    def update(size, alignment, elements)
      @size = size
      @alignment = alignment
      @elements = elements
      addresses = elements.take_while(&:itself).map(&:address)
      @list = FFI.storage(8 * (addresses.size + 1))
      list = [*addresses, 0].pack("Q*")
      Primitive.zr_ffi_write(FFI.address_of(@list), list, 0, list.bytesize)
      fields = [size, alignment, code, FFI.address_of(@list)].pack("QSSx4Q")
      Primitive.zr_ffi_write(@address, fields, 0, fields.bytesize)
      self
    end

    def float? = code == FLOAT || code == DOUBLE

    # find_homogeneous_leaf_type: the one scalar every leaf is, or nil,
    # and whether each leaf is a float.
    def homogeneous_leaf
      return [self, float?] if code != STRUCT || elements.nil?

      result = nil
      floats = true
      elements.take_while(&:itself).each do |element|
        leaf, float = element.homogeneous_leaf
        floats &&= float
        result = result.nil? || (leaf && leaf.equal?(result)) ? leaf : nil
      end
      [result, floats]
    end
  end
  private_constant :FFIType
end
