# frozen_string_literal: true

# Derived from the C part of the rbs gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.

module RBS
  class Parser
    # src/serialize.c: an AST in the binary form that the gem's WebAssembly
    # build gives, and its RBS::WASM::Deserializer reads back. This is that
    # reader's inverse, over the same schema (rbs/wasm/serialization_schema,
    # which config.yml generates beside serialize.c).
    #
    # The C serializes its own nodes, which keep what the AST objects do
    # not: the spelling of an integer, and the bytes of a symbol that is no
    # valid text. A parse for bytes keeps them as Raw values (Engine's
    # `bytes` mode).
    class Serializer
      # Bytes that the AST keeps as they are: a symbol's, or an integer's
      # spelling.
      Raw = Struct.new(:tag, :bytes)

      SYMBOL = 79
      BOOL = 2
      INTEGER = 17
      STRING = 46
      RECORD_FIELD = 74
      NAMESPACE = 49
      SIGNATURE = 50
      TYPE_NAME = 51

      def self.schema
        @schema ||= begin
          require "rbs/wasm/serialization_schema"
          WASM::SerializationSchema::SCHEMA.each_with_index.filter_map { |entry, tag| [entry[1], [tag, entry]] if entry&.first == :node }.to_h
        end
      end

      def initialize
        @out = "".b
        @schema = Serializer.schema
      end

      # rbs_serialize_node of a signature: its directives and declarations.
      def signature((directives, declarations))
        u8(SIGNATURE)
        list(directives)
        list(declarations)
        @out
      end

      def node(value)
        write(value)
        @out
      end

      private

      def write(value)
        case value
        when nil then u8(0)
        when Symbol then tagged(SYMBOL, value.name.b)
        when Raw then tagged(value.tag, value.bytes)
        when true, false
          u8(BOOL)
          u8(value ? 1 : 0)
        when Integer then tagged(INTEGER, value.to_s)
        when String then tagged(STRING, value.b)
        when RBS::Namespace
          u8(NAMESPACE)
          list(value.path)
          u8(value.absolute? ? 1 : 0)
        when RBS::TypeName
          u8(TYPE_NAME)
          write(value.namespace)
          write(value.name)
        else ast(value)
        end
      end

      def ast(value)
        tag, (_, _, expose_location, children, fields) = @schema.fetch(value.class.name)
        u8(tag)
        location(value.location, children) if expose_location
        fields&.each { |name, reader| field(field_value(value, name), reader) }
      end

      # The value of a schema field: the instance variable of its name,
      # but for the two that the AST keeps under another.
      def field_value(node, name)
        case node
        when RBS::AST::TypeParam
          return node.upper_bound_type if name == :upper_bound
          return node.lower_bound_type if name == :lower_bound
        when RBS::Types::Bases::Any
          return node.instance_variable_get(:@string) == "__todo__" if name == :todo
        end
        node.instance_variable_get(:"@#{name}")
      end

      def field(value, reader)
        case reader
        when :node then write(value)
        when :node_list then list(value)
        when :hash then hash(value)
        when :string then string(value.b)
        when :bool then u8(value ? 1 : 0)
        when :location_range then range(value && [value._start_pos, value._end_pos])
        when :location_range_list
          u32(value.size)
          value.each { range(it && [it._start_pos, it._end_pos]) }
        when :attr_ivar_name then ivar_name(value)
        else u8(reader[1].index(value))
        end
      end

      # The node's range, and each child's as the schema lists them.
      def location(location, children)
        range(location && [location._start_pos, location._end_pos])
        children&.each do |name, _|
          child = location && location[name]
          range(child && [child._start_pos, child._end_pos])
        end
      end

      def range(range)
        if range.nil? || range[0] == -1
          u8(0)
        else
          u8(1)
          @out << [range[0], range[1]].pack("l<l<")
        end
      end

      def list(nodes)
        u32(nodes.size)
        nodes.each { write(it) }
      end

      # A Hash of keywords to parameters, or of record keys to their
      # `[type, required]` pairs.
      def hash(hash)
        u32(hash.size)
        hash.each do |key, value|
          write(key)
          if value.is_a?(Array)
            u8(RECORD_FIELD)
            write(value[0])
            u8(value[1] ? 1 : 0)
          else
            write(value)
          end
        end
      end

      def ivar_name(value)
        case value
        when nil then u8(0)
        when false then u8(1)
        else tagged(2, value.is_a?(Raw) ? value.bytes : value.name.b)
        end
      end

      def tagged(tag, bytes)
        u8(tag)
        string(bytes)
      end

      def u8(byte) = @out << byte
      def u32(value) = @out << [value].pack("L<")

      def string(bytes)
        u32(bytes.bytesize)
        @out << bytes
      end
    end
    private_constant :Serializer
  end
end
