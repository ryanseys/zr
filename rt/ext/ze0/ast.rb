# frozen_string_literal: true

# RubyVM::AbstractSyntaxTree over prism.
#
# CRuby 4.0 answers RubyVM::AbstractSyntaxTree.parse with parse.y's node
# tree (the NODE_* taxonomy that ast.c shows through Node#children). zeo has
# no parse.y, so this file rebuilds that tree from prism's tree. The
# Translator walks prism's nodes and replays the grammar actions of parse.y
# (revision 03b6d3f8898a): it builds nodes with the same fields, calls the
# same helpers (block_append, list_append, arg_append, logop, cond0,
# new_bodystmt, reduce_nodes, ...), and gives each node the span that the
# grammar rule gives it. Node#children then reads those fields the way
# ast.c's node_children does.
#
# tools/ast.rb checks the translator against the host's
# RubyVM::AbstractSyntaxTree, node for node.

require "prism"

# In zeo's runtime these classes are RubyVM::AbstractSyntaxTree's own,
# which the runtime defines empty before it loads this file on a first
# parse, so they carry its names; on a CRuby host, which has its own,
# they stay in Ze0::AST.
if RubyVM::AbstractSyntaxTree::Node.instance_methods(false).empty?
  module Ze0
    module AST
      Node = RubyVM::AbstractSyntaxTree::Node
      Location = RubyVM::AbstractSyntaxTree::Location
    end
  end
end

module Ze0
  module AST
    # A span in the source. Lines count from 1; columns count bytes from 0.
    class Location
      attr_reader :first_lineno, :first_column, :last_lineno, :last_column

      class << self
        def new(*)
          raise TypeError, "allocator undefined for RubyVM::AbstractSyntaxTree::Location"
        end

        def build(first_lineno, first_column, last_lineno, last_column)
          location = allocate
          location.send(:setup, first_lineno, first_column, last_lineno, last_column)
          location
        end
      end

      def inspect
        "#<RubyVM::AbstractSyntaxTree::Location:@#{first_lineno}:#{first_column}-#{last_lineno}:#{last_column}>"
      end

      private

      def setup(first_lineno, first_column, last_lineno, last_column)
        @first_lineno = first_lineno
        @first_column = first_column
        @last_lineno = last_lineno
        @last_column = last_column
      end
    end

    # What every node of one parse shares: the script lines and the tokens.
    class Tree
      attr_reader :script_lines, :tokens

      def initialize(script_lines, tokens)
        @script_lines = script_lines
        @tokens = tokens
      end
    end

    # A node of RubyVM::AbstractSyntaxTree: its type, span, and children, as
    # CRuby's Node answers them.
    class Node
      # The keyword locations each node type reports after its own span.
      EXTRA_LOCATIONS = {
        ALIAS: 1, AND: 1, BLOCK_PASS: 1, BREAK: 1, CASE: 2, CASE2: 2, CASE3: 2,
        CLASS: 3, COLON2: 2, COLON3: 2, DEFINED: 1, DOT2: 1, DOT3: 1, EVSTR: 2,
        FLIP2: 1, FLIP3: 1, FOR: 4, LAMBDA: 3, IF: 3, IN: 3, MODULE: 2, NEXT: 1,
        OR: 1, OP_ASGN1: 4, OP_ASGN2: 3, POSTEXE: 3, REDO: 1, REGX: 3, RETURN: 1,
        SCLASS: 3, SPLAT: 1, SUPER: 3, UNDEF: 1, UNLESS: 3, VALIAS: 1, WHEN: 2,
        WHILE: 2, UNTIL: 2, YIELD: 3
      }.freeze

      class << self
        def new(*)
          raise TypeError, "allocator undefined for RubyVM::AbstractSyntaxTree::Node"
        end

        # Makes a node; `spans` holds the node's own span and then its keyword
        # spans, each [first_lineno, first_column, last_lineno, last_column] or nil.
        def build(type, spans, children, node_id, tree)
          node = allocate
          node.send(:setup, type, spans, children, node_id, tree)
          node
        end
      end

      attr_reader :type, :first_lineno, :first_column, :last_lineno, :last_column, :node_id

      # A new array on each call, as CRuby's is.
      def children
        @children.map { |child| child.is_a?(Array) ? child.dup : child }
      end

      def locations
        count = EXTRA_LOCATIONS.fetch(type, 0)
        Array.new(count + 1) do |index|
          span = @spans[index]
          span && Location.build(*span)
        end
      end

      def inspect
        "#<RubyVM::AbstractSyntaxTree::Node:#{type}@#{first_lineno}:#{first_column}-#{last_lineno}:#{last_column}>"
      end

      def script_lines
        @tree&.script_lines&.dup
      end

      def source
        lines = script_lines
        return nil unless lines

        lines = lines[(first_lineno - 1)..(last_lineno - 1)]
        lines[-1] = lines[-1].byteslice(0...last_column)
        lines[0] = lines[0].byteslice(first_column..-1)
        lines.join
      end

      def all_tokens
        @tree&.tokens
      end

      def tokens
        return nil unless all_tokens

        all_tokens.each_with_object([]) do |token, found|
          loc = token.last
          if ([first_lineno, first_column] <=> [loc[0], loc[1]]) <= 0 &&
             ([last_lineno, last_column] <=> [loc[2], loc[3]]) >= 0
            found << token
          end
        end
      end

      private

      def setup(type, spans, children, node_id, tree)
        @type = type
        @spans = spans
        @first_lineno, @first_column, @last_lineno, @last_column = spans.first
        @children = children
        @node_id = node_id
        @tree = tree
      end
    end

    # One parse.y node while the translator builds it. It holds the fields a
    # NODE_* struct has (`head`, `next`, `body`, ...), which parse.y's helpers
    # rewrite in place; #children reads them the way ast.c's node_children does.
    class Draft
      NO_NAME_REST = :NODE_SPECIAL_NO_NAME_REST
      REQUIRED_KEYWORD = :NODE_SPECIAL_REQUIRED_KEYWORD
      NO_REST_KEYWORD = :NODE_SPECIAL_NO_REST_KEYWORD
      EXCESSIVE_COMMA = :NODE_SPECIAL_EXCESSIVE_COMMA

      def initialize(type, first, last, node_id)
        @type = type
        @first_lineno, @first_column = first
        @last_lineno, @last_column = last
        @node_id = node_id
      end

      attr_reader :type, :node_id
      attr_accessor :first_lineno, :first_column, :last_lineno, :last_column
      # parse.y's field names, shared across node types.
      attr_accessor :head, :body, :next, :end_node, :cond, :else_body, :value, :vid,
                    :mid, :recv, :args, :iter, :state, :resq, :exc_var, :ensr,
                    :first, :second, :string, :lit, :cpath, :super_class, :tbl,
                    :ainfo, :pconst, :pre_args, :rest_arg, :post_args, :pre_rest,
                    :post_rest, :kw_rest, :undefs, :aid, :index, :op,
                    :beg_node, :fin_node, :orig, :new_name, :path, :keyword_locations,
                    :tail_cell
      attr_writer :type

      def first_pos = [first_lineno, first_column]
      def last_pos = [last_lineno, last_column]

      def first_pos=(pos)
        @first_lineno, @first_column = pos
      end

      def last_pos=(pos)
        @last_lineno, @last_column = pos
      end

      def children
        case type
        when :BLOCK then block_children
        when :IF, :UNLESS then [cond, body, else_body]
        when :CASE, :CASE3 then [head, body]
        when :CASE2 then [nil, body]
        when :WHEN, :IN then [head, body, self.next]
        when :WHILE, :UNTIL then [cond, body, state]
        when :ITER, :FOR then [iter, body]
        when :FOR_MASGN then [value]
        when :BREAK, :NEXT, :RETURN then [head]
        when :REDO, :RETRY, :ZSUPER, :ZLIST, :SELF, :NIL, :TRUE, :FALSE, :ERRINFO, :ERROR, :UNKNOWN then []
        when :BEGIN, :ONCE, :EVSTR, :POSTEXE, :LAMBDA then [body]
        when :RESCUE then [head, resq, else_body]
        when :RESBODY then [args, exc_var, body, self.next]
        when :ENSURE then [head, ensr]
        when :AND, :OR then logop_children
        when :MASGN then [value, head, args]
        when :LASGN, :DASGN
          [vid, value.equal?(REQUIRED_KEYWORD) ? REQUIRED_KEYWORD : value]
        when :IASGN, :CVASGN, :GASGN then [vid, value]
        when :CDECL then vid ? [vid, value] : [path, path.mid, value]
        when :OP_ASGN1 then [recv, op, index, value]
        when :OP_ASGN2 then [recv, aid, vid, op, value]
        when :OP_ASGN_AND then [head, :"&&", value]
        when :OP_ASGN_OR then [head, :"||", value]
        when :OP_CDECL then [head, op, value]
        when :CALL, :OPCALL, :QCALL, :ATTRASGN then [recv, mid, args]
        when :FCALL then [mid, args]
        when :VCALL, :COLON3 then [mid]
        when :SUPER, :YIELD, :HASH, :SPLAT, :DEFINED then [head]
        when :LIST then list_children
        when :LVAR, :DVAR, :IVAR, :CONST, :CVAR, :GVAR, :NTH_REF, :BACK_REF then [vid]
        when :MATCH, :STR, :XSTR, :INTEGER, :FLOAT, :RATIONAL, :IMAGINARY, :REGX, :SYM,
             :LINE, :FILE, :ENCODING
          [lit]
        when :MATCH2 then args ? [recv, value, args] : [recv, value]
        when :MATCH3 then [recv, value]
        when :DSTR, :DXSTR, :DREGX, :DSYM
          [string, self.next&.head, self.next&.next]
        when :ARGSCAT, :ARGSPUSH, :BLOCK_PASS then [head, body]
        when :DEFN then [mid, body]
        when :DEFS then [recv, mid, body]
        when :ALIAS then [new_name, orig]
        when :VALIAS then [new_name, orig]
        when :UNDEF then [undefs.dup]
        when :CLASS then [cpath, super_class, body]
        when :MODULE then [cpath, body]
        when :SCLASS then [recv, body]
        when :COLON2 then [head, mid]
        when :DOT2, :DOT3, :FLIP2, :FLIP3 then [beg_node, fin_node]
        when :OPT_ARG, :KW_ARG then [body, self.next]
        when :POSTARG then [first, second]
        when :ARGS then args_children
        when :SCOPE then [tbl.dup, args, body]
        when :ARYPTN then [pconst, pre_args, rest_arg, post_args]
        when :FNDPTN then [pconst, pre_rest, args, post_rest]
        when :HSHPTN then [pconst, head, kw_rest]
        else []
        end
      end

      private

      def block_children
        found = []
        node = self
        loop do
          found << node.head
          following = node.next
          break unless following&.type == :BLOCK

          node = following
        end
        found << node.next if node.next
        found
      end

      def list_children
        found = [head]
        node = self
        while node.next&.type == :LIST
          node = node.next
          found << node.head
        end
        found << node.next
        found
      end

      def logop_children
        found = []
        node = self
        loop do
          found << node.first
          break unless node.second&.type == type

          node = node.second
        end
        found << node.second
        found
      end

      def args_children
        info = ainfo
        [
          info[:pre_args_num], info[:pre_init], info[:opt_args], info[:first_post_arg],
          info[:post_args_num], info[:post_init],
          info[:rest_arg],
          info[:no_kwarg] ? false : info[:kw_args],
          info[:no_kwarg] ? false : info[:kw_rest_arg],
          info[:block_arg]
        ]
      end
    end

    class << self
      # The byte offsets of each `#$` and `#@` in text, where parse.y's lexer
      # ends a string content token.
      def variable_marks(text)
        marks = []
        offset = 0
        while (offset = text.byteindex("#", offset))
          following = text.getbyte(offset + 1)
          marks << offset if following == 36 || following == 64
          offset += 1
        end
        marks
      end

      # Parses source the way RubyVM::AbstractSyntaxTree.parse does. A source
      # prism refuses raises SyntaxError unless error_tolerant is set, which
      # answers a tree with ERROR nodes where the source is broken.
      def parse(source, keep_script_lines: false, error_tolerant: false, keep_tokens: false)
        unless source.respond_to?(:to_str)
          raise TypeError, "no implicit conversion of #{source.nil? ? 'nil' : source.class} into String"
        end

        source = source.to_str
        result = prism_parse(source)
        raise SyntaxError, syntax_error_message(source, result) if result.failure? && !error_tolerant

        lines = keep_script_lines ? script_lines_of(source, result) : nil
        tokens = keep_tokens ? Tokens.new(source, result).to_a : nil
        Translator.new(result, source, tree: Tree.new(lines, tokens)).scope
      end

      # Parses the file at path the way RubyVM::AbstractSyntaxTree.parse_file
      # does. Like CRuby, `__FILE__` in the tree is an empty string.
      def parse_file(path, keep_script_lines: false, error_tolerant: false, keep_tokens: false)
        path = path.to_path if path.respond_to?(:to_path)
        source = File.binread(path).force_encoding(Encoding::UTF_8)
        parse(source, keep_script_lines: keep_script_lines, error_tolerant: error_tolerant, keep_tokens: keep_tokens)
      end

      private

      def prism_parse(source)
        Prism.parse(source, version: "4.0")
      rescue ArgumentError
        Prism.parse(source)
      end

      # CRuby's message shape: the complaint, the source line, and a caret.
      def syntax_error_message(source, result)
        error = result.errors.first
        location = error.location
        line = source.byteslice(location.start_offset - location.start_column, source.bytesize)
        line = line.b[/\A[^\n]*/n].force_encoding(source.encoding)
        "syntax error, #{error.message}\n#{line}\n#{' ' * location.start_column}^\n"
      end

      # The lines parse.y read: through an `__END__` line, and no further.
      def script_lines_of(source, result)
        text = source
        if (data = result.data_loc)
          line_end = source.byteindex("\n", data.start_offset)
          text = source.byteslice(0, line_end ? line_end + 1 : source.bytesize)
        end
        text.lines
      end
    end

    # The token list keep_tokens: true answers: parse.y's tokens, rebuilt
    # from prism's lexer. Each token is
    # [id, type, text, [first_lineno, first_column, last_lineno, last_column]].
    # parse.y's lexer states decide some token types, so a few of them
    # (such as which `do` a block opens) come from the tree instead.
    class Tokens
      TYPES = {
        IDENTIFIER: :tIDENTIFIER, CONSTANT: :tCONSTANT, METHOD_NAME: :tFID, LABEL: :tLABEL,
        INSTANCE_VARIABLE: :tIVAR, CLASS_VARIABLE: :tCVAR, GLOBAL_VARIABLE: :tGVAR,
        BACK_REFERENCE: :tBACK_REF, NUMBERED_REFERENCE: :tNTH_REF,
        INTEGER: :tINTEGER, FLOAT: :tFLOAT, INTEGER_RATIONAL: :tRATIONAL, FLOAT_RATIONAL: :tRATIONAL,
        INTEGER_IMAGINARY: :tIMAGINARY, FLOAT_IMAGINARY: :tIMAGINARY,
        INTEGER_RATIONAL_IMAGINARY: :tIMAGINARY, FLOAT_RATIONAL_IMAGINARY: :tIMAGINARY,
        CHARACTER_LITERAL: :tCHAR, STRING_BEGIN: :tSTRING_BEG, STRING_CONTENT: :tSTRING_CONTENT,
        STRING_END: :tSTRING_END, LABEL_END: :tLABEL_END, SYMBOL_BEGIN: :tSYMBEG,
        REGEXP_BEGIN: :tREGEXP_BEG, REGEXP_END: :tREGEXP_END, BACKTICK: :tXSTRING_BEG,
        PERCENT_LOWER_X: :tXSTRING_BEG, PERCENT_LOWER_W: :tQWORDS_BEG, PERCENT_UPPER_W: :tWORDS_BEG,
        PERCENT_LOWER_I: :tQSYMBOLS_BEG, PERCENT_UPPER_I: :tSYMBOLS_BEG, WORDS_SEP: :word_sep,
        HEREDOC_START: :tHEREDOC_BEG, HEREDOC_END: :tHEREDOC_END,
        EMBEXPR_BEGIN: :tSTRING_DBEG, EMBEXPR_END: :tSTRING_DEND, EMBVAR: :tSTRING_DVAR,
        COMMENT: :tCOMMENT, EMBDOC_BEGIN: :tEMBDOC_BEG, EMBDOC_LINE: :tEMBDOC, EMBDOC_END: :tEMBDOC_END,
        NEWLINE: :nl, IGNORED_NEWLINE: :tIGNORED_NL,
        COLON_COLON: :tCOLON2, UCOLON_COLON: :tCOLON3, AMPERSAND_DOT: :tANDDOT,
        EQUAL_GREATER: :tASSOC, MINUS_GREATER: :tLAMBDA, LAMBDA_BEGIN: :tLAMBEG,
        DOT_DOT: :tDOT2, DOT_DOT_DOT: :tDOT3, UDOT_DOT: :tBDOT2, UDOT_DOT_DOT: :tBDOT3,
        AMPERSAND_AMPERSAND: :tANDOP, PIPE_PIPE: :tOROP, EQUAL_EQUAL: :tEQ, EQUAL_EQUAL_EQUAL: :tEQQ,
        BANG_EQUAL: :tNEQ, EQUAL_TILDE: :tMATCH, BANG_TILDE: :tNMATCH, LESS_EQUAL_GREATER: :tCMP,
        GREATER_EQUAL: :tGEQ, LESS_EQUAL: :tLEQ, LESS_LESS: :tLSHFT, GREATER_GREATER: :tRSHFT,
        STAR_STAR: :tPOW, USTAR: :tSTAR, USTAR_STAR: :tDSTAR, UAMPERSAND: :tAMPER,
        UMINUS: :tUMINUS, UMINUS_NUM: :tUMINUS_NUM, UPLUS: :tUPLUS,
        BRACKET_LEFT_ARRAY: :tLBRACK, BRACKET_LEFT_RIGHT: :tAREF, BRACKET_LEFT_RIGHT_EQUAL: :tASET,
        BRACKET_LEFT: :'"["', BRACKET_RIGHT: :'"]"', PARENTHESIS_RIGHT: :'")"', BRACE_RIGHT: :'"}"',
        KEYWORD_IF_MODIFIER: :modifier_if, KEYWORD_UNLESS_MODIFIER: :modifier_unless,
        KEYWORD_WHILE_MODIFIER: :modifier_while, KEYWORD_UNTIL_MODIFIER: :modifier_until,
        KEYWORD_RESCUE_MODIFIER: :modifier_rescue, KEYWORD_DO_LOOP: :keyword_do_cond,
        KEYWORD___FILE__: :keyword__FILE__, KEYWORD___LINE__: :keyword__LINE__,
        KEYWORD___ENCODING__: :keyword__ENCODING__, KEYWORD_BEGIN_UPCASE: :keyword_BEGIN,
        KEYWORD_END_UPCASE: :keyword_END, KEYWORD_DEFINED: :keyword_defined
      }.freeze

      EXPR_BEG_ANY = 1 | 64 | 512 # EXPR_BEG, EXPR_MID, EXPR_CLASS
      EXPR_ARG_ANY = 16 | 32      # EXPR_ARG, EXPR_CMDARG
      EXPR_END_LABEL = 2 | 1024   # EXPR_END, EXPR_LABEL

      # The openings whose content interpolates, so `#$` and `#@` split it.
      OPENINGS = %i[STRING_BEGIN HEREDOC_START SYMBOL_BEGIN REGEXP_BEGIN BACKTICK PERCENT_LOWER_X
                    PERCENT_UPPER_W PERCENT_UPPER_I PERCENT_LOWER_W PERCENT_LOWER_I].freeze

      def initialize(source, result)
        @source = source
        @result = result
      end

      def to_a
        @do_blocks, @lambda_dos = do_keywords
        @tokens = []
        @state = 1 # the lexer state after the previous token, EXPR_BEG at first
        @paren_args = []
        @interpolating = true
        emitted = []
        previous = nil
        reorder_newlines(Prism.lex(@source).value).each do |token, state|
          type = token.type
          break if type == :EOF || type == :__END__

          loc = token.location
          before = preceding(emitted, loc.start_offset)
          gap(before, loc) if before
          insert_emitted(emitted, loc)
          spaced = previous && previous.end_offset < loc.start_offset
          previous = loc
          add(token, name_of(token, spaced), state)
        end
        @tokens.freeze
      end

      private

      def add(token, name, state)
        type = token.type
        text = token.value
        loc = token.location
        @state = state unless type == :PARENTHESIS_RIGHT && @state == 4
        @state = 1 if type == :EMBEXPR_BEGIN || (type == :COMMENT && text.end_with?("\n"))
        @interpolating = interpolating?(text.b) if OPENINGS.include?(type)
        if type == :WORDS_SEP
          separators(loc, text.b)
        elsif type == :STRING_CONTENT && @interpolating && text.b.match?(/.#[$@]/mn)
          split_content(loc, text)
        else
          @tokens << [@tokens.size, name, text.b, span(loc, text)]
        end
      end

      # parse.y's token type, which for a few tokens hangs on the lexer state.
      def name_of(token, spaced)
        type = token.type
        text = token.value
        case type
        when :PARENTHESIS_LEFT, :PARENTHESIS_LEFT_PARENTHESES
          if @state.anybits?(EXPR_BEG_ANY) || @state.allbits?(16 | 2048)
            @paren_args << false
            :tLPAREN
          elsif spaced && (@state.anybits?(EXPR_ARG_ANY) || @state.allbits?(EXPR_END_LABEL))
            @paren_args << true
            :tLPAREN_ARG
          else
            @paren_args << false
            :'"("'
          end
        when :PARENTHESIS_RIGHT
          @state = 4 if @paren_args.pop # EXPR_ENDARG
          :'")"'
        when :BRACE_LEFT
          if @state.anybits?(2048) then :tLBRACE
          elsif @state.anybits?(EXPR_ARG_ANY | 2 | 8) then :'"{"'
          elsif @state.anybits?(4) then :tLBRACE_ARG
          else :tLBRACE
          end
        when :KEYWORD_DO
          if @lambda_dos.include?(token.location.start_offset) then :keyword_do_LAMBDA
          elsif @do_blocks.include?(token.location.start_offset) then :keyword_do_block
          else :keyword_do
          end
        when :BACKTICK
          @tokens.last&.at(1) == :tSYMBEG ? :` : :tXSTRING_BEG
        else
          TYPES[type] ||
            if type.start_with?("KEYWORD_") then :"keyword_#{text}"
            elsif type.end_with?("_EQUAL") && text.end_with?("=") && text.size > 1 then :tOP_ASGN
            else text.b.to_sym
            end
        end
      end

      def interpolating?(opening)
        !(opening.start_with?("'") || opening.match?(/\A%[qwis]/n) || opening.match?(/\A<<[-~]?'/n))
      end

      # parse.y splits a word separator at each newline.
      def separators(loc, text)
        line = loc.start_line
        column = loc.start_column
        text.scan(/\n|[^\n]+/n) do |piece|
          @tokens << [@tokens.size, :word_sep, piece, [line, column, line, column + piece.bytesize]]
          if piece == "\n"
            line += 1
            column = 0
          else
            column += piece.bytesize
          end
        end
      end


      # parse.y's lexer reads the comment lines right after a newline before
      # it answers the newline, so their tokens come first.
      def reorder_newlines(lexed)
        ordered = []
        index = 0
        while index < lexed.size
          token = lexed[index]
          unless token[0].type == :NEWLINE
            ordered << token
            index += 1
            next
          end

          line = token[0].location.start_line
          following = index + 1
          while (comment = lexed[following]) && comment[0].type == :COMMENT &&
                comment[0].location.start_line == line + 1
            ordered << comment
            line += 1
            following += 1
          end
          ordered << token
          index = following
        end
        ordered
      end

      # parse.y reports a token that ends its line on that line.
      def span(loc, text)
        text = text.b
        if text.end_with?("\n") && loc.end_line > loc.start_line
          last_line = loc.end_line - 1
          last_column = text.count("\n") == 1 ? loc.start_column + text.bytesize : text.b[/[^\n]*\n\z/n].bytesize
          [loc.start_line, loc.start_column, last_line, last_column]
        else
          [loc.start_line, loc.start_column, loc.end_line, loc.end_column]
        end
      end

      # parse.y ends a content token before each `#$` and `#@`.
      def split_content(loc, text)
        raw = text.b
        cuts = AST.variable_marks(raw).reject { |at| at.zero? || raw.byteslice(0, at)[/\\*\z/n].size.odd? }
        line = loc.start_line
        column = loc.start_column
        [0, *cuts, raw.bytesize].each_cons(2) do |from, to|
          piece = raw.byteslice(from, to - from)
          lines = piece.count("\n")
          last_line = line + lines
          last_column = lines.zero? ? column + piece.bytesize : piece[/[^\n]*\z/n].bytesize
          @tokens << [@tokens.size, :tSTRING_CONTENT, piece, [line, column, last_line, last_column]]
          line = last_line
          column = last_column
        end
      end

      # The emitted token that starts last before offset: the spaces after it
      # are the gap before the token at offset.
      def preceding(emitted, offset)
        index = emitted.bsearch_index { |loc| loc.start_offset >= offset } || emitted.size
        index.zero? ? nil : emitted[index - 1]
      end

      def insert_emitted(emitted, loc)
        index = emitted.bsearch_index { |other| other.start_offset > loc.start_offset } || emitted.size
        emitted.insert(index, loc)
      end

      # The spaces between two tokens on one line are a tSP token; an escaped
      # newline is one of its own.
      def gap(previous, loc)
        from = previous.end_offset
        to = loc.start_offset
        return unless from < to

        text = @source.byteslice(from, to - from).b
        return unless text.match?(/\A(?:[ \t\f\v\r\n]|\\\r?\n)*\z/n)

        line = previous.end_line
        column = previous.end_column
        text.scan(/\\\r?\n|[ \t\f\v\r]+|\n/) do |piece|
          if piece == "\n"
            line += 1
            column = 0
            next
          end
          @tokens << [@tokens.size, :tSP, piece, [line, column, line, column + piece.bytesize]]
          if piece.end_with?("\n")
            line += 1
            column = 0
          else
            column += piece.bytesize
          end
        end
      end

      # The `do` of a command's block (keyword_do_block) and of a lambda.
      def do_keywords
        do_blocks = []
        lambda_dos = []
        stack = [@result.value]
        until stack.empty?
          node = stack.pop
          case node
          when Prism::CallNode
            block = node.block
            if block.is_a?(Prism::BlockNode) && node.arguments && node.opening_loc.nil? &&
               block.opening_loc.slice == "do"
              do_blocks << block.opening_loc.start_offset
            end
          when Prism::LambdaNode
            lambda_dos << node.opening_loc.start_offset if node.opening_loc.slice == "do"
          end
          stack.concat(node.compact_child_nodes)
        end
        [do_blocks, lambda_dos]
      end
    end
  end
end

module Ze0
  module AST
    # Rebuilds parse.y's tree from prism's. Each visit method answers the
    # Draft that parse.y's grammar action builds for the same source, with
    # the span that rule gives it; #scope turns the drafts into Nodes.
    #
    # Positions are [line, column] pairs. Most spans come from prism's
    # locations, but parse.y also puts nodes where no prism node is: an
    # empty statement list is a zero-width `BEGIN nil` at the end of the
    # grammar symbol before it, and a list of statements runs through its
    # terminators. The translator scans the source for those terminators
    # (`;` and the newlines parse.y's lexer answers as tokens) itself.
    class Translator < Prism::BasicVisitor
      # A prism node kind without a mapping degrades to an UNKNOWN leaf.
      Prism::Visitor.instance_methods(false).each do |name|
        next unless name.to_s.start_with?("visit_")

        define_method(name) { |node| unknown(node) }
      end

      # A terminator token (`;` or a significant newline) and the offset after it.
      Term = Struct.new(:first, :last, :offset)

      NL = 10
      SPACE_BYTES = [32, 9, 13, 12, 11].freeze
      BINARY_OPERATORS = %i[+ - * / % ** | ^ & <=> > >= < <= == === != !~ << >>].freeze
      UNARY_OPERATORS = %i[-@ +@ ! ~].freeze

      # result: the Prism::ParseResult of the source. The source itself is
      # read back from the result; `file` is the value `__FILE__` answers,
      # and `tree` holds what every node shares.
      def initialize(result, source = nil, file: "", tree: nil)
        super()
        @result = result
        @src = result.source.source.b
        @size = @src.bytesize
        @bom = @src.start_with?("\xEF\xBB\xBF".b) ? 3 : 0
        @offsets = result.source.offsets
        @start_line = result.source.start_line
        @file = file
        @tree = tree
        @next_id = -1
        @scopes = []
        @begin_blocks = nil
        @heredoc_bodies = {}
        @semicolons = 0
      end

      # The SCOPE node for the whole program.
      def scope
        publish(visit(@result.value), {})
      end

      # Turns the drafts into RubyVM::AbstractSyntaxTree nodes.
      def publish(value, done)
        case value
        when Draft
          done[value.object_id] ||= begin
            children = value.children.map { |child| publish(child, done) }
            spans = [[value.first_lineno, value.first_column, value.last_lineno, value.last_column],
                     *Array(value.keyword_locations)]
            Node.build(value.type, spans, children, value.node_id, @tree)
          end
        when Array
          value.map { |item| publish(item, done) }
        else
          value
        end
      end

      # ---------------------------------------------------------------
      # Positions

      def line_index(offset)
        (@offsets.bsearch_index { |start| start > offset } || @offsets.size) - 1
      end

      def pos(offset)
        index = line_index(offset)
        [index + @start_line, offset - line_start(index)]
      end

      # parse.y's lexer skips a byte order mark, so the first line's columns
      # start after it.
      def line_start(index)
        index.zero? ? @bom : @offsets[index]
      end

      # The position of an end offset. An end just past a newline stays on
      # the newline's line, a column past its last character.
      def end_pos(offset)
        return pos(offset) unless offset.positive? && @src.getbyte(offset - 1) == NL

        index = line_index(offset - 1)
        [index + @start_line, offset - line_start(index)]
      end

      def loc_of(thing)
        thing.is_a?(Prism::Location) || thing.is_a?(Piece) ? thing : thing.location
      end

      def first_of(thing) = pos(loc_of(thing).start_offset)
      def last_of(thing) = end_pos(loc_of(thing).end_offset)
      def start_offset(thing) = loc_of(thing).start_offset
      def end_offset(thing) = loc_of(thing).end_offset

      def byte(offset) = @src.getbyte(offset)

      # ---------------------------------------------------------------
      # Node construction

      def mk(type, first, last, **fields)
        node = Draft.new(type, first, last, @next_id += 1)
        fields.each { |name, value| node.public_send(:"#{name}=", value) }
        node
      end

      def span(type, thing, **fields)
        mk(type, first_of(thing), last_of(thing), **fields)
      end

      # A keyword span for Node#locations, or nil when the source has none.
      def kw(thing)
        return nil unless thing

        [*first_of(thing), *last_of(thing)]
      end

      # `then`: a terminator, the `then` keyword, or both. Answers its span.
      def then_span(offset, keyword, newline: true)
        semicolons = @semicolons
        term = scan_terms(offset, newline).first
        @semicolons = semicolons
        term = nil if term && keyword && term.offset > start_offset(keyword)
        return [*term.first, *last_of(keyword)] if term && keyword
        return kw(keyword) if keyword

        term && [*term.first, *term.last]
      end

      # rparen and rbracket: `'\n'? ')'` starts where the token before it ends.
      def closing_span(before, closing)
        return nil unless closing

        [*last_of(before), *last_of(closing)]
      end

      def unknown(node)
        span(:UNKNOWN, node)
      end

      def begin_nil(at)
        mk(:BEGIN, at, at, body: nil)
      end

      def nil_at(at)
        mk(:NIL, at, at)
      end

      # ---------------------------------------------------------------
      # parse.y's list and block helpers

      def new_list(item, first = item.first_pos, last = item.last_pos)
        mk(:LIST, first, last, head: item)
      end

      def new_block(item, first = item.first_pos, last = item.last_pos)
        block = mk(:BLOCK, first, last, head: item)
        block.end_node = block
        block
      end

      # The last cell of a list. The head caches it, as parse.y's nd_end
      # does, so long literals append in constant time.
      def list_last(list)
        node = list.tail_cell || list
        node = node.next while node.next
        list.tail_cell = node
      end

      def list_append(list, item)
        return new_list(item) unless list

        cell = new_list(item)
        list_last(list).next = cell
        list.tail_cell = cell
        list.last_pos = item.last_pos
        list
      end

      def list_concat(head, tail)
        list_last(head).next = tail
        head.tail_cell = list_last(tail)
        head.last_pos = tail.last_pos
        head
      end

      def block_append(head, tail)
        return head unless tail
        return tail unless head

        if head.type == :BLOCK
          last = head.end_node
        else
          head = last = new_block(head)
        end
        tail = new_block(tail) unless tail.type == :BLOCK
        last.next = tail
        head.end_node = tail.end_node
        head.last_pos = tail.last_pos
        head
      end

      def remove_begin(node)
        node = node.body while node && node.type == :BEGIN && node.body
        node
      end

      alias newline_node remove_begin

      def splat_array(node)
        node = node.head if node.type == :SPLAT
        node.type == :LIST ? node : nil
      end

      def arg_append(node1, node2, first, last)
        return new_list(node2) unless node1

        case node1.type
        when :LIST
          return list_append(node1, node2)
        when :BLOCK_PASS
          node1.head = arg_append(node1.head, node2, first, last)
          node1.last_pos = node1.head.last_pos
          return node1
        when :ARGSPUSH
          node1.body = list_append(new_list(node1.body), node2)
          node1.last_pos = node1.body.last_pos
          node1.type = :ARGSCAT
          return node1
        when :ARGSCAT
          if node1.body.type == :LIST
            node1.body = list_append(node1.body, node2)
            node1.last_pos = node1.body.last_pos
            return node1
          end
        end
        mk(:ARGSPUSH, first, last, head: node1, body: node2)
      end

      def arg_concat(node1, node2, first, last)
        return node1 unless node2

        case node1.type
        when :BLOCK_PASS
          if node1.head
            node1.head = arg_concat(node1.head, node2, first, last)
          else
            node1.head = new_list(node2, first, last)
          end
          return node1
        when :ARGSPUSH
          if node2.type == :LIST
            node1.body = list_concat(new_list(node1.body, first, last), node2)
            node1.type = :ARGSCAT
            return node1
          end
        when :ARGSCAT
          if node2.type == :LIST && node1.body.type == :LIST
            node1.body = list_concat(node1.body, node2)
            return node1
          end
        end
        mk(:ARGSCAT, first, last, head: node1, body: node2)
      end

      def rest_arg_append(args, rest, first, last)
        if rest.type == :LIST && (list = splat_array(args))
          return list_concat(list, rest)
        end

        arg_concat(args, rest, first, last)
      end

      def last_arg_append(args, last_arg, first, last)
        if (list = splat_array(args))
          return list_append(list, last_arg)
        end

        arg_append(args, last_arg, first, last)
      end

      def arg_blk_pass(node1, block_pass)
        return node1 unless block_pass
        return block_pass unless node1

        block_pass.head = node1
        block_pass.first_pos = node1.first_pos
        block_pass
      end

      def logop(type, left, right, first, last, operator = nil)
        if left && left.type == type
          node = left
          node = node.second while node.second&.type == type
          node.second = mk(type, first, last, first: node.second, second: right, keyword_locations: [kw(operator)])
          left.last_pos = last
          return left
        end
        mk(type, first, last, first: left, second: right, keyword_locations: [kw(operator)])
      end

      # parse.y's cond0: a condition turns a regexp literal into a match
      # against $_ and a range into a flip-flop. The nodes it adds span
      # `loc`, the span the calling rule passes.
      def cond0(node, loc, top = true)
        return nil unless node

        case node.type
        when :BEGIN
          node.body = cond0(node.body, loc, top)
        when :REGX
          node.type = :MATCH
        when :DREGX
          return mk(:MATCH2, *loc, recv: node, value: mk(:GVAR, *loc, vid: :$_))
        when :BLOCK
          last = node.end_node
          last.head = cond0(last.head, loc, top && node.equal?(last))
        when :AND, :OR
          node.first = cond0(node.first, loc, true)
          node.second = cond0(node.second, loc, true)
        when :DOT2, :DOT3
          if top
            node.beg_node = range_op(node.beg_node, loc)
            node.fin_node = range_op(node.fin_node, loc)
            node.type = node.type == :DOT2 ? :FLIP2 : :FLIP3
          end
        end
        node
      end

      def range_op(node, loc)
        return nil unless node

        if node.type == :INTEGER
          line = mk(:GVAR, *loc, vid: :$.)
          return mk(:CALL, *loc, recv: node, mid: :==, args: new_list(line, *loc))
        end
        cond0(node, loc, true)
      end

      # parse.y's reduce_nodes, applied to a method body.
      def reduce_nodes(node)
        return nil unless node

        reduce_tail(node) { |replacement| node = replacement }
        node
      end

      # Walks the value-producing tail of a body and drops a trailing nil or
      # a BEGIN wrapper, the way reduce_nodes does. The block stores the
      # replacement for the slot that held the node.
      def reduce_tail(node, &store)
        while node
          case node.type
          when :NIL
            store.call(nil)
            return
          when :BEGIN
            node = node.body
            store.call(node)
            next
          when :BLOCK
            last = node.end_node
            node = last.head
            store = ->(value) { last.head = value }
          when :IF, :UNLESS
            owner = node
            if !owner.body
              return unless owner.else_body

              node = owner.else_body
              store = ->(value) { owner.else_body = value }
            elsif !owner.else_body
              node = owner.body
              store = ->(value) { owner.body = value }
            else
              reduce_tail(owner.body) { |value| owner.body = value }
              node = owner.else_body
              store = ->(value) { owner.else_body = value }
            end
          when :CASE
            owner = node
            node = owner.body
            store = ->(value) { owner.body = value }
          when :WHEN
            owner = node
            if !owner.body
              unless owner.next
                store.call(nil)
                return
              end
              node = owner.next
              store = ->(value) { owner.next = value }
            elsif !owner.next
              node = owner.body
              store = ->(value) { owner.body = value }
            else
              reduce_tail(owner.body) { |value| owner.body = value }
              node = owner.next
              store = ->(value) { owner.next = value }
            end
          when :ENSURE
            owner = node
            node = owner.head
            store = ->(value) { owner.head = value }
          when :RESCUE
            owner = node
            if owner.else_body
              node = owner.resq
              store = ->(value) { owner.resq = value }
            elsif !owner.head
              unless owner.resq
                store.call(nil)
                return
              end
              node = owner.resq
              store = ->(value) { owner.resq = value }
            elsif !owner.resq
              node = owner.head
              store = ->(value) { owner.head = value }
            else
              reduce_tail(owner.head) { |value| owner.head = value }
              node = owner.resq
              store = ->(value) { owner.resq = value }
            end
          else
            return
          end
        end
      end

      # ---------------------------------------------------------------
      # Terminators

      # Scans the terminators after offset: `;` tokens and, while a newline
      # is a token there, the newline. Stops at anything else.
      def scan_terms(offset, newline)
        terms = []
        while offset < @size
          if (skip = @heredoc_bodies[offset])
            offset = skip
            next
          end
          c = byte(offset)
          if SPACE_BYTES.include?(c)
            offset += 1
          elsif c == 92 && byte(offset + 1) == NL
            offset += 2
          elsif c == 92 && byte(offset + 1) == 13 && byte(offset + 2) == NL
            offset += 3
          elsif c == NL
            if newline
              # A carriage return before the newline reads as part of it.
              at = pos(offset.positive? && byte(offset - 1) == 13 ? offset - 1 : offset)
              terms << Term.new(at, at, offset + 1)
              newline = false
            end
            offset = skip_embedded_document(offset + 1)
          elsif c == 35 # '#'
            if newline
              at, offset = comment_term(offset)
              terms << Term.new(at, at, offset)
              newline = false
            else
              line_end = @src.byteindex("\n", offset)
              offset = line_end ? skip_embedded_document(line_end + 1) : @size
            end
          elsif c == 59 # ';'
            @semicolons += 1
            terms << Term.new(pos(offset), pos(offset + 1), offset + 1)
            newline = false
            offset += 1
          else
            break
          end
        end
        terms
      end

      def skip_embedded_document(offset)
        return offset unless @src.byteslice(offset, 6) == "=begin"

        finish = @src.byteindex(/^=end\b[^\n]*\n?/, offset)
        return offset unless finish

        line_end = @src.byteindex("\n", finish)
        line_end ? line_end + 1 : @size
      end

      # The position of a newline term that follows a comment. parse.y's
      # lexer keeps reading comment-only lines; the token sits past the end
      # of the last one, or at that comment's start at the end of input.
      def comment_term(offset)
        comment = offset
        loop do
          line_end = @src.byteindex("\n", comment)
          return [pos(comment), @size] unless line_end

          following = line_end + 1
          following = @heredoc_bodies[following] while @heredoc_bodies[following]
          return [pos(comment), following] if following >= @size

          scan = following
          scan += 1 while SPACE_BYTES.include?(byte(scan))
          # Spaces before the end of input are a token of their own.
          return [pos(following), @size] if scan >= @size

          if byte(scan) == 35
            comment = scan
            next
          end
          return [end_pos(line_end + 1), following]
        end
      end

      # ---------------------------------------------------------------
      # Statements

      # compstmt: `stmts terms?`. The statements come from prism's
      # StatementsNode (or an Array of nodes); `prev` and `offset` locate the
      # grammar symbol before them, `newline` says whether a newline is a
      # token right after it, and `absorb` says whether the rule before the
      # body takes one terminator itself (`then`, `do`, a def's arglist).
      # Answers [node, first, last, offset].
      def compstmt(statements, prev, offset, newline: false, absorb: false)
        body = statements.is_a?(Array) ? statements : (statements&.body || [])
        terms = scan_terms(offset, newline)
        if absorb && !terms.empty?
          term = terms.shift
          prev = term.last
          offset = term.offset
        end
        if !terms.empty?
          offset = terms.last.offset
        end

        node = nil
        first = prev
        last = prev
        if body.empty? || !terms.empty?
          node = begin_nil(prev)
          last = terms.last.last unless terms.empty?
        else
          first = first_of(body.first)
        end
        body.each do |statement|
          node = block_append(node, newline_node(visit(statement)))
          last = last_of(statement)
          offset = end_offset(statement)
          trailing = scan_terms(offset, true)
          unless trailing.empty?
            last = trailing.last.last
            offset = trailing.last.offset
          end
        end
        [node, first, last, offset]
      end

      # ---------------------------------------------------------------
      # Scopes and local tables

      # Runs the block inside a local variable scope: :top, :def, :class, or
      # :block. Inside a block every local reads as DVAR and assigns as DASGN.
      def push_scope(kind)
        @scopes.push(kind)
        yield
      ensure
        @scopes.pop
      end

      def in_block? = @scopes.last == :block

      # The local table parse.y builds: parameters in parse.y's order (with
      # internal ids as nil), then the variables the body assigns.
      def local_table(locals, parameters)
        table = []
        destructured = []
        if parameters.is_a?(Prism::ParametersNode)
          parameters.requireds.each { |param| table_param(table, destructured, param) }
          parameters.optionals.each { |param| table << param.name }
          case (rest = parameters.rest)
          when Prism::RestParameterNode then table << (rest.name || :*)
          end
          parameters.posts.each { |param| table_param(table, destructured, param) }
          keywords = parameters.keywords
          required = keywords.select { |param| param.is_a?(Prism::RequiredKeywordParameterNode) }
          optional = keywords - required
          table.concat(required.map(&:name))
          table.concat(optional.map(&:name))
          table << nil unless keywords.empty?
          case (kwrest = parameters.keyword_rest)
          when Prism::KeywordRestParameterNode then table << (kwrest.name || :**)
          when Prism::ForwardingParameterNode then table.push(:*, :**, :&, :"...")
          end
          if (block = parameters.block)
            table << (block.name || :&)
          end
        end
        destructured.each { |name| table << name unless table.include?(name) }
        locals.each { |name| table << name unless table.include?(name) }
        table
      end

      def table_param(table, destructured, param)
        case param
        when Prism::RequiredParameterNode
          table << param.name
        when Prism::MultiTargetNode
          table << nil
          collect_targets(param, destructured)
        end
      end

      def collect_targets(target, names)
        (target.lefts + [target.rest].compact + target.rights).each do |item|
          case item
          when Prism::RequiredParameterNode then names << item.name
          when Prism::SplatNode
            names << item.expression.name if item.expression
          when Prism::MultiTargetNode then collect_targets(item, names)
          end
        end
      end

      # ---------------------------------------------------------------
      # Program

      def visit_program_node(node)
        push_scope(:top) do
          @begin_blocks = nil
          body, _first, last, = compstmt(node.statements, [@start_line, 0], 0)
          body = block_append(@begin_blocks, body)
          mk(:SCOPE, [@start_line, 0], last, tbl: node.locals, args: nil, body: body)
        end
      end

      def visit_statements_node(node)
        body, = compstmt(node, first_of(node), start_offset(node))
        body
      end

      # ---------------------------------------------------------------
      # Literals

      def visit_integer_node(node) = span(:INTEGER, node, lit: node.value)
      def visit_float_node(node) = span(:FLOAT, node, lit: node.value)
      def visit_rational_node(node) = span(:RATIONAL, node, lit: node.value)
      def visit_imaginary_node(node) = span(:IMAGINARY, node, lit: node.value)
      def visit_nil_node(node) = span(:NIL, node)
      def visit_true_node(node) = span(:TRUE, node)
      def visit_false_node(node) = span(:FALSE, node)
      def visit_self_node(node) = span(:SELF, node)
      def visit_source_line_node(node) = span(:LINE, node, lit: node.location.start_line)
      def visit_source_file_node(node) = span(:FILE, node, lit: @file.dup)

      def visit_source_encoding_node(node)
        span(:ENCODING, node, lit: @result.source.encoding)
      end

      def visit_symbol_node(node)
        span(:SYM, node, lit: string_value(node).to_sym)
      end

      def visit_regular_expression_node(node) = plain_regexp(node)
      def visit_match_last_line_node(node) = plain_regexp(node)

      # A regexp without interpolation, unless a `#$` or `#@` splits its content.
      def plain_regexp(node)
        content = node.content_loc
        pieces = content_pieces(content.start_offset, content.end_offset, node.unescaped)
        if pieces.size == 1
          return span(:REGX, node, lit: regexp_of(node, node.unescaped),
                                   keyword_locations: [kw(node.opening_loc), kw(content), kw(node.closing_loc)])
        end

        new_regexp(node, pieces)
      end

      def regexp_of(node, source)
        source = source.dup
        if node.euc_jp?
          source.force_encoding(Encoding::EUC_JP)
        elsif node.windows_31j?
          source.force_encoding(Encoding::Windows_31J)
        elsif node.utf_8?
          source.force_encoding(Encoding::UTF_8)
        end
        options = 0
        options |= Regexp::IGNORECASE if node.ignore_case?
        options |= Regexp::EXTENDED if node.extended?
        options |= Regexp::MULTILINE if node.multi_line?
        options |= Regexp::NOENCODING if node.ascii_8bit?
        source = source.dup.force_encoding(Encoding::BINARY) if node.ascii_8bit?
        Regexp.new(source, options)
      rescue RegexpError
        nil
      end

      # ---------------------------------------------------------------
      # Strings

      # The literal's value, in the encoding its escapes force.
      def string_value(node)
        value = node.unescaped.dup
        if node.respond_to?(:forced_utf8_encoding?) && node.forced_utf8_encoding?
          value.force_encoding(Encoding::UTF_8)
        elsif node.respond_to?(:forced_binary_encoding?) && node.forced_binary_encoding?
          value.force_encoding(Encoding::BINARY)
        elsif node.respond_to?(:forced_us_ascii_encoding?) && node.forced_us_ascii_encoding?
          value.force_encoding(Encoding::US_ASCII)
        end
        value
      end

      def visit_string_node(node)
        heredoc_body(node)
        mk(:STR, first_of(node), last_of(node), lit: string_value(node))
      end

      # Records where a heredoc's body lines sit, so terminator scans skip them.
      def heredoc_body(node)
        opening = node.opening_loc
        return unless opening && @src.byteslice(opening.start_offset, 2) == "<<"

        closing = node.closing_loc
        body_start =
          if node.respond_to?(:parts)
            node.parts.empty? ? closing.start_offset : start_offset(node.parts.first)
          else
            node.content_loc.start_offset
          end
        @heredoc_bodies[body_start] = closing.end_offset if closing
      end

      # `strings: string` over a literal or a run of adjacent literals.
      def visit_interpolated_string_node(node)
        first = first_of(node)
        last = last_of(node)
        if node.opening_loc.nil? && node.parts.all? { |part| literal_piece?(part) }
          head = nil
          node.parts.each do |part|
            piece = string1(part)
            head = literal_concat(head, piece, first, last_of(part))
          end
        else
          head = string1(node)
        end
        head ? evstr2dstr(head) : mk(:STR, first, last, lit: +"")
      end

      def literal_piece?(part)
        (part.is_a?(Prism::StringNode) || part.is_a?(Prism::InterpolatedStringNode)) && part.opening_loc
      end

      # string1: `tSTRING_BEG string_contents tSTRING_END`, spanning the literal.
      def string1(node)
        heredoc_body(node)
        contents =
          if node.is_a?(Prism::StringNode)
            node.unescaped.empty? && node.content_loc.length.zero? ? nil : mk(:STR, first_of(node), last_of(node), lit: string_value(node))
          else
            string_contents(node.parts, node)
          end
        if contents
          contents.first_pos = first_of(node)
          contents.last_pos = last_of(node)
        end
        contents
      end

      def visit_interpolated_symbol_node(node)
        contents = string_contents(node.parts, node)
        dsym_node(contents, first_of(node), last_of(node))
      end

      def visit_x_string_node(node)
        heredoc_body(node)
        mk(:XSTR, first_of(node), last_of(node), lit: string_value(node))
      end

      # new_xstring
      def visit_interpolated_x_string_node(node)
        heredoc_body(node)
        contents = string_contents(node.parts, node)
        first = first_of(node)
        last = last_of(node)
        return mk(:XSTR, first, last, lit: +"") unless contents

        case contents.type
        when :STR then contents.type = :XSTR
        when :DSTR then contents.type = :DXSTR
        else return mk(:DXSTR, first, last, string: nil, next: new_list(contents, first, last))
        end
        contents.first_pos = first
        contents.last_pos = last
        contents
      end

      def visit_interpolated_regular_expression_node(node) = new_regexp(node)
      def visit_interpolated_match_last_line_node(node) = new_regexp(node)

      # new_regexp over regexp_contents.
      def new_regexp(node, parts = node.parts)
        first = first_of(node)
        last = last_of(node)
        contents = regexp_contents(parts, node)
        case contents&.type
        when nil
          at = last_of(node.opening_loc)
          return mk(:REGX, first, last, lit: regexp_of(node, ""),
                                        keyword_locations: [kw(node.opening_loc), [*at, *at], kw(node.closing_loc)])
        when :STR
          return mk(:REGX, first, last, lit: regexp_of(node, contents.lit),
                                        keyword_locations: [kw(node.opening_loc), [*contents.first_pos, *contents.last_pos],
                                                            kw(node.closing_loc)])
        when :DSTR
          nil
        else
          contents = mk(:DSTR, first, last, string: +"", next: new_list(contents, first, last))
        end
        contents.type = :DREGX
        contents.first_pos = first
        contents.last_pos = last
        return mk(:ONCE, first, last, body: contents) if node.once?

        contents
      end

      def regexp_contents(parts, literal)
        head = nil
        first = nil
        parts = pieces_of(parts)
        parts.each_with_index do |part, index|
          tail = string_content(part, literal, parts, index)
          next unless tail

          first ||= tail.first_pos
          if !head
            head = tail
          else
            head = case head.type
                   when :STR then str2dstr(head)
                   when :DSTR then head
                   else list_append(mk(:DSTR, first, tail.last_pos, string: nil), head)
                   end
            head = list_append(head, tail)
          end
        end
        head
      end

      def dsym_node(node, first, last)
        return mk(:SYM, first, last, lit: :"") unless node

        case node.type
        when :DSTR
          node.type = :DSYM
          node.first_pos = first
          node.last_pos = last
          node
        when :STR
          mk(:SYM, first, last, lit: node.lit.to_sym)
        else
          mk(:DSYM, first, last, string: nil, next: new_list(node, first, last))
        end
      end

      # string_contents: literal_concat over the pieces of one literal.
      def string_contents(parts, literal)
        dedent = dedent_heredoc?(literal)
        head = nil
        first = nil
        parts = pieces_of(parts)
        parts.each_with_index do |part, index|
          tail = string_content(part, literal, parts, index)
          next unless tail

          first ||= tail.first_pos
          head = literal_concat(head, tail, first, tail.last_pos, dedent: dedent)
        end
        dedent ? heredoc_dedent(head) : head
      end

      # A squiggly heredoc whose lines share some indentation. parse.y lexes
      # such a heredoc line by line and joins the pieces after dedenting;
      # with no common indentation it lexes it like any other heredoc.
      def dedent_heredoc?(literal)
        opening = literal.respond_to?(:opening_loc) ? literal.opening_loc : nil
        return false unless opening && @src.byteslice(opening.start_offset, 3) == "<<~"

        @dedent_heredocs ||= {}
        @dedent_heredocs.fetch(opening.start_offset) do
          @dedent_heredocs[opening.start_offset] = heredoc_indent(literal).positive?
        end
      end

      def heredoc_indent(literal)
        closing = literal.closing_loc
        return 0 unless closing

        parts = literal.respond_to?(:parts) ? literal.parts : []
        offset = parts.empty? ? closing.start_offset : start_offset(parts.first)
        offset = line_start(line_index(offset))
        indent = nil
        while offset < closing.start_offset
          column = 0
          scan = offset
          while [32, 9].include?(byte(scan))
            column = byte(scan) == 9 ? (column / 8 + 1) * 8 : column + 1
            scan += 1
          end
          blank = scan >= closing.start_offset || byte(scan) == NL || (byte(scan) == 13 && byte(scan + 1) == NL)
          indent = column if !blank && (indent.nil? || column < indent)
          line_end = @src.byteindex("\n", scan)
          break unless line_end

          offset = line_end + 1
        end
        indent || 0
      end

      # heredoc_dedent: joins each run of adjacent string pieces into its first.
      def heredoc_dedent(root)
        return root unless root

        prev_node = node = str_node = root
        prev_lit = nil
        while str_node
          jump = false
          if prev_lit.nil?
            prev_lit = str_node
          else
            append_literal(prev_lit, str_node.type == :STR ? str_node.lit : (str_node.string || ""))
            node = prev_node.next = node.next
            if node.nil?
              if prev_node.type == :DSTR
                prev_node.type = :STR
                prev_node.lit = prev_node.string
              end
              break
            end
            jump = true
          end
          str_node = nil
          loop do
            unless jump
              break unless %i[LIST DSTR].include?(node.type)

              prev_node = node
              node = node.next
              break unless node
            end
            jump = false
            break unless node.type == :LIST

            str_node = node.head
            next unless str_node
            break if %i[STR DSTR].include?(str_node.type)

            prev_lit = nil
            str_node = nil
          end
        end
        root.tail_cell = nil
        root
      end

      # One piece of a literal. A content token's span follows parse.y's
      # lexer: in a squiggly heredoc each line is a token; elsewhere a token
      # that crosses lines starts at its last line, and the token that ends
      # a heredoc sits at the end of the heredoc's opening.
      def string_content(part, literal, parts, index)
        case part
        when Piece
          mk(:STR, *content_span(part, literal, parts, index), lit: part.value)
        when Prism::InterpolatedStringNode
          string_contents(part.parts, part)
        else
          visit(part)
        end
      end

      # A content token of a literal: a prism string piece, or the part of
      # one that parse.y's lexer reads as a token of its own.
      Piece = Struct.new(:start_offset, :end_offset, :value, :split)

      # parse.y ends a content token before each `#$` and `#@`, even when no
      # variable follows, so those split prism's pieces.
      def pieces_of(parts)
        parts.flat_map do |part|
          next [part] unless part.is_a?(Prism::StringNode)

          content_pieces(start_offset(part), end_offset(part), string_value(part))
        end
      end

      def content_pieces(start, finish, value)
        raw = @src.byteslice(start, finish - start)
        marks = AST.variable_marks(raw)
        cuts = marks.reject { |at| at.zero? || raw.byteslice(0, at)[/\\*\z/n].size.odd? }
        values = AST.variable_marks(value.b)
        return [Piece.new(start, finish, value, false)] if cuts.empty? || values.size != marks.size

        value_cuts = cuts.map { |at| values[marks.index(at)] }
        bounds = [0, *cuts, raw.bytesize]
        value_bounds = [0, *value_cuts, value.bytesize]
        bounds.each_cons(2).with_index.map do |(from, to), index|
          text = value.byteslice(value_bounds[index], value_bounds[index + 1] - value_bounds[index])
          Piece.new(start + from, start + to, text, index.positive?)
        end
      end

      def content_span(part, literal, parts, index)
        opening = literal.respond_to?(:opening_loc) ? literal.opening_loc : nil
        heredoc = opening && @src.byteslice(opening.start_offset, 2) == "<<"
        first = first_of(part)
        if heredoc && dedent_heredoc?(literal)
          # Each line is a token; a piece that crosses lines keeps its first line's span.
          line_end = @src.byteindex("\n", start_offset(part))
          finish = end_offset(part)
          finish = line_end + 1 if line_end && line_end + 1 < finish
          return [first, end_pos(finish)]
        end

        # prism splits a squiggly heredoc into lines even when parse.y lexes
        # it whole, so a run of adjacent pieces is one token.
        run_end = index
        run_end += 1 while parts[run_end + 1].is_a?(Piece) && !parts[run_end + 1].split
        if heredoc && run_end == parts.size - 1
          at = last_of(opening)
          return [at, at]
        end

        last = pos(end_offset(parts[run_end]))
        first = [last[0], 0] unless first[0] == last[0]
        [first, last]
      end

      def str2dstr(node)
        mk(:DSTR, node.first_pos, node.last_pos, string: node.lit, next: nil)
      end

      def evstr2dstr(node)
        return node unless node.type == :EVSTR

        new_dstr(node, node.first_pos, node.last_pos)
      end

      def new_dstr(node, first, last)
        list_append(mk(:DSTR, first, last, string: +""), node)
      end

      # The node whose string a following literal joins: the DSTR itself,
      # or its last piece when that is a STR.
      def string_literal_head(head)
        return nil unless head.type == :DSTR
        return head unless head.next

        last = list_last(head.next).head
        last&.type == :STR ? last : nil
      end

      def append_literal(holder, text)
        if holder.type == :STR
          holder.lit = holder.lit + text
        else
          holder.string = (holder.string || +"") + text
        end
      end

      def literal_concat(head, tail, first, last, dedent: false)
        return tail unless head
        return head unless tail

        head = new_dstr(head, first, last) if head.type == :EVSTR
        if dedent
          head = str2dstr(head) if head.type == :STR
          return list_append(head, tail) if head.type == :DSTR
        end
        case tail.type
        when :STR
          if head.type == :STR
            head.lit = head.lit + tail.lit
          elsif (holder = string_literal_head(head))
            append_literal(holder, tail.lit)
          else
            list_append(head, tail)
          end
        when :DSTR
          if head.type == :STR
            tail.string = head.lit + (tail.string || "")
            head = tail
          elsif tail.string.nil?
            dstr_append(head, tail)
          elsif (holder = string_literal_head(head))
            append_literal(holder, tail.string)
            tail.string = nil
            dstr_append(head, tail)
          else
            cell = new_list(mk(:STR, first, last, lit: tail.string), first, last)
            cell.next = tail.next
            list_concat(head, cell)
            tail.string = nil
          end
        when :EVSTR
          head = str2dstr(head) if head.type == :STR
          list_append(head, tail)
        end
        head
      end

      def dstr_append(head, tail)
        if head.next.nil?
          head.next = tail.next
        elsif tail.next
          list_last(head.next).next = tail.next
        end
      end

      def visit_embedded_statements_node(node)
        opening = node.opening_loc
        body, = compstmt(node.statements, last_of(opening), end_offset(opening))
        if body
          case body.type
          when :STR then return str2dstr(body)
          when :EVSTR then return body
          end
        end
        mk(:EVSTR, first_of(node), last_of(node), body: body,
                                                  keyword_locations: [kw(node.opening_loc), kw(node.closing_loc)])
      end

      def visit_embedded_variable_node(node)
        mk(:EVSTR, first_of(node), last_of(node), body: visit(node.variable), keyword_locations: [kw(node.operator_loc), nil])
      end

      # ---------------------------------------------------------------
      # Variables

      def visit_local_variable_read_node(node)
        span(in_block? ? :DVAR : :LVAR, node, vid: node.name)
      end

      def visit_it_local_variable_read_node(node)
        span(:DVAR, node, vid: :"<it>")
      end

      def visit_instance_variable_read_node(node) = span(:IVAR, node, vid: node.name)
      def visit_class_variable_read_node(node) = span(:CVAR, node, vid: node.name)
      def visit_global_variable_read_node(node) = span(:GVAR, node, vid: node.name)
      def visit_constant_read_node(node) = span(:CONST, node, vid: node.name)
      def visit_back_reference_read_node(node) = span(:BACK_REF, node, vid: node.name)

      def visit_numbered_reference_read_node(node)
        span(:NTH_REF, node, vid: :"$#{node.number}")
      end

      def assignable(name, first, last, value = nil)
        type =
          case name.to_s
          when /\A@@/ then :CVASGN
          when /\A@/ then :IASGN
          when /\A\$/ then :GASGN
          when /\A[A-Z]/ then :CDECL
          else in_block? ? :DASGN : :LASGN
          end
        mk(type, first, last, vid: name, value: value)
      end

      # The anonymous `*`, `**`, and `&` parameters are always read as LVAR.
      def lvar(name, first, last)
        mk(:LVAR, first, last, vid: name)
      end

      def gettable(name, first, last)
        type =
          case name.to_s
          when /\A@@/ then :CVAR
          when /\A@/ then :IVAR
          when /\A\$/ then :GVAR
          when /\A[A-Z]/ then :CONST
          else in_block? ? :DVAR : :LVAR
          end
        mk(type, first, last, vid: name)
      end

      def visit_local_variable_write_node(node) = variable_write(node)
      def visit_instance_variable_write_node(node) = variable_write(node)
      def visit_class_variable_write_node(node) = variable_write(node)
      def visit_global_variable_write_node(node) = variable_write(node)
      def visit_constant_write_node(node) = variable_write(node)

      def variable_write(node)
        value = rhs_value(node.value)
        assignable(node.name, first_of(node), last_of(node), value)
      end

      # The right side of an assignment: an array without brackets is mrhs.
      def rhs_value(value)
        if value.is_a?(Prism::ArrayNode) && value.opening_loc.nil?
          mrhs(value.elements)
        else
          visit(value)
        end
      end

      def visit_local_variable_target_node(node) = assignable(node.name, first_of(node), last_of(node))
      def visit_instance_variable_target_node(node) = assignable(node.name, first_of(node), last_of(node))
      def visit_class_variable_target_node(node) = assignable(node.name, first_of(node), last_of(node))
      def visit_global_variable_target_node(node) = assignable(node.name, first_of(node), last_of(node))
      def visit_constant_target_node(node) = assignable(node.name, first_of(node), last_of(node))

      def visit_constant_path_target_node(node)
        path = constant_path(node)
        mk(:CDECL, first_of(node), last_of(node), vid: nil, value: nil, path: path)
      end

      def visit_call_target_node(node)
        mid = node.safe_navigation? ? node.name.to_s.chomp("=").to_sym : node.name
        mk(:ATTRASGN, first_of(node), last_of(node), recv: visit(node.receiver), mid: mid, args: nil)
      end

      def visit_index_target_node(node)
        args = call_arguments(node.arguments, node.block)
        mk(:ATTRASGN, first_of(node), last_of(node), recv: visit(node.receiver), mid: :[]=, args: args)
      end

      # Operator assignment: `x += 1`, `x ||= 1`, `x &&= 1`.
      def visit_local_variable_operator_write_node(node) = operator_write(node, node.binary_operator)
      def visit_instance_variable_operator_write_node(node) = operator_write(node, node.binary_operator)
      def visit_class_variable_operator_write_node(node) = operator_write(node, node.binary_operator)
      def visit_global_variable_operator_write_node(node) = operator_write(node, node.binary_operator)
      def visit_constant_operator_write_node(node) = operator_write(node, node.binary_operator)
      def visit_local_variable_or_write_node(node) = operator_write(node, :"||")
      def visit_instance_variable_or_write_node(node) = operator_write(node, :"||")
      def visit_class_variable_or_write_node(node) = operator_write(node, :"||")
      def visit_global_variable_or_write_node(node) = operator_write(node, :"||")
      def visit_constant_or_write_node(node) = operator_write(node, :"||")
      def visit_local_variable_and_write_node(node) = operator_write(node, :"&&")
      def visit_instance_variable_and_write_node(node) = operator_write(node, :"&&")
      def visit_class_variable_and_write_node(node) = operator_write(node, :"&&")
      def visit_global_variable_and_write_node(node) = operator_write(node, :"&&")
      def visit_constant_and_write_node(node) = operator_write(node, :"&&")

      def operator_write(node, op)
        first = first_of(node)
        last = last_of(node)
        lhs_first = first_of(node.name_loc)
        lhs_last = last_of(node.name_loc)
        lhs = assignable(node.name, lhs_first, lhs_last)
        rhs = visit(node.value)
        case op
        when :"||", :"&&"
          lhs.value = rhs
          lhs.first_pos = first
          lhs.last_pos = last
          mk(op == :"||" ? :OP_ASGN_OR : :OP_ASGN_AND, first, last,
             head: gettable(node.name, lhs_first, lhs_last), value: lhs)
        else
          call = mk(:CALL, first, last, recv: gettable(node.name, lhs_first, lhs_last), mid: op,
                                        args: new_list(rhs))
          lhs.value = call
          lhs.first_pos = first
          lhs.last_pos = last
          lhs
        end
      end

      def visit_index_operator_write_node(node) = index_operator_write(node, node.binary_operator)
      def visit_index_or_write_node(node) = index_operator_write(node, :"||")
      def visit_index_and_write_node(node) = index_operator_write(node, :"&&")

      def index_operator_write(node, op)
        recv = visit(node.receiver)
        args = call_arguments(node.arguments, node.block)
        opening = node.opening_loc
        if args
          args_first = first_of(node.arguments || node.block)
          args_last = last_of(node.block || node.arguments)
          args.first_pos = args_first
          args.last_pos = args_last
        else
          at = last_of(opening)
          args = mk(:ZLIST, at, at)
        end
        mk(:OP_ASGN1, first_of(node), last_of(node), recv: recv, op: op, index: args, value: visit(node.value),
                                                     keyword_locations: [nil, kw(node.opening_loc),
                                                                         closing_span(node.arguments || node.opening_loc, node.closing_loc),
                                                                         kw(node.respond_to?(:binary_operator_loc) ? node.binary_operator_loc : node.operator_loc)])
      end

      def visit_call_operator_write_node(node) = call_operator_write(node, node.binary_operator)
      def visit_call_or_write_node(node) = call_operator_write(node, :"||")
      def visit_call_and_write_node(node) = call_operator_write(node, :"&&")

      def call_operator_write(node, op)
        mk(:OP_ASGN2, first_of(node), last_of(node),
           recv: visit(node.receiver), aid: node.safe_navigation?, vid: node.read_name,
           op: op, value: visit(node.value),
           keyword_locations: [kw(node.call_operator_loc), kw(node.message_loc), kw(node.respond_to?(:binary_operator_loc) ? node.binary_operator_loc : node.operator_loc)])
      end

      def visit_constant_path_operator_write_node(node) = constant_path_operator_write(node, node.binary_operator)
      def visit_constant_path_or_write_node(node) = constant_path_operator_write(node, :"||")
      def visit_constant_path_and_write_node(node) = constant_path_operator_write(node, :"&&")

      def constant_path_operator_write(node, op)
        mk(:OP_CDECL, first_of(node), last_of(node), head: constant_path(node.target), op: op, value: visit(node.value))
      end

      def visit_constant_path_node(node)
        constant_path(node)
      end

      def constant_path(node)
        if node.parent
          mk(:COLON2, first_of(node), last_of(node), head: visit(node.parent), mid: node.name,
                                                     keyword_locations: [kw(node.delimiter_loc), kw(node.name_loc)])
        else
          mk(:COLON3, first_of(node), last_of(node), mid: node.name,
                                                     keyword_locations: [kw(node.delimiter_loc), kw(node.name_loc)])
        end
      end

      def visit_constant_path_write_node(node)
        path = constant_path(node.target)
        mk(:CDECL, first_of(node), last_of(node), vid: nil, value: rhs_value(node.value), path: path)
      end

      # ---------------------------------------------------------------
      # Multiple assignment

      def visit_multi_write_node(node)
        masgn = mlhs(node)
        masgn.value = rhs_value(node.value)
        masgn.first_pos = first_of(node)
        masgn.last_pos = last_of(node)
        masgn
      end

      def visit_multi_target_node(node)
        mlhs(node)
      end

      # mlhs_basic: a MASGN over the targets before the splat, the splat, and
      # a POSTARG for the targets after it. The first cell of each list spans
      # its item's grammar symbol, parentheses included. In a parameter list
      # (`margs`) the splat target's span includes its `*`.
      def mlhs(node, margs: false)
        lefts = node.lefts
        rest = node.rest
        rest = nil if rest.is_a?(Prism::ImplicitRestNode)
        rights = node.rights
        first, last = mlhs_span(node)
        head = mlhs_items(lefts, margs)
        rest_node = nil
        if rest
          rest_node =
            if rest.expression
              target = mlhs_item(rest.expression, margs)
              if margs
                target.first_pos = first_of(rest)
                target.last_pos = last_of(rest)
              end
              target
            else
              Draft::NO_NAME_REST
            end
          unless rights.empty?
            rest_node = mk(:POSTARG, first, last, first: rest_node, second: mlhs_items(rights, margs))
          end
        end
        mk(:MASGN, first, last, value: nil, head: head, args: rest_node)
      end

      def mlhs_items(items, margs)
        list = nil
        items.each do |item|
          node = mlhs_item(item, margs)
          list = list ? list_append(list, node) : new_list(node, first_of(item), last_of(item))
        end
        list
      end

      def mlhs_span(node)
        items = node.lefts + [node.rest].compact + node.rights
        return [first_of(node), last_of(node)] if items.empty?

        [first_of(items.first), last_of(items.last)]
      end

      def mlhs_item(target, margs)
        target.is_a?(Prism::MultiTargetNode) ? mlhs(target, margs: margs) : visit(target)
      end

      # ---------------------------------------------------------------
      # Arrays and hashes

      def visit_array_node(node)
        first = first_of(node)
        last = last_of(node)
        opening = node.opening_loc
        return word_list(node, first, last) if opening && @src.byteslice(opening.start_offset, 1) == "%"

        list = aref_args(node.elements, list_rule_last(node.elements))
        if list
          list.first_pos = first
          list.last_pos = last
          list
        else
          mk(:ZLIST, first, last)
        end
      end

      # words and symbols: `%w`, `%W`, `%i`, `%I` lists of lexed words.
      def word_list(node, first, last)
        symbols = %w[i I].include?(@src.byteslice(node.opening_loc.start_offset + 1, 1))
        list = nil
        node.elements.each do |element|
          word =
            case element
            when Prism::InterpolatedStringNode, Prism::InterpolatedSymbolNode
              string_contents(element.parts, element)
            else
              piece = Piece.new(start_offset(element), end_offset(element), string_value(element), false)
              mk(:STR, *content_span(piece, element, [piece], 0), lit: piece.value)
            end
          word = evstr2dstr(word)
          if symbols
            word = case word.type
                   when :DSTR then word.tap { |dstr| dstr.type = :DSYM }
                   when :STR then mk(:SYM, word.first_pos, word.last_pos, lit: word.lit.to_sym)
                   else word
                   end
          end
          list = list_append(list, word)
        end
        return mk(:ZLIST, first, last) unless list

        list.first_pos = first
        list.last_pos = last
        list
      end

      # args: a list that turns into ARGSCAT/ARGSPUSH around splats.
      def args_list(elements)
        node = nil
        first = nil
        elements.each do |element|
          first ||= first_of(element)
          last = last_of(element)
          if element.is_a?(Prism::SplatNode)
            splat = splat_node(element)
            node = node ? rest_arg_append(node, splat.head, first, last) : splat
          else
            item = visit(element)
            node = node ? last_arg_append(node, item, first, last) : new_list(item, first, last)
          end
        end
        node
      end

      def splat_node(element)
        value = element.expression ? visit(element.expression) : lvar(:*, first_of(element), last_of(element))
        mk(:SPLAT, first_of(element), last_of(element), head: value, keyword_locations: [kw(element.operator_loc)])
      end

      def mrhs(elements)
        args_list(elements)
      end

      # aref_args and call_args: plain arguments, then an optional brace-less hash.
      # `rule_last` ends the grammar rule: a trailing comma or a block
      # argument after the elements. In an array literal a lone hash's list
      # spans the rule; in call arguments it spans the hash.
      def aref_args(elements, rule_last = nil, call: false)
        plain = elements
        hash = nil
        if elements.last.is_a?(Prism::KeywordHashNode)
          plain = elements[0...-1]
          hash = elements.last
        end
        node = args_list(plain)
        if hash
          assocs = assocs(hash.elements)
          hash_node = mk(:HASH, first_of(hash), last_of(hash), head: assocs)
          rule_last ||= last_of(hash)
          if node
            node = arg_append(node, hash_node, first_of(plain.first), rule_last)
          else
            node = new_list(hash_node, first_of(hash), call ? last_of(hash) : rule_last)
          end
        end
        node
      end

      # The end of an element list, through a trailing comma.
      def list_rule_last(elements)
        last = elements.last
        return nil unless last

        comma = comma_offset(end_offset(last))
        comma ? pos(comma + 1) : last_of(last)
      end

      def visit_hash_node(node)
        mk(:HASH, first_of(node), last_of(node), head: assocs(node.elements))
      end

      def visit_keyword_hash_node(node)
        mk(:HASH, first_of(node), last_of(node), head: assocs(node.elements))
      end

      def assocs(elements)
        list = nil
        elements.each do |element|
          tail = assoc(element)
          if !list
            list = tail
          else
            if list.head && tail.head.nil? && tail.next&.type == :LIST && tail.next.head&.type == :HASH
              tail = tail.next.head.head
            end
            list = list_concat(list, tail) if tail
          end
        end
        list
      end

      def assoc(element)
        first = first_of(element)
        last = last_of(element)
        case element
        when Prism::AssocNode
          key = element.key
          value = element.value
          key_node = visit(key)
          if value.is_a?(Prism::ImplicitNode)
            value_node = implicit_value(value.value, first_of(value), last_of(value))
          else
            value_node = visit(value)
          end
          list_append(new_list(key_node, first, last), value_node)
        when Prism::AssocSplatNode
          value = element.value ? visit(element.value) : lvar(:**, first, last)
          list_append(new_list(nil, first, last), value)
        end
      end

      def implicit_value(value, first, last)
        case value
        when Prism::LocalVariableReadNode then gettable(value.name, first, last)
        when Prism::CallNode then mk(:VCALL, first, last, mid: value.name)
        else
          node = visit(value)
          node.first_pos = first
          node.last_pos = last
          node
        end
      end

      def visit_splat_node(node)
        splat_node(node)
      end

      def visit_range_node(node)
        type = node.exclude_end? ? :DOT3 : :DOT2
        operator = node.operator_loc
        left = node.left ? visit(node.left) : nil_at(first_of(operator))
        right = node.right ? visit(node.right) : nil_at(last_of(operator))
        mk(type, first_of(node), last_of(node), beg_node: left, fin_node: right, keyword_locations: [kw(operator)])
      end

      def visit_flip_flop_node(node)
        visit_range_node(node)
      end

      # ---------------------------------------------------------------
      # Calls

      def visit_call_node(node)
        call = call_without_block(node)
        block = node.block
        return call unless block.is_a?(Prism::BlockNode)

        iter = block_iter(block)
        iter.iter = call
        iter.first_pos = call.first_pos
        iter.last_pos = last_of(node)
        iter
      end

      def operator_call?(node)
        return true if node.name == :! && node.message == "not"

        node.receiver && node.call_operator_loc.nil? && node.opening_loc.nil? &&
          !node.attribute_write? && node.message_loc &&
          (BINARY_OPERATORS.include?(node.name) || UNARY_OPERATORS.include?(node.name) || node.name == :=~)
      end

      def call_without_block(node)
        first = first_of(node)
        last = call_last(node)
        name = node.name

        if node.variable_call?
          return mk(:VCALL, first, last, mid: name)
        end

        if operator_call?(node)
          return operator_call(node, first, last)
        end

        if node.attribute_write?
          return attribute_write(node, first, last)
        end

        args = call_arguments(node.arguments, block_argument(node.block), node.opening_loc, node.closing_loc)
        if node.receiver.nil?
          return mk(:FCALL, first, last, mid: name, args: args)
        end

        recv = visit(node.receiver)
        if node.opening_loc && node.message_loc.nil? && name == :call
          type = node.safe_navigation? ? :QCALL : :CALL
          return mk(type, first, last, recv: recv, mid: :call, args: args)
        end
        type = node.safe_navigation? ? :QCALL : :CALL
        mk(type, first, last, recv: recv, mid: name, args: args)
      end

      def block_argument(block)
        block.is_a?(Prism::BlockArgumentNode) ? block : nil
      end

      # The call's own span, without a literal block.
      def call_last(node)
        block = node.block
        if block.is_a?(Prism::BlockNode)
          # new_command_qcall gives the call the whole span, block included:
          # a call on a block_call, and a command call with a brace block.
          brace = @src.byteslice(block.opening_loc.start_offset, 1) == "{"
          return last_of(node) if node.receiver && (block_call?(node.receiver) || (brace && command_args?(node)))
          # `primary_value tCOLON2 tCONSTANT '{' brace_body '}'`
          if brace && node.receiver && node.call_operator_loc && node.arguments.nil? && node.opening_loc.nil? &&
             @src.byteslice(node.call_operator_loc.start_offset, 2) == "::" && node.name.match?(/\A[A-Z]/)
            return last_of(node)
          end

          candidates = [node.closing_loc, node.arguments, node.message_loc, node.receiver].compact
          last_of(candidates.max_by { |thing| end_offset(thing) })
        else
          last_of(node)
        end
      end

      # `not(expr)` takes the expression itself; `not()` takes a nil at its `(`.
      def not_operand(node)
        receiver = node.receiver
        return nil unless node.message == "not" && receiver.is_a?(Prism::ParenthesesNode)
        return nil unless end_offset(node.message_loc) == start_offset(receiver)

        body = receiver.body
        return nil_at(first_of(receiver.opening_loc)).tap { |n| n.last_pos = last_of(receiver.opening_loc) } if body.nil?

        visit(body.is_a?(Prism::StatementsNode) && body.body.size == 1 ? body.body.first : body)
      end

      def command_args?(node)
        node.arguments && node.opening_loc.nil?
      end

      # block_call: a command with a do block, or a call chained onto one.
      def block_call?(node)
        return false unless node.is_a?(Prism::CallNode)

        block = node.block
        if block.is_a?(Prism::BlockNode)
          return false unless @src.byteslice(block.opening_loc.start_offset, 2) == "do"

          return command_args?(node) || (node.receiver && block_call?(node.receiver))
        end
        !node.receiver.nil? && !node.call_operator_loc.nil? && block_call?(node.receiver)
      end

      def operator_call(node, first, last)
        recv = not_operand(node) || visit(node.receiver)
        name = node.name
        if UNARY_OPERATORS.include?(name) && (node.arguments.nil? || node.arguments.arguments.empty?)
          if name == :-@ && negative_power?(node)
            # `-2 ** 2`: tUMINUS_NUM simple_numeric tPOW arg gives both calls the whole span.
            recv.first_pos = first
            recv.last_pos = last
          end
          recv = cond0(recv, [first_of(node.receiver), last_of(node.receiver)]) if name == :!
          return mk(:OPCALL, first, last, recv: recv, mid: name, args: nil)
        end

        arg = visit(node.arguments.arguments.first)
        if name == :=~
          return match_op(recv, arg, first, last)
        end

        mk(:OPCALL, first, last, recv: recv, mid: name, args: new_list(arg))
      end

      def negative_power?(node)
        inner = node.receiver
        inner.is_a?(Prism::CallNode) && inner.name == :** && inner.call_operator_loc.nil? &&
          [Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode].any? { |kind| inner.receiver.is_a?(kind) } &&
          end_offset(node.message_loc) == start_offset(inner.receiver)
      end

      def match_op(node1, node2, first, last)
        target = node1.type == :ONCE ? node1.body : node1
        case target.type
        when :DREGX
          return mk(:MATCH2, first, last, recv: node1, value: node2)
        when :REGX
          if target.lit
            match = mk(:MATCH2, first, last, recv: node1, value: node2)
            return match
          end
        end
        target = node2.type == :ONCE ? node2.body : node2
        if target.type == :DREGX
          return mk(:MATCH3, first, last, recv: node2, value: node1)
        end

        mk(:CALL, first, last, recv: node1, mid: :=~, args: new_list(node2))
      end

      def visit_match_write_node(node)
        match = visit(node.call)
        first = match.first_pos
        last = match.last_pos
        # reg_named_capture_assign appends to a placeholder and answers what follows it.
        assigns = mk(:ERROR, first, last)
        node.targets.each do |target|
          assign = assignable(target.name, first, last, mk(:SYM, first, last, lit: target.name))
          assigns = block_append(assigns, assign)
        end
        match.args = assigns.next
        match
      end

      def attribute_write(node, first, last)
        recv = visit(node.receiver)
        arguments = node.arguments&.arguments || []
        if node.name == :[]=
          index = arguments[0...-1]
          value = arguments.last
          args = index.empty? ? nil : aref_args(index)
          args = arg_append(args, rhs_value(value), first, last)
          args.last_pos = last_of(value) if args.type == :LIST
          return mk(:ATTRASGN, first, last, recv: recv, mid: :[]=, args: args)
        end

        mid = node.safe_navigation? ? node.name.to_s.chomp("=").to_sym : node.name
        value = arguments.last
        args = new_list(rhs_value(value))
        mk(:ATTRASGN, first, last, recv: recv, mid: mid, args: args)
      end

      # call_args and opt_call_args. The parentheses locate `(...)` forwarding.
      def call_arguments(arguments, block_arg, opening = nil, closing = nil)
        elements = arguments&.arguments || []
        node = nil
        if elements.last.is_a?(Prism::ForwardingArgumentsNode)
          leading = elements.size > 1 ? aref_args(elements[0...-1]) : nil
          return forward_arguments(leading, elements.last, first_of(opening), last_of(closing))
        end

        unless elements.empty?
          rule_last = block_arg ? last_of(block_arg) : list_rule_last(elements)
          node = aref_args(elements, rule_last, call: true)
        end
        if block_arg
          value = block_arg.expression ? visit(block_arg.expression) : lvar(:&, first_of(block_arg), last_of(block_arg))
          pass = mk(:BLOCK_PASS, first_of(block_arg), last_of(block_arg), head: nil, body: value,
                                                                          keyword_locations: [kw(block_arg.operator_loc)])
          node = arg_blk_pass(node, pass)
        end
        node
      end

      # new_args_forward_call: `(...)` passes the rest, keyword rest, and block.
      def forward_arguments(leading, forwarding, args_first, args_last)
        at_first = first_of(forwarding)
        at_last = last_of(forwarding)
        rest = lvar(:*, at_first, at_last)
        kwrest = list_append(new_list(nil, at_first, at_last), lvar(:**, at_first, at_last))
        block = mk(:BLOCK_PASS, args_first, args_last, head: nil, body: lvar(:&, at_first, at_last))
        args = leading ? rest_arg_append(leading, rest, args_first, args_last) : mk(:SPLAT, at_first, at_last, head: rest)
        args = arg_append(args, mk(:HASH, at_first, at_last, head: kwrest), args_first, args_last)
        arg_blk_pass(args, block)
      end

      def visit_super_node(node)
        args = call_arguments(node.arguments, block_argument(node.block), node.lparen_loc, node.rparen_loc)
        first = first_of(node)
        # parse.y cuts both parentheses out of paren_args' span by column only.
        if node.lparen_loc && node.rparen_loc
          open_first = first_of(node.lparen_loc)
          close_last = last_of(node.rparen_loc)
          lparen = [*open_first, close_last[0], open_first[1] + 1]
          rparen = [open_first[0], close_last[1] - 1, *close_last]
        end
        call = mk(:SUPER, first, super_last(node), head: args, keyword_locations: [kw(node.keyword_loc), lparen, rparen])
        with_block(node, call)
      end

      def super_last(node)
        if node.block.is_a?(Prism::BlockNode)
          last_of([node.rparen_loc, node.arguments, node.keyword_loc].compact.max_by { |thing| end_offset(thing) })
        else
          last_of(node)
        end
      end

      def visit_forwarding_super_node(node)
        first = first_of(node)
        keyword_end = start_offset(node) + "super".bytesize
        call = mk(:ZSUPER, first, node.block ? end_pos(keyword_end) : last_of(node))
        with_block(node, call)
      end

      def with_block(node, call)
        return call unless node.block.is_a?(Prism::BlockNode)

        iter = block_iter(node.block)
        iter.iter = call
        iter.first_pos = call.first_pos
        iter.last_pos = last_of(node)
        iter
      end

      def visit_yield_node(node)
        args = call_arguments(node.arguments, nil)
        mk(:YIELD, first_of(node), last_of(node), head: args,
                                                  keyword_locations: [kw(node.keyword_loc), kw(node.lparen_loc),
                                                                      closing_span(node.arguments || node.lparen_loc, node.rparen_loc)])
      end

      def visit_block_argument_node(node)
        value = node.expression ? visit(node.expression) : lvar(:&, first_of(node), last_of(node))
        mk(:BLOCK_PASS, first_of(node), last_of(node), head: nil, body: value, keyword_locations: [kw(node.operator_loc)])
      end

      # ---------------------------------------------------------------
      # Blocks and lambdas

      # brace_block / do_block: an ITER whose SCOPE spans the braces.
      def block_iter(block)
        opening = block.opening_loc
        brace = @src.byteslice(opening.start_offset, 1) == "{"
        params = block.parameters
        push_scope(:block) do
          args, prev, offset = block_parameters(params, block)
          table = block_table(params, block.locals)
          if brace
            body, = compstmt(block.body, prev, offset)
          else
            body = bodystmt(block.body, prev, offset).first
          end
          args = numbered_args(params, block, args)
          scope = mk(:SCOPE, first_of(block), last_of(block), tbl: table, args: args, body: body)
          mk(:ITER, first_of(block), last_of(block), body: scope)
        end
      end

      # The local table of a block or a lambda: its parameters, then its
      # block-local variables, then what its body assigns.
      def block_table(params, locals)
        case params
        when Prism::BlockParametersNode
          table = local_table(locals, params.parameters)
          params.locals.each { |local| table << local.name unless table.include?(local.name) }
          locals.each { |name| table << name unless table.include?(name) }
          table
        when Prism::ItParametersNode
          [:"<it>", *locals]
        when Prism::NumberedParametersNode
          numbered = (1..params.maximum).map { |n| :"_#{n}" }
          numbered + (locals - numbered)
        else
          locals.dup
        end
      end

      # block_param_def: the ARGS node, and where the body's statements start
      # (a newline right after `|` or `{` is no token). Answers [args, prev, offset].
      def block_parameters(params, block)
        return [nil, last_of(block.opening_loc), end_offset(block.opening_loc)] unless params.is_a?(Prism::BlockParametersNode)

        args = params.parameters ? parameters_args(params.parameters) : nil
        after = params.closing_loc || params
        [args, last_of(after), end_offset(after)]
      end

      def numbered_args(params, block, args)
        count =
          case params
          when Prism::NumberedParametersNode then params.maximum
          when Prism::ItParametersNode then 1
          end
        return args unless count

        at = last_of(block)
        args ||= new_args_node(at, at)
        args.ainfo[:pre_args_num] = count
        args
      end

      def visit_lambda_node(node)
        params = node.parameters
        push_scope(:block) do
          table = block_table(params, node.locals)
          operator = node.operator_loc
          args_first = last_of(operator)
          if params.is_a?(Prism::BlockParametersNode)
            args = params.parameters ? parameters_args(params.parameters) : new_args_node(args_first, args_first)
            args_span_first = first_of(params)
            args_span_last = last_of(params)
            unless params.opening_loc
              args_span_first = args.first_pos
              args_span_last = args.last_pos
            end
            if params.opening_loc && params.parameters.nil?
              args.first_pos = first_of(params.opening_loc)
              args.last_pos = last_of(params.opening_loc)
            end
          else
            args = new_args_node(args_first, args_first)
            args_span_first = args_first
            args_span_last = args_first
          end
          count =
            case params
            when Prism::NumberedParametersNode then params.maximum
            when Prism::ItParametersNode then 1
            end
          args.ainfo[:pre_args_num] = count if count

          opening = node.opening_loc
          if @src.byteslice(opening.start_offset, 1) == "{"
            body, = compstmt(node.body, last_of(opening), end_offset(opening))
          else
            body = bodystmt(node.body, last_of(opening), end_offset(opening)).first
          end
          scope = mk(:SCOPE, args_span_first, last_of(node), tbl: table, args: args, body: body)
          mk(:LAMBDA, first_of(node), last_of(node), body: scope,
                                                     keyword_locations: [kw(node.operator_loc), kw(node.opening_loc), kw(node.closing_loc)])
        end
      end

      # ---------------------------------------------------------------
      # Parameters

      def new_args_node(first, last)
        mk(:ARGS, first, last, ainfo: {
          pre_args_num: 0, pre_init: nil, opt_args: nil, first_post_arg: nil,
          post_args_num: 0, post_init: nil, rest_arg: nil, kw_args: nil,
          kw_rest_arg: nil, block_arg: nil, no_kwarg: false
        })
      end

      # f_args: the ARGS node for a ParametersNode.
      def parameters_args(params)
        items = [*params.requireds, *params.optionals, params.rest, *params.posts,
                 *params.keywords, params.keyword_rest, params.block].compact
        first = first_of(items.first)
        last = last_of(items.last)
        args = new_args_node(first, last)
        info = args.ainfo

        info[:pre_args_num] = params.requireds.size
        info[:pre_init] = destructure_chain(params.requireds)
        info[:opt_args] = params.optionals.inject(nil) do |chain, param|
          asgn = assignable(param.name, first_of(param), last_of(param), visit(param.value))
          opt_arg_append(chain, mk(:OPT_ARG, first_of(param), last_of(param), body: asgn))
        end

        case (rest = params.rest)
        when Prism::RestParameterNode then info[:rest_arg] = rest.name || :*
        when Prism::ImplicitRestNode then info[:rest_arg] = Draft::EXCESSIVE_COMMA
        end

        info[:post_args_num] = params.posts.size
        info[:post_init] = destructure_chain(params.posts)
        first_post = params.posts.first
        info[:first_post_arg] = first_post.is_a?(Prism::RequiredParameterNode) ? first_post.name : nil

        kw = params.keywords.inject(nil) do |chain, param|
          value = param.is_a?(Prism::OptionalKeywordParameterNode) ? visit(param.value) : Draft::REQUIRED_KEYWORD
          asgn = assignable(param.name, first_of(param), last_of(param), value)
          opt_arg_append(chain, mk(:KW_ARG, first_of(param), last_of(param), body: asgn))
        end
        info[:kw_args] = kw

        kwrest = params.keyword_rest
        case kwrest
        when Prism::NoKeywordsParameterNode
          info[:no_kwarg] = true
        when Prism::KeywordRestParameterNode
          info[:kw_rest_arg] = mk(:DVAR, first_of(kwrest), last_of(kwrest), vid: kwrest.name || :**)
        when Prism::ForwardingParameterNode
          info[:rest_arg] = :*
          info[:kw_rest_arg] = mk(:DVAR, first_of(kwrest), last_of(kwrest), vid: :**)
          info[:block_arg] = :&
        end
        if kw && !kwrest.is_a?(Prism::KeywordRestParameterNode)
          # new_args_tail answers a nameless DVAR spanning the keywords.
          info[:kw_rest_arg] = mk(:DVAR, first_of(params.keywords.first), last_of(params.keywords.last), vid: nil)
        end
        if (block = params.block)
          info[:block_arg] = block.name || :&
        end
        args
      end

      # opt_arg_append: each earlier item's span grows to the new item's end.
      def opt_arg_append(chain, item)
        return item unless chain

        cursor = chain
        loop do
          cursor.last_pos = item.last_pos
          break unless cursor.next

          cursor = cursor.next
        end
        cursor.next = item
        chain
      end

      def destructure_chain(params)
        chain = nil
        params.each do |param|
          next unless param.is_a?(Prism::MultiTargetNode)

          masgn = f_margs(param)
          chain = block_append(chain, masgn)
        end
        chain
      end

      # f_margs: a MASGN over destructured parameters, valued by an internal
      # variable at the list's start.
      def f_margs(node)
        masgn = mlhs(node, margs: true)
        at = masgn.first_pos
        masgn.value = mk(in_block? ? :DVAR : :LVAR, at, at, vid: nil)
        masgn
      end

      def visit_required_parameter_node(node)
        assignable(node.name, first_of(node), last_of(node))
      end

      # ---------------------------------------------------------------
      # Definitions

      # bodystmt: statements, then rescue clauses, else, and ensure.
      # Answers [node, first, last, offset].
      def bodystmt(node, prev, offset, newline: false, absorb: false)
        unless node.is_a?(Prism::BeginNode)
          return compstmt(node, prev, offset, newline: newline, absorb: absorb)
        end

        head, first, last, offset = compstmt(node.statements, prev, offset, newline: newline, absorb: absorb)
        rescue_node = nil
        if node.rescue_clause
          rescue_node, _r_first, last, offset = rescue_clause(node.rescue_clause, offset)
        end
        else_node = nil
        if node.else_clause
          keyword = node.else_clause.else_keyword_loc
          else_node, _e_first, last, offset = compstmt(node.else_clause.statements, last_of(keyword), end_offset(keyword))
        end
        ensure_node = nil
        if node.ensure_clause
          keyword = node.ensure_clause.ensure_keyword_loc
          ensure_node, _n_first, last, offset = compstmt(node.ensure_clause.statements, last_of(keyword), end_offset(keyword))
        end

        result = head
        if rescue_node
          tail = else_node || rescue_node
          result = mk(:RESCUE, head.first_pos, tail.last_pos, head: head, resq: rescue_node, else_body: else_node)
        end
        if ensure_node
          result = mk(:ENSURE, first, last, head: result, ensr: ensure_node)
        end
        [result, first, last, offset]
      end

      # opt_rescue: `k_rescue exc_list exc_var then compstmt opt_rescue`.
      def rescue_clause(node, _offset)
        first = first_of(node.keyword_loc)
        exceptions = node.exceptions
        args = nil
        unless exceptions.empty?
          if exceptions.length == 1 && !exceptions.first.is_a?(Prism::SplatNode)
            item = visit(exceptions.first)
            args = new_list(item)
          else
            args = args_list(exceptions)
            args = splat_array(args) || args
          end
        end
        exc_var = nil
        prev_thing = exceptions.last || node.keyword_loc
        newline = true
        if (reference = node.reference)
          operator = node.operator_loc
          var_first = first_of(operator)
          var_last = last_of(reference)
          target = visit(reference)
          errinfo = mk(:ERRINFO, var_first, var_last)
          set_value(target, errinfo, var_first, var_last)
          exc_var = target
          prev_thing = reference
        end
        if node.then_keyword_loc
          prev_thing = node.then_keyword_loc
          newline = false
        end
        body, _b_first, last, offset = compstmt(node.statements, last_of(prev_thing), end_offset(prev_thing),
                                                newline: newline, absorb: newline)
        following = nil
        if node.subsequent
          following, _f_first, last, offset = rescue_clause(node.subsequent, offset)
        end
        resbody = mk(:RESBODY, first, last, args: args, exc_var: exc_var, body: body, next: following)
        [resbody, first, last, offset]
      end

      def set_value(target, value, first, last)
        case target.type
        when :ATTRASGN
          target.args = arg_append(target.args, value, first, last)
        else
          target.value = value
        end
        target.first_pos = first
        target.last_pos = last
      end

      def visit_begin_node(node)
        keyword = node.begin_keyword_loc
        unless keyword
          body, = bodystmt(node, first_of(node), start_offset(node))
          return body
        end

        body, = bodystmt(node, last_of(keyword), end_offset(keyword))
        mk(:BEGIN, first_of(node), last_of(node), body: body)
      end

      def visit_rescue_modifier_node(node)
        first = first_of(node)
        last = last_of(node)
        resbody = mk(:RESBODY, first_of(node.keyword_loc), last, args: nil, exc_var: nil,
                                                               body: remove_begin(visit(node.rescue_expression)), next: nil)
        mk(:RESCUE, first, last, head: remove_begin(visit(node.expression)), resq: resbody, else_body: nil)
      end

      def visit_def_node(node)
        receiver = node.receiver
        if receiver.is_a?(Prism::ParenthesesNode)
          # singleton: `'(' expr rparen` answers the expression itself.
          receiver = receiver.body.is_a?(Prism::StatementsNode) ? receiver.body.body.first : receiver.body
        end
        recv = receiver ? visit(receiver) : nil
        push_scope(:def) do
          params = node.parameters
          table = local_table(node.locals, params)
          name_loc = node.name_loc
          endless = node.equal_loc
          if node.lparen_loc
            args = params ? parameters_args(params) : nil
            unless args
              args = new_args_node(first_of(node.lparen_loc), last_of(node.lparen_loc))
            end
            prev = last_of(node.rparen_loc)
            offset = end_offset(node.rparen_loc)
            newline = false
            absorb = false
          elsif params
            args = parameters_args(params)
            prev = args.last_pos
            offset = end_offset(params)
            newline = true
            absorb = true
          else
            at = last_of(name_loc)
            args = new_args_node(endless ? first_of(node) : at, at)
            prev = at
            offset = end_offset(name_loc)
            newline = true
            absorb = true
          end

          if endless
            body = visit(node.body.is_a?(Prism::StatementsNode) ? node.body.body.first : node.body)
          else
            body, = bodystmt(node.body, prev, offset, newline: newline, absorb: absorb)
          end
          body = reduce_nodes(remove_begin(body))
          first = first_of(node)
          last = last_of(node)
          scope = mk(:SCOPE, first, last, tbl: table, args: args, body: body)
          if recv
            mk(:DEFS, first, last, recv: recv, mid: node.name, body: scope)
          else
            mk(:DEFN, first, last, mid: node.name, body: scope)
          end
        end
      end

      def visit_class_node(node)
        cpath = cpath(node.constant_path)
        superclass = nil
        if node.superclass
          superclass = visit(node.superclass)
          prev = last_of(node.superclass)
          offset = end_offset(node.superclass)
          absorb = true
        else
          prev = last_of(node.constant_path)
          offset = end_offset(node.constant_path)
          absorb = false
        end
        push_scope(:class) do
          body, = bodystmt(node.body, prev, offset, newline: true, absorb: absorb)
          scope = mk(:SCOPE, first_of(node), last_of(node), tbl: node.locals, args: nil, body: body)
          if (operator = node.inheritance_operator_loc)
            # The superclass rule's span, cut to one column: its last line is its terminator's.
            term = scan_terms(end_offset(node.superclass), true).first
            term_last = term ? term.last : last_of(node.superclass)
            inheritance = [*first_of(operator), term_last[0], first_of(operator)[1] + 1]
          end
          mk(:CLASS, first_of(node), last_of(node), cpath: cpath, super_class: superclass, body: scope,
                                                    keyword_locations: [kw(node.class_keyword_loc), inheritance, kw(node.end_keyword_loc)])
        end
      end

      def cpath(node)
        case node
        when Prism::ConstantReadNode
          mk(:COLON2, first_of(node), last_of(node), head: nil, mid: node.name, keyword_locations: [nil, kw(node)])
        when Prism::ConstantPathNode
          constant_path(node)
        else
          visit(node)
        end
      end

      def visit_module_node(node)
        cpath = cpath(node.constant_path)
        push_scope(:class) do
          body, = bodystmt(node.body, last_of(node.constant_path), end_offset(node.constant_path), newline: true)
          scope = mk(:SCOPE, first_of(node), last_of(node), tbl: node.locals, args: nil, body: body)
          mk(:MODULE, first_of(node), last_of(node), cpath: cpath, body: scope,
                                                     keyword_locations: [kw(node.module_keyword_loc), kw(node.end_keyword_loc)])
        end
      end

      def visit_singleton_class_node(node)
        recv = visit(node.expression)
        push_scope(:class) do
          body, = bodystmt(node.body, last_of(node.expression), end_offset(node.expression), newline: true, absorb: true)
          scope = mk(:SCOPE, first_of(node), last_of(node), tbl: node.locals, args: nil, body: body)
          mk(:SCLASS, first_of(node), last_of(node), recv: recv, body: scope,
                                                     keyword_locations: [kw(node.class_keyword_loc), kw(node.operator_loc), kw(node.end_keyword_loc)])
        end
      end

      def visit_alias_method_node(node)
        mk(:ALIAS, first_of(node), last_of(node), new_name: visit(node.new_name), orig: visit(node.old_name),
                                                  keyword_locations: [kw(node.keyword_loc)])
      end

      def visit_alias_global_variable_node(node)
        mk(:VALIAS, first_of(node), last_of(node), new_name: node.new_name.name, orig: node.old_name.name,
                                                   keyword_locations: [kw(node.keyword_loc)])
      end

      def visit_undef_node(node)
        mk(:UNDEF, first_of(node), last_of(node), undefs: node.names.map { |name| visit(name) },
                                                  keyword_locations: [kw(node.keyword_loc)])
      end

      # ---------------------------------------------------------------
      # Control flow

      # `tLPAREN compstmt ')'` wraps the statements in a BLOCK; the lexer's
      # tLPAREN_ARG (a parenthesis after a method name and a space) does not.
      def visit_parentheses_node(node)
        opening = node.opening_loc
        body, = compstmt(node.body.is_a?(Prism::StatementsNode) ? node.body : [node.body].compact,
                         last_of(opening), end_offset(opening))
        return body if lparen_arg?(start_offset(node))

        new_block(body, first_of(node), last_of(node))
      end

      ARG_KEYWORDS = %w[yield super defined? not].freeze
      KEYWORDS = %w[
        alias and begin BEGIN break case class def defined? do else elsif end END ensure false
        for if in module next nil not or redo rescue retry return self super then true undef
        unless until when while yield __FILE__ __LINE__ __ENCODING__
      ].freeze

      def lparen_arg?(offset)
        scan = offset - 1
        return false unless scan >= 0 && [32, 9].include?(byte(scan))

        scan -= 1 while scan >= 0 && [32, 9].include?(byte(scan))
        return false if scan.negative?

        word_end = scan + 1
        scan -= 1 if [63, 33].include?(byte(scan)) # a method name's ? or !
        return false unless scan >= 0 && identifier_byte?(byte(scan))

        scan -= 1 while scan >= 0 && identifier_byte?(byte(scan))
        word = @src.byteslice(scan + 1, word_end - scan - 1)
        return false if word.match?(/\A\d/)
        return false if scan >= 0 && [64, 36].include?(byte(scan)) # @ivar, $gvar
        return false if scan >= 0 && byte(scan) == 58 && byte(scan - 1) != 58 # :symbol
        return ARG_KEYWORDS.include?(word) if KEYWORDS.include?(word)

        true
      end

      def identifier_byte?(c)
        c && (c >= 128 || (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95)
      end

      def visit_and_node(node)
        logop(:AND, visit(node.left), visit(node.right), first_of(node), last_of(node), node.operator_loc)
      end

      def visit_or_node(node)
        logop(:OR, visit(node.left), visit(node.right), first_of(node), last_of(node), node.operator_loc)
      end

      def visit_if_node(node)
        keyword = node.if_keyword_loc
        cond = cond0(visit(node.predicate), [first_of(node), last_of(node)])
        if keyword.nil?
          # The ternary operator.
          return mk(:IF, first_of(node), last_of(node), cond: cond, body: visit(node.statements.body.first),
                                                         else_body: visit(node.subsequent.statements.body.first),
                                                         keyword_locations: [nil, kw(node.subsequent.else_keyword_loc), nil])
        end
        if node.end_keyword_loc.nil? && start_offset(node.statements) < start_offset(keyword)
          # The modifier form.
          body = remove_begin(visit(node.statements.body.first))
          return mk(:IF, first_of(node), last_of(node), cond: cond, body: body, else_body: nil,
                                                         keyword_locations: [kw(keyword), nil, nil])
        end

        if_body(node, cond, :IF)
      end

      def if_body(node, cond, type, nested: false)
        then_keyword = then_keyword_of(node)
        if then_keyword
          body, _first, last, offset = compstmt(node.statements, last_of(then_keyword), end_offset(then_keyword))
        else
          body, _first, last, offset = compstmt(node.statements, last_of(node.predicate), end_offset(node.predicate),
                                                newline: true, absorb: true)
        end
        tail = node.respond_to?(:subsequent) ? node.subsequent : node.else_clause
        else_node = nil
        case tail
        when Prism::ElseNode
          keyword = tail.else_keyword_loc
          else_node, _first, last, = compstmt(tail.statements, last_of(keyword), end_offset(keyword))
        when Prism::IfNode
          else_node = elsif_node(tail)
        end
        keyword = type == :IF ? node.if_keyword_loc : node.keyword_loc
        then_loc = then_span(end_offset(node.predicate), then_keyword)
        end_loc = nested ? nil : kw(node.end_keyword_loc)
        # parse.y gives an `if`'s end to whatever IF its tail answers.
        if type == :IF && !nested && else_node&.type == :IF && else_node.keyword_locations
          else_node.keyword_locations[2] = kw(node.end_keyword_loc)
        end
        mk(type, first_of(node), last_of(node), cond: cond, body: body, else_body: else_node,
                                                keyword_locations: [kw(keyword), then_loc, end_loc])
      end

      # prism gives an `elsif` without `then` the `then` of the branch before it.
      def then_keyword_of(node)
        keyword = node.then_keyword_loc
        keyword if keyword && start_offset(keyword) >= end_offset(node.predicate)
      end

      def elsif_node(node)
        cond = cond0(visit(node.predicate), [first_of(node), elsif_last(node)])
        result = if_body(node, cond, :IF, nested: true)
        result.last_pos = elsif_last(node)
        result
      end

      # An elsif's span runs to the end of its last clause's statements.
      def elsif_last(node)
        then_keyword = then_keyword_of(node)
        _body, _first, last, = if then_keyword
                                 compstmt_span(node.statements, last_of(then_keyword), end_offset(then_keyword))
                               else
                                 compstmt_span(node.statements, last_of(node.predicate), end_offset(node.predicate), true, true)
                               end
        case (tail = node.subsequent)
        when Prism::ElseNode
          keyword = tail.else_keyword_loc
          _body, _first, last, = compstmt_span(tail.statements, last_of(keyword), end_offset(keyword))
        when Prism::IfNode
          last = elsif_last(tail)
        end
        last
      end

      # compstmt's span without building nodes.
      def compstmt_span(statements, prev, offset, newline = false, absorb = false)
        body = statements&.body || []
        terms = scan_terms(offset, newline)
        if absorb && !terms.empty?
          term = terms.shift
          prev = term.last
        end
        last = terms.empty? ? prev : terms.last.last
        unless body.empty?
          last = last_of(body.last)
          trailing = scan_terms(end_offset(body.last), true)
          last = trailing.last.last unless trailing.empty?
        end
        [nil, prev, last, nil]
      end

      def visit_unless_node(node)
        cond = cond0(visit(node.predicate), [first_of(node), last_of(node)])
        if node.end_keyword_loc.nil? && node.statements && start_offset(node.statements) < start_offset(node.keyword_loc)
          body = remove_begin(visit(node.statements.body.first))
          return mk(:UNLESS, first_of(node), last_of(node), cond: cond, body: body, else_body: nil,
                                                             keyword_locations: [kw(node.keyword_loc), nil, nil])
        end

        if_body(node, cond, :UNLESS)
      end

      def visit_else_node(node)
        body, = compstmt(node.statements, last_of(node.else_keyword_loc), end_offset(node.else_keyword_loc))
        body
      end

      def visit_while_node(node) = loop_node(node, :WHILE)
      def visit_until_node(node) = loop_node(node, :UNTIL)

      def loop_node(node, type)
        predicate = node.predicate
        if node.closing_loc.nil? || start_offset(node.statements || node) < start_offset(node.keyword_loc)
          cond = cond0(visit(predicate), [first_of(predicate), last_of(predicate)])
          body = node.statements ? visit(node.statements.body.first) : nil
          if node.begin_modifier? && body&.type == :BEGIN
            return mk(type, first_of(node), last_of(node), cond: cond, body: body.body, state: false,
                                                           keyword_locations: [kw(node.keyword_loc), nil])
          end

          return mk(type, first_of(node), last_of(node), cond: cond, body: body, state: true,
                                                         keyword_locations: [kw(node.keyword_loc), nil])
        end

        # expr_value_do spans the condition through its `do` or terminator.
        do_last = last_of(predicate)
        if (keyword = node.do_keyword_loc)
          do_last = last_of(keyword)
        elsif (term = scan_terms(end_offset(predicate), true).first)
          do_last = term.last
        end
        cond = cond0(visit(predicate), [first_of(predicate), do_last])
        if keyword
          body, = compstmt(node.statements, last_of(keyword), end_offset(keyword))
        else
          body, = compstmt(node.statements, last_of(predicate), end_offset(predicate), newline: true, absorb: true)
        end
        mk(type, first_of(node), last_of(node), cond: cond, body: body, state: true,
                                                keyword_locations: [kw(node.keyword_loc), kw(node.closing_loc)])
      end

      def visit_for_node(node)
        iter = visit(node.collection)
        var = node.index
        var_first = first_of(var)
        var_last = last_of(var)
        internal = mk(:DVAR, var_first, var_last, vid: nil)
        args = new_args_node(var_first, var_last)
        info = args.ainfo
        target = var.is_a?(Prism::MultiTargetNode) ? mlhs(var) : visit(var)
        case target.type
        when :LASGN, :DASGN
          target.value = internal
          info[:pre_args_num] = 1
          info[:pre_init] = target
        when :MASGN
          target.value = mk(:FOR_MASGN, var_first, var_last, value: internal)
          target.first_pos = var_first
          target.last_pos = var_last
          info[:pre_init] = target
        else
          masgn = mk(:MASGN, var_first, var_last, value: internal, head: new_list(target), args: nil)
          info[:pre_init] = masgn
        end
        if (keyword = node.do_keyword_loc)
          body, = compstmt(node.statements, last_of(keyword), end_offset(keyword))
        else
          body, = compstmt(node.statements, last_of(node.collection), end_offset(node.collection),
                           newline: true, absorb: true)
        end
        scope = mk(:SCOPE, first_of(node), last_of(node), tbl: [nil], args: args, body: body)
        mk(:FOR, first_of(node), last_of(node), iter: iter, body: scope,
                                                keyword_locations: [kw(node.for_keyword_loc), kw(node.in_keyword_loc),
                                                                    kw(node.do_keyword_loc), kw(node.end_keyword_loc)])
      end

      def visit_case_node(node)
        head = node.predicate ? visit(node.predicate) : nil
        body = when_chain(node.conditions, node.else_clause)
        if head
          mk(:CASE, first_of(node), last_of(node), head: head, body: body,
                                                   keyword_locations: [kw(node.case_keyword_loc), kw(node.end_keyword_loc)])
        else
          mk(:CASE2, first_of(node), last_of(node), head: nil, body: body,
                                                    keyword_locations: [kw(node.case_keyword_loc), kw(node.end_keyword_loc)])
        end
      end

      # case_body: WHEN nodes chained through `next`, ending in the else body.
      def when_chain(conditions, else_clause)
        whens = conditions.map { |condition| when_clause(condition) }
        else_node = nil
        else_last = nil
        if else_clause
          keyword = else_clause.else_keyword_loc
          else_node, _first, else_last, = compstmt(else_clause.statements, last_of(keyword), end_offset(keyword))
        end
        following = else_node
        last = else_last
        whens.reverse_each do |clause, clause_last|
          clause.next = following
          clause.last_pos = last || clause_last
          following = clause
          last = clause.last_pos
        end
        following
      end

      def when_clause(node)
        args = case_args(node.conditions)
        if (keyword = node.then_keyword_loc)
          body, _first, last, = compstmt(node.statements, last_of(keyword), end_offset(keyword))
        else
          body, _first, last, = compstmt(node.statements, last_of(node.conditions.last), end_offset(node.conditions.last),
                                         newline: true, absorb: true)
        end
        then_loc = then_span(end_offset(node.conditions.last), node.then_keyword_loc)
        [mk(:WHEN, first_of(node), last, head: args, body: body, next: nil,
                                         keyword_locations: [kw(node.keyword_loc), then_loc]), last]
      end

      def case_args(conditions)
        node = nil
        first = first_of(conditions.first)
        conditions.each do |condition|
          last = last_of(condition)
          if condition.is_a?(Prism::SplatNode)
            if node
              node = rest_arg_append(node, visit(condition.expression), first, last)
            else
              node = splat_node(condition)
            end
          else
            item = visit(condition)
            node = node ? last_arg_append(node, item, first, last) : new_list(item, first, last)
          end
        end
        node
      end

      def visit_break_node(node) = jump(node, :BREAK)
      def visit_next_node(node) = jump(node, :NEXT)

      def visit_return_node(node)
        jump(node, :RETURN)
      end

      def jump(node, type)
        args = call_arguments(node.arguments, nil)
        args = args.head if args && args.type == :LIST && args.next.nil?
        mk(type, first_of(node), last_of(node), head: args, keyword_locations: [kw(node.keyword_loc)])
      end

      def visit_redo_node(node) = span(:REDO, node, keyword_locations: [kw(node)])
      def visit_retry_node(node) = span(:RETRY, node)

      # new_defined: a `;` inside the expression keeps it whole in a BLOCK.
      def visit_defined_node(node)
        semicolons = @semicolons
        expr = visit(node.value)
        if @semicolons > semicolons && expr && expr.type != :BLOCK
          return mk(:DEFINED, first_of(node), last_of(node), head: new_block(expr, first_of(node), last_of(node)),
                                                             keyword_locations: [kw(node.keyword_loc)])
        end

        n = expr
        while n
          if n.type == :BEGIN
            n = n.body
          elsif n.type == :BLOCK && n.end_node.equal?(n)
            n = n.head
          else
            break
          end
        end
        mk(:DEFINED, first_of(node), last_of(node), head: n, keyword_locations: [kw(node.keyword_loc)])
      end

      def visit_pre_execution_node(node)
        opening = node.opening_loc
        body, = compstmt(node.statements, last_of(opening), end_offset(opening))
        first = first_of(opening)
        last = last_of(node)
        @begin_blocks = block_append(@begin_blocks, mk(:BEGIN, first, last, body: body))
        mk(:BEGIN, first, last, body: nil)
      end

      def visit_post_execution_node(node)
        opening = node.opening_loc
        body, = compstmt(node.statements, last_of(opening), end_offset(opening))
        scope = mk(:SCOPE, first_of(node), last_of(node), tbl: [], args: nil, body: body)
        mk(:POSTEXE, first_of(node), last_of(node), body: scope,
                                                    keyword_locations: [kw(node.keyword_loc), kw(node.opening_loc), kw(node.closing_loc)])
      end

      def visit_shareable_constant_node(node)
        visit(node.write)
      end

      def visit_missing_node(node)
        span(:ERROR, node)
      end

      # ---------------------------------------------------------------
      # Pattern matching

      def visit_case_match_node(node)
        head = visit(node.predicate)
        clauses = node.conditions.map { |condition| in_clause(condition) }
        else_node = nil
        last = nil
        if (else_clause = node.else_clause)
          keyword = else_clause.else_keyword_loc
          else_node, _first, last, = compstmt(else_clause.statements, last_of(keyword), end_offset(keyword))
        end
        following = else_node
        clauses.reverse_each do |clause, clause_last|
          clause.next = following
          clause.last_pos = last || clause_last
          following = clause
          last = clause.last_pos
        end
        mk(:CASE3, first_of(node), last_of(node), head: head, body: following,
                                                  keyword_locations: [kw(node.case_keyword_loc), kw(node.end_keyword_loc)])
      end

      def in_clause(node)
        pattern = top_pattern(node.pattern)
        if (keyword = node.then_loc)
          body, _first, last, = compstmt(node.statements, last_of(keyword), end_offset(keyword))
        else
          body, _first, last, = compstmt(node.statements, last_of(node.pattern), end_offset(node.pattern),
                                         newline: true, absorb: true)
        end
        then_loc = then_span(end_offset(node.pattern), node.then_loc)
        [mk(:IN, first_of(node), last, head: pattern, body: body, next: nil,
                                       keyword_locations: [kw(node.in_loc), then_loc, nil]), last]
      end

      def top_pattern(node)
        case node
        when Prism::IfNode
          cond = cond0(visit(node.predicate), [first_of(node), last_of(node)])
          body = pattern(node.statements.body.first, top: true)
          mk(:IF, first_of(node), last_of(node), cond: cond, body: body, else_body: nil,
                                                 keyword_locations: [kw(node.if_keyword_loc), nil, nil])
        when Prism::UnlessNode
          cond = cond0(visit(node.predicate), [first_of(node), last_of(node)])
          body = pattern(node.statements.body.first, top: true)
          mk(:UNLESS, first_of(node), last_of(node), cond: cond, body: body, else_body: nil,
                                                     keyword_locations: [kw(node.keyword_loc), nil, nil])
        else
          pattern(node, top: true)
        end
      end

      def pattern(node, top: false)
        case node
        when Prism::ArrayPatternNode then array_pattern(node, top)
        when Prism::FindPatternNode then find_pattern(node)
        when Prism::HashPatternNode then hash_pattern(node)
        when Prism::AlternationPatternNode
          mk(:OR, first_of(node), last_of(node), first: pattern(node.left), second: pattern(node.right),
                                                 keyword_locations: [kw(node.operator_loc)])
        when Prism::CapturePatternNode
          value = pattern(node.value)
          target = assignable(node.target.name, first_of(node.target), last_of(node.target))
          list = list_append(new_list(value, first_of(node), last_of(node)), target)
          mk(:HASH, first_of(node), last_of(node), head: list)
        when Prism::LocalVariableTargetNode
          assignable(node.name, first_of(node), last_of(node))
        when Prism::PinnedVariableNode
          variable = visit(node.variable)
          variable.first_pos = first_of(node)
          variable.last_pos = last_of(node)
          variable
        when Prism::PinnedExpressionNode
          new_block(visit(node.expression), first_of(node), last_of(node))
        when Prism::ParenthesesNode
          pattern(node.body.is_a?(Prism::StatementsNode) ? node.body.body.first : node.body)
        else
          visit(node)
        end
      end

      # p_rest: `*name` assigns; a bare `*` is no node.
      def pattern_rest(node)
        return nil unless node.is_a?(Prism::SplatNode) && node.expression

        assignable(node.expression.name, first_of(node), last_of(node))
      end

      # The LIST cells p_args builds, one per element, concatenated.
      def pattern_list(items)
        list = nil
        items.each do |item|
          cell = new_list(pattern(item), first_of(item), last_of(item))
          list = list ? list_concat(list, cell) : cell
        end
        list
      end

      def array_pattern(node, top)
        rest = node.rest
        elements = [*node.requireds, rest, *node.posts].compact
        constant = node.constant ? visit(node.constant) : nil
        if elements.empty?
          return mk(:ARYPTN, first_of(node), last_of(node), pconst: constant, pre_args: nil, rest_arg: nil, post_args: nil)
        end

        first = first_of(elements.first)
        last = last_of(elements.last)
        rest_arg = rest ? (pattern_rest(rest) || Draft::NO_NAME_REST) : nil
        post = pattern_list(node.posts)
        requireds = node.requireds
        if top && node.opening_loc.nil? && !requireds.empty? && elements.size > 1
          # p_top_expr_body: `p_expr ',' p_args` wraps the first element in
          # a list spanning the whole pattern.
          head = new_list(pattern(requireds.first), first, last)
          tail = pattern_list(requireds.drop(1))
          head = list_concat(head, tail) if tail
          pre = head
        else
          pre = pattern_list(requireds)
        end
        first = first_of(node.constant) if node.constant
        mk(:ARYPTN, first, last, pconst: constant, pre_args: pre, rest_arg: rest_arg, post_args: post)
      end

      def list_concat_or_new(list, tail)
        list ? list_concat(list, tail) : tail
      end

      def find_pattern(node)
        constant = node.constant ? visit(node.constant) : nil
        first = first_of(node.left)
        first = first_of(node.constant) if node.constant
        mk(:FNDPTN, first, last_of(node.right), pconst: constant,
                                                pre_rest: pattern_rest(node.left) || Draft::NO_NAME_REST,
                                                args: pattern_list(node.requireds),
                                                post_rest: pattern_rest(node.right) || Draft::NO_NAME_REST)
      end

      def hash_pattern(node)
        elements = node.elements
        rest = node.rest
        items = [*elements, rest].compact
        constant = node.constant ? visit(node.constant) : nil
        if items.empty?
          return mk(:HSHPTN, first_of(node), last_of(node), pconst: constant, head: nil, kw_rest: nil)
        end

        first = first_of(items.first)
        last = last_of(items.last)
        if rest.nil? && trailing_comma?(end_offset(items.last))
          last = pos(comma_offset(end_offset(items.last)) + 1)
        end
        list = nil
        elements.each do |element|
          key = element.key
          name = key.unescaped.to_sym
          if element.value.is_a?(Prism::ImplicitNode) || element.value.nil?
            at_first = first_of(element)
            at_last = last_of(element)
            sym = mk(:SYM, at_first, at_last, lit: name)
            item = list_append(new_list(sym, at_first, at_last), assignable(name, at_first, at_last))
          else
            sym = mk(:SYM, first_of(key), last_of(key), lit: name)
            item = list_append(new_list(sym, first_of(element), last_of(element)), pattern(element.value))
          end
          list = list_concat_or_new(list, item)
        end
        kw_rest = nil
        case rest
        when Prism::AssocSplatNode
          kw_rest = rest.value ? assignable(rest.value.name, first, last) : nil
        when Prism::NoKeywordsParameterNode
          kw_rest = Draft::NO_REST_KEYWORD
        end
        hash = mk(:HASH, first, last, head: list)
        first = first_of(node.constant) if node.constant
        mk(:HSHPTN, first, last, pconst: constant, head: hash, kw_rest: kw_rest)
      end

      def trailing_comma?(offset)
        !comma_offset(offset).nil?
      end

      def comma_offset(offset)
        offset += 1 while offset < @size && SPACE_BYTES.include?(byte(offset))
        byte(offset) == 44 ? offset : nil
      end

      def visit_match_predicate_node(node)
        value = visit(node.value)
        pat = top_pattern(node.pattern)
        first = first_of(node.pattern)
        last = last_of(node.pattern)
        clause = mk(:IN, first, last, head: pat, body: mk(:TRUE, first, last), next: mk(:FALSE, first, last),
                                      keyword_locations: [kw(node.operator_loc), nil, nil])
        mk(:CASE3, first_of(node), last_of(node), head: value, body: clause)
      end

      def visit_match_required_node(node)
        value = visit(node.value)
        pat = top_pattern(node.pattern)
        clause = mk(:IN, first_of(node.pattern), last_of(node.pattern), head: pat, body: nil, next: nil,
                                                                        keyword_locations: [nil, nil, kw(node.operator_loc)])
        mk(:CASE3, first_of(node), last_of(node), head: value, body: clause)
      end
    end
  end
end
