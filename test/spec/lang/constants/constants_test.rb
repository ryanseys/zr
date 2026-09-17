# frozen_string_literal: true

require "spec_helper"

describe "Constants programs" do
  it "bare constant searches every enclosing scope" do
    result = ze0(<<~'RUBY')
      # Ruby resolves a bare constant by searching every entry of `Module.nesting`
      # outward, then the cref's ancestors, then Object. zeo's emitted lookup jumped
      # straight from the innermost scope to the top, so any name the compile-time
      # owner map cannot place -- every constant on a class built at RUNTIME -- was
      # searched for in two scopes where Ruby searches three or more.
      #
      # jmespath hit it: `class Parser` in `module JMESPath` reads
      # `Token::BINDING_POWER`, and `Token` is a `Struct.new` subclass, so the lookup
      # asked `JMESPath::Parser` and `Object`, skipped `JMESPath`, and raised.
      module M
        class Reader
          def table
            Holder::TABLE[:star]
          end

          def deep
            Inner::Deeper.new.reach
          end
        end

        # Built at runtime, so no compile-time owner places `Holder`.
        Holder = Class.new
        Holder.const_set(:TABLE, { star: 42 })

        module Inner
          class Deeper
            # Two scopes out: Deeper -> Inner -> M.
            def reach
              Holder::TABLE[:star] + 1
            end
          end
        end
      end

      p M::Reader.new.table
      p M::Reader.new.deep
      p M::Inner::Deeper.new.reach

      # The qualified form does NOT see the path prefix's constants lexically, and
      # that distinction has to survive the wider search.
      module Outer
        SECRET = :outer
        module Mid; end
      end
      class Outer::Mid::Leaf
        def peek
          defined?(SECRET) ? SECRET : :not_visible
        end
      end
      p Outer::Mid::Leaf.new.peek
    RUBY

    _(result).must_answer <<~'OUT'
      42
      43
      43
      :not_visible
    OUT
  end

  it "bare module constants lists the lexical scopes" do
    result = ze0(<<~'RUBY')
      # Module.constants with no argument lists the constants of each lexical
      # scope and of Object, as rb_mod_s_constants does. With an argument it
      # is Module#constants on Module.

      module Outer
        X = 1
        class Inner
          Y = 2
          names = Module.constants
          p names.include?(:X), names.include?(:Y), names.include?(:String)
        end
      end
      p Module.constants(false), Module.singleton_methods(false).include?(:constants)
      p Module.constants.include?(:Outer), Module.constants.include?(:Inner)

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      []
      true
      true
      false
    OUT
  end

  it "bare public at top level marks the following defs" do
    result = ze0(<<~'RUBY')
      def show(label)
        puts format("%-30s %s", label, (yield).inspect)
      rescue => e
        puts format("%-30s %s", label, e.class)
      end

      def plain = "plain"
      show("plain def is private")   { Object.private_method_defined?(:plain) }

      public
      def after_public = "after_public"
      show("after public is public") { Object.public_method_defined?(:after_public) }
      show("after public not private") { Object.private_method_defined?(:after_public) }
      show("callable through self")  { self.after_public }

      private
      def after_private = "after_private"
      show("after private")          { Object.private_method_defined?(:after_private) }

      public
      def second_public = "second"
      show("second public run")      { Object.public_method_defined?(:second_public) }

      show("method owner")           { method(:private).owner.to_s.start_with?("#<Class:") }
    RUBY

    _(result).must_answer <<~'OUT'
      plain def is private           true
      after public is public         true
      after public not private       false
      callable through self          "after_public"
      after private                  true
      second public run              true
      method owner                   true
    OUT
  end

  it "begin unknown const tail" do
    result = ze0(<<~'RUBY')
      # A begin whose body is an unknown constant: the read emits a raise, whose C
      # type is the class struct, and assigning that to the slot the handler's value
      # settled on did not compile. Control never reaches the assignment.
      p(begin; NoSuchConst1; rescue NameError => e; "x"; end)
      p(begin; NoSuchConst2; rescue NameError; 5; end)
      p(begin; 7; rescue; 0; end)
      p(begin; NoSuchConst3; rescue NameError => e3; e3.class.to_s; end)
      def f; NoSuchConst4; rescue NameError; -1; end
      p f
      p(begin; [1,2]; rescue; 0; end)
    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      5
      7
      "NameError"
      -1
      [1, 2]
    OUT
  end

  it "big constant table" do
    result = ze0(<<~'RUBY')
      # A large constant table lands in the binary's data section whole.
      SQUARES = (1..64).map { |n| n * n }.freeze
      NAMES = %w[
        ada alan alonzo barbara claude dennis donald edsger grace guido james
        john ken linus margaret niklaus ole rich robin tony yukihiro
      ].freeze
      CODES = { ok: 0, warn: 1, err: 2, fatal: 3 }.freeze
      puts SQUARES.sum
      puts NAMES.length, NAMES.max_by(&:length)
      p CODES.sort_by { |_, v| -v }.first
    RUBY

    _(result).must_answer <<~'OUT'
      89440
      21
      margaret
      [:fatal, 3]
    OUT
  end

  it "boxs constant is its own" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # The CONSTANT channel, both halves. A box's `Object.const_set` is
      # unreachable from main, and reachable from the box -- which needs its own
      # record for `Object`, since a box's cref chain ends at its surrogate and
      # otherwise never consults `Object` at all.



      b = Ruby::Box.new
      b.eval("Object.const_set(:BOXCONST, 5)")
      p(begin; Object.const_get(:BOXCONST); rescue NameError; :namee; end)
      p b.eval("BOXCONST")
    RUBY

    _(result).must_answer <<~'OUT'
      :namee
      5
    OUT
  end

  it "case when value constant" do
    result = ze0(<<~'RUBY')
      # A constant holding a VALUE (symbol/int/string) used in `when` is an
      # equality test, not a Module#=== class test. Treating it as a class name
      # made every arm compile to `if (0)`, so the whole case fell through.

      class Menu
        STATE_TITLE = :title
        STATE_OPTIONS = :options
        STATE_SKILL = 2
        LABEL = "quit"

        def initialize
          @state = STATE_TITLE
        end

        def advance(s)
          @state = s
        end

        def render
          case @state
          when STATE_TITLE then "title screen"
          when STATE_OPTIONS then "options screen"
          when STATE_SKILL then "skill select"
          when LABEL then "quitting"
          else "unknown"
          end
        end
      end

      m = Menu.new
      puts m.render
      m.advance(Menu::STATE_OPTIONS)
      puts m.render
      m.advance(Menu::STATE_SKILL)
      puts m.render
      m.advance(Menu::LABEL)
      puts m.render
      m.advance(:bogus)
      puts m.render

      # classes in `when` still work as class tests alongside value constants
      def kind(x)
        case x
        when Integer then "int"
        when String then "str"
        when Menu::STATE_TITLE then "title-sym"
        else "other"
        end
      end
      puts kind(5)
      puts kind("s")
      puts kind(:title)
      puts kind(3.5)

      # a constant ALIASING a class must stay a Module#=== class test
      class Widget; end
      WidgetAlias = Widget
      def alias_kind(x)
        case x
        when WidgetAlias then "widget"
        else "other"
        end
      end
      puts alias_kind(Widget.new)
      puts alias_kind(7)
    RUBY

    _(result).must_answer <<~'OUT'
      title screen
      options screen
      skill select
      quitting
      unknown
      int
      str
      title-sym
      other
      widget
      other
    OUT
  end

  it "class is not there before its statement runs" do
    result = ze0(<<~'RUBY')
      # A `class` statement CREATES its constant where it stands, so a read above
      # it is a NameError -- the same answer `defined?` gives there.
      begin
        Missing.new
      rescue NameError => e
        puts "read: #{e.message}"
      end
      p defined?(Missing)

      class Missing
        def initialize = @made = true
      end

      p Missing.new.class
      p defined?(Missing)

      # A class body runs at its statement's position, so a read inside one is
      # placed the same way.
      begin
        module Holder
          Later.name
        end
      rescue NameError => e
        puts "in a body: #{e.message}"
      end

      class Later; end
      p Later.name

      # A method body runs when it is CALLED, so a read inside one written above
      # the class is fine.
      def name_of_soon = Soon.name
      class Soon; end
      p name_of_soon

      # The class is still there for everything below it, however deep.
      p [Missing, Later, Soon].map(&:name)
    RUBY

    _(result).must_answer <<~'OUT'
      read: uninitialized constant Missing
      nil
      Missing
      "constant"
      in a body: uninitialized constant Holder::Later
      "Later"
      "Soon"
      ["Missing", "Later", "Soon"]
    OUT
  end

  it "const added hook" do
    result = ze0(<<~'RUBY')
      # `Module#const_added` -- ruby announces a constant the moment it becomes
      # readable, on the module it was set on, with the constant's own leaf name.
      #
      # Unlike the `method_*` family this one has no singleton rerouting, and its
      # order against the other two class hooks is fixed: `const_added` for the name,
      # THEN `inherited`, THEN the class body.

      puts "== a plain write, a class, a module"
      module Outer
        def self.const_added(n) = puts("Outer const_added #{n}")
        def self.inherited(s) = puts("Outer inherited #{s}")

        X = 1
        class Inner
          puts "  (inner body runs after its name is announced)"
        end
        module M; end

        # A class minted by an expression is announced by the write that names it.
        S = Struct.new(:a)
        D = Data.define(:b)
        K = Class.new
      end

      puts "== a reopen declares nothing"
      module Outer
        class Inner
          puts "  (inner reopened -- no announcement)"
        end
        Z = 9
      end

      puts "== every assignment announces, re-assignment included"
      Outer.send(:remove_const, :Z)
      Outer::Z = 10

      puts "== const_added, then inherited, then the body"
      class Base
        def self.const_added(n) = puts("Base const_added #{n}")
        def self.inherited(s) = puts("Base inherited #{s}")
      end
      class Base
        class Child < Base
          puts "  (child body)"
        end
      end

      puts "== the runtime shapes"
      module Runtime
        def self.const_added(n) = puts("Runtime const_added #{n}")
      end
      Runtime.const_set(:VIA_SET, 1)
      # An autoload announces at DECLARATION, not when the file loads -- and on every
      # declaration, re-declaring the same name included.
      Runtime.autoload(:LAZY, "some/file")
      Runtime.autoload(:LAZY, "some/file")

      puts "== an explicit scope announces on that scope"
      Outer::FROM_OUTSIDE = 5

      puts "== a module with no hook stays silent"
      module Quiet
        QUIET_CONST = 1
        class QuietInner; end
      end
      p Quiet.constants.sort
    RUBY

    _(result).must_answer "== a plain write, a class, a module\nOuter const_added X\nOuter const_added Inner\n  (inner body runs after its name is announced)\nOuter const_added M\nOuter const_added S\nOuter const_added D\nOuter const_added K\n== a reopen declares nothing\n  (inner reopened -- no announcement)\nOuter const_added Z\n== every assignment announces, re-assignment included\nOuter const_added Z\n== const_added, then inherited, then the body\nBase const_added Child\nBase inherited Base::Child\n  (child body)\n== the runtime shapes\nRuntime const_added VIA_SET\nRuntime const_added LAZY\nRuntime const_added LAZY\n== an explicit scope announces on that scope\nOuter const_added FROM_OUTSIDE\n== a module with no hook stays silent\n[:QUIET_CONST, :QuietInner]\n"
  end

  it "const compound assign" do
    result = ze0(<<~'RUBY', path: "lang/constants/const_compound_assign.rb")
      # Compound assignment to a constant (`A += 2`, `A ||= 2`, `A &&= 2`).
      # The constant slot is mutated at runtime, so its reads must load the
      # live value rather than fold the declaration literal. ||=/&&= follow
      # Ruby truthiness: 0 is truthy, so `A ||= x` keeps a zero constant.
      A = 0
      A += 2
      p A          # 2
      B = 10
      B -= 3
      p B          # 7
      C = 4
      C *= 5
      p C          # 20
      D = 17
      D /= 5
      p D          # 3
      E = 17
      E %= 5
      p E          # 2
      F = 1
      F <<= 4
      p F          # 16
      ZERO = 0
      ZERO ||= 99
      p ZERO       # 0 (0 is truthy in Ruby)
      FIVE = 5
      FIVE ||= 99
      p FIVE       # 5
      G = 0
      G &&= 99
      p G          # 99 (0 is truthy, so &&= reassigns)
      H = 7
      H &&= 99
      p H          # 99
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/constants/const_compound_assign.rb:6: warning: already initialized constant A\nlang/constants/const_compound_assign.rb:5: warning: previous definition of A was here\nlang/constants/const_compound_assign.rb:9: warning: already initialized constant B\nlang/constants/const_compound_assign.rb:8: warning: previous definition of B was here\nlang/constants/const_compound_assign.rb:12: warning: already initialized constant C\nlang/constants/const_compound_assign.rb:11: warning: previous definition of C was here\nlang/constants/const_compound_assign.rb:15: warning: already initialized constant D\nlang/constants/const_compound_assign.rb:14: warning: previous definition of D was here\nlang/constants/const_compound_assign.rb:18: warning: already initialized constant E\nlang/constants/const_compound_assign.rb:17: warning: previous definition of E was here\nlang/constants/const_compound_assign.rb:21: warning: already initialized constant F\nlang/constants/const_compound_assign.rb:20: warning: previous definition of F was here\nlang/constants/const_compound_assign.rb:30: warning: already initialized constant G\nlang/constants/const_compound_assign.rb:29: warning: previous definition of G was here\nlang/constants/const_compound_assign.rb:33: warning: already initialized constant H\nlang/constants/const_compound_assign.rb:32: warning: previous definition of H was here\n"
      2
      7
      20
      3
      2
      16
      0
      5
      99
      99
    OUT
  end

  it "const defined invalid name" do
    result = ze0(<<~'RUBY')
      # Module#const_defined? validates the constant name. A defined name answers
      # true, an undefined-but-well-formed name answers false, and a malformed name
      # (lowercase / leading underscore / a non-identifier byte) raises NameError
      # "wrong constant name <name>" -- Spinel previously answered false silently.
      # (Only a literal name argument is folded; a runtime name rejects separately.)
      module M
        X = 1
      end

      p M.const_defined?("X")   # true
      p M.const_defined?(:X)    # true
      p M.const_defined?("Y")   # false (well-formed, undefined)
      p M.const_defined?(:Zz)   # false
      p M.const_defined?("X1")  # false

      def check(&blk)
        blk.call
        puts "no raise"
      rescue NameError => e
        puts e.message
      end

      check { M.const_defined?("name") }
      check { M.const_defined?("_Foo") }
      check { M.const_defined?("@x") }
      check { M.const_defined?("1A") }
      check { M.const_defined?("A B") }
      check { M.const_defined?("") }
      check { M.const_defined?(:lower) }
    RUBY

    _(result).must_answer "true\ntrue\nfalse\nfalse\nfalse\nwrong constant name name\nwrong constant name _Foo\nwrong constant name @x\nwrong constant name 1A\nwrong constant name A B\nwrong constant name \nwrong constant name lower\n"
  end

  it "const get builtin" do
    result = ze0(<<~'RUBY')
      p Float::INFINITY
      r = (Float.const_get(:INFINITY) rescue $!.class); p r
      p Math::PI
      r2 = (Math.const_get(:PI) rescue $!.class); p r2
    RUBY

    _(result).must_answer <<~'OUT'
      Infinity
      Infinity
      3.141592653589793
      3.141592653589793
    OUT
  end

  it "const get literal" do
    result = ze0(<<~'RUBY')
      module M
        X = 7
        NAME = "spinel"
        module N
          Z = 1
        end
      end

      # literal symbol and string names resolve to the constant value
      puts M.const_get(:X)
      puts M.const_get(:NAME)
      puts M.const_get("X")

      # a literal but unresolved name raises NameError at runtime, matching CRuby:
      # a valid constant name reports "uninitialized constant", qualified by a named
      # module receiver; a name without a leading uppercase reports "wrong constant name".
      begin; M.const_get(:Missing); rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; M.const_get(:lower); rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; Object.const_get(:Nope); rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; M::N.const_get(:Missing); rescue => e; puts "#{e.class}: #{e.message}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      7
      spinel
      7
      NameError: uninitialized constant M::Missing
      NameError: wrong constant name lower
      NameError: uninitialized constant Nope
      NameError: uninitialized constant M::N::Missing
    OUT
  end

  it "const get on a shadowed namespace head" do
    result = ze0(<<~'RUBY')
      # `Klass.const_get(:NAME)` on a statically-known class folds at compile time.
      # The fold took an already-resolved class and round-tripped it through
      # `fq_name` -- an UNANCHORED string -- then re-resolved that string against the
      # emit site's own cref chain. Any name shadowing along that chain makes the
      # round trip lossy.
      #
      # appraisal2 3.2.2 is the shape: a module with a same-named class nested inside
      # it. Resolving the head segment `Appraisal` from inside `module Appraisal`
      # finds the nested CLASS, which has no `Hooks`, so the fold panicked with
      # `internal error: unknown class/module 'Appraisal::Hooks' in const_owner_id`.
      # The gem's own source is correctly anchored (`::Appraisal::Hooks`); it was
      # `fq_name` that dropped the anchor.
      module Sample
        # The shadow: `Sample::Sample`, so the head segment resolves to a class that
        # knows nothing about the modules beside it.
        class Sample
        end

        module Hooks
          GEMFILE = "Gemfile"
        end

        class << self
          def gemfile = ::Sample::Hooks.const_get(:GEMFILE)
        end
      end

      p Sample.gemfile

      # The panic was the LUCKY case. When the shadowing class also answers the name,
      # nothing raises -- the fold silently resolves against the WRONG owner and
      # reads the wrong constant. Same lookup, a miscompile instead of a crash.
      module Twin
        class Twin
          module Inner
            VALUE = :from_the_nested_class
          end
        end

        module Inner
          VALUE = :from_the_module
        end

        class << self
          def value = ::Twin::Inner.const_get(:VALUE)
          def nested = ::Twin::Twin::Inner.const_get(:VALUE)
        end
      end

      p Twin.value
      p Twin.nested

      # The same read spelled every other way must agree.
      p Twin::Inner.const_get(:VALUE)
      p Twin::Inner::VALUE
      p Twin::Inner.const_defined?(:VALUE)
      p Sample::Hooks.const_get(:GEMFILE)

      # And an unqualified reference from inside the shadowed namespace still means
      # what Ruby says it means.
      module Twin
        def self.from_inside = Inner.const_get(:VALUE)
      end
      p Twin.from_inside
    RUBY

    _(result).must_answer <<~'OUT'
      "Gemfile"
      :from_the_module
      :from_the_nested_class
      :from_the_module
      :from_the_module
      true
      "Gemfile"
      :from_the_module
    OUT
  end

  it "const path compound assign" do
    result = ze0(<<~'RUBY', path: "lang/constants/const_path_compound_assign.rb")
      # Compound assignment to a constant-path target (`M::X += 2`). Resolves
      # to the qualified constant slot and mutates it at runtime.
      module M
        X = 0
        Y = 10
        Z = 0
      end
      M::X += 2
      p M::X       # 2
      M::Y -= 3
      p M::Y       # 7
      M::Z ||= 5
      p M::Z       # 0 (truthy)
      M::Z &&= 8
      p M::Z       # 8
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/constants/const_path_compound_assign.rb:8: warning: already initialized constant M::X\nlang/constants/const_path_compound_assign.rb:4: warning: previous definition of X was here\nlang/constants/const_path_compound_assign.rb:10: warning: already initialized constant M::Y\nlang/constants/const_path_compound_assign.rb:5: warning: previous definition of Y was here\nlang/constants/const_path_compound_assign.rb:14: warning: already initialized constant M::Z\nlang/constants/const_path_compound_assign.rb:6: warning: previous definition of Z was here\n"
      2
      7
      0
      8
    OUT
  end

  it "const probe and anchored shell" do
    result = ze0(<<~'RUBY')
      # Two constant-resolution rules rubygems and bundler lean on all through their
      # compatibility shims.
      #
      # 1. `if defined?(Const)` gates a whole definition. Whether the constant exists
      #    is fixed for a whole-program target, so the branch is decided at compile
      #    time -- and registration and emission have to decide it the SAME way, or a
      #    class reaches codegen with nothing registered behind it.
      # 2. A `::`-anchored path names the top level and nothing else, including when
      #    the definition it names comes LATER in the flattened program.

      # A gate on something the program never defines: the body is unreachable, and
      # may name things that don't exist at all.
      if defined?(NoSuchThingAnywhere)
        class OnlyUnderTheGate
          def call = NoSuchThingAnywhere::Also::Missing.new
        end
      end
      p defined?(OnlyUnderTheGate)

      # A gate on something the program DOES define: the branch compiles and runs.
      # (Asked BEFORE the definition, zeo answers "constant" where ruby answers nil --
      # a constant's document-order visibility is a separate, pre-existing
      # over-approximation, filed as `tests/gaps/issue_defined_before_the_definition.rb`.)
      class DefinedBelow; end
      if defined?(DefinedBelow)
        class GatedOnReal
          VALUE = 41
          def call = VALUE + 1
        end
      end
      p GatedOnReal.new.call

      # The same gate written against a nested path, and against a plain constant
      # assignment rather than a class.
      module Outer
        module Inner; end
      end
      p defined?(Outer::Inner)
      p defined?(Outer::Nope)
      p defined?(NEVER_ASSIGNED)

      # A VALUE constant, not a class: `resolve_class` has nothing to say about it,
      # so the const registry has to be consulted too.
      class Holder
        LIMIT = 7
        def known = defined?(LIMIT)
        def unknown = defined?(NO_SUCH_LIMIT)
      end
      p Holder.new.known, Holder.new.unknown
      module Namespaced
        SIZE = 2
        def self.known = defined?(SIZE)
      end
      p Namespaced.known
      p defined?(Holder::LIMIT)
      p defined?(Holder::MISSING)

      # ...and `unless defined?` -- the vendored-shim spelling.
      unless defined?(Vendored)
        module Vendored
          VERSION = "0.1"
        end
      end
      p Vendored::VERSION

      # A top-anchored superclass whose target is defined later in the program.
      module Pkg
        module Timeout
          class Error < RuntimeError; end
        end
      end

      module Pkg
        module Net
          # Resolved against the top level, skipping the `Pkg::Net` cref -- a bare
          # `Timeout::Error` here would find `Pkg::Timeout::Error` too, but the
          # anchored spelling must not depend on that coincidence.
          class OpenTimeout < ::Pkg::Timeout::Error; end
        end
      end

      class Elsewhere
        class TimeoutError < ::Pkg::Timeout::Error; end
      end

      p Pkg::Net::OpenTimeout.ancestors[0, 3]
      p Elsewhere::TimeoutError.ancestors[0, 3]
      begin
        raise Elsewhere::TimeoutError, "timed out"
      rescue Pkg::Timeout::Error => e
        p [e.class, e.message]
      end

      # A `::`-anchored name that shadows a same-named constant in scope.
      COLOUR = :top_level
      module Shadow
        COLOUR = :nested
        def self.here = COLOUR
        def self.rooted = ::COLOUR
      end
      p Shadow.here, Shadow.rooted
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      42
      "constant"
      nil
      nil
      "constant"
      nil
      "constant"
      "constant"
      nil
      "0.1"
      [Pkg::Net::OpenTimeout, Pkg::Timeout::Error, RuntimeError]
      [Elsewhere::TimeoutError, Pkg::Timeout::Error, RuntimeError]
      [Elsewhere::TimeoutError, "timed out"]
      :nested
      :top_level
    OUT
  end

  it "const scope operator" do
    result = ze0(<<~'RUBY')
      # `Object` is an ancestor of every class, so an ancestry walk that reads its
      # constant table makes every top-level constant answer as every class's own:
      # `SystemCallError::Errno` found the top-level `Errno` module, and a `FLAGS` a
      # `Struct.new` block left at top level would answer for `Line::FLAGS`.
      #
      # Ruby draws the line with one flag (`variable.c`'s `exclude`). The scope
      # OPERATOR rejects a hit `Object` owns; `const_get`/`const_defined?` accept it.
      # Everything below is that one difference, seen from both sides.

      module M; end
      class K; end

      def try(label)
        v = yield
        puts "#{label} => #{v.inspect}"
      rescue => e
        puts "#{label} !! #{e.class}: #{e.message}"
      end

      TOP = 4

      # `::` cannot see a constant `Object` owns -- neither a top-level class nor a
      # top-level value.
      try("K::Errno") { K::Errno }
      try("SystemCallError::Errno") { SystemCallError::Errno }
      try("BasicObject::Errno") { BasicObject::Errno }
      try("M::Errno") { M::Errno }
      try("K::TOP") { K::TOP }
      try("K::String") { K::String }

      # ...but a receiver that IS `Object` reads them, since the rule excludes the
      # ancestor rather than the receiver.
      try("Object::Errno") { Object::Errno }
      try("Object::TOP") { Object::TOP }
      try("::TOP") { ::TOP }

      # `const_get`/`const_defined?` ask the other question, and get the other answer.
      try("K.const_get(:Errno)") { K.const_get(:Errno) }
      try("K.const_get(:TOP)") { K.const_get(:TOP) }
      try("M.const_get(:Errno)") { M.const_get(:Errno) }
      try("K.const_defined?(:TOP)") { K.const_defined?(:TOP) }
      try("K.const_defined?(:TOP, false)") { K.const_defined?(:TOP, false) }
      try("M.const_defined?(:TOP)") { M.const_defined?(:TOP) }

      # `defined?` gates the scope operator, so it answers the operator's way.
      try("defined? K::TOP") { defined?(K::TOP) }
      try("defined? K::Errno") { defined?(K::Errno) }
      try("defined? Object::TOP") { defined?(Object::TOP) }

      # Only the HEAD of a `const_get` path gets `const_get`'s reach. Every segment
      # past it is a scope operator.
      try("Object.const_get('K::TOP')") { Object.const_get("K::TOP") }
      try("Object.const_get('K')") { Object.const_get("K") }

      # A REAL ancestor still answers through `::` -- it is `Object` that is out of
      # reach, not inheritance.
      class Base
        INSIDE = 1
      end
      class Deriv < Base; end
      module Mixin
        VIA = 2
      end
      class WithMix
        include Mixin
      end
      try("Deriv::INSIDE") { Deriv::INSIDE }
      try("WithMix::VIA") { WithMix::VIA }
      try("File::SEEK_SET") { File::SEEK_SET }
      try("Deriv.const_get(:INSIDE, false)") { Deriv.const_get(:INSIDE, false) }

      # The NameError names the missing leaf and the SCOPE it was asked of, not
      # whatever ancestor the lookup ended on.
      begin
        K::TOP
      rescue NameError => e
        p [e.name, e.receiver, e.message]
      end
      begin
        K::Nope
      rescue NameError => e
        p [e.name, e.receiver, e.message]
      end

      # A scoped WRITE targets the scope, and does not disturb the top-level name it
      # cannot read.
      K::TOP = 5
      p [TOP, K::TOP, K.const_get(:TOP), K.constants]
    RUBY

    _(result).must_answer <<~'OUT'
      K::Errno !! NameError: uninitialized constant K::Errno
      SystemCallError::Errno !! NameError: uninitialized constant SystemCallError::Errno
      BasicObject::Errno !! NameError: uninitialized constant BasicObject::Errno
      M::Errno !! NameError: uninitialized constant M::Errno
      K::TOP !! NameError: uninitialized constant K::TOP
      K::String !! NameError: uninitialized constant K::String
      Object::Errno => Errno
      Object::TOP => 4
      ::TOP => 4
      K.const_get(:Errno) => Errno
      K.const_get(:TOP) => 4
      M.const_get(:Errno) => Errno
      K.const_defined?(:TOP) => true
      K.const_defined?(:TOP, false) => false
      M.const_defined?(:TOP) => true
      defined? K::TOP => nil
      defined? K::Errno => nil
      defined? Object::TOP => "constant"
      Object.const_get('K::TOP') !! NameError: uninitialized constant K::TOP
      Object.const_get('K') => K
      Deriv::INSIDE => 1
      WithMix::VIA => 2
      File::SEEK_SET => 0
      Deriv.const_get(:INSIDE, false) !! NameError: uninitialized constant Deriv::INSIDE
      [:TOP, K, "uninitialized constant K::TOP"]
      [:Nope, K, "uninitialized constant K::Nope"]
      [4, 5, 5, [:TOP]]
    OUT
  end

  it "constant name is validated before the lookup" do
    result = ze0(<<~'RUBY')
      # `rb_is_const_id` runs BEFORE the lookup: a string that is not a constant
      # name raises `wrong constant name`, carrying the name, rather than reporting
      # an `uninitialized constant` miss. zeo checked only the FIRST character, so
      # `Bad.Name` and `Bad Name` passed the gate and came back as misses -- and
      # `const_defined?` ran no check at all.
      #
      # A `::`-separated PATH is still a legal argument, each segment checked on its
      # own, and `**nil` below is the other "no-op spelled as a value" this pass
      # fixed: it means "pass no keywords", never a conversion.

      module Holder
        Inner = Module.new
        Deep = 1
      end

      [
        "Bad.Name", "Bad Name", "lower", "_Under", "9Nine", "", "Holder::lower",
        "Holder::Nope", "Holder::Deep", "Holder", "Holder::Inner",
      ].each do |name|
        begin
          p [name, Object.const_get(name)]
        rescue NameError => e
          p [name, e.class, e.message]
        end
      end

      # `const_defined?` and `const_source_location` run the same gate.
      ["Bad.Name", "lower", "Holder"].each do |name|
        begin
          p Object.const_defined?(name)
        rescue NameError => e
          p [:defined, e.message]
        end
        begin
          p Object.const_source_location(name).nil?
        rescue NameError => e
          p [:location, e.message]
        end
      end

      # A Symbol argument goes through the same check, and its `#name` is the
      # symbol it was given.
      begin
        Object.const_get(:"Bad Name")
      rescue NameError => e
        p [e.message, e.name]
      end

      # --- `**nil` -----------------------------------------------------------------
      def kw(a, b: 2, **rest) = [a, b, rest]
      p kw(1, **nil)
      p kw(2, **nil, b: 3)
      h = nil
      p kw(4, **h)
      def anykw(**k) = k
      p anykw(**nil)
    RUBY

    _(result).must_answer <<~'OUT'
      ["Bad.Name", NameError, "wrong constant name Bad.Name"]
      ["Bad Name", NameError, "wrong constant name Bad Name"]
      ["lower", NameError, "wrong constant name lower"]
      ["_Under", NameError, "wrong constant name _Under"]
      ["9Nine", NameError, "wrong constant name 9Nine"]
      ["", NameError, "wrong constant name "]
      ["Holder::lower", NameError, "wrong constant name lower"]
      ["Holder::Nope", NameError, "uninitialized constant Holder::Nope"]
      ["Holder::Deep", 1]
      ["Holder", Holder]
      ["Holder::Inner", Holder::Inner]
      [:defined, "wrong constant name Bad.Name"]
      [:location, "wrong constant name Bad.Name"]
      [:defined, "wrong constant name lower"]
      [:location, "wrong constant name lower"]
      true
      false
      ["wrong constant name Bad Name", :"Bad Name"]
      [1, 2, {}]
      [2, 3, {}]
      [4, 2, {}]
      {}
    OUT
  end

  it "constant path" do
    result = ze0(<<~'RUBY')
      # ConstantPath access — covers ARGV (top-level builtin), built-in
      # constructors (::Array.new etc.), nested const reads (A::B::C),
      # class-method dispatch (A::B.create), and the relative-vs-root
      # scope distinction (RootNS::Mid::LEAF vs ::RootNS::Mid::LEAF).
      # Merged from constant_path_{argv,builtin_new,class_method,
      # nested_read,new}.rb. The class-method section's `A::B` (a class)
      # would collide with the nested-read section's `A::B::C` (where
      # A::B is a module), so the class-method section is namespaced as
      # CmA::CmB to keep both shapes co-resident.

      # ---- ARGV access via ConstantPath ----
      # Runs at top-level scope so sp_argv is in scope (sp_argv is only
      # declared in main()).
      puts ARGV.length
      puts ::ARGV.length
      puts(ARGV[0] == nil)
      puts(::ARGV[0] == nil)

      # ---- Built-in constructors via absolute ConstantPath ----
      require "stringio"

      bia = ::Array.new(3, 2)
      puts bia[0] + bia[2]

      bih = ::Hash.new
      bih["k"] = bia[1]
      puts bih["k"]

      bip = ::Proc.new { |x| x + 1 }
      puts bip.call(5)

      bis = ::StringIO.new("ab")
      puts bis.getc

      bif = ::Fiber.new { |x|
        ::Fiber.yield(x + 1)
        x + 2
      }
      puts bif.resume(4)
      puts bif.resume(4)

      bicur = ::Fiber.current
      puts bicur.alive?

      # ---- ConstantPath class-method dispatch (A::B.create) ----
      module CmA
        class CmB
          def self.create(x)
            x + 1
          end
        end
      end
      puts CmA::CmB.create(41)
      puts ::CmA::CmB.create(99)

      # ---- Nested ConstantPath reads (A::B::C, M::C::X) ----
      module A
        module B
          C = 7
        end
      end
      module M
        class C
          X = 11
        end
      end
      puts A::B::C
      puts ::A::B::C
      puts M::C::X
      puts ::M::C::X

      # Relative path prefers lexical scope; `::` forces root scope.
      module RootNS
        module Mid
          LEAF = 31
        end
      end
      module Lex
        module RootNS
          module Mid
            LEAF = 47
          end
        end
        def self.pick_relative
          RootNS::Mid::LEAF
        end
        def self.pick_root
          ::RootNS::Mid::LEAF
        end
      end
      puts Lex.pick_relative
      puts Lex.pick_root

      # ---- Top-level constructor via absolute ConstantPath (::TopC.new) ----
      # Renamed from `class C` to TopC to keep it distinct from M::C above.
      class TopC
        def initialize
          puts "init"
        end
      end
      puts "start"
      ::TopC.new
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      true
      true
      4
      2
      6
      a
      5
      6
      true
      42
      100
      7
      7
      11
      11
      47
      31
      start
      init
    OUT
  end

  it "constant path may be rooted at a value" do
    result = ze0(<<~'RUBY', path: "lang/constants/a_constant_path_may_be_rooted_at_a_value.rb")
      # `::` takes a class or module on its left, and that left side is an ordinary
      # EXPRESSION -- `self`, a parameter, a method call. Only the name after `::` has
      # to be spelled at compile time. So the whole search happens at run time: the
      # scope operator's own search (a constant `Object` owns stays out of reach, and
      # a `private_constant` is hidden), never `const_get`'s, which reaches through
      # both and which a class may override.
      #
      # activerecord's `ColumnDefinition = Struct.new(...) do self::OPTION_NAMES =
      # [...] end` is the shape, and orm_adapter writes the same thing inside an
      # `ActiveSupport.on_load` block, where nothing NAMES the class at all.

      class Named
        self::FOO = 1
      end
      p Named::FOO

      # An anonymous class has no name to write, which is the point of the form.
      anon = Class.new
      anon::NAME = :set
      p anon.const_get(:NAME)
      p anon::NAME

      # The scope is evaluated FIRST, then the value, and the "not a module" check
      # comes after BOTH -- `1::X = (puts ...; 3)` prints before it raises.
      def scope_of(m)
        puts "scope"
        m
      end

      holder = Module.new
      scope_of(holder)::VALUE = (puts "value"; 42)
      p holder::VALUE

      begin
        1::WHAT = (puts "rhs still ran"; 2)
      rescue TypeError => e
        p e.message
      end

      begin
        Object.new::ANY
      rescue TypeError => e
        p e.message.sub(/0x\h+/, "0xXXXX")
      end

      # A plain `obj::NAME = v` inside a method is the `dynamic constant assignment`
      # SyntaxError -- but `||=` is not, which is the loophole act_as_attribute's
      # `self::AVAILABLE_ATTRIBUTES ||= []` is built on. Never assigned reads as nil
      # and the write defines it, exactly as a bare `CONST ||= v` does.
      module Registry; end

      def stock(m)
        m::LIST ||= []
        m::LIST << :entry
        m::COUNT ||= 0
      end

      stock(Registry)
      stock(Registry)
      p Registry::LIST
      p Registry::COUNT

      # `+=` and `&&=` keep the RAISING read, again matching the bare form.
      module Counter
        START = 10
      end

      def bump(m)
        m::START += 1
      end
      p bump(Counter)
      p Counter::START

      def guard(m)
        m::MISSING &&= :never
      rescue NameError => e
        e.message
      end
      p guard(Counter)

      # The scope expression is evaluated ONCE per assignment, not once per half.
      $calls = 0
      def counted(m)
        $calls += 1
        m
      end

      module Once; end
      counted(Once)::SEEN ||= :first
      counted(Once)::SEEN ||= :second
      p [$calls, Once::SEEN]

      # Reading through a value works wherever a constant does -- as a rescue class,
      # as a raise class, as a superclass check.
      Errors = Module.new
      Errors.const_set(:Denied, Class.new(StandardError))

      def attempt(mod)
        raise mod::Denied, "no"
      rescue mod::Denied => e
        e.message
      end
      p attempt(Errors)

      # `defined?` answers "constant" or nil, and swallows the TypeError a non-module
      # scope would otherwise raise.
      def defined_pair(x)
        [defined?(x::Denied), defined?(x::Absent)]
      end
      p defined_pair(Errors)
      p defined_pair(7)

      # The scope operator does NOT reach a top-level constant through the scope's
      # ancestry, even though `const_get` does.
      TOP_LEVEL = :visible

      def through(m)
        m::TOP_LEVEL
      rescue NameError => e
        e.message.sub(/0x\h+/, "0xXXXX")
      end

      plain = Module.new
      p through(plain)
      p plain.const_get(:TOP_LEVEL)

      # ... nor a `private_constant`.
      class Sealed
        HIDDEN = :secret
        private_constant :HIDDEN
      end

      def peek(k)
        k::HIDDEN
      rescue NameError => e
        e.message
      end
      p peek(Sealed)
      p defined?(Sealed::HIDDEN)

      # An ancestor's constant DOES answer, since the search walks the chain.
      module Base
        SHARED = :inherited
      end

      class Derived
        include Base
      end

      def shared(k)
        k::SHARED
      end
      p shared(Derived)

      # `self` in a class body is the class, so `self::NAME` and a bare `NAME` name
      # the same constant.
      class Both
        self::ONE = 1
        TWO = 2
        p [self::ONE, self::TWO, ONE, TWO]
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/constants/a_constant_path_may_be_rooted_at_a_value.rb:69: warning: already initialized constant Counter::START\nlang/constants/a_constant_path_may_be_rooted_at_a_value.rb:65: warning: previous definition of START was here\n"
      1
      :set
      :set
      scope
      value
      42
      rhs still ran
      "1 is not a class/module"
      "#<Object:0xXXXX> is not a class/module"
      [:entry, :entry]
      0
      11
      11
      "uninitialized constant Counter::MISSING"
      [2, :first]
      "no"
      ["constant", nil]
      [nil, nil]
      "uninitialized constant #<Module:0xXXXX>::TOP_LEVEL"
      :visible
      "private constant Sealed::HIDDEN referenced"
      nil
      :inherited
      [1, 2, 1, 2]
    OUT
  end

  it "constant path off a dynamic scope resolves at runtime" do
    result = ze0(<<~'RUBY')
      # `expr::NAME` where the scope is a runtime value (`self.class::Reason`,
      # optparse) resolves the constant off that value at runtime, walking its
      # ancestry -- so a subclass sees its own override.

      class Base
        Reason = "base"
        def reason; self.class::Reason; end
      end
      class Sub < Base
        Reason = "sub"
      end
      puts Base.new.reason
      puts Sub.new.reason
      holder = Base
      puts holder::Reason
    RUBY

    _(result).must_answer <<~'OUT'
      base
      sub
      base
    OUT
  end

  it "constant path write" do
    result = ze0(<<~'RUBY', path: "lang/constants/constant_path_write.rb")
      # `Mod::X = v` assigns through a constant path. Spinel requires the constant to
      # be declared first (registered by analysis); reassigning it then works, as the
      # `M::X ||= v` / `M::X += v` forms already did. (Output is compared on stdout;
      # Ruby's "already initialized constant" warning goes to stderr.)

      module M
        COUNT = 0
        NAME = ""
      end

      M::COUNT = 5
      p M::COUNT                  # 5

      M::NAME = "spinel"
      p M::NAME.upcase            # "SPINEL"

      # reassign using the constant's own value
      M::COUNT = M::COUNT + 10
      p M::COUNT                  # 15

      # nested constant path
      module A
        module B
          LEVEL = 1
        end
      end
      A::B::LEVEL = 42
      p A::B::LEVEL              # 42

      # the operator / or-write forms still work alongside plain write
      module N
        V = 1
      end
      N::V = 3
      N::V += 4
      p N::V                     # 7
      N::V ||= 99
      p N::V                     # 7 (already truthy)

      # an empty [] / {} reassignment keeps the constant's specialized array/hash type
      module E
        NUMS = [1, 2, 3]
        TBL = { "a" => 1 }
      end
      E::NUMS = []
      p E::NUMS                  # []
      E::TBL = {}
      p E::TBL                   # {}
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/constants/constant_path_write.rb:11: warning: already initialized constant M::COUNT\nlang/constants/constant_path_write.rb:7: warning: previous definition of COUNT was here\nlang/constants/constant_path_write.rb:14: warning: already initialized constant M::NAME\nlang/constants/constant_path_write.rb:8: warning: previous definition of NAME was here\nlang/constants/constant_path_write.rb:18: warning: already initialized constant M::COUNT\nlang/constants/constant_path_write.rb:11: warning: previous definition of COUNT was here\nlang/constants/constant_path_write.rb:27: warning: already initialized constant A::B::LEVEL\nlang/constants/constant_path_write.rb:24: warning: previous definition of LEVEL was here\nlang/constants/constant_path_write.rb:34: warning: already initialized constant N::V\nlang/constants/constant_path_write.rb:32: warning: previous definition of V was here\nlang/constants/constant_path_write.rb:35: warning: already initialized constant N::V\nlang/constants/constant_path_write.rb:34: warning: previous definition of V was here\nlang/constants/constant_path_write.rb:45: warning: already initialized constant E::NUMS\nlang/constants/constant_path_write.rb:42: warning: previous definition of NUMS was here\nlang/constants/constant_path_write.rb:47: warning: already initialized constant E::TBL\nlang/constants/constant_path_write.rb:43: warning: previous definition of TBL was here\n"
      5
      "SPINEL"
      15
      42
      7
      7
      []
      {}
    OUT
  end

  it "constant path write undeclared" do
    result = ze0(<<~'RUBY', path: "lang/constants/constant_path_write_undeclared.rb")
      # Nested constant assignment to a constant that was NOT pre-declared inside the
      # module body: `Mod::X = v` and the or/and-write forms. The leaf name is
      # registered flat; an or/and-write-only constant defaults to nil so its `||=`
      # assigns on first use. (Ruby's "already initialized constant" warnings go to
      # stderr; only stdout is compared.)
      module M; end

      M::X = 5
      p M::X                    # 5

      M::S = "hi"
      M::S = M::S + "!"         # reassignment reads the current value
      p M::S                    # "hi!"

      # ||= on a fresh constant assigns (undefined is nil/falsy); a second ||= no-ops.
      M::B ||= 5
      p M::B                    # 5
      M::B ||= 9
      p M::B                    # 5

      # fresh ||= with a string value.
      M::T ||= "x"
      p M::T                    # "x"

      # ||= on a constant given a definite value first keeps that value.
      M::A = 3
      M::A ||= 99
      p M::A                    # 3

      # &&= on a predefined constant reassigns.
      M::C = 1
      M::C &&= 2
      p M::C                    # 2
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/constants/constant_path_write_undeclared.rb:12: warning: already initialized constant M::S\nlang/constants/constant_path_write_undeclared.rb:11: warning: previous definition of S was here\nlang/constants/constant_path_write_undeclared.rb:32: warning: already initialized constant M::C\nlang/constants/constant_path_write_undeclared.rb:31: warning: previous definition of C was here\n"
      5
      "hi!"
      5
      5
      "x"
      3
      2
    OUT
  end

  it "constant visibility is positional" do
    result = ze0(<<~'RUBY')
      # `private_constant` and `public_constant` are RUN-TIME flags, and each runs
      # where it is written -- a read between two directives sees whichever had
      # run by then. zeo applied the whole program's directives at STARTUP, so a
      # read before a `private_constant` raised and a read before a later
      # `public_constant` did not.

      module Z
        D = 1
        private_constant :D
      end
      begin
        p Z::D
      rescue NameError => e
        puts "1: #{e.message}"
      end
      p defined?(Z::D)

      module Z
        public_constant :D
      end
      p Z::D
      p defined?(Z::D)

      module Y
        E = 2
      end
      p Y::E
      p defined?(Y::E)

      module Y
        private_constant :E
      end
      begin
        p Y::E
      rescue NameError => e
        puts "2: #{e.message}"
      end
      p Y.constants

      # The directive is still an expression, and its value is the module it
      # applied to.
      v = module N
        Inner = 3
        private_constant :Inner
      end
      p v
    RUBY

    _(result).must_answer <<~'OUT'
      1: private constant Z::D referenced
      nil
      1
      "constant"
      2
      "constant"
      2: private constant Y::E referenced
      []
      N
    OUT
  end

  it "constants" do
    result = ze0(<<~'RUBY')
      # Test module constants and top-level constants

      MAX_SIZE = 100
      PI_APPROX = 3
      NAME = "spinel"

      module Config
        VERSION = 42
        GREETING = "hello"
        ENABLED = true
      end

      puts MAX_SIZE         # 100
      puts PI_APPROX        # 3
      puts NAME             # spinel
      puts Config::VERSION  # 42
      puts Config::GREETING # hello
      puts Config::ENABLED  # true

      # Constants in expressions
      puts MAX_SIZE + 1     # 101
      puts NAME.length      # 6
      puts Config::GREETING.upcase  # HELLO

      # Lexical constant reads inside module/class initializers
      module LexicalConst
        A = 10
        B = A + 1

        class C
          X = 7
          Y = X + 2
        end

        module N
          P = A + 3
        end
      end

      puts LexicalConst::B     # 11
      puts LexicalConst::C::Y  # 9
      puts LexicalConst::N::P  # 13

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      100
      3
      spinel
      42
      hello
      true
      101
      6
      HELLO
      11
      9
      13
      done
    OUT
  end

  it "def takes the definee of its cref not its self" do
    result = ze0(<<~'RUBY')
      # Ruby's default definee is a property of the FRAME, inherited by every block
      # the frame opens -- it is not `self`. `module_eval`/`class_eval` replace it
      # with the module, `instance_eval`/`instance_exec` with the receiver's
      # singleton, and an ordinary block changes it not at all.
      #
      # zeo derived it from `self` instead, which is right for those three and wrong
      # for every other block: a `def` there came out as a singleton method of
      # whatever object happened to be self, so the CREF's class never gained it.
      [1].each { def in_block = "block" }
      p Object.private_instance_methods(false).include?(:in_block)
      p in_block

      def outer
        def nested = "nested"
      end
      outer
      p Object.public_instance_methods(false).include?(:nested)
      p Object.new.nested

      # The cref is where the `def` was WRITTEN, so one inside a method body of a
      # class lands on that class -- and is public, since the visibility belongs to
      # the frame and only the top level's is private.
      class Home
        def build
          def made = "made"
          [1].each { def blocky = "blocky" }
        end
      end
      Home.new.build
      p Home.public_instance_methods(false).sort
      p Home.private_instance_methods(false)

      module Mod
        def self.go
          [1].each { def from_block = "from_block" }
        end
      end
      Mod.go
      p Mod.instance_methods(false), Mod.singleton_methods(false)

      # The three forms that DO replace the definee.
      Anon = Class.new { def built = "built" }
      p Anon.new.built
      p Anon.public_instance_methods(false)

      Named = Class.new
      Named.class_eval { def evaled = "evaled" }
      Named.class_exec { def execed = "execed" }
      p Named.public_instance_methods(false).sort
      p Object.public_instance_methods(false).include?(:evaled)

      o = Object.new
      o.instance_eval { def only_mine = "mine" }
      p o.only_mine
      p o.singleton_methods
      p Object.private_instance_methods(false).include?(:only_mine)

      # An `instance_eval` nested inside a `class_eval` takes the inner rule, and
      # the outer one resumes when it closes.
      Named.class_eval do
        o.instance_eval { def nested_only = 1 }
        def after_nesting = 2
      end
      p o.singleton_methods.sort, Named.public_instance_methods(false).sort
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "block"
      true
      "nested"
      [:blocky, :build, :made]
      []
      [:from_block]
      [:go]
      "built"
      [:built]
      [:evaled, :execed]
      false
      "mine"
      [:only_mine]
      false
      [:nested_only, :only_mine]
      [:after_nesting, :evaled, :execed]
    OUT
  end

  it "defined asks a runtime scope" do
    result = ze0(<<~'RUBY')
      p defined?(Nope)
      p defined?(Nope::Deep)
      p defined?(Nope::Deep::Deeper)
      Scoped = Module.new do
        X = 1
      end
      p defined?(Scoped::X)
      p defined?(Scoped::Y)
      Val = 7
      p defined?(Val::Anything)
      p defined?(::Nope::Deep)
      module Outer; end
      p defined?(Outer::Missing)
      S2 = Module.new
      S2.const_set(:Z, 5)
      p defined?(S2::Z)
      p S2::Z
      Num = 3
      p defined?(Num::Anything)
      p defined?(Nope) ? "yes" : "no"
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      nil
      "constant"
      5
      nil
      "no"
    OUT
  end

  it "defined const fallback" do
    result = ze0(<<~'RUBY')
      # A defined?-guarded constant fallback folds to its live arm in value
      # position: the dead arm may reference the missing constant itself, and it
      # never evaluates (no NameError), matching CRuby.
      class Foo
        VER = "2.5"
      end

      v = defined?(Foo::BAR) ? Foo::BAR : "1.0.0"
      p v

      def pick = defined?(Foo::BAR) ? Foo::BAR : "fallback"
      p pick

      class Holder
        def initialize
          @v = defined?(Foo::MISSING) ? Foo::MISSING : "default"
        end
        attr_reader :v
      end
      p Holder.new.v

      # defined-true side: the dead fallback references a missing constant
      w = defined?(Foo::VER) ? Foo::VER : Foo::NOPE
      p w
      x = defined?(String) ? "have-string" : Absent::Thing
      p x

      # unless polarity
      y = "set" unless defined?(Foo::BAR)
      p y

      # statement form (both polarities)
      if defined?(Foo::BAR)
        p Foo::BAR
      else
        p "no-bar"
      end
      if defined?(Foo::VER)
        p "have-ver"
      else
        p "no-ver"
      end

      # elsif chain continues as the value
      z = if defined?(Foo::BAR)
            Foo::BAR
          elsif defined?(Foo::VER)
            Foo::VER
          else
            "neither"
          end
      p z
    RUBY

    _(result).must_answer <<~'OUT'
      "1.0.0"
      "fallback"
      "default"
      "2.5"
      "have-string"
      "set"
      "no-bar"
      "have-ver"
      "2.5"
    OUT
  end

  it "definition scoped to the runtime self" do
    result = ze0(<<~'RUBY')
      # `class self::Task` / `module self::Base` name their NAMESPACE with the
      # runtime `self`, so there is no compile-time class to register: the
      # constant lands on whichever class the enclosing hook block runs against.
      # dk-dumpdb gives every including script its own `Task` subclass this way,
      # and flight_facade's `module self::Base` is the ActiveSupport::Concern
      # spelling of the same idea.
      module Task
        def run = "ran"
      end

      module Script
        def self.hooks = (@hooks ||= [])
        def self.on_included(&blk) = hooks << blk
        def self.included(base) = hooks.each { |b| base.class_eval(&b) }

        on_included do
          class self::Task
            include Task

            def self.owner_tag = :task
          end

          module self::Helpers
            def self.tag = :helper
          end

          # A superclass expression, and the constant read back in the same body.
          class self::Timed < self::Task
            def run = "timed " + super
          end
        end
      end

      class Alpha
        include Script
      end

      class Beta
        include Script
      end

      p Alpha::Task.new.run
      p Alpha::Task.ancestors.include?(Task)
      p Alpha::Task.name
      p Alpha::Task.owner_tag
      p Alpha::Helpers.tag
      p Alpha::Timed.new.run
      p Alpha::Timed.superclass == Alpha::Task
      # Each includer gets its OWN pair -- the whole point of scoping to `self`.
      p Beta::Task.name
      p Beta::Task.equal?(Alpha::Task)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      "ran"
      true
      "Alpha::Task"
      :task
      :helper
      "timed ran"
      true
      "Beta::Task"
      false
      still running
    OUT
  end

  it "globals constants and multi assign" do
    result = ze0(<<~'RUBY')
      $counter = 0
      puts $counter
      puts $never_set
      $counter += 1
      puts $counter

      MAX = 100
      puts MAX

      class Base
        GREETING = "hi"
      end
      class Sub < Base
        def greet
          GREETING
        end
      end
      puts Sub.new.greet
      puts Base::GREETING

      begin
        puts NOT_DEFINED
      rescue NameError => e
        puts "caught: #{e.message}"
      end

      x = nil
      x ||= 5
      puts x
      y = 10
      y &&= 20
      puts y

      class Box
        attr_accessor :n
        def initialize
          @n = 0
        end
      end
      b = Box.new
      b.n += 3
      puts b.n
      b.n ||= 999
      puts b.n

      arr = [1, 2, 3]
      arr[0] += 10
      puts arr[0]
      arr[1] ||= 42
      puts arr[1]

      (a, b2), c = [[1, 2], 3]
      puts a
      puts b2
      puts c

      class Thing
        attr_reader :x
        def set_both(g)
          @x, $g2 = 10, g
        end
      end
      t = Thing.new
      t.set_both(99)
      puts t.x
      puts $g2

      for p1, p2 in [[1, 2], [3, 4]]
        puts p1 + p2
      end

      class Adder
        def add3(p, q, r)
          p + q + r
        end
      end
      adder = Adder.new
      nums = [1, 2, 3]
      puts adder.add3(*nums)
      puts adder.add3(1, *[2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      0

      1
      100
      hi
      hi
      caught: uninitialized constant NOT_DEFINED
      5
      20
      3
      3
      11
      2
      1
      2
      3
      10
      99
      3
      7
      6
      6
    OUT
  end

  it "holds shareable values it did not build" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true
      # shareable_constant_value: literal
      # Under `literal`, an Array or Hash literal may hold a value that is not
      # itself a literal when that value is shareable already: each such
      # element is checked, and the container is frozen whole. An interpolated
      # String is deduplicated first; an element that is not shareable is
      # refused by the constant's name.

      p Ractor.shareable?("x".b.freeze), Ractor.shareable?(["x".b.freeze])
      TABLE = { "a" => "x".b.freeze, "b" => ("x" "y").b.freeze }
      p TABLE, TABLE.frozen?, Ractor.shareable?(TABLE)
      NESTED = [1, "s", { k: "v".b.freeze, j: [2, :z] }]
      p NESTED, NESTED[2].frozen?, NESTED[2][:j].frozen?, Ractor.shareable?(NESTED)
      INTERPOLATED = "a#{1}b"
      p INTERPOLATED, INTERPOLATED.frozen?
      held = [1]
      begin
        REFUSED = [held]
      rescue Ractor::IsolationError => e
        p e
      end
      begin
        ALSO_REFUSED = { a: held }
      rescue Ractor::IsolationError => e
        p e
      end
      p held.frozen?

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      {"a" => "x", "b" => "xy"}
      true
      true
      [1, "s", {k: "v", j: [2, :z]}]
      true
      true
      true
      "a1b"
      true
      #<Ractor::IsolationError: cannot assign unshareable object to REFUSED>
      #<Ractor::IsolationError: cannot assign unshareable object to ALSO_REFUSED>
      false
    OUT
  end

  it "issue 3320 defined anchored const" do
    result = ze0(<<~'RUBY')
      module Underscore
        module Rails
          if defined?(::Rails)
            puts "guard TRUE"
          else
            puts "guard false"
          end
        end
      end

      module Toplevel1
      end
      module Wrap
        module Toplevel1
          p defined?(::Toplevel1)
          p defined?(::Wrap)
          p defined?(::NotDefinedAnywhere)
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      guard false
      "constant"
      "constant"
      nil
    OUT
  end

  it "issue const defined two arg" do
    _(ze0(<<~'RUBY')).must_answer "true\n"
      # Module#const_defined? only supports the single-argument form -- passing the
      # second `inherit` boolean argument raises NoMethodError as if the method
      # didn't exist at all, instead of being accepted with its normal meaning
      # (whether to also search ancestors). This breaks bare `require "uri"`: the
      # vendored gem's top level calls `RFC2396_REGEXP::PATTERN.const_defined?(sym,
      # false)` and crashes before any URI functionality can be used.
      module Foo
        X = 1
      end
      p Foo.const_defined?(:X, false)
    RUBY
  end

  it "kwarg only toplevel leading optional" do
    _(ze0(<<~'RUBY')).must_answer "a=nil k=1\n"
      # One shape per file: a companion call that supplies the positional would
      # immunise this (#3525).
      def top(a = nil, k: :default)
        "a=#{a.inspect} k=#{k.inspect}"
      end
      puts top(k: 1)
    RUBY
  end

  it "later constant reaches back" do
    result = ze0(<<~'RUBY')
      module Outer
        X = :outer
      end

      p Outer.constants.sort
      p Outer.const_defined?(:Late)

      class Outer::Late
      end

      p Outer.constants.sort
      p Outer.const_defined?(:Late)
    RUBY

    _(result).must_answer <<~'OUT'
      [:X]
      false
      [:Late, :X]
      true
    OUT
  end

  it "leading colon colon skips a shadowing scope" do
    result = ze0(<<~'RUBY')
      # `::Widget` means the TOP-LEVEL `Widget`, whatever the enclosing scopes call
      # their own. zeo lowered the anchor to a read scoped to `Object`, and when that
      # found nothing it re-resolved the BARE name -- through the lexical chain,
      # which is precisely what the `::` prefix says not to do. Inside a scope that
      # shadows the name, the anchored reference answered the shadow.
      #
      # Silently: the shadow is a real class, so nothing raised and nothing warned.
      # `NS::Array#to_a` calling `::Array.new` reached `NS::Array.new` and got an
      # ArgumentError from a constructor it never meant to call -- and a shadow with
      # a compatible constructor would simply have returned the wrong object.
      class Widget
        def self.who = :toplevel
      end
      module NS
        class Widget
          def self.who = :nested
          def anchored = ::Widget.who
          def bare = Widget.who
        end
      end
      p NS::Widget.new.anchored
      p NS::Widget.new.bare

      # The case that found it: a class shadowing a BUILTIN name, which is what any
      # gem defining its own `Array`/`Hash`/`Set` does.
      module Collections
        class Array
          def build = ::Array.new(2) { |i| i * 3 }
          def anchored = ::Array
          def bare = Array
        end
        class Hash
          def anchored = ::Hash
        end
      end
      p Collections::Array.new.build
      p Collections::Array.new.anchored
      p Collections::Array.new.bare
      p Collections::Hash.new.anchored

      # A value constant takes the same anchor.
      VERSION = "top"
      module Versioned
        VERSION = "nested"
        class Reader
          def anchored = ::VERSION
          def bare = VERSION
        end
      end
      p Versioned::Reader.new.anchored
      p Versioned::Reader.new.bare

      # A module shadowing its own enclosing module's name -- the anchor reaches past
      # every level, not just one.
      module Deep
        module Deep
          def self.who = :inner
        end
        def self.who = :outer
        class C
          def anchored = ::Deep.who
          def bare = Deep.who
        end
      end
      p Deep::C.new.anchored
      p Deep::C.new.bare

      # An arbitrary `Scope::Name` must NOT gain the same fallback: `M::V` is M's own
      # constant, never the unrelated top-level one.
      module M
        V = :m_owns_it
      end
      V = :top_level
      p M::V
      p ::V
    RUBY

    _(result).must_answer <<~'OUT'
      :toplevel
      :nested
      [0, 3]
      Array
      Collections::Array
      Hash
      "top"
      "nested"
      :outer
      :inner
      :m_owns_it
      :top_level
    OUT
  end

  it "masgn constpath target" do
    result = ze0(<<~'RUBY', path: "lang/constants/masgn_constpath_target.rb")
      # Constant-path multi-assignment targets (`a, M::X = 1, 2`). Each
      # ConstantPathTargetNode resolves to the qualified constant's slot so
      # the destructured value lands in the right place.
      module M
        X = 0
        Y = 0
      end
      a, M::X = 1, 2
      p [a, M::X]
      b, M::Y = 10, 20
      p [b, M::Y]
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/constants/masgn_constpath_target.rb:8: warning: already initialized constant M::X\nlang/constants/masgn_constpath_target.rb:5: warning: previous definition of X was here\nlang/constants/masgn_constpath_target.rb:10: warning: already initialized constant M::Y\nlang/constants/masgn_constpath_target.rb:6: warning: previous definition of Y was here\n"
      [1, 2]
      [10, 20]
    OUT
  end

  it "namespaced constant read via double colon" do
    _(ze0(<<~'RUBY')).must_answer "42\n"
      class Foo
        BAR = 42
      end
      puts Foo::BAR
    RUBY
  end

  it "namespaces" do
    result = ze0(<<~'RUBY')
      module Store
        DEFAULT = 10

        class Item
          def initialize(name)
            @name = name
          end

          def price
            DEFAULT
          end

          def label
            "#{@name} ($#{price})"
          end
        end

        class Errors
          class NotFound
            def msg
              "not found"
            end
          end
        end
      end

      module Registry
        class Item
          def price
            99
          end
        end
      end

      puts Store::Item.new("apple").label
      puts Registry::Item.new.price
      puts Store::Errors::NotFound.new.msg
      puts Store::DEFAULT

      class Store::Cart
        def initialize
          @items = []
        end

        def add(item)
          @items << item
          self
        end

        def count
          @items.length
        end
      end

      cart = Store::Cart.new
      cart.add(Store::Item.new("pear")).add(Store::Item.new("plum"))
      puts cart.count
    RUBY

    _(result).must_answer <<~'OUT'
      apple ($10)
      99
      not found
      10
      2
    OUT
  end

  it "nesting and assignment" do
    result = ze0(<<~'RUBY')
      module Store
        LIMIT = 3

        class Item
          KIND = "item"

          def initialize(name, price)
            @name = name
            @price = price
          end

          def name
            @name
          end

          def price
            @price
          end

          def kind
            [KIND, LIMIT]
          end

          def to_s
            "#{@name}@#{@price}"
          end
        end

        class Discounted < Item
          def price
            @price / 2
          end
        end

        module Format
          SEP = ", "

          def self.join(parts)
            parts.join(SEP)
          end
        end

        def self.build(name, price)
          Item.new(name, price)
        end
      end

      p Store
      p Store::Item
      p Store::Item::KIND
      p Store::LIMIT
      p Store::Item.name
      p Store::Format::SEP

      item = Store::Item.new("pen", 10)
      p item.name
      p item.kind
      puts item
      p Store.build("cup", 8).price
      p Store::Discounted.new("hat", 20).price
      p Store::Discounted.superclass
      p Store::Format.join(["a", "b"])

      a, b = 1, 2
      p [a, b]
      a, b = b, a
      p [a, b]
      c, d = [3, 4]
      p [c, d]
      e, f = 5
      p [e, f]
      g, *rest = [1, 2, 3, 4]
      p [g, rest]
      *init, last = [1, 2, 3]
      p [init, last]
      h, (i, j), k = 1, [2, 3], 4
      p [h, i, j, k]
      x, = [9, 8]
      p x
      $g1, $g2 = 1, 2
      p [$g1, $g2]
      @m, @n = 3, 4
      p [@m, @n]
      P1, P2 = 5, 6
      p [P1, P2]
      arr = [0, 0]
      arr[0], arr[1] = 7, 8
      p arr

      def two
        [1, 2]
      end
      m, n = two
      p [m, n]

      word = /\A[a-z]+\z/
      p word
      p "abc".match?(word)
      p "Abc".match?(word)
      p "Abc".match?(/\Aa/i)
      p "a-b-c".split(/-/)
      p "x1y2".gsub(/\d/) { |digit| "<#{digit}>" }
      p word.source

      counts = {}
      counts["k"] ||= 1
      counts["k"] ||= 2
      counts["k"] += 10
      p counts

      class Holder
        def initialize
          @v = nil
        end

        def v
          @v
        end

        def v=(value)
          @v = value
        end
      end

      hold = Holder.new
      hold.v ||= "first"
      hold.v ||= "second"
      p hold.v
      hold.v &&= "#{hold.v}!"
      p hold.v
    RUBY

    _(result).must_answer <<~'OUT'
      Store
      Store::Item
      "item"
      3
      "Store::Item"
      ", "
      "pen"
      ["item", 3]
      pen@10
      8
      10
      Store::Item
      "a, b"
      [1, 2]
      [2, 1]
      [3, 4]
      [5, nil]
      [1, [2, 3, 4]]
      [[1, 2], 3]
      [1, 2, 3, 4]
      9
      [1, 2]
      [3, 4]
      [5, 6]
      [7, 8]
      [1, 2]
      /\A[a-z]+\z/
      true
      false
      true
      ["a", "b", "c"]
      "x<1>y<2>"
      "\\A[a-z]+\\z"
      {"k" => 11}
      "first"
      "first!"
    OUT
  end

  it "parameter default assigns the scope s own local" do
    result = ze0(<<~'RUBY')
      # `def discard(key = (no_arg = true))` is ruby's idiom for "was an argument
      # passed?" -- the default expression assigns a local, and the body reads it.
      # That local belongs to the scope being DEFINED: the default runs in the
      # callee's own frame, only when the argument is omitted.
      #
      # Reading only the body saw the read and no assignment, so an inner block
      # spelling it this way looked like it captured its enclosing block's own
      # local -- the one nesting shape codegen refuses. roda's flash plugin and
      # pantheios' thread naming both write it.
      class Flash
        def initialize = @seen = []

        def discard(key = (no_arg = true))
          no_arg ? :cleared_all : [:cleared, key]
        end
      end

      p Flash.new.discard
      p Flash.new.discard(:notice)

      # The same default inside a `define_method` written in a block -- the nesting
      # that made this a rejection rather than a wrong answer.
      class Named; end
      Named.instance_eval do
        define_method :thread_name do |name = (name_not_given = true)|
          if name_not_given
            "unnamed"
          else
            "named-#{name}"
          end
        end
      end

      p Named.new.thread_name
      p Named.new.thread_name("worker")

      # A keyword default assigns the same way, and a default that reads an EARLIER
      # parameter still sees it.
      def sized(width, height = (square = true; width), unit: (bare = true; "px"))
        [width, height, unit, square, bare]
      end

      p sized(3)
      p sized(3, 4, unit: "em")

      # The enclosing scope keeps its OWN name of the same spelling: the default's
      # assignment never reaches out.
      square = :outer
      p sized(2)
      p square
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      :cleared_all
      [:cleared, :notice]
      "unnamed"
      "named-worker"
      [3, 3, "px", true, true]
      [3, 4, "em", nil, nil]
      [2, 2, "px", true, true]
      :outer
      still running
    OUT
  end

  it "private constant" do
    result = ze0(<<~'RUBY')
      # `private_constant` hides the SCOPE OPERATOR, not the reader: `M::S` raises
      # everywhere -- even inside `M`'s own body -- while a bare `S` resolved through
      # the cref still answers, and so does `M.const_get(:S)`. That split is what
      # makes it a real access rule rather than a naming convention.

      module M
        SECRET = 1
        OPEN = 2
        class Hidden; end
        module Nested; end
        private_constant :SECRET, :Hidden, :Nested

        def self.bare_value = SECRET
        def self.bare_class = Hidden
        def self.qualified = M::SECRET
      end

      puts "-- the listing omits them"
      p M.constants.sort

      puts "-- but the bindings are still there"
      p M.const_defined?(:SECRET)
      p M.const_defined?(:SECRET, false)
      p M.const_get(:SECRET)
      p M.const_get(:Hidden)
      p Object.const_get("M::SECRET")

      puts "-- a bare reference through the cref answers"
      p M.bare_value
      p M.bare_class

      puts "-- the scope operator does not, from anywhere"
      [
        -> { M::SECRET },
        -> { M::Hidden },
        -> { M::Nested },
        -> { M.qualified },
      ].each do |probe|
        begin
          probe.call
        rescue NameError => e
          puts e.message
        end
      end
      p M::OPEN

      puts "-- defined? agrees with the reference, not with const_defined?"
      p defined?(M::SECRET)
      p defined?(M::Hidden)
      p defined?(M::OPEN)
      p defined?(M)

      puts "-- public_constant restores it, at run time"
      M.public_constant :SECRET
      p M::SECRET
      p defined?(M::SECRET)
      p M.constants.sort

      puts "-- and a subclass reads its parent's private constant bare"
      class K
        A = 3
        private_constant :A
      end
      begin
        K::A
      rescue NameError => e
        puts e.message
      end
      class Sub < K
        def self.peek = A
      end
      p Sub.peek

      puts "-- const_get walks a path"
      module Outer
        module Inner
          LEAF = 9
        end
      end
      p Object.const_get("Outer::Inner::LEAF")
      p Object.const_get("Outer::Inner")
      begin
        Object.const_get("Outer::Nope")
      rescue NameError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      -- the listing omits them
      [:OPEN]
      -- but the bindings are still there
      true
      true
      1
      M::Hidden
      1
      -- a bare reference through the cref answers
      1
      M::Hidden
      -- the scope operator does not, from anywhere
      private constant M::SECRET referenced
      private constant M::Hidden referenced
      private constant M::Nested referenced
      private constant M::SECRET referenced
      2
      -- defined? agrees with the reference, not with const_defined?
      nil
      nil
      "constant"
      "constant"
      -- public_constant restores it, at run time
      1
      "constant"
      [:OPEN, :SECRET]
      -- and a subclass reads its parent's private constant bare
      private constant K::A referenced
      3
      -- const_get walks a path
      9
      Outer::Inner
      uninitialized constant Outer::Nope
    OUT
  end

  it "private constant directive has a value" do
    result = ze0(<<~'RUBY')
      # `private_constant :Hidden` as the last statement of a module body is where
      # rspec-openapi and three other gems put it -- and a module body is an
      # expression, so something can read what it evaluates to. The directive
      # itself is a compile-time fact with no runtime emission; its VALUE is the
      # module it hid the constant on (oracle-checked).
      module M
        Hidden = 1
        private_constant :Hidden
      end
      p M.constants
      v = module N
        Inner = 2
        private_constant :Inner
      end
      p v
      class K
        Secret = 3
        private_constant :Secret
      end
      p K.constants
      begin
        M::Hidden
      rescue NameError => e
        p e.class
      end
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      []
      N
      []
      NameError
      still running
    OUT
  end

  it "qualified constant writes target the named namespace" do
    _(ze0(<<~'RUBY')).must_answer "99\n"
      module Cfg
      end

      Cfg::LIMIT = 99
      puts Cfg::LIMIT
    RUBY
  end

  it "qualified definition form does not see the namespace lexically" do
    _(ze0(<<~'RUBY')).must_answer "NameError: uninitialized constant Store::Cart::DEFAULT\n"
      # `class Store::Cart`'s cref is just [Cart] -- real Ruby raises
      # NameError for `DEFAULT`, naming the cref head's qualified path.

      module Store
        DEFAULT = 10
      end

      class Store::Cart
        def d
          DEFAULT
        rescue NameError => e
          "NameError: #{e.message}"
        end
      end

      puts Store::Cart.new.d
    RUBY
  end

  it "qualified definition sees the scope it is written in" do
    result = ze0(<<~'RUBY', path: "lang/constants/a_qualified_definition_sees_the_scope_it_is_written_in.rb")
      # `class A::B` skips the prefix it SPELLS -- its body does not see `A`'s
      # constants lexically -- but it keeps every scope it is written inside.
      # httpx spells `class Connection::HTTP2` inside `module HTTPX` and then
      # `class Error < Error`, meaning `HTTPX::Error`.
      module HTTPX
        MAX = 42
        class Error < StandardError; end
        class Connection; end

        class Connection::HTTP2
          LOCAL = MAX + 1

          class Error < Error
            def tag = "h2"
          end
          class PingError < Error; end

          def limit = MAX
        end
      end

      p HTTPX::Connection::HTTP2::Error.superclass
      p HTTPX::Connection::HTTP2::PingError.superclass
      p HTTPX::Connection::HTTP2::Error.new.tag
      p HTTPX::Connection::HTTP2::LOCAL
      p HTTPX::Connection::HTTP2.new.limit
      p HTTPX::Connection::HTTP2.name

      # The prefix itself stays invisible: `Connection`'s own constants are not in
      # the cref, so a bare name that only it defines raises.
      module Store
        class Bin
          HIDDEN = :bin
        end
        class Bin::Slot
          def peek
            HIDDEN
          rescue NameError => e
            e.class
          end
        end
      end
      p Store::Bin::Slot.new.peek

      # A top-level qualified definition has nothing enclosing it, so its cref is
      # just itself.
      TOP = :top
      class Store::Loose
        def reach = TOP
      end
      p Store::Loose.new.reach

      # A superclass that names the class being DEFINED and resolves nowhere else is
      # ruby's NameError at the definition, not a compile failure -- api_notify has
      # its `require "logger"` commented out and ruby raises there too. The class
      # must not come into being either: the search that looks for the name may not
      # mint a shell of it on the way past.
      module ApiNotify
        module ActiveRecord
          class Logger < Logger
            def tag = "x"
          end
        end
      end
      p ApiNotify::ActiveRecord::Logger.superclass
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/constants/a_qualified_definition_sees_the_scope_it_is_written_in.rb:60:in '<module:ActiveRecord>': uninitialized constant ApiNotify::ActiveRecord::Logger (NameError)\n\n    class Logger < Logger\n                   ^^^^^^\n\tfrom lang/constants/a_qualified_definition_sees_the_scope_it_is_written_in.rb:59:in '<module:ApiNotify>'\n\tfrom lang/constants/a_qualified_definition_sees_the_scope_it_is_written_in.rb:58:in '<main>'\n", status: 1
      HTTPX::Error
      HTTPX::Connection::HTTP2::Error
      "h2"
      43
      42
      "HTTPX::Connection::HTTP2"
      NameError
      :top
    OUT
  end

  it "qualified missing constant value" do
    result = ze0(<<~'RUBY')
      # An unresolvable constant raises NameError, and in a value position its raise
      # carries an sp_Class the slot cannot hold, so the tail assignment casts it to
      # the slot's own zero. The list of node kinds that got that treatment named the
      # bare spelling and not the qualified one, so a rescued `M::Missing` in a value
      # position assigned an sp_Class to a `const char *` and did not build at all --
      # a program CRuby runs and answers.
      r = begin
        NoSuchMod::NoSuchConstF
      rescue NameError
        "qualified"
      end
      p r

      # the same in an Integer-typed slot, and in an object-typed one
      n = begin
        Absent::COUNT
      rescue NameError
        7
      end
      p n

      class Frame
        attr_reader :n
        def initialize(n); @n = n; end
      end
      f = begin
        Gone::FRAME
      rescue NameError
        Frame.new(3)
      end
      p f.n

      # a deeper path, and one whose parent is a real module
      module Real; end
      d = begin
        Real::Missing::Deep
      rescue NameError
        "deep"
      end
      p d
    RUBY

    _(result).must_answer <<~'OUT'
      "qualified"
      7
      3
      "deep"
    OUT
  end

  it "ruby version constants" do
    result = ze0(<<~'RUBY')
      # RUBY_* version/build constants and the File::SEPARATOR family that zeo
      # shares with its ruby 4.0.6 oracle. The platform/revision are machine- and
      # build-specific, so this checks the STABLE shared values exactly and the
      # dynamic ones structurally, keeping the golden output portable across build
      # hosts AND identical between zeo and the oracle.
      #
      # The ENGINE-IDENTITY constants (RUBY_ENGINE, RUBY_ENGINE_VERSION,
      # RUBY_DESCRIPTION) mirror CRuby's own ("ruby", RUBY_VERSION, version.c's
      # banner). Their exact values are asserted in `ruby_engine_identifies_as_ruby`;
      # this golden covers the shared version/build constants.
      puts RUBY_VERSION
      puts RUBY_PATCHLEVEL
      puts RUBY_RELEASE_DATE
      puts File::SEPARATOR
      p File::ALT_SEPARATOR
      puts File::PATH_SEPARATOR

      # Structural checks (true on every build host, both engines):
      puts RUBY_PLATFORM.include?("-")
      puts RUBY_REVISION.length >= 10
    RUBY

    _(result).must_answer <<~'OUT'
      4.0.6
      0
      2026-07-14
      /
      nil
      :
      true
      true
    OUT
  end

  it "runtime names" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # A name only the run time builds. Each of these verbs mints its methods
      # where it stands rather than from a row, so the compile has nothing to
      # emit and the call goes out as an ordinary send.

      class Fields
        %i[a b].each { |n| attr_accessor n }

        def initialize
          @a = 1
          @b = 2
        end

        def orig = :orig

        COPY = :copy
        alias_method COPY, :orig
      end

      f = Fields.new
      p f.a, f.b
      f.a = 9
      p f.a, f.copy
      p Fields.instance_methods(false).sort

      # An interpolated `alias` and `undef` name is a value the runtime takes
      # exactly as it takes a literal.
      class Named
        def base = :base

        n = 1
        alias :"base#{n}" :base
      end

      p Named.new.base1

      class Retired
        def gone = :gone
        n = 2
        def gone2 = :gone2
        undef :"gone#{n}"
      end

      p Retired.new.gone
      p Retired.new.respond_to?(:gone2)

      # `` `cmd` `` runs the string through the shell, interpolated or not.
      p `echo one`.strip
      who = "two"
      p `echo #{who}`.strip
      p $?.success?
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      9
      :orig
      [:a, :a=, :b, :b=, :copy, :orig]
      :base
      :gone
      false
      "one"
      "two"
      true
    OUT
  end

  it "small namespaces" do
    result = ze0(<<~'RUBY')
      # Three namespaces ruby carries that zeo lacked, none of which has a method
      # of its own -- they are names, and a name is the whole contract.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      # `UnicodeNormalize` is an EMPTY module: the namespace `String`'s
      # `#unicode_normalize` family is documented under.
      show("UnicodeNormalize class") { UnicodeNormalize.class }
      show("UnicodeNormalize methods") { UnicodeNormalize.instance_methods(false) }
      show("UnicodeNormalize singletons") { UnicodeNormalize.singleton_methods(false) }
      show("UnicodeNormalize constants") { UnicodeNormalize.constants(false) }
      show("UnicodeNormalize name") { UnicodeNormalize.name }

      # `Set::CoreSet` is a Set subclass with no methods of its own, and NOT the
      # same object as `Set`.
      show("CoreSet name") { Set::CoreSet.name }
      show("CoreSet superclass") { Set::CoreSet.superclass }
      show("CoreSet ancestors") { Set::CoreSet.ancestors.take(3) }
      show("CoreSet own methods") { Set::CoreSet.instance_methods(false) }
      show("CoreSet is not Set") { Set::CoreSet.equal?(Set) }

      # ruby defines `BasicObject` as a constant on ITSELF, which is why its own
      # constant list is not empty where every other class's is.
      show("BasicObject constants") { BasicObject.constants(false) }
      show("BasicObject::BasicObject") { BasicObject::BasicObject }
      show("Object constants(false) has no self") { Object.constants(false).include?(:Object) }
    RUBY

    _(result).must_answer <<~'OUT'
      UnicodeNormalize class: Module
      UnicodeNormalize methods: []
      UnicodeNormalize singletons: []
      UnicodeNormalize constants: []
      UnicodeNormalize name: "UnicodeNormalize"
      CoreSet name: "Set::CoreSet"
      CoreSet superclass: Set
      CoreSet ancestors: [Set::CoreSet, Set, Enumerable]
      CoreSet own methods: []
      CoreSet is not Set: false
      BasicObject constants: [:BasicObject]
      BasicObject::BasicObject: BasicObject
      Object constants(false) has no self: true
    OUT
  end

  it "svar scope belongs to the frame that matched" do
    result = ze0(<<~'RUBY')
      # `$~` -- and every read that goes through it (`$1`, `$&`, `` $` ``, `$'`,
      # `Regexp.last_match`) -- is FRAME-LOCAL. A scope that matches and returns
      # leaves the caller's match exactly as it found it, and a scope that never
      # matched reads the one it inherited from where it was ENTERED.
      #
      # The rule follows the frame: a method, a class or module body and a
      # singleton-class body each get a scope of their own; a block, a lambda and a
      # `define_method` body share the scope of the frame they run under, because
      # that is the frame ruby gives them.

      probe = -> { [$~ && $~[0], $1] }

      # --- a method keeps its match to itself ------------------------------------
      def matches(s)
        s =~ /(y)/
        $1
      end
      "abc" =~ /(b)/
      p matches("xyz")
      p probe.call

      # A method that matches without ever naming an svar still needs the scope.
      def silent(s)
        s.match(/(y)/)
        :done
      end
      "abc" =~ /(b)/
      p silent("xyz")
      p probe.call

      # --- a class body is a frame, so it is a scope -----------------------------
      "abc" =~ /(b)/
      class Body
        "xyz" =~ /(y)/
        INSIDE = $1
      end
      p Body::INSIDE
      p probe.call

      "abc" =~ /(b)/
      module Mod
        "xyz" =~ /(y)/
      end
      p probe.call

      class Sing
        class << self
          "xyz" =~ /(y)/
        end
      end
      p probe.call

      # --- a block shares the frame it runs under --------------------------------
      "abc" =~ /(b)/
      [1].each { "xyz" =~ /(y)/ }
      p probe.call

      "abc" =~ /(b)/
      -> { "xyz" =~ /(y)/ }.call
      p probe.call

      "abc" =~ /(b)/
      Class.new { "xyz" =~ /(y)/ }
      p probe.call

      # ...but a block inside a METHOD writes that method's scope, not ours.
      def through_a_block(s)
        [1].each { s =~ /(y)/ }
        $1
      end
      "abc" =~ /(b)/
      p through_a_block("xyz")
      p probe.call

      # --- a class method and a `define_method` body -----------------------------
      class Owner
        def self.classy(s)
          s =~ /(y)/
          $1
        end
        define_method(:installed) do |s|
          s =~ /(y)/
          $1
        end
      end
      "abc" =~ /(b)/
      p Owner.classy("xyz")
      p probe.call
      p Owner.new.installed("xyz")
      p probe.call

      # --- a scope that fails to match reports the failure, not the inherited one -
      def fails(s)
        s =~ /(q)/
        [$~, $1]
      end
      "abc" =~ /(b)/
      p fails("xyz")
      p probe.call

      # --- an early return cannot leak the callee's match ------------------------
      def early(s)
        return :none unless s =~ /(y)/
        $1
      end
      "abc" =~ /(b)/
      p early("zzz")
      p probe.call

      # --- a raise out of a matched scope pops it too ----------------------------
      def raises(s)
        s =~ /(y)/
        raise "boom"
      end
      "abc" =~ /(b)/
      begin
        raises("xyz")
      rescue RuntimeError
        p probe.call
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "y"
      ["b", "b"]
      :done
      ["b", "b"]
      "y"
      ["b", "b"]
      ["b", "b"]
      ["b", "b"]
      ["y", "y"]
      ["y", "y"]
      ["y", "y"]
      "y"
      ["b", "b"]
      "y"
      ["b", "b"]
      "y"
      ["b", "b"]
      [nil, nil]
      ["b", "b"]
      :none
      ["b", "b"]
      ["b", "b"]
    OUT
  end

  it "top level constant read and write" do
    _(ze0(<<~'RUBY')).must_answer "100\n"
      MAX = 100
      puts MAX
    RUBY
  end

  it "top level def defines and calls" do
    result = ze0(<<~'RUBY')
      def greet(name, punct = "!")
        "hi #{name}#{punct}"
      end
      puts greet("world")
      puts greet("you", "?")
    RUBY

    _(result).must_answer <<~'OUT'
      hi world!
      hi you?
    OUT
  end

  it "top level def used as a value is still private" do
    result = ze0(<<~'RUBY')
      # A top-level `def` is a PRIVATE instance method of Object. Writing it where a
      # value is read does not change that -- `p(def m; end)` is the same definition,
      # and only the `:m` it answers with is new. zeo registers the bare spelling at
      # analyze time and reaches codegen's expression form for this one, which
      # installs through `define_method` and so came out public.
      p(def top; end)
      p Object.private_instance_methods(false).include?(:top)
      p Object.public_instance_methods(false).include?(:top)

      # Callable through implicit self, and not with a receiver -- which is the whole
      # observable consequence of the mark.
      p top.nil?
      begin
        self.top
      rescue NoMethodError => e
        puts e.message
      end
      p Object.new.respond_to?(:top)
      p Object.new.respond_to?(:top, true)

      # A class body's default is PUBLIC, and the same value position must not borrow
      # the top level's rule.
      class K
        p(def in_class; end)
      end
      p K.public_instance_methods(false).include?(:in_class)
      p K.new.in_class.nil?

      # `def self.x` in a value position is a singleton method of `main`, not an
      # Object instance method -- a different definee, so a different rule.
      p(def self.on_main; end)
      p Object.private_instance_methods(false).include?(:on_main)
      p on_main.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      :top
      true
      false
      true
      false
      true
      :in_class
      true
      true
      :on_main
      false
      true
    OUT
  end

  it "top level private marks the following defs" do
    result = ze0(<<~'RUBY')
      # `main`'s private singleton methods. CRuby installs eight on the top-level
      # self (`define_method`, `include`, `inspect`, `private`, `public`,
      # `ruby2_keywords`, `to_s`, `using`); each of the mixin ones lands on
      # `Object`, which is what makes what it does visible everywhere afterwards.
      #
      # zeo installs no singleton on main at all -- doing it at startup would mark
      # the runtime-overlay maps live for every program -- so dispatch routes the
      # names instead. Only `include` was routed, and a bare `private` at top level
      # (plain Ruby, and the shape rubygems' own files open with) was a
      # NoMethodError naming `main`.
      #
      # Reflection reads the same list, so `respond_to?`, `private_methods` and
      # `singleton_methods` cannot drift from what dispatch answers.

      def helper = "helper"
      private :helper
      puts "private with a name  #{Object.private_method_defined?(:helper)}"
      puts "still callable       #{helper}"

      def public_one = "public"
      public :public_one
      puts "public with a name   #{Object.public_method_defined?(:public_one)}"
      puts "through self         #{self.public_one}"

      private
      def after_bare = "after"
      puts "after bare private   #{Object.private_method_defined?(:after_bare)}"
      puts "still callable       #{after_bare}"

      define_method(:from_define) { "from_define" }
      puts "define_method        #{from_define}"

      module Mixed
        def from_mixed = "from_mixed"
      end
      include Mixed
      puts "include at top       #{from_mixed}"
      puts "reached Object       #{Object.ancestors.include?(Mixed)}"

      puts "to_s                 #{self.to_s}"
      puts "inspect              #{self.inspect}"
      puts "public singletons    #{self.singleton_methods.sort}"
      puts "respond_to? private  #{respond_to?(:private, true)}"
      puts "respond_to? public   #{respond_to?(:public, true)}"
      puts "not without all      #{respond_to?(:private)}"
      puts "private_methods      #{(self.private_methods & %i[private public include define_method]).sort}"
    RUBY

    _(result).must_answer <<~'OUT'
      private with a name  true
      still callable       helper
      public with a name   true
      through self         public
      after bare private   true
      still callable       after
      define_method        from_define
      include at top       from_mixed
      reached Object       true
      to_s                 main
      inspect              main
      public singletons    [:inspect, :to_s]
      respond_to? private  true
      respond_to? public   true
      not without all      false
      private_methods      [:define_method, :include, :private, :public]
    OUT
  end

  it "top level self is the main object" do
    _(ze0(<<~'RUBY')).must_answer "true\n"
      puts self.is_a?(Object)
    RUBY
  end

  it "toplevel def private on object" do
    result = ze0(<<~'RUBY')
      # A top-level `def` lands on Object as a PRIVATE method: CRuby answers an
      # explicit-receiver call with "private method called", never with the method.
      # Spinel counted such a def as owning the name for every receiver dispatch, so
      # a builtin arm stood down for it -- and with no user CLASS defining the name,
      # `v.upcase` on a boxed receiver compiled to an unconditional NoMethodError.
      def upcase(v) = "top-upcase:#{v}"
      def chars(v) = "top-chars:#{v}"
      def empty?(v) = v.nil?
      def size(v) = -1

      def up(v) = v.upcase
      def ch(v) = v.chars
      def blank(v) = v&.empty?

      p up("abc")
      p ch("abc")
      p blank("abc")
      p blank(nil)

      # the top-level methods themselves still answer an implicit-receiver call
      p upcase(1)
      p chars(2)
      p empty?(nil)
      p size(3)

      # a user CLASS defining the name still owns it: the dispatch keeps a builtin
      # arm alongside the class arm
      class Shout
        def upcase = "SHOUT"
      end

      def either(v) = v.upcase
      p either("abc")
      p either(Shout.new)
    RUBY

    _(result).must_answer <<~'OUT'
      "ABC"
      ["a", "b", "c"]
      false
      nil
      "top-upcase:1"
      "top-chars:2"
      true
      -1
      "ABC"
      "SHOUT"
    OUT
  end

  it "toplevel def self" do
    result = ze0(<<~'RUBY')
      # A top-level `def self.name` / `class << self` installs SINGLETON methods on
      # the `main` object (Batch G) -- callable via implicit self at the top level,
      # but not from inside another object (CRuby's asymmetry with a plain top-level
      # `def`, which is a private Object instance method).

      def self.only_main
        "main-only"
      end

      def self.wrap
        "[#{yield}]"
      end

      class << self
        def shout
          "MAIN"
        end
      end

      puts only_main
      puts wrap { "inner" }
      puts shout

      class Widget
        def try
          only_main rescue "not visible in Widget"
        end
      end
      puts Widget.new.try
    RUBY

    _(result).must_answer <<~'OUT'
      main-only
      [inner]
      MAIN
      not visible in Widget
    OUT
  end

  it "two namespaces can share a constant leaf" do
    result = ze0(<<~'RUBY')
      # Two namespaces may each hold a constant of the same LEAF name, and neither
      # may answer for the other. One row per shape, printed as `name<TAB>result`.
      #
      # zeo decides at LOWERING time whether a `class X < Super` is a compile-time
      # class or a runtime `X = Class.new(Super)`, and that decision reads two
      # whole-program tables: "is this constant assigned?" and "is this constant a
      # class definition?". The second always asked from the CREF the site is
      # written in; the first asked by BARE LEAF, over the whole program.
      #
      # So one namespace's `Path = Struct.new(...) do ... end` made every `class X <
      # Path` anywhere look like a subclass of a runtime-minted class, and a plain
      # `class Path` in another namespace was rewritten into a runtime REOPEN of a
      # class that does not exist there -- `uninitialized constant Files::Path`,
      # four lines into this file, for ordinary Ruby.
      #
      # Under `require "bundler"` the same collision was quieter and worse:
      # `Bundler::Settings::Path` rewrote `class Git < Path` in
      # `bundler/source/git.rb` to `Git = Class.new(Path)`, so
      # `Bundler::Source::Git` existed TWICE -- once as a compile-time class
      # nothing ever revealed, once as the runtime class in the constant table.
      # `const_get(:Git)` answered the second and `Bundler::Source::Git` raised on
      # the first.
      #
      # The fix is one rule: a scope-less write is keyed by its cref path, and the
      # query is Ruby's own lexical search -- exactly what `record_class_def` and
      # `class_defined_in_scope` already did for the class half. Two hand-rolled
      # leaf-matching workarounds went away with it.
      #
      # Every row below is ordinary Ruby with an unambiguous answer.

      def row(name)
        print name, "\t"
        begin
          puts(yield.inspect)
        rescue Exception => e
          puts "#{e.class}: #{e.message}"
        end
      end

      # --- 1. a runtime-minted constant beside a same-leaf class -------------------

      module Settings
        Path = Struct.new(:a) do
          def kind = "struct"
        end
      end

      module Files
        class Path
          def kind = "class"
        end
        class Sub < Path
        end
      end

      row("settings_path_kind") { Settings::Path.new(1).kind }
      row("files_path_kind") { Files::Path.new.kind }
      row("files_sub_superclass") { Files::Sub.superclass.to_s }
      row("files_sub_kind") { Files::Sub.new.kind }
      row("files_sub_name") { Files::Sub.name }
      # The class must be the SAME object by both routes -- the failure this probe
      # was written for produced two.
      row("files_path_identity") { Files::Path.equal?(Files.const_get(:Path)) }
      row("files_sub_identity") { Files::Sub.equal?(Files.const_get(:Sub)) }
      row("files_constants") { Files.constants.sort.inspect }

      # --- 2. the collision in the other order ------------------------------------

      module Early
        class Token
          def kind = "class"
        end
        class Tagged < Token
        end
      end

      module Late
        Token = Class.new do
          def kind = "runtime"
        end
      end

      row("early_tagged_superclass") { Early::Tagged.superclass.to_s }
      row("early_tagged_kind") { Early::Tagged.new.kind }
      row("late_token_kind") { Late::Token.new.kind }

      # --- 3. a genuine runtime superclass still works ----------------------------

      module Real
        Base = Class.new do
          def kind = "runtime-base"
        end
        class Derived < Base
          def extra = 7
        end
      end

      row("real_derived_superclass") { Real::Derived.superclass.equal?(Real::Base) }
      row("real_derived_kind") { Real::Derived.new.kind }
      row("real_derived_extra") { Real::Derived.new.extra }
      row("real_derived_name") { Real::Derived.name }

      # --- 4. a qualified superclass naming a runtime constant --------------------

      module Outer
        module Inner
          Impl = Class.new do
            def kind = "inner-impl"
          end
        end
        class Uses < Inner::Impl
        end
      end

      row("outer_uses_superclass") { Outer::Uses.superclass.equal?(Outer::Inner::Impl) }
      row("outer_uses_kind") { Outer::Uses.new.kind }

      # --- 5. a bare top-level constant must not capture a nested class -----------

      Marker = 7

      module Holder
        class Marker
          def kind = "nested"
        end
        class UsesMarker < Marker
        end
      end

      row("toplevel_marker") { Marker }
      row("holder_marker_kind") { Holder::Marker.new.kind }
      row("holder_uses_superclass") { Holder::UsesMarker.superclass.to_s }

      # --- 6. the same leaf three deep --------------------------------------------

      module A1
        Value = Class.new { def where = "A1" }
      end
      module B1
        class Value
          def where = "B1"
        end
        class Uses < Value; end
      end
      module C1
        Value = 3
      end

      row("a1_value_where") { A1::Value.new.where }
      row("b1_uses_where") { B1::Uses.new.where }
      row("b1_uses_superclass") { B1::Uses.superclass.to_s }
      row("c1_value") { C1::Value }

      # --- 7. reopening: a bare `class X` where an unrelated X is runtime-minted --

      module Mint
        Shape = Class.new { def kind = "minted" }
      end

      module Plain
        class Shape
          def one = 1
        end
        class Shape
          def two = 2
        end
      end

      row("mint_shape_kind") { Mint::Shape.new.kind }
      row("plain_shape_one") { Plain::Shape.new.one }
      row("plain_shape_two") { Plain::Shape.new.two }
      row("plain_shape_ancestors") { Plain::Shape.ancestors.first.to_s }

      # --- 8. a real reopen of a runtime-minted class still reopens ---------------

      module Reopen
        Thing = Class.new { def one = 1 }
        class Thing
          def two = 2
        end
      end

      row("reopen_thing_one") { Reopen::Thing.new.one }
      row("reopen_thing_two") { Reopen::Thing.new.two }
      row("reopen_thing_count") { Reopen.constants.count { |c| c == :Thing } }

      # --- 9. `defined?` and const_get must agree with the read -------------------

      module Agree
        class Leaf; end
        class Branch < Leaf; end
      end

      row("agree_defined_leaf") { defined?(Agree::Leaf) }
      row("agree_defined_branch") { defined?(Agree::Branch) }
      row("agree_get_equals_read") { Agree.const_get(:Branch).equal?(Agree::Branch) }
      row("agree_branch_instance") { Agree::Branch.new.is_a?(Agree::Leaf) }

      # --- 10. a same-leaf module and class ---------------------------------------

      module KindA
        Mixed = Module.new
      end
      module KindB
        class Mixed; end
        class UsesMixed < Mixed; end
      end

      row("kinda_mixed_class") { KindA::Mixed.class.to_s }
      row("kindb_mixed_class") { KindB::Mixed.class.to_s }
      row("kindb_uses_superclass") { KindB::UsesMixed.superclass.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      settings_path_kind	"struct"
      files_path_kind	"class"
      files_sub_superclass	"Files::Path"
      files_sub_kind	"class"
      files_sub_name	"Files::Sub"
      files_path_identity	true
      files_sub_identity	true
      files_constants	"[:Path, :Sub]"
      early_tagged_superclass	"Early::Token"
      early_tagged_kind	"class"
      late_token_kind	"runtime"
      real_derived_superclass	true
      real_derived_kind	"runtime-base"
      real_derived_extra	7
      real_derived_name	"Real::Derived"
      outer_uses_superclass	true
      outer_uses_kind	"inner-impl"
      toplevel_marker	7
      holder_marker_kind	"nested"
      holder_uses_superclass	"Holder::Marker"
      a1_value_where	"A1"
      b1_uses_where	"B1"
      b1_uses_superclass	"B1::Value"
      c1_value	3
      mint_shape_kind	"minted"
      plain_shape_one	1
      plain_shape_two	2
      plain_shape_ancestors	"Plain::Shape"
      reopen_thing_one	1
      reopen_thing_two	2
      reopen_thing_count	1
      agree_defined_leaf	"constant"
      agree_defined_branch	"constant"
      agree_get_equals_read	true
      agree_branch_instance	true
      kinda_mixed_class	"Module"
      kindb_mixed_class	"Class"
      kindb_uses_superclass	"KindB::Mixed"
    OUT
  end

  it "undefined constant warns" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # The uninitialized-constant message is namespaced ("Object::AlsoMissing");
      # ruby names the constant alone.
      #
      # A constant the whole program never defines is warned about at build time and
      # still raises NameError when reached, which is what CRuby does and what
      # ruby/spec asserts (#3976). The warning is what a dropped `require` needs: the
      # build used to say nothing at all.
      p defined?(Nope)
      p defined?(Nope::Deep)

      begin
        p Missing
      rescue NameError => e
        p e.message
      end

      begin
        p Object::AlsoMissing
      rescue NameError => e
        p e.message
      end

      X = 5
      p X
      p Integer
      class Y; end
      p Y
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      "uninitialized constant Missing"
      "uninitialized constant AlsoMissing"
      5
      Integer
      Y
    OUT
  end

  it "unresolved constant frames" do
    result = ze0(<<~'RUBY', path: "lang/constants/unresolved_constant_frames.rb")
      # A constant that resolves nowhere raises NameError where it is READ, and both
      # the message and the backtrace frame depend on where that is.
      module Outer
        module Wrap
          def self.bare = Missing
          def self.scoped = Deep::Missing
        end
      end

      def failure
        yield
      rescue NameError => e
        puts "#{e.message} | name=#{e.name.inspect} | #{e.backtrace.first[/:\d+:in .*/]}"
      end

      # A bare miss inside a module is reported under that module's path; so is the
      # missing HEAD of a scoped path (`Deep`, not `Deep::Missing` -- Ruby never got
      # far enough to look for the leaf).
      failure { Outer::Wrap.bare }
      failure { Outer::Wrap.scoped }
      failure { Nowhere }
      failure { Nowhere::Leaf }

      # A class-body frame is labelled with the class's LEAF name, however the class
      # was spelled at its definition site.
      module Pkg; end
      module Pkg::Inner
        PROBE = -> { Gone }
      end
      failure { Pkg::Inner::PROBE.call }

      # `include` of an undefined module is a call like any other -- it raises only
      # when the body actually runs, and nothing above it is disturbed.
      puts "reached the include"
      include NeverDefined
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/constants/unresolved_constant_frames.rb:35:in '<main>': uninitialized constant NeverDefined (NameError)\n\ninclude NeverDefined\n        ^^^^^^^^^^^^\n", status: 1
      uninitialized constant Outer::Wrap::Missing | name=:Missing | :5:in 'Outer::Wrap.bare'
      uninitialized constant Outer::Wrap::Deep | name=:Deep | :6:in 'Outer::Wrap.scoped'
      uninitialized constant Nowhere | name=:Nowhere | :21:in 'block in <main>'
      uninitialized constant Nowhere | name=:Nowhere | :22:in 'block in <main>'
      uninitialized constant Pkg::Inner::Gone | name=:Gone | :28:in 'block in <module:Inner>'
      reached the include
    OUT
  end

  it "writes" do
    result = ze0(<<~'RUBY', path: "ze0/constant_writes.rb")
      # frozen_string_literal: true

      # The operator writes a constant takes. `||=` is the one read that
      # tolerates an unassigned name; the other two ask for it outright.

      FIRST = 1
      FIRST_TWICE = FIRST + 1
      p FIRST_TWICE

      MAYBE ||= 5
      p MAYBE

      EMPTY = nil
      EMPTY ||= 7
      p EMPTY

      BOTH = 3
      BOTH &&= BOTH * 2
      p BOTH

      module Holder
        COUNT = 1
      end

      Holder::COUNT += 1
      p Holder::COUNT

      Holder::EXTRA ||= 9
      p Holder::EXTRA

      Holder::COUNT &&= 100
      p Holder::COUNT

      # A pattern in parentheses is the pattern inside, and an `[a,]` trailing
      # comma opens the length without binding anything.
      def kind(v)
        case v
        in (Integer | Float) then :number
        in [only,] then [:first, only]
        else :other
        end
      end

      p kind(1), kind(2.5), kind([1, 2, 3]), kind("x")
      [1, 2, 3] => [head,]
      p head
    RUBY

    _(result).must_answer <<~'OUT', stderr: "ze0/constant_writes.rb:14: warning: already initialized constant EMPTY\nze0/constant_writes.rb:13: warning: previous definition of EMPTY was here\nze0/constant_writes.rb:18: warning: already initialized constant BOTH\nze0/constant_writes.rb:17: warning: previous definition of BOTH was here\nze0/constant_writes.rb:25: warning: already initialized constant Holder::COUNT\nze0/constant_writes.rb:22: warning: previous definition of COUNT was here\nze0/constant_writes.rb:31: warning: already initialized constant Holder::COUNT\nze0/constant_writes.rb:25: warning: previous definition of COUNT was here\n"
      2
      5
      7
      6
      2
      9
      100
      :number
      :number
      [:first, 1]
      :other
      1
    OUT
  end
end
