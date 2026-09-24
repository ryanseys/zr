# frozen_string_literal: true

# Type.c, ArrayType.c, MappedType.c and StructByValue.c: a C type, its
# builtin instances under every name the gem gives them, and the types
# that describe an array, a converted value and a struct passed whole.
module FFI
  TypeDefs = {}

  class Type
    # NativeType, the kinds of value the C half reads and writes.
    NATIVE = %i[VOID INT8 UINT8 INT16 UINT16 INT32 UINT32 INT64 UINT64 LONG ULONG FLOAT32 FLOAT64 LONGDOUBLE POINTER FUNCTION
                BUFFER_IN BUFFER_OUT BUFFER_INOUT BOOL STRING VARARGS STRUCT ARRAY MAPPED].each_with_index.to_h.freeze
    private_constant :NATIVE

    def initialize(value)
      case value
      when Integer
        raise ArgumentError, "wrong type" unless value.between?(-2**62, 2**62 - 1)

        @native = value
        @ffi = ffi_type
      when Type
        @native = value.ffi_native
        @ffi = value.ffi_type
      else
        raise ArgumentError, "wrong type"
      end
      freeze
    end

    def size = ffi_type.size

    def alignment = ffi_type.alignment

    def inspect = "#<#{Primitive.zr_class_path(Primitive.zr_real_class(self))}::#{FFI.hex(__id__ << 3)} size=#{size} alignment=#{alignment}>"

    # The NativeType this is, as a Symbol.
    def ffi_native
      Primitive.attr! :hidden
      @native || -1
    end

    def ffi_kind
      Primitive.attr! :hidden
      NATIVE.key(ffi_native)
    end

    # The ffi_type libffi reads for this.
    def ffi_type
      Primitive.attr! :hidden
      @ffi || FFIType.builtin("void", FFIType::VOID, 1)
    end

    class Builtin < Type
      class << self
        undef_method :new
      end

      def inspect = "#<#{Primitive.zr_class_path(Primitive.zr_real_class(self))}::#{@name} size=#{size} alignment=#{alignment}>"

      private

      def assign(name, ffi)
        Primitive.attr! :hidden
        @name = name
        @native = NATIVE.fetch(name)
        @ffi = ffi
        freeze
      end
    end
  end

  module NativeType
  end

  class Type
    # builtin_type_new under its three names, then the aliases.
    [
      [:VOID, "void", 0, 1], [:INT8, "sint8", 6, 1], [:UINT8, "uint8", 5, 1], [:INT16, "sint16", 8, 2], [:UINT16, "uint16", 7, 2],
      [:INT32, "sint32", 10, 4], [:UINT32, "uint32", 9, 4], [:INT64, "sint64", 12, 8], [:UINT64, "uint64", 11, 8],
      [:LONG, "sint64", 12, 8], [:ULONG, "uint64", 11, 8], [:FLOAT32, "float", 2, 4], [:FLOAT64, "double", 3, 8],
      [:LONGDOUBLE, "double", 3, 8], [:POINTER, "pointer", 14, 8], [:STRING, "pointer", 14, 8], [:BUFFER_IN, "pointer", 14, 8],
      [:BUFFER_OUT, "pointer", 14, 8], [:BUFFER_INOUT, "pointer", 14, 8], [:BOOL, "uint8", 5, 1], [:VARARGS, "void", 0, 1]
    ].each do |name, ffi_name, code, size|
      type = Primitive.zr_class_build(Builtin).__send__(:assign, name, FFIType.builtin(ffi_name, code, size))
      const_set(name, type)
      NativeType.const_set(name, type)
      FFI.const_set(:"TYPE_#{name}", type)
    end

    { SCHAR: :INT8, CHAR: :INT8, UCHAR: :UINT8, SHORT: :INT16, SSHORT: :INT16, USHORT: :UINT16, INT: :INT32, SINT: :INT32,
      UINT: :UINT32, LONG_LONG: :INT64, SLONG_LONG: :INT64, ULONG_LONG: :UINT64, SLONG: :LONG, FLOAT: :FLOAT32,
      DOUBLE: :FLOAT64 }.each { |name, type| const_set(name, const_get(type)) }
  end

  class << self
    # rbffi_Type_Lookup: the Type a name stands for, or nil.
    def type_lookup(name)
      Primitive.attr! :hidden
      case name
      when Symbol, String
        [custom_typedefs, TypeDefs].each do |map|
          found = map.fetch(name, nil)
          return found if found.is_a?(Type)
        end
        nil
      when Type then name
      end
    end

    # rbffi_type_size: how many bytes a type spec takes.
    def size_of(type)
      Primitive.attr! :hidden
      case type
      when Integer then int_value(type)
      when Symbol
        found = TypeDefs.fetch(type, nil)
        return found.ffi_type.size if found.is_a?(Type)
        return int_value(found.size) if found.respond_to?(:size)

        int_value(FFI.type_size(type))
      else int_value(type.size)
      end
    end
  end

  class ArrayType < Type
    def initialize(component, length)
      @length = FFI.uint_value(length)
      @component = component
      element = FFI.typed(component, Type).ffi_type
      @ffi = FFIType.aggregate(element.size * @length, element.alignment, [element] * @length)
    end

    def length = @length || 0

    def elem_type = @component

    def ffi_native
      Primitive.attr! :hidden
      NATIVE[:ARRAY]
    end

    def ffi_type
      Primitive.attr! :hidden
      @ffi || FFIType.aggregate(0, 0, [])
    end
  end

  Type::Array = ArrayType

  class Type
    class Mapped < Type
      def initialize(converter)
        raise NoMethodError, "native_type method not implemented" unless converter.respond_to?(:native_type)
        raise NoMethodError, "to_native method not implemented" unless converter.respond_to?(:to_native)
        raise NoMethodError, "from_native method not implemented" unless converter.respond_to?(:from_native)

        @type = converter.__send__(:native_type)
        raise TypeError, "native_type did not return instance of FFI::Type" unless @type.is_a?(Type)

        @converter = converter
        @ffi = @type.ffi_type
        freeze
      end

      def native_type = @type

      alias type native_type

      def to_native(*args) = @converter.__send__(:to_native, *args)

      def from_native(*args) = @converter.__send__(:from_native, *args)

      def converter = @converter

      def ffi_native
        Primitive.attr! :hidden
        NATIVE[:MAPPED]
      end
    end
  end

  class StructByValue < Type
    def initialize(struct_class)
      layout = Kernel.instance_method(:instance_variable_get).bind_call(struct_class, :@layout)
      raise TypeError, "wrong type in @layout ivar (expected FFI::StructLayout)" unless layout.instance_of?(StructLayout)

      @struct_class = struct_class
      @layout = layout
      @ffi = FFIType.aggregate(layout.size, layout.alignment, layout.ffi_type.elements)
    end

    def layout = @layout

    def struct_class = @struct_class

    def ffi_native
      Primitive.attr! :hidden
      NATIVE[:STRUCT]
    end

    def ffi_type
      Primitive.attr! :hidden
      @ffi || FFIType.aggregate(0, 1, [])
    end
  end

  Type::Struct = StructByValue
end
