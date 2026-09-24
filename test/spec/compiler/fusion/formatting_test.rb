# frozen_string_literal: true

require "spec_helper"

describe "Fusion: formatting and inspection" do
  it "inlined accessor ignores a later redefinition" do
    result = zr(<<~'RUBY')
      # A call to an accessor from INSIDE the class was inlined to the ivar read,
      # and a later `define_method` of that name did not reach it. The same call
      # from outside saw the redefinition, so one object answered two different
      # values for one method depending on who asked.
      #
      # `inline_accessor` devirtualizes a self-call whose target
      # `accessor_shape` recognizes: `attr_reader :v`, `attr_writer`, and a `Struct`
      # member. The fold now asks `zeo_rt_is_live` first and takes the ordinary
      # dispatch once anything has been defined at run time.
      #
      # The guard is emitted only for a name `may_be_patched_at_runtime` answers
      # for, so a program that redefines nothing emits what it emitted before --
      # which is what keeps `bm_getivar`/`bm_setivar`/`bm_attr_accessor` unchanged.
      # The writer half stands down instead of guarding: both arms would lower the
      # argument from the same node.
      #
      # rspec's summary line is the case that found it. The golden stubs
      # `SummaryNotification#duration` with `define_method(:duration) { 0.0 }`; the
      # stub worked from outside and the formatter's own `format_duration(duration)`
      # still read the member.

      class K
        attr_reader :v
        def initialize = @v = 1
        def inside = v
      end

      k = K.new
      p k.inside
      K.class_eval { define_method(:v) { 99 } }
      p k.inside
      p k.v

      S = Struct.new(:duration)
      class S
        def report = "took #{duration}"
      end
      s = S.new(1.5)
      p s.report
      S.class_eval { define_method(:duration) { 0.0 } }
      p s.report
      p s.duration
    RUBY

    _(result).must_answer <<~'OUT'
      1
      99
      99
      "took 1.5"
      "took 0.0"
      0.0
    OUT
  end

  it "inlined method celled local" do
    result = zr(<<~'RUBY')
      # A method local captured by a block is reached through a heap cell. When the
      # method is INLINED at its call site -- which a `yield` in it forces -- the
      # inlined body kept the cell form while the prologue declared a plain renamed
      # local, and nothing declared the cell (#4088). Two halves: the cell form did
      # not go through the rename map that the plain form did, and the three inline
      # emitters each declared the plain form for a celled local.
      #
      # Same symptom as #4087 from the other side: there the block became a function
      # of its own, here the callee is folded into the caller.

      # ...and once it built, the repro answered 0 where CRuby answers 7: an inlined
      # `each` over a poly receiver walks it AS A CONTAINER, and a user class that
      # defines #each without #to_a -- the ordinary way to write one, forwarding the
      # block -- walked as an empty array. emit_poly_iter_obj_normalize drives such a
      # class's own #each with a collector now, which is what it already did for a
      # class that answers #to_a.

      class Bag
        def initialize(a) = @a = a
        def each(&b) = @a.each(&b)
      end

      class Yielder
        def initialize(a) = @a = a
        def each
          @a.each { |x| yield x }
        end
      end

      class WithToA
        def initialize(a) = @a = a
        def to_a = @a
        def each(&b) = @a.each(&b)
      end

      module M
        def self.sum_of(list)
          n = 0
          list.each { |x| n += yield x }
          n
        end
      end

      def run(list) = M.sum_of(list) { |x| x }
      puts run([1, 2])
      puts run([3, 4, 5])

      # the cell types that are not sp_int
      module F
        def self.join_of(list)
          s = ""
          list.each { |x| s += (yield x).to_s }
          s
        end

        def self.total_of(list)
          f = 0.0
          list.each { |x| f += (yield x) }
          f
        end

        def self.gather(list)
          a = []
          list.each { |x| a.push(yield x) }
          a
        end
      end

      def joined(list) = F.join_of(list) { |x| x }
      def totalled(list) = F.total_of(list) { |x| x * 1.0 }
      def gathered(list) = F.gather(list) { |x| x }
      p joined([1, 2])
      p totalled([1, 2])
      p gathered([1, 2])

      # a closure over the celled local outlives the loop
      module K
        def self.keep(list)
          seen = []
          list.each { |x| seen.push(yield x) }
          seen.length
        end
      end
      def kept(list) = K.keep(list) { |x| x }
      p kept([1, 2, 3])

      p run(Bag.new([3, 4]))
      p run(Yielder.new([5, 6]))
      p run(WithToA.new([7, 8]))
      p kept(Bag.new([1, 2, 3]))

      # not inlined, which has always worked: the same answers
      def walk(list)
        t = 0
        list.each { |x| t += x }
        t
      end
      p walk([1, 2])
      p walk(Bag.new([3, 4]))
      p walk(Yielder.new([5, 6]))

      # a class with no each at all still walks as a container where it is one
      p run([9])
    RUBY

    _(result).must_answer <<~'OUT'
      3
      12
      "12"
      3.0
      [1, 2]
      3
      7
      11
      15
      3
      3
      7
      11
      9
    OUT
  end

  it "instance exec spliced types" do
    result = zr(<<~'RUBY')
      # String, symbol, and mixed-type block params inside a spliced
      # trampoline body.
      #
      # The trampoline-pattern inliner splices the block body at the
      # call site with each block param bound to a per-call-site C
      # local (e.g. `s_ix1` instead of `s`). For `puts <s>` and similar
      # type-aware dispatch inside the spliced body to format the
      # value correctly, the analyzer must resolve `s`'s type to
      # "string" via find_var_type. Previously only the suffixed name
      # (`s_ix1`) was declared in the splice scope, so find_var_type
      # of the original `s` returned "" and puts defaulted to integer
      # format -- string params printed as garbage ints.
      #
      # Now the splice declares each block param under both names
      # (`s_ix1` AND `s`), and the splice scope is bracketed by
      # push_scope / pop_scope so the original-name declaration shadows
      # outer locals only inside the splice. Outer locals with the
      # same name (e.g. an outer `b = Builder.new` and a block param
      # `|b|`) are restored after the splice via pop_scope.
      #
      # Tag has a subclass (TagPlus) so Spinel keeps it heap-allocated
      # (multi-instance classes can't be SRA-promoted to value types).

      class Tag
        def fire(s, y, n, &b)
          instance_exec(s, y, n, &b)
        end
      end

      class TagPlus < Tag
      end

      t = Tag.new
      t.fire("hi", :sym, 7) { |s, y, n| puts s; puts y; puts n }

      # Block-param name shadowing an outer local: `b` (the receiver)
      # vs `|b|` (the second block param). After the splice, `b` must
      # still be the Builder so subsequent dispatch works.
      class Builder
        def initialize; @s = 0; end
        def add(n); @s = @s + n; end
        def total; @s; end
      end

      class BuilderPlus < Builder
      end

      b = Builder.new
      t.fire("hi", :sym, 7) { |s, y, n| b.add(n) }   # `b` here is the outer Builder
      t.fire("hi", :sym, 7) { |s, y, n| b.add(n) }

      # Now actually shadow `b`: the middle block param is named `b`, so inside
      # the splice `b` is the :sym param (prints "sym"), not the Builder. After
      # the splice pop_scope restores `b`, so puts b.total below still sees the
      # Builder. If the restore were missing, `b.total` would mis-resolve.
      t.fire("hi", :sym, 7) { |s, b, n| puts b }
      puts b.total                     # 14

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      sym
      7
      sym
      14
      done
    OUT
  end

  it "matchdata methods work on a dynamically typed receiver" do
    result = zr(<<~'RUBY')
      # `$~` can be nil (whenever the last match failed), so it never infers
      # as `TyKind::MatchData` and can't take codegen's static MatchData fast
      # path -- it dispatches dynamically, which needs a real runtime table.
      # `$~[0]` raised NoMethodError while `re.match(s)[0]` worked.

      "hello" =~ /e(l+)(o)/
      m = $~
      p m[0]
      p m[1]
      p m.captures
      p m.pre_match
      p m.post_match
      p m.to_a
      p m.string
      p m.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "ello"
      "ll"
      ["ll", "o"]
      "h"
      ""
      ["ello", "ll", "o"]
      "hello"
      "ello"
    OUT
  end

  it "typed array empty returns nil" do
    result = zr(<<~'RUBY')
      # Issue #832: int_array pop/shift/min/max on empty return nil
      # (int? sentinel SP_INT_NIL) per MRI. Non-empty returns the value.
      # float_array is deferred (needs float? sentinel design).
      a = [1, 2]
      2.times { a.pop }
      puts "empty int pop: " + a.pop.inspect

      b = [1, 2]
      2.times { b.shift }
      puts "empty int shift: " + b.shift.inspect

      puts "empty int min: " + [].min.inspect
      puts "empty int max: " + [].max.inspect

      # Non-empty still works.
      puts [1, 2, 3].pop
      puts [1, 2, 3].shift
      puts [3, 1, 2].min
      puts [3, 1, 2].max
    RUBY

    _(result).must_answer <<~'OUT'
      empty int pop: nil
      empty int shift: nil
      empty int min: nil
      empty int max: nil
      3
      1
      1
      3
    OUT
  end

  it "typed hash caller no body widen" do
    result = zr(<<~'RUBY')
      # #556 (Ori Pekelman). Smoke test for the move of
      # infer_hash_param_from_body out of the iterative inference
      # loop. The full bug only triggers in tep's framework
      # surface (where iter 0 leaves the param's ivar slot
      # untyped, the body-usage widening fires, then
      # unify_call_types pulls it to poly against the actual
      # typed caller). Reductions to a standalone script don't
      # reproduce -- iter 0 already pins the ivar via the
      # initial-literal observation. Documenting both here:
      # this fixture exercises the "typed caller + body[]
      # usage" shape end-to-end so a future regression that
      # poisons the typed-caller path would be caught even if
      # the iter-0 timing is more permissive than tep's.
      #
      # Verified against tep@9ca09fd: pre-fix
      # `sp_tep_mustache_m_ivars(sp_StrStrHash *, sp_RbVal)`,
      # post-fix `sp_tep_mustache_m_ivars(sp_StrStrHash *, sp_StrStrHash *)`,
      # caller drops the sp_box_obj wrap.

      class Request
        attr_accessor :ivars
        def initialize
          @ivars = {"k" => "v"}
          @ivars.delete("k")
        end
      end

      def lookup_typed(h, key)
        h[key].to_s
      end

      def forward_to_typed(locals, ivars)
        out = ""
        out += lookup_typed(ivars, "name")
        out += "/"
        out += lookup_typed(ivars, "count")
        out += "/"
        out += ivars["raw"].to_s
        out
      end

      req = Request.new
      req.ivars["name"] = "alice"
      req.ivars["count"] = "5"
      req.ivars["raw"] = "<i>I</i>"
      puts forward_to_typed({"unused" => "x"}, req.ivars)
    RUBY

    _(result).must_answer "alice/5/<i>I</i>\n"
  end

  it "typed hash inspect and each value" do
    result = zr(<<~'RUBY')
      # Issue #851: typed-hash inspect for sym_int_hash, plus
      # Hash#each_value across common typed hashes.
      h = {a: 1, b: 2}
      puts h.inspect
      h.each_value { |v| puts v * 10 }

      # str_int_hash.
      counts = {"x" => 5, "y" => 7}
      counts.each_value { |v| puts v + 1 }

      # inspect on str_int_hash.
      puts counts.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      10
      20
      6
      8
      {"x" => 5, "y" => 7}
    OUT
  end

  it "typed hash missing returns nil" do
    result = zr(<<~'RUBY')
      # Issue #833 (#801 partial): *StrHash missing-key bracket access
      # returns nil per MRI, not the type's zero value.
      # *IntHash variants still return 0 (their analyze-side LV slot
      # can't be widened to int? without cascading through declare_var --
      # deferred to a follow-up phase).

      # SymStrHash
      puts({a: "hi"}[:missing].inspect)

      # StrStrHash
      puts({"a" => "hi"}["missing"].inspect)

      # IntStrHash
      puts({1 => "hi"}[99].inspect)

      # Existing key still works
      puts({a: "hello"}[:a])
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      hello
    OUT
  end
end
