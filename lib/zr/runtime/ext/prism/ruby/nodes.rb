# frozen_string_literal: true
# shareable_constant_value: literal

using Prism::Ruby::Mutation

module Prism
  module Ruby
    # pm_arguments_t: a call's arguments with the parentheses or brackets
    # around them and its block, as parse_arguments_list fills them in.
    Arguments = Struct.new(:opening_loc, :arguments, :closing_loc, :block, :has_forwarding)

    # prism.c's node functions: the checks on nodes, and one method per
    # pm_*_node_create and its setters. A node gets its id when it is made,
    # at the point the C's PM_NODE_INIT runs, so ids follow the C's order.
    class Parser
      # Internal flags the C keeps on nodes beside the public ones.
      WRITE_NODE_FLAGS_IMPLICIT_ARRAY = 1 << 2
      CALL_NODE_FLAGS_LAST = CallNodeFlags::IGNORE_VISIBILITY + 1
      CALL_NODE_FLAGS_IMPLICIT_ARRAY = (CALL_NODE_FLAGS_LAST - 1) << 1
      CALL_NODE_FLAGS_COMPARISON = (CALL_NODE_FLAGS_LAST - 1) << 2
      CALL_NODE_FLAGS_INDEX = (CALL_NODE_FLAGS_LAST - 1) << 3

      # PM_REGULAR_EXPRESSION_ENCODING_MASK
      REGULAR_EXPRESSION_ENCODING_MASK = ~(RegularExpressionFlags::EUC_JP | RegularExpressionFlags::ASCII_8BIT |
                                           RegularExpressionFlags::WINDOWS_31J | RegularExpressionFlags::UTF_8)

      # The keywords pm_local_is_keyword knows.
      LOCAL_KEYWORDS = %w[
        do if in or and def end for nil not case else next redo self then true when alias begin break class
        elsif false retry super undef until while yield ensure module rescue return unless __LINE__ __FILE__
        __ENCODING__
      ].to_h { |keyword| [keyword.b, true] }.freeze

      private

      # -- nodes and locations ----------------------------------------------

      # The id PM_NODE_INIT gives the next node.
      def next_node_id = @node_id += 1

      # A location packed as `(start << 32) | length`.
      def loc(start, finish) = Mutation::Location.pack(start, finish)

      def loc_start(location) = location >> 32
      def loc_end(location) = Mutation::Location.packed_end(location)

      # A location of some length: the C's `length > 0`. A missing token
      # leaves one of no length.
      def loc_present?(location) = !location.nil? && (location & 0xFFFF_FFFF) > 0

      # PM_LOCATION_NULL_VALUE
      def null_location = 0

      # -- constants --------------------------------------------------------

      # The Symbol of the constant numbered `id`, as a node stores it. A name
      # that is not valid in the source's encoding keeps its bytes.
      def constant_symbol(id)
        @constant_symbols[id] ||= begin
          bytes = @constant_pool.bytes(id).dup.force_encoding(ruby_encoding)
          bytes.valid_encoding? ? bytes.to_sym : bytes.b.to_sym
        end
      end

      # The constant id of a name in a node.
      def constant_id_of(symbol) = @constant_pool.find(symbol.name)

      # pm_parser_constant_id_token, as the node's Symbol.
      def token_name(token) = constant_symbol(constant_id_location(token.start, token.end))

      # pm_parser_optional_constant_id_token, as the node's Symbol or nil.
      def optional_token_name(token) = token.provided? ? token_name(token) : nil

      # pm_parser_constant_id_location, as the node's Symbol.
      def location_name(start, finish) = constant_symbol(constant_id_location(start, finish))

      # pm_parser_constant_id_constant, as the node's Symbol.
      def constant_name(bytes) = constant_symbol(constant_id_constant(bytes))

      # -- diagnostics on nodes and tokens ----------------------------------

      # pm_parser_err_node, PM_PARSER_ERR_NODE_FORMAT
      def err_node(node, id, *arguments) = err(node.start_offset, node.end_offset, id, *arguments)

      # pm_parser_err_token, PM_PARSER_ERR_TOKEN_FORMAT
      def err_token(token, id, *arguments) = err(token.start, token.end, id, *arguments)

      # pm_parser_warn_node, PM_PARSER_WARN_NODE_FORMAT
      def warn_node(node, id, *arguments) = warn(node.start_offset, node.end_offset, id, *arguments)

      # pm_parser_warn_token, PM_PARSER_WARN_TOKEN_FORMAT
      def warn_token(token, id, *arguments) = warn(token.start, token.end, id, *arguments)

      # PM_PARSER_ERR_NODE_FORMAT_CONTENT
      def err_node_content(node, id) = err_node(node, id, node_slice(node))

      # PM_PARSER_ERR_TOKEN_FORMAT_CONTENT
      def err_token_content(token, id) = err_token(token, id, token_slice(token))

      # PM_PARSER_WARN_TOKEN_FORMAT_CONTENT
      def warn_token_content(token, id) = warn_token(token, id, token_slice(token))

      def token_slice(token) = @source.byteslice(token.start, token.end - token.start)
      def node_slice(node) = @source.byteslice(node.start_offset, node.end_offset - node.start_offset)

      def command_line_e? = command_line?(Options::COMMAND_LINE["e"])

      # -- checks on nodes --------------------------------------------------

      # PM_CASE_VOID_VALUE
      VOID_VALUE_NODES = [ReturnNode, BreakNode, NextNode, RedoNode, RetryNode, MatchRequiredNode].freeze

      # pm_check_value_expression: the node that makes `node` no value (a
      # return, break, next, redo, retry or `=>` match on every path), or
      # nil.
      def check_value_expression(node)
        void_node = nil
        # Bug #21669: from 4.1, the check sees every branch.
        thorough = @version >= Options::VERSION_CRUBY_4_1

        until node.nil?
          case node
          when *VOID_VALUE_NODES
            return void_node || node
          when MatchPredicateNode
            return
          when BeginNode
            if node.ensure_clause
              if node.rescue_clause && (value = check_value_expression(node.rescue_clause))
                return value
              end
              if node.statements && (value = check_value_expression(node.statements))
                return value
              end

              node = node.ensure_clause
            elsif node.rescue_clause
              if node.else_clause.nil? || !thorough
                return if node.statements.nil?

                value = check_value_expression(node.statements)
                return if value.nil?

                void_node ||= value
              end

              rescue_clause = node.rescue_clause
              until rescue_clause.nil?
                if check_value_expression(rescue_clause.statements).nil?
                  return if thorough

                  void_node = nil
                  break
                end
                rescue_clause = rescue_clause.subsequent
              end

              return void_node if node.else_clause.nil?

              node = node.else_clause
              if thorough && (value = check_value_expression(node))
                return value
              end
            else
              node = node.statements
            end
          when CaseNode, CaseMatchNode
            return if !thorough || node.else_clause.nil?

            node.conditions.each do |condition|
              value = check_value_expression(condition.statements)
              return if value.nil?

              void_node ||= value
            end
            node = node.else_clause
          when EnsureNode, ElseNode
            node = node.statements
          when ParenthesesNode
            node = node.body
          when StatementsNode
            if thorough && (statement = node.body.find { |body_part| VOID_VALUE_NODES.include?(body_part.class) })
              return void_node || statement
            end

            node = node.body.last
          when IfNode
            return if node.statements.nil? || node.subsequent.nil?

            value = check_value_expression(node.statements)
            return if value.nil?

            void_node ||= value
            node = node.subsequent
          when UnlessNode
            return if node.statements.nil? || node.else_clause.nil?

            value = check_value_expression(node.statements)
            return if value.nil?

            void_node ||= value
            node = node.else_clause
          when AndNode, OrNode
            # The left operand was checked when the node was made.
            return
          when LocalVariableWriteNode
            scope = @current_scope
            node.depth.times { scope = scope.previous }
            scope.locals.read(constant_id_of(node.name))
            return
          else
            return
          end
        end
        nil
      end

      # pm_assert_value_expression
      def assert_value_expression(node)
        void_node = check_value_expression(node)
        err_node(void_node, :void_expression) if void_node
      end

      # The one- and two-byte operator names pm_void_statement_check warns
      # about.
      VOID_OPERATORS = %w[+ - * / % | ^ & > < <= >= != == +@ -@ ** <=>].to_h { |name| [name.b, true] }.freeze

      # pm_void_statement_check: a warning for a statement whose value is
      # thrown away.
      def void_statement_check(node)
        type =
          case node
          when BackReferenceReadNode, ClassVariableReadNode, GlobalVariableReadNode, InstanceVariableReadNode,
               LocalVariableReadNode, NumberedReferenceReadNode
            "a variable"
          when CallNode
            if node.call_operator_loc.nil? && loc_present?(node.message_loc)
              message = @constant_pool.bytes(constant_id_of(node.name))
              message if VOID_OPERATORS.key?(message)
            end
          when ConstantPathNode then "::"
          when ConstantReadNode then "a constant"
          when DefinedNode then "defined?"
          when FalseNode then "false"
          when FloatNode, ImaginaryNode, IntegerNode, InterpolatedRegularExpressionNode, InterpolatedStringNode,
               RationalNode, RegularExpressionNode, SourceEncodingNode, SourceFileNode, SourceLineNode, StringNode,
               SymbolNode
            "a literal"
          when NilNode then "nil"
          when RangeNode then node.flag?(RangeFlags::EXCLUDE_END) ? "..." : ".."
          when SelfNode then "self"
          when TrueNode then "true"
          end

        warn_node(node, :void_statement, type) if type
      end

      # pm_void_statements_check
      def void_statements_check(node, last_value)
        body = node.body
        (last_value ? body.size - 1 : body.size).times { |index| void_statement_check(body[index]) }
      end

      # pm_parser_warn_conditional_predicate_literal
      def warn_conditional_predicate_literal(node, type, id, prefix)
        case type
        when :conditional then warn_node(node, id, prefix, "condition")
        when :flip_flop then warn_node(node, id, prefix, "flip-flop")
        end
      end

      # pm_conditional_predicate_warn_write_literal_p
      def conditional_predicate_write_literal?(node)
        case node
        when ArrayNode
          node.flag?(NodeFlags::STATIC_LITERAL) || node.elements.all? { |element| conditional_predicate_write_literal?(element) }
        when HashNode
          node.flag?(NodeFlags::STATIC_LITERAL) ||
            node.elements.all? do |element|
              element.is_a?(AssocNode) && conditional_predicate_write_literal?(element.key) &&
                conditional_predicate_write_literal?(element.value)
            end
        when FalseNode, FloatNode, ImaginaryNode, IntegerNode, NilNode, RationalNode, RegularExpressionNode,
             SourceEncodingNode, SourceFileNode, SourceLineNode, StringNode, SymbolNode, TrueNode
          true
        else
          false
        end
      end

      # pm_conditional_predicate_warn_write_literal
      def conditional_predicate_warn_write_literal(node)
        return unless conditional_predicate_write_literal?(node)

        warn_node(node, @version <= Options::VERSION_CRUBY_3_3 ? :equal_in_conditional_3_3 : :equal_in_conditional)
      end

      # pm_conditional_predicate: in a predicate, a range is a flip-flop and
      # a regexp matches $_, and literals cause warnings. `type` is
      # :conditional, :flip_flop or :not. The C changes a node's type in
      # place; this returns the node to use in its place.
      def conditional_predicate(node, type)
        case node
        when AndNode, OrNode
          node.left = conditional_predicate(node.left, :conditional)
          node.right = conditional_predicate(node.right, :conditional)
        when ParenthesesNode
          body = node.body
          if body.is_a?(StatementsNode) && body.body.size == 1
            body.body[0] = conditional_predicate(body.body[0], type)
          end
        when BeginNode
          statements = node.statements
          if statements && statements.body.size == 1
            statements.body[0] = conditional_predicate(statements.body[0], type)
          end
        when RangeNode
          node.left = conditional_predicate(node.left, :flip_flop) if node.left
          node.right = conditional_predicate(node.right, :flip_flop) if node.right
          return retype(node, FlipFlopNode)
        when RegularExpressionNode
          node = retype(node, MatchLastLineNode)
          warn_conditional_predicate_literal(node, type, :literal_in_condition_default, "regex ") unless command_line_e?
        when InterpolatedRegularExpressionNode
          node = retype(node, InterpolatedMatchLastLineNode)
          warn_conditional_predicate_literal(node, type, :literal_in_condition_verbose, "regex ") unless command_line_e?
        when IntegerNode
          if type == :flip_flop
            warn_node(node, :integer_in_flip_flop) unless command_line_e?
          else
            warn_conditional_predicate_literal(node, type, :literal_in_condition_verbose, "")
          end
        when StringNode, SourceFileNode, InterpolatedStringNode
          warn_conditional_predicate_literal(node, type, :literal_in_condition_default, "string ")
        when SymbolNode, InterpolatedSymbolNode
          warn_conditional_predicate_literal(node, type, :literal_in_condition_verbose, "symbol ")
        when SourceLineNode, SourceEncodingNode, FloatNode, RationalNode, ImaginaryNode
          warn_conditional_predicate_literal(node, type, :literal_in_condition_verbose, "")
        when ClassVariableWriteNode, ConstantWriteNode, GlobalVariableWriteNode, InstanceVariableWriteNode,
             LocalVariableWriteNode, MultiWriteNode
          conditional_predicate_warn_write_literal(node.value)
        end
        node
      end

      # A node as another type with the same fields, as the C changes a
      # node's type in place. It keeps the node's id.
      def retype(node, type) = type.new(@node_source, node.node_id, node.location, node.flags, *node.fields)

      # pm_arguments_end
      def arguments_end(arguments)
        # A missing `)` leaves a closing location of no length.
        closing = arguments.closing_loc if loc_present?(arguments.closing_loc)
        if arguments.block
          finish = arguments.block.end_offset
          finish = loc_end(closing) if closing && loc_end(closing) > finish
          return finish
        end
        return loc_end(closing) if closing
        return arguments.arguments.end_offset if arguments.arguments
        return loc_end(arguments.opening_loc) if loc_present?(arguments.opening_loc)

        nil
      end

      # pm_arguments_validate_block: a brace block cannot attach to a call
      # whose arguments have no parentheses.
      def arguments_validate_block(arguments, block)
        return if arguments.arguments.nil? || loc_present?(arguments.closing_loc)
        return if arguments.arguments.arguments.size == 1 && arguments.arguments.arguments[0].is_a?(ParenthesesNode)

        err_node(block, :argument_unexpected_block)
      end

      # token_is_setter_name
      def token_setter_name?(token)
        token.type == :BRACKET_LEFT_RIGHT_EQUAL ||
          (token.type == :IDENTIFIER && token.end - token.start >= 2 && @source.getbyte(token.end - 1) == 0x3D)
      end

      # pm_local_is_keyword
      def local_keyword?(bytes) = LOCAL_KEYWORDS.key?(bytes)

      # pm_node_flag_set_repeated_parameter
      def flag_repeated_parameter(node) = node.flag_set(ParameterFlags::REPEATED_PARAMETER)

      # pm_regular_expression_flags_create: the flags a regexp's closing
      # token spells, with an error for letters that are no option.
      def regular_expression_flags(closing)
        flags = 0
        return flags unless closing.type == :REGEXP_END

        unknown = "".b
        ((closing.start + 1)...closing.end).each do |at|
          case (byte = @source.getbyte(at))
          when 0x69 then flags |= RegularExpressionFlags::IGNORE_CASE # i
          when 0x6D then flags |= RegularExpressionFlags::MULTI_LINE # m
          when 0x78 then flags |= RegularExpressionFlags::EXTENDED # x
          when 0x6F then flags |= RegularExpressionFlags::ONCE # o
          when 0x65 then flags = (flags & REGULAR_EXPRESSION_ENCODING_MASK) | RegularExpressionFlags::EUC_JP # e
          when 0x6E then flags = (flags & REGULAR_EXPRESSION_ENCODING_MASK) | RegularExpressionFlags::ASCII_8BIT # n
          when 0x73 then flags = (flags & REGULAR_EXPRESSION_ENCODING_MASK) | RegularExpressionFlags::WINDOWS_31J # s
          when 0x75 then flags = (flags & REGULAR_EXPRESSION_ENCODING_MASK) | RegularExpressionFlags::UTF_8 # u
          else unknown << byte
          end
        end

        unless unknown.empty?
          err(@previous_start, @previous_end, :regexp_unknown_options, unknown.bytesize >= 2 ? "options" : "option", unknown)
        end
        flags
      end

      # -- node creation ----------------------------------------------------

      # pm_error_recovery_node_create: a node that stands where the parser
      # expected one and found none.
      def error_recovery_node(start, finish) = ErrorRecoveryNode.new(@node_source, next_node_id, loc(start, finish), 0, nil)

      # pm_error_recovery_node_create_unexpected: a node that stands where
      # the parser found `unexpected`, which is not valid there.
      def error_recovery_node_unexpected(unexpected)
        ErrorRecoveryNode.new(@node_source, next_node_id, unexpected.location, 0, unexpected)
      end

      # pm_alias_global_variable_node_create
      def alias_global_variable_node(keyword, new_name, old_name)
        AliasGlobalVariableNode.new(@node_source, next_node_id, loc(keyword.start, old_name.end_offset), 0,
                                    new_name, old_name, keyword.location)
      end

      # pm_alias_method_node_create
      def alias_method_node(keyword, new_name, old_name)
        AliasMethodNode.new(@node_source, next_node_id, loc(keyword.start, old_name.end_offset), 0,
                            new_name, old_name, keyword.location)
      end

      # pm_alternation_pattern_node_create
      def alternation_pattern_node(left, right, operator)
        AlternationPatternNode.new(@node_source, next_node_id, loc(left.start_offset, right.end_offset), 0,
                                   left, right, operator.location)
      end

      # pm_and_node_create
      def and_node(left, operator, right)
        assert_value_expression(left)
        AndNode.new(@node_source, next_node_id, loc(left.start_offset, right.end_offset), 0, left, right, operator.location)
      end

      # pm_arguments_node_create
      def arguments_node = ArgumentsNode.new(@node_source, next_node_id, null_location, 0, [])

      # pm_arguments_node_arguments_append
      def arguments_node_arguments_append(node, argument)
        node.start_offset_keep_length = argument.start_offset if node.arguments.empty?
        node.end_offset = argument.end_offset if node.end_offset < argument.end_offset

        node.arguments << argument

        return unless argument.is_a?(SplatNode)

        if node.flag?(ArgumentsNodeFlags::CONTAINS_SPLAT)
          node.flag_set(ArgumentsNodeFlags::CONTAINS_MULTIPLE_SPLATS)
        else
          node.flag_set(ArgumentsNodeFlags::CONTAINS_SPLAT)
        end
      end

      # pm_array_node_create
      def array_node(opening)
        ArrayNode.new(@node_source, next_node_id, opening.location, NodeFlags::STATIC_LITERAL, [],
                      opening.optional_location, opening.optional_location)
      end

      # pm_array_node_elements_append
      def array_node_elements_append(node, element)
        node.start_offset = element.start_offset if node.elements.empty? && node.opening_loc.nil?

        node.elements << element
        node.end_offset = element.end_offset

        if element.is_a?(ArrayNode) || element.is_a?(HashNode) || element.is_a?(RangeNode) || !element.flag?(NodeFlags::STATIC_LITERAL)
          node.flag_unset(NodeFlags::STATIC_LITERAL)
        end

        node.flag_set(ArrayNodeFlags::CONTAINS_SPLAT) if element.is_a?(SplatNode)
      end

      # pm_array_node_close_set
      def array_node_close_set(node, closing)
        node.end_offset = closing.end
        node.closing_loc = closing.location
      end

      # pm_array_pattern_node_node_list_create: at least two nodes, split
      # around the first splat.
      def array_pattern_node_node_list(nodes)
        node = ArrayPatternNode.new(@node_source, next_node_id, loc(nodes.first.start_offset, nodes.last.end_offset), 0,
                                    nil, [], nil, [], nil, nil)

        found_rest = false
        nodes.each do |child|
          if !found_rest && (child.is_a?(SplatNode) || child.is_a?(ImplicitRestNode))
            node.rest = child
            found_rest = true
          elsif found_rest
            node.posts << child
          else
            node.requireds << child
          end
        end
        node
      end

      # pm_array_pattern_node_rest_create
      def array_pattern_node_rest(rest)
        ArrayPatternNode.new(@node_source, next_node_id, rest.location, 0, nil, [], rest, [], nil, nil)
      end

      # pm_array_pattern_node_constant_create
      def array_pattern_node_constant(constant, opening, closing)
        ArrayPatternNode.new(@node_source, next_node_id, loc(constant.start_offset, closing.end), 0,
                             constant, [], nil, [], opening.location, closing.location)
      end

      # pm_array_pattern_node_empty_create
      def array_pattern_node_empty(opening, closing)
        ArrayPatternNode.new(@node_source, next_node_id, loc(opening.start, closing.end), 0,
                             nil, [], nil, [], opening.location, closing.location)
      end

      # pm_assoc_node_create
      def assoc_node(key, operator, value)
        finish =
          if value && value.end_offset > key.end_offset then value.end_offset
          elsif operator.provided? then operator.end
          else key.end_offset
          end

        # A string key is frozen, which also makes it a static literal.
        key.flag_set(StringFlags::FROZEN | NodeFlags::STATIC_LITERAL) if key.is_a?(StringNode)

        flags = 0
        if !container_node?(key) && value && !container_node?(value)
          flags = key.flags & value.flags & NodeFlags::STATIC_LITERAL
        end

        AssocNode.new(@node_source, next_node_id, loc(key.start_offset, finish), flags, key, value, operator.optional_location)
      end

      # An array, hash or range, which is never a static literal inside
      # another literal.
      def container_node?(node) = node.is_a?(ArrayNode) || node.is_a?(HashNode) || node.is_a?(RangeNode)

      # pm_assoc_splat_node_create
      def assoc_splat_node(value, operator)
        location = value.nil? ? operator.location : loc(operator.start, value.end_offset)
        AssocSplatNode.new(@node_source, next_node_id, location, 0, value, operator.location)
      end

      # pm_back_reference_read_node_create
      def back_reference_read_node(name)
        BackReferenceReadNode.new(@node_source, next_node_id, name.location, 0, token_name(name))
      end

      # pm_begin_node_create
      def begin_node(begin_keyword, statements)
        location = statements.nil? ? begin_keyword.location : loc(begin_keyword.start, statements.end_offset)
        BeginNode.new(@node_source, next_node_id, location, 0, begin_keyword.optional_location, statements, nil, nil, nil, nil)
      end

      # pm_begin_node_rescue_clause_set
      def begin_node_rescue_clause_set(node, rescue_clause)
        node.start_offset = rescue_clause.start_offset if node.begin_keyword_loc.nil?
        node.end_offset = rescue_clause.end_offset
        node.rescue_clause = rescue_clause
      end

      # pm_begin_node_else_clause_set
      def begin_node_else_clause_set(node, else_clause)
        node.end_offset = else_clause.end_offset
        node.else_clause = else_clause
      end

      # pm_begin_node_ensure_clause_set
      def begin_node_ensure_clause_set(node, ensure_clause)
        node.end_offset = ensure_clause.end_offset
        node.ensure_clause = ensure_clause
      end

      # pm_begin_node_end_keyword_set
      def begin_node_end_keyword_set(node, end_keyword)
        node.end_offset = end_keyword.end
        node.end_keyword_loc = end_keyword.optional_location
      end

      # pm_block_argument_node_create
      def block_argument_node(operator, expression)
        location = expression.nil? ? operator.location : loc(operator.start, expression.end_offset)
        BlockArgumentNode.new(@node_source, next_node_id, location, 0, expression, operator.location)
      end

      # pm_block_node_create
      def block_node(locals, opening, parameters, body, closing)
        BlockNode.new(@node_source, next_node_id, loc(opening.start, closing.end), 0,
                      locals, parameters, body, opening.location, closing.location)
      end

      # pm_block_parameter_node_create
      def block_parameter_node(name, operator)
        location = name.provided? ? loc(operator.start, name.end) : operator.location
        BlockParameterNode.new(@node_source, next_node_id, location, 0,
                               optional_token_name(name), name.optional_location, operator.location)
      end

      # pm_block_parameters_node_create. With neither an opening nor
      # parameters the C leaves the location unset (NULL); its start and
      # end are then nil until a block local sets them.
      def block_parameters_node(parameters, opening)
        start =
          if opening.provided? then opening.start
          elsif parameters then parameters.start_offset
          end
        finish =
          if parameters then parameters.end_offset
          elsif opening.provided? then opening.end
          end

        BlockParametersNode.new(@node_source, next_node_id, start && loc(start, finish), 0,
                                parameters, [], opening.optional_location, nil)
      end

      # pm_block_parameters_node_closing_set
      def block_parameters_node_closing_set(node, closing)
        node.end_offset = closing.end
        node.closing_loc = closing.location
      end

      # pm_block_local_variable_node_create
      def block_local_variable_node(name)
        BlockLocalVariableNode.new(@node_source, next_node_id, name.location, 0, token_name(name))
      end

      # pm_block_parameters_node_append_local
      def block_parameters_node_append_local(node, local)
        node.locals << local

        if node.location.nil?
          node.location = local.location
        else
          node.end_offset = local.end_offset
        end
      end

      # pm_break_node_create
      def break_node(keyword, arguments)
        location = arguments.nil? ? keyword.location : loc(keyword.start, arguments.end_offset)
        BreakNode.new(@node_source, next_node_id, location, 0, arguments, keyword.location)
      end

      # pm_call_node_create: a call with nothing set, for the variants to
      # fill in.
      def call_node(flags)
        CallNode.new(@node_source, next_node_id, null_location, flags, nil, nil, nil, nil, nil, nil, nil, nil, nil)
      end

      # pm_call_node_ignore_visibility_flag
      def call_node_ignore_visibility_flag(receiver)
        receiver.is_a?(SelfNode) ? CallNodeFlags::IGNORE_VISIBILITY : 0
      end

      # pm_call_node_aref_create: receiver[arguments]
      def call_node_aref(receiver, arguments)
        assert_value_expression(receiver)

        flags = call_node_ignore_visibility_flag(receiver)
        flags |= CALL_NODE_FLAGS_INDEX if arguments.block.nil? || arguments.block.is_a?(BlockArgumentNode)

        node = call_node(flags)
        node.location = loc(receiver.start_offset, arguments_end(arguments))
        node.receiver = receiver
        node.message_loc = loc(loc_start(arguments.opening_loc), loc_end(arguments.closing_loc))
        node.opening_loc = arguments.opening_loc
        node.arguments = arguments.arguments
        node.closing_loc = arguments.closing_loc
        node.block = arguments.block
        node.name = constant_name("[]")
        node
      end

      # pm_call_node_binary_create
      def call_node_binary(receiver, operator, argument, flags)
        assert_value_expression(receiver)
        assert_value_expression(argument)

        node = call_node(call_node_ignore_visibility_flag(receiver) | flags)
        node.location = loc([receiver.start_offset, argument.start_offset].min, [receiver.end_offset, argument.end_offset].max)
        node.receiver = receiver
        node.message_loc = operator.optional_location

        arguments = arguments_node
        arguments_node_arguments_append(arguments, argument)
        node.arguments = arguments

        node.name = token_name(operator)
        node
      end

      # pm_call_node_call_create: receiver.message(arguments)
      def call_node_call(receiver, operator, message, arguments)
        assert_value_expression(receiver)

        node = call_node(call_node_ignore_visibility_flag(receiver))
        node.location = loc(receiver.start_offset, arguments_end(arguments) || message.end)
        node.receiver = receiver
        node.call_operator_loc = operator.optional_location
        node.message_loc = message.optional_location
        node.opening_loc = arguments.opening_loc
        node.arguments = arguments.arguments
        node.closing_loc = arguments.closing_loc
        node.block = arguments.block

        node.flag_set(CallNodeFlags::SAFE_NAVIGATION) if operator.type == :AMPERSAND_DOT

        # `foo.~@` names ~, as the symbol does.
        node.name = location_name(message.start, operator_symbol_name_end(message))
        node
      end

      # pm_call_node_call_synthesized_create
      def call_node_call_synthesized(receiver, message, arguments)
        node = call_node(0)
        node.location = loc(0, @end)
        node.receiver = receiver
        node.arguments = arguments
        node.name = constant_name(message)
        node
      end

      # pm_call_node_fcall_create: message(arguments), which cannot be a
      # local variable.
      def call_node_fcall(message, arguments)
        node = call_node(CallNodeFlags::IGNORE_VISIBILITY)
        node.location = loc(message.start, arguments_end(arguments))
        node.message_loc = message.optional_location
        node.opening_loc = arguments.opening_loc
        node.arguments = arguments.arguments
        node.closing_loc = arguments.closing_loc
        node.block = arguments.block
        node.name = token_name(message)
        node
      end

      # pm_call_node_fcall_synthesized_create
      def call_node_fcall_synthesized(arguments, name)
        node = call_node(CallNodeFlags::IGNORE_VISIBILITY)
        node.location = null_location
        node.arguments = arguments
        node.name = name
        node
      end

      # pm_call_node_not_create
      def call_node_not(receiver, message, arguments)
        assert_value_expression(receiver)
        receiver = conditional_predicate(receiver, :not) if receiver

        node = call_node(receiver.nil? ? 0 : call_node_ignore_visibility_flag(receiver))
        finish = loc_present?(arguments.closing_loc) ? loc_end(arguments.closing_loc) : receiver.end_offset
        node.location = loc(message.start, finish)
        node.receiver = receiver
        node.message_loc = message.optional_location
        node.opening_loc = arguments.opening_loc
        node.arguments = arguments.arguments
        node.closing_loc = arguments.closing_loc
        node.name = constant_name("!")
        node
      end

      # pm_call_node_shorthand_create: receiver.(arguments)
      def call_node_shorthand(receiver, operator, arguments)
        assert_value_expression(receiver)

        node = call_node(call_node_ignore_visibility_flag(receiver))
        node.location = loc(receiver.start_offset, arguments_end(arguments))
        node.receiver = receiver
        node.call_operator_loc = operator.optional_location
        node.opening_loc = arguments.opening_loc
        node.arguments = arguments.arguments
        node.closing_loc = arguments.closing_loc
        node.block = arguments.block

        node.flag_set(CallNodeFlags::SAFE_NAVIGATION) if operator.type == :AMPERSAND_DOT

        node.name = constant_name("call")
        node
      end

      # pm_call_node_unary_create
      def call_node_unary(operator, receiver, name)
        assert_value_expression(receiver)

        node = call_node(call_node_ignore_visibility_flag(receiver))
        node.location = loc(operator.start, receiver.end_offset)
        node.receiver = receiver
        node.message_loc = operator.optional_location
        node.name = constant_name(name)
        node
      end

      # pm_call_node_variable_call_create: a name that could also have been
      # a local variable.
      def call_node_variable_call(message)
        node = call_node(CallNodeFlags::IGNORE_VISIBILITY)
        node.location = message.location
        node.message_loc = message.optional_location
        node.name = token_name(message)
        node
      end

      # pm_call_node_writable_p: whether `node` can be the target of an
      # operator write.
      def call_node_writable?(node)
        message_loc = node.message_loc
        return false unless loc_present?(message_loc)

        last = @source.getbyte(loc_end(message_loc) - 1)
        last != 0x21 && last != 0x3F && identifier_start_width(loc_start(message_loc)) != 0 &&
          node.opening_loc.nil? && node.arguments.nil? && node.block.nil?
      end

      # pm_call_write_read_name_init: the write name without its `=`.
      def call_write_read_name(write_name)
        bytes = @constant_pool.bytes(constant_id_of(write_name))
        return constant_name("") if bytes.empty?

        constant_symbol(constant_id_owned(bytes.byteslice(0, bytes.bytesize - 1)))
      end

      # pm_call_and_write_node_create
      def call_and_write_node(target, operator, value)
        CallAndWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), target.flags,
                             target.receiver, target.call_operator_loc, target.message_loc,
                             call_write_read_name(target.name), target.name, operator.location, value)
      end

      # pm_index_arguments_check: from 3.4, no keywords or block in an index.
      def index_arguments_check(arguments, block)
        return unless @version >= Options::VERSION_CRUBY_3_4

        if arguments&.flag?(ArgumentsNodeFlags::CONTAINS_KEYWORDS)
          keywords = arguments.arguments.find { |argument| argument.is_a?(KeywordHashNode) }
          err_node(keywords, :unexpected_index_keywords) if keywords
        end

        err_node(block, :unexpected_index_block) if block
      end

      # pm_index_and_write_node_create
      def index_and_write_node(target, operator, value)
        index_arguments_check(target.arguments, target.block)
        IndexAndWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), target.flags,
                              target.receiver, target.call_operator_loc, target.opening_loc, target.arguments,
                              target.closing_loc, target.block, operator.location, value)
      end

      # pm_call_operator_write_node_create
      # The binary operator is interned before the read name, as the C's
      # initializer runs first.
      def call_operator_write_node(target, operator, value)
        location = loc(target.start_offset, value.end_offset)
        id = next_node_id
        binary_operator = location_name(operator.start, operator.end - 1)
        CallOperatorWriteNode.new(@node_source, id, location, target.flags, target.receiver, target.call_operator_loc,
                                  target.message_loc, call_write_read_name(target.name), target.name, binary_operator,
                                  operator.location, value)
      end

      # pm_index_operator_write_node_create
      def index_operator_write_node(target, operator, value)
        index_arguments_check(target.arguments, target.block)
        IndexOperatorWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), target.flags,
                                   target.receiver, target.call_operator_loc, target.opening_loc, target.arguments,
                                   target.closing_loc, target.block, location_name(operator.start, operator.end - 1),
                                   operator.location, value)
      end

      # pm_call_or_write_node_create
      def call_or_write_node(target, operator, value)
        CallOrWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), target.flags,
                            target.receiver, target.call_operator_loc, target.message_loc,
                            call_write_read_name(target.name), target.name, operator.location, value)
      end

      # pm_index_or_write_node_create
      def index_or_write_node(target, operator, value)
        index_arguments_check(target.arguments, target.block)
        IndexOrWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), target.flags,
                             target.receiver, target.call_operator_loc, target.opening_loc, target.arguments,
                             target.closing_loc, target.block, operator.location, value)
      end

      # pm_call_target_node_create. A call operator missing after an error
      # gets an empty location, as the location is required.
      def call_target_node(target)
        call_operator_loc = target.call_operator_loc || loc(target.start_offset, target.start_offset)
        CallTargetNode.new(@node_source, next_node_id, target.location, target.flags,
                           target.receiver, call_operator_loc, target.name, target.message_loc)
      end

      # pm_index_target_node_create
      def index_target_node(target)
        index_arguments_check(target.arguments, target.block)
        IndexTargetNode.new(@node_source, next_node_id, target.location, target.flags | CallNodeFlags::ATTRIBUTE_WRITE,
                            target.receiver, target.opening_loc, target.arguments, target.closing_loc, target.block)
      end

      # pm_capture_pattern_node_create
      def capture_pattern_node(value, target, operator)
        CapturePatternNode.new(@node_source, next_node_id, loc(value.start_offset, target.end_offset), 0,
                               value, target, operator.location)
      end

      # pm_case_node_create
      def case_node(case_keyword, predicate, end_keyword)
        CaseNode.new(@node_source, next_node_id, loc(case_keyword.start, end_keyword.end), 0,
                     predicate, [], nil, case_keyword.location, end_keyword.location)
      end

      # pm_case_node_condition_append, pm_case_match_node_condition_append
      def case_node_condition_append(node, condition)
        node.conditions << condition
        node.end_offset = condition.end_offset
      end

      # pm_case_node_else_clause_set, pm_case_match_node_else_clause_set
      def case_node_else_clause_set(node, else_clause)
        node.else_clause = else_clause
        node.end_offset = else_clause.end_offset
      end

      # pm_case_node_end_keyword_loc_set, pm_case_match_node_end_keyword_loc_set
      def case_node_end_keyword_loc_set(node, end_keyword)
        node.end_offset = end_keyword.end
        node.end_keyword_loc = end_keyword.location
      end

      # pm_case_match_node_create
      def case_match_node(case_keyword, predicate, end_keyword)
        CaseMatchNode.new(@node_source, next_node_id, loc(case_keyword.start, end_keyword.end), 0,
                          predicate, [], nil, case_keyword.location, end_keyword.location)
      end

      # pm_class_node_create
      def class_node(locals, class_keyword, constant_path, name, inheritance_operator, superclass, body, end_keyword)
        location = loc(class_keyword.start, end_keyword.end)
        id = next_node_id
        ClassNode.new(@node_source, id, location, 0, locals, class_keyword.location, constant_path,
                      inheritance_operator.optional_location, superclass, body, end_keyword.location, token_name(name))
      end

      # pm_class_variable_and_write_node_create
      def class_variable_and_write_node(target, operator, value)
        ClassVariableAndWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                      target.name, target.location, operator.location, value)
      end

      # pm_class_variable_operator_write_node_create
      def class_variable_operator_write_node(target, operator, value)
        ClassVariableOperatorWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                           target.name, target.location, operator.location, value,
                                           location_name(operator.start, operator.end - 1))
      end

      # pm_class_variable_or_write_node_create
      def class_variable_or_write_node(target, operator, value)
        ClassVariableOrWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                     target.name, target.location, operator.location, value)
      end

      # pm_class_variable_read_node_create
      def class_variable_read_node(token)
        ClassVariableReadNode.new(@node_source, next_node_id, token.location, 0, token_name(token))
      end

      # pm_implicit_array_write_flags: `flags` when the value is an array
      # without brackets (`a = 1, 2` or `a = *b`).
      def implicit_array_write_flags(node, flags)
        node.is_a?(ArrayNode) && node.opening_loc.nil? ? flags : 0
      end

      # pm_class_variable_write_node_create
      def class_variable_write_node(read_node, operator, value)
        flags = implicit_array_write_flags(value, WRITE_NODE_FLAGS_IMPLICIT_ARRAY)
        ClassVariableWriteNode.new(@node_source, next_node_id, loc(read_node.start_offset, value.end_offset), flags,
                                   read_node.name, read_node.location, value, operator.location)
      end

      # pm_constant_path_and_write_node_create
      def constant_path_and_write_node(target, operator, value)
        ConstantPathAndWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                     target, operator.location, value)
      end

      # pm_constant_path_operator_write_node_create
      def constant_path_operator_write_node(target, operator, value)
        ConstantPathOperatorWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                          target, operator.location, value, location_name(operator.start, operator.end - 1))
      end

      # pm_constant_path_or_write_node_create
      def constant_path_or_write_node(target, operator, value)
        ConstantPathOrWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                    target, operator.location, value)
      end

      # pm_constant_path_node_create
      def constant_path_node(parent, delimiter, name_token)
        assert_value_expression(parent)

        name = name_token.type == :CONSTANT ? token_name(name_token) : nil
        start = parent.nil? ? delimiter.start : parent.start_offset
        ConstantPathNode.new(@node_source, next_node_id, loc(start, name_token.end), 0,
                             parent, name, delimiter.location, name_token.location)
      end

      # pm_constant_path_write_node_create
      def constant_path_write_node(target, operator, value)
        flags = implicit_array_write_flags(value, WRITE_NODE_FLAGS_IMPLICIT_ARRAY)
        ConstantPathWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), flags,
                                  target, operator.optional_location, value)
      end

      # pm_constant_and_write_node_create
      def constant_and_write_node(target, operator, value)
        ConstantAndWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                 target.name, target.location, operator.location, value)
      end

      # pm_constant_operator_write_node_create
      def constant_operator_write_node(target, operator, value)
        ConstantOperatorWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                      target.name, target.location, operator.location, value,
                                      location_name(operator.start, operator.end - 1))
      end

      # pm_constant_or_write_node_create
      def constant_or_write_node(target, operator, value)
        ConstantOrWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                target.name, target.location, operator.location, value)
      end

      # pm_constant_read_node_create
      def constant_read_node(name)
        ConstantReadNode.new(@node_source, next_node_id, name.location, 0, token_name(name))
      end

      # pm_constant_write_node_create
      def constant_write_node(target, operator, value)
        flags = implicit_array_write_flags(value, WRITE_NODE_FLAGS_IMPLICIT_ARRAY)
        ConstantWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), flags,
                              target.name, target.location, value, operator.optional_location)
      end

      # pm_def_node_receiver_check: no singleton methods on literals.
      def def_node_receiver_check(node)
        case node
        when BeginNode
          def_node_receiver_check(node.statements) if node.statements
        when ParenthesesNode
          def_node_receiver_check(node.body) if node.body
        when StatementsNode
          def_node_receiver_check(node.body.last)
        when ArrayNode, FloatNode, ImaginaryNode, IntegerNode, InterpolatedRegularExpressionNode, InterpolatedStringNode,
             InterpolatedSymbolNode, InterpolatedXStringNode, RationalNode, RegularExpressionNode, SourceEncodingNode,
             SourceFileNode, SourceLineNode, StringNode, SymbolNode, XStringNode
          err_node(node, :singleton_for_literals)
        end
      end

      # pm_def_node_create
      def def_node(name, name_loc, receiver, parameters, body, locals, def_keyword, operator, lparen, rparen, equal, end_keyword)
        def_node_receiver_check(receiver) if receiver

        location = end_keyword.provided? ? loc(def_keyword.start, end_keyword.end) : loc(def_keyword.start, body.end_offset)
        DefNode.new(@node_source, next_node_id, location, 0, name, name_loc.location, receiver, parameters, body, locals,
                    def_keyword.location, operator.optional_location, lparen.optional_location,
                    rparen.optional_location, equal.optional_location, end_keyword.optional_location)
      end

      # pm_defined_node_create
      def defined_node(lparen, value, rparen, keyword)
        location = rparen.provided? ? loc(keyword.start, rparen.end) : loc(keyword.start, value.end_offset)
        DefinedNode.new(@node_source, next_node_id, location, 0, lparen.optional_location, value,
                        rparen.optional_location, keyword.location)
      end

      # pm_else_node_create
      def else_node(else_keyword, statements, end_keyword)
        location =
          if !end_keyword.provided? && statements
            loc(else_keyword.start, statements.end_offset)
          else
            loc(else_keyword.start, end_keyword.end)
          end
        ElseNode.new(@node_source, next_node_id, location, 0, else_keyword.location, statements, end_keyword.optional_location)
      end

      # pm_embedded_statements_node_create
      def embedded_statements_node(opening, statements, closing)
        EmbeddedStatementsNode.new(@node_source, next_node_id, loc(opening.start, closing.end), 0,
                                   opening.location, statements, closing.location)
      end

      # pm_embedded_variable_node_create
      def embedded_variable_node(operator, variable)
        EmbeddedVariableNode.new(@node_source, next_node_id, loc(operator.start, variable.end_offset), 0,
                                 operator.location, variable)
      end

      # pm_ensure_node_create
      def ensure_node(ensure_keyword, statements, end_keyword)
        EnsureNode.new(@node_source, next_node_id, loc(ensure_keyword.start, end_keyword.end), 0,
                       ensure_keyword.location, statements, end_keyword.location)
      end

      # pm_false_node_create
      def false_node(token) = FalseNode.new(@node_source, next_node_id, token.location, NodeFlags::STATIC_LITERAL)

      # pm_find_pattern_node_create: the first node is a splat, and so is the
      # last when there are two or more.
      def find_pattern_node(nodes)
        left = nodes.first
        right = nodes.size == 1 ? error_recovery_node(left.end_offset, left.end_offset) : nodes.last

        FindPatternNode.new(@node_source, next_node_id, loc(left.start_offset, right.end_offset), 0,
                            nil, left, nodes[1...-1] || [], right, nil, nil)
      end

      # pm_double_parse: the token's value, with a warning when it is out of
      # range.
      def double_parse(token)
        length = token.end - token.start
        return 0.0 if length <= 0

        text = @source.byteslice(token.start, length).delete("_")
        value = quietly { Float(text, exception: false) }
        if value.nil?
          err_token_content(token, :float_parse)
          return 0.0
        end

        # The C shows the token's first bytes, as many as the digits
        # without underscores, at most 20.
        if value.infinite?
          shown = [text.bytesize, 20].min
          warn(token.start, token.end, :float_out_of_range, @source.byteslice(token.start, shown), text.bytesize > 20 ? "..." : "")
        end
        value
      end

      # The block's return value, without ruby's own out-of-range warning,
      # which $VERBOSE prints.
      def quietly
        verbose = $VERBOSE
        $VERBOSE = nil
        yield
      ensure
        $VERBOSE = verbose
      end

      # pm_float_node_create
      def float_node(token)
        id = next_node_id
        FloatNode.new(@node_source, id, token.location, NodeFlags::STATIC_LITERAL, double_parse(token))
      end

      # pm_float_node_imaginary_create: the numeric is made after the
      # imaginary, as the C's initializer runs in order.
      def float_node_imaginary(token)
        location = token.location
        id = next_node_id
        numeric = float_node(Token.new(:FLOAT, token.start, token.end - 1))
        ImaginaryNode.new(@node_source, id, location, NodeFlags::STATIC_LITERAL, numeric)
      end

      # pm_float_node_rational_create: the digits over a power of ten,
      # reduced when both fit in 32 bits.
      def float_node_rational(token)
        node = RationalNode.new(@node_source, next_node_id, token.location,
                                IntegerBaseFlags::DECIMAL | NodeFlags::STATIC_LITERAL, 0, 0)

        start = token.start
        finish = token.end - 1 # r
        start += 1 while start < finish && @source.getbyte(start) == 0x30 # 0.1 -> .1
        finish -= 1 while finish > start && @source.getbyte(finish - 1) == 0x30 # 1.0 -> 1.

        if finish - start == 1
          node.denominator = 1
          return node
        end

        text = @source.byteslice(start, finish - start)
        point = text.index(".")
        numerator = (text.byteslice(0, point) + text.byteslice((point + 1)..)).delete("_").to_i
        denominator = 10**text.byteslice((point + 1)..).delete("_").bytesize

        if numerator != 0 && numerator <= 0xFFFF_FFFF && denominator != 1 && denominator <= 0xFFFF_FFFF
          divisor = numerator.gcd(denominator)
          numerator /= divisor
          denominator /= divisor
        end

        node.numerator = numerator
        node.denominator = denominator
        node
      end

      # pm_float_node_rational_imaginary_create
      def float_node_rational_imaginary(token)
        location = token.location
        id = next_node_id
        numeric = float_node_rational(Token.new(:FLOAT_RATIONAL, token.start, token.end - 1))
        ImaginaryNode.new(@node_source, id, location, NodeFlags::STATIC_LITERAL, numeric)
      end

      # pm_for_node_create
      def for_node(index, collection, statements, for_keyword, in_keyword, do_keyword, end_keyword)
        ForNode.new(@node_source, next_node_id, loc(for_keyword.start, end_keyword.end), 0,
                    index, collection, statements, for_keyword.location, in_keyword.location,
                    do_keyword.optional_location, end_keyword.location)
      end

      # pm_forwarding_arguments_node_create
      def forwarding_arguments_node(token) = ForwardingArgumentsNode.new(@node_source, next_node_id, token.location, 0)

      # pm_forwarding_parameter_node_create
      def forwarding_parameter_node(token) = ForwardingParameterNode.new(@node_source, next_node_id, token.location, 0)

      # pm_forwarding_super_node_create
      def forwarding_super_node(token, arguments)
        block = arguments.block
        location = block.nil? ? token.location : loc(token.start, block.end_offset)
        ForwardingSuperNode.new(@node_source, next_node_id, location, 0, token.location, block)
      end

      # pm_hash_pattern_node_empty_create
      def hash_pattern_node_empty(opening, closing)
        HashPatternNode.new(@node_source, next_node_id, loc(opening.start, closing.end), 0,
                            nil, [], nil, opening.location, closing.location)
      end

      # pm_hash_pattern_node_node_list_create
      def hash_pattern_node_node_list(elements, rest)
        if elements.empty?
          start = rest.start_offset
          finish = rest.end_offset
        elsif rest
          start = [rest.start_offset, elements.first.start_offset].min
          finish = [rest.end_offset, elements.last.end_offset].max
        else
          start = elements.first.start_offset
          finish = elements.last.end_offset
        end

        HashPatternNode.new(@node_source, next_node_id, loc(start, finish), 0, nil, elements.dup, rest, nil, nil)
      end

      # pm_global_variable_write_name
      def global_variable_write_name(target)
        case target
        when GlobalVariableReadNode, BackReferenceReadNode then target.name
        when NumberedReferenceReadNode then location_name(target.start_offset, target.end_offset)
        end
      end

      # pm_global_variable_and_write_node_create
      def global_variable_and_write_node(target, operator, value)
        location = loc(target.start_offset, value.end_offset)
        id = next_node_id
        GlobalVariableAndWriteNode.new(@node_source, id, location, 0, global_variable_write_name(target),
                                       target.location, operator.location, value)
      end

      # pm_global_variable_operator_write_node_create
      def global_variable_operator_write_node(target, operator, value)
        location = loc(target.start_offset, value.end_offset)
        id = next_node_id
        name = global_variable_write_name(target)
        GlobalVariableOperatorWriteNode.new(@node_source, id, location, 0, name, target.location, operator.location,
                                            value, location_name(operator.start, operator.end - 1))
      end

      # pm_global_variable_or_write_node_create
      def global_variable_or_write_node(target, operator, value)
        location = loc(target.start_offset, value.end_offset)
        id = next_node_id
        GlobalVariableOrWriteNode.new(@node_source, id, location, 0, global_variable_write_name(target),
                                      target.location, operator.location, value)
      end

      # pm_global_variable_read_node_create
      def global_variable_read_node(name)
        GlobalVariableReadNode.new(@node_source, next_node_id, name.location, 0, token_name(name))
      end

      # pm_global_variable_read_node_synthesized_create
      def global_variable_read_node_synthesized(name)
        GlobalVariableReadNode.new(@node_source, next_node_id, null_location, 0, name)
      end

      # pm_global_variable_write_node_create
      def global_variable_write_node(target, operator, value)
        flags = implicit_array_write_flags(value, WRITE_NODE_FLAGS_IMPLICIT_ARRAY)
        location = loc(target.start_offset, value.end_offset)
        id = next_node_id
        GlobalVariableWriteNode.new(@node_source, id, location, flags, global_variable_write_name(target),
                                    target.location, value, operator.optional_location)
      end

      # pm_global_variable_write_node_synthesized_create
      def global_variable_write_node_synthesized(name, value)
        GlobalVariableWriteNode.new(@node_source, next_node_id, null_location, 0, name, null_location, value, null_location)
      end

      # pm_hash_node_create
      def hash_node(opening)
        HashNode.new(@node_source, next_node_id, opening.location, NodeFlags::STATIC_LITERAL, opening.location, [], null_location)
      end

      # pm_hash_node_elements_append
      def hash_node_elements_append(hash, element)
        hash.elements << element

        static_literal = element.is_a?(AssocNode) && !container_node?(element.key) &&
                         element.key.flag?(NodeFlags::STATIC_LITERAL) && element.flag?(NodeFlags::STATIC_LITERAL)
        hash.flag_unset(NodeFlags::STATIC_LITERAL) unless static_literal
      end

      # pm_hash_node_closing_loc_set
      def hash_node_closing_loc_set(hash, token)
        hash.end_offset = token.end
        hash.closing_loc = token.location
      end

      # pm_if_node_create
      def if_node(if_keyword, predicate, then_keyword, statements, subsequent, end_keyword)
        predicate = conditional_predicate(predicate, :conditional)

        finish =
          if end_keyword.provided? then end_keyword.end
          elsif subsequent then subsequent.end_offset
          elsif statements_node_body_length(statements) != 0 then statements.end_offset
          else predicate.end_offset
          end

        IfNode.new(@node_source, next_node_id, loc(if_keyword.start, finish), NodeFlags::NEWLINE,
                   if_keyword.location, predicate, then_keyword.optional_location, statements, subsequent,
                   end_keyword.optional_location)
      end

      # pm_if_node_modifier_create
      def if_node_modifier(statement, if_keyword, predicate)
        predicate = conditional_predicate(predicate, :conditional)

        statements = statements_node
        statements_node_body_append(statements, statement, true)

        IfNode.new(@node_source, next_node_id, loc(statement.start_offset, predicate.end_offset), NodeFlags::NEWLINE,
                   if_keyword.location, predicate, nil, statements, nil, nil)
      end

      # pm_if_node_ternary_create
      def if_node_ternary(predicate, qmark, true_expression, colon, false_expression)
        assert_value_expression(predicate)
        predicate = conditional_predicate(predicate, :conditional)

        if_statements = statements_node
        statements_node_body_append(if_statements, true_expression, true)

        else_statements = statements_node
        statements_node_body_append(else_statements, false_expression, true)

        subsequent = else_node(colon, else_statements, NOT_PROVIDED)

        IfNode.new(@node_source, next_node_id, loc(predicate.start_offset, false_expression.end_offset), NodeFlags::NEWLINE,
                   nil, predicate, qmark.location, if_statements, subsequent, nil)
      end

      # pm_if_node_end_keyword_loc_set, pm_else_node_end_keyword_loc_set,
      # pm_unless_node_end_keyword_loc_set
      def end_keyword_loc_set(node, keyword)
        node.end_offset = keyword.end
        node.end_keyword_loc = keyword.location
      end

      # pm_implicit_node_create
      def implicit_node(value) = ImplicitNode.new(@node_source, next_node_id, value.location, 0, value)

      # pm_implicit_rest_node_create
      def implicit_rest_node(token) = ImplicitRestNode.new(@node_source, next_node_id, token.location, 0)

      # The pm_integer_base_t of a node's base flag.
      INTEGER_BASES = {
        IntegerBaseFlags::BINARY => :binary, IntegerBaseFlags::OCTAL => :octal,
        IntegerBaseFlags::DECIMAL => :decimal, IntegerBaseFlags::HEXADECIMAL => :hexadecimal
      }

      # pm_integer_parse: the value of digits in `base` (:default, :binary,
      # :octal, :decimal, :hexadecimal or :unknown) from `start` to `finish`,
      # past the prefix and without underscores. The lexer has validated
      # them.
      def integer_parse(base, start, finish)
        start += 1 if @source.getbyte(start) == 0x2B # +

        radix = 10
        case base
        when :default
          start += 1 while @source.getbyte(start) == 0x30
        when :binary
          start += 2
          radix = 2
        when :octal
          start += 1
          start += 1 if [0x5F, 0x6F, 0x4F].include?(@source.getbyte(start)) # _ o O
          radix = 8
        when :decimal
          start += 2 if @source.getbyte(start) == 0x30 && finish - start > 1
        when :hexadecimal
          start += 2
          radix = 16
        when :unknown
          if @source.getbyte(start) == 0x30 && finish - start > 1
            case @source.getbyte(start + 1)
            when 0x5F then start += 2; radix = 8
            when 0x30..0x37 then start += 1; radix = 8
            when 0x62, 0x42 then start += 2; radix = 2
            when 0x6F, 0x4F then start += 2; radix = 8
            when 0x64, 0x44 then start += 2
            when 0x78, 0x58 then start += 2; radix = 16
            end
          end
        end

        return 0 if start >= finish

        @source.byteslice(start, finish - start).delete("_").to_i(radix)
      end

      # pm_integer_node_create
      def integer_node(base, token)
        node = IntegerNode.new(@node_source, next_node_id, token.location, base | NodeFlags::STATIC_LITERAL, 0)
        if @integer_lexed
          # The value the lexer kept, which may be the last integer lexed.
          node.value = @integer_value
          @integer_lexed = false
        else
          node.value = integer_parse(INTEGER_BASES.fetch(base), token.start, token.end)
        end
        node
      end

      # pm_integer_node_imaginary_create
      def integer_node_imaginary(base, token)
        location = token.location
        id = next_node_id
        numeric = integer_node(base, Token.new(:INTEGER, token.start, token.end - 1))
        ImaginaryNode.new(@node_source, id, location, NodeFlags::STATIC_LITERAL, numeric)
      end

      # pm_integer_node_rational_create
      def integer_node_rational(base, token)
        node = RationalNode.new(@node_source, next_node_id, token.location, base | NodeFlags::STATIC_LITERAL, 0, 1)
        node.numerator = integer_parse(INTEGER_BASES.fetch(base), token.start, token.end - 1)
        node
      end

      # pm_integer_node_rational_imaginary_create
      def integer_node_rational_imaginary(base, token)
        location = token.location
        id = next_node_id
        numeric = integer_node_rational(base, Token.new(:INTEGER_RATIONAL, token.start, token.end - 1))
        ImaginaryNode.new(@node_source, id, location, NodeFlags::STATIC_LITERAL, numeric)
      end

      # pm_in_node_create
      def in_node(pattern, statements, in_keyword, then_keyword)
        finish =
          if statements then statements.end_offset
          elsif then_keyword.provided? then then_keyword.end
          else pattern.end_offset
          end

        InNode.new(@node_source, next_node_id, loc(in_keyword.start, finish), 0,
                   pattern, statements, in_keyword.location, then_keyword.optional_location)
      end

      # pm_instance_variable_and_write_node_create
      def instance_variable_and_write_node(target, operator, value)
        InstanceVariableAndWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                         target.name, target.location, operator.location, value)
      end

      # pm_instance_variable_operator_write_node_create
      def instance_variable_operator_write_node(target, operator, value)
        InstanceVariableOperatorWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                              target.name, target.location, operator.location, value,
                                              location_name(operator.start, operator.end - 1))
      end

      # pm_instance_variable_or_write_node_create
      def instance_variable_or_write_node(target, operator, value)
        InstanceVariableOrWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                        target.name, target.location, operator.location, value)
      end

      # pm_instance_variable_read_node_create
      def instance_variable_read_node(token)
        InstanceVariableReadNode.new(@node_source, next_node_id, token.location, 0, token_name(token))
      end

      # pm_instance_variable_write_node_create
      def instance_variable_write_node(read_node, operator, value)
        flags = implicit_array_write_flags(value, WRITE_NODE_FLAGS_IMPLICIT_ARRAY)
        InstanceVariableWriteNode.new(@node_source, next_node_id, loc(read_node.start_offset, value.end_offset), flags,
                                      read_node.name, read_node.location, value, operator.optional_location)
      end

      # pm_interpolated_node_append: a part of a regexp, symbol or xstring,
      # and whether the whole stays a static literal.
      def interpolated_node_append(node, parts, part)
        case part
        when StringNode
          part.flag_set(NodeFlags::STATIC_LITERAL | StringFlags::FROZEN)
        when EmbeddedStatementsNode
          embedded = part.statements && part.statements.body.size == 1 ? part.statements.body[0] : nil

          if embedded.nil?
            node.flag_unset(NodeFlags::STATIC_LITERAL)
          elsif embedded.is_a?(StringNode)
            embedded.flag_set(NodeFlags::STATIC_LITERAL | StringFlags::FROZEN)
          elsif !(embedded.is_a?(InterpolatedStringNode) && embedded.flag?(NodeFlags::STATIC_LITERAL))
            node.flag_unset(NodeFlags::STATIC_LITERAL)
          end
        when EmbeddedVariableNode
          node.flag_unset(NodeFlags::STATIC_LITERAL)
        end

        parts << part
      end

      # pm_interpolated_regular_expression_node_create
      def interpolated_regular_expression_node(opening)
        InterpolatedRegularExpressionNode.new(@node_source, next_node_id, opening.location, NodeFlags::STATIC_LITERAL,
                                              opening.location, [], opening.location)
      end

      # pm_interpolated_regular_expression_node_append
      def interpolated_regular_expression_node_append(node, part)
        node.start_offset_keep_length = part.start_offset if node.start_offset > part.start_offset
        node.end_offset = part.end_offset if node.end_offset < part.end_offset

        interpolated_node_append(node, node.parts, part)
      end

      # pm_interpolated_regular_expression_node_closing_set
      def interpolated_regular_expression_node_closing_set(node, closing)
        node.closing_loc = closing.location
        node.end_offset = closing.end
        node.flag_set(regular_expression_flags(closing))
      end

      INTERPOLATED_STRING_FLAGS = NodeFlags::STATIC_LITERAL | InterpolatedStringNodeFlags::FROZEN | InterpolatedStringNodeFlags::MUTABLE

      # pm_interpolated_string_node_append: a part, and what it does to the
      # string's static literal, frozen and mutable flags.
      def interpolated_string_node_append(node, part)
        node.start_offset_keep_length = part.start_offset if node.parts.empty? && node.opening_loc.nil?
        node.end_offset = [node.end_offset, part.end_offset].max

        case part
        when StringNode
          # Joined frozen strings (`'foo' 'bar'`) stay frozen.
          node.flag_unset(NodeFlags::STATIC_LITERAL) unless part.flag?(StringFlags::FROZEN)
          part.flags = (part.flags | NodeFlags::STATIC_LITERAL | StringFlags::FROZEN) & ~StringFlags::MUTABLE
        when InterpolatedStringNode
          node.flag_unset(INTERPOLATED_STRING_FLAGS) unless part.flag?(NodeFlags::STATIC_LITERAL)
        when EmbeddedStatementsNode
          embedded = part.statements && part.statements.body.size == 1 ? part.statements.body[0] : nil

          if embedded.nil?
            node.flag_unset(INTERPOLATED_STRING_FLAGS)
          elsif embedded.is_a?(StringNode)
            embedded.flags = (embedded.flags | NodeFlags::STATIC_LITERAL | StringFlags::FROZEN) & ~StringFlags::MUTABLE
            interpolated_string_node_mutable(node)
          elsif embedded.is_a?(InterpolatedStringNode) && embedded.flag?(NodeFlags::STATIC_LITERAL)
            interpolated_string_node_mutable(node)
          else
            node.flag_unset(INTERPOLATED_STRING_FLAGS)
          end
        when EmbeddedVariableNode, ErrorRecoveryNode
          node.flag_unset(INTERPOLATED_STRING_FLAGS)
        when XStringNode, InterpolatedXStringNode, SymbolNode, InterpolatedSymbolNode
          # Only after an error: the part is not valid here.
          node.flag_unset(INTERPOLATED_STRING_FLAGS)
          return node.parts << error_recovery_node_unexpected(part)
        end

        node.parts << part
      end

      # The MUTABLE_FLAGS of pm_interpolated_string_node_append, for a
      # string that is still a static literal.
      def interpolated_string_node_mutable(node)
        return unless node.flag?(NodeFlags::STATIC_LITERAL)

        node.flags = (node.flags | InterpolatedStringNodeFlags::MUTABLE) & ~InterpolatedStringNodeFlags::FROZEN
      end

      # The flags a string literal starts with under the
      # frozen_string_literal magic comment or option.
      def frozen_string_literal_flags(disabled, enabled)
        case @frozen_string_literal
        when Options::FROZEN_STRING_LITERAL_DISABLED then disabled
        when Options::FROZEN_STRING_LITERAL_ENABLED then enabled
        else 0
        end
      end

      # pm_interpolated_string_node_create
      def interpolated_string_node(opening, parts, closing)
        flags = NodeFlags::STATIC_LITERAL |
                frozen_string_literal_flags(InterpolatedStringNodeFlags::MUTABLE, InterpolatedStringNodeFlags::FROZEN)

        node = InterpolatedStringNode.new(@node_source, next_node_id, loc(opening.start, closing.end), flags,
                                          opening.optional_location, [], closing.optional_location)
        parts&.each { |part| interpolated_string_node_append(node, part) }
        node
      end

      # pm_interpolated_string_node_closing_set, pm_interpolated_symbol_node_closing_loc_set,
      # pm_interpolated_xstring_node_closing_set
      def interpolated_node_closing_set(node, closing)
        node.closing_loc = closing.optional_location
        node.end_offset = closing.end
      end

      # pm_interpolated_symbol_node_append
      def interpolated_symbol_node_append(node, part)
        node.start_offset_keep_length = part.start_offset if node.parts.empty? && node.opening_loc.nil?

        interpolated_node_append(node, node.parts, part)
        node.end_offset = [node.end_offset, part.end_offset].max
      end

      # pm_interpolated_symbol_node_create
      def interpolated_symbol_node(opening, parts, closing)
        node = InterpolatedSymbolNode.new(@node_source, next_node_id, loc(opening.start, closing.end), NodeFlags::STATIC_LITERAL,
                                          opening.optional_location, [], closing.optional_location)
        parts&.each { |part| interpolated_symbol_node_append(node, part) }
        node
      end

      # pm_interpolated_xstring_node_create
      def interpolated_xstring_node(opening, closing)
        InterpolatedXStringNode.new(@node_source, next_node_id, loc(opening.start, closing.end), 0,
                                    opening.optional_location, [], closing.optional_location)
      end

      # pm_interpolated_xstring_node_append
      def interpolated_xstring_node_append(node, part)
        interpolated_node_append(node, node.parts, part)
        node.end_offset = part.end_offset
      end

      # pm_it_local_variable_read_node_create
      def it_local_variable_read_node(name) = ItLocalVariableReadNode.new(@node_source, next_node_id, name.location, 0)

      # pm_it_parameters_node_create
      def it_parameters_node(opening, closing)
        ItParametersNode.new(@node_source, next_node_id, loc(opening.start, closing.end), 0)
      end

      # pm_keyword_hash_node_create: its location is unset (nil) until the
      # first element.
      def keyword_hash_node
        KeywordHashNode.new(@node_source, next_node_id, nil, KeywordHashNodeFlags::SYMBOL_KEYS, [])
      end

      # pm_keyword_hash_node_elements_append
      def keyword_hash_node_elements_append(hash, element)
        unless element.is_a?(AssocNode) && element.key.is_a?(SymbolNode)
          hash.flag_unset(KeywordHashNodeFlags::SYMBOL_KEYS)
        end

        hash.elements << element
        if hash.location.nil?
          hash.location = element.location
        else
          hash.end_offset = element.end_offset
        end
      end

      # pm_required_keyword_parameter_node_create
      def required_keyword_parameter_node(name)
        RequiredKeywordParameterNode.new(@node_source, next_node_id, name.location, 0,
                                         location_name(name.start, name.end - 1), name.location)
      end

      # pm_optional_keyword_parameter_node_create
      def optional_keyword_parameter_node(name, value)
        OptionalKeywordParameterNode.new(@node_source, next_node_id, loc(name.start, value.end_offset), 0,
                                         location_name(name.start, name.end - 1), name.location, value)
      end

      # pm_keyword_rest_parameter_node_create
      def keyword_rest_parameter_node(operator, name)
        location = name.provided? ? loc(operator.start, name.end) : operator.location
        KeywordRestParameterNode.new(@node_source, next_node_id, location, 0,
                                     optional_token_name(name), name.optional_location, operator.location)
      end

      # pm_lambda_node_create
      def lambda_node(locals, operator, opening, closing, parameters, body)
        LambdaNode.new(@node_source, next_node_id, loc(operator.start, closing.end), 0,
                       locals, operator.location, opening.location, closing.location, parameters, body)
      end

      # pm_local_variable_and_write_node_create
      def local_variable_and_write_node(target, operator, value, name, depth)
        LocalVariableAndWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                      target.location, operator.location, value, name, depth)
      end

      # pm_local_variable_operator_write_node_create
      def local_variable_operator_write_node(target, operator, value, name, depth)
        location = loc(target.start_offset, value.end_offset)
        id = next_node_id
        LocalVariableOperatorWriteNode.new(@node_source, id, location, 0, target.location, operator.location, value,
                                           name, location_name(operator.start, operator.end - 1), depth)
      end

      # pm_local_variable_or_write_node_create
      def local_variable_or_write_node(target, operator, value, name, depth)
        LocalVariableOrWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), 0,
                                     target.location, operator.location, value, name, depth)
      end

      # pm_local_variable_read_node_create_constant_id: a read counts toward
      # the local's uses unless the local is missing.
      def local_variable_read_node_constant_id(name, name_id, depth, missing)
        scope_find(depth).locals.read(name_id) unless missing
        LocalVariableReadNode.new(@node_source, next_node_id, name.location, 0, constant_symbol(name_id), depth)
      end

      # pm_local_variable_read_node_create
      def local_variable_read_node(name, depth)
        local_variable_read_node_constant_id(name, constant_id_location(name.start, name.end), depth, false)
      end

      # pm_local_variable_read_node_missing_create
      def local_variable_read_node_missing(name, depth)
        local_variable_read_node_constant_id(name, constant_id_location(name.start, name.end), depth, true)
      end

      # pm_local_variable_write_node_create
      def local_variable_write_node(name, depth, value, name_loc, operator)
        flags = implicit_array_write_flags(value, WRITE_NODE_FLAGS_IMPLICIT_ARRAY)
        LocalVariableWriteNode.new(@node_source, next_node_id, loc(loc_start(name_loc), value.end_offset), flags,
                                   name, depth, name_loc, value, operator.optional_location)
      end

      # pm_token_is_it
      def token_it?(start, finish) = finish - start == 2 && @source.getbyte(start) == 0x69 && @source.getbyte(start + 1) == 0x74

      # pm_refute_numbered_parameter
      def refute_numbered_parameter(start, finish)
        return unless numbered_parameter?(start, finish)

        err(start, finish, :parameter_numbered_reserved, @source.byteslice(start, 2))
      end

      # pm_local_variable_target_node_create
      def local_variable_target_node(location, name, depth)
        refute_numbered_parameter(loc_start(location), loc_end(location))
        LocalVariableTargetNode.new(@node_source, next_node_id, location, 0, name, depth)
      end

      # pm_match_predicate_node_create
      def match_predicate_node(value, pattern, operator)
        assert_value_expression(value)
        MatchPredicateNode.new(@node_source, next_node_id, loc(value.start_offset, pattern.end_offset), 0,
                               value, pattern, operator.location)
      end

      # pm_match_required_node_create
      def match_required_node(value, pattern, operator)
        assert_value_expression(value)
        MatchRequiredNode.new(@node_source, next_node_id, loc(value.start_offset, pattern.end_offset), 0,
                              value, pattern, operator.location)
      end

      # pm_match_write_node_create
      def match_write_node(call) = MatchWriteNode.new(@node_source, next_node_id, call.location, 0, call, [])

      # pm_module_node_create
      def module_node(locals, module_keyword, constant_path, name, body, end_keyword)
        location = loc(module_keyword.start, end_keyword.end)
        id = next_node_id
        ModuleNode.new(@node_source, id, location, 0, locals || [], module_keyword.location, constant_path, body,
                       end_keyword.location, token_name(name))
      end

      # pm_multi_target_node_create: its location is unset (nil) until the
      # first target.
      def multi_target_node = MultiTargetNode.new(@node_source, next_node_id, nil, 0, [], nil, [], nil, nil)

      # pm_multi_target_node_targets_append
      def multi_target_node_targets_append(node, target)
        case target
        when SplatNode
          if node.rest.nil?
            node.rest = target
          else
            err_node(target, :multi_assign_multi_splats)
            node.rights << target
          end
        when ImplicitRestNode
          if node.rest.nil?
            node.rest = target
          else
            err_token_content(current_token, :multi_assign_unexpected_rest)
            node.rights << target
          end
        else
          if node.rest.nil?
            node.lefts << target
          else
            node.rights << target
          end
        end

        if node.location.nil?
          node.location = target.location
        else
          # A location of no length is not set yet (PM_LOCATION_INIT_UNSET).
          unset = node.start_offset == node.end_offset
          node.start_offset_keep_length = target.start_offset if unset || node.start_offset > target.start_offset
          node.end_offset = target.end_offset if unset || node.end_offset < target.end_offset
        end
      end

      # pm_multi_target_node_opening_set: the node starts as its `(`.
      def multi_target_node_opening_set(node, lparen)
        node.location = lparen.location
        node.lparen_loc = lparen.location
      end

      # pm_multi_target_node_closing_set
      def multi_target_node_closing_set(node, rparen)
        node.end_offset = rparen.end
        node.rparen_loc = rparen.location
      end

      # pm_multi_write_node_create
      def multi_write_node(target, operator, value)
        flags = implicit_array_write_flags(value, WRITE_NODE_FLAGS_IMPLICIT_ARRAY)
        MultiWriteNode.new(@node_source, next_node_id, loc(target.start_offset, value.end_offset), flags,
                           target.lefts, target.rest, target.rights, target.lparen_loc, target.rparen_loc,
                           operator.location, value)
      end

      # pm_next_node_create
      def next_node(keyword, arguments)
        location = arguments.nil? ? keyword.location : loc(keyword.start, arguments.end_offset)
        NextNode.new(@node_source, next_node_id, location, 0, arguments, keyword.location)
      end

      # pm_nil_node_create
      def nil_node(token) = NilNode.new(@node_source, next_node_id, token.location, NodeFlags::STATIC_LITERAL)

      # pm_no_keywords_parameter_node_create
      def no_keywords_parameter_node(operator, keyword)
        NoKeywordsParameterNode.new(@node_source, next_node_id, loc(operator.start, keyword.end), 0,
                                    operator.location, keyword.location)
      end

      # pm_numbered_parameters_node_create
      def numbered_parameters_node(location, maximum)
        NumberedParametersNode.new(@node_source, next_node_id, location, 0, maximum)
      end

      # NTH_REF_MAX
      NTH_REF_MAX = (2**31 - 1) >> 1

      # pm_numbered_reference_read_node_number: 0, with a warning, past the
      # largest reference.
      def numbered_reference_read_node_number(token)
        start = token.start + 1
        digits = @source.byteslice(start, token.end - start)
        value = digits.to_i

        if value > NTH_REF_MAX
          warn(start, token.end, :invalid_numbered_reference, @source.byteslice(token.start, digits.bytesize + 1))
          value = 0
        end
        value
      end

      # pm_numbered_reference_read_node_create
      def numbered_reference_read_node(name)
        location = name.location
        id = next_node_id
        NumberedReferenceReadNode.new(@node_source, id, location, 0, numbered_reference_read_node_number(name))
      end

      # pm_optional_parameter_node_create
      def optional_parameter_node(name, operator, value)
        OptionalParameterNode.new(@node_source, next_node_id, loc(name.start, value.end_offset), 0,
                                  token_name(name), name.location, operator.location, value)
      end

      # pm_or_node_create
      def or_node(left, operator, right)
        assert_value_expression(left)
        OrNode.new(@node_source, next_node_id, loc(left.start_offset, right.end_offset), 0, left, right, operator.location)
      end

      # pm_parameters_node_create: its location is unset (nil) until the
      # first parameter.
      def parameters_node = ParametersNode.new(@node_source, next_node_id, nil, 0, [], [], nil, [], [], nil, nil)

      # pm_parameters_node_location_set
      def parameters_node_location_set(params, param)
        # A location of no length is not set yet (PM_LOCATION_INIT_UNSET).
        if params.location.nil? || params.start_offset == params.end_offset
          params.location = param.location
        else
          params.start_offset_keep_length = param.start_offset if params.start_offset > param.start_offset
          params.end_offset = param.end_offset if params.end_offset < param.end_offset
        end
      end

      # pm_parameters_node_requireds_append
      def parameters_node_requireds_append(params, param)
        parameters_node_location_set(params, param)
        params.requireds << param
      end

      # pm_parameters_node_optionals_append
      def parameters_node_optionals_append(params, param)
        parameters_node_location_set(params, param)
        params.optionals << param
      end

      # pm_parameters_node_posts_append
      def parameters_node_posts_append(params, param)
        parameters_node_location_set(params, param)
        params.posts << param
      end

      # pm_parameters_node_rest_set
      def parameters_node_rest_set(params, param)
        parameters_node_location_set(params, param)
        params.rest = param
      end

      # pm_parameters_node_keywords_append
      def parameters_node_keywords_append(params, param)
        parameters_node_location_set(params, param)
        params.keywords << param
      end

      # pm_parameters_node_keyword_rest_set
      def parameters_node_keyword_rest_set(params, param)
        parameters_node_location_set(params, param)
        params.keyword_rest = param
      end

      # pm_no_block_parameter_node_create: `&nil`.
      def no_block_parameter_node(operator, keyword)
        NoBlockParameterNode.new(@node_source, next_node_id, loc(operator.start, keyword.end), 0, operator.location, keyword.location)
      end

      # pm_parameters_node_block_set
      def parameters_node_block_set(params, param)
        parameters_node_location_set(params, param)
        params.block = param
      end

      # pm_program_node_create
      def program_node(locals, statements)
        ProgramNode.new(@node_source, next_node_id, statements.location, 0, locals, statements)
      end

      # pm_parentheses_node_create
      def parentheses_node(opening, body, closing, flags)
        ParenthesesNode.new(@node_source, next_node_id, loc(opening.start, closing.end), flags,
                            body, opening.location, closing.location)
      end

      # pm_pinned_expression_node_create
      def pinned_expression_node(expression, operator, lparen, rparen)
        PinnedExpressionNode.new(@node_source, next_node_id, loc(operator.start, rparen.end), 0,
                                 expression, operator.location, lparen.location, rparen.location)
      end

      # pm_pinned_variable_node_create
      def pinned_variable_node(operator, variable)
        PinnedVariableNode.new(@node_source, next_node_id, loc(operator.start, variable.end_offset), 0,
                               variable, operator.location)
      end

      # pm_post_execution_node_create
      def post_execution_node(keyword, opening, statements, closing)
        PostExecutionNode.new(@node_source, next_node_id, loc(keyword.start, closing.end), 0,
                              statements, keyword.location, opening.location, closing.location)
      end

      # pm_pre_execution_node_create
      def pre_execution_node(keyword, opening, statements, closing)
        PreExecutionNode.new(@node_source, next_node_id, loc(keyword.start, closing.end), 0,
                             statements, keyword.location, opening.location, closing.location)
      end

      # pm_range_node_create
      def range_node(left, operator, right)
        assert_value_expression(left)
        assert_value_expression(right)

        flags = 0
        flags |= RangeFlags::EXCLUDE_END if operator.type == :DOT_DOT_DOT || operator.type == :UDOT_DOT_DOT

        # nil..1 and 1..2 are static literals.
        if (left.nil? || left.is_a?(NilNode) || left.is_a?(IntegerNode)) &&
           (right.nil? || right.is_a?(NilNode) || right.is_a?(IntegerNode))
          flags |= NodeFlags::STATIC_LITERAL
        end

        start = left.nil? ? operator.start : left.start_offset
        finish = right.nil? ? operator.end : right.end_offset
        RangeNode.new(@node_source, next_node_id, loc(start, finish), flags, left, right, operator.location)
      end

      # pm_redo_node_create
      def redo_node(token) = RedoNode.new(@node_source, next_node_id, token.location, 0)

      # pm_regular_expression_node_create_unescaped
      def regular_expression_node_unescaped(opening, content, closing, unescaped)
        flags = regular_expression_flags(closing) | NodeFlags::STATIC_LITERAL
        RegularExpressionNode.new(@node_source, next_node_id, loc(opening.start, closing.end), flags,
                                  opening.location, content.location, closing.location, unescaped)
      end

      # pm_regular_expression_node_create
      def regular_expression_node(opening, content, closing)
        regular_expression_node_unescaped(opening, content, closing, "".b)
      end

      # pm_required_parameter_node_create
      def required_parameter_node(token)
        RequiredParameterNode.new(@node_source, next_node_id, token.location, 0, token_name(token))
      end

      # pm_rescue_modifier_node_create
      def rescue_modifier_node(expression, keyword, rescue_expression)
        RescueModifierNode.new(@node_source, next_node_id, loc(expression.start_offset, rescue_expression.end_offset), 0,
                               expression, keyword.location, rescue_expression)
      end

      # pm_rescue_node_create
      def rescue_node(keyword)
        RescueNode.new(@node_source, next_node_id, keyword.location, 0, keyword.location, [], nil, nil, nil, nil, nil)
      end

      # pm_rescue_node_operator_set
      def rescue_node_operator_set(node, operator) = node.operator_loc = operator.optional_location

      # pm_rescue_node_reference_set
      def rescue_node_reference_set(node, reference)
        node.reference = reference
        node.end_offset = reference.end_offset
      end

      # pm_rescue_node_statements_set
      def rescue_node_statements_set(node, statements)
        node.statements = statements
        node.end_offset = statements.end_offset if statements_node_body_length(statements) > 0
      end

      # pm_rescue_node_subsequent_set
      def rescue_node_subsequent_set(node, subsequent)
        node.subsequent = subsequent
        node.end_offset = subsequent.end_offset
      end

      # pm_rescue_node_exceptions_append
      def rescue_node_exceptions_append(node, exception)
        node.exceptions << exception
        node.end_offset = exception.end_offset
      end

      # pm_rest_parameter_node_create
      def rest_parameter_node(operator, name)
        location = name.provided? ? loc(operator.start, name.end) : operator.location
        RestParameterNode.new(@node_source, next_node_id, location, 0,
                              optional_token_name(name), name.optional_location, operator.location)
      end

      # pm_retry_node_create
      def retry_node(token) = RetryNode.new(@node_source, next_node_id, token.location, 0)

      # pm_return_node_create
      def return_node(keyword, arguments)
        location = arguments.nil? ? keyword.location : loc(keyword.start, arguments.end_offset)
        ReturnNode.new(@node_source, next_node_id, location, 0, keyword.location, arguments)
      end

      # pm_self_node_create
      def self_node(token) = SelfNode.new(@node_source, next_node_id, token.location, 0)

      # pm_shareable_constant_node_create
      def shareable_constant_node(write, value)
        ShareableConstantNode.new(@node_source, next_node_id, write.location, value, write)
      end

      # pm_singleton_class_node_create
      def singleton_class_node(locals, class_keyword, operator, expression, body, end_keyword)
        SingletonClassNode.new(@node_source, next_node_id, loc(class_keyword.start, end_keyword.end), 0,
                               locals, class_keyword.location, operator.location, expression, body, end_keyword.location)
      end

      # pm_source_encoding_node_create
      def source_encoding_node(token)
        SourceEncodingNode.new(@node_source, next_node_id, token.location, NodeFlags::STATIC_LITERAL)
      end

      # pm_source_file_node_create: from 4.1, `__FILE__` is no static
      # literal, as ruby reads it when the code runs.
      def source_file_node(file_keyword)
        frozen = StringFlags::FROZEN
        frozen |= NodeFlags::STATIC_LITERAL if @version < Options::VERSION_CRUBY_4_1
        flags = frozen_string_literal_flags(StringFlags::MUTABLE, frozen)
        SourceFileNode.new(@node_source, next_node_id, file_keyword.location, flags, @filepath)
      end

      # pm_source_line_node_create
      def source_line_node(token)
        SourceLineNode.new(@node_source, next_node_id, token.location, NodeFlags::STATIC_LITERAL)
      end

      # pm_splat_node_create
      def splat_node(operator, expression)
        location = expression.nil? ? operator.location : loc(operator.start, expression.end_offset)
        SplatNode.new(@node_source, next_node_id, location, 0, operator.location, expression)
      end

      # pm_statements_node_create
      def statements_node = StatementsNode.new(@node_source, next_node_id, null_location, 0, [])

      # pm_statements_node_body_length
      def statements_node_body_length(node) = node.nil? ? 0 : node.body.size

      # pm_statements_node_location_set
      def statements_node_location_set(node, start, finish) = node.location = loc(start, finish)

      # pm_statements_node_body_update
      def statements_node_body_update(node, statement)
        if statements_node_body_length(node) == 0 || statement.start_offset < node.start_offset
          node.start_offset_keep_length = statement.start_offset
        end
        node.end_offset = statement.end_offset if statement.end_offset > node.end_offset
      end

      # pm_statements_node_body_append: a warning for a statement after a
      # jump.
      def statements_node_body_append(node, statement, newline)
        statements_node_body_update(node, statement)

        case node.body.last
        when BreakNode, NextNode, RedoNode, RetryNode, ReturnNode
          warn_node(statement, :unreachable_statement)
        end

        node.body << statement
        statement.flag_set(NodeFlags::NEWLINE) if newline
      end

      # pm_statements_node_body_prepend
      def statements_node_body_prepend(node, statement)
        statements_node_body_update(node, statement)
        node.body.unshift(statement)
        statement.flag_set(NodeFlags::NEWLINE)
      end

      # pm_string_node_create_unescaped
      def string_node_unescaped(opening, content, closing, string)
        flags = frozen_string_literal_flags(StringFlags::MUTABLE, NodeFlags::STATIC_LITERAL | StringFlags::FROZEN)
        start = opening.provided? ? opening.start : content.start
        finish = closing.provided? ? closing.end : content.end

        StringNode.new(@node_source, next_node_id, loc(start, finish), flags,
                       opening.optional_location, content.location, closing.optional_location, string)
      end

      # pm_string_node_create
      def string_node(opening, content, closing) = string_node_unescaped(opening, content, closing, "".b)

      # pm_string_node_create_current_string
      def string_node_current_string(opening, content, closing)
        node = string_node_unescaped(opening, content, closing, @current_string)
        @current_string = "".b
        node
      end

      # pm_super_node_create
      def super_node(keyword, arguments)
        SuperNode.new(@node_source, next_node_id, loc(keyword.start, arguments_end(arguments)), 0,
                      keyword.location, arguments.opening_loc, arguments.arguments, arguments.closing_loc, arguments.block)
      end

      # parse_symbol_encoding_validate_utf8, parse_symbol_encoding_validate_other
      def symbol_encoding_validate(location, contents, encoding)
        cursor = 0
        while cursor < contents.bytesize
          width = encoding.char_width(contents, cursor, contents.bytesize - cursor)
          if width == 0
            err(location.start, location.end, :invalid_symbol)
            break
          end
          cursor += width
        end
      end

      # parse_symbol_encoding: the encoding flag of a symbol, which is
      # US-ASCII when ASCII only, or the encoding an escape fixed.
      def symbol_encoding(location, contents, validate, explicit = @explicit_encoding)
        if explicit
          if explicit == Encodings::UTF_8
            symbol_encoding_validate(location, contents, Encodings::UTF_8) if validate
            return SymbolFlags::FORCED_UTF8_ENCODING
          elsif @encoding == Encodings::US_ASCII
            return SymbolFlags::FORCED_BINARY_ENCODING
          elsif validate
            symbol_encoding_validate(location, contents, @encoding)
          end
        elsif contents.ascii_only?
          return SymbolFlags::FORCED_US_ASCII_ENCODING
        elsif validate
          symbol_encoding_validate(location, contents, @encoding)
        end
        0
      end

      # pm_symbol_node_create_unescaped
      def symbol_node_unescaped(opening, value, closing, unescaped, flags)
        start = opening.provided? ? opening.start : value.start
        finish = closing.provided? ? closing.end : value.end
        SymbolNode.new(@node_source, next_node_id, loc(start, finish), NodeFlags::STATIC_LITERAL | flags,
                       opening.optional_location, value.location, closing.optional_location, unescaped)
      end

      # pm_symbol_node_create
      def symbol_node(opening, value, closing) = symbol_node_unescaped(opening, value, closing, "".b, 0)

      # pm_symbol_node_create_current_string
      def symbol_node_current_string(opening, value, closing)
        flags = symbol_encoding(value, @current_string, false)
        node = symbol_node_unescaped(opening, value, closing, @current_string, flags)
        @current_string = "".b
        node
      end

      # pm_symbol_node_label_create
      def symbol_node_label(token)
        case token.type
        when :LABEL
          closing = Token.new(:LABEL_END, token.end - 1, token.end)
          label = Token.new(:LABEL, token.start, token.end - 1)
          node = symbol_node(NOT_PROVIDED, label, closing)
          node.unescaped = shared_string(label.start, label.end)
          node.flag_set(symbol_encoding(label, node.unescaped, false))
          node
        when :MISSING
          symbol_node(NOT_PROVIDED, Token.new(:LABEL, token.start, token.end), NOT_PROVIDED)
        end
      end

      # pm_symbol_node_synthesized_create
      def symbol_node_synthesized(content)
        SymbolNode.new(@node_source, next_node_id, null_location,
                       NodeFlags::STATIC_LITERAL | SymbolFlags::FORCED_US_ASCII_ENCODING, nil, null_location, nil, content.b)
      end

      # pm_symbol_node_label_p: a symbol or interpolated symbol ending in `:`.
      def symbol_node_label?(node)
        return false unless node.is_a?(SymbolNode) || node.is_a?(InterpolatedSymbolNode)

        loc_present?(node.closing_loc) && @source.getbyte(loc_end(node.closing_loc) - 1) == 0x3A
      end

      # pm_string_node_to_symbol_node
      def string_node_to_symbol_node(node, opening, closing)
        new_node = SymbolNode.new(@node_source, next_node_id, loc(opening.start, closing.end), NodeFlags::STATIC_LITERAL,
                                  opening.optional_location, node.content_loc, closing.optional_location, node.unescaped)

        content = Token.new(:IDENTIFIER, loc_start(node.content_loc), loc_end(node.content_loc))
        new_node.flag_set(symbol_encoding(content, node.unescaped, true))
        new_node
      end

      # pm_symbol_node_to_string_node
      def symbol_node_to_string_node(node)
        flags = frozen_string_literal_flags(StringFlags::MUTABLE, NodeFlags::STATIC_LITERAL | StringFlags::FROZEN)
        StringNode.new(@node_source, next_node_id, node.location, flags,
                       node.opening_loc, node.content_loc, node.closing_loc, node.unescaped)
      end

      # pm_true_node_create
      def true_node(token) = TrueNode.new(@node_source, next_node_id, token.location, NodeFlags::STATIC_LITERAL)

      # pm_true_node_synthesized_create
      def true_node_synthesized = TrueNode.new(@node_source, next_node_id, null_location, NodeFlags::STATIC_LITERAL)

      # pm_undef_node_create
      def undef_node(token) = UndefNode.new(@node_source, next_node_id, token.location, 0, [], token.location)

      # pm_undef_node_append
      def undef_node_append(node, name)
        node.end_offset = name.end_offset
        node.names << name
      end

      # pm_unless_node_create
      def unless_node(keyword, predicate, then_keyword, statements)
        predicate = conditional_predicate(predicate, :conditional)
        finish = statements.nil? ? predicate.end_offset : statements.end_offset

        UnlessNode.new(@node_source, next_node_id, loc(keyword.start, finish), NodeFlags::NEWLINE,
                       keyword.location, predicate, then_keyword.optional_location, statements, nil, nil)
      end

      # pm_unless_node_modifier_create
      def unless_node_modifier(statement, unless_keyword, predicate)
        predicate = conditional_predicate(predicate, :conditional)

        statements = statements_node
        statements_node_body_append(statements, statement, true)

        UnlessNode.new(@node_source, next_node_id, loc(statement.start_offset, predicate.end_offset), NodeFlags::NEWLINE,
                       unless_keyword.location, predicate, nil, statements, nil, nil)
      end

      # pm_loop_modifier_block_exits: the jumps inside a loop's body no
      # longer need a block around them.
      def loop_modifier_block_exits(statements)
        start = statements.start_offset
        exits = @current_block_exits
        exits.pop while !exits.empty? && exits.last.start_offset >= start
      end

      # pm_until_node_create
      def until_node(keyword, do_keyword, closing, predicate, statements, flags)
        predicate = conditional_predicate(predicate, :conditional)
        UntilNode.new(@node_source, next_node_id, loc(keyword.start, closing.end), flags, keyword.location,
                      do_keyword.optional_location, closing.optional_location, predicate, statements)
      end

      # pm_until_node_modifier_create
      def until_node_modifier(keyword, predicate, statements, flags)
        predicate = conditional_predicate(predicate, :conditional)
        loop_modifier_block_exits(statements)
        UntilNode.new(@node_source, next_node_id, loc(statements.start_offset, predicate.end_offset), flags,
                      keyword.location, nil, nil, predicate, statements)
      end

      # pm_when_node_create
      def when_node(keyword) = WhenNode.new(@node_source, next_node_id, keyword.location, 0, keyword.location, [], nil, nil)

      # pm_when_node_conditions_append
      def when_node_conditions_append(node, condition)
        node.end_offset = condition.end_offset
        node.conditions << condition
      end

      # pm_when_node_then_keyword_loc_set
      def when_node_then_keyword_loc_set(node, then_keyword)
        node.end_offset = then_keyword.end
        node.then_keyword_loc = then_keyword.location
      end

      # pm_when_node_statements_set
      def when_node_statements_set(node, statements)
        node.end_offset = statements.end_offset if statements.end_offset > node.end_offset
        node.statements = statements
      end

      # pm_while_node_create
      def while_node(keyword, do_keyword, closing, predicate, statements, flags)
        predicate = conditional_predicate(predicate, :conditional)
        WhileNode.new(@node_source, next_node_id, loc(keyword.start, closing.end), flags, keyword.location,
                      do_keyword.optional_location, closing.optional_location, predicate, statements)
      end

      # pm_while_node_modifier_create
      def while_node_modifier(keyword, predicate, statements, flags)
        predicate = conditional_predicate(predicate, :conditional)
        loop_modifier_block_exits(statements)
        WhileNode.new(@node_source, next_node_id, loc(statements.start_offset, predicate.end_offset), flags,
                      keyword.location, nil, nil, predicate, statements)
      end

      # pm_while_node_synthesized_create
      def while_node_synthesized(predicate, statements)
        WhileNode.new(@node_source, next_node_id, null_location, 0, null_location, null_location, null_location,
                      predicate, statements)
      end

      # pm_xstring_node_create_unescaped
      def xstring_node_unescaped(opening, content, closing, unescaped)
        XStringNode.new(@node_source, next_node_id, loc(opening.start, closing.end), StringFlags::FROZEN,
                        opening.location, content.location, closing.location, unescaped)
      end

      # pm_xstring_node_create
      def xstring_node(opening, content, closing) = xstring_node_unescaped(opening, content, closing, "".b)

      # pm_yield_node_create
      def yield_node(keyword, lparen_loc, arguments, rparen_loc)
        finish =
          if loc_present?(rparen_loc) then loc_end(rparen_loc)
          elsif arguments then arguments.end_offset
          elsif loc_present?(lparen_loc) then loc_end(lparen_loc)
          else keyword.end
          end

        YieldNode.new(@node_source, next_node_id, loc(keyword.start, finish), 0,
                      keyword.location, lparen_loc, arguments, rparen_loc)
      end

      # -- scopes and locals ------------------------------------------------

      # pm_parser_scope_toplevel_p
      def scope_toplevel?
        scope = @current_scope
        until scope.nil?
          return true if scope.previous.nil?
          return false if scope.closed?

          scope = scope.previous
        end
        true
      end

      # pm_parser_scope_find
      def scope_find(depth)
        scope = @current_scope
        depth.times { scope = scope.previous }
        scope
      end

      # pm_parser_scope_forwarding_param_check: :pass, :conflict or :fail.
      def scope_forwarding_param_check(mask)
        scope = @current_scope
        conflict = false

        until scope.nil?
          if scope.parameters.anybits?(mask)
            return conflict ? :conflict : :pass if scope.closed?

            conflict = true
          end
          break if scope.closed?

          scope = scope.previous
        end
        :fail
      end

      # pm_parser_scope_forwarding_block_check, _positionals_check,
      # _all_check and _keywords_check
      def scope_forwarding_check(token, mask, conflict_id, fail_id)
        case scope_forwarding_param_check(mask)
        when :conflict then err_token(token, conflict_id) if conflict_id
        when :fail then err_token(token, fail_id)
        end
      end

      def scope_forwarding_block_check(token)
        scope_forwarding_check(token, Scope::FORWARDING_BLOCK, :argument_conflict_ampersand, :argument_no_forwarding_ampersand)
      end

      def scope_forwarding_positionals_check(token)
        scope_forwarding_check(token, Scope::FORWARDING_POSITIONALS, :argument_conflict_star, :argument_no_forwarding_star)
      end

      # A conflict cannot happen for `...`, which blocks cannot declare.
      def scope_forwarding_all_check(token)
        scope_forwarding_check(token, Scope::FORWARDING_ALL, nil, :argument_no_forwarding_ellipses)
      end

      def scope_forwarding_keywords_check(token)
        scope_forwarding_check(token, Scope::FORWARDING_KEYWORDS, :argument_conflict_star_star, :argument_no_forwarding_star_star)
      end

      # pm_parser_scope_shareable_constant_get
      def scope_shareable_constant = @current_scope.shareable_constant

      # pm_parser_scope_shareable_constant_set: on each scope open to this
      # one.
      def scope_shareable_constant_set(value)
        scope = @current_scope
        loop do
          scope.shareable_constant = value
          break if scope.closed? || (scope = scope.previous).nil?
        end
      end

      # pm_locals_order: the scope's locals in the order they were added,
      # warning about any never read.
      def locals_order(locals, toplevel)
        list = Array.new(locals.size)
        warn_unused = !toplevel || (!@parsing_eval && !command_line_e?)

        locals.each_slot do |local|
          list[local.index] = constant_symbol(local.name)

          next unless warn_unused && local.reads == 0 && (@start_line >= 0 || newline_line(local.start, @start_line) >= 0)

          bytes = @constant_pool.bytes(local.name)
          if bytes.bytesize >= 1 && bytes.getbyte(0) != 0x5F
            warn(local.start, local.end, :unused_local_variable, bytes)
          end
        end
        list
      end

      # pm_newline_list_line: the line of `offset`, counting from
      # `start_line`.
      def newline_line(offset, start_line) = @newlines.bsearch_index { |line_start| line_start > offset }.then { |index| (index || @newlines.size) - 1 + start_line }

      # pm_parser_local_add_location
      def local_add_location(start, finish, reads)
        constant_id = constant_id_location(start, finish)
        local_add(constant_id, start, finish, reads) if constant_id != 0
        constant_id
      end

      # pm_parser_local_add_token
      def local_add_token(token, reads) = local_add_location(token.start, token.end, reads)

      # pm_parser_local_add_constant
      def local_add_constant(bytes)
        constant_id = constant_id_constant(bytes)
        local_add(constant_id, 0, 0, 1) if constant_id != 0
        constant_id
      end

      # pm_parser_parameter_name_check: whether the name repeats a
      # parameter, with an error unless it starts with `_`.
      def parameter_name_check(name)
        refute_numbered_parameter(name.start, name.end)

        constant_id = constant_id_location(name.start, name.end)
        return false unless @current_scope.locals.include?(constant_id)

        err_token(name, :parameter_name_duplicated) if name.start < name.end && @source.getbyte(name.start) != 0x5F
        true
      end
    end
  end
end
