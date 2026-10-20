# frozen_string_literal: true
# shareable_constant_value: literal

# Derived from prism's C (MIT); see THIRD_PARTY_NOTICES.md.

using Prism::Ruby::Mutation

module Prism
  module Ruby
    # static_literals.c: the literal hash keys and `when` values seen so far,
    # to warn about duplicates. Each kind of literal has its own table; the
    # tables keep the C's murmur hash, size and linear probing, which decide
    # the order the nodes compare in.
    class StaticLiterals
      # pm_node_hash_t
      class Table
        def initialize(hash, compare)
          @hash = hash
          @compare = compare
          @nodes = []
          @size = 0
          @capacity = 0
        end

        # pm_node_hash_insert: the node already there that equals `node`, or
        # nil; with `replace` the new node takes its slot.
        def insert(node, replace)
          if @size * 2 >= @capacity
            capacity = @capacity.zero? ? 4 : @capacity * 2
            mask = capacity - 1
            nodes = Array.new(capacity)
            @nodes.each do |existing|
              next if existing.nil?

              index = @hash.(existing) & mask
              index = (index + 1) & mask until nodes[index].nil?
              nodes[index] = existing
            end
            @nodes = nodes
            @capacity = capacity
          end

          mask = @capacity - 1
          index = @hash.(node) & mask
          until @nodes[index].nil?
            break if @compare.(@nodes[index], node).zero?

            index = (index + 1) & mask
          end

          result = @nodes[index]
          if result.nil?
            @size += 1
            @nodes[index] = node
          elsif replace
            @nodes[index] = node
          end
          result
        end
      end

      # `parser` supplies the C's node_hash and comparisons.
      def initialize(parser)
        hash = parser.method(:static_literal_hash)
        @integers = Table.new(hash, parser.method(:compare_integer_nodes))
        @floats = Table.new(hash, parser.method(:compare_float_nodes))
        @numbers = Table.new(hash, parser.method(:compare_number_nodes))
        @strings = Table.new(hash, parser.method(:compare_string_nodes))
        @regexps = Table.new(hash, parser.method(:compare_regular_expression_nodes))
        @symbols = Table.new(hash, parser.method(:compare_string_nodes))
        @singletons = {}
      end

      # pm_static_literals_add: the earlier equal literal, or nil.
      def add(node, replace)
        case node
        when IntegerNode, SourceLineNode then @integers.insert(node, replace)
        when FloatNode then @floats.insert(node, replace)
        when RationalNode, ImaginaryNode then @numbers.insert(node, replace)
        when StringNode, SourceFileNode then @strings.insert(node, replace)
        when RegularExpressionNode then @regexps.insert(node, replace)
        when SymbolNode then @symbols.insert(node, replace)
        when TrueNode, FalseNode, NilNode, SourceEncodingNode
          duplicated = @singletons[node.class]
          @singletons[node.class] = node if duplicated.nil? || replace
          duplicated
        end
      end
    end

    class Parser
      # pm_node_type_t numbers, which the hashes and comparisons mix in.
      NODE_TYPE_NUMBERS = Dump::NODE_TYPES

      private

      # node_hash
      def static_literal_hash(node)
        case node
        when IntegerNode then integer_hash(node.value, negative_zero?(node))
        when SourceLineNode then murmur_hash([newline_line(node.start_offset, @start_line)].pack("l"))
        when FloatNode then murmur_hash([node.value].pack("d"))
        when RationalNode
          integer_hash(node.numerator, false) ^ integer_hash(node.denominator, false) ^
            murmur_scramble(NODE_TYPE_NUMBERS.fetch(:rational_node))
        when ImaginaryNode
          static_literal_hash(node.numeric) ^ murmur_scramble(NODE_TYPE_NUMBERS.fetch(:imaginary_node))
        when StringNode, SymbolNode then murmur_hash(node.unescaped) ^ murmur_scramble(static_literal_encoding_flags(node))
        when SourceFileNode then murmur_hash(node.filepath)
        when RegularExpressionNode then murmur_hash(node.unescaped) ^ murmur_scramble(node.flags)
        end
      end

      # pm_compare_integer_nodes
      def compare_integer_nodes(left, right)
        if left.is_a?(SourceLineNode) || right.is_a?(SourceLineNode)
          return int64_value(left) <=> int64_value(right)
        end

        integer_compare(left.value, negative_zero?(left), right.value, negative_zero?(right))
      end

      # pm_compare_float_nodes, where NaN compares equal.
      def compare_float_nodes(left, right) = (left.value <=> right.value) || 0

      # pm_compare_number_nodes
      def compare_number_nodes(left, right)
        left_type = NODE_TYPE_NUMBERS.fetch(left.type)
        right_type = NODE_TYPE_NUMBERS.fetch(right.type)
        return left_type <=> right_type if left_type != right_type

        case left
        when ImaginaryNode then compare_number_nodes(left.numeric, right.numeric)
        when RationalNode
          result = left.denominator <=> right.denominator
          result.zero? ? left.numerator <=> right.numerator : result
        when IntegerNode then compare_integer_nodes(left, right)
        when FloatNode then compare_float_nodes(left, right)
        end
      end

      # node_encoding_flags: the flags that decide a string's encoding. A
      # `\u` escape forces UTF-8 also in a UTF-8 source, where it makes the
      # same string as the character itself, so there it does not count.
      def static_literal_encoding_flags(node)
        utf8 = @encoding == Encodings::UTF_8
        case node
        when StringNode
          mask = StringFlags::FORCED_BINARY_ENCODING
          mask |= StringFlags::FORCED_UTF8_ENCODING unless utf8
          node.flags & mask
        when SymbolNode
          mask = SymbolFlags::FORCED_BINARY_ENCODING | SymbolFlags::FORCED_US_ASCII_ENCODING
          mask |= SymbolFlags::FORCED_UTF8_ENCODING unless utf8
          node.flags & mask
        else
          # __FILE__ resolves the same way each time in a parse.
          0
        end
      end

      # pm_string_compare: by length, then bytes.
      def static_literal_bytes_compare(left, right)
        return left.bytesize <=> right.bytesize if left.bytesize != right.bytesize

        left.b <=> right.b
      end

      # pm_compare_string_nodes: the bytes, then the encoding flags, since
      # equal bytes of another encoding are another string.
      def compare_string_nodes(left, right)
        result = static_literal_bytes_compare(static_literal_string(left), static_literal_string(right))
        result.zero? ? static_literal_encoding_flags(left) <=> static_literal_encoding_flags(right) : result
      end

      # pm_compare_regular_expression_nodes
      def compare_regular_expression_nodes(left, right)
        result = static_literal_bytes_compare(left.unescaped, right.unescaped)
        result.zero? ? left.flags <=> right.flags : result
      end

      # pm_string_value
      def static_literal_string(node) = node.is_a?(SourceFileNode) ? node.filepath : node.unescaped

      # murmur_scramble
      def murmur_scramble(value)
        value = (value * 0xcc9e2d51) & 0xFFFF_FFFF
        value = ((value << 15) | (value >> 17)) & 0xFFFF_FFFF
        (value * 0x1b873593) & 0xFFFF_FFFF
      end

      # murmur_hash over the bytes of `key`.
      def murmur_hash(key)
        hash = 0x9747b28c
        length = key.bytesize
        full = length >> 2

        key.unpack("L<#{full}").each do |segment|
          hash ^= murmur_scramble(segment)
          hash = ((hash << 13) | (hash >> 19)) & 0xFFFF_FFFF
          hash = (hash * 5 + 0xe6546b64) & 0xFFFF_FFFF
        end

        segment = 0
        (length & 3).downto(1) { |index| segment = ((segment << 8) | key.getbyte(full * 4 + index - 1)) & 0xFFFF_FFFF }

        hash ^= murmur_scramble(segment)
        hash ^= length & 0xFFFF_FFFF
        hash ^= hash >> 16
        hash = (hash * 0x85ebca6b) & 0xFFFF_FFFF
        hash ^= hash >> 13
        hash = (hash * 0xc2b2ae35) & 0xFFFF_FFFF
        hash ^ (hash >> 16)
      end

      # integer_hash over pm_integer_t's words: one 32-bit value, or the
      # magnitude's 32-bit words past that, least significant first.
      def integer_hash(value, negative_zero)
        magnitude = value.abs
        words = []
        loop do
          words << (magnitude & 0xFFFF_FFFF)
          magnitude >>= 32
          break if magnitude.zero?
        end

        hash = murmur_hash(words.pack("L<*"))
        hash ^= murmur_scramble(1) if value.negative? || negative_zero
        hash
      end

      # pm_integer_compare, with a negated zero below zero.
      def integer_compare(left, left_negative_zero, right, right_negative_zero)
        left_negative = left.negative? || left_negative_zero
        right_negative = right.negative? || right_negative_zero
        return left_negative ? -1 : 1 if left_negative != right_negative

        result = left.abs <=> right.abs
        left_negative ? -result : result
      end

      # pm_int64_value
      def int64_value(node)
        case node
        when IntegerNode
          negative = node.value.negative? || negative_zero?(node)
          return negative ? -(2**63) : 2**63 - 1 if node.value.abs > 0xFFFF_FFFF

          negative ? -node.value.abs : node.value.abs
        when SourceLineNode
          newline_line(node.start_offset, @start_line)
        end
      end

      # Whether an integer node contains a negated zero (`-0`).
      def negative_zero?(node) = @negative_zeros.include?(node.node_id)

      # pm_hash_key_static_literals_add: a warning when a literal key repeats,
      # at the earlier key.
      def hash_key_static_literals_add(literals, node)
        duplicated = literals.add(node, true)
        hash_key_duplicated_warn(duplicated, node) if duplicated
      end

      # pm_hash_key_duplicated_warn
      def hash_key_duplicated_warn(duplicated, node)
        warn_node(duplicated, :duplicated_hash_key, static_literal_inspect(duplicated), newline_line(node.start_offset, @start_line))
      end

      # pm_hash_key_static_literals_merge: the keys of a hash literal
      # splatted with `**` join the outer hash's, as if written in place. A
      # pair that is all inside the splatted hash (from `boundary` on) was
      # warned about already.
      def hash_key_static_literals_merge(literals, hash, boundary)
        hash.elements.each do |element|
          case element
          when AssocNode
            duplicated = literals.add(element.key, true)
            hash_key_duplicated_warn(duplicated, element.key) if duplicated && duplicated.start_offset < boundary
          when AssocSplatNode
            hash_key_static_literals_merge(literals, element.value, boundary) if element.value.is_a?(HashNode)
          end
        end
      end

      # pm_when_clause_static_literals_add
      def when_clause_static_literals_add(literals, node)
        previous = literals.add(node, false)
        return if previous.nil?

        warn_node(node, :duplicated_when_clause, newline_line(node.start_offset, @start_line),
                  newline_line(previous.start_offset, @start_line))
      end

      # pm_static_literal_inspect: the literal as Ruby would show it.
      def static_literal_inspect(node)
        case node
        when FalseNode then "false"
        when FloatNode
          value = node.value
          sign = @source.getbyte(node.start_offset) == 0x2D ? "-" : ""
          if value.infinite?
            "#{sign}Infinity"
          elsif value.zero?
            "#{sign}0.0"
          else
            text = format("%g", value)
            unless text.include?(".")
              exponent = text.index("e") || text.size
              text = text.dup.insert(exponent, ".0")
            end
            text
          end
        when ImaginaryNode
          numeric = node.numeric
          "(0#{"+" if static_literal_positive?(numeric)}#{static_literal_inspect(numeric)}#{"*" if numeric.is_a?(RationalNode)}i)"
        when IntegerNode then "#{"-" if negative_zero?(node)}#{node.value}"
        when NilNode then "nil"
        when RationalNode then "(#{node.numerator}/#{node.denominator})"
        when RegularExpressionNode
          options = +""
          options << "m" if node.flag?(RegularExpressionFlags::MULTI_LINE)
          options << "i" if node.flag?(RegularExpressionFlags::IGNORE_CASE)
          options << "x" if node.flag?(RegularExpressionFlags::EXTENDED)
          options << "n" if node.flag?(RegularExpressionFlags::ASCII_8BIT)
          "/#{escape_ruby(node.unescaped)}/#{options}"
        when SourceEncodingNode then "#<Encoding:#{@encoding.name}>"
        when SourceFileNode then "\"#{escape_ruby(node.filepath)}\""
        when SourceLineNode then newline_line(node.start_offset, @start_line).to_s
        when StringNode then "\"#{escape_ruby(node.unescaped)}\""
        when SymbolNode then ":#{escape_ruby(node.unescaped)}"
        when TrueNode then "true"
        end.b
      end

      # pm_static_literal_positive_p
      def static_literal_positive?(node)
        case node
        when FloatNode then node.value > 0
        when IntegerNode then !node.value.negative? && !negative_zero?(node)
        when RationalNode then !node.numerator.negative?
        when ImaginaryNode then static_literal_positive?(node.numeric)
        end
      end

      # The escapes pm_buffer_append_source writes with Ruby escaping.
      RUBY_ESCAPES = { 0x07 => "\\a", 0x08 => "\\b", 0x09 => "\\t", 0x0A => "\\n", 0x0B => "\\v", 0x0C => "\\f",
                       0x0D => "\\r", 0x22 => "\\\"", 0x5C => "\\\\" }.freeze

      # pm_buffer_append_source with PM_BUFFER_ESCAPING_RUBY
      def escape_ruby(bytes)
        bytes = bytes.b
        escaped = "".b
        bytes.each_byte.with_index do |byte, index|
          if byte <= 0x06 || (byte >= 0x0E && byte <= 0x1F) || byte >= 0x7F
            escaped << format("\\x%02X", byte)
          elsif (escape = RUBY_ESCAPES[byte])
            escaped << escape
          elsif byte == 0x23 && [0x7B, 0x40, 0x24].include?(bytes.getbyte(index + 1))
            escaped << "\\#"
          else
            escaped << byte
          end
        end
        escaped
      end
    end
  end
end
