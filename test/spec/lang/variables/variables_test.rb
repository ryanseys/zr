# frozen_string_literal: true

require "spec_helper"

describe "Variables programs" do
  it "arg assigned in sequence" do
    result = ze0(<<~'RUBY')
      # A call whose pointer argument is a bare variable assigned earlier in the SAME
      # sequence-expression the call belongs to: the argument must be read at the call
      # (after the in-sequence assignment), not hoisted above it. Regression: the arg
      # was rooted into a statement-prelude temp captured before `a = {...}` ran, so
      # the callee received a stale (empty) hash and every lookup blanked.
      def render(h)
        h["name"]
      end
      def handle
        "" + ((a = {"z" => "z"}; a.delete("z"); a["name"] = "world"; render(a)))
      end
      puts "[" + handle + "]"

      # statement form (already worked) stays correct
      def handle2
        a = {"k" => "v"}
        a["name"] = "ok"
        "" + render(a)
      end
      puts handle2
    RUBY

    _(result).must_answer "[world]\nok\n"
  end

  it "assignment rescue modifier" do
    result = ze0(<<~'RUBY')
      class TopRisk
        def risky_top
          raise "bad"
        end
      end
      x = TopRisk.new.risky_top rescue "fallback"
      puts x
    RUBY

    _(result).must_answer "fallback\n"
  end

  it "backref globals are frame local" do
    result = ze0(<<~'RUBY')
      # CRuby scopes $~ (and so $1/$&/$`/$') per method frame (the svar slot on the
      # frame): a match inside a called method never touches the caller's backrefs.
      # zeo stores one process-global last-match, so the callee's match leaks out.
      # Second half: String#scan must SET $~ to its last match; zeo's scan leaves
      # the global untouched.
      "hello world" =~ /(w\w+)/
      puts $1.inspect

      def match_inside
        "abc" =~ /(b)/
        $1
      end

      puts match_inside.inspect
      puts $1.inspect
      puts $~[0].inspect

      nums = "a1b2c3".scan(/\d/)
      puts nums.inspect
      puts $~[0].inspect

      [1].each do
        "block shares the method frame" =~ /(shares)/
      end
      puts $1.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "world"
      "b"
      "world"
      "world"
      ["1", "2", "3"]
      "3"
      "shares"
    OUT
  end

  it "bigint local in int slot" do
    result = ze0(<<~'RUBY')
      # A counter the analysis widens to Bignum (repeated doubling) still has to
      # work where an integer is wanted: an index, a count, a slice bound.
      n = 10
      a = Array.new(n) { |i| i * 10 }
      k = 1
      while k < 4
        k *= 2
      end
      p k
      p a[k]
      p a[(3 + k) % n]
      p a[k, 2]
      p a.first(k)
      s = "abcdefghij"
      p s[k]
      p s[k, 3]
      acc = 0
      k.times { |i| acc += i }
      p acc
      p Array.new(k, 7)
    RUBY

    _(result).must_answer <<~'OUT'
      4
      40
      70
      [40, 50]
      [0, 10, 20, 30]
      "e"
      "efg"
      6
      [7, 7, 7, 7]
    OUT
  end

  it "box globals are fully separate" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # Gvar isolation is BIDIRECTIONAL (separate per-box tables, no fallback):
      # a box reads nil for main's `$g`, and a box's write never reaches main.



      $g = "main value"
      box = Ruby::Box.new
      p box.eval("$g")
      box.eval("$g = 'box value'")
      p $g
      p box.eval("$g")
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "main value"
      "box value"
    OUT
  end

  it "break in a non lambda proc call raises local jump error" do
    result = ze0(<<~'RUBY')
      # `break` inside an explicitly created proc invoked via `#call` has no
      # iterator to unwind to, so CRuby raises LocalJumpError (`#reason`
      # `:break`) -- even while the creating iterator is still live. A lambda's
      # `break`, by contrast, just returns from the lambda.

      p(-> { break 9 }.call)
      def orphan; proc { break 1 }; end
      begin
        orphan.call
      rescue LocalJumpError => e
        puts "#{e.message} / #{e.reason.inspect}"
      end
      [1, 2].each do |x|
        pr = proc { break :pb }
        begin
          pr.call
        rescue LocalJumpError => e
          puts "live: #{e.message}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      9
      break from proc-closure / :break
      live: break from proc-closure
      live: break from proc-closure
    OUT
  end

  it "callers locals are the evals locals" do
    result = ze0(<<~'RUBY')
      n = 20
      src = "n * 3"
      p eval(src)
      write = "n = 7"
      eval(write)
      p n
    RUBY

    _(result).must_answer "60\n7\n"
  end

  it "case in hash pattern shorthand binds local named after key" do
    result = ze0(<<~'RUBY')
      h = { name: 1 }
      case h
      in { name: }
        puts name
      end
    RUBY

    _(result).must_answer "1\n"
  end

  it "case when poly scrutinee bound to local" do
    result = ze0(<<~'RUBY')
      # `case v when X then ... end` bound to a local via `r = ...`
      # pre-fix emitted two C temps: a result temp (typed from the
      # branch values) and a scrutinee temp (used inside
      # `sp_class_for_poly(...)`). The scrutinee temp wrongly inherited
      # the result type. For a poly scrutinee with int result, the
      # emit produced `mrb_int _t2 = lv_v;` (a value-conversion that
      # discards the sp_RbVal struct), then `sp_class_for_poly(_t2)`
      # failed C compile because the helper expects sp_RbVal.
      #
      # Fix: the scrutinee temp picks its C type from the predicate's
      # inferred type (not from the case-result type). Added a `poly`
      # arm to compile_expr's CaseNode emit so `sp_RbVal _t2 = lv_v;`
      # lands correctly. The compile_case_stmt sibling arm gains
      # concrete `range` / `time` / `float` / `bool` arms too so a
      # tail-position `case <range>` doesn't fall to the int default.
      # Issue #604.

      def classify(v)
        r = case v when Range then 1 end
        r
      end
      puts classify(200..299)             # 1 (Range matches)
      puts classify(404)                  # 0 (no when match -> default 0)

      # Case-when result bound to local with mixed branches and poly scrutinee.
      def label(v)
        r = case v
            when Range   then "range"
            when Integer then "int"
            else "other"
            end
        r
      end
      puts label(200..299)                # range
      puts label(404)                     # int
      puts label("hi")                    # other
    RUBY

    _(result).must_answer <<~'OUT'
      1

      range
      int
      other
    OUT
  end

  it "celled op assign types" do
    result = ze0(<<~'RUBY')
      # `x op= v` on a local captured by a proc must take the same typed arm as an
      # uncaptured one. The celled path used to carry its own short list of arms and
      # sent every other type through the int helpers.
      def acc(init, a, b)
        s = init
        f = proc { |x| s += x }
        f.call(a)
        f.call(b)
        s
      end

      p acc("", "a", "b")
      p acc([1], [2], [3])
      p acc(["a"], ["b"], ["c"])
      p acc(0, 3, 4)
      p acc(0.0, 1.5, 2.5)
      p acc(Rational(1, 2), Rational(1, 3), Rational(1, 6))
      p acc(Complex(1, 2), Complex(3, 4), Complex(5, 6))

      # the shape that first surfaced it: one poly param reached by both an Array and
      # a user class, so the block became a real proc and the accumulator a cell.
      class Bag
        def initialize(a) = @a = a
        def each(&b) = @a.each(&b)
      end

      def joined(list)
        s = ""
        list.each { |x| s += x.to_s }
        s
      end

      p joined([1, 2])
      p joined(Bag.new([3, 4]))
    RUBY

    _(result).must_answer <<~'OUT'
      "ab"
      [1, 2, 3]
      ["a", "b", "c"]
      7
      4.0
      (1/1)
      (9+12i)
      "12"
      "34"
    OUT
  end

  it "class method dispatches dynamically through a class valued variable" do
    result = ze0(<<~'RUBY')
      # The receiver isn't a literal constant, so codegen can't emit a direct
      # `H1::__cm_run(...)` -- it goes through the registry's class-method
      # table on a `RubyValue::Class` receiver.

      class H1
        def self.run(x); "h1:#{x}"; end
      end
      class H2
        def self.run(x); "h2:#{x}"; end
      end
      [H1, H2].each { |h| puts h.run(5) }
      handler = H1
      puts handler.run(9)
      handler = H2
      puts handler.run(9)
    RUBY

    _(result).must_answer <<~'OUT'
      h1:5
      h2:5
      h1:9
      h2:9
    OUT
  end

  it "class own method shadows an included module method" do
    result = ze0(<<~'RUBY')
      module Greetable
        def greet
          "hi"
        end
      end
      class Person
        include Greetable
        def greet
          "overridden"
        end
      end
      class Robot
        include Greetable
      end
      puts Person.new.greet
      puts Robot.new.greet
    RUBY

    _(result).must_answer "overridden\nhi\n"
  end

  it "class stored in a variable constructs and dispatches" do
    result = ze0(<<~'RUBY')
      class Widget
        def initialize(n)
          @n = n
        end

        def n
          @n
        end
      end

      x = Widget
      puts x.new(5).n
      puts x.name
    RUBY

    _(result).must_answer "5\nWidget\n"
  end

  it "compound assignment on a frozen array raises after the read" do
    result = ze0(<<~'RUBY')
      # `d[0] += 1` desugars to a read (fine on a frozen array) then a `[]=`
      # (raises) -- real Ruby's own order.

      d = [1]
      d.freeze
      begin
        d[0] += 1
      rescue FrozenError => e
        puts e.send(:message)
      end
    RUBY

    _(result).must_answer "can't modify frozen Array: [1]\n"
  end

  it "compound assignment on a plain non class constant dispatches correctly" do
    result = ze0(<<~'RUBY')
      # A real, previously-undetected bug, found alongside the `||=` fix
      # above: the compiler's call lowering treated ANY `HirNode::ClassRef`
      # receiver as a `ClassName.foo(...)` class-method call, UNCONDITIONALLY
      # -- but `ClassRef` is also how an ordinary bare constant read lowers
      # (see its own docs). So `MAX += 1` (desugared to `MAX.+(1)`, where
      # `MAX` is a plain `Integer` constant, not a class) panicked with a
      # confusing "unknown class/module `MAX`" instead of reading/writing
      # its actual value -- EVERY compound-assignment operator except `||=`
      # on any non-class constant was completely broken. Fixed by only
      # taking the class-method-call branch when the name is ACTUALLY a
      # registered class/module.

      MAX = 100
      MAX += 1
      puts MAX
      MAX -= 50
      puts MAX
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      101
      51
    OUT
      lang/variables/variables_test.rb:14: warning: already initialized constant MAX
      lang/variables/variables_test.rb:13: warning: previous definition of MAX was here
      lang/variables/variables_test.rb:16: warning: already initialized constant MAX
      lang/variables/variables_test.rb:14: warning: previous definition of MAX was here
    ERR
  end

  it "compound assignment on an attribute evaluates the receiver exactly once" do
    result = ze0(<<~'RUBY')
      class Box
        attr_accessor :n
        def initialize
          @n = 0
        end
      end
      class Tracker
        attr_reader :calls
        def initialize(box)
          @box = box
          @calls = 0
        end
        def get
          @calls += 1
          @box
        end
      end

      b = Box.new
      t = Tracker.new(b)
      t.get.n += 5
      puts b.n
      puts t.calls
    RUBY

    _(result).must_answer "5\n1\n"
  end

  it "condition variable wait signal and broadcast coordinate threads" do
    result = ze0(<<~'RUBY')
      # signal/broadcast return self; wait releases the mutex, parks the thread
      # until broadcast, then re-acquires. The handoff is deterministic via the
      # shared `ready` flag under the mutex.

      cv = ConditionVariable.new
      puts cv.signal.equal?(cv)
      puts cv.broadcast.equal?(cv)
      # a lone wait with a timeout returns (does not hang)
      m0 = Mutex.new
      m0.synchronize { cv.wait(m0, 0.01) }
      puts "timeout-ok"

      mutex = Mutex.new
      ready = false
      worker = Thread.new do
        mutex.synchronize do
          cv.wait(mutex) until ready
        end
        puts "woke"
      end
      mutex.synchronize do
        ready = true
        cv.broadcast
      end
      worker.join
      puts "joined"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      timeout-ok
      woke
      joined
    OUT
  end

  it "cvar cref" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # `@@x` resolves against the LEXICAL cref, and only a `class`/`module`
      # body opens one. Outside any of them ruby raises where the access
      # stands, so a compile that cannot name an owner answers the raise rather
      # than refusing the program.
      #
      # A name-taking macro spreads a `*` splat of a written Array, which is how
      # `attr_reader(*%i[a b])` and `private(*names)` are written.

      class Counted
        @@count = 0
        attr_accessor(*%i[tag note])
        def self.bump = @@count += 1
        def count = @@count
        def defined_count = defined?(@@count)
        def defined_other = defined?(@@nowhere)
      end
      Counted.bump
      p Counted.new.count
      p Counted.class_variables

      # Reopening Object explicitly IS a cref, so this stores.
      class Object
        @@on_object = 1
      end
      p Object.class_variables.include?(:@@on_object)

      def raised
        yield
        "no raise"
      rescue RuntimeError => e
        e.message
      end

      p raised { @@toplevel_read }
      p raised { @@toplevel_write = 1 }
      p raised { @@toplevel_op ||= 1 }
      p raised { Class.new { @@in_class_new = 1 } }

      # `defined?` never evaluates its operand, so it answers nil rather than
      # raising -- and inside a body it asks the run time.
      p defined?(@@never_assigned)
      p [Counted.new.defined_count, Counted.new.defined_other]

      # The right-hand side has already run by the time the raise fires.
      ran = nil
      p raised { @@late = (ran = :ran) }
      p ran

      class Visible
        def one = 1
        def two = 2
        private(*[:one, :two])
        class << self
          def hidden = :hidden
          private :hidden
          public(*%i[hidden])
        end
      end
      p Visible.private_instance_methods(false).sort
      p Visible.hidden
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [:@@count]
      true
      "class variable access from toplevel"
      "class variable access from toplevel"
      "class variable access from toplevel"
      "class variable access from toplevel"
      nil
      ["class variable", nil]
      "class variable access from toplevel"
      :ran
      [:one, :two]
      :hidden
    OUT
  end

  it "deeply nested dynamic blocks share locals through capture cells" do
    result = ze0(<<~'RUBY')
      # bm_ao_render's shape: `.times` on an UNTYPED receiver makes every
      # level a real escaping Proc, and the innermost block both assigns its
      # own local (`vf`) and reads outer block params. The mid-chain block
      # used to panic ("capturing its enclosing BLOCK's own local") because
      # the guard ran before the nested-capture cell machinery classified
      # the name; it now recognizes a deeper block's own local. The
      # accumulator (`rad`) round-trips through three closure levels via its
      # cell. Output oracle-verified.

      def render(n)
        n.times do |x|
          rad = 0.0
          n.times do |v|
            n.times do |u|
              vf = v.to_f
              rad = rad + vf + u.to_f
            end
          end
          puts rad
        end
      end
      render(2)
    RUBY

    _(result).must_answer "4.0\n4.0\n"
  end

  it "defined asks every part as written" do
    result = ze0(<<~'RUBY')
      # `defined?` asks about each part as it is written. A call with any
      # receiver, `self` among them, is asked as an explicit call, so a private
      # method -- a private writer too -- is not there; a writer that is, is a
      # "method". An Array or a Hash literal is defined only when every part of
      # it is, and parentheses ask about what they hold.
      class K
        def pub = 1

        def run
          [defined?(self.priv), defined?(priv), defined?(self.prot), defined?(prot), defined?(self.w = 1), defined?(self.pw = 1),
           defined?(K.new.prot), defined?(K.new.priv), defined?(self.pub), defined?(self[1] = 2)]
        end

        def w=(v); end
        def []=(k, v); end

        private

        def priv = 1
        def pw=(v); end

        protected

        def prot = 1
      end
      p K.new.run

      o = K.new
      p defined?(o.w = 1), defined?(o[1] = 2), defined?(o.pw = 1), defined?(o.zz = 1)
      p defined?([1, [2, Nope]]), defined?([1, [2, Array]]), defined?([]), defined?([@zz]), defined?([$zzz]), defined?([nope_m])
      p defined?(1.+(Nope)), defined?(puts(Nope)), defined?(String.new(Array))
      a = [1]
      p defined?([*a])
      p defined?({a: 1}), defined?({a: Nope}), defined?({Nope => 1}), defined?({**Nope}), defined?({a: nope_m})
      x = 1
      p defined?([{a: Nope}]), defined?({x:}), defined?([{**{b: 1}}]), defined?({a: [Nope]})
      p defined?("#{Nope}"), defined?(1..Nope), defined?(!Nope), defined?(Nope && 1), defined?((Nope)), defined?((String))
      p defined?(x = Nope), defined?(@a ||= 1), defined?((c, d = 1, 2))

    RUBY

    _(result).must_answer <<~'OUT'
      [nil, "method", "method", "method", "method", nil, "method", nil, "method", "method"]
      "method"
      "method"
      nil
      nil
      nil
      "expression"
      "expression"
      nil
      nil
      nil
      nil
      nil
      "method"
      "expression"
      "expression"
      nil
      nil
      nil
      nil
      nil
      "expression"
      "expression"
      nil
      "expression"
      "expression"
      nil
      "expression"
      nil
      "constant"
      "assignment"
      "assignment"
      "assignment"
    OUT
  end

  it "defined classifies calls assignments and keyword literals" do
    result = ze0(<<~'RUBY')
      # A method call answers "method" only if the receiver responds; a bare
      # undefined name is nil. Assignments answer "assignment". nil/true/false
      # answer their own name.

      def foo; end
      p defined?(foo)
      p defined?(undefined_zzz)
      p defined?(1 + 2)
      p defined?(1.nope_zzz)
      p defined?(x = 2)
      p defined?(@iv = 3)
      p defined?(nil)
      p defined?(true)
      p defined?(false)
      p defined?(puts)
    RUBY

    _(result).must_answer <<~'OUT'
      "method"
      nil
      "method"
      nil
      "assignment"
      "assignment"
      "nil"
      "true"
      "false"
      "method"
    OUT
  end

  it "defined globals methods" do
    result = ze0(<<~'RUBY')
      # defined? on globals and methods. Methods already returned
      # "method"; globals were returning "expression". CRuby returns
      # "global-variable" for assigned $x but nil for never-assigned
      # globals (the name alone is not "defined" if never written).
      $g = 1
      puts defined?($g)
      puts defined?($unset_gvar)

      def foo; end
      puts defined?(foo)

      # Locals already correct.
      x = 1
      puts defined?(x)
      puts defined?(undefined_local).nil?
    RUBY

    _(result).must_answer <<~'OUT'
      global-variable

      method
      local-variable
      true
    OUT
  end

  it "dir handle argf class and binding local variable get" do
    result = ze0(<<~'RUBY')
      # Dir.new/Dir.open handles (#path/#read/#each/#children/#entries/
      # #rewind/#close, the block form, ENOENT on a missing path), ARGF's
      # literally-named class and default "-" filename with no file args, and
      # binding.local_variable_get(:name) reading an in-scope local (including a
      # reserved-word parameter).

      dir = "/tmp/sp_e2e_dirh_#{Process.pid}"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      File.write("#{dir}/x", "")
      File.write("#{dir}/y", "")
      d = Dir.new(dir)
      p d.class
      p d.path == dir
      names = []
      d.each { |n| names << n }
      p names.sort
      d.rewind
      p d.read.class
      d.close
      r = Dir.open(dir) { |dd| dd.children.sort }
      p r
      p((Dir.new("/nonexistent_zz_e2e") rescue $!.class))
      File.delete("#{dir}/x", "#{dir}/y")
      Dir.rmdir(dir)

      p ARGF.class
      p ARGF.filename

      def read_reserved(then:)
        binding.local_variable_get(:then)
      end
      p read_reserved(then: :tick)
      x = [1, 2, 3]
      p binding.local_variable_get(:x)
    RUBY

    _(result).must_answer <<~'OUT'
      Dir
      true
      [".", "..", "x", "y"]
      String
      ["x", "y"]
      Errno::ENOENT
      ARGF.class
      "-"
      :tick
      [1, 2, 3]
    OUT
  end

  it "earlier i root shadows a later same named stdlib file" do
    files = beside("earlier_root/main.rb",
                "earlier_root/stdliblib/patched.rb",
                "earlier_root/userlib/patched.rb")

    result = ze0(<<~'RUBY', files: files)
      # The documented precedence: `-I` roots are searched in order, first hit
      # wins (Ruby's own `$LOAD_PATH` rule) -- so a user root placed BEFORE the
      # stdlib checkout shadows the stdlib copy of a same-named feature, and the
      # later root's file is never loaded.

      $LOAD_PATH.unshift(File.expand_path("earlier_root/userlib", __dir__))
      $LOAD_PATH.unshift(File.expand_path("earlier_root/stdliblib", __dir__))
      require_relative "earlier_root/main"
    RUBY

    _(result).must_answer "stdlib original\n"
  end

  it "eval locals defined and read within one scope" do
    result = ze0(<<~'RUBY')
      src = "a = 4; b = 5; a * b"; puts eval(src)
    RUBY

    _(result).must_answer "20\n"
  end

  it "eval shares the enclosing local scope" do
    result = ze0(<<~'RUBY')
      x = 1
      eval("x = x + 1")
      puts x
    RUBY

    _(result).must_answer "2\n"
  end

  it "fiber body captures and mutates enclosing locals" do
    result = ze0(<<~'RUBY')
      # The fiber's block goes through the ordinary escaping-Proc capture
      # machinery (Arc<Mutex> cells), so shared mutation across
      # suspension points works exactly like any other escaping block.

      count = 0
      c = Fiber.new do
        count += 10
        Fiber.yield
        count += 100
      end
      c.resume
      puts count
      c.resume
      puts count
    RUBY

    _(result).must_answer "10\n110\n"
  end

  it "fiber rebinding a captured local propagates to the enclosing scope" do
    result = ze0(<<~'RUBY')
      # From the reference project's own regression corpus
      # (fiber_reassign_capture.rb): REBINDING (not just mutating) a captured
      # name inside the fiber must write through the shared cell.

      s = "old"
      f = Fiber.new do
        s = "new"
        Fiber.yield
      end
      f.resume
      puts s
    RUBY

    _(result).must_answer "new\n"
  end

  it "freezing an array makes index assignment raise a catchable frozen error" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 3]
      a.freeze
      begin
        a[0] = 9
      rescue FrozenError => e
        puts e.send(:message)
      end
      puts a[0]
    RUBY

    _(result).must_answer "can't modify frozen Array: [1, 2, 3]\n1\n"
  end

  it "frozen hash assignment raises with the inspect bearing message" do
    result = ze0(<<~'RUBY')
      h = { a: 1 }
      h.freeze
      begin
        h[:b] = 2
      rescue FrozenError => e
        puts e.send(:message)
      end
      puts h.length
    RUBY

    _(result).must_answer "can't modify frozen Hash: {a: 1}\n1\n"
  end

  it "frozen string assignment raises with the quoted inspect message" do
    result = ze0(<<~'RUBY')
      s = "abc"
      s.freeze
      begin
        s[0] = "z"
      rescue FrozenError => e
        puts e.send(:message)
      end
      puts s
    RUBY

    _(result).must_answer <<~'OUT'
      can't modify frozen String: "abc"
      abc
    OUT
  end

  it "global alias shares storage in both directions" do
    result = ze0(<<~'RUBY')
      # `alias $copy $orig` is a real alias, not a copy: one slot, two names,
      # and writing EITHER is visible through the other. Oracle-verified both
      # ways -- which is why it can't lower to `$copy = $orig`.

      $orig = 5
      alias $copy $orig
      $copy = 7
      p $orig
      p $copy
      $orig = 9
      p [$orig, $copy]
      alias $b $never_set
      p $b
      $never_set = 1
      p $b
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      [9, 9]
      nil
      1
    OUT
  end

  it "global var punct" do
    result = ze0(<<~'RUBY')
      # Issue #831: punctuation global variables compile to safe
      # C identifiers. Pre-fix the generated C had `gv_!` / `gv_;` /
      # `gv_,` / `gv_/` etc. which aren't valid C and broke any program
      # that referenced them — including `rescue => e` bodies because
      # the parser implicitly threads `$!` through some shapes.
      puts $!.inspect       # nil outside rescue
      puts $;.inspect       # nil (split-default sep — spinel doesn't honor it)
      puts $,.inspect       # nil (Array#print sep — same)
      puts $/.inspect       # "\n" — the only one with a meaningful default
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      "\n"
    OUT
  end

  it "global variables read write and default to nil" do
    result = ze0(<<~'RUBY')
      $x = 10
      puts $x
      puts $never_set
      $x += 5
      puts $x
    RUBY

    _(result).must_answer <<~'OUT'
      10

      15
    OUT
  end

  it "gsub block form can capture and mutate an enclosing local" do
    result = ze0(<<~'RUBY')
      # Exercises the same real-`Proc`/capture machinery every other escaping
      # block already uses (`emit_proc_value`) -- not a bespoke code path.

      count = 0
      "one two three".gsub(/\w+/) { |w| count += 1; w }
      puts count
    RUBY

    _(result).must_answer "3\n"
  end

  it "gvar" do
    result = ze0(<<~'RUBY')
      # Test global variables
      $count = 0
      $name = "world"

      def increment
        $count = $count + 1
      end

      def greet
        puts "hello " + $name
      end

      increment
      increment
      increment
      puts $count
      greet
      $name = "ruby"
      greet

      $pi = 3.14
      puts $pi
    RUBY

    _(result).must_answer <<~'OUT'
      3
      hello world
      hello ruby
      3.14
    OUT
  end

  it "gvar opassign value" do
    result = ze0(<<~'RUBY')
      # a global-variable operator assignment evaluates to the updated value --
      # as a method's tail (its return value), as a call argument, and inline in
      # an expression. `def tick; $count += 1; end` used to compile tick as void,
      # so callers got nil (or `invalid use of void expression` in an array).

      $count = 0

      def tick
        $count += 1
      end

      p [tick, 10]
      p tick
      x = tick
      p x

      # other numeric operators, and float slots
      $total = 100
      p($total -= 30)
      p($total *= 2)

      $ratio = 1.5
      p($ratio += 0.25)

      # a string global: += concatenates and returns the updated string
      $log = "a"
      def log_append(s)
        $log += s
      end

      p log_append("b")
      p log_append("c")
      p $log

      # inline in a larger expression
      $n = 5
      y = ($n += 3) + 2
      p y
      p $n
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 10]
      2
      3
      70
      140
      1.75
      "ab"
      "abc"
      "abc"
      10
      8
    OUT
  end

  it "hash reassigning an existing key keeps its original insertion position" do
    result = ze0(<<~'RUBY')
      h = {}
      h[:a] = 1
      h[:b] = 2
      h[:c] = 3
      h[:a] = 99
      puts h
    RUBY

    _(result).must_answer "{a: 99, b: 2, c: 3}\n"
  end

  it "indexed assignment value" do
    result = ze0(<<~'RUBY')
      # An assignment expression evaluates to its RIGHT-HAND SIDE, never to what the
      # setter returned. zeo answers the setter's return value.
      #
      # Ruby compiles `recv[i] = v` and `recv.x = v` to a send followed by a pop --
      # the value left on the stack is always `v`, whatever `[]=` or `x=` answered.
      # That is why a setter can `return false` and `h[k] = v` still evaluates truthy,
      # and it is what makes chained assignment (`a = b[0] = 1`) give every target the
      # same value.
      #
      # zeo emits the send and uses its result. For the builtin containers the two
      # agree -- `Array#[]=` answers the value it stored -- so only a USER-defined
      # setter shows the divergence, which is also where it matters most: a DSL whose
      # `[]=` answers `self` for chaining silently changes the meaning of every
      # assignment that uses it.

      # (A setter cannot be written in the endless form -- ruby rejects
      # `def []=(k, v) = ...` outright -- so these carry ordinary bodies.)
      class Store
        def []=(k, v)
          :ignored_return
        end

        def value=(v)
          :also_ignored
        end
      end

      s = Store.new
      p(s[:k] = 42)
      p(s.value = 7)

      x = (s[:k] = "chain")
      p x

      a = b = (s[:k] = 1)
      p [a, b]

      # The builtin path already agrees.
      h = {}
      p(h[:k] = 5)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      7
      "chain"
      [1, 1]
      5
    OUT
  end

  it "is a and kind of against a statically known int local" do
    result = ze0(<<~'RUBY')
      x = 5
      puts x.is_a?(Integer)
      puts x.is_a?(String)
      puts x.is_a?(Object)
      puts x.kind_of?(Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
    OUT
  end

  it "a method whose tail is a subscript assignment answers the value assigned" do
    result = ze0(<<~'RUBY')
      module Slap
        class Flag
          def initialize(kind)
          end

          def takes_param? = nil

          def parse_param(switch, param)
            param
          end
        end

        class Parser
          attr_reader :options
          def initialize
            @options = {}
          end

          def parse_flag(flag, switch, separator, param)
            flag.takes_param?
            options[0] = flag.parse_param(0, param)
          end
        end
      end
      values = [
        true,
        1,
        Slap::Parser.new.parse_flag(Slap::Flag.new(0), 0, 0, "x"),
      ]
      raise "FAIL" unless values == [true, 1, "x"]
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "late ret through local chain" do
    result = ze0(<<~'RUBY')
      # A method that returns another method's value through a local (`a = nxt; a`)
      # was inferred as void when the callee's own return -- also flowing through a
      # local (`r = ...; r`) -- only settled in the post-fixpoint write-type re-run.
      # The re-run typed the locals but never re-derived the returns, so the wrapper
      # stayed at UNKNOWN, emitted as a void C function, and its value was silently
      # dropped (callers read nil / 0.0). The `<<` on the ivar is what delays the
      # ivar's settling past the main fixpoint. Issue #1670.

      class R
        def initialize(s)
          @s0 = s
          @s1 = s + 1
        end

        def nxt
          t = (@s1 << 9) & 0xFFFFFFFF
          @s0 = @s0 ^ @s1
          @s1 = @s1 ^ t
          r = (@s0 + @s1) & 0xFFFFFFFF
          r
        end

        # int result through a local
        def uni_int
          a = nxt
          a
        end

        # float result computed from locals fed by two chained calls
        def uni_float
          a = nxt >> 5
          b = nxt >> 6
          (a * 67108864.0 + b) / 9007199254740992.0
        end
      end

      r1 = R.new(12345)
      x = r1.uni_int
      puts x                            # 6308925

      r2 = R.new(12345)
      puts format("%.10f", r2.uni_float)  # 0.0014689099

      # Result used directly as an argument (was a compile error: "unsupported
      # puts argument" once the wrapper's return degraded to void).
      puts R.new(777).uni_int           # 399117
    RUBY

    _(result).must_answer <<~'OUT'
      6308925
      0.0014689099
      399117
    OUT
  end

  it "load reexecutes every time with fresh locals and never registers the feature" do
    result = ze0(<<~'RUBY', files: beside("load_reexecutes/main.rb", "load_reexecutes/tick.rb"))
      # Three executions: two `load`s plus a `require` -- load never adds to
      # the feature table in real Ruby, so the require still fires. `ticks`
      # restarts at 0 each execution (fresh local scope per load), which the
      # per-splice-instance gensym reproduces.

      Dir.chdir(File.expand_path("load_reexecutes", __dir__))
      require_relative "load_reexecutes/main"
    RUBY

    _(result).must_answer <<~'OUT'
      tick! total=1
      tick! total=2
      tick! total=3
      end total=3
    OUT
  end

  it "local or assign and and assign" do
    result = ze0(<<~'RUBY')
      x = nil
      x ||= 5
      puts x
      y = 1
      y &&= 2
      puts y
    RUBY

    _(result).must_answer "5\n2\n"
  end

  it "local reassigned to a different class still compiles" do
    result = ze0(<<~'RUBY')
      # `local_types` is read flow-insensitively, so a retyped local must
      # widen to Poly rather than let a later class's identifier describe an
      # earlier read.

      class A
        def who = "A"
      end
      class B
        def who = "B"
      end
      x = A.new
      puts x.who
      x = B.new
      puts x.who
      y = 1
      y = "str"
      puts y
    RUBY

    _(result).must_answer <<~'OUT'
      A
      B
      str
    OUT
  end

  it "locals and assignment" do
    result = ze0(<<~'RUBY')
      a = 1
      b = a
      a = a + 1
      puts a
      puts b
      s = "x"
      t = s
      s = s + "y"
      puts s
      puts t
      u = u = 5
      puts u
      c = nil
      p c
      c = "set"
      puts c
      d = (e = 3) + 1
      puts d
      puts e
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      xy
      x
      5
      nil
      set
      4
      3
    OUT
  end

  it "massign nil underflow" do
    result = ze0(<<~'RUBY')
      # Multiple assignment edges: an explicit-nil RHS element, and splat-underflow
      # where post-splat targets run past the available elements (they land nil).
      # Distinct variable names per statement avoid cross-statement type unification.

      # explicit nil element (was a `void` temp build error)
      n1a, n1c = [1, nil]
      p [n1a, n1c]
      n2x, n2y = [nil, nil]
      p [n2x, n2y]
      n3a, n3b, n3c = [1, nil, 3]
      p [n3a, n3b, n3c]

      # a non-literal nil element still runs for its side effects
      def sideff_nil
        puts "side-effect ran"
        nil
      end
      v1a, v1b = [1, sideff_nil]
      p [v1a, v1b]                      # side-effect ran, then [1, nil]

      # splat-underflow: post-splat targets nil-fill left-to-right past the splat
      u1a, *u1b, u1c = [1]
      p [u1a, u1b, u1c]                 # [1, [], nil]
      u2a, *u2b, u2c, u2d = [1, 2]
      p [u2a, u2b, u2c, u2d]            # [1, [], 2, nil]
      u3a, u3b, *u3c, u3d = [1, 2]
      p [u3a, u3b, u3c, u3d]            # [1, 2, [], nil]

      # non-underflow splat still correct
      s1a, *s1b, s1c = [1, 2, 3, 4]
      p [s1a, s1b, s1c]                 # [1, [2, 3], 4]
      s2a, *s2b, s2c, s2d = [1, 2, 3, 4, 5]
      p [s2a, s2b, s2c, s2d]           # [1, [2, 3], 4, 5]
      s3a, s3b, *s3c, s3d = [1, 2, 3, 4, 5]
      p [s3a, s3b, s3c, s3d]           # [1, 2, [3, 4], 5]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, nil]
      [nil, nil]
      [1, nil, 3]
      side-effect ran
      [1, nil]
      [1, [], nil]
      [1, [], 2, nil]
      [1, 2, [], nil]
      [1, [2, 3], 4]
      [1, [2, 3], 4, 5]
      [1, 2, [3, 4], 5]
    OUT
  end

  it "massign pair of object and int" do
    result = ze0(<<~'RUBY')
      # `path << [start, -1]` then `cell, _ = path[id]`. While the fixpoint runs,
      # `start` has no type yet and the literal reads as an int array (an UNKNOWN
      # element unifies away), so the container was narrowed to a table of int arrays
      # -- and that pin outlived the rounds that knew `start` is an object. `cell`
      # then bound an Integer and the call on it raised.

      class C
        attr_reader :v, :ns
        def initialize(v); @v = v; @ns = []; end
        def link(c); @ns << c; end
      end

      def bfs(start, target)
        path = []
        queue = []
        path << [start, -1]
        queue << 0
        while !queue.empty?
          pid = queue.shift
          cell, _ = path[pid]
          cell.ns.each do |n|
            return path.length if n == target
            path << [n, pid]
            queue << path.size - 1
          end
        end
        -1
      end

      a = C.new(1)
      b = C.new(2)
      a.link(b)
      p bfs(a, b)
    RUBY

    _(result).must_answer "1\n"
  end

  it "massign poly scalar target" do
    result = ze0(<<~'RUBY')
      class Cell
        attr_reader :n
        def initialize(n); @n = n; end
      end

      def build
        path = []
        path << [Cell.new(1), -1]
        path << [Cell.new(2), 0]
        path
      end

      path = build
      i = 0
      while i < 2
        cell, prev = path[i]
        p [cell.n, prev]
        i += 1
      end
    RUBY

    _(result).must_answer "[1, -1]\n[2, 0]\n"
  end

  it "massign underfill nil" do
    result = ze0(<<~'RUBY')
      # Multiple assignment with fewer RHS values than LHS targets fills the extra
      # targets with nil (not the type's zero), for scalar, literal-array, and
      # mixed-splat RHS forms.
      def f(x); a, b, c = x; [a, b, c]; end
      p f(1)
      def h; a, b = 10; [a, b]; end
      p h
      def lit; a, b, c = [1, 2]; [a, b, c]; end
      p lit
      def mid; a, *b, c = [1, 2, 3, 4]; [a, b, c]; end
      p mid
      def s(x); a, b = x; [a, b]; end
      p s("hi")
    RUBY

    _(result).must_answer <<~'OUT'
      [1, nil, nil]
      [10, nil]
      [1, 2, nil]
      [1, [2, 3], 4]
      ["hi", nil]
    OUT
  end

  it "module constants included modules and class variables" do
    result = ze0(<<~'RUBY')
      # Module#constants (own first, ancestors' next, Object's excluded),
      # #included_modules (modules in the MRO), and #class_variables (own +
      # ancestors).

      module Walks; end
      class Animal; end
      class Dog < Animal; include Walks; end
      p Dog.included_modules
      module Mod; MC = 9; end
      class A; X = 1; end
      class B < A; Y = 2; include Mod; end
      p A.constants
      p B.constants.sort
      p B.constants(false)
      class C; @@x = 5; end
      C.class_variable_set(:@@y, 9)
      p C.class_variables.sort
    RUBY

    _(result).must_answer <<~'OUT'
      [Walks, Kernel]
      [:X]
      [:MC, :X, :Y]
      [:Y]
      [:@@x, :@@y]
    OUT
  end

  it "multi assign from a non array binds one value and nil fills" do
    result = ze0(<<~'RUBY')
      a, b = 5
      p [a, b]
      c, d = [1, 2]
      p [c, d]
    RUBY

    _(result).must_answer "[5, nil]\n[1, 2]\n"
  end

  it "multi assign into attr targets correctly calls the setter" do
    result = ze0(<<~'RUBY')
      # A real, previously-undetected bug: `CallTargetNode::name()` is
      # ALREADY the setter name (`:x=`, confirmed via `Prism.parse`), but
      # `parse::lower_multi_target` appended ANOTHER `=`, building an
      # unresolvable `x==` method name -- so ANY multi-assignment into two
      # attr targets (`b.x, b.y = b.y, b.x`, the idiomatic in-place swap)
      # panicked with a confusing "unsupported call `x==`" instead of
      # swapping the values. Array-index multi-assign targets (`arr[0],
      # arr[1] = ...`) were unaffected (a distinct code path, `[]=`, not
      # string-formatted from a name at all).

      arr = [1, 2, 3, 4]
      arr[0], arr[1] = arr[1], arr[0]
      puts arr[0]
      puts arr[1]

      class Box
        attr_accessor :x, :y
        def initialize(x, y)
          @x = x
          @y = y
        end
      end
      b = Box.new(1, 2)
      b.x, b.y = b.y, b.x
      puts b.x
      puts b.y
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      2
      1
    OUT
  end

  it "multi assign poly rhs" do
    result = ze0(<<~'RUBY')
      # Multi-assign with a TY_POLY right-hand side: the boxed value can hold an
      # array at runtime, so it must be destructured element-by-element. The
      # scalar fast path used to hand the whole array to the first target and
      # nil-fill the rest.

      def widen(x); x; end

      pair = widen(["TROOA1", true])
      name, mirrored = pair
      puts name
      puts mirrored
      # TROOA1
      # true

      # through a poly hash read (the doom sprite-index shape)
      index = widen({ "k" => ["POSSB2", false] })
      lump, mir = index["k"]
      puts lump
      puts mir.inspect
      # POSSB2
      # false

      # more targets than elements: trailing targets nil-fill
      a, b, c = widen([1, 2])
      puts a
      puts b
      puts c.nil?
      # 1
      # 2
      # true

      # a poly SCALAR RHS keeps Ruby semantics: first target takes the whole
      # value, the rest nil-fill (no Integer#[] bit reads / String#[] chars)
      x = widen(42)
      a2, b2 = x
      puts a2
      puts b2.nil?
      s2 = widen("hi")
      c2, d2 = s2
      puts c2
      puts d2.nil?
      h2 = widen({ k: 1 })
      e2, f2 = h2
      puts e2 == h2
      puts f2.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      TROOA1
      true
      POSSB2
      false
      1
      2
      true
      42
      true
      hi
      true
      true
      true
    OUT
  end

  it "multi assign post targets clamp when underfull" do
    result = ze0(<<~'RUBY')
      # The same underfull clamping in a multi-assignment: `w, *x, y, z = [1, 2]`
      # is `y=2, z=nil`, not `z=2`.

      w, *x, y, z = [1, 2]
      p [w, x, y, z]
      a, *b, c = [1]
      p [a, b, c]
      q, r, *s, t, u = [1, 2, 3]
      p [q, r, s, t, u]
      a2, *b2, c2 = [1, 2, 3, 4]
      p [a2, b2, c2]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, [], 2, nil]
      [1, [], nil]
      [1, 2, [], 3, nil]
      [1, [2, 3], 4]
    OUT
  end

  it "multi assign trailing comma discards the tail" do
    result = ze0(<<~'RUBY')
      # `a, = rhs` is prism's ImplicitRestNode -- an anonymous rest that takes
      # the named lefts and discards the rest, exactly like `a, *_ = rhs`. This
      # is the `spec_tuples, = fetcher.spec_for_dependency` shape rubygems uses.

      a, = [1, 2, 3]
      puts a                       # 1

      first, = 5                   # non-array RHS: first element is the value
      puts first                   # 5

      def pair; [10, 20]; end
      loc, = pair
      puts loc                     # 10

      x, y, = [1, 2, 3, 4]         # two named, discard the rest
      puts [x, y].inspect          # [1, 2]

      # Implicit rest composes with everything: nested, ivars, index targets,
      # a splat RHS, and the assignment's own return value.
      a2, (b2,) = 1, [2, 9]
      puts [a2, b2].inspect        # [1, 2]

      arr = [7, 8, 9]
      z, = *arr
      puts z                       # 7

      h = {}
      h[:k], = [11, 22]
      puts h.inspect               # {k: 11}

      v = (q, = [30, 40])          # a multi-assign evaluates to its RHS
      puts v.inspect               # [30, 40]
      puts q                       # 30
    RUBY

    _(result).must_answer <<~'OUT'
      1
      5
      10
      [1, 2]
      [1, 2]
      7
      {k: 11}
      [30, 40]
      30
    OUT
  end

  it "multi assign with and without a splat" do
    result = ze0(<<~'RUBY')
      a, b = 1, 2
      puts a
      puts b

      a, *b, c = [1, 2, 3, 4, 5]
      puts a
      puts b
      puts c
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      1
      2
      3
      4
      5
    OUT
  end

  it "multi assignment into a frozen index target raises" do
    result = ze0(<<~'RUBY')
      f = [1, 2]
      f.freeze
      begin
        f[0], x = 5, 6
      rescue FrozenError => e
        puts e.send(:message)
      end
    RUBY

    _(result).must_answer "can't modify frozen Array: [1, 2]\n"
  end

  it "multiple assignment used as an expression yields the raw rhs" do
    result = ze0(<<~'RUBY')
      # `(a, b = rhs)` in value position yields the RHS verbatim, as CRuby does:
      # a call returning an array yields that array (not a fresh copy), a bare
      # scalar yields the scalar (not `[scalar]`), an implicit list yields the
      # list. The destructuring still happens; the expression's own value is the
      # untouched RHS. Regression: the sub-expression form used to yield `nil`,
      # so an outer subscript/comparison hit `[]`/`<` on nil.

      def two_ints; [10, 20]; end
      result = (x, y = two_ints)
      p x
      p y
      p result
      first = (p1, p2, p3 = [7, 8, 9])[0]
      p first
      flag = (a, b = [3, 4])[0] == 3
      p flag
      p((c, d = 5))
      p((e, f = 1, 2))
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      [10, 20]
      7
      true
      5
      [1, 2]
    OUT
  end

  it "named capture auto binding assigns a local per group" do
    result = ze0(<<~'RUBY')
      # `/(?<a>..)/ =~ str` assigns each named group to a local of that name.
      # Only with the literal on the LEFT -- `str =~ /(?<a>.)/` binds nothing,
      # which is Ruby's own asymmetry (the parser can only declare the locals
      # when it can see the names), not an approximation. Oracle-verified,
      # including that a failed match leaves each name nil.

      if /(?<first>\w+) (?<last>\w+)/ =~ "John Smith"
        puts first
        puts last
      end
      p(/(?<n>\d+)/ =~ "abc123")
      p n
      /(?<z>\d+)/ =~ "none"
      p z
    RUBY

    _(result).must_answer <<~'OUT'
      John
      Smith
      3
      "123"
      nil
    OUT
  end

  it "nested destructuring multi assign" do
    result = ze0(<<~'RUBY')
      (a, b), c = [[1, 2], 3]
      puts a
      puts b
      puts c
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
    OUT
  end

  it "nested massign" do
    result = ze0(<<~'RUBY')
      # Nested multiple-assignment targets bind through the nesting.
      def s(x); x; end
      (a, (b, c)), d = s([[1, [2, 3]], 4])
      p [a, b, c, d]
      (e, (f, g, h)), i = s([[10, [20, 30, 40]], 50])
      p [e, f, g, h, i]
    RUBY

    _(result).must_answer "[1, 2, 3, 4]\n[10, 20, 30, 40, 50]\n"
  end

  it "nested massign poly" do
    result = ze0(<<~'RUBY')
      # Nested multiple-assignment from a poly-typed RHS (an Integer|Array union, not
      # a statically-typed array), which destructures via sp_poly_massign_get.
      def maybe(f)
        return 0 unless f
        [[1, [2, 3]], 4]
      end
      x = maybe(true)
      (a, (b, c)), d = x
      p [a, b, c, d]
    RUBY

    _(result).must_answer "[1, 2, 3, 4]\n"
  end

  it "nonlocal return and localjump" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A Deferred holds the proc whose home it is, so the object and its proc own each other.
      # At exit: cycle leak: 2 objects (Deferred x1, Proc x1)
      # A non-lambda Proc's `return` is a NON-LOCAL return: it returns from the
      # method that created the Proc, while that method is still on the stack. Once
      # that home method has unwound, the same `return` raises LocalJumpError
      # instead of jumping into a freed frame. A lambda's `return` is always local.

      # --- Live home: return from the creating method ---
      def simple; proc { return 30 }.call; 40; end
      p simple                              # 30

      def conditional(x); proc { return "yes" if x > 0 }.call; "no"; end
      p conditional(5)                      # "yes"
      p conditional(-1)                     # "no"

      def multi; proc { return 1, 2, 3 }.call; [9]; end
      p multi                               # [1, 2, 3]

      # Through a builtin iterator (the return unwinds out of `each` and the method).
      def first_hit; proc { [1, 2, 3].each { |x| return x * 10 if x == 2 }; :none }.call; end
      p first_hit                           # 20

      # Through `yield` into a user method.
      def gives; yield; end
      def via_yield; gives { return 55 }; 66; end
      p via_yield                           # 55

      # Nested returning-proc methods: inner's return unwinds only inner.
      def inner; proc { return "IR" }.call; "IN"; end
      def outer; x = inner; proc { return "O:#{x}" }.call; "ON"; end
      p outer                               # "O:IR"

      # A lambda's return stays local to the lambda.
      def with_lambda; -> { return 30 }.call; 40; end
      p with_lambda                         # 40

      # --- Dead home: LocalJumpError ---
      # Home escaped via an exception, Proc called afterward.
      $escaped = nil
      def home_raises; $escaped = proc { return 99 }; raise "boom"; end
      begin; home_raises; rescue; end
      begin
        $escaped.call
      rescue LocalJumpError => e
        puts "after exception: #{e.message}"
      end

      # Home returned normally, Proc stored on an object and fired later.
      class Deferred
        def arm; @job = proc { return :never }; self; end
        def fire; @job.call; end
      end
      begin
        Deferred.new.arm.fire
      rescue LocalJumpError => e
        puts "after normal exit: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      30
      "yes"
      "no"
      [1, 2, 3]
      20
      55
      "O:IR"
      40
      after exception: unexpected return
      after normal exit: unexpected return
    OUT
  end

  it "object local boxed write" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # `@right = self`, plus a Node and a Column pointing at each other. The ring IS the subject.
      # At exit: cycle leak: 2 objects (Column x1, Node x1)
      # An attribute that holds a base class AND its subclass reads as a boxed value.
      # A local assigned from one had settled on the object type, and kept the
      # pointer while the read handed back an sp_RbVal -- every such assignment was a
      # build error (#4023):
      #
      #   error: incompatible types when assigning to type 'sp_Node *' from 'sp_RbVal'
      class Node
        attr_accessor :right, :column

        def initialize
          @right = self
          @column = nil
        end
      end

      class Column < Node
        attr_accessor :size

        def initialize
          super()
          @size = 0
          @column = self
        end
      end

      col = Column.new
      n = Node.new
      n.right = col
      n.column = col
      col.right = n

      # the ring holds both classes, so each read is boxed
      j = n.right
      p j.class
      k = j.right
      p k.class
      m = n.column
      p m.class
      p m.size

      # walking it keeps working
      cur = col
      2.times do
        cur = cur.right
      end
      p cur.class
    RUBY

    _(result).must_answer <<~'OUT'
      Column
      Node
      Column
      0
      Column
    OUT
  end

  it "object local written in a branch" do
    result = ze0(<<~'RUBY')
      # A local holding a user-class instance, assigned somewhere other than a
      # top-level statement of its scope. Zeo gives such a local an unboxed
      # `Arc<Concrete>` slot whose binding comes from the assignment itself, so
      # writing it inside an `if` arm scoped the binding to that arm and every read
      # after the `if` named something that was not there -- the generated program
      # did not compile at all. Fifteen lines of ordinary Ruby; irb's ext/loader.rb
      # writes the same shape with a WorkSpace.
      class W
        def initialize(x = nil)
          @x = x
        end
        def show = @x.inspect
      end

      def by_branch(c)
        if c
          ws = W.new(1)
        else
          ws = W.new
        end
        ws.show
      end

      puts by_branch(true)
      puts by_branch(false)

      # The same through a rescue clause, and through a block -- both are nested
      # positions for the same reason.
      def by_rescue(c)
        w = W.new(:fine)
        raise "no" if c
        w.show
      rescue RuntimeError
        w = W.new(:rescued)
        w.show
      end

      puts by_rescue(false)
      puts by_rescue(true)

      def by_block(list)
        list.each do |n|
          w = W.new(n)
          puts w.show
        end
      end

      by_block([1, 2])

      # A local assigned only at the top level of its scope keeps the fast path,
      # which is the case this must not disturb.
      def straight_line
        w = W.new(:direct)
        w.show
      end

      puts straight_line

      # Assignment-as-expression still evaluates to the assigned value.
      def chained
        a = (b = W.new(:shared))
        [a.show, b.show]
      end

      p chained
    RUBY

    _(result).must_answer <<~'OUT'
      1
      nil
      :fine
      :rescued
      1
      2
      :direct
      [":shared", ":shared"]
    OUT
  end

  it "object typed local widened to poly across branches boxes correctly" do
    result = ze0(<<~'RUBY')
      # `x`'s two branches assign DIFFERENT classes, so
      # `analyze::locals::merge_locals` widens its whole-scope type to `Poly`
      # (a plain `RubyValue` slot) -- but each branch's own `HirNode::New` codegen
      # still produces a bare, unboxed value unless the write site itself boxes
      # it. Before this fix, this was a genuine type mismatch in the GENERATED
      # program, not just a wrong answer.

      class Foo
        def initialize
          @tag = "foo"
        end
        def tag
          @tag
        end
      end

      class Bar
        def initialize
          @tag = "bar"
        end
        def tag
          @tag
        end
      end

      class Picker
        def pick(flag)
          if flag
            x = Foo.new
          else
            x = Bar.new
          end
          x
        end
      end

      p = Picker.new
      puts p.pick(true).tag
      puts p.pick(false).tag
    RUBY

    _(result).must_answer "foo\nbar\n"
  end

  it "op assign tail return" do
    result = ze0(<<~'RUBY')
      # An operator-assignment (x += 1, @x += 1) in method tail position returns the
      # updated value, like the class-variable form already did. (matz/spinel#1484)
      class CounterLocal
        def inc(v); v += 1; end
        def dec(v); v -= 2; end
        def scale(v); v *= 3; end
      end
      class CounterIvar
        attr_accessor :value
        def initialize(v); @value = v; end
        def inc; @value += 1; end
        def add(n); @value += n; end
      end
      class CounterCvar
        @@v = 10
        def self.inc; @@v += 1; end
      end

      c = CounterLocal.new
      puts c.inc(10)     # 11
      puts c.dec(10)     # 8
      puts c.scale(4)    # 12

      iv = CounterIvar.new(10)
      puts iv.inc        # 11
      puts iv.inc        # 12
      puts iv.add(5)     # 17
      puts iv.value      # 17

      puts CounterCvar.inc   # 11
      puts CounterCvar.inc   # 12

      # op-assign tail inside a conditional branch still returns the value
      def branchy(x)
        if x > 0
          x += 100
        else
          x -= 100
        end
      end
      puts branchy(5)    # 105
      puts branchy(-5)   # -105
    RUBY

    _(result).must_answer <<~'OUT'
      11
      8
      12
      11
      12
      17
      17
      11
      12
      105
      -105
    OUT
  end

  it "op assign user operator" do
    result = ze0(<<~'RUBY')
      # `slot OP= rhs` desugars to `slot = slot OP rhs`. When the slot
      # is obj-typed and the class defines OP as a user method, codegen
      # must dispatch through that method. The previous version emitted
      # raw C `slot OP= rhs` for every slot type — on an obj pointer
      # that compiled to pointer arithmetic, silently miscompiling the
      # Ruby semantics.

      class Box
        def initialize(n)
          @n = n
          @arr = []
          @arr << n   # force heap layout (sp_Box *), not value-type
        end
        attr_reader :n

        def +(other); Box.new(@n + other); end
        def -(other); Box.new(@n - other); end
      end

      # Instance-variable op-assign in stmt position.
      class IvarStmt
        def initialize
          @b = Box.new(10)
          @b += 5
        end
        attr_reader :b
      end
      puts IvarStmt.new.b.n          # 15

      # Local-variable op-assign in stmt position.
      def local_stmt
        b = Box.new(20)
        b -= 3
        b.n
      end
      puts local_stmt                # 17
    RUBY

    _(result).must_answer "15\n17\n"
  end

  it "operators work on locals not just literals" do
    result = ze0(<<~'RUBY')
      # Originally, only a literal-on-literal `+` compiled at all. This
      # proves the generalization: arithmetic on locals typed `Int` by the
      # forward local-type tracker (`analyze::locals`).

      x = 5
      y = 3
      puts x + y
      puts x - y
      puts x * y
      puts x / y
      puts x % y
    RUBY

    _(result).must_answer <<~'OUT'
      8
      2
      15
      1
      2
    OUT
  end

  it "or assign on a never before defined constant quietly defines it" do
    result = ze0(<<~'RUBY')
      # A real, previously-undetected bug: `CONST ||= v` on a constant that
      # was NEVER assigned raised `NameError` instead of quietly defining
      # it -- confirmed via real `ruby` that this is a genuine, narrow
      # special case (ONLY `||=` gets this leniency; `+=`/`&&=` on the same
      # undefined constant still raise, see the next test). Fixed via a new
      # `HirNode::ConstReadOrNil`, used only by `||=`'s own desugar.

      MAX ||= 100
      puts MAX
      MAX ||= 200
      puts MAX
    RUBY

    _(result).must_answer "100\n100\n"
  end

  it "or assign on an attribute short circuits without calling the setter" do
    result = ze0(<<~'RUBY')
      class Box
        attr_accessor :n
      end
      b = Box.new
      b.n = 5
      b.n ||= 99
      puts b.n
      b.n = nil
      b.n ||= 42
      puts b.n
    RUBY

    _(result).must_answer "5\n42\n"
  end

  it "or assignment writes only when it has to" do
    result = ze0(<<~'RUBY')
      # `x ||= v` is `x || (x = v)` and `x &&= v` is `x && (x = v)`: the write
      # happens only when the value is needed. A frozen receiver sees that --
      # memoizing into an ivar that is already set does not write -- and so does
      # a constant's redefinition warning.
      class Memo
        def initialize = (@x = 1; @y = nil)
        def or_x = (@x ||= 2)
        def and_y = (@y &&= 3)
        def or_y = (@y ||= 4)
      end
      memo = Memo.new.freeze
      p memo.or_x
      p memo.and_y
      begin
        memo.or_y
      rescue FrozenError => e
        p e.class
      end

      $g = 5
      p($g ||= 6, $g &&= 7, $g)
      $n = nil
      p($n &&= 1, $n ||= 2, $n)

      class Counter
        @@v = nil
        p(@@v &&= 1, @@v ||= 2, @@v &&= 3, @@v)
      end

      K = 1
      p(K &&= K)
      module Holder
        X = nil
      end
      p(Holder::X &&= 2)
      p(Holder::X ||= 3)

    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      1
      nil
      FrozenError
      5
      7
      7
      nil
      2
      2
      nil
      2
      3
      3
      1
      nil
      3
    OUT
      lang/variables/variables_test.rb:31: warning: already initialized constant K
      lang/variables/variables_test.rb:30: warning: previous definition of K was here
      lang/variables/variables_test.rb:36: warning: already initialized constant Holder::X
      lang/variables/variables_test.rb:33: warning: previous definition of X was here
    ERR
  end

  it "other compound assignment operators still raise on an undefined constant" do
    result = ze0(<<~'RUBY')
      # Regression guard for the fix above: `||=`'s new leniency must NOT
      # leak into `+=`/`&&=` -- confirmed against real `ruby` that those
      # still raise on a genuinely undefined constant. An uncaught Ruby
      # exception exits the compiled binary nonzero with a message on
      # stderr (see `uncaught_raise_with_no_rescue_anywhere_exits_with_the_message`),
      # not an abort, so this asserts on the process output directly.

      UNDEF += 1

    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      lang/variables/variables_test.rb:8:in '<main>': uninitialized constant UNDEF (NameError)
    ERR
  end

  it "output separator globals are honoured" do
    result = ze0(<<~'RUBY')
      # `$,` (the output field separator) and `$\` (the output record separator)
      # are honoured by the three sites that read them: `print` on any stream and
      # `Array#join`.
      #
      # Ruby resolves both at the CALL, not at stream creation, so a program that
      # sets `$,` around one `print` and clears it after gets the separator for
      # that call only -- which is why every reader asks
      # `kernel::output_separator` rather than caching one.
      #
      # The two sites that DON'T read them are the point of the last two cases:
      # `IO#write` ignores `$,` (only `print` joins its arguments with it), and
      # `puts` ignores both.

      require "stringio"
      s = StringIO.new("".dup)
      $, = "-"
      s.print("a", "b")
      $, = nil
      p s.string

      t = StringIO.new("".dup)
      $\ = "!"
      t.print("a")
      $\ = nil
      p t.string

      $, = "-"
      p [1, 2].join
      $, = nil

      u = StringIO.new("".dup)
      $, = "-"
      u.write("a", "b")
      $, = nil
      p u.string

      v = StringIO.new("".dup)
      $\ = "!"
      v.puts("a")
      $\ = nil
      p v.string
    RUBY

    _(result).must_answer <<~'OUT'
      "a-b"
      "a!"
      "1-2"
      "ab"
      "a\n"
    OUT
  end

  it "poly global scalar assign" do
    result = ze0(<<~'RUBY')
      # A global that holds different types across assignments has a poly (sp_RbVal)
      # slot; assigning a bare scalar (`$g = 42`) into it must box the value, not
      # store the raw int into the sp_RbVal slot (a C compile error).
      $g = 5
      $g = "hello"
      $g = [1, 2]
      p $g
      $g = 42
      p $g
      $g = :sym
      p $g
      $g = true
      p $g
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      42
      :sym
      true
    OUT
  end

  it "polymorphic locals" do
    result = ze0(<<~'RUBY')
      class Foo
        def initialize
          @tag = "foo"
        end

        def tag
          @tag
        end
      end

      class Bar
        def initialize
          @tag = "bar"
        end

        def tag
          @tag
        end
      end

      class Picker
        def pick(flag)
          if flag
            x = Foo.new
          else
            x = Bar.new
          end
          x
        end
      end

      picker = Picker.new
      puts picker.pick(true).tag
      puts picker.pick(false).tag
    RUBY

    _(result).must_answer "foo\nbar\n"
  end

  it "require relative splices in document order and shares the global namespace" do
    result = ze0(<<~'RUBY', files: beside("require_relative_order/greeter.rb", "require_relative_order/main.rb"))
      # Top-level `def` in ANY file (main or required) is a separate,
      # pre-existing gap ("unexpected top-level-only node"), routed
      # around with classes/module functions here exactly like every
      # prior phase's tests.

      require_relative "require_relative_order/main"
    RUBY

    _(result).must_answer <<~'OUT'
      before require
      greeter loaded
      after require
      hello, world!
      hello
    OUT
  end

  it "required files top level locals are isolated from the main file" do
    result = ze0(<<~'RUBY', files: beside("required_file_locals/counterlib.rb", "required_file_locals/main.rb"))
      # Real Ruby gives every file its own top-level local scope: main's
      # `count` and the lib's `count` (mutated through a block, exercising
      # the rename pass inside shared-scope block bodies) never touch. The
      # lib hands its result out through a global -- the only channel real
      # Ruby shares.

      require_relative "required_file_locals/main"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      103
      2
    OUT
  end

  it "return from proc whose home is gone raises localjumperror" do
    result = ze0(<<~'RUBY')
      # Once the home method has unwound -- via exception OR normal return --
      # the Proc's `return` finds no live home and raises LocalJumpError rather
      # than leaking a Signal::Return.
      #
      # `$escaped` outlives its home method, and the deferred frame it points at
      # points back: a ring nothing breaks.
      # At exit: cycle leak: 2 objects (Deferred x1, Proc x1)

      $escaped = nil
      def home_raises; $escaped = proc { return 99 }; raise "boom"; end
      begin; home_raises; rescue; end
      begin
        $escaped.call; puts "WRONG"
      rescue LocalJumpError => e
        puts "exc: #{e.message}"
      end

      class Deferred
        def arm; @job = proc { return :never }; self; end
        def fire; @job.call; end
      end
      begin
        Deferred.new.arm.fire; puts "WRONG"
      rescue LocalJumpError => e
        puts "norm: #{e.message}"
      end

      def collect; [proc { return 4 }]; end
      arr = collect
      begin
        arr[0].call; puts "WRONG"
      rescue LocalJumpError => e
        puts "arr: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      exc: unexpected return
      norm: unexpected return
      arr: unexpected return
    OUT
  end

  it "rightward assign" do
    result = ze0(<<~'RUBY')
      # Rightward assignment `expr => var` (Ruby 3.0+). Prism encodes this
      # as a MatchRequiredNode whose `pattern` is a LocalVariableTargetNode.
      # spinel_parse rewrites the simple-target case to a LocalVariableWriteNode
      # at the AST boundary so the codegen reuses the regular assignment path.

      # 1. Integer rightward assignment.
      42 => x
      puts x
      # 42

      # 2. String rightward assignment.
      "hello" => msg
      puts msg
      # hello

      # 3. Method-call result rightward-assigned.
      def square(n)
        n * n
      end

      square(7) => sq
      puts sq
      # 49

      # 4. Rightward inside an expression (each statement creates one local).
      1 + 2 + 3 => total
      total * 2 => doubled
      puts total
      # 6
      puts doubled
      # 12

      # 5. Boolean.
      (5 > 3) => is_bigger
      puts is_bigger
      # true
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hello
      49
      6
      12
      true
    OUT
  end

  it "sees globals and main object ivars" do
    result = ze0(<<~'RUBY')
      $g = "global"
      @iv = 41
      puts eval("$g".dup)
      puts eval("@iv + 1".dup)
    RUBY

    _(result).must_answer "global\n42\n"
  end

  it "std streams not reassigned" do
    result = ze0(<<~'RUBY')
      # A program that never reassigns a standard stream must emit exactly as before:
      # no global, no runtime test on the read path.
      #
      # The harness compares the two streams separately, so the split is the check:
      # every write below lands where it was addressed.
      $stdout.puts "a"
      p($stdout == $stderr)
      p($stdout == $stdout)
      p($stderr == $stderr)
      $stdout.write("w\n")
      $stdout.flush
      $stderr.puts "b"
      $stderr.write("e\n")
      $stderr.flush
    RUBY

    _(result).must_answer <<~'OUT', stderr: "b\ne\n"
      a
      false
      true
      true
      w
    OUT
  end

  it "stdout stderr constants and globals" do
    result = ze0(<<~'RUBY')
      STDOUT.puts "via const"
      $stdout.puts "via global"
      STDERR.puts "err const"
      $stderr.print "err global\n"
      puts STDOUT.write("abc\n")
      $stdout = STDERR
      puts "redirected"
      $stdout = STDOUT
      puts "back"
      puts STDOUT.inspect
    RUBY

    _(result).must_answer <<~'OUT', stderr: "err const\nerr global\nredirected\n"
      via const
      via global
      abc
      4
      back
      #<IO:<STDOUT>>
    OUT
  end

  it "subclass reassigning a cvar mutates the shared inherited storage" do
    result = ze0(<<~'RUBY')
      # Verified against real Ruby first: a subclass's own `@@x = ...`
      # does NOT shadow -- it finds and mutates the SAME storage inherited
      # from the superclass (real Ruby's actual, if slightly surprising,
      # class-variable semantics). This is also the exact scenario zeo's
      # own C implementation gets wrong (a subclass writing a superclass-only
      # cvar allocates fresh, separate storage there -- an outright compile
      # failure in zeo's case).

      class Base
        @@x = 1
        def base_x
          @@x
        end
      end
      class Sub < Base
        @@x = 99
        def sub_x
          @@x
        end
      end
      puts Base.new.base_x
      puts Sub.new.sub_x
    RUBY

    _(result).must_answer "99\n99\n"
  end

  it "thread current name status and thread locals" do
    result = ze0(<<~'RUBY')
      p Thread.current == Thread.main
      p Thread.pass
      t = Thread.new { 20 + 22 }
      t.name = "worker"
      p t.name
      p t.value
      p t.status
      p Thread.main.status
      Thread.current[:tag] = "root"
      p Thread.current[:tag]
      p Thread.current.key?(:tag)
      p Thread.current.keys
      Thread.current.thread_variable_set(:count, 3)
      p Thread.current.thread_variable_get(:count)
      p Thread.current.thread_variables.grep_v(/logger/)
      p Thread.current.report_on_exception
      workers = [Thread.new { 1 }, Thread.new { 2 }]
      workers.each(&:join)
      p workers.map(&:status)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      "worker"
      42
      false
      "run"
      "root"
      true
      [:tag]
      3
      [:count]
      true
      [false, false]
    OUT
  end

  it "time utc and local accept a fractional seconds field" do
    result = ze0(<<~'RUBY')
      # A Rational/Float seconds field splits into the integer second plus an
      # EXACT sub-second (Time stores a rational epoch, so #subsec is exact).

      p Time.utc(2020, 1, 1, 0, 0, Rational(3, 2)).subsec
      p Time.utc(2020, 1, 1, 0, 0, Rational(3, 2)).sec
      p Time.utc(2020, 1, 1, 0, 0, 2.5).subsec
    RUBY

    _(result).must_answer <<~'OUT'
      (1/2)
      1
      (1/2)
    OUT
  end

  it "user method named clone does not shadow the internal arc clone" do
    result = ze0(<<~'RUBY')
      # A Ruby method named `clone` becomes an INHERENT `fn clone` on the
      # generated struct; every internal self/local copy must therefore avoid
      # `.clone()` method syntax (which would resolve to the Ruby method --
      # infinite recursion in `clone`'s own body, type errors elsewhere).
      # Exercises the collision through self-reference, ivar writes (the
      # frozen-check emission), and an Object-typed local re-read.

      class Uncopyable
        def initialize
          @n = 1
        end
        def clone
          raise TypeError, "can't clone #{self.class}"
        end
        def bump
          @n += 1
          self
        end
        def n
          @n
        end
      end
      u = Uncopyable.new
      u.bump
      puts u.n
      begin
        u.clone
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer "2\ncan't clone Uncopyable\n"
  end

  it "verbose global default" do
    result = ze0(<<~'RUBY')
      p $VERBOSE
      $VERBOSE = true
      p $VERBOSE
      $VERBOSE = nil
      p $VERBOSE
      $VERBOSE = false
      p $VERBOSE
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      nil
      false
    OUT
  end
end
