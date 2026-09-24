# frozen_string_literal: true
# shareable_constant_value: literal

using Prism::Ruby::Mutation

module Prism
  module Ruby
    class Parser
      # pm_parameters_order_t: where a parameter list is, from NONE (nothing
      # yet) down to NOTHING_AFTER; a parameter may not move back up.
      PARAMETERS_NO_CHANGE = 0
      PARAMETERS_ORDER_NOTHING_AFTER = 1
      PARAMETERS_ORDER_KEYWORDS_REST = 2
      PARAMETERS_ORDER_KEYWORDS = 3
      PARAMETERS_ORDER_REST = 4
      PARAMETERS_ORDER_AFTER_OPTIONAL = 5
      PARAMETERS_ORDER_OPTIONAL = 6
      PARAMETERS_ORDER_NAMED = 7
      PARAMETERS_ORDER_NONE = 8

      # parameters_ordering
      PARAMETERS_ORDERING = Hash.new(PARAMETERS_NO_CHANGE).merge!(
        UAMPERSAND: PARAMETERS_ORDER_NOTHING_AFTER, AMPERSAND: PARAMETERS_ORDER_NOTHING_AFTER,
        UDOT_DOT_DOT: PARAMETERS_ORDER_NOTHING_AFTER, IDENTIFIER: PARAMETERS_ORDER_NAMED,
        PARENTHESIS_LEFT: PARAMETERS_ORDER_NAMED, EQUAL: PARAMETERS_ORDER_OPTIONAL, LABEL: PARAMETERS_ORDER_KEYWORDS,
        USTAR: PARAMETERS_ORDER_AFTER_OPTIONAL, STAR: PARAMETERS_ORDER_AFTER_OPTIONAL,
        USTAR_STAR: PARAMETERS_ORDER_KEYWORDS_REST, STAR_STAR: PARAMETERS_ORDER_KEYWORDS_REST
      ).freeze

      # The errors for a parameter named like a constant or a variable.
      FORMAL_ARGUMENT_ERRORS = {
        CONSTANT: :argument_formal_constant, INSTANCE_VARIABLE: :argument_formal_ivar,
        GLOBAL_VARIABLE: :argument_formal_global, CLASS_VARIABLE: :argument_formal_class
      }

      private

      # parse_required_destructured_parameter: `(a, *b, (c, d))` among
      # parameters.
      def parse_required_destructured_parameter
        expect(:PARENTHESIS_LEFT, :expect_lparen_req_parameter)

        node = multi_target_node
        multi_target_node_opening_set(node, previous_token)

        loop do
          # A trailing comma is not allowed here.
          if !node.lefts.empty? && @current_type == :PARENTHESIS_RIGHT
            multi_target_node_targets_append(node, implicit_rest_node(previous_token))
            err_current(:parameter_wild_loose_comma)
            break
          end

          if @current_type == :PARENTHESIS_LEFT
            param = parse_required_destructured_parameter
          elsif accept(:USTAR)
            star = previous_token
            value = nil

            if accept(:IDENTIFIER)
              name = previous_token
              value = required_parameter_node(name)
              flag_repeated_parameter(value) if parameter_name_check(name)
              local_add_token(name, 1)
            end

            param = splat_node(star, value)
          else
            expect(:IDENTIFIER, :expect_ident_req_parameter)
            name = previous_token

            param = required_parameter_node(name)
            flag_repeated_parameter(param) if parameter_name_check(name)
            local_add_token(name, 1)
          end

          multi_target_node_targets_append(node, param)
          break unless accept(:COMMA)
        end

        accept(:NEWLINE)
        expect(:PARENTHESIS_RIGHT, :expect_rparen_req_parameter)
        multi_target_node_closing_set(node, previous_token)

        node
      end

      # update_parameter_state: the order after the parameter that starts with
      # `token`, or an error when it is out of order. Answers the new order
      # and whether the parameter was in order.
      def update_parameter_state(token, current)
        state = PARAMETERS_ORDERING[token.type]
        return [current, true] if state == PARAMETERS_NO_CHANGE

        # Named parameters may follow optional ones, until something else.
        return [PARAMETERS_ORDER_AFTER_OPTIONAL, true] if current == PARAMETERS_ORDER_OPTIONAL && state == PARAMETERS_ORDER_NAMED
        return [current, true] if current == PARAMETERS_ORDER_AFTER_OPTIONAL && state == PARAMETERS_ORDER_NAMED

        if token.type == :USTAR && current == PARAMETERS_ORDER_AFTER_OPTIONAL
          err_token(token, :parameter_star)
          return [current, false]
        elsif token.type == :UDOT_DOT_DOT && current >= PARAMETERS_ORDER_KEYWORDS_REST && current <= PARAMETERS_ORDER_AFTER_OPTIONAL
          err_token(token, current == PARAMETERS_ORDER_AFTER_OPTIONAL ? :parameter_forwarding_after_rest : :parameter_order)
          return [current, false]
        elsif current == PARAMETERS_ORDER_NOTHING_AFTER || state > current
          err_token(token, :parameter_order)
          return [current, false]
        end

        [[state, current].min, true]
      end

      # parse_parameters: a method's, block's or lambda's parameters; nil
      # when there are none.
      def parse_parameters(binding_power, uses_parentheses, allows_trailing_comma, allows_forwarding_parameters,
                           accepts_blocks_in_defaults, in_block, depth)
        do_loop_stack_push(false)

        params = parameters_node
        order = PARAMETERS_ORDER_NONE

        loop do
          parsing = true

          case @current_type
          when :PARENTHESIS_LEFT
            order, = update_parameter_state(current_token, order)
            param = parse_required_destructured_parameter

            if order > PARAMETERS_ORDER_AFTER_OPTIONAL
              parameters_node_requireds_append(params, param)
            else
              parameters_node_posts_append(params, param)
            end
          when :UAMPERSAND, :AMPERSAND
            order, = update_parameter_state(current_token, order)
            lex

            operator = previous_token
            repeated = false
            if accept(:IDENTIFIER)
              name = previous_token
              repeated = parameter_name_check(name)
              local_add_token(name, 1)
            else
              name = NOT_PROVIDED
              @current_scope.parameters |= Scope::FORWARDING_BLOCK
            end

            param = block_parameter_node(name, operator)
            flag_repeated_parameter(param) if repeated
            if params.block.nil?
              parameters_node_block_set(params, param)
            else
              err_node(param, :parameter_block_multi)
              parameters_node_posts_append(params, param)
            end
          when :UDOT_DOT_DOT
            err_current(:argument_no_forwarding_ellipses) unless allows_forwarding_parameters

            order, succeeded = update_parameter_state(current_token, order)
            lex

            @current_scope.parameters |= Scope::FORWARDING_ALL
            param = forwarding_parameter_node(previous_token)

            if params.keyword_rest
              # The forwarding takes the keyword rest's place, which moves to
              # the posts.
              parameters_node_posts_append(params, params.keyword_rest)
              err_previous(:parameter_unexpected_fwd) if succeeded
              params.keyword_rest = nil
            end

            parameters_node_keyword_rest_set(params, param)
          when :CLASS_VARIABLE, :IDENTIFIER, :CONSTANT, :INSTANCE_VARIABLE, :GLOBAL_VARIABLE, :METHOD_NAME
            lex
            if (id = FORMAL_ARGUMENT_ERRORS[@previous_type])
              err_previous(id)
            elsif @previous_type == :METHOD_NAME
              err_previous(:parameter_method_name)
            end

            order, = update_parameter_state(@current_type == :EQUAL ? current_token : previous_token, order)

            name = previous_token
            repeated = parameter_name_check(name)
            local_add_token(name, 1)

            if @current_type == :EQUAL
              operator = current_token
              context_push(:default_params)
              lex

              name_id = constant_id_location(name.start, name.end)
              reads = before_3_4? ? @current_scope.locals.reads(name_id) : 0

              accepts_block_stack_push(true) if accepts_blocks_in_defaults
              value = parse_value_expression(binding_power, false, false, :parameter_no_default, depth + 1)
              accepts_block_stack_pop if accepts_blocks_in_defaults

              param = optional_parameter_node(name, operator, value)
              flag_repeated_parameter(param) if repeated
              parameters_node_optionals_append(params, param)

              # A default that reads its own parameter is circular.
              if before_3_4? && @current_scope.locals.reads(name_id) != reads
                err_token_content(name, :parameter_circular)
              end

              context_pop

              parsing = false if @recovering
            else
              param = required_parameter_node(name)
              flag_repeated_parameter(param) if repeated

              if order > PARAMETERS_ORDER_AFTER_OPTIONAL
                parameters_node_requireds_append(params, param)
              else
                parameters_node_posts_append(params, param)
              end
            end
          when :LABEL
            @in_keyword_arg = true if !uses_parentheses && !in_block
            order, = update_parameter_state(current_token, order)

            context_push(:default_params)
            lex

            name = previous_token
            local = Token.new(name.type, name.start, name.end - 1)

            upper = @encoding_changed ? @encoding.isupper_char(@source, local.start, local.end - local.start) : Encodings::UTF_8.isupper_char(@source, local.start, local.end - local.start)
            last = @source.getbyte(local.end - 1)
            if upper
              err(local.start, local.end, :argument_formal_constant)
            elsif last == 0x21 || last == 0x3F
              err_token_content(local, :invalid_local_variable_write)
            end

            repeated = parameter_name_check(local)
            local_add_token(local, 1)

            case @current_type
            when :COMMA, :PARENTHESIS_RIGHT, :PIPE
              context_pop

              param = required_keyword_parameter_node(name)
              flag_repeated_parameter(param) if repeated
              parameters_node_keywords_append(params, param)
            when :SEMICOLON, :NEWLINE
              context_pop

              if uses_parentheses
                parsing = false
              else
                param = required_keyword_parameter_node(name)
                flag_repeated_parameter(param) if repeated
                parameters_node_keywords_append(params, param)
              end
            else
              if token_begins_expression?(@current_type)
                name_id = constant_id_location(local.start, local.end)
                reads = before_3_4? ? @current_scope.locals.reads(name_id) : 0

                accepts_block_stack_push(true) if accepts_blocks_in_defaults
                value = parse_value_expression(binding_power, false, false, :parameter_no_default_kw, depth + 1)
                accepts_block_stack_pop if accepts_blocks_in_defaults

                if before_3_4? && @current_scope.locals.reads(name_id) != reads
                  err_token_content(local, :parameter_circular)
                end

                param = optional_keyword_parameter_node(name, value)
              else
                param = required_keyword_parameter_node(name)
              end

              flag_repeated_parameter(param) if repeated

              context_pop
              parameters_node_keywords_append(params, param)

              parsing = false if @recovering
            end

            @in_keyword_arg = false
          when :USTAR, :STAR
            order, = update_parameter_state(current_token, order)
            lex

            operator = previous_token
            repeated = false

            if accept(:IDENTIFIER)
              name = previous_token
              repeated = parameter_name_check(name)
              local_add_token(name, 1)
            else
              name = NOT_PROVIDED
              @current_scope.parameters |= Scope::FORWARDING_POSITIONALS
            end

            param = rest_parameter_node(operator, name)
            flag_repeated_parameter(param) if repeated

            if params.rest.nil?
              parameters_node_rest_set(params, param)
            else
              err_node(param, :parameter_splat_multi)
              parameters_node_posts_append(params, param)
            end
          when :STAR_STAR, :USTAR_STAR
            previous_order = order
            order, = update_parameter_state(current_token, order)
            lex

            operator = previous_token

            if accept(:KEYWORD_NIL)
              err_previous(:parameter_unexpected_no_kw) if previous_order <= PARAMETERS_ORDER_KEYWORDS

              param = no_keywords_parameter_node(operator, previous_token)
            else
              repeated = false
              if accept(:IDENTIFIER)
                name = previous_token
                repeated = parameter_name_check(name)
                local_add_token(name, 1)
              else
                name = NOT_PROVIDED
                @current_scope.parameters |= Scope::FORWARDING_KEYWORDS
              end

              param = keyword_rest_parameter_node(operator, name)
              flag_repeated_parameter(param) if repeated
            end

            if params.keyword_rest.nil?
              parameters_node_keyword_rest_set(params, param)
            else
              err_node(param, :parameter_assoc_splat_multi)
              parameters_node_posts_append(params, param)
            end
          else
            if @previous_type == :COMMA
              if allows_trailing_comma && order >= PARAMETERS_ORDER_NAMED
                # A trailing comma in block parameters.
                param = implicit_rest_node(previous_token)

                if params.rest.nil?
                  parameters_node_rest_set(params, param)
                else
                  err_node(param, :parameter_splat_multi)
                  parameters_node_posts_append(params, param)
                end
              else
                err_previous(:parameter_wild_loose_comma)
              end
            end

            parsing = false
          end

          break unless parsing

          accepted_newline = uses_parentheses && accept(:NEWLINE)

          break unless accept(:COMMA)

          err_previous(:invalid_comma) if accepted_newline
        end

        do_loop_stack_pop

        # No parameters: nil rather than an empty node.
        return if params.location.nil? || params.start_offset == params.end_offset

        params
      end

      # token_newline_index: the line index the current token is on.
      def token_newline_index
        @heredoc_end.nil? ? @newlines.size - 1 : newline_line(@current_start, 0)
      end

      # token_column: the token's column, with tabs to the next multiple of
      # 8; with `break_on_non_space`, -1 when anything but spaces and tabs
      # comes before it on its line.
      def token_column(newline_index, token, break_on_non_space)
        cursor = @newlines[newline_index]
        cursor += 3 if newline_index == 0 && @source.getbyte(0) == 0xEF && @source.getbyte(1) == 0xBB && @source.getbyte(2) == 0xBF

        column = 0
        while cursor < token.start
          case @source.getbyte(cursor)
          when 0x09 then column = (column / TAB_WHITESPACE_SIZE + 1) * TAB_WHITESPACE_SIZE
          when 0x20 then column += 1
          else
            column += 1
            return -1 if break_on_non_space
          end
          cursor += 1
        end
        column
      end

      # parser_warn_indentation_mismatch: a warning when the current token
      # (an `end`, `else` and the like) is indented differently from the
      # token that opened it.
      def warn_indentation_mismatch(opening_newline_index, opening_token, if_after_else, allow_indent)
        return unless @warn_mismatched_indentation

        closing_newline_index = token_newline_index
        return if opening_newline_index == closing_newline_index

        opening_column = token_column(opening_newline_index, opening_token, !if_after_else)
        return if !if_after_else && opening_column == -1

        closing_token = current_token
        closing_column = token_column(closing_newline_index, closing_token, true)
        return if closing_column == -1 || opening_column == closing_column
        return if allow_indent && closing_column > opening_column

        warn(closing_token.start, closing_token.end, :indentation_mismatch, token_slice(closing_token),
             token_slice(opening_token), opening_newline_index + @start_line)
      end

      # The contexts each kind of rescue clause's statements are in:
      # [rescue, else, ensure].
      RESCUES_CONTEXTS = {
        begin: %i[begin_rescue begin_else begin_ensure], block: %i[block_rescue block_else block_ensure],
        class: %i[class_rescue class_else class_ensure], def: %i[def_rescue def_else def_ensure],
        lambda: %i[lambda_rescue lambda_else lambda_ensure], module: %i[module_rescue module_else module_ensure],
        sclass: %i[sclass_rescue sclass_else sclass_ensure]
      }

      # parse_rescues: the rescue, else and ensure clauses and the end of
      # `parent_node`, a begin node. `opening` (or nil) is the token whose
      # indentation the clauses should match; `type` is the kind of body.
      def parse_rescues(opening_newline_index, opening, parent_node, type, depth)
        rescue_context, else_context, ensure_context = RESCUES_CONTEXTS.fetch(type)
        current = nil

        while @current_type == :KEYWORD_RESCUE
          warn_indentation_mismatch(opening_newline_index, opening, false, false) if opening
          lex

          rescue_clause = rescue_node(previous_token)

          case @current_type
          when :EQUAL_GREATER
            # `rescue => e` rescues StandardError.
            lex
            rescue_node_operator_set(rescue_clause, previous_token)

            reference = parse_expression(BINDING_POWER_INDEX, false, false, :rescue_variable, depth + 1)
            reference = parse_target(reference, false, false)

            rescue_node_reference_set(rescue_clause, reference)
          when :NEWLINE, :SEMICOLON, :KEYWORD_THEN
            # No exceptions.
          else
            if token_begins_expression?(@current_type) || @current_type == :USTAR
              loop do
                expression = parse_starred_expression(BINDING_POWER_DEFINED, false, :rescue_expression, depth + 1)
                rescue_node_exceptions_append(rescue_clause, expression)

                break if match?(:NEWLINE, :SEMICOLON, :KEYWORD_THEN)

                if accept(:EQUAL_GREATER)
                  rescue_node_operator_set(rescue_clause, previous_token)

                  reference = parse_expression(BINDING_POWER_INDEX, false, false, :rescue_variable, depth + 1)
                  reference = parse_target(reference, false, false)

                  rescue_node_reference_set(rescue_clause, reference)
                  break
                end

                break unless accept(:COMMA)
              end
            end
          end

          if accept(:NEWLINE, :SEMICOLON)
            rescue_clause.then_keyword_loc = previous_token.optional_location if accept(:KEYWORD_THEN)
          else
            expect(:KEYWORD_THEN, :rescue_term)
            rescue_clause.then_keyword_loc = previous_token.optional_location
          end

          unless match?(:KEYWORD_ELSE, :KEYWORD_ENSURE, :KEYWORD_END)
            accepts_block_stack_push(true)
            statements = parse_statements(rescue_context, depth + 1)
            rescue_node_statements_set(rescue_clause, statements) if statements

            accepts_block_stack_pop
            accept(:NEWLINE, :SEMICOLON)
          end

          if current.nil?
            begin_node_rescue_clause_set(parent_node, rescue_clause)
          else
            rescue_node_subsequent_set(current, rescue_clause)
          end

          current = rescue_clause
        end

        # Every rescue clause ends where the last one does.
        if current
          end_to_set = current.end_offset
          clause = parent_node.rescue_clause
          until clause.nil?
            clause.end_offset = end_to_set
            clause = clause.subsequent
          end
        end

        if @current_type == :KEYWORD_ELSE
          warn_indentation_mismatch(opening_newline_index, opening, false, false) if opening
          opening_newline_index = token_newline_index

          else_keyword = current_token
          opening = else_keyword

          lex
          accept(:NEWLINE, :SEMICOLON)

          else_statements = nil
          unless match?(:KEYWORD_END, :KEYWORD_ENSURE)
            accepts_block_stack_push(true)
            else_statements = parse_statements(else_context, depth + 1)
            accepts_block_stack_pop

            accept(:NEWLINE, :SEMICOLON)
          end

          else_clause = else_node(else_keyword, else_statements, current_token)
          begin_node_else_clause_set(parent_node, else_clause)

          # An else with no rescue clause is an error.
          err_node(else_clause, :begin_lonely_else) if current.nil?
        end

        if @current_type == :KEYWORD_ENSURE
          warn_indentation_mismatch(opening_newline_index, opening, false, false) if opening
          ensure_keyword = current_token

          lex
          accept(:NEWLINE, :SEMICOLON)

          ensure_statements = nil
          unless @current_type == :KEYWORD_END
            accepts_block_stack_push(true)
            ensure_statements = parse_statements(ensure_context, depth + 1)
            accepts_block_stack_pop

            accept(:NEWLINE, :SEMICOLON)
          end

          ensure_clause = ensure_node(ensure_keyword, ensure_statements, current_token)
          begin_node_ensure_clause_set(parent_node, ensure_clause)
        end

        if @current_type == :KEYWORD_END
          warn_indentation_mismatch(opening_newline_index, opening, false, false) if opening
          begin_node_end_keyword_set(parent_node, current_token)
        else
          begin_node_end_keyword_set(parent_node, Token.new(:MISSING, @previous_end, @previous_end))
        end
      end

      # parse_rescues_implicit_begin: rescue clauses on a body without
      # `begin` (a def, class, block, ...), from `start`.
      def parse_rescues_implicit_begin(opening_newline_index, opening, start, statements, type, depth)
        node = begin_node(NOT_PROVIDED, statements)

        parse_rescues(opening_newline_index, opening, node, type, depth + 1)
        node.start_offset = start

        node
      end

      # parse_block_parameters: a block's or lambda's parameters and its
      # block locals after `;`.
      def parse_block_parameters(allows_trailing_comma, opening, is_lambda_literal, accepts_blocks_in_defaults, depth)
        parameters = nil
        unless @current_type == :SEMICOLON
          context_push(:block_parameters) unless is_lambda_literal
          parameters = parse_parameters(is_lambda_literal ? BINDING_POWER_DEFINED : BINDING_POWER_INDEX,
                                        false, allows_trailing_comma, false, accepts_blocks_in_defaults, true, depth + 1)
          context_pop unless is_lambda_literal
        end

        block_parameters = block_parameters_node(parameters, opening)
        return block_parameters unless opening.provided?

        accept(:NEWLINE)
        return block_parameters unless accept(:SEMICOLON)

        loop do
          if (id = FORMAL_ARGUMENT_ERRORS[@current_type])
            err_current(id)
            lex
          else
            expect(:IDENTIFIER, :block_param_local_variable)
          end

          name = previous_token
          repeated = parameter_name_check(name)
          local_add_token(name, 1)

          local = block_local_variable_node(name)
          flag_repeated_parameter(local) if repeated

          block_parameters_node_append_local(block_parameters, local)
          break unless accept(:COMMA)
        end

        block_parameters
      end

      # outer_scope_using_numbered_parameters_p
      def outer_scope_using_numbered_parameters?
        scope = @current_scope.previous
        until scope.nil? || scope.closed?
          return true if scope.parameters.anybits?(Scope::NUMBERED_FOUND)

          scope = scope.previous
        end
        false
      end

      # parse_blocklike_parameters: a block's or lambda's parameters node,
      # its numbered parameters, or `it`.
      def parse_blocklike_parameters(parameters, opening, closing)
        implicit_parameters = @current_scope.implicit_parameters

        if parameters
          # Ordinary parameters with implicit ones are an error.
          case (node = implicit_parameters.first)
          when LocalVariableReadNode then err_node(node, :numbered_parameter_ordinary)
          when ItLocalVariableReadNode then err_node(node, :it_not_allowed_ordinary)
          end

          return parameters
        end

        return if implicit_parameters.empty?

        # Numbered parameters or `it`, but not both.
        numbered_parameter = 0
        it_parameter = false

        implicit_parameters.each do |node|
          case node
          when LocalVariableReadNode
            if it_parameter
              err_node(node, :numbered_parameter_it)
            elsif outer_scope_using_numbered_parameters?
              err_node(node, :numbered_parameter_outer_block)
            elsif @current_scope.parameters.anybits?(Scope::NUMBERED_INNER)
              err_node(node, :numbered_parameter_inner_block)
            elsif numbered_parameter?(node.start_offset, node.end_offset)
              numbered_parameter = [numbered_parameter, @source.getbyte(node.start_offset + 1) - 0x30].max
            end
          when ItLocalVariableReadNode
            if numbered_parameter > 0
              err_node(node, :it_not_allowed_numbered)
            else
              it_parameter = true
            end
          end
        end

        if numbered_parameter > 0
          # The scopes around may no longer use numbered parameters.
          scope = @current_scope.previous
          until scope.nil? || scope.closed?
            scope.parameters |= Scope::NUMBERED_INNER
            scope = scope.previous
          end

          return numbered_parameters_node(loc(opening.start, closing.end), numbered_parameter)
        end

        return it_parameters_node(opening, closing) if it_parameter

        nil
      end

      # parse_block: a `{ }` or `do end` block, after its opening token.
      def parse_block(depth)
        opening = previous_token
        accept(:NEWLINE)

        accepts_block_stack_push(true)
        scope_push(false)

        block_parameters = nil

        if accept(:PIPE)
          block_parameters_opening = previous_token
          if @current_type == :PIPE
            block_parameters = block_parameters_node(nil, block_parameters_opening)
            @command_start = true
            lex
          else
            block_parameters = parse_block_parameters(true, block_parameters_opening, false, true, depth + 1)
            accept(:NEWLINE)
            @command_start = true
            expect(:PIPE, :block_param_pipe_term)
          end

          block_parameters_node_closing_set(block_parameters, previous_token)
        end

        accept(:NEWLINE)
        statements = nil

        if opening.type == :BRACE_LEFT
          statements = parse_statements(:block_braces, depth + 1) unless @current_type == :BRACE_RIGHT

          expect_opening(:BRACE_RIGHT, :block_term_brace, opening)
        else
          unless @current_type == :KEYWORD_END
            unless match?(:KEYWORD_RESCUE, :KEYWORD_ELSE, :KEYWORD_ENSURE)
              accepts_block_stack_push(true)
              statements = parse_statements(:block_keywords, depth + 1)
              accepts_block_stack_pop
            end

            if match?(:KEYWORD_RESCUE, :KEYWORD_ENSURE)
              statements = parse_rescues_implicit_begin(0, nil, opening.start, statements, :block, depth + 1)
            end
          end

          expect_opening(:KEYWORD_END, :block_term_end, opening)
        end

        locals = locals_order(@current_scope.locals, scope_toplevel?)
        parameters = parse_blocklike_parameters(block_parameters, opening, previous_token)

        scope_pop
        accepts_block_stack_pop

        block_node(locals, opening, parameters, statements, previous_token)
      end

      # parse_arguments_list: a call's arguments, with or without
      # parentheses, and its block; whether any were found.
      def parse_arguments_list(arguments, accepts_block, accepts_command_call, depth)
        found = false

        if accept(:PARENTHESIS_LEFT)
          found = true
          arguments.opening_loc = previous_token.location

          if accept(:PARENTHESIS_RIGHT)
            arguments.closing_loc = previous_token.location
          else
            accepts_block_stack_push(true)
            parse_arguments(arguments, accepts_block, :PARENTHESIS_RIGHT, depth + 1)

            unless accept(:PARENTHESIS_RIGHT)
              err_current(:argument_term_paren, Tokens::HUMAN.fetch(@current_type))
              @previous_start = @previous_end
              @previous_type = :MISSING
            end

            accepts_block_stack_pop
            arguments.closing_loc = previous_token.location
          end
        elsif accepts_command_call && (token_begins_expression?(@current_type) || match?(:USTAR, :USTAR_STAR, :UAMPERSAND)) &&
              @current_type != :BRACE_LEFT
          found = true
          accepts_block_stack_push(false)

          # A command call's arguments.
          parse_arguments(arguments, accepts_block, :EOF, depth + 1)

          # A trailing comma, unless a semicolon follows.
          if @previous_type == :COMMA && @current_type != :SEMICOLON
            err_previous(:expect_argument, Tokens::HUMAN.fetch(@current_type))
          end

          accepts_block_stack_pop
        end

        if accepts_block
          block = nil

          if accept(:BRACE_LEFT)
            found = true
            block = parse_block(depth + 1)
            arguments_validate_block(arguments, block)
          elsif accepts_block_stack? && accept(:KEYWORD_DO)
            found = true
            block = parse_block(depth + 1)
          end

          if block
            if arguments.block.nil? && !arguments.has_forwarding
              arguments.block = block
            else
              err_node(block, :argument_block_multi)

              if arguments.block
                arguments.arguments ||= arguments_node
                arguments_node_arguments_append(arguments.arguments, arguments.block)
              end
              arguments.block = block
            end
          end
        end

        found
      end

      # The contexts a return sees through (:pass), may be in (:valid), may
      # not be in (:invalid), or that make it one in a singleton class body.
      RETURN_CONTEXTS = {
        begin_else: :pass, begin_ensure: :pass, begin_rescue: :pass, begin: :pass, case_in: :pass, case_when: :pass,
        default_params: :pass, defined: :pass, else: :pass, elsif: :pass, embexpr: :pass, for_index: :pass, for: :pass,
        if: :pass, loop_predicate: :pass, main: :pass, multi_target: :pass, parens: :pass, postexe: :pass,
        predicate: :pass, preexe: :pass, rescue_modifier: :pass, ternary: :pass, unless: :pass, until: :pass, while: :pass,
        sclass_else: :sclass, sclass_ensure: :sclass, sclass_rescue: :sclass, sclass: :sclass,
        class_else: :invalid, class_ensure: :invalid, class_rescue: :invalid, class: :invalid,
        module_else: :invalid, module_ensure: :invalid, module_rescue: :invalid, module: :invalid,
        block_braces: :valid, block_else: :valid, block_ensure: :valid, block_keywords: :valid, block_rescue: :valid,
        block_parameters: :valid, def_else: :valid, def_ensure: :valid, def_params: :valid, def_rescue: :valid,
        def: :valid, lambda_braces: :valid, lambda_do_end: :valid, lambda_else: :valid, lambda_ensure: :valid,
        lambda_rescue: :valid
      }

      # parse_return: an error for a return in a class or module body, or
      # from 3.4 in a singleton class body.
      def parse_return(node)
        in_sclass = false
        @contexts.reverse_each do |context|
          case RETURN_CONTEXTS.fetch(context)
          when :sclass then in_sclass = true
          when :invalid
            err_node(node, :return_invalid)
            return
          when :valid then return
          end
        end
        err_node(node, :return_invalid) if in_sclass && @version >= Options::VERSION_CRUBY_3_4
      end

      # The contexts a block exit may be in (:valid), may not be in unless a
      # while or until modifier follows (:invalid), or sees through.
      BLOCK_EXIT_CONTEXTS = {
        block_braces: :valid, block_keywords: :valid, block_else: :valid, block_ensure: :valid,
        block_parameters: :valid, block_rescue: :valid, defined: :valid, for: :valid, lambda_braces: :valid,
        lambda_do_end: :valid, lambda_else: :valid, lambda_ensure: :valid, lambda_rescue: :valid,
        loop_predicate: :valid, postexe: :valid, until: :valid, while: :valid,
        def: :invalid, def_params: :invalid, def_else: :invalid, def_ensure: :invalid, def_rescue: :invalid,
        main: :invalid, preexe: :invalid, sclass: :invalid, sclass_else: :invalid, sclass_ensure: :invalid,
        sclass_rescue: :invalid
      }

      # parse_block_exit: a break, next or redo outside a block may still be
      # valid inside a while or until modifier, so it waits in the block
      # exits.
      def parse_block_exit(node)
        @contexts.reverse_each do |context|
          case BLOCK_EXIT_CONTEXTS[context]
          when :valid then return
          when :invalid
            @current_block_exits << node
            return
          end
        end
      end

      # push_block_exits: a new list of block exits; answers the one before.
      def push_block_exits(current_block_exits)
        previous_block_exits = @current_block_exits
        @current_block_exits = current_block_exits
        previous_block_exits
      end

      # flush_block_exits: an error for each block exit left.
      def flush_block_exits(previous_block_exits)
        @current_block_exits.each do |block_exit|
          type = case block_exit
                 when BreakNode then "break"
                 when NextNode then "next"
                 when RedoNode then "redo"
                 end
          err_node(block_exit, :invalid_block_exit, type)
        end

        @current_block_exits = previous_block_exits
      end

      # pop_block_exits: a while or until modifier makes the block exits
      # valid; otherwise they move to the list around, or are errors at the
      # top.
      def pop_block_exits(previous_block_exits)
        if match?(:KEYWORD_WHILE_MODIFIER, :KEYWORD_UNTIL_MODIFIER)
          @current_block_exits = previous_block_exits
        elsif previous_block_exits
          previous_block_exits.concat(@current_block_exits)
          @current_block_exits = previous_block_exits
        else
          flush_block_exits(previous_block_exits)
        end
      end

      # parse_predicate: an if's or unless's predicate and what closes it;
      # answers the predicate and the `then` keyword (or NOT_PROVIDED).
      def parse_predicate(binding_power, context, then_keyword, depth)
        context_push(:predicate)
        error_id = context == :if ? :conditional_if_predicate : :conditional_unless_predicate
        predicate = parse_value_expression(binding_power, true, false, error_id, depth + 1)

        predicate_closed = accept(:NEWLINE, :SEMICOLON)

        if accept(:KEYWORD_THEN)
          predicate_closed = true
          then_keyword = previous_token
        end

        err_current(:conditional_predicate_term) unless predicate_closed

        context_pop
        [predicate, then_keyword]
      end

      # parse_conditional: an if (with its elsif and else clauses) or an
      # unless, after its keyword.
      def parse_conditional(context, opening_newline_index, if_after_else, depth)
        previous_block_exits = push_block_exits([])

        keyword = previous_token
        then_keyword = NOT_PROVIDED

        predicate, then_keyword = parse_predicate(BINDING_POWER_MODIFIER, context, then_keyword, depth + 1)
        statements = nil

        unless match?(:KEYWORD_ELSIF, :KEYWORD_ELSE, :KEYWORD_END)
          accepts_block_stack_push(true)
          statements = parse_statements(context, depth + 1)
          accepts_block_stack_pop
          accept(:NEWLINE, :SEMICOLON)
        end

        end_keyword = NOT_PROVIDED
        parent =
          if context == :if
            if_node(keyword, predicate, then_keyword, statements, nil, end_keyword)
          else
            unless_node(keyword, predicate, then_keyword, statements)
          end

        current = parent

        if context == :if
          while @current_type == :KEYWORD_ELSIF
            warn_token_content(current_token, :keyword_eol) if end_of_line?

            warn_indentation_mismatch(opening_newline_index, keyword, false, false)
            elsif_keyword = current_token
            lex

            elsif_predicate, then_keyword = parse_predicate(BINDING_POWER_MODIFIER, :elsif, then_keyword, depth + 1)
            accepts_block_stack_push(true)

            elsif_statements = parse_statements(:elsif, depth + 1)
            accepts_block_stack_pop
            accept(:NEWLINE, :SEMICOLON)

            elsif_node = if_node(elsif_keyword, elsif_predicate, then_keyword, elsif_statements, nil, end_keyword)
            current.subsequent = elsif_node
            current = elsif_node
          end
        end

        if @current_type == :KEYWORD_ELSE
          warn_indentation_mismatch(opening_newline_index, keyword, false, false)
          opening_newline_index = token_newline_index

          lex
          else_keyword = previous_token

          accepts_block_stack_push(true)
          else_statements = parse_statements(:else, depth + 1)
          accepts_block_stack_pop

          accept(:NEWLINE, :SEMICOLON)
          warn_indentation_mismatch(opening_newline_index, else_keyword, false, false)
          expect_opening(:KEYWORD_END, :conditional_term_else, keyword)

          else_clause = else_node(else_keyword, else_statements, previous_token)

          if context == :if
            current.subsequent = else_clause
          else
            parent.else_clause = else_clause
          end
        else
          warn_indentation_mismatch(opening_newline_index, keyword, if_after_else, false)
          expect_opening(:KEYWORD_END, :conditional_term, keyword)
        end

        # Every node in the chain ends at the end keyword.
        if context == :if
          node = parent
          loop do
            case node
            when IfNode
              end_keyword_loc_set(node, previous_token)
              node = node.subsequent
              break if node.nil?
            when ElseNode
              end_keyword_loc_set(node, previous_token)
              break
            else
              break
            end
          end
        else
          end_keyword_loc_set(parent, previous_token)
        end

        pop_block_exits(previous_block_exits)

        parent
      end
    end
  end
end
