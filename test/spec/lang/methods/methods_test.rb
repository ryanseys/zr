# frozen_string_literal: true

require "spec_helper"

describe "Methods programs" do
  it "aliasing a genuinely undefined method is a runtime name error" do
    skip "ruby's did_you_mean writes 'Did you mean?  undef_method' between the message and the backtrace, " \
         "and a compiled program carries no did_you_mean"
    result = ze0(<<~'RUBY', path: "lang/methods/aliasing_a_genuinely_undefined_method_is_a_runtime_name_error.rb")
      # An `alias`/`alias_method` whose source is defined neither in this body
      # nor anywhere in the ancestry COMPILES (the compiler can't distinguish a
      # typo from a runtime-table builtin source, `alias_method :dup!, :dup`)
      # and raises `NameError` at program start instead -- real Ruby's timing,
      # the class body executing. See `mro::resolve_aliases` /
      # `zeo_rt::validate_aliases`; the full-message shape is asserted in
      # `methods::an_alias_whose_source_resolves_nowhere_is_a_name_error_at_program_start`.

      class Foo
        alias bar undefined_method
      end
    RUBY

    _(result).must_answer "", stderr: "lang/methods/aliasing_a_genuinely_undefined_method_is_a_runtime_name_error.rb:10:in '<class:Foo>': undefined method 'undefined_method' for class 'Foo' (NameError)\n\tfrom lang/methods/aliasing_a_genuinely_undefined_method_is_a_runtime_name_error.rb:9:in '<main>'\n", status: 1
  end

  it "arg forwarding fixed callee" do
    result = ze0(<<~'RUBY')
      # Forwarding preserves both channels when the callee mixes a flexible channel
      # with a fixed positional or keyword parameter.
      def rest_and_fixed_kw(*a, k: 0) = [a, k]
      def forward_to_rest_and_fixed_kw(...) = rest_and_fixed_kw(...)
      p forward_to_rest_and_fixed_kw(1, 2, k: 9)
      p forward_to_rest_and_fixed_kw(3)

      def fixed_pos_and_kwrest(x, **k) = [x, k]
      def forward_to_fixed_pos_and_kwrest(...) = fixed_pos_and_kwrest(...)
      p forward_to_fixed_pos_and_kwrest(4, extra: 8)
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], 9]
      [[3], 0]
      [4, {extra: 8}]
    OUT
  end

  it "arg forwarding limits" do
    result = ze0(<<~'RUBY')
      # Exercise the former fixed-size forwarding rewrite buffers.
      def collect(*a) = a.length

      def many_forwarding_calls(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
        collect(...)
      end
      p many_forwarding_calls(1, 2, 3)

      def many_explicit_arguments(...) = collect(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, ...)
      p many_explicit_arguments(1, 2, 3)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      70
    OUT
  end

  it "ast translator builds splat lists like parse y" do
    result = ze0(<<~'RUBY')
      # `RubyVM::AbstractSyntaxTree` maps prism's node kinds onto CRuby's NODE_*
      # names, and the shapes the two disagree about were all one family: a list
      # with a SPLAT in it, and the empty statement CRuby's grammar leaves at the
      # head of certain bodies.
      #
      # CRuby builds every element list with `arg_append`/`arg_concat` (parse.y),
      # and the accumulator changes SHAPE as the splats land. A run of plain
      # elements is a `LIST`; a splat concatenates onto it (`ARGSCAT`, whose body is
      # the splatted VALUE, not a `SPLAT` node); a plain element after a splat
      # pushes onto that (`ARGSPUSH`); and a SECOND plain element folds the push
      # back into an `ARGSCAT` over a two-element `LIST`. zeo emitted a flat `LIST`
      # of everything, which was right only when there was no splat -- for a call's
      # arguments, an array literal, a `when`'s conditions and a multiple
      # assignment alike.
      #
      # The empty statement is `stmts: none` reducing to `NEW_BEGIN(0)` before the
      # first real one, so a body whose text starts with a terminator carries a
      # zero-width `BEGIN nil` ahead of it, at the position the statements list
      # starts parsing. WHICH terminators survive is a grammar fact, measured
      # against the oracle: a `\n` is absorbed everywhere something can take it
      # (`def`'s arglist, `while`'s `do`, `if`'s `then`, a `class ... < Super`'s
      # term, a block's parameter list) while a `;` never is -- except in a
      # `class`/`module` body with NO superclass clause, where nothing is there to
      # take either.
      #
      # Two spans follow the same separator rule: a `when` arm and a `rescue`/
      # `ensure` clause run THROUGH a `;` that terminates them, and stop at their
      # last statement when there is none.
      #
      # And a `begin ... end` is a `BEGIN` wrapper in EXPRESSION position and bare
      # as a statement, which is the one thing prism's node cannot say for itself.

      def dump(n, d = 0)
        return puts("#{'  ' * d}#{n.inspect}") unless n.is_a?(RubyVM::AbstractSyntaxTree::Node)
        puts "#{'  ' * d}#{n.type} #{n.first_lineno},#{n.first_column}-#{n.last_lineno},#{n.last_column}"
        n.children.each { |c| dump(c, d + 1) }
      end

      [
        # The splat family, in every position that builds an element list.
        "case x; when *y, 3 then 1; end",
        "case x; when *y, 3, 4 then 1; end",
        "case x; when 1, *y then 1; end",
        "case x; when 1, *y, 2 then 1; end",
        "case x; when *y then 1; end",
        "f(*y, 3)",
        "f(1, *y)",
        "[*y, 3]",
        "[1, *y, 2]",
        "a = *y, 3",
        # The empty statement, and the terminators that do and do not survive.
        "x = begin; 1; rescue; 2; end",
        "x = begin; 1; ensure; 2; end",
        "x = begin\n1\nend",
        "x = begin 1 end",
        "begin; 1; rescue; 2; end",
        "class K\n1\nend",
        "class K; 1; end",
        "class K < Object\n1\nend",
        "class K;end",
        "module M\n1\nend",
        "class << self\n1\nend",
        "def m; 1; end",
        "def m; ; 1; end",
        "while x; 1; end",
        "if x; 1; end",
        "[1].each do |z|\n1\nend",
        "[1].each do |z|; 1; end",
        "[1].each {; 1 }",
        "x = (1)",
        "x = (; 1)",
        # The arm and clause spans that run through their separator.
        "case x; when 1 then 2; end",
        "case x; when 1 then 2 end",
        "case x; when 1; end",
        # Node kinds that used to answer :UNKNOWN.
        "A::B",
        "::A::B",
        "A::B = 1",
        "x = __FILE__",
        "x = __LINE__",
        # Interpolated literals, in CRuby's three-child shape.
        '"a#{b}c#{d}e"',
        '"#{b}"',
        '"#{1}#{2}"',
        '"a#@iv"',
        '"a#{ }b"',
        ':"a#{b}"',
        '/a#{b}/',
        '`a#{b}`',
        # Adjacent string literals are ONE literal, and the second lends its span to
        # the interpolation it consists of.
        '"a" "#{b}"',
        # A heredoc part ends AT its newline: a column past that line's last
        # character, not column 0 of the next one.
        "x = <<~H\n  a\#{b}\nH",
      ].each do |s|
        puts "### #{s.inspect}"
        dump(RubyVM::AbstractSyntaxTree.parse(s))
      end
    RUBY

    _(result).must_answer "### \"case x; when *y, 3 then 1; end\"\nSCOPE 1,0-1,30\n  []\n  nil\n  CASE 1,0-1,30\n    VCALL 1,5-1,6\n      :x\n    WHEN 1,8-1,26\n      ARGSPUSH 1,13-1,18\n        SPLAT 1,13-1,15\n          VCALL 1,14-1,15\n            :y\n        INTEGER 1,17-1,18\n          3\n      INTEGER 1,24-1,25\n        1\n      nil\n### \"case x; when *y, 3, 4 then 1; end\"\nSCOPE 1,0-1,33\n  []\n  nil\n  CASE 1,0-1,33\n    VCALL 1,5-1,6\n      :x\n    WHEN 1,8-1,29\n      ARGSCAT 1,13-1,21\n        SPLAT 1,13-1,15\n          VCALL 1,14-1,15\n            :y\n        LIST 1,17-1,21\n          INTEGER 1,17-1,18\n            3\n          INTEGER 1,20-1,21\n            4\n          nil\n      INTEGER 1,27-1,28\n        1\n      nil\n### \"case x; when 1, *y then 1; end\"\nSCOPE 1,0-1,30\n  []\n  nil\n  CASE 1,0-1,30\n    VCALL 1,5-1,6\n      :x\n    WHEN 1,8-1,26\n      ARGSCAT 1,13-1,18\n        LIST 1,13-1,14\n          INTEGER 1,13-1,14\n            1\n          nil\n        VCALL 1,17-1,18\n          :y\n      INTEGER 1,24-1,25\n        1\n      nil\n### \"case x; when 1, *y, 2 then 1; end\"\nSCOPE 1,0-1,33\n  []\n  nil\n  CASE 1,0-1,33\n    VCALL 1,5-1,6\n      :x\n    WHEN 1,8-1,29\n      ARGSPUSH 1,13-1,21\n        ARGSCAT 1,13-1,18\n          LIST 1,13-1,14\n            INTEGER 1,13-1,14\n              1\n            nil\n          VCALL 1,17-1,18\n            :y\n        INTEGER 1,20-1,21\n          2\n      INTEGER 1,27-1,28\n        1\n      nil\n### \"case x; when *y then 1; end\"\nSCOPE 1,0-1,27\n  []\n  nil\n  CASE 1,0-1,27\n    VCALL 1,5-1,6\n      :x\n    WHEN 1,8-1,23\n      SPLAT 1,13-1,15\n        VCALL 1,14-1,15\n          :y\n      INTEGER 1,21-1,22\n        1\n      nil\n### \"f(*y, 3)\"\nSCOPE 1,0-1,8\n  []\n  nil\n  FCALL 1,0-1,8\n    :f\n    ARGSPUSH 1,2-1,7\n      SPLAT 1,2-1,4\n        VCALL 1,3-1,4\n          :y\n      INTEGER 1,6-1,7\n        3\n### \"f(1, *y)\"\nSCOPE 1,0-1,8\n  []\n  nil\n  FCALL 1,0-1,8\n    :f\n    ARGSCAT 1,2-1,7\n      LIST 1,2-1,3\n        INTEGER 1,2-1,3\n          1\n        nil\n      VCALL 1,6-1,7\n        :y\n### \"[*y, 3]\"\nSCOPE 1,0-1,7\n  []\n  nil\n  ARGSPUSH 1,0-1,7\n    SPLAT 1,1-1,3\n      VCALL 1,2-1,3\n        :y\n    INTEGER 1,5-1,6\n      3\n### \"[1, *y, 2]\"\nSCOPE 1,0-1,10\n  []\n  nil\n  ARGSPUSH 1,0-1,10\n    ARGSCAT 1,1-1,6\n      LIST 1,1-1,2\n        INTEGER 1,1-1,2\n          1\n        nil\n      VCALL 1,5-1,6\n        :y\n    INTEGER 1,8-1,9\n      2\n### \"a = *y, 3\"\nSCOPE 1,0-1,9\n  [:a]\n  nil\n  LASGN 1,0-1,9\n    :a\n    ARGSPUSH 1,4-1,9\n      SPLAT 1,4-1,6\n        VCALL 1,5-1,6\n          :y\n      INTEGER 1,8-1,9\n        3\n### \"x = begin; 1; rescue; 2; end\"\nSCOPE 1,0-1,28\n  [:x]\n  nil\n  LASGN 1,0-1,28\n    :x\n    BEGIN 1,4-1,28\n      RESCUE 1,9-1,24\n        BLOCK 1,9-1,12\n          BEGIN 1,9-1,9\n            nil\n          INTEGER 1,11-1,12\n            1\n        RESBODY 1,14-1,24\n          nil\n          nil\n          INTEGER 1,22-1,23\n            2\n          nil\n        nil\n### \"x = begin; 1; ensure; 2; end\"\nSCOPE 1,0-1,28\n  [:x]\n  nil\n  LASGN 1,0-1,28\n    :x\n    BEGIN 1,4-1,28\n      ENSURE 1,9-1,24\n        BLOCK 1,9-1,12\n          BEGIN 1,9-1,9\n            nil\n          INTEGER 1,11-1,12\n            1\n        BLOCK 1,20-1,23\n          BEGIN 1,20-1,20\n            nil\n          INTEGER 1,22-1,23\n            2\n### \"x = begin\\n1\\nend\"\nSCOPE 1,0-3,3\n  [:x]\n  nil\n  LASGN 1,0-3,3\n    :x\n    BEGIN 1,4-3,3\n      INTEGER 2,0-2,1\n        1\n### \"x = begin 1 end\"\nSCOPE 1,0-1,15\n  [:x]\n  nil\n  LASGN 1,0-1,15\n    :x\n    BEGIN 1,4-1,15\n      INTEGER 1,10-1,11\n        1\n### \"begin; 1; rescue; 2; end\"\nSCOPE 1,0-1,24\n  []\n  nil\n  RESCUE 1,5-1,20\n    BLOCK 1,5-1,8\n      BEGIN 1,5-1,5\n        nil\n      INTEGER 1,7-1,8\n        1\n    RESBODY 1,10-1,20\n      nil\n      nil\n      INTEGER 1,18-1,19\n        2\n      nil\n    nil\n### \"class K\\n1\\nend\"\nSCOPE 1,0-3,3\n  []\n  nil\n  CLASS 1,0-3,3\n    COLON2 1,6-1,7\n      nil\n      :K\n    nil\n    SCOPE 1,0-3,3\n      []\n      nil\n      BLOCK 1,7-2,1\n        BEGIN 1,7-1,7\n          nil\n        INTEGER 2,0-2,1\n          1\n### \"class K; 1; end\"\nSCOPE 1,0-1,15\n  []\n  nil\n  CLASS 1,0-1,15\n    COLON2 1,6-1,7\n      nil\n      :K\n    nil\n    SCOPE 1,0-1,15\n      []\n      nil\n      BLOCK 1,7-1,10\n        BEGIN 1,7-1,7\n          nil\n        INTEGER 1,9-1,10\n          1\n### \"class K < Object\\n1\\nend\"\nSCOPE 1,0-3,3\n  []\n  nil\n  CLASS 1,0-3,3\n    COLON2 1,6-1,7\n      nil\n      :K\n    CONST 1,10-1,16\n      :Object\n    SCOPE 1,0-3,3\n      []\n      nil\n      INTEGER 2,0-2,1\n        1\n### \"class K;end\"\nSCOPE 1,0-1,11\n  []\n  nil\n  CLASS 1,0-1,11\n    COLON2 1,6-1,7\n      nil\n      :K\n    nil\n    SCOPE 1,0-1,11\n      []\n      nil\n      BEGIN 1,7-1,7\n        nil\n### \"module M\\n1\\nend\"\nSCOPE 1,0-3,3\n  []\n  nil\n  MODULE 1,0-3,3\n    COLON2 1,7-1,8\n      nil\n      :M\n    SCOPE 1,0-3,3\n      []\n      nil\n      BLOCK 1,8-2,1\n        BEGIN 1,8-1,8\n          nil\n        INTEGER 2,0-2,1\n          1\n### \"class << self\\n1\\nend\"\nSCOPE 1,0-3,3\n  []\n  nil\n  SCLASS 1,0-3,3\n    SELF 1,9-1,13\n    SCOPE 1,0-3,3\n      []\n      nil\n      INTEGER 2,0-2,1\n        1\n### \"def m; 1; end\"\nSCOPE 1,0-1,13\n  []\n  nil\n  DEFN 1,0-1,13\n    :m\n    SCOPE 1,0-1,13\n      []\n      ARGS 1,5-1,5\n        0\n        nil\n        nil\n        nil\n        0\n        nil\n        nil\n        nil\n        nil\n        nil\n      INTEGER 1,7-1,8\n        1\n### \"def m; ; 1; end\"\nSCOPE 1,0-1,15\n  []\n  nil\n  DEFN 1,0-1,15\n    :m\n    SCOPE 1,0-1,15\n      []\n      ARGS 1,5-1,5\n        0\n        nil\n        nil\n        nil\n        0\n        nil\n        nil\n        nil\n        nil\n        nil\n      BLOCK 1,6-1,10\n        BEGIN 1,6-1,6\n          nil\n        INTEGER 1,9-1,10\n          1\n### \"while x; 1; end\"\nSCOPE 1,0-1,15\n  []\n  nil\n  WHILE 1,0-1,15\n    VCALL 1,6-1,7\n      :x\n    INTEGER 1,9-1,10\n      1\n    true\n### \"if x; 1; end\"\nSCOPE 1,0-1,12\n  []\n  nil\n  IF 1,0-1,12\n    VCALL 1,3-1,4\n      :x\n    INTEGER 1,6-1,7\n      1\n    nil\n### \"[1].each do |z|\\n1\\nend\"\nSCOPE 1,0-3,3\n  []\n  nil\n  ITER 1,0-3,3\n    CALL 1,0-1,8\n      LIST 1,0-1,3\n        INTEGER 1,1-1,2\n          1\n        nil\n      :each\n      nil\n    SCOPE 1,9-3,3\n      [:z]\n      ARGS 1,13-1,14\n        1\n        nil\n        nil\n        nil\n        0\n        nil\n        nil\n        nil\n        nil\n        nil\n      INTEGER 2,0-2,1\n        1\n### \"[1].each do |z|; 1; end\"\nSCOPE 1,0-1,23\n  []\n  nil\n  ITER 1,0-1,23\n    CALL 1,0-1,8\n      LIST 1,0-1,3\n        INTEGER 1,1-1,2\n          1\n        nil\n      :each\n      nil\n    SCOPE 1,9-1,23\n      [:z]\n      ARGS 1,13-1,14\n        1\n        nil\n        nil\n        nil\n        0\n        nil\n        nil\n        nil\n        nil\n        nil\n      BLOCK 1,15-1,18\n        BEGIN 1,15-1,15\n          nil\n        INTEGER 1,17-1,18\n          1\n### \"[1].each {; 1 }\"\nSCOPE 1,0-1,15\n  []\n  nil\n  ITER 1,0-1,15\n    CALL 1,0-1,8\n      LIST 1,0-1,3\n        INTEGER 1,1-1,2\n          1\n        nil\n      :each\n      nil\n    SCOPE 1,9-1,15\n      []\n      nil\n      BLOCK 1,10-1,13\n        BEGIN 1,10-1,10\n          nil\n        INTEGER 1,12-1,13\n          1\n### \"x = (1)\"\nSCOPE 1,0-1,7\n  [:x]\n  nil\n  LASGN 1,0-1,7\n    :x\n    BLOCK 1,4-1,7\n      INTEGER 1,5-1,6\n        1\n### \"x = (; 1)\"\nSCOPE 1,0-1,9\n  [:x]\n  nil\n  LASGN 1,0-1,9\n    :x\n    BLOCK 1,4-1,9\n      BLOCK 1,5-1,8\n        BEGIN 1,5-1,5\n          nil\n        INTEGER 1,7-1,8\n          1\n### \"case x; when 1 then 2; end\"\nSCOPE 1,0-1,26\n  []\n  nil\n  CASE 1,0-1,26\n    VCALL 1,5-1,6\n      :x\n    WHEN 1,8-1,22\n      LIST 1,13-1,14\n        INTEGER 1,13-1,14\n          1\n        nil\n      INTEGER 1,20-1,21\n        2\n      nil\n### \"case x; when 1 then 2 end\"\nSCOPE 1,0-1,25\n  []\n  nil\n  CASE 1,0-1,25\n    VCALL 1,5-1,6\n      :x\n    WHEN 1,8-1,21\n      LIST 1,13-1,14\n        INTEGER 1,13-1,14\n          1\n        nil\n      INTEGER 1,20-1,21\n        2\n      nil\n### \"case x; when 1; end\"\nSCOPE 1,0-1,19\n  []\n  nil\n  CASE 1,0-1,19\n    VCALL 1,5-1,6\n      :x\n    WHEN 1,8-1,15\n      LIST 1,13-1,14\n        INTEGER 1,13-1,14\n          1\n        nil\n      BEGIN 1,15-1,15\n        nil\n      nil\n### \"A::B\"\nSCOPE 1,0-1,4\n  []\n  nil\n  COLON2 1,0-1,4\n    CONST 1,0-1,1\n      :A\n    :B\n### \"::A::B\"\nSCOPE 1,0-1,6\n  []\n  nil\n  COLON2 1,0-1,6\n    COLON3 1,0-1,3\n      :A\n    :B\n### \"A::B = 1\"\nSCOPE 1,0-1,8\n  []\n  nil\n  CDECL 1,0-1,8\n    COLON2 1,0-1,4\n      CONST 1,0-1,1\n        :A\n      :B\n    :B\n    INTEGER 1,7-1,8\n      1\n### \"x = __FILE__\"\nSCOPE 1,0-1,12\n  [:x]\n  nil\n  LASGN 1,0-1,12\n    :x\n    FILE 1,4-1,12\n      \"\"\n### \"x = __LINE__\"\nSCOPE 1,0-1,12\n  [:x]\n  nil\n  LASGN 1,0-1,12\n    :x\n    LINE 1,4-1,12\n      1\n### \"\\\"a\\\#{b}c\\\#{d}e\\\"\"\nSCOPE 1,0-1,13\n  []\n  nil\n  DSTR 1,0-1,13\n    \"a\"\n    EVSTR 1,2-1,6\n      VCALL 1,4-1,5\n        :b\n    LIST 1,6-1,7\n      STR 1,6-1,7\n        \"c\"\n      EVSTR 1,7-1,11\n        VCALL 1,9-1,10\n          :d\n      STR 1,11-1,12\n        \"e\"\n      nil\n### \"\\\"\\\#{b}\\\"\"\nSCOPE 1,0-1,6\n  []\n  nil\n  DSTR 1,0-1,6\n    \"\"\n    EVSTR 1,0-1,6\n      VCALL 1,3-1,4\n        :b\n    nil\n### \"\\\"\\\#{1}\\\#{2}\\\"\"\nSCOPE 1,0-1,10\n  []\n  nil\n  DSTR 1,0-1,10\n    \"\"\n    EVSTR 1,1-1,5\n      INTEGER 1,3-1,4\n        1\n    LIST 1,5-1,9\n      EVSTR 1,5-1,9\n        INTEGER 1,7-1,8\n          2\n      nil\n### \"\\\"a\\\#@iv\\\"\"\nSCOPE 1,0-1,7\n  []\n  nil\n  DSTR 1,0-1,7\n    \"a\"\n    EVSTR 1,2-1,6\n      IVAR 1,3-1,6\n        :@iv\n    nil\n### \"\\\"a\\\#{ }b\\\"\"\nSCOPE 1,0-1,8\n  []\n  nil\n  DSTR 1,0-1,8\n    \"a\"\n    EVSTR 1,2-1,6\n      BEGIN 1,4-1,4\n        nil\n    LIST 1,6-1,7\n      STR 1,6-1,7\n        \"b\"\n      nil\n### \":\\\"a\\\#{b}\\\"\"\nSCOPE 1,0-1,8\n  []\n  nil\n  DSYM 1,0-1,8\n    \"a\"\n    EVSTR 1,3-1,7\n      VCALL 1,5-1,6\n        :b\n    nil\n### \"/a\\\#{b}/\"\nSCOPE 1,0-1,7\n  []\n  nil\n  DREGX 1,0-1,7\n    \"a\"\n    EVSTR 1,2-1,6\n      VCALL 1,4-1,5\n        :b\n    nil\n### \"`a\\\#{b}`\"\nSCOPE 1,0-1,7\n  []\n  nil\n  DXSTR 1,0-1,7\n    \"a\"\n    EVSTR 1,2-1,6\n      VCALL 1,4-1,5\n        :b\n    nil\n### \"\\\"a\\\" \\\"\\\#{b}\\\"\"\nSCOPE 1,0-1,10\n  []\n  nil\n  DSTR 1,0-1,10\n    \"a\"\n    EVSTR 1,4-1,10\n      VCALL 1,7-1,8\n        :b\n    nil\n### \"x = <<~H\\n  a\\\#{b}\\nH\"\nSCOPE 1,0-1,8\n  [:x]\n  nil\n  LASGN 1,0-1,8\n    :x\n    DSTR 1,4-1,8\n      \"a\"\n      EVSTR 2,3-2,7\n        VCALL 2,5-2,6\n          :b\n      LIST 2,7-2,8\n        STR 2,7-2,8\n          \"\\n\"\n        nil\n"
  end

  it "attr" do
    result = ze0(<<~'RUBY')
      # Test attr_accessor, attr_reader, attr_writer, class methods, for..in, loop

      class Point
        attr_accessor :x, :y

        def initialize(x, y)
          @x = x
          @y = y
        end

        def self.origin
          Point.new(0, 0)
        end

        def distance_to(other)
          dx = @x - other.x
          dy = @y - other.y
          Math.sqrt(dx * dx + dy * dy)
        end

        def to_s
          "(" + @x.to_s + ", " + @y.to_s + ")"
        end
      end

      p1 = Point.new(3, 4)
      puts p1.x        # 3
      puts p1.y        # 4
      p1.x = 10
      puts p1.x        # 10

      p2 = Point.origin
      puts p2.x        # 0

      # for..in with range
      total = 0
      for i in 1..10
        total += i
      end
      puts total        # 55

      # loop with break
      count = 0
      loop do
        count += 1
        break if count >= 5
      end
      puts count        # 5

      # Array#each with index (using each)
      arr = (1..5).to_a
      sum = 0
      arr.each do |x|
        sum += x
      end
      puts sum          # 15

      # String#to_s on object
      puts p1.to_s      # (10, 4)

      # attr_accessor path should keep ivar/local namespaces distinct.
      class IvarCollision
        attr_accessor :x, :iv_x

        def initialize
          @x = 1
          @iv_x = 2
        end

        def sum
          x = 10
          iv_x = 20
          @x + @iv_x + self.x + self.iv_x + x + iv_x
        end
      end

      puts IvarCollision.new.sum   # 36
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      10
      0
      55
      5
      15
      (10, 4)
      36
    OUT
  end

  it "attributes undefined dsl" do
    result = ze0(<<~'RUBY')
      # The spinel-era compile-time `attributes` DSL does not exist: CRuby (and
      # zeo) raise NoMethodError when the class body executes. Rescued inside
      # the body so the output is path-portable.
      class BadAttributes
        begin
          attributes "name"
        rescue NoMethodError => e
          puts "rescued: #{e.message}"
        end
      end
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      rescued: undefined method 'attributes' for class BadAttributes
      after
    OUT
  end

  it "bound method obj recv" do
    result = ze0(<<~'RUBY')
      # `<obj>.method(:bar)` — bind to a receiver that's not the current
      # `self`. The Method's iv_self_obj must end up holding the
      # receiver, not the *enclosing* class's `self`.
      #
      # Note: Method#call(x) lowers to a function pointer cast to
      # `(void *, mrb_int...) -> mrb_int`, so the bound underlying method
      # must return an int. Non-int returns are out of scope for this PR.

      class Worker
        def initialize(base)
          @base = base
        end
        def shout(x)
          @base + x
        end
      end

      # (a) bound on a local variable
      def via_local
        w = Worker.new(100)
        w.method(:shout)
      end
      puts via_local.call(42)   # 142

      # (b) bound on an ivar from another class
      class Boss
        def initialize
          @worker = Worker.new(1000)
        end
        def via_ivar
          @worker.method(:shout)
        end
      end
      puts Boss.new.via_ivar.call(99)   # 1099

      # (c) array of Methods on a non-self receiver
      def fns
        w = Worker.new(10)
        [w.method(:shout), w.method(:shout)]
      end
      fns.each {|bm| puts bm.call(7) }   # 17, 17
    RUBY

    _(result).must_answer <<~'OUT'
      142
      1099
      17
      17
    OUT
  end

  it "bound method single eval" do
    result = ze0(<<~'RUBY')
      # Issue #215 / Gemini-review-critical: the receiver expression in
      # `<recv>.method(:foo).call(args)` and `<recv>.method(:foo)[args]`
      # must be evaluated exactly once. The Method#call lowering reads
      # both `iv_fn_ptr` and `iv_self_obj` off the receiver — a naive
      # `((cast)rc->iv_fn_ptr)((void *)rc->iv_self_obj, args)` evaluates
      # `rc` twice, so a side-effecting receiver fires its side effect
      # twice (and pays the cost twice).
      #
      # This test exercises a Method whose source receiver is the result
      # of a side-effecting call. The side-effect counter must increment
      # exactly once per `bm.call`, not twice.

      class Worker
        def initialize(base)
          @base = base
        end
        def shout(x)
          @base + x
        end
      end

      $count = 0

      def make_worker
        $count = $count + 1
        Worker.new(100)
      end

      # Chained: the receiver of `.call` is the whole make_worker.method(...)
      # expression. Double-eval would fire the side effect twice.
      puts make_worker.method(:shout).call(7)   # 107
      puts $count                                # 1

      # Same shape via Method#[].
      $count = 0
      puts make_worker.method(:shout)[42]        # 142
      puts $count                                # 1
    RUBY

    _(result).must_answer <<~'OUT'
      107
      1
      142
      1
    OUT
  end

  it "call op write def writer" do
    result = ze0(<<~'RUBY')
      # `obj.attr op= v` when the writer is a hand-written `def attr=`: Ruby means a
      # reader call and a writer call, and the writer's body has to run (#3809).
      class Rect
        attr_reader :x, :writes
        def initialize
          @x = 0
          @writes = 0
        end

        def x=(v)
          @writes += 1
          @x = v
        end
      end

      r = Rect.new
      r.x += 1
      r.x += 2
      r.x -= 1
      p r.x
      p r.writes

      class Counted
        def initialize
          @n = 5
        end
        def n
          @n
        end
        def n=(v)
          @n = v * 10
        end
      end

      cc = Counted.new
      cc.n += 1
      p cc.n

      # the attr_accessor form still works
      class Plain
        attr_accessor :y
        def initialize
          @y = 3
        end
      end
      p2 = Plain.new
      p2.y += 4
      p p2.y
    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      60
      7
    OUT
  end

  it "class method site stays correct when the class changes" do
    result = ze0(<<~'RUBY')
      # A `Target.name` call site caches the class method it resolved. Everything
      # that can make that answer wrong must still win.

      module Shape
        def self.area(n) = n * n
        def self.secret = :hidden
        private_class_method :secret
      end

      3.times { print Shape.area(3), " " }
      puts

      begin
        Shape.secret
      rescue NoMethodError => e
        p e.class
      end

      # A runtime singleton definition beats a site that already filled.
      class Counter
        def self.tick = 1
      end
      p [Counter.tick, Counter.tick]
      def Counter.tick = 2
      p [Counter.tick, Counter.tick]

      # An `extend`ed module supplies a class method through the singleton ancestry.
      module Greet
        def hello = "hi"
      end
      class Host
        extend Greet
      end
      p [Host.hello, Host.hello]

      # `method_missing` on the singleton answers where no method exists.
      class Ghost
        def self.method_missing(n, *a) = [n, a]
        def self.respond_to_missing?(_n, _p = false) = true
      end
      p Ghost.anything(1, 2)
      p Ghost.anything(1, 2)

      # Builtin class methods keep working under repetition.
      p [Integer.sqrt(16), Integer.sqrt(16)]
      p [Math.hypot(3, 4), Math.hypot(3, 4)]
      p [String.new("x"), String.new("x")]

      # A minted Struct class's own singleton methods shadow `Struct.new`.
      Point = Struct.new(:x, :y)
      p Point.members
      p Point[1, 2].to_a
      p Point.new(3, 4).to_a

      # A class method reached through inheritance.
      class Base
        def self.tag = "base"
      end
      class Sub < Base; end
      p [Sub.tag, Sub.tag]

      # The same name on two classes must not share one site's answer.
      class A1
        def self.who = :a
      end
      class B1
        def self.who = :b
      end
      2.times { print A1.who, B1.who, " " }
      puts
    RUBY

    _(result).must_answer "9 9 9 \nNoMethodError\n[1, 1]\n[2, 2]\n[\"hi\", \"hi\"]\n[:anything, [1, 2]]\n[:anything, [1, 2]]\n[4, 4]\n[5.0, 5.0]\n[\"x\", \"x\"]\n[:x, :y]\n[1, 2]\n[3, 4]\n[\"base\", \"base\"]\nab ab \n"
  end

  it "constant declared in a superclass resolves from a subclass method" do
    result = ze0(<<~'RUBY')
      class Base
        X = 1
      end
      class Sub < Base
        def get
          X
        end
      end
      puts Sub.new.get
    RUBY

    _(result).must_answer "1\n"
  end

  it "cvar method first assign" do
    result = ze0(<<~'RUBY')
      class C
        def self.set; @@x = 5; end
        def self.get; @@x; end
      end
      C.set
      p C.get
    RUBY

    _(result).must_answer "5\n"
  end

  it "def in the source has a home of its own" do
    result = ze0(<<~'RUBY')
      # `super`, `yield` and `return` need the enclosing method's identity,
      # block channel and return target -- which a snippet's own level does
      # not have, but a `def` written INSIDE it does: the emitter's
      # run-time-installed body reads its defining class off the method
      # frame stack. So the refusal is about where they sit, not what they
      # are.

      class Base
        def greet = "base"
      end
      class Kid < Base; end
      src = "def greet; %(kid+) + super; end"
      Kid.class_eval(src)
      p Kid.new.greet
      yielder = "def y_it; yield 5; end"
      eval(yielder)
      p(y_it { |v| v * 3 })
    RUBY

    _(result).must_answer <<~'OUT'
      "kid+base"
      15
    OUT
  end

  it "def tail empty literal" do
    result = ze0(<<~'RUBY')
      class A
        def items
          []
        end
        def opts
          {}
        end
        def self.defaults
          {}
        end
      end
      puts A.new.items.length
      puts A.new.opts.length
      puts A.defaults.length
      p A.new.items
      p A.new.opts
      a = A.new.items
      a << 5
      p a
      h = A.new.opts
      h["k"] = 1
      p h.length
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
      []
      {}
      [5]
      1
    OUT
  end

  it "defined of a rewritten call is a method" do
    result = ze0(<<~'RUBY')
      # `defined?` never runs its call, so a call the compiler would rewrite
      # (`!x`, `"lit".freeze`, a `require` of a literal name) still answers
      # "method", as any other call to a method that exists does.
      x = 1
      p defined?(!x)
      p defined?("a".freeze)
      p defined?(require "set")
      p defined?(x.nope)
      p defined?(!nope_at_all)

    RUBY

    _(result).must_answer <<~'OUT'
      "method"
      "method"
      "method"
      nil
      nil
    OUT
  end

  it "destructure splat underflow" do
    result = ze0(<<~'RUBY')
      # A splat multi-assign with fewer RHS elements than the fixed targets empties
      # the splat and nil-fills the trailing targets, rather than wrapping indices.
      def s(x); x; end
      a, *b, c = s([1]);          p [a, b, c]
      a, *b, c = s([1, 2]);       p [a, b, c]
      a, *b, c = s([1, 2, 3]);    p [a, b, c]
      a, *b, c = s([1, 2, 3, 4]); p [a, b, c]
      w, *x, y, z = s([1, 2]);    p [w, x, y, z]

      # The same clamping applies when a post-splat target is an instance variable.
      class C
        def set(arr)
          a, *b, @c = arr
          p [a, b, @c]
        end
      end
      C.new.set([1])
      C.new.set([1, 2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      [1, [], nil]
      [1, [], 2]
      [1, [2], 3]
      [1, [2, 3], 4]
      [1, [], 2, nil]
      [1, [], nil]
      [1, [2], 3]
    OUT
  end

  it "dotdotdot leading param forward" do
    result = ze0(<<~'RUBY')
      # `def f(a, ...)` binds the leading param and forwards only the rest; plain
      # `def f(...)` forwards everything.
      def g(b, c) = [b, c]
      def one_leading(a, ...) = g(...)
      p one_leading(1, 2, 3)
      def g3(x, y, z) = [x, y, z]
      def two_leading(a, b, ...) = g3(...)
      p two_leading(1, 2, 3, 4, 5)
      def plain(...) = g(...)
      p plain(9, 8)
      def gk(x, k:) = [x, k]
      def fwd_kw(a, ...) = gk(...)
      p fwd_kw(1, 2, k: 3)
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      [3, 4, 5]
      [9, 8]
      [2, 3]
    OUT
  end

  it "eval defined method calls its module siblings" do
    result = ze0(<<~'PROGRAM')
      # A method installed by `module_eval` on a STRING can reach the module's other
      # methods through `self`. i18n's delegators do exactly that -- the eval'd
      # `backend=` calls `writable_config`, a literal `def` two lines above it.
      #
      # The seam is `extend`: an extended module's method has to run with the CLASS
      # as `self`. A compiled body needs an object receiver and gets a surrogate
      # whose class IS the extending class, and a runtime-defined body took that
      # same route -- so `self` read as an instance of Host and every sibling call
      # missed. A runtime body is already value-shaped and takes `self` directly.
      module Host
        module Base
          def helper = :helper

          %w(alpha).each do |name|
            module_eval <<-RUBY, __FILE__, __LINE__ + 1
              def #{name}
                helper
              end
            RUBY
          end
        end
        extend Base
      end

      p Host.alpha

      class Direct
        include Host::Base
      end
      p Direct.new.alpha

      # `self` is the module itself, not an instance of it, and the ivars it writes
      # are the extending object's own.
      module Wide
        module Api
          def helper = :helper
          def ivar_write; @stash = 7; end
          module_eval "def evald; [self.to_s, self.class.to_s, helper]; end"
          define_method(:defined_m) { [self.to_s, helper] }
        end
        extend Api
      end
      p Wide.evald
      p Wide.defined_m
      Wide.ivar_write
      p Wide.instance_variable_get(:@stash)
      p Wide.singleton_methods(false)
      p Wide.singleton_methods.sort
      p [Wide.method(:evald).owner.to_s, Wide.respond_to?(:evald)]

      # A class and a plain object extend the same way.
      class Klass
        extend Wide::Api
      end
      p Klass.evald
      o = Object.new
      o.extend(Wide::Api)
      p o.evald[1..]
    PROGRAM

    _(result).must_answer <<~'OUT'
      :helper
      :helper
      ["Wide", "Module", :helper]
      ["Wide", :helper]
      7
      []
      [:defined_m, :evald, :helper, :ivar_write]
      ["Wide::Api", true]
      ["Klass", "Class", :helper]
      ["Object", :helper]
    OUT
  end

  it "eval dynamic method call on evaluated receiver" do
    result = ze0(<<~'RUBY')
      src = "[3, 1, 2].sort.inspect"; puts eval(src)
    RUBY

    _(result).must_answer "[1, 2, 3]\n"
  end

  it "eval return belongs to the enclosing method" do
    result = ze0(<<~'RUBY')
      # A `return` written in a run-time `eval` returns from the METHOD the eval
      # sits in, exactly as one written there would. The signal is unmarked, so it
      # belongs to the nearest catcher -- and the enclosing method only pushes a
      # home when the compiler can see it might be needed, which is why an `eval`
      # anywhere in a body arms that catch.

      def straight
        eval("return 9".dup)
        1
      end
      p straight

      def after
        x = eval("return 8; 5".dup)
        p ["never", x]
        2
      end
      p after

      def through_a_block
        [1, 2, 3].each do |i|
          eval("return i * 10".dup) if i == 2
        end
        :fell_through
      end
      p through_a_block

      def under_an_ensure
        begin
          eval("return 7".dup)
        ensure
          puts "ensure ran"
        end
        :not_here
      end
      p under_an_ensure

      def value_of_the_eval
        eval("6".dup)
      end
      p value_of_the_eval

      # The program keeps running afterwards.
      p [1, 2].map { |i| i + 1 }
    RUBY

    _(result).must_answer <<~'OUT'
      9
      8
      20
      ensure ran
      7
      6
      [2, 3]
    OUT
  end

  it "explicit self dot method and bare self as a value" do
    result = ze0(<<~'RUBY')
      class Box
        def initialize(v)
          @v = v
        end

        def value
          @v
        end

        def describe
          self.value
        end

        def identity
          self
        end
      end

      b = Box.new(42)
      puts b.describe
      puts b.identity.value
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
    OUT
  end

  it "fallible class body constant and method default args" do
    result = ze0(<<~'RUBY')
      # `CONST = <fallible expr>` in a class body and `def m(a = <fallible>)`
      # both previously emitted `?` outside a Result context.

      def source
        41
      end
      class Config
        LIMIT = [1, 2, 3].sum
      end
      def bump(a = source + 1)
        a
      end
      puts Config::LIMIT
      puts bump
      puts bump(5)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      42
      5
    OUT
  end

  it "flat map pair index param" do
    result = ze0(<<~'RUBY')
      h = { 1 => [1], 2 => [2] }
      n = 0
      h.each_with_index.flat_map { |(k, g), i| n += 1; [k, i] }.each { |v| }
      p n

      a = [[1, 2], [3, 4]]
      m = 0
      p(a.each_with_index.flat_map { |(x, y), i| m += 1; [x, y, i] })
      p m

      p(a.each_with_index.flat_map { |(x, y), i| [i] })
    RUBY

    _(result).must_answer <<~'OUT'
      2
      [1, 2, 0, 3, 4, 1]
      2
      [0, 1]
    OUT
  end

  it "forward call param type inference" do
    result = ze0(<<~'RUBY')
      # Direct-call form (no caller-class wrapper): a top-level method
      # `apply` is the caller, target is a parameter. Verifies the callee's
      # param widening fires when the call is inside a top-level method
      # whose param type for `t` is itself widened from the caller-side
      # type.

      def apply(t, arr)
        t.set_data(arr)
        t
      end

      class Target
        def set_data(arr)
          @arr = arr
        end
        def length
          @arr.length
        end
      end

      t = Target.new
      apply(t, [10, 20, 30, 40])
      puts t.length
    RUBY

    _(result).must_answer "4\n"
  end

  it "getter push with user shift" do
    result = ze0(<<~'RUBY')
      # `dest.list << x` takes its element evidence through the getter's backing
      # ivar. The push was declined outright whenever ANY user class defined `<<`
      # (a bundled csv or a Set-like class is enough), so the ivar kept the empty
      # literal's bottom kind and every element read back as an Integer.

      class Collector
        def initialize
          @items = []
        end

        def <<(x)
          @items << x
          self
        end

        def size
          @items.size
        end
      end

      class Synapse
        attr_accessor :weight
        def initialize(w)
          @weight = w
        end
      end

      class Neuron
        attr_accessor :synapses_in

        def initialize
          @synapses_in = []
        end

        def bump(rate)
          synapses_in.each do |s|
            s.weight += rate
          end
        end

        def total
          synapses_in.reduce(0.0) { |acc, s| acc + s.weight }
        end
      end

      n = Neuron.new
      [0.5, 1.5].each { |w| n.synapses_in << Synapse.new(w) }
      n.bump(1.0)
      p n.total

      c = Collector.new
      c << 1 << 2
      p c.size
    RUBY

    _(result).must_answer <<~'OUT'
      4.0
      2
    OUT
  end

  it "grapheme clusters alias" do
    result = ze0(<<~'RUBY')
      # grapheme_clusters / each_grapheme_cluster alias to the chars/each_char
      # machinery -- equivalent over the supported text domain (no combining
      # sequences).
      p "hello".grapheme_clusters
      acc = []
      "abc".each_grapheme_cluster { |ch| acc << ch }
      p acc
      p "ab".each_grapheme_cluster.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      ["h", "e", "l", "l", "o"]
      ["a", "b", "c"]
      ["a", "b"]
    OUT
  end

  it "i1020" do
    result = ze0(<<~'RUBY')
      class Item
        def initialize(tag); @tag = tag; end
        attr_reader :tag
      end
      module S
        def self.root; Item.new("R"); end
        def self.list
          [Item.new("a"), Item.new("b"), Item.new("c"),
           Item.new("d"), Item.new("e"), Item.new("f"),
           Item.new("g"), Item.new("h"), Item.new("i")]
        end
      end

      def f(table)
        i = 0
        while i < table.length
          table[i]
          i += 1
        end
      end

      bad = 0
      i = 0
      while i < 50
        combined = [S.root] + S.list
        bad += 1 if combined.length != 10
        f(combined)
        i += 1
      end
      puts bad
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      0
      done
    OUT
  end

  it "isa scalar arm dead" do
    result = ze0(<<~'RUBY')
      # `x.is_a?(UserClass)` with a numeric receiver is statically false, so the arm
      # is dead -- and it is the only place the call in it comes from. Without
      # dropping it, `Int64.new(0)` (an Integer argument) made the emitter meet
      # `value.value` on an Integer and refuse the program.

      class Int64
        MASK64 = 0xFFFFFFFFFFFFFFFF
        attr_reader :value

        def initialize(value = 0)
          if value.is_a?(Int64)
            @value = value.value
          else
            v = value.to_i
            @value = v & MASK64
            @value -= (1 << 64) if @value & (1 << 63) != 0
          end
        end

        def /(other)
          b = other.value
          return Int64.new(0) if b == 0
          Int64.new(@value / b)
        end

        def %(other)
          b = other.value
          return Int64.new(0) if b == 0
          Int64.new(@value - (self / other).value * b)
        end

        def to_i
          @value
        end
      end

      a = Int64.new(17)
      b = Int64.new(5)
      p (a / b).to_i
      p (a % b).to_i
      p Int64.new(a).to_i
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      17
    OUT
  end

  it "issue class method owner" do
    result = ze0(<<~'RUBY')
      # `Method#owner` answered the CLASS for a class method, where ruby answers that
      # class's SINGLETON class -- which is also where `def self.a` actually put it.
      #
      # Uniform across user classes and builtins, so it was one shared helper on the
      # `MethodKind::Singleton` branch of `Method#owner` and `UnboundMethod#owner`.
      # The third case needed more: `Foo.singleton_class.instance_method(:a)` asks
      # the singleton class for an INSTANCE method, and `responds_to` had no
      # redirection to the owner's class-method side -- the one
      # `instance_method_visibility` already made.

      class Foo
        def self.a = 1
        def b = 2
      end

      p Foo.method(:a).owner
      p Time.method(:now).owner
      p Foo.singleton_class.instance_method(:a).owner

      # An INSTANCE method is unaffected, which is what makes this a singleton-branch
      # fix rather than a blanket one.
      p Foo.instance_method(:b).owner
      p Foo.new.method(:b).owner
      p Foo.method(:name).owner

      # The answer is a real class object, and the same one `singleton_class` gives.
      p Foo.method(:a).owner.equal?(Foo.singleton_class)
      p Foo.method(:a).owner.class
      p Foo.singleton_class.instance_method(:a).name
      p Foo.method(:a).unbind.owner

      # A module's class method, and an inherited one.
      module Util
        def self.helper = :helped
      end
      class Sub < Foo; end
      p Util.method(:helper).owner
      p Sub.method(:a).owner
    RUBY

    _(result).must_answer <<~'OUT'
      #<Class:Foo>
      #<Class:Time>
      #<Class:Foo>
      Foo
      Foo
      Module
      true
      Class
      :a
      #<Class:Foo>
      #<Class:Util>
      #<Class:Foo>
    OUT
  end

  it "keyword arguments fill their slots in order" do
    result = ze0(<<~'RUBY')
      # A keyword call whose keys are literal and cover the callee's required
      # keywords EXACTLY can fill the parameter slots at the call site. The two
      # orders it has to keep apart:
      #
      #   - keyword VALUES evaluate in WRITTEN order (they are ordinary argument
      #     expressions, and one of them can have a side effect)
      #   - they land in the callee's DECLARED order (which is the slot order)
      #
      # Every other pairing -- a missing key, a spare one, a `**` splat, a
      # non-literal key -- is the binder's question, and stays its question so
      # its error text cannot drift.
      def add(left:, right:) = left + right
      def mix(a, b, k:, j:) = [a, b, k, j]

      p add(left: 1, right: 2)
      p add(right: 2, left: 1)
      p mix(1, 2, j: 4, k: 3)

      $log = []
      def note(x) = ($log << x; x)
      p mix(note(:a), note(:b), j: note(:j), k: note(:k))
      p $log

      begin
        add(left: 1)
      rescue ArgumentError => e
        puts "missing: #{e.message}"
      end
      begin
        add(left: 1, right: 2, extra: 3)
      rescue ArgumentError => e
        puts "extra: #{e.message}"
      end

      h = { left: 1, right: 2 }
      p add(**h)
      p add(**{ left: 5, right: 6 })
      key = :left
      p add(key => 1, right: 9)

      # An OPTIONAL keyword keeps the binder -- deciding what is absent is its
      # whole job -- and so does a `**rest`.
      def opt(a:, b: a * 10) = [a, b]
      def rest(a:, **others) = [a, others]
      p opt(a: 1)
      p opt(a: 1, b: 2)
      p rest(a: 1, z: 26)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      [1, 2, 3, 4]
      [:a, :b, :k, :j]
      [:a, :b, :j, :k]
      missing: missing keyword: :right
      extra: unknown keyword: :extra
      3
      11
      10
      [1, 10]
      [1, 2]
      [1, {z: 26}]
    OUT
  end

  it "keyword flag truthiness" do
    result = ze0(<<~'RUBY')
      p "ab\n".each_line(chomp: 1).to_a
      p "ab\n".each_line(chomp: nil).to_a
      p "ab\ncd\n".lines(chomp: 1)
      p "ab\ncd\n".lines(chomp: false)
      p "ab\ncd\n".lines("\n", chomp: :yes)
      p "ab\ncd\n".lines("\n", chomp: nil)
      f = false
      t = "truthy"
      p "ab\n".lines(chomp: f)
      p "ab\n".lines(chomp: t)
      p "ab\n".each_line(chomp: t).to_a
      one = "/tmp/zeo_kwflag_#{Process.pid}_1.txt"
      two = "/tmp/zeo_kwflag_#{Process.pid}_2.txt"
      File.write(one, "a\nb\nc\n")
      File.open(one) do |fh|
        p fh.gets(chomp: "yes")
        p fh.readline(chomp: nil)
        p fh.gets(chomp: t)
      end
      File.delete(one)
      File.write(two, "a\nb\n")
      p File.readlines(two, chomp: 1)
      p File.readlines(two, chomp: f)
      p File.readlines(two, chomp: t)
      File.open(two) { |fh| p fh.readlines(chomp: :y) }
      File.open(two) { |fh| p fh.readlines(chomp: t) }
      File.delete(two)
    RUBY

    _(result).must_answer <<~'OUT'
      ["ab"]
      ["ab\n"]
      ["ab", "cd"]
      ["ab\n", "cd\n"]
      ["ab", "cd"]
      ["ab\n", "cd\n"]
      ["ab\n"]
      ["ab"]
      ["ab"]
      "a"
      "b\n"
      "c"
      ["a", "b"]
      ["a\n", "b\n"]
      ["a", "b"]
      ["a", "b"]
      ["a", "b"]
    OUT
  end

  it "keyword params bind by name regardless of call site order" do
    result = ze0(<<~'RUBY')
      class Kw
        def greet(x:, y: 10)
          x + y
        end
        def opts(**rest)
          rest.length
        end
      end
      k = Kw.new
      puts k.greet(x: 1)
      puts k.greet(x: 1, y: 2)
      puts k.greet(y: 3, x: 4)
      puts k.opts(a: 1, b: 2, c: 3)
    RUBY

    _(result).must_answer <<~'OUT'
      11
      3
      7
      3
    OUT
  end

  it "kwargs" do
    result = ze0(<<~'RUBY')
      # Test keyword arguments and splat

      def greet(name:, greeting: "Hello")
        puts greeting
        puts name
      end

      greet(name: "world")
      greet(name: "Ruby", greeting: "Hi")

      # Rest args (splat)
      def sum(*nums)
        total = 0
        nums.each do |n|
          total += n
        end
        total
      end

      puts sum(1, 2, 3)    # 6
      puts sum(10, 20)     # 30
    RUBY

    _(result).must_answer <<~'OUT'
      Hello
      world
      Hi
      Ruby
      6
      30
    OUT
  end

  it "kwargs double splat" do
    result = ze0(<<~'RUBY')
      # `foo(**h)` — double-splat a sym-keyed hash into the callee's
      # keyword params. Only the single-arg shape is wired here
      # (no positional + splat mixing); the splat hash must be
      # sym-keyed (sym_int/sym_str/sym_poly).
      def foo(a:, b:)
        puts "a=#{a} b=#{b}"
      end
      h = {a: 1, b: 2}
      foo(**h)

      def bar(x:, y:, z:)
        puts "#{x},#{y},#{z}"
      end
      h2 = {x: 10, y: 20, z: 30}
      bar(**h2)
    RUBY

    _(result).must_answer <<~'OUT'
      a=1 b=2
      10,20,30
    OUT
  end

  it "kwargs param widen" do
    result = ze0(<<~'RUBY')
      # Issue #314 (B): a module class method's required keyword params
      # never widened from the "int" default at scan_new_calls time. The
      # AST presents kwargs as a single trailing KeywordHashNode, and the
      # existing positional-only widening loop unified the hash type into
      # `ptypes[0]` and never touched the per-kwarg slots.
      #
      # Two complementary fixes:
      #  1. widen_ptypes_from_args helper that walks KeywordHashNode
      #     children, mapping each `key: value` pair to the matching
      #     keyword param's slot in the callee's ptypes array.
      #  2. compile_call_args_with_defaults / compile_call_args_splat
      #     emit-side: replace the hardcoded `sp_box_str(...)` for poly
      #     kwargs with `box_expr_to_poly(...)` so the box helper is
      #     picked from the arg's actual source type.
      #
      # Surfaced via Roundhouse's emitted real-blog `form_with(model:,
      # model_name:, action:, method:, opts:)` shape — minimal repro
      # extracted with two distinct obj types passed to the same kwarg.

      # Article/Comment have an array ivar so neither qualifies for the
      # value-type optimization — instances stay heap-allocated and the
      # captured-by-poly boxing site (`sp_box_obj`) sees a real pointer.
      # (Pure-int/string-ivar classes flowing into a poly param at a call
      # site is a separate, orthogonal value-type-exclusion concern that
      # surfaces only with inline `X.new(...)` directly inside a poly-
      # typed call slot — not exercised by this issue's Roundhouse trigger,
      # where the receiver is always a previously-allocated local.)

      class Article
        def initialize(id, name); @id = id; @name = name; @tags = []; end
        def kind; "article-" + @name; end
      end

      class Comment
        def initialize(body); @body = body; @replies = []; end
        def kind; "comment-" + @body; end
      end

      module M
        def self.render(model:, label:)
          "[#{label}] #{model.kind}"
        end
      end

      # Pre-allocate (matches the Roundhouse `lv_article` shape — locals
      # carry `sp_<C> *`, not struct-by-value).
      a = Article.new(7, "alpha")
      c = Comment.new("hello")

      # Two call sites with different obj types for `model:`. The widening
      # pass must collapse them to poly so the call-site box helper picks
      # sp_box_obj (not the pre-fix sp_box_str).
      puts M.render(model: a, label: "art")     # [art] article-alpha
      puts M.render(model: c, label: "com")     # [com] comment-hello

      # Module-inner class constructor inside a module class method
      # body. infer_function_body_call_types now pins
      # @current_method_name so resolve_const_read_name's
      # `<Mod>_cls_<m>` peel resolves `Inner` to `M_Inner` — pre-fix
      # the find_class_idx lookup returned -1 and skipped the
      # constructor-arg widening of N::Inner.@x.
      module N
        class Inner
          def initialize(x); @x = x; end
          def show; "inner=#{@x.kind}"; end
        end

        def self.make(model:)
          Inner.new(model).show
        end
      end

      puts N.make(model: a)                     # inner=article-alpha
    RUBY

    _(result).must_answer <<~'OUT'
      [art] article-alpha
      [com] comment-hello
      inner=article-alpha
    OUT
  end

  it "kwrest copies a key without calling its hash again" do
    result = ze0(<<~'RUBY')
      # `**rest` takes the keywords the method does not declare from a Hash
      # whose keys already have their codes: ruby copies the entries, so a
      # key's own `hash` runs once, at the call, and never for the rest.
      class Key
        def initialize(limit) = @limit = limit
        def hash
          @limit -= 1
          raise "boom" if @limit < 0
          1
        end
        def eql?(other) = equal?(other)
      end
      def m(**rest) = rest.size
      begin
        p m(Key.new(1) => 1)
      rescue => e
        p [e.class, e.message]
      end
      def n(a: 0, **rest) = [a, rest.size]
      p n(Key.new(1) => 2, a: 1)


    RUBY

    _(result).must_answer <<~'OUT'
      1
      [1, 1]
    OUT
  end

  it "kwsplat forward defaults" do
    result = ze0(<<~'RUBY')
      # Forwarding **opts into a method with optional keyword parameters must apply
      # the callee's defaults for keys absent from the forwarded hash -- a bare hash
      # lookup returns nil and silently drops the default.
      def target(a:, b: 99, c: "hi")
        [a, b, c]
      end
      def forward(**opts) = target(**opts)

      p forward(a: 1)
      p forward(a: 1, b: 2)
      p forward(a: 1, c: "yo")
      p forward(a: 1, b: 5, c: "z")

      def tagged(x:, tag: :none) = [x, tag]
      def ftag(**opts) = tagged(**opts)
      p ftag(x: 10)
      p ftag(x: 10, tag: :set)

      # a literal keyword combined with a forwarded splat
      def mixed(**opts) = target(a: 0, **opts)
      p mixed(b: 7)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 99, "hi"]
      [1, 2, "hi"]
      [1, 99, "yo"]
      [1, 5, "z"]
      [10, :none]
      [10, :set]
      [0, 7, "hi"]
    OUT
  end

  it "map shadowed param poly arg" do
    result = ze0(<<~'RUBY')
      # A value-position map whose block param feeds a poly-widened callee param.
      # The param's scope-local rides the fixpoint to poly (its array's element type
      # settles late), and the map emitter then shadow-pins it to the element type
      # (string) for the body's emission. The shallow per-statement re-inference did
      # not descend into call ARGUMENTS, so the argument read kept its stale poly
      # cache and was passed unboxed: `sp_RbVal _t = lv_root;` -- a C compile error
      # (invalid initializer).

      class Reader
        def initialize(data)
          @data = data
          @pos = 0
        end

        def read_hash
          s = @data[@pos, 4]
          @pos += 4
          s
        end
      end

      class Proof
        attr_reader :fri_roots

        def initialize(fri_roots)
          @fri_roots = fri_roots
        end
      end

      class Transcript
        def initialize
          @n = 0
        end

        def absorb(label, data)
          @n += 1
        end

        def challenge
          [@n, @n * 10]
        end
      end

      def deserialize(data)
        reader = Reader.new(data)
        roots = Array.new(2) { reader.read_hash }
        Proof.new(roots)
      end

      def verify(proof, transcript)
        proof.fri_roots.map do |root|
          transcript.absorb("fri_root", root)
          transcript.challenge
        end
      end

      proof = deserialize("aaaabbbb")
      transcript = Transcript.new
      transcript.absorb("init", 42)
      p verify(proof, transcript)
      p proof.fri_roots
    RUBY

    _(result).must_answer <<~'OUT'
      [[2, 20], [3, 30]]
      ["aaaa", "bbbb"]
    OUT
  end

  it "method" do
    result = ze0(<<~'RUBY')
      def double(x)
        x * 2
      end

      # Direct call for type inference
      puts double(1)   # 2

      m = method(:double)
      puts m.call(5)   # 10
      puts m.call(10)  # 20

      def add_ten(x)
        x + 10
      end

      puts add_ten(0)  # 10

      a = method(:add_ten)
      puts a.call(3)   # 13

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      2
      10
      20
      10
      13
      done
    OUT
  end

  it "method at toplevel" do
    result = ze0(<<~'RUBY')
      # __method__ is nil at the top level; inside a method it is the method's name.
      p __method__
      def foo; __method__; end
      p foo
      def bar; __callee__; end
      p bar
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      :foo
      :bar
    OUT
  end

  it "method call splat args" do
    result = ze0(<<~'RUBY')
      # Method#[] / #call with a trailing splat expands the array into the
      # target's declared params at runtime (#3248).
      def add(a, b) = a + b
      args = [4, 5]
      p(method(:add)[*args])
      p(method(:add).call(*args))
      p(method(:add).call(1, *[2]))

      class C
        def mul(a, b) = a * b
      end
      m = C.new.method(:mul)
      p m.call(*[3, 7])
      p m[*[3, 7]]
    RUBY

    _(result).must_answer <<~'OUT'
      9
      9
      3
      21
      21
    OUT
  end

  it "method call splat rest" do
    result = ze0(<<~'RUBY')
      class Var
        def sum(*a); a.sum; end
      end
      args001 = [1, 2, 3]
      p Var.new.method(:sum).call(*args001)

      m002 = Var.new.method(:sum); p m002.call(*args001)   # Ruby: 6

      p Var.new.method(:sum).call(1, 2, 3)   # => 6
      p Var.new.method(:sum).call(1)         # => 1
      p Var.new.method(:sum).call            # => 0
      p Var.new.sum(*args001)                # => 6
      p Var.new.sum(1, 2, 3)                 # => 6
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      6
      1
      0
      6
      6
    OUT
  end

  it "method capture before own def" do
    result = ze0(<<~'RUBY')
      # `K.method(:name)` captured BEFORE `def self.name` in document order binds
      # the INHERITED entry -- CRuby resolves at capture time, so the later
      # override must not be found by the capture (rspec-support's
      # `NEW_MUTEX_METHOD = Mutex.method(:new)` / `def self.new` delegation pair;
      # a by-name capture recurses forever).
      class Base
        def self.make
          "base-make"
        end
      end

      class Sub < Base
        CAP = Sub.method(:make)
        def self.make
          "sub-wraps(#{CAP.call})"
        end
      end

      p Sub.make
      p Sub.method(:make).call
    RUBY

    _(result).must_answer <<~'OUT'
      "sub-wraps(base-make)"
      "sub-wraps(base-make)"
    OUT
  end

  it "method compose container" do
    result = ze0(<<~'RUBY')
      fs001 = [->(x001) { x001 + 1 }]
      m001 = 2.method(:*)
      c001 = m001 >> fs001[0]
      p c001.call(4)

      fs002 = [->(x002) { x002 + 1 }]; m002 = 2.method(:*); p((m002 >> fs002[0]).call(4))  # Ruby: 9
      fs003 = [->(x003) { x003 + 1 }]; m003 = 2.method(:*); p((m003 << fs003[0]).call(4))  # Ruby: 6

      fs004 = [->(x004) { x004 + 1 }, ->(x004b) { x004b * 3 }]; id004 = ->(x004c) { x004c }
      p(fs004.reduce(id004, :>>).call(4))   # Ruby: 15

      fs006 = [->(x006) { x006 + 1 }]
      id006 = ->(x006b) { x006b }
      c006 = id006 >> fs006[0]
      p c006.call(4)                                   # => 5
      p((id006 << fs006[0]).call(4))                   # => 5
      m007 = 2.method(:*)
      p((m007 >> ->(x007) { x007 + 1 }).call(4))       # => 9
      fs008 = [->(x008) { x008 + 1 }, ->(x008b) { x008b * 3 }]
      id008 = ->(x008c) { x008c }
      p(fs008.inject(id008) { |a008, b008| a008 >> b008 }.call(4))   # => 15
      p(fs008.reduce(:>>).call(4))                                   # => 15

      fs = [->(x) { x * 2 }, ->(x) { x + 3 }]
      p(fs.reduce(->(x) { x }, :<<).call(2))
      m = 3.method(:+)
      h = { f: ->(x) { x * 10 } }
      p((m >> h[:f]).call(1))
      p((m << h[:f]).call(1))
    RUBY

    _(result).must_answer <<~'OUT'
      9
      9
      10
      15
      5
      5
      9
      15
      15
      10
      40
      13
    OUT
  end

  it "method defined" do
    result = ze0(<<~'RUBY')
      # Module#method_defined?(:sym) — compile-time decided via the
      # class's recorded method table (walks the parent chain, includes
      # attr readers/writers).
      class Animal
        def name; "Animal"; end
        attr_accessor :age
      end

      class Dog < Animal
        def bark; "woof"; end
      end

      p Animal.method_defined?(:name)
      p Animal.method_defined?(:age)
      p Animal.method_defined?(:age=)
      p Animal.method_defined?(:bark)
      p Animal.method_defined?(:nope)

      p Dog.method_defined?(:name)
      p Dog.method_defined?(:bark)
      p Dog.method_defined?(:age)
      p Dog.method_defined?(:nope)

      # String arg form
      p Animal.method_defined?("name")
      p Animal.method_defined?("nope")

      # Inherit=false — restrict the lookup to the receiver's own methods.
      # Dog#bark is defined locally; Dog inherits #name and #age from Animal.
      # With inherit=false, only :bark is reported on Dog.
      p Dog.method_defined?(:bark, false)   # true  (defined on Dog)
      p Dog.method_defined?(:name, false)   # false (inherited from Animal)
      p Dog.method_defined?(:age, false)    # false (inherited)
      p Dog.method_defined?(:age=, false)   # false (inherited)
      p Animal.method_defined?(:name, false) # true (defined on Animal)
      p Animal.method_defined?(:bark, false) # false (defined on Dog only)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      true
      true
      true
      false
      true
      false
      true
      false
      false
      false
      true
      false
    OUT
  end

  it "method extended" do
    result = ze0(<<~'RUBY')
      class Animal
        def speak(sound) = "#{sound}!"
      end
      class Dog < Animal
      end

      d = Dog.new
      m = d.method(:speak)

      # owner walks to the defining ancestor, not the receiver's class
      p m.owner
      p m.original_name

      # composition: (m >> f).call(x) == f(m.call(x))
      shout = ->(s) { s.upcase }
      p (m >> shout).call("woof")
      p (m << shout).call("woof")

      # a Method composes with another Method too
      add1 = 1.method(:+)
      double = ->(n) { n * 2 }
      p (add1 >> double).call(10)

      # equality: same receiver + same method are ==, different receivers are not
      p d.method(:speak) == d.method(:speak)
      p Dog.new.method(:speak) == Dog.new.method(:speak)
      p m.hash == d.method(:speak).hash

      # curry a multi-arg Method
      class Adder
        def add3(a, b, c) = a + b + c
      end
      cm = Adder.new.method(:add3)
      p cm.curry[1][2][3]

      # UnboundMethod owner / original_name
      um = Dog.instance_method(:speak)
      p um.owner
      p um.original_name
      p um.bind(Dog.new).call("bark")
    RUBY

    _(result).must_answer <<~'OUT'
      Animal
      :speak
      "WOOF!"
      "WOOF!"
      22
      true
      false
      true
      6
      Animal
      :speak
      "bark!"
    OUT
  end

  it "method object accessor" do
    result = ze0(<<~'RUBY')
      # method(:accessor) for auto-generated attr / struct accessors (no real def):
      # reader, writer, name, arity, and to_proc with a correct-arity block.
      class C
        attr_accessor :x, :name
        def initialize; @x = 7; @name = "hi"; end
      end
      o = C.new
      p o.method(:x).call
      p o.method(:name).call
      m = o.method(:x=)
      m.call(9)
      p o.x
      p o.method(:x).name
      p o.method(:x).arity
      p o.method(:x=).arity
      [1, 2, 3].each(&o.method(:x=))
      p o.x

      S = Struct.new(:ok?, :count)
      s = S.new(true, 0)
      p s.method(:ok?).call
      s.method(:"ok?=").call(false)
      p s.ok?
      p s.method(:ok?).arity
      p s.method(:"ok?=").arity

      # a real def is still resolved (regression guard)
      class D
        def double(n); n * 2; end
      end
      p D.new.method(:double).call(21)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      "hi"
      9
      :x
      0
      1
      3
      true
      false
      0
      1
      42
    OUT
  end

  it "method objects" do
    result = ze0(<<~'RUBY')
      # `method(:name)` answers a Method -- a bound (receiver, name) pair whose
      # #call dispatches through the ordinary send machinery.

      def double(x) = x * 2

      m = method(:double)
      p m.call(21)
      p m.(21)
      p m[21]
      p m.name
      p m.class

      # A Method converts to a Proc, so it passes as a block.
      p [1, 2, 3].map(&method(:double))
      p method(:double).to_proc.call(5)
      p method(:double).to_proc.class

      # On an explicit receiver.
      class Greeter
        def initialize(greeting)
          @greeting = greeting
        end

        def greet(name)
          "#{@greeting}, #{name}!"
        end

        def shout(name)
          greet(name).upcase
        end
      end

      g = Greeter.new("Hello")
      gm = g.method(:greet)
      p gm.call("Ada")
      p gm.name
      p gm.receiver.equal?(g)

      # The binding is to THAT instance, so it keeps its own ivars.
      other = Greeter.new("Hi")
      p other.method(:greet).call("Bob")
      p gm.call("Bob")

      # Method objects are first-class: store them, pass them, call later.
      handlers = [g.method(:greet), g.method(:shout)]
      handlers.each { |h| puts h.call("Cat") }

      table = { greet: g.method(:greet), shout: g.method(:shout) }
      p table[:shout].call("dog")

      # A Method for a builtin receiver's method.
      up = "hello".method(:upcase)
      p up.call
      len = [1, 2, 3].method(:length)
      p len.call

      # === invokes it, so a Method works in a case/when.
      matcher = method(:double)
      p matcher === 4

      # A Method surviving through a block that yields it.
      def with_method
        yield method(:double)
      end
      p(with_method { |mm| mm.call(50) })

      # Method#inspect mentions the owner and name.
      p g.method(:greet).inspect.include?("greet")

      # An unknown method name raises NameError at CONSTRUCTION, not at call.
      begin
        "str".method(:definitely_not_defined)
      rescue NameError => e
        puts e.message
      end
      begin
        g.method(:definitely_not_defined)
      rescue NameError => e
        puts e.message
      end

      # A PRIVATE method is still reachable by reflection (privacy limits call
      # sites, not `method`).
      class WithPrivate
        private

        def secret = "shh"
      end
      p WithPrivate.new.method(:secret).call
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      42
      :double
      Method
      [2, 4, 6]
      10
      Proc
      "Hello, Ada!"
      :greet
      true
      "Hi, Bob!"
      "Hello, Bob!"
      Hello, Cat!
      HELLO, CAT!
      "HELLO, DOG!"
      "HELLO"
      3
      8
      100
      true
      undefined method 'definitely_not_defined' for class 'String'
      undefined method 'definitely_not_defined' for class 'Greeter'
      "shh"
    OUT
  end

  it "method out of container" do
    result = ze0(<<~'RUBY')
      class Calc
        def initialize(b); @b = b; end
        def add(n); @b + n; end
      end
      ms001 = [Calc.new(3).method(:add)]
      p ms001[0].class
      r002 = (ms001[0].name rescue $!.class); p r002
      r003 = (ms001[0].owner rescue $!.class); p r003
      r005 = (ms001[0].parameters rescue $!.class); p r005
      h008 = { a: Calc.new(3).method(:add) }
      r008 = (h008[:a].name rescue $!.class); p r008
    RUBY

    _(result).must_answer <<~'OUT'
      Method
      :add
      Calc
      [[:req, :n]]
      :add
    OUT
  end

  it "method owner receiver" do
    result = ze0(<<~'RUBY')
      # Method#owner is the defining class (the receiver's class for a builtin
      # method object); #receiver is the bound receiver (#2701).
      m = 5.method(:+)
      p m.owner
      p m.receiver
      p "hi".method(:upcase).owner
      p "hi".method(:upcase).receiver
      class U; def f; 1; end; end
      u = U.new
      mu = u.method(:f)
      p mu.owner
      p mu.receiver.class
      class Sub < U; end
      p Sub.new.method(:f).owner
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      5
      String
      "hi"
      U
      U
      U
    OUT
  end

  it "method params" do
    result = ze0(<<~'RUBY')
      class Greeter
        def greet(name, greeting = "Hello")
          "#{greeting}, #{name}!"
        end
      end

      g = Greeter.new
      puts g.greet("Ada")
      puts g.greet("Ada", "Hi")

      class Collector
        def count(*nums)
          nums.length
        end

        def between(a, *mid, z)
          "#{a}-#{mid.length}-#{z}"
        end
      end

      c = Collector.new
      puts c.count(1, 2, 3)
      puts c.count
      puts c.between(1, 2, 3, 9)

      class Kw
        def greet(x:, y: 10)
          x + y
        end

        def opts(**rest)
          rest.length
        end
      end

      k = Kw.new
      puts k.greet(x: 1)
      puts k.greet(x: 1, y: 2)
      puts k.greet(y: 3, x: 4)
      puts k.opts(a: 1, b: 2, c: 3)

      class Box
        attr_accessor :value
        attr_reader :ro

        def initialize
          @value = 1
          @ro = 7
        end
      end

      b = Box.new
      puts b.value
      b.value = 99
      puts b.value
      puts b.ro

      class Calc
        def double(x) = x * 2
      end
      puts Calc.new.double(21)

      class Adder
        def add(a, b)
          a + b
        end
      end
      puts Adder.new.add(3, 4)
    RUBY

    _(result).must_answer <<~'OUT'
      Hello, Ada!
      Hi, Ada!
      3
      0
      1-2-9
      11
      3
      7
      3
      1
      99
      7
      42
      7
    OUT
  end

  it "method source location" do
    result = ze0(<<~'RUBY', path: "lang/methods/method_source_location.rb")
      # `Method#source_location` / `UnboundMethod#source_location` -- `[file, line]`
      # for a method written in Ruby, `nil` for one defined natively. The line is the
      # `def` keyword's own, which is why the assertions below name it explicitly
      # rather than printing the (machine-specific) path.

      def at_line_6 = 1

      class Shapes
        def area(w, h)              # line 9
          w * h
        end

        def self.build = new        # line 13

        attr_accessor :label        # line 15

        alias_method :size, :area   # line 17
      end

      def line_of(m) = m.source_location&.last
      def file_of(m) = File.basename(m.source_location&.first || "")

      # A plain top-level def, a class body def, and a class method.
      p line_of(method(:at_line_6))
      p line_of(Shapes.new.method(:area))
      p line_of(Shapes.method(:build))

      # The file is this one, in every case.
      p file_of(method(:at_line_6))
      p file_of(Shapes.new.method(:area))

      # An attr_accessor pair reports the `attr_accessor` line itself.
      p line_of(Shapes.new.method(:label))
      p line_of(Shapes.new.method(:label=))

      # An alias reports its SOURCE's location, not the alias line.
      p line_of(Shapes.new.method(:size))

      # UnboundMethod answers the same pair.
      p line_of(Shapes.instance_method(:area))
      p Shapes.instance_method(:area).source_location.is_a?(Array)
      p Shapes.instance_method(:area).source_location.length

      # A method defined at runtime carries its block's location.
      class Shapes
        define_method(:scaled) { |k| k }   # line 46
      end
      p line_of(Shapes.new.method(:scaled))

      # Natively defined methods have no Ruby source.
      p 5.method(:+).source_location
      p [].method(:push).source_location
      p Array.method(:try_convert).source_location
      p String.instance_method(:upcase).source_location
    RUBY

    _(result).must_answer <<~'OUT'
      6
      9
      13
      "method_source_location.rb"
      "method_source_location.rb"
      15
      15
      9
      9
      true
      2
      46
      nil
      nil
      nil
      nil
    OUT
  end

  it "method visibility attr" do
    result = ze0(<<~'RUBY')
      # Visibility applies to attr_accessor / attr_reader / attr_writer methods
      # declared under a bare private/protected section (writers tracked as "name=").

      class Box
        attr_reader :open_r
        attr_accessor :open_rw

        private

        attr_accessor :hidden       # hidden + hidden= are private
        attr_reader :hidden_r

        protected

        attr_writer :prot_w         # prot_w= is protected

        public
      end

      def sorted(arr); arr.map(&:to_s).sort; end

      puts sorted(Box.instance_methods(false)).inspect
      puts sorted(Box.private_instance_methods(false)).inspect
      puts sorted(Box.protected_instance_methods(false)).inspect

      puts Box.method_defined?(:open_r)
      puts Box.method_defined?(:open_rw=)
      puts Box.method_defined?(:hidden)
      puts Box.method_defined?(:hidden=)
      puts Box.private_method_defined?(:hidden)
      puts Box.private_method_defined?(:hidden_r)
      puts Box.protected_method_defined?(:prot_w=)

      b = Box.new
      puts b.respond_to?(:open_r)
      puts b.respond_to?(:open_rw=)
      puts b.respond_to?(:hidden)
      puts b.respond_to?(:hidden, true)
      puts b.respond_to?(:hidden_r, true)
    RUBY

    _(result).must_answer <<~'OUT'
      ["open_r", "open_rw", "open_rw=", "prot_w="]
      ["hidden", "hidden=", "hidden_r"]
      ["prot_w="]
      true
      true
      false
      false
      true
      true
      true
      true
      true
      false
      true
      true
    OUT
  end

  it "module level state accumulates across class method calls" do
    result = ze0(<<~'RUBY')
      module Counter
        @n = 0
        def self.bump; @n += 1; end
        def self.n; @n; end
      end
      Counter.bump
      Counter.bump
      Counter.bump
      p Counter.n
    RUBY

    _(result).must_answer "3\n"
  end

  it "module method does not shadow the builtin class method" do
    result = ze0(<<~'RUBY')
      # Reopening a builtin MODULE and defining a method the including CLASS
      # already defines itself must not shadow the class's own method. `Array`
      # includes `Enumerable`, and `Array#none?`/`Array#size` are defined on `Array`
      # -- so `Array` comes first in the ancestry and its own definitions win.
      # CRuby answers `true` / `3`; zeo answers `:from_enumerable` /
      # `:from_enumerable_size`, taking the module's.
      #
      # The cause is which side of the MRO the BUILTIN rows sit on. A user's `def`
      # inside `module Enumerable` registers as an `own_method` on the Enumerable
      # ClassInfo, and `mro::materialize_methods` walks the ancestry putting the
      # closest ancestor's own_methods first -- Array, then Enumerable -- so the
      # table itself is ordered correctly. What is missing is `Array`'s own row:
      # `none?` and `size` are native builtins with no `Scope`, so `Array`
      # contributes nothing to `own_methods` for those names and the walk falls
      # through to the first ancestor that DOES have a user scope. The builtin
      # table is consulted only after the materialized table misses.
      #
      # The fix is for materialization to treat a builtin row on `class_id` as
      # claiming the name -- the same `seen.insert` an `undef` already performs --
      # so a further ancestor's user definition cannot supply it. That needs the
      # builtin method list per class at materialization time, which is
      # `zeo_abi::BUILTINS` and is already indexed by ClassId.
      #
      # Independent of the fused-iterator work: this reproduces byte-identically on
      # the binary built before Wave 8's kinds existed, with the site unfused.
      module Enumerable
        def none?
          :from_enumerable
        end

        def size
          :from_enumerable_size
        end
      end

      arr = [1, 2, 3]
      p arr.none? { |x| x > 9 }
      p arr.size
      p [].none?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      3
      true
    OUT
  end

  it "module method via class value" do
    result = ze0(<<~'RUBY')
      # `target.seen(x)` where `target` holds a Class value the analysis cannot pin to
      # one class -- a parameter, an element, an untyped slot -- reaches every class
      # method of that name at run time, so every one of them has this call as a
      # caller. Only callers naming the module outright were counted, so one of those
      # settled the parameter and the call through the variable was then READ at that
      # type: an object arrived as a String and answered with its bytes, an Integer
      # segfaulted, and nothing was said at compile time (#4066).
      class Named
      end

      module Lang
        def self.seen(path)
          path
        end
      end

      def through(target, path)
        target.seen(path)
      end

      p through(Lang, Named.new).class
      p Lang.seen("x.rb")
      p through(Lang, 42)
      p through(Lang, [1, 2])
      p through(Lang, "direct")

      # two modules answering the same name, reached through the same variable
      module Other
        def self.seen(path)
          "other:#{path}"
        end
      end
      p through(Other, 7)
      p Other.seen("s")

      # a class value held in an array element
      mods = [Lang, Other]
      p mods[0].seen(3)
      p mods[1].seen(4)
    RUBY

    _(result).must_answer <<~'OUT'
      Named
      "x.rb"
      42
      [1, 2]
      "direct"
      "other:7"
      "other:s"
      3
      "other:4"
    OUT
  end

  it "op method bitwise" do
    result = ze0(<<~'RUBY')
      # User-defined | & ^ % dispatch to the class method (mangled C name),
      # not a raw C bitwise/modulo op on the struct pointer.
      class Flags
        def initialize(v)
          @v = v
        end
        def |(o)
          @v + 100
        end
        def &(o)
          @v + 200
        end
        def ^(o)
          @v + 300
        end
        def %(o)
          @v + 400
        end
      end
      f = Flags.new(1)
      g = Flags.new(2)
      puts(f | g)
      puts(f & g)
      puts(f ^ g)
      puts(f % g)
      # Builtin int operators still work (regression guard).
      puts(6 | 1)
      puts(6 & 4)
      puts(6 ^ 2)
      puts(7 % 3)
    RUBY

    _(result).must_answer <<~'OUT'
      101
      201
      301
      401
      7
      4
      4
      1
    OUT
  end

  it "optional params use the default only when omitted" do
    result = ze0(<<~'RUBY')
      class Greeter
        def greet(name, greeting = "Hello")
          "#{greeting}, #{name}!"
        end
      end
      g = Greeter.new
      puts g.greet("Ada")
      puts g.greet("Ada", "Hi")
    RUBY

    _(result).must_answer <<~'OUT'
      Hello, Ada!
      Hi, Ada!
    OUT
  end

  it "param default references sibling" do
    result = ze0(<<~'RUBY')
      # A parameter default that references an earlier parameter (positional or
      # keyword) must be evaluated with that parameter bound, exactly as CRuby
      # evaluates defaults left-to-right in the callee.

      def kw(a:, b: a * 2)
        [a, b]
      end
      p kw(a: 5)
      p kw(a: 5, b: 100)

      def pos(a, b = a * 2)
        [a, b]
      end
      p pos(5)
      p pos(5, 100)

      # a chain of defaults, each referencing the previous
      def chain(a, b = a + 1, c = b * 2)
        [a, b, c]
      end
      p chain(10)
      p chain(10, 20)
      p chain(10, 20, 30)

      def kwchain(x:, y: x + 1, z: y + 1)
        [x, y, z]
      end
      p kwchain(x: 1)
      p kwchain(x: 1, z: 99)

      # string-typed default referencing a string param
      def greet(name, msg = name + "!")
        [name, msg]
      end
      p greet("hi")
      p greet("hi", "yo")

      # a keyword default referencing a positional param
      def mix(a, b: a * 3)
        [a, b]
      end
      p mix(4)
      p mix(4, b: 40)
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 10]
      [5, 100]
      [5, 10]
      [5, 100]
      [10, 11, 22]
      [10, 20, 40]
      [10, 20, 30]
      [1, 2, 3]
      [1, 2, 99]
      ["hi", "hi!"]
      ["hi", "yo"]
      [4, 12]
      [4, 40]
    OUT
  end

  it "param shapes" do
    result = ze0(<<~'RUBY')
      # Positional parameter shapes: parenthesized destructuring, the auto-splat
      # rule, post-parameter distribution, and the trailing-comma implicit rest.

      def one(x) = yield x

      # --- Parenthesized destructuring --------------------------------------------
      # A single fully-parenthesized param splits the element it receives.
      [[1, 2], [3, 4]].each { |(a, b)| p [a, b] }

      # Mixed with plain params, at any position.
      [[1, [2, 3], 4]].each { |a, (b, c), d| p [a, b, c, d] }
      [[[1, 2], 3]].each { |(a, b), c| p [a, b, c] }

      # Nested arbitrarily deep.
      [[1, [2, [3, 4]]]].each { |a, (b, (c, d))| p [a, b, c, d] }

      # A named splat inside the destructure collects the tail; an anonymous one
      # consumes its slot and discards it.
      [[1, [2, 3, 4]]].each { |a, (b, *r)| p [a, b, r] }
      [[1, 2, 3]].each { |a, (*), b| p [a, b] }

      # Destructuring works on METHOD params too, not just blocks.
      def pair((a, b)) = "#{a}-#{b}"
      puts pair([1, 2])

      def nested((a, (b, c))) = [a, b, c]
      p nested([1, [2, 3]])

      # The destructured names are ordinary locals: an escaping block can capture
      # them, and reassigning one inside the block is visible outside.
      def capture((a, b))
        bump = -> { a += 10 }
        bump.call
        [a, b]
      end
      p capture([1, 2])

      # --- Auto-splat -------------------------------------------------------------
      # A lone Array argument spreads across a block's positional params -- but a
      # block taking exactly one plain param receives it WHOLE (the `each { |pair| }`
      # idiom), and so does a lone optional.
      one([1, 2]) { |a| p a }
      one([1, 2]) { |a = 9| p a }
      one([1, 2]) { |*a| p a }
      one([1, 2]) { |a, **k| p a }

      # Two or more positional slots spread it.
      one([1, 2]) { |a, b| p [a, b] }
      one([1, 2]) { |a, *b| p [a, b] }
      one([1, 2]) { |*a, b| p [a, b] }

      # More than one OPTIONAL spreads it, even with no required param at all --
      # while a single optional plus a rest does not.
      one([1, 2]) { |a = 5, b = 4| p [a, b] }
      one([1, 2]) { |a = 5, *b| p [a, b] }

      # A lambda is strict and never auto-splats.
      p(->(a) { a }.call([1, 2]))

      # --- Post parameters --------------------------------------------------------
      # Post params fill left-to-right from whatever the lead/rest left behind, and
      # nil-pad when there isn't enough to go around.
      one([1, 2]) { |a, *b, c, d| p [a, b, c, d] }
      one([1, 2, 3, 4, 5]) { |a, *b, c| p [a, b, c] }
      one([1, 2]) { |a, b = 5, c = 6, d, e| p [a, b, c, d, e] }
      one([1, 2, 3, 4, 5]) { |a, b = 5, c = 6, d, e| p [a, b, c, d, e] }

      # The same clamping in a multi-assignment.
      w, *x, y, z = [1, 2]
      p [w, x, y, z]

      # --- Trailing comma ---------------------------------------------------------
      # `|a, |` means "more than one param", which turns on auto-splat, then
      # discards everything past `a`.
      one([1, 2]) { |a,| p a }

      # --- Block-local declarations -----------------------------------------------
      # The names after the `;` are FRESH locals scoped to the block: they shadow
      # any enclosing local of the same name, are reset to nil on every single
      # invocation, and never write back out.
      sum = 99
      [1].each { |x; sum| sum = x }
      p sum                              # 99 -- the outer one is untouched

      # Reset per call, so this never accumulates -- `total` is nil again at the
      # top of each iteration.
      total = 42
      [1, 2, 3].each { |x; total| total = (total || 0) + x }
      p total                            # 42

      # Several at once, and alongside ordinary params.
      a = 1
      b = 2
      [0].each { |z; a, b| a = 7; b = 8 }
      p [a, b]                           # [1, 2]

      # A nested block's own block-local shadows without disturbing the outer
      # block's variable.
      r = 0
      [5].each do |i|
        [9].each { |j; r| r = j }
        r = i
      end
      p r                                # 5
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [3, 4]
      [1, 2, 3, 4]
      [1, 2, 3]
      [1, 2, 3, 4]
      [1, 2, [3, 4]]
      [1, 3]
      1-2
      [1, 2, 3]
      [11, 2]
      [1, 2]
      [1, 2]
      [[1, 2]]
      [1, 2]
      [1, 2]
      [1, [2]]
      [[1], 2]
      [1, 2]
      [[1, 2], []]
      [1, 2]
      [1, [], 2, nil]
      [1, [2, 3, 4], 5]
      [1, 5, 6, 2, nil]
      [1, 2, 3, 4, 5]
      [1, [], 2, nil]
      1
      99
      42
      [1, 2]
      5
    OUT
  end

  it "parameters" do
    result = ze0(<<~'RUBY')
      def opt(a, b = 10, c = b + 1)
        [a, b, c]
      end

      def rest(a, *r)
        [a, r]
      end

      def post(a, *m, z)
        [a, m, z]
      end

      def kw(a:, b: 5)
        [a, b]
      end

      def kwrest(a, **o)
        [a, o]
      end

      def blockp(a, &b)
        b.nil? ? :none : b.call(a)
      end

      def everything(a, b = 2, *m, z, k:, j: 9, **o, &blk)
        [a, b, m, z, k, j, o, blk.nil?]
      end

      class Box
        def initialize(value, label: "box")
          @value = value
          @label = label
        end

        def to_s
          "#{@label}=#{@value}"
        end

        def with(*extra, **opts)
          [@value, extra, opts]
        end

        def each_pair
          @value.each { |v| yield(v, @label) }
        end
      end

      p opt(1)
      p opt(1, 2)
      p opt(1, 2, 3)
      p rest(1)
      p rest(1, 2, 3)
      p post(1, 9)
      p post(1, 2, 3, 9)
      p kw(a: 1)
      p kw(a: 1, b: 2)
      p kwrest(1)
      p kwrest(1, x: 2, y: 3)
      p blockp(4)
      p blockp(4) { |n| n * 2 }
      p everything(1, 2, 3, 4, 5, k: 6)
      p everything(1, 2, 3, k: 6, j: 7, extra: 8) { }

      p method(:opt).parameters
      p method(:everything).parameters
      p method(:opt).arity
      p method(:everything).arity

      p [1, 2, 3].map { |x, y = 10| [x, y] }
      p [[1, 2], [3, 4]].map { |a, *r| [a, r] }

      double = ->(x) { x * 2 }
      p double.call(5)
      p double.(6)
      p double[7]
      p double.lambda?
      p double.arity
      p double.parameters
      p [1, 2, 3].map(&double)
      p ["a", "b"].map(&:upcase)

      add = ->(a, b = 1) { a + b }
      p add.call(2)
      p add.call(2, 3)
      p add.arity

      # A `->` closes over a name the same way a block does: one shared cell,
      # not a copy taken where the lambda was written.
      tally = 0
      count = ->(n) { tally += n }
      count.call(3)
      count.call(4)
      p tally

      pr = proc { |a, b = 1| [a, b] }
      p pr.call(7)
      p pr.arity
      p lambda { |a, b = 1| }.arity
      p proc { |a, *r| }.arity

      puts Box.new(1)
      puts Box.new(2, label: "two")
      p Box.new(3).with(4, 5, a: 6)
      Box.new([7, 8], label: "n").each_pair { |v, l| puts "#{l}:#{v}" }

      # `_1`/`_2` and `it` are that many required positionals, under the names
      # ruby gives them, so they answer a block's ordinary arity.
      p [1, 2].map { _1 * 2 }
      p({ "a" => 1 }.map { _1 + _2.to_s })
      p [1, 2].map { it * 2 }
      p proc { _1 + _2 }.arity
      p proc { it }.arity
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 10, 11]
      [1, 2, 3]
      [1, 2, 3]
      [1, []]
      [1, [2, 3]]
      [1, [], 9]
      [1, [2, 3], 9]
      [1, 5]
      [1, 2]
      [1, {}]
      [1, {x: 2, y: 3}]
      :none
      8
      [1, 2, [3, 4], 5, 6, 9, {}, true]
      [1, 2, [], 3, 6, 7, {extra: 8}, false]
      [[:req, :a], [:opt, :b], [:opt, :c]]
      [[:req, :a], [:opt, :b], [:rest, :m], [:req, :z], [:keyreq, :k], [:key, :j], [:keyrest, :o], [:block, :blk]]
      -2
      -4
      [[1, 10], [2, 10], [3, 10]]
      [[1, [2]], [3, [4]]]
      10
      12
      14
      true
      1
      [[:req, :x]]
      [2, 4, 6]
      ["A", "B"]
      3
      5
      -2
      7
      [7, 1]
      1
      -2
      -2
      box=1
      two=2
      [3, [4, 5], {a: 6}]
      n:7
      n:8
      [2, 4]
      ["a1"]
      [2, 4]
      2
      1
    OUT
  end

  it "poly delete dispatch" do
    result = ze0(<<~'RUBY')
      # `delete` on a boxed receiver dispatches on what the receiver turns out to
      # be: a Hash gives the deleted value, an Array the object, a String the
      # stripped copy. It used to commit to String#delete and stringify the
      # receiver (#3806).
      opts = { n: 1, map: { 'a' => 7 }, list: [1, 2, 3], text: 'banana' }
      h = opts[:map]
      p h.delete('a')
      p h

      a = opts[:list]
      p a.delete(2)
      p a

      s = opts[:text]
      p s.delete('a')

      k = opts[:n]
      m = { 1 => 'one' }
      mm = [m, nil].first
      p mm.delete(k)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      {}
      2
      [1, 3]
      "bnn"
      "one"
    OUT
  end

  it "redefinition warns under verbose" do
    result = ze0(<<~'RUBY', path: "lang/methods/a_redefinition_warns_under_verbose.rb")
      # Under $VERBOSE true a definition over a method warns as
      # rb_method_entry_make does: not over an alias, an undef, a copy a
      # visibility verb made, or the same definition again.

      $VERBOSE = true
      class A
        def m; end
        def m; end
        def n; end
        alias o n
        def n; end
        def o; end
        attr_accessor :x
        attr_accessor :x
        define_method(:d) {}
        define_method(:d) {}
        def d; end
        def u; end
        undef u
        def u; end
        def v; end
        remove_method :v
        def v; end
        def self.s; end
        def self.s; end
        private def p1; end
        private :p1
        public
        def p1; end
      end
      class B < A
        private :m
        def m; end
      end
      class String
        def upcase; end
      end
      module Kernel
        def puts(*); end
      end
      $VERBOSE = false
      class A
        def m; end
      end
      $VERBOSE = nil
      class A
        def m; end
      end
      o = Object.new
      $VERBOSE = true
      def o.q; end
      def o.q; end
      Struct.new(:a).class_eval { def a; end }

    RUBY

    _(result).must_answer "", stderr: "lang/methods/a_redefinition_warns_under_verbose.rb:8: warning: method redefined; discarding old m\nlang/methods/a_redefinition_warns_under_verbose.rb:7: warning: previous definition of m was here\nlang/methods/a_redefinition_warns_under_verbose.rb:14: warning: method redefined; discarding old x\nlang/methods/a_redefinition_warns_under_verbose.rb:14: warning: method redefined; discarding old x=\nlang/methods/a_redefinition_warns_under_verbose.rb:16: warning: method redefined; discarding old d\nlang/methods/a_redefinition_warns_under_verbose.rb:15: warning: previous definition of d was here\nlang/methods/a_redefinition_warns_under_verbose.rb:17: warning: method redefined; discarding old d\nlang/methods/a_redefinition_warns_under_verbose.rb:16: warning: previous definition of d was here\nlang/methods/a_redefinition_warns_under_verbose.rb:25: warning: method redefined; discarding old s\nlang/methods/a_redefinition_warns_under_verbose.rb:24: warning: previous definition of s was here\nlang/methods/a_redefinition_warns_under_verbose.rb:29: warning: method redefined; discarding old p1\nlang/methods/a_redefinition_warns_under_verbose.rb:26: warning: previous definition of p1 was here\nlang/methods/a_redefinition_warns_under_verbose.rb:36: warning: method redefined; discarding old upcase\nlang/methods/a_redefinition_warns_under_verbose.rb:39: warning: method redefined; discarding old puts\nlang/methods/a_redefinition_warns_under_verbose.rb:52: warning: method redefined; discarding old q\nlang/methods/a_redefinition_warns_under_verbose.rb:51: warning: previous definition of q was here\nlang/methods/a_redefinition_warns_under_verbose.rb:53: warning: method redefined; discarding old a\n"
  end

  it "repeated optional parameter default writes the name" do
    result = ze0(<<~'RUBY')
      # CRuby compiles an optional parameter's DEFAULT as an assignment to the NAME,
      # not to the slot -- so a repeated `_`'s later default overwrites the local the
      # FIRST `_` owns, which is the one every read answers. zeo bound each slot
      # independently, so a later default was invisible.
      def both_default(_ = 1, _ = 2) = _
      p [both_default, both_default(9), both_default(9, 8)]
      def req_then_opt(_, _ = 5) = _
      p [req_then_opt(1), req_then_opt(1, 2)]
      def lead(a, _ = 2, _ = 3) = [a, _]
      p [lead(0), lead(0, 7), lead(0, 7, 8)]
      def three(_ = 1, _ = 2, _ = 3) = _
      p [three, three(9), three(9, 8), three(9, 8, 7)]
      # a default that reads an earlier parameter
      def reads(a, _ = a, _ = a + 1) = [a, _]
      p [reads(5), reads(5, 6), reads(5, 6, 7)]
      # named (non-underscore) duplicates are a SyntaxError in ruby, so only `_`
      # shapes exist. A single optional is unchanged.
      def single(a = 4) = a
      p [single, single(1)]
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 2, 9]
      [5, 1]
      [[0, 3], [0, 3], [0, 7]]
      [3, 3, 3, 9]
      [[5, 6], [5, 6], [5, 6]]
      [4, 1]
    OUT
  end

  it "ruby2 keywords method" do
    result = ze0(<<~'RUBY')
      def target(*a, **k) = [a, k]
      ruby2_keywords def fwd(*a) = target(*a)
      p fwd(1, k: 2)
    RUBY

    _(result).must_answer "[[1], {k: 2}]\n"
  end

  it "runtime defined method knows where it was written" do
    result = ze0(<<~'RUBY', path: "lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb")
      # Every method of a RUNTIME-minted class answers `source_location`.
      #
      # `parameters` and `arity` were already right, because both are derived from
      # the proc the body arrives as. The LOCATION was dropped on the floor:
      # `record_runtime_params` built its row with `source: None` while holding the
      # very proc that knows where it was written.
      #
      # So an entire family answered nil -- `Class.new { def m; end }`, a subclass
      # of one, a `define_method` body, and every method of a `Data.define`
      # subclass. The last is why a Data subclass's backtrace frame said
      # `Object#initialize`: with no row there is nothing to name it with.
      #
      # `Struct.new(:a)` is compiled to a REAL class (`as_compiled_struct`), so its
      # subclass never took this path and was correct all along. That asymmetry is
      # what narrowed this: the two shapes are written the same way and only one
      # worked.

      # --- a runtime-minted class, both spellings of a definition
      K = Class.new do
        def m(a); end
        define_method(:dm) { |b| }
      end
      p ["K#m", K.instance_method(:m).source_location]
      p ["K#dm", K.instance_method(:dm).source_location]

      # --- a subclass of one
      class K2 < K
        def n(c); end
      end
      p ["K2#n", K2.instance_method(:n).source_location]

      # --- a Data subclass: the shape that surfaced this
      D = Data.define(:x)
      class D2 < D
        def q(d); end
        def initialize(**kw); super; end
      end
      p ["D2#q", D2.instance_method(:q).source_location]
      p ["D2#initialize", D2.instance_method(:initialize).source_location]

      # --- the Struct twin, which never regressed and must not start
      S = Struct.new(:a)
      class S2 < S
        def r(e); end
      end
      p ["S2#r", S2.instance_method(:r).source_location]

      # --- a class method installed at run time
      K3 = Class.new do
        def self.cm(f); end
      end
      p ["K3.cm", K3.method(:cm).source_location]

      # --- a per-object singleton
      o = Object.new
      def o.sing(g); end
      p ["o.sing", o.method(:sing).source_location]

      # --- what must STILL answer nil: a builtin has no Ruby body to point at
      p ["String#upcase", String.instance_method(:upcase).source_location]
      p ["Integer#+", Integer.instance_method(:+).source_location]

      # --- the other two reflection channels stay right
      p ["K#m params", K.instance_method(:m).parameters]
      p ["K#dm params", K.instance_method(:dm).parameters]
      p ["D2#q arity", D2.instance_method(:q).arity]

      # --- a Method object carries it too
      p ["bound", K.new.method(:m).source_location]
      p ["unbound->bound", K.instance_method(:m).bind(K.new).source_location]
    RUBY

    _(result).must_answer <<~'OUT'
      ["K#m", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 20]]
      ["K#dm", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 21]]
      ["K2#n", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 28]]
      ["D2#q", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 35]]
      ["D2#initialize", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 36]]
      ["S2#r", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 44]]
      ["K3.cm", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 50]]
      ["o.sing", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 56]]
      ["String#upcase", nil]
      ["Integer#+", nil]
      ["K#m params", [[:req, :a]]]
      ["K#dm params", [[:req, :b]]]
      ["D2#q arity", 1]
      ["bound", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 20]]
      ["unbound->bound", ["lang/methods/a_runtime_defined_method_knows_where_it_was_written.rb", 20]]
    OUT
  end

  it "same name forwarder union receiver" do
    result = ze0(<<~'RUBY')
      # A method whose body forwards to the SAME name on a union-typed receiver
      # resolved the call to itself -- the only class defining that name -- so the
      # return type union was the method's own unfinished answer and the whole thing
      # came out void: `zero?` answered nil for every receiver, and `<=>` returned
      # nil and took Comparable's operators down with it (#3488, #3490).
      class Q
        def initialize(v)
          @value = v
        end

        def zero?
          @value.zero?
        end

        def positive?
          @value.positive?
        end
      end

      p Q.new(0).zero?
      p Q.new(Rational(0)).zero?
      p Q.new(1).zero?
      p Q.new(1).positive?
      p Q.new(Rational(-1)).positive?

      class M
        include Comparable
        attr_reader :v

        def initialize(v)
          @v = v
        end

        def <=>(other)
          @v <=> other.v
        end

        # never called: defining it is enough to widen the class's ivar, which is
        # what used to make <=> void
        def widen(other)
          other = M.new(other) unless other.is_a?(M)
          other.v
        end
      end

      p(M.new(1) <=> M.new(2))
      p(M.new(2) <=> M.new(1))
      p(M.new(1) <=> M.new(1))
      p(M.new(1) < M.new(2))
      p(M.new(2) > M.new(1))
      p(M.new(1) == M.new(1))
      p [M.new(3), M.new(1), M.new(2)].sort.map(&:v)
      p M.new(2).between?(M.new(1), M.new(3))
      p M.new(5).clamp(M.new(1), M.new(3)).v
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      -1
      1
      0
      true
      true
      true
      [1, 2, 3]
      true
      3
    OUT
  end

  it "self inside a class method is the class object" do
    result = ze0(<<~'RUBY')
      # A class method's `self` is the class object (a `RubyValue::Class`
      # value), so `self` and the class constant are interchangeable --
      # including as a receiver for the class's OWN other class methods.

      class Foo
        def self.bar
          self
        end
        def self.baz
          self.bar.name
        end
      end
      p Foo.bar
      p Foo.bar == Foo
      p Foo.baz
      p Foo.bar.new.class
    RUBY

    _(result).must_answer <<~'OUT'
      Foo
      true
      "Foo"
      Foo
    OUT
  end

  it "singleton class instance methods" do
    result = ze0(<<~'RUBY')
      # `obj.singleton_methods` finds a `def obj.x`, but the singleton CLASS does not
      # report it: `instance_methods(false)` is empty, `method_defined?` is false and
      # `instance_method` raises `NameError`.
      #
      # A per-object singleton lives in `runtime_meta`'s identity-keyed `singletons`
      # table, and `singleton_methods` reads it by identity. `singleton_class` mints a
      # class id and records the owner both ways (`singleton_classes`/
      # `singleton_owner`), but Module's reflection rows answer from the CLASS-keyed
      # tables, which that id has no rows in -- so the two views of the same method
      # disagree.
      #
      # A CLASS's singleton (`def K.cm`) already reports correctly, because a class
      # method is stored class-keyed to begin with. Only the per-object case splits.

      o = Object.new
      def o.hi = 1

      p o.singleton_methods
      p o.singleton_class.instance_methods(false)
      p o.singleton_class.public_instance_methods(false)
      p o.singleton_class.method_defined?(:hi)
      p o.singleton_class.instance_method(:hi).owner == o.singleton_class

      class K; end
      def K.cm = 2
      p K.singleton_class.instance_methods(false)
      p K.singleton_methods
    RUBY

    _(result).must_answer <<~'OUT'
      [:hi]
      [:hi]
      [:hi]
      true
      true
      [:cm]
      [:cm]
    OUT
  end

  it "singleton def labels its frame after the method" do
    result = ze0(<<~'RUBY')
      def frames
        yield
      rescue => e
        puts e.backtrace.first(3).map { |l| l.sub(/\A.*:\d+:in /, "") }
      end

      # `class << obj` on a plain object. Its `def` is a real method, so ruby names
      # the frame after it -- not after the scope the body was written in.
      o = Object.new
      class << o
        def sm
          [1].each { raise "x" }
        end
      end
      frames { o.sm }

      puts "--- def obj.m ---"
      p2 = Object.new
      def p2.dm
        [1].each { raise "x" }
      end
      frames { p2.dm }

      puts "--- def self.meta inside class << obj ---"
      p3 = Object.new
      class << p3
        def self.meta = [1].each { raise "x" }
      end
      frames { p3.singleton_class.meta }

      puts "--- a define_method body really is a block ---"
      class D
        define_method(:dm) { [1].each { raise "x" } }
      end
      frames { D.new.dm }

      puts "--- def self.x in a class body is qualified ---"
      class L
        def self.sm2 = [1].each { raise "x" }
      end
      frames { L.sm2 }

      puts "--- the iseq label reads the same string ---"
      q = Object.new
      def q.labelled = RubyVM::InstructionSequence.of(method(:labelled)).label
      p q.labelled
    RUBY

    _(result).must_answer <<~'OUT'
      'block in sm'
      'Array#each'
      'sm'
      --- def obj.m ---
      'block in dm'
      'Array#each'
      'dm'
      --- def self.meta inside class << obj ---
      'block in meta'
      'Array#each'
      'meta'
      --- a define_method body really is a block ---
      'block (2 levels) in <class:D>'
      'Array#each'
      'block in <class:D>'
      --- def self.x in a class body is qualified ---
      'block in L.sm2'
      'Array#each'
      'L.sm2'
      --- the iseq label reads the same string ---
      "labelled"
    OUT
  end

  it "splat heterogeneous call" do
    result = ze0(<<~'RUBY')
      # Issue #666: heterogeneous call sites against a `def f(*args)` method
      # previously left the splat slot at the default `int_array` and packed
      # subsequent string args through `(mrb_int)<char*>` casts. Each was
      # then re-interpreted by `puts x.to_s` as a giant integer (the pointer
      # bit-pattern). Fix widens the splat slot to `poly_array` when call
      # sites disagree, and emits a PolyArray builder at the heterogeneous
      # call site so each arg is boxed under its concrete type.

      def test_splat(*args)
        args.each { |x| puts x.to_s }
      end

      test_splat(1, 2, 3)
      test_splat("a", "b")
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      a
      b
    OUT
  end

  it "splat in a when clause tests every candidate" do
    result = ze0(<<~'RUBY')
      a = [1, 2]
      case 1
      when *a then puts "hit"
      else puts "miss"
      end
      case 9
      when *a then puts "hit"
      else puts "miss"
      end
      case 5
      when 3, *a, 5 then puts "mixed hit"
      else puts "mixed miss"
      end
      kinds = [Integer, String]
      case "s"
      when *kinds then puts "kind hit"
      end
      none = []
      case 1
      when *none then puts "never"
      else puts "empty ok"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      hit
      miss
      mixed hit
      kind hit
      empty ok
    OUT
  end

  it "splat params instance" do
    result = ze0(<<~'RUBY')
      # Splat parameter (def f(*a)) on instance methods: the call site packs
      # trailing args into the rest array instead of spilling each into its
      # own slot (which produced "too many arguments to function").
      class T
        def go(*a); a.size; end
        def withpre(x, *a); x + a.size; end
        def firstrest(*a); a[0]; end
        def sumrest(*a); s = 0; a.each { |v| s += v }; s; end
      end
      class Obj; def initialize(n); @n = n; end; def n; @n; end; end
      class ObjSub < Obj; end  # heap, not value-typed
      t = T.new
      puts t.go(1, 2)
      puts t.go(1, 2, 3, 4)
      puts t.go
      puts t.withpre(10, 1, 2, 3)
      puts t.firstrest(7, 8, 9)
      puts t.sumrest(1, 2, 3, 4)
      xs = [5, 6, 7]
      puts t.sumrest(*xs)
      puts t.go(Obj.new(1), Obj.new(2))
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      0
      13
      7
      10
      18
      2
    OUT
  end

  it "unbound method bind call" do
    result = ze0(<<~'RUBY')
      # UnboundMethod#bind_call(recv, *args) = bind(recv).call(*args) (#3246).
      class C
        def a(n) = n + 1
        def greet(x, y = "!") = "#{x}#{y}"
      end
      p(C.instance_method(:a).bind_call(C.new, 5))
      p(C.instance_method(:greet).bind_call(C.new, "hi"))
      p(C.instance_method(:greet).bind_call(C.new, "hi", "?"))
    RUBY

    _(result).must_answer <<~'OUT'
      6
      "hi!"
      "hi?"
    OUT
  end

  it "unbound method identity" do
    result = ze0(<<~'RUBY')
      # Module#instance_method yields an UnboundMethod (#2724): #class says so, and
      # calling it without a #bind is CRuby's NoMethodError. Binding restores the
      # ordinary Method behavior.
      class Animal; def breathe; "air"; end; end
      m = Animal.instance_method(:breathe)
      p m.class
      r = (m.call rescue $!.class)
      p r
      p m.bind(Animal.new).call
      p m.bind(Animal.new).class
    RUBY

    _(result).must_answer <<~'OUT'
      UnboundMethod
      NoMethodError
      "air"
      Method
    OUT
  end

  it "user method named eval" do
    result = ze0(<<~'RUBY')
      # zeo's divergence: a receiverless `eval(x)` inside a class that DEFINES its
      # own `eval` is taken for Kernel#eval -- the eval recognizer in lower/parse
      # runs before sibling-method resolution -- so the recursive call at line 14
      # coerces its argument to String and raises TypeError ("no implicit conversion
      # of Integer into String") where ruby runs Interp#eval. The explicit-receiver
      # spelling (`i.eval(3)`) already dispatches correctly, which is what makes the
      # recognizer the cause. (Imported from spinel, which had the same bug for a
      # different reason; its Kernel#eval-on-a-runtime-string refusal is separate
      # and stays.)
      class Interp
        def initialize
          @visits = 0
        end

        def eval(node)
          @visits += 1
          if node.is_a?(Array)
            eval(node[0]) + eval(node[1])
          else
            node * 2
          end
        end

        def visits
          @visits
        end
      end

      i = Interp.new
      p i.eval(3)
      p i.eval([1, 2])
      p i.eval([[1, 2], 3])
      p i.visits

      # an explicit receiver resolves the same way
      p i.eval(5)
      p Interp.new.eval([4, 5])

      # a subclass inherits it
      class Sub < Interp
        def twice(n)
          eval(n) + eval(n)
        end
      end
      p Sub.new.twice(6)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      12
      9
      10
      18
      24
    OUT
  end

  it "user method named load is not an eval" do
    result = ze0(<<~'RUBY')
      # A program that defines its own `load`, `eval` or `require` used to carry the
      # whole embedded run-time compiler -- 14 MB, and all 170 builtin class tables
      # with it -- because the predicate that decides matched the call's NAME and
      # nothing else.
      #
      # A RECEIVERLESS call resolves the way DISPATCH resolves it: a user method of
      # that name in the enclosing class's chain is what runs, and `Kernel#eval` is
      # unreachable from there. This pins that the narrowed answer agrees with what
      # ruby actually calls -- if it did not, the wrong method would answer.
      #
      # An explicit receiver is deliberately NOT narrowed: `Binding#eval` is a real
      # eval, and nothing static separates it from `obj.eval` on a user object.

      def load(x) = [:top_level_load, x]
      p load(1)

      class K
        def eval(src) = [:k_eval, src]
        def go = eval("ignored")
      end
      p K.new.eval("x")
      p K.new.go

      module M
        def self.require(feature) = [:m_require, feature]
        def self.go = require("nothing")
      end
      p M.require("a")
      p M.go

      # Kernel's own still answers where no user method shadows it.
      p eval("1 + 1")
      p defined?(Kernel.instance_method(:eval))
    RUBY

    _(result).must_answer <<~'OUT'
      [:top_level_load, 1]
      [:k_eval, "x"]
      [:k_eval, "ignored"]
      [:m_require, "a"]
      [:m_require, "nothing"]
      2
      "method"
    OUT
  end

  it "variadic and optional args" do
    result = ze0(<<~'RUBY')
      # Many core methods accept more argument shapes than a single fixed arity:
      # an optional count, a variadic list, an alternate block form, or an extra
      # position/limit. The same method name binds several signatures, dispatched
      # by what actually shows up at the call site.

      # --- Array: an optional count changes the RETURN TYPE ----------------------
      # Bare `last` answers one element; `last(n)` an array of the last n (clamped
      # to what's there). `sample(n)` likewise answers n random DISTINCT elements.
      p [1, 2, 3].last          # 3
      p [1, 2, 3].last(2)       # [2, 3]
      p [1, 2, 3].last(5)       # [1, 2, 3]   -- n past the length takes them all
      p [1, 2, 3].sample(3).sort # [1, 2, 3]  -- distinct; sorted so it's stable

      # --- Array: a block form as an alternative to a value ----------------------
      # `rindex(obj)` searches from the right by ==; `rindex { }` by a predicate.
      p [1, 2, 3, 2].rindex(2)             # 3
      p [1, 2, 3, 2].rindex { |x| x < 3 }  # 3

      # --- Array: `fill` spans, growing the array when asked ----------------------
      p([0, 0, 0].fill(9))              # [9, 9, 9]
      p([0, 0, 0].fill(9, 1, 1))        # [0, 9, 0]      -- start 1, length 1
      p([1, 2, 3].fill(9, 1, 5))        # [1, 9, 9, 9, 9, 9]  -- grows past the end
      p([1, 2, 3].fill { |i| i })       # [0, 1, 2]      -- block maps each index

      # --- Array: variadic set-ops (the named siblings of `|`/`&`/`-`) -----------
      # The operators are binary; the named forms take any number of arrays.
      p [1, 2, 3].union([2, 3], [4])                 # [1, 2, 3, 4]
      p [1, 2, 3, 4].intersection([2, 3, 4], [3, 4]) # [3, 4]
      p [1, 2, 3].difference([2], [4])               # [1, 3]

      # --- String: one OR MORE char-set specs, intersected -----------------------
      # `count`/`delete` AND every spec together; a leading `^` negates one.
      p "hello world".count("lo")         # 5
      p "hello world".count("lo", "o")    # 2   -- chars in BOTH "lo" and "o"
      p "hello world".count("^l", "lo")   # 2   -- in "lo" but NOT "l"  => the o's

      # --- String: an optional start position ------------------------------------
      p "hello".rindex("l", 2)   # 2    -- last "l" at or before index 2
      p "hello".rindex(/l/)      # 3    -- rindex takes a Regexp too
      p "hello".match?(/o/, -1)  # true -- position is end-relative when negative

      # --- String: split's optional limit ----------------------------------------
      p "a,b,c".split(",", 2)    # ["a", "b,c"]        -- positive caps the fields
      p "a,b,,".split(",")       # ["a", "b"]          -- trailing empties dropped
      p "a,b,,".split(",", -1)   # ["a", "b", "", ""]  -- negative keeps them
      p "one two three".each_line(" ").to_a  # ["one ", "two ", "three"]
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [2, 3]
      [1, 2, 3]
      [1, 2, 3]
      3
      3
      [9, 9, 9]
      [0, 9, 0]
      [1, 9, 9, 9, 9, 9]
      [0, 1, 2]
      [1, 2, 3, 4]
      [3, 4]
      [1, 3]
      5
      2
      2
      2
      3
      true
      ["a", "b,c"]
      ["a", "b"]
      ["a", "b", "", ""]
      ["one ", "two ", "three"]
    OUT
  end

  it "warn double splat" do
    result = ze0(<<~'RUBY')
      # Kernel#warn accepts a forwarded keyword-rest (`**opts`) as its options
      # bundle rather than a message. A double-splat made solely of forwarded hashes
      # is evaluated for side effects and otherwise ignored; positional messages
      # still reach stderr. (Literal uplevel:/category: keywords are unsupported and
      # rejected at compile time, since spinel models neither.)
      def s(x); x; end

      opts = s({})
      warn(**opts)              # forwarded empty options: no output
      warn("with opts", **opts) # positional message + forwarded options
      warn(**{})                # empty literal double-splat
      puts "stdout done"

      # the splat value is still evaluated (side effect preserved)
      $count = 0
      def make_opts; $count += 1; {}; end
      warn(**make_opts)
      p $count
    RUBY

    _(result).must_answer <<~'OUT', stderr: "with opts\n"
      stdout done
      1
    OUT
  end
end
