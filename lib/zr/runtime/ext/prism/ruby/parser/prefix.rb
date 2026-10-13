# frozen_string_literal: true
# shareable_constant_value: literal

using Prism::Ruby::Mutation

module Prism
  module Ruby
    class Parser
      # size_t -1: a <<~ heredoc's common whitespace before any line sets it.
      COMMON_WHITESPACE_UNSET = 2**64 - 1

      private

      # The node of a variable at the start of a statement, or the targets of
      # a multiple write when a comma follows.
      def parse_statement_targets(node, binding_power, depth)
        return node unless binding_power == BINDING_POWER_STATEMENT && @current_type == :COMMA

        parse_targets_validate(node, BINDING_POWER_INDEX, depth + 1)
      end

      # [ elements ]
      def parse_array_literal(flags, depth)
        lex

        array = array_node(previous_token)
        parsed_bare_hash = false

        until match?(:BRACKET_RIGHT, :EOF)
          accepted_newline = accept(:NEWLINE)

          # A newline before the right bracket without a comma.
          break if accepted_newline && @current_type == :BRACKET_RIGHT

          unless array.elements.empty?
            if accept(:COMMA)
              err_previous(:invalid_comma) if accepted_newline
            else
              location = @previous_end
              err(location, location, :array_separator, Tokens::HUMAN.fetch(@current_type))

              @previous_start = location
              @previous_type = :MISSING
            end
          end

          # A trailing comma.
          break if @current_type == :BRACKET_RIGHT

          if accept(:USTAR)
            operator = previous_token
            expression = nil

            if match?(:BRACKET_RIGHT, :COMMA, :EOF)
              scope_forwarding_positionals_check(operator)
            else
              expression = parse_value_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :array_expression_after_star, depth + 1)
            end

            element = splat_node(operator, expression)
          elsif match?(:LABEL, :USTAR_STAR)
            err_current(:expression_bare_hash) if parsed_bare_hash

            element = keyword_hash_node
            hash_keys = StaticLiterals.new(self)

            unless match?(:EOF, :NEWLINE, :SEMICOLON, :KEYWORD_DO_BLOCK, :BRACE_RIGHT, :BRACKET_RIGHT, :KEYWORD_DO, :PARENTHESIS_RIGHT)
              parse_assocs(hash_keys, element, depth + 1)
            end

            parsed_bare_hash = true
          else
            element = parse_value_expression(BINDING_POWER_DEFINED, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_LABEL, :array_expression, depth + 1)

            if symbol_node_label?(element) || accept(:EQUAL_GREATER)
              err_previous(:expression_bare_hash) if parsed_bare_hash

              hash = keyword_hash_node
              hash_keys = StaticLiterals.new(self)
              hash_key_static_literals_add(hash_keys, element)

              operator = @previous_type == :EQUAL_GREATER ? previous_token : NOT_PROVIDED

              value = parse_value_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :hash_value, depth + 1)
              keyword_hash_node_elements_append(hash, assoc_node(element, operator, value))

              element = hash
              parse_assocs(hash_keys, element, depth + 1) if accept(:COMMA) && @current_type != :BRACKET_RIGHT

              parsed_bare_hash = true
            end
          end

          array_node_elements_append(array, element)
          break if element.is_a?(ErrorRecoveryNode)
        end

        accept(:NEWLINE)

        unless accept(:BRACKET_RIGHT)
          err_current(:array_term, Tokens::HUMAN.fetch(@current_type))
          @previous_start = @previous_end
          @previous_type = :MISSING
        end

        array_node_close_set(array, previous_token)

        array
      end

      # Semicolons and newlines inside parentheses; the flags gain
      # MULTIPLE_STATEMENTS for a semicolon.
      def parse_parentheses_terminators(flags)
        loop do
          if accept(:SEMICOLON)
            flags |= ParenthesesNodeFlags::MULTIPLE_STATEMENTS
          elsif !accept(:NEWLINE)
            break
          end
        end
        flags
      end

      # ( statements ), or parenthesized targets of a multiple write.
      def parse_parentheses(binding_power, flags, depth)
        opening = current_token
        paren_flags = 0

        previous_block_exits = push_block_exits([])

        lex
        paren_flags = parse_parentheses_terminators(paren_flags)

        # ()
        if match?(:PARENTHESIS_RIGHT, :EOF)
          # A command argument group sets ENDARG before its `)`, also when
          # empty, so a `{` after it lexes as a block brace.
          @lex_state = STATE_ENDARG if @current_type == :PARENTHESIS_RIGHT && opening.type == :PARENTHESIS_LEFT_PARENTHESES

          expect(:PARENTHESIS_RIGHT, :expect_rparen)
          pop_block_exits(previous_block_exits)
          return parentheses_node(opening, nil, previous_token, paren_flags)
        end

        context_push(:parens)
        statement = parse_expression(BINDING_POWER_STATEMENT, ACCEPTS_COMMAND_CALL | ACCEPTS_DO_BLOCK, :cannot_parse_expression, depth + 1)
        context_pop

        terminator_found = false
        if accept(:SEMICOLON)
          terminator_found = true
          paren_flags |= ParenthesesNodeFlags::MULTIPLE_STATEMENTS
        elsif accept(:NEWLINE)
          terminator_found = true
        end

        paren_flags = parse_parentheses_terminators(paren_flags) if terminator_found

        if @current_type == :PARENTHESIS_RIGHT
          @lex_state = STATE_ENDARG if opening.type == :PARENTHESIS_LEFT_PARENTHESES

          lex
          pop_block_exits(previous_block_exits)

          if statement.is_a?(MultiTargetNode) || statement.is_a?(SplatNode)
            # (a, b) as a target.
            if statement.is_a?(MultiTargetNode) && statement.lparen_loc.nil?
              multi_target = statement
            else
              multi_target = multi_target_node
              multi_target_node_targets_append(multi_target, statement)
            end

            multi_target.lparen_loc = opening.location
            multi_target.rparen_loc = previous_token.location
            multi_target.location = loc(opening.start, @previous_end)

            if @current_type == :COMMA && binding_power == BINDING_POWER_STATEMENT
              result = parse_targets(multi_target, BINDING_POWER_INDEX, depth + 1)
              accept(:NEWLINE)
            else
              result = multi_target
            end

            if context?(:multi_target)
              # Allowed by the parent.
            elsif context?(:for_index) && match?(:KEYWORD_IN, :COMMA)
              # A for loop's targets; a comma continues them.
            elsif flags.anybits?(ACCEPTS_STATEMENT)
              # A rescue modifier's value takes the targets on `=` or a
              # comma; another binary operator may not take them.
              err_node(result, :write_target_unexpected) if BINDING_POWERS[@current_type].binary && @current_type != :EQUAL
            elsif binding_power != BINDING_POWER_STATEMENT || !match?(:EQUAL, :PARENTHESIS_RIGHT)
              err_node(result, :write_target_unexpected)
            end

            return result
          end

          statements = statements_node
          statements_node_body_append(statements, statement, true)

          return parentheses_node(opening, statements, previous_token, paren_flags)
        end

        # Several statements.
        context_push(:parens)
        paren_flags |= ParenthesesNodeFlags::MULTIPLE_STATEMENTS

        statements = statements_node
        statements_node_body_append(statements, statement, true)

        if !terminator_found && @current_type != :EOF
          err_current(:expect_eol_after_statement, Tokens::HUMAN.fetch(@current_type))
        end

        loop do
          node = parse_expression(BINDING_POWER_STATEMENT, ACCEPTS_COMMAND_CALL | ACCEPTS_DO_BLOCK, :cannot_parse_expression, depth + 1)
          statements_node_body_append(statements, node, true)

          if @recovering
            @recovering = false if @current_type == :PARENTHESIS_RIGHT
            break
          end

          break if node.is_a?(ErrorRecoveryNode)

          if accept(:NEWLINE, :SEMICOLON)
            nil while accept(:NEWLINE, :SEMICOLON)
            break if @current_type == :PARENTHESIS_RIGHT
          elsif @current_type == :PARENTHESIS_RIGHT
            break
          elsif @current_type != :EOF
            err_current(:expect_eol_after_statement, Tokens::HUMAN.fetch(@current_type))
          end
        end

        context_pop
        expect(:PARENTHESIS_RIGHT, :expect_rparen)

        # Targets may end parentheses only at the statement level.
        statement = statements.body.last

        if statement.is_a?(SplatNode)
          multi_target = multi_target_node
          multi_target_node_targets_append(multi_target, statement)

          statement = multi_target
          statements.body[-1] = statement
        end

        if statement.is_a?(MultiTargetNode)
          offset = statement.end_offset
          operator = Token.new(:EQUAL, offset, offset)
          value = error_recovery_node(offset, offset)

          statement = multi_write_node(statement, operator, value)
          statements.body[-1] = statement

          err_node(statement, :write_target_unexpected)
        end

        pop_block_exits(previous_block_exits)

        void_statements_check(statements, true)
        parentheses_node(opening, statements, previous_token, paren_flags)
      end

      # { assocs }
      def parse_hash_literal(depth)
        lex

        opening = previous_token
        node = hash_node(opening)

        unless match?(:BRACE_RIGHT, :EOF)
          parse_assocs(StaticLiterals.new(self), node, depth + 1)
          accept(:NEWLINE)
        end

        expect_opening(:BRACE_RIGHT, :hash_term, opening)
        hash_node_closing_loc_set(node, previous_token)

        node
      end

      # ?a
      def parse_character_literal(depth)
        opening = Token.new(:STRING_BEGIN, @current_start, @current_start + 1)
        content = Token.new(:STRING_CONTENT, @current_start + 1, @current_end)
        node = string_node_current_string(opening, content, NOT_PROVIDED)

        node.flag_set(parse_unescaped_encoding)

        lex

        # ?a "b" joins.
        return parse_strings(node, false, depth + 1) if @current_type == :STRING_BEGIN

        node
      end

      # Whether arguments or a block follow a name, which make it a call.
      def call_arguments_follow?(flags)
        (flags.anybits?(ACCEPTS_COMMAND_CALL) && (token_begins_expression?(@current_type) || match?(:UAMPERSAND, :USTAR, :USTAR_STAR))) ||
          (accepts_block_stack? && @current_type == :KEYWORD_DO) ||
          @current_type == :BRACE_LEFT
      end

      # Foo, or Foo(...) as a call.
      def parse_constant(binding_power, flags, depth)
        lex
        constant = previous_token

        if @current_type == :PARENTHESIS_LEFT || call_arguments_follow?(flags & ACCEPTS_COMMAND_CALL)
          arguments = Arguments.new
          parse_arguments_list(arguments, true, flags, depth + 1)
          return call_node_fcall(constant, arguments)
        end

        parse_statement_targets(constant_read_node(previous_token), binding_power, depth)
      end

      # an identifier: a local variable or a method call.
      def parse_identifier(binding_power, flags, depth)
        lex
        identifier = previous_token
        node = parse_variable_call

        if node.is_a?(CallNode)
          # Not a local, so arguments may follow.
          arguments = Arguments.new

          if parse_arguments_list(arguments, true, flags, depth + 1)
            node.flag_unset(CallNodeFlags::VARIABLE_CALL)

            node.opening_loc = arguments.opening_loc
            node.arguments = arguments.arguments
            node.closing_loc = arguments.closing_loc
            node.block = arguments.block

            node.end_offset = arguments_end(arguments) || loc_end(node.message_loc)
          end
        elsif call_arguments_follow?(flags & ACCEPTS_COMMAND_CALL)
          # A local followed by arguments or a block is a call after all.
          arguments = Arguments.new
          parse_arguments_list(arguments, true, flags, depth + 1)
          fcall = call_node_fcall(identifier, arguments)

          if node.is_a?(ItLocalVariableReadNode) || numbered_parameter?(identifier.start, identifier.end)
            node_unreference(node)
          else
            scope_find(node.depth).locals.unread(constant_id_of(node.name))
          end

          return fcall
        end

        parse_statement_targets(node, binding_power, depth)
      end

      # <<HEREDOC
      def parse_heredoc(depth)
        mode = @lex_mode
        mode.common_whitespace = COMMON_WHITESPACE_UNSET

        lex
        opening = previous_token

        if match?(:HEREDOC_END, :EOF)
          # An empty heredoc.
          expect_heredoc_term(mode.ident_start, mode.ident_length)
          content = Token.new(:STRING_CONTENT, @previous_start, @previous_start)

          node =
            if mode.quote == 0x60
              xstring_node_unescaped(opening, content, previous_token, "".b)
            else
              string_node_unescaped(opening, content, previous_token, "".b)
            end

          node.end_offset = opening.end
        elsif (part = parse_string_part(depth + 1)).nil?
          # parse_string_part reported the error.
          node = error_recovery_node(@previous_start, @previous_end)
        elsif part.is_a?(StringNode) && match?(:HEREDOC_END, :EOF)
          # One line of plain content.
          part.flag_set(parse_unescaped_encoding)

          part.opening_loc = opening.location
          part.closing_loc = current_token.location
          part.location = part.opening_loc

          part = retype(part, XStringNode) if mode.quote == 0x60

          if mode.indent == :tilde && mode.common_whitespace != COMMON_WHITESPACE_UNSET && mode.common_whitespace != 0
            part.unescaped = parse_heredoc_dedent_string(part.unescaped, mode.common_whitespace)
          end

          node = part
          expect_heredoc_term(mode.ident_start, mode.ident_length)
        else
          parts = [part]

          until match?(:HEREDOC_END, :EOF)
            part = parse_string_part(depth + 1)
            parts << part if part
          end

          if mode.quote == 0x60
            node = interpolated_xstring_node(opening, opening)
            node.parts = parts

            expect_heredoc_term(mode.ident_start, mode.ident_length)
            interpolated_node_closing_set(node, previous_token)
          else
            node = interpolated_string_node(opening, parts, opening)

            expect_heredoc_term(mode.ident_start, mode.ident_length)
            interpolated_node_closing_set(node, previous_token)
          end
          node.location = node.opening_loc

          if mode.indent == :tilde && mode.common_whitespace != COMMON_WHITESPACE_UNSET && mode.common_whitespace != 0
            parse_heredoc_dedent(node.parts, mode.common_whitespace)
          end
        end

        return parse_strings(node, false, depth + 1) if @current_type == :STRING_BEGIN

        node
      end

      # alias new old
      def parse_alias(binding_power, flags, depth)
        err_current(:statement_alias) if binding_power != BINDING_POWER_STATEMENT && !flags.anybits?(ACCEPTS_STATEMENT)

        lex
        keyword = previous_token

        new_name = parse_alias_argument(true, depth + 1)
        old_name = parse_alias_argument(false, depth + 1)

        case new_name
        when BackReferenceReadNode, NumberedReferenceReadNode, GlobalVariableReadNode
          case old_name
          when NumberedReferenceReadNode then err_node(old_name, :alias_argument_numbered_reference)
          when BackReferenceReadNode, GlobalVariableReadNode, ErrorRecoveryNode then nil
          else
            err_node(old_name, :alias_argument)
            old_name = error_recovery_node_unexpected(old_name)
          end

          alias_global_variable_node(keyword, new_name, old_name)
        else
          if (new_name.is_a?(SymbolNode) || new_name.is_a?(InterpolatedSymbolNode)) &&
             !old_name.is_a?(SymbolNode) && !old_name.is_a?(InterpolatedSymbolNode) && !old_name.is_a?(ErrorRecoveryNode)
            err_node(old_name, :alias_argument)
            old_name = error_recovery_node_unexpected(old_name)
          end

          alias_method_node(keyword, new_name, old_name)
        end
      end

      # case ... when / case ... in
      def parse_case(flags, depth)
        opening_newline_index = token_newline_index
        lex

        case_keyword = previous_token
        predicate = nil

        previous_block_exits = push_block_exits([])

        if accept(:NEWLINE, :SEMICOLON)
          nil while accept(:NEWLINE, :SEMICOLON)
        elsif !match?(:KEYWORD_WHEN, :KEYWORD_IN, :KEYWORD_END) && token_begins_expression?(@current_type)
          predicate = parse_value_expression(BINDING_POWER_COMPOSITION, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :case_expression_after_case, depth + 1)
          nil while accept(:NEWLINE, :SEMICOLON)
        end

        if @current_type == :KEYWORD_END
          warn_indentation_mismatch(opening_newline_index, case_keyword, false, false)
          lex

          pop_block_exits(previous_block_exits)

          err_token(case_keyword, :case_missing_conditions)
          return case_node(case_keyword, predicate, previous_token)
        end

        if @current_type == :KEYWORD_WHEN
          node = case_node(case_keyword, predicate, NOT_PROVIDED)
          literals = StaticLiterals.new(self)

          while @current_type == :KEYWORD_WHEN
            warn_indentation_mismatch(opening_newline_index, case_keyword, false, true)
            lex

            when_clause = when_node(previous_token)

            loop do
              if accept(:USTAR)
                operator = previous_token
                expression = parse_value_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_star, depth + 1)

                when_node_conditions_append(when_clause, splat_node(operator, expression))
                break if expression.is_a?(ErrorRecoveryNode)
              else
                condition = parse_value_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :case_expression_after_when, depth + 1)
                when_node_conditions_append(when_clause, condition)
                break if condition.is_a?(ErrorRecoveryNode)

                # A string in a when clause is frozen.
                if condition.is_a?(StringNode)
                  condition.flag_set(StringFlags::FROZEN | NodeFlags::STATIC_LITERAL)
                elsif condition.is_a?(SourceFileNode) && @version < Options::VERSION_CRUBY_4_1
                  condition.flag_set(NodeFlags::STATIC_LITERAL)
                end

                when_clause_static_literals_add(literals, condition)
              end

              break unless accept(:COMMA)
            end

            if accept(:NEWLINE, :SEMICOLON)
              when_node_then_keyword_loc_set(when_clause, previous_token) if accept(:KEYWORD_THEN)
            else
              expect(:KEYWORD_THEN, :expect_when_delimiter)
              when_node_then_keyword_loc_set(when_clause, previous_token)
            end

            unless match?(:KEYWORD_WHEN, :KEYWORD_ELSE, :KEYWORD_END)
              statements = parse_statements(:case_when, depth + 1)
              when_node_statements_set(when_clause, statements) if statements
            end

            case_node_condition_append(node, when_clause)
          end

          err_token(case_keyword, :case_missing_conditions) if node.conditions.empty?
        else
          node = case_match_node(case_keyword, predicate, NOT_PROVIDED)

          # Pattern matching needs a value.
          err_token(case_keyword, :case_match_missing_predicate) if predicate.nil?

          while @current_type == :KEYWORD_IN
            warn_indentation_mismatch(opening_newline_index, case_keyword, false, true)

            previous_pattern_matching_newlines = @pattern_matching_newlines
            @pattern_matching_newlines = true

            @lex_state = STATE_BEG | STATE_LABEL
            @command_start = false
            lex

            in_keyword = previous_token

            pattern = parse_pattern([], PARSE_PATTERN_TOP | PARSE_PATTERN_MULTI, :pattern_expression_after_in, depth + 1)

            @pattern_matching_newlines = previous_pattern_matching_newlines

            # A guard clause.
            if accept(:KEYWORD_IF_MODIFIER)
              keyword = previous_token
              guard = parse_value_expression(BINDING_POWER_COMPOSITION, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :conditional_if_predicate, depth + 1)
              pattern = if_node_modifier(pattern, keyword, guard)
            elsif accept(:KEYWORD_UNLESS_MODIFIER)
              keyword = previous_token
              guard = parse_value_expression(BINDING_POWER_COMPOSITION, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :conditional_unless_predicate, depth + 1)
              pattern = unless_node_modifier(pattern, keyword, guard)
            end

            if accept(:NEWLINE, :SEMICOLON)
              then_keyword = accept(:KEYWORD_THEN) ? previous_token : NOT_PROVIDED
            else
              expect(:KEYWORD_THEN, :expect_in_delimiter)
              then_keyword = previous_token
            end

            statements = match?(:KEYWORD_IN, :KEYWORD_ELSE, :KEYWORD_END) ? nil : parse_statements(:case_in, depth + 1)

            case_node_condition_append(node, in_node(pattern, statements, in_keyword, then_keyword))
          end

          err_token(case_keyword, :case_missing_conditions) if node.conditions.empty?
        end

        accept(:NEWLINE, :SEMICOLON)
        if accept(:KEYWORD_ELSE)
          else_keyword = previous_token
          statements = @current_type == :KEYWORD_END ? nil : parse_statements(:else, depth + 1)
          case_node_else_clause_set(node, else_node(else_keyword, statements, current_token))
        end

        warn_indentation_mismatch(opening_newline_index, case_keyword, false, false)
        expect_opening(:KEYWORD_END, :case_term, case_keyword)

        case_node_end_keyword_loc_set(node, previous_token)

        pop_block_exits(previous_block_exits)

        node
      end

      # begin ... end
      def parse_begin(depth)
        opening_newline_index = token_newline_index
        lex

        begin_keyword = previous_token
        accept(:NEWLINE, :SEMICOLON)

        previous_block_exits = push_block_exits([])
        begin_statements = nil

        unless match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE, :KEYWORD_ELSE, :KEYWORD_END)
          accepts_block_stack_push(true)
          begin_statements = parse_statements(:begin, depth + 1)
          accepts_block_stack_pop
          accept(:NEWLINE, :SEMICOLON)
        end

        node = begin_node(begin_keyword, begin_statements)
        parse_rescues(opening_newline_index, begin_keyword, node, :begin, depth + 1)
        expect_opening(:KEYWORD_END, :begin_term, begin_keyword)

        node.end_offset = @previous_end
        begin_node_end_keyword_set(node, previous_token)

        pop_block_exits(previous_block_exits)

        node
      end

      # BEGIN { ... }
      def parse_pre_execution(binding_power, depth)
        previous_block_exits = push_block_exits([])

        err_current(:statement_preexe_begin) if binding_power != BINDING_POWER_STATEMENT

        lex
        keyword = previous_token

        expect(:BRACE_LEFT, :begin_upcase_brace)
        opening = previous_token
        statements = parse_statements(:preexe, depth + 1)

        expect_opening(:BRACE_RIGHT, :begin_upcase_term, opening)
        context = current_context
        err_token(keyword, :begin_upcase_toplevel) if context != :main && context != :preexe

        flush_block_exits(previous_block_exits)

        pre_execution_node(keyword, opening, statements, previous_token)
      end

      # break, next, return
      def parse_jump(flags, depth)
        lex

        keyword = previous_token
        arguments = Arguments.new

        if token_begins_expression?(@current_type) || match?(:USTAR, :USTAR_STAR)
          binding_power = BINDING_POWERS[@current_type].left

          if binding_power == BINDING_POWER_UNSET || binding_power >= BINDING_POWER_RANGE
            following = current_token
            parse_arguments(arguments, false, :EOF, flags, depth + 1)

            # `foo && return bar`
            if !flags.anybits?(ACCEPTS_COMMAND_CALL) && arguments.arguments
              err_token(following, :expect_eol_after_statement, Tokens::HUMAN.fetch(following.type))
            end

            # `return a,` at the end of the input. The arguments take a
            # trailing comma only before the terminator, here EOF.
            if @previous_type == :COMMA && @current_type == :EOF
              err_previous(:expect_argument, Tokens::HUMAN.fetch(@current_type))
            end
          end

          # A block argument has no place in a jump.
          if arguments.block
            err_node(arguments.block, :unexpected_block_argument)
            node_unreference(arguments.block)
            arguments.block = nil
          end
        end

        case keyword.type
        when :KEYWORD_BREAK
          node = break_node(keyword, arguments.arguments)
          parse_block_exit(node) unless @partial_script
        when :KEYWORD_NEXT
          node = next_node(keyword, arguments.arguments)
          parse_block_exit(node) unless @partial_script
        else
          node = return_node(keyword, arguments.arguments)
          parse_return(node)
        end
        node
      end

      # super, super(...)
      def parse_super(flags, depth)
        lex

        keyword = previous_token
        arguments = Arguments.new
        parse_arguments_list(arguments, true, flags, depth + 1)

        if arguments.opening_loc.nil? && arguments.arguments.nil? && (arguments.block.nil? || arguments.block.is_a?(BlockNode))
          return forwarding_super_node(keyword, arguments)
        end

        super_node(keyword, arguments)
      end

      # yield
      def parse_yield_expression(flags, depth)
        lex

        keyword = previous_token
        arguments = Arguments.new
        parse_arguments_list(arguments, false, flags, depth + 1)

        # A yield has no place for a block argument.
        if arguments.block
          err_node(arguments.block, :unexpected_block_argument)
          node_unreference(arguments.block)
          arguments.block = nil
        end

        node = yield_node(keyword, arguments.opening_loc, arguments.arguments, arguments.closing_loc)
        parse_yield(node) if !@parsing_eval && !@partial_script

        node
      end

      # class Name < Super, class << self
      def parse_class(flags, depth)
        opening_newline_index = token_newline_index
        lex

        class_keyword = previous_token
        do_loop_stack_push(false)

        previous_block_exits = push_block_exits([])

        if accept(:LESS_LESS)
          operator = previous_token
          expression = parse_value_expression(BINDING_POWER_COMPOSITION, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :expect_expression_after_less_less, depth + 1)

          scope_push(true)
          unless match?(:NEWLINE, :SEMICOLON)
            err_current(:expect_singleton_class_delimiter, Tokens::HUMAN.fetch(@current_type))
          end

          statements = nil
          unless match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE, :KEYWORD_ELSE, :KEYWORD_END)
            accepts_block_stack_push(true)
            statements = parse_statements(:sclass, depth + 1)
            accepts_block_stack_pop
          end

          if match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE)
            statements = parse_rescues_implicit_begin(opening_newline_index, class_keyword, class_keyword.start, statements, :sclass, depth + 1)
          else
            warn_indentation_mismatch(opening_newline_index, class_keyword, false, false)
          end

          expect_opening(:KEYWORD_END, :class_term, class_keyword)

          locals = locals_order(@current_scope.locals, false)

          scope_pop
          do_loop_stack_pop

          flush_block_exits(previous_block_exits)

          return singleton_class_node(locals, class_keyword, operator, expression, statements, previous_token)
        end

        constant_path = parse_expression(BINDING_POWER_INDEX, flags & ACCEPTS_DO_BLOCK, :class_name, depth + 1)
        name = previous_token
        err_token(name, :class_name) if name.type != :CONSTANT

        if @current_type == :LESS
          inheritance_operator = current_token
          @lex_state = STATE_BEG

          @command_start = true
          lex

          superclass = parse_value_expression(BINDING_POWER_COMPOSITION, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :class_superclass, depth + 1)
        else
          inheritance_operator = NOT_PROVIDED
          superclass = nil
        end

        scope_push(true)

        if inheritance_operator.provided?
          expect(:NEWLINE, :SEMICOLON, :class_unexpected_end)
        else
          accept(:NEWLINE, :SEMICOLON)
        end

        statements = nil
        unless match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE, :KEYWORD_ELSE, :KEYWORD_END)
          accepts_block_stack_push(true)
          statements = parse_statements(:class, depth + 1)
          accepts_block_stack_pop
        end

        if match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE)
          statements = parse_rescues_implicit_begin(opening_newline_index, class_keyword, class_keyword.start, statements, :class, depth + 1)
        else
          warn_indentation_mismatch(opening_newline_index, class_keyword, false, false)
        end

        expect_opening(:KEYWORD_END, :class_term, class_keyword)

        err_token(class_keyword, :class_in_method) if context_def?

        locals = locals_order(@current_scope.locals, false)

        scope_pop
        do_loop_stack_pop

        unless constant_path.is_a?(ConstantPathNode) || constant_path.is_a?(ConstantReadNode)
          err_node(constant_path, :class_name)
          constant_path = error_recovery_node_unexpected(constant_path) unless constant_path.is_a?(ErrorRecoveryNode)
        end

        pop_block_exits(previous_block_exits)

        class_node(locals, class_keyword, constant_path, name, inheritance_operator, superclass, statements, previous_token)
      end

      # The receiver node a `def` names with a keyword, constant or variable.
      DEF_RECEIVERS = {
        CONSTANT: :constant_read_node, INSTANCE_VARIABLE: :instance_variable_read_node,
        CLASS_VARIABLE: :class_variable_read_node, GLOBAL_VARIABLE: :global_variable_read_node,
        KEYWORD_NIL: :nil_node, KEYWORD_SELF: :self_node, KEYWORD_TRUE: :true_node, KEYWORD_FALSE: :false_node,
        KEYWORD___FILE__: :source_file_node, KEYWORD___LINE__: :source_line_node,
        KEYWORD___ENCODING__: :source_encoding_node
      }

      # def name(params) ... end, def name = value
      def parse_def(binding_power, flags, depth)
        previous_block_exits = push_block_exits([])

        def_keyword = current_token
        opening_newline_index = token_newline_index

        receiver = nil
        operator = NOT_PROVIDED

        # `...` lexes as parameters from the first token on.
        context_push(:def_params)
        lex

        case @current_type
        when *CASE_OPERATOR
          scope_push(true)
          @lex_state = STATE_ENDFN
          lex

          name = previous_token
        when :IDENTIFIER
          lex

          if match?(:DOT, :COLON_COLON)
            receiver = parse_variable_call

            scope_push(true)
            @lex_state = STATE_FNAME
            lex

            operator = previous_token
            name = parse_method_definition_name
          else
            refute_numbered_parameter(@previous_start, @previous_end)
            scope_push(true)

            name = previous_token
          end
        when :INSTANCE_VARIABLE, :CLASS_VARIABLE, :GLOBAL_VARIABLE, :CONSTANT, :KEYWORD_NIL, :KEYWORD_SELF,
             :KEYWORD_TRUE, :KEYWORD_FALSE, :KEYWORD___FILE__, :KEYWORD___LINE__, :KEYWORD___ENCODING__
          valid_name = !match?(:INSTANCE_VARIABLE, :CLASS_VARIABLE, :GLOBAL_VARIABLE)

          scope_push(true)
          lex

          identifier = previous_token

          if match?(:DOT, :COLON_COLON)
            @lex_state = STATE_FNAME
            lex
            operator = previous_token

            receiver = send(DEF_RECEIVERS.fetch(identifier.type), identifier)
            name = parse_method_definition_name
          else
            err_token(identifier, :def_name, Tokens::HUMAN.fetch(identifier.type)) unless valid_name
            name = identifier
          end
        when :PARENTHESIS_LEFT
          # The receiver's expression is not among parameters.
          context_pop
          lex

          lparen = previous_token
          expression = parse_value_expression(BINDING_POWER_COMPOSITION, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :def_receiver, depth + 1)

          accept(:NEWLINE)
          expect(:PARENTHESIS_RIGHT, :expect_rparen)
          rparen = previous_token

          @lex_state = STATE_FNAME
          expect(:DOT, :COLON_COLON, :def_receiver_term)

          operator = previous_token
          receiver = parentheses_node(lparen, expression, rparen, 0)

          scope_push(true)
          context_push(:def_params)
          name = parse_method_definition_name
        else
          scope_push(true)
          name = parse_method_definition_name
        end

        accept_endless_def = true
        case @current_type
        when :PARENTHESIS_LEFT
          lex
          lparen = previous_token

          # From 4.1 (Feature #19107) the parameters may end in a comma.
          unless @current_type == :PARENTHESIS_RIGHT
            params = parse_parameters(BINDING_POWER_DEFINED, true, @version >= Options::VERSION_CRUBY_4_1, true, true, false,
                                      :argument_no_forwarding_ellipses, depth + 1)
          end

          @lex_state = STATE_BEG
          @command_start = true

          context_pop
          unless accept(:PARENTHESIS_RIGHT)
            err_current(:def_params_term_paren, Tokens::HUMAN.fetch(@current_type))
            @previous_start = @previous_end
            @previous_type = :MISSING
          end

          rparen = previous_token
        when *CASE_PARAMETER
          # A label's newline is ignored.
          @lex_state |= STATE_LABEL if @current_type == :LABEL

          lparen = NOT_PROVIDED
          rparen = NOT_PROVIDED
          params = parse_parameters(BINDING_POWER_DEFINED, false, false, true, true, false, :argument_no_forwarding_ellipses, depth + 1)

          # `def * = 1` is ambiguous with an optional parameter.
          accept_endless_def = false

          context_pop
        else
          lparen = NOT_PROVIDED
          rparen = NOT_PROVIDED
          params = nil

          context_pop
        end

        statements = nil

        if accept(:EQUAL)
          err_token(name, :def_endless_setter) if token_setter_name?(name)
          err_previous(:def_endless_parameters) unless accept_endless_def
          if current_context == :default_params && @contexts[-2] == :block_parameters
            err(def_keyword.start, @previous_end, :unexpected_parameter_default_value, "endless method definition")
          end
          equal = previous_token

          context_push(:def)
          do_loop_stack_push(false)
          statements = statements_node

          allow_flags =
            if @version >= Options::VERSION_CRUBY_4_0
              flags & ACCEPTS_COMMAND_CALL
            elsif binding_power == BINDING_POWER_ASSIGNMENT || binding_power < BINDING_POWER_COMPOSITION
              # `def foo = puts "Hello"`, but not `private def foo = puts "Hello"`.
              ACCEPTS_COMMAND_CALL
            else
              0
            end

          # In the body, `do` lexes as KEYWORD_DO; a command's arguments
          # make it KEYWORD_DO_BLOCK, which the outer context takes. The
          # frame spans the rescue modifiers too.
          accepts_block_stack_push(true)
          statement = parse_expression(BINDING_POWER_DEFINED + 1, allow_flags | IN_ENDLESS_DEF, :def_endless, depth + 1)

          # `def f = 1 do end`
          if accept(:KEYWORD_DO)
            block = parse_block(depth + 1)
            err_node(block, :def_endless_do_block)
          end

          # `def f = a rescue b rescue c` rescues within the body, to the
          # left.
          while accept(:KEYWORD_RESCUE_MODIFIER)
            context_push(:rescue_modifier)

            rescue_keyword = previous_token
            # The value excludes `and`, `or`, `in` and `=>`.
            value = parse_expression(BINDING_POWER_MATCH + 1, flags & ACCEPTS_DO_BLOCK, :rescue_modifier_value, depth + 1)
            context_pop

            statement = rescue_modifier_node(statement, rescue_keyword, value)
          end

          accepts_block_stack_pop

          # `def f = def g = foo bar`
          if statement.is_a?(DefNode) && command_call_value?(statement)
            err_node(statement, :expect_eol_after_statement, Tokens::HUMAN.fetch(@current_type))
          end

          statements_node_body_append(statements, statement, false)
          do_loop_stack_pop
          context_pop
          end_keyword = NOT_PROVIDED
        else
          equal = NOT_PROVIDED

          if lparen.provided?
            accept(:NEWLINE, :SEMICOLON)
          else
            @lex_state = STATE_BEG
            @command_start = true
            expect(:NEWLINE, :SEMICOLON, :def_params_term)
          end

          accepts_block_stack_push(true)
          do_loop_stack_push(false)

          unless match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE, :KEYWORD_ELSE, :KEYWORD_END)
            accepts_block_stack_push(true)
            statements = parse_statements(:def, depth + 1)
            accepts_block_stack_pop
          end

          if match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE, :KEYWORD_ELSE)
            statements = parse_rescues_implicit_begin(opening_newline_index, def_keyword, def_keyword.start, statements, :def, depth + 1)
          else
            warn_indentation_mismatch(opening_newline_index, def_keyword, false, false)
          end

          accepts_block_stack_pop
          do_loop_stack_pop

          expect_opening(:KEYWORD_END, :def_term, def_keyword)
          end_keyword = previous_token
        end

        locals = locals_order(@current_scope.locals, false)
        scope_pop

        # `def -@` names `-@`, but `def ~@` names `~`.
        name_symbol = location_name(name.start, operator_symbol_name_end(name))

        flush_block_exits(previous_block_exits)

        def_node(name_symbol, name, receiver, params, statements, locals, def_keyword, operator, lparen, rparen, equal, end_keyword)
      end

      # defined?(expression)
      def parse_defined(flags, depth)
        lex
        keyword = previous_token

        context_push(:defined)
        newline = accept(:NEWLINE)

        if accept(:PARENTHESIS_LEFT, :PARENTHESIS_LEFT_GROUPING)
          lparen = previous_token

          if newline && accept(:PARENTHESIS_RIGHT)
            expression = parentheses_node(lparen, nil, previous_token, 0)
            lparen = NOT_PROVIDED
            rparen = NOT_PROVIDED
          else
            expression = parse_expression(BINDING_POWER_COMPOSITION, ACCEPTS_COMMAND_CALL | ACCEPTS_DO_BLOCK, :defined_expression, depth + 1)

            if @recovering
              rparen = NOT_PROVIDED
            else
              accept(:NEWLINE)
              expect(:PARENTHESIS_RIGHT, :expect_rparen)
              rparen = previous_token
            end
          end
        else
          lparen = NOT_PROVIDED
          rparen = NOT_PROVIDED
          expression = parse_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :defined_expression, depth + 1)
        end

        context_pop
        defined_node(lparen, expression, rparen, keyword)
      end

      # END { ... }
      def parse_post_execution(binding_power, flags, depth)
        err_current(:statement_postexe_end) if binding_power != BINDING_POWER_STATEMENT && !flags.anybits?(ACCEPTS_STATEMENT)

        lex
        keyword = previous_token

        warn_token(keyword, :end_in_method) if context_def?

        expect(:BRACE_LEFT, :end_upcase_brace)
        opening = previous_token
        statements = parse_statements(:postexe, depth + 1)

        expect_opening(:BRACE_RIGHT, :end_upcase_term, opening)
        post_execution_node(keyword, opening, statements, previous_token)
      end

      # for index in collection ... end
      def parse_for(flags, depth)
        opening_newline_index = token_newline_index
        lex

        for_keyword = previous_token

        context_push(:for_index)

        if accept(:USTAR)
          index = parse_splat(flags, depth)
        elsif token_begins_expression?(@current_type)
          index = parse_expression(BINDING_POWER_INDEX, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_comma, depth + 1)
        else
          err_token(for_keyword, :for_index)
          index = error_recovery_node(for_keyword.start, for_keyword.end)
        end

        index = @current_type == :COMMA ? parse_targets(index, BINDING_POWER_INDEX, depth + 1) : parse_target(index, false, false)

        context_pop
        do_loop_stack_push(true)

        expect(:KEYWORD_IN, :for_in)
        in_keyword = previous_token

        collection = parse_value_expression(BINDING_POWER_COMPOSITION, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :for_collection, depth + 1)
        do_loop_stack_pop

        if accept(:KEYWORD_DO_LOOP)
          do_keyword = previous_token
        else
          do_keyword = NOT_PROVIDED
          unless match?(:SEMICOLON, :NEWLINE)
            err_current(:expect_for_delimiter, Tokens::HUMAN.fetch(@current_type))
          end
        end

        statements = @current_type == :KEYWORD_END ? nil : parse_statements(:for, depth + 1)

        warn_indentation_mismatch(opening_newline_index, for_keyword, false, false)
        expect_opening(:KEYWORD_END, :for_term, for_keyword)

        for_node(index, collection, statements, for_keyword, in_keyword, do_keyword, previous_token)
      end

      # if ... end
      def parse_if(depth)
        warn_token_content(current_token, :keyword_eol) if end_of_line?

        opening_newline_index = token_newline_index
        if_after_else = @previous_type == :KEYWORD_ELSE
        lex

        parse_conditional(:if, opening_newline_index, if_after_else, depth + 1)
      end

      # undef names
      def parse_undef(binding_power, flags, depth)
        err_current(:statement_undef) if binding_power != BINDING_POWER_STATEMENT && !flags.anybits?(ACCEPTS_STATEMENT)

        lex
        node = undef_node(previous_token)
        name = parse_undef_argument(depth + 1)

        unless name.is_a?(ErrorRecoveryNode)
          undef_node_append(node, name)

          while @current_type == :COMMA
            @lex_state = STATE_FNAME | STATE_FITEM
            lex
            name = parse_undef_argument(depth + 1)
            break if name.is_a?(ErrorRecoveryNode)

            undef_node_append(node, name)
          end
        end

        node
      end

      # not expression, not(expression)
      def parse_not(binding_power, flags, depth)
        lex

        message = previous_token
        arguments = Arguments.new
        receiver = nil

        # Above its own binding power, `not` needs parentheses, except in
        # an endless def's body.
        if binding_power > BINDING_POWER_NOT && !flags.anybits?(IN_ENDLESS_DEF) && @current_type != :PARENTHESIS_LEFT
          if @current_type == :PARENTHESIS_LEFT_PARENTHESES
            err(@previous_end, @previous_end + 1, :expect_lparen_after_not_lparen)
          else
            accept(:NEWLINE)
            err_current(:expect_lparen_after_not_other)
          end

          return error_recovery_node(@current_start, @current_end)
        end

        accept(:NEWLINE)

        if accept(:PARENTHESIS_LEFT, :PARENTHESIS_LEFT_GROUPING)
          lparen = previous_token

          if accept(:PARENTHESIS_RIGHT)
            receiver = parentheses_node(lparen, nil, previous_token, 0)
          else
            arguments.opening_loc = lparen.location
            receiver = parse_expression(BINDING_POWER_COMPOSITION, ACCEPTS_COMMAND_CALL | ACCEPTS_DO_BLOCK, :not_expression, depth + 1)

            unless @recovering
              accept(:NEWLINE)
              expect(:PARENTHESIS_RIGHT, :expect_rparen)
              arguments.closing_loc = previous_token.location
            end
          end
        else
          receiver = parse_expression(BINDING_POWER_NOT, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, :not_expression, depth + 1)
        end

        call_node_not(receiver, message, arguments)
      end

      # module Name ... end
      def parse_module(flags, depth)
        previous_block_exits = push_block_exits([])

        opening_newline_index = token_newline_index
        lex
        module_keyword = previous_token

        constant_path = parse_expression(BINDING_POWER_INDEX, flags & ACCEPTS_DO_BLOCK, :module_name, depth + 1)

        # A name that failed to parse.
        if constant_path.is_a?(ErrorRecoveryNode)
          pop_block_exits(previous_block_exits)

          missing = Token.new(:MISSING, @previous_end, @previous_end)
          return module_node(nil, module_keyword, constant_path, missing, nil, missing)
        end

        while accept(:COLON_COLON)
          double_colon = previous_token

          expect(:CONSTANT, :constant_path_colon_colon_constant)
          constant_path = constant_path_node(constant_path, double_colon, previous_token)
        end

        name = previous_token
        err_token(name, :module_name) if name.type != :CONSTANT
        unless constant_path.is_a?(ConstantReadNode) || constant_path.is_a?(ConstantPathNode) || constant_path.is_a?(ErrorRecoveryNode)
          constant_path = error_recovery_node_unexpected(constant_path)
        end

        scope_push(true)
        accept(:SEMICOLON, :NEWLINE)
        statements = nil

        unless match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE, :KEYWORD_ELSE, :KEYWORD_END)
          accepts_block_stack_push(true)
          statements = parse_statements(:module, depth + 1)
          accepts_block_stack_pop
        end

        if match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE, :KEYWORD_ELSE)
          statements = parse_rescues_implicit_begin(opening_newline_index, module_keyword, module_keyword.start, statements, :module, depth + 1)
        else
          warn_indentation_mismatch(opening_newline_index, module_keyword, false, false)
        end

        locals = locals_order(@current_scope.locals, false)

        scope_pop
        expect_opening(:KEYWORD_END, :module_term, module_keyword)

        err_token(module_keyword, :module_in_method) if context_def?

        pop_block_exits(previous_block_exits)

        module_node(locals, module_keyword, constant_path, name, statements, previous_token)
      end

      # while and until loops.
      def parse_loop(type, flags, depth)
        opening_newline_index = token_newline_index

        context_push(:loop_predicate)
        do_loop_stack_push(true)

        lex
        keyword = previous_token
        predicate_error = type == :while ? :conditional_while_predicate : :conditional_until_predicate
        predicate = parse_value_expression(BINDING_POWER_COMPOSITION, (flags & ACCEPTS_DO_BLOCK) | ACCEPTS_COMMAND_CALL, predicate_error, depth + 1)

        do_loop_stack_pop
        context_pop

        if accept(:KEYWORD_DO_LOOP)
          do_keyword = previous_token
        else
          do_keyword = NOT_PROVIDED
          expect(:NEWLINE, :SEMICOLON, predicate_error)
        end

        statements = nil
        unless @current_type == :KEYWORD_END
          accepts_block_stack_push(true)
          statements = parse_statements(type, depth + 1)
          accepts_block_stack_pop
          accept(:NEWLINE, :SEMICOLON)
        end

        warn_indentation_mismatch(opening_newline_index, keyword, false, false)

        if type == :while
          expect_opening(:KEYWORD_END, :while_term, keyword)
          while_node(keyword, do_keyword, previous_token, predicate, statements, 0)
        else
          expect_opening(:KEYWORD_END, :until_term, keyword)
          until_node(keyword, do_keyword, previous_token, predicate, statements, 0)
        end
      end

      # The end of a %-list: its closing token, or a missing one at the end
      # of the source.
      def parse_list_close(array, opening, term_error)
        closing = current_token
        if @current_type == :EOF
          err_token(opening, term_error)
          closing = Token.new(:MISSING, @previous_end, @previous_end)
        else
          expect(:STRING_END, term_error)
        end
        array_node_close_set(array, closing)
        array
      end

      # A symbol element of %i or %I that gains another string part: the
      # symbol becomes an interpolated symbol of its string and this one.
      def parse_list_symbol_split(current)
        content = Token.new(:STRING_CONTENT, loc_start(current.content_loc), loc_end(current.content_loc))
        first_string = string_node_unescaped(NOT_PROVIDED, content, NOT_PROVIDED, current.unescaped)
        # The C makes the second part from the previous token.
        second_string = string_node_current_string(NOT_PROVIDED, previous_token, NOT_PROVIDED)
        lex

        interpolated = interpolated_symbol_node(NOT_PROVIDED, nil, NOT_PROVIDED)
        interpolated_symbol_node_append(interpolated, first_string)
        interpolated_symbol_node_append(interpolated, second_string)
        interpolated
      end

      # %i[]
      def parse_percent_lower_i
        lex
        opening = previous_token
        array = array_node(opening)
        current = nil

        until match?(:STRING_END, :EOF)
          accept(:WORDS_SEP)
          break if @current_type == :STRING_END

          # Heredoc content after an escaped newline splits an element.
          while @current_type == :STRING_CONTENT
            case current
            when nil
              current = symbol_node_current_string(NOT_PROVIDED, current_token, NOT_PROVIDED)
              lex
            when InterpolatedSymbolNode
              string = string_node_current_string(NOT_PROVIDED, current_token, NOT_PROVIDED)
              lex
              interpolated_symbol_node_append(current, string)
            when SymbolNode
              current = parse_list_symbol_split(current)
            end
          end

          if current
            array_node_elements_append(array, current)
            current = nil
          else
            expect(:STRING_CONTENT, :list_i_lower_element)
          end
        end

        parse_list_close(array, opening, :list_i_lower_term)
      end

      # %I[] with interpolation.
      def parse_percent_upper_i(depth)
        lex
        opening = previous_token
        array = array_node(opening)
        current = nil

        until match?(:STRING_END, :EOF)
          case @current_type
          when :WORDS_SEP
            # Each element has its own encoding.
            @explicit_encoding = nil

            if current
              array_node_elements_append(array, current)
              current = nil
            end
            lex
          when :STRING_CONTENT
            case current
            when nil
              current = symbol_node_current_string(NOT_PROVIDED, current_token, NOT_PROVIDED)
              lex
            when InterpolatedSymbolNode
              string = string_node_current_string(NOT_PROVIDED, current_token, NOT_PROVIDED)
              lex
              interpolated_symbol_node_append(current, string)
            when SymbolNode
              current = parse_list_symbol_split(current)
            end
          when :EMBVAR, :EMBEXPR_BEGIN
            start_location_set = false
            if current.nil?
              current = interpolated_symbol_node(NOT_PROVIDED, nil, NOT_PROVIDED)
            elsif current.is_a?(SymbolNode)
              interpolated = interpolated_symbol_node(NOT_PROVIDED, nil, NOT_PROVIDED)

              string = symbol_node_to_string_node(current)
              interpolated_symbol_node_append(interpolated, string)
              interpolated.start_offset_keep_length = string.start_offset
              start_location_set = true
              current = interpolated
            end

            part = parse_string_part(depth + 1)
            interpolated_symbol_node_append(current, part)
            current.start_offset_keep_length = part.start_offset unless start_location_set
          else
            expect(:STRING_CONTENT, :list_i_upper_element)
            lex
          end
        end

        array_node_elements_append(array, current) if current

        parse_list_close(array, opening, :list_i_upper_term)
      end

      # %w[]
      def parse_percent_lower_w
        lex
        opening = previous_token
        array = array_node(opening)
        current = nil

        until match?(:STRING_END, :EOF)
          accept(:WORDS_SEP)
          break if @current_type == :STRING_END

          while @current_type == :STRING_CONTENT
            string = string_node_current_string(NOT_PROVIDED, current_token, NOT_PROVIDED)

            case current
            when nil
              current = string
            when InterpolatedStringNode
              interpolated_string_node_append(current, string)
            when StringNode
              interpolated = interpolated_string_node(NOT_PROVIDED, nil, NOT_PROVIDED)
              interpolated_string_node_append(interpolated, current)
              interpolated_string_node_append(interpolated, string)
              current = interpolated
            end
            lex
          end

          if current
            array_node_elements_append(array, current)
            current = nil
          else
            expect(:STRING_CONTENT, :list_w_lower_element)
          end
        end

        parse_list_close(array, opening, :list_w_lower_term)
      end

      # %W[] with interpolation.
      def parse_percent_upper_w(depth)
        lex
        opening = previous_token
        array = array_node(opening)
        current = nil

        until match?(:STRING_END, :EOF)
          case @current_type
          when :WORDS_SEP
            # Each element has its own encoding.
            @explicit_encoding = nil

            if current
              array_node_elements_append(array, current)
              current = nil
            end
            lex
          when :STRING_CONTENT
            string = string_node_current_string(NOT_PROVIDED, current_token, NOT_PROVIDED)
            string.flag_set(parse_unescaped_encoding)
            lex

            case current
            when nil
              current = string
            when InterpolatedStringNode
              interpolated_string_node_append(current, string)
            when StringNode
              interpolated = interpolated_string_node(NOT_PROVIDED, nil, NOT_PROVIDED)
              interpolated_string_node_append(interpolated, current)
              interpolated_string_node_append(interpolated, string)
              current = interpolated
            end
          when :EMBVAR, :EMBEXPR_BEGIN
            if current.nil?
              current = interpolated_string_node(NOT_PROVIDED, nil, NOT_PROVIDED)
            elsif current.is_a?(StringNode)
              interpolated = interpolated_string_node(NOT_PROVIDED, nil, NOT_PROVIDED)
              interpolated_string_node_append(interpolated, current)
              current = interpolated
            end

            part = parse_string_part(depth + 1)
            interpolated_string_node_append(current, part)
          else
            expect(:STRING_CONTENT, :list_w_upper_element)
            lex
          end
        end

        array_node_elements_append(array, current) if current

        parse_list_close(array, opening, :list_w_upper_term)
      end

      # /regexp/
      def parse_regexp_literal(depth)
        opening = current_token
        lex

        if @current_type == :REGEXP_END
          # //
          content = Token.new(:STRING_CONTENT, @previous_end, @previous_end)
          lex

          node = regular_expression_node(opening, content, previous_token)
          node.flag_set(regexp_parse(node))
          return node
        end

        if @current_type == :STRING_CONTENT
          unescaped = @current_string
          content = current_token
          lex

          if accept(:REGEXP_END)
            node = regular_expression_node_unescaped(opening, content, previous_token, unescaped)

            # Before `=~` the regexp is checked with its named captures.
            node.flag_set(regexp_parse(node)) unless @current_type == :EQUAL_TILDE
            return node
          end

          interpolated = interpolated_regular_expression_node(opening)

          part = string_node_unescaped(NOT_PROVIDED, previous_token, NOT_PROVIDED, unescaped)

          # The first part of a regexp in a US-ASCII file is always binary.
          part.flag_set(StringFlags::FORCED_BINARY_ENCODING) if @encoding == Encodings::US_ASCII

          interpolated_regular_expression_node_append(interpolated, part)
        else
          interpolated = interpolated_regular_expression_node(opening)
        end

        until match?(:REGEXP_END, :EOF)
          part = parse_string_part(depth + 1)
          interpolated_regular_expression_node_append(interpolated, part) if part
        end

        closing = current_token
        if @current_type == :EOF
          err_token(opening, :regexp_term)
          closing = Token.new(:MISSING, @previous_end, @previous_end)
        else
          expect(:REGEXP_END, :regexp_term)
        end

        interpolated_regular_expression_node_closing_set(interpolated, closing)
        interpolated
      end

      # `xstring`, %x()
      def parse_xstring_literal(depth)
        lex
        opening = previous_token

        if @current_type == :STRING_END
          content = Token.new(:STRING_CONTENT, @previous_end, @previous_end)
          lex
          return xstring_node(opening, content, previous_token)
        end

        if @current_type == :STRING_CONTENT
          unescaped = @current_string
          content = current_token
          lex

          if @current_type == :STRING_END
            node = xstring_node_unescaped(opening, content, current_token, unescaped)
            node.flag_set(parse_unescaped_encoding)
            lex
            return node
          end

          node = interpolated_xstring_node(opening, opening)

          part = string_node_unescaped(NOT_PROVIDED, previous_token, NOT_PROVIDED, unescaped)
          part.flag_set(parse_unescaped_encoding)

          interpolated_xstring_node_append(node, part)
        else
          node = interpolated_xstring_node(opening, opening)
        end

        until match?(:STRING_END, :EOF)
          part = parse_string_part(depth + 1)
          interpolated_xstring_node_append(node, part) if part
        end

        closing = current_token
        if @current_type == :EOF
          err_token(opening, :xstring_term)
          closing = Token.new(:MISSING, @previous_end, @previous_end)
        else
          expect(:STRING_END, :xstring_term)
        end
        interpolated_node_closing_set(node, closing)

        node
      end

      # parse_splat: `*` (just lexed) and the optional expression after it.
      def parse_splat(flags, depth)
        operator = previous_token
        name = nil
        if token_begins_expression?(@current_type)
          name = parse_expression(BINDING_POWER_INDEX, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_star, depth + 1)
        end

        splat_node(operator, name)
      end

      # *splat at the start of a multiple write.
      def parse_splat_target(binding_power, flags, diag_id, depth)
        lex

        # Only a multiple write may start with *.
        if binding_power != BINDING_POWER_STATEMENT
          err_prefix(diag_id)
          return error_recovery_node(@previous_start, @previous_end)
        end

        splat = parse_splat(flags, depth)

        return parse_targets_validate(splat, BINDING_POWER_INDEX, depth + 1) if @current_type == :COMMA

        parse_target_validate(splat, true)
      end

      # ! ~ -@ +@ as prefix operators.
      def parse_unary(binding_power, name, flags, depth)
        err_prefix(:unary_disallowed) if binding_power > BINDING_POWER_UNARY

        lex

        operator = previous_token
        receiver_flags = flags & ACCEPTS_DO_BLOCK
        receiver_flags |= ACCEPTS_COMMAND_CALL if name == "!" && binding_power < BINDING_POWER_MATCH
        receiver = parse_expression(BINDING_POWERS[@previous_type].right, receiver_flags, :unary_receiver, depth + 1)
        node = call_node_unary(operator, receiver, name)

        node.receiver = conditional_predicate(receiver, :not) if name == "!"
        node
      end

      # -1, and -2 ** 2 as -(2 ** 2).
      def parse_negative_number(flags, depth)
        lex

        operator = previous_token
        node = parse_expression(BINDING_POWERS[@previous_type].right, flags & ACCEPTS_DO_BLOCK, :unary_receiver, depth + 1)

        if accept(:STAR_STAR)
          exponent_operator = previous_token
          exponent = parse_expression(BINDING_POWERS[exponent_operator.type].right, flags & ACCEPTS_DO_BLOCK, :expect_argument, depth + 1)
          node = call_node_binary(node, exponent_operator, exponent, 0)
          call_node_unary(operator, node, "-@")
        elsif node.is_a?(IntegerNode) || node.is_a?(FloatNode) || node.is_a?(RationalNode) || node.is_a?(ImaginaryNode)
          parse_negative_numeric(node)
          node
        else
          call_node_unary(operator, node, "-@")
        end
      end

      # -> (params) { body }
      def parse_lambda(depth)
        previous_lambda_enclosure_nesting = @lambda_enclosure_nesting
        @lambda_enclosure_nesting = @enclosure_nesting

        opening_newline_index = token_newline_index
        lex

        operator = previous_token
        scope_push(false)

        case @current_type
        when :PARENTHESIS_LEFT
          opening = current_token
          lex

          block_parameters =
            if @current_type == :PARENTHESIS_RIGHT
              block_parameters_node(nil, opening)
            else
              parse_block_parameters(false, opening, true, true, depth + 1)
            end

          accept(:NEWLINE)
          expect(:PARENTHESIS_RIGHT, :expect_rparen)

          block_parameters_node_closing_set(block_parameters, previous_token)
        when *CASE_PARAMETER
          block_parameters = parse_block_parameters(false, NOT_PROVIDED, true, false, depth + 1)
        else
          block_parameters = nil
        end

        body = nil

        if accept(:LAMBDA_BEGIN)
          opening = previous_token

          body = parse_statements(:lambda_braces, depth + 1) unless @current_type == :BRACE_RIGHT

          warn_indentation_mismatch(opening_newline_index, operator, false, false)

          # The token after the `}` lexes in the enclosing lambda's nesting.
          @lambda_enclosure_nesting = previous_lambda_enclosure_nesting
          expect_opening(:BRACE_RIGHT, :lambda_term_brace, opening)
        else
          # The lexer manages the frame of a `{ }` body; a `do end` body
          # pushes its own before the `do` lexes the body's first token.
          accepts_block_stack_push(true)
          expect(:KEYWORD_DO_LAMBDA, :lambda_open)
          opening = previous_token

          # No token in the body is at the start of a lambda, also when
          # the `do` is missing.
          @lambda_enclosure_nesting = -1

          body = parse_statements(:lambda_do_end, depth + 1) unless match?(:KEYWORD_END, :KEYWORD_RESCUE, :KEYWORD_ENSURE)

          if match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE)
            body = parse_rescues_implicit_begin(opening_newline_index, operator, opening.start, body, :lambda, depth + 1)
          else
            warn_indentation_mismatch(opening_newline_index, operator, false, false)
          end

          accepts_block_stack_pop

          @lambda_enclosure_nesting = previous_lambda_enclosure_nesting
          expect_opening(:KEYWORD_END, :lambda_term_end, operator)
        end

        locals = locals_order(@current_scope.locals, scope_toplevel?)
        parameters = parse_blocklike_parameters(block_parameters, operator, previous_token)

        scope_pop

        lambda_node(locals, operator, opening, previous_token, parameters, body)
      end

      # A token no expression starts with: an error, and a missing node. A
      # token that closes an enclosing context starts recovery.
      def parse_unexpected(diag_id)
        recoverable = context_recoverable(@current_type)

        if recoverable != :none
          @recovering = true

          # A specific error adds context to the recovery's own.
          err_prefix(diag_id) if diag_id != :cannot_parse_expression

          err_current(:unexpected_token_close_context, Tokens::HUMAN.fetch(@current_type), context_human(recoverable))
        elsif diag_id == :cannot_parse_expression
          err_current(:unexpected_token_ignore, Tokens::HUMAN.fetch(@current_type))
        else
          err_prefix(diag_id)
        end

        error_recovery_node(@previous_start, @previous_end)
      end

      # pm_parser_err_prefix: the errors whose messages name a token.
      def err_prefix(diag_id)
        case diag_id
        when :hash_key
          err_previous(diag_id, Tokens::HUMAN.fetch(@previous_type))
        when :hash_value, :expect_expression_after_operator, :unary_disallowed, :expect_argument
          err_current(diag_id, Tokens::HUMAN.fetch(@current_type))
        when :unary_receiver
          human = @current_type == :EOF ? "end-of-input" : Tokens::HUMAN.fetch(@current_type)
          err_previous(diag_id, human, @source.getbyte(@previous_start))
        else
          err_previous(diag_id)
        end
      end

      # parse_retry: a retry belongs in a rescue clause.
      RETRY_CONTEXTS = {
        begin_rescue: :valid, block_rescue: :valid, class_rescue: :valid, def_rescue: :valid, lambda_rescue: :valid,
        module_rescue: :valid, sclass_rescue: :valid, defined: :valid, rescue_modifier: :valid,
        class: :invalid, def: :invalid, def_params: :invalid, main: :invalid, module: :invalid, preexe: :invalid,
        sclass: :invalid,
        begin_else: :else, block_else: :else, class_else: :else, def_else: :else, lambda_else: :else,
        module_else: :else, sclass_else: :else,
        begin_ensure: :ensure, block_ensure: :ensure, class_ensure: :ensure, def_ensure: :ensure,
        lambda_ensure: :ensure, module_ensure: :ensure, sclass_ensure: :ensure
      }

      def parse_retry(node)
        through = nil
        @contexts.reverse_each do |context|
          case RETRY_CONTEXTS[context]
          when :valid then return
          when :invalid
            id =
              case through
              when nil then :invalid_retry_without_rescue
              when :ensure then :invalid_retry_after_ensure
              else :invalid_retry_after_else
              end
            err_node(node, id)
            return
          when :else, :ensure
            through = RETRY_CONTEXTS[context]
          end
        end
      end

      # parse_yield: a yield belongs in a method.
      YIELD_CONTEXTS = {
        def: :valid, def_params: :valid, defined: :valid, def_ensure: :valid, def_rescue: :valid, def_else: :valid,
        class: :invalid, class_ensure: :invalid, class_rescue: :invalid, class_else: :invalid, main: :invalid,
        module: :invalid, module_ensure: :invalid, module_rescue: :invalid, module_else: :invalid, sclass: :invalid,
        sclass_rescue: :invalid, sclass_ensure: :invalid, sclass_else: :invalid
      }

      def parse_yield(node)
        @contexts.reverse_each do |context|
          case YIELD_CONTEXTS[context]
          when :valid then return
          when :invalid
            err_node(node, :invalid_yield)
            return
          end
        end
      end

      # parse_expression_prefix: an expression from its first token.
      def parse_expression_prefix(binding_power, flags, diag_id, depth)
        case @current_type
        when :BRACKET_LEFT_ARRAY then parse_array_literal(flags, depth)
        when :PARENTHESIS_LEFT_GROUPING, :PARENTHESIS_LEFT_PARENTHESES then parse_parentheses(binding_power, flags, depth)
        when :BRACE_LEFT_HASH then parse_hash_literal(depth)
        when :CHARACTER_LITERAL then parse_character_literal(depth)
        when :CLASS_VARIABLE
          lex
          parse_statement_targets(class_variable_read_node(previous_token), binding_power, depth)
        when :CONSTANT then parse_constant(binding_power, flags, depth)
        when :UCOLON_COLON
          lex
          delimiter = previous_token

          expect(:CONSTANT, :constant_path_colon_colon_constant)
          parse_statement_targets(constant_path_node(nil, delimiter, previous_token), binding_power, depth)
        when :UDOT_DOT, :UDOT_DOT_DOT
          operator = current_token
          lex

          right = parse_expression(BINDING_POWERS[operator.type].left, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_operator, depth + 1)

          # `..1..2` is not allowed.
          err_current(:unexpected_range_operator) if match?(:DOT_DOT, :DOT_DOT_DOT)

          range_node(nil, operator, right)
        when :FLOAT
          lex
          float_node(previous_token)
        when :FLOAT_IMAGINARY
          lex
          float_node_imaginary(previous_token)
        when :FLOAT_RATIONAL
          lex
          float_node_rational(previous_token)
        when :FLOAT_RATIONAL_IMAGINARY
          lex
          float_node_rational_imaginary(previous_token)
        when :NUMBERED_REFERENCE
          lex
          parse_statement_targets(numbered_reference_read_node(previous_token), binding_power, depth)
        when :GLOBAL_VARIABLE
          lex
          parse_statement_targets(global_variable_read_node(previous_token), binding_power, depth)
        when :BACK_REFERENCE
          lex
          parse_statement_targets(back_reference_read_node(previous_token), binding_power, depth)
        when :IDENTIFIER, :METHOD_NAME then parse_identifier(binding_power, flags, depth)
        when :HEREDOC_START then parse_heredoc(depth)
        when :INSTANCE_VARIABLE
          lex
          parse_statement_targets(instance_variable_read_node(previous_token), binding_power, depth)
        when :INTEGER
          base = @integer_base
          lex
          integer_node(base, previous_token)
        when :INTEGER_IMAGINARY
          base = @integer_base
          lex
          integer_node_imaginary(base, previous_token)
        when :INTEGER_RATIONAL
          base = @integer_base
          lex
          integer_node_rational(base, previous_token)
        when :INTEGER_RATIONAL_IMAGINARY
          base = @integer_base
          lex
          integer_node_rational_imaginary(base, previous_token)
        when :KEYWORD___ENCODING__
          lex
          source_encoding_node(previous_token)
        when :KEYWORD___FILE__
          lex
          source_file_node(previous_token)
        when :KEYWORD___LINE__
          lex
          source_line_node(previous_token)
        when :KEYWORD_ALIAS then parse_alias(binding_power, flags, depth)
        when :KEYWORD_CASE then parse_case(flags, depth)
        when :KEYWORD_BEGIN then parse_begin(depth)
        when :KEYWORD_BEGIN_UPCASE then parse_pre_execution(binding_power, depth)
        when :KEYWORD_BREAK, :KEYWORD_NEXT, :KEYWORD_RETURN then parse_jump(flags, depth)
        when :KEYWORD_SUPER then parse_super(flags, depth)
        when :KEYWORD_YIELD then parse_yield_expression(flags, depth)
        when :KEYWORD_CLASS then parse_class(flags, depth)
        when :KEYWORD_DEF then parse_def(binding_power, flags, depth)
        when :KEYWORD_DEFINED then parse_defined(flags, depth)
        when :KEYWORD_END_UPCASE then parse_post_execution(binding_power, flags, depth)
        when :KEYWORD_FALSE
          lex
          false_node(previous_token)
        when :KEYWORD_FOR then parse_for(flags, depth)
        when :KEYWORD_IF then parse_if(depth)
        when :KEYWORD_UNDEF then parse_undef(binding_power, flags, depth)
        when :KEYWORD_NOT then parse_not(binding_power, flags, depth)
        when :KEYWORD_UNLESS
          opening_newline_index = token_newline_index
          lex
          parse_conditional(:unless, opening_newline_index, false, depth + 1)
        when :KEYWORD_MODULE then parse_module(flags, depth)
        when :KEYWORD_NIL
          lex
          nil_node(previous_token)
        when :KEYWORD_REDO
          lex
          node = redo_node(previous_token)
          parse_block_exit(node) unless @partial_script
          node
        when :KEYWORD_RETRY
          lex
          node = retry_node(previous_token)
          parse_retry(node)
          node
        when :KEYWORD_SELF
          lex
          self_node(previous_token)
        when :KEYWORD_TRUE
          lex
          true_node(previous_token)
        when :KEYWORD_UNTIL then parse_loop(:until, flags, depth)
        when :KEYWORD_WHILE then parse_loop(:while, flags, depth)
        when :PERCENT_LOWER_I then parse_percent_lower_i
        when :PERCENT_UPPER_I then parse_percent_upper_i(depth)
        when :PERCENT_LOWER_W then parse_percent_lower_w
        when :PERCENT_UPPER_W then parse_percent_upper_w(depth)
        when :REGEXP_BEGIN then parse_regexp_literal(depth)
        when :XSTRING_BEGIN, :PERCENT_LOWER_X then parse_xstring_literal(depth)
        when :USTAR then parse_splat_target(binding_power, flags, diag_id, depth)
        when :BANG then parse_unary(binding_power, "!", flags, depth)
        when :TILDE then parse_unary(binding_power, "~", flags, depth)
        when :UMINUS then parse_unary(binding_power, "-@", flags, depth)
        when :UMINUS_NUM then parse_negative_number(flags, depth)
        when :MINUS_GREATER then parse_lambda(depth)
        when :UPLUS then parse_unary(binding_power, "+@", flags, depth)
        when :STRING_BEGIN then parse_strings(nil, flags.anybits?(ACCEPTS_LABEL), depth + 1)
        when :SYMBOL_BEGIN
          lex_mode = @lex_mode.dup
          lex
          parse_symbol(lex_mode, STATE_END, depth + 1)
        else
          parse_unexpected(diag_id)
        end
      end
    end
  end
end
