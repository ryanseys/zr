# frozen_string_literal: true

# `ripper.so`: the C part of ext/ripper, over prism. CRuby's ripper runs
# parse.y's lexer and parser and calls a method for each token (a scanner
# event) and each rule it reduces (a parser event). Here prism supplies
# both: its lex_compat stream gives every token with ripper's position and
# lexer state, and prism's own Ripper translation walks the tree and gives
# the parser events. The Ruby part, ripper.rb and ripper/*.rb, is ruby's.
require "prism"
require "prism/translation/ripper"

class Ripper
  Version = "0.1.0"

  # T_DATA, of a type that is not frozen-shareable.
  Ractor.send(:data_class!, self)

  # The tables ripper/core.rb reads, which ripper/lexer.rb adds to.
  PARSER_EVENT_TABLE = Prism::Translation::Ripper::PARSER_EVENT_TABLE.dup
  SCANNER_EVENT_TABLE = Prism::Translation::Ripper::SCANNER_EVENT_TABLE.dup

  Prism::Translation::Ripper.constants.grep(/\AEXPR_/).each do |name|
    const_set(name, Prism::Translation::Ripper.const_get(name))
  end

  def self.lex_state_name(state) = Prism::Translation::Ripper.lex_state_name(state)

  # The leading spaces and tabs of `input` that make up `width` columns,
  # a tab reaching the next multiple of eight, removed in place, as
  # parse.y's dedent_string removes them. Returns the bytes removed.
  def self.dedent_string(input, width)
    raise TypeError, no_implicit_conversion(input, "String") unless input.is_a?(String)

    columns = 0
    removed = 0
    input.each_byte do |byte|
      break if columns >= width

      if byte == 32
        columns += 1
      elsif byte == 9
        tabbed = (columns / 8 + 1) * 8
        break if tabbed > width

        columns = tabbed
      else
        break
      end
      removed += 1
    end
    input.replace(input.byteslice(removed..))
    removed
  end

  # As ripper_initialize: an IO or an object with `gets` is read when
  # the parse starts, anything else is a String (StringValue). The file
  # name is a frozen copy (StringValueCStr), and the line a C int.
  def initialize(src, filename = nil, lineno = nil)
    if src.is_a?(IO) || src.respond_to?(:gets)
      @input = src
      src = nil
    else
      src = Primitive.zr_str_operand(src)
    end
    filename = filename.nil? ? "(ripper)".freeze : Primitive.zr_str_operand(filename)
    raise ArgumentError, "string contains null byte" if File.send(:nul_char?, filename)

    @cursor = Cursor.new(src, filename.dup.freeze, lineno.nil? ? 1 : Integer.send(:int_operand, lineno))
  end

  def filename = @cursor.filename

  # The position of the event being dispatched, and the lexer's state
  # and token there; nil outside a parse.
  def lineno = @cursor.parsing ? @cursor.lineno : nil
  def column = @cursor.parsing ? @cursor.column : nil
  def state = @cursor.parsing ? @cursor.state : nil
  def token = @cursor.parsing ? @cursor.token : nil

  def error? = @cursor.error ? true : false
  def end_seen? = @cursor.parsed ? !Prism.parse(source_text).data_loc.nil? : false
  def encoding = Prism.parse(source_text).encoding

  # The parser's debug flag, which a prism parse reads nowhere.
  def yydebug = Primitive.zr_hidden_get(self, :__yydebug__) || false

  def yydebug=(flag)
    Primitive.zr_hidden_set(self, :__yydebug__, flag ? true : false)
    flag
  end
  def debug_output = nil
  def debug_output=(output); end

  # Every token as its scanner event, in order; then the tree as its
  # parser events, where a token in the tree gives the value that its
  # scanner event returned. A second parse finds the input at its end.
  def parse
    raise ArgumentError, "Ripper#parse is not reentrant" if @cursor.parsing
    return nil if @cursor.parsed

    @cursor.parsing = true
    begin
      source_text
      Events.new(self, @cursor).parse
    ensure
      @cursor.parsing = false
      @cursor.parsed = true
    end
  end

  private

  def dedent_string(input, width) = Ripper.dedent_string(input, width)

  # The source: the String given, or the lines that the input gives
  # until nil, as ripper_lex_io_get and ripper_lex_get_generic read
  # them; a line of another class is a TypeError.
  def source_text
    @cursor.source ||= begin
      text = +""
      while (line = @input.public_send(:gets))
        raise TypeError, "gets returned #{line.class} (expected String or nil)" unless line.is_a?(String)

        text << line
      end
      text
    end
  end

  # A parse's source and the positions of its events.
  Cursor = Struct.new(:source, :filename, :first_lineno, :lineno, :column, :state, :token, :parsing, :parsed, :error) do
    def at(line, col, lex_state = state, text = token)
      self.lineno = line
      self.column = col
      self.state = lex_state
      self.token = text
    end
  end
  private_constant :Cursor

  # Finds the `)` that closes a def's parenthesized parameters: after
  # `def`, the name, and at most one space, a `(` opens them.
  class DefParams
    def initialize
      @phase = nil
      @depth = 0
    end

    # Whether the token before this one closed the parameters. Then it
    # reads this token.
    def closed_before?(event, text)
      closed = @phase == :closed
      @phase = nil if closed
      read(event, text)
      closed
    end

    private

    def read(event, text)
      case @phase
      when :def then @phase = :name unless event == :on_sp
      when :name then @phase = event == :on_sp ? :gap : @phase
      when :gap then @phase = nil unless event == :on_lparen
      when :params
        @depth += 1 if event == :on_lparen
        @depth -= 1 if event == :on_rparen
        @phase = :closed if @depth.zero?
        return
      end
      if event == :on_kw && text == "def"
        @phase = :def
      elsif event == :on_lparen && %i[name gap].include?(@phase)
        @phase = :params
        @depth = 1
      end
    end
  end
  private_constant :DefParams

  # prism's walk of the tree, which calls each event on the Ripper that
  # requested the parse.
  class Events < Prism::Translation::Ripper
    # parse.y's warning for each of prism's: the method that it calls
    # (`warn` for rb_warn, `warning` for rb_warning), its format, and
    # whether it warns only when $VERBOSE is true. The arguments are read
    # back from prism's message; with no format, the message is parse.y's
    # format. Ripper has no warning for an unused local.
    WARNINGS = {
      ambiguous_prefix_ampersand: [:warning, "'&' interpreted as argument prefix"],
      ambiguous_prefix_star: [:warning, "'*' interpreted as argument prefix"],
      ambiguous_prefix_star_star: [:warning, "'**' interpreted as argument prefix"],
      comparison_after_comparison: [:warning, "comparison '%s' after comparison"],
      dot_dot_dot_eol: [:warn, "... at EOL, should be parenthesized?"],
      duplicated_hash_key: [:warn, "key %+li\v is duplicated and overwritten on line %d"],
      duplicated_when_clause: [:warning, "'when' clause on line %d duplicates 'when' clause on line %d and is ignored"],
      end_in_method: [:warn, "END in method; use at_exit"],
      equal_in_conditional: [:warn, "found '= literal' in conditional, should be =="],
      equal_in_conditional_3_3: [:warn, "found '= literal' in conditional, should be =="],
      float_out_of_range: [:warning, "Float %s out of range"],
      ignored_frozen_string_literal: [:warning, "'%s' is ignored after any tokens"],
      indentation_mismatch: [:warn, "mismatched indentations at '%s' with '%s' at %d", true],
      integer_in_flip_flop: [:warn, "integer literal in flip-flop"],
      invalid_character: [:warn, "invalid character syntax; use ?\\%c"],
      invalid_magic_comment_value: [:warning, "invalid value for %s: %s"],
      invalid_numbered_reference: [:warn, "'%s' is too big for a number variable, always nil"],
      literal_in_condition_default: [:warn, nil],
      literal_in_condition_verbose: [:warning, nil],
      shareable_constant_value_line: [:warning, "'%s' is ignored unless in comment-only line"],
      unexpected_carriage_return: [:warn, "encountered \\r in middle of line, treated as a mere space"],
      unreachable_statement: [:warning, "statement not reached"],
      unused_local_variable: nil,
      void_statement: [:warn, "possibly useless use of %s in void context", true]
    }.freeze

    # parse.y's report of each of prism's errors that it reports in its own
    # way: the event, and its text, or :reason for the part of prism's
    # message after its "; ", or nil for prism's message. The lexer's
    # errors are compile errors; an error with a token is an event of its
    # own, whose second argument is the token's value.
    ERRORS = {
      alias_argument_numbered_reference: [:on_alias_error, :reason],
      argument_formal_class: [:on_param_error, :reason],
      argument_formal_constant: [:on_param_error, :reason],
      argument_formal_global: [:on_param_error, :reason],
      argument_formal_ivar: [:on_param_error, :reason],
      argument_no_forwarding_ampersand: [:compile_error, :reason],
      argument_no_forwarding_star: [:compile_error, :reason],
      argument_no_forwarding_star_star: [:compile_error, :reason],
      begin_upcase_toplevel: [:on_parse_error, nil],
      class_name: [:on_class_name_error, :reason],
      class_variable_bare: [:compile_error, nil],
      def_endless_setter: [:on_parse_error, "setter method cannot be defined in an endless method definition"],
      escape_invalid_control: [:on_parse_error, nil],
      escape_invalid_hexadecimal: [:on_parse_error, "invalid hex escape"],
      global_variable_bare: [:compile_error, nil],
      heredoc_term: [:compile_error, :reason],
      incomplete_variable_class: [:compile_error, nil],
      incomplete_variable_instance: [:compile_error, nil],
      instance_variable_bare: [:compile_error, nil],
      invalid_character: [:compile_error, nil],
      invalid_block_exit: [:on_parse_error, nil],
      invalid_retry_after_else: [:on_parse_error, nil],
      invalid_retry_after_ensure: [:on_parse_error, nil],
      invalid_retry_without_rescue: [:on_parse_error, nil],
      invalid_variable_global: [:compile_error, nil],
      invalid_variable_global_3_3: [:compile_error, nil],
      invalid_yield: [:on_parse_error, nil],
      module_name: [:on_class_name_error, :reason],
      parameter_name_duplicated: [:on_parse_error, nil],
      regexp_term: [:compile_error, "unterminated regexp meets end of file"],
      return_invalid: [:on_parse_error, nil]
    }.freeze

    # The errors of a target that cannot be written: parse.y reports each
    # as an assign_error around the target, in the tree.
    ASSIGN_ERRORS = %i[
      expression_not_writable expression_not_writable_encoding expression_not_writable_false expression_not_writable_file
      expression_not_writable_line expression_not_writable_nil expression_not_writable_numbered expression_not_writable_self
      expression_not_writable_true write_target_readonly write_target_in_method
    ].freeze

    # The errors after which parse.y's tree is whole, so that its parser
    # events follow, as prism's tree is.
    KEEPS_TREE = (ASSIGN_ERRORS + %i[
      alias_argument_numbered_reference argument_formal_class argument_formal_constant argument_formal_global
      argument_formal_ivar argument_no_forwarding_ampersand argument_no_forwarding_star argument_no_forwarding_star_star
      begin_upcase_toplevel def_endless_setter invalid_block_exit invalid_retry_after_else invalid_retry_after_ensure
      invalid_retry_without_rescue invalid_yield parameter_name_duplicated parameter_order return_invalid
    ]).freeze

    def initialize(ripper, cursor)
      super(cursor.source, cursor.filename, cursor.first_lineno)
      @ripper = ripper
      @cursor = cursor
      # Each token's scanner event, by its line: its column, the event, the
      # token, its state, and the value that the event returned.
      @tokens = Hash.new { |tokens, key| tokens[key] = [] }
    end

    # The scanner events first, each token once; then the comments, the
    # warnings and the errors; then the tree as its parser events, when
    # parse.y would have the whole tree.
    def parse
      scan
      comments
      warnings
      walk = walks?
      errors(walk)
      result.value.accept(self) if walk
    end

    # The whole program: a jump with nowhere to go (`yield` outside a
    # method, a bare `break`) is an error, as parse.y reports it, where
    # prism's own translation reads the source as part of a script. It
    # starts at the parse's first line, as the tokens do (irb lexes from
    # line 0, after a line that declares its local variables).
    def result
      @result ||= Prism.parse(source, version: "current", line: @cursor.first_lineno)
    end

    # A superclass takes the terminator after it, as parse.y's
    # `superclass` rule does, so the body starts with no void statement.
    def visit_class_node(node)
      return super if node.superclass.nil? || node.body.nil?

      constant_path =
        if node.constant_path.is_a?(Prism::ConstantReadNode)
          bounds(node.constant_path.location)
          on_const_ref(on_const(node.constant_path.name.to_s))
        else
          visit(node.constant_path)
        end
      superclass = visit(node.superclass)
      bodystmt = visit_body_node(node.body.location.copy(length: 0), node.body, true)

      bounds(node.location)
      on_class(constant_path, superclass, bodystmt)
    end

    # A target that cannot be written: its field, or the whole operator
    # assignment, inside an assign_error, as parse.y's tree has it.
    def visit(node)
      message = @assigns&.delete(node) if node
      return super unless message

      if node.type.end_with?("_operator_write_node", "_or_write_node", "_and_write_node")
        on_assign_error(message, super)
      else
        @assign_error = message
        super
      end
    end

    # The target of a multiple assignment that cannot be written, such as
    # `$&` in `$&, _ = 1`.
    def visit_error_recovery_node(node) = on_var_field(visit(node.unexpected))

    # A parameter that is no local variable is a param_error in the list.
    def visit_required_parameter_node(node)
      message = @params&.delete(node.location.start_offset)
      return super unless message

      bounds(node.location)
      on_param_error(message, token_value(node.location))
    end

    # `alias $a $1`: an alias_error in place of the alias.
    def visit_alias_global_variable_node(node)
      message = @aliases&.delete(node.old_name.location.start_offset)
      return super unless message

      bounds(node.keyword_loc)
      on_kw("alias")
      visit_alias_global_variable_node_value(node.new_name)
      bounds(node.old_name.location)
      old_name = on_backref(node.old_name.slice)
      bounds(node.location)
      on_alias_error(message, old_name)
    end

    # `a::C {}`: parse.y's rule for a constant after `::` with a brace
    # block makes a command call with no arguments.
    def on_call(receiver, operator, message)
      return @ripper.__send__(:on_command_call, receiver, operator, message, nil) if @span && brace_command?(@span)

      @ripper.__send__(:on_call, receiver, operator, message)
    end

    private

    # Every token of prism's lexer as its scanner event, with ripper's
    # position and lexer state, as parse.y's lexer would give it.
    def scan
      tokens = Prism.lex_compat(@cursor.source, filepath: @cursor.filename, line: @cursor.first_lineno, version: "current").value
      # Ripper has no event for the end of the input, which prism's
      # lex_compat leaves in place when the source is invalid.
      tokens.pop if tokens.last&.[](1) == :on_eof
      settle_at_eof(tokens)
      before = nil
      params = DefParams.new
      braces = 0
      tokens.each do |(line, col), event, text, lex_state|
        # parse.y leaves the state after a heredoc's body as it was, where
        # prism's lexer moves it on.
        lex_state = before if event == :on_heredoc_end && before
        # parse.y's rule for a def's parenthesized parameters sets the state
        # to BEG before the lexer reads on; prism's token keeps ENDFN.
        lex_state = EXPR_BEG if params.closed_before?(event, text) && event == :on_sp
        # A `}` that closes nothing ends an embedded expression, as
        # parse.y's lexer reads it, and leaves the state as it was.
        case event
        when :on_lbrace, :on_tlambeg, :on_embexpr_beg then braces += 1
        when :on_rbrace, :on_embexpr_end
          if braces.zero?
            event = :on_embexpr_end
            lex_state = before || EXPR_BEG
          else
            braces -= 1
          end
        end
        before = lex_state
        @cursor.at(line, col, lex_state.to_i, text)
        @tokens[line] << [col, event, text, lex_state, @ripper.__send__(event, text)]
      end
    end

    # The spaces and comments after the last newline at the end of the
    # input have the state of the token before that newline: parse.y's
    # lexer reads them looking for a `.` that would go on the line, and
    # goes back to that state at the end.
    def settle_at_eof(tokens)
      newline = tokens.rindex { |token| token[1] == :on_nl } or return
      tail = tokens[(newline + 1)..]
      return if tail.empty? || newline.zero? || !tail.all? { |token| %i[on_sp on_comment].include?(token[1]) }

      state = tokens[newline - 1][3]
      tail.each { |token| token[3] = state }
    end

    # The value that the scanner event returned for the token at this
    # place in the tree: the token of the event that starts here, or one
    # whose text is the same where parse.y's token is of another kind (the
    # `self` of `self = 1` is a keyword), or one inside the text, which a
    # squiggly heredoc's lexing has already dedented.
    def token_at(event, text)
      line = @tokens.fetch(lineno, nil) or return nil
      here = line.select { |token| token[0] == column }
      here.find { |token| token[1] == event } || here.find { |token| token[2] == text } ||
        line.find { |col, kind| kind == event && col > column && col < column + text.bytesize }
    end

    # The first token that starts at `location`.
    def token_starting(location) = @tokens.fetch(location.start_line, nil)&.find { |token| token[0] == location.start_column }

    # The value of the token that starts at `location`.
    def token_value(location) = token_starting(location)&.last

    def bounds(location)
      super
      @span = [location.start_offset, location.end_offset]
      @cursor.at(lineno, column)
    end

    # Places an event at the token that starts at `location`, with that
    # token's text and state, as parse.y reports an error at its token;
    # inside a token, the text is the error's own.
    def place(location)
      bounds(location)
      token = token_starting(location)
      token ? @cursor.at(lineno, column, token[3].to_i, token[2]) : @cursor.at(lineno, column, @cursor.state, location.slice)
    end

    def comments
      result.comments.each do |comment|
        location = comment.location
        bounds(location)
        if comment.is_a?(Prism::InlineComment)
          # An inline comment has its line's newline, where there is one.
          on_comment(result.source.source.bytesize > location.end_offset ? "#{comment.slice}\n" : comment.slice)
        else
          offset = location.start_offset
          lines = comment.slice.lines
          lines.each_with_index do |line, index|
            bounds(location.copy(start_offset: offset))
            if index.zero?
              on_embdoc_beg(line)
            elsif index == lines.size - 1
              on_embdoc_end(line)
            else
              on_embdoc(line)
            end
            offset += line.bytesize
          end
        end
      end
      # parse.y gives a magic comment's name with `_` for each `-`.
      result.magic_comments.each { |magic| on_magic_comment(magic.key.tr("-", "_"), magic.value) }
    end

    def warnings
      result.warnings.each do |warning|
        bounds(warning.location)
        case warning.type
        when :ambiguous_first_argument_plus then on_arg_ambiguous("+")
        when :ambiguous_first_argument_minus then on_arg_ambiguous("-")
        when :ambiguous_slash then on_arg_ambiguous("/")
        when :ambiguous_binary_operator
          operator, syntax = warning.message.match(/\A'(.+)' .* seems like (.+)\z/)&.captures
          on_operator_ambiguous(operator.to_sym, syntax) if operator
        else
          if WARNINGS.key?(warning.type)
            event, format, verbose = WARNINGS[warning.type]
            __send__(event, format || warning.message, *warning_args(warning, format.to_s)) if event && (!verbose || $VERBOSE)
          else
            warning.level == :default ? warning(warning.message) : warn(warning.message)
          end
        end
      end
    end

    # The arguments of a warning's format, read from prism's message, which
    # is the format with them in place.
    def warning_args(warning, format)
      if warning.type == :duplicated_hash_key
        return [literal_value(warning.location), warning.message[/on line (\d+)\z/, 1].to_i]
      end
      return [] unless format.include?("%")

      conversions = format.scan(/%[sdc]/)
      pattern = Regexp.escape(format).gsub(/%[sdc]/, "%s" => "(.*)", "%d" => "(\\d+)", "%c" => "(.)")
      values = warning.message.match(/\A#{pattern}\z/m)&.captures or return []
      values.zip(conversions).map do |value, conversion|
        case conversion
        when "%d" then value.to_i
        when "%c" then value.ord
        else value
        end
      end
    end

    # The value of the literal at `location`, a duplicated key of a hash.
    def literal_value(location)
      node = result.value.breadth_first_search { |n| n.location.start_offset == location.start_offset && n.location.length == location.length }
      case node
      when Prism::SymbolNode then node.unescaped.to_sym
      when Prism::StringNode then node.unescaped
      when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode then node.value
      when Prism::TrueNode then true
      when Prism::FalseNode then false
      end
    end

    # Whether parse.y would have the whole tree: each error is one after
    # which it does, and each piece of prism's tree that recovers from an
    # error is a target that cannot be written.
    def walks?
      return true if result.errors.empty?
      return false unless result.errors.all? { |error| KEEPS_TREE.include?(error.type) }

      @assigns = assign_targets
      @params = errors_by_offset(:on_param_error)
      @aliases = errors_by_offset(:on_alias_error)
      result.value.breadth_first_search { |node| node.is_a?(Prism::ErrorRecoveryNode) && !@assigns.key?(node) }.nil?
    end

    # Each target that cannot be written, with its error: the smallest
    # write or target whose span before its value holds the error.
    def assign_targets
      errors = result.errors.select { |error| ASSIGN_ERRORS.include?(error.type) }
      targets = {}.compare_by_identity
      return targets if errors.empty?

      writes = []
      result.value.breadth_first_search do |node|
        writes << node if node.is_a?(Prism::ErrorRecoveryNode) || node.type.end_with?("_write_node", "_target_node")
        false
      end
      errors.each do |error|
        at = error.location.start_offset
        node = writes.select { |write| write.location.start_offset <= at && at < target_end(write) }.min_by { it.location.length }
        targets[node] = error.message if node
      end
      targets
    end

    def target_end(node) = node.respond_to?(:value) && node.value ? node.value.location.start_offset : node.location.end_offset

    # The messages of the errors of `event`, by where each starts.
    def errors_by_offset(event)
      result.errors.each_with_object({}) do |error, found|
        found[error.location.start_offset] = message(error) if ERRORS[error.type]&.first == event
      end
    end

    # Each error as parse.y reports it. The tree reports those of its
    # targets, parameters and aliases when it is walked. Of the syntax
    # errors that parse.y words in its own way, only the first is
    # reported: prism goes on to report where it recovered.
    def errors(walk)
      syntax = false
      result.errors.uniq { |error| [error.type, error.location.start_offset] }.each do |error|
        event, = ERRORS[error.type]
        event = :on_param_error if error.type == :invalid_local_variable_write && label?(error.location)
        next if walk && (ASSIGN_ERRORS.include?(error.type) || %i[on_param_error on_alias_error].include?(event))

        place(error.location)
        case event
        when :on_param_error, :on_alias_error, :on_class_name_error
          __send__(event, message(error), token_value(error.location))
        when nil
          if ASSIGN_ERRORS.include?(error.type)
            on_assign_error(error.message, token_value(error.location))
          elsif !syntax
            syntax = true
            on_parse_error(heredoc_identifier?(error) ? "unterminated here document identifier" : error.message)
          end
        else
          __send__(event, message(error))
        end
      end
    end

    # `<<"` with no end of its identifier, which prism reads as `<<` and
    # a string.
    def heredoc_identifier?(error)
      error.type == :unexpected_token_ignore && error.location.slice == "<<" && %w[" ' `].include?(source.byteslice(error.location.end_offset, 1))
    end

    # A keyword parameter whose name is no local variable: `def m(a?:)`.
    def label?(location) = token_starting(location)&.[](1) == :on_label

    def message(error)
      return "formal argument must be local variable" if error.type == :invalid_local_variable_write

      _, text = ERRORS[error.type]
      case text
      when :reason then error.message.split("; ", 2).last
      when nil then error.message
      else text
      end
    end

    def brace_command?(span)
      @brace_commands ||= Set.new.tap do |found|
        next unless source.include?("::")

        result.value.breadth_first_search do |node|
          found << [node.location.start_offset, node.location.end_offset] if brace_command_node?(node)
          false
        end
      end
      @brace_commands.include?(span)
    end

    def brace_command_node?(node)
      node.is_a?(Prism::CallNode) && node.call_operator == "::" && node.message&.match?(/\A[A-Z]/) && node.arguments.nil? &&
        node.opening_loc.nil? && node.block.is_a?(Prism::BlockNode) && node.block.opening == "{"
    end

    (PARSER_EVENT_TABLE.keys - %i[call heredoc_dedent var_field const_path_field top_const_field]).each do |event|
      define_method(:"on_#{event}") do |*args|
        @cursor.error = true if event.end_with?("error")
        @ripper.__send__(:"on_#{event}", *args)
      end
    end

    # The field of a target that cannot be written goes inside an
    # assign_error.
    %i[var_field const_path_field top_const_field].each do |event|
      define_method(:"on_#{event}") do |*args|
        field = @ripper.__send__(:"on_#{event}", *args)
        message = @assign_error
        @assign_error = nil
        message ? on_assign_error(message, field) : field
      end
    end

    SCANNER_EVENT_TABLE.each_key do |event|
      define_method(:"on_#{event}") do |text|
        found = token_at(:"on_#{event}", text.to_s)
        found ? found.last : @ripper.__send__(:"on_#{event}", text)
      end
    end

    def warn(fmt, *args) = @ripper.__send__(:warn, fmt, *args)
    def warning(fmt, *args) = @ripper.__send__(:warning, fmt, *args)

    def compile_error(message)
      @cursor.error = true
      @ripper.__send__(:compile_error, message)
    end

    # A squiggly heredoc's tokens come from prism's lexer already
    # dedented, as were their scanner events, so no width is left to
    # take off. parse.y gives the event while it lexes, with the width,
    # before the tokens after the heredoc.
    def on_heredoc_dedent(value, _width) = @ripper.__send__(:on_heredoc_dedent, value, 0)

    def dedent_string(input, width) = @ripper.__send__(:dedent_string, input, width)
  end
  private_constant :Events
end
