# frozen_string_literal: true
# shareable_constant_value: literal

using Prism::Ruby::Mutation

module Prism
  module Ruby
    class Parser
      # PM_PARSE_PATTERN_SINGLE, _TOP and _MULTI
      PARSE_PATTERN_SINGLE = 0
      PARSE_PATTERN_TOP = 1
      PARSE_PATTERN_MULTI = 2

      # The tokens a pattern primitive may start with.
      PATTERN_PRIMITIVE_STARTS = (%i[IDENTIFIER BRACKET_LEFT_ARRAY BRACE_LEFT CARET CONSTANT UCOLON_COLON UDOT_DOT UDOT_DOT_DOT] +
                                  CASE_PRIMITIVE).freeze

      private

      # parse_pattern_capture: a local a pattern binds, which may not repeat
      # unless it starts with `_`.
      def parse_pattern_capture(captures, capture, location)
        return if peek_at(loc_start(location)) == 0x5F

        if captures.include?(capture)
          err(loc_start(location), loc_end(location), :pattern_capture_duplicate)
        else
          captures << capture
        end
      end

      # A local variable a pattern binds, added to the scope when new: its
      # target node.
      def parse_pattern_local_target(captures, token)
        constant_id = constant_id_location(token.start, token.end)

        depth = local_depth_constant_id(constant_id)
        local_add(constant_id, token.start, token.end, 0) if depth == -1

        parse_pattern_capture(captures, constant_id, token.location)
        local_variable_target_node(token.location, constant_symbol(constant_id), depth == -1 ? 0 : depth)
      end

      # parse_pattern_constant_path: `A::B`, and `A::B[...]` or `A::B(...)`
      # around an inner pattern.
      def parse_pattern_constant_path(captures, node, depth)
        while accept(:COLON_COLON)
          delimiter = previous_token
          expect(:CONSTANT, :constant_path_colon_colon_constant)
          node = constant_path_node(node, delimiter, previous_token)
        end

        return node unless match?(:BRACKET_LEFT, :PARENTHESIS_LEFT)

        inner = nil

        if accept(:BRACKET_LEFT)
          opening = previous_token
          accept(:NEWLINE)

          unless accept(:BRACKET_RIGHT)
            inner = parse_pattern(captures, PARSE_PATTERN_TOP | PARSE_PATTERN_MULTI, :pattern_expression_after_bracket, depth + 1)
            accept(:NEWLINE)
            expect_opening(:BRACKET_RIGHT, :pattern_term_bracket, opening)
          end
        else
          lex
          opening = previous_token
          accept(:NEWLINE)

          unless accept(:PARENTHESIS_RIGHT)
            inner = parse_pattern(captures, PARSE_PATTERN_TOP | PARSE_PATTERN_MULTI, :pattern_expression_after_paren, depth + 1)
            accept(:NEWLINE)
            expect_opening(:PARENTHESIS_RIGHT, :pattern_term_paren, opening)
          end
        end
        closing = previous_token

        # Foo() and Foo[]
        return array_pattern_node_constant(node, opening, closing) if inner.nil?

        # The constant joins an array, find or hash pattern that has none.
        if (inner.is_a?(ArrayPatternNode) || inner.is_a?(FindPatternNode) || inner.is_a?(HashPatternNode)) &&
           inner.constant.nil? && inner.opening_loc.nil?
          inner.location = loc(node.start_offset, closing.end)
          inner.constant = node
          inner.opening_loc = opening.location
          inner.closing_loc = closing.location
          return inner
        end

        pattern_node = array_pattern_node_constant(node, opening, closing)
        pattern_node.requireds << inner
        pattern_node
      end

      # parse_pattern_rest: `*` or `*name` after the star.
      def parse_pattern_rest(captures)
        operator = previous_token
        name = accept(:IDENTIFIER) ? parse_pattern_local_target(captures, previous_token) : nil
        splat_node(operator, name)
      end

      # parse_pattern_keyword_rest: `**nil`, `**` or `**name`.
      def parse_pattern_keyword_rest(captures)
        lex

        operator = previous_token
        return no_keywords_parameter_node(operator, previous_token) if accept(:KEYWORD_NIL)

        value = accept(:IDENTIFIER) ? parse_pattern_local_target(captures, previous_token) : nil
        assoc_splat_node(value, operator)
      end

      # pm_slice_is_valid_local
      def slice_valid_local?(start, finish)
        return false if finish == start

        width = identifier_start_width(start)
        return false if width == 0

        upper = @encoding_changed ? @encoding.isupper_char(@source, start, finish - start) : Encodings::UTF_8.isupper_char(@source, start, finish - start)
        return false if upper

        cursor = start + width
        cursor += width while (width = identifier_width(cursor)) != 0
        cursor == finish
      end

      # parse_pattern_hash_implicit_value: `{ name: }` binds `name`.
      def parse_pattern_hash_implicit_value(captures, key)
        value_loc = key.value_loc
        value_start = loc_start(value_loc)
        value_end = loc_end(value_loc)

        constant_id = constant_id_location(value_start, value_end)
        depth = -1

        if slice_valid_local?(value_start, value_end)
          depth = local_depth_constant_id(constant_id)
        else
          err(key.start_offset, key.end_offset, :pattern_hash_key_locals)

          last = @source.getbyte(value_end - 1)
          if value_end > value_start && (last == 0x21 || last == 0x3F)
            err(value_start, value_end, :invalid_local_variable_write, @source.byteslice(value_start, value_end - value_start))
          end
        end

        local_add(constant_id, value_start, value_end, 0) if depth == -1

        parse_pattern_capture(captures, constant_id, value_loc)
        target = local_variable_target_node(value_loc, constant_symbol(constant_id), depth == -1 ? 0 : depth)

        implicit_node(target)
      end

      # parse_pattern_hash_key: an error for a repeated key.
      def parse_pattern_hash_key(keys, node)
        err_node(node, :pattern_hash_key_duplicate) if keys.add(node, true)
      end

      # The tokens after a hash pattern key that leave its value out.
      PATTERN_HASH_VALUE_ENDS = %i[COMMA KEYWORD_THEN BRACE_RIGHT BRACKET_RIGHT PARENTHESIS_RIGHT NEWLINE SEMICOLON]

      # parse_pattern_hash: a hash pattern from its first key or rest.
      def parse_pattern_hash(captures, first_node, depth)
        assocs = []
        keys = StaticLiterals.new(self)
        rest = nil

        if first_node.is_a?(AssocSplatNode) || first_node.is_a?(NoKeywordsParameterNode)
          rest = first_node
        elsif first_node.is_a?(SymbolNode) && symbol_node_label?(first_node)
          parse_pattern_hash_key(keys, first_node)

          value =
            if match?(*PATTERN_HASH_VALUE_ENDS, :EOF)
              parse_pattern_hash_implicit_value(captures, first_node)
            else
              parse_pattern(captures, PARSE_PATTERN_SINGLE, :pattern_expression_after_key, depth + 1)
            end

          assocs << assoc_node(first_node, NOT_PROVIDED, value)
        else
          id = first_node.is_a?(InterpolatedSymbolNode) ? :pattern_hash_key_interpolated : :pattern_hash_key_label
          err_node(first_node, id)

          value = missing_node(first_node.start_offset, first_node.end_offset)
          assocs << assoc_node(first_node, NOT_PROVIDED, value)
        end

        while accept(:COMMA)
          # A trailing comma, but not after a rest.
          if match?(:KEYWORD_THEN, :BRACE_RIGHT, :BRACKET_RIGHT, :PARENTHESIS_RIGHT, :NEWLINE, :SEMICOLON, :EOF)
            err_token(current_token, :pattern_expression_after_rest) if rest
            break
          end

          if @current_type == :USTAR_STAR
            assoc = parse_pattern_keyword_rest(captures)

            if rest.nil?
              rest = assoc
            else
              err_node(assoc, :pattern_expression_after_rest)
              assocs << assoc
            end
          else
            if @current_type == :STRING_BEGIN
              key = parse_strings(nil, true, depth + 1)

              if key.is_a?(InterpolatedSymbolNode)
                err_node(key, :pattern_hash_key_interpolated)
              elsif !symbol_node_label?(key)
                err_node(key, :pattern_label_after_comma)
              end
            else
              expect(:LABEL, :pattern_label_after_comma)
              key = symbol_node_label(previous_token)
            end

            parse_pattern_hash_key(keys, key)

            value =
              if match?(*PATTERN_HASH_VALUE_ENDS)
                if key.is_a?(SymbolNode)
                  parse_pattern_hash_implicit_value(captures, key)
                else
                  missing_node(key.end_offset, key.end_offset)
                end
              else
                parse_pattern(captures, PARSE_PATTERN_SINGLE, :pattern_expression_after_key, depth + 1)
              end

            assoc = assoc_node(key, NOT_PROVIDED, value)
            err_node(assoc, :pattern_expression_after_rest) if rest
            assocs << assoc
          end
        end

        hash_pattern_node_node_list(assocs, rest)
      end

      # An array or find pattern takes the brackets around it, unless it has
      # its own already.
      def parse_pattern_bracketed(inner, opening, closing)
        if (inner.is_a?(ArrayPatternNode) || inner.is_a?(FindPatternNode)) && inner.opening_loc.nil?
          inner.location = loc(opening.start, closing.end)
          inner.opening_loc = opening.location
          inner.closing_loc = closing.location
          return inner
        end

        node = array_pattern_node_empty(opening, closing)
        node.requireds << inner
        node
      end

      # parse_pattern_primitive
      def parse_pattern_primitive(captures, id, depth)
        case @current_type
        when :IDENTIFIER, :METHOD_NAME
          lex
          parse_pattern_local_target(captures, previous_token)
        when :BRACKET_LEFT_ARRAY
          opening = current_token
          lex

          return array_pattern_node_empty(opening, previous_token) if accept(:BRACKET_RIGHT)

          inner = parse_pattern(captures, PARSE_PATTERN_MULTI, :pattern_expression_after_bracket, depth + 1)

          accept(:NEWLINE)
          expect_opening(:BRACKET_RIGHT, :pattern_term_bracket, opening)
          parse_pattern_bracketed(inner, opening, previous_token)
        when :BRACE_LEFT
          previous_pattern_matching_newlines = @pattern_matching_newlines
          @pattern_matching_newlines = false

          opening = current_token
          lex

          if accept(:BRACE_RIGHT)
            node = hash_pattern_node_empty(opening, previous_token)
          else
            first_node =
              case @current_type
              when :LABEL
                lex
                symbol_node_label(previous_token)
              when :USTAR_STAR
                parse_pattern_keyword_rest(captures)
              when :STRING_BEGIN
                parse_expression(BINDING_POWER_MAX, false, true, :pattern_hash_key_label, depth + 1)
              else
                err_current(:pattern_hash_key, Tokens::HUMAN.fetch(@current_type))
                lex
                missing_node(@previous_start, @previous_end)
              end

            node = parse_pattern_hash(captures, first_node, depth + 1)

            accept(:NEWLINE)
            expect_opening(:BRACE_RIGHT, :pattern_term_brace, opening)
            closing = previous_token

            node.location = loc(opening.start, closing.end)
            node.opening_loc = opening.location
            node.closing_loc = closing.location
          end

          @pattern_matching_newlines = previous_pattern_matching_newlines
          node
        when :UDOT_DOT, :UDOT_DOT_DOT
          operator = current_token
          lex

          if CASE_PRIMITIVE.include?(@current_type)
            right = parse_expression(BINDING_POWER_MAX, false, false, :pattern_expression_after_range, depth + 1)
          else
            err_token(operator, :pattern_expression_after_range)
            right = missing_node(operator.start, operator.end)
          end
          range_node(nil, operator, right)
        when *CASE_PRIMITIVE
          node = parse_expression(BINDING_POWER_MAX, false, true, id, depth + 1)

          # A label goes back to the caller.
          return node if symbol_node_label?(node)

          # No arithmetic in a pattern.
          if node.is_a?(CallNode)
            err_node(node, id)
            missing = missing_node(node.start_offset, node.end_offset)
            node_unreference(node)
            return missing
          end

          if accept(:DOT_DOT, :DOT_DOT_DOT)
            operator = previous_token

            if CASE_PRIMITIVE.include?(@current_type)
              right = parse_expression(BINDING_POWER_MAX, false, false, :pattern_expression_after_range, depth + 1)
              return range_node(node, operator, right)
            end

            return range_node(node, operator, nil)
          end

          node
        when :CARET
          lex
          operator = previous_token

          variable =
            case @current_type
            when :IDENTIFIER
              lex
              parse_variable || begin
                err_token_content(previous_token, :no_local_variable)
                local_variable_read_node_missing(previous_token, 0)
              end
            when :INSTANCE_VARIABLE
              lex
              instance_variable_read_node(previous_token)
            when :CLASS_VARIABLE
              lex
              class_variable_read_node(previous_token)
            when :GLOBAL_VARIABLE
              lex
              global_variable_read_node(previous_token)
            when :NUMBERED_REFERENCE
              lex
              numbered_reference_read_node(previous_token)
            when :BACK_REFERENCE
              lex
              back_reference_read_node(previous_token)
            when :PARENTHESIS_LEFT
              previous_pattern_matching_newlines = @pattern_matching_newlines
              @pattern_matching_newlines = false

              lparen = current_token
              lex

              expression = parse_value_expression(BINDING_POWER_STATEMENT, true, false, :pattern_expression_after_pin, depth + 1)
              @pattern_matching_newlines = previous_pattern_matching_newlines

              accept(:NEWLINE)
              expect_opening(:PARENTHESIS_RIGHT, :pattern_term_paren, lparen)
              return pinned_expression_node(expression, operator, lparen, previous_token)
            else
              err_token(operator, :pattern_expression_after_pin)
              missing_node(operator.start, operator.end)
            end

          pinned_variable_node(operator, variable)
        when :UCOLON_COLON
          delimiter = current_token
          lex

          expect(:CONSTANT, :constant_path_colon_colon_constant)
          node = constant_path_node(nil, delimiter, previous_token)

          parse_pattern_constant_path(captures, node, depth + 1)
        when :CONSTANT
          constant = current_token
          lex

          parse_pattern_constant_path(captures, constant_read_node(constant), depth + 1)
        else
          err_current(id)
          missing_node(@current_start, @current_end)
        end
      end

      # parse_pattern_alternation_error: a capture in an alternative is an
      # error.
      def parse_pattern_alternation_error(node)
        if node.is_a?(LocalVariableTargetNode)
          err(node.start_offset, node.end_offset, :pattern_capture_in_alternative)
        else
          node.compact_child_nodes.each { |child| parse_pattern_alternation_error(child) }
        end
      end

      # parse_pattern_primitives: primitives joined by `|`, then `=> name`
      # captures.
      def parse_pattern_primitives(captures, first_node, id, depth)
        node = first_node
        alternation = false

        while node.nil? || (alternation = accept(:PIPE))
          parse_pattern_alternation_error(node) if alternation && !node.is_a?(AlternationPatternNode) && !captures.empty?

          case @current_type
          when *PATTERN_PRIMITIVE_STARTS
            if alternation
              operator = previous_token
              right = parse_pattern_primitive(captures, :pattern_expression_after_pipe, depth + 1)

              parse_pattern_alternation_error(right) unless captures.empty?
              node = alternation_pattern_node(node, right, operator)
            else
              node = parse_pattern_primitive(captures, id, depth + 1)
            end
          when :PARENTHESIS_LEFT, :PARENTHESIS_LEFT_PARENTHESES
            operator = previous_token
            opening = current_token
            lex

            body = parse_pattern(captures, PARSE_PATTERN_SINGLE, :pattern_expression_after_paren, depth + 1)
            accept(:NEWLINE)
            expect_opening(:PARENTHESIS_RIGHT, :pattern_term_paren, opening)
            right = parentheses_node(opening, body, previous_token, 0)

            if alternation
              parse_pattern_alternation_error(right) unless captures.empty?
              node = alternation_pattern_node(node, right, operator)
            else
              node = right
            end
          else
            err_current(id)
            right = missing_node(@current_start, @current_end)

            if alternation
              parse_pattern_alternation_error(right) unless captures.empty?
              node = alternation_pattern_node(node, right, previous_token)
            else
              node = right
            end
          end
        end

        # `pattern => name` binds the value.
        while accept(:EQUAL_GREATER)
          operator = previous_token
          expect(:IDENTIFIER, :pattern_ident_after_hrocket)

          target = parse_pattern_local_target(captures, previous_token)
          node = capture_pattern_node(node, target, operator)
        end

        node
      end

      # parse_pattern: a pattern, which with PARSE_PATTERN_TOP may be a hash
      # pattern without braces and with PARSE_PATTERN_MULTI an array or find
      # pattern without brackets.
      def parse_pattern(captures, flags, id, depth)
        leading_rest = false
        trailing_rest = false

        case @current_type
        when :LABEL
          lex
          key = symbol_node_label(previous_token)
          node = parse_pattern_hash(captures, key, depth + 1)

          err_node(node, :pattern_hash_implicit) unless flags.anybits?(PARSE_PATTERN_TOP)
          return node
        when :USTAR_STAR
          node = parse_pattern_keyword_rest(captures)
          node = parse_pattern_hash(captures, node, depth + 1)

          err_node(node, :pattern_hash_implicit) unless flags.anybits?(PARSE_PATTERN_TOP)
          return node
        when :STRING_BEGIN
          # A dynamic symbol may be a hash pattern's first key.
          node = parse_pattern_primitive(captures, id, depth + 1)

          if symbol_node_label?(node)
            node = parse_pattern_hash(captures, node, depth + 1)

            err_node(node, :pattern_hash_implicit) unless flags.anybits?(PARSE_PATTERN_TOP)
            return node
          end

          node = parse_pattern_primitives(captures, node, id, depth + 1)
        when :USTAR
          if flags.anybits?(PARSE_PATTERN_TOP | PARSE_PATTERN_MULTI)
            lex
            node = parse_pattern_rest(captures)
            leading_rest = true
          else
            node = parse_pattern_primitives(captures, nil, id, depth + 1)
          end
        else
          node = parse_pattern_primitives(captures, nil, id, depth + 1)
        end

        return parse_pattern_hash(captures, node, depth + 1) if symbol_node_label?(node)

        if flags.anybits?(PARSE_PATTERN_MULTI) && @current_type == :COMMA
          nodes = [node]

          while accept(:COMMA)
            # A trailing comma is an implicit rest.
            if match?(:KEYWORD_THEN, :BRACE_RIGHT, :BRACKET_RIGHT, :PARENTHESIS_RIGHT, :SEMICOLON, :KEYWORD_AND, :KEYWORD_OR)
              nodes << implicit_rest_node(previous_token)
              trailing_rest = true
              break
            end

            if accept(:USTAR)
              node = parse_pattern_rest(captures)

              # Only one rest after the first.
              err_previous(:pattern_rest) if trailing_rest

              trailing_rest = true
            else
              node = parse_pattern_primitives(captures, nil, :pattern_expression_after_comma, depth + 1)
            end

            nodes << node
          end

          # Rests first and last make a find pattern.
          if leading_rest && nodes.last.is_a?(SplatNode)
            node = find_pattern_node(nodes)
            err_node(node, :pattern_find_missing_inner) if nodes.size == 2
          else
            node = array_pattern_node_node_list(nodes)
            err_node(node, :pattern_array_multiple_rests) if leading_rest && trailing_rest
          end
        elsif leading_rest
          node = array_pattern_node_rest(node)
        end

        node
      end

      # parse_negative_numeric: a `-` before a number joins it.
      def parse_negative_numeric(node)
        node.start_offset -= 1

        case node
        when IntegerNode
          node.value.zero? ? @negative_zeros << node.node_id : node.value = -node.value
        when FloatNode
          node.value = -node.value
        when RationalNode
          node.numerator.zero? ? @negative_zeros << node.node_id : node.numerator = -node.numerator
        when ImaginaryNode
          parse_negative_numeric(node.numeric)
        end
      end
    end
  end
end
