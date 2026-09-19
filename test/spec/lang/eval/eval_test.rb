# frozen_string_literal: true

require "spec_helper"

describe "Eval programs" do
  it "bare private in a singleton body runs under eval" do
    result = ze0(<<~'PROGRAM')
      # A `class << self` body holding a BARE `private` compiles inside a run-time
      # `eval`.
      #
      # A class body written in a snippet runs as one more `class_eval` of its own
      # SOURCE TEXT, sliced from its statements' spans, so a statement with no span
      # cannot be re-emitted at all. A bare visibility directive in a singleton body
      # survives lowering as a marker plus a synthesized `public` reset at body end,
      # and that reset used to be stamped `Span::SYNTH` -- which refused the whole
      # compile. rubygems' `platform.rb` is the corpus case: its `class << self`
      # holds a bare `private` two thirds of the way down.

      src = <<~RUBY
        class Widget
          class << self
            def build
              "built"
            end

            private

            def helper
              "helper"
            end
          end
        end
      RUBY

      eval src

      p Widget.build
      p Widget.singleton_class.private_method_defined?(:helper)
      begin
        Widget.helper
      rescue NoMethodError => e
        p e.class
      end
      # The cursor dies with the body, exactly as CRuby's dies with the cref: a
      # `def self.x` written after it is public again.
      class Widget
        def self.after
          "after"
        end
      end
      p Widget.after
    PROGRAM

    _(result).must_answer <<~'OUT'
      "built"
      true
      NoMethodError
      "after"
    OUT
  end

  it "binding captures the frame it was taken in" do
    result = ze0(<<~'RUBY')
      # `Kernel#binding` cannot be a builtin row: it would have to see its CALLER's
      # locals. The emitter builds it instead, from the names a `binding` in the
      # scope promotes to cells -- the only storage a binding can share.

      a = 1
      b = "two"
      bd = binding
      p bd.local_variables.sort
      p bd.local_variable_get(:a)
      bd.local_variable_set(:a, 99)
      p a
      p bd.eval("a.to_s + b")
      p bd.receiver
      p bd.local_variable_defined?(:b)
      p bd.local_variable_defined?(:nope)

      # A method's binding reports its params and its own locals, and nothing of
      # the caller's.
      def m(x, y = 2)
        z = x + y
        binding
      end
      mb = m(5)
      p mb.local_variables.sort
      p mb.eval("x + y + z")

      # A block's binding reports the block's own names FIRST, then the enclosing
      # scope's -- CRuby's innermost-first order -- and a name the block binds
      # shadows the outer one.
      outer_only = :outer
      shadowed = :from_main
      seen = nil
      [10].each do |item|
        shadowed = :from_block
        inner = item * 2
        seen = binding.local_variables
      end
      p seen.sort
      p shadowed

      # A destructuring block parameter binds the names it destructures, and zeo's
      # own internal slot for the un-destructured value is not one of them.
      names = nil
      [[[1, 2], 9]].each do |(x, y), i|
        names = binding.local_variables.sort
      end
      p names

      # `Proc#binding` is the scope the proc was BUILT in -- its own locals do not
      # exist until it runs.
      def make
        hidden = :in_make
        proc { hidden }
      end
      pr = make
      p pr.binding.local_variables.sort
      p pr.binding.local_variable_get(:hidden)
      p pr.binding.eval("hidden")

      # A lambda too.
      lam_local = :outside
      lam = lambda { |q| q }
      p lam.binding.local_variable_defined?(:lam_local)

      # Assignment through a binding is visible to the frame it came from.
      def round_trip
        v = 1
        bd = binding
        bd.local_variable_set(:v, 2)
        v
      end
      p round_trip
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :b, :bd, :lam, :lam_local, :mb, :names, :outer_only, :pr, :seen, :shadowed]
      1
      99
      "99two"
      main
      true
      false
      [:x, :y, :z]
      14
      [:a, :b, :bd, :inner, :item, :lam, :lam_local, :mb, :names, :outer_only, :pr, :seen, :shadowed]
      :from_block
      [:a, :b, :bd, :i, :lam, :lam_local, :mb, :names, :outer_only, :pr, :seen, :shadowed, :x, :y]
      [:hidden]
      :in_make
      :in_make
      true
      2
    OUT
  end

  it "binding lvget" do
    result = ze0(<<~'RUBY')
      # binding.local_variable_get(:name) with a literal symbol naming an in-scope
      # local is the only way to read a reserved-word parameter. It has a static
      # answer (the value of that local), so it lowers to a direct read.

      # reading a reserved-word keyword parameter (`then`)
      def read_reserved(then:)
        binding.local_variable_get(:then).inspect
      end
      puts read_reserved(then: :tick)

      # an ordinary parameter name
      def read_named(name:)
        binding.local_variable_get(:name)
      end
      p read_named(name: "hello")

      # another reserved word (`if`) as a parameter
      def read_if(if:)
        binding.local_variable_get(:if).to_s
      end
      puts read_if(if: 99)

      # a plain local (not a parameter)
      def read_local
        count = 41 + 1
        binding.local_variable_get(:count)
      end
      p read_local

      # top-level local
      x = [1, 2, 3]
      p binding.local_variable_get(:x)
    RUBY

    _(result).must_answer <<~'OUT'
      :tick
      "hello"
      99
      42
      [1, 2, 3]
    OUT
  end

  it "binding scopes" do
    result = ze0(<<~'PROGRAM')
      # Where a `binding` is taken decides what it holds. A method's carries its
      # parameters (every kind) ahead of its locals; a class body's `self` and cref
      # are the class, which is what makes the `eval <<-RUBY, binding` idiom every
      # gemspec attribute writer is built from work; a block's names come first and
      # the enclosing scope's after, innermost outward.

      puts "-- a method frame --"
      def m(a, b = 2, *rest, k: 3, **kw, &blk)
        c = a + b
        bd = binding
        p bd.local_variables
        p [bd.local_variable_get(:a), bd.local_variable_get(:b)]
        p [bd.local_variable_get(:rest), bd.local_variable_get(:k)]
        p [bd.local_variable_get(:kw), bd.local_variable_get(:blk)]
        bd
      end
      mb = m(1)
      p mb.local_variable_get(:c)
      p mb.eval("a + c")

      puts "-- an instance method: self, ivars, lexical constants --"
      class Holder
        LIMIT = 5
        def initialize
          @v = 10
        end

        def peek
          y = 1
          binding
        end
      end
      hb = Holder.new.peek
      p hb.receiver.class
      p hb.local_variables
      p [hb.eval("@v"), hb.eval("y"), hb.eval("LIMIT")]

      puts "-- a class body, and a def written through its binding --"
      class Built
        cb = binding
        p cb.receiver
        p cb.local_variables

        eval <<-RUBY, binding, __FILE__, __LINE__ + 1
          def greet
            "hi from eval"
          end
          private :greet
        RUBY

        WIDTH = 3
        p cb.eval("WIDTH")
      end
      p Built.new.send(:greet)
      p Built.private_instance_methods(false)

      puts "-- a block: its own names first, then the enclosing scope's --"
      def outer
        o = 1
        [1].each do |i|
          inner = i + o
          return binding
        end
      end
      ob = outer
      p ob.local_variables
      p [ob.local_variable_get(:i), ob.local_variable_get(:inner), ob.local_variable_get(:o)]
      ob.local_variable_set(:o, 100)
      p ob.eval("inner + o")

      puts "-- nested blocks compose --"
      def deep
        q = 1
        [1].map { |i| [2].map { |j| binding } }
      end
      db = deep[0][0]
      p db.local_variables.sort
      p [db.local_variable_get(:q), db.local_variable_get(:i), db.local_variable_get(:j)]
    PROGRAM

    _(result).must_answer <<~'OUT'
      -- a method frame --
      [:a, :b, :rest, :k, :kw, :blk, :c, :bd]
      [1, 2]
      [[], 3]
      [{}, nil]
      3
      4
      -- an instance method: self, ivars, lexical constants --
      Holder
      [:y]
      [10, 1, 5]
      -- a class body, and a def written through its binding --
      Built
      [:cb]
      3
      "hi from eval"
      [:greet]
      -- a block: its own names first, then the enclosing scope's --
      [:i, :inner, :o]
      [1, 2, 1]
      102
      -- nested blocks compose --
      [:i, :j, :q]
      [1, 1, 2]
    OUT
  end

  it "binding toplevel" do
    result = ze0(<<~'RUBY')
      # `TOPLEVEL_BINDING` IS the main script's frame, so it reads and writes the
      # same locals the file does -- and `Kernel#eval`'s own binding/filename/lineno
      # arguments run their source in whichever scope they name.
      zz = 12

      puts "-- the constant is the top-level frame --"
      p TOPLEVEL_BINDING.class
      p TOPLEVEL_BINDING.source_location
      p TOPLEVEL_BINDING.local_variables
      p TOPLEVEL_BINDING.local_variable_get(:zz)

      puts "-- Kernel#eval's binding argument --"
      p eval("zz + 1", binding)
      p eval("zz + 2", TOPLEVEL_BINDING)
      p eval("zz + 3", nil)
      begin
        eval("1", 5)
      rescue TypeError => e
        p [e.class, e.message]
      end

      puts "-- filename and lineno --"
      p eval("__FILE__", binding, "fake.rb", 10)
      p eval("__LINE__", binding, "fake.rb", 10)
      p eval("__LINE__\n__LINE__", binding, "fake.rb", 10)

      puts "-- dup shares the frame, not the additions --"
      d = TOPLEVEL_BINDING.dup
      d.local_variable_set(:only_on_the_copy, 1)
      p TOPLEVEL_BINDING.local_variable_defined?(:only_on_the_copy)
      p d.local_variable_defined?(:only_on_the_copy)
      d.local_variable_set(:zz, 99)
      p zz
      p TOPLEVEL_BINDING.dup.local_variable_defined?(:only_on_the_copy)
    RUBY

    _(result).must_answer <<~'OUT'
      -- the constant is the top-level frame --
      Binding
      ["<main>", 0]
      [:zz, :e, :d]
      12
      -- Kernel#eval's binding argument --
      13
      14
      15
      [TypeError, "wrong argument type Integer (expected binding)"]
      -- filename and lineno --
      "fake.rb"
      10
      11
      -- dup shares the frame, not the additions --
      false
      true
      99
      false
    OUT
  end

  it "bindings" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # `binding` and `local_variables` read the CALLER's scope, so no method
      # row can answer them: the compile writes them out of the cells the
      # scope's names live in. A cell is the only storage a Binding can share,
      # so a scope that takes one keeps every name in one.

      def method_scope
        x = 1
        y = "two"
        b = binding
        [b.local_variables, b.local_variable_get(:x), b.receiver.class]
      end
      p method_scope
      p local_variables

      # The names come back the way ruby orders them: the innermost scope's
      # own first, then the enclosing ones a block carries.
      outer = 1
      [9].each { |i| inner = 2; p local_variables }

      # A binding writes back through the same cell the scope reads.
      def written_back
        n = 1
        binding.local_variable_set(:n, 9)
        n
      end
      p written_back

      # `Proc#binding` is the scope the proc was BUILT in: its own locals do
      # not exist until it runs.
      def make
        hidden = :in_make
        proc { hidden }
      end
      pr = make
      p [pr.binding.local_variables, pr.binding.local_variable_get(:hidden)]

      # A bare `eval` runs in the caller's binding, and so does one handed nil.
      zz = 11
      p [eval("zz + 1"), eval("zz + 2", nil), eval("zz + 3", binding)]

      # `TOPLEVEL_BINDING` is `<main>`'s own frame.
      p TOPLEVEL_BINDING.class
      p TOPLEVEL_BINDING.source_location
      p TOPLEVEL_BINDING.local_variable_get(:zz)

      # A method's binding sees the receiver's instance variables and its cref.
      class Holder
        LIMIT = 5
        def initialize = @v = 10
        def peek
          y = 1
          binding
        end
      end
      hb = Holder.new.peek
      p [hb.eval("@v"), hb.eval("y"), hb.eval("LIMIT")]
    RUBY

    _(result).must_answer <<~'OUT'
      [[:x, :y, :b], 1, Object]
      [:outer, :pr, :zz, :hb]
      [:i, :inner, :outer, :pr, :zz, :hb]
      9
      [[:hidden], :in_make]
      [12, 13, 14]
      Binding
      ["<main>", 0]
      11
      [10, 1, 5]
    OUT
  end

  it "bm instance eval" do
    result = ze0(<<~'RUBY')
      # Test instance_eval { block } block-form lifting.
      # Each section's output is compared against CRuby by `make test`.

      class Config
        attr_accessor :port, :host, :debug

        def initialize
          @port = 0
          @host = ""
          @debug = false
        end
      end

      # ---- 1. Top-level basic form ----
      cfg = Config.new
      cfg.instance_eval do
        self.port = 8080
        self.host = "localhost"
        self.debug = true
      end
      puts cfg.port    # 8080
      puts cfg.host    # localhost
      puts cfg.debug   # true

      # ---- 2. Two instance_eval calls in sequence (same object) ----
      cfg.instance_eval do
        self.port = 9090
      end
      puts cfg.port    # 9090

      # ---- 3. Methods called inside the block dispatch through self ----
      class Routes
        attr_accessor :entries

        def initialize
          @entries = "init".split(",")  # StrArray hint
          @entries.pop                  # start empty
        end

        def get(path)
          @entries.push("GET " + path)
        end

        def post(path)
          @entries.push("POST " + path)
        end
      end

      app = Routes.new
      app.instance_eval do
        get("/")
        get("/about")
        post("/login")
      end
      i = 0
      while i < app.entries.length
        puts app.entries[i]
        i = i + 1
      end

      # ---- 4. instance_eval inside a top-level while loop ----
      counter = Config.new
      i = 0
      while i < 3
        counter.instance_eval do
          self.port = self.port + 1
        end
        i = i + 1
      end
      puts counter.port  # 3

      # ---- 5. instance_eval inside a top-level if branch ----
      flag = Config.new
      cond = 1
      if cond > 0
        flag.instance_eval do
          self.debug = true
        end
      end
      puts flag.debug  # true

      # ---- 6. Different objects of different classes interleaved ----
      a = Config.new
      b = Routes.new
      a.instance_eval { self.port = 1 }
      b.instance_eval { get("/x") }
      a.instance_eval { self.port = 2 }
      b.instance_eval { post("/y") }
      puts a.port              # 2
      puts b.entries.length    # 2
      puts b.entries[0]        # GET /x
      puts b.entries[1]        # POST /y

      # ---- 7. Reassignment to another instance of the same class ----
      fresh = Config.new
      fresh.instance_eval { self.port = 11 }
      puts fresh.port  # 11
      fresh = Config.new
      fresh.instance_eval { self.port = 22 }
      puts fresh.port  # 22

      # ---- 8. Receiver from instance variable inside a class method ----
      # v2 wider-receiver (ivars): @ivar receiver. cls_ivar_type returns the
      # ivar's stored type; @current_class_idx is set by ieval_walk_class_methods
      # when entering each class's instance method bodies, so the lift can
      # resolve `@routes` to obj_Routes without going through a local copy.
      class Boot
        attr_accessor :routes

        def initialize
          @routes = Routes.new
        end

        def install
          @routes.instance_eval do
            get("/ivar")
            post("/ivar")
          end
        end
      end

      boot = Boot.new
      boot.install
      puts boot.routes.entries.length  # 2
      puts boot.routes.entries[0]      # GET /ivar
      puts boot.routes.entries[1]      # POST /ivar

      # ---- 9. Ivar receiver in tail position of a class method ----
      # Same lift but the instance_eval call is the method body's last
      # expression. The block's last call (`get("/tail")`) returns the
      # entries array, so the lift's value would flow out; explicitly
      # return @routes to keep `setup` returning the receiver.
      class Configure
        attr_accessor :routes

        def initialize
          @routes = Routes.new
        end

        def setup
          @routes.instance_eval { get("/tail") }
          @routes
        end
      end

      cfgr = Configure.new
      ret = cfgr.setup
      puts ret.entries.length  # 1
      puts ret.entries[0]      # GET /tail

      # ---- 10. Receiver from a method param ----
      # v2 wider-receiver (params): the param's class comes from the caller,
      # not the body. infer_param_types_from_callsites widens Wire#wire_param's
      # `r` ptype from "int" to obj_Routes when it sees `w.wire_param(shared)`
      # at top level (with `w` declared in scope so the receiver-method
      # branch fires). ieval_walk_class_methods then declares `r: obj_Routes`
      # in scope, and find_var_type resolves the LocalVariableReadNode
      # receiver inside the method body.
      class Wire
        def wire_param(r)
          r.instance_eval do
            get("/param")
          end
        end
      end

      w = Wire.new
      shared = Routes.new
      w.wire_param(shared)
      puts shared.entries.length  # 1
      puts shared.entries[0]      # GET /param

      # ---- 11. Param receiver in tail position ----
      # Same as §10 but the lift is the method body's last expression.
      # Block's last call (`get("/tail-param")`) returns the entries
      # array; explicitly return `r` to keep wire_param returning the
      # receiver.
      class WireTail
        def wire_param(r)
          r.instance_eval { get("/tail-param") }
          r
        end
      end

      w2 = WireTail.new
      shared2 = Routes.new
      ret2 = w2.wire_param(shared2)
      puts ret2.entries.length  # 1
      puts ret2.entries[0]      # GET /tail-param

      # ---- 12. Method-local copy of a class instance ----
      # scan_locals_first_type sees `routes = Routes.new` and declares
      # `routes : obj_Routes` in scope. The method-param case (§10) and
      # this method-local case both flow through the same find_var_type
      # fallback added to ieval_rewrite_call's LocalVariableReadNode branch.
      class WireLocal
        def setup
          routes = Routes.new
          routes.instance_eval do
            get("/local")
            post("/local")
          end
          routes
        end
      end

      ret3 = WireLocal.new.setup
      puts ret3.entries.length  # 2
      puts ret3.entries[0]      # GET /local
      puts ret3.entries[1]      # POST /local
    RUBY

    _(result).must_answer <<~'OUT'
      8080
      localhost
      true
      9090
      GET /
      GET /about
      POST /login
      3
      true
      2
      2
      GET /x
      POST /y
      11
      22
      2
      GET /ivar
      POST /ivar
      1
      GET /tail
      1
      GET /param
      1
      GET /tail-param
      2
      GET /local
      POST /local
    OUT
  end

  it "call arg eval order" do
    result = ze0(<<~'RUBY')
      $n = 0

      def nxt
        $n += 1
        $n
      end

      def three(a, b, c)
        [a, b, c]
      end

      class Box
        def initialize(a, b, c, d)
          @a = a
          @b = b
          @c = c
          @d = d
        end

        def to_a
          [@a, @b, @c, @d]
        end
      end

      p three(nxt, nxt, nxt)
      p Box.new(nxt, nxt, "%d!" % [nxt], nxt).to_a
      p three(nxt, [nxt, nxt], nxt)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [4, 5, "6!", 7]
      [8, [9, 10], 11]
    OUT
  end

  it "call arg eval order scalar" do
    result = ze0(<<~'RUBY')
      $log = []
      def sink(a, b, c)
        "#{a}|#{b}|#{c}"
      end
      def bump(n)
        $log << n
        n
      end
      i = 0
      puts sink(bump(1), bump(2), bump(3))
      p $log

      # a scalar operator argument beside a real side effect still sequences
      $log = []
      x = 5
      puts sink(x + 1, bump(9), x * 2)
      p $log

      # a mutating argument must still be ordered against a read of what it mutates
      arr = [1, 2, 3]
      def two(a, b) = "#{a}/#{b}"
      puts two(arr.shift, arr.first)
      p arr
    RUBY

    _(result).must_answer <<~'OUT'
      1|2|3
      [1, 2, 3]
      6|9|10
      [9]
      1/2
      [2, 3]
    OUT
  end

  it "class eval definee" do
    result = ze0(<<~'RUBY')
      # A `def` or `define_method` inside a `class_eval`/`module_eval` block installs
      # on the receiver when the BLOCK runs, not when the enclosing class body was
      # compiled -- so it has to displace whatever the class already answers.
      #
      # The definition itself always reached the right class: a brand-new name works
      # even without any of this. What failed was the CALL -- a receiver whose class
      # zeo knows folds to the compiled body and never asks the overlay. So the names
      # a block-position `def` installs join `Compiler::runtime_redefs` beside the
      # explicit `define_method` calls, and the fold stands down for them.
      #
      # Both call kinds needed it: an instance call and a `def self.` class-method
      # call fold at different sites.

      class N
        def d = "d0"
        def e = "e0"
      end
      n = N.new

      N.class_eval { define_method(:d) { "d1" } }
      p n.d

      N.class_eval { def e = "e1" }
      p n.e

      # `module_eval` is the same method under its other name, and a class-method
      # definition folds at a different site than an instance one.
      module M
        def self.tag = "m0"
      end
      M.module_eval { def self.tag = "m1" }
      p M.tag

      # A brand-new name never had the problem -- there was no compiled body to fold
      # to -- which is what showed the definee was right all along.
      N.class_eval { def fresh = "f" }
      p n.fresh

      # Nested a block deeper, and reached through a local rather than the constant.
      target = N
      [1].each { target.class_eval { def deep = "deep" } }
      p n.deep

      # A class body's own `def` still folds: nothing here installs at runtime.
      class Untouched
        def stable = "s"
      end
      p Untouched.new.stable
    RUBY

    _(result).must_answer <<~'OUT'
      "d1"
      "e1"
      "m1"
      "f"
      "deep"
      "s"
    OUT
  end

  it "class eval reopen" do
    result = ze0(<<~'RUBY')
      # `Klass.class_eval do ... end` reopens the class: each `def` and
      # `define_method(:lit)` in the block body becomes an instance method on
      # the class, exactly as a `class Klass ... end` reopen would. A def may
      # read an existing ivar or assign a new one (which gets its own slot),
      # subclasses inherit the added methods, and `module_eval` is an alias.
      # The receiver may be a constant (plain or namespaced `M::Klass`) or, inside
      # a class body, a bare/`self.` receiver naming the enclosing class.
      class Box
        def initialize(v)
          @v = v
        end
      end

      class BoxPlus < Box
      end

      Box.class_eval do
        def doubled
          @v * 2
        end

        define_method(:tripled) do
          @v * 3
        end

        # A String literal names the method just as a Symbol does.
        define_method("quadded") do
          @v * 4
        end
      end

      # module_eval is the same operation under a different name.
      Box.module_eval do
        def labelled
          @label = "n=" + @v.to_s
          @label
        end
      end

      b = Box.new(21)
      puts b.doubled
      puts b.tripled
      puts b.quadded
      puts b.labelled

      # A subclass inherits the class_eval-added instance methods.
      bp = BoxPlus.new(5)
      puts bp.doubled
      puts bp.tripled

      # A namespaced receiver (`M::Widget`) reopens the same way.
      module M
        class Widget
          def initialize(v)
            @v = v
          end
        end
      end

      M::Widget.class_eval do
        def quad
          @v * 4
        end
      end

      puts M::Widget.new(3).quad

      # Inside a class body, a bare or `self.` receiver names the enclosing class.
      class Gadget
        def initialize(v)
          @v = v
        end

        class_eval do
          def a
            @v
          end
        end

        self.class_eval do
          def doubled
            @v * 2
          end
        end
      end

      g = Gadget.new(10)
      puts g.a
      puts g.doubled
    RUBY

    _(result).must_answer <<~'OUT'
      42
      63
      84
      n=21
      10
      15
      12
      10
      20
    OUT
  end

  it "class eval resolves constants in the receiver" do
    result = ze0(<<~'RUBY')
      # The receiver is a class only the RUN TIME knows -- the snippet's own
      # compiler has no entry for it, so its id travels as an immediate and
      # every static fold stands down. The `def`'s body inherits the same
      # cref, which is what makes `def tell = SECRET` find `Host::SECRET`.

      class Host
        SECRET = :host_secret
      end
      reader = "SECRET"
      p Host.class_eval(reader)
      defn = "def tell = SECRET"
      Host.class_eval(defn)
      p Host.new.tell
      p Host.private_instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      :host_secret
      :host_secret
      []
    OUT
  end

  it "class eval value form" do
    result = ze0(<<~'RUBY')
      # The value forms of class_eval / class_exec / module_eval / module_exec: the
      # block is spliced inline (self = the receiver constant), its value is the
      # call's value, and class_exec's args bind the block params (#2697). A pure-def
      # body keeps going through the compile-time reopen path.
      class C; end
      module M; end
      r = C.class_eval { 40 + 2 }
      p r
      p(C.class_exec(5) { |n| n * 2 })
      r2 = C.class_eval do
        x = 10
        y = x * 2
        "#{self}/#{y}"
      end
      p r2
      p(M.module_eval { 7 })
      p(M.module_exec(3, 4) { |a, b| a + b })
      base = 100
      p(C.class_exec(5) { |n| base + n })
      class D; end
      D.class_eval do
        def hi; "hi"; end
      end
      p D.new.hi
    RUBY

    _(result).must_answer <<~'OUT'
      42
      10
      "C/20"
      7
      7
      105
      "hi"
    OUT
  end

  it "definition hooks at runtime" do
    result = ze0(<<~'RUBY')
      # Ruby reports every definition to the class it landed on. This file covers the
      # definitions made AT RUNTIME -- `define_method`, `class_eval`, `Class.new`, a
      # singleton def -- where the hook fires from the runtime writer itself.
      #
      # One rule drives all six names (CRuby's `CALL_METHOD_HOOK`): a definition on a
      # singleton reports to the attached OBJECT under the `singleton_` name;
      # everything else reports to the class.

      Base = Class.new do
        def self.method_added(n) = puts("added #{n}")
        def self.method_removed(n) = puts("removed #{n}")
        def self.method_undefined(n) = puts("undefined #{n}")
        # Installed last, so it is the only one of the four that reports itself.
        def self.singleton_method_added(n) = puts("s_added #{n}")
      end

      puts "-- define_method"
      Base.send(:define_method, :a) { 1 }
      puts "-- attr_accessor reports the reader, then the writer"
      Base.class_eval { attr_accessor :c }
      puts "-- alias_method reports the NEW name"
      Base.send(:alias_method, :d, :a)
      puts "-- define_singleton_method"
      Base.define_singleton_method(:sing) { 2 }
      puts "-- define_method from a Method object"
      Base.send(:define_method, :e, Base.instance_method(:a))
      puts "-- remove_method"
      Base.send(:remove_method, :d)
      puts "-- undef_method"
      Base.send(:undef_method, :a)

      # `private :m` on the class's OWN method sets the visibility in place and
      # reports nothing. On an INHERITED one ruby synthesizes a fresh entry, which
      # IS a definition.
      puts "-- private, own vs inherited"
      Base.send(:define_method, :own) { }
      Base.send(:private, :own)
      Base.send(:private, :inspect)

      # A per-object singleton reports to that object alone.
      puts "-- per-object singleton"
      o = Object.new
      o.define_singleton_method(:singleton_method_added) { |n| puts "o s_added #{n}" }
      o.define_singleton_method(:bar) { }
      def o.written_as_a_def = 1
      class << o
        def written_in_a_singleton_class = 2
      end

      # `module_function` makes an instance copy AND a module method, and ruby
      # reports both -- but the explicit-name form reports only the module half,
      # because the instance copy already existed.
      puts "-- module_function"
      M = Module.new do
        def self.method_added(n) = puts("M added #{n}")
        def self.singleton_method_added(n) = puts("M s_added #{n}")
      end
      M.send(:define_method, :mm) { }
      M.send(:module_function, :mm)

      # A `Numeric` is meant to be interchangeable with any equal value, so ruby
      # refuses it a singleton at all -- through this very hook.
      puts "-- Numeric refuses a singleton"
      class Deg < Numeric
        def initialize(v) = @v = v
        def inspect = "Deg"
      end
      n = Deg.new(7)
      [-> { def n.frob = :frobbed }, -> { n.define_singleton_method(:frob) { } }].each do |attempt|
        attempt.call
      rescue TypeError => e
        puts "numeric: #{e.message}"
      end

      # `include`/`extend` splice a module in; they define nothing, so nothing fires.
      puts "-- include and extend report nothing"
      Mixin = Module.new { def mixed = 1 }
      Base.send(:include, Mixin)
      o.extend(Mixin)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      s_added singleton_method_added
      -- define_method
      added a
      -- attr_accessor reports the reader, then the writer
      added c
      added c=
      -- alias_method reports the NEW name
      added d
      -- define_singleton_method
      s_added sing
      -- define_method from a Method object
      added e
      -- remove_method
      removed d
      -- undef_method
      undefined a
      -- private, own vs inherited
      added own
      added inspect
      -- per-object singleton
      o s_added singleton_method_added
      o s_added bar
      o s_added written_as_a_def
      o s_added written_in_a_singleton_class
      -- module_function
      M s_added singleton_method_added
      M added mm
      M s_added mm
      -- Numeric refuses a singleton
      numeric: can't define singleton method "frob" for Deg
      numeric: can't define singleton method "frob" for Deg
      -- include and extend report nothing
      done
    OUT
  end

  it "destructured param in a binding" do
    result = ze0(<<~'RUBY')
      # A parenthesized destructuring block parameter, in a scope that materializes
      # a Binding. Zeo names the un-destructured slot internally (`__destr_0`) and
      # listed it among the scope's own locals, which did two wrong things at once:
      # `local_variables` reported the synthetic name, and the slot was promoted to
      # a shared cell -- while the destructure that READS it runs in the prologue,
      # ahead of the promotion, so the read found a plain value where a cell was
      # promised and the program did not compile.
      #
      # prism's lex_compat.rb is written this way (`sort_by.with_index { |(token,
      # lex_state), index| ... }`), which is how irb reached it.
      seen = nil
      [[[1, 2], 9]].each do |(a, b), i|
        seen = binding.local_variables.sort
      end
      p seen

      names = nil
      [[1, 2]].each do |(x, y)|
        inner = proc { x + y }
        names = inner.binding.local_variables.sort
      end
      p names

      # The destructure itself still binds, and the Binding still reads the names it
      # really does hold.
      vals = nil
      [[[3, 4], 5]].each do |(m, n), k|
        b = binding
        vals = [b.local_variable_get(:m), b.local_variable_get(:n), b.local_variable_get(:k)]
      end
      p vals

      # A nested destructure, and one with a splat.
      deep = nil
      [[[1, [2, 3]], 4]].each do |(p1, (p2, p3)), q|
        deep = binding.local_variables.sort
      end
      p deep

      rest = nil
      [[[1, 2, 3]]].each do |(first, *others)|
        rest = [binding.local_variables.sort, first, others]
      end
      p rest

      # `Proc#parameters` has always hidden the slot; it agrees with the Binding now.
      p(proc { |(a, b), c| }.parameters)
      p(lambda { |(a, b), c| }.parameters)
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :b, :deep, :i, :names, :rest, :seen, :vals]
      [:deep, :inner, :names, :rest, :seen, :vals, :x, :y]
      [3, 4, 5]
      [:deep, :names, :p1, :p2, :p3, :q, :rest, :seen, :vals]
      [[:deep, :first, :names, :others, :rest, :seen, :vals], [1, 2, 3], []]
      [[:opt], [:opt, :c]]
      [[:req], [:req, :c]]
    OUT
  end

  it "a literal eval reads and writes the enclosing local and instance variables" do
    result = ze0(<<~'RUBY')
      puts eval("1 + 2")

      x = 1
      eval("x = x + 1")
      puts x

      class Box
        def initialize
          eval("@value = 10")
        end

        def value
          @value
        end
      end

      b = Box.new
      puts b.value
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      10
    OUT
  end

  it "a class body compiled at run time keeps its own openers, so the snippet still parses" do
    result = ze0(<<~'RUBY')
      # A class body compiled at RUN TIME is recovered from the snippet's own
      # source text, and the slice has to start where the BODY starts -- not at
      # the first statement.
      #
      # `lower::defs` flattens a `class << self` into a surrogate reopen plus the
      # retagged `def`s, so neither the opener nor the closing `end` belongs to a
      # statement any more. The recovery already added the closing `end` back. It
      # did not add the OPENER, and with a constant inside the singleton body the
      # first statement is the one written INSIDE it -- so the recovered text
      # carried one `end` too many and prism refused the whole snippet with
      # `unexpected \'end\'`, at a line the program never wrote.
      #
      # `rubygems/vendor/uri/lib/uri/common.rb` is written exactly that way, and
      # this was the second thing standing between zeo and `require "rubygems"`.
      #
      # Slicing from the end of the class HEADER hands back the text the program
      # wrote, openers included.

      def try(name, src)
        eval src, nil, "s.rb"
        puts "#{name}\tok"
      rescue Exception => e
        puts "#{name}\t#{e.class}: #{e.message.lines.first.chomp}"
      end

      # A constant inside `class << self` -- the shape that refused.
      try("const in a singleton body", <<~SRC)
        module E1
          class << self
            CHARS = ".+-"
            def escape(s) = s.tr(CHARS, "___")
          end
        end
      SRC
      puts "escape\t#{E1.escape("a.b")}"

      # A brace block spanning lines, which was never the problem but reads like it.
      try("a multi-line brace block", <<~SRC)
        module E2
          class << self
            def pairs
              [1, 2].map { |x|
                [x, x]
              }.to_h
            end
          end
        end
      SRC
      puts "pairs\t#{E2.pairs}"

      # Both together, plus a one-line header (`;` ends it, not a newline).
      try("a one-line class header", <<~SRC)
        class E3; class << self
            LIMIT = 3
            def under = (1..LIMIT).to_a
          end
        end
      SRC
      puts "under\t#{E3.under}"

      # A plain body still reports the same lines it always did.
      try("a plain body raising", <<~SRC)
        module E4
          def self.boom
            raise "x"
          end
        end
      SRC
      begin
        E4.boom
      rescue RuntimeError => e
        puts "frame\t#{e.backtrace.first}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      const in a singleton body	ok
      escape	a_b
      a multi-line brace block	ok
      pairs	{1 => 1, 2 => 2}
      a one-line class header	ok
      under	[1, 2, 3]
      a plain body raising	ok
      frame	s.rb:3:in 'E4.boom'
    OUT
  end

  it "the class keyword binds the constant before the inherited hook fires, in a snippet too" do
    result = ze0(<<~'RUBY')
      # The `class` KEYWORD names a class and binds its constant BEFORE the
      # superclass's `inherited` hook fires -- CRuby's rb_define_class_id_under
      # order -- in an eval snippet too. Only `Class.new` shows the hook a nil
      # name. rss's Element.inherited reads `klass.name` for the tag name.
      module M
        class Base
          def self.inherited(k)
            super
            p [:inherited, k.name, M.const_defined?(:Kid, false)]
          end
        end
        M.module_eval("class Kid < Base; end")
        p M::Kid.name
      end
      anon = Class.new(M::Base)
      p anon.name
    RUBY

    _(result).must_answer <<~'OUT'
      [:inherited, "M::Kid", true]
      "M::Kid"
      [:inherited, nil, true]
      nil
    OUT
  end

  it "a class at a literal eval's top level registers as one written in place" do
    result = ze0(<<~'RUBY')
      # A literal `eval` splices at compile time, and a `class` at its top level
      # registers exactly as one written in place -- the registration walk descends
      # the spliced body. (A top-level `def` in an eval is still a rejection.)
      eval("class EvalKlass\n  def hi\n    41 + 1\n  end\nend")
      p EvalKlass.new.hi
      p EvalKlass.instance_methods(false).sort
    RUBY

    _(result).must_answer "42\n[:hi]\n"
  end

  it "class_eval writes a def on its receiver, and a bare private is a cursor the later defs read" do
    result = ze0(<<~'RUBY')
      # The definition-level statements a run-time `eval` may write. Each one names
      # a DEFINEE only the run time knows -- `class_eval`'s receiver, a plain
      # `eval`'s enclosing class -- so each is the send ruby writes on it, and a
      # bare `private`/`module_function` is a cursor every later `def` reads.

      class K
        def a = "a"
        def b = "b"
        def self.c = "c"
      end

      p K.class_eval("alias a2 a".dup)
      p K.new.a2
      K.class_eval("undef b".dup)
      p K.new.respond_to?(:b)
      p K.class_eval("private :a".dup)
      p [K.new.respond_to?(:a), K.new.send(:a)]
      K.class_eval("private_class_method :c".dup)
      p K.respond_to?(:c)

      # A bare directive is the body's running default.
      class Cursor; end
      Cursor.class_eval("def pub = 1\nprivate\ndef pri = 2\npublic\ndef pub2 = 3".dup)
      p [Cursor.new.respond_to?(:pub), Cursor.new.respond_to?(:pri), Cursor.new.respond_to?(:pub2)]
      p Cursor.new.send(:pri)

      module Funcs
        def helper = :h
      end
      p Funcs.module_eval("module_function :helper".dup)
      p Funcs.helper

      module Bare; end
      Bare.module_eval("module_function\ndef mf = :mf".dup)
      p [Bare.mf, Bare.respond_to?(:mf)]

      # `include`/`extend`/`prepend` are ordinary sends, hooks and all.
      module Loud
        def self.included(base) = puts("included #{base}")
        def shout = "loud"
      end
      class Host; end
      p Host.class_eval("include Loud".dup)
      p Host.new.shout

      # A redefinition inside one snippet takes at its own position.
      class Twice; end
      Twice.class_eval("def d = 1\ndef d = 2".dup)
      p Twice.new.d

      # A `def` announces to the class it lands on.
      class Watched
        def self.method_added(name) = puts("added #{name}")
      end
      Watched.class_eval("def watched = 1".dup)

      # A singleton class is an ordinary definee too.
      class Single
        class << self
          def sc = 1
        end
      end
      Single.singleton_class.class_eval("alias sc2 sc".dup)
      p Single.sc2
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "a"
      false
      :a
      [false, "a"]
      false
      [true, false, true]
      2
      :helper
      :h
      [:mf, true]
      included Host
      Host
      "loud"
      2
      added watched
      1
    OUT
  end

  it "a source only known at run time runs through the eval VM with self, constants and globals" do
    result = ze0(<<~'RUBY')
      # Runtime string `eval` (#97 stage 2). Each source is a runtime VALUE (a
      # variable, not a string literal), so it runs through the eval VM -- a
      # tree-walking interpreter over prism, linked into the runtime -- rather than
      # the compile-time inline path a string LITERAL takes. Scope: a correct `self`,
      # constants, and globals, but not the caller's own locals (a first-class
      # `binding` is a later increment).

      # Arithmetic honours precedence.
      puts eval("1 + 2 * 3".dup)

      # Method calls on evaluated receivers.
      puts eval("[3, 1, 2].sort.inspect".dup)
      puts eval("'Ruby'.upcase".dup)
      puts eval("(-5).abs".dup)

      # Locals defined and read within the SAME eval share one scope.
      puts eval("a = 10; b = 20; a + b".dup)

      # String interpolation inside the eval'd source.
      puts eval('x = 5; "x squared is #{x * x}"'.dup)

      # The source itself is assembled at runtime.
      op = "*"
      lhs = 6
      rhs = 7
      puts eval("#{lhs} #{op} #{rhs}")

      # Control flow -- the value is the last expression evaluated.
      puts eval("if 2 > 1 then 'yes' else 'no' end".dup)
      puts eval("total = 0; i = 1; while i <= 5; total = total + i; i = i + 1; end; total".dup)

      # Short-circuit operators return the operand, not a coerced boolean.
      puts eval("nil || 'fallback'".dup)

      # Constants resolve -- builtin classes, module constants, method calls on them.
      puts eval("Integer".dup)
      puts eval("Math::PI".dup).round(3)
      puts eval("Math.sqrt(144)".dup)

      # Collections.
      puts eval("[1, 2, 3, 4].length".dup)
      puts eval("{ a: 1, b: 2 }.length".dup)
      puts eval("(1..5).to_a.inspect".dup)

      # eval sees top-level globals and the main object's ivars.
      $greeting = "hi"
      puts eval("$greeting".dup)
      @count = 41
      puts eval("@count + 1".dup)

      # A non-String argument is a TypeError, exactly as in CRuby.
      begin
        eval(123)
      rescue TypeError => e
        puts e.message
      end

      # A syntax error in the source is a catchable SyntaxError.
      begin
        eval("1 +".dup)
      rescue SyntaxError
        puts "caught SyntaxError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      [1, 2, 3]
      RUBY
      5
      30
      x squared is 25
      42
      yes
      15
      fallback
      Integer
      3.142
      12.0
      4
      2
      [1, 2, 3, 4, 5]
      hi
      42
      no implicit conversion of Integer into String
      caught SyntaxError
    OUT
  end

  it "instance_eval of a string rebinds self, so an @ivar read resolves against the receiver" do
    result = ze0(<<~'RUBY')
      # The STRING form of `instance_eval` (#97 stage 2): the source runs through the
      # eval VM with `self` rebound to the receiver, so `@ivar` reads and
      # implicit-self calls resolve against that object -- the whole point of
      # `instance_eval`. (The block form, `obj.instance_eval { ... }`, is unchanged.)

      class Account
        def initialize(balance)
          @balance = balance
          @currency = "USD"
        end
      end

      acct = Account.new(100)

      # read the receiver's ivars from an eval'd string
      puts acct.instance_eval("@balance")
      puts acct.instance_eval("@currency")
      puts acct.instance_eval("@balance * 2")

      # interpolate the receiver's state
      puts acct.instance_eval('"#{@balance} #{@currency}"')

      # mutate an ivar through instance_eval, then observe it
      acct.instance_eval("@balance = @balance + 50")
      puts acct.instance_eval("@balance")

      # instance_eval on a literal receiver: self is that object
      puts "hello".instance_eval("upcase.reverse")
      puts [5, 3, 1, 4, 2].instance_eval("sort.inspect")

      # the block form still works alongside the string form
      puts acct.instance_eval { @currency }

      # top-level eval shares the main object's ivars
      @note = "top-level"
      puts eval("@note")
    RUBY

    _(result).must_answer <<~'OUT'
      100
      USD
      200
      100 USD
      150
      OLLEH
      [1, 2, 3, 4, 5]
      USD
      top-level
    OUT
  end

  it "a class written in a run-time eval mints the class and runs the body as its own scope" do
    result = ze0(<<~'RUBY')
      # A `class`/`module` written in a run-time `eval`. The header mints or reuses
      # the class through the runtime; the BODY runs as one more `class_eval` of its
      # own source, which is what a class body IS -- a scope with its own cref, its
      # own locals, sharing nothing with the snippet around it.

      r = eval("class Made\n  SECRET = 41\n  def hi = 'hi'\n  def sec = SECRET + 1\nend".dup)
      p r
      p Made.new.hi
      p Made.new.sec
      p Made::SECRET
      p [Made.name, Made.superclass]

      # A superclass expression reads in the SNIPPET's scope, and `super` walks.
      eval("class Sub2 < Made\n  def hi = 'sub-' + super\nend".dup)
      p Sub2.new.hi

      # A module, and a scoped name.
      eval("module Mod1\n  def self.who = 'mod'\nend".dup)
      p [Mod1.who, Mod1.name]
      module Outer; end
      eval("class Outer::Inner\n  def z = 1\nend".dup)
      p [Outer::Inner.new.z, Outer::Inner.name]

      # A reopen finds the class the constant already names.
      eval("class Made\n  def more = 2\nend".dup)
      p [Made.new.more, Made.new.hi]

      # The body is worth its last statement, and an empty one is nil.
      p eval("class Val; 7; end".dup)
      p eval("class Empty; end".dup)

      # Nesting, class variables, mixins, accessors, and an enclosing cref.
      TOP = 1
      module Wrap
        IN_WRAP = 2
      end
      eval(<<~SRC.dup)
        class Deep
          class Nested
            def n = 'n'
          end
          @@cv = 5
          def self.cv = @@cv
          attr_accessor :a
          include Comparable
          def <=>(other) = 0
          def top = TOP
          ME = self
        end
      SRC
      p Deep::Nested.new.n
      p Deep.cv
      d = Deep.new
      d.a = 9
      p d.a
      p Deep.ancestors.include?(Comparable)
      p [Deep.new.top, Deep::ME, Deep::Nested.name]

      # A class opened inside a `class_eval` inherits ITS cref, so a constant of the
      # enclosing module is still in reach.
      Wrap.class_eval("class Inside\n  def w = IN_WRAP\nend".dup)
      p [Wrap::Inside.new.w, Wrap::Inside.name]
    RUBY

    _(result).must_answer <<~'OUT'
      :sec
      "hi"
      42
      41
      ["Made", Object]
      "sub-hi"
      ["mod", "Mod1"]
      [1, "Outer::Inner"]
      [2, "hi"]
      7
      nil
      "n"
      5
      9
      true
      [1, Deep, "Deep::Nested"]
      [2, "Wrap::Inside"]
    OUT
  end

  it "a return an eval writes leaves the method the eval stands in, whichever form the eval took" do
    result = ze0(<<~'RUBY')
      # A `return` written inside an eval'd string belongs to the method the eval
      # sits in, not to the eval. The method arms a catch for a return signal that
      # carries no home of its own, and it must arm it for every spelling of eval,
      # not only for a call written `eval`.

      class Widget; end

      def literal;      eval("return 1");                :fell_through; end
      def instance;     instance_eval("return 2");       :fell_through; end
      def on_a_number;  1.instance_eval("return 3");     :fell_through; end
      def klass;        Widget.class_eval("return 4");   :fell_through; end
      def mod;          Widget.module_eval("return 5");  :fell_through; end
      def sent;         send(:eval, "return 6");         :fell_through; end
      def sent_twice;   __send__(:eval, "return 7");     :fell_through; end
      def fetched;      method(:eval).call("return 8");  :fell_through; end
      def bound;        binding.eval("return 9");        :fell_through; end

      p [literal, instance, on_a_number, klass, mod, sent, sent_twice, fetched, bound]
    RUBY

    _(result).must_answer "[1, 2, 3, 4, 5, 6, 7, 8, 9]\n"
  end

  it "a def written inside an eval keeps its own return" do
    result = ze0(<<~'RUBY')
      # The catch belongs to the method the eval stands in. A `def` the eval writes
      # is a method of its own, so its `return` leaves it and no more: `outer` runs
      # on to its last statement.

      def outer
        instance_eval("def inner; return :inner; end")
        [inner, :outer]
      end

      p outer
    RUBY

    _(result).must_answer "[:inner, :outer]\n"
  end

  it "send, public_send and method all reach eval, and the string still compiles where it runs" do
    result = ze0(<<~'RUBY')
      p send(:eval, "1 + 1")
      p __send__(:eval, "2 + 2")
      p "s".public_send(:instance_eval, "size")
      p method(:eval).call("3 + 3")
      String.send(:class_eval, "def zz = :zz")
      p "q".zz

    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      1
      6
      :zz
    OUT
  end

  it "an invalid pattern in an eval raises SyntaxError, which a bare rescue does not catch" do
    result = ze0(<<~'RUBY')
      # A pattern the engine will not compile is a SYNTAX error, not a run-time
      # one: ruby reads the literal as it compiles the string, so the eval raises
      # SyntaxError and names onig's reason and the pattern. SyntaxError is a
      # ScriptError, so `rescue StandardError` walks past it.
      begin
        eval("/[z-a]/ =~ 'a'")
      rescue SyntaxError => e
        p e.class
        p e.message[/empty range in char class: .*/]
      end

      begin
        eval("/a{2,1}/ =~ 'a'")
      rescue SyntaxError => e
        p e.message[/upper is smaller.*/]
      end

      begin
        eval("/[b-a]/ =~ 'a'")
      rescue StandardError
        puts "standard"
      rescue SyntaxError
        puts "script"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      SyntaxError
      "empty range in char class: /[z-a]/"
      "upper is smaller than lower in repeat range: /a{2,1}/"
      script
    OUT
  end


  it "a non-literal source is not refused at compile time; it runs in the VM" do
    result = ze0(<<~'RUBY')
      # A non-literal source is not rejected at compile time; it runs
      # through the runtime `eval`. (`y` is interpolated INTO the source string, not
      # referenced inside the eval.)

      y = 40
      puts eval("#{y} + 2")
    RUBY

    _(result).must_answer "42\n"
  end

  it "|| in an eval'd source answers the operand, not true" do
    result = ze0(<<~'RUBY')
      src = "nil || 'fallback'"; puts eval(src)
    RUBY

    _(result).must_answer "fallback\n"
  end

  it "a class << self body in a snippet homes its constants on the singleton" do
    result = ze0(<<~'RUBY')
      src = <<~SRC
        module Schemes
          class << self
            CHARS = ".+-"
            MAX = CHARS.size
            class Box; end
            def list = constants
            def chars = CHARS
            def box = Box
            private def hidden = :hidden
          end
        end
      SRC
      eval src, nil, "s.rb"

      # The constants and the nested class belong to the SINGLETON, not the module.
      p Schemes.constants
      p Schemes.list
      p Schemes.singleton_class.constants(false).sort
      p Schemes.chars
      p [Schemes.box.is_a?(Class), Schemes.box.equal?(Schemes.singleton_class.const_get(:Box))]
      p((Schemes::CHARS rescue $!.class))

      # The defs are class methods of the module, and `private` still holds.
      p Schemes.respond_to?(:chars)
      p Schemes.respond_to?(:hidden)
      p Schemes.singleton_methods.sort

      # `class << self` in a snippet whose self is main opens MAIN's singleton.
      eval "class << self; def only_here = 7; end"
      p self.singleton_class.instance_methods(false).include?(:only_here)
      p only_here
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      [:Box, :CHARS, :MAX]
      ".+-"
      [true, true]
      NameError
      true
      false
      [:box, :chars, :list]
      true
      7
    OUT
  end

  it "a source assembled by interpolation runs as the text it became" do
    result = ze0(<<~'RUBY')
      op = "-"; puts eval("10 #{op} 3")
    RUBY

    _(result).must_answer "7\n"
  end

  it "eval, class_eval and module_eval each link the run-time compiler for the string they are given" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # The verbs that run a STRING of ruby. There is nothing for the compile
      # to see, so the sidecar asks the backend to link the run-time compiler
      # and the string is compiled where it runs.

      p eval("1 + 2")
      p eval("[1, 2].map { |n| n * 3 }")

      # `class_eval` installs into the class it is called on.
      class Counter
        def initialize = @n = 0
      end
      Counter.class_eval("def bump = @n += 1")
      c = Counter.new
      c.bump
      p c.bump

      # `module_eval` reaches a module's own singleton.
      module Tools; end
      Tools.module_eval("def self.twice(x) = x * 2")
      p Tools.twice(21)

      # `instance_eval` runs with the receiver as `self`, so a `def` there is
      # that one object's.
      o = Object.new
      o.instance_eval("def only_mine = :mine")
      p o.only_mine
      p(o.instance_eval("self") == o)

      # A string that does not parse raises where the eval stands.
      begin
        eval("1 +")
      rescue SyntaxError
        puts "SyntaxError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [3, 6]
      2
      42
      :mine
      true
      SyntaxError
    OUT
  end

  it "the eval VM answers defined? and forwards (...), which def_delegators needs" do
    result = ze0(<<~'PROGRAM')
      # The eval VM's `defined?` and `(...)` forwarding -- forwardable's generated
      # delegators need both, so every gem that uses `def_delegators` does.
      class Box
        def initialize(inner) = @inner = inner
      end

      Box.class_eval(<<~RUBY)
        def call_it(...)
          _ = @inner
          if defined?(_.upcase)
            _.upcase(...)
          else
            :no_upcase
          end
        end

        def probe
          x = 1
          [defined?(x), defined?(y), defined?(@inner), defined?(@nope),
           defined?(String), defined?(NotAThing), defined?(self), defined?(1 + 1),
           defined?(probe), defined?(no_such_method)]
        end
      RUBY

      p Box.new("hi").call_it
      p Box.new(42).call_it
      p Box.new("x").probe

      # Forwarding carries the BLOCK too, not just the positional arguments.
      class Relay
        def initialize(target) = @target = target
      end
      Relay.class_eval(<<~RUBY)
        def each(...)
          @target.each(...)
        end
      RUBY
      seen = []
      Relay.new([1, 2, 3]).each { |v| seen << v * 2 }
      p seen

      # A `do ... end` block inside eval re-parses correctly (it is stored as its own
      # source and wrapped back into call position on each invocation).
      g = eval("proc do\n  def made_here(a, b = 2)\n    a + b\n  end\nend")
      class Target; end
      Target.module_eval(&g)
      p Target.new.made_here(1)
      p Target.new.made_here(1, 10)
    PROGRAM

    _(result).must_answer <<~'OUT'
      "HI"
      :no_upcase
      ["local-variable", nil, "instance-variable", nil, "constant", nil, "self", "method", "method", nil]
      [2, 4, 6]
      3
      11
    OUT
  end

  it "expression evaluates" do
    result = ze0(<<~'RUBY')
      src = "1 + 1"
      p eval(src)
      p eval("2 * 3" + "")
    RUBY

    _(result).must_answer "2\n6\n"
  end

  it "instance eval binds the receiver and its singleton" do
    result = ze0(<<~'RUBY')
      obj = Object.new
      obj.instance_variable_set(:@v, 3)
      read = "@v * 2"
      p obj.instance_eval(read)
      defn = "def dbl; @v * 4; end"
      obj.instance_eval(defn)
      p obj.dbl
    RUBY

    _(result).must_answer "6\n12\n"
  end

  it "instance eval builtin receiver" do
    result = ze0(<<~'RUBY')
      # instance_eval / instance_exec with a block on a BUILTIN receiver (#2634):
      # the body is spliced inline with self bound to a temp; receiverless calls
      # dispatch on the new self (Kernel globals stay receiverless), and the call's
      # value is the block's. User-object receivers keep the dedicated splice that
      # handles their ivars and methods.
      p "abc".instance_eval { upcase }
      p 5.instance_eval { self + 1 }
      p [1, 2].instance_eval { length * 10 }
      p "xy".instance_exec(3) { |n| self * n }
      p "s".instance_eval { |s| s + "!" }
      p "abc".instance_eval { self.upcase }
      p "hi".instance_eval { puts upcase; length }
      x = "abc".instance_eval { 1 + 1 }
      p x
      # multi-statement body with locals
      p("ab".instance_eval do
        u = upcase
        "#{u}/#{length}"
      end)
      # user-object receivers still ride the ivar-aware path
      class W
        def initialize; @v = 7; end
        def get; @v; end
      end
      p W.new.instance_eval { @v + 1 }
      p W.new.instance_eval { get * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      "ABC"
      6
      20
      "xyxyxy"
      "s!"
      "ABC"
      HI
      2
      2
      "AB/2"
      8
      14
    OUT
  end

  it "instance_eval with an arity-0 block runs the block against the receiver" do
    result = ze0(<<~'RUBY')
      # Inline-at-call-site arity-0 instance-eval trampoline.
      #
      # Full Ruby instance-eval is dynamic — `self` is rebound at runtime,
      # so AOT compilation needs static type information to resolve method
      # dispatch inside the block. Spinel's compromise: detect the exact
      # DSL trampoline shape `def m(&b); instance_eval(&b); end` at compile
      # time, and inline the block body at the call site with `self`
      # rebound to the receiver. Receiverless calls inside the spliced
      # body dispatch to the receiver's class via static type inference
      # (the new `@instance_eval_self_var` / `@instance_eval_self_type`).
      #
      # Anything other than the arity-0 single-statement shape falls
      # through to the previous silent no-op — by design.

      # 1. Basic trampoline: `recv.configure { add 10 }` rebinds self to
      #    the Builder instance, so `add(10)` resolves as Builder#add.
      class Builder
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def total
          @sum
        end

        def configure(&block)
          instance_eval(&block)
        end
      end

      # Inline-at-call-site arity-0 instance-eval trampoline.
      #
      # Full Ruby instance-eval is dynamic — `self` is rebound at runtime,
      # so AOT compilation needs static type information to resolve method
      # dispatch inside the block. Spinel's compromise: detect the exact
      # DSL trampoline shape `def m(&b); instance_eval(&b); end` at compile
      # time, and inline the block body at the call site with `self`
      # rebound to the receiver. Receiverless calls inside the spliced
      # body dispatch to the receiver's class via static type inference
      # (the new `@instance_eval_self_var` / `@instance_eval_self_type`).
      #
      # Anything other than the arity-0 single-statement shape falls
      # through to the previous silent no-op — by design.

      # 1. Basic trampoline: `recv.configure { add 10 }` rebinds self to
      #    the Builder instance, so `add(10)` resolves as Builder#add.
      class Builder
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def total
          @sum
        end

        def configure(&block)
          instance_eval(&block)
        end
      end

      b = Builder.new
      b.configure do
        add(10)
        add(20)
        add(12)
      end
      puts b.total              #=> 42

    RUBY

    _(result).must_answer <<~'OUT'
      42
    OUT
  end

  it "each receiverless call in the block reaches the receiver" do
    result = ze0(<<~'RUBY')
      # Inline-at-call-site arity-0 instance-eval trampoline.
      #
      # Full Ruby instance-eval is dynamic — `self` is rebound at runtime,
      # so AOT compilation needs static type information to resolve method
      # dispatch inside the block. Spinel's compromise: detect the exact
      # DSL trampoline shape `def m(&b); instance_eval(&b); end` at compile
      # time, and inline the block body at the call site with `self`
      # rebound to the receiver. Receiverless calls inside the spliced
      # body dispatch to the receiver's class via static type inference
      # (the new `@instance_eval_self_var` / `@instance_eval_self_type`).
      #
      # Anything other than the arity-0 single-statement shape falls
      # through to the previous silent no-op — by design.

      # 1. Basic trampoline: `recv.configure { add 10 }` rebinds self to
      #    the Builder instance, so `add(10)` resolves as Builder#add.
      class Builder
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def total
          @sum
        end

        def configure(&block)
          instance_eval(&block)
        end
      end

      b = Builder.new
      b.configure do
        add(10)
        add(20)
        add(12)
      end

      # 2. Multiple statements inside the block — each receiverless call
      #    dispatches against the rebound class, including reads.
      class Counter
        def initialize
          @n = 0
        end

        def bump
          @n = @n + 1
        end

        def get
          @n
        end

        def with(&block)
          instance_eval(&block)
        end
      end

      # 2. Multiple statements inside the block — each receiverless call
      #    dispatches against the rebound class, including reads.
      class Counter
        def initialize
          @n = 0
        end

        def bump
          @n = @n + 1
        end

        def get
          @n
        end

        def with(&block)
          instance_eval(&block)
        end
      end

      c = Counter.new
      c.with do
        bump
        bump
        bump
      end
      puts c.get                #=> 3

    RUBY

    _(result).must_answer <<~'OUT'
      3
    OUT
  end

  it "nested trampolines compose, inner receiver inside outer" do
    result = ze0(<<~'RUBY')
      # Inline-at-call-site arity-0 instance-eval trampoline.
      #
      # Full Ruby instance-eval is dynamic — `self` is rebound at runtime,
      # so AOT compilation needs static type information to resolve method
      # dispatch inside the block. Spinel's compromise: detect the exact
      # DSL trampoline shape `def m(&b); instance_eval(&b); end` at compile
      # time, and inline the block body at the call site with `self`
      # rebound to the receiver. Receiverless calls inside the spliced
      # body dispatch to the receiver's class via static type inference
      # (the new `@instance_eval_self_var` / `@instance_eval_self_type`).
      #
      # Anything other than the arity-0 single-statement shape falls
      # through to the previous silent no-op — by design.

      # 1. Basic trampoline: `recv.configure { add 10 }` rebinds self to
      #    the Builder instance, so `add(10)` resolves as Builder#add.
      class Builder
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def total
          @sum
        end

        def configure(&block)
          instance_eval(&block)
        end
      end

      b = Builder.new
      b.configure do
        add(10)
        add(20)
        add(12)
      end

      # 2. Multiple statements inside the block — each receiverless call
      #    dispatches against the rebound class, including reads.
      class Counter
        def initialize
          @n = 0
        end

        def bump
          @n = @n + 1
        end

        def get
          @n
        end

        def with(&block)
          instance_eval(&block)
        end
      end

      c = Counter.new
      c.with do
        bump
        bump
        bump
      end

      # 3. Nested trampolines compose: an outer Builder#configure block
      #    contains an inner Counter#with block. The splicer save/restores
      #    @instance_eval_self_var / @instance_eval_self_type, so the
      #    outer self is restored after the inner block returns.
      b2 = Builder.new
      c2 = Counter.new
      b2.configure do
        add(7)
        c2.with do
          bump
          bump
        end
        add(35)
      end
      puts b2.total             #=> 42
      puts c2.get               #=> 2

    RUBY

    _(result).must_answer <<~'OUT'
      42
      2
    OUT
  end

  it "an ivar read and written inside the block belongs to the receiver" do
    result = ze0(<<~'RUBY')
      # Inline-at-call-site arity-0 instance-eval trampoline.
      #
      # Full Ruby instance-eval is dynamic — `self` is rebound at runtime,
      # so AOT compilation needs static type information to resolve method
      # dispatch inside the block. Spinel's compromise: detect the exact
      # DSL trampoline shape `def m(&b); instance_eval(&b); end` at compile
      # time, and inline the block body at the call site with `self`
      # rebound to the receiver. Receiverless calls inside the spliced
      # body dispatch to the receiver's class via static type inference
      # (the new `@instance_eval_self_var` / `@instance_eval_self_type`).
      #
      # Anything other than the arity-0 single-statement shape falls
      # through to the previous silent no-op — by design.

      # 1. Basic trampoline: `recv.configure { add 10 }` rebinds self to
      #    the Builder instance, so `add(10)` resolves as Builder#add.
      class Builder
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def total
          @sum
        end

        def configure(&block)
          instance_eval(&block)
        end
      end

      b = Builder.new
      b.configure do
        add(10)
        add(20)
        add(12)
      end

      # 2. Multiple statements inside the block — each receiverless call
      #    dispatches against the rebound class, including reads.
      class Counter
        def initialize
          @n = 0
        end

        def bump
          @n = @n + 1
        end

        def get
          @n
        end

        def with(&block)
          instance_eval(&block)
        end
      end

      c = Counter.new
      c.with do
        bump
        bump
        bump
      end

      # 3. Nested trampolines compose: an outer Builder#configure block
      #    contains an inner Counter#with block. The splicer save/restores
      #    @instance_eval_self_var / @instance_eval_self_type, so the
      #    outer self is restored after the inner block returns.
      b2 = Builder.new
      c2 = Counter.new
      b2.configure do
        add(7)
        c2.with do
          bump
          bump
        end
        add(35)
      end

      # 4. Ivar read/write inside the block body. The block body splices
      #    into the call site with `self` rebound, so `@n = ...` must
      #    write the rebound receiver's `iv_n`, not the outer scope's
      #    self. Without @self_override routing, the ivar would resolve
      #    to a toplevel static-global slot -- broken silently because no
      #    prior trampoline test exercises direct ivar access inside the
      #    spliced block (existing tests only call methods like `bump`).
      #    Counter is reused here (two instances above) so value-type
      #    promotion stays disabled; the direct-ivar path needs heap
      #    receivers.
      c3 = Counter.new
      c3.with do
        @n = @n + 5
        @n = @n + 3
      end
      puts c3.get               #=> 8

    RUBY

    _(result).must_answer <<~'OUT'
      8
    OUT
  end

  it "the program runs to the end after the trampolines" do
    result = ze0(<<~'RUBY')
      # Inline-at-call-site arity-0 instance-eval trampoline.
      #
      # Full Ruby instance-eval is dynamic — `self` is rebound at runtime,
      # so AOT compilation needs static type information to resolve method
      # dispatch inside the block. Spinel's compromise: detect the exact
      # DSL trampoline shape `def m(&b); instance_eval(&b); end` at compile
      # time, and inline the block body at the call site with `self`
      # rebound to the receiver. Receiverless calls inside the spliced
      # body dispatch to the receiver's class via static type inference
      # (the new `@instance_eval_self_var` / `@instance_eval_self_type`).
      #
      # Anything other than the arity-0 single-statement shape falls
      # through to the previous silent no-op — by design.

      # 1. Basic trampoline: `recv.configure { add 10 }` rebinds self to
      #    the Builder instance, so `add(10)` resolves as Builder#add.
      class Builder
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def total
          @sum
        end

        def configure(&block)
          instance_eval(&block)
        end
      end

      b = Builder.new
      b.configure do
        add(10)
        add(20)
        add(12)
      end

      # 2. Multiple statements inside the block — each receiverless call
      #    dispatches against the rebound class, including reads.
      class Counter
        def initialize
          @n = 0
        end

        def bump
          @n = @n + 1
        end

        def get
          @n
        end

        def with(&block)
          instance_eval(&block)
        end
      end

      c = Counter.new
      c.with do
        bump
        bump
        bump
      end

      # 3. Nested trampolines compose: an outer Builder#configure block
      #    contains an inner Counter#with block. The splicer save/restores
      #    @instance_eval_self_var / @instance_eval_self_type, so the
      #    outer self is restored after the inner block returns.
      b2 = Builder.new
      c2 = Counter.new
      b2.configure do
        add(7)
        c2.with do
          bump
          bump
        end
        add(35)
      end

      # 4. Ivar read/write inside the block body. The block body splices
      #    into the call site with `self` rebound, so `@n = ...` must
      #    write the rebound receiver's `iv_n`, not the outer scope's
      #    self. Without @self_override routing, the ivar would resolve
      #    to a toplevel static-global slot -- broken silently because no
      #    prior trampoline test exercises direct ivar access inside the
      #    spliced block (existing tests only call methods like `bump`).
      #    Counter is reused here (two instances above) so value-type
      #    promotion stays disabled; the direct-ivar path needs heap
      #    receivers.
      c3 = Counter.new
      c3.with do
        @n = @n + 5
        @n = @n + 3
      end

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      done
    OUT
  end

  it "instance eval unused param" do
    result = ze0(<<~'RUBY')
      # instance_eval/instance_exec with an unused block parameter must still
      # compile: the param gets no C declaration, so its binding is skipped (the
      # exec arg still evaluates for effect).
      p(true.instance_eval { |o| self })
      p(5.instance_eval { |o| self * 2 })
      p("ab".instance_exec(3) { |n| self })
      p(7.instance_eval { |o| o + 1 })
      class W; def initialize; @v = 9; end; def go; instance_eval { |w| @v }; end; end
      p W.new.go
      class U; def initialize; @z = 4; end; def zz; @z; end; end
      u = U.new
      p(u.instance_eval { |o| self.zz })
      p(u.instance_exec(5) { |n| zz })
      p(u.instance_exec(5) { |n| n + zz })
      side = []
      p(1.instance_exec(side << :evaluated) { |a| self })
      p side
      p(true.instance_exec(1, 2) { |a, b| self })
    RUBY

    _(result).must_answer <<~'OUT'
      true
      10
      "ab"
      8
      9
      4
      4
      9
      1
      [:evaluated]
      true
    OUT
  end

  it "instance_eval and instance_exec run against nil and against a number" do
    result = ze0(<<~'RUBY')
      a001 = (nil.instance_eval { 42 } rescue $!.class); p a001
      a002 = (nil.instance_exec(5) { |y| y } rescue $!.class); p a002
      v = nil.instance_eval { 42 }; p v
      p(nil.instance_exec(7) { |x| x * 2 })
      p 5.instance_eval { 10 }
      p "hi".instance_exec(3) { |n| n * 2 }
      p nil.instance_exec(1, 2) { |a, b| a + b }
      p 5.instance_eval { self }
    RUBY

    _(result).must_answer <<~'OUT'
      42
      5
      42
      14
      10
      6
      3
      5
    OUT
  end

  it "iter bound evaluated once" do
    result = ze0(<<~'RUBY')
      $n = 0
      def nxt; $n += 1; $n; end
      def lim; $n += 1; 3; end

      $n = 0; a = []; nxt.times { |i| a << i }; p [a, $n]
      $n = 0; a = []; lim.times { |i| a << i }; p [a, $n]
      $n = 0; a = []; 1.upto(lim) { |i| a << i }; p [a, $n]
      $n = 0; a = []; 5.downto(lim) { |i| a << i }; p [a, $n]
      $n = 0; a = []; (1..lim).each { |i| a << i }; p [a, $n]
      $n = 0; a = []; (1...lim).each { |i| a << i }; p [a, $n]
      $n = 0; a = []; 1.step(lim, 1) { |i| a << i }; p [a, $n]
      $n = 0; a = []; while a.size < lim; a << a.size; end; p [a, $n]
      $n = 0; a = []; (1..3).each { |i| a << lim }; p [a, $n]
      $n = 0; a = []; b = [1,2,3]; b.each { |i| a << i }; p [a, $n]
      $n = 0; a = []; lim.downto(1) { |i| a << i }; p [a, $n]
    RUBY

    _(result).must_answer <<~'OUT'
      [[0], 1]
      [[0, 1, 2], 1]
      [[1, 2, 3], 1]
      [[5, 4, 3], 1]
      [[1, 2, 3], 1]
      [[1, 2], 1]
      [[1, 2, 3], 1]
      [[0, 1, 2], 4]
      [[3, 3, 3], 3]
      [[1, 2, 3], 0]
      [[3, 2, 1], 1]
    OUT
  end

  it "iter recv evaluated once" do
    result = ze0(<<~'RUBY')
      # A fused loop must evaluate its receiver expression once, not once per
      # iteration: re-running a call mid-loop re-reads whatever it returns, so
      # `Dir.children(dir).each` deleting entries used to skip half of them.
      $n = 0
      def src
        $n += 1
        [1, 2, 3]
      end

      def chk(label)
        $n = 0
        yield
        puts "#{label} #{$n}"
      end

      chk("each") { src.each { |x| x } }
      chk("each_with_index") { src.each_with_index { |x, i| x } }
      chk("reverse_each") { src.reverse_each { |x| x } }
      chk("zip") { src.zip(src) { |a, b| a } }
      chk("map") { src.map { |x| x } }
      chk("select") { src.select { |x| x > 1 } }
      chk("each_slice") { src.each_slice(2) { |a| a } }
      chk("each_cons") { src.each_cons(2) { |a| a } }

      # a directory listing is a snapshot: deleting inside the block still visits
      # every entry the call returned
      root = "/tmp/spinel_iter_recv_once_t"
      Dir.mkdir(root) unless Dir.exist?(root)
      File.write("#{root}/a.txt", "a")
      File.write("#{root}/b.txt", "b")
      File.write("#{root}/c.txt", "c")
      visited = []
      Dir.children(root).each do |name|
        visited << name
        File.delete("#{root}/#{name}")
      end
      puts visited.sort.inspect
      puts Dir.children(root).sort.inspect
      Dir.rmdir(root)
    RUBY

    _(result).must_answer <<~'OUT'
      each 1
      each_with_index 1
      reverse_each 1
      zip 2
      map 1
      select 1
      each_slice 1
      each_cons 1
      ["a.txt", "b.txt", "c.txt"]
      []
    OUT
  end

  it "output args eval before write" do
    result = ze0(<<~'RUBY')
      # puts / print / p evaluate every argument before writing any.
      def a; puts "eval-a"; 1; end
      def b; puts "eval-b"; 2; end
      p a, b
      puts a, b
      print a, b
      puts
      begin
        puts 1, 2, (raise "x")
      rescue
        puts "rescued: nothing printed before"
      end
      i = 0
      puts (i += 1), (i += 1), (i += 1)
      p i, (i = 10), i
      def z = 0
      puts [], z
      puts [1, []], z
      puts *[[]]
      puts *[]
      arr = [1, 2]
      puts *arr, z
      p *arr, z
      print *arr, z
      puts
      x = puts("a", "b".upcase)
      p x

      # an argument whose emitter hoists setup into the statement prelude (a call
      # on a user-class receiver) still evaluates in argument order
      require "set"
      st = Set[1]
      p st.size, st.add(2).size, st.size
      class Counter
        def initialize; @n = 0; end
        def bump; @n += 1; self; end
        def n; @n; end
      end
      c = Counter.new
      p c.n, c.bump.n, c.n
      puts c.n, c.bump.n
      n = 0
      p n, (n += 1), n
      a = [1]
      p a.size, a.push(2).size
      h = { a: 1 }
      p h.size, h.store(:b, 2), h.size
    RUBY

    _(result).must_answer <<~'OUT'
      eval-a
      eval-b
      1
      2
      eval-a
      eval-b
      1
      2
      eval-a
      eval-b
      12
      rescued: nothing printed before
      1
      2
      3
      3
      10
      10
      0
      1
      0

      1
      2
      0
      1
      2
      0
      120
      a
      B
      nil
      1
      2
      2
      0
      1
      1
      1
      2
      0
      1
      1
      1
      2
      1
      2
      2
    OUT
  end

  it "per object singleton body runs its leftovers in a class eval" do
    result = ze0(<<~'RUBY')
      # `class << obj` had a fixed list of statements it could map, and rejected the
      # rest. The rejected shape is the same one `class << self` had: a statement
      # whose BLOCK reaches for `self`, which no receiver rewrite can rebind.
      #
      # `class << self` gets a compile-time class for this. A PER-OBJECT singleton
      # has none -- so the escape is the runtime one, `recv.singleton_class.class_eval`,
      # whose `self` IS that class. That is ruby's own primitive, not a paraphrase.
      obj = Object.new
      class << obj
        [:a, :b].each do |name|
          define_method(name) { "runtime:#{name}" }
        end
        def plain = :plain
      end
      p obj.a
      p obj.b
      p obj.plain

      # Reflection cannot tell the two apart, and they keep source order.
      p obj.singleton_methods.sort
      p obj.singleton_class.instance_methods(false).sort

      # A statement that only NAMES `self` needs no runtime body at all -- the `self`
      # just has to evaluate to the singleton class. google_drive spells its
      # `get_singleton_class` helper exactly this way.
      def get_singleton_class(o)
        class << o
          return self
        end
      end
      x = Object.new
      p get_singleton_class(x) == x.singleton_class

      # `class << Const` on a CLASS installs class methods, and a statically compiled
      # `def self.x` beside it survives.
      module Enc
        def self.encode(v) = "enc:#{v}"
      end
      class Null
        class << self
          def passthru(v) = v
        end
      end
      class << Null
        Enc.singleton_methods.each do |m|
          define_method(m, Enc.method(m).to_proc)
        end
      end
      p Null.encode("q")
      p Null.passthru(:kept)

      # The block's `self` is the singleton class, so a receiverless send inside it
      # targets the singleton too -- treetop's `included_modules - Object.included_modules`
      # is 101 corpus rows of this.
      module Marker; end
      target = Object.new
      target.extend(Marker)
      class << target
        (included_modules - Object.included_modules).each do |m|
          define_method(:"from_#{m}") { m.to_s }
        end
      end
      p target.from_Marker

      # A statement with no `self` under it still runs unchanged, at its position.
      $order = []
      sink = Object.new
      class << sink
        $order << :before
        [:late].each { |n| define_method(n) { n } }
        $order << :after
      end
      p $order
      p sink.late
    RUBY

    _(result).must_answer <<~'OUT'
      "runtime:a"
      "runtime:b"
      :plain
      [:a, :b, :plain]
      [:a, :b, :plain]
      true
      "enc:q"
      :kept
      "Marker"
      [:before, :after]
      :late
    OUT
  end

  it "protected reach from instance eval" do
    result = ze0(<<~'RUBY')
      # `protected` asks whether the CALLER's `self` is a kind of the method's owner.
      # zeo answers that from the class the call SITE sits in -- a compile-time
      # constant baked into the site (`codegen::call::visibility::caller_class`,
      # recorded in the `CallSite`) -- so anything that changes `self` at RUN time
      # without changing the enclosing class is invisible to it.
      #
      # `instance_eval` and `instance_exec` are the whole population: the block's
      # `self` becomes the receiver, so ruby lets it reach that receiver's protected
      # methods, while zeo still sees the class the block was WRITTEN in.
      #
      # Fix shape: the caller class is the only compile-time input to
      # `dispatch::explicit_call_barrier`. A block that `instance_eval` re-homes
      # would have to carry its runtime `self`'s class to the sites inside it --
      # either by passing it (a per-call cost on the hot dynamic path, which is why
      # the class rides in the CallSite today) or by compiling such blocks against an
      # unknown caller and letting those sites ask at run time.

      class Acct
        protected def balance = 42
      end

      a = Acct.new
      b = Acct.new

      # The ordinary shape works: the call site sits inside Acct.
      class Acct
        def richer?(other) = balance > other.balance
      end
      p a.richer?(b)

      # ...and this one does not, though ruby allows it.
      begin
        p a.instance_eval { b.balance }
      rescue NoMethodError => e
        puts e.message
      end

      begin
        p a.instance_exec { b.balance }
      rescue NoMethodError => e
        puts e.message
      end

      # A non-kin `self` is refused either way, which is the half that already agrees.
      begin
        p Object.new.instance_eval { b.balance }
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      42
      42
      protected method 'balance' called for an instance of Acct
    OUT
  end

  it "resolves builtin class and module constants" do
    result = ze0(<<~'RUBY')
      puts eval("Integer".dup)
      puts eval("Math::PI".dup).round(2)
      puts eval("Math.sqrt(81)".dup)
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      3.14
      9.0
    OUT
  end

  it "resolves user constants and classes" do
    result = ze0(<<~'RUBY')
      FOO = 42
      class Widget; end
      puts eval("FOO".dup)
      puts eval("Widget".dup)
    RUBY

    _(result).must_answer "42\nWidget\n"
  end

  it "runtime eval defines classes and modules" do
    result = ze0(<<~'PROGRAM')
      # `class`/`module` bodies inside eval: a fresh class with initialize+ivars,
      # a subclass whose method calls `super`, a module function, reopening a
      # compiled class, and the class expression's value. Non-literal source ->
      # the runtime `eval` entry. Oracle-verified verbatim.

      code = <<~RUBY
        class Point
          def initialize(x, y)
            @x = x
            @y = y
          end
          def sum
            @x + @y
          end
        end
      RUBY
      eval(code)
      p Point.new(3, 4).sum
      eval("class Base; def kind; \"base\"; end; end; class Sub < Base; def kind; \"sub:\" + super; end; end")
      p Sub.new.kind
      eval("module Helpers; def self.double(n); n * 2; end; end")
      p Helpers.double(21)
      class Widget
        def base; 1; end
      end
      eval("class Widget; def extra; base + 10; end; end")
      p Widget.new.extra
      p eval("class Empty; 99; end")
    PROGRAM

    _(result).must_answer <<~'OUT'
      7
      "sub:base"
      42
      11
      99
    OUT
  end

  it "singleton body inside an eval keeps its end" do
    result = ze0(<<~'RUBY')
      # A class body inside an `eval` runs as one more `class_eval` of its own
      # SOURCE TEXT, recovered by slicing the snippet -- and the slice runs to the
      # CLASS's own `end`, not to its last statement.
      #
      # `class << self` is not a statement: `lower::defs` SPLICES it into the
      # enclosing class body as an empty surrogate reopen carrying the keyword's
      # span, then the retagged `def`s carrying theirs. So the last statement stops
      # short of the `end` that closes the singleton body, and prism reported an
      # unterminated `class`.
      #
      # The class node's own span ends past its `end` keyword, which is the one
      # thing that says where the body really stops. Checked before it is used --
      # the three bytes really are `end`, and they really are past the last
      # statement -- so a body whose statements analyze REWROTE (an `FFI::Struct`'s
      # synthesized accessors) still takes the other path.

      eval <<~SRC
        class SelfSing
          class << self
            def hi = "class method"
          end
          def inst = "instance"
        end
      SRC
      p [SelfSing.hi, SelfSing.new.inst]

      # An `attr_accessor` in the singleton body, which is what the shape is
      # normally written for.
      eval <<~SRC
        class Configured
          def a = 1
          class << self
            attr_accessor :cfg
          end
        end
      SRC
      Configured.cfg = 5
      p [Configured.cfg, Configured.new.a]

      # `class << obj` was never affected, and neither was a module's.
      o = Object.new
      eval <<~SRC
        class << o
          def only = "obj"
        end
      SRC
      p o.only

      eval <<~SRC
        module Meta
          class << self
            def mm = "module meta"
          end
        end
      SRC
      p Meta.mm

      # An ordinary body still slices to the same place.
      eval <<~SRC
        class Plain
          A = 1
          def b = A
        end
      SRC
      p Plain.new.b
    RUBY

    _(result).must_answer <<~'OUT'
      ["class method", "instance"]
      [5, 1]
      "obj"
      "module meta"
      1
    OUT
  end

  it "string class eval reads the locals of the method it stands in" do
    result = ze0(<<~'RUBY')
      # A class_eval, module_eval or instance_eval of a string reads and writes
      # the locals of the method it stands in, as eval does; the gem's heredoc
      # form names a local the string never assigns.
      module M; end

      def attach(mod)
        invoker = 42
        mod.module_eval <<-code, __FILE__, __LINE__
          @v = invoker
          def self.v = @v
        code
        mod.v
      end

      def sums(mod)
        x = 1
        mod.class_eval("x += 1")
        Object.new.instance_eval("x += 10")
        x
      end

      p attach(M)
      p sums(M)
      p M.module_eval("[self, __LINE__]", "f.rb", 7)

    RUBY

    _(result).must_answer <<~'OUT'
      42
      12
      [M, 7]
    OUT
  end

  it "toplevel binding constant" do
    result = ze0(<<~'RUBY')
      # TOPLEVEL_BINDING is a global constant from boot: self = main, cref Object.
      p Object.constants.include?(:TOPLEVEL_BINDING)
      p TOPLEVEL_BINDING.class
      p TOPLEVEL_BINDING.receiver.to_s

      x = 42
      p TOPLEVEL_BINDING.local_variable_defined?(:x)
      p TOPLEVEL_BINDING.local_variable_get(:x)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Binding
      "main"
      true
      42
    OUT
  end

  it "toplevel binding is mains own" do
    result = ze0(<<~'RUBY')
      # `TOPLEVEL_BINDING` IS the top-level frame's binding. It is installed
      # unconditionally so `Object.constants` lists it, but naming it anywhere in
      # the program -- including from inside a required library's method, which is
      # how erb reaches it -- is what deoptimizes the top level to cells so the
      # binding has locals to report.
      #
      # NOTE: `Object.const_source_location(:TOPLEVEL_BINDING)` is `["<main>", 0]`
      # in ruby. Not pinned here.

      top_a = 1
      top_b = "two"

      p TOPLEVEL_BINDING.class
      p Object.constants.include?(:TOPLEVEL_BINDING)
      p TOPLEVEL_BINDING.receiver
      p TOPLEVEL_BINDING.local_variables.sort
      p TOPLEVEL_BINDING.local_variable_get(:top_a)
      p TOPLEVEL_BINDING.eval("top_a.to_s + top_b")

      # It is main's frame, so a write through it lands there.
      TOPLEVEL_BINDING.local_variable_set(:top_a, 42)
      p top_a

      # ...and reaching it from inside a method still names main's frame, not the
      # method's.
      def from_a_method
        local_to_method = :hidden
        [TOPLEVEL_BINDING.local_variables.include?(:local_to_method),
         TOPLEVEL_BINDING.local_variables.include?(:top_b)]
      end
      p from_a_method

      # The same object every time.
      p TOPLEVEL_BINDING.equal?(TOPLEVEL_BINDING)
    RUBY

    _(result).must_answer <<~'OUT'
      Binding
      true
      main
      [:top_a, :top_b]
      1
      "1two"
      42
      [false, true]
      true
    OUT
  end
  it "walks past a builtin to the scope that wrote the eval" do
    result = ze0(<<~'RUBY')
      x = 41

      # A Method object's `call` stands between the eval and the scope
      # that wrote it, and it has no locals, no cref and no block to
      # lend. ruby walks out to the nearest frame written in ruby
      # (rb_vm_get_ruby_level_next_cfp), so the eval still reads `x`;
      # ze0 read the builtin's frame and raised NameError.
      p method(:eval).call("x + 1")

      def inner
        y = 7
        method(:eval).call("y * 2")
      end
      p inner

      # A block frame is written in ruby, so the walk stops there.
      p [2, 3].map { |i| method(:eval).call("x + i") }

      # `self` is the receiver the Method carries, not the frame's.
      p method(:eval).call("self")
      p 7.method(:instance_eval).call("self + 1")
      p String.method(:class_eval).call("def shout = upcase; :defined")
      p "hi".shout

      # The eval's own frame is labelled for the frame it took its
      # scope from, and the rows below it name what it came through.
      begin
        method(:eval).call("raise 'boom'")
      rescue => e
        puts e.backtrace.first(3).map { |row| row.split(":in ").last }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      42
      14
      [43, 44]
      main
      8
      :defined
      "HI"
      '<main>'
      'Kernel#eval'
      'Method#call'
    OUT
  end
end
