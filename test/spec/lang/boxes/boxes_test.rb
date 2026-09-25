# frozen_string_literal: true

require "spec_helper"

describe "Boxes programs" do
  it "boolean operators box object typed operands" do
    result = zr(<<~'RUBY')
      class Flag; end
      f = Flag.new
      puts (f && 1).inspect
      puts (nil || Flag.new).class
      puts f ? "truthy" : "falsy"
      puts (!f).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      1
      Flag
      truthy
      false
    OUT
  end

  it "box attr accessor is its own" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; attr_accessor :tag; end")
      p [].respond_to?(:tag)
      p b.eval("a = []; a.tag = 5; a.tag")
    RUBY

    _(result).must_answer "false\n5\n"
  end

  it "box class ivar is not readable in the box" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; @civ = 7; def self.civ = @civ; end")
      p b.eval("Array.civ")
    RUBY

    _(result).must_answer "7\n"
  end

  it "box class method is absent from mains reflection" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # Reflection agrees with dispatch. A name the box defined must not appear
      # in main's `singleton_methods`, which reads a name set with no box axis of
      # its own.

      b = Ruby::Box.new
      b.eval("class Array; def self.zzz = 1; end")
      p Array.singleton_methods(false).include?(:zzz)
      p b.eval("Array.singleton_methods(false).include?(:zzz)")
    RUBY

    _(result).must_answer "false\ntrue\n"
  end

  it "box class variable is its own" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; @@cv = 3; def self.cv = @@cv; end")
      p(begin; Array.cv; rescue NoMethodError; :nome; end)
      p b.eval("Array.cv")
    RUBY

    _(result).must_answer ":nome\n3\n"
  end

  it "box const set reaches main" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("Object.const_set(:BOXCONST, 5)")
      p(begin; Object.const_get(:BOXCONST); rescue NameError; :namee; end)
    RUBY

    _(result).must_answer ":namee\n"
  end

  it "box constant on a shared class is its own" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # A constant written on a SHARED class inside a box, read back by path.
      # `Array::BOXC` is a scope-operator read rather than a cref walk, so it is
      # a different path into the same table.

      b = Ruby::Box.new
      b.eval("class Array; BOXC = 11; end")
      p(begin; Array::BOXC; rescue NameError; :namee; end)
      p b.eval("Array::BOXC")
    RUBY

    _(result).must_answer ":namee\n11\n"
  end

  it "box exceptions are rescuable in main" do
    files = beside("box_exceptions/main.rb", "box_exceptions/thrower.rb")

    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: files, ruby: ["-W:no-experimental"])
      # Exceptions cross the boundary as plain references: a box-defined
      # `BoxError < StandardError` raised from box code is rescuable in main
      # through the SHARED bootstrap superclass chain, and `e.class` names it.



      require_relative "box_exceptions/main"
    RUBY

    _(result).must_answer "rescued: from the box (BoxError)\n"
  end

  it "box handle carries cruby ids" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # The `Ruby::Box` handle surface, under CRuby's own gate.
      #
      # Two id spaces are kept apart on purpose. The INTERNAL id is what codegen
      # bakes at every site, with `box_id == 0` meaning main at some twenty
      # places; the DISPLAY id is CRuby's -- master 1, root 2, main 3, user
      # boxes from 4 in creation order -- and is derived, never stored in a key.
      #
      # `master` and `root` are inert handles: zr has no boot box, and saying
      # so is more honest than faking one. They exist so `Ruby::Box.master` and
      # `#master?` answer what ruby answers.
      #
      # `Ruby::Box.current` cannot be a method row -- a `MethodFn` takes no box,
      # so no row can see its caller's. The emitter folds the literal spelling
      # to its own site's box, which is why the box's own code answers the box.
      b = Ruby::Box.new
      c = Ruby::Box.new

      # The handle is a real box, and a module besides -- `Ruby::Box < Module`.
      p b.class.to_s
      p b.is_a?(Ruby::Box)
      p Ruby::Box.superclass.to_s
      p b.name

      # Creation order, from 4.
      p [b.inspect, c.inspect]
      p [Ruby::Box.main.inspect, Ruby::Box.root.inspect, Ruby::Box.master.inspect]
      p [b.main?, b.root?, b.master?]
      p [Ruby::Box.main.main?, Ruby::Box.root.root?, Ruby::Box.master.master?]

      # `p` renders a handle as the box, not as the module standing in for its
      # top level.
      p Ruby::Box.current
      p Ruby::Box.current.main?

      # ... and inside the box, `current` is the box.
      p b.eval("Ruby::Box.current.inspect")
      p b.eval("Ruby::Box.current.main?")

      # A box minted at RUN time is a box like any other.
      d = [Ruby::Box.new].first
      p [d.class.to_s, d.main?, d.inspect]
      d.eval("RUNTIME_BOX_CONST = 7")
      p d.eval("RUNTIME_BOX_CONST")
      p defined?(RUNTIME_BOX_CONST)

      # Each box has its own `$LOAD_PATH`, seeded as a COPY, so an `unshift` in
      # one is invisible to the other.
      p b.eval("$LOAD_PATH.class.to_s")
      b.eval("$LOAD_PATH.unshift('/only-in-the-box')")
      p b.eval("$LOAD_PATH.first")
      p $LOAD_PATH.include?("/only-in-the-box")
    RUBY

    _(result).must_answer <<~'OUT'
      "Ruby::Box"
      true
      "Module"
      nil
      ["#<Ruby::Box:4,user,optional>", "#<Ruby::Box:5,user,optional>"]
      ["#<Ruby::Box:3,user,main>", "#<Ruby::Box:2,root>", "#<Ruby::Box:1,master>"]
      [false, false, false]
      [true, true, true]
      #<Ruby::Box:3,user,main>
      true
      "#<Ruby::Box:4,user,optional>"
      false
      ["Ruby::Box", false, "#<Ruby::Box:6,user,optional>"]
      7
      nil
      "Array"
      "/only-in-the-box"
      false
    OUT
  end

  it "box handle is a real ruby box" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # `Ruby::Box.new` answers a value that IS a `Ruby::Box`.
      #
      # `b.class.to_s` answers "Ruby::Box", and `b.is_a?(Ruby::Box)` is
      # true. `b.eval` resolves `Ruby::Box#eval`, not `Kernel#eval`.
      #
      # `Ruby::Box.new` needs `RUBY_BOX=1` in the environment when the
      # program RUNS, not when it compiles.

      b = Ruby::Box.new
      p b.class.to_s
      p b.is_a?(Ruby::Box)
      p b.main?
    RUBY

    _(result).must_answer <<~'OUT'
      "Ruby::Box"
      true
      false
    OUT
  end

  it "box include is invisible to main" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # `include` from inside a box reaches the class's ancestry rather than its
      # own tables, and stays the box's.

      b = Ruby::Box.new
      b.eval("module BoxMix; def mixed = 'm'; end; class Array; include BoxMix; end")
      p [].respond_to?(:mixed)
      p b.eval("[].mixed")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      "m"
    OUT
  end

  it "box isolation and shared builtins" do
    files = beside("box_isolation/main.rb", "box_isolation/widget.rb")

    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: files, ruby: ["-W:no-experimental"])
      # The keystone: a box-required file's classes are DISTINCT from main's
      # (same file, different class objects), builtins are SHARED
      # (`box::String == String`), a box top-level constant is readable
      # externally, and box gvars are invisible in main -- all per the CRuby
      # box model.



      require_relative "box_isolation/main"
    RUBY

    _(result).must_answer <<~'OUT'
      "main widget"
      "box widget"
      false
      true
      99
      nil
      #<Ruby::Box:4,user,optional>
    OUT
  end

  it "box loads its own copy of a file" do
    files = beside("box_own_copy/widget.rb")

    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: files, ruby: ["-W:no-experimental"])


      # A box requires from its OWN load path, and gets its own copy.
      #
      # Each box has its own `$LOAD_PATH` (seeded as a copy of the creating
      # box's) and its own `$LOADED_FEATURES` (empty), so a file main already
      # required RE-EXECUTES in the box -- which is what makes `box::Widget !=
      # Widget`, and CRuby's whole point.
      #
      # The once-only table is keyed by `(box, canonical path)` for exactly that
      # reason: the path is the identity CRuby's `$LOADED_FEATURES` uses, and
      # the box is what keeps two boxes' copies apart.
      #
      # An expression-position `box.require` also works. A TOP-LEVEL one is still spliced by the loader -- the fast,
      # statically typed path -- and everywhere else it is the ordinary send,
      # which reaches the box's run-time load path.
      root = File.join(__dir__, "box_own_copy")
      $LOAD_PATH.unshift(root)
      require "widget"
      p BoxedWidget.new.hi

      b = Ruby::Box.new
      b.load_path.unshift(root)
      p b.require("widget")
      p b.require("widget")
      p b.eval("BoxedWidget.new.hi")
      p b.eval("BOXED_WIDGET_CONST")

      # Main's copy is untouched: its own class, its own global, its own list.
      p [BoxedWidget.new.hi, $boxed_widget_runs]
      p b.eval("BoxedWidget") == BoxedWidget
      p b.eval("$LOADED_FEATURES.count { |f| f.end_with?(\'widget.rb\') }")
      p $LOADED_FEATURES.count { |f| f.end_with?("widget.rb") }

      # A second box is a third copy.
      c = Ruby::Box.new
      c.load_path.unshift(root)
      p c.require("widget")
      p c.eval("BoxedWidget.new.hi")
      p c.eval("BoxedWidget") == b.eval("BoxedWidget")
    RUBY

    _(result).must_answer <<~'OUT'
      "widget 1"
      true
      false
      "widget 1"
      99
      ["widget 1", 1]
      false
      1
      1
      true
      "widget 1"
      false
    OUT
  end

  it "box nested class is reachable by path" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("module Outer; class Inner; def self.who = 'in'; end; end")
      p b::Outer::Inner.who
      p(begin; Outer; rescue NameError; :namee; end)
    RUBY

    _(result).must_answer <<~'OUT'
      "in"
      :namee
    OUT
  end

  it "box nullable builtin" do
    result = zr(<<~'RUBY')
      # A reference-backed BUILTIN type (IO/Fiber/Thread/Exception/Proc/...) is a
      # nilable C pointer just like a user object: an unset ivar or a `return nil`
      # yields NULL. Boxing it into a poly slot must produce nil, not a "truthy"
      # wrapper over a NULL pointer -- otherwise `x.nil?` lies and `if x` / `unless x`
      # passes, then the first method/field read segfaults.
      class Sink
        def open(p); @io = File.open(p, "w"); end
        def io; @io; end   # @io is a NULL sp_File* until #open runs
      end

      s = Sink.new
      box = []
      box << s.io          # boxes a NULL IO into a poly array
      a = box[0]
      puts "unset nil? #{a.nil?}"
      puts "BUG: truthy NULL IO" if a        # without the fix, this wrongly prints

      s.open("/tmp/box_nullable_builtin_out.txt")
      box << s.io          # boxes a real IO into the poly array
      b = box[1]
      puts "open nil? #{b.nil?}"
      puts "have io" if b                     # this SHOULD print
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      unset nil? true
      open nil? false
      have io
      done
    OUT
  end

  it "box nullable obj" do
    result = zr(<<~'RUBY')
      # A method or hash lookup that can `return nil` yields a genuinely NULL object
      # pointer. Boxing it into a poly value must produce nil, not a "truthy" object
      # wrapping a NULL pointer -- otherwise `unless x` / `if x` passes and the first
      # field/method read segfaults (doom's TextureManager#[] -> build_composite ->
      # texture.width).
      Pt = Struct.new(:x, :y)
      class Cache
        def initialize; @h = {}; end
        def fetch(k); @h[k] ||= make(k); end
        def make(k)
          return nil if k < 0
          Pt.new(k, k * 2)
        end
      end
      c = Cache.new
      a = c.fetch(3)
      puts "a: #{a.x},#{a.y}"
      b = c.fetch(-1)
      puts "b nil? #{b.nil?}"
      puts "b.x=#{b.x}" if b   # must NOT run (b is nil); without the fix b is a truthy NULL -> segv
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      a: 3,6
      b nil? true
      done
    OUT
  end

  it "box pointer to poly" do
    result = zr(<<~'RUBY')
      # A method returns a Hash from one branch and a String from the other.
      # The example only checks that the program compiles and runs.

      def get(flag)
        if flag > 0
          return {a: 1, b: 2, c: 3}
        end
        "hello"
      end

      x = get(0)
      y = get(1)
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "box prepend is invisible to main" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("module BoxPre; def size = 99; end; class Array; prepend BoxPre; end")
      p [1,2].size
      p b.eval("[1,2].size")
    RUBY

    _(result).must_answer "2\n99\n"
  end

  it "box reopen after the first loses its mixin" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("module M1; def one = 1; end
      module M2; def two = 2; end
      class Array; include M1; end
      class Array; include M2; end")
      p b.eval("[1, 2].one")
      p b.eval("[1, 2].two")
      p b.eval("Array.ancestors.take(3).inspect")
      p b.eval("[Array.include?(M1), Array.include?(M2)].inspect")
      p b.eval("[1, 2].is_a?(M1)")
      p b.eval("Array.method_defined?(:one)")
      p b.eval("[1, 2].respond_to?(:two)")
      p b.eval("Array.instance_method(:one).owner.to_s")
      p b.eval("[1, 2].method(:two).owner.to_s")

      c = Ruby::Box.new
      c.eval("module P1; def label = 'from P1'; end
      class Hash; def label = 'own'; end
      class Hash; prepend P1; end")
      p c.eval("({}).label")
      p c.eval("Hash.ancestors.first.to_s")
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      "[Array, M2, M1]"
      "[true, true]"
      true
      true
      true
      "M1"
      "M2"
      "from P1"
      "P1"
    OUT
  end

  it "box reopen in expression position stays in the box" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new

      # The reopen's VALUE is used, so the splice sits in expression position.
      x = b.eval("class String; def shout = upcase + '!'; end; 'a'.shout")
      p x
      p "a".respond_to?(:shout)

      # ...and inside a block, which is the same nesting question.
      [1].each { b.eval("class Array; def two = 2; end") }
      p b.eval("[1].two")
      p [1].respond_to?(:two)

      # A class-level ivar written in a box body is the box's own.
      b.eval("class Array; @zz = 7; def self.zz = @zz; end")
      p b.eval("Array.zz")
      p Array.instance_variable_get(:@zz)

      # A box's `remove_method`/`undef_method` names its own rows, and retires
      # them for that box alone.
      p b.eval("class String; def gone = 1; end; String.instance_methods(false).include?(:gone)")
      p b.eval("class String; remove_method :gone; end; 'a'.respond_to?(:gone)")
      p b.eval("class String; undef_method :upcase; end; ('a'.upcase rescue $!.class.to_s)")
      p "a".upcase

      # A builtin MODULE mixed in inside a box reaches the OPERATOR form too.
      c = Ruby::Box.new
      c.eval("class Array; include Comparable; end")
      p c.eval("[1] < [2]")
      p c.eval("[1].send(:<, [2])")
      p ([1] < [2] rescue $!.class.to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      "A!"
      false
      2
      false
      7
      nil
      true
      false
      "NoMethodError"
      "A"
      true
      true
      "NoMethodError"
    OUT
  end

  it "box snippet names itself in a backtrace" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # A box's snippet names itself differently from every other eval, in three
      # places at once: the file is `eval` (not `(eval at f.rb:14)`), the snippet's
      # own scope is `<compiled>` (not the caller's), and the frame between them is
      # `Ruby::Box#eval` (not `Kernel#eval`).
      #
      # The LITERAL form is spliced at compile time and still reports the
      # program's own file. This file computes the source
      # (`["K", ""].first` is opaque to the constant folder), so the eval
      # compiles at run time instead.
      #
      # Oracle: the box cannot see main's `K`, so ruby raises NameError from the
      # snippet's own frame.
      K = 5
      b = Ruby::Box.new
      src = ["K", ""].first
      p b.eval(src)
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      eval:1:in '<compiled>': uninitialized constant K (NameError)
      	from lang/boxes/boxes_test.rb:18:in 'Ruby::Box#eval'
      	from lang/boxes/boxes_test.rb:18:in '<main>'
    ERR
  end

  it "box unbox local assign cond" do
    result = zr(<<~'RUBY')
      # `if (entry = @arr[i])` tests the value of the assignment. The array
      # holds values of mixed types, and the test uses Ruby truthiness.

      class C
        def initialize
          @arr = [10, "twenty", :thirty]   # mixed types
        end
        def find(i)
          if (entry = @arr[i])             # entry can hold any of the element types
            entry
          end
        end
      end

      c = C.new
      puts c.find(0).to_s
      puts c.find(1).to_s
    RUBY

    _(result).must_answer "10\ntwenty\n"
  end

  it "a class in a box is its own class, globals and constants are box-separate, and values cross as references" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # Phase 18 -- Ruby::Box: compile-time box namespaces. A class defined in a
      # box is a distinct class; builtins are shared (and patchable PER BOX);
      # globals and top-level constants are fully box-separate; values and
      # exceptions cross the boundary as plain references.

      class Widget
        def hi
          "main widget"
        end
      end

      box = Ruby::Box.new
      box.eval("class Widget; def hi; 'box widget'; end; end")

      p Widget.new.hi
      w = box.eval("Widget.new")
      p w.hi
      p box::Widget == Widget
      p box::String == String

      box.eval("BOX_CONST = 99")
      p box::BOX_CONST

      $g = "main value"
      p box.eval("$g")
      box.eval("$g = 'box value'")
      p $g
      p box.eval("$g")

      box.eval("class String; def shout; upcase + '!'; end; end")
      p box.eval("'hey'.shout")
      begin
        "hey".shout
      rescue NoMethodError
        puts "main: no shout"
      end

      box2 = Ruby::Box.new
      box2.eval("class Widget; def hi; 'other box'; end; end")
      p box2::Widget.new.hi
      p(box::Widget == box2::Widget)

      box.eval("class BoxError < StandardError; end")
      begin
        box.eval("raise BoxError, 'crossed'")
      rescue StandardError => e
        puts "rescued: #{e.message} (#{e.class})"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "main widget"
      "box widget"
      false
      true
      99
      nil
      "main value"
      "box value"
      "HEY!"
      main: no shout
      "other box"
      false
      rescued: crossed (BoxError)
    OUT
  end

  it "one file required into two boxes runs twice, and a box's builtin patch stays inside it" do
    files = beside("boxes_reexecute/blank.rb", "boxes_reexecute/main.rb")

    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: files, ruby: ["-W:no-experimental"])
      # Per-box re-execution (the same file `box.require`d into two boxes runs
      # twice, with independent class-variable state per box), and per-box
      # builtin MONKEYPATCHES: a box's `String#blank?` resolves from that box's
      # code while main's `"foo".blank?` stays a NoMethodError -- the docs'
      # motivating example, dispatch by DEFINING box.



      require_relative "boxes_reexecute/main"
    RUBY

    _(result).must_answer <<~'OUT'
      loaded
      loaded
      true
      main: undefined method 'blank?' for an instance of String
      2
      1
    OUT
  end

  it "class written in a box stays in it" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # A `class` written in a box belongs to that box: main cannot reach it.
      #
      # A box's top-level class keeps its bare ruby name -- `Escapee` written in a
      # box is called `Escapee`. But in main, `Object.constants`, a bare constant
      # read and `defined?` do not see it, and the three agree.

      b = Ruby::Box.new
      b.eval("class Escapee; def self.hi = 'in box'; end")
      p defined?(Escapee)
      begin
        p Escapee
      rescue NameError => e
        p e.class
      end
    RUBY

    _(result).must_answer "nil\nNameError\n"
  end

  it "disabled box carries no gate rows" do
    result = zr(<<~'RUBY', ruby: ["-W:no-experimental"])

      # `Ruby::Box`'s gate-only rows exist only under `RUBY_BOX=1`, as CRuby's do.
      #
      # zr's rows live in a static table the `ruby_class!` DSL builds at compile
      # time, so they are registered either way -- the GATE has to hide them. That
      # is what `builtins::gate` already does for the require-gated `IO` rows
      # (`io/console`, `io/nonblock`), so `Ruby::Box` joins the same projection
      # filter rather than needing a class-side `undef` mechanism of its own. The
      # gate is keyed on the environment instead of on `$LOADED_FEATURES`, which is
      # the only thing that differs.
      #
      # Nothing could reach a WRONG answer through this before -- all six refused
      # with the gate's own message -- but reflection listed six names CRuby does
      # not, which is what a library checking `respond_to?` sees.
      #
      # The harness runs a box source under `RUBY_BOX=1` when the SOURCE TEXT
      # allocates a box -- a plain substring test, so even naming that call in a
      # comment flips the very gate this file is testing. The enabled surface is
      # `tests/ruby_box_surface.rb`'s.

      p (Ruby::Box.singleton_methods(false) - %i[current enabled?]).sort
      p (Ruby::Box.instance_methods(false) -
         %i[eval inspect load load_path require require_relative]).sort
      p Ruby::Box.enabled?
      p Ruby::Box.current
      begin
        Ruby::Box.main
      rescue Exception => e
        p e.class
      end
      p Ruby::Box.respond_to?(:root)
      p Ruby::Box.method_defined?(:root?)
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      false
      nil
      NoMethodError
      false
      false
    OUT
  end

  it "if arms with different object classes box to ruby value" do
    result = zr(<<~'RUBY')
      class A
        def tag = "a"
      end
      class B
        def tag = "b"
      end
      pick = true
      x = pick ? A.new : B.new
      puts x.send(:tag)
    RUBY

    _(result).must_answer "a\n"
  end

  it "a method that answers with what it yielded hands back the object itself" do
    result = zr(<<~'RUBY')
      class A; def id; 1; end; end
      class B; def id; 2; end; end
      def txn; result = yield; result; end
      def ba; txn { A.new }; end
      def bb; txn { B.new }; end
      x = ba; y = bb; puts x.id; puts y.id
    RUBY

    _(result).must_answer "1\n2\n"
  end

  it "main definitions are invisible inside a box" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # A main-only class/constant is INVISIBLE inside a box (boxes dup from
      # MASTER, not main): resolving it inside box.eval raises NameError-shaped
      # failures rather than leaking main's definitions.



      MAIN_ONLY = 42
      box = Ruby::Box.new
      box.eval("begin; p MAIN_ONLY; rescue NameError => e; puts 'invisible'; end")
    RUBY

    _(result).must_answer "invisible\n"
  end

  it "master constants stay visible inside a box" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # The other half of that line: a box IS a copy of master, so the constants
      # the runtime installed before main ran stay visible inside it -- the bare
      # read's fallback tail reaches those and stops, rather than continuing into
      # main's own `Object` table.



      VERSION_COPY = RUBY_VERSION
      box = Ruby::Box.new
      box.eval("puts RUBY_VERSION")
      box.eval("begin; p VERSION_COPY; rescue NameError; puts 'invisible'; end")
    RUBY

    _(result).must_answer "4.0.6\ninvisible\n"
  end

  it "module acc dispatch param box" do
    result = zr(<<~'RUBY')
      # `Mod.accessor.method(args)`: a module-singleton accessor returns a
      # module, and a call on it takes args of different types at different
      # call sites.
      #
      # The shape comes from Roundhouse's `ActiveRecord.adapter.update(table,
      # @id, attrs)`, where `@id` can be an Integer or a String.

      module Backend
        class << self
          attr_accessor :db
        end
      end

      module Storage
        module_function
        def fetch(id)
          # Just round-trip the id through to_s + length so the
          # method body works for both int and String inputs.
          id.to_s.length
        end
      end

      Backend.db = Storage

      # Two call sites with different types.
      puts Backend.db.fetch(42)          # 2
      puts Backend.db.fetch("alpha")     # 5
    RUBY

    _(result).must_answer "2\n5\n"
  end

  it "nullable array keyword box" do
    result = zr(<<~'RUBY')
      # A nil-defaulting array-typed value boxed into a poly slot must become nil,
      # not a truthy object that wraps nothing.
      class Config
        def int(*opts, choices: nil) = Flag.new(choices:)
      end
      class Flag
        def initialize(choices: nil)
          @choices = choices
          validate
        end
        def validate
          "choices must be empty" if @choices && @choices.empty?
        end
      end
      c = Config.new
      c.int("--http-port")
      c.int "--bad-int", choices: ["1"]
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "poly attr reader box dispatch" do
    result = zr(<<~'RUBY')
      # A setter whose ivar holds values of mixed types receives an attr_reader
      # value from another class. The String value arrives unchanged.

      class Comment
        attr_accessor :commenter

        def []=(field, value)
          case field
          when :commenter then @commenter = value
          when :other then @other = value
          end
        end
      end

      class CommentRow
        attr_reader :commenter
        def initialize(c); @commenter = c; end
      end

      # Comment's @commenter also takes an Integer here.
      seed = Comment.new
      seed[:other] = 42
      seed[:commenter] = "x"

      def update_from_row(c, p)
        c.commenter = p.commenter
      end

      c = Comment.new
      row = CommentRow.new("alice")
      update_from_row(c, row)
      puts c.commenter
    RUBY

    _(result).must_answer "alice\n"
  end

  it "poly recv aref box arm" do
    result = zr(<<~'RUBY')
      # A user `def [](k)` that callers call with keys of different types
      # (String and Symbol), on receivers of different classes.
      #
      # The shape comes from Roundhouse's view helper:
      # `def field_for(model, field); model[field]; end` where model can be
      # an Article, a Comment, a HWIA or a Parameters, and field is a Symbol.

      class A
        def [](k)
          "from-A"
        end
      end

      class B
        def [](k)
          "from-B"
        end
      end

      # Two callers with different key types.
      def lookup_str(receiver, key)
        receiver[key]
      end
      puts lookup_str(A.new, "alpha")
      puts lookup_str(B.new, "beta")

      def lookup_sym(receiver, key)
        receiver[key]
      end
      puts lookup_sym(A.new, :alpha)
      puts lookup_sym(B.new, :beta)
    RUBY

    _(result).must_answer <<~'OUT'
      from-A
      from-B
      from-A
      from-B
    OUT
  end

  it "return of an object typed value boxes" do
    result = zr(<<~'RUBY')
      class Box
        def initialize(tag)
          @tag = tag
        end
        attr_reader :tag
      end
      def find_or_nil(want)
        if want == "yes"
          return Box.new("found")
        end
        nil
      end
      r = find_or_nil("yes")
      puts r.send(:tag)
      puts find_or_nil("no").inspect
    RUBY

    _(result).must_answer "found\nnil\n"
  end

  it "ruby box surface" do
    result = zr(<<~'RUBY', ruby: ["-W:no-experimental"])

      # The Ruby namespace + Ruby::Box census surface, disabled mode (no RUBY_BOX
      # in the environment -- the harness sets the gate only for a source that
      # ALLOCATES a box): identity constants alias the RUBY_* globals, the Box
      # class carries its real rows, and the gate answers CRuby's disabled shape.
      p Ruby.class
      p Ruby.constants.sort
      p [Ruby::VERSION == RUBY_VERSION, Ruby::ENGINE, Ruby::PLATFORM == RUBY_PLATFORM]
      p [Ruby::COPYRIGHT == RUBY_COPYRIGHT, Ruby::DESCRIPTION == RUBY_DESCRIPTION,
         Ruby::RELEASE_DATE == RUBY_RELEASE_DATE]
      p [Ruby::PATCHLEVEL == RUBY_PATCHLEVEL, Ruby::REVISION == RUBY_REVISION,
         Ruby::ENGINE_VERSION == RUBY_ENGINE_VERSION]
      p Ruby::Box.superclass
      # CRuby defines the gate-only rows (`main`/`root`/`master` and their
      # predicates) ONLY under `RUBY_BOX=1`; zr's are in the static table
      # either way, so this pins the surface both modes share. See
      # `tests/gaps/a_disabled_box_still_carries_its_gate_rows.rb`.
      GATE_ONLY = %i[main master root main? master? root?]
      p (Ruby::Box.singleton_methods(false) - GATE_ONLY).sort
      p (Ruby::Box.instance_methods(false) - GATE_ONLY).sort
      p Ruby::Box.constants.sort
      p [Ruby::Box::Entry.class, Ruby::Box::Entry.superclass]
      p Ruby::Box::Loader.class
      p Ruby::Box.enabled?
      p Ruby::Box.current
      p Ruby::Box.instance_method(:initialize).arity
      p Ruby::Box.instance_method(:eval).arity
      p Ruby::Box.instance_method(:load_path).arity
      p Ruby::Box.instance_method(:require).arity
    RUBY

    _(result).must_answer <<~'OUT'
      Module
      [:Box, :COPYRIGHT, :DESCRIPTION, :ENGINE, :ENGINE_VERSION, :PATCHLEVEL, :PLATFORM, :RELEASE_DATE, :REVISION, :VERSION]
      [true, "ruby", true]
      [true, true, true]
      [true, true, true]
      Module
      [:current, :enabled?]
      [:eval, :inspect, :load, :load_path, :require, :require_relative]
      [:Entry, :Loader]
      [Class, Object]
      Module
      false
      nil
      0
      1
      0
      1
    OUT
  end

  it "run time box reads back its own constant" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # A box minted at RUN TIME, whose id the compiler never saw. Its constant
      # has to be written and read under the same box, which is the case that
      # broke when the write learned the box before the read did.



      d = [Ruby::Box.new].first
      d.eval("RUNTIME_BOX_CONST = 7")
      p d.eval("RUNTIME_BOX_CONST")
      p defined?(RUNTIME_BOX_CONST)
    RUBY

    _(result).must_answer "7\nnil\n"
  end

  it "shift operator boxes an object typed argument" do
    result = zr(<<~'RUBY')
      # `junk << Trash.new(1)` on a Poly receiver: the numeric-op fallback must
      # box an argument it holds unboxed (found by the conformance corpus's
      # argv_gc as a compile failure).

      class Trash
        def initialize(n)
          @n = n
        end
        attr_reader :n
      end
      def build
        junk = []
        junk << Trash.new(7)
        junk
      end
      puts build.length
      puts build[0].n
    RUBY

    _(result).must_answer "1\n7\n"
  end

  it "snippet mints no compile time box" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # `Ruby::Box.new` in a SNIPPET mints a real box.
      #
      # `box = Ruby::Box.new` at a program's top level allocates a COMPILE-TIME
      # box: the loader mints it, binds the local to its surrogate, and splices
      # every `box.require` into the program. A snippet's cannot be one -- the
      # handle would name a box nothing else in the program can reach -- so it
      # stays the ordinary call, and reaches `Ruby::Box`'s own constructor,
      # which mints at run time. The snippet runs; it is not refused.

      def show(src)
        puts eval([src, "nil"].first).inspect
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end

      show("b = Ruby::Box.new; b.class.to_s")
      show("Ruby::Box.new.class.to_s")
    RUBY

    _(result).must_answer <<~'OUT'
      "Ruby::Box"
      "Ruby::Box"
    OUT
  end

  it "top level def in a box stays in it" do
    result = zr(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # A top-level `def` written in a box belongs to that box: main cannot call
      # it.
      #
      # A top-level `def` is a private instance method of `Object`, and a box has
      # its OWN `Object` -- so a `def` in a box means the `class Object` reopen
      # that a box already isolates. The box does not make a SECOND class called
      # `Object`.

      b = Ruby::Box.new
      b.eval("def leaked_helper = 1")
      begin
        p leaked_helper
      rescue NameError, NoMethodError => e
        p e.class
      end
    RUBY

    _(result).must_answer "NameError\n"
  end

  it "yield boxes an object typed argument" do
    result = zr(<<~'RUBY')
      # `yield self` passes the object to the block, and a send on it works.

      class Builder
        def run
          yield self
        end
        def ping = "pong"
      end
      Builder.new.run { |b| puts b.send(:ping) }
    RUBY

    _(result).must_answer "pong\n"
  end
end
