# frozen_string_literal: true

require "spec_helper"

describe "Fusion: dispatch" do
  it "dispatch inline cache invalidation" do
    result = ze0(<<~'RUBY')
      # A dynamic call site remembers what the receiver's class resolved to, so
      # anything that can change that answer has to be seen. Every case below WARMS
      # the site first -- a cache that was never filled would pass these by accident.

      class Greeter
        def hello = "plain"
      end

      def call_hello(g) = g.hello

      warm = Greeter.new
      100.times { call_hello(warm) }
      p call_hello(warm)

      # A runtime `define_method` replaces it, on the warmed receiver and a fresh one.
      Greeter.define_method(:hello) { "redefined" }
      p call_hello(warm)
      p call_hello(Greeter.new)

      # A per-object singleton is closer than the class.
      solo = Greeter.new
      100.times { call_hello(solo) }
      def solo.hello = "singleton"
      p call_hello(solo)
      p call_hello(Greeter.new)

      # `extend` splices a module ahead of nothing, but `prepend` beats the class.
      module Loud
        def hello = "LOUD"
      end
      ext = Greeter.new
      100.times { call_hello(ext) }
      ext.extend(Loud)
      p call_hello(ext)

      class Prepended
        def hello = "base"
      end
      pre = Prepended.new
      100.times { call_hello(pre) }
      Prepended.prepend(Loud)
      p call_hello(pre)
      p call_hello(Prepended.new)

      # A second class at the same site: the cache holds one, the other must still
      # resolve correctly.
      class Other
        def hello = "other"
      end
      mixed = [Greeter.new, Other.new, Greeter.new, Other.new]
      p mixed.map { |m| call_hello(m) }

      # The same site over builtin VALUE receivers, which resolve by a different
      # route but share the cache.
      def stringify(v) = v.to_s
      100.times { stringify(1) }
      p [stringify(1), stringify(2.5), stringify(:sym), stringify([1, 2]), stringify(nil)]

      # `undef` retracts a name after the site is warm.
      class Fragile
        def hello = "here"
      end
      f = Fragile.new
      100.times { call_hello(f) }
      class Fragile
        undef_method :hello
      end
      begin
        call_hello(f)
      rescue NoMethodError
        p :undefined
      end

      # An alias added at runtime resolves through the same site.
      class Greeter
        def real = "real"
      end
      g2 = Greeter.new
      100.times { call_hello(g2) }
      Greeter.alias_method :hello, :real
      p call_hello(g2)
    RUBY

    _(result).must_answer <<~'OUT'
      "plain"
      "redefined"
      "redefined"
      "singleton"
      "redefined"
      "LOUD"
      "LOUD"
      "LOUD"
      ["redefined", "other", "redefined", "other"]
      ["1", "2.5", "sym", "[1, 2]", ""]
      :undefined
      "real"
    OUT
  end

  it "implicit alloc site cache helper specialization" do
    result = ze0(<<~'RUBY')
      RowA = Struct.new(:id, :name)
      RowB = Struct.new(:id, :label)

      class RecordCache
        def initialize
          @records = []
          @loaded = false
        end

        def loaded?
          @loaded
        end

        def read_all
          @records
        end

        def replace(records)
          @records = records
          @loaded = true
          @records
        end

        def mark_unloaded
          @loaded = false
        end

        def find_by_id(id)
          index = 0
          while index < @records.length
            record = @records[index]
            return record if record.id == id

            index = index + 1
          end
          nil
        end

        def relationship_exists(id)
          !find_by_id(id).nil?
        end
      end

      class AStore
        def initialize
          @cache = RecordCache.new
        end

        def load_records
          records = [RowA.new(0, "")]
          records.delete_at(0)
          records << RowA.new(1, "alpha")
          records << RowA.new(2, "next")
          records
        end

        def read_all
          return @cache.read_all if @cache.loaded?

          @cache.replace(load_records)
        end

        def find_by_id(id)
          read_all
          @cache.find_by_id(id)
        end

        def relationship_exists(id)
          read_all
          @cache.relationship_exists(id)
        end
      end

      class BStore
        def initialize
          @cache = RecordCache.new
        end

        def load_records
          records = [RowB.new(0, "")]
          records.delete_at(0)
          records << RowB.new(1, "first")
          records << RowB.new(2, "beta")
          records
        end

        def read_all
          return @cache.read_all if @cache.loaded?

          @cache.replace(load_records)
        end

        def find_by_id(id)
          read_all
          @cache.find_by_id(id)
        end

        def relationship_exists(id)
          read_all
          @cache.relationship_exists(id)
        end
      end

      store_a = AStore.new
      store_b = BStore.new

      puts store_a.read_all[0].name
      puts store_b.read_all[1].label
      puts store_a.find_by_id(2).name
      puts store_b.find_by_id(1).label
      puts store_a.relationship_exists(2)
      puts store_b.relationship_exists(3)
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
      next
      first
      true
      false
    OUT
  end

  it "inlined accessor takes the ordinary dispatch" do
    result = ze0(<<~'RUBY')
      # The widened sweep behind `an_inlined_accessor_ignores_a_later_redefinition`:
      # every route by which a run-time definition can displace an accessor the
      # compiler folded to an ivar read. Each pair below reads the same accessor
      # from INSIDE the class and from outside, so a fold that outlived its
      # redefinition shows as two answers for one method.
      #
      # The routes: a reader and a writer replaced by `define_method`; the same
      # name replaced on a SUBCLASS, where the superclass keeps its own answer; a
      # `remove_method` followed by an `include` that supplies the name from a
      # module; and an `alias_method` over the accessor.

      class A
        attr_accessor :v
        def initialize = @v = 1
        def read = v
        def write(x) = (self.v = x)
      end
      a = A.new
      p a.read
      A.class_eval { define_method(:v) { 99 } }
      p a.read
      A.class_eval { define_method(:v=) { |x| @v = x * 10 } }
      p a.write(5)
      p a.instance_variable_get(:@v)

      class B
        attr_reader :w
        def initialize = @w = 2
        def read = w
      end
      class C < B
        def read2 = w
      end
      c = C.new
      p c.read
      p c.read2
      C.class_eval { define_method(:w) { :sub } }
      p c.read
      p c.read2
      p B.new.read

      module M
        def z = :module_z
      end
      class D
        attr_reader :z
        def initialize = @z = 3
        def read = z
      end
      d = D.new
      p d.read
      D.class_eval { remove_method :z }
      D.include(M)
      p d.read

      class E
        attr_reader :q
        def initialize = @q = 4
        def read = q
      end
      e = E.new
      p e.read
      E.class_eval { alias_method :q, :object_id }
      p e.read.is_a?(Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      99
      5
      50
      2
      2
      :sub
      :sub
      2
      3
      :module_z
      4
      true
    OUT
  end

  it "is a against a poly typed method parameter" do
    result = ze0(<<~'RUBY')
      # A method PARAMETER is always `TyKind::Poly` (zeo never infers a
      # param's type from its call sites) -- this exercises the runtime
      # `zeo_rt::is_a` fallback (via the new universal `RubyValue::class_id`)
      # rather than the static ancestors-constant-fold path.

      class Checker
        def check(v)
          v.is_a?(Integer)
        end
      end
      c = Checker.new
      puts c.check(5)
      puts c.check("hi")
      puts c.check([1, 2])
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
    OUT
  end

  it "nil guard narrows int or nil" do
    result = ze0(<<~'RUBY')
      # #550. Mirror of d3ee2b2 (#493) for the nil-vs-not case on
      # int|nil locals. After `return -1 if h.nil?`, the rest of the
      # scope sees `h` as non-nil; for a local whose writer was a
      # known int-or-nil source (String#index, rindex, find_index),
      # the non-nil arm is mrb_int. The function's return type
      # narrows accordingly, and the trailing `h + 1` lowers via
      # integer arithmetic on the unboxed payload instead of routing
      # through sp_poly_add.
      #
      # Cascade: the 0210389 String#index return-type change widened
      # all downstream consumers to sp_RbVal. Before this fix, every
      # `h = s.index(needle); ...; h + 1` had to be hand-wrapped in a
      # pure-int helper (Tep.str_find) to avoid the poly widening.
      # With the nil-guard narrow, the idiomatic form works directly.
      #
      # Discriminator: `lookup` consumes find_or_neg's return as an
      # int-typed array index. Pre-fix the function returns sp_RbVal
      # and arr[poly] does not compile cleanly (spinel emits no
      # implicit poly->int unbox at the index site). Post-fix the
      # return is mrb_int and arr[i] is direct integer indexing.

      ARR = [10, 20, 30, 40, 50, 60]

      def find_or_neg(s, needle)
        h = s.index(needle)
        return -1 if h.nil?
        h + 1
      end

      def lookup(s, needle)
        i = find_or_neg(s, needle)
        return 0 if i < 0
        ARR[i]
      end

      puts find_or_neg("abcdef", "b")
      puts find_or_neg("abcdef", "z")
      puts lookup("abcdef", "b")
      puts lookup("abcdef", "a")
      puts lookup("abcdef", "z")
    RUBY

    _(result).must_answer <<~'OUT'
      2
      -1
      30
      20
      0
    OUT
  end

  it "nil guard param narrow" do
    result = ze0(<<~'RUBY')
      def up(s)
        return "nil" if s.nil?
        s.upcase
      end
      puts up("hi")
      puts up(nil)

      def fmt(t)
        return "null" if t.nil?
        t.strftime("%Y")
      end
      puts fmt(Time.at(0).utc)
      puts fmt(nil)

      def inc(x)
        return -1 if x.nil?
        x + 1
      end
      p inc(41)
      p inc(nil)

      def two(a, b)
        return "a-nil" if a.nil?
        return "b-nil" if b.nil?
        a + b.upcase
      end
      puts two(nil, "x")
      puts two("x", nil)
      puts two("x-", "y")

      def blocky(s)
        return 0 if s.nil?
        n = 0
        2.times { n += s.length }
        n
      end
      p blocky("abc")
      p blocky(nil)

      def reassigned(s)
        return "n" if s.nil?
        s = nil if s == "z"
        s.to_s
      end
      puts reassigned("a")
      puts reassigned("z")
      puts reassigned(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      HI
      nil
      1970
      null
      42
      -1
      a-nil
      b-nil
      x-Y
      6
      0
      a

      n
    OUT
  end

  it "poly arg to typed method param" do
    result = ze0(<<~'RUBY')
      # Sibling to #438. A poly local guarded by `is_a?(String)` passed
      # as a positional arg to a top-level typed-param method: the call
      # site unboxes via `(lv_v).v.s` so the const-char* parameter
      # type-checks. Same shape for Integer / Float narrows.

      def helper_s(s)
        s.length
      end

      def encode(v)
        return helper_s(v) if v.is_a?(String)
        -1
      end

      puts encode("hello")
      puts encode(42)

      def helper_i(i)
        i * 2
      end

      def double_if_int(v)
        return helper_i(v) if v.is_a?(Integer)
        0
      end

      puts double_if_int(7)
      puts double_if_int("nope")
    RUBY

    _(result).must_answer <<~'OUT'
      5
      -1
      14
      0
    OUT
  end

  it "poly dispatch narrow return type" do
    result = ze0(<<~'RUBY')
      # #549. Followup to #531. The cls_id-switch dispatch's RESULT
      # temp widened to sp_RbVal even when every reachable arm
      # returned the same scalar. The reachable set is computed by
      # the same arm-suppression logic the codegen emit loop applies:
      # arms whose param types are incompatible with the dispatch
      # site's arg types are pruned, and only arms in the observed
      # obj-class set survive. With both filters applied, the return
      # types of surviving arms are unified; if they agree on a
      # scalar (e.g. all `const char *`), the result temp uses that
      # scalar instead of sp_RbVal, and the boxed arm rhs (`_t =
      # sp_box_str(...)`) collapses to a direct assignment.
      #
      # Shape: M::Server#run takes `port:int` and returns int; the
      # Worker family takes `item:string` and returns string. The
      # dispatch site `@w.run(item)` supplies a string, so M::Server's
      # arm is param-incompat and pruned. The Worker arms return
      # string, so the dispatch produces `const char *` and the
      # scalar-only consumer `s + "."` below compiles correctly.
      # Pre-fix, the dispatch result was sp_RbVal and `s + "."`
      # routed through sp_poly_concat -- still ran but the
      # concatenated form leaked the boxing.
      #
      # Discriminator: `Holder#use` returns `s + "."`. If the
      # dispatch result is sp_RbVal, `s + "."` lowers through
      # sp_poly_concat, which formats the box and produces e.g.
      # `x!.` only because sp_box_str / sp_poly_concat happen to
      # preserve the underlying string. The shape is correct but
      # the path is wrong; once the dispatch is narrowed to
      # const char *, `s + "."` lowers to sp_str_concat which is
      # what we want.

      module M
        class WorkerA
          def run(item); item + "!"; end
        end
        class WorkerB
          def run(item); item + "?"; end
        end
        class Holder
          def initialize(w); @w = w; end
          def use(item)
            s = @w.run(item)
            s + "."
          end
        end
        class Server
          def run(port); port + 1; end
        end
      end

      puts M::Holder.new(M::WorkerA.new).use("x")
      puts M::Holder.new(M::WorkerB.new).use("y")
      puts M::Server.new.run(80)
    RUBY

    _(result).must_answer <<~'OUT'
      x!.
      y?.
      81
    OUT
  end

  it "poly local is a string narrow in non tail if" do
    result = ze0(<<~'RUBY')
      # Sibling case to poly_local_is_a_string_narrow_in_tail_if (#612):
      # a poly-typed local narrowed via `if content.is_a?(String) ... end`
      # when the if is NOT in tail position. Before this fix
      # compile_if_stmt didn't push the is_a? narrow, so a typed-arg
      # callee inside the body (sp_re_escape's `const char *`) saw the
      # raw sp_RbVal and tripped a C compile. The fix mirrors
      # compile_cond_return's narrow push and also switches
      # compile_stmt's LV-write to use the slot's declared type so a
      # rewrite of the narrowed var inside the body picks the slot arm,
      # not the narrow's pseudo-type. Issue #615.

      class Resp
        attr_reader :body
        def initialize(b); @body = b; end
      end

      class Tester
        attr_accessor :response

        def assert_select(selector, content_or_opts = nil, &block)
          body = response.body
          if content_or_opts.is_a?(Hash)
            content = nil
          else
            content = content_or_opts
          end
          if content.is_a?(String)
            pattern = Regexp.new("<#{selector}>#{Regexp.escape(content)}<")
            raise "no match" unless pattern.match?(body)
          end
          yield if block
        end
      end

      t = Tester.new
      t.response = Resp.new("<h1>Title<")
      t.assert_select("h1", "Title")
      t.assert_select("div", { count: 1 })
      puts "OK"
    RUBY

    _(result).must_answer "OK\n"
  end

  it "poly local is a string narrow in tail if" do
    result = ze0(<<~'RUBY')
      # Tail-position `if x.is_a?(C) ... end` now pushes a narrow for `x`
      # inside the body, so a typed callee that consumes `x` unboxes via
      # the matching union field (`.v.s` for string, `.v.i` for int, etc.)
      # instead of emitting the raw sp_RbVal. Issue #612: pre-fix
      # Regexp.escape on a poly param narrowed via `is_a?(String)` emitted
      # `sp_re_escape(lv_x)` against the un-narrowed slot and the C
      # compile failed.

      def matcher(content_or_opts)
        if content_or_opts.is_a?(Hash)
          content = nil
        else
          content = content_or_opts
        end
        if content.is_a?(String)
          pattern = Regexp.new("<h1>#{Regexp.escape(content)}<")
          body = "<h1>Title<"
          puts pattern.match?(body) ? "match" : "no match"
        end
      end

      matcher("Title")
      matcher({ "opt" => 1 })   # content is nil, skips the inner if entirely
    RUBY

    _(result).must_answer "match\n"
  end

  it "poly local is a string narrow in y1 inline" do
    result = ze0(<<~'RUBY')
      # Sibling to #615 (poly_local_is_a_string_narrow_in_non_tail_if):
      # the is_a? narrow + LV-read unbox must also fire inside the y1
      # inlined specialization that block-passing creates. The
      # non-inlined `sp_Base_check` body already unboxed correctly after
      # #615 / #817149f; the inlined y1 copy emitted the raw poly local
      # where `const char *` is expected. Issue #624.

      class Base
        def check(content = nil, &block)
          if content.is_a?(String)
            pattern = Regexp.new(Regexp.escape(content))
            raise "no match" unless pattern.match?(content)
          end
          yield if block
        end
      end

      class Sub < Base
        def run
          check("hello")
          check(123)        # makes content's static type poly
          check { nil }     # block-passing call triggers y1 inlining
        end
      end

      Sub.new.run
      puts "OK"
    RUBY

    _(result).must_answer "OK\n"
  end

  it "poly recv dispatch narrow module" do
    result = ze0(<<~'RUBY')
      # #531. Sibling to #513. The poly-recv narrowing in af55659
      # walks the global AST for `<Class>.new(...)` call sites to
      # recover concrete classes seen at a poly ivar slot. The walker
      # matched only `ConstantReadNode` receivers, so module-scoped
      # classes (`module M; class Holder; end; end` with call sites
      # `M::Holder.new(...)`) fell through to the all-classes fallback.
      # Server got pulled into M::Holder.use's cls_id-dispatch table
      # even though no M::Server is ever assigned to @w, and
      # M::Server#run's port widened to sp_RbVal.
      #
      # Fix: also match `ConstantPathNode` receivers via
      # `const_ref_flat_name`, which produces the same flattened
      # `Mod_Class` form that `@cls_names` stores.

      module M
        class WorkerA
          def run(item); item + "!"; end
        end
        class WorkerB
          def run(item); item + "?"; end
        end
        class Holder
          def initialize(w); @w = w; end
          def use(item); @w.run(item); end
        end
        # Same shape as #513's top-level Server: same method name (`run`),
        # different param type (int instead of string). After the fix,
        # M::Server#run keeps `mrb_int lv_port` and M::Server is dropped
        # from the M::Holder.use dispatch table.
        class Server
          def run(port); port + 1; end
        end
      end

      puts M::Holder.new(M::WorkerA.new).use("x")
      puts M::Holder.new(M::WorkerB.new).use("y")
      puts M::Server.new.run(80)
    RUBY

    _(result).must_answer <<~'OUT'
      x!
      y?
      81
    OUT
  end

  it "poly slot typed array read" do
    result = ze0(<<~'RUBY')
      # A typed array stored into a poly slot -- a Hash value, here -- has a
      # different layout from the poly array the index read assumed, so every
      # element came back nil.
      h = {}
      h["a"] = [7, 8, 9]
      row = h["a"]
      p row[0]
      p row[2]
      p row[-1]
      p row[9]

      h["b"] = ["x", "y"]
      p h["b"][1]
      h["c"] = [1.5, 2.5]
      p h["c"][0]
      h["d"] = [1, "s"]
      p h["d"][1]

      # a poly array in the same slot keeps working
      h["e"] = [1, :two, "three"]
      e = h["e"]
      p e[0]
      p e[1]
      p e[-1]

      # and so does a nested read without the intermediate local
      p h["a"][1]
    RUBY

    _(result).must_answer <<~'OUT'
      7
      9
      9
      nil
      "y"
      1.5
      "s"
      1
      :two
      "three"
      8
    OUT
  end
end
