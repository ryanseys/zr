# frozen_string_literal: true

require "spec_helper"

describe "Fusion: searching and matching" do
  it "array index int opt narrow" do
    result = ze0(<<~'RUBY')
      # Array#index on int_array returns the new int? (scalar-nullable
      # int with INT64_MIN sentinel) instead of being widened to poly.
      # After the nil-check guard the value narrows back to plain int
      # so downstream arithmetic compiles to direct integer ops without
      # poly box/unbox.
      #
      # Sibling of nil_guard_narrows_int_or_nil.rb (which exercises the
      # same shape on String#index, still poly-widened). Both forms
      # behave identically at the Ruby level; this test pins the
      # int_array case so a regression in the int?-narrow path surfaces
      # here.

      ARR = [10, 20, 30, 40, 50]

      def offset_or_zero(arr, target)
        i = arr.index(target)
        return 0 if i.nil?
        i + 1
      end

      puts offset_or_zero(ARR, 30)    # 3
      puts offset_or_zero(ARR, 999)   # 0
      puts offset_or_zero(ARR, 10)    # 1

      # Inspect/.nil? on the int? value flows through the sentinel-aware
      # helpers (sp_int_opt_inspect / sp_int_is_nil).
      puts ARR.index(20).inspect      # 1
      puts ARR.index(999).inspect     # nil
      puts ARR.index(999).nil?        # true
      puts ARR.index(20).nil?         # false
    RUBY

    _(result).must_answer <<~'OUT'
      3
      0
      1
      1
      nil
      true
      false
    OUT
  end

  it "array splice" do
    result = ze0(<<~'RUBY')
      # Array#[]= in its SPLICE forms -- `a[start, len] = v` and `a[range] = v` --
      # replaces the span with the value's elements (CRuby's rb_ary_splice), which
      # is a different operation from the one-index store `a[i] = v`.

      # The plain index store still just stores.
      a = [1, 2, 3]
      a[1] = 9
      p a
      a[5] = 7
      p a
      a[-1] = 0
      p a

      # start/length: the span is replaced by the VALUE's elements.
      b = [1, 2, 3, 4]
      b[1, 2] = [:x, :y, :z]
      p b

      # Replacing with fewer elements shrinks the array.
      c = [1, 2, 3, 4]
      c[1, 3] = [:only]
      p c

      # A zero length INSERTS without removing.
      d = [1, 2, 3]
      d[1, 0] = [:a, :b]
      p d

      # A length past the end just truncates the span.
      e = [1, 2, 3]
      e[1, 99] = [:end]
      p e

      # Splicing at the end appends; past the end nil-pads first.
      f = [1, 2]
      f[2, 0] = [:x]
      p f
      g = [1]
      g[3, 0] = [:y]
      p g

      # A non-Array value inserts as ONE element.
      h = [1, 2, 3]
      h[0, 2] = :single
      p h

      # Negative starts count from the end.
      i = [1, 2, 3, 4]
      i[-2, 2] = [:last]
      p i

      # Range forms: inclusive and exclusive.
      j = [1, 2, 3, 4]
      j[1..2] = [:a]
      p j
      k = [1, 2, 3, 4]
      k[1...3] = [:b]
      p k

      # An endless / beginless range.
      l = [1, 2, 3, 4]
      l[2..] = [:tail]
      p l
      m = [1, 2, 3, 4]
      m[..1] = [:head]
      p m

      # A range with a negative bound.
      n = [1, 2, 3, 4]
      n[-2..] = [:z]
      p n

      # The expression VALUE is the right-hand side as written, never the coercion
      # or the receiver.
      o = [1, 2, 3]
      r = (o[0, 1] = [:v])
      p r

      # A user object defining to_ary is coerced through it, and its elements are
      # spliced -- while the expression value stays the object itself.
      class IntPair
        def initialize(a, b)
          @a = a
          @b = b
        end

        def to_ary
          [@a, @b]
        end
      end

      q = [1, 2, 3]
      q[1, 1] = IntPair.new(7, 8)
      p q

      s = [1, 2, 3, 4]
      s[1..2] = IntPair.new(9, 9)
      p s

      t = [1, 2, 3]
      value = (t[1, 1] = IntPair.new(6, 6))
      p value.is_a?(IntPair)
      p t

      # An object without to_ary inserts as a single element.
      class Opaque; end
      u = [1, 2, 3]
      u[0, 2] = Opaque.new
      p u.length
      p u[1]

      # A negative length raises.
      begin
        [1, 2, 3][0, -1] = [:x]
      rescue IndexError => e
        puts "IndexError: #{e.message}"
      end

      # A too-small negative index raises.
      begin
        [1, 2, 3][-9, 1] = [:x]
      rescue IndexError => e
        puts "IndexError: #{e.message}"
      end

      # Splicing works through a dynamically-typed receiver too.
      nested = [[1, 2, 3], "x"]
      nested[0][1, 1] = IntPair.new(4, 5)
      p nested[0]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 9, 3]
      [1, 9, 3, nil, nil, 7]
      [1, 9, 3, nil, nil, 0]
      [1, :x, :y, :z, 4]
      [1, :only]
      [1, :a, :b, 2, 3]
      [1, :end]
      [1, 2, :x]
      [1, nil, nil, :y]
      [:single, 3]
      [1, 2, :last]
      [1, :a, 4]
      [1, :b, 4]
      [1, 2, :tail]
      [:head, 3, 4]
      [1, 2, :z]
      [:v]
      [1, 7, 8, 3]
      [1, 9, 9, 4]
      true
      [1, 6, 6, 3]
      2
      3
      IndexError: negative length (-1)
      IndexError: index -9 too small for array; minimum: -3
      [1, 4, 5, 3]
    OUT
  end

  it "array splice widen" do
    result = ze0(<<~'RUBY')
      # Analysis-time widening: an index write or splice whose value a typed array
      # cannot hold widens the local (or ivar) to a poly array, so the write stores
      # the value exactly as CRuby does instead of rejecting (or miscompiling the
      # single-index form). The receivers here are direct locals -- the static
      # route, complementing the runtime-promotion route in array_splice.rb.

      # single-index []= with a mismatched value (formerly emitted invalid C)
      a = [1, 2]
      a[0] = "s"
      p a
      b = [1, 2]
      b[1] = nil
      p b
      f = [1.5, 2.5]
      f[0] = "x"
      p f

      # splice with a mismatched-element array source
      c = [1, 2, 3]
      c[1, 1] = ["x"]
      p c

      # splice with a mismatched scalar source
      d = [1, 2, 3]
      d[0, 2] = "s"
      p d

      # range-form splice with a mixed source
      e = [1, 2, 3]
      e[1..2] = [nil, "y"]
      p e

      # nil-gap fill past the end now works on a (widened) direct local
      g = [1, 2]
      g[4, 0] = ["z"]
      p g

      # same-element-type splices keep the typed representation (and still splice)
      h = [1, 2, 3, 4]
      h[1, 2] = [9]
      p h

      # aliasing: the widened local and its alias see the same array
      i = [1, 2]
      j = i
      i[0] = :sym
      p j

      # value position: the expression value is the RHS as written
      k = [1, 2, 3]
      p(k[1, 1] = "v")
      p k

      # ivar route: a typed ivar widened by a mismatched splice in another method
      class Holder
        def initialize
          @xs = [1, 2, 3]
        end
        def poke
          @xs[1, 1] = ["mid"]
        end
        def dump
          @xs
        end
      end
      hh = Holder.new
      hh.poke
      p hh.dump

      # the alias fix also covers push widening (previously read garbage through j)
      pi = [1, 2]
      pj = pi
      pi << "s"
      p pj
    RUBY

    _(result).must_answer <<~'OUT'
      ["s", 2]
      [1, nil]
      ["x", 2.5]
      [1, "x", 3]
      ["s", 3]
      [1, nil, "y"]
      [1, 2, nil, nil, "z"]
      [1, 9, 4]
      [:sym, 2]
      "v"
      [1, "v", 3]
      [1, "mid", 3]
      [1, 2, "s"]
    OUT
  end

  it "cmethod specialize samename unrelated" do
    result = ze0(<<~'RUBY')
      # Issue #1314. `specialize_inherited_cls_new` clones an inherited class
      # method that does a bare `new` (or a subclass-specific cmethod call)
      # into each subclass that calls it, then DCEs the now-shadowed source
      # unless it is called directly as `<DefiningClass>.<name>`. The
      # "was this specialized?" test used to match by method *name* only, so
      # specializing `Base.find` into `Article` also flagged the completely
      # unrelated `Store.find` (same name, different class) as a transplanted
      # source and dropped it from emission. When `Store.find` was still
      # reachable and called through a non-constant receiver (here a bare
      # sibling call, which is not "called directly as Store.find"), its body
      # was never emitted while the call site survived -- the generated C then
      # referenced an undefined `sp_Store_s_find`, failing to compile.
      #
      # The fix narrows the match to require the appended copy to live in a
      # *subclass* of the source's defining class, so unrelated same-named
      # class methods are left alone.

      class Base
        def self.find(x)
          new
        end
        def initialize
          @v = 7
        end
        attr_reader :v
      end

      # A subclass that inherits Base.find: `Article.find` triggers the
      # bare-`new` specialization, appending an `Article`-owned `find` copy.
      class Article < Base
      end

      # An unrelated module with its own same-named `find`. It must NOT be
      # treated as a specialization of Base.find.
      module Store
        def self.find(x)
          x * 2
        end
        def self.lookup(x)
          # Bare sibling call -> resolves to Store.find, emitted as
          # sp_Store_s_find, but the call has no constant receiver, so the
          # DCE's "called_direct" guard does not protect it.
          find(x)
        end
      end

      p Article.find(1).v
      p Store.lookup(21)
    RUBY

    _(result).must_answer "7\n42\n"
  end

  it "dup untyped index write shape" do
    result = ze0(<<~'RUBY')
      # A `dup` of a statically unknown receiver keeps the SOURCE's shape: an int-keyed
      # `[]=` into the copy is no evidence that it is a hash, and guessing one made the
      # method answer `{}` where CRuby answered an Array (#3952).
      def build(node, n)
        copy = node.dup
        copy[0] = n.zero? ? 7 : build(node[0], n - 1)
        copy
      end
      p build([], 0)
      p build([[1]], 1)

      def store(src)
        copy = src.dup
        copy[0] = "v"
        copy
      end
      p store([])
      p store(["a", "b"])
      p store({})
      p store({ 0 => "z", 1 => "y" })
    RUBY

    _(result).must_answer <<~'OUT'
      [7]
      [[7]]
      ["v"]
      ["v", "b"]
      {0 => "v"}
      {0 => "v", 1 => "y"}
    OUT
  end

  it "guarded mixin into an existing class splices at runtime" do
    result = ze0(<<~'RUBY')
      # A mixin into an EXISTING class under a runtime-undecidable guard is a
      # runtime ancestry edit: the directive runs as the send it is, exactly when
      # the guard passes (hammertime's `unless ::Object < Hammertime` idempotence
      # guard, clusterer's `$LINALG == true`). Call sites the module could newly
      # answer or override are de-optimized, so a folded call cannot bypass the
      # splice -- and before the guard runs, the ancestry is untouched.
      module Warmth
        def warmed? = true
      end

      class Thermos
        def temperature = 20
      end

      $want_warmth = true
      p Thermos.ancestors.include?(Warmth)
      if $want_warmth
        class Thermos
          include Warmth
        end
      end
      p Thermos.ancestors.include?(Warmth)
      p Thermos < Warmth
      p Thermos.new.warmed?

      # A prepend that OVERRIDES a method the class already answers -- the
      # de-optimization is what keeps a statically-resolved `capacity` from
      # reaching the class's own body underneath the override.
      module Doubled
        def capacity = super * 2
      end

      class Bottle
        def capacity = 350
      end

      unless Bottle < Doubled
        class Bottle
          prepend Doubled
        end
      end
      p Bottle.new.capacity
      p Bottle.ancestors.first == Doubled

      # A FALSE guard splices nothing.
      module Chill
        def frosty? = true
      end

      $never = false
      if $never
        class Thermos
          include Chill
        end
      end
      p Thermos.ancestors.include?(Chill)
      begin
        Thermos.new.frosty?
      rescue NoMethodError => e
        puts e.class
      end

      # `extend` under the guard: the module's methods arrive as class methods.
      module Stockroom
        def stocked? = true
      end

      class Pantry; end

      $inventory = 1
      if $inventory == 1
        class Pantry
          extend Stockroom
        end
      end
      p Pantry.stocked?

      # The singleton half (`class << self; prepend M`), overriding an existing
      # class method.
      module Announcing
        def open = "announcing: " + super
      end

      class Shop
        def self.open = "9am"
      end

      $noisy = true
      if $noisy
        class Shop
          class << self
            prepend Announcing
          end
        end
      end
      p Shop.open

      # The module's hook fires when (and only when) the guard passes, with the
      # edited class as its argument.
      module Tracked
        def self.included(base)
          $included_into = base.name
        end
      end

      class Ledger; end

      $track = true
      if $track
        class Ledger
          include Tracked
        end
      end
      p $included_into

      # hammertime's exact shape: Object itself, behind its own idempotence probe.
      module Hammer
        def hammer_time? = true
      end

      unless ::Object < Hammer
        class ::Object
          include ::Hammer
        end
      end
      p 42.hammer_time?
      p "anything".hammer_time?
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      true
      700
      true
      false
      NoMethodError
      true
      "announcing: 9am"
      "Ledger"
      true
      true
      still running
    OUT
  end

  it "implicit conversion narrowing" do
    result = ze0(<<~'RUBY')
      # The conversion protocol reached through a NARROWING rather than an argument.
      # A local written from a poly source whose every read is an int context, one of
      # them an array index, is typed Integer (analyze.c: the index-narrowing pass) --
      # and the poly value is unboxed at the write. That unboxing read a user object
      # as 0, so the index silently named the wrong element: the narrowing pass reads
      # an array index as PROOF the value is an integer, where CRuby reads it as the
      # demand that it become one, or raise.
      class Idx
        def to_int
          1
        end
      end

      class Inert
      end

      # 1. converts through #to_int, so the index is 1 (was element 0)
      b = [10, Idx.new][1]
      p [10, 20, 30][b]

      # 2. the same shape through a named array
      arr = [10, Idx.new]
      c = arr[1]
      p [10, 20, 30][c]

      # 3. no conversion method: CRuby's TypeError (was a silent element 0). This
      #    program defines no #to_int anywhere, which is the case a per-program gate
      #    would have had to leave behind.
      begin
        d = [10, Inert.new][1]
        p [10, 20, 30][d]
      rescue TypeError => e
        p [e.class, e.message]
      end

      # An EXPLICIT #to_i is the method, named by the program, not a slot demanding an
      # Integer: an object without it is NoMethodError, and one with it answers.
      class HasToI
        def to_i
          42
        end
      end
      begin
        p [1, Inert.new][1].to_i
      rescue NoMethodError => e
        p [e.class, e.message]
      end
      p [1, HasToI.new][1].to_i

      # The int slots the runtime fills SPECULATIVELY must still accept an object:
      # each of these publishes its value boxed as well, and the unboxed copy is read
      # only by a callee that wants a number. Raising there broke curry, Pathname#join
      # and CSV headers.
      show = ->(label, value) { "#{label}=#{value.class}" }
      p show.call("obj", Inert.new)                  # proc argument slot
      p [Inert.new, Inert.new].reduce { |a, _b| a }.class
      def pick(a, b) = a
      f = method(:pick).to_proc.curry
      p f[Inert.new][2].class                        # curry argument slots
    RUBY

    _(result).must_answer <<~'OUT'
      20
      20
      [TypeError, "no implicit conversion of Inert into Integer"]
      [NoMethodError, "undefined method 'to_i' for an instance of Inert"]
      42
      "obj=Inert"
      Inert
      Inert
    OUT
  end

  it "is a string narrow to primitive" do
    result = ze0(<<~'RUBY')
      # A `String | nil` value narrowed to String via is_a?(String) must reach a
      # string primitive (sp_str_include / start_with? / end_with?) as a real
      # const char*, not an sp_RbVal. (#1512)
      def has_match?(haystacks, needle)
        return false unless needle.is_a?(String)
        haystacks.any? { |h| h.include?(needle) }
      end
      p has_match?(["abc", "def"], "bc")   # true
      p has_match?(["abc", "def"], nil)    # false

      def starts?(s, pre)
        return false unless pre.is_a?(String)
        s.start_with?(pre)
      end
      p starts?("hello", "he")   # true
      p starts?("hello", nil)    # false

      def ends?(s, suf)
        return false unless suf.is_a?(String)
        s.end_with?(suf)
      end
      p ends?("hello", "lo")     # true
      p ends?("hello", nil)      # false
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      true
      false
    OUT
  end

  it "regexp inline comment" do
    result = ze0(<<~'RUBY')
      # (?#comment) groups parse as empty atoms.
      p(/foo(?#comment)bar/.match("foobar") ? "m" : "n")
      p(/foo(?#)bar/ =~ "xfoobar")
    RUBY

    _(result).must_answer <<~'OUT'
      "m"
      1
    OUT
  end

  it "unresolved value typed slot" do
    result = ze0(<<~'RUBY')
      # An unresolved name lowers to a raising token whose C value is boxed. Landing
      # it in a concretely-typed slot needs the coercing emit, or the emitted C
      # assigns an sp_RbVal to the slot's own type and the program does not build at
      # all. Two slots the coercion was not reaching: a `const char *` operand of a
      # string concat (the token arrived wrapped in a paren, so the match missed it)
      # and an object-pointer ivar written through an attr writer.
      class Frame
        attr_reader :n
        def initialize(n); @n = n; end
      end

      class Holder
        attr_accessor :frame
        def initialize; @frame = Frame.new(1); end
      end

      # concat: the unresolved call is the right operand of `+`, written with the
      # parentheses that hid the raising token from the coercion's text match
      def concat_unresolved(a, b)
        "" + (Missing.build(a.to_f, b.to_i))
      end

      begin
        puts concat_unresolved("1.5", "2")
      rescue NameError => e
        p e.class
      end

      def concat_unresolved_bare(a)
        "" + Absent.build(a.to_i)
      end

      begin
        puts concat_unresolved_bare("3")
      rescue NameError => e
        p e.class
      end

      # object-pointer slot: an attr writer taking an unresolved name
      h = Holder.new
      p h.frame.n
      begin
        h.frame = missing_frame
      rescue NameError => e
        p e.class
      end
      p h.frame.n

      # a resolvable value still goes into the same slot unchanged
      h.frame = Frame.new(7)
      p h.frame.n
      p ("" + "ok")
    RUBY

    _(result).must_answer <<~'OUT'
      NameError
      NameError
      1
      NameError
      1
      7
      "ok"
    OUT
  end
end
