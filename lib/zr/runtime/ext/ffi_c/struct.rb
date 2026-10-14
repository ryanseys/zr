# frozen_string_literal: true

# StructLayout.c and Struct.c: the position of each field of a C struct
# and its type, a struct over memory, and the array that a struct
# contains inline.
module FFI
  class StructLayout < Type
    class Field
      def initialize(*args)
        raise ArgumentError, wrong_arity(args.size, 3) unless args.size == 3

        name, offset, type = args
        raise TypeError, "wrong argument type #{Primitive.zr_class_path(Primitive.zr_real_class(name))} (expected Symbol/String)" unless name.is_a?(Symbol) || name.is_a?(::String)
        raise TypeError, "wrong argument type #{__send__(:conversion_name, offset)} (expected Integer)" unless offset.is_a?(Integer) && offset.between?(-2**62, 2**62 - 1)
        raise TypeError, "wrong argument type #{Primitive.zr_class_path(Primitive.zr_real_class(type))} (expected FFI::Type)" unless type.is_a?(Type)

        @offset = FFI.uint_value(offset) % 2**32
        @name = name.is_a?(Symbol) ? name : name.to_sym
        @type = type
        native = type.ffi_kind == :MAPPED ? type.native_type.ffi_kind : type.ffi_kind
        @reference = %i[FUNCTION POINTER].include?(native) ||
                     (respond_to?(:reference_required?) && reference_required?) ||
                     (type.respond_to?(:reference_required?) && type.reference_required?) ? true : false
        freeze
      end

      def offset = @offset

      def size = @type.ffi_type.size

      def alignment = @type.ffi_type.alignment

      def name = @name

      def type = @type

      def get(pointer)
        raise ArgumentError, "get not supported for #{Primitive.zr_class_path(Primitive.zr_real_class(@type))}" unless ffi_op?

        FFI.typed(pointer, AbstractMemory).ffi_get(@type.ffi_kind, @offset)
      end

      def put(pointer, value)
        raise ArgumentError, "put not supported for #{Primitive.zr_class_path(Primitive.zr_real_class(@type))}" unless ffi_op?

        FFI.typed(pointer, AbstractMemory).ffi_put(@type.ffi_kind, @offset, value)
        self
      end

      # Whether a memory op reads and writes this field without `get`.
      def ffi_op?
        Primitive.attr! :hidden
        AbstractMemory.op?(@type.ffi_kind)
      end

      def ffi_reference?
        Primitive.attr! :hidden
        @reference
      end
    end

    class Number < Field; end
    class String < Field; end
    class Pointer < Field; end

    class Function < Field
      def get(pointer)
        FFI::Function.new_instance(type, FFI.typed(pointer, AbstractMemory).ffi_get(:POINTER, offset))
      end

      def put(pointer, proc)
        value = if proc.nil? || proc.is_a?(FFI::Function) then proc
                elsif proc.is_a?(Proc) || proc.respond_to?(:call) then FFI::Function.for_proc(type, proc)
                else raise TypeError, "wrong type (expected Proc or Function)"
                end
        FFI.typed(pointer, AbstractMemory).ffi_put(:POINTER, offset, value)
        self
      end
    end

    class Array < Field
      def get(pointer)
        klass = %i[INT8 UINT8].include?(type.elem_type.ffi_kind) ? CharArray : FFI::Struct::InlineArray
        klass.new(pointer, self)
      end

      def put(pointer, value)
        array = FFI.typed(type, ArrayType)
        raise NotImplementedError, "cannot set array field" unless %i[INT8 UINT8].include?(array.elem_type.ffi_kind) && value.instance_of?(::String)

        if value.bytesize < array.length
          pointer.put_string(offset, value)
        elsif value.bytesize == array.length
          pointer.put_bytes(offset, value)
        else
          raise IndexError, "String is longer (#{value.bytesize} bytes) than the char array (#{array.length} bytes)"
        end
        value
      end
    end

    def initialize(fields, size, alignment)
      fields = FFI.typed(fields, ::Array)
      size = FFI.int_value(size)
      @alignment = FFI.int_value(alignment)
      @size = ((size - 1) | (@alignment - 1)) + 1
      @fields = []
      @names = []
      @map = {}
      elements = fields.each_with_index.map do |field, i|
        raise TypeError, "wrong type for field #{i}." unless field.is_a?(Field)

        name = field.name
        type = field.type.ffi_type
        raise TypeError, "type of field #{i} has zero size" if type.size.zero? && i < fields.size - 1

        @map[name] = field
        @fields << field
        @names << name
        type if type.size.positive?
      end
      raise RuntimeError, "Struct size is zero" if @size.zero?

      @ffi = FFIType.aggregate(@size, @alignment, elements)
      @map.freeze
      @fields.freeze
      @names.freeze
      freeze
    end

    def [](name) = @map[name]

    def fields = @fields.dup

    def members = @names.dup

    def to_a = @fields.dup

    # struct_layout_union_bang: libffi has no unions, so a union passes as
    # repeats of the one type whose alignment is the union's.
    def __union!
      leaf, floats = ffi_type.homogeneous_leaf
      type = leaf if leaf && floats
      type ||= [["float", 2, 4], ["double", 3, 8]].map { |name, code, size| FFIType.builtin(name, code, size) }.find { |t| t.alignment == @alignment } if floats
      type ||= [["sint8", 6, 1], ["sint16", 8, 2], ["sint32", 10, 4], ["sint64", 12, 8]].map { |name, code, size| FFIType.builtin(name, code, size) }.find { |t| t.alignment == @alignment }
      raise RuntimeError, "cannot create libffi union representation for alignment #{@alignment}" if type.nil?

      ffi_type.update(@size, @alignment, [type] * (@size / type.size))
      self
    end

    def ffi_native
      Primitive.attr! :hidden
      NATIVE[:STRUCT]
    end

    def ffi_type
      Primitive.attr! :hidden
      @ffi || FFIType.aggregate(0, 0, [])
    end

    def ffi_field(name)
      Primitive.attr! :hidden
      @map[name]
    end
  end

  class Struct
    Primitive.zr_define_alloc(self)

    class << self
      alias alloc_in new
      alias alloc_out new
      alias alloc_inout new
      alias new_in new
      alias new_out new
      alias new_inout new
    end

    def initialize(*args)
      pointer, *rest = args
      @layout = if rest.empty?
                  Struct.class_layout(self.class)
                else
                  self.class.layout(*rest)
                end
      raise RuntimeError, "Invalid Struct layout" unless @layout.is_a?(StructLayout)

      if pointer.nil?
        ffi_allocate
      else
        FFI.typed(pointer, AbstractMemory)
        @pointer = pointer
      end
    end

    def initialize_copy(other)
      other = FFI.typed(other, Struct)
      return self if equal?(other)

      @layout = other.__send__(:ffi_layout)
      source = other.__send__(:ffi_pointer)
      if source && !source.ffi_address.zero?
        @pointer = MemoryPointer.new_instance(1, @layout.size, false)
        Primitive.zr_ffi_copy(@pointer.ffi_address, source.ffi_address, @layout.size)
      else
        @pointer = source
      end
      @references = other.__send__(:ffi_references)&.dup
      self
    end

    def order(*args)
      return @pointer.order if args.empty?

      struct = dup
      struct.__send__(:pointer=, @pointer.order(*args))
      struct
    end

    def pointer = @pointer

    def layout = @layout

    def [](name)
      field = ffi_field(name)
      return field.get(@pointer) unless field.ffi_op?

      @pointer.ffi_get(field.type.ffi_kind, field.offset)
    end

    def []=(name, value)
      Primitive.zr_frozen_error(self) if frozen?

      field = ffi_field(name)
      if field.ffi_op?
        @pointer.ffi_put(field.type.ffi_kind, field.offset, value)
      else
        field.put(@pointer, value)
      end
      (@references ||= {})[field.name] = value if field.ffi_reference?
      value
    end

    def null? = ffi_pointer.ffi_address.zero?

    def self.class_layout(klass)
      Primitive.attr! :hidden
      raise RuntimeError, "no Struct layout configured for #{klass}" unless klass.instance_variable_defined?(:@layout)

      layout = klass.instance_variable_get(:@layout)
      raise RuntimeError, "invalid Struct layout for #{klass}" unless layout.is_a?(StructLayout)

      layout
    end

    private

    def pointer=(pointer)
      Primitive.zr_frozen_error(self) if frozen?
      raise TypeError, "wrong argument type #{Primitive.zr_class_path(Primitive.zr_real_class(pointer))} (expected Pointer or Buffer)" unless pointer.is_a?(AbstractMemory)

      size = ffi_layout.size
      if size > pointer.ffi_size
        raise ArgumentError, "memory of #{pointer.ffi_size} bytes too small for struct #{Primitive.zr_class_path(Primitive.zr_real_class(self))} (expected at least #{size})"
      end

      @pointer = pointer
      instance_variable_set(:@pointer, pointer)
      self
    end

    def layout=(layout)
      raise TypeError, "wrong argument type #{Primitive.zr_class_path(Primitive.zr_real_class(layout))} (expected FFI::StructLayout)" unless layout.is_a?(StructLayout)

      Primitive.zr_frozen_error(self) if frozen?
      @set_layout = layout
      instance_variable_set(:@layout, layout)
      self
    end

    # struct_layout and struct_validate: the layout, taken from the class
    # the first time, and the memory, allocated the first time.
    def ffi_layout
      Primitive.attr! :hidden
      @set_layout || @layout || (@layout = Struct.class_layout(self.class))
    end

    def ffi_pointer
      Primitive.attr! :hidden
      @pointer
    end

    def ffi_references
      Primitive.attr! :hidden
      @references
    end

    def ffi_allocate
      Primitive.attr! :hidden
      @pointer = MemoryPointer.new_instance(ffi_layout.size, 1, true)
    end

    # struct_field: the field `name` names, which must be one.
    def ffi_field(name)
      Primitive.attr! :hidden
      ffi_allocate if @pointer.nil? && ffi_layout
      ffi_layout.ffi_field(name) || raise(ArgumentError, "No such field '#{name}'")
    end

    class InlineArray
      include Enumerable

      def initialize(memory, field)
        @memory = FFI.typed(memory, AbstractMemory)
        @field = FFI.typed(field, StructLayout::Field)
        @array = FFI.typed(field.type, ArrayType)
        @component = FFI.typed(@array.elem_type, Type)
        @kind = @component.ffi_kind == :MAPPED ? @component.native_type.ffi_kind : @component.ffi_kind
      end

      def [](index)
        if AbstractMemory.op?(@kind)
          value = @memory.ffi_get(@kind, ffi_offset(FFI.int_value(index)))
          @component.ffi_kind == :MAPPED ? @component.converter.__send__(:from_native, value, nil) : value
        elsif @component.ffi_kind == :STRUCT
          pointer = @memory.slice(ffi_offset(FFI.int_value(index)), @component.ffi_type.size)
          struct = Class.instance_method(:allocate).bind_call(@component.struct_class)
          struct.__send__(:initialize, pointer)
          struct
        else
          raise ArgumentError, "get not supported for #{Primitive.zr_class_path(Primitive.zr_real_class(@component))}"
        end
      end

      def []=(index, value)
        Primitive.zr_frozen_error(self) if frozen?

        if AbstractMemory.op?(@kind)
          value = @component.converter.__send__(:to_native, value, nil) if @component.ffi_kind == :MAPPED
          @memory.ffi_put(@kind, ffi_offset(FFI.int_value(index)), value)
        elsif @component.ffi_kind == :STRUCT
          offset = ffi_offset(FFI.int_value(index))
          raise TypeError, "argument not an instance of struct" unless value.is_a?(FFI::Struct)

          size = @component.ffi_type.size
          @memory.ffi_check_write
          @memory.ffi_check_bounds(offset, size)
          source = value.__send__(:ffi_pointer)
          source.ffi_check_read
          source.ffi_check_bounds(0, size)
          Primitive.zr_ffi_copy(@memory.ffi_address + offset, source.ffi_address, size)
        else
          raise ArgumentError, "set not supported for #{Primitive.zr_class_path(Primitive.zr_real_class(@component))}"
        end
        value
      end

      def each
        @array.length.times { |i| yield self[i] }
        self
      end

      def size = @field.type.length

      def to_a = ::Array.new(@array.length) { |i| self[i] }

      def to_ptr = @memory.slice(@field.offset, @array.ffi_type.size)

      private

      # inline_array_offset.
      def ffi_offset(index)
        Primitive.attr! :hidden
        raise IndexError, "index #{index} out of bounds" if index.negative? || (index >= @array.length && @array.length.positive?)

        @field.offset + index * @component.ffi_type.size
      end
    end
  end

  class StructLayout
    class CharArray < Struct::InlineArray
      def to_s
        return super unless %i[INT8 UINT8].include?(@component.ffi_kind)

        @memory.get_string(@field.offset, @array.length)
      end

      alias to_str to_s
    end
  end
end
