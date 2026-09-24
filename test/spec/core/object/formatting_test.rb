# frozen_string_literal: true

require "spec_helper"

describe "Object: formatting and inspection" do
  it "builtin rows report rubys signature" do
    result = zr(<<~'RUBY')
      # `Method#parameters` and `#arity` on a BUILTIN row.
      #
      # CRuby reports NO parameter name on most of its C rows, so zeo's default is
      # the anonymous descriptor its arity implies. The rows below are the ones ruby
      # DOES name -- because it writes them in Ruby (Pathname), or because its C
      # function declares a real signature -- and each carries a `ruby def` or a
      # `params "..."` spelling in the DSL to say so.
      #
      # Two rows are asymmetric on purpose:
      #   * `Kernel#require` names its parameter and `Kernel.require` does not,
      #     because CRuby defines the two separately.
      #   * a Struct WRITER's parameter is named `_`, a reader has none.

      require "pathname" # a no-op in zeo and in ruby 4.0: the class is already there
      require "tmpdir"   # what adds `Pathname.mktmpdir`

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # ---- Pathname: ruby writes it in Ruby, so every row names its parameters.
      %i[+ / == eql? basename children chmod chown cleanpath each_child each_entry
         find fnmatch? glob join mkpath open opendir read relative_path_from rename
         rmtree sub_ext truncate utime write].each do |m|
        um = Pathname.instance_method(m)
        puts "Pathname##{m}: #{um.parameters.inspect} / #{um.arity}"
      end
      %i[glob mktmpdir pwd].each do |m|
        um = Pathname.method(m)
        puts "Pathname.#{m}: #{um.parameters.inspect} / #{um.arity}"
      end
      # The private helpers are named too, and stay private.
      %i[chop_basename plus prepend_prefix same_paths? split_names].each do |m|
        um = Pathname.instance_method(m)
        puts "Pathname##{m} (private): #{um.parameters.inspect} / #{um.arity}"
      end
      show("Pathname private set") { Pathname.private_instance_methods(false).sort }
      show("Pathname protected set") { Pathname.protected_instance_methods(false).sort }

      # ---- Kernel: the seven rows ruby names.
      %i[Float Integer Pathname clone pp require warn].each do |m|
        um = Kernel.instance_method(m)
        puts "Kernel##{m}: #{um.parameters.inspect} / #{um.arity}"
      end
      show("Kernel.require") { [Kernel.method(:require).parameters, Kernel.method(:require).arity] }

      # ---- Three builtins whose C function declares a real signature.
      show("Dir#initialize") { Dir.instance_method(:initialize).parameters }
      show("Hash#initialize") { Hash.instance_method(:initialize).parameters }
      show("Time#initialize") { Time.instance_method(:initialize).parameters }

      # ---- Every exception class that declares its own `initialize` reports
      # `[[:rest]]` and -1: CRuby declares each one `argc = -1`.
      [Exception, FrozenError, Interrupt, KeyError, NameError,
       NoMatchingPatternKeyError, NoMethodError, SignalException, SyntaxError,
       SystemCallError, SystemExit, UncaughtThrowError].each do |k|
        um = k.instance_method(:initialize)
        puts "#{k}#initialize: #{um.parameters.inspect} / #{um.arity}"
      end

      # ---- A Struct accessor.
      S = Struct.new(:a, :b)
      show("S#a=") { S.instance_method(:a=).parameters }
      show("S#a") { S.instance_method(:a).parameters }
      D = Data.define(:x)
      show("D#x") { D.instance_method(:x).parameters }

      # ---- An UNNAMED row still answers the anonymous descriptor, which is ruby's
      # own answer for a C method that declares only a count.
      show("String#index") { [String.instance_method(:index).parameters, String.instance_method(:index).arity] }
      show("Array#push") { [Array.instance_method(:push).parameters, Array.instance_method(:push).arity] }

    RUBY

    _(result).must_answer <<~'OUT'
      Pathname#+: [[:req, :other]] / 1
      Pathname#/: [[:req, :other]] / 1
      Pathname#==: [[:req, :other]] / 1
      Pathname#eql?: [[:req, :other]] / 1
      Pathname#basename: [[:rest, :*], [:keyrest, :**], [:block, :&]] / -1
      Pathname#children: [[:opt, :with_directory]] / -1
      Pathname#chmod: [[:req, :mode]] / 1
      Pathname#chown: [[:req, :owner], [:req, :group]] / 2
      Pathname#cleanpath: [[:opt, :consider_symlink]] / -1
      Pathname#each_child: [[:opt, :with_directory], [:block, :b]] / -1
      Pathname#each_entry: [[:block, :block]] / 0
      Pathname#find: [[:key, :ignore_error]] / -1
      Pathname#fnmatch?: [[:req, :pattern], [:rest, :*], [:keyrest, :**], [:block, :&]] / -2
      Pathname#glob: [[:rest, :args], [:keyrest, :kwargs]] / -1
      Pathname#join: [[:rest, :args]] / -1
      Pathname#mkpath: [[:key, :mode]] / -1
      Pathname#open: [[:rest, :*], [:keyrest, :**], [:block, :&]] / -1
      Pathname#opendir: [[:block, :block]] / 0
      Pathname#read: [[:rest, :*], [:keyrest, :**], [:block, :&]] / -1
      Pathname#relative_path_from: [[:req, :base_directory]] / 1
      Pathname#rename: [[:req, :to]] / 1
      Pathname#rmtree: [[:key, :noop], [:key, :verbose], [:key, :secure]] / -1
      Pathname#sub_ext: [[:req, :repl]] / 1
      Pathname#truncate: [[:req, :length]] / 1
      Pathname#utime: [[:req, :atime], [:req, :mtime]] / 2
      Pathname#write: [[:rest, :*], [:keyrest, :**], [:block, :&]] / -1
      Pathname.glob: [[:rest, :args], [:keyrest, :kwargs]] / -1
      Pathname.mktmpdir: [] / 0
      Pathname.pwd: [] / 0
      Pathname#chop_basename (private): [[:req, :path]] / 1
      Pathname#plus (private): [[:req, :path1], [:req, :path2]] / 2
      Pathname#prepend_prefix (private): [[:req, :prefix], [:req, :relpath]] / 2
      Pathname#same_paths? (private): [[:req, :a], [:req, :b]] / 2
      Pathname#split_names (private): [[:req, :path]] / 1
      Pathname private set: [:add_trailing_separator, :chop_basename, :cleanpath_aggressive, :cleanpath_conservative, :del_trailing_separator, :has_trailing_separator?, :initialize, :plus, :prepend_prefix, :same_paths?, :split_names]
      Pathname protected set: [:path]
      Kernel#Float: [[:req, :arg], [:key, :exception]] / -2
      Kernel#Integer: [[:req, :arg], [:opt, :base], [:key, :exception]] / -2
      Kernel#Pathname: [[:req, :path]] / 1
      Kernel#clone: [[:key, :freeze]] / -1
      Kernel#pp: [[:rest, :objs]] / -1
      Kernel#require: [[:req, :path]] / 1
      Kernel#warn: [[:rest, :msgs], [:key, :uplevel], [:key, :category]] / -1
      Kernel.require: [[[:req]], 1]
      Dir#initialize: [[:req, :name], [:key, :encoding]]
      Hash#initialize: [[:opt, :ifnone], [:key, :capacity], [:block, :block]]
      Time#initialize: [[:opt, :year], [:opt, :mon], [:opt, :mday], [:opt, :hour], [:opt, :min], [:opt, :sec], [:opt, :zone], [:key, :in], [:key, :precision]]
      Exception#initialize: [[:rest]] / -1
      FrozenError#initialize: [[:rest]] / -1
      Interrupt#initialize: [[:rest]] / -1
      KeyError#initialize: [[:rest]] / -1
      NameError#initialize: [[:rest]] / -1
      NoMatchingPatternKeyError#initialize: [[:rest]] / -1
      NoMethodError#initialize: [[:rest]] / -1
      SignalException#initialize: [[:rest]] / -1
      SyntaxError#initialize: [[:rest]] / -1
      SystemCallError#initialize: [[:rest]] / -1
      SystemExit#initialize: [[:rest]] / -1
      UncaughtThrowError#initialize: [[:rest]] / -1
      S#a=: [[:req, :_]]
      S#a: []
      D#x: []
      String#index: [[[:rest]], -1]
      Array#push: [[[:rest]], -1]
    OUT
  end

  it "clone carries the singleton class" do
    result = zr(<<~'RUBY')
      # Object#clone copies the receiver's singleton class (dup deliberately does
      # not). zeo's clone builds a plain copy of the underlying object, so a
      # singleton method defined on the original is gone on the clone -- the copy
      # answers the class's method instead.
      class Cloneable
        def greet
          "base"
        end
      end

      o = Cloneable.new
      def o.greet
        "singleton " + super
      end

      puts o.greet
      puts o.clone.greet
      puts o.dup.greet
      puts o.clone.singleton_methods.inspect
      puts o.dup.singleton_methods.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      singleton base
      singleton base
      base
      [:greet]
      []
    OUT
  end

  it "default object inspect and to s carry address and ivars" do
    result = zr(<<~'RUBY')
      # Default (no override) `to_s` is `#<Class:0xADDR>`; `inspect` adds the
      # ivars as `@name=<inspected>` in declaration order. Addresses are
      # normalized in-program (as the corpus tests do) so the expectation is
      # stable. A frozen-mutation FrozenError message carries the same inspect.

      def norm(s) = s.gsub(/0x[0-9a-f]+/, "0xADDR")
      class Widget
        def initialize(n); @name = n; @size = 3; end
      end
      w = Widget.new("gadget")
      puts norm(w.to_s)
      puts norm(w.inspect)
      class Empty; end
      puts norm(Empty.new.inspect)
      puts norm(Object.new.inspect)
      class Frozen
        attr_accessor :v
        def initialize; @v = 1; freeze; end
      end
      begin
        Frozen.new.v = 2
      rescue FrozenError => e
        puts norm(e.message)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<Widget:0xADDR>
      #<Widget:0xADDR @name="gadget", @size=3>
      #<Empty:0xADDR>
      #<Object:0xADDR>
      can't modify frozen Frozen: #<Frozen:0xADDR @v=1>
    OUT
  end

  it "definition whose namespace is a runtime value" do
    result = zr(<<~'RUBY')
      # `class <expr>::Name` -- a definition whose NAMESPACE is a runtime value
      # rather than a constant path. Four spellings in the corpus, all the same
      # thing said differently, and zeo used to reject every one of them with
      # "expected a constant name or path":
      #
      #   class self::Task            (inside an `included do ... end` hook)
      #   class parent::Pagination    (a local, jekyll-localization)
      #   module Wires.current_network::Namespace
      #   module Num[16]::Trigonometry            (flt)
      #
      # JRuby's lowercase java packages are the same shape once more:
      # `class org::jrubyparser::ast::CallNode` parses `org::jrubyparser` as a CALL,
      # not a constant path, so lowering the namespace as an expression gives the
      # `NameError` on `org` that CRuby raises when the definition runs.
      module Host; end

      def current = Host
      parent = Host
      INDEXED = [Host]

      class parent::Pag
        def self.hi = "from a local"
      end

      module current::Ns
        def self.v = "from a method"
      end

      class INDEXED[0]::Deep < String
        def self.hi = "from an index"
      end

      Host.instance_eval do
        module self::Hooked
          def self.hi = "from self"
        end
      end

      module Host.itself::Nested
        module Inner
          def self.go = "nested inner"
        end

        def self.direct = "nested direct"
      end

      p Host::Pag.hi
      p Host::Pag.name
      p Host::Ns.v
      p Host::Ns.name
      p Host::Deep.hi
      p Host::Deep.superclass
      p Host::Hooked.hi
      p Host::Nested::Inner.go
      p Host::Nested.direct
      p Host.constants.map(&:to_s).sort

      # The namespace expression is evaluated where the definition is written, so a
      # raise there is the definition's raise.
      begin
        class org::foo::Bar
        end
      rescue NameError => e
        puts e.message
      end
      p defined?(Host::Missing).nil?
    RUBY

    _(result).must_answer <<~'OUT'
      "from a local"
      "Host::Pag"
      "from a method"
      "Host::Ns"
      "from an index"
      String
      "from self"
      "nested inner"
      "nested direct"
      ["Deep", "Hooked", "Nested", "Ns", "Pag"]
      undefined local variable or method 'org' for main
      true
    OUT
  end

  it "dollar star is argv" do
    result = zr(<<~'RUBY')
      # `$*` is an alias of ARGV. zeo maps ARGV but leaves $* an ordinary
      # (nil-valued) global.
      puts $*.inspect
      puts ARGV.inspect
      puts ($*.equal?(ARGV)).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      true
    OUT
  end

  it "inspect" do
    result = zr(<<~'RUBY')
      # Primitives: .inspect as a method call

      # Integer
      puts 5.inspect
      puts (-42).inspect
      puts 0.inspect

      # Float
      puts 1.5.inspect
      puts 1.0.inspect
      puts (-3.25).inspect

      # String
      puts "hi".inspect
      puts "".inspect
      puts "a\nb".inspect
      puts "tab\there".inspect
      puts "quote\"inside".inspect
      puts "back\\slash".inspect

      # Symbol (regression)
      puts :foo.inspect

      # Boolean
      puts true.inspect
      puts false.inspect

      # nil
      puts nil.inspect

      # Interpolation via explicit .inspect call
      x = 42
      puts "got #{x.inspect}"

      # Kernel#p equivalence: p obj == puts(obj.inspect) for scalars
      p 5
      p 1.0
      p "hi"
      p :foo
      p true
      p nil

      # Arrays: .inspect + p
      p []
      p [1, 2, 3]
      p [-5, 0, 42]
      p [99]
      p [1.5, 2.0]
      p [1.0]
      p ["hello", "world"]
      p [""]
      p [:foo, :bar]

      # Heterogeneous / mixed-type arrays (poly_array)
      p [1, "x"]
      p [nil, :sym, 1.5]
      p [1, "two", :three, 4.0, true]
      p [false, nil]

      # Mixed arrays as a receiver (inspect / to_s as methods)
      mx = [1, "x"]
      puts mx.inspect
      puts mx.to_s

      # Array#inspect as a method call
      arr = [1, 2, 3]
      puts arr.inspect

      # Array#to_s is aliased to Array#inspect in CRuby
      puts arr.to_s

      # Interpolation uses to_s
      puts "got #{arr.inspect}"

      # From a method returning an array
      def make_arr; [10, 20, 30]; end
      p make_arr

      # puts on arrays: flatten, element-per-line (not inspect)
      puts [1, 2, 3]
      puts []
      puts ["a", "b"]
      puts [:x, :y]
      puts [1.5, 2.0]

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      -42
      0
      1.5
      1.0
      -3.25
      "hi"
      ""
      "a\nb"
      "tab\there"
      "quote\"inside"
      "back\\slash"
      :foo
      true
      false
      nil
      got 42
      5
      1.0
      "hi"
      :foo
      true
      nil
      []
      [1, 2, 3]
      [-5, 0, 42]
      [99]
      [1.5, 2.0]
      [1.0]
      ["hello", "world"]
      [""]
      [:foo, :bar]
      [1, "x"]
      [nil, :sym, 1.5]
      [1, "two", :three, 4.0, true]
      [false, nil]
      [1, "x"]
      [1, "x"]
      [1, 2, 3]
      [1, 2, 3]
      got [1, 2, 3]
      [10, 20, 30]
      1
      2
      3
      a
      b
      x
      y
      1.5
      2.0
      done
    OUT
  end

  it "inspect element reaches container" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A container holding itself, which is what the golden inspects.
      # At exit: cycle leak: 2 objects (Array x1, Hash x1)
      # An element's `inspect`/`to_s` may read the very container being printed.
      #
      # The `seen` stack guards a container that contains ITSELF (`a << a` prints
      # `[...]`), but it cannot guard this: the recursion leaves through a USER
      # method, which reaches the container by another name entirely. Rendering
      # therefore must not hold the payload lock across the element dispatch --
      # a non-reentrant Mutex turns that into a silent hang, with no output and
      # no error, which is how it escaped notice.
      class Peeker
        def inspect
          "<#{$arr.length}>"
        end

        def to_s
          "<s#{$arr.length}>"
        end
      end

      $arr = [Peeker.new, 2]
      p $arr
      puts $arr.to_s
      puts "#{$arr}"

      class HashPeeker
        def inspect
          "<#{$h.size}>"
        end
      end

      $h = { k: HashPeeker.new, j: 2 }
      p $h
      puts $h.to_s

      # The element reaches a DIFFERENT container that in turn holds the first,
      # so the two renderings interleave without either being self-referential.
      class CrossPeeker
        def inspect
          "<#{$other.length}>"
        end
      end

      $other = [1, 2, 3]
      p [CrossPeeker.new, $other]

      # Still prints the cycle marker when the container really does contain
      # itself -- the snapshot must not cost us that.
      cyc = [1]
      cyc << cyc
      p cyc

      hcyc = {}
      hcyc[:self] = hcyc
      p hcyc
    RUBY

    _(result).must_answer <<~'OUT'
      [<2>, 2]
      [<2>, 2]
      [<2>, 2]
      {k: <2>, j: 2}
      {k: <2>, j: 2}
      [<3>, [1, 2, 3]]
      [1, [...]]
      {self: {...}}
    OUT
  end

  it "inspect ivar filter" do
    result = zr(<<~'RUBY')
      # Kernel#instance_variables_to_inspect: nil = every ivar; an Array is a
      # MEMBERSHIP filter over the object's own ivar order (oracle-pinned: the
      # array's order does not reorder, strings never match, non-Array raises).
      p Kernel.private_instance_methods(false).include?(:instance_variables_to_inspect)

      class Plain
        def initialize = (@a = 1)
      end
      p Plain.new.inspect.sub(/0x[0-9a-f]+/, "0xADDR")

      class Filtered
        def initialize
          @a = 1
          @b = 2
          @secret = "s3cr3t"
        end
        private def instance_variables_to_inspect = [:@b, :@a, :@missing]
      end
      p Filtered.new.inspect.sub(/0x[0-9a-f]+/, "0xADDR")

      class Hidden
        def initialize = (@a = 1)
        private def instance_variables_to_inspect = []
      end
      p Hidden.new.inspect.sub(/0x[0-9a-f]+/, "0xADDR")

      class Strings
        def initialize = (@a = 1)
        private def instance_variables_to_inspect = ["@a"]
      end
      p Strings.new.inspect.sub(/0x[0-9a-f]+/, "0xADDR")

      class Wrong
        def initialize = (@a = 1)
        private def instance_variables_to_inspect = 5
      end
      begin
        Wrong.new.inspect
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "#<Plain:0xADDR @a=1>"
      "#<Filtered:0xADDR @a=1, @b=2>"
      "#<Hidden:0xADDR>"
      "#<Strings:0xADDR>"
      Expected #instance_variables_to_inspect to return an Array or nil, but it returned Integer
    OUT
  end

  it "is a walks the cruby chains" do
    result = zr(<<~'RUBY')
      # The hierarchy is live in `is_a?`/`kind_of?`/`instance_of?` -- statically
      # folded sites AND the runtime path through a Poly receiver, plus a user
      # class inheriting the full Object tail. Every line oracle-verified.

      class Widget; end

      puts 5.is_a?(Comparable)
      puts 5.is_a?(Numeric)
      puts 5.is_a?(BasicObject)
      puts 3.14.is_a?(Numeric)
      puts "s".is_a?(Comparable)
      puts [].is_a?(Kernel)
      puts nil.is_a?(BasicObject)
      puts 5.kind_of?(Comparable)
      puts 5.instance_of?(Numeric)
      puts [5].first.is_a?(Numeric)
      puts Widget.new.is_a?(Kernel)
      puts Widget.ancestors.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      false
      true
      true
      [Widget, Object, Kernel, BasicObject]
    OUT
  end

  it "issue anonymous module inspect" do
    result = zr(<<~'RUBY')
      # Two compounding divergences in the default inspect of an anonymous
      # Class/Module: (1) an anonymous Module renders as `#<Class:0x...>` instead
      # of `#<Module:0x...>` -- zeo doesn't distinguish the two; (2) the address
      # zeo renders is a short sequential counter (`0x40000000`) rather than a
      # real pointer padded to 16 hex digits like every other object's default
      # inspect, so it never matches the golden's `0xADDR` address-normalization
      # even once the Module/Class mislabeling above is fixed.
      m = Module.new
      puts m.to_s
      puts m.inspect
      puts Class.new.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      #<Module:0xADDR>
      #<Module:0xADDR>
      #<Class:0xADDR>
    OUT
  end

  it "method inspect forwarding" do
    result = zr(<<~'PROGRAM')
      # The anonymous forwarding parameters (`*`, `**`, `&`, and the `...` that means
      # all three) in `#parameters` and in `#inspect`'s signature. Ruby names each
      # anonymous slot for its own sigil, and renders the group with rules that are
      # not simply "print what was written" -- every combination is pinned here.
      def s(m) = m.inspect.sub(/ [^ ]+:\d+>\z/, ">")

      class S
        def a(*, **, &) = 1
        def b(x, *, **, &) = 1
        def c(*) = 1
        def d(**) = 1
        def e(&) = 1
        def f(*, **) = 1
        def g(*, &) = 1
        def h(**, &) = 1
        def i(...) = 1
        def j(x, ...) = 1
        def k(*r, **kw, &blk) = 1
        def l(x, *, y) = 1
      end
      %i[a b c d e f g h i j k l].each { |n| puts "#{n}: #{s(S.instance_method(n))}" }
      %i[a b c d e f g h i j k l].each { |n| puts "#{n}: #{S.instance_method(n).parameters.inspect}" }

      # `...` forwards positionals, keywords and the block -- through a def the
      # compiler saw, and through one an eval built at runtime.
      class T
        def target(a, b = 2, *r, k: 3, &blk) = [a, b, r, k, blk&.call]
        def fwd(...) = target(...)
        eval <<~RUBY
          def fwd_eval(...)
            target(...)
          end
        RUBY
      end
      p T.new.fwd(1)
      p T.new.fwd(1, 9, 8, k: 7) { :blk }
      p T.new.fwd_eval(1)
      p T.new.fwd_eval(1, 9, 8, k: 7) { :blk }
    PROGRAM

    _(result).must_answer <<~'OUT'
      a: #<UnboundMethod: S#a(...)>
      b: #<UnboundMethod: S#b(x, *, ...)>
      c: #<UnboundMethod: S#c(*)>
      d: #<UnboundMethod: S#d(**)>
      e: #<UnboundMethod: S#e(...)>
      f: #<UnboundMethod: S#f(*)>
      g: #<UnboundMethod: S#g(*, ...)>
      h: #<UnboundMethod: S#h(**, ...)>
      i: #<UnboundMethod: S#i(...)>
      j: #<UnboundMethod: S#j(x, *, ...)>
      k: #<UnboundMethod: S#k(*r, **kw, &blk)>
      l: #<UnboundMethod: S#l(x, *, y)>
      a: [[:rest, :*], [:keyrest, :**], [:block, :&]]
      b: [[:req, :x], [:rest, :*], [:keyrest, :**], [:block, :&]]
      c: [[:rest, :*]]
      d: [[:keyrest, :**]]
      e: [[:block, :&]]
      f: [[:rest, :*], [:keyrest, :**]]
      g: [[:rest, :*], [:block, :&]]
      h: [[:keyrest, :**], [:block, :&]]
      i: [[:rest, :*], [:keyrest, :**], [:block, :&]]
      j: [[:req, :x], [:rest, :*], [:keyrest, :**], [:block, :&]]
      k: [[:rest, :r], [:keyrest, :kw], [:block, :blk]]
      l: [[:req, :x], [:rest, :*], [:req, :y]]
      [1, 2, [], 3, nil]
      [1, 9, [8], 7, :blk]
      [1, 2, [], 3, nil]
      [1, 9, [8], 7, :blk]
    OUT
  end

  it "method inspect native" do
    result = zr(<<~'RUBY')
      # A body installed at RUNTIME reports its own signature. `def obj.m(x, y = 1)`,
      # `define_method`, `define_singleton_method`, and a `class_eval`-`def` all
      # install a proc that knows its parameters, and `#arity`/`#parameters`/`#inspect`
      # each read them back -- keyed by the object for a per-object singleton, so one
      # object's `def obj.m` never describes another instance of the same class.
      def shape(m) = [m.arity, m.parameters]
      def printed(m) = m.inspect.sub(/ [^ ]+:\d+>\z/, ">").sub(/0x[0-9a-f]+/, "ADDR")

      class Widget; end
      w = Widget.new
      def w.only(x, y = 1) = x
      p shape(w.method(:only))
      p printed(w.method(:only))

      w.define_singleton_method(:dsm) { |a, *r, k: 1, &b| }
      p shape(w.method(:dsm))
      p printed(w.method(:dsm))

      # A singleton on a non-object heap value.
      A = [1]
      def A.pick(i, j = 0) = i
      p shape(A.method(:pick))

      # A runtime class: both its instance methods and its class methods.
      K = Class.new do
        define_method(:pair) { |a, b = 2, *r| }
        def self.cm(q, *s); end
      end
      p shape(K.instance_method(:pair))
      p printed(K.instance_method(:pair))
      p shape(K.method(:cm))
      p printed(K.method(:cm))

      # A compiled class reopened at runtime.
      class Reop; end
      Reop.define_method(:dm) { |a, b:, **o| }
      p shape(Reop.instance_method(:dm))
      p printed(Reop.new.method(:dm))
      Reop.define_singleton_method(:sdm) { |z = 3| }
      p shape(Reop.method(:sdm))

      # An override replaces the recorded signature.
      Reop.define_method(:dm) { |single| }
      p shape(Reop.instance_method(:dm))

      class Late; end
      Late.class_eval { def ce(u, v = 1); end }
      p shape(Late.instance_method(:ce))

      # A per-object singleton shadows the class's method of the same name -- for
      # that object only.
      class Shadow
        def m(a, b); end
      end
      s = Shadow.new
      def s.m(only_one); end
      p printed(s.method(:m))
      p printed(Shadow.new.method(:m))
      p printed(Shadow.instance_method(:m))

      # A compiled `def` and a builtin still report what they always did.
      class Plain
        def sig(a, b = 1, *c, d:, e: 2, **f, &g); end
      end
      p shape(Plain.instance_method(:sig))
      p [3.method(:between?).arity, [].method(:push).arity]
    RUBY

    _(result).must_answer <<~'OUT'
      [-2, [[:req, :x], [:opt, :y]]]
      "#<Method: #<Widget:ADDR>.only(x, y=...)>"
      [-2, [[:req, :a], [:rest, :r], [:key, :k], [:block, :b]]]
      "#<Method: #<Widget:ADDR>.dsm(a, *r, k: ..., &b)>"
      [-2, [[:req, :i], [:opt, :j]]]
      [-2, [[:req, :a], [:opt, :b], [:rest, :r]]]
      "#<UnboundMethod: K#pair(a, b=..., *r)>"
      [-2, [[:req, :q], [:rest, :s]]]
      "#<Method: K.cm(q, *s)>"
      [2, [[:req, :a], [:keyreq, :b], [:keyrest, :o]]]
      "#<Method: Reop#dm(a, b:, **o)>"
      [-1, [[:opt, :z]]]
      [1, [[:req, :single]]]
      [-2, [[:req, :u], [:opt, :v]]]
      "#<Method: #<Shadow:ADDR>.m(only_one)>"
      "#<Method: Shadow#m(a, b)>"
      "#<UnboundMethod: Shadow#m(a, b)>"
      [-3, [[:req, :a], [:opt, :b], [:rest, :c], [:keyreq, :d], [:key, :e], [:keyrest, :f], [:block, :g]]]
      [2, -1]
    OUT
  end

  it "method inspect shapes" do
    result = zr(<<~'RUBY')
      # `Method#inspect` / `UnboundMethod#inspect` name where a method LIVES, how it
      # was reached, and what it takes. The location tail is this file's path, so
      # every assertion below strips it -- what is being pinned is the shape in
      # front of it.
      #
      # Three divergences this file deliberately steps around, all in the rendering
      # of methods zeo did not compile from Ruby source:
      #
      #   * CRuby reports a location for the parts of ITSELF written in Ruby
      #     (`#<Method: Integer#zero?() <internal:numeric>:288>`); zeo's are native,
      #     so they print unlocated. zeo's `Integer#zero?` also lives on `Numeric`,
      #     so it prints `Integer(Numeric)#zero?`. Both are declines: they describe
      #     CRuby's own source tree, which zeo does not have.
      #   * A per-object singleton (`def obj.m(x)`) is a runtime-defined body here
      #     and reports no signature at all -- a real gap, tracked at
      #     `tests/gaps/method_inspect_native.rb`.
      #   * A native method with no declared arity prints the variadic `(*)` where
      #     CRuby knows the real count.
      #
      # The anonymous forwarding slots (`*`/`**`/`&`/`...`) DO match, and are pinned
      # in `tests/method_inspect_forwarding.rb`.
      #
      # Everything below is a method zeo compiled, or a native one whose arity is
      # declared -- the surface an inspect implementation is actually responsible for.

      def shape(m) = m.inspect.sub(/ [^ ]+:\d+>\z/, ">")

      # --- an instance method: its own class, then the ancestor that defines it ---
      class Base
        def greet = "base"
      end
      class Sub < Base
        def greet = "sub"
      end
      class Quiet < Base; end

      p shape(Sub.new.method(:greet))
      p shape(Quiet.new.method(:greet))
      p shape(Sub.new.method(:greet).super_method)

      # A module in the chain is named the same way.
      module Loud
        def shout = "!"
      end
      class Speaker
        include Loud
      end
      p shape(Speaker.new.method(:shout))

      # --- the signature, in Ruby's own `def` spelling -----------------------------
      class Sig
        def none = 1
        def req(a, b) = a
        def opt(a, b = 1) = a
        def rest(a, *r) = a
        def kw(a, k:, j: 2) = a
        def kwrest(**kw) = kw
        def blk(&b) = b
        def every(a, b = 1, *r, c, k:, j: 2, **kw, &blk) = a
      end
      %i[none req opt rest kw kwrest blk every].each do |name|
        p shape(Sig.new.method(name))
      end

      # --- a class method prints a `.`, and qualifies an inherited one -------------
      module Api
        def self.fetch(url) = url
      end
      class Store
        def self.open(path, mode = "r") = path
      end
      class Cache < Store; end

      p shape(Api.method(:fetch))
      p shape(Store.method(:open))
      p shape(Cache.method(:open))

      # --- a per-object singleton names the RECEIVER, not a class ------------------
      class Widget
        def to_s = "a widget"
        def inspect = "#<Widget custom>"
      end
      w = Widget.new
      def w.only = 1
      p shape(w.method(:only))

      # --- natively defined methods: arity placeholders, and no location -----------
      p [].method(:each).inspect
      p "".method(:sub).inspect
      p 1.method(:+).inspect
      p Hash.instance_method(:store).inspect
      p Array.method(:try_convert).inspect

      # --- unbound: the OWNER alone, never the class it was fetched from -----------
      p shape(Sub.instance_method(:greet))
      p shape(Quiet.instance_method(:greet))
      p shape(Speaker.instance_method(:shout))
      p shape(Sig.instance_method(:every))
      p shape(Sub.new.method(:greet).unbind)
      p shape(method(:shape).unbind)

      # --- a top-level def lives on Object -----------------------------------------
      def helper(n, verbose: false) = n
      p shape(method(:helper))
      p shape(Object.instance_method(:helper))

      # `to_s` is the same string.
      p Sub.new.method(:greet).to_s == Sub.new.method(:greet).inspect
      p Sub.instance_method(:greet).to_s == Sub.instance_method(:greet).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "#<Method: Sub#greet()>"
      "#<Method: Quiet(Base)#greet()>"
      "#<Method: Base#greet()>"
      "#<Method: Speaker(Loud)#shout()>"
      "#<Method: Sig#none()>"
      "#<Method: Sig#req(a, b)>"
      "#<Method: Sig#opt(a, b=...)>"
      "#<Method: Sig#rest(a, *r)>"
      "#<Method: Sig#kw(a, k:, j: ...)>"
      "#<Method: Sig#kwrest(**kw)>"
      "#<Method: Sig#blk(&b)>"
      "#<Method: Sig#every(a, b=..., *r, c, k:, j: ..., **kw, &blk)>"
      "#<Method: Api.fetch(url)>"
      "#<Method: Store.open(path, mode=...)>"
      "#<Method: Cache(Store).open(path, mode=...)>"
      "#<Method: #<Widget custom>.only()>"
      "#<Method: Array#each()>"
      "#<Method: String#sub(*)>"
      "#<Method: Integer#+(_)>"
      "#<UnboundMethod: Hash#store(_, _)>"
      "#<Method: Array.try_convert(_)>"
      "#<UnboundMethod: Sub#greet()>"
      "#<UnboundMethod: Base#greet()>"
      "#<UnboundMethod: Loud#shout()>"
      "#<UnboundMethod: Sig#every(a, b=..., *r, c, k:, j: ..., **kw, &blk)>"
      "#<UnboundMethod: Sub#greet()>"
      "#<UnboundMethod: Object#shape(m)>"
      "#<Method: Object#helper(n, verbose: ...)>"
      "#<UnboundMethod: Object#helper(n, verbose: ...)>"
      true
      true
    OUT
  end

  it "nil receiver tap then" do
    result = zr(<<~'RUBY')
      puts nil.tap { |x| x }.inspect
      puts nil.then { |x| x }.inspect
      p nil.then { |x| x.nil? ? 42 : 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      42
    OUT
  end

  it "nullable int to s evaluates once" do
    result = zr(<<~'RUBY')
      # `<nullable int>.to_s` / `.inspect` must evaluate its receiver exactly once.
      # It lowers to a test-then-convert (`x == SP_INT_NIL ? "" : to_s(x)`); a naive
      # emit inlines the receiver twice, so a side-effecting receiver (a counter
      # bump, an I/O read) runs twice and yields the wrong value.
      $n = 0
      def step
        $n = $n + 1
        $n
      end

      puts step.to_s        # 1
      puts step.to_s        # 2
      puts step.inspect     # 3
      puts $n.to_s          # 3 -- exactly three bumps, not six
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      3
    OUT
  end

  it "instance_variables and inspect report the ivars in assignment order, minted class or compiled" do
    result = zr(<<~'RUBY')
      # An object's instance variables are reported in ASSIGNMENT order -- by
      # `instance_variables` and by the `inspect` built on it. For a class minted at
      # run time, zeo reports them in hash order instead.
      #
      # A compiled class gets a generated struct whose fields are laid out in source
      # order, so its objects already answer correctly (the first pair below). A
      # `Class.new` instance is a `runtime_meta::DynObject`, whose ivars live in a
      # `FMap` -- foldhash, deliberately unordered -- so the order it reports is
      # whatever the hash produced, and it is not even stable across ivar names.
      #
      # Ruby's order is a property of the OBJECT, not the class: an ivar assigned
      # later appears later, including one added after construction. That is what
      # makes `p obj` stable enough to diff, which is most of what `inspect` is for --
      # and a runtime-built class is exactly the kind a fixture or a factory produces.

      class Compiled
        def initialize
          @a = 1
          @b = "s"
          @c = :z
        end
      end
      p Compiled.new.instance_variables
      puts Compiled.new.inspect.sub(/0x\h+/, "0xADDR")

      Runtime = Class.new do
        def initialize
          @a = 1
          @b = "s"
          @c = :z
        end
      end
      p Runtime.new.instance_variables
      puts Runtime.new.inspect.sub(/0x\h+/, "0xADDR")

      r = Runtime.new
      r.instance_variable_set(:@d, 4)
      p r.instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      [:@a, :@b, :@c]
      #<Compiled:0xADDR @a=1, @b="s", @c=:z>
      [:@a, :@b, :@c]
      #<Runtime:0xADDR @a=1, @b="s", @c=:z>
      [:@a, :@b, :@c, :@d]
    OUT
  end

  it "proc inspect identity" do
    result = zr(<<~'RUBY')
      # `Proc#inspect` identifies the proc: its address, where it was written, and
      # whether it is a lambda -- `#<Proc:0x000...7318 /path/to/file.rb:3>`, with
      # ` (lambda)` appended for one. zeo answers a bare `#<Proc>` for every proc in
      # the program, so no two are distinguishable.
      #
      # The information is all present: zeo already reports `Proc#source_location`
      # and `#lambda?` correctly (both below), and every other heap value's `inspect`
      # carries an address. Only the assembled string is missing.
      #
      # It matters where procs are data rather than control flow -- a callback
      # registry, a middleware stack, a `Hash` of handlers -- because `p handlers`
      # then prints a column of identical `#<Proc>` with nothing to tell them apart.

      pr = proc { }
      la = lambda { }

      p pr.lambda?
      p la.lambda?
      p pr.source_location&.last
      p la.source_location&.last

      puts pr.inspect.sub(/0x\h+/, "0xADDR").sub(/[^ ]+\.rb/, "FILE")
      puts la.inspect.sub(/0x\h+/, "0xADDR").sub(/[^ ]+\.rb/, "FILE")

      # Two distinct procs must not inspect identically.
      a = proc { }
      b = proc { }
      p a.inspect == b.inspect

      p :sym.to_proc.lambda?
      p method(:puts).to_proc.lambda?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      14
      15
      #<Proc:0xADDR FILE:14>
      #<Proc:0xADDR FILE:15 (lambda)>
      false
      true
      true
    OUT
  end

  it "singleton body is a lexical scope" do
    result = zr(<<~'RUBY')
      # A `def` written in a constant-bearing `class << self` body is lexically
      # inside the SINGLETON class. Its bare constants and `Module.nesting` resolve
      # through the surrogate, whose lexical parent is the class itself -- so the
      # rest of the chain is unchanged, and dispatch/ivars/`super` keep using the
      # owner.

      module Outer
        PLAIN = :module_const
        SHADOWED = :from_module
        class << self
          SC = :singleton_const
          SHADOWED = :from_singleton
          def both = [SC, PLAIN, SHADOWED]
          def nest = Module.nesting.map(&:to_s)
        end
      end
      p Outer.both
      p Outer.nest

      # A class method written OUTSIDE the singleton body cannot see the
      # singleton's constant by bare name.
      module Outer
        def self.blind
          SC
        rescue NameError
          :name_error
        end
      end
      p Outer.blind

      # Nesting depth: the surrogate joins the full lexical chain.
      module A
        ROOT = :a_const
        module B
          INNER_MOD = :b_const
          class << self
            INNER = :inner
            def chain = [INNER, INNER_MOD, ROOT]
            def nest = Module.nesting.map(&:to_s)
          end
        end
      end
      p A::B.chain
      p A::B.nest

      # `Module.nesting` outside any body, and in an ordinary class body.
      p Module.nesting
      class Plain
        NEST = Module.nesting.map(&:to_s)
        def self.nest = Module.nesting.map(&:to_s)
      end
      p Plain::NEST
      p Plain.nest

      # Reflection agrees: the constant lives on the singleton, not the module.
      p Outer.singleton_class.const_get(:SC)
      p [Outer.const_defined?(:SC), Outer.singleton_class.const_defined?(:SC)]
    RUBY

    _(result).must_answer <<~'OUT'
      [:singleton_const, :module_const, :from_singleton]
      ["#<Class:Outer>", "Outer"]
      :name_error
      [:inner, :b_const, :a_const]
      ["#<Class:A::B>", "A::B", "A"]
      []
      ["Plain"]
      ["Plain"]
      :singleton_const
      [false, true]
    OUT
  end

  it "to s renders the canonical opts body form and inspect the literal form" do
    result = zr(<<~'RUBY')
      r = /abc/x
      puts r.to_s
      r2 = /a.c/im
      puts r2.to_s
      puts(/abc/x.inspect)
      puts(/abc/mi.inspect)
    RUBY

    _(result).must_answer <<~'OUT'
      (?x-mi:abc)
      (?mi-x:a.c)
      /abc/x
      /abc/mi
    OUT
  end

  it "tuple inspect" do
    result = zr(<<~'RUBY')
      # Issues #724, #726. Tuples (fixed-arity return types from
      # Integer#divmod, Array#minmax, String#partition, etc.) used to fall
      # through to the unresolved-call warning when passed to inspect.
      # Now any tuple type goes through the generic tuple-inspect builder.

      puts [1, 2, 3].minmax.inspect              # tuple:int,int
      puts 17.divmod(5).inspect                   # tuple:int,int
      puts "hello world".partition(" ").inspect  # tuple:string,string,string
      puts "abc".rpartition("b").inspect         # tuple:string,string,string
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      [3, 2]
      ["hello", " ", "world"]
      ["a", "b", "c"]
    OUT
  end

  it "value type interp to s" do
    result = zr(<<~'RUBY')
      class Point
        def initialize(x)
          @x = x
        end
        def to_s
          "P#{@x}"
        end
      end
      pt = Point.new(3)
      puts "point: #{pt}"
    RUBY

    _(result).must_answer "point: P3\n"
  end
end
