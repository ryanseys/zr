# frozen_string_literal: true
# shareable_constant_value: literal

using Prism::Ruby::Mutation

module Prism
  module Ruby
    class Parser
      # The PM_PARSE_* flags that steer how an expression parses.
      ACCEPTS_COMMAND_CALL = 0x1
      ACCEPTS_LABEL = 0x2
      ACCEPTS_DO_BLOCK = 0x4
      IN_ENDLESS_DEF = 0x8
      # The value of a `rescue` modifier, which CRuby parses as a statement
      # in statement, multiple-assignment and command-call contexts.
      ACCEPTS_STATEMENT = 0x10

      # pm_binding_power_t
      BINDING_POWER_UNSET = 0
      BINDING_POWER_STATEMENT = 2
      BINDING_POWER_MODIFIER_RESCUE = 4
      BINDING_POWER_MODIFIER = 6
      BINDING_POWER_COMPOSITION = 8
      BINDING_POWER_NOT = 10
      BINDING_POWER_MATCH = 12
      BINDING_POWER_DEFINED = 14
      BINDING_POWER_MULTI_ASSIGNMENT = 16
      BINDING_POWER_ASSIGNMENT = 18
      BINDING_POWER_TERNARY = 20
      BINDING_POWER_RANGE = 22
      BINDING_POWER_LOGICAL_OR = 24
      BINDING_POWER_LOGICAL_AND = 26
      BINDING_POWER_EQUALITY = 28
      BINDING_POWER_COMPARISON = 30
      BINDING_POWER_BITWISE_OR = 32
      BINDING_POWER_BITWISE_AND = 34
      BINDING_POWER_SHIFT = 36
      BINDING_POWER_TERM = 38
      BINDING_POWER_FACTOR = 40
      BINDING_POWER_UMINUS = 42
      BINDING_POWER_EXPONENT = 44
      BINDING_POWER_UNARY = 46
      BINDING_POWER_INDEX = 48
      BINDING_POWER_CALL = 50
      BINDING_POWER_MAX = 52

      # pm_binding_powers_t: the powers a token binds with, whether it is a
      # binary operator, and whether it is non-associative.
      BindingPowers = Data.define(:left, :right, :binary, :nonassoc)

      binding_powers = lambda do
        assignment = BindingPowers.new(BINDING_POWER_UNARY, BINDING_POWER_ASSIGNMENT, true, false)
        left = ->(power) { BindingPowers.new(power, power + 1, true, false) }
        right = ->(power) { BindingPowers.new(power, power, true, false) }
        non = ->(power) { BindingPowers.new(power, power + 1, true, true) }
        unary = ->(power) { BindingPowers.new(power, power, false, false) }

        {
          KEYWORD_RESCUE_MODIFIER: BindingPowers.new(BINDING_POWER_MODIFIER_RESCUE, BINDING_POWER_COMPOSITION, true, false),
          KEYWORD_IF_MODIFIER: left.(BINDING_POWER_MODIFIER),
          KEYWORD_UNLESS_MODIFIER: left.(BINDING_POWER_MODIFIER),
          KEYWORD_UNTIL_MODIFIER: left.(BINDING_POWER_MODIFIER),
          KEYWORD_WHILE_MODIFIER: left.(BINDING_POWER_MODIFIER),
          KEYWORD_AND: left.(BINDING_POWER_COMPOSITION),
          KEYWORD_OR: left.(BINDING_POWER_COMPOSITION),
          EQUAL_GREATER: non.(BINDING_POWER_MATCH),
          KEYWORD_IN: non.(BINDING_POWER_MATCH),
          AMPERSAND_AMPERSAND_EQUAL: assignment,
          AMPERSAND_EQUAL: assignment,
          CARET_EQUAL: assignment,
          EQUAL: assignment,
          GREATER_GREATER_EQUAL: assignment,
          LESS_LESS_EQUAL: assignment,
          MINUS_EQUAL: assignment,
          PERCENT_EQUAL: assignment,
          PIPE_EQUAL: assignment,
          PIPE_PIPE_EQUAL: assignment,
          PLUS_EQUAL: assignment,
          SLASH_EQUAL: assignment,
          STAR_EQUAL: assignment,
          STAR_STAR_EQUAL: assignment,
          QUESTION_MARK: right.(BINDING_POWER_TERNARY),
          DOT_DOT: non.(BINDING_POWER_RANGE),
          DOT_DOT_DOT: non.(BINDING_POWER_RANGE),
          UDOT_DOT: unary.(BINDING_POWER_LOGICAL_OR),
          UDOT_DOT_DOT: unary.(BINDING_POWER_LOGICAL_OR),
          PIPE_PIPE: left.(BINDING_POWER_LOGICAL_OR),
          AMPERSAND_AMPERSAND: left.(BINDING_POWER_LOGICAL_AND),
          BANG_EQUAL: non.(BINDING_POWER_EQUALITY),
          BANG_TILDE: non.(BINDING_POWER_EQUALITY),
          EQUAL_EQUAL: non.(BINDING_POWER_EQUALITY),
          EQUAL_EQUAL_EQUAL: non.(BINDING_POWER_EQUALITY),
          EQUAL_TILDE: non.(BINDING_POWER_EQUALITY),
          LESS_EQUAL_GREATER: non.(BINDING_POWER_EQUALITY),
          GREATER: left.(BINDING_POWER_COMPARISON),
          GREATER_EQUAL: left.(BINDING_POWER_COMPARISON),
          LESS: left.(BINDING_POWER_COMPARISON),
          LESS_EQUAL: left.(BINDING_POWER_COMPARISON),
          CARET: left.(BINDING_POWER_BITWISE_OR),
          PIPE: left.(BINDING_POWER_BITWISE_OR),
          AMPERSAND: left.(BINDING_POWER_BITWISE_AND),
          GREATER_GREATER: left.(BINDING_POWER_SHIFT),
          LESS_LESS: left.(BINDING_POWER_SHIFT),
          MINUS: left.(BINDING_POWER_TERM),
          PLUS: left.(BINDING_POWER_TERM),
          PERCENT: left.(BINDING_POWER_FACTOR),
          SLASH: left.(BINDING_POWER_FACTOR),
          STAR: left.(BINDING_POWER_FACTOR),
          USTAR: unary.(BINDING_POWER_FACTOR),
          UMINUS: unary.(BINDING_POWER_UMINUS),
          UMINUS_NUM: BindingPowers.new(BINDING_POWER_UMINUS, BINDING_POWER_MAX, false, false),
          STAR_STAR: right.(BINDING_POWER_EXPONENT),
          USTAR_STAR: unary.(BINDING_POWER_UNARY),
          BANG: unary.(BINDING_POWER_UNARY),
          TILDE: unary.(BINDING_POWER_UNARY),
          UPLUS: unary.(BINDING_POWER_UNARY),
          BRACKET_LEFT: left.(BINDING_POWER_INDEX),
          COLON_COLON: right.(BINDING_POWER_CALL),
          DOT: right.(BINDING_POWER_CALL),
          AMPERSAND_DOT: right.(BINDING_POWER_CALL)
        }
      end

      # pm_binding_powers, unset for any other token.
      BINDING_POWERS = Hash.new(BindingPowers.new(BINDING_POWER_UNSET, BINDING_POWER_UNSET, false, false))
                           .merge!(binding_powers.call).freeze

      # context_terminators: the tokens that end each context.
      CONTEXT_TERMINATORS = {
        none: [],
        begin: %i[KEYWORD_ENSURE KEYWORD_RESCUE KEYWORD_ELSE KEYWORD_END],
        begin_ensure: %i[KEYWORD_END],
        begin_else: %i[KEYWORD_ENSURE KEYWORD_END],
        begin_rescue: %i[KEYWORD_ENSURE KEYWORD_RESCUE KEYWORD_ELSE KEYWORD_END],
        block_braces: %i[BRACE_RIGHT],
        block_keywords: %i[KEYWORD_END KEYWORD_RESCUE KEYWORD_ENSURE],
        block_ensure: %i[KEYWORD_END],
        block_else: %i[KEYWORD_ENSURE KEYWORD_END],
        block_parameters: %i[PIPE],
        block_rescue: %i[KEYWORD_ENSURE KEYWORD_RESCUE KEYWORD_ELSE KEYWORD_END],
        case_when: %i[KEYWORD_WHEN KEYWORD_END KEYWORD_ELSE],
        case_in: %i[KEYWORD_IN KEYWORD_END KEYWORD_ELSE],
        class: %i[KEYWORD_END KEYWORD_RESCUE KEYWORD_ENSURE],
        class_ensure: %i[KEYWORD_END],
        class_else: %i[KEYWORD_ENSURE KEYWORD_END],
        class_rescue: %i[KEYWORD_ENSURE KEYWORD_RESCUE KEYWORD_ELSE KEYWORD_END],
        def: %i[KEYWORD_END KEYWORD_RESCUE KEYWORD_ENSURE],
        def_ensure: %i[KEYWORD_END],
        def_else: %i[KEYWORD_ENSURE KEYWORD_END],
        def_rescue: %i[KEYWORD_ENSURE KEYWORD_RESCUE KEYWORD_ELSE KEYWORD_END],
        def_params: %i[EOF],
        defined: %i[EOF],
        default_params: %i[COMMA PARENTHESIS_RIGHT],
        else: %i[KEYWORD_END],
        elsif: %i[KEYWORD_ELSE KEYWORD_ELSIF KEYWORD_END],
        embexpr: %i[EMBEXPR_END],
        for: %i[KEYWORD_END],
        for_index: %i[KEYWORD_IN],
        if: %i[KEYWORD_ELSE KEYWORD_ELSIF KEYWORD_END],
        lambda_braces: %i[BRACE_RIGHT],
        lambda_do_end: %i[KEYWORD_END KEYWORD_RESCUE KEYWORD_ENSURE],
        lambda_ensure: %i[KEYWORD_END],
        lambda_else: %i[KEYWORD_ENSURE KEYWORD_END],
        lambda_rescue: %i[KEYWORD_ENSURE KEYWORD_RESCUE KEYWORD_ELSE KEYWORD_END],
        loop_predicate: %i[KEYWORD_DO KEYWORD_THEN],
        main: %i[EOF],
        module: %i[KEYWORD_END KEYWORD_RESCUE KEYWORD_ENSURE],
        module_ensure: %i[KEYWORD_END],
        module_else: %i[KEYWORD_ENSURE KEYWORD_END],
        module_rescue: %i[KEYWORD_ENSURE KEYWORD_RESCUE KEYWORD_ELSE KEYWORD_END],
        multi_target: %i[EOF],
        parens: %i[PARENTHESIS_RIGHT],
        postexe: %i[BRACE_RIGHT],
        predicate: %i[KEYWORD_THEN NEWLINE SEMICOLON],
        preexe: %i[BRACE_RIGHT],
        rescue_modifier: %i[EOF],
        sclass: %i[KEYWORD_END KEYWORD_RESCUE KEYWORD_ENSURE],
        sclass_ensure: %i[KEYWORD_END],
        sclass_else: %i[KEYWORD_ENSURE KEYWORD_END],
        sclass_rescue: %i[KEYWORD_ENSURE KEYWORD_RESCUE KEYWORD_ELSE KEYWORD_END],
        ternary: %i[EOF],
        unless: %i[KEYWORD_ELSE KEYWORD_END],
        until: %i[KEYWORD_END],
        while: %i[KEYWORD_END]
      }

      # The contexts inside a method (true) or a class body that ends the
      # search (false), for context_def_p.
      CONTEXT_DEF = {
        def: true, def_params: true, def_ensure: true, def_rescue: true, def_else: true,
        class: false, class_ensure: false, class_rescue: false, class_else: false,
        module: false, module_ensure: false, module_rescue: false, module_else: false,
        sclass: false, sclass_ensure: false, sclass_rescue: false, sclass_else: false
      }

      # context_human
      CONTEXT_HUMAN = {
        begin: "begin statement", block_braces: "'{'..'}' block", block_keywords: "'do'..'end' block",
        block_parameters: "'|'..'|' block parameter", case_when: "'when' clause", case_in: "'in' clause",
        class: "class definition", def: "method definition", def_params: "method parameters",
        default_params: "parameter default value", defined: "'defined?' expression",
        else: "'else' clause", begin_else: "'else' clause", block_else: "'else' clause", class_else: "'else' clause",
        def_else: "'else' clause", lambda_else: "'else' clause", module_else: "'else' clause", sclass_else: "'else' clause",
        elsif: "'elsif' clause", embexpr: "embedded expression",
        begin_ensure: "'ensure' clause", block_ensure: "'ensure' clause", class_ensure: "'ensure' clause",
        def_ensure: "'ensure' clause", lambda_ensure: "'ensure' clause", module_ensure: "'ensure' clause",
        sclass_ensure: "'ensure' clause",
        for: "for loop", for_index: "for loop index", if: "if statement", lambda_braces: "'{'..'}' lambda block",
        lambda_do_end: "'do'..'end' lambda block", loop_predicate: "loop predicate", main: "top level context",
        module: "module definition", multi_target: "multiple targets", parens: "parentheses", postexe: "'END' block",
        predicate: "predicate", preexe: "'BEGIN' block",
        begin_rescue: "'rescue' clause", block_rescue: "'rescue' clause", class_rescue: "'rescue' clause",
        def_rescue: "'rescue' clause", lambda_rescue: "'rescue' clause", module_rescue: "'rescue' clause",
        rescue_modifier: "'rescue' clause", sclass_rescue: "'rescue' clause",
        sclass: "singleton class definition", ternary: "ternary expression", unless: "unless statement",
        until: "until statement", while: "while statement"
      }

      private

      # -- tokens ---------------------------------------------------------------

      # match1 through match8
      def match?(*types) = types.include?(@current_type)

      # accept1, accept2
      def accept(*types)
        return false unless types.include?(@current_type)

        lex
        true
      end

      # expect1, expect2: a missing token is put in its place, empty at the
      # end of the previous one, with an error there.
      def expect(*types, id)
        return if accept(*types)

        location = @previous_end
        err(location, location, id)
        @previous_start = location
        @previous_type = :MISSING
      end

      # expect1_heredoc_term
      def expect_heredoc_term(ident_start, ident_length)
        if @current_type == :HEREDOC_END
          lex
        else
          err_heredoc_term(ident_start, ident_length)
          @previous_start = @previous_end
          @previous_type = :MISSING
        end
      end

      # expect1_opening: the error is at the token that opened the construct.
      def expect_opening(type, id, opening)
        return if accept(type)

        err(opening.start, opening.end, id)
        @previous_start = @previous_end
        @previous_type = :MISSING
      end

      # -- contexts ---------------------------------------------------------

      # context_terminator
      def context_terminator?(context, type) = CONTEXT_TERMINATORS.fetch(context).include?(type)

      # context_recoverable: the innermost context the token ends, or :none.
      def context_recoverable(type)
        @contexts.reverse_each { |context| return context if context_terminator?(context, type) }
        :none
      end

      # context_push
      def context_push(context) = @contexts.push(context)

      # context_pop
      def context_pop = @contexts.pop

      # context_p
      def context?(context) = @contexts.include?(context)

      # context_def_p
      def context_def?
        @contexts.reverse_each do |context|
          inside = CONTEXT_DEF[context]
          return inside unless inside.nil?
        end
        false
      end

      # context_human
      def context_human(context) = CONTEXT_HUMAN.fetch(context)

      # The current context, or :none.
      def current_context = @contexts.last || :none

      # -- expressions ----------------------------------------------------------

      # parse_value_expression
      def parse_value_expression(binding_power, flags, id, depth)
        node = parse_expression(binding_power, flags, id, depth)
        assert_value_expression(node)
        node
      end

      # Tokens that never begin an expression, though they have no binding
      # power, and the unary tokens that do, though they have one.
      NO_EXPRESSION_TOKENS = %i[
        EQUAL_GREATER KEYWORD_IN BRACE_RIGHT BRACKET_RIGHT COLON COMMA EMBEXPR_END EOF LAMBDA_BEGIN KEYWORD_DO
        KEYWORD_DO_BLOCK KEYWORD_DO_LAMBDA KEYWORD_DO_LOOP KEYWORD_END KEYWORD_ELSE KEYWORD_ELSIF KEYWORD_ENSURE KEYWORD_THEN KEYWORD_RESCUE
        KEYWORD_WHEN NEWLINE PARENTHESIS_RIGHT SEMICOLON UAMPERSAND
      ].to_h { |type| [type, true] }.freeze
      UNARY_EXPRESSION_TOKENS = %i[UCOLON_COLON UMINUS UMINUS_NUM UPLUS BANG TILDE UDOT_DOT UDOT_DOT_DOT].to_h { |type| [type, true] }.freeze

      # token_begins_expression_p
      def token_begins_expression?(type)
        return false if NO_EXPRESSION_TOKENS.key?(type)
        return true if UNARY_EXPRESSION_TOKENS.key?(type)

        BINDING_POWERS[type].left == BINDING_POWER_UNSET
      end

      # parse_starred_expression
      def parse_starred_expression(binding_power, flags, id, depth)
        if accept(:USTAR)
          operator = previous_token
          expression = parse_value_expression(binding_power, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_star, depth + 1)
          return splat_node(operator, expression)
        end

        parse_value_expression(binding_power, flags, id, depth)
      end

      # pm_node_unreference: before the C frees a node, its jumps leave the
      # block exits and its implicit parameters leave the scope's list.
      def node_unreference(node)
        case node
        when BreakNode, NextNode, RedoNode
          index = @current_block_exits.index { |block_exit| block_exit.equal?(node) }
          @current_block_exits.delete_at(index) if index
        when LocalVariableReadNode, ItLocalVariableReadNode
          implicit = @current_scope.implicit_parameters
          index = implicit.index { |parameter| parameter.equal?(node) }
          implicit.delete_at(index) if index
          return
        end

        node.compact_child_nodes.each { |child| node_unreference(child) }
      end

      # -- targets and writes -----------------------------------------------

      # parse_write_name: `foo` as the write name `foo=`.
      def parse_write_name(name)
        bytes = @constant_pool.bytes(constant_id_of(name))
        constant_symbol(constant_id_owned(bytes + "="))
      end

      UNWRITABLE_ERRORS = {
        SourceEncodingNode => :expression_not_writable_encoding, FalseNode => :expression_not_writable_false,
        SourceFileNode => :expression_not_writable_file, SourceLineNode => :expression_not_writable_line,
        NilNode => :expression_not_writable_nil, SelfNode => :expression_not_writable_self,
        TrueNode => :expression_not_writable_true
      }

      # parse_unwriteable_target: `nil`, `self` and the like become local
      # targets, with an error naming them.
      def parse_unwriteable_target(target)
        id = UNWRITABLE_ERRORS[target.class]
        err_node(target, id) if id

        name = constant_symbol(constant_id_location(target.start_offset, target.end_offset))
        local_variable_target_node(target.location, name, 0)
      end

      # Whether a call can become a local variable or attribute write: a
      # message without `!` or `?`, and no parentheses, arguments or block.
      def call_writable_target?(call)
        return false unless loc_present?(call.message_loc)

        last = @source.getbyte(loc_end(call.message_loc) - 1)
        last != 0x21 && last != 0x3F && call.opening_loc.nil? && call.arguments.nil? && call.block.nil?
      end

      # parse_target: the node as the target of a write. `multiple` for one of
      # several targets, where `&.` is not allowed; `splat_parent` inside a
      # splat, where fewer targets are.
      def parse_target(target, multiple, splat_parent)
        case target
        when ErrorRecoveryNode
          target
        when SourceEncodingNode, FalseNode, SourceFileNode, SourceLineNode, NilNode, SelfNode, TrueNode
          parse_unwriteable_target(target)
        when ClassVariableReadNode
          retype(target, ClassVariableTargetNode)
        when ConstantPathNode
          err_node(target, :write_target_in_method) if context_def?
          retype(target, ConstantPathTargetNode)
        when ConstantReadNode
          err_node(target, :write_target_in_method) if context_def?
          retype(target, ConstantTargetNode)
        when BackReferenceReadNode, NumberedReferenceReadNode
          err_node_content(target, :write_target_readonly)
          error_recovery_node_unexpected(target)
        when GlobalVariableReadNode
          retype(target, GlobalVariableTargetNode)
        when LocalVariableReadNode
          if numbered_parameter?(target.start_offset, target.end_offset)
            err(target.start_offset, target.end_offset, :parameter_numbered_reserved, @source.byteslice(target.start_offset, 2))
            node_unreference(target)
          end

          scope_find(target.depth).locals.unread(constant_id_of(target.name))
          retype(target, LocalVariableTargetNode)
        when ItLocalVariableReadNode
          name = constant_symbol(local_add_constant("it"))
          node = local_variable_target_node(target.location, name, 0)
          node_unreference(target)
          node
        when InstanceVariableReadNode
          retype(target, InstanceVariableTargetNode)
        when MultiTargetNode
          err_node(target, :write_target_unexpected) if splat_parent
          target
        when SplatNode
          target.expression = parse_target(target.expression, multiple, true) if target.expression
          target
        when CallNode
          if call_writable_target?(target)
            if target.receiver.nil?
              # `foo` was a method call; before `=` it is a local variable.
              message_loc = target.message_loc
              name = constant_symbol(local_add_location(loc_start(message_loc), loc_end(message_loc), 0))
              return local_variable_target_node(message_loc, name, 0)
            end

            message_start = loc_start(target.message_loc)
            if @source.getbyte(message_start) == 0x5F ||
               @encoding.alnum_char(@source, message_start, loc_end(target.message_loc) - message_start) != 0
              err_node(target, :unexpected_safe_navigation) if multiple && target.flag?(CallNodeFlags::SAFE_NAVIGATION)

              target.name = parse_write_name(target.name)
              return call_target_node(target)
            end
          end

          return index_target_node(target) if target.flag?(CALL_NODE_FLAGS_INDEX)

          err_node(target, :write_target_unexpected)
          target
        else
          err_node(target, :write_target_unexpected)
          target
        end
      end

      # parse_target_validate: a target must be followed by `=`, by `in` in a
      # for loop's index, or by `)` in parentheses.
      def parse_target_validate(target, multiple)
        result = parse_target(target, multiple, false)

        unless @current_type == :EQUAL ||
               (context?(:for_index) && @current_type == :KEYWORD_IN) ||
               (context?(:parens) && @current_type == :PARENTHESIS_RIGHT)
          err_node(result, :write_target_unexpected)
        end
        result
      end

      # parse_shareable_constant_write
      def parse_shareable_constant_write(write)
        shareable_constant = scope_shareable_constant
        return write if shareable_constant == 0

        shareable_constant_node(write, shareable_constant)
      end

      # parse_write: `target operator value` as a write node.
      def parse_write(target, operator, value)
        case target
        when ErrorRecoveryNode
          target
        when ClassVariableReadNode
          class_variable_write_node(target, operator, value)
        when ConstantPathNode
          node = constant_path_write_node(target, operator, value)
          err_node(node, :write_target_in_method) if context_def?
          parse_shareable_constant_write(node)
        when ConstantReadNode
          node = constant_write_node(target, operator, value)
          err_node(node, :write_target_in_method) if context_def?
          parse_shareable_constant_write(node)
        when BackReferenceReadNode, NumberedReferenceReadNode, GlobalVariableReadNode
          err_node_content(target, :write_target_readonly) unless target.is_a?(GlobalVariableReadNode)
          global_variable_write_node(target, operator, value)
        when LocalVariableReadNode
          depth = target.depth
          scope = scope_find(depth)

          if numbered_parameter?(target.start_offset, target.end_offset)
            id = scope.parameters.anybits?(Scope::NUMBERED_FOUND) ? :expression_not_writable_numbered : :parameter_numbered_reserved
            err(target.start_offset, target.end_offset, id, @source.byteslice(target.start_offset, 2))
            node_unreference(target)
          end

          scope.locals.unread(constant_id_of(target.name))
          local_variable_write_node(target.name, depth, value, target.location, operator)
        when ItLocalVariableReadNode
          name = constant_symbol(local_add_constant("it"))
          node = local_variable_write_node(name, 0, value, target.location, operator)
          node_unreference(target)
          node
        when InstanceVariableReadNode
          instance_variable_write_node(target, operator, value)
        when MultiTargetNode
          multi_write_node(target, operator, value)
        when SplatNode
          target.expression = parse_write(target.expression, operator, value) if target.expression

          multi_target = multi_target_node
          multi_target_node_targets_append(multi_target, target)
          multi_write_node(multi_target, operator, value)
        when CallNode
          if call_writable_target?(target)
            if target.receiver.nil?
              # `foo` was a method call; before `=` it is a local variable.
              message = target.message_loc
              local_add_location(loc_start(message), loc_end(message), 0)
              name = constant_symbol(constant_id_location(loc_start(message), loc_end(message)))
              node = local_variable_write_node(name, 0, value, message, operator)
              refute_numbered_parameter(loc_start(message), loc_end(message))
              return node
            end

            if identifier_start_width(loc_start(target.message_loc)) != 0
              # `foo.bar = 1` calls `bar=` with the value.
              arguments = arguments_node
              target.arguments = arguments
              arguments_node_arguments_append(arguments, value)
              target.end_offset = arguments.end_offset
              target.equal_loc = operator.location

              target.name = parse_write_name(target.name)
              target.flag_set(CallNodeFlags::ATTRIBUTE_WRITE | implicit_array_write_flags(value, CALL_NODE_FLAGS_IMPLICIT_ARRAY))
              return target
            end
          end

          if target.flag?(CALL_NODE_FLAGS_INDEX)
            # `foo[bar] = 1` calls `[]=` with the value last.
            target.arguments ||= arguments_node
            arguments_node_arguments_append(target.arguments, value)
            target.end_offset = value.end_offset

            target.name = constant_name("[]=")
            target.equal_loc = operator.location

            index_arguments_check(target.arguments, target.block)
            target.flag_set(CallNodeFlags::ATTRIBUTE_WRITE | implicit_array_write_flags(value, CALL_NODE_FLAGS_IMPLICIT_ARRAY))
            return target
          end

          # The value has nowhere to go; the C frees it.
          node_unreference(value)
          err_token(operator, :write_target_unexpected)
          target
        else
          err_token(operator, :write_target_unexpected)
          target
        end
      end

      # parse_unwriteable_write: `nil = 1` and the like become local writes,
      # with an error at the `=`.
      def parse_unwriteable_write(target, equals, value)
        id = UNWRITABLE_ERRORS[target.class]
        err_token(equals, id) if id

        name = constant_symbol(local_add_location(target.start_offset, target.end_offset, 1))
        local_variable_write_node(name, 0, value, target.location, equals)
      end

      # parse_targets: the targets of a multiple write or a for loop's index,
      # from the first one.
      def parse_targets(first_target, binding_power, depth)
        has_rest = first_target.is_a?(SplatNode)

        result = multi_target_node
        multi_target_node_targets_append(result, parse_target(first_target, true, false))

        while accept(:COMMA)
          if accept(:USTAR)
            err_previous(:multi_assign_multi_splats) if has_rest

            star_operator = previous_token
            name = nil

            if token_begins_expression?(@current_type)
              name = parse_expression(binding_power, ACCEPTS_DO_BLOCK, :expect_expression_after_star, depth + 1)
              name = parse_target(name, true, true)
            end

            multi_target_node_targets_append(result, splat_node(star_operator, name))
            has_rest = true
          elsif @current_type == :PARENTHESIS_LEFT_GROUPING
            context_push(:multi_target)
            target = parse_expression(binding_power, ACCEPTS_DO_BLOCK, :expect_expression_after_comma, depth + 1)
            target = parse_target(target, true, false)

            multi_target_node_targets_append(result, target)
            context_pop
          elsif token_begins_expression?(@current_type)
            target = parse_expression(binding_power, ACCEPTS_DO_BLOCK, :expect_expression_after_comma, depth + 1)
            target = parse_target(target, true, false)

            multi_target_node_targets_append(result, target)
          elsif @current_type != :EOF
            # A trailing comma is an implicit rest.
            multi_target_node_targets_append(result, implicit_rest_node(previous_token))
            break
          end
        end

        result
      end

      # parse_targets_validate: the targets must be followed by `=` or `)`.
      def parse_targets_validate(first_target, binding_power, depth)
        result = parse_targets(first_target, binding_power, depth)

        # A newline may come before the `)` or `=` only inside parentheses
        # (`a, b\n= 1, 2` is not valid).
        accept(:NEWLINE) if context?(:parens) || context?(:multi_target)

        err_node(result, :write_target_unexpected) unless match?(:EQUAL, :PARENTHESIS_RIGHT)
        result
      end

      # -- statements ---------------------------------------------------------

      # parse_statements: statements separated by newlines or semicolons, up
      # to a token that ends `context`; nil when there are none.
      def parse_statements(context, depth)
        nil while accept(:SEMICOLON, :NEWLINE)
        return if context_terminator?(context, @current_type)

        statements = statements_node
        context_push(context)

        loop do
          node = parse_expression(BINDING_POWER_STATEMENT, ACCEPTS_COMMAND_CALL | ACCEPTS_DO_BLOCK, :cannot_parse_expression, depth + 1)
          statements_node_body_append(statements, node, true)

          # After an error, the context the recovery is for ends the list.
          if @recovering
            @recovering = false if context_terminator?(context, @current_type)
            break
          end

          if accept(:NEWLINE, :SEMICOLON)
            nil while accept(:NEWLINE, :SEMICOLON)
            break if context_terminator?(context, @current_type)

            next
          end

          break if context_terminator?(context, @current_type)

          # An unterminated statement: skip a token that could not be parsed,
          # or report the missing terminator.
          if node.is_a?(ErrorRecoveryNode)
            lex

            if @current_type == :EOF
              @recovering = true
              break
            end

            nil while accept(:NEWLINE, :SEMICOLON)
            break if context_terminator?(context, @current_type)
          elsif !accept(:NEWLINE, :EOF)
            err_current(:expect_eol_after_statement, Tokens::HUMAN.fetch(@current_type))
            @previous_start = @previous_end
            @previous_type = :MISSING
          end
        end

        context_pop
        void_statements_check(statements, context != :begin_ensure && context != :def_ensure)
        statements
      end

      # -- hashes and arguments -----------------------------------------------

      # parse_assocs: the elements of a hash or keyword hash; true when one is
      # a `**` splat.
      def parse_assocs(literals, node, depth)
        contains_keyword_splat = false

        loop do
          case @current_type
          when :USTAR_STAR
            lex
            operator = previous_token
            value = nil

            if token_begins_expression?(@current_type)
              value = parse_value_expression(BINDING_POWER_DEFINED, ACCEPTS_DO_BLOCK, :expect_expression_after_splat_hash, depth + 1)

              # A hash literal's keys join this hash's.
              hash_key_static_literals_merge(literals, value, value.start_offset) if value.is_a?(HashNode)
            else
              scope_forwarding_keywords_check(operator)
            end

            element = assoc_splat_node(value, operator)
            contains_keyword_splat = true
          when :LABEL
            label = current_token
            lex

            key = symbol_node_label(label)
            hash_key_static_literals_add(literals, key)

            value = nil
            if token_begins_expression?(@current_type)
              value = parse_value_expression(BINDING_POWER_DEFINED, ACCEPTS_DO_BLOCK, :hash_expression_after_label, depth + 1)
            else
              # `{ foo: }` reads the value of `foo`.
              value = parse_assoc_implicit_value(label)
              value.end_offset += 1
              value = implicit_node(value)
            end

            element = assoc_node(key, NOT_PROVIDED, value)
          else
            key = parse_value_expression(BINDING_POWER_DEFINED, ACCEPTS_DO_BLOCK | ACCEPTS_LABEL, :hash_key, depth + 1)

            # A string key is frozen.
            key.flag_set(StringFlags::FROZEN | NodeFlags::STATIC_LITERAL) if key.is_a?(StringNode)

            hash_key_static_literals_add(literals, key)

            if symbol_node_label?(key)
              operator = NOT_PROVIDED
            else
              expect(:EQUAL_GREATER, :hash_rocket)
              operator = previous_token
            end

            value = parse_value_expression(BINDING_POWER_DEFINED, ACCEPTS_DO_BLOCK, :hash_value, depth + 1)
            element = assoc_node(key, operator, value)
          end

          if node.is_a?(HashNode)
            hash_node_elements_append(node, element)
          else
            keyword_hash_node_elements_append(node, element)
          end

          break unless accept(:COMMA)
          next if match?(:USTAR_STAR, :LABEL)
          next if token_begins_expression?(@current_type)

          break
        end

        contains_keyword_splat
      end

      # The value of a label with none written: a constant, a local variable,
      # or a method call of that name.
      def parse_assoc_implicit_value(label)
        if @encoding.isupper_char(@source, label.start, label.end - 1 - label.start)
          return constant_read_node(Token.new(:CONSTANT, label.start, label.end - 1))
        end

        identifier = Token.new(:IDENTIFIER, label.start, label.end - 1)
        depth = -1
        last = @source.getbyte(identifier.end - 1)
        if last == 0x21 || last == 0x3F
          err_token_content(identifier, :invalid_local_variable_read)
        else
          depth = local_depth(identifier.start, identifier.end)
        end

        depth == -1 ? call_node_variable_call(identifier) : local_variable_read_node(identifier, depth)
      end

      # argument_allowed_for_bare_hash: whether the argument is the key of a
      # hash without braces, which a label is, or which `=>` follows.
      def argument_allowed_for_bare_hash?(argument)
        return true if symbol_node_label?(argument)

        if argument.is_a?(CallNode) && argument.opening_loc.nil? && argument.arguments
          return false if argument.arguments.flag?(ArgumentsNodeFlags::CONTAINS_KEYWORDS | ArgumentsNodeFlags::CONTAINS_SPLAT)
          return false if argument.block
        end

        accept(:EQUAL_GREATER)
      end

      # parse_arguments_append
      def parse_arguments_append(arguments, argument)
        arguments.arguments ||= arguments_node
        arguments_node_arguments_append(arguments.arguments, argument)
      end

      # parse_arguments: a call's arguments up to `terminator`, into
      # `arguments`.
      def parse_arguments(arguments, accepts_forwarding, terminator, flags, depth)
        binding_power = BINDING_POWERS[@current_type].left

        if match?(terminator, :EOF) ||
           (binding_power != BINDING_POWER_UNSET && binding_power < BINDING_POWER_RANGE) ||
           context_terminator?(current_context, @current_type)
          return
        end

        parsed_first_argument = false
        parsed_bare_hash = false
        parsed_block_argument = false
        parsed_forwarding_arguments = false

        until @current_type == :EOF
          err_current(:argument_after_forwarding_ellipses) if parsed_forwarding_arguments

          argument = nil
          # The forwarding `...` case falls into the default one when it is a
          # range instead.
          default = true

          case @current_type
          when :USTAR_STAR, :LABEL
            default = false
            err_current(:argument_bare_hash) if parsed_bare_hash

            hash = keyword_hash_node
            argument = hash

            hash_keys = StaticLiterals.new(self)
            contains_keyword_splat = parse_assocs(hash_keys, hash, depth + 1)

            parse_arguments_append(arguments, argument)

            node_flags = ArgumentsNodeFlags::CONTAINS_KEYWORDS
            node_flags |= ArgumentsNodeFlags::CONTAINS_KEYWORD_SPLAT if contains_keyword_splat
            arguments.arguments.flag_set(node_flags)

            parsed_bare_hash = true
          when :UAMPERSAND
            default = false
            lex
            operator = previous_token
            expression = nil

            if token_begins_expression?(@current_type)
              expression = parse_value_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :expect_argument, depth + 1)
            else
              scope_forwarding_block_check(operator)
            end

            argument = block_argument_node(operator, expression)
            if parsed_block_argument
              parse_arguments_append(arguments, argument)
            else
              arguments.block = argument
            end

            err_current(:argument_after_block) if @current_type == :COMMA

            parsed_block_argument = true
          when :USTAR
            default = false
            lex
            operator = previous_token

            if match?(:PARENTHESIS_RIGHT, :COMMA, :SEMICOLON, :BRACKET_RIGHT)
              scope_forwarding_positionals_check(operator)
              argument = splat_node(operator, nil)
              err_previous(:argument_splat_after_assoc_splat) if parsed_bare_hash
            else
              expression = parse_value_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_splat, depth + 1)
              err(operator.start, expression.end_offset, :argument_splat_after_assoc_splat) if parsed_bare_hash
              argument = splat_node(operator, expression)
            end

            parse_arguments_append(arguments, argument)
          when :UDOT_DOT_DOT
            if accepts_forwarding
              lex

              if token_begins_expression?(@current_type)
                # `...` before an expression is a beginless range.
                operator = previous_token
                right = parse_expression(BINDING_POWER_RANGE, flags & ACCEPTS_DO_BLOCK, :expect_expression_after_operator, depth + 1)

                if right.is_a?(RangeNode)
                  err(loc_start(right.operator_loc), loc_end(right.operator_loc), :unexpected_range_operator)
                end

                argument = range_node(nil, operator, right)
              else
                default = false
                scope_forwarding_all_check(previous_token)
                err_previous(:argument_forwarding_unbound) if parsed_first_argument && terminator == :EOF

                argument = forwarding_arguments_node(previous_token)
                parse_arguments_append(arguments, argument)
                arguments.arguments.flag_set(ArgumentsNodeFlags::CONTAINS_FORWARDING)
                arguments.has_forwarding = true
                parsed_forwarding_arguments = true
              end
            end
          end

          if default
            argument ||= parse_value_expression(BINDING_POWER_DEFINED,
                                                (flags & ACCEPTS_DO_BLOCK) | (parsed_first_argument ? 0 : ACCEPTS_COMMAND_CALL) | ACCEPTS_LABEL,
                                                :expect_argument, depth + 1)

            contains_keywords = false
            contains_keyword_splat = false

            if argument_allowed_for_bare_hash?(argument)
              err_previous(:argument_bare_hash) if parsed_bare_hash

              # A key is an argument: a command call or a block call is none
              # (`Foo::Bar { } => v`, `foo bar do end => v`).
              if command_call_value?(argument) || block_call?(argument)
                err_previous(:expect_eol_after_statement, Tokens::HUMAN.fetch(@previous_type))
              end

              operator = @previous_type == :EQUAL_GREATER ? previous_token : NOT_PROVIDED

              bare_hash = keyword_hash_node
              contains_keywords = true

              hash_keys = StaticLiterals.new(self)
              hash_key_static_literals_add(hash_keys, argument)

              # The value of the key already parsed.
              value = parse_value_expression(BINDING_POWER_DEFINED, flags & ACCEPTS_DO_BLOCK, :hash_value, depth + 1)
              argument = assoc_node(argument, operator, value)

              keyword_hash_node_elements_append(bare_hash, argument)
              argument = bare_hash

              if accept(:COMMA) && (token_begins_expression?(@current_type) || match?(:USTAR_STAR, :LABEL))
                contains_keyword_splat = parse_assocs(hash_keys, bare_hash, depth + 1)
              end

              parsed_bare_hash = true
            end

            parse_arguments_append(arguments, argument)

            node_flags = 0
            node_flags |= ArgumentsNodeFlags::CONTAINS_KEYWORDS if contains_keywords
            node_flags |= ArgumentsNodeFlags::CONTAINS_KEYWORD_SPLAT if contains_keyword_splat
            arguments.arguments.flag_set(node_flags)
          end

          parsed_first_argument = true

          break if argument.is_a?(ErrorRecoveryNode) || @recovering

          # Before a specific terminator a newline is no statement end.
          accepted_newline = terminator != :EOF && accept(:NEWLINE)

          if @previous_type == :COMMA && parsed_bare_hash
            # The hash took the comma; more arguments follow.
          elsif accept(:COMMA)
            err_previous(:invalid_comma) if accepted_newline

            # `foo(bar 1 do end, 2)`: a command call with a block ends the
            # arguments.
            if argument.is_a?(CallNode) && argument.opening_loc.nil? && argument.arguments && argument.block
              err_previous(:invalid_comma)
              break
            end
          else
            break
          end

          # A trailing comma, which may not follow `...` (`foo(...,)`).
          if @current_type == terminator
            err_previous(:invalid_comma) if parsed_forwarding_arguments
            break
          end
        end
      end
    end
  end
end
