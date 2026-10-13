# frozen_string_literal: true
# shareable_constant_value: literal

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
      }

      # The errors of each operator write: [value missing, multiple write].
      OPERATOR_WRITE_ERRORS = [
        %i[expect_expression_after_ampampeq ampampeq_multi_assign],
        %i[expect_expression_after_pipepipeeq pipepipeeq_multi_assign],
        %i[expect_expression_after_operator operator_multi_assign]
      ]

      # The binary operators that may follow a rescue modifier's or `and`'s
      # match only on a new statement.
      BINARY_OPERATORS = %i[
        UAMPERSAND USTAR USTAR_STAR BANG_EQUAL BANG_TILDE EQUAL_EQUAL EQUAL_EQUAL_EQUAL LESS_EQUAL_GREATER CARET PIPE
        AMPERSAND GREATER_GREATER LESS_LESS MINUS PLUS PERCENT SLASH STAR STAR_STAR
      ]

      OPERATOR_ASSIGNMENTS = %i[
        AMPERSAND_EQUAL CARET_EQUAL GREATER_GREATER_EQUAL LESS_LESS_EQUAL MINUS_EQUAL PERCENT_EQUAL PIPE_EQUAL
        PLUS_EQUAL SLASH_EQUAL STAR_EQUAL STAR_STAR_EQUAL
      ]

      private

      # parse_rescue_modifier_terminator: an operator above the modifiers
      # after a statement that a rescue modifier rescues to is an error;
      # it and its right side are skipped.
      def parse_rescue_modifier_terminator(flags, depth)
        return unless BINDING_POWERS[@current_type].left > BINDING_POWER_MODIFIER

        err_current(:expect_eol_after_statement, Tokens::HUMAN.fetch(@current_type))
        lex
        parse_expression(BINDING_POWERS[@previous_type].right, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_operator, depth + 1)
      end

      # A command call, with or without a block, as a value.
      def command_value?(node) = command_call_value?(node) || block_call?(node)

      # A pattern match, which is a statement.
      def match_node?(node) = node.is_a?(MatchRequiredNode) || node.is_a?(MatchPredicateNode)

      # parse_assignment_value: the value of an operator write, which may
      # take a rescue modifier.
      def parse_assignment_value(previous_binding_power, binding_power, flags, diag_id, depth)
        value_flags = flags & ACCEPTS_DO_BLOCK
        if previous_binding_power == BINDING_POWER_ASSIGNMENT
          value_flags |= flags & ACCEPTS_COMMAND_CALL
        elsif previous_binding_power < BINDING_POWER_MATCH
          value_flags |= ACCEPTS_COMMAND_CALL
        end
        value = parse_value_expression(binding_power, value_flags, diag_id, depth + 1)

        # `a = b c` takes only modifiers after it.
        parse_rescue_modifier_terminator(flags, depth) if command_value?(value)

        return value unless @current_type == :KEYWORD_RESCUE_MODIFIER

        context_push(:rescue_modifier)

        rescue_keyword = current_token
        lex

        # The rescue value is a statement when the value is a command call.
        statement_value = command_value?(value)
        rescue_flags = (flags & ACCEPTS_DO_BLOCK) | (statement_value ? ACCEPTS_COMMAND_CALL : 0)

        right = parse_rescue_modifier_value(rescue_flags, statement_value, depth + 1)
        context_pop

        parse_rescue_modifier_terminator(flags, depth) if match_node?(right)

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
      def parse_assignment_values(previous_binding_power, binding_power, flags, diag_id, depth)
        statement_level = previous_binding_power == BINDING_POWER_STATEMENT || flags.anybits?(ACCEPTS_STATEMENT)
        permitted = statement_level || @current_type != :USTAR

        # A command call is a value of a plain write, or of any write at a
        # statement.
        command_call_flag =
          if previous_binding_power == BINDING_POWER_ASSIGNMENT
            flags & ACCEPTS_COMMAND_CALL
          elsif previous_binding_power < BINDING_POWER_MODIFIER || statement_level
            ACCEPTS_COMMAND_CALL
          else
            0
          end

        value = parse_starred_expression(binding_power, (flags & ACCEPTS_DO_BLOCK) | command_call_flag, diag_id, depth + 1)
        err_node(value, :unexpected_multi_write) unless permitted

        parse_assignment_value_local(value)
        single_value = true

        # A block call may not start several values.
        if statement_level && !block_call?(value) && (value.is_a?(SplatNode) || @current_type == :COMMA)
          single_value = false

          array = array_node(NOT_PROVIDED)
          array_node_elements_append(array, value)
          value = array

          while accept(:COMMA)
            element = parse_starred_expression(binding_power, 0, :array_element, depth + 1)

            array_node_elements_append(array, element)
            break if element.is_a?(ErrorRecoveryNode)

            parse_assignment_value_local(element)
          end
        end

        # `a = b c` takes only modifiers after it.
        parse_rescue_modifier_terminator(flags, depth) if single_value && command_value?(value)

        multiple_assignment = binding_power == BINDING_POWER_MULTI_ASSIGNMENT + 1
        if (single_value || multiple_assignment) && @current_type == :KEYWORD_RESCUE_MODIFIER
          command_value = command_value?(value)

          # `x, y = foo bar rescue z` rescues the whole statement.
          return value if multiple_assignment && command_value

          context_push(:rescue_modifier)

          rescue_keyword = current_token
          lex

          statement_value = multiple_assignment || command_value
          rescue_flags = (flags & ACCEPTS_DO_BLOCK) | (statement_value ? ACCEPTS_COMMAND_CALL : 0)

          right = parse_rescue_modifier_value(rescue_flags, statement_value, depth + 1)
          context_pop

          parse_rescue_modifier_terminator(flags, depth) if match_node?(right)

          return rescue_modifier_node(value, rescue_keyword, right)
        end

        value
      end

      # parse_rescue_modifier_value: the value after a rescue modifier. A
      # statement value may be a multiple write; another is an argument
      # above `and`, `or` and `not`.
      def parse_rescue_modifier_value(flags, statement, depth)
        return parse_expression(BINDING_POWER_DEFINED, flags, :rescue_modifier_value, depth + 1) unless statement

        if @current_type == :USTAR
          # A splat starts only the targets of a multiple write.
          lex
          value = parse_splat(flags, depth)
          multiple = true
        else
          value = parse_expression(BINDING_POWERS[:KEYWORD_RESCUE_MODIFIER].right, flags | ACCEPTS_STATEMENT, :rescue_modifier_value, depth + 1)
          multiple = @current_type == :COMMA || value.is_a?(MultiTargetNode)
        end

        if multiple
          target = parse_targets_validate(value, BINDING_POWER_INDEX, depth + 1)

          # Targets are a value only with `= values`.
          unless @current_type == :EQUAL
            err_node(target, :write_target_unexpected) if @current_type == :PARENTHESIS_RIGHT
            return target
          end

          operator = current_token
          lex

          values = parse_assignment_values(BINDING_POWER_STATEMENT, BINDING_POWER_MULTI_ASSIGNMENT + 1, flags, :expect_expression_after_equal, depth + 1)
          value = parse_write(target, operator, values)
        end

        parse_rescue_modifier_terminator(flags, depth) unless match_node?(value)

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

      # parse_regular_expression_named_capture: `/(?<name>..)/ =~ value`
      # writes the named groups of `content` to locals, through a match
      # write node. It returns the callback for each name, and a lambda for
      # the match write node, or nil when no name became a local.
      def regular_expression_named_captures(content, shared, call)
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

        [on_name, -> { match }]
      end

      # pm_slice_is_valid_local over bytes not in the source.
      def valid_local_bytes?(bytes)
        return false if bytes.empty?

        with_source(bytes) { slice_valid_local?(0, bytes.bytesize) }
      end

      # The block's return value, with `bytes` as the source that the
      # character functions read.
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
      def parse_operator_write(node, token, operator, previous_binding_power, binding_power, flags, depth)
        value_error, multi_error = OPERATOR_WRITE_ERRORS[operator]
        value = -> { parse_assignment_value(previous_binding_power, binding_power, flags, value_error, depth + 1) }
        create = ->(kind, *arguments) { send(OPERATOR_WRITES.fetch(kind)[operator], *arguments) }

        case (kind = operator_write_kind(node))
        when :global
          err_node_content(node, :write_target_readonly) unless node.is_a?(GlobalVariableReadNode)
          lex
          create.(kind, node, token, value.())
        when :class_variable, :instance_variable
          lex
          create.(kind, node, token, value.())
        when :constant_path
          lex
          parse_shareable_constant_write(create.(kind, node, token, value.()))
        when :constant
          lex
          write = create.(kind, node, token, value.())
          # A dynamic constant assignment.
          err_node(write, :write_target_in_method) if context_def?
          parse_shareable_constant_write(write)
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
      def parse_write_expression(node, token, previous_binding_power, binding_power, flags, depth)
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
          value = parse_assignment_values(previous_binding_power, value_power, flags, :expect_expression_after_equal, depth + 1)

          if node.is_a?(MultiTargetNode) && previous_binding_power != BINDING_POWER_STATEMENT && !flags.anybits?(ACCEPTS_STATEMENT)
            err_node(node, :unexpected_multi_write)
          end

          parse_write(node, token, value)
        when SplatNode
          multi_target = multi_target_node
          multi_target_node_targets_append(multi_target, node)

          lex
          value = parse_assignment_values(previous_binding_power, BINDING_POWER_MULTI_ASSIGNMENT + 1, flags, :expect_expression_after_equal, depth + 1)
          parse_write(multi_target, token, value)
        when SourceEncodingNode, FalseNode, SourceFileNode, SourceLineNode, NilNode, SelfNode, TrueNode
          lex
          value = parse_assignment_values(previous_binding_power, binding_power, flags, :expect_expression_after_equal, depth + 1)
          parse_unwriteable_write(node, token, value)
        else
          lex
          err_token(token, :expression_not_writable)
          node
        end
      end

      # `left =~ right`, which writes named captures of a regexp literal.
      def parse_match_expression(node, token, binding_power, flags, depth)
        # The value parses before the captures become locals.
        lex
        argument = parse_expression(binding_power, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_operator, depth + 1)

        call = call_node_binary(node, token, argument, 0)

        case node
        when InterpolatedRegularExpressionNode
          # A regexp split by a heredoc may hold strings only.
          parts = node.parts
          return call unless parts.all? { |part| part.is_a?(StringNode) }

          content = parts.map(&:unescaped).join.b
          return call if content.empty?

          # parse_interpolated_regular_expression_named_captures: the
          # joined bytes are no slice of the source.
          on_name, match = regular_expression_named_captures(content, nil, call)
          regexp_parse_named_captures(content, nil, node.flag?(RegularExpressionFlags::EXTENDED), on_name, node.location)
          match.call || call
        when RegularExpressionNode
          # The regexp's encoding check waited for its named captures.
          on_name, match = regular_expression_named_captures(node.unescaped, @shared_strings[node.unescaped], call)
          node.flag_set(regexp_parse(node, on_name))
          match.call || call
        else
          call
        end
      end

      # `receiver.message(arguments)` and `receiver&.message`
      def parse_call_expression(node, previous_binding_power, flags, depth)
        lex
        operator = previous_token
        arguments = Arguments.new

        # foo.()
        if @current_type == :PARENTHESIS_LEFT
          parse_arguments_list(arguments, true, 0, depth + 1)
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

        parse_arguments_list(arguments, true, flags, depth + 1)
        call = call_node_call(node, operator, message, arguments)

        if previous_binding_power == BINDING_POWER_STATEMENT && arguments.arguments.nil? && arguments.opening_loc.nil? &&
           @current_type == :COMMA
          return parse_targets_validate(call, BINDING_POWER_INDEX, depth + 1)
        end

        call
      end

      # `receiver::Constant` and `receiver::method`
      def parse_colon_colon_expression(node, previous_binding_power, flags, depth)
        lex
        delimiter = previous_token

        case @current_type
        when :CONSTANT
          lex

          if @current_type == :PARENTHESIS_LEFT ||
             (flags.anybits?(ACCEPTS_COMMAND_CALL) && (token_begins_expression?(@current_type) || match?(:UAMPERSAND, :USTAR, :USTAR_STAR)))
            # Foo::Bar() calls Bar.
            message = previous_token
            arguments = Arguments.new

            parse_arguments_list(arguments, true, flags, depth + 1)
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
          parse_arguments_list(arguments, true, flags, depth + 1)
          call = call_node_call(node, delimiter, message, arguments)

          return parse_targets_validate(call, BINDING_POWER_INDEX, depth + 1) if previous_binding_power == BINDING_POWER_STATEMENT && @current_type == :COMMA

          call
        when :PARENTHESIS_LEFT
          # Foo::(bar)
          arguments = Arguments.new
          parse_arguments_list(arguments, true, 0, depth + 1)

          call_node_shorthand(node, delimiter, arguments)
        else
          expect(:CONSTANT, :constant_path_colon_colon_constant)
          constant_path_node(node, delimiter, previous_token)
        end
      end

      # `receiver[arguments]`
      def parse_index_expression(node, previous_binding_power, flags, depth)
        lex

        arguments = Arguments.new
        arguments.opening_loc = previous_token.location

        unless accept(:BRACKET_RIGHT)
          parse_arguments(arguments, false, :BRACKET_RIGHT, flags & ~ACCEPTS_DO_BLOCK, depth + 1)
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
      def parse_ternary(node, flags, depth)
        context_push(:ternary)
        previous_block_exits = push_block_exits([])

        qmark = current_token
        lex

        true_expression = parse_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :ternary_expression_true, depth + 1)

        if @recovering
          # Placeholders for missing pieces go in before `expect` can pass a later `:`.
          colon = Token.new(:MISSING, @previous_end, @previous_end)
          false_expression = error_recovery_node(colon.start, colon.end)

          context_pop
          pop_block_exits(previous_block_exits)

          return if_node_ternary(node, qmark, true_expression, colon, false_expression)
        end

        accept(:NEWLINE)
        expect(:COLON, :ternary_colon)

        colon = previous_token
        false_expression = parse_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :ternary_expression_false, depth + 1)

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
      def parse_expression_infix(node, previous_binding_power, binding_power, flags, depth)
        token = current_token

        case token.type
        when :EQUAL then parse_write_expression(node, token, previous_binding_power, binding_power, flags, depth)
        when :AMPERSAND_AMPERSAND_EQUAL
          parse_operator_write(node, token, 0, previous_binding_power, binding_power, flags, depth)
        when :PIPE_PIPE_EQUAL
          parse_operator_write(node, token, 1, previous_binding_power, binding_power, flags, depth)
        when *OPERATOR_ASSIGNMENTS
          parse_operator_write(node, token, 2, previous_binding_power, binding_power, flags, depth)
        when :AMPERSAND_AMPERSAND, :KEYWORD_AND
          lex
          right = parse_expression(binding_power, (flags & ACCEPTS_DO_BLOCK) | (@previous_type == :KEYWORD_AND ? ACCEPTS_COMMAND_CALL : 0), :expect_expression_after_operator, depth + 1)
          and_node(node, token, right)
        when :KEYWORD_OR, :PIPE_PIPE
          lex
          right = parse_expression(binding_power, (flags & ACCEPTS_DO_BLOCK) | (@previous_type == :KEYWORD_OR ? ACCEPTS_COMMAND_CALL : 0), :expect_expression_after_operator, depth + 1)
          or_node(node, token, right)
        when :EQUAL_TILDE then parse_match_expression(node, token, binding_power, flags, depth)
        when *BINARY_OPERATORS
          lex
          operator = previous_token
          err_token(operator, :expect_eol_after_statement, Tokens::HUMAN.fetch(operator.type)) if match_after_operator?(node)

          argument = parse_expression(binding_power, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_operator, depth + 1)
          call_node_binary(node, token, argument, 0)
        when :GREATER, :GREATER_EQUAL, :LESS, :LESS_EQUAL
          if node.is_a?(CallNode) && node.flag?(CALL_NODE_FLAGS_COMPARISON)
            warn_token_content(current_token, :comparison_after_comparison)
          end

          lex
          argument = parse_expression(binding_power, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_operator, depth + 1)
          call_node_binary(node, token, argument, CALL_NODE_FLAGS_COMPARISON)
        when :AMPERSAND_DOT, :DOT then parse_call_expression(node, previous_binding_power, flags, depth)
        when :DOT_DOT, :DOT_DOT_DOT
          lex

          right = nil
          if token_begins_expression?(@current_type)
            right = parse_expression(binding_power, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_operator, depth + 1)
          end

          range_node(node, token, right)
        when :KEYWORD_IF_MODIFIER, :KEYWORD_UNLESS_MODIFIER
          keyword = current_token
          lex

          if keyword.type == :KEYWORD_IF_MODIFIER
            predicate = parse_value_expression(binding_power, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :conditional_if_predicate, depth + 1)
            if_node_modifier(node, keyword, predicate)
          else
            predicate = parse_value_expression(binding_power, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :conditional_unless_predicate, depth + 1)
            unless_node_modifier(node, keyword, predicate)
          end
        when :KEYWORD_UNTIL_MODIFIER, :KEYWORD_WHILE_MODIFIER
          lex
          statements = statements_node
          statements_node_body_append(statements, node, true)

          loop_flags = node.is_a?(BeginNode) ? LoopFlags::BEGIN_MODIFIER : 0
          if token.type == :KEYWORD_UNTIL_MODIFIER
            predicate = parse_value_expression(binding_power, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :conditional_until_predicate, depth + 1)
            until_node_modifier(token, predicate, statements, loop_flags)
          else
            predicate = parse_value_expression(binding_power, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :conditional_while_predicate, depth + 1)
            while_node_modifier(token, predicate, statements, loop_flags)
          end
        when :QUESTION_MARK then parse_ternary(node, flags, depth)
        when :COLON_COLON then parse_colon_colon_expression(node, previous_binding_power, flags, depth)
        when :KEYWORD_RESCUE_MODIFIER
          context_push(:rescue_modifier)
          lex
          accept(:NEWLINE)

          value = parse_rescue_modifier_value((flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, previous_binding_power == BINDING_POWER_STATEMENT, depth + 1)
          context_pop

          rescue_modifier_node(node, token, value)
        when :BRACKET_LEFT then parse_index_expression(node, previous_binding_power, flags, depth)
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

      # pm_constant_path_command_call_p: `Foo::Bar { }`, a command with a
      # brace block that takes no operators.
      def constant_path_command_call?(call)
        call.receiver && call.opening_loc.nil? && call.block.is_a?(BlockNode) && call.call_operator_loc &&
          @source.getbyte(loc_start(call.call_operator_loc)) == 0x3A && loc_present?(call.message_loc) &&
          @encoding.isupper_char(@source, loc_start(call.message_loc), loc_end(call.message_loc) - loc_start(call.message_loc))
      end

      # pm_command_call_value_p: a call without parentheses that has
      # arguments, not an operator call.
      def command_call_value?(node)
        case node
        when CallNode
          return true if call_node_command?(node) && !node.flag?(CallNodeFlags::ATTRIBUTE_WRITE) && (node.receiver.nil? || node.call_operator_loc)
          return true if constant_path_command_call?(node)

          # `!foo bar` and `not foo bar`.
          if node.receiver && node.arguments.nil? && node.opening_loc.nil? && node.call_operator_loc.nil?
            return command_call_value?(node.receiver)
          end

          false
        when SuperNode
          # A super with a do block is a block call.
          node.lparen_loc.nil? && (node.arguments || node.block) && !node.block.is_a?(BlockNode)
        when YieldNode
          node.lparen_loc.nil? && !node.arguments.nil?
        when RescueModifierNode
          command_call_value?(node.expression)
        when DefNode
          return false unless node.equal_loc && node.body

          body = node.body
          body = body.body.last if body.is_a?(StatementsNode)
          command_call_value?(body)
        else
          false
        end
      end

      # pm_block_call_p: a command with a block, or a call chained from one.
      def block_call?(node)
        while node.is_a?(CallNode)
          return true if node.opening_loc.nil? && node.arguments && node.block.is_a?(BlockNode)
          return false unless node.call_operator_loc && node.receiver

          node = node.receiver
        end

        # `super a do end`
        node.is_a?(SuperNode) && node.lparen_loc.nil? && node.block.is_a?(BlockNode)
      end

      # PRISM_DEPTH_MAXIMUM
      DEPTH_MAXIMUM = 10_000

      # The writes that end an expression when their value is an array
      # without brackets.
      IMPLICIT_ARRAY_WRITES = [ClassVariableWriteNode, ConstantPathWriteNode, ConstantWriteNode, GlobalVariableWriteNode,
                               InstanceVariableWriteNode, LocalVariableWriteNode].freeze

      # parse_expression_terminator: whether a node is a statement that the
      # current token may not continue.
      def parse_expression_terminator(node)
        left = BINDING_POWERS[@current_type].left

        case node
        when MultiWriteNode, ReturnNode, BreakNode, NextNode
          left > BINDING_POWER_MODIFIER
        when *IMPLICIT_ARRAY_WRITES
          node.flag?(WRITE_NODE_FLAGS_IMPLICIT_ARRAY) && left > BINDING_POWER_MODIFIER
        when CallNode
          return left > BINDING_POWER_MODIFIER if node.flag?(CALL_NODE_FLAGS_IMPLICIT_ARRAY)
          # A command takes only composition and modifiers.
          return left > BINDING_POWER_COMPOSITION if command_call_value?(node)

          # A block call takes method chains too.
          left > BINDING_POWER_COMPOSITION && left < BINDING_POWER_CALL && block_call?(node)
        when SuperNode, YieldNode
          return left > BINDING_POWER_COMPOSITION if command_call_value?(node)

          left > BINDING_POWER_COMPOSITION && left < BINDING_POWER_CALL && block_call?(node)
        when DefNode
          # `def f = foo bar` takes only modifiers.
          left > BINDING_POWER_MODIFIER && command_call_value?(node)
        when RescueModifierNode
          # A rescue whose value is a pattern match is a statement.
          left > BINDING_POWER_MODIFIER && (node.rescue_expression.is_a?(MatchRequiredNode) || node.rescue_expression.is_a?(MatchPredicateNode))
        else
          false
        end
      end

      # parse_expression: an expression, and the infix operators that bind at
      # least as tightly as `binding_power`.
      def parse_expression(binding_power, flags, diag_id, depth)
        if depth >= DEPTH_MAXIMUM
          err_current(:nesting_too_deep)
          return error_recovery_node(@current_start, @current_end)
        end

        node = parse_expression_prefix(binding_power, flags, diag_id, depth)

        case node
        when ErrorRecoveryNode, PreExecutionNode
          return node
        when PostExecutionNode, AliasGlobalVariableNode, AliasMethodNode, UndefNode
          return node if BINDING_POWERS[@current_type].left > BINDING_POWER_MODIFIER
        when CallNode, SuperNode, YieldNode, DefNode
          return node if parse_expression_terminator(node)
        when SymbolNode
          # A label is never followed by an operator.
          return node if symbol_node_label?(node)
        end

        loop do
          current_type = @current_type
          powers = BINDING_POWERS[current_type]
          break unless binding_power <= powers.left && powers.binary

          node = parse_expression_infix(node, binding_power, powers.right, flags, depth + 1)
          return node if parse_expression_terminator(node)

          if powers.nonassoc
            # Another non-associative operator of the same precedence is an
            # error: `1 == 2 == 3`, `1 == 2 != 3`, `1...2..3`.
            next_powers = BINDING_POWERS[@current_type]
            if next_powers.nonassoc && next_powers.left == powers.left
              err_current(:non_associative_operator, Tokens::HUMAN.fetch(@current_type), Tokens::HUMAN.fetch(current_type))
              break
            end

            if node.is_a?(RangeNode) && node.right.nil?
              # `1.. & 2` and `1.. * 2`
              if match?(:UAMPERSAND, :USTAR, :DOT, :AMPERSAND_DOT)
                err_current(:non_associative_operator, Tokens::HUMAN.fetch(@current_type), Tokens::HUMAN.fetch(current_type))
                break
              end

              break if BINDING_POWER_TERM <= next_powers.left
            elsif powers.left <= next_powers.left
              break
            end
          end

          # A command call continues only a method chain.
          if flags.anybits?(ACCEPTS_COMMAND_CALL)
            case node
            when CallNode
              message_loc = node.message_loc
              index = node.call_operator_loc.nil? && loc_present?(message_loc) &&
                      @source.getbyte(loc_start(message_loc)) == 0x5B && @source.getbyte(loc_end(message_loc) - 1) == 0x5D
              attribute = node.call_operator_loc && node.arguments.nil? && node.block.nil? && node.opening_loc.nil?
              parenthesized = node.call_operator_loc && node.opening_loc
              with_block = node.block.is_a?(BlockNode)
              flags &= ~ACCEPTS_COMMAND_CALL unless index || attribute || parenthesized || with_block
            when ConstantPathNode
              # Foo::Bar
            else
              flags &= ~ACCEPTS_COMMAND_CALL
            end
          end

          # A token that ends the context ends the expression, unless it is
          # an operator that binds here.
          next unless context_terminator?(current_context, @current_type)

          next_powers = BINDING_POWERS[@current_type]
          if !next_powers.binary || binding_power > next_powers.left || (node.is_a?(CallNode) && call_node_command?(node))
            return node
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

      # pm_parse_continuable: whether the source could become valid if more
      # input were appended to it, as IRB asks. It has errors, none of them
      # fatal before the end of the source, and each stray token is the
      # cascade of an earlier error, a truncated token at the end, or a
      # `=` that may start `=begin`.
      def continuable?
        return false if @errors.empty?

        others = @errors.any? { |error| !STRAY_ERRORS[error.id] && !FATAL_ERRORS[error.id] }
        first_other = nil
        @errors.all? do |error|
          at_end = error.end >= @end
          next false if FATAL_ERRORS[error.id] && !at_end

          unless STRAY_ERRORS[error.id]
            first_other = error.start if first_other.nil? || error.start < first_other
            next true
          end
          next true if first_other && first_other < error.start

          single = error.end - error.start == 1
          byte = @source.getbyte(error.start)
          if at_end && error.start.positive?
            next !")]}".include?(byte.chr) if single
            next true if others
          end
          single && byte == 0x3D && (error.start.zero? || @source.getbyte(error.start - 1) == 0x0A)
        end
      end
    end
  end
end
