# frozen_string_literal: true

require "spec_helper"

describe "String: formatting and inspection" do
  it "byref string param instance method" do
    result = zr(<<~'RUBY')
      # `def add(buf, i); buf << ...; end` is ordinary Ruby: the append lands in the
      # caller's string. Only free functions and class methods took the out-param
      # ABI, so an INSTANCE method appended to a copy and the caller's buffer stayed
      # empty -- the log a benchmark built line by line came out zero-length and
      # every later match found nothing.

      class Builder
        def initialize
          @log = String.new
        end

        attr_reader :log

        def add(str, i)
          str << "line" << i.to_s << "\n"
        end

        def build_local(n)
          buf = String.new
          n.times { |i| add(buf, i) }
          buf
        end

        def build_ivar(n)
          @log = String.new
          n.times { |i| add(@log, i) }
          @log
        end
      end

      b = Builder.new
      p b.build_local(3).length
      p b.build_ivar(3).length
      p b.log.split("\n").size
      p b.build_ivar(2)
    RUBY

    _(result).must_answer <<~'OUT'
      18
      18
      3
      "line0\nline1\n"
    OUT
  end

  it "empty symbol literal" do
    result = zr(<<~'RUBY')
      # The empty symbol literal `:""` is a real SymbolNode whose content is
      # "". collect_sym_names skipped "" (its shared helper guards param-name
      # callers against a blank), so the symbol got no table entry and
      # compile_symbol_literal fell back to sp_sym_intern -- a function that is
      # only emitted when the intern path is otherwise needed, leaving an
      # `undefined reference to sp_sym_intern` link failure for a bare `:""`.

      s = :""
      puts s.to_s.length          #=> 0
      puts(s == :"")              #=> true
      puts(:"" == :"")           #=> true
      puts(:"" == :a)            #=> false

      # In a symbol array and as a value.
      arr = [:"", :a, :""]
      puts arr.length             #=> 3
      puts arr[0].to_s.length     #=> 0
      puts arr[1].to_s            #=> a

      # Round-trips through to_s/to_sym.
      t = "".to_sym
      puts(t == :"")             #=> true
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      0
      true
      true
      false
      3
      0
      a
      true
      done
    OUT
  end

  it "env nil string to s" do
    result = zr(<<~'RUBY')
      v = ENV["SPINEL_NO_SUCH_1664"].to_s
      puts v == ""
      puts v.length
      puts v.nil?
      w = ENV["SPINEL_NO_SUCH_1664"]
      puts w.nil?
      ENV["SPINEL_T_1664"] = "val"
      puts ENV["SPINEL_T_1664"].to_s
      ENV["SPINEL_T_1664"] = nil
      puts ENV["SPINEL_T_1664"].nil?
      puts "x#{ENV["SPINEL_NO_SUCH_1664"]}y"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      0
      false
      true
      val
      true
      xy
    OUT
  end

  it "kwrest non symbol keys" do
    result = zr(<<~'RUBY')
      # A `**kwrest` parameter captures keyword arguments with ANY key, not just
      # symbols -- the options-hash idiom `method CONST => :value` (Thor's
      # `map HELP_MAPPINGS => :help`) passes a non-symbol key, which real Ruby routes
      # into `**kw` as a hash entry (a keyword parameter NAME is always a symbol, so a
      # non-symbol key can only land in the rest). Distinct from an explicit `{...}`
      # positional Hash, which the Ruby 3 keyword separation keeps out of `**kw`.
      HELP = %w[-h --help]

      def cmd(mappings = nil, **kw)
        "m=#{mappings.inspect} kw=#{kw.inspect}"
      end

      puts cmd HELP => :help        # non-symbol (array) key -> **kw
      puts cmd(a: 1, b: 2)          # symbol keys -> **kw
      puts cmd("s" => 1, x: 2)      # mixed keys -> one **kw hash
      puts cmd({ z: 9 })            # explicit hash is POSITIONAL, not keywords

      def only_kw(**opts)
        opts.inspect
      end

      puts only_kw HELP => :help
      puts only_kw(a: 1)
    RUBY

    _(result).must_answer <<~'OUT'
      m=nil kw={["-h", "--help"] => :help}
      m=nil kw={a: 1, b: 2}
      m=nil kw={"s" => 1, x: 2}
      m={z: 9} kw={}
      {["-h", "--help"] => :help}
      {a: 1}
    OUT
  end

  it "literal string markers" do
    result = zr(<<~'RUBY')
      # Every string spinel hands back to Ruby carries a marker byte at [-1].
      # sp_gc_mark reads it to decide whether a rooted pointer is a literal to skip
      # or a heap object whose mark word it should write, so a runtime arm that
      # returns a BARE C literal is a fault waiting for a collection: the collector
      # reads whatever rodata precedes the literal, fails to recognise a marker,
      # concludes it has a heap object and writes into read-only memory.
      #
      # Each value below is held in a live local across an explicit GC.start, which
      # is exactly that window. #3393 fixed sp_sym_to_s's empty return; these are the
      # rest of the same family (class names, the inspect fallbacks, an exception
      # with no object behind it).

      def churn
        a = []
        200.times { |i| a.push("filler #{i}") }
        a.length
      end

      def through_gc(s)
        churn
        GC.start
        churn
        GC.start
        s
      end

      require "stringio"

      p through_gc(StringIO.new("x").class.to_s)
      p through_gc($stdout.class.to_s)
      p through_gc(proc { 1 }.inspect).start_with?("#<Proc")
      p through_gc([1, 2].each.inspect).start_with?("#<Enumerator")
      p through_gc(:sym.inspect)
      p through_gc(1.method(:+).inspect).start_with?("#<Method")

      begin
        raise "boom"
      rescue => e
        p through_gc(e.class.to_s)
        p through_gc(e.message)
      end

      # a nil Symbol slot renders through sp_sym_to_s's out-of-range arm (#3393)
      class Holder
        def initialize(s)
          @s = s
        end

        def label
          @s
        end
      end
      p through_gc(Holder.new(nil).label.to_s).length
      p through_gc(:named.to_s)

      # $0 is argv[0], which lives in the process's argument block rather than the
      # string heap; it is an ordinary Ruby String all the same
      p through_gc($0).class.to_s
      p through_gc($PROGRAM_NAME).length > 0
    RUBY

    _(result).must_answer <<~'OUT'
      "StringIO"
      "IO"
      true
      true
      ":sym"
      true
      "RuntimeError"
      "boom"
      0
      "named"
      "String"
      true
    OUT
  end

  it "method name symbol" do
    result = zr(<<~'RUBY')
      # Method#name returns a Symbol (not a String), matching CRuby. The method
      # object is also routed through a param so the `.name` runs on a non-folded
      # TY_METHOD value.
      class Calc
        def add(a, b); a + b; end
        def noarg; 0; end
        def +(other); 1; end
      end
      c = Calc.new

      m = c.method(:add)
      p m.name                  # :add
      puts m.name.inspect       # :add
      puts m.name == :add       # true
      puts m.name.class         # Symbol
      puts m.name.to_s          # add

      # no-arg method
      puts c.method(:noarg).name.inspect   # :noarg

      # operator method name
      p c.method(:+).name       # :+

      # routed through a method param to defeat constant-folding
      def id(x); x; end
      p id(c.method(:add)).name # :add

      # usable as a case/when scrutinee against symbol literals
      case m.name
      when :add then puts "is add"
      else puts "other"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      :add
      :add
      true
      Symbol
      add
      :noarg
      :+
      :add
      is add
    OUT
  end

  it "numeric string argument" do
    result = zr(<<~'RUBY')
      r001 = (5.div("x") rescue $!.class)
      p r001

      r002 = (5.gcdlcm("x") rescue $!.class); p r002
      r003 = (5.modulo("x") rescue $!.class); p r003
      r004 = (5.remainder("x") rescue $!.class); p r004
      r005 = (5.divmod("x") rescue $!.class); p r005
      r006 = (5.pow("x") rescue $!.class); p r006
      r007 = (5.fdiv("x") rescue $!.class); p r007
      r008 = (5.digits("x") rescue $!.class); p r008
      r009 = (5.to_s("x") rescue $!.class); p r009
      r010 = (5.ceildiv("x") rescue $!.class); p r010
      r011 = (Integer.sqrt("x") rescue $!.class); p r011
      r012 = (1.5.fdiv("x") rescue $!.class); p r012
      r013 = (1.5.divmod("x") rescue $!.class); p r013
      r014 = (1.5.round("x") rescue $!.class); p r014
      r015 = (1.5.floor("x") rescue $!.class); p r015
      r016 = (1.5.ceil("x") rescue $!.class); p r016
      r017 = (1.5.truncate("x") rescue $!.class); p r017

      r018 = (5.coerce("x") rescue $!.class); p r018
      r019 = (1.5.coerce("x") rescue $!.class); p r019
      r020 = (5.clamp("a", "z") rescue $!.class); p r020
      r021 = (1.upto("a").to_a rescue $!.class); p r021
      r022 = (3.downto("a").to_a rescue $!.class); p r022
      r023 = (1.step("z", 1).to_a rescue $!.class); p r023
      r024 = (1.5.between?("a", "z") rescue $!.class); p r024

      r025 = (5.between?("a", "z") rescue $!.class); p r025   # Ruby: ArgumentError   Spinel: false

      p((5.gcd("x") rescue $!.class))     # both: TypeError
      p((5.lcm("x") rescue $!.class))     # both: TypeError
      p((1.5 + "x" rescue $!.class))      # both: TypeError
      p((1.5 ** "x" rescue $!.class))     # both: TypeError
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      TypeError
      TypeError
      TypeError
      TypeError
    OUT
  end

  it "str array uniq" do
    result = zr(<<~'RUBY')
      # Array#uniq (non-bang) on a str_array — returns a fresh array with
      # duplicates removed, first occurrence kept, order preserved. The
      # receiver stays a str_array. Routed through an identity method to
      # defeat constant folding and exercise the real typed runtime path.
      def as(x); x; end

      a = as(["a", "b", "a", "c", "b"])
      puts a.uniq.inspect
      puts a.inspect            # non-bang leaves the receiver untouched

      puts as(["x", "y", "z"]).uniq.inspect
      puts as([]).uniq.inspect

      # built via gsub (the widened-but-still-str_array path)
      u = "http://example.com/page#frag"
      urls = [u.gsub(/#.*/, "")]
      urls.push u.gsub(/#.*/, "")
      urls.push "http://other.test"
      puts urls.uniq.length
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["a", "b", "a", "c", "b"]
      ["x", "y", "z"]
      []
      2
    OUT
  end

  it "str int hash missing key nil" do
    result = zr(<<~'RUBY')
      h = {"a" => 1, "b" => 2}
      # Missing-key reads are value-level nil (#801).
      p h["miss"]
      p h["miss"].nil?
      p h["miss"].inspect
      p(h["miss"] || 42)
      # Stored in a local, then observed (the case the consumption-site rewrites miss).
      v = h["miss"]
      p v.nil?
      p(v || 7)
      # Present keys are unaffected.
      p h["a"]
      p h["a"].nil?
      p(h["a"] + 1)
      w = h["b"]
      p(w + 10)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      "nil"
      42
      true
      7
      1
      false
      2
      12
    OUT
  end

  it "a NUL is a byte of the string for length, bytes, == and a Hash key" do
    result = zr(<<~'RUBY')
      s = "a\0b"
      puts s.length
      puts s.bytes.inspect
      puts (s == "a\0b")
      puts (s == "a\0c")
      puts (s == "a")
      h = {}
      h[s] = 1
      h["a\0c"] = 2
      h["a"] = 3
      puts h.size
      d = s.dup
      puts d.bytes.inspect
      puts (d == s)
      t = "x" + 0.chr + "y"
      e = t[0, 3]
      puts e.bytes.inspect
      puts e.length
      puts s[2]
      f = "/tmp/spinel_nul_core_t.bin"
      File.write(f, s)
      r = File.read(f)
      puts r.bytes.inspect
      puts (r == s)
      File.delete(f)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [97, 0, 98]
      true
      false
      false
      3
      [97, 0, 98]
      true
      [120, 0, 121]
      3
      b
      [97, 0, 98]
      true
    OUT
  end

  it "repeat, +@, the justify family and the character walk all keep a NUL and what follows it" do
    result = zr(<<~'RUBY')
      # A NUL is an ordinary byte in a Ruby String, but repeat, unary plus, the
      # justify family and the character walk all sized themselves with strlen and
      # so dropped the NUL and everything after it. #3473.
      s = "a\0b"
      p((s * 2).bytes)
      p((+s).bytes)
      p(s.center(7, "-").bytes)
      p(s.ljust(6, "-").bytes)
      p(s.rjust(6, "-").bytes)
      p(s.center(7).bytes)
      p(s.ljust(6).bytes)
      p(s.rjust(6).bytes)
      p(s.chars.map(&:bytes))
      p(s.each_char.to_a.map(&:bytes))
      n = 0
      s.each_char { |ch| n += 1 }
      p n
      u = 0.chr * 3
      p(u.bytes)
      p(u.length)
      p(("" + 0.chr).ljust(3, "x").bytes)
      # the copy unary plus hands back is mutable, and keeps the NUL through an append
      c = +s
      c << "z"
      p(c.bytes)
    RUBY

    _(result).must_answer <<~'OUT'
      [97, 0, 98, 97, 0, 98]
      [97, 0, 98]
      [45, 45, 97, 0, 98, 45, 45]
      [97, 0, 98, 45, 45, 45]
      [45, 45, 45, 97, 0, 98]
      [32, 32, 97, 0, 98, 32, 32]
      [97, 0, 98, 32, 32, 32]
      [32, 32, 32, 97, 0, 98]
      [[97], [0], [98]]
      [[97], [0], [98]]
      3
      [0, 0, 0]
      3
      [0, 120, 120]
      [97, 0, 98, 122]
    OUT
  end

  it "a blockless each_char or each_line answers an Enumerator stamped with the string and the method" do
    result = zr(<<~'RUBY')
      # Blockless String#each_char / each_line / each_byte / each_codepoint
      # return Enumerators stamped with the ORIGINAL string receiver and creating
      # method, so #inspect shows #<Enumerator: "abc":each_char> -- not the
      # materialized snapshot array with a generic :each. Iteration still drains
      # the snapshot (next/to_a unchanged).
      p("abc".each_char)
      p("a\nb\n".each_line)
      p("ab".each_byte)
      p("ab".each_codepoint)
      p("x\ny\n".each_line(chomp: true))
      e = "hi".each_char
      p e.next
      p e.next
      p e.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      #<Enumerator: "abc":each_char>
      #<Enumerator: "a\nb\n":each_line>
      #<Enumerator: "ab":each_byte>
      #<Enumerator: "ab":each_codepoint>
      #<Enumerator: "x\ny\n":each_line(chomp: true)>
      "h"
      "i"
      ["h", "i"]
    OUT
  end

  it "inspect and dump escape an interpolation, a global, an ivar and a non-ASCII character" do
    result = zr(<<~'RUBY')
      p "a\#{x}".inspect
      p "a#b".dump
      p "é".dump
      p "é".inspect
      p "a#$g".dump
      p "a#@i".inspect
      p "plain".dump
      p "tab\there".dump
      p "\u{1F600}".dump
    RUBY

    _(result).must_answer <<~'OUT'
      "\"a\\\#{x}\""
      "\"a#b\""
      "\"\\u00E9\""
      "\"é\""
      "\"a\""
      "\"a\""
      "\"plain\""
      "\"tab\\there\""
      "\"\\u{1F600}\""
    OUT
  end

  it "undump is the inverse of dump, so the pair round-trips" do
    result = zr(<<~'RUBY')
      # String#undump is the inverse of String#dump. Round-tripping a string
      # through dump then undump returns the original (each engine round-trips
      # its own dump format, so the comparison is version-independent).
      # Previously undump was unresolved.
      ["hello", "a\tb\nc", "q\"u\\o#te", "tab\there", "café"].each do |s|
        puts(s.dump.undump == s)
      end
      # undump of an explicit dumped form
      puts "\"hi\\nthere\"".undump
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      hi
      there
    OUT
  end

  it "struct inspect labels non identifier members as symbols" do
    result = zr(<<~'RUBY')
      # A Struct/Data member whose name isn't a plain identifier prints with a
      # leading colon in inspect (`:verbose?=`), while a plain one stays bare.

      S = Struct.new(:verbose?, :name)
      p S.new(true, "x").inspect
      D = Data.define(:ok?, :count)
      p D.new(ok?: false, count: 3).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "#<struct S :verbose?=true, name=\"x\">"
      "#<data D :ok?=false, count=3>"
    OUT
  end

  it "symbol embedded nul" do
    result = zr(<<~'RUBY')
      # A symbol's NAME may hold a NUL. Everything downstream of the parser lost it:
      # the compiler interned by strdup/strcmp, the emitted name table measured with
      # strlen, and the runtime intern compared with strcmp. The node table always
      # carried the byte -- nothing was lost before codegen.
      #
      # A symbol is an integer at run time, so equality, hash lookup and case/when
      # never touch a name; only interning, #to_s, ordering and inspect do.
      a = :"a\0b"
      b = "a\0b".to_sym

      p a.to_s.bytesize
      p b.to_s.bytesize
      p a == b
      p a.to_s == "a\0b"
      p a.to_s == "a"
      p a.to_s.bytes
      p a.length
      p a.size

      # distinct names that share a prefix up to the NUL stay distinct
      p :"a\0b" == :"a\0c"
      p :"a\0b" == :a
      p [:"a\0b", :"a\0c", :a].map { |s| s.to_s.bytesize }

      # ordering is byte-exact: strcmp called the first two equal
      p(:"a\0b" <=> :"a\0b")
      p(:"a\0b" <=> :"a\0c")
      p(:a <=> :"a\0b")
      p [:"a\0b", :a].sort.map { |s| s.to_s.bytesize }

      # hash keys keep them apart
      h = { a => 1, :a => 2 }
      p h.size
      p h[a]
      p h[b]
      p h[:a]

      # and the ordinary symbol surface is untouched
      p :abc.to_s
      p :abc == :abc
      p :abc == :abd
      p(:abc <=> :abd)
      p({ abc: 1 }[:abc])
      p :abc.inspect
      p :"a b".inspect
      p %i[x y].map(&:to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      true
      true
      false
      [97, 0, 98]
      3
      3
      false
      false
      [3, 3, 1]
      0
      -1
      -1
      [1, 3]
      2
      1
      1
      2
      "abc"
      true
      false
      -1
      1
      ":abc"
      ":\"a b\""
      ["x", "y"]
    OUT
  end

  it "symbol id2name ruby desc minmax" do
    result = zr(<<~'RUBY')
      # #1249 Symbol#id2name: the symbol's name as a String (alias of to_s).
      p :hello.id2name
      p :foo_bar.id2name
      puts :sym.id2name.class

      # #1251 RUBY_DESCRIPTION is a String (value is engine-specific; only the
      # class is asserted so it stays portable).
      puts RUBY_DESCRIPTION.class

      # #1217 Range#minmax: [min, max], honouring exclusive end.
      p (1..10).minmax
      p (1...10).minmax
      p (5..5).minmax
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "foo_bar"
      String
      String
      [1, 10]
      [1, 9]
      [5, 5]
    OUT
  end

  it "symbol inspect quoting" do
    result = zr(<<~'RUBY')
      # A symbol prints unquoted when its name is a plain identifier (incl. a
      # constant), an @ivar/@@cvar/$gvar, a name ending in ? ! =, or a known operator
      # method name; otherwise it is quoted like a string. Hash symbol keys use the
      # short `name:` form, quoting the name when needed.

      # plain identifiers and constants
      p :abc
      p :Foo
      p :_x9

      # variable-sigil names
      p :@iv
      p :@@cv
      p :$g

      # method-name suffixes
      p :foo?
      p :bar!
      p :baz=

      # every operator method symbol prints unquoted
      p :+
      p :-
      p :*
      p :/
      p :%
      p :**
      p :==
      p :===
      p :!=
      p :=~
      p :!~
      p :<
      p :<=
      p :>
      p :>=
      p :<=>
      p :<<
      p :>>
      p :&
      p :|
      p :^
      p :~
      p :!
      p :+@
      p :-@
      p :[]
      p :[]=
      p :`

      # names that REQUIRE quoting
      p :"a b"
      p :"1x"
      p :""
      p :"has\"quote"
      p :"with\nnewline"
      p :"foo?bar"
      p :"@"

      # the .inspect method (string-returning path) agrees with p
      puts :"a b".inspect
      puts :plain.inspect
      sym = :"x y"
      puts sym.inspect

      # symbol array and symbol-keyed hash
      p [:"a b", :ok, :+, :"with space"]
      p({a: 1, "k space": 2, normal: 3, "1bad": 4})
    RUBY

    _(result).must_answer <<~'OUT'
      :abc
      :Foo
      :_x9
      :@iv
      :@@cv
      :$g
      :foo?
      :bar!
      :baz=
      :+
      :-
      :*
      :/
      :%
      :**
      :==
      :===
      :!=
      :=~
      :!~
      :<
      :<=
      :>
      :>=
      :<=>
      :<<
      :>>
      :&
      :|
      :^
      :~
      :!
      :+@
      :-@
      :[]
      :[]=
      :`
      :"a b"
      :"1x"
      :""
      :"has\"quote"
      :"with\nnewline"
      :"foo?bar"
      :"@"
      :"a b"
      :plain
      :"x y"
      [:"a b", :ok, :+, :"with space"]
      {a: 1, "k space": 2, normal: 3, "1bad": 4}
    OUT
  end

  it "user to s and inspect drive puts interpolation and p" do
    result = zr(<<~'RUBY')
      class Named
        def initialize(n)
          @n = n
        end

        def to_s
          "Named<#{@n}>"
        end

        def inspect
          "#<Named n=#{@n}>"
        end
      end

      n = Named.new(7)
      puts n
      puts "in a string: #{n}"
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      Named<7>
      in a string: Named<7>
      #<Named n=7>
    OUT
  end
end
