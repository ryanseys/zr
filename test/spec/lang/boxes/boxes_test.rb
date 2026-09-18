# frozen_string_literal: true

require "spec_helper"

describe "Boxes programs" do
  it "boolean operators box object typed operands" do
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; attr_accessor :tag; end")
      p [].respond_to?(:tag)
      p b.eval("a = []; a.tag = 5; a.tag")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      5
    OUT
  end

  it "box class ivar is not readable in the box" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; @civ = 7; def self.civ = @civ; end")
      p b.eval("Array.civ")
    RUBY

    _(result).must_answer "7\n"
  end

  it "box class method is absent from mains reflection" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; def self.zzz = 1; end")
      p Array.singleton_methods(false).include?(:zzz)
      p b.eval("Array.singleton_methods(false).include?(:zzz)")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
    OUT
  end

  it "box class variable is its own" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; @@cv = 3; def self.cv = @@cv; end")
      p(begin; Array.cv; rescue NoMethodError; :nome; end)
      p b.eval("Array.cv")
    RUBY

    _(result).must_answer <<~'OUT'
      :nome
      3
    OUT
  end

  it "box const set reaches main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("Object.const_set(:BOXCONST, 5)")
      p(begin; Object.const_get(:BOXCONST); rescue NameError; :namee; end)
    RUBY

    _(result).must_answer ":namee\n"
  end

  it "box constant on a shared class is its own" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; BOXC = 11; end")
      p(begin; Array::BOXC; rescue NameError; :namee; end)
      p b.eval("Array::BOXC")
    RUBY

    _(result).must_answer <<~'OUT'
      :namee
      11
    OUT
  end

  it "box exceptions are rescuable in main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: {"box_exceptions_are_rescuable_in_main/main.rb" => "box = Ruby::Box.new\nbox.require_relative \"thrower\"\nbegin\n  box::Thrower.go\nrescue StandardError => e\n  puts \"rescued: \#{e.message} (\#{e.class})\"\nend\n", "box_exceptions_are_rescuable_in_main/thrower.rb" => "class BoxError < StandardError\nend\nclass Thrower\n  def self.go\n    raise BoxError, \"from the box\"\n  end\nend\n"}, ruby: ["-W:no-experimental"])
      # Exceptions cross the boundary as plain references: a box-defined
      # `BoxError < StandardError` raised from box code is rescuable in main
      # through the SHARED bootstrap superclass chain, and `e.class` names it.



      require_relative "box_exceptions_are_rescuable_in_main/main"
    RUBY

    _(result).must_answer "rescued: from the box (BoxError)\n"
  end

  it "box handle carries cruby ids" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # The `Ruby::Box` handle surface, under CRuby's own gate.
      #
      # Two id spaces are kept apart on purpose. The INTERNAL id is what codegen
      # bakes at every site, with `box_id == 0` meaning main at some twenty
      # places; the DISPLAY id is CRuby's -- master 1, root 2, main 3, user
      # boxes from 4 in creation order -- and is derived, never stored in a key.
      #
      # `master` and `root` are inert handles: zeo has no boot box, and saying
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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # `Ruby::Box.new` answers a value that IS a `Ruby::Box`.
      #
      # In CRuby `Ruby::Box` is a `Module` subclass, so zeo's
      # `RubyValue::Class(surrogate)` representation is structurally RIGHT --
      # `b::W` resolves for the same reason. What was wrong was `.class`: it
      # answered `Module`, so `b.is_a?(Ruby::Box)` was false and `b.eval`
      # silently resolved `Kernel#eval` instead of `Ruby::Box#eval`. The
      # class-of walk has an arm for the box table now, beside the two it
      # already had (a `class X < Module` instance, a refinement holder).
      #
      # The other half of what this file used to record was the ENV GATE:
      # `Ruby::Box.new` answered a box without `RUBY_BOX=1`, where CRuby raises.
      # The gate is a RUN-TIME question, so asking it during the compile that
      # allocated the box would bake the build machine's environment into the
      # program; the handle comes from `zeo_rt_box_handle` instead, which asks
      # it where the program runs.

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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: {"box_isolation_and_shared_builtins/main.rb" => "class Widget\n  def hi\n    \"main widget\"\n  end\nend\nbox = Ruby::Box.new\nbox.require_relative \"widget\"\np Widget.new.hi\nw = box::Widget.new\np w.hi\np box::Widget == Widget\np box::String == String\np box::WIDGET_CONST\np $box_g\np box\n", "box_isolation_and_shared_builtins/widget.rb" => "class Widget\n  def hi\n    \"box widget\"\n  end\nend\nWIDGET_CONST = 99\n$box_g = 5\n"}, ruby: ["-W:no-experimental"])
      # The keystone: a box-required file's classes are DISTINCT from main's
      # (same file, different class objects), builtins are SHARED
      # (`box::String == String`), a box top-level constant is readable
      # externally, and box gvars are invisible in main -- all per the CRuby
      # box model.



      require_relative "box_isolation_and_shared_builtins/main"
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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: {"a_box_loads_its_own_copy_of_a_file/widget.rb" => "$boxed_widget_runs = ($boxed_widget_runs || 0) + 1\n\nclass BoxedWidget\n  def hi = \"widget \#{$boxed_widget_runs}\"\nend\n\nBOXED_WIDGET_CONST = 99\n"}, ruby: ["-W:no-experimental"])


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
      # An expression-position `box.require` used to be a compile-time
      # rejection. A TOP-LEVEL one is still spliced by the loader -- the fast,
      # statically typed path -- and everywhere else it is the ordinary send,
      # which reaches the box's run-time load path.
      root = File.join(__dir__, "a_box_loads_its_own_copy_of_a_file")
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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # `box_val_to_poly` and `box_expr_to_poly` previously fell through
      # to `sp_box_int(val)` for any pointer-typed expression they didn't
      # explicitly recognize (hashes, mutable strings, etc.), yielding
      # -Wint-conversion errors and silently truncating the pointer to a
      # 64-bit int. The fix routes pointer types through `sp_box_obj`.
      #
      # Triggers the path: a method whose return type is widened to poly
      # across branches (here: hash and string). The hash branch's
      # `return {a: 1, ...}` runs through `box_expr_to_poly`, which
      # without the fix emitted `sp_box_int(<sp_SymIntHash *>)` and gcc
      # rejected with "passing argument 1 of sp_box_int makes integer
      # from pointer without a cast".
      #
      # The test only verifies the program compiles and runs — round-
      # tripping the hash back out of the poly slot is the caller's
      # problem since the cls_id of 0 erases the concrete type.

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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("module BoxPre; def size = 99; end; class Array; prepend BoxPre; end")
      p [1,2].size
      p b.eval("[1,2].size")
    RUBY

    _(result).must_answer <<~'OUT'
      2
      99
    OUT
  end

  it "box removes only its own class method 2" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # `remove_method` in a box's `class << self` retires the box's own row and
      # leaves main's alone. The removal has to find the row first -- it asked
      # about the overlay id and was told the method did not exist.



      b = Ruby::Box.new
      b.eval("class String; def self.zz = 1; end")
      b.eval("class String; class << self; remove_method :zz; end; end")
      p(begin; b.eval("String.zz"); rescue NoMethodError; :nome; end)
      p String.respond_to?(:zz)
    RUBY

    _(result).must_answer <<~'OUT'
      :nome
      false
    OUT
  end

  it "box reopen after the first loses its mixin" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # A box's snippet names itself differently from every other eval, in three
      # places at once: the file is `eval` (not `(eval at f.rb:14)`), the snippet's
      # own scope is `<compiled>` (not the caller's), and the frame between them is
      # `Ruby::Box#eval` (not `Kernel#eval`).
      #
      # This file was filed because the same shape ABORTED the process -- the
      # emitter asserted that every box has a compile-time surrogate and a SNIPPET
      # compile has no boxes at all, and a panic cannot unwind out of `extern "C"`.
      # G7's B0 fixed that; what was left was the naming, and a computed
      # `box.eval` reaching `Kernel#eval` rather than the box's own row.
      #
      # The LITERAL form is spliced at compile time and still reports the
      # program's own file -- see `tests/gaps/a_box_literal_eval_is_spliced.rb`.
      # This file computes the source (`["K", ""].first` is opaque to the constant
      # folder) so the eval is compiled at run time.
      #
      # Oracle: the box cannot see main's `K`, so ruby raises NameError from the
      # snippet's own frame.
      K = 5
      b = Ruby::Box.new
      src = ["K", ""].first
      p b.eval(src)
    RUBY

    _(result).must_answer "", stderr: "eval:1:in '<compiled>': uninitialized constant K (NameError)\n\tfrom lang/boxes/boxes_test.rb:24:in 'Ruby::Box#eval'\n\tfrom lang/boxes/boxes_test.rb:24:in '<main>'\n", status: 1
  end

  it "box unbox local assign cond" do
    result = ze0(<<~'RUBY')
      # `infer_type(LocalVariableWriteNode)` returned the RHS's static
      # type rather than the slot's. `compile_cond_expr` uses the
      # expression type to pick between `sp_poly_truthy(...)` and a
      # direct test. Without the slot-type report, an
      # `if (sprite = arr[i])` expression where `sprite`'s slot is poly
      # (widened by other writers) but the RHS is scalar fell through
      # to a direct test on the boxed value, which gcc rejects.

      class C
        def initialize
          @arr = [10, "twenty", :thirty]   # poly_array
        end
        def find(i)
          if (entry = @arr[i])             # entry-slot is poly (widened by all the writes below)
            entry
          end
        end
      end

      c = C.new
      puts c.find(0).to_s
      puts c.find(1).to_s
    RUBY

    _(result).must_answer <<~'OUT'
      10
      twenty
    OUT
  end

  it "boxes" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


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

  it "boxes reexecute files and patch builtins privately" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: {"boxes_reexecute_files_and_patch_builtins_privately/blank.rb" => "class String\n  def blank?\n    strip.empty?\n  end\nend\nclass Foo\n  def self.blank_one?\n    \"   \".blank?\n  end\nend\nclass Counter\n  @@count = 0\n  def self.bump\n    @@count += 1\n  end\n  def self.count\n    @@count\n  end\nend\nputs \"loaded\"\n", "boxes_reexecute_files_and_patch_builtins_privately/main.rb" => "box = Ruby::Box.new\nbox.require_relative \"blank\"\nbox2 = Ruby::Box.new\nbox2.require_relative \"blank\"\np box::Foo.blank_one?\nbegin\n  \"foo\".blank?\nrescue NoMethodError => e\n  puts \"main: \#{e.message}\"\nend\nbox::Counter.bump\nbox::Counter.bump\nbox2::Counter.bump\np box::Counter.count\np box2::Counter.count\n"}, ruby: ["-W:no-experimental"])
      # Per-box re-execution (the same file `box.require`d into two boxes runs
      # twice, with independent class-variable state per box), and per-box
      # builtin MONKEYPATCHES: a box's `String#blank?` resolves from that box's
      # code while main's `"foo".blank?` stays a NoMethodError -- the docs'
      # motivating example, dispatch by DEFINING box.



      require_relative "boxes_reexecute_files_and_patch_builtins_privately/main"
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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # A `class` written in a box belongs to that box: main cannot reach it.
      #
      # zeo's boxes share one class registry, and a box's top-level class keeps
      # its bare ruby name -- `Escapee` written in a box is called `Escapee`. So
      # the registry's name table alone would hand main the box's class, which is
      # what `Object.constants` and a bare constant read both scan. A
      # `REG_MARK_BOX_CLASS` row records the box each class belongs to, and the
      # two scans that answer for a TOP LEVEL -- `Object`'s and a box
      # surrogate's -- filter on it. A program with no box emits no such row, so
      # the filter is one empty-table read.
      #
      # Two things this file used to show, both fixed: main could reach the class
      # BY NAME, and `defined?` said nil while the read answered -- the two
      # disagreeing was the tell, because the fold ran against a table the class
      # was never in.

      b = Ruby::Box.new
      b.eval("class Escapee; def self.hi = 'in box'; end")
      p defined?(Escapee)
      begin
        p Escapee
      rescue NameError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      NameError
    OUT
  end

  it "disabled box carries no gate rows" do
    result = ze0(<<~'RUBY', ruby: ["-W:no-experimental"])

      # `Ruby::Box`'s gate-only rows exist only under `RUBY_BOX=1`, as CRuby's do.
      #
      # zeo's rows live in a static table the `ruby_class!` DSL builds at compile
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      class A; def id; 1; end; end
      class B; def id; 2; end; end
      def txn; result = yield; result; end
      def ba; txn { A.new }; end
      def bb; txn { B.new }; end
      x = ba; y = bb; puts x.id; puts y.id
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
    OUT
  end

  it "main definitions are invisible inside a box" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # The other half of that line: a box IS a copy of master, so the constants
      # the runtime installed before main ran stay visible inside it -- the bare
      # read's fallback tail reaches those and stops, rather than continuing into
      # main's own `Object` table.



      VERSION_COPY = RUBY_VERSION
      box = Ruby::Box.new
      box.eval("puts RUBY_VERSION")
      box.eval("begin; p VERSION_COPY; rescue NameError; puts 'invisible'; end")
    RUBY

    _(result).must_answer <<~'OUT'
      4.0.6
      invisible
    OUT
  end

  it "module acc dispatch param box" do
    result = ze0(<<~'RUBY')
      # Issue #314 follow-up: `Mod.accessor.method(args)` (the
      # module-singleton-accessor dispatch from #126/#304) emitted
      # call-site args with raw `compile_expr` (no boxing). When the
      # resolved candidate's per-arg ptype was widened to `poly` (e.g.
      # via #304's cross-class unification), but the caller passed an
      # int/string at the specific call site, the C arg type didn't
      # match the ptype slot — Wint-conversion / hard
      # incompatible-pointer-conversion.
      #
      # Fix: in compile_call_expr's module-accessor branch, look up
      # the resolved candidate's ptypes and box each arg through
      # box_expr_to_poly when the target ptype is poly.
      #
      # Companion: scan_new_calls' #304 widening also gained a
      # parallel branch for module candidates (`<Mod>_cls_<m>` stored
      # in @meth_*) so the per-class unify reaches them.
      #
      # Surfaced via Roundhouse's `ActiveRecord.adapter.update(table,
      # @id, attrs)` — `@id` widened to poly across heterogeneous
      # subclasses, but the call site emitted `lv_id` (sp_RbVal) into
      # `InMemoryAdapter.update`'s pre-widening `mrb_int lv_id` slot.

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

      # Two call sites with different types — without #304 widening
      # reaching the module candidate, only the first caller's type
      # pinned the ptype; the second hit a C arg-type mismatch. With
      # the widening + boxing fix, the ptype unifies to poly and both
      # call sites box their arg through sp_box_int / sp_box_str.
      puts Backend.db.fetch(42)          # 2
      puts Backend.db.fetch("alpha")     # 5
    RUBY

    _(result).must_answer <<~'OUT'
      2
      5
    OUT
  end

  it "nullable array keyword box" do
    result = ze0(<<~'RUBY')
      # A nil-defaulting array-typed value boxed into a poly slot must become nil,
      # not a truthy OBJ wrapping a NULL pointer (segfault on later access) (#3275).
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
    result = ze0(<<~'RUBY')
      # #700 shape A: when a poly-widened setter receives an attr_reader
      # value from an int-typed LV (where codegen's
      # compile_int_class_fallback_expr picks the first class with the
      # attr_reader to emit `((sp_C *)lv)->iv_X`), the boxer dispatch
      # was picking sp_box_int on a `const char *` value.

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

      # Widen Comment's @commenter to sp_RbVal via case-narrow union with int.
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
    result = ze0(<<~'RUBY')
      # Issue #351: sister-to-#341. After #341 widened the per-class
      # `def [](k)` parameter to `sp_RbVal` (poly) when callers pass
      # heterogeneous key types, compile_poly_method_call's per-class
      # dispatch arm passed the raw call-site value (`const char *`,
      # `mrb_int`, ...) directly to the `sp_RbVal` parameter — gcc
      # errored `incompatible type for argument 2 of 'sp_<C>__aref'`.
      #
      # Fix: at the per-arm emit, when the arm's ptype is `poly` (base
      # type) but the call-site arg's type is concrete, wrap the arg
      # expression in `box_value_to_poly(arg_type, val)` so the
      # call-site value reaches the slot pre-boxed.
      #
      # Surfaced via Roundhouse's view-helper shape:
      # `def field_for(model, field); model[field]; end` where model is
      # poly{Article, Comment, HWIA, Parameters} and field is Symbol.

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

      # Two callers with different key types — forces the union to
      # widen sp_<C>__aref's lv_k to sp_RbVal across A and B.
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
    result = ze0(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      found
      nil
    OUT
  end

  it "ruby box surface" do
    result = ze0(<<~'RUBY', ruby: ["-W:no-experimental"])

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
      # predicates) ONLY under `RUBY_BOX=1`; zeo's are in the static table
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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # A box minted at RUN TIME, whose id the compiler never saw. Its constant
      # has to be written and read under the same box, which is the case that
      # broke when the write learned the box before the read did.



      d = [Ruby::Box.new].first
      d.eval("RUNTIME_BOX_CONST = 7")
      p d.eval("RUNTIME_BOX_CONST")
      p defined?(RUNTIME_BOX_CONST)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      nil
    OUT
  end

  it "shift operator boxes an object typed argument" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      1
      7
    OUT
  end

  it "snippet mints no compile time box" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # `Ruby::Box.new` in a SNIPPET mints a real box.
      #
      # `box = Ruby::Box.new` at a program's top level allocates a COMPILE-TIME
      # box: the loader mints it, binds the local to its surrogate, and splices
      # every `box.require` into the program. A snippet's cannot be one -- the
      # handle would name a box nothing else in the program can reach -- so it
      # stays the ordinary call, and reaches `Ruby::Box`'s own constructor,
      # which mints at run time.
      #
      # What it used to do instead is why this is written down: the loader
      # recognized `b = Ruby::Box.new` in the SNIPPET and minted a compile-time
      # box, handing back a surrogate handle to a box the program has no other
      # way to name -- and the refusal walk then declined the whole snippet
      # with "the source has a `Ruby::Box`", which was true of nothing the
      # program had written.

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
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # A top-level `def` written in a box belongs to that box: main cannot call
      # it.
      #
      # A top-level `def` is a private instance method of `Object`, and a box has
      # its OWN `Object` -- so a `def` in a box means the `class Object` reopen
      # that a box already isolates (a per-box builtin OVERLAY whose rows
      # register on the root's entry keyed by the box). Analyze wraps it into
      # exactly that; without the wrap the def fell through to the run-time
      # install, which knows one `Object`.
      #
      # The Object root had to become resolvable from a box for that to work. It
      # predates the builtin placeholders and carries neither `is_builtin` nor
      # `is_bootstrap`, so a box's name lookup skipped it and minted a SECOND
      # class called `Object` instead of an overlay of the real one.

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
    result = ze0(<<~'RUBY')
      # (`Builder.new { }` can't be used here: `.new` doesn't forward its
      # block to `initialize` yet -- a separate, pre-existing gap.)

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
