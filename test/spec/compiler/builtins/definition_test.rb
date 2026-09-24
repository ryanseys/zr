# frozen_string_literal: true

require "spec_helper"

describe "Builtins: defining and naming methods" do
  it "arity errors attribute to the callee frame like cruby" do
    result = zr(<<~'RUBY')
      # CRuby raises wrong-number-of-arguments / missing-keyword INSIDE the
      # callee: the innermost backtrace row is the callee's label at its
      # `def` line, and an `initialize`-less `.new` shows the C-frame shape
      # `'BasicObject#initialize'` at the CALLER's line. This battery was
      # verified verbatim against ruby 4.0.6 (the arity family was previously
      # an excluded, catalogued divergence of the frame-tracking battery).

      def f(a, b)
        a + b
      end
      begin
        f(1)
      rescue ArgumentError => e
        puts e.message
        puts e.backtrace.first.split('/').last
      end
      class Bag
        def initialize(x)
          @x = x
        end
      end
      begin
        Bag.new(1, 2, 3)
      rescue ArgumentError => e
        puts e.message
        puts e.backtrace.first.split('/').last
      end
      class Plain; end
      begin
        Plain.new(5)
      rescue ArgumentError => e
        puts e.message
        puts e.backtrace.first.split('/').last
      end
      def kw(x:)
        x
      end
      begin
        kw
      rescue ArgumentError => e
        puts e.message
        puts e.backtrace.first.split('/').last
      end
    RUBY

    _(result).must_answer <<~'OUT'
      wrong number of arguments (given 1, expected 2)
      definition_test.rb:8:in 'Object#f'
      wrong number of arguments (given 3, expected 1)
      definition_test.rb:18:in 'Bag#initialize'
      wrong number of arguments (given 1, expected 0)
      definition_test.rb:30:in 'BasicObject#initialize'
      missing keyword: :x
      definition_test.rb:35:in 'Object#kw'
    OUT
  end

  it "arity keyword argument errors" do
    result = zr(<<~'RUBY')
      # Statically-detectable argument-shape errors raise ArgumentError at runtime,
      # in CRuby's words: too many positionals, an unknown keyword, and a missing
      # required keyword. An options-hash call (no keyword matches any parameter)
      # still collapses into the positional hash, and splat/rest shapes are exempt.
      def m(a, b) = a + b
      begin
        puts m(1, 2, 3)
      rescue ArgumentError => e
        puts "1: #{e.message}"
      end
      def k(a:) = a
      begin
        puts k(a: 1, zzz: 2)
      rescue ArgumentError => e
        puts "2: #{e.message}"
      end
      class World
        def initialize(width:, height:)
          @w = width
          @h = height
        end
        def area = @w * @h
      end
      begin
        puts World.new(width: 150).area
      rescue ArgumentError => e
        puts "3: #{e.message}"
      end
      puts World.new(width: 3, height: 4).area
      def opts_hash(o = {}) = o.size
      puts opts_hash(timeout: 5, retries: 2)
      def rest(*xs) = xs.length
      puts rest(1, 2, 3, 4)
    RUBY

    _(result).must_answer <<~'OUT'
      1: wrong number of arguments (given 3, expected 2)
      2: unknown keyword: :zzz
      3: missing keyword: :height
      12
      2
      4
    OUT
  end

  it "builtin arity class methods" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at fa06b601.
      #
      # A builtin CLASS method's declared arity is wider than CRuby's, so a call
      # CRuby rejects is accepted and the ArgumentError names the wrong range:
      # zr reports `expected 1..4` where CRuby says `1..3`.
      #
      # One row the arity census gated before it was retired at zero.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix, not zr's divergence above.
      #
      # A builtin class/module method called with a count CRuby rejects raises
      # CRuby's ArgumentError. File.open with no arguments crashed the compiler.
      def check
        yield
      rescue => e
        p [e.class, e.message]
      end

      check { File.open }
      check { File.new }
      check { File.read }
      check { File.write("only-a-path") }
      check { IO.for_fd }
      check { IO.sysopen }
      check { Time.at }
      check { Hash.new(1, 2) }
      check { Integer.sqrt }
      check { Math.lgamma }
      check { Dir.mkdir }
      # the valid shapes still answer
      p Hash.new(5)[:missing]
      # A name no run ever creates: this corpus's own working directory is `tests/`,
      # so anything plausible there is a file somebody may add.
      p File.exist?("no-such-file-e7c1a0")
    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 0, expected 1..3)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1..3)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1..4)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 2..3)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1..2)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1..3)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1..3)"]
      [ArgumentError, "wrong number of arguments (given 2, expected 0..1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1..2)"]
      5
      false
    OUT
  end

  it "builtin arity instance" do
    result = zr(<<~'RUBY')
      # A builtin instance method called with a count CRuby rejects raises
      # CRuby's own ArgumentError, with its message.
      #
      # What this file was FILED for is fixed, and it crashed the whole
      # process: `Enumerable#first` with two arguments hit an internal
      # assumption about the argument count that the CALLER actually controls.
      # Ten such cases are ordinary raises now.
      #
      # Two more rows were silently LENIENT rather than loud: `Array#first` read
      # `args[0]` out of a `*args` it never counted, and `Range#first`/`#last`
      # spelled their bound `0..1` where CRuby's message spells it `1`.

      def check
        yield
      rescue => e
        p [e.class, e.message]
      end

      # missing required argument (compile-time SIGSEGV before the arity guard)
      check { (1..3).cover? }
      check { (1..3).include? }
      # an operator spelled as a method call with its operand missing
      check { :a.<=> }
      check { 1.+() }
      # too few for an exact multi-argument method
      s = +"x"
      check { s.insert(1) }
      h = {a: 1}
      check { h.store(1) }
      # too many for a zero-argument method
      check { :a.to_s(9) }
      check { "x".succ(1) }
      # too many for a bounded optional range
      check { "x".chomp("a", "b") }
      check { [1, 2].first(1, 2) }
      check { (1..2).first(1, 2) }
      # variadic minimum
      a = [1]
      check { a.insert }
      # the valid shapes still answer
      p (1..2).first
      p "x".chomp
      p [1, 2].first(1)
      # a block changes several counts: the bare-call spec must not fire
      p [1].fill { 9 }
    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 2)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 2)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 2, expected 0..1)"]
      [ArgumentError, "wrong number of arguments (given 2, expected 0..1)"]
      [ArgumentError, "wrong number of arguments (given 2, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1+)"]
      1
      "x"
      [1]
      [9]
    OUT
  end

  it "builtin reopen methods reachable via send" do
    result = zr(<<~'RUBY')
      # `send` with a literal symbol reaches a reopen method through
      # `send_value`'s value-method-first probe (the generated arity-checked
      # trampoline), same result as the direct static call.

      class String
        def echo(a, b)
          a.to_s + b.to_s + self
        end
      end

      puts "s".send(:echo, 1, 2)
      puts "s".echo(9, 8)
    RUBY

    _(result).must_answer "12s\n98s\n"
  end

  it "builtin reopen rest params and respond to" do
    result = zr(<<~'RUBY')
      # Full `Params` support on a reopen method (required + rest), plus
      # `respond_to?` seeing value methods through the widened registry probe.

      class String
        def tag(first, *rest)
          label = first.to_s
          rest.each do |r|
            label = label + "|" + r.to_s
          end
          label + ":" + self
        end
      end

      puts "v".tag("a", "b", "c")
      puts "w".tag("z")
      puts "x".respond_to?(:tag)
      puts "x".respond_to?(:zzz)
    RUBY

    _(result).must_answer <<~'OUT'
      a|b|c:v
      z:w
      true
      false
    OUT
  end

  it "class new arity" do
    result = zr(<<~'RUBY')
      # Class#new must enforce initialize's arity: extra (or missing) positional args
      # raise ArgumentError at the .new site, as in MRI. Previously the surplus args
      # were silently dropped and construction succeeded.
      class C; end
      def f; C.new(7); end
      begin
        f
        puts "no raise"
      rescue ArgumentError => e
        puts e.message                 # wrong number of arguments (given 1, expected 0)
      end

      class D
        def initialize(a, b); @a = a; @b = b; end
      end
      def too_few; D.new(1); end
      begin
        too_few
      rescue ArgumentError => e
        puts e.message                 # given 1, expected 2
      end

      def too_many; D.new(1, 2, 3); end
      begin
        too_many
      rescue ArgumentError => e
        puts e.message                 # given 3, expected 2
      end

      # Exactly-right construction still works.
      def ok; D.new(4, 5); end
      p ok.class                       # D

      # An initialize with an optional param accepts a range of counts.
      class E
        def initialize(a, b = 10); @a = a; @b = b; end
      end
      def e1; E.new(1); end
      def e2; E.new(1, 2); end
      p e1.class                       # E
      p e2.class                       # E
      def e_bad; E.new(1, 2, 3); end
      begin
        e_bad
      rescue ArgumentError => e
        puts e.message                 # given 3, expected 1..2
      end

      # A splat initialize takes any count -- no arity error.
      class F
        def initialize(*a); @a = a; end
      end
      def f_any; F.new(1, 2, 3, 4); end
      p f_any.class                    # F
    RUBY

    _(result).must_answer <<~'OUT'
      wrong number of arguments (given 1, expected 0)
      wrong number of arguments (given 1, expected 2)
      wrong number of arguments (given 3, expected 2)
      D
      E
      E
      wrong number of arguments (given 3, expected 1..2)
      F
    OUT
  end

  it "class value dispatch arity" do
    result = zr(<<~'RUBY')
      # Dispatch through a class-valued slot compiles to a switch over cls_id, and
      # each arm calls a different C function with its own parameter list. Passing
      # the caller's argument list verbatim only worked while every candidate took
      # exactly as many as the call supplied (#3526), and a class with no such
      # method fell out of the switch with the result slot at its default, which the
      # caller could not tell from an answer (#3527).
      class Holder
        def initialize(k)
          @k = k
        end

        def klass
          @k
        end

        def go1
          klass.f(1)
        end

        def go2
          klass.g(1, 2)
        end
      end

      class A
        def self.f(x, y = nil)
          "A.f(#{x.inspect}, #{y.inspect})"
        end

        def self.g(x, r)
          "A.g"
        end
      end

      class B
        def self.f(x, y = nil)
          "B.f(#{x.inspect}, #{y.inspect})"
        end

        def self.g(x, r, extra = nil)
          "B.g(extra=#{extra.inspect})"
        end
      end

      puts Holder.new(A).go1
      puts Holder.new(B).go1
      puts Holder.new(A).go2
      puts Holder.new(B).go2

      class NoMethods
      end

      begin
        Holder.new(NoMethods).go1
        puts "no raise"
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      A.f(1, nil)
      B.f(1, nil)
      A.g
      B.g(extra=nil)
      NoMethodError
    OUT
  end

  it "class value dispatch mixed arity" do
    result = zr(<<~'RUBY')
      # A method called through a variable holding a Class value dispatches on the
      # runtime class id, with one arm per class that defines the name. A candidate
      # whose method cannot take this call's argument count is not a possible
      # receiver HERE -- CRuby raises ArgumentError if you try -- but it used to veto
      # the whole dispatch, so the call was refused at compile time (#4129).
      #
      # `Other` below is never called and never passed anywhere.
      module Other
        def self.answer(a, b) = "other #{a}#{b}"
      end

      module Grammar
        def self.answer(a) = "grammar #{a}"
      end

      def read(thing)
        thing.answer("x")
      end

      p read(Grammar)

      # Optional parameters make the acceptance a range, not an equality: the old
      # test compared nrequired to argc, so a candidate with a trailing default
      # called with the argument that fills it was refused too.
      module Loose
        def self.tag(a, b = "d") = "loose #{a}#{b}"
      end

      module Tight
        def self.tag(a, b) = "tight #{a}#{b}"
      end

      def label(thing, *rest)
        rest.length == 1 ? thing.tag(rest[0]) : thing.tag(rest[0], rest[1])
      end

      p label(Loose, "1")
      p label(Loose, "1", "2")
      p label(Tight, "1", "2")

      # The arm the call CAN reach still answers, and the arms it cannot are still
      # reachable through their own arity.
      def one(thing) = thing.answer("only")
      p one(Grammar)

      def two(thing) = thing.answer("a", "b")
      p two(Other)

      # Calling a class through a variable with an argument count its method cannot
      # take raises ArgumentError, as CRuby does, rather than answering nil.
      begin
        p one(Other)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "grammar x"
      "loose 1d"
      "loose 12"
      "tight 12"
      "grammar only"
      "other ab"
      ArgumentError: wrong number of arguments (given 1, expected 2)
    OUT
  end

  it "instance call arity" do
    result = zr(<<~'RUBY')
      # An over- or under-supplied instance call went through with the extra
      # arguments simply dropped, where the free-function path already raised.
      class K
        def g(a); a; end
        def h(a, b); [a, b]; end
        def opt(a, b = 2); [a, b]; end
        def lead(x = 1, y); [x, y]; end
        def rest(*a); a; end
      end

      k = K.new
      p((k.g(1, 2) rescue $!.class))
      p((k.g rescue $!.class))
      p((k.h(1) rescue $!.class))
      p((k.h(1, 2, 3) rescue $!.message))
      p k.g(1)
      p k.h(1, 2)
      p k.opt(1)
      p k.opt(1, 3)
      p((k.opt(1, 2, 3) rescue $!.class))
      p k.lead(8)
      p k.lead(7, 8)
      p k.rest(1, 2, 3)
      p k.rest

      require 'set'
      p((Set[1].union([2], [3]).to_a rescue $!.class))
      p(Set[1].union([2]).to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      "wrong number of arguments (given 3, expected 2)"
      1
      [1, 2]
      [1, 2]
      [1, 3]
      ArgumentError
      [1, 8]
      [7, 8]
      [1, 2, 3]
      []
      ArgumentError
      [1, 2]
    OUT
  end

  it "instance exec lenient arity" do
    result = zr(<<~'RUBY')
      # CRuby block arity is lenient: a direct instance_exec binds each
      # positional param to its arg in order, ignores surplus args, and binds
      # a param with no matching arg to nil. Box has a subclass to stay heap.
      class Box
        def initialize(v)
          @v = v
        end
      end

      class BoxPlus < Box
      end

      b = BoxPlus.new(5)

      # surplus args ignored (a=1, the 2 is dropped)
      puts b.instance_exec(1, 2) { |a| a + @v }

      # missing arg binds nil (a=1, c=nil)
      puts b.instance_exec(1) { |a, c| a.to_s + ":" + c.inspect }

      # no args, one param -> nil
      puts b.instance_exec { |a| a.inspect }

      # args but no params -> args ignored, body still runs
      puts b.instance_exec(7, 8) { @v * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      6
      1:nil
      nil
      10
    OUT
  end

  it "method arity" do
    result = zr(<<~'RUBY')
      # Method#arity is a compile-time constant derived from the target method's
      # parameter shape, read off the method's DefNode. A method reports its required
      # argument count, unless an optional positional, a rest parameter, a forwarding
      # `...`, or a non-mandatory keyword block makes it variadic, in which case it
      # reports -(required + 1). A required keyword counts as one mandatory argument
      # and keeps the method's arity fixed; a block parameter never affects arity.

      # Zero / required-only.
      def none; 1; end
      p method(:none).arity

      def one(x); x; end
      p method(:one).arity

      def two(a, b); a + b; end
      p method(:two).arity

      # Optional parameter -> variadic.
      def opt(x, y = 1); x + y; end
      p method(:opt).arity

      def two_one_opt(a, b, c = 0); a + b + c; end
      p method(:two_one_opt).arity

      # Rest parameter -> variadic.
      def splat(*xs); xs; end
      p method(:splat).arity

      def req_splat(x, *ys); x; end
      p method(:req_splat).arity

      # Post-splat required parameter: the requireds before and after the splat both
      # count toward the (variadic) required total.
      def post_splat(a, *b, c); a; end
      p method(:post_splat).arity

      # Keyword parameters. A required keyword is one mandatory argument (fixed
      # arity); an optional keyword or keyword-rest with no required keyword is
      # variadic.
      def opt_kw(a, b: 1); a; end
      p method(:opt_kw).arity

      def req_kw(a, b:); a; end
      p method(:req_kw).arity

      def mix_kw(a, b:, c: 1); a; end
      p method(:mix_kw).arity

      def kw_rest(a, **kw); a; end
      p method(:kw_rest).arity

      def req_kw_rest(a, b:, **kw); a; end
      p method(:req_kw_rest).arity

      def kw_only_opt(b: 1); b; end
      p method(:kw_only_opt).arity

      def kw_only_req(b:); b; end
      p method(:kw_only_req).arity

      # Block parameter does not affect arity.
      def with_blk(a, &blk); a; end
      p method(:with_blk).arity

      # Through a local binding.
      adder = method(:two)
      p adder.arity

      # Instance method via recv.method(:name).
      class Calc
        def scale(value, factor); value * factor; end
      end
      p Calc.new.method(:scale).arity
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      -2
      -3
      -1
      -2
      -3
      -2
      2
      2
      -2
      2
      -1
      1
      1
      2
      2
    OUT
  end

  it "method arity builtin" do
    result = zr(<<~'RUBY')
      # Method#arity for a builtin-receiver method object comes from a table dumped
      # from CRuby (#2700): the synthesized __bam wrapper's params are ABI plumbing,
      # not the builtin's signature.
      p("hello".method(:upcase).arity)
      p(5.method(:+).arity)
      p([1].method(:size).arity)
      p("s".method(:gsub).arity)
      p((1..2).method(:each).arity)
      m = "hello".method(:upcase)
      p m.arity
      p m.call
      # user methods keep the def-derived arity
      class U
        def two(a, b); a + b; end
        def var(a, *rest); a; end
      end
      p U.new.method(:two).arity
      p U.new.method(:var).arity
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
      -1
      0
      -1
      "HELLO"
      2
      -2
    OUT
  end

  it "method arity for builtins and accessors" do
    result = zr(<<~'RUBY')
      # Builtin-receiver method objects read a dumped CRuby arity table; attr and
      # struct accessors derive theirs from the accessor shape (reader 0, writer 1).

      p "hello".method(:upcase).arity
      p 5.method(:+).arity
      p [1].method(:size).arity
      class C; attr_accessor :x; end
      p C.new.method(:x).arity
      p C.new.method(:x=).arity
      S = Struct.new(:a)
      s = S.new(1)
      p s.method(:a).arity
      p s.method(:a=).arity
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
      0
      1
      0
      1
    OUT
  end

  it "method arity oracle" do
    result = zr(<<~'RUBY')
      # Comprehensive Method#arity / #parameters coverage, byte-diffed against the
      # ruby oracle. Each line prints the code expression next to its result so a
      # zr-vs-oracle diff points straight at the failing method. Builtin arities
      # are declared per-name at each method's `builtin_methods!` definition site
      # (mirroring CRuby's `rb_define_method` argc), so this is their regression gate.

      def show(label, val) = puts("#{label.ljust(34)} => #{val}")

      # --- user def arity: every positional / rest / keyword / block shape ---------
      def d0; end
      def d1(a); end
      def d2(a, b); end
      def dopt(a, b = 1); end
      def drest(*a); end
      def dreq_rest(a, *b); end
      def dpost(a, *b, c); end
      def dkopt(a, b: 1); end
      def dkreq(a, b:); end
      def dkmix(a, b:, c: 1); end
      def dkrest(a, **k); end
      def dkreq_rest(a, b:, **k); end
      def dkonly_req(b:); end
      def dblk(a, &b); end
      def dfwd(...); end
      %i[d0 d1 d2 dopt drest dreq_rest dpost dkopt dkreq dkmix dkrest dkreq_rest
         dkonly_req dblk dfwd].each { |m| show("def #{m}", method(m).arity) }

      show("method(:dkmix).parameters", method(:dkmix).parameters)
      show("method(:dpost).parameters", method(:dpost).parameters)
      show("method(:dblk).parameters",  method(:dblk).parameters)

      # --- attr + struct + data accessors ------------------------------------------
      class C
        attr_accessor :x
        attr_reader :y
        attr_writer :z
      end
      o = C.new
      show("attr_reader x",  o.method(:x).arity)
      show("attr_writer x=", o.method(:x=).arity)
      show("attr_reader y",  o.method(:y).arity)
      show("attr_writer z=", o.method(:z=).arity)
      show("UnboundMethod x",  C.instance_method(:x).arity)
      show("UnboundMethod x=", C.instance_method(:x=).arity)

      S = Struct.new(:a, :b)
      s = S.new(1, 2)
      show("Struct reader a",  s.method(:a).arity)
      show("Struct writer a=", s.method(:a=).arity)

      D = Data.define(:m, :n)
      dv = D.new(1, 2)
      show("Data reader m", dv.method(:m).arity)

      # --- Proc / lambda -----------------------------------------------------------
      show("proc {|a,b|}.arity",   proc { |a, b| }.arity)
      show("->(a,b){}.arity",      ->(a, b) {}.arity)
      show("proc {|a,b=1|}.arity", proc { |a, b = 1| }.arity)
      show("->(a,*b){}.arity",     ->(a, *b) {}.arity)
      show("proc{|a,b|}.params",       proc { |a, b| }.parameters)
      show("proc{|a,b|}.params(l:t)",  proc { |a, b| }.parameters(lambda: true))
      show("->(a,b){}.params(l:f)",    ->(a, b) {}.parameters(lambda: false))
      show("method(:d1).to_proc.arity",   method(:d1).to_proc.arity)
      show("method(:d1).to_proc.lambda?", method(:d1).to_proc.lambda?)

      # --- builtin arity: one labeled line per method, across many classes ---------
      {
        "Integer#+"          => 1.method(:+),
        "Integer#divmod"     => 1.method(:divmod),
        "Integer#gcd"        => 1.method(:gcd),
        "Integer#abs"        => 1.method(:abs),
        "Integer#bit_length" => 1.method(:bit_length),
        "Integer#<=>"        => 1.method(:<=>),
        "Integer#[]"         => 1.method(:[]),
        "Integer#digits"     => 1.method(:digits),
        "Integer#to_s"       => 1.method(:to_s),
        "Integer#pow"        => 1.method(:pow),
        "Integer#<<"         => 1.method(:<<),
        "Integer#coerce"     => 1.method(:coerce),
        "Float#round"        => 1.0.method(:round),
        "Float#ceil"         => 1.0.method(:ceil),
        "Float#nan?"         => 1.0.method(:nan?),
        "Float#divmod"       => 1.0.method(:divmod),
        "Float#step"         => 1.0.method(:step),
        "Float#to_i"         => 1.0.method(:to_i),
        "String#length"      => "s".method(:length),
        "String#upcase"      => "s".method(:upcase),
        "String#+"           => "s".method(:+),
        "String#*"           => "s".method(:*),
        "String#gsub"        => "s".method(:gsub),
        "String#sub"         => "s".method(:sub),
        "String#index"       => "s".method(:index),
        "String#center"      => "s".method(:center),
        "String#tr"          => "s".method(:tr),
        "String#count"       => "s".method(:count),
        "String#replace"     => "s".method(:replace),
        "String#insert"      => "s".method(:insert),
        "String#start_with?" => "s".method(:start_with?),
        "String#<<"          => "s".method(:<<),
        "String#<=>"         => "s".method(:<=>),
        "Array#size"         => [].method(:size),
        "Array#<<"           => [].method(:<<),
        "Array#push"         => [].method(:push),
        "Array#first"        => [].method(:first),
        "Array#map"          => [].method(:map),
        "Array#join"         => [].method(:join),
        "Array#+"            => [].method(:+),
        "Array#index"        => [].method(:index),
        "Array#include?"     => [].method(:include?),
        "Array#insert"       => [].method(:insert),
        "Array#dig"          => [].method(:dig),
        "Array#zip"          => [].method(:zip),
        "Array#rotate"       => [].method(:rotate),
        "Array#fill"         => [].method(:fill),
        "Array#reduce"       => [].method(:reduce),
        "Hash#size"          => {}.method(:size),
        "Hash#merge"         => {}.method(:merge),
        "Hash#fetch"         => {}.method(:fetch),
        "Hash#key?"          => {}.method(:key?),
        "Hash#dig"           => {}.method(:dig),
        "Hash#store"         => {}.method(:store),
        "Hash#invert"        => {}.method(:invert),
        "Range#include?"     => (1..2).method(:include?),
        "Range#cover?"       => (1..2).method(:cover?),
        "Range#step"         => (1..2).method(:step),
        "Range#sum"          => (1..2).method(:sum),
        "Range#first"        => (1..2).method(:first),
        "Range#exclude_end?" => (1..2).method(:exclude_end?),
        "Symbol#to_s"        => :x.method(:to_s),
        "Symbol#length"      => :x.method(:length),
        "Symbol#<=>"         => :x.method(:<=>),
        "Symbol#succ"        => :x.method(:succ),
        "Rational#+"         => Rational(1, 2).method(:+),
        "Rational#numerator" => Rational(1, 2).method(:numerator),
        "Complex#+"          => Complex(1, 2).method(:+),
        "Complex#abs"        => Complex(1, 2).method(:abs),
        "Complex#real"       => Complex(1, 2).method(:real),
        "Regexp#match"       => /a/.method(:match),
        "Regexp#source"      => /a/.method(:source),
        "Regexp#names"       => /a/.method(:names),
        "MatchData#[]"       => "abc".match(/(b)/).method(:[]),
        "MatchData#captures" => "abc".match(/(b)/).method(:captures),
        "NilClass#to_s"      => nil.method(:to_s),
        "NilClass#nil?"      => nil.method(:nil?),
        "TrueClass#&"        => true.method(:&),
        "Integer#clamp"      => 1.method(:clamp),
        "Integer#between?"   => 1.method(:between?),
        "Array#min"          => [1].method(:min),
        "Array#sort_by"      => [1].method(:sort_by),
        "Array#group_by"     => [1].method(:group_by),
        "Array#each_with_index"  => [1].method(:each_with_index),
        "Array#each_with_object" => [1].method(:each_with_object),
        "Array#partition"    => [1].method(:partition),
        "Array#tally"        => [1].method(:tally),
        "Time#year"          => Time.at(0).method(:year),
        "Time#+"             => Time.at(0).method(:+),
        "Time#strftime"      => Time.at(0).method(:strftime),
        "Time#<=>"           => Time.at(0).method(:<=>),
      }.each { |label, m| show(label, m.arity) }
    RUBY

    _(result).must_answer <<~'OUT'
      def d0                             => 0
      def d1                             => 1
      def d2                             => 2
      def dopt                           => -2
      def drest                          => -1
      def dreq_rest                      => -2
      def dpost                          => -3
      def dkopt                          => -2
      def dkreq                          => 2
      def dkmix                          => 2
      def dkrest                         => -2
      def dkreq_rest                     => 2
      def dkonly_req                     => 1
      def dblk                           => 1
      def dfwd                           => -1
      method(:dkmix).parameters          => [[:req, :a], [:keyreq, :b], [:key, :c]]
      method(:dpost).parameters          => [[:req, :a], [:rest, :b], [:req, :c]]
      method(:dblk).parameters           => [[:req, :a], [:block, :b]]
      attr_reader x                      => 0
      attr_writer x=                     => 1
      attr_reader y                      => 0
      attr_writer z=                     => 1
      UnboundMethod x                    => 0
      UnboundMethod x=                   => 1
      Struct reader a                    => 0
      Struct writer a=                   => 1
      Data reader m                      => 0
      proc {|a,b|}.arity                 => 2
      ->(a,b){}.arity                    => 2
      proc {|a,b=1|}.arity               => 1
      ->(a,*b){}.arity                   => -2
      proc{|a,b|}.params                 => [[:opt, :a], [:opt, :b]]
      proc{|a,b|}.params(l:t)            => [[:req, :a], [:req, :b]]
      ->(a,b){}.params(l:f)              => [[:opt, :a], [:opt, :b]]
      method(:d1).to_proc.arity          => 1
      method(:d1).to_proc.lambda?        => true
      Integer#+                          => 1
      Integer#divmod                     => 1
      Integer#gcd                        => 1
      Integer#abs                        => 0
      Integer#bit_length                 => 0
      Integer#<=>                        => 1
      Integer#[]                         => -1
      Integer#digits                     => -1
      Integer#to_s                       => -1
      Integer#pow                        => -1
      Integer#<<                         => 1
      Integer#coerce                     => 1
      Float#round                        => -1
      Float#ceil                         => -1
      Float#nan?                         => 0
      Float#divmod                       => 1
      Float#step                         => -1
      Float#to_i                         => 0
      String#length                      => 0
      String#upcase                      => -1
      String#+                           => 1
      String#*                           => 1
      String#gsub                        => -1
      String#sub                         => -1
      String#index                       => -1
      String#center                      => -1
      String#tr                          => 2
      String#count                       => -1
      String#replace                     => 1
      String#insert                      => 2
      String#start_with?                 => -1
      String#<<                          => 1
      String#<=>                         => 1
      Array#size                         => 0
      Array#<<                           => 1
      Array#push                         => -1
      Array#first                        => -1
      Array#map                          => 0
      Array#join                         => -1
      Array#+                            => 1
      Array#index                        => -1
      Array#include?                     => 1
      Array#insert                       => -1
      Array#dig                          => -1
      Array#zip                          => -1
      Array#rotate                       => -1
      Array#fill                         => -1
      Array#reduce                       => -1
      Hash#size                          => 0
      Hash#merge                         => -1
      Hash#fetch                         => -1
      Hash#key?                          => 1
      Hash#dig                           => -1
      Hash#store                         => 2
      Hash#invert                        => 0
      Range#include?                     => 1
      Range#cover?                       => 1
      Range#step                         => -1
      Range#sum                          => -1
      Range#first                        => -1
      Range#exclude_end?                 => 0
      Symbol#to_s                        => 0
      Symbol#length                      => 0
      Symbol#<=>                         => 1
      Symbol#succ                        => 0
      Rational#+                         => 1
      Rational#numerator                 => 0
      Complex#+                          => 1
      Complex#abs                        => 0
      Complex#real                       => 0
      Regexp#match                       => -1
      Regexp#source                      => 0
      Regexp#names                       => 0
      MatchData#[]                       => -1
      MatchData#captures                 => 0
      NilClass#to_s                      => 0
      NilClass#nil?                      => 0
      TrueClass#&                        => 1
      Integer#clamp                      => -1
      Integer#between?                   => 2
      Array#min                          => -1
      Array#sort_by                      => 0
      Array#group_by                     => 0
      Array#each_with_index              => -1
      Array#each_with_object             => 1
      Array#partition                    => 0
      Array#tally                        => -1
      Time#year                          => 0
      Time#+                             => 1
      Time#strftime                      => 1
      Time#<=>                           => 1
    OUT
  end

  it "method arity parameters" do
    result = zr(<<~'RUBY')
      # Method / UnboundMethod — arity, parameters, bind, and bind_call.

      class Calc
        def add(a, b); a + b; end
        def scale(x, factor = 2); x * factor; end
        def variadic(first, *rest, last); [first, rest, last]; end
        def keyed(x, y:, z: 0); x + y + z; end
        def nullary; 42; end
      end

      c = Calc.new

      # Bound Method: call, arity, parameters.
      m = c.method(:add)
      p m.call(3, 4)                 # 7
      p m.arity                      # 2
      p m.parameters                 # [[:req, :a], [:req, :b]]

      p c.method(:scale).arity       # -2 (one optional)
      p c.method(:scale).parameters  # [[:req, :x], [:opt, :factor]]
      p c.method(:variadic).arity    # -3 (req + rest + post-req)
      p c.method(:variadic).parameters
      p c.method(:keyed).arity       # 2 (x + required keyword y)
      p c.method(:keyed).parameters  # [[:req, :x], [:keyreq, :y], [:key, :z]]
      p c.method(:nullary).arity     # 0

      # UnboundMethod via Module#instance_method.
      um = Calc.instance_method(:add)
      p um.class                     # UnboundMethod
      p um.name                      # :add
      p um.arity                     # 2
      bound = um.bind(c)
      p bound.class                  # Method
      p bound.call(10, 20)           # 30
      p um.bind_call(c, 5, 6)        # 11

      # Method#unbind is the inverse.
      p c.method(:add).unbind.class  # UnboundMethod

      # bind rejects an incompatible receiver.
      begin
        um.bind("not a Calc")
      rescue TypeError
        puts "TypeError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      2
      [[:req, :a], [:req, :b]]
      -2
      [[:req, :x], [:opt, :factor]]
      -3
      [[:req, :first], [:rest, :rest], [:req, :last]]
      2
      [[:req, :x], [:keyreq, :y], [:key, :z]]
      0
      UnboundMethod
      :add
      2
      Method
      30
      11
      UnboundMethod
      TypeError
    OUT
  end

  it "method arity parameters and unbound bind" do
    result = zr(<<~'RUBY')
      class C
        def a(x, y); x + y; end
        def b(x, y=1); end
        def d(x, y:, z: 2); end
        def f(x, *r, z, k:, **o, &blk); end
        def g; end
      end
      o = C.new
      puts o.method(:a).arity                 # 2
      puts o.method(:a).parameters.inspect     # [[:req, :x], [:req, :y]]
      puts o.method(:b).arity                 # -2
      puts o.method(:d).arity                 # 2
      puts o.method(:d).parameters.inspect     # [[:req,:x],[:keyreq,:y],[:key,:z]]
      puts o.method(:f).arity                 # -4
      puts o.method(:g).arity                 # 0
      um = C.instance_method(:a)
      puts um.class                           # UnboundMethod
      puts um.name                            # a
      puts um.arity                           # 2
      puts um.bind(o).call(2, 3)              # 5
      puts um.bind_call(o, 4, 5)              # 9
      puts o.method(:a).unbind.class          # UnboundMethod
      begin
        um.bind(42)
      rescue TypeError
        puts "typeerror"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      2
      [[:req, :x], [:req, :y]]
      -2
      2
      [[:req, :x], [:keyreq, :y], [:key, :z]]
      -4
      0
      UnboundMethod
      a
      2
      5
      9
      UnboundMethod
      typeerror
    OUT
  end

  it "method arity reflects the keyword shape" do
    result = zr(<<~'RUBY')
      # A required keyword adds one fixed mandatory slot; an optional keyword or
      # keyword-rest with NO required keyword makes the method variadic. An
      # optional positional or rest is variadic; a block never affects arity.

      def none; end
      def two(a, b); end
      def opt(x, y = 1); end
      def splat(*xs); end
      def post_splat(a, *b, c); end
      def opt_kw(a, b: 1); end
      def req_kw(a, b:); end
      def mix_kw(a, b:, c: 1); end
      def kw_rest(a, **kw); end
      def req_kw_rest(a, b:, **kw); end
      def with_blk(a, &blk); end
      p [method(:none).arity, method(:two).arity, method(:opt).arity,
         method(:splat).arity, method(:post_splat).arity, method(:opt_kw).arity,
         method(:req_kw).arity, method(:mix_kw).arity, method(:kw_rest).arity,
         method(:req_kw_rest).arity, method(:with_blk).arity]
    RUBY

    _(result).must_answer "[0, 2, -2, -1, -3, -2, 2, 2, -2, 2, 1]\n"
  end

  it "new with the wrong arity raises a rescuable runtime error" do
    result = zr(<<~'RUBY')
      # Was a COMPILE-TIME crash, from `.new`'s own hand-rolled argument
      # binding. Now that `.new` binds through the same call-argument
      # lowering every other call site uses, it inherits that posture,
      # which is real Ruby's: arity resolves at RUNTIME, the error is
      # rescuable, and a never-executed bad call compiles fine. Both lines
      # oracle-verified, message included.

      class Bag
        def initialize(a, b = 1); end
      end
      begin
        Bag.new(1, 2, 3)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
      def never_called
        Bag.new(1, 2, 3)
      end
      puts "compiled fine"
    RUBY

    _(result).must_answer "ArgumentError: wrong number of arguments (given 3, expected 1..2)\ncompiled fine\n"
  end

  it "numbered param arity" do
    result = zr(<<~'RUBY')
      # The highest _N used is the numbered-param proc's mandatory arity.
      p(-> { _1 }.arity)
      p(-> { _2 }.arity)
      p(-> { _1 + _3 }.arity)
      p(proc { _1 }.arity)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      1
    OUT
  end

  it "reflection universals" do
    result = zr(<<~'RUBY')
      # Universal reflection, to_set, and Regexp#timeout.

      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end
      end

      pt = Point.new(3, 4)
      p pt.instance_variables
      p pt.instance_variable_get(:@x)
      p pt.instance_variable_set(:@x, 99)
      p pt.instance_variable_get(:@x)
      p pt.instance_variable_defined?(:@y)
      p pt.instance_variable_defined?(:@z)

      # Value types expose no ivars and no per-object singleton methods.
      p 42.instance_variables
      p 42.instance_variable_get(:@a)
      p "s".singleton_methods

      # respond_to? now agrees with the universal reflection methods.
      p 42.respond_to?(:instance_variables)
      p 42.respond_to?(:instance_variable_get)
      p 42.respond_to?(:singleton_methods)

      # A dynamic send resolves them too.
      p 42.send(:instance_variables)

      # to_set reaches Array, Range, and Hash through Enumerable.
      p [1, 2, 2, 3].to_set
      p (1..3).to_set
      p({ a: 1, b: 2 }.to_set.size)

      # Regexp timeout reports the (absent) default.
      p(/x/.timeout)
      p Regexp.timeout
    RUBY

    _(result).must_answer <<~'OUT'
      [:@x, :@y]
      3
      99
      99
      true
      false
      []
      nil
      []
      true
      true
      true
      []
      Set[1, 2, 3]
      Set[1, 2, 3]
      2
      nil
      nil
    OUT
  end

  it "respond to core class surface" do
    result = zr(<<~'RUBY')
      # A core class object answers the Class/Module surface every class has, but it
      # has no user class entry, so the fold never consulted that list and the probe
      # cannot type a bare `Range.new` -- it is the call that builds a value, not one
      # that has a value (#3494).
      p Range.new(1, 3).to_a
      p Range.respond_to?(:new)
      p Symbol.respond_to?(:all_symbols)
      p Array.respond_to?(:instance_method)
      p Array.respond_to?(:new)
      p Array.respond_to?(:instance_methods)
      p String.respond_to?(:ancestors)
      p Integer.respond_to?(:superclass)
      p Hash.respond_to?(:method_defined?)

      # a name a class object genuinely does not answer stays false
      p Array.respond_to?(:no_such_class_method)
      p Range.respond_to?(:all_symbols)

      # a module answers the module surface but not :new
      module Mod
        def helper
          1
        end
      end
      p Mod.respond_to?(:instance_methods)
      p Mod.respond_to?(:instance_method)
      p Mod.respond_to?(:new)

      # a user class still answers its own class methods and the universal ones
      class UC
        def self.build
          new
        end
      end
      p UC.respond_to?(:build)
      p UC.respond_to?(:new)
      p UC.respond_to?(:instance_method)
      p UC.respond_to?(:nope)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      true
      true
      true
      true
      true
      true
      true
      true
      false
      false
      true
      true
      false
      true
      true
      true
      false
    OUT
  end

  it "splat into fixed arity builtin" do
    result = zr(<<~'RUBY')
      # compile side (#3515): the splat reached the slot expecting a single key
      k001 = [:a]
      p({ a: 1 }.fetch(*k001))

      k003 = ["a"]
      p({ "a" => 1 }.fetch(*k003))

      k004 = [1, :x]
      a004 = [1, 2]
      a004.insert(*k004)
      p a004

      k005 = [:b, 2]
      h005 = { a: 1 }
      h005.store(*k005)
      p h005

      # runtime side (#3516): it compiled and dropped the extra arguments
      k006 = [:b]
      h006 = { a: 1 }
      h006[*k006] = 9
      p h006

      k007 = [0, 2]
      p([1, 2, 3].slice(*k007))
      p([1, 2, 3][*k007])

      k008 = [1, 2]
      p("hello".slice(*k008))
      p("hello"[*k008])

      k009 = [5, :d]
      p([9].fetch(*k009))

      k010 = [0, 2]
      a010 = [1, 2, 3]
      a010.fill(9, *k010)
      p a010

      k011 = [1]
      p({ 1 => :x }.fetch(*k011))

      k012 = ["l", "L"]
      p("hello".sub(*k012))

      # a literal splat, no local in between
      p([1, 2, 3].slice(*[0, 2]))

      # the forms that already worked stay working: a user method reads the array
      # into its params, and the variadic builtins take it as it stands
      def two(a, b)
        a + b
      end
      k013 = [1, 2]
      p two(*k013)
      p [1, 2, 3].dig(*[0])
      p [1, 2, 3].values_at(*[0, 2])
      a014 = [1, 2]
      a014.push(*[3, 4])
      p a014
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      [1, :x, 2]
      {a: 1, b: 2}
      {a: 1, b: 9}
      [1, 2]
      [1, 2]
      "el"
      "el"
      :d
      [9, 9, 3]
      :x
      "heLlo"
      [1, 2]
      3
      1
      [1, 3]
      [1, 2, 3, 4]
    OUT
  end

  it "undef method retires a native row" do
    result = zr(<<~'RUBY')
      # `undef_method` writes a TOMBSTONE in the overlay -- the only record that a
      # native row was retired, since a builtin's `class_table` is a static list.
      # `respond_to?`/`method_defined?` already read it; dispatch did not, so the
      # predicate said no and the call still answered.

      class Array
        undef_method :zip
      end
      p Array.method_defined?(:zip)
      p [1].respond_to?(:zip)
      begin; [1].zip([2]); rescue NoMethodError => e; p e.class; end
      begin; [1].send(:zip, [2]); rescue NoMethodError => e; p [:send, e.class]; end
      # Everything else on the class is untouched.
      p [3, 1, 2].sort
      p [1, 2].map { |x| x * 2 }

      # A SUBCLASS retires the inherited row for itself only.
      class Stack < Array
        undef_method :size
      end
      p Stack.method_defined?(:size)
      begin; Stack.new.size; rescue NoMethodError => e; p e.class; end
      p Stack.new.length
      p [1, 2].size

      # The bare `undef` keyword reaches the same rows.
      class Queue2 < Array
        undef push
      end
      begin; Queue2.new.push(1); rescue NoMethodError => e; p e.class; end
      p Queue2.new << 1

      # A name no ancestor defines is a NameError, not a silent no-op.
      begin
        Array.send(:undef_method, :no_such_method_at_all)
      rescue NameError => e
        p e.class
      end

      # A user class is unaffected by the builtin tombstones.
      class Plain2
        def size; :plain; end
      end
      p Plain2.new.size
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      NoMethodError
      [:send, NoMethodError]
      [1, 2, 3]
      [2, 4]
      false
      NoMethodError
      0
      2
      NoMethodError
      [1]
      NameError
      :plain
    OUT
  end

  it "value trampoline wrong arity raises a rescuable argument error" do
    result = zr(<<~'RUBY')
      # This dynamic-dispatch trampoline backs both a user CLASS method reached
      # dynamically and a reopened-builtin instance method. Its arity guard
      # used to crash the process the same way the other dynamic trampoline
      # did; both now raise a rescuable ArgumentError. Oracle-verified.

      class A
        def self.cm(a, b) = a + b
      end
      class Integer
        def double(a); self * 2; end
      end
      k = A
      begin
        k.send(:cm, 1)
      rescue ArgumentError => e
        puts "cm: #{e.message}"
      end
      begin
        5.send(:double)
      rescue ArgumentError => e
        puts "double: #{e.message}"
      end
      puts "survived"
    RUBY

    _(result).must_answer <<~'OUT'
      cm: wrong number of arguments (given 1, expected 2)
      double: wrong number of arguments (given 0, expected 1)
      survived
    OUT
  end
end
