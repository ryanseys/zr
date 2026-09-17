# frozen_string_literal: true

require "spec_helper"

describe "Array: formatting and inspection" do
  it "array and hash to s use inspect form only puts flattens" do
    result = ze0(<<~'RUBY')
      p [1, 2].to_s
      print [1, 2]; puts
      puts "i #{[1, 2]}"
      puts [1, 2]
      p({ a: 1 }.to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      "[1, 2]"
      [1, 2]
      i [1, 2]
      1
      2
      "{a: 1}"
    OUT
  end

  it "array at out of bounds" do
    result = ze0(<<~'RUBY')
      # Array#at returns nil for an out-of-range index. For a scalar element
      # array the result is now typed int?/float?, so the out-of-bounds
      # sentinel (sp_IntArray_get already returns SP_INT_NIL; sp_FloatArray_get
      # now returns the float-nil) is recognised by `== nil`, `.nil?`, and
      # inspect. (Array#[] keeps the plain element type -- making it nullable
      # would cascade the sentinel through every hot index.)

      p([1, 2, 3, 4, 5, 6].at(99) == nil)        #=> true
      p [1, 2, 3].at(99)                          #=> nil
      p [1, 2, 3].at(1)                           #=> 2
      p [1, 2, 3].at(-1)                          #=> 3
      p([1, 2, 3].at(99).nil?)                    #=> true
      p([1, 2, 3].at(1).nil?)                     #=> false
      p ["a", "b"].at(5)                          #=> nil

      # In-bounds results still behave as plain scalars in arithmetic.
      puts [10, 20, 30].at(1) + 5                 #=> 25
      puts [1.5, 2.5].at(0) + 1.0                 #=> 2.5

      # Float out-of-range.
      p([1.5, 2.5].at(9) == nil)                  #=> true
      p [1.5, 2.5].at(9)                          #=> nil
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      2
      3
      true
      false
      nil
      25
      2.5
      true
      nil
      done
    OUT
  end

  it "array get oob negative" do
    result = ze0(<<~'RUBY')
      # a[-100] with a 3-element array must not segfault.
      # Before the fix, sp_IntArray_get adjusted the negative index but
      # didn't bounds-check the result, reading far below the buffer.
      # The int? nil-display gap is a known limitation; this test only
      # verifies that OOB access doesn't crash.

      a = [1, 2, 3]
      # these used to segfault — now they return SP_INT_NIL (non-crashing)
      a[-100]
      a[100]
      puts a[-1]
      puts a[2]

      sa = ["a", "b", "c"]
      puts sa[-100].inspect
      puts sa[100].inspect

      fa = [1.0, 2.0, 3.0]
      fa[-100]
      fa[100]
      puts fa[-1]
      puts fa[1]
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      nil
      nil
      3.0
      2.0
    OUT
  end

  it "array product" do
    result = ze0(<<~'RUBY')
      # Array#product on two int_arrays: Cartesian product.
      puts [1, 2].product([3, 4]).inspect
      puts [1, 2, 3].product([10, 20]).inspect
      # Empty other → empty product.
      puts [1, 2].product([]).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [[1, 10], [1, 20], [2, 10], [2, 20], [3, 10], [3, 20]]
      []
    OUT
  end

  it "array unresolved inspect no segv" do
    result = ze0(<<~'RUBY')
      # Issue #1244: an unresolved Array method (originally repeated_permutation,
      # then unimplemented) used to emit a NULL placeholder whose chained
      # .to_a.inspect dereferenced a->len and SEGVed; later it silently printed
      # "[]"; under the NoMethodError gate it raised. repeated_permutation is now
      # implemented, so the chain computes the real value -- keep pinning that the
      # chained call neither crashes nor silently degrades.
      begin
        puts [1, 2].repeated_permutation(2).to_a.inspect
      rescue NoMethodError
        puts "raised NoMethodError"
      end
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 1], [1, 2], [2, 1], [2, 2]]
      after
    OUT
  end

  it "closure captures object array" do
    result = ze0(<<~'RUBY')
      class Item
        attr_accessor :name
      end

      class Callbacks
        def register(&blk)
          @blk = blk
        end

        def run
          @blk.call
        end
      end

      c = Callbacks.new
      items = []
      items << Item.new

      c.register do
        puts items.size
      end

      c.run

      it = Item.new
      it.name = "one"
      items << it

      c.run

      c2 = Callbacks.new
      c2.register do
        puts items.map { |i| i.name.inspect }.join(",")
      end
      c2.run
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      nil,"one"
    OUT
  end

  it "empty array local arg widen" do
    result = ze0(<<~'RUBY')
      # An empty-array local (`x = []`) that is then filled with objects via
      # `<<` and passed as a call argument must widen the callee's parameter
      # (and any ivar it is stored in) to the real element type. Previously
      # the class-body call-type pass typed such a local from its `[]` seed
      # alone (int_array) and ignored the pushes, so the parameter and ivar
      # became int_array. A real object array was then stored and later read
      # back as an IntArray, making `.size` / `.length` return garbage.
      #
      # Mirrors the roundhouse "preload" pattern: a controller groups child
      # records into a fresh array (built inside nested `each` blocks, off
      # another empty-array local) and hands it to a model's `_preload`,
      # which stashes it in an ivar that an accessor reads back.
      class Comment
        def initialize(id, aid); @id = id; @aid = aid; end
        def id; @id; end
        def article_id; @aid; end
        def touch(x); @id = x; end          # self-mutating -> heap class
      end

      class Article
        def initialize(id)
          @id = id
          @cache = []
          @loaded = false
        end
        def id; @id; end
        def _preload(list)
          @cache = list
          @loaded = true
        end
        def comments
          return @cache if @loaded
          fresh = []
          fresh << Comment.new(0, @id)
          fresh
        end
      end

      class Controller
        def index(articles)
          loaded = []                       # empty-array local #1
          loaded << Comment.new(10, 1)
          loaded << Comment.new(20, 1)
          loaded << Comment.new(30, 2)
          articles.each { |a|
            group = []                      # empty-array local #2 (transitive)
            loaded.each { |r| group << r if r.article_id == a.id }
            a._preload(group) }
        end
      end

      articles = []
      articles << Article.new(1)
      articles << Article.new(2)
      Controller.new.index(articles)

      articles.each { |a| puts a.id.to_s + ": " + a.comments.length.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      1: 2
      2: 1
    OUT
  end

  it "empty int array min max" do
    result = ze0(<<~'RUBY')
      # Issue #745. `[].min` / `[].max` used to read uninitialized memory
      # in `sp_IntArray_min` / `_max` (no empty-array guard before reading
      # `a->data[a->start]`). After #832 both return nil (int? sentinel
      # SP_INT_NIL); inspect renders as "nil" per MRI.

      # `[1].first(0)` produces an empty int-typed array, preserving the
      # element type. Both min/max should return safely now.
      a = [1].first(0)
      puts a.min.inspect
      puts a.max.inspect

      # Non-empty: unchanged.
      b = [3, 1, 4, 1, 5, 9, 2, 6]
      puts b.min
      puts b.max
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      1
      9
    OUT
  end

  it "hash flatten rassoc compact" do
    result = ze0(<<~'RUBY')
      # Hash#flatten / #rassoc / #compact on typed hashes. flatten interleaves
      # keys and values into a flat boxed array; rassoc finds the first pair by
      # value (nil on a miss); compact drops nil-valued entries while preserving
      # the hash variant. compact is checked via lookups rather than #inspect,
      # whose symbol-key spacing differs across Ruby versions.
      h = {a: 1, b: 2, c: 3}
      p h.flatten
      p h.rassoc(2)
      p h.rassoc(99)

      s = {"x" => 10, "y" => 20}
      p s.flatten
      p s.rassoc(20)
      p s.rassoc(0)

      ss = {a: "one", b: "two"}
      p ss.flatten
      p ss.rassoc("two")

      # compact on a poly-valued hash drops the nil entry.
      pp = {a: 1, b: nil, c: 3}
      c = pp.compact
      p c.size
      p c[:a]
      p c.key?(:b)
      p c[:c]

      # compact on a hash whose values can't be nil is a straight copy.
      ii = {1 => 10, 2 => 20}
      ci = ii.compact
      p ci.size
      p ci[1]
      p ci[2]
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1, :b, 2, :c, 3]
      [:b, 2]
      nil
      ["x", 10, "y", 20]
      ["y", 20]
      nil
      [:a, "one", :b, "two"]
      [:b, "two"]
      2
      1
      false
      3
      2
      10
      20
    OUT
  end

  it "hash sum array init" do
    result = ze0(<<~'RUBY')
      r001 = ({ a: 1, b: 2 }.sum([]) rescue $!.class); p r001
      p({ a: 1 }.sum("") { |k, _v| k.to_s })
      p([[1], [2]].sum([]))
      p({ a: 1, b: 2 }.sum(10) { |_k, v| v })
      p([1, 2].sum(10))
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1, :b, 2]
      "a"
      [1, 2]
      13
      13
    OUT
  end

  it "int array rotate window" do
    result = ze0(<<~'RUBY')
      # rotate! advances the array's own start offset and copies only the head to the
      # tail, instead of buffering the head, sliding the rest down and copying back.
      # Everything that reads the array has to keep working across that bump: the
      # window is no longer at offset zero.
      a = [1, 2, 3, 4, 5, 6, 7, 8]
      a.rotate!(3)
      p a
      a.rotate!(3)
      p a
      a.rotate!(-2)
      p a
      p a.length
      p a[0]
      p a[-1]
      p a[2, 3]
      p a.first
      p a.last

      # repeated rotations, which is what exhausts the headroom and forces the slide
      b = (0...16).to_a
      12.times { b.rotate!(8) }
      p b
      p b.length

      # the mutators, after the window has moved
      c = [1, 2, 3, 4]
      c.rotate!(1)
      c.push(99)
      p c
      p c.pop
      c.unshift(0)
      p c
      p c.shift
      p c

      d = [10, 20, 30, 40, 50, 60]
      d.rotate!(2)
      d[1, 2] = [77, 88]
      p d
      d[0, 4] = [1]
      p d

      # reads that walk the whole window
      e = [5, 1, 4, 2, 3]
      e.rotate!(3)
      p e.sort
      p e.include?(4)
      p e.index(2)
      p e.sum
      p e.min
      p e.max
      p e.reverse
      p e.map { |x| x * 2 }
      p e.each_slice(2).to_a
      p e.dup
      p e.to_a
      p e.inspect

      # degenerate rotations
      f = [1, 2, 3]
      f.rotate!(0)
      p f
      f.rotate!(3)
      p f
      f.rotate!(300)
      p f
      g = []
      g.rotate!(5)
      p g
      h = [7]
      h.rotate!(1)
      p h

      # a large one keeps the in-place path (no headroom growth)
      big = (0...600).to_a
      big.rotate!(1)
      p big.first(3)
      p big.last(3)
      p big.length
    RUBY

    _(result).must_answer <<~'OUT'
      [4, 5, 6, 7, 8, 1, 2, 3]
      [7, 8, 1, 2, 3, 4, 5, 6]
      [5, 6, 7, 8, 1, 2, 3, 4]
      8
      5
      4
      [7, 8, 1]
      5
      4
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
      16
      [2, 3, 4, 1, 99]
      99
      [0, 2, 3, 4, 1]
      0
      [2, 3, 4, 1]
      [30, 77, 88, 60, 10, 20]
      [1, 10, 20]
      [1, 2, 3, 4, 5]
      true
      0
      15
      1
      5
      [4, 1, 5, 3, 2]
      [4, 6, 10, 2, 8]
      [[2, 3], [5, 1], [4]]
      [2, 3, 5, 1, 4]
      [2, 3, 5, 1, 4]
      "[2, 3, 5, 1, 4]"
      [1, 2, 3]
      [1, 2, 3]
      [1, 2, 3]
      []
      [7]
      [1, 2, 3]
      [598, 599, 0]
      600
    OUT
  end

  it "int array tally" do
    result = ze0(<<~'RUBY')
      # Array#tally on int_array maps each distinct element to its
      # occurrence count. Result is an int_int_hash (new variant
      # alongside sym_int_hash / str_int_hash etc.).
      result = [1, 2, 2, 3, 3, 3].tally
      puts result[1]
      puts result[2]
      puts result[3]
      puts result.length
      puts result.inspect
      puts result.has_key?(2)
      puts result.has_key?(99)
      # missing-key returns 0 in spinel today (vs nil in CRuby) —
      # the broader nullable-hash semantics are tracked in #801.
      puts result[99] == 0
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      3
      {1 => 1, 2 => 2, 3 => 3}
      true
      false
      false
    OUT
  end

  it "local empty array push promotion propagates" do
    result = ze0(<<~'RUBY')
      # #450 cascade 3. A local seeded with `[]` (default int_array)
      # whose subsequent push observations promote it to an obj-ptr_array:
      # the promoted element type needs to propagate back to (a) ivars
      # assigned from the local, and (b) the function's return type when
      # the local is the body's implicit return. Before the fix, both
      # sites pinned at sp_IntArray * based on the local's pre-promotion
      # type that scan_writer_calls / infer_body_return saw.

      class Item
        attr_accessor :id, :name
        def initialize
          @id = 0
          @name = ""
        end
      end

      # (a) ivar = local with push promotion.
      class Holder
        def initialize
          @items = nil
        end

        def build
          results = []
          a = Item.new
          a.id = 1
          a.name = "first"
          results << a
          b = Item.new
          b.id = 2
          b.name = "second"
          results << b
          @items = results
        end

        def first_name
          @items[0].name
        end
      end

      h = Holder.new
      h.build
      puts h.first_name

      # (b) method returns the local-pushed-into.
      def collect_items
        results = []
        i = 0
        while i < 3
          item = Item.new
          item.id = i
          item.name = "item_" + i.to_s
          results << item
          i = i + 1
        end
        results
      end

      items = collect_items
      puts items.length
      puts items[1].name
    RUBY

    _(result).must_answer <<~'OUT'
      first
      3
      item_1
    OUT
  end

  it "param body array hash inference" do
    result = ze0(<<~'RUBY')
      # #544 / #545 follow-up to #542. Body-usage param inference
      # extended to two new shapes:
      #
      # A. Array body inference (#545 conservative path):
      #    `param.push(x)` / `.pop` / `.shift` / `.unshift` / `.concat`
      #    / `.compact` / `.flatten` / `.transpose` widens an
      #    int/nil-defaulted param to poly_array. Critically does NOT
      #    fire on `<<`, `&`, `|`, `*`, `+`, `-` (overlap with
      #    Integer bitwise/arithmetic -- optcarrot's poke(data) shape).
      #    Runs ONCE post-fixpoint so call-site inference can pin
      #    narrower variants (int_array / float_array / etc.) first.
      #
      # B. Hash iteration inference (#545 iteration arm, lifted to
      #    #542's pass):
      #    `param.keys` / `.values` / `.each_pair` / `.merge` /
      #    `.has_key?` / `.fetch` / `.store` / `.delete` /
      #    `.transform_values` / `.transform_keys` / `.to_h` widens
      #    to str_poly_hash when no literal-key signal has already
      #    pinned the more-specific variant. These methods don't exist
      #    on Array / String / Integer, so the classifier is
      #    unambiguous.
      #
      # Updated to MRI-compat after #634 shape B landed. The prior
      # fixture seeded the body widening via `b.contents` on an
      # uninitialized `attr_accessor :contents` whose read returned
      # the int placeholder (cast to NULL at the call site, with
      # runtime NULL-guards no-op'ing the body). That setup contradicts
      # MRI -- `nil.push` raises NoMethodError. The body-widening
      # passes themselves still need test coverage; we keep that by
      # seeding from concrete literal arguments instead.

      # Array body inference - typed caller via an array literal.
      def consume_arr(arr)
        arr.push(42)
        puts "arr.length=" + arr.length.to_s
      end

      consume_arr([])

      # Hash iteration inference -- .each + .merge / .keys + [k].
      def merge_into_seed(other)
        result = {a: 1}
        other.each { |k, v| result[k] = v }
        result.keys.length
      end

      puts merge_into_seed({b: 2, c: 3})

      # Hash widening via .keys (no .each, no [k] literal access) --
      # Sam's SqliteAdapter#insert/update shape (`cols = attrs.keys;
      # cols.map { |k| attrs[k] }` -- the [k] uses a computed key,
      # not a literal, so #542's literal-key arm misses but .keys
      # catches the param's Hash shape).
      def hash_keys_count(h)
        h.keys.length
      end

      puts hash_keys_count({a: 1, b: 2})
    RUBY

    _(result).must_answer <<~'OUT'
      arr.length=1
      3
      2
    OUT
  end

  it "repeated permutation defers argument check" do
    result = ze0(<<~'RUBY')
      p [3, 1, 2].repeated_permutation("l").inspect
      p [3, 1, 2].repeated_permutation(nil).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "#<Enumerator: [3, 1, 2]:repeated_permutation(\"l\")>"
      "#<Enumerator: [3, 1, 2]:repeated_permutation(nil)>"
    OUT
  end
end
