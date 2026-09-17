# frozen_string_literal: true

require "spec_helper"

describe "Ripper programs" do
  it "ripper sexp lex and events" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer "[:program,\n [[:def,\n   [:@ident, \"m\", [1, 4]],\n   [:paren,\n    [:params,\n     [[:@ident, \"a\", [1, 6]]],\n     [[[:@ident, \"b\", [1, 9]], [:@int, \"1\", [1, 13]]]],\n     nil,\n     nil,\n     nil,\n     nil,\n     nil]],\n   [:bodystmt,\n    [:binary,\n     [:var_ref, [:@ident, \"a\", [1, 18]]],\n     :+,\n     [:var_ref, [:@ident, \"b\", [1, 22]]]],\n    nil,\n    nil,\n    nil]],\n  [:assign,\n   [:var_field, [:@ident, \"x\", [2, 0]]],\n   [:string_literal,\n    [:string_content,\n     [:@tstring_content, \"one \", [3, 2]],\n     [:string_embexpr, [[:var_ref, [:@ident, \"x\", [3, 8]]]]],\n     [:@tstring_content, \"\\n\", [3, 10]],\n     [:@tstring_content, \"  two\\n\", [4, 2]]]]],\n  [:method_add_block,\n   [:call,\n    [:array, [[:@int, \"1\", [6, 1]], [:@int, \"2\", [6, 4]]]],\n    [:@period, \".\", [6, 6]],\n    [:@ident, \"map\", [6, 7]]],\n   [:brace_block,\n    [:block_var,\n     [:params, [[:@ident, \"v\", [6, 14]]], nil, nil, nil, nil, nil, nil],\n     false],\n    [[:binary,\n      [:var_ref, [:@ident, \"v\", [6, 17]]],\n      :*,\n      [:@int, \"2\", [6, 21]]]]]],\n  [:class,\n   [:const_ref, [:@const, \"Foo\", [7, 6]]],\n   [:var_ref, [:@const, \"Bar\", [7, 12]]],\n   [:bodystmt,\n    [[:command,\n      [:@ident, \"attr_reader\", [7, 17]],\n      [:args_add_block,\n       [[:symbol_literal, [:symbol, [:@ident, \"q\", [7, 30]]]]],\n       false]]],\n    nil,\n    nil,\n    nil]],\n  [:case,\n   [:vcall, [:@ident, \"y\", [8, 5]]],\n   [:in,\n    [:aryptn,\n     nil,\n     [[:binary,\n       [:var_ref, [:@const, \"Integer\", [9, 4]]],\n       :\"=>\",\n       [:var_field, [:@ident, \"n\", [9, 15]]]]],\n     [:var_field, nil],\n     nil],\n    [[:var_ref, [:@ident, \"n\", [9, 26]]]],\n    nil]],\n  [:command,\n   [:@ident, \"puts\", [11, 0]],\n   [:args_add_block,\n    [[:string_literal,\n      [:string_content,\n       [:@tstring_content, \"a\", [11, 6]],\n       [:string_embexpr, [[:vcall, [:@ident, \"b\", [11, 9]]]]],\n       [:@tstring_content, \"c\", [11, 11]]]],\n     [:symbol_literal, [:symbol, [:@ident, \"sym\", [11, 16]]]],\n     [:@rational, \"1.5r\", [11, 21]],\n     [:@CHAR, \"?x\", [11, 27]]],\n    false]]]]\n[:program,\n [:stmts_add,\n  [:stmts_new],\n  [:method_add_arg,\n   [:call,\n    [:vcall, [:@ident, \"a\", [1, 0]]],\n    [:@period, \".\", [1, 1]],\n    [:@ident, \"b\", [1, 2]]],\n   [:arg_paren,\n    [:args_add_block,\n     [:args_add, [:args_new], [:@int, \"1\", [1, 4]]],\n     false]]]]]\n[[[1, 0], :on_kw, \"def\"],\n [[1, 3], :on_sp, \" \"],\n [[1, 4], :on_ident, \"m\"],\n [[1, 5], :on_lparen, \"(\"],\n [[1, 6], :on_ident, \"a\"],\n [[1, 7], :on_comma, \",\"],\n [[1, 8], :on_sp, \" \"],\n [[1, 9], :on_ident, \"b\"],\n [[1, 10], :on_sp, \" \"],\n [[1, 11], :on_op, \"=\"],\n [[1, 12], :on_sp, \" \"],\n [[1, 13], :on_int, \"1\"],\n [[1, 14], :on_rparen, \")\"],\n [[1, 15], :on_sp, \" \"],\n [[1, 16], :on_op, \"=\"],\n [[1, 17], :on_sp, \" \"],\n [[1, 18], :on_ident, \"a\"],\n [[1, 19], :on_sp, \" \"],\n [[1, 20], :on_op, \"+\"],\n [[1, 21], :on_sp, \" \"],\n [[1, 22], :on_ident, \"b\"],\n [[1, 23], :on_nl, \"\\n\"],\n [[2, 0], :on_ident, \"x\"],\n [[2, 1], :on_sp, \" \"],\n [[2, 2], :on_op, \"=\"],\n [[2, 3], :on_sp, \" \"],\n [[2, 4], :on_heredoc_beg, \"<<~H\"],\n [[2, 8], :on_nl, \"\\n\"],\n [[3, 0], :on_ignored_sp, \"  \"],\n [[3, 2], :on_tstring_content, \"one \"],\n [[3, 6], :on_embexpr_beg, \"\\\#{\"],\n [[3, 8], :on_ident, \"x\"],\n [[3, 9], :on_embexpr_end, \"}\"],\n [[3, 10], :on_tstring_content, \"\\n\"],\n [[4, 0], :on_ignored_sp, \"  \"],\n [[4, 2], :on_tstring_content, \"  two\\n\"],\n [[5, 0], :on_heredoc_end, \"H\\n\"],\n [[6, 0], :on_lbracket, \"[\"],\n [[6, 1], :on_int, \"1\"],\n [[6, 2], :on_comma, \",\"],\n [[6, 3], :on_sp, \" \"],\n [[6, 4], :on_int, \"2\"],\n [[6, 5], :on_rbracket, \"]\"],\n [[6, 6], :on_period, \".\"],\n [[6, 7], :on_ident, \"map\"],\n [[6, 10], :on_sp, \" \"],\n [[6, 11], :on_lbrace, \"{\"],\n [[6, 12], :on_sp, \" \"],\n [[6, 13], :on_op, \"|\"],\n [[6, 14], :on_ident, \"v\"],\n [[6, 15], :on_op, \"|\"],\n [[6, 16], :on_sp, \" \"],\n [[6, 17], :on_ident, \"v\"],\n [[6, 18], :on_sp, \" \"],\n [[6, 19], :on_op, \"*\"],\n [[6, 20], :on_sp, \" \"],\n [[6, 21], :on_int, \"2\"],\n [[6, 22], :on_sp, \" \"],\n [[6, 23], :on_rbrace, \"}\"],\n [[6, 24], :on_sp, \" \"],\n [[6, 25], :on_comment, \"# note\\n\"],\n [[7, 0], :on_kw, \"class\"],\n [[7, 5], :on_sp, \" \"],\n [[7, 6], :on_const, \"Foo\"],\n [[7, 9], :on_sp, \" \"],\n [[7, 10], :on_op, \"<\"],\n [[7, 11], :on_sp, \" \"],\n [[7, 12], :on_const, \"Bar\"],\n [[7, 15], :on_semicolon, \";\"],\n [[7, 16], :on_sp, \" \"],\n [[7, 17], :on_ident, \"attr_reader\"],\n [[7, 28], :on_sp, \" \"],\n [[7, 29], :on_symbeg, \":\"],\n [[7, 30], :on_ident, \"q\"],\n [[7, 31], :on_semicolon, \";\"],\n [[7, 32], :on_sp, \" \"],\n [[7, 33], :on_kw, \"end\"],\n [[7, 36], :on_nl, \"\\n\"],\n [[8, 0], :on_kw, \"case\"],\n [[8, 4], :on_sp, \" \"],\n [[8, 5], :on_ident, \"y\"],\n [[8, 6], :on_nl, \"\\n\"],\n [[9, 0], :on_kw, \"in\"],\n [[9, 2], :on_sp, \" \"],\n [[9, 3], :on_lbracket, \"[\"],\n [[9, 4], :on_const, \"Integer\"],\n [[9, 11], :on_sp, \" \"],\n [[9, 12], :on_op, \"=>\"],\n [[9, 14], :on_sp, \" \"],\n [[9, 15], :on_ident, \"n\"],\n [[9, 16], :on_comma, \",\"],\n [[9, 17], :on_sp, \" \"],\n [[9, 18], :on_op, \"*\"],\n [[9, 19], :on_rbracket, \"]\"],\n [[9, 20], :on_sp, \" \"],\n [[9, 21], :on_kw, \"then\"],\n [[9, 25], :on_sp, \" \"],\n [[9, 26], :on_ident, \"n\"],\n [[9, 27], :on_nl, \"\\n\"],\n [[10, 0], :on_kw, \"end\"],\n [[10, 3], :on_nl, \"\\n\"],\n [[11, 0], :on_ident, \"puts\"],\n [[11, 4], :on_sp, \" \"],\n [[11, 5], :on_tstring_beg, \"\\\"\"],\n [[11, 6], :on_tstring_content, \"a\"],\n [[11, 7], :on_embexpr_beg, \"\\\#{\"],\n [[11, 9], :on_ident, \"b\"],\n [[11, 10], :on_embexpr_end, \"}\"],\n [[11, 11], :on_tstring_content, \"c\"],\n [[11, 12], :on_tstring_end, \"\\\"\"],\n [[11, 13], :on_comma, \",\"],\n [[11, 14], :on_sp, \" \"],\n [[11, 15], :on_symbeg, \":\"],\n [[11, 16], :on_ident, \"sym\"],\n [[11, 19], :on_comma, \",\"],\n [[11, 20], :on_sp, \" \"],\n [[11, 21], :on_rational, \"1.5r\"],\n [[11, 25], :on_comma, \",\"],\n [[11, 26], :on_sp, \" \"],\n [[11, 27], :on_CHAR, \"?x\"],\n [[11, 29], :on_nl, \"\\n\"]]\n[\"def\", \" \", \"m\", \"(\", \"a\", \")\", \" \", \"nil\", \" \", \"end\"]\n\"m\"\nnil\n[[[1, 0], :on_kw, \"def\"], [[1, 3], :on_sp, \" \"], [[1, 4], :on_lparen, \"(\"]]\n{on_ident: 2, on_sp: 4, on_op: 2, on_int: 1}\n[nil, nil, \"(ripper)\"]\nnil\n2\n\"BEG|LABEL\"\nSyntaxError\n"
  end
end
