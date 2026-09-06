# frozen_string_literal: true

module Ze0
  # `class X < FFI::Struct` with a `layout`, as ruby source.
  #
  # `layout` is not a method any runtime carries: the field offsets are C
  # facts a compile works out, and the accessors are generated from them.
  # zeo's own tier does the same walk and writes the same source
  # (`crates/zeo/src/lower/ffi/synth.rs`), so a struct answers the same on
  # either road; this is the front end's half of it.
  #
  # A field shape outside the table -- an enum, a callback, a nested
  # struct, an inline array -- is refused by name rather than guessed at:
  # a wrong width silently moves every field after it.
  module Ffi
    # The scalar keywords the gem spells, each with its C width and the
    # `FFI::Pointer` accessor pair that reads and writes it. Alignment is
    # the width for every one of them.
    SCALARS = {
      "char" => [1, "int8"], "int8" => [1, "int8"],
      "uchar" => [1, "uint8"], "uint8" => [1, "uint8"],
      "short" => [2, "int16"], "int16" => [2, "int16"],
      "ushort" => [2, "uint16"], "uint16" => [2, "uint16"],
      "int" => [4, "int32"], "int32" => [4, "int32"],
      "uint" => [4, "uint32"], "uint32" => [4, "uint32"],
      "long_long" => [8, "int64"], "int64" => [8, "int64"],
      "ulong_long" => [8, "uint64"], "uint64" => [8, "uint64"],
      # LP64: `long` and `size_t` are eight bytes on every target zeo emits
      # for, and the gem marshals them through their own converters.
      "long" => [8, "long"], "ssize_t" => [8, "long"],
      "ulong" => [8, "ulong"], "size_t" => [8, "ulong"],
      "float" => [4, "float32"], "double" => [8, "float64"],
      "bool" => [1, "int8"],
      "string" => [8, "pointer"], "pointer" => [8, "pointer"],
      "buffer_in" => [8, "pointer"], "buffer_out" => [8, "pointer"],
      "buffer_inout" => [8, "pointer"],
    }.freeze

    # The superclasses whose body a `layout` describes. A union lays every
    # field at offset zero and is as wide as its widest.
    STRUCT = "FFI::Struct"
    UNION = "FFI::Union"

    # `[name, keyword]` for each field the call declares, or nil where the
    # shape is one this walk does not read. Both spellings the gem takes:
    # `layout :x, :int, :y, :int` and `layout x: :int, y: :int`.
    def self.declared_fields(node, nested = {})
      args = node.arguments&.arguments || []
      return nil if args.empty?

      return hash_fields(args[0], nested) if args.size == 1 && args[0].is_a?(Prism::KeywordHashNode)
      return nil unless args.size.even?

      pairs = []
      args.each_slice(2) do |name, type|
        return nil unless name.is_a?(Prism::SymbolNode)

        field = field_of(type, nested)
        return nil if field.nil?

        pairs << [name.unescaped, field]
      end
      pairs
    end

    # A field's type: a scalar keyword, `[keyword, count]` -- an INLINE
    # array, which occupies its elements in place and so is what decides
    # where the next field starts -- or the name of a struct class stored
    # BY VALUE, whose own layout says how wide it is.
    def self.field_of(node, nested = {})
      return [node.unescaped, nil] if scalar?(node)

      if node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
        found = nested[node.slice]
        return found && [node.slice, nil, found[0], found[1]]
      end
      return nil unless node.is_a?(Prism::ArrayNode) && node.elements.size == 2

      elem, count = node.elements
      return nil unless scalar?(elem) && count.is_a?(Prism::IntegerNode)

      [elem.unescaped, count.value]
    end

    def self.hash_fields(node, nested = {})
      pairs = []
      node.elements.each do |e|
        return nil unless e.is_a?(Prism::AssocNode)
        return nil unless e.key.is_a?(Prism::SymbolNode)

        field = field_of(e.value, nested)
        return nil if field.nil?

        pairs << [e.key.unescaped, field]
      end
      pairs
    end

    def self.scalar?(node)
      node.is_a?(Prism::SymbolNode) && SCALARS.key?(node.unescaped)
    end

    # Where C puts each field: at the next offset its own width divides,
    # and the struct is as wide as its widest field divides.
    def self.place(pairs, union)
      offset = 0
      widest = 1
      placed = pairs.map do |name, (keyword, count, struct_size, struct_align)|
        # A nested struct's width and alignment are its OWN layout's.
        esize, accessor = struct_size ? [struct_align, nil] : SCALARS.fetch(keyword)
        size = struct_size
        # An inline array aligns to ONE element and occupies all of them.
        size ||= count ? esize * count : esize
        widest = esize if esize > widest
        at = union ? 0 : (offset + esize - 1) / esize * esize
        offset = union ? [offset, size].max : at + size
        [name, keyword, accessor, at, count, esize, struct_size]
      end
      [placed, (offset + widest - 1) / widest * widest, widest]
    end

    # The class body zeo would have compiled, as source. Written out
    # rather than built at run time because a field's offset is settled
    # here and the accessor is only ever that one load.
    def self.source(placed, total, alignment)
      reads = placed.map { |f| read_arm(*f) }
      writes = placed.map { |f| write_arm(*f) }
      offsets = placed.map { |name, _, _, at| "        when :#{name} then #{at}\n" }
      members = placed.map { |f| ":#{f[0]}" }.join(", ")
      pairs = placed.map { |name, _, _, at| "[:#{name}, #{at}]" }.join(", ")
      <<~SOURCE
        def initialize(__ffi_ptr = nil)
          @__ffi_ptr = __ffi_ptr || FFI::MemoryPointer.new(#{total})
        end
        def [](__ffi_field)
          case __ffi_field
        #{reads.join}      else raise ArgumentError, "no such struct field \#{__ffi_field.inspect}"
          end
        end
        def []=(__ffi_field, __ffi_value)
          case __ffi_field
        #{writes.join}      else raise ArgumentError, "no such struct field \#{__ffi_field.inspect}"
          end
          __ffi_value
        end
        def pointer = @__ffi_ptr
        def to_ptr = @__ffi_ptr
        def self.size = #{total}
        def self.alignment = #{alignment}
        def self.offset_of(__ffi_field)
          case __ffi_field
        #{offsets.join}      else raise ArgumentError, "no such struct field \#{__ffi_field.inspect}"
          end
        end
        def self.by_value = ::FFI::StructByValue.new(self)
        def self.members = [#{members}]
        def self.offsets = [#{pairs}]
        def offsets = self.class.offsets
      SOURCE
    end

    # The synthesized source as statements. It is ruby a compile wrote,
    # so a parse error here is this compiler's bug and not the program's.
    def self.parse(source, node)
      result = Prism.parse(source, filepath: "<ffi layout>")
      raise Unsupported.new(node, "a `layout` this compile cannot write") unless result.errors.empty?

      result.value.statements.body
    end

    # A `:string` field is a `char *`, so the read follows the pointer; a
    # `:bool` is one byte that is not the number it stores.
    def self.read_arm(name, keyword, accessor, at, count = nil, esize = nil, struct = nil)
      # A nested struct reads back as its class VIEWING the field's bytes
      # in place, so a write through the view writes the parent.
      return "        when :#{name} then #{keyword}.new(@__ffi_ptr + #{at})\n" if struct

      # An inline array reads back as a PROXY over the same bytes, never a
      # copy: writing through it writes the struct. The 8-bit one is the
      # proxy that also answers `to_s`, as the gem has it.
      if count
        klass = esize == 1 ? "FFI::StructLayout::CharArray" : "FFI::Struct::InlineArray"
        return "        when :#{name} then #{klass}.new(@__ffi_ptr, #{at}, #{count}, " \
               ":get_#{accessor}, :put_#{accessor}, #{esize})\n"
      end

      read = "@__ffi_ptr.get_#{accessor}(#{at})"
      read = "(__zeo_p = #{read}; __zeo_p.null? ? nil : __zeo_p.read_string)" if keyword == "string"
      read = "#{read} != 0" if keyword == "bool"
      "        when :#{name} then #{read}\n"
    end

    # ruby refuses a `:string` write: storing the pointer would leave the
    # bytes for nobody to keep alive.
    def self.write_arm(name, keyword, accessor, at, count = nil, _esize = nil, struct = nil)
      # A nested struct write COPIES the value's bytes over the field.
      if struct
        return "        when :#{name} then @__ffi_ptr.put_bytes(#{at}, " \
               "__ffi_value.to_ptr.get_bytes(0, #{struct}))\n"
      end

      # ruby refuses a whole-array assignment: the proxy's own `[]=` is
      # how an inline array is written.
      if count
        return "        when :#{name} then raise NotImplementedError, \"cannot set array field\"\n"
      end
      if keyword == "string"
        return "        when :#{name} then raise ArgumentError, \"Cannot set :string fields\"\n"
      end

      value = keyword == "bool" ? "(__ffi_value ? 1 : 0)" : "__ffi_value"
      "        when :#{name} then @__ffi_ptr.put_#{accessor}(#{at}, #{value})\n"
    end
  end
end
