# frozen_string_literal: true

# Derived from the C part of the rbs gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.

module RBS
  class Parser
    # rbs's parser (src/parser.c), in Ruby. Each method is the C function
    # of its name, and builds the gem's AST objects as ast_translation.c
    # makes them from the C's nodes.
    #
    # A range is a pair of character positions, and NULL_RANGE is the C's
    # range of -1s. The C's errors are kept as it keeps them: the first one
    # wins, and most return at once (`fail!`, a throw to `run`); two only
    # record theirs and go on (`set_error`).
    class Engine
      KEYWORDS = %i[
        kBOOL kBOT kCLASS kFALSE kINSTANCE kINTERFACE kNIL kSELF kSINGLETON kTOP kTRUE kVOID kTYPE kUNCHECKED kIN kOUT
        kEND kDEF kINCLUDE kEXTEND kPREPEND kALIAS kMODULE kATTRREADER kATTRWRITER kATTRACCESSOR kPUBLIC kPRIVATE
        kUNTYPED kUSE kAS k__TODO__ kSKIP kRETURN
      ].freeze
      KEYWORD_TOKENS = (%i[tLIDENT tUIDENT tULIDENT tULLIDENT tNONASCIIIDENT tQIDENT tBANGIDENT] + KEYWORDS).to_set.freeze
      METHOD_NAMES = (%i[tUIDENT tLIDENT tULIDENT tULLIDENT tNONASCIIIDENT] + KEYWORDS).freeze
      OPERATOR_NAMES = %i[pBAR pHAT pAMP pSTAR pSTAR2 pLT pGT pAREF_OPR tOPERATOR].freeze
      REQUIRED_KEYWORDS = (%i[tUIDENT tLIDENT tQIDENT tULIDENT tULLIDENT tNONASCIIIDENT tBANGIDENT] + KEYWORDS).freeze
      PARAM_NAMES = (%i[tLIDENT tNONASCIIIDENT] + KEYWORDS - %i[kSKIP kRETURN]).freeze
      RECORD_KEYS = %i[tSYMBOL tSQSYMBOL tDQSYMBOL tSQSTRING tDQSTRING tINTEGER kTRUE kFALSE].to_set.freeze
      METHOD_TYPE_STARTS = %i[pLPAREN pARROW pLBRACE pLBRACKET pQUESTION].freeze

      CLASS_NAME = 1
      INTERFACE_NAME = 2
      ALIAS_NAME = 4

      NULL_RANGE = [-1, -1].freeze
      EMPTY_HASH = {}.freeze

      FAILED = :rbs_parse_failed

      # A run of line comments on consecutive lines (rbs_comment_t).
      Comment = Struct.new(:start, :end, :end_line, :tokens)

      # The parameters of a function (method_params): `required` is nil for
      # the untyped `(?)`.
      Params = Struct.new(:required, :optional, :rest, :trailing, :required_keywords, :optional_keywords, :rest_keywords,
                          :forwarding)

      # rbs_parser_new_with_options, after its lexer: three tokens ahead.
      # `bytes` parses for Serializer, as the C's `_to_bytes` entry points,
      # which translate nothing to Ruby, so raise none of its errors.
      def initialize(buffer, lexer, forwarding, bytes: false)
        @buffer = buffer
        @lexer = lexer
        @encoding = lexer.encoding
        @utf8 = @encoding == Encoding::UTF_8
        @forwarding = forwarding
        @bytes = bytes
        @current = @next = @next2 = @next3 = Lexer::NULL_TOKEN
        @vars = []
        @comments = []
        @error = nil
        @late_error = nil
        advance
        advance
        advance
      end

      # Runs a parse, and raises its first error: an RBS::ParsingError, or
      # the RuntimeError of an error that is no syntax error.
      def run
        result = nil
        catch(FAILED) { result = yield }
        raise_error if @error
        raise @late_error if @late_error && !@bytes

        result
      end

      # declare_type_variables (main.c).
      def declare_type_variables(variables)
        raise TypeError, "wrong argument type #{variables.class} (must be an Array of Symbols or nil)" unless variables.is_a?(Array)

        push_typevar_table(true)
        variables.each do |symbol|
          unless symbol.is_a?(Symbol)
            raise TypeError, "Type variables Array contains invalid value #{symbol.inspect} of type #{symbol.class} " \
                             "(must be an Array of Symbols or nil)"
          end

          insert_typevar(symbol.name.b)
        end
      end

      # parse_type_try.
      def type_entry(require_eof, void_allowed, self_allowed, classish_allowed)
        return nil if @next.type == :pEOF

        type = parse_type(void_allowed ? true : false, self_allowed ? true : false, classish_allowed ? true : false)
        throw FAILED if @error
        if require_eof
          advance
          fail!(@current, "expected a token `pEOF`") unless @current.type == :pEOF
        end
        type
      end

      # parse_method_type_try.
      def method_type_entry(require_eof)
        return nil if @next.type == :pEOF

        parse_method_type(require_eof ? true : false, true)
      end

      # parse_signature_try.
      def signature_entry = parse_signature

      # parse_type_params_try and rbs_parse_type_params. The flag is a C
      # bool from a VALUE: only false is false.
      def type_params_entry(module_type_params)
        return nil if @next.type == :pEOF

        fail!(@next, "expected a token `pLBRACKET`") unless @next.type == :pLBRACKET
        push_typevar_table(true)
        params, = parse_type_params(module_type_params != false)
        push_typevar_table(false)
        advance
        fail!(@current, "expected a token `pEOF`") unless @current.type == :pEOF
        params
      end

      # rbs_parse_inline_leading_annotation.
      def inline_leading_entry
        annotation = parse_inline_leading_annotation
        advance_assert(:pEOF)
        annotation
      end

      # rbs_parse_inline_trailing_annotation.
      def inline_trailing_entry
        annotation = parse_inline_trailing_annotation
        advance_assert(:pEOF)
        annotation
      end

      private

      # raise_error (main.c).
      def raise_error
        token, message, syntax = @error
        raise RuntimeError, "Unexpected error" unless syntax

        raise RBS::ParsingError.new(Location.new(@buffer, token.start, token.end), message, token.type.to_s)
      end

      # rbs_parser_set_error: only the first error counts.
      def set_error(token, message, syntax: true)
        @error ||= [token, message, syntax]
      end

      def fail!(token, message, syntax: true)
        set_error(token, message, syntax: syntax)
        throw FAILED
      end

      def assert_token(type)
        fail!(@current, "expected a token `#{type}`") unless @current.type == type
      end

      def advance_assert(type)
        advance
        assert_token(type)
      end

      # rbs_parser_advance: the next token that is no trivia and no comment.
      # A comment that is all of its line joins the comments.
      def advance
        @current = @next
        @next = @next2
        @next2 = @next3
        until @next3.type == :pEOF
          @next3 = @lexer.next_token
          case @next3.type
          when :tCOMMENT, :tTRIVIA then next
          when :tLINECOMMENT then insert_comment_line(@next3)
          else break
          end
        end
      end

      def advance_if(type)
        return false unless @next.type == type

        advance
        true
      end

      def advance_no_gap
        if @current.end == @next.start
          advance
        else
          set_error(@next, "unexpected token")
        end
      end

      def range(token) = [token.start, token.end]
      def text(token) = @lexer.bytes(token.start, token.end)

      # A Symbol of the bytes, in the buffer's encoding, as rb_intern3 makes
      # it. Bytes that are no valid text make the C's translation raise
      # EncodingError, after a parse without errors.
      def symbol(bytes)
        bytes.force_encoding(@encoding).to_sym
      rescue EncodingError => e
        return Serializer::Raw.new(Serializer::SYMBOL, bytes.b) if @bytes

        @late_error ||= e
        :""
      end
      def symbol_of(token) = symbol(text(token))

      # A location of `range` and its children, or nil for a null range.
      # A null range with children is ast_translation.c's TypeError, which
      # comes after the parse.
      def location(range, required = nil, optional = nil)
        if range[0] == -1 && !(@bytes && (required || optional))
          @late_error ||= TypeError.new("wrong argument type nil (expected RBS::Location)") if required || optional
          return nil
        end

        location = Location.new(@buffer, range[0], range[1])
        required&.each { |name, (from, to)| location._add_required_child(name, from, to) }
        optional&.each { |name, (from, to)| location._add_optional_child(name, from, to) }
        location
      end

      def locations(ranges) = ranges.map { location(it) }
      # The translation resolves the variables in bounds; the C serializes before it.
      def resolve_variables(type_params) = @bytes || RBS::AST::TypeParam.resolve_variables(type_params)
      def keywords_hash(hash) = hash.empty? ? EMPTY_HASH : hash

      # The type variables: a stack of tables, where nil is a reset
      # table, which a lookup does not pass.
      def push_typevar_table(reset)
        @vars << nil if reset
        @vars << []
      end

      def insert_typevar(name)
        table = @vars.last
        fail!(@current, "Cannot insert to reset table", syntax: false) if table.nil?

        table << name
      end

      def pop_typevar_table
        fail!(@current, "Cannot pop empty table", syntax: false) if @vars.empty?

        @vars.pop
        @vars.pop if !@vars.empty? && @vars.last.nil?
      end

      def typevar?(name)
        @vars.reverse_each do |table|
          return false if table.nil?
          return true if table.include?(name)
        end
        false
      end

      # rbs_unquote_string and unescape_string (rbs_unescape.c).
      def unquote(bytes)
        first = bytes.getbyte(0)
        bytes = bytes.byteslice(1, bytes.bytesize - 2) if first == 0x22 || first == 0x27 || first == 0x60
        unescape(bytes, first == 0x22)
      end

      ESCAPES = { 0x61 => 7, 0x62 => 8, 0x65 => 27, 0x66 => 12, 0x6E => 10, 0x72 => 13, 0x73 => 32, 0x74 => 9, 0x76 => 11,
                  0x22 => 0x22, 0x27 => 0x27, 0x5C => 0x5C }.freeze
      private_constant :ESCAPES

      def unescape(input, double)
        output = "".b
        length = input.bytesize
        i = 0
        while i < length
          c = input.getbyte(i)
          following = input.getbyte(i + 1) if i + 1 < length
          if c != 0x5C || following.nil?
            output << c
            i += 1
          elsif !double
            if following == 0x27 || following == 0x5C
              output << following
              i += 2
            else
              output << c
              i += 1
            end
          elsif digit?(following)
            size = 1
            size += 1 while size < 3 && i + 1 + size < length && digit?(input.getbyte(i + 1 + size))
            output << (number(input, i + 1, size, 8) & 0xFF)
            i += size + 1
          elsif following == 0x78 && i + 3 < length
            size = hex?(input.getbyte(i + 3)) ? 2 : 1
            output << (number(input, i + 2, size, 16) & 0xFF)
            i += size + 2
          elsif following == 0x75 && i + 5 < length
            if @utf8
              output << utf8(number(input, i + 2, 4, 16))
            else
              output << input.byteslice(i, 6)
            end
            i += 6
          elsif (escaped = ESCAPES[following])
            output << escaped
            i += 2
          else
            # The table's last entry, a lone `\`, maps to its NUL.
            output << 0
            i += 1
          end
        end
        output
      end

      def digit?(byte) = byte && byte >= 0x30 && byte <= 0x39
      def hex?(byte) = digit?(byte) || (byte && ((byte | 0x20) >= 0x61 && (byte | 0x20) <= 0x66))

      # hex_to_int and octal_to_int, which take any byte as a digit.
      def number(input, at, size, base)
        value = 0
        size.times do |k|
          byte = input.getbyte(at + k)
          digit = if digit?(byte) then byte - 0x30
                  elsif base == 8 then byte - 0x30
                  else (byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte) - 0x61 + 10
                  end
          value = value * base + digit
        end
        value
      end

      # rbs_utf8_fill_codepoint, which writes a surrogate as three bytes.
      def utf8(code)
        if code <= 0x7F then code.chr
        elsif code <= 0x7FF then [0xC0 | (code >> 6), 0x80 | (code & 0x3F)].pack("C*")
        else [0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F)].pack("C*")
        end
      end

      # rbs_string_strip_whitespace, with C's isspace.
      def strip(bytes) = bytes.b.sub(/\A[\t\n\v\f\r ]+/n, "").sub(/[\t\n\v\f\r ]+\z/n, "")

      # type_name ::= {`::`} (tUIDENT `::`)* <tXIDENT>
      # Returns the TypeName and its range.
      def parse_type_name(kind)
        start = @current.start
        absolute = false
        if @current.type == :pCOLON2
          absolute = true
          advance_no_gap
        end

        path = []
        while @current.type == :tUIDENT && @next.type == :pCOLON2 && @current.end == @next.start && @next.end == @next2.start
          path << symbol_of(@current)
          advance
          advance
        end

        accepted = case @current.type
                   when :tLIDENT, :kSKIP, :kRETURN then kind.anybits?(ALIAS_NAME)
                   when :tULIDENT then kind.anybits?(INTERFACE_NAME)
                   when :tUIDENT then kind.anybits?(CLASS_NAME)
                   else false
                   end
        unless accepted
          ids = "alias name" if kind.anybits?(ALIAS_NAME)
          ids = "interface name" if kind.anybits?(INTERFACE_NAME)
          ids = "class/module/constant name" if kind.anybits?(CLASS_NAME)
          fail!(@current, "expected one of #{ids}")
        end

        [RBS::TypeName[RBS::Namespace[path, absolute], symbol_of(@current)], [start, @current.end]]
      end

      def parse_type_list(eol, types, void_allowed, self_allowed, classish_allowed)
        loop do
          types << parse_type(void_allowed, self_allowed, classish_allowed)
          if @next.type == :pCOMMA
            advance
            break if @next.type == eol
          elsif @next.type == eol
            break
          else
            fail!(@next, "comma delimited type list is expected")
          end
        end
      end

      def parse_type_list_with_commas(eol, types, commas, void_allowed, self_allowed, classish_allowed)
        loop do
          types << parse_type(void_allowed, self_allowed, classish_allowed)
          if @next.type == :pCOMMA
            commas << location(range(@next))
            advance
            if @next.type == eol
              fail!(@next, "unexpected trailing comma") if eol == :pRBRACKET
              break
            end
          elsif @next.type == eol
            break
          else
            fail!(@next, "comma delimited type list is expected")
          end
        end
      end

      # function_param ::= {} <type> | {} type <param>
      def parse_function_param(self_allowed, classish_allowed)
        type_start = @next.start
        type = parse_type(false, self_allowed, classish_allowed)
        type_end = @current.end

        if @next.type == :pCOMMA || @next.type == :pRPAREN
          return RBS::Types::Function::Param.new(type: type, name: nil, location: location([type_start, type_end], nil, name: NULL_RANGE))
        end

        name_range = range(@next)
        advance
        fail!(@current, "unexpected token for function parameter name") unless KEYWORD_TOKENS.include?(@current.type)

        name = symbol(unquote(text(@current)))
        RBS::Types::Function::Param.new(type: type, name: name, location: location([type_start, name_range[1]], nil, name: name_range))
      end

      # keyword_key ::= {} <keyword> `:` | {} keyword <`?`> `:`
      # Returns the key's Symbol and its bytes.
      def parse_keyword_key
        advance
        if @next.type == :pQUESTION
          bytes = @lexer.bytes(@current.start, @next.end)
          advance
        else
          bytes = text(@current)
        end
        [symbol(bytes.dup), bytes]
      end

      def parse_keyword(keywords, memo, self_allowed, classish_allowed)
        key, bytes = parse_keyword_key
        fail!(@current, "duplicated keyword argument") if memo.include?(bytes)

        memo << bytes
        advance_assert(:pCOLON)
        keywords[key] = parse_function_param(self_allowed, classish_allowed)
      end

      def keyword?
        return false unless KEYWORD_TOKENS.include?(@next.type)
        return true if @next2.type == :pCOLON && @next.end == @next2.start

        @next2.type == :pQUESTION && @next3.type == :pCOLON && @next.end == @next2.start && @next2.end == @next3.start
      end

      # params ::= {} `)` | {} `?` `)` | {} `...` `)` | <required_params> `)` ...
      # The C's labels are phases that only go forward.
      def parse_params(params, forwarding_allowed, self_allowed, classish_allowed)
        if @next.type == :pQUESTION && @next2.type == :pRPAREN
          params.required = nil
          advance
          return
        end
        return if @next.type == :pRPAREN

        memo = []
        phase = required_params(params, forwarding_allowed, self_allowed, classish_allowed)
        phase = optional_params(params, memo, self_allowed, classish_allowed) if phase == :optional
        phase = rest_param(params, self_allowed, classish_allowed) if phase == :rest
        phase = trailing_params(params, self_allowed, classish_allowed) if phase == :trailing
        keyword_params(params, memo, self_allowed, classish_allowed) if phase == :keywords
        fail!(@next, "unexpected token for method type parameters") unless @next.type == :pRPAREN
      end

      def required_params(params, forwarding_allowed, self_allowed, classish_allowed)
        loop do
          case @next.type
          when :pQUESTION then return :optional
          when :pSTAR then return :rest
          when :pSTAR2 then return :keywords
          when :pRPAREN then return :eop
          when :pDOT3
            fail!(@next, "forwarding parameter is not allowed in this context") unless forwarding_allowed
            fail!(@next, "forwarding parameter syntax is not enabled") unless @forwarding

            advance
            params.forwarding = RBS::Types::Function::ForwardingParam.new(location: location(range(@current)))
            return :eop
          else
            return :keywords if keyword?

            params.required << parse_function_param(self_allowed, classish_allowed)
          end
          return :eop unless advance_if(:pCOMMA)
        end
      end

      def optional_params(params, memo, self_allowed, classish_allowed)
        loop do
          return :rest unless @next.type == :pQUESTION

          advance
          if keyword?
            parse_keyword(params.optional_keywords, memo, self_allowed, classish_allowed)
            advance_if(:pCOMMA)
            return :keywords
          end
          params.optional << parse_function_param(self_allowed, classish_allowed)
          return :eop unless advance_if(:pCOMMA)
        end
      end

      def rest_param(params, self_allowed, classish_allowed)
        if @next.type == :pSTAR
          advance
          params.rest = parse_function_param(self_allowed, classish_allowed)
          return :eop unless advance_if(:pCOMMA)
        end
        :trailing
      end

      def trailing_params(params, self_allowed, classish_allowed)
        loop do
          case @next.type
          when :pQUESTION, :pSTAR2 then return :keywords
          when :pSTAR, :pRPAREN then return :eop
          else
            return :keywords if keyword?

            params.trailing << parse_function_param(self_allowed, classish_allowed)
          end
          return :eop unless advance_if(:pCOMMA)
        end
      end

      def keyword_params(params, memo, self_allowed, classish_allowed)
        loop do
          case @next.type
          when :pQUESTION
            advance
            fail!(@next, "optional keyword argument type is expected") unless keyword?

            parse_keyword(params.optional_keywords, memo, self_allowed, classish_allowed)
          when :pSTAR2
            advance
            params.rest_keywords = parse_function_param(self_allowed, classish_allowed)
          when *REQUIRED_KEYWORDS
            fail!(@next, "required keyword argument type is expected") unless keyword?

            parse_keyword(params.required_keywords, memo, self_allowed, classish_allowed)
          else
            return
          end
          return unless advance_if(:pCOMMA)
        end
      end

      # optional ::= {} <simple_type> | {} simple_type <`?`>
      def parse_optional(void_allowed, self_allowed, classish_allowed)
        start = @next.start
        type = parse_simple(void_allowed, self_allowed, classish_allowed)
        return type unless @next.type == :pQUESTION

        fail!(@current, "void type is not allowed here") if void_allowed && type.instance_of?(RBS::Types::Bases::Void)

        advance
        RBS::Types::Optional.new(type: type, location: location([start, @current.end]))
      end

      def new_params = Params.new([], [], nil, [], {}, {}, nil, nil)

      # self_type_binding ::= {} <> | {} `[` `self` `:` type <`]`>
      def parse_self_type_binding(self_allowed, classish_allowed)
        return nil unless @next.type == :pLBRACKET

        advance
        advance_assert(:kSELF)
        advance_assert(:pCOLON)
        type = parse_type(false, self_allowed, classish_allowed)
        advance_assert(:pRBRACKET)
        type
      end

      def function(params, return_type)
        return RBS::Types::UntypedFunction.new(return_type: return_type) if params.required.nil?

        RBS::Types::Function.new(
          required_positionals: params.required, optional_positionals: params.optional, rest_positionals: params.rest,
          trailing_positionals: params.trailing, required_keywords: keywords_hash(params.required_keywords),
          optional_keywords: keywords_hash(params.optional_keywords), rest_keywords: params.rest_keywords,
          forwarding: params.forwarding, return_type: return_type
        )
      end

      # function ::= {} `(` params `)` self_type_binding? `{` ... `}` `->` <optional> | ...
      # Returns the function, its block and its self type.
      def parse_function(accept_type_binding, block_allowed, forwarding_allowed, self_allowed, classish_allowed)
        params = new_params
        if @next.type == :pLPAREN
          advance
          parse_params(params, forwarding_allowed, self_allowed, classish_allowed)
          advance_assert(:pRPAREN)
        end

        function_self_type = nil
        if accept_type_binding
          function_self_type = parse_self_type_binding(self_allowed, classish_allowed)
        elsif params.required.nil? && @next.type != :pARROW
          fail!(@next2, "A method type with untyped method parameter cannot have block")
        end

        required = true
        has_block = @next.type == :pLBRACE || (@next.type == :pQUESTION && @next2.type == :pLBRACE)
        fail!(@next, "method type with forwarding parameter cannot have block") if params.forwarding && has_block
        fail!(@next, "block is not allowed in this context") if !block_allowed && has_block

        if @next.type == :pQUESTION && @next2.type == :pLBRACE
          block_start = @next.start
          required = false
          advance
        elsif @next.type == :pLBRACE
          block_start = @next.start
        end

        block = nil
        if @next.type == :pLBRACE
          advance
          block_params = new_params
          if @next.type == :pLPAREN
            advance
            parse_params(block_params, false, self_allowed, classish_allowed)
            advance_assert(:pRPAREN)
          end
          self_type = parse_self_type_binding(self_allowed, classish_allowed)
          advance_assert(:pARROW)
          block_return_type = parse_optional(true, self_allowed, classish_allowed)
          advance_assert(:pRBRACE)
          block = RBS::Types::Block.new(type: function(block_params, block_return_type), required: required, self_type: self_type,
                                        location: location([block_start, @current.end]))
        end

        advance_assert(:pARROW)
        type = parse_optional(true, self_allowed, classish_allowed)
        [function(params, type), block, function_self_type]
      end

      # proc_type ::= {`^`} <function>
      def parse_proc_type(self_allowed, classish_allowed)
        start = @current.start
        function, block, self_type = parse_function(true, true, false, self_allowed, classish_allowed)
        RBS::Types::Proc.new(type: function, block: block, self_type: self_type, location: location([start, @current.end]))
      end

      # The key of a record field as rbs_node_equal compares it.
      def record_key_identity(literal)
        case literal
        when Symbol then [:symbol, literal.name.b]
        when String then [:string, literal.b]
        when Integer then [:integer, strip(text(@current))]
        when Serializer::Raw then [literal.tag == Serializer::SYMBOL ? :symbol : :integer, literal.bytes]
        else [:bool, literal]
        end
      end

      def check_key_duplication(fields, identity)
        set_error(@current, "duplicated record key") if fields.any? { |key, _| key == identity }
      end

      # record_attributes ::= {`{`} record_attribute... <record_attribute> `}`
      def parse_record_attributes(self_allowed, classish_allowed)
        fields = []
        return EMPTY_HASH if @next.type == :pRBRACE

        loop do
          required = true
          if @next.type == :pQUESTION
            required = false
            advance
          end

          if keyword?
            key, bytes = parse_keyword_key
            identity = [:symbol, bytes]
            check_key_duplication(fields, identity)
            advance_assert(:pCOLON)
          else
            fail!(@next, "unexpected record key token") unless RECORD_KEYS.include?(@next.type)

            key = parse_simple(false, self_allowed, classish_allowed).literal
            identity = record_key_identity(key)
            check_key_duplication(fields, identity)
            advance_assert(:pFATARROW)
          end

          value = [parse_type(false, self_allowed, classish_allowed), required]
          if (field = fields.find { |known, _| known == identity })
            field[2] = value
          else
            fields << [identity, key, value]
          end

          break unless advance_if(:pCOMMA) && @next.type != :pRBRACE
        end

        hash = {}
        fields.each { |_, key, value| hash[key] = value }
        keywords_hash(hash)
      end

      # symbol ::= {<tSYMBOL>}
      def parse_symbol(literal_location)
        bytes = text(@current).byteslice(1..)
        literal = case @current.type
                  when :tSYMBOL then symbol(bytes)
                  when :tDQSYMBOL, :tSQSYMBOL then symbol(unquote(bytes))
                  else fail!(@current, "Unexpected error", syntax: false)
                  end
        RBS::Types::Literal.new(literal: literal, location: literal_location)
      end

      # instance_type ::= {type_name} <type_args>
      def parse_instance_type(parse_alias)
        kind = INTERFACE_NAME | CLASS_NAME
        kind |= ALIAS_NAME if parse_alias
        name, name_range = parse_type_name(kind)

        klass = case @current.type
                when :tUIDENT then RBS::Types::ClassInstance
                when :tULIDENT then RBS::Types::Interface
                when :kSKIP, :kRETURN, :tLIDENT then RBS::Types::Alias
                else fail!(@current, "unexpected token for type name", syntax: false)
                end

        args = []
        args_range = NULL_RANGE
        if @next.type == :pLBRACKET
          advance
          args_start = @current.start
          parse_type_list(:pRBRACKET, args, true, true, true)
          advance_assert(:pRBRACKET)
          args_range = [args_start, @current.end]
        end

        type_range = [name_range[0], args_range[1] == -1 ? name_range[1] : args_range[1]]
        klass.new(name: name, args: args, location: location(type_range, { name: name_range }, args: args_range))
      end

      # singleton_type ::= {`singleton`} `(` type_name <`)`> type_args?
      def parse_singleton_type(self_allowed, classish_allowed)
        assert_token(:kSINGLETON)
        start = @current.start
        advance_assert(:pLPAREN)
        advance
        name, name_range = parse_type_name(CLASS_NAME)
        advance_assert(:pRPAREN)

        args = []
        args_range = NULL_RANGE
        if @next.type == :pLBRACKET
          advance
          args_start = @current.start
          parse_type_list(:pRBRACKET, args, true, self_allowed, classish_allowed)
          advance_assert(:pRBRACKET)
          args_range = [args_start, @current.end]
        end

        RBS::Types::ClassSingleton.new(name: name, args: args,
                                       location: location([start, @current.end], { name: name_range }, args: args_range))
      end

      # simple ::= {} `(` type <`)`> | {} <base type> | {} <type_name> | ...
      def parse_simple(void_allowed, self_allowed, classish_allowed)
        advance
        token = @current
        case token.type
        when :pLPAREN
          type = parse_type(void_allowed, self_allowed, classish_allowed)
          advance_assert(:pRPAREN)
          type
        when :kBOOL then RBS::Types::Bases::Bool.new(location: location(range(token)))
        when :kBOT then RBS::Types::Bases::Bottom.new(location: location(range(token)))
        when :kCLASS
          fail!(token, "class type is not allowed here") unless classish_allowed

          RBS::Types::Bases::Class.new(location: location(range(token)))
        when :kINSTANCE
          fail!(token, "instance type is not allowed here") unless classish_allowed

          RBS::Types::Bases::Instance.new(location: location(range(token)))
        when :kNIL then RBS::Types::Bases::Nil.new(location: location(range(token)))
        when :kSELF
          fail!(token, "self type is not allowed here") unless self_allowed

          RBS::Types::Bases::Self.new(location: location(range(token)))
        when :kTOP then RBS::Types::Bases::Top.new(location: location(range(token)))
        when :kVOID
          fail!(token, "void type is not allowed here") unless void_allowed

          RBS::Types::Bases::Void.new(location: location(range(token)))
        when :kUNTYPED then RBS::Types::Bases::Any.new(location: location(range(token)), todo: false)
        when :k__TODO__ then RBS::Types::Bases::Any.new(location: location(range(token)), todo: true)
        when :tINTEGER
          digits = strip(text(token))
          integer = @bytes ? Serializer::Raw.new(Serializer::INTEGER, digits) : digits.force_encoding(Encoding::UTF_8).to_i
          RBS::Types::Literal.new(literal: integer, location: location(range(token)))
        when :kTRUE then RBS::Types::Literal.new(literal: true, location: location(range(token)))
        when :kFALSE then RBS::Types::Literal.new(literal: false, location: location(range(token)))
        when :tSQSTRING, :tDQSTRING
          string = unquote(text(token)).force_encoding(Encoding::UTF_8)
          RBS::Types::Literal.new(literal: string, location: location(range(token)))
        when :tSYMBOL, :tSQSYMBOL, :tDQSYMBOL then parse_symbol(location(range(token)))
        when :tUIDENT
          name = text(token)
          return RBS::Types::Variable.new(name: symbol(name), location: location(range(token))) if typevar?(name.b)

          parse_instance_type(true)
        when :tULIDENT, :tLIDENT, :kSKIP, :kRETURN, :pCOLON2 then parse_instance_type(true)
        when :kSINGLETON then parse_singleton_type(self_allowed, classish_allowed)
        when :pLBRACKET
          start = token.start
          types = []
          parse_type_list(:pRBRACKET, types, false, self_allowed, classish_allowed) unless @next.type == :pRBRACKET
          advance_assert(:pRBRACKET)
          RBS::Types::Tuple.new(types: types, location: location([start, @current.end]))
        when :pAREF_OPR then RBS::Types::Tuple.new(types: [], location: location(range(token)))
        when :pLBRACE
          start = token.start
          fields = parse_record_attributes(self_allowed, classish_allowed)
          advance_assert(:pRBRACE)
          RBS::Types::Record.new(all_fields: fields, location: location([start, @current.end]))
        when :pHAT then parse_proc_type(self_allowed, classish_allowed)
        else fail!(token, "unexpected token for simple type")
        end
      end

      # intersection ::= {} optional `&` ... '&' <optional> | {} <optional>
      def parse_intersection(void_allowed, self_allowed, classish_allowed)
        start = @next.start
        first = parse_optional(void_allowed, self_allowed, classish_allowed)
        types = [first]
        while @next.type == :pAMP
          fail!(@current, "void type is not allowed here") if void_allowed && first.instance_of?(RBS::Types::Bases::Void)

          advance
          types << parse_optional(false, self_allowed, classish_allowed)
        end
        return first if types.size == 1

        RBS::Types::Intersection.new(types: types, location: location([start, @current.end]))
      end

      # union ::= {} intersection '|' ... '|' <intersection> | {} <intersection>
      def parse_type(void_allowed, self_allowed, classish_allowed)
        start = @next.start
        first = parse_intersection(void_allowed, self_allowed, classish_allowed)
        types = [first]
        while @next.type == :pBAR
          fail!(@current, "void type is not allowed here") if void_allowed && first.instance_of?(RBS::Types::Bases::Void)

          advance
          types << parse_intersection(false, self_allowed, classish_allowed)
        end
        return first if types.size == 1

        RBS::Types::Union.new(types: types, location: location([start, @current.end]))
      end

      # type_params ::= {} `[` type_param `,` ... <`]`> | {<>}
      # Returns the params and their range.
      def parse_type_params(module_type_params)
        params = []
        return [params, NULL_RANGE] unless @next.type == :pLBRACKET

        required_param_allowed = true
        advance
        start = @current.start
        loop do
          unchecked = false
          variance = :invariant
          upper_bound = lower_bound = default_type = nil
          param_start = @next.start
          unchecked_range = variance_range = NULL_RANGE
          if module_type_params
            if @next.type == :kUNCHECKED
              unchecked = true
              advance
              unchecked_range = range(@current)
            end
            if @next.type == :kIN || @next.type == :kOUT
              variance = @next.type == :kIN ? :contravariant : :covariant
              advance
              variance_range = range(@current)
            end
          end

          advance_assert(:tUIDENT)
          name_range = range(@current)
          bytes = text(@current)
          name = symbol(bytes.dup)
          insert_typevar(bytes.b)

          upper_bound_range = lower_bound_range = NULL_RANGE
          2.times do
            case @next.type
            when :pLT
              fail!(@next, "duplicate upper bound ('<') for type parameter") if upper_bound

              advance
              bound_start = @current.start
              upper_bound = parse_type(false, false, false)
              upper_bound_range = [bound_start, @current.end]
            when :pGT
              fail!(@next, "duplicate lower bound ('>') for type parameter") if lower_bound

              advance
              bound_start = @current.start
              lower_bound = parse_type(false, false, false)
              lower_bound_range = [bound_start, @current.end]
            end
          end

          default_range = NULL_RANGE
          if module_type_params
            if @next.type == :pEQ
              advance
              default_start = @current.start
              default_type = parse_type(true, false, false)
              default_range = [default_start, @current.end]
              required_param_allowed = false
            elsif !required_param_allowed
              fail!(@current, "required type parameter is not allowed after optional type parameter")
            end
          end

          params << RBS::AST::TypeParam.new(
            name: name, variance: variance, upper_bound: upper_bound, lower_bound: lower_bound, default_type: default_type,
            unchecked: unchecked,
            location: location([param_start, @current.end], { name: name_range },
                               variance: variance_range, unchecked: unchecked_range, upper_bound: upper_bound_range,
                               lower_bound: lower_bound_range, default: default_range)
          )

          if @next.type == :pCOMMA
            advance
          elsif @next.type == :pRBRACKET
            break
          else
            fail!(@next, "expected ',' or ']' after type parameter, got #{@next.type}")
          end
        end

        advance_assert(:pRBRACKET)
        [params, [start, @current.end]]
      end

      # method_type ::= {} type_params <function>
      def parse_method_type(require_eof, classish_allowed)
        push_typevar_table(false)
        start = @next.start
        type_params, params_range = parse_type_params(false)
        type_start = @next.start
        function, block, = parse_function(false, true, true, true, classish_allowed)
        pop_typevar_table
        stop = @current.end

        if require_eof
          advance
          fail!(@current, "expected a token `pEOF`") unless @current.type == :pEOF
        end

        method_type_location = location([start, stop], { type: [type_start, stop] }, type_params: params_range)
        resolve_variables(type_params)
        RBS::MethodType.new(type_params: type_params, type: function, block: block, location: method_type_location)
      end

      # global_decl ::= {tGIDENT} `:` <type>
      def parse_global_decl(annotations)
        start = @current.start
        comment = get_comment(@current.line)
        name_range = range(@current)
        name = symbol_of(@current)
        advance_assert(:pCOLON)
        colon_range = range(@current)
        type = parse_type(false, false, false)
        RBS::AST::Declarations::Global.new(
          name: name, type: type, comment: comment, annotations: annotations,
          location: location([start, @current.end], name: name_range, colon: colon_range)
        )
      end

      # const_decl ::= {const_name} `:` <type>
      def parse_const_decl(annotations)
        start = @current.start
        comment = get_comment(@current.line)
        name, name_range = parse_type_name(CLASS_NAME)
        advance_assert(:pCOLON)
        colon_range = range(@current)
        type = parse_type(false, false, false)
        RBS::AST::Declarations::Constant.new(
          name: name, type: type, comment: comment, annotations: annotations,
          location: location([start, @current.end], name: name_range, colon: colon_range)
        )
      end

      # type_decl ::= {kTYPE} alias_name `=` <type>
      def parse_type_decl(annotation, annotations)
        push_typevar_table(true)
        start = @current.start
        comment_line = (annotation || @current).line
        keyword_range = range(@current)
        advance
        name, name_range = parse_type_name(ALIAS_NAME)
        type_params, params_range = parse_type_params(true)
        advance_assert(:pEQ)
        eq_range = range(@current)
        type = parse_type(false, false, false)
        stop = @current.end
        pop_typevar_table
        comment = get_comment(comment_line)

        decl_location = location([start, stop], { keyword: keyword_range, name: name_range, eq: eq_range }, type_params: params_range)
        resolve_variables(type_params)
        RBS::AST::Declarations::TypeAlias.new(name: name, type_params: type_params, type: type, annotations: annotations,
                                              comment: comment, location: decl_location)
      end

      # annotation ::= {<tANNOTATION>}
      def parse_annotation
        bytes = text(@current)
        string = strip(bytes.byteslice(3, bytes.bytesize - 4)).force_encoding(@encoding)
        RBS::AST::Annotation.new(string: string, location: location(range(@current)))
      end

      # annotations ::= {} annotation ... <annotation> | {<>}
      # Returns the first annotation's token, or nil.
      def parse_annotations(annotations)
        first = nil
        while @next.type == :tANNOTATION
          advance
          first ||= @current
          annotations << parse_annotation
        end
        first
      end

      # method_name ::= {} <IDENT | keyword> | {} (IDENT | keyword)~<`?`>
      # Returns the name and its range. For a quoted name, the C leaves the
      # caller's range as it was, uninitialized; this gives the name's own.
      def parse_method_name
        advance
        token = @current
        case token.type
        when *METHOD_NAMES
          if @next.type == :pQUESTION && token.end == @next.start
            name_range = [token.start, @next.end]
            advance
            [symbol(@lexer.bytes(*name_range)), name_range]
          else
            [symbol_of(token), range(token)]
          end
        when :tBANGIDENT, :tEQIDENT, *OPERATOR_NAMES then [symbol_of(token), range(token)]
        when :tQIDENT then [symbol(unquote(text(token))), range(token)]
        else fail!(token, "unexpected token for method name")
        end
      end

      # instance_singleton_kind ::= {<>} | {} kSELF <`.`> | {} kSELF~`?` <`.`>
      # Returns the kind and its range.
      def parse_instance_singleton_kind(allow_selfq)
        return [:instance, NULL_RANGE] unless @next.type == :kSELF

        start = @next.start
        kind = :instance
        if @next2.type == :pDOT
          advance
          advance
          kind = :singleton
        elsif @next2.type == :pQUESTION && @next.end == @next2.start && @next3.type == :pDOT && allow_selfq
          advance
          advance
          advance
          kind = :singleton_instance
        end
        [kind, [start, @current.end]]
      end

      # def_member ::= {kDEF} method_name `:` <method_types> | {kPRIVATE} kDEF ... | {kPUBLIC} kDEF ...
      def parse_member_def(instance_only, accept_overload, annotation, annotations)
        start = @current.start
        comment = get_comment((annotation || @current).line)

        case @current.type
        when :kPRIVATE, :kPUBLIC
          visibility_range = range(@current)
          visibility = @current.type == :kPRIVATE ? :private : :public
          start = visibility_range[0]
          advance
        else
          visibility_range = NULL_RANGE
          visibility = nil
        end

        keyword_range = range(@current)
        kind, kind_range = instance_only ? [:instance, NULL_RANGE] : parse_instance_singleton_kind(visibility.nil?)
        name, name_range = parse_method_name

        if @next.type == :pDOT && name == :self?
          fail!(@next, "`self?` method cannot have visibility")
        else
          advance_assert(:pCOLON)
        end

        push_typevar_table(kind != :instance)
        overloads = []
        overloading = false
        overloading_range = NULL_RANGE
        stop = nil
        looping = true
        while looping
          overload_annotations = []
          parse_annotations(overload_annotations) if @next.type == :tANNOTATION

          case @next.type
          when *METHOD_TYPE_STARTS
            method_type = parse_method_type(false, !instance_only)
            overloads << RBS::AST::Members::MethodDefinition::Overload.new(annotations: overload_annotations, method_type: method_type)
            stop = @current.end
          when :pDOT3
            fail!(@next, "unexpected overloading method definition") unless accept_overload

            overloading = true
            advance
            looping = false
            overloading_range = range(@current)
            stop = overloading_range[1]
          else
            fail!(@next, "unexpected token for method type")
          end

          if @next.type == :pBAR
            advance
          else
            looping = false
          end
        end

        pop_typevar_table
        RBS::AST::Members::MethodDefinition.new(
          name: name, kind: kind, overloads: overloads, annotations: annotations, comment: comment, overloading: overloading,
          visibility: visibility,
          location: location([start, stop], { keyword: keyword_range, name: name_range },
                             kind: kind_range, overloading: overloading_range, visibility: visibility_range)
        )
      end

      # class_instance_name ::= {} <class_name> | {} class_name `[` type args <`]`>
      # Returns the name, the args and their ranges.
      def class_instance_name(kind, classish_allowed)
        advance
        name, name_range = parse_type_name(kind)
        args = []
        args_range = NULL_RANGE
        if @next.type == :pLBRACKET
          advance
          args_start = @current.start
          parse_type_list(:pRBRACKET, args, true, false, classish_allowed)
          advance_assert(:pRBRACKET)
          args_range = [args_start, @current.end]
        end
        [name, args, name_range, args_range]
      end

      MIXINS = { kINCLUDE: RBS::AST::Members::Include, kEXTEND: RBS::AST::Members::Extend, kPREPEND: RBS::AST::Members::Prepend }.freeze
      private_constant :MIXINS

      # mixin_member ::= {kINCLUDE} <class_instance_name> | {kPREPEND} ... | {kEXTEND} ...
      def parse_mixin_member(from_interface, annotation, annotations)
        start = @current.start
        comment_line = (annotation || @current).line
        type = @current.type
        keyword_range = range(@current)
        klass = MIXINS[type] or fail!(@current, "Unexpected error", syntax: false)
        fail!(@current, "unexpected mixin in interface declaration") if from_interface && type != :kINCLUDE

        push_typevar_table(type == :kEXTEND)
        name, args, name_range, args_range =
          class_instance_name(from_interface ? INTERFACE_NAME : INTERFACE_NAME | CLASS_NAME, !from_interface)
        pop_typevar_table
        stop = @current.end
        comment = get_comment(comment_line)
        klass.new(name: name, args: args, annotations: annotations, comment: comment,
                  location: location([start, stop], { name: name_range, keyword: keyword_range }, args: args_range))
      end

      # alias_member ::= {kALIAS} method_name <method_name> | {kALIAS} kSELF `.` method_name kSELF `.` <method_name>
      def parse_alias_member(instance_only, annotation, annotations)
        start = @current.start
        keyword_range = range(@current)
        comment = get_comment((annotation || @current).line)

        if !instance_only && @next.type == :kSELF
          kind = :singleton
          new_kind_range = [@next.start, @next2.end]
          advance_assert(:kSELF)
          advance_assert(:pDOT)
          new_name, new_name_range = parse_method_name
          old_kind_range = [@next.start, @next2.end]
          advance_assert(:kSELF)
          advance_assert(:pDOT)
          old_name, old_name_range = parse_method_name
        else
          kind = :instance
          new_name, new_name_range = parse_method_name
          old_name, old_name_range = parse_method_name
          new_kind_range = old_kind_range = NULL_RANGE
        end

        RBS::AST::Members::Alias.new(
          new_name: new_name, old_name: old_name, kind: kind, annotations: annotations, comment: comment,
          location: location([start, @current.end], { keyword: keyword_range, new_name: new_name_range, old_name: old_name_range },
                             new_kind: new_kind_range, old_kind: old_kind_range)
        )
      end

      # variable_member ::= {tAIDENT} `:` <type> | {kSELF} `.` tAIDENT `:` <type> | {tA2IDENT} `:` <type>
      def parse_variable_member(annotation, annotations)
        fail!(@current, "annotation cannot be given to variable members") unless annotations.empty?

        start = @current.start
        comment = get_comment((annotation || @current).line)
        case @current.type
        when :tAIDENT, :kATRBS
          name_range = range(@current)
          name = symbol_of(@current)
          advance_assert(:pCOLON)
          colon_range = range(@current)
          type = parse_type(false, true, true)
          RBS::AST::Members::InstanceVariable.new(
            name: name, type: type, comment: comment,
            location: location([start, @current.end], { name: name_range, colon: colon_range }, kind: NULL_RANGE)
          )
        when :tA2IDENT
          name_range = range(@current)
          name = symbol_of(@current)
          advance_assert(:pCOLON)
          colon_range = range(@current)
          push_typevar_table(true)
          type = parse_type(false, false, true)
          pop_typevar_table
          RBS::AST::Members::ClassVariable.new(
            name: name, type: type, comment: comment,
            location: location([start, @current.end], { name: name_range, colon: colon_range }, kind: NULL_RANGE)
          )
        when :kSELF
          kind_range = [@current.start, @next.end]
          advance_assert(:pDOT)
          fail!(@current, "Unexpected error", syntax: false) unless @next.type == :tAIDENT || @next.type == :kATRBS

          advance
          name_range = range(@current)
          name = symbol_of(@current)
          advance_assert(:pCOLON)
          colon_range = range(@current)
          push_typevar_table(true)
          type = parse_type(false, true, true)
          pop_typevar_table
          RBS::AST::Members::ClassInstanceVariable.new(
            name: name, type: type, comment: comment,
            location: location([start, @current.end], { name: name_range, colon: colon_range }, kind: kind_range)
          )
        else
          fail!(@current, "Unexpected error", syntax: false)
        end
      end

      # visibility_member ::= {<`public`>} | {<`private`>}
      def parse_visibility_member(annotations)
        fail!(@current, "annotation cannot be given to visibility members") unless annotations.empty?

        case @current.type
        when :kPUBLIC then RBS::AST::Members::Public.new(location: location(range(@current)))
        when :kPRIVATE then RBS::AST::Members::Private.new(location: location(range(@current)))
        else fail!(@current, "Unexpected error", syntax: false)
        end
      end

      ATTRIBUTES = { kATTRREADER: RBS::AST::Members::AttrReader, kATTRWRITER: RBS::AST::Members::AttrWriter,
                     kATTRACCESSOR: RBS::AST::Members::AttrAccessor }.freeze
      private_constant :ATTRIBUTES

      # attribute_member ::= {attr_keyword} attr_name attr_var `:` <type> | {visibility} attr_keyword ... | ...
      def parse_attribute_member(annotation, annotations)
        start = @current.start
        comment = get_comment((annotation || @current).line)

        case @current.type
        when :kPRIVATE, :kPUBLIC
          visibility_range = range(@current)
          visibility = @current.type == :kPRIVATE ? :private : :public
          advance
        else
          visibility = nil
          visibility_range = NULL_RANGE
        end

        attr_type = @current.type
        keyword_range = range(@current)
        is_kind, kind_range = parse_instance_singleton_kind(false)
        kind = is_kind == :instance ? :instance : :singleton
        name, name_range = parse_method_name

        ivar_name = nil
        ivar_range = ivar_name_range = NULL_RANGE
        if @next.type == :pLPAREN
          advance_assert(:pLPAREN)
          ivar_start = @current.start
          ivar_name = false
          if advance_if(:tAIDENT) || advance_if(:kATRBS)
            ivar_name = symbol_of(@current)
            ivar_name_range = range(@current)
          end
          advance_assert(:pRPAREN)
          ivar_range = [ivar_start, @current.end]
        end

        advance_assert(:pCOLON)
        colon_range = range(@current)
        push_typevar_table(is_kind == :singleton)
        type = parse_type(false, true, true)
        pop_typevar_table

        klass = ATTRIBUTES[attr_type] or fail!(@current, "Unexpected error", syntax: false)
        klass.new(
          name: name, type: type, ivar_name: ivar_name, kind: kind, annotations: annotations, comment: comment, visibility: visibility,
          location: location([start, @current.end], { keyword: keyword_range, name: name_range, colon: colon_range },
                             kind: kind_range, ivar: ivar_range, ivar_name: ivar_name_range, visibility: visibility_range)
        )
      end

      # interface_members ::= {} ...<interface_member> kEND
      def parse_interface_members
        members = []
        until @next.type == :kEND
          annotations = []
          annotation = parse_annotations(annotations)
          advance

          members << case @current.type
                     when :kDEF then parse_member_def(true, true, annotation, annotations)
                     when :kINCLUDE, :kEXTEND, :kPREPEND then parse_mixin_member(true, annotation, annotations)
                     when :kALIAS then parse_alias_member(true, annotation, annotations)
                     else fail!(@current, "unexpected token for interface declaration member")
                     end
        end
        members
      end

      # interface_decl ::= {`interface`} interface_name module_type_params interface_members <kEND>
      def parse_interface_decl(annotation, annotations)
        push_typevar_table(true)
        start = @current.start
        comment_line = (annotation || @current).line
        keyword_range = range(@current)
        advance
        name, name_range = parse_type_name(INTERFACE_NAME)
        type_params, params_range = parse_type_params(true)
        members = parse_interface_members
        advance_assert(:kEND)
        end_range = range(@current)
        pop_typevar_table
        comment = get_comment(comment_line)

        decl_location = location([start, end_range[1]], { keyword: keyword_range, name: name_range, end: end_range },
                                 type_params: params_range)
        resolve_variables(type_params)
        RBS::AST::Declarations::Interface.new(name: name, type_params: type_params, members: members, annotations: annotations,
                                              comment: comment, location: decl_location)
      end

      # module_self_types ::= {`:`} module_self_type `,` ... `,` <module_self_type>
      def parse_module_self_types(self_types)
        loop do
          advance
          start = @current.start
          name, name_range = parse_type_name(CLASS_NAME | INTERFACE_NAME)
          stop = name_range[1]
          args = []
          args_range = NULL_RANGE
          if @next.type == :pLBRACKET
            advance
            args_start = @current.start
            parse_type_list(:pRBRACKET, args, true, false, false)
            advance
            stop = @current.end
            args_range = [args_start, stop]
          end

          self_types << RBS::AST::Declarations::Module::Self.new(
            name: name, args: args, location: location([start, stop], { name: name_range }, args: args_range)
          )
          break unless @next.type == :pCOMMA

          advance
        end
      end

      # module_members ::= {} ...<module_member> kEND
      def parse_module_members
        members = []
        until @next.type == :kEND
          annotations = []
          annotation = parse_annotations(annotations)
          advance

          members << case @current.type
                     when :kDEF then parse_member_def(false, true, annotation, annotations)
                     when :kINCLUDE, :kEXTEND, :kPREPEND then parse_mixin_member(false, annotation, annotations)
                     when :kALIAS then parse_alias_member(false, annotation, annotations)
                     when :tAIDENT, :tA2IDENT, :kATRBS, :kSELF then parse_variable_member(annotation, annotations)
                     when :kATTRREADER, :kATTRWRITER, :kATTRACCESSOR then parse_attribute_member(annotation, annotations)
                     when :kPUBLIC, :kPRIVATE then visibility_or_member(annotation, annotations)
                     else parse_nested_decl(annotation, annotations)
                     end
        end
        members
      end

      def visibility_or_member(annotation, annotations)
        return parse_visibility_member(annotations) unless @next.line == @current.line

        case @next.type
        when :kDEF then parse_member_def(false, true, annotation, annotations)
        when :kATTRREADER, :kATTRWRITER, :kATTRACCESSOR then parse_attribute_member(annotation, annotations)
        else fail!(@next, "method or attribute definition is expected after visibility modifier")
        end
      end

      # module_decl ::= {module_name} module_type_params module_members <kEND> | ...
      def parse_module_decl0(keyword_range, name, name_range, comment, annotations)
        push_typevar_table(true)
        type_params, params_range = parse_type_params(true)

        self_types = []
        colon_range = self_types_range = NULL_RANGE
        if @next.type == :pCOLON
          advance
          colon_range = range(@current)
          self_types_start = @next.start
          parse_module_self_types(self_types)
          self_types_range = [self_types_start, @current.end]
        end

        members = parse_module_members
        advance_assert(:kEND)
        end_range = range(@current)
        pop_typevar_table

        decl_location = location([keyword_range[0], end_range[1]], { keyword: keyword_range, name: name_range, end: end_range },
                                 type_params: params_range, colon: colon_range, self_types: self_types_range)
        resolve_variables(type_params)
        RBS::AST::Declarations::Module.new(name: name, type_params: type_params, self_types: self_types, members: members,
                                           annotations: annotations, comment: comment, location: decl_location)
      end

      # module_decl ::= {`module`} module_name `=` old_module_name <kEND> | {`module`} module_name module_decl0 <kEND>
      def parse_module_decl(annotation, annotations)
        keyword_range = range(@current)
        comment = get_comment((annotation || @current).line)
        advance
        name, name_range = parse_type_name(CLASS_NAME)
        return parse_module_decl0(keyword_range, name, name_range, comment, annotations) unless @next.type == :pEQ

        eq_range = range(@next)
        advance
        advance
        old_name, old_name_range = parse_type_name(CLASS_NAME)
        RBS::AST::Declarations::ModuleAlias.new(
          new_name: name, old_name: old_name, comment: comment, annotations: annotations,
          location: location([keyword_range[0], old_name_range[1]],
                             keyword: keyword_range, new_name: name_range, eq: eq_range, old_name: old_name_range)
        )
      end

      # class_decl_super ::= {} `<` <class_instance_name> | {<>}
      # Returns the super class and the range of `<`.
      def parse_class_decl_super
        return [nil, NULL_RANGE] unless advance_if(:pLT)

        lt_range = range(@current)
        start = @next.start
        name, args, name_range, args_range = class_instance_name(CLASS_NAME, false)
        super_class = RBS::AST::Declarations::Class::Super.new(
          name: name, args: args, location: location([start, @current.end], { name: name_range }, args: args_range)
        )
        [super_class, lt_range]
      end

      # class_decl ::= {class_name} type_params class_decl_super class_members <`end`>
      def parse_class_decl0(keyword_range, name, name_range, comment, annotations)
        push_typevar_table(true)
        type_params, params_range = parse_type_params(true)
        super_class, lt_range = parse_class_decl_super
        members = parse_module_members
        advance_assert(:kEND)
        end_range = range(@current)
        pop_typevar_table

        decl_location = location([keyword_range[0], end_range[1]], { keyword: keyword_range, name: name_range, end: end_range },
                                 type_params: params_range, lt: lt_range)
        resolve_variables(type_params)
        RBS::AST::Declarations::Class.new(name: name, type_params: type_params, super_class: super_class, members: members,
                                          annotations: annotations, comment: comment, location: decl_location)
      end

      # class_decl ::= {`class`} class_name `=` <class_name> | {`class`} class_name <class_decl0>
      def parse_class_decl(annotation, annotations)
        keyword_range = range(@current)
        comment = get_comment((annotation || @current).line)
        advance
        name, name_range = parse_type_name(CLASS_NAME)
        return parse_class_decl0(keyword_range, name, name_range, comment, annotations) unless @next.type == :pEQ

        eq_range = range(@next)
        advance
        advance
        old_name, old_name_range = parse_type_name(CLASS_NAME)
        RBS::AST::Declarations::ClassAlias.new(
          new_name: name, old_name: old_name, comment: comment, annotations: annotations,
          location: location([keyword_range[0], old_name_range[1]],
                             keyword: keyword_range, new_name: name_range, eq: eq_range, old_name: old_name_range)
        )
      end

      # A declaration that a decl and a nested decl both start with, or nil.
      def declaration(annotation, annotations)
        case @current.type
        when :tUIDENT, :pCOLON2 then parse_const_decl(annotations)
        when :tGIDENT then parse_global_decl(annotations)
        when :kTYPE then parse_type_decl(annotation, annotations)
        when :kINTERFACE then parse_interface_decl(annotation, annotations)
        when :kMODULE then parse_module_decl(annotation, annotations)
        when :kCLASS then parse_class_decl(annotation, annotations)
        end
      end

      # nested_decl ::= {<const_decl>} | {<class_decl>} | {<interface_decl>} | {<module_decl>}
      def parse_nested_decl(annotation, annotations)
        push_typevar_table(true)
        decl = declaration(annotation, annotations) or fail!(@current, "unexpected token for class/module declaration member")
        pop_typevar_table
        decl
      end

      def parse_decl
        annotations = []
        annotation = parse_annotations(annotations)
        advance
        declaration(annotation, annotations) or fail!(@current, "cannot start a declaration")
      end

      # namespace ::= {} (`::`)? (`tUIDENT` `::`)* `tUIDENT` <`::`> | {} <>
      # Returns the namespace and its range.
      def parse_namespace
        start = stop = -1
        absolute = false
        if @next.type == :pCOLON2
          start, stop = range(@next)
          absolute = true
          advance
        end

        path = []
        while @next.type == :tUIDENT && @next2.type == :pCOLON2
          path << symbol_of(@next)
          start = @next.start if start == -1
          stop = @next2.end
          advance
          advance
        end
        [RBS::Namespace[path, absolute], [start, stop]]
      end

      # use_clauses ::= {} use_clause `,` ... `,` <use_clause>
      def parse_use_clauses(clauses)
        loop do
          namespace, namespace_range = parse_namespace
          case @next.type
          when :tLIDENT, :tULIDENT, :tUIDENT
            advance
            ident_type = @current.type
            type_name_range = namespace_range[0] == -1 ? range(@current) : [namespace_range[0], @current.end]
            type_name = RBS::TypeName[namespace, symbol_of(@current)]

            keyword_range = new_name_range = NULL_RANGE
            new_name = nil
            clause_range = type_name_range
            if @next.type == :kAS
              advance
              keyword_range = range(@current)
              advance_assert(ident_type)
              new_name = symbol_of(@current)
              new_name_range = range(@current)
              clause_range = [clause_range[0], new_name_range[1]]
            end

            clauses << RBS::AST::Directives::Use::SingleClause.new(
              type_name: type_name, new_name: new_name,
              location: location(clause_range, { type_name: type_name_range }, keyword: keyword_range, new_name: new_name_range)
            )
          when :pSTAR
            advance
            star_range = range(@current)
            clauses << RBS::AST::Directives::Use::WildcardClause.new(
              namespace: namespace,
              location: location([namespace_range[0], star_range[1]], namespace: namespace_range, star: star_range)
            )
          else
            fail!(@next, "use clause is expected")
          end

          break unless @next.type == :pCOMMA

          advance
        end
      end

      # use_directive ::= {} `use` <clauses>
      def parse_use_directive
        return nil unless @next.type == :kUSE

        advance
        keyword_range = range(@current)
        clauses = []
        parse_use_clauses(clauses)
        RBS::AST::Directives::Use.new(clauses: clauses, location: location([keyword_range[0], @current.end], keyword: keyword_range))
      end

      # parse_comment_lines: each line's text after its `#` and one space.
      def parse_comment_lines(comment)
        string = "".b
        comment.tokens.each do |token|
          from = @lexer.byte_at(token.start) + 1
          size = @lexer.byte_at(token.end) - from
          if @lexer.string.getbyte(from) == 0x20
            from += 1
            size -= 1
          end
          string << @lexer.string.byteslice(from, size) << "\n"
        end
        RBS::AST::Comment.new(string: string.force_encoding(@encoding), location: location([comment.start, comment.end]))
      end

      # comment_get_comment: the comment that ends on `line`, if any. The
      # newest comment is last.
      def find_comment(line)
        @comments.reverse_each do |comment|
          return nil if comment.end_line < line
          return comment if comment.end_line == line
        end
        nil
      end

      def insert_comment_line(token)
        if (comment = find_comment(token.line - 1))
          comment.tokens << token
          comment.end = token.end
          comment.end_line = token.line
        else
          @comments << Comment.new(token.start, token.end, token.line, [token])
        end
      end

      # rbs_parser_get_comment: the comment on the line before `subject_line`.
      def get_comment(subject_line)
        comment = find_comment(subject_line - 1)
        comment && parse_comment_lines(comment)
      end

      def parse_signature
        directives = []
        declarations = []
        directives << parse_use_directive while @next.type == :kUSE
        declarations << parse_decl until @next.type == :pEOF
        [directives, declarations]
      end

      # parse_method_overload ::= {} annotations <method_type>
      def parse_method_overload(annotations)
        parse_annotations(annotations)
        parse_method_type(false, true)
      end

      # inline_method_overloads ::= {} <overload> | {} overload `|` ... `|` overload | {} overload `|` ... `|` `...`
      # Returns the range of `...`, or NULL_RANGE.
      def parse_inline_method_overloads(overloads, bar_locations)
        loop do
          annotations = []
          method_type = parse_method_overload(annotations)
          overloads << RBS::AST::Members::MethodDefinition::Overload.new(annotations: annotations, method_type: method_type)
          return NULL_RANGE unless @next.type == :pBAR

          bar_range = range(@next)
          advance
          bar_locations << location(bar_range)
          next unless @next.type == :pDOT3

          dot3_range = range(@next)
          advance
          return dot3_range
        end
      end

      def parse_inline_comment
        return NULL_RANGE unless @next.type == :tINLINECOMMENT

        comment_range = range(@next)
        advance
        comment_range
      end

      def parse_inline_param_type_annotation(rbs_range)
        advance
        name_range = range(@current)
        advance_assert(:pCOLON)
        colon_range = range(@current)
        param_type = parse_type(false, true, true)
        comment_range = parse_inline_comment
        RBS::AST::Ruby::Annotations::ParamTypeAnnotation.new(
          location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range), name_location: location(name_range),
          colon_location: location(colon_range), param_type: param_type, comment_location: location(comment_range)
        )
      end

      # The name of a splat, a double splat or a block parameter, if any.
      def param_name_range
        return NULL_RANGE unless @next.type == :tLIDENT || @next.type == :tNONASCIIIDENT

        advance
        range(@current)
      end

      def parse_inline_leading_annotation
        case @next.type
        when :pCOLON
          colon_range = range(@next)
          advance
          annotations = []
          method_type = parse_method_overload(annotations)
          RBS::AST::Ruby::Annotations::ColonMethodTypeAnnotation.new(
            location: location([colon_range[0], @current.end]), prefix_location: location(colon_range), annotations: annotations,
            method_type: method_type
          )
        when :kATRBS
          rbs_range = range(@next)
          advance
          rbs_annotation(rbs_range)
        else
          fail!(@next, "unexpected token for inline leading annotation")
        end
      end

      def rbs_annotation(rbs_range)
        case @next.type
        when :pDOT3
          dot3_range = range(@next)
          advance
          RBS::AST::Ruby::Annotations::MethodTypesAnnotation.new(
            location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range), overloads: [],
            vertical_bar_locations: [], dot3_location: location(dot3_range)
          )
        when :pLPAREN, :pLBRACKET, :pLBRACE, :tANNOTATION
          overloads = []
          bar_locations = []
          dot3_range = parse_inline_method_overloads(overloads, bar_locations)
          RBS::AST::Ruby::Annotations::MethodTypesAnnotation.new(
            location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range), overloads: overloads,
            vertical_bar_locations: bar_locations, dot3_location: location(dot3_range)
          )
        when :kSKIP
          return parse_inline_param_type_annotation(rbs_range) if @next2.type == :pCOLON

          advance
          skip_range = range(@current)
          comment_range = parse_inline_comment
          RBS::AST::Ruby::Annotations::SkipAnnotation.new(
            location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range),
            skip_location: location(skip_range), comment_location: location(comment_range)
          )
        when :kRETURN
          advance
          return_range = range(@current)
          advance_assert(:pCOLON)
          colon_range = range(@current)
          return_type = parse_type(true, true, true)
          comment_range = parse_inline_comment
          RBS::AST::Ruby::Annotations::ReturnTypeAnnotation.new(
            location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range),
            return_location: location(return_range), colon_location: location(colon_range), return_type: return_type,
            comment_location: location(comment_range)
          )
        when :tAIDENT
          advance
          ivar_name_range = range(@current)
          ivar_name = symbol_of(@current)
          advance_assert(:pCOLON)
          colon_range = range(@current)
          type = parse_type(false, true, true)
          comment_range = parse_inline_comment
          RBS::AST::Ruby::Annotations::InstanceVariableAnnotation.new(
            location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range), ivar_name: ivar_name,
            ivar_name_location: location(ivar_name_range), colon_location: location(colon_range), type: type,
            comment_location: location(comment_range)
          )
        when *PARAM_NAMES then parse_inline_param_type_annotation(rbs_range)
        when :pSTAR, :pSTAR2
          klass = @next.type == :pSTAR ? RBS::AST::Ruby::Annotations::SplatParamTypeAnnotation : RBS::AST::Ruby::Annotations::DoubleSplatParamTypeAnnotation
          advance
          star_range = range(@current)
          name_range = param_name_range
          advance_assert(:pCOLON)
          colon_range = range(@current)
          param_type = parse_type(false, true, true)
          comment_range = parse_inline_comment
          star = klass == RBS::AST::Ruby::Annotations::SplatParamTypeAnnotation ? :star_location : :star2_location
          klass.new(
            location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range), star => location(star_range),
            name_location: location(name_range), colon_location: location(colon_range), param_type: param_type,
            comment_location: location(comment_range)
          )
        when :pAMP
          advance
          ampersand_range = range(@current)
          name_range = param_name_range
          advance_assert(:pCOLON)
          colon_range = range(@current)
          question_range = NULL_RANGE
          if @next.type == :pQUESTION
            advance
            question_range = range(@current)
          end
          type_start = @next.start
          function, = parse_function(true, false, false, true, true)
          type_range = [type_start, @current.end]
          comment_range = parse_inline_comment
          RBS::AST::Ruby::Annotations::BlockParamTypeAnnotation.new(
            location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range),
            ampersand_location: location(ampersand_range), name_location: location(name_range), colon_location: location(colon_range),
            question_location: location(question_range), type_location: location(type_range), type: function,
            comment_location: location(comment_range)
          )
        when :kMODULESELF
          advance
          keyword_range = range(@current)
          advance_assert(:pCOLON)
          colon_range = range(@current)
          advance
          name, = parse_type_name(CLASS_NAME | INTERFACE_NAME)
          args = []
          commas = []
          open_range = close_range = NULL_RANGE
          if @next.type == :pLBRACKET
            advance
            open_range = range(@current)
            parse_type_list_with_commas(:pRBRACKET, args, commas, true, false, false)
            advance
            close_range = range(@current)
          end
          comment_range = parse_inline_comment
          RBS::AST::Ruby::Annotations::ModuleSelfAnnotation.new(
            location: location([rbs_range[0], @current.end]), prefix_location: location(rbs_range),
            keyword_location: location(keyword_range), colon_location: location(colon_range), name: name, args: args,
            open_bracket_location: location(open_range), close_bracket_location: location(close_range), args_comma_locations: commas,
            comment_location: location(comment_range)
          )
        else
          fail!(@next, "unexpected token for @rbs annotation")
        end
      end

      def parse_inline_trailing_annotation
        prefix_range = range(@next)
        case @next.type
        when :pCOLON
          advance
          return alias_annotation(prefix_range) if @next.type == :kCLASSALIAS || @next.type == :kMODULEALIAS

          type = parse_type(true, true, true)
          RBS::AST::Ruby::Annotations::NodeTypeAssertion.new(
            location: location([prefix_range[0], @current.end]), prefix_location: location(prefix_range), type: type
          )
        when :pLBRACKET
          advance
          fail!(@next, "type application cannot be empty") if @next.type == :pRBRACKET

          type_args = []
          commas = []
          parse_type_list_with_commas(:pRBRACKET, type_args, commas, true, true, false)
          close_range = range(@next)
          advance
          RBS::AST::Ruby::Annotations::TypeApplicationAnnotation.new(
            location: location([prefix_range[0], close_range[1]]), prefix_location: location(prefix_range), type_args: type_args,
            close_bracket_location: location(close_range), comma_locations: commas
          )
        else
          fail!(@next, "unexpected token for inline trailing annotation")
        end
      end

      def alias_annotation(prefix_range)
        klass = @next.type == :kCLASSALIAS ? RBS::AST::Ruby::Annotations::ClassAliasAnnotation : RBS::AST::Ruby::Annotations::ModuleAliasAnnotation
        keyword_range = range(@next)
        advance

        type_name = nil
        type_name_range = NULL_RANGE
        stop = keyword_range[1]
        if @next.type == :tUIDENT || @next.type == :pCOLON2
          advance
          type_name, type_name_range = parse_type_name(CLASS_NAME)
          stop = type_name_range[1]
        end

        klass.new(
          location: location([prefix_range[0], stop]), prefix_location: location(prefix_range), keyword_location: location(keyword_range),
          type_name: type_name, type_name_location: location(type_name_range)
        )
      end
    end
    private_constant :Engine
  end
end
