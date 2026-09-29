# frozen_string_literal: true

require "spec_helper"

describe "Ripper programs" do
  it "sexp, lex, slice, a Filter and a subclass's own events all answer over prism" do
    result = zr(<<~'RUBY')
      # Ripper over prism: sexp and sexp_raw, the tokens lex and tokenize
      # answer, slice, a Filter, a subclass's own events with the position each
      # one stands at, and the errors a broken program reports.
      require "ripper"
      require "pp"
      src = <<~'RB'
        def m(a, b = 1) = a + b
        x = <<~H
          one #{x}
            two
        H
        [1, 2].map { |v| v * 2 } # note
        class Foo < Bar; attr_reader :q; end
        case y
        in [Integer => n, *] then n
        end
        puts "a#{b}c", :sym, 1.5r, ?x
      RB
      pp Ripper.sexp(src)
      pp Ripper.sexp_raw("a.b(1)")
      pp Ripper.lex(src).map { |pos, event, tok, _state| [pos, event, tok] }
      p Ripper.tokenize("def m(a) nil end")
      p Ripper.slice("def m(a) nil end", "ident")
      p Ripper.sexp("def (")
      p Ripper.lex("def (").map { |pos, event, tok, _state| [pos, event, tok] }
      class Counter < Ripper::Filter
        def on_default(event, tok, data) = data.merge(event => data.fetch(event, 0) + 1)
      end
      p Counter.new("a = 1 + b").parse({})
      r = Ripper.new("foo(1)")
      p [r.lineno, r.column, r.filename]
      class Show < Ripper
        def on_int(t) = [:int, t, lineno, column, state]
        def on_method_add_arg(c, a) = [:mad, c, a]
      end
      p Show.new("foo(1)").parse
      p Ripper.dedent_string(+"    hello", 2)
      p Ripper.lex_state_name(Ripper::EXPR_BEG | Ripper::EXPR_LABEL)
      begin
        Ripper.sexp("def (", raise_errors: true)
      rescue SyntaxError => e
        p e.class
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [:program,
       [[:def,
         [:@ident, "m", [1, 4]],
         [:paren,
          [:params,
           [[:@ident, "a", [1, 6]]],
           [[[:@ident, "b", [1, 9]], [:@int, "1", [1, 13]]]],
           nil,
           nil,
           nil,
           nil,
           nil]],
         [:bodystmt,
          [:binary,
           [:var_ref, [:@ident, "a", [1, 18]]],
           :+,
           [:var_ref, [:@ident, "b", [1, 22]]]],
          nil,
          nil,
          nil]],
        [:assign,
         [:var_field, [:@ident, "x", [2, 0]]],
         [:string_literal,
          [:string_content,
           [:@tstring_content, "one ", [3, 2]],
           [:string_embexpr, [[:var_ref, [:@ident, "x", [3, 8]]]]],
           [:@tstring_content, "\n", [3, 10]],
           [:@tstring_content, "  two\n", [4, 2]]]]],
        [:method_add_block,
         [:call,
          [:array, [[:@int, "1", [6, 1]], [:@int, "2", [6, 4]]]],
          [:@period, ".", [6, 6]],
          [:@ident, "map", [6, 7]]],
         [:brace_block,
          [:block_var,
           [:params, [[:@ident, "v", [6, 14]]], nil, nil, nil, nil, nil, nil],
           false],
          [[:binary,
            [:var_ref, [:@ident, "v", [6, 17]]],
            :*,
            [:@int, "2", [6, 21]]]]]],
        [:class,
         [:const_ref, [:@const, "Foo", [7, 6]]],
         [:var_ref, [:@const, "Bar", [7, 12]]],
         [:bodystmt,
          [[:command,
            [:@ident, "attr_reader", [7, 17]],
            [:args_add_block,
             [[:symbol_literal, [:symbol, [:@ident, "q", [7, 30]]]]],
             false]]],
          nil,
          nil,
          nil]],
        [:case,
         [:vcall, [:@ident, "y", [8, 5]]],
         [:in,
          [:aryptn,
           nil,
           [[:binary,
             [:var_ref, [:@const, "Integer", [9, 4]]],
             :"=>",
             [:var_field, [:@ident, "n", [9, 15]]]]],
           [:var_field, nil],
           nil],
          [[:var_ref, [:@ident, "n", [9, 26]]]],
          nil]],
        [:command,
         [:@ident, "puts", [11, 0]],
         [:args_add_block,
          [[:string_literal,
            [:string_content,
             [:@tstring_content, "a", [11, 6]],
             [:string_embexpr, [[:vcall, [:@ident, "b", [11, 9]]]]],
             [:@tstring_content, "c", [11, 11]]]],
           [:symbol_literal, [:symbol, [:@ident, "sym", [11, 16]]]],
           [:@rational, "1.5r", [11, 21]],
           [:@CHAR, "?x", [11, 27]]],
          false]]]]
      [:program,
       [:stmts_add,
        [:stmts_new],
        [:method_add_arg,
         [:call,
          [:vcall, [:@ident, "a", [1, 0]]],
          [:@period, ".", [1, 1]],
          [:@ident, "b", [1, 2]]],
         [:arg_paren,
          [:args_add_block,
           [:args_add, [:args_new], [:@int, "1", [1, 4]]],
           false]]]]]
      [[[1, 0], :on_kw, "def"],
       [[1, 3], :on_sp, " "],
       [[1, 4], :on_ident, "m"],
       [[1, 5], :on_lparen, "("],
       [[1, 6], :on_ident, "a"],
       [[1, 7], :on_comma, ","],
       [[1, 8], :on_sp, " "],
       [[1, 9], :on_ident, "b"],
       [[1, 10], :on_sp, " "],
       [[1, 11], :on_op, "="],
       [[1, 12], :on_sp, " "],
       [[1, 13], :on_int, "1"],
       [[1, 14], :on_rparen, ")"],
       [[1, 15], :on_sp, " "],
       [[1, 16], :on_op, "="],
       [[1, 17], :on_sp, " "],
       [[1, 18], :on_ident, "a"],
       [[1, 19], :on_sp, " "],
       [[1, 20], :on_op, "+"],
       [[1, 21], :on_sp, " "],
       [[1, 22], :on_ident, "b"],
       [[1, 23], :on_nl, "\n"],
       [[2, 0], :on_ident, "x"],
       [[2, 1], :on_sp, " "],
       [[2, 2], :on_op, "="],
       [[2, 3], :on_sp, " "],
       [[2, 4], :on_heredoc_beg, "<<~H"],
       [[2, 8], :on_nl, "\n"],
       [[3, 0], :on_ignored_sp, "  "],
       [[3, 2], :on_tstring_content, "one "],
       [[3, 6], :on_embexpr_beg, "\#{"],
       [[3, 8], :on_ident, "x"],
       [[3, 9], :on_embexpr_end, "}"],
       [[3, 10], :on_tstring_content, "\n"],
       [[4, 0], :on_ignored_sp, "  "],
       [[4, 2], :on_tstring_content, "  two\n"],
       [[5, 0], :on_heredoc_end, "H\n"],
       [[6, 0], :on_lbracket, "["],
       [[6, 1], :on_int, "1"],
       [[6, 2], :on_comma, ","],
       [[6, 3], :on_sp, " "],
       [[6, 4], :on_int, "2"],
       [[6, 5], :on_rbracket, "]"],
       [[6, 6], :on_period, "."],
       [[6, 7], :on_ident, "map"],
       [[6, 10], :on_sp, " "],
       [[6, 11], :on_lbrace, "{"],
       [[6, 12], :on_sp, " "],
       [[6, 13], :on_op, "|"],
       [[6, 14], :on_ident, "v"],
       [[6, 15], :on_op, "|"],
       [[6, 16], :on_sp, " "],
       [[6, 17], :on_ident, "v"],
       [[6, 18], :on_sp, " "],
       [[6, 19], :on_op, "*"],
       [[6, 20], :on_sp, " "],
       [[6, 21], :on_int, "2"],
       [[6, 22], :on_sp, " "],
       [[6, 23], :on_rbrace, "}"],
       [[6, 24], :on_sp, " "],
       [[6, 25], :on_comment, "# note\n"],
       [[7, 0], :on_kw, "class"],
       [[7, 5], :on_sp, " "],
       [[7, 6], :on_const, "Foo"],
       [[7, 9], :on_sp, " "],
       [[7, 10], :on_op, "<"],
       [[7, 11], :on_sp, " "],
       [[7, 12], :on_const, "Bar"],
       [[7, 15], :on_semicolon, ";"],
       [[7, 16], :on_sp, " "],
       [[7, 17], :on_ident, "attr_reader"],
       [[7, 28], :on_sp, " "],
       [[7, 29], :on_symbeg, ":"],
       [[7, 30], :on_ident, "q"],
       [[7, 31], :on_semicolon, ";"],
       [[7, 32], :on_sp, " "],
       [[7, 33], :on_kw, "end"],
       [[7, 36], :on_nl, "\n"],
       [[8, 0], :on_kw, "case"],
       [[8, 4], :on_sp, " "],
       [[8, 5], :on_ident, "y"],
       [[8, 6], :on_nl, "\n"],
       [[9, 0], :on_kw, "in"],
       [[9, 2], :on_sp, " "],
       [[9, 3], :on_lbracket, "["],
       [[9, 4], :on_const, "Integer"],
       [[9, 11], :on_sp, " "],
       [[9, 12], :on_op, "=>"],
       [[9, 14], :on_sp, " "],
       [[9, 15], :on_ident, "n"],
       [[9, 16], :on_comma, ","],
       [[9, 17], :on_sp, " "],
       [[9, 18], :on_op, "*"],
       [[9, 19], :on_rbracket, "]"],
       [[9, 20], :on_sp, " "],
       [[9, 21], :on_kw, "then"],
       [[9, 25], :on_sp, " "],
       [[9, 26], :on_ident, "n"],
       [[9, 27], :on_nl, "\n"],
       [[10, 0], :on_kw, "end"],
       [[10, 3], :on_nl, "\n"],
       [[11, 0], :on_ident, "puts"],
       [[11, 4], :on_sp, " "],
       [[11, 5], :on_tstring_beg, "\""],
       [[11, 6], :on_tstring_content, "a"],
       [[11, 7], :on_embexpr_beg, "\#{"],
       [[11, 9], :on_ident, "b"],
       [[11, 10], :on_embexpr_end, "}"],
       [[11, 11], :on_tstring_content, "c"],
       [[11, 12], :on_tstring_end, "\""],
       [[11, 13], :on_comma, ","],
       [[11, 14], :on_sp, " "],
       [[11, 15], :on_symbeg, ":"],
       [[11, 16], :on_ident, "sym"],
       [[11, 19], :on_comma, ","],
       [[11, 20], :on_sp, " "],
       [[11, 21], :on_rational, "1.5r"],
       [[11, 25], :on_comma, ","],
       [[11, 26], :on_sp, " "],
       [[11, 27], :on_CHAR, "?x"],
       [[11, 29], :on_nl, "\n"]]
      ["def", " ", "m", "(", "a", ")", " ", "nil", " ", "end"]
      "m"
      nil
      [[[1, 0], :on_kw, "def"], [[1, 3], :on_sp, " "], [[1, 4], :on_lparen, "("]]
      {on_ident: 2, on_sp: 4, on_op: 2, on_int: 1}
      [nil, nil, "(ripper)"]
      nil
      2
      "BEG|LABEL"
      SyntaxError
    OUT
  end

  it "a jump with nowhere to go is a parse error, and a heredoc's end keeps its state" do
    result = zr(<<~'RUBY')
      # A jump with nowhere to go is a parse error, so sexp is nil, and the
      # state after a heredoc's end is the state its body had.
      require "ripper"
      class Errors < Ripper::SexpBuilder
        def on_parse_error(message) = (print "#{message}; "; super)
      end
      ["yield 1", "break", "next", "redo", "-> { yield }", "module M; yield; end", "def f = yield", "[].each { break }"].each do |source|
        Errors.new(source).parse
        puts Ripper.sexp(source).nil?
      end
      p Ripper.lex("<<~X\n  q\nX\nx").map { |(_, event, _, state)| [event, state.to_s] }
    RUBY

    _(result).must_answer <<~'OUT'
      Invalid yield; true
      Invalid break; true
      Invalid next; true
      Invalid redo; true
      Invalid yield; true
      Invalid yield; true
      false
      false
      [[:on_heredoc_beg, "BEG"], [:on_nl, "BEG"], [:on_ignored_sp, "BEG"], [:on_tstring_content, "BEG"], [:on_heredoc_end, "BEG"], [:on_ident, "CMDARG"]]
    OUT
  end
  it "a lexer that starts at line 0 gives each token its line, as irb lexes" do
    result = zr(<<~'RUBY')
      # irb puts a line that declares its local variables before the code
      # and lexes from line 0, so the code starts at line 1.
      require "ripper"
      p Ripper::Lexer.new("x=nil;\np x\n", "-", 0).scan.map { |t| [t.pos, t.event, t.tok] }
    RUBY

    _(result).must_answer <<~'OUT'
      [[[0, 0], :on_ident, "x"], [[0, 1], :on_op, "="], [[0, 2], :on_kw, "nil"], [[0, 5], :on_semicolon, ";"], [[0, 6], :on_ignored_nl, "\n"], [[1, 0], :on_ident, "p"], [[1, 1], :on_sp, " "], [[1, 2], :on_ident, "x"], [[1, 3], :on_nl, "\n"]]
    OUT
  end
end
