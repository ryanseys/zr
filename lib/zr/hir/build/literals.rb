# frozen_string_literal: true

# `Hir::Build`'s literals: strings, arrays, hashes, shareable constants,
# frozen strings and regexps.

module Zr
  module Hir
    class Build
      # A string literal as prism flags it: frozen if the file's magic
      # comment says so (as CRuby reads the comment), and then the one
      # frozen String of its text, as CRuby interns it.
      # Under --debug=frozen-string-literal each literal keeps where it was
      # made (`:debug`): a frozen one is its site's own String, not the
      # interned one, as CRuby compiles it.
      #: (Prism::StringNode | Prism::SourceFileNode node, String text, Integer line) -> (Literal | FrozenString)
      def literal_string(node, text, line)
        debug = @loader&.debug_frozen_strings?
        return (debug ? FrozenString.new(text, line, :debug) : frozen_literal_string(text, line)) if node.frozen?

        chilled = debug ? :debug : true
        Literal.new(text, line, node.mutable? ? false : chilled)
      end

      # A Symbol literal. The static symbols are all UTF-8, so a name in
      # another encoding (`:il_était` in a binary source) is interned
      # from its String when it runs.
      #: (Prism::SymbolNode node, Integer line) -> node
      def literal_symbol(node, line)
        text = unescaped(node)
        return Literal.new(text.to_sym, line) if text.ascii_only? || text.encoding == ::Encoding::UTF_8

        Send.of(frozen_literal_string(text, line), :to_sym, [], line)
      end

      # `__FILE__`: the file's shown name. In the main file it is a path
      # from the command line, which ruby gives the locale's encoding.
      #: (Prism::SourceFileNode node, Integer line) -> node
      def source_file(node, line)
        text = literal_string(node, Paths.shown(@file), line)
        text.is_a?(Literal) && !@eval && @loader&.main?(@file) ? PathLiteral.new(text, line) : text
      end

      # A literal that a frozen_string_literal comment freezes: the one
      # frozen String of its text, with no send of `freeze` (ruby never
      # sends it for this case).
      #: (String text, Integer line) -> FrozenString
      def frozen_literal_string(text, line) = FrozenString.new(text, line, text.encoding == ::Encoding::UTF_8)

      # Whether prism found a string static (`"a" "b"`, a heredoc with no
      # interpolation). `static_text` joins its parts.
      #: (untyped node) -> bool
      def static_string?(node)
        node.parts.all? { |part| part.is_a?(Prism::StringNode) || (part.is_a?(Prism::InterpolatedStringNode) && static_string?(part)) }
      end

      #: (untyped node) -> String
      def static_text(node) = node.parts.map { |part| part.is_a?(Prism::StringNode) ? unescaped(part) : static_text(part) }.join

      # A string part's text with ruby's encoding: a \u escape makes it
      # UTF-8, and a non-ASCII \x escape in a US-ASCII file makes it
      # binary, whatever the file's encoding. Prism flags both, but gives
      # the text in the file's encoding.
      #: (untyped node) -> String
      def unescaped(node)
        text = node.unescaped
        if node.forced_utf8_encoding? then text.dup.force_encoding(Encoding::UTF_8)
        elsif node.forced_binary_encoding? then text.dup.force_encoding(Encoding::BINARY)
        # Prism reads ASCII text as UTF-8, whatever an eval's String says.
        elsif text.encoding != text_encoding && text.ascii_only? then text.dup.force_encoding(text_encoding)
        else text
        end
      end

      # The encoding of a literal's ASCII text: the source's, or the
      # message's in an error that stands in for rb_raise's (`c_message`).
      #: () -> Encoding
      def text_encoding = @in_c_message || @encoding

      # An element of an array literal. `[1, a: 2]` contains a Hash.
      # Keywords that are only `**` splats add it only if it is not empty.
      #: (Prism::node node, Integer line) -> node
      def array_element(node, line)
        case node
        when Prism::SplatNode then splat(node, line)
        when Prism::KeywordHashNode
          hash = HashLit.new(hash_pairs(node.elements), line)
          node.elements.all?(Prism::AssocSplatNode) ? Splat.new(KwSplatElement.new(hash, line), line) : hash
        else expr(node)
        end
      end

      # A hash's elements as a flat pair list; a `**value` is a HashSplat
      # key with a nil value.
      #: (Array[Prism::node] elements) -> Array[node?]
      def hash_pairs(elements)
        elements.flat_map do |e|
          case e
          when Prism::AssocNode
            [expr(e.key), expr(e.value.is_a?(Prism::ImplicitNode) ? e.value.value : e.value)]
          when Prism::AssocSplatNode
            [HashSplat.new(e.value ? expr(e.value) : anonymous(:kwrest, e.location.start_line), e.location.start_line), nil]
          end
        end
      end

      # `# shareable_constant_value:` on a constant write. A value that the
      # compiler knows is a literal is deep-frozen. Any other value must
      # already be shareable, as in ruby.
      #: (Prism::ShareableConstantNode node, Integer line) -> node
      def shareable_constant(node, line)
        built = expr(node.write)
        write = written_constant(built) #: untyped
        ractor = ConstRead.new(nil, :Ractor, line)
        write.value =
          if node.literal?
            literally_shareable(node.write.value, write.value, constant_written(node.write), line)
          elsif node.experimental_copy?
            Send.of(ractor, :make_shareable, [write.value], line, kwargs: HashLit.new([Literal.new(:copy, line), Literal.new(true, line)], line))
          else
            Send.of(ractor, :make_shareable, [write.value], line)
          end
        built
      end

      # The write that a constant write builds: the node itself, or the
      # one after the scope that an expression gives (`expr::C ||= v`), or
      # the one that `&&=` guards.
      #: (node built) -> node
      def written_constant(built)
        case built
        when Seq then written_constant(built.stmts.last)
        when And then written_constant(built.right)
        else built
        end
      end

      # `literal`'s value, as prism_compile.c's
      # pm_compile_shareable_constant_value builds it. An Array or Hash
      # literal builds each element the same way, then is made shareable
      # as a whole. A value of only literals is made shareable. Any other
      # value must already be shareable (an interpolated String after
      # deduplication). `top` is the constant's own value, not an element.
      #: (Prism::node node, untyped value, String? name, Integer line, ?top: bool) -> node
      def literally_shareable(node, value, name, line, top: true)
        node, value = unparenthesized(node, value)
        return frozen_literal(node, value, line) if shareable_literal?(node)

        ractor = ConstRead.new(nil, :Ractor, line)
        whole = ->(built) { top ? Send.of(ractor, :make_shareable, [built], line) : built }
        if node.is_a?(Prism::ArrayNode) && node.elements.none? { |e| e.is_a?(Prism::SplatNode) || e.is_a?(Prism::KeywordHashNode) }
          value.elements = node.elements.zip(value.elements).map { |e, v| literally_shareable(e, v, name, line, top: false) }
          whole.call(value)
        elsif node.is_a?(Prism::HashNode) && node.elements.all?(Prism::AssocNode)
          value.pairs = value.pairs.each_slice(2).zip(node.elements).flat_map do |(key, v), e|
            [key, literally_shareable(e.value.is_a?(Prism::ImplicitNode) ? e.value.value : e.value, v, name, line, top: false)]
          end
          whole.call(value)
        else
          value = Send.of(value, :-@, [], line) if node.is_a?(Prism::InterpolatedStringNode)
          Send.of(ractor, :ensure_shareable, [value, Literal.new(name, line)], line)
        end
      end

      # `(value)`: the one statement inside, and its built value, as
      # compile.c reads through the parentheses of `X = (1..2)`.
      #: (Prism::node node, untyped value) -> [Prism::node, untyped]
      def unparenthesized(node, value)
        # @type var inner: Prism::node
        # @type var built: untyped
        inner = node
        built = value
        while inner.is_a?(Prism::ParenthesesNode) && (body = inner.body).is_a?(Prism::StatementsNode) && body.body.size == 1 &&
              built.is_a?(Seq) && built.stmts.size == 1
          inner = body.body[0]
          built = built.stmts[0]
        end
        [inner, built]
      end

      # Whether CRuby makes a new Range of two String literals at each run.
      # Its peephole optimizer folds the two strings and the newrange into
      # one static Range only if no label is before the first string. A
      # label starts a block's body, a loop's body, the else branch of an
      # `if`, the then branch of an `unless` (a `case` has none), and a
      # body that a rescue covers.
      #: (Prism::node node) -> bool
      def after_label?(node)
        after_label = @after_label
        unless after_label
          after_label = {} #: Hash[Prism::node, bool]
          labeled(@root, after_label.compare_by_identity)
          @after_label = after_label
        end
        after_label.key?(node)
      end

      #: (Prism::node? node, Hash[Prism::node, bool] found) -> void
      def labeled(node, found)
        return if node.nil?

        start = case node
                when Prism::BlockNode, Prism::LambdaNode then node.body
                when Prism::WhileNode, Prism::UntilNode then node.statements
                when Prism::IfNode then node.subsequent
                when Prism::UnlessNode then node.statements
                when Prism::BeginNode then node.rescue_clause && node.statements
                end
        first = leading(start)
        found[first] = true if first
        node.compact_child_nodes.each { |child| labeled(child, found) }
      end

      # The Range whose code comes first in `node`'s code, if any: a
      # receiver comes before its call, a value before the variable that
      # it sets, a condition before its branches.
      #: (Prism::node? node) -> Prism::RangeNode?
      def leading(node)
        case node
        when Prism::RangeNode then node
        when Prism::StatementsNode then leading(node.body.first)
        when Prism::ParenthesesNode then leading(node.body)
        when Prism::ElseNode then leading(node.statements)
        when Prism::BeginNode then node.rescue_clause ? nil : leading(node.statements)
        when Prism::IfNode, Prism::UnlessNode then leading(node.predicate)
        when Prism::CallNode then leading(node.receiver)
        when Prism::AndNode, Prism::OrNode then leading(node.left)
        when Prism::ArrayNode then leading(node.elements.first)
        when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::GlobalVariableWriteNode,
             Prism::ClassVariableWriteNode then leading(node.value)
        end
      end

      # A value built only of literals (`shareable_literal?`), frozen when
      # it is built and with no send, as compile.c freezes the object that
      # it makes at compile time. An Array or Hash literal is marked frozen
      # and its elements are built the same way. A String is the shared
      # frozen String of its text. A Range's ends are frozen. All other
      # literals are always frozen.
      #: (Prism::node? node, untyped value, Integer line) -> untyped
      def frozen_literal(node, value, line)
        case node
        when Prism::ArrayNode
          value.elements = node.elements.zip(value.elements).map { |e, v| frozen_literal(e, v, line) }
          value.frozen = true
        when Prism::HashNode
          value.pairs = value.pairs.each_slice(2).zip(node.elements).flat_map do |(key, v), e|
            [frozen_literal(e.key, key, line), frozen_literal(e.value, v, line)]
          end
          value.frozen = true
        when Prism::RangeNode
          value.low = frozen_literal(node.left, value.low, line) if node.left
          value.high = frozen_literal(node.right, value.high, line) if node.right
        when Prism::StringNode
          text = value.value #: String
          return FrozenString.new(text, line, text.encoding == ::Encoding::UTF_8)
        end
        value
      end

      # The constant name of a shareable constant write, for the error.
      #: (Prism::node write) -> String?
      def constant_written(write)
        case write
        when Prism::ConstantWriteNode, Prism::ConstantAndWriteNode, Prism::ConstantOrWriteNode, Prism::ConstantOperatorWriteNode
          write.name.to_s
        when Prism::ConstantPathWriteNode, Prism::ConstantPathAndWriteNode, Prism::ConstantPathOrWriteNode,
             Prism::ConstantPathOperatorWriteNode
          constant_path_written(write.target)
        end
      end

      # pm_constant_path_path: the names of the path as written. A path
      # from the top starts with `::`, and one under an expression that is
      # not a constant starts with `...`.
      #: (Prism::ConstantPathNode target) -> String
      def constant_path_written(target)
        parts = [target.name.to_s]
        # @type var current: Prism::node?
        current = target.parent
        while current.is_a?(Prism::ConstantPathNode)
          parts.unshift(current.name.to_s)
          current = current.parent
        end
        parts.unshift(
          case current
          when nil then ""
          when Prism::ConstantReadNode then current.name.to_s
          else "..."
          end
        )
        parts.join("::")
      end

      # Whether a value is built only of literals, so a freeze cannot
      # affect an object that the program still uses. `__FILE__` is not
      # one (pm_static_literal_value has no case for it), so its String
      # must be shareable already. A Range with literal ends counts as the
      # constant's own value, but not as an element: compile.c's
      # static_literal_node_p, which reads an Array's or a Hash's
      # elements, has no case for it, so `[(1..2)]` uses make_shareable.
      #: (Prism::node? node, ?top: bool) -> bool
      def shareable_literal?(node, top: true)
        case node
        when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode,
             Prism::SymbolNode, Prism::StringNode, Prism::NilNode, Prism::TrueNode, Prism::FalseNode,
             Prism::RegularExpressionNode, Prism::SourceLineNode, Prism::SourceEncodingNode
          true
        when Prism::ArrayNode then node.elements.all? { |e| shareable_literal?(e, top: false) }
        when Prism::HashNode
          node.elements.all? { |e| e.is_a?(Prism::AssocNode) && shareable_literal?(e.key, top: false) && shareable_literal?(e.value, top: false) }
        when Prism::RangeNode
          top && (node.left.nil? || shareable_literal?(node.left, top: false)) && (node.right.nil? || shareable_literal?(node.right, top: false))
        else false
        end
      end

      # A regexp literal's option bits, as Regexp.new takes them.
      # `i`, `x` and `m`, then the two encoding bits: `n` declares the
      # pattern encoding-agnostic, and `e`, `s` and `u` pin it to one.
      #: (untyped node) -> Integer
      def regexp_options(node)
        (node.ignore_case? ? 1 : 0) | (node.extended? ? 2 : 0) | (node.multi_line? ? 4 : 0) |
          (flag_encoding(node) ? 16 : 0) | (node.ascii_8bit? ? 32 : 0)
      end

      # The encoding that a flag letter sets for the pattern, or nil.
      #: (untyped node) -> Encoding?
      def flag_encoding(node)
        if node.euc_jp? then ::Encoding::EUC_JP
        elsif node.windows_31j? then ::Encoding::Windows_31J
        elsif node.utf_8? then ::Encoding::UTF_8
        end
      end

      # The encoding the pattern is read in: a flag letter's, else the
      # source's when it is not UTF-8, as a file with `# encoding: binary`
      # has it. A pattern with an escaped byte past ASCII in a source that
      # is not UTF-8 is binary, as Prism marks it (reg_fragment_setenc).
      # nil reads it as UTF-8.
      #: (untyped node) -> Encoding?
      def regexp_encoding(node)
        flag = flag_encoding(node)
        return flag if flag
        return nil if @encoding == ::Encoding::UTF_8
        return ::Encoding::BINARY if node.forced_binary_encoding?

        @encoding
      end

      # What rb_reg_preprocess says of the escapes and the multibyte
      # characters of a pattern, before the engine compiles it.
      PREPROCESS_ERRORS = [
        "too short escaped multibyte character", "too short escape sequence", "invalid hex escape",
        "duplicate meta escape", "too short meta escape", "too short control escape", "duplicate control escape",
        "unexpected escape sequence", "invalid escape code", "invalid multibyte escape",
        "escaped non ASCII character in UTF-8 regexp", "invalid Unicode range", "UTF-8 character in non UTF-8 regexp",
        "invalid Unicode list", "invalid Unicode escape", "invalid multibyte character", "non ASCII character in UTF-8 regexp"
      ].freeze

      # Ruby checks the pattern. A pattern that ruby refuses is also a
      # syntax error here.
      #: (Prism::InterpolatedRegularExpressionNode | Prism::InterpolatedMatchLastLineNode node, Integer line) -> node
      def interpolated_regexp(node, line)
        # Each fragment is a separate String: ruby reads each one in its
        # own encoding before it joins them, so only a flag letter pins one.
        pinned = flag_encoding(node)
        check_fragments(node, pinned)
        parts = interpolation(node, line).parts
        # A regexp of a US-ASCII source reads as binary (reg_fragment_setenc),
        # so the empty start of `/#{x}/` is binary, and an escape past ASCII
        # in `x` fixes the pattern to binary. A String literal in the braces
        # is text of the pattern, which keeps the source's encoding.
        first = parts.first
        if !pinned && @encoding == ::Encoding::US_ASCII && node.parts.size == 1 && !fragment_text(node, node.parts[0], pinned) &&
           first.is_a?(Literal) && first.value == ""
          parts = [Literal.new(String.new(encoding: ::Encoding::BINARY), line), *parts.drop(1)]
        end
        fragments = ArrayLit.new(parts.map { |part| Interp.new([part], line) }, line)
        args = [fragments, Literal.new(regexp_options(node), line), Literal.new(pinned && ::Encoding.list.index(pinned), line)]
        made = Send.of(ConstRead.new(nil, :Regexp, line), :interpolated, args, line)
        return made unless node.once?

        # CRuby compiles the interpolation of a `/o` regexp as a block of
        # its own (`once`), so a backtrace from inside it shows `block in`.
        none = Params.new([], [], nil, [], [], nil, nil)
        RegexpOnce.new(Send.of(Core.new(:Kernel, line), :post_exe, [], line, block: Block.new(none, [], deepen(made, 0), line)), line)
      end

      # pm_interpolated_node_compile: ruby's compiler reads the escapes and
      # the multibyte characters of each literal fragment, and of a String
      # literal that is all of an interpolation, before the program runs
      # (parse_regexp_string_part). It joins the fragments that follow
      # each other, which raises for two encodings that do not mix.
      #: (untyped node, Encoding? pinned) -> void
      def check_fragments(node, pinned)
        joined = nil #: String?
        text_part = false
        node.parts.each do |part|
          text = fragment_text(node, part, pinned)
          if text
            check_fragment(node, text)
            if joined
              both = joined_fragment(node, joined, text, text_part || part.is_a?(Prism::StringNode))
              check_fragment(node, both)
              joined = both
            else
              joined = text
            end
            text_part ||= part.is_a?(Prism::StringNode)
          else
            joined = nil
            text_part = false
          end
        end
      end

      # Two literal fragments that follow each other, as one text. Two
      # String literals of encodings that do not mix raise as a join of
      # Strings does; with text of the pattern among them, a byte past
      # ASCII next to a UTF-8 character is the parser's error.
      #: (untyped node, String joined, String text, bool text_part) -> String
      def joined_fragment(node, joined, text, text_part)
        joined + text
      rescue ::Encoding::CompatibilityError
        raise unless text_part

        invalid(node, "non ASCII character in UTF-8 regexp")
      end

      # The text of a literal fragment, or nil for an interpolation.
      #: (untyped node, Prism::node part, Encoding? pinned) -> String?
      def fragment_text(node, part, pinned)
        if part.is_a?(Prism::EmbeddedStatementsNode) && (body = part.statements&.body) && body.size == 1 && body[0].is_a?(Prism::StringNode)
          part = body[0]
        end
        return unless part.is_a?(Prism::StringNode)

        text = unescaped(part).dup
        encoding = node.ascii_8bit? ? ::Encoding::BINARY : pinned
        text.force_encoding(encoding) if encoding
        text
      end

      # The engine reads the escapes before it compiles anything, so its
      # error for a fragment is one of rb_reg_preprocess's, or none: a
      # fragment alone is often no whole pattern (`(`), which is no error.
      # Its warnings are dropped: ruby warns for the whole pattern, where a
      # fragment's `]` can close a class that another fragment opened.
      #: (untyped node, String text) -> void
      def check_fragment(node, text)
        read_pattern(text, regexp_options(node) & 2)
      rescue RegexpError => e
        invalid(node, e.message) if PREPROCESS_ERRORS.any? { |known| e.message.start_with?(known) }
      end

      # Used in place of $stderr while a check compiles a pattern. It keeps
      # what the engine writes.
      class Written < String
        #: (*_ToS parts) -> Integer
        def write(*parts) = parts.sum { |part| concat(part.to_s) && part.to_s.bytesize }
      end

      # Whether this build keeps the engine's warnings, and does not let
      # the engine print them.
      #: () -> bool
      def keeps_warnings? = !@loader&.eval?

      # The engine's warnings for `held`, as [verbose, message] rows. The
      # read is also the check: an invalid pattern raises.
      #
      # A build replaces $stderr and $VERBOSE to keep them, because it
      # forks and nothing else in that process writes. An eval compile runs
      # inside the program, where all threads share the two. There, zr's
      # own Regexp compiler gives the rows, and the program's toplevel
      # prints them at the literal's file and line, as ruby's parser does.
      #: (String held, Integer options) -> Array[[bool, String]]
      def read_pattern(held, options)
        return compiled_warnings(held, options) unless keeps_warnings?

        written = Written.new
        stderr = $stderr
        verbose = $VERBOSE
        begin
          # Ruby takes any object with a `write` as $stderr, but RBS types
          # it as an IO.
          $stderr = written # steep:ignore IncompatibleAssignment
          $VERBOSE = false
          Regexp.new(held, options)
          written.scan(/warning: (.*)$/).map { |(message)| [false, message.to_s] } #: Array[[bool, String]]
        ensure
          $stderr = stderr
          $VERBOSE = verbose
        end
      end

      # The rows of zr's own Regexp compiler. CRuby, which runs an eval
      # compile on the host, has no such compiler: there the engine prints
      # its own warnings.
      #: (String held, Integer options) -> Array[[bool, String]]
      def compiled_warnings(held, options)
        rows = Regexp.send(:compiled, held, Regexp.send(:option_bits, options))[4]
        rows.map { |verbose, text| [verbose, text.to_s] }
      rescue NoMethodError
        Regexp.new(held, options)
        []
      end

      # The branch that a literal condition always selects, or nil if the
      # program decides. Ruby's compiler writes no code for the other
      # branch and does not read it: `if false then /[q-a]/ end` runs, and
      # `if 1 == 2 then /[q-a]/ end` does not.
      #: (Prism::node node) -> bool?
      def chooses?(node)
        case node
        when Prism::TrueNode then true
        when Prism::FalseNode, Prism::NilNode then false
        end
      end

      # Whether a condition can be true, and whether it can be false, as
      # CRuby's compiler knows them from its literals (compile_branch_condition):
      # `x and false` is never true, and `x or true` never false. A branch
      # that it cannot take is code that CRuby does not compile.
      #: (Prism::node node) -> [bool, bool]
      def reaches(node)
        case node
        when Prism::AndNode
          left_true, left_false = reaches(node.left)
          right_true, right_false = reaches(node.right)
          [left_true && right_true, left_false || (left_true && right_false)]
        when Prism::OrNode
          left_true, left_false = reaches(node.left)
          right_true, right_false = reaches(node.right)
          [left_true || (left_false && right_true), left_false && right_false]
        else
          chosen = chooses?(node)
          [chosen != false, chosen != true]
        end
      end

      #: (Prism::RegularExpressionNode | Prism::MatchLastLineNode node, Integer line, ?taken: bool) -> (RegexpLit | Seq)
      def regexp_literal(node, line, taken: true)
        # This literal's value is not used, so ruby never reads the
        # pattern, and zr does not either. An invalid one here is a
        # program that runs. An interpolated regexp is a Send, not this,
        # and it still runs its parts.
        return Seq.new([], line) unless taken

        pinned = regexp_encoding(node)
        # `n` reads the pattern as bytes, so a non-ASCII escape is valid
        # only there. The check must read it the same way.
        held = node.unescaped.dup.force_encoding(node.ascii_8bit? ? ::Encoding::BINARY : (pinned || node.unescaped.encoding))
        read_pattern(held, regexp_options(node)).each do |verbose, message|
          @warnings << "#{Loader::VERBOSE_WARNING if verbose}#{Paths.shown(@file)}:#{line}: warning: #{message}"
        end
        RegexpLit.new(node.unescaped, regexp_options(node), pinned, line)
      rescue RegexpError => e
        invalid(node, "#{e.message.sub(/: \/.*\z/m, "")}: /#{node.unescaped}/")
      end

      # The parts of an interpolated string, each a String or the value
      # of an embedded expression.
      #: (untyped node, Integer line) -> Interp
      def interpolation(node, line)
        parts = node.parts.map do |part|
          case part
          when Prism::StringNode then Literal.new(unescaped(part), part.location.start_line)
          when Prism::EmbeddedStatementsNode then part.statements ? embedded(part.statements) : Literal.new(nil, line)
          when Prism::EmbeddedVariableNode then expr(part.variable)
          when Prism::InterpolatedStringNode then interpolation(part, line)
          else unsupported(part, "#{Refused.form_of(part)} in a string")
          end
        end
        # A single embedded part is joined to an empty literal in the
        # source's encoding, which gives the result's start encoding, as
        # ruby's compiler does.
        parts.unshift(Literal.new(String.new(encoding: text_encoding), line)) if node.parts.size == 1 && !node.parts[0].is_a?(Prism::StringNode)
        # If refinements are active, each part gets `to_s` at its own site,
        # which does the lookup with them. Ruby folds a String or Symbol
        # part into the text first, and a String or Symbol value skips the
        # refined `to_s` at run time.
        parts = parts.map { |part| folded?(part) ? part : Send.of(part, :to_s, [], line, interp: true) } if @using
        Interp.new(parts, line)
      end

      # The code of a `#{}`, whose own literals keep the source's encoding
      # in a raise's message too.
      #: (Prism::StatementsNode statements) -> node
      def embedded(statements)
        message = @in_c_message
        begin
          @in_c_message = nil
          seq(statements)
        ensure
          @in_c_message = message
        end
      end

      #: (node part) -> bool
      def folded?(part)
        part = part.stmts.first if part.is_a?(Seq) && part.stmts.size == 1
        part.is_a?(Interp) || (part.is_a?(Literal) && [String, Symbol].include?(part.value.class))
      end
    end
  end
end
