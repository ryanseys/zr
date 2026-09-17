# frozen_string_literal: true

using Prism::Ruby::Mutation

module Prism
  module Ruby
    class Parser
      # The node an operator write makes of each target, by operator:
      # [&&=, ||=, op=].
      OPERATOR_WRITES = {
        global: %i[global_variable_and_write_node global_variable_or_write_node global_variable_operator_write_node],
        class_variable: %i[class_variable_and_write_node class_variable_or_write_node class_variable_operator_write_node],
        constant_path: %i[constant_path_and_write_node constant_path_or_write_node constant_path_operator_write_node],
        constant: %i[constant_and_write_node constant_or_write_node constant_operator_write_node],
        instance_variable: %i[instance_variable_and_write_node instance_variable_or_write_node instance_variable_operator_write_node],
        local_variable: %i[local_variable_and_write_node local_variable_or_write_node local_variable_operator_write_node],
        index: %i[index_and_write_node index_or_write_node index_operator_write_node],
        call: %i[call_and_write_node call_or_write_node call_operator_write_node]
      }.freeze

      # The errors of each operator write: [value missing, multiple write].
      OPERATOR_WRITE_ERRORS = [
        %i[expect_expression_after_ampampeq ampampeq_multi_assign],
        %i[expect_expression_after_pipepipeeq pipepipeeq_multi_assign],
        %i[expect_expression_after_operator operator_multi_assign]
      ].freeze

      # The binary operators that may follow a rescue modifier's or `and`'s
      # match only on a new statement.
      BINARY_OPERATORS = %i[
        UAMPERSAND USTAR USTAR_STAR BANG_EQUAL BANG_TILDE EQUAL_EQUAL EQUAL_EQUAL_EQUAL LESS_EQUAL_GREATER CARET PIPE
        AMPERSAND GREATER_GREATER LESS_LESS MINUS PLUS PERCENT SLASH STAR STAR_STAR
      ].freeze

      OPERATOR_ASSIGNMENTS = %i[
        AMPERSAND_EQUAL CARET_EQUAL GREATER_GREATER_EQUAL LESS_LESS_EQUAL MINUS_EQUAL PERCENT_EQUAL PIPE_EQUAL
        PLUS_EQUAL SLASH_EQUAL STAR_EQUAL STAR_STAR_EQUAL
      ].freeze

      private

      # parse_assignment_value: the value of an operator write, which may
      # take a rescue modifier.
      def parse_assignment_value(previous_binding_power, binding_power, accepts_command_call, diag_id, depth)
        accepts = previous_binding_power == BINDING_POWER_ASSIGNMENT ? accepts_command_call : previous_binding_power < BINDING_POWER_MATCH
        value = parse_value_expression(binding_power, accepts, false, diag_id, depth + 1)

        return value unless @current_type == :KEYWORD_RESCUE_MODIFIER

        context_push(:rescue_modifier)

        rescue_keyword = current_token
        lex

        right = parse_expression(BINDING_POWERS[:KEYWORD_RESCUE_MODIFIER].right, false, false, :rescue_modifier_value, depth + 1)
        context_pop

        rescue_modifier_node(value, rescue_keyword, right)
      end

      # parse_assignment_value_local: a local written as the value of
      # another write counts as used.
      def parse_assignment_value_local(node)
        case node
        when BeginNode
          parse_assignment_value_local(node.statements) if node.statements
        when LocalVariableWriteNode
          scope_find(node.depth).locals.read(constant_id_of(node.name))
        when ParenthesesNode
          parse_assignment_value_local(node.body) if node.body
        when StatementsNode
          node.body.each { |statement| parse_assignment_value_local(statement) }
        end
      end

      # parse_assignment_values: the value after `=`, which at a statement
      # may be several (an array without brackets) and may take a rescue
      # modifier.
      def parse_assignment_values(previous_binding_power, binding_power, accepts_command_call, diag_id, depth)
        permitted = !(previous_binding_power != BINDING_POWER_STATEMENT && @current_type == :USTAR)

        accepts = previous_binding_power == BINDING_POWER_ASSIGNMENT ? accepts_command_call : previous_binding_power < BINDING_POWER_MODIFIER
        value = parse_starred_expression(binding_power, accepts, diag_id, depth + 1)
        err_node(value, :unexpected_multi_write) unless permitted

        parse_assignment_value_local(value)
        single_value = true

        if previous_binding_power == BINDING_POWER_STATEMENT && (value.is_a?(SplatNode) || @current_type == :COMMA)
          single_value = false

          array = array_node(NOT_PROVIDED)
          array_node_elements_append(array, value)
          value = array

          while accept(:COMMA)
            element = parse_starred_expression(binding_power, false, :array_element, depth + 1)

            array_node_elements_append(array, element)
            break if element.is_a?(MissingNode)

            parse_assignment_value_local(element)
          end
        end

        if (single_value || binding_power == BINDING_POWER_MULTI_ASSIGNMENT + 1) && @current_type == :KEYWORD_RESCUE_MODIFIER
          context_push(:rescue_modifier)

          rescue_keyword = current_token
          lex

          # A command call without parentheses may be rescued by another.
          accepts_command_call_inner = value.is_a?(CallNode) && value.arguments && value.opening_loc.nil?

          right = parse_expression(BINDING_POWERS[:KEYWORD_RESCUE_MODIFIER].right, accepts_command_call_inner, false, :rescue_modifier_value, depth + 1)
          context_pop

          return rescue_modifier_node(value, rescue_keyword, right)
        end

        value
      end

      # parse_call_operator_write: an operator write's call target has no
      # arguments or block.
      def parse_call_operator_write(call_node, operator)
        if call_node.arguments
          err_token(operator, :operator_write_arguments)
          node_unreference(call_node.arguments)
          call_node.arguments = nil
        end

        return unless call_node.block

        err_token(operator, :operator_write_block)
        node_unreference(call_node.block)
        call_node.block = nil
      end

      # pm_named_capture_escape_hex
      def named_capture_escape_hex(unescaped, bytes, cursor)
        cursor += 1

        if cursor < bytes.bytesize && hexadecimal_digit?(bytes.getbyte(cursor))
          value = escape_hexadecimal_digit(bytes.getbyte(cursor))
          cursor += 1

          if cursor < bytes.bytesize && hexadecimal_digit?(bytes.getbyte(cursor))
            value = ((value << 4) | escape_hexadecimal_digit(bytes.getbyte(cursor))) & 0xFF
            cursor += 1
          end

          unescaped << value
        else
          unescaped << "\\x"
        end
        cursor
      end

      # pm_named_capture_escape_octal
      def named_capture_escape_octal(unescaped, bytes, cursor)
        value = bytes.getbyte(cursor) - 0x30
        cursor += 1

        2.times do
          break unless cursor < bytes.bytesize && octal_digit?(bytes.getbyte(cursor))

          value = ((value << 3) & 0xFF) | (bytes.getbyte(cursor) - 0x30)
          cursor += 1
        end

        unescaped << value
        cursor
      end

      # escape_unicode over `bytes`, with a surrogate's error at the regexp
      # (`error_location`) or at the digits when the bytes are the source.
      def named_capture_unicode_value(bytes, from, length, error_location)
        value = 0
        length.times { |index| value = ((value << 4) | escape_hexadecimal_digit(bytes.getbyte(from + index))) & 0xFFFF_FFFF }
        return value unless value >= 0xD800 && value <= 0xDFFF

        if error_location
          err(loc_start(error_location), loc_end(error_location), :escape_invalid_unicode)
        else
          err(from, from + length, :escape_invalid_unicode)
        end
        0xFFFD
      end

      # The run of hexadecimal digits at `from` in `bytes`, at most `limit`.
      def hexadecimal_run(bytes, from, limit)
        length = 0
        length += 1 while length < limit && from + length < bytes.bytesize && hexadecimal_digit?(bytes.getbyte(from + length))
        length
      end

      # pm_named_capture_escape_unicode
      def named_capture_escape_unicode(unescaped, bytes, cursor, error_location)
        start = cursor - 1
        cursor += 1

        if cursor >= bytes.bytesize
          unescaped << "\\u"
          return cursor
        end

        if bytes.getbyte(cursor) != 0x7B
          length = hexadecimal_run(bytes, cursor, [bytes.bytesize - cursor, 4].min)
          value = named_capture_unicode_value(bytes, cursor, length, error_location)
          unescaped << bytes.byteslice(start, cursor + length - start) unless append_codepoint(unescaped, value)
          return cursor + length
        end

        cursor += 1
        loop do
          cursor += 1 while cursor < bytes.bytesize && bytes.getbyte(cursor) == 0x20
          break if cursor >= bytes.bytesize

          if bytes.getbyte(cursor) == 0x7D
            cursor += 1
            break
          end

          length = hexadecimal_run(bytes, cursor, bytes.bytesize - cursor)
          break if length == 0

          append_codepoint(unescaped, named_capture_unicode_value(bytes, cursor, length, error_location))
          cursor += length
        end
        cursor
      end

      # pm_memchr over `bytes`.
      def memchr(bytes, value, from)
        unless @encoding_changed && @encoding.multibyte? && value >= 0x40
          return bytes.byteindex(value.chr, from)
        end

        index = from
        while index < bytes.bytesize
          return index if bytes.getbyte(index) == value

          width = @encoding.char_width(bytes, index, bytes.bytesize - index)
          return if width == 0

          index += width
        end
        nil
      end

      # pm_named_capture_escape: a capture group's name with its escapes
      # read, from the first backslash at `cursor`.
      def named_capture_escape(bytes, cursor, error_location)
        unescaped = bytes.byteslice(0, cursor).b

        loop do
          cursor += 1
          if cursor >= bytes.bytesize
            unescaped << 0x5C
            return unescaped
          end

          case bytes.getbyte(cursor)
          when 0x78 then cursor = named_capture_escape_hex(unescaped, bytes, cursor)
          when 0x30..0x37 then cursor = named_capture_escape_octal(unescaped, bytes, cursor)
          when 0x75 then cursor = named_capture_escape_unicode(unescaped, bytes, cursor, error_location)
          else unescaped << 0x5C
          end

          next_cursor = memchr(bytes, 0x5C, cursor)
          break if next_cursor.nil?

          unescaped << bytes.byteslice(cursor, next_cursor - cursor)
          cursor = next_cursor
        end

        unescaped << bytes.byteslice(cursor..)
      end

      # parse_regular_expression_named_captures: `/(?<name>..)/ =~ value`
      # writes the named groups to locals, through a match write node.
      def parse_regular_expression_named_captures(content, shared, call, extended_mode)
        names = []
        match = nil
        receiver_location = call.receiver.location

        on_name = lambda do |name_start, name_end|
          source = content.byteslice(name_start, name_end - name_start)
          escaped = false

          if (backslash = memchr(source, 0x5C, 0))
            source = named_capture_escape(source, backslash, shared ? nil : receiver_location)
            escaped = true
          end

          # Only a valid local name becomes a local.
          next unless valid_local_bytes?(source)

          if shared && !escaped
            location = loc(shared + name_start, shared + name_start + source.bytesize)
            name = constant_id_location(loc_start(location), loc_end(location))
          else
            location = receiver_location
            name = constant_id_owned(source)
          end

          next if name == 0 || names.include?(name)

          names << name

          depth = local_depth_constant_id(name)
          if depth == -1
            # A keyword is no capture.
            next if local_keyword?(source)

            local_add(name, loc_start(location), loc_end(location), 0)
          end

          match ||= match_write_node(call)
          match.targets << local_variable_target_node(location, constant_symbol(name), depth == -1 ? 0 : depth)
        end

        regexp_parse(content, extended_mode, on_name) do |error_start, error_end, message|
          if shared
            err(shared + error_start, shared + error_end, :regexp_parse_error, message)
          else
            err(loc_start(receiver_location), loc_end(receiver_location), :regexp_parse_error, message)
          end
        end

        match || call
      end

      # pm_slice_is_valid_local over bytes not in the source.
      def valid_local_bytes?(bytes)
        return false if bytes.empty?

        with_source(bytes) { slice_valid_local?(0, bytes.bytesize) }
      end

      # The block's answer with `bytes` as the source the character
      # questions read.
      def with_source(bytes)
        saved_source = @source
        saved_end = @end
        @source = bytes
        @end = bytes.bytesize
        yield
      ensure
        @source = saved_source
        @end = saved_end
      end

      # The kind of target an operator write writes to.
      def operator_write_kind(node)
        case node
        when BackReferenceReadNode, NumberedReferenceReadNode, GlobalVariableReadNode then :global
        when ClassVariableReadNode then :class_variable
        when ConstantPathNode then :constant_path
        when ConstantReadNode then :constant
        when InstanceVariableReadNode then :instance_variable
        when ItLocalVariableReadNode, LocalVariableReadNode then :local_variable
        when CallNode then :call
        when MultiWriteNode then :multi_write
        end
      end

      # `target &&= value`, `target ||= value` and `target op= value`, where
      # `operator` is 0, 1 or 2.
      def parse_operator_write(node, token, operator, previous_binding_power, binding_power, accepts_command_call, depth)
        value_error, multi_error = OPERATOR_WRITE_ERRORS[operator]
        value = -> { parse_assignment_value(previous_binding_power, binding_power, accepts_command_call, value_error, depth + 1) }
        create = ->(kind, *arguments) { send(OPERATOR_WRITES.fetch(kind)[operator], *arguments) }

        case (kind = operator_write_kind(node))
        when :global
          err_node_content(node, :write_target_readonly) unless node.is_a?(GlobalVariableReadNode)
          lex
          create.(kind, node, token, value.())
        when :class_variable, :instance_variable
          lex
          create.(kind, node, token, value.())
        when :constant_path, :constant
          lex
          parse_shareable_constant_write(create.(kind, node, token, value.()))
        when :local_variable
          if node.is_a?(ItLocalVariableReadNode)
            name = local_add_constant("it")
            lex
            result = create.(kind, node, token, value.(), constant_symbol(name), 0)
            node_unreference(node)
            return result
          end

          if numbered_parameter?(node.start_offset, node.end_offset)
            err(node.start_offset, node.end_offset, :parameter_numbered_reserved, @source.byteslice(node.start_offset, 2))
            node_unreference(node)
          end

          lex
          create.(kind, node, token, value.(), node.name, node.depth)
        when :call
          # An op= lexes past the operator before the variable call check.
          lex if operator == 2

          if node.flag?(CallNodeFlags::VARIABLE_CALL)
            # `foo &&= 1` writes the local `foo`.
            message_loc = node.message_loc
            refute_numbered_parameter(loc_start(message_loc), loc_end(message_loc))

            constant_id = local_add_location(loc_start(message_loc), loc_end(message_loc), 1)
            lex unless operator == 2

            return create.(:local_variable, node, token, value.(), constant_symbol(constant_id), 0)
          end

          lex unless operator == 2

          return create.(:index, node, token, value.()) if node.flag?(CALL_NODE_FLAGS_INDEX)

          if call_node_writable?(node)
            node.name = parse_write_name(node.name)
          else
            err_node(node, :write_target_unexpected)
          end

          parse_call_operator_write(node, token)
          create.(kind, node, token, value.())
        when :multi_write
          lex
          err_token(token, multi_error)
          node
        else
          lex

          if operator == 2
            err_previous(:expect_expression_after_operator, Tokens::HUMAN.fetch(@current_type))
          else
            err_token(token, value_error)
          end
          node
        end
      end

      # Whether a match (`=>` or `in`) ends the right side of a rescue
      # modifier, `and` or `or`, which an operator may not follow.
      def match_after_operator?(node)
        right =
          case node
          when RescueModifierNode then node.rescue_expression
          when AndNode, OrNode then node.right
          end
        right.is_a?(MatchPredicateNode) || right.is_a?(MatchRequiredNode)
      end

      # `target = value`
      def parse_write_expression(node, token, previous_binding_power, binding_power, accepts_command_call, depth)
        case node
        when CallNode, ClassVariableReadNode, ConstantPathNode, ConstantReadNode, GlobalVariableReadNode,
             LocalVariableReadNode, InstanceVariableReadNode, MultiTargetNode, BackReferenceReadNode,
             NumberedReferenceReadNode, ItLocalVariableReadNode
          # A method call named like a local becomes one before its value.
          if node.is_a?(CallNode) && node.flag?(CallNodeFlags::VARIABLE_CALL)
            local_add_location(loc_start(node.message_loc), loc_end(node.message_loc), 0)
          end

          # `it = value` makes `it` a local before the value.
          local_add_location(node.start_offset, node.end_offset, 0) if node.is_a?(ItLocalVariableReadNode)

          lex
          value_power = node.is_a?(MultiTargetNode) ? BINDING_POWER_MULTI_ASSIGNMENT + 1 : binding_power
          value = parse_assignment_values(previous_binding_power, value_power, accepts_command_call, :expect_expression_after_equal, depth + 1)

          if node.is_a?(MultiTargetNode) && previous_binding_power != BINDING_POWER_STATEMENT
            err_node(node, :unexpected_multi_write)
          end

          parse_write(node, token, value)
        when SplatNode
          multi_target = multi_target_node
          multi_target_node_targets_append(multi_target, node)

          lex
          value = parse_assignment_values(previous_binding_power, BINDING_POWER_MULTI_ASSIGNMENT + 1, accepts_command_call, :expect_expression_after_equal, depth + 1)
          parse_write(multi_target, token, value)
        when SourceEncodingNode, FalseNode, SourceFileNode, SourceLineNode, NilNode, SelfNode, TrueNode
          lex
          value = parse_assignment_values(previous_binding_power, binding_power, accepts_command_call, :expect_expression_after_equal, depth + 1)
          parse_unwriteable_write(node, token, value)
        else
          lex
          err_token(token, :expression_not_writable)
          node
        end
      end

      # `left =~ right`, which writes named captures of a regexp literal.
      def parse_match_expression(node, token, binding_power, depth)
        # The value parses before the captures become locals.
        lex
        argument = parse_expression(binding_power, false, false, :expect_expression_after_operator, depth + 1)

        call = call_node_binary(node, token, argument, 0)

        case node
        when InterpolatedRegularExpressionNode
          # A regexp split by a heredoc may hold strings only.
          parts = node.parts
          return call unless parts.all? { |part| part.is_a?(StringNode) }

          content = parts.map(&:unescaped).join.b
          return call if content.empty?

          parse_regular_expression_named_captures(content, nil, call, node.flag?(RegularExpressionFlags::EXTENDED))
        when RegularExpressionNode
          content = node.unescaped
          parse_regular_expression_named_captures(content, @shared_strings[content], call, node.flag?(RegularExpressionFlags::EXTENDED))
        else
          call
        end
      end

      # `receiver.message(arguments)` and `receiver&.message`
      def parse_call_expression(node, previous_binding_power, accepts_command_call, depth)
        lex
        operator = previous_token
        arguments = Arguments.new

        # foo.()
        if @current_type == :PARENTHESIS_LEFT
          parse_arguments_list(arguments, true, false, depth + 1)
          return call_node_shorthand(node, operator, arguments)
        end

        err_token(operator, :expect_eol_after_statement, Tokens::HUMAN.fetch(operator.type)) if match_after_operator?(node)

        case @current_type
        when *CASE_OPERATOR, *CASE_KEYWORD, :CONSTANT, :IDENTIFIER, :METHOD_NAME
          lex
          message = previous_token
        else
          err_current(:expect_message, Tokens::HUMAN.fetch(@current_type))
          message = Token.new(:MISSING, @previous_end, @previous_end)
        end

        parse_arguments_list(arguments, true, accepts_command_call, depth + 1)
        call = call_node_call(node, operator, message, arguments)

        if previous_binding_power == BINDING_POWER_STATEMENT && arguments.arguments.nil? && arguments.opening_loc.nil? &&
           @current_type == :COMMA
          return parse_targets_validate(call, BINDING_POWER_INDEX, depth + 1)
        end

        call
      end

      # `receiver::Constant` and `receiver::method`
      def parse_colon_colon_expression(node, previous_binding_power, accepts_command_call, depth)
        lex
        delimiter = previous_token

        case @current_type
        when :CONSTANT
          lex

          if @current_type == :PARENTHESIS_LEFT ||
             (accepts_command_call && (token_begins_expression?(@current_type) || match?(:UAMPERSAND, :USTAR, :USTAR_STAR)))
            # Foo::Bar() calls Bar.
            message = previous_token
            arguments = Arguments.new

            parse_arguments_list(arguments, true, accepts_command_call, depth + 1)
            path = call_node_call(node, delimiter, message, arguments)
          else
            path = constant_path_node(node, delimiter, previous_token)
          end

          return parse_targets_validate(path, BINDING_POWER_INDEX, depth + 1) if previous_binding_power == BINDING_POWER_STATEMENT && @current_type == :COMMA

          path
        when *CASE_OPERATOR, *CASE_KEYWORD, :IDENTIFIER, :METHOD_NAME
          lex
          message = previous_token

          arguments = Arguments.new
          parse_arguments_list(arguments, true, accepts_command_call, depth + 1)
          call = call_node_call(node, delimiter, message, arguments)

          return parse_targets_validate(call, BINDING_POWER_INDEX, depth + 1) if previous_binding_power == BINDING_POWER_STATEMENT && @current_type == :COMMA

          call
        when :PARENTHESIS_LEFT
          # Foo::(bar)
          arguments = Arguments.new
          parse_arguments_list(arguments, true, false, depth + 1)

          call_node_shorthand(node, delimiter, arguments)
        else
          expect(:CONSTANT, :constant_path_colon_colon_constant)
          constant_path_node(node, delimiter, previous_token)
        end
      end

      # `receiver[arguments]`
      def parse_index_expression(node, previous_binding_power, depth)
        lex

        arguments = Arguments.new
        arguments.opening_loc = previous_token.location

        unless accept(:BRACKET_RIGHT)
          accepts_block_stack_push(true)
          parse_arguments(arguments, false, :BRACKET_RIGHT, depth + 1)
          accepts_block_stack_pop
          expect(:BRACKET_RIGHT, :expect_rbracket)
        end

        arguments.closing_loc = previous_token.location

        # foo[1], bar = ...
        if previous_binding_power == BINDING_POWER_STATEMENT && @current_type == :COMMA
          return parse_targets_validate(call_node_aref(node, arguments), BINDING_POWER_INDEX, depth + 1)
        end

        block = nil
        if accept(:BRACE_LEFT)
          block = parse_block(depth + 1)
          arguments_validate_block(arguments, block)
        elsif accepts_block_stack? && accept(:KEYWORD_DO)
          block = parse_block(depth + 1)
        end

        if block
          if arguments.block
            err_node(block, :argument_after_block)
            arguments.arguments ||= arguments_node
            arguments_node_arguments_append(arguments.arguments, arguments.block)
          end

          arguments.block = block
        end

        call_node_aref(node, arguments)
      end

      # `value ? a : b`
      def parse_ternary(node, depth)
        context_push(:ternary)
        previous_block_exits = push_block_exits([])

        qmark = current_token
        lex

        true_expression = parse_expression(BINDING_POWER_DEFINED, false, false, :ternary_expression_true, depth + 1)

        if @recovering
          # Missing pieces stand in before `expect` can pass a later `:`.
          colon = Token.new(:MISSING, @previous_end, @previous_end)
          false_expression = missing_node(colon.start, colon.end)

          context_pop
          pop_block_exits(previous_block_exits)

          return if_node_ternary(node, qmark, true_expression, colon, false_expression)
        end

        accept(:NEWLINE)
        expect(:COLON, :ternary_colon)

        colon = previous_token
        false_expression = parse_expression(BINDING_POWER_DEFINED, false, false, :ternary_expression_false, depth + 1)

        context_pop
        pop_block_exits(previous_block_exits)

        if_node_ternary(node, qmark, true_expression, colon, false_expression)
      end

      # `value in pattern` and `value => pattern`
      def parse_match_pattern(node, required, depth)
        previous_pattern_matching_newlines = @pattern_matching_newlines
        @pattern_matching_newlines = true

        operator = current_token
        @command_start = false
        @lex_state = STATE_BEG | STATE_LABEL
        lex

        diag_id = required ? :pattern_expression_after_hrocket : :pattern_expression_after_in
        pattern = parse_pattern([], PARSE_PATTERN_TOP | PARSE_PATTERN_MULTI, diag_id, depth + 1)

        @pattern_matching_newlines = previous_pattern_matching_newlines

        required ? match_required_node(node, pattern, operator) : match_predicate_node(node, pattern, operator)
      end

      # parse_expression_infix: the infix operator at the current token
      # applied to `node`.
      def parse_expression_infix(node, previous_binding_power, binding_power, accepts_command_call, depth)
        token = current_token

        case token.type
        when :EQUAL then parse_write_expression(node, token, previous_binding_power, binding_power, accepts_command_call, depth)
        when :AMPERSAND_AMPERSAND_EQUAL
          parse_operator_write(node, token, 0, previous_binding_power, binding_power, accepts_command_call, depth)
        when :PIPE_PIPE_EQUAL
          parse_operator_write(node, token, 1, previous_binding_power, binding_power, accepts_command_call, depth)
        when *OPERATOR_ASSIGNMENTS
          parse_operator_write(node, token, 2, previous_binding_power, binding_power, accepts_command_call, depth)
        when :AMPERSAND_AMPERSAND, :KEYWORD_AND
          lex
          right = parse_expression(binding_power, @previous_type == :KEYWORD_AND, false, :expect_expression_after_operator, depth + 1)
          and_node(node, token, right)
        when :KEYWORD_OR, :PIPE_PIPE
          lex
          right = parse_expression(binding_power, @previous_type == :KEYWORD_OR, false, :expect_expression_after_operator, depth + 1)
          or_node(node, token, right)
        when :EQUAL_TILDE then parse_match_expression(node, token, binding_power, depth)
        when *BINARY_OPERATORS
          lex
          operator = previous_token
          err_token(operator, :expect_eol_after_statement, Tokens::HUMAN.fetch(operator.type)) if match_after_operator?(node)

          argument = parse_expression(binding_power, false, false, :expect_expression_after_operator, depth + 1)
          call_node_binary(node, token, argument, 0)
        when :GREATER, :GREATER_EQUAL, :LESS, :LESS_EQUAL
          if node.is_a?(CallNode) && node.flag?(CALL_NODE_FLAGS_COMPARISON)
            warn_token_content(current_token, :comparison_after_comparison)
          end

          lex
          argument = parse_expression(binding_power, false, false, :expect_expression_after_operator, depth + 1)
          call_node_binary(node, token, argument, CALL_NODE_FLAGS_COMPARISON)
        when :AMPERSAND_DOT, :DOT then parse_call_expression(node, previous_binding_power, accepts_command_call, depth)
        when :DOT_DOT, :DOT_DOT_DOT
          lex

          right = nil
          if token_begins_expression?(@current_type)
            right = parse_expression(binding_power, false, false, :expect_expression_after_operator, depth + 1)
          end

          range_node(node, token, right)
        when :KEYWORD_IF_MODIFIER, :KEYWORD_UNLESS_MODIFIER
          keyword = current_token
          lex

          if keyword.type == :KEYWORD_IF_MODIFIER
            predicate = parse_value_expression(binding_power, true, false, :conditional_if_predicate, depth + 1)
            if_node_modifier(node, keyword, predicate)
          else
            predicate = parse_value_expression(binding_power, true, false, :conditional_unless_predicate, depth + 1)
            unless_node_modifier(node, keyword, predicate)
          end
        when :KEYWORD_UNTIL_MODIFIER, :KEYWORD_WHILE_MODIFIER
          lex
          statements = statements_node
          statements_node_body_append(statements, node, true)

          flags = node.is_a?(BeginNode) ? LoopFlags::BEGIN_MODIFIER : 0
          if token.type == :KEYWORD_UNTIL_MODIFIER
            predicate = parse_value_expression(binding_power, true, false, :conditional_until_predicate, depth + 1)
            until_node_modifier(token, predicate, statements, flags)
          else
            predicate = parse_value_expression(binding_power, true, false, :conditional_while_predicate, depth + 1)
            while_node_modifier(token, predicate, statements, flags)
          end
        when :QUESTION_MARK then parse_ternary(node, depth)
        when :COLON_COLON then parse_colon_colon_expression(node, previous_binding_power, accepts_command_call, depth)
        when :KEYWORD_RESCUE_MODIFIER
          context_push(:rescue_modifier)
          lex
          accept(:NEWLINE)

          value = parse_expression(binding_power, true, false, :rescue_modifier_value, depth + 1)
          context_pop

          rescue_modifier_node(node, token, value)
        when :BRACKET_LEFT then parse_index_expression(node, previous_binding_power, depth)
        when :KEYWORD_IN then parse_match_pattern(node, false, depth)
        when :EQUAL_GREATER then parse_match_pattern(node, true, depth)
        end
      end

      # pm_call_node_command_p: arguments or a block argument, without
      # parentheses.
      def call_node_command?(node)
        node.opening_loc.nil? && (node.block.nil? || node.block.is_a?(BlockArgumentNode)) &&
          (!node.arguments.nil? || !node.block.nil?)
      end

      # PRISM_DEPTH_MAXIMUM
      DEPTH_MAXIMUM = 10_000

      # The statements that end an expression unless a modifier follows.
      STATEMENT_NODES = [PreExecutionNode, PostExecutionNode, AliasGlobalVariableNode, AliasMethodNode, MultiWriteNode, UndefNode].freeze

      # The writes that end an expression when their value is an array
      # without brackets.
      IMPLICIT_ARRAY_WRITES = [ClassVariableWriteNode, ConstantPathWriteNode, ConstantWriteNode, GlobalVariableWriteNode,
                               InstanceVariableWriteNode, LocalVariableWriteNode].freeze

      # parse_expression: an expression, and the infix operators that bind at
      # least as tightly as `binding_power`.
      def parse_expression(binding_power, accepts_command_call, accepts_label, diag_id, depth)
        if depth >= DEPTH_MAXIMUM
          err_current(:nesting_too_deep)
          return missing_node(@current_start, @current_end)
        end

        node = parse_expression_prefix(binding_power, accepts_command_call, accepts_label, diag_id, depth)

        case node
        when MissingNode
          return node
        when *STATEMENT_NODES
          return node if BINDING_POWERS[@current_type].left > BINDING_POWER_MODIFIER
        when CallNode
          # A command call takes only composition and modifiers.
          return node if BINDING_POWERS[@current_type].left > BINDING_POWER_COMPOSITION && call_node_command?(node)
        when SymbolNode
          # A label is never followed by an operator.
          return node if symbol_node_label?(node)
        end

        loop do
          current_type = @current_type
          powers = BINDING_POWERS[current_type]
          break unless binding_power <= powers.left && powers.binary

          node = parse_expression_infix(node, binding_power, powers.right, accepts_command_call, depth + 1)

          # A token that ends the context makes the expression a statement.
          return node if context_terminator?(current_context, @current_type)

          case node
          when MultiWriteNode
            return node if BINDING_POWERS[@current_type].left > BINDING_POWER_MODIFIER
          when *IMPLICIT_ARRAY_WRITES
            if node.flag?(WRITE_NODE_FLAGS_IMPLICIT_ARRAY) && BINDING_POWERS[@current_type].left > BINDING_POWER_MODIFIER
              return node
            end
          when CallNode
            if node.flag?(CALL_NODE_FLAGS_IMPLICIT_ARRAY) && BINDING_POWERS[@current_type].left > BINDING_POWER_MODIFIER
              return node
            end
          end

          if powers.nonassoc
            # The same non-associative operator again is an error.
            if @current_type == current_type
              err_current(:non_associative_operator, Tokens::HUMAN.fetch(@current_type), Tokens::HUMAN.fetch(current_type))
              break
            end

            if node.is_a?(RangeNode) && node.right.nil?
              # `1.. & 2` and `1.. * 2`
              if match?(:UAMPERSAND, :USTAR, :DOT, :AMPERSAND_DOT)
                err_current(:non_associative_operator, Tokens::HUMAN.fetch(@current_type), Tokens::HUMAN.fetch(current_type))
                break
              end

              break if BINDING_POWER_TERM <= BINDING_POWERS[@current_type].left
            elsif powers.left <= BINDING_POWERS[@current_type].left
              break
            end
          end

          # A command call continues only a method chain.
          if accepts_command_call
            case node
            when CallNode
              message_loc = node.message_loc
              index = node.call_operator_loc.nil? && message_loc &&
                      @source.getbyte(loc_start(message_loc)) == 0x5B && @source.getbyte(loc_end(message_loc) - 1) == 0x5D
              attribute = node.call_operator_loc && node.arguments.nil? && node.block.nil? && node.opening_loc.nil?
              parenthesized = node.call_operator_loc && node.opening_loc
              with_block = node.block.is_a?(BlockNode)
              accepts_command_call = false unless index || attribute || parenthesized || with_block
            when ConstantPathNode
              # Foo::Bar
            else
              accepts_command_call = false
            end
          end
        end

        node
      end

      # wrap_statements: -p, -n, -a and -l as the loop and statements they
      # add.
      def wrap_statements(statements)
        if command_line?(Options::COMMAND_LINE["p"])
          statements ||= statements_node

          arguments = arguments_node
          arguments_node_arguments_append(arguments, global_variable_read_node_synthesized(constant_name("$_")))

          statements_node_body_append(statements, call_node_fcall_synthesized(arguments, constant_name("print")), true)
        end

        if command_line?(Options::COMMAND_LINE["n"])
          if command_line?(Options::COMMAND_LINE["a"])
            statements ||= statements_node

            arguments = arguments_node
            arguments_node_arguments_append(arguments, global_variable_read_node_synthesized(constant_name("$;")))

            receiver = global_variable_read_node_synthesized(constant_name("$_"))
            call = call_node_call_synthesized(receiver, "split", arguments)

            write = global_variable_write_node_synthesized(constant_name("$F"), call)

            statements_node_body_prepend(statements, write)
          end

          arguments = arguments_node
          arguments_node_arguments_append(arguments, global_variable_read_node_synthesized(constant_name("$/")))

          if command_line?(Options::COMMAND_LINE["l"])
            keywords = keyword_hash_node
            keyword_hash_node_elements_append(keywords, assoc_node(symbol_node_synthesized("chomp"), NOT_PROVIDED, true_node_synthesized))

            arguments_node_arguments_append(arguments, keywords)
            arguments.flag_set(ArgumentsNodeFlags::CONTAINS_KEYWORDS)
          end

          wrapped_statements = statements_node
          loop_node = while_node_synthesized(call_node_fcall_synthesized(arguments, constant_name("gets")), statements)
          statements_node_body_append(wrapped_statements, loop_node, true)

          statements = wrapped_statements
        end

        statements
      end

      public

      # parse_program: the whole source as a program node.
      def parse_program
        # Scopes given in the options are already pushed.
        scope_push(true) if @current_scope.nil?

        previous_block_exits = push_block_exits([])

        lex
        statements = parse_statements(:main, 0)

        # The last statement's value is checked here, as parse_statements
        # checks all but the last.
        void_statement_check(statements.body.last) if statements && !@parsing_eval

        locals = locals_order(@current_scope.locals, true)
        scope_pop

        if @command_line.anybits?(Options::COMMAND_LINE["p"] | Options::COMMAND_LINE["n"])
          statements = wrap_statements(statements)
        else
          flush_block_exits(previous_block_exits)
        end

        # An empty file still gathers its comments; its statements sit at the
        # start.
        if statements.nil?
          statements = statements_node
          statements_node_location_set(statements, 0, 0)
        end

        program_node(locals, statements)
      end
    end
  end
end
