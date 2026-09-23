# frozen_string_literal: true

require "spec_helper"

describe "Guards programs" do
  it "alias of an inherited builtin resolves statically dynamically and in subclasses" do
    result = ze0(<<~'RUBY')
      # The general (non-raise) family: `dup!` for Object's `dup` becomes a
      # registry NAME-INDIRECTION row (`register_alias`), consulted on the send
      # MISS paths -- so a static call, a dynamic `send`, a subclass receiver,
      # and an alias OF an alias all resolve. `respond_to?` answers through the
      # source name, inheriting its visibility (`dup!` public, `raise!` private
      # like `raise` itself). All outputs oracle-verified.

      class Dupper
        alias_method :dup!, :dup
        alias_method :dup2!, :dup!
        alias_method :raise!, :raise
      end
      class SubDupper < Dupper; end
      puts Dupper.new.dup!.class
      puts SubDupper.new.dup2!.class
      puts SubDupper.new.send(:dup!).class
      puts Dupper.new.respond_to?(:dup!)
      puts Dupper.new.respond_to?(:raise!)
    RUBY

    _(result).must_answer <<~'OUT'
      Dupper
      SubDupper
      SubDupper
      true
      false
    OUT
  end

  it "alias under a static modifier and if elsif" do
    result = ze0(<<~'RUBY')
      # A statically-literal `if`/`unless` guard on an `alias` is folded at
      # definition time: the selected branch's alias is registered.

      class C
        def one = 1
        def two = 2
        alias uno one if true
        alias dos two unless false
        alias never one if false
        if false
          alias chosen one
        elsif true
          alias chosen two
        end
      end
      puts C.new.uno
      puts C.new.dos
      puts C.new.chosen
      puts C.new.respond_to?(:never)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      2
      false
    OUT
  end

  it "array bounds guards" do
    result = ze0(<<~'RUBY')
      # Array negative-argument guards and nil returns: slice with a negative
      # length, sample(-n), Array.new(-n), fetch with a block / CRuby's IndexError
      # message, and first/last on an empty literal.
      def sl(a, i, n); a[i, n]; end
      def sm(a, n); a.sample(n); end
      def mk(n); Array.new(n); end
      def mkf(n); Array.new(n, 7); end
      def fch(a, i); a.fetch(i); end
      def fst(a); a.first; end
      def lst(a); a.last; end

      p sl([1, 2, 3, 4], 0, -1)      # nil
      p sl([1, 2, 3, 4], 1, 2)       # [2, 3]
      p sl([1, 2, 3, 4], -2, 5)      # [3, 4]
      p sl(["a", "b"], 0, -9)        # nil
      begin
        sm([1, 2], -1)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      p sm([5], 1)                   # [5]
      begin
        mk(-1)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        mkf(-3)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      p mk(2)                        # [nil, nil]
      p [1, 2, 3].fetch(9) { |i| i * 10 }    # 90
      p [1, 2, 3].fetch(1) { |i| i * 10 }    # 2
      p [1, 2, 3].fetch(-1) { |i| i }        # 3
      p [1, 2, 3].fetch(-9) { |i| i }        # -9
      begin
        fch([1, 2], 5)
      rescue IndexError => e
        puts e.message               # index 5 outside of array bounds: -2...2
      end
      begin
        fch([1, 2], -3)
      rescue IndexError => e
        puts e.message               # index -3 outside of array bounds: -2...2
      end
      p fst([])                      # nil
      p lst([])                      # nil
      p fst([4, 5])                  # 4
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      [2, 3]
      [3, 4]
      nil
      ArgumentError: negative sample number
      [5]
      ArgumentError: negative array size
      ArgumentError: negative array size
      [nil, nil]
      90
      2
      3
      -9
      index 5 outside of array bounds: -2...2
      index -3 outside of array bounds: -2...2
      nil
      nil
      4
    OUT
  end

  it "array clear frozen guard" do
    result = ze0(<<~'RUBY')
      # Array#clear on a frozen array raises FrozenError with the CRuby message
      # (including the inspected contents); a non-frozen array clears normally.
      def cl(a); a.clear; a; end
      begin
        cl([1, 2].freeze)
      rescue FrozenError => e
        puts e.class
        puts e.message
      end
      arr = [10, 20, 30]
      cl(arr)
      p arr
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
      can't modify frozen Array: [1, 2]
      []
    OUT
  end

  it "array fold delete flatten rindex" do
    result = ze0(<<~'RUBY')
      # Empty seedless folds are nil; delete's not-found block yields its value;
      # flatten! mutates in place; rindex takes a block.
      p [].reduce(:+).inspect
      p [].inject(:+).inspect
      p (1...1).reduce(:+).inspect
      p [1, 2].reduce(:+)
      p [].reduce(10, :+)
      p ["a", "b"].delete("z") { "missing" }
      p ["a", "b"].delete("a") { "missing" }
      p [1, 2].delete(9) { :nope }
      a = [[1], [2, [3]]]
      a.flatten!
      p a
      p [1, 2, 3, 2].rindex { |x| x < 3 }
      p [1, 2, 3, 2].rindex(2)
    RUBY

    _(result).must_answer <<~'OUT'
      "nil"
      "nil"
      "nil"
      3
      10
      "missing"
      "a"
      :nope
      [1, 2, 3]
      3
      3
    OUT
  end

  it "autoload target is also a guarded require" do
    result = ze0(<<~'RUBY', files: beside("autoload_target/lib.rb", "autoload_target/target.rb"))
      # One file, demanded twice under two different names. rack writes both:
      #
      #   lib/rack.rb          autoload :MediaType, "rack/media_type"
      #   test/spec_media.rb   separate_testing { require_relative "../lib/rack/media_type" }
      #
      # The second never runs (that method does not yield), so the autoload is the
      # only thing that can load the file -- and it has to still work.
      #
      # A unit registered under whichever name the loader saw first dropped the
      # other, and when the one dropped was the autoload's, the read that should
      # have run the unit found no unit under that name -- silently, because a
      # unit's classes are in the dispatch tables from startup. `Outer::Target`
      # resolved, `Outer::Target.read` was callable, and only its body's constant
      # was missing:
      #
      #   NameError: uninitialized constant #<Class:Outer::Target>::SPLIT
      #
      # This file pins the ORDER OF EVENTS against ruby. The regression test for
      # the drop itself is `an_autoload_and_a_guarded_require_of_one_file_share_
      # its_unit` in `tests/e2e/gems_require.rs`: reproducing it needs the autoload
      # to name a LOAD-PATH feature, so a name that resolves to nothing has no file
      # to fall back to, and a golden has no `-I` of its own.

      def self.never_yields
        :no_yield
      end

      # The file holding the `autoload` is itself behind a guard, which is what puts
      # its demand in a later round. HOME is set in any test environment.
      require_relative "autoload_target/lib" if ENV["HOME"]

      # The rack shape: a guarded require of the same file that never runs.
      never_yields do
        require_relative "autoload_target/target"
      end

      # Nothing has read the constant, so nothing has loaded the target.
      p Outer.autoload?(:Target) != nil
      p Object.const_defined?(:MISSING_MARKER)

      # The read is what runs it -- and its body's constants are there.
      p Outer::Target.read
      p Outer.autoload?(:Target) != nil
    RUBY

    _(result).must_answer <<~'OUT'
      lib.rb ran
      true
      false
      target.rb ran
      :split
      false
    OUT
  end

  it "both branches define the same conditional class" do
    result = ze0(<<~'RUBY')
      class Base
        def greet = "base"
      end
      def jruby? = false
      if jruby?
        class Impl < Base
          def greet = "java-#{@n}"
        end
      else
        class Impl < Base
          def initialize
            @n = 7
          end
          def greet = "native-#{@n}"
          def self.flavor = "self-native"
        end
      end
      i = Impl.new
      puts i.greet
      puts Impl.flavor
      puts Impl.name
      puts Impl.superclass
      puts Impl.instance_methods(false).sort.inspect
      puts i.is_a?(Base)
    RUBY

    _(result).must_answer <<~'OUT'
      native-7
      self-native
      Impl
      Base
      [:greet]
      true
    OUT
  end

  it "a version comparison at build time picks the branch its number falls in" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      p Adapter.superclass
      p Adapter.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      Array
      :current
    OUT
  end

  it "String#to_i reads the leading integer of a version and stops" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      # `String#to_i` reads the leading integer and stops -- chef spells its major
      # version this way.
      if Framework::VERSION::STRING.to_i >= 12
        class Chef12
          def which = :new
        end
      else
        class Chef12
          def which = :old
        end
      end
      p Chef12.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      :old
    OUT
  end

  it "an unescaped dot in a version pattern is exactly one character" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      # An unescaped `.` in a pattern is exactly one character, which is what gmp's
      # `unless RUBY_VERSION =~ /^1.8/` says. It reads the same as `/^1\.8/` on
      # every real version string, and is matched rather than assumed.
      unless RUBY_VERSION =~ /^1.8/
        class Modern
          def which = :modern
        end
      end
      p Modern.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      :modern
    OUT
  end

  it "an /i pattern over the engine name reads the same at build time" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      # `/i` -- the spelling a jruby gate uses.
      if RUBY_PLATFORM =~ /java/i
        class Vm < String
          def which = :jvm
        end
      else
        class Vm < Array
          def which = :native
        end
      end
      p Vm.superclass
      p Vm.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      Array
      :native
    OUT
  end

  it "String#[] as a condition asks whether the pattern matched" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      # `String#[]` hands back the match or nil, so as a CONDITION it asks whether
      # the platform string contains that text.
      if RUBY_PLATFORM['nosuchplatform']
        class Odd
          def which = :odd
        end
      end
      p defined?(Odd)

    RUBY

    _(result).must_answer <<~'OUT'
      nil
    OUT
  end

  it "a literal list asked for membership is the comparison spelled sideways" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      # A literal list asked for membership is the comparison spelled sideways.
      if ['opal', 'rubymotion'].include?(RUBY_ENGINE)
        class Web < String
          def which = :web
        end
      else
        class Web < Array
          def which = :mri
        end
      end
      p Web.superclass
      p Web.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      Array
      :mri
    OUT
  end

  it "instance_methods.include? is method_defined? the long way" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      # `X.instance_methods.include?(:m)` is `X.method_defined?(:m)` the long way --
      # a polyfill gate, and it decides against the compiled method tables.
      unless Regexp.instance_methods.include?(:match?)
        class MatchPolyfill
          def which = :polyfilled
        end
      end
      p defined?(MatchPolyfill)

    RUBY

    _(result).must_answer <<~'OUT'
      nil
    OUT
  end

  it "a guard on a constant the program does fill installs the filled body" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      class Bare
        def only_this = 1
      end
      unless Bare.instance_methods.include?(:absent)
        class Filled
          def which = :filled
        end
      end
      p Filled.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      :filled
    OUT
  end

  it "RUBY_PLATFORM.to_s is RUBY_PLATFORM, because String#to_s answers self" do
    result = ze0(<<~'RUBY')
      # A version gate is written against the NUMBER as often as against the string
      # (`Rails::VERSION::MAJOR`), and a platform gate against a pattern or a list.
      # All three are as fixed for a whole-program target as the version strings the
      # comparison folders already decide, and each one wraps a whole class in the
      # corpus -- so a compiler that cannot decide it registers both arms and reports
      # a superclass mismatch for a program ruby runs without complaint.

      module Framework
        module VERSION
          MAJOR = 8
          MINOR = 1
          STRING = "8.1.0"
        end
      end

      if Framework::VERSION::MAJOR == 8 && Framework::VERSION::MINOR >= 1
        class Adapter < Array
          def which = :current
        end
      else
        class Adapter < String
          def which = :legacy
        end
      end

      # `RUBY_PLATFORM.to_s` is `RUBY_PLATFORM` -- `String#to_s` returns self.
      if RUBY_PLATFORM.to_s == 'java'
        class Engine
          def which = :jruby
        end
      else
        class Engine
          def which = :mri
        end
      end
      p Engine.new.which
    RUBY

    _(result).must_answer <<~'OUT'
      :mri
    OUT
  end

  it "case in guard binding" do
    result = ze0(<<~'RUBY')
      # A destructured array-pattern guard sees the bindings the pattern introduces.
      def s(x); x; end
      r = case s([1, 2])
          in [a, b] if a + b == 3 then "sum3"
          else "no"
          end
      p r
      r2 = case s([2, 2])
           in [a, b] if a + b == 3 then "sum3"
           else "no"
           end
      p r2
    RUBY

    _(result).must_answer <<~'OUT'
      "sum3"
      "no"
    OUT
  end

  it "case in guard bindings" do
    result = ze0(<<~'RUBY')
      # A pattern guard (`in PATTERN if GUARD` / `unless GUARD`) can reference the
      # bindings introduced by the pattern. Receivers go through per-type identity
      # methods to defeat constant folding while keeping each scrutinee monomorphic.
      # Binding names are unique per arm so cross-arm type unification can't muddy them.
      def ai(x); x; end
      def aii(x); x; end
      def hh(x); x; end
      def ii(x); x; end

      # array pattern + if guard referencing the bindings
      case ai([1, 2])
      in [p1, q1] if p1 + q1 == 3 then p "sum3"
      else p "no"
      end                                       # "sum3"

      case ai([1, 2])
      in [p2, q2] if p2 + q2 == 99 then p "yes"
      else p "fell-through"
      end                                       # "fell-through"

      # three-element array, guard chooses among arms
      case aii([1, 2, 3])
      in [p3, q3, r3] if p3 + q3 + r3 == 6 then p "six"
      in [p3b, q3b, r3b] then p "other"
      end                                       # "six"

      # hash pattern + guard over its typed-capture bindings
      case hh({ name: "x", age: 5 })
      in { name: String => nm, age: Integer => ag } if ag > 3 then p [nm, ag]
      else p "no"
      end                                       # ["x", 5]

      # unless guard negates
      case ai([1, 2])
      in [p4, q4] unless p4 == q4 then p "diff"
      else p "same"
      end                                       # "diff"

      # a plain local-binding pattern with a guard still works
      case ii(7)
      in n5 if n5 > 5 then p "big"
      else p "small"
      end                                       # "big"

      # a guard of a concrete (non-bool) type follows Ruby truthiness: 0 is truthy,
      # so an Integer-valued guard that evaluates to 0 still passes (C would treat 0
      # as falsy without the truthiness wrapper).
      case ii(5)
      in n6 if n6 - 5 then p "truthy-zero"
      else p "wrongly-falsy"
      end                                       # "truthy-zero"
    RUBY

    _(result).must_answer <<~'OUT'
      "sum3"
      "fell-through"
      "six"
      ["x", 5]
      "diff"
      "big"
      "truthy-zero"
    OUT
  end

  it "case in object deconstruct keys with constant guard" do
    result = ze0(<<~'RUBY')
      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end
        def deconstruct_keys(keys)
          { x: @x, y: @y }
        end
      end
      p1 = Point.new(1, 2)
      case p1
      in Point(x:, y:)
        puts "constant: #{x}, #{y}"
      end
      case p1
      in { x:, y: }
        puts "plain: #{x}, #{y}"
      end
    RUBY

    _(result).must_answer "constant: 1, 2\nplain: 1, 2\n"
  end

  it "case in unless guard" do
    result = ze0(<<~'RUBY')
      case [1, 2]
      in [a, *b] unless a == 0
        puts a
      end
    RUBY

    _(result).must_answer "1\n"
  end

  it "casecmp folds non ascii" do
    result = ze0(<<~'RUBY')
      # `String#casecmp` and `Symbol#casecmp` compare ASCII case-insensitively
      # and everything else BY BYTES.
      #
      # That is CRuby's documented split and the reason `casecmp?` exists beside
      # it: `casecmp` is `rb_str_casecmp`, which walks bytes and folds only
      # `A-Z`, while `casecmp?` is `rb_str_casecmp?`, which case-folds both
      # sides first. zeo implemented both as the Unicode comparison, so
      # `casecmp` answered `casecmp?`'s question -- `"Ä".casecmp("ä")` was 0
      # where ruby says -1, and nothing raised.

      p "A".casecmp("a")
      p "Ä".casecmp("ä")
      p "Д".casecmp("д")
      p :Ä.casecmp(:ä)
      p "Ä".casecmp?("ä")
      p "A".casecmp?("a")
      p "a".casecmp(1)
      p "ä".casecmp("Ä")
      p "aÄ".casecmp("aä")
    RUBY

    _(result).must_answer <<~'OUT'
      0
      -1
      -1
      -1
      true
      true
      nil
      1
      -1
    OUT
  end

  it "class body guard folds in cref" do
    result = ze0(<<~'RUBY')
      # A class-body guard folds with the same superset the top level uses, in the
      # body's own cref. Before the lift this whole shape was a compile error ("a
      # position the analyze walk doesn't register"). The probe names a class
      # registered BEFORE this body began -- a probe of a sibling statement the
      # walk has not reached stays undecidable rather than misfolding.
      class Helper; end

      module Outer
        if defined?(Helper)
          module Inner
            WHO = "folded"
          end
        end
      end
      puts Outer::Inner::WHO
    RUBY

    _(result).must_answer "folded\n"
  end

  it "class in a block under an undecided guard" do
    result = ze0(<<~'RUBY')
      # A `class`/`module` written inside a BLOCK registers at the top level -- the
      # walk descends into the block body, the definition keeps its document
      # position, and the class exists once the block has run.
      #
      # Under an UNDECIDED top-level guard the branch's own definitions register as
      # runtime-conditional, but an interleaved statement was kept whole and never
      # descended into, so a class inside a block inside the branch reached codegen
      # unregistered. core_ex is the shape: a `silence_warnings do module Inflector`
      # inside `unless defined? CORE_EX_LOADED`, whose condition the branch itself
      # assigns.
      def wrap
        yield
      end

      unless defined?(GUARD_LOADED) && GUARD_LOADED
        GUARD_LOADED = true

        # Registered by the guarded-branch walk, as it already was.
        class Plain
          def hi = "plain"
        end

        wrap do
          module Inflector
            class Inflections
              def hi = "inflections"
            end

            def self.hi = "inflector"
          end
        end

        wrap do
          class Plain::Nested
            def hi = "nested"
          end
        end
      end

      p Plain.new.hi
      p Inflector.hi
      p Inflector::Inflections.new.hi
      p Plain::Nested.new.hi
      p [Inflector.class, Inflector::Inflections.superclass, Plain::Nested.name]

      # The guard really is undecided: a second pass over the same shape is a no-op,
      # so nothing was defined twice.
      unless defined?(GUARD_LOADED) && GUARD_LOADED
        wrap do
          module Inflector
            def self.hi = "redefined"
          end
        end
      end
      p Inflector.hi
    RUBY

    _(result).must_answer <<~'OUT'
      "plain"
      "inflector"
      "inflections"
      "nested"
      [Module, Object, "Plain::Nested"]
      "inflector"
    OUT
  end

  it "class self conditional def" do
    result = ze0(<<~'RUBY')
      # A conditional `def` inside `class << self` -- erb/compiler.rb's
      # `class << self; if defined?(Ractor); def register_scanner ...; else; ...`.
      # zeo statically decides the version/`defined?` guard and registers ONLY the
      # taken branch's class methods, matching ruby (which runs one branch).
      class Scanner
        class << self
          if RUBY_VERSION >= "3.0"
            def which
              "new"
            end
          else
            def which
              "old"
            end
          end
        end
      end
      puts Scanner.which
    RUBY

    _(result).must_answer "new\n"
  end

  it "conditional class body defs" do
    result = ze0(<<~'RUBY')
      # A class-body `if`/`unless` whose guard is compile-time decidable (a
      # target-version or feature-probe gate) and whose taken branch holds a whole
      # definition (`class`/`module`/`include`/`prepend`) is inlined into that branch,
      # exactly as CRuby's load-time reachability decides it. The taken branch's
      # nested definition registers like an ordinary class-body one; a dropped branch
      # leaves nothing behind. (This is the class-body analogue of the top-level
      # conditional-definition handling.)
      class Host
        # "4.0.6" >= "3.0" is true -> Modern registers.
        if RUBY_VERSION >= "3.0"
          class Modern
            def tag
              "modern"
            end
          end
        end

        # "4.0.6" < "3.0" is false -> the legacy nested class is dropped entirely.
        if RUBY_VERSION < "3.0"
          class Legacy
            def tag
              "legacy"
            end
          end
        end

        # An `unless` over a true guard drops its branch too.
        unless RUBY_VERSION >= "3.0"
          module NeverMixed
            def extra; end
          end
          include NeverMixed
        end
      end

      puts Host::Modern.new.tag
      puts defined?(Host::Legacy).inspect
      puts Host.ancestors.include?(Host::NeverMixed) rescue puts "NeverMixed undefined"
    RUBY

    _(result).must_answer <<~'OUT'
      modern
      nil
      NeverMixed undefined
    OUT
  end

  it "conditional class method def leaves the inherited one reachable" do
    result = ze0(<<~'RUBY')
      class Base
        def self.create
          :inherited
        end
      end

      class Sub < Base
        p methods.include?(:create)
        p Sub.respond_to?(:create)
        p respond_to?(:create)
        p Sub.create
        def self.create
          :own
        end unless respond_to? :create
      end
      p Sub.create

      class Wide < Base
        def self.create
          :fires
        end unless $PROGRAM_NAME.empty?
      end
      p Wide.create
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      :inherited
      :inherited
      :fires
    OUT
  end

  it "a def under a false guard is absent to a call and to reflection alike" do
    result = ze0(<<~'RUBY')
      # A `def` inside a class-body `if` whose guard zeo cannot decide runs only if
      # the guard says so -- which means it must claim no compile-time method-table
      # row, because that row would answer whether or not the branch ran. What the
      # guard installs goes into the runtime overlay instead, and the overlay is what
      # answers: it already outranks a class's own table and an inherited one both.
      #
      # The name still has to REGISTER, so the compile-time machinery that resolves
      # `extend` and the method tables can see it. Registering it is not the same as
      # promising it.

      OFF = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "on"
      ON = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "off"

      # The guard is false, so the method is not there -- not to a call, not to
      # `respond_to?`, and not to `instance_methods`.
      class Absent
        if OFF
          def only_when_on = :on
        end
      end
      p Absent.new.respond_to?(:only_when_on)
      p Absent.instance_methods(false)
      begin
        Absent.new.only_when_on
      rescue NoMethodError
        p :no_method
      end

    RUBY

    _(result).must_answer <<~'OUT'
      false
      []
      :no_method
    OUT
  end

  it "a def under a true guard is present by every one of those readings" do
    result = ze0(<<~'RUBY')
      # A `def` inside a class-body `if` whose guard zeo cannot decide runs only if
      # the guard says so -- which means it must claim no compile-time method-table
      # row, because that row would answer whether or not the branch ran. What the
      # guard installs goes into the runtime overlay instead, and the overlay is what
      # answers: it already outranks a class's own table and an inherited one both.
      #
      # The name still has to REGISTER, so the compile-time machinery that resolves
      # `extend` and the method tables can see it. Registering it is not the same as
      # promising it.

      OFF = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "on"
      ON = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "off"

      # The guard is true, so it is there, by every one of those readings.
      class Present
        if ON
          def only_when_on = :on
        end
      end
      p Present.new.only_when_on
      p Present.new.respond_to?(:only_when_on)
      p Present.instance_methods(false)

    RUBY

    _(result).must_answer <<~'OUT'
      :on
      true
      [:only_when_on]
    OUT
  end

  it "a conditional def does not displace one that always runs when its guard is false" do
    result = ze0(<<~'RUBY')
      # A `def` inside a class-body `if` whose guard zeo cannot decide runs only if
      # the guard says so -- which means it must claim no compile-time method-table
      # row, because that row would answer whether or not the branch ran. What the
      # guard installs goes into the runtime overlay instead, and the overlay is what
      # answers: it already outranks a class's own table and an inherited one both.
      #
      # The name still has to REGISTER, so the compile-time machinery that resolves
      # `extend` and the method tables can see it. Registering it is not the same as
      # promising it.

      OFF = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "on"
      ON = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "off"

      # A conditional `def` does not displace one that always runs: last-def-wins is
      # a rule about `def`s that RAN.
      class Both
        def which = :always
        if OFF
          def which = :guarded
        end
      end
      p Both.new.which
      p Both.instance_methods(false)

    RUBY

    _(result).must_answer <<~'OUT'
      :always
      [:which]
    OUT
  end

  it "the conditional def wins when its guard is true, as last-def-wins says" do
    result = ze0(<<~'RUBY')
      # A `def` inside a class-body `if` whose guard zeo cannot decide runs only if
      # the guard says so -- which means it must claim no compile-time method-table
      # row, because that row would answer whether or not the branch ran. What the
      # guard installs goes into the runtime overlay instead, and the overlay is what
      # answers: it already outranks a class's own table and an inherited one both.
      #
      # The name still has to REGISTER, so the compile-time machinery that resolves
      # `extend` and the method tables can see it. Registering it is not the same as
      # promising it.

      OFF = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "on"
      ON = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "off"

      # ...and when the guard IS true, the overlay it writes wins, which is the same
      # answer from the other direction.
      class BothOn
        def which = :always
        if ON
          def which = :guarded
        end
      end
      p BothOn.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      :guarded
    OUT
  end

  it "a false-guarded def does not shadow an ancestor's, so the inherited body answers" do
    result = ze0(<<~'RUBY')
      # A `def` inside a class-body `if` whose guard zeo cannot decide runs only if
      # the guard says so -- which means it must claim no compile-time method-table
      # row, because that row would answer whether or not the branch ran. What the
      # guard installs goes into the runtime overlay instead, and the overlay is what
      # answers: it already outranks a class's own table and an inherited one both.
      #
      # The name still has to REGISTER, so the compile-time machinery that resolves
      # `extend` and the method tables can see it. Registering it is not the same as
      # promising it.

      OFF = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "on"
      ON = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "off"

      # Nor does it shadow an ancestor's: with the guard false the inherited body
      # answers, which takes the name not claiming a row on the subclass at all.
      class Base
        def which = :base
      end

      class QuietSub < Base
        if OFF
          def which = :sub
        end
      end
      p QuietSub.new.which
      p QuietSub.instance_methods(false)

      class LoudSub < Base
        if ON
          def which = :sub
        end
      end
      p LoudSub.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      :base
      []
      :sub
    OUT
  end

  it "where both branches define the name, the taken branch is what answers" do
    result = ze0(<<~'RUBY')
      # A `def` inside a class-body `if` whose guard zeo cannot decide runs only if
      # the guard says so -- which means it must claim no compile-time method-table
      # row, because that row would answer whether or not the branch ran. What the
      # guard installs goes into the runtime overlay instead, and the overlay is what
      # answers: it already outranks a class's own table and an inherited one both.
      #
      # The name still has to REGISTER, so the compile-time machinery that resolves
      # `extend` and the method tables can see it. Registering it is not the same as
      # promising it.

      OFF = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "on"
      ON = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "off"

      # Both branches defining the same name is the compat-shim shape, and the taken
      # branch is the one that answers.
      class Either
        if OFF
          def which = :then_branch
        else
          def which = :else_branch
        end
      end
      p Either.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      :else_branch
    OUT
  end

  it "a top-level class X ... end if cond reopens through the same path" do
    result = ze0(<<~'RUBY')
      # A `def` inside a class-body `if` whose guard zeo cannot decide runs only if
      # the guard says so -- which means it must claim no compile-time method-table
      # row, because that row would answer whether or not the branch ran. What the
      # guard installs goes into the runtime overlay instead, and the overlay is what
      # answers: it already outranks a class's own table and an inherited one both.
      #
      # The name still has to REGISTER, so the compile-time machinery that resolves
      # `extend` and the method tables can see it. Registering it is not the same as
      # promising it.

      OFF = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "on"
      ON = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "off"

      # The top-level `class X ... end if cond` form reopens through the same
      # machinery (`analyze::try_conditional_reopen` pushes the guard into the class
      # body), so it decides the same way. pp.rb's `class Set ... end if set_pp` is
      # the shape.
      class Reopened
        def base = :base
      end

      class Reopened
        def added = :added
      end if OFF

      p Reopened.new.respond_to?(:added)
      p Reopened.instance_methods(false)

    RUBY

    _(result).must_answer <<~'OUT'
      false
      [:base]
    OUT
  end

  it "a definition carries more than one trailing modifier, and the pair is read together" do
    result = ze0(<<~'RUBY')
      # A `def` inside a class-body `if` whose guard zeo cannot decide runs only if
      # the guard says so -- which means it must claim no compile-time method-table
      # row, because that row would answer whether or not the branch ran. What the
      # guard installs goes into the runtime overlay instead, and the overlay is what
      # answers: it already outranks a class's own table and an inherited one both.
      #
      # The name still has to REGISTER, so the compile-time machinery that resolves
      # `extend` and the method tables can see it. Registering it is not the same as
      # promising it.

      OFF = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "on"
      ON = ENV.fetch("ZEO_CONDITIONAL_DEF_UNSET", "off") == "off"

      # Ruby lets a definition carry more than one trailing modifier, and the pair
      # pushes into the class body exactly as a single one does. sexp_processor
      # closes its whole `Sexp` reopen with two.
      class Twice
        def base = :base
      end

      class Twice
        def added = :added
      end unless Twice.new.respond_to? :added if ON

      p Twice.new.added
      p Twice.instance_methods(false).sort

      class TwiceOff
        def base = :base
      end

      class TwiceOff
        def added = :added
      end unless TwiceOff.new.respond_to? :added if OFF

      p TwiceOff.new.respond_to?(:added)
      p TwiceOff.instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      :added
      [:added, :base]
      false
      [:base]
    OUT
  end

  it "conditional reopen adds method" do
    result = ze0(<<~'RUBY')
      # A class REOPENING that only ADDS methods, guarded by a runtime-undecidable
      # condition (`... end if enabled`). zeo pushes the guard into the class body
      # (`class Widget; if enabled; def extra; ...`) so the method is defined
      # conditionally at runtime and still registered for reflection -- matching real
      # Ruby (this is the pp.rb `class Set ... end if set_pp` monkeypatch idiom).
      class Widget
        def base
          "base"
        end
      end

      enabled = [true].sample # deterministic (single element) but not statically foldable

      class Widget
        def extra
          "extra"
        end
      end if enabled

      w = Widget.new
      puts w.base
      puts w.extra
      puts Widget.instance_method(:extra).name
    RUBY

    _(result).must_answer <<~'OUT'
      base
      extra
      extra
    OUT
  end

  it "def two guards deep stays inside both of them" do
    result = ze0(<<~'RUBY')
      # Bundler's actual nesting: a guard inside a guard, with a local assigned
      # between them and the body reading a constant only the inner branch writes.

      def cpu = ["arm", "64"].join
      class C
        [:tag].each { |n| attr_accessor(n) }
        if cpu
          arch = cpu
          if arch == "universal"
            DEEP = "deep"
            def which = DEEP
          end
        end
        def which = "real"
      end
      puts C.new.which
    RUBY

    _(result).must_answer "real\n"
  end

  it "defined const document order" do
    result = ze0(<<~'RUBY')
      # `defined?(Const)` answers from DOCUMENT ORDER: ruby knows a constant only
      # once its `class` statement or its assignment has executed, where a
      # whole-program view finds the definition wherever in the file it is written.
      # `analyze::mro::index_document_order` numbers the statements in execution
      # order and records where each constant starts answering, so the fold commits
      # only when the definition provably precedes the query.
      #
      # The numbering deliberately stops at a `def`, a lambda and a block body --
      # those run when they are CALLED, which is no position at all -- and a query
      # or a definition it cannot place keeps the whole-program answer.
      p defined?(Later)
      class Later; end
      p defined?(Later)

      module Wrapper
        p defined?(Inner)
        class Inner; end
        p defined?(Inner)
      end

      # The same question through a conditional, which is the shape that matters --
      # a compat shim guarding on a constant its own file defines further down.
      if defined?(Sentinel)
        p :early
      else
        p :not_yet
      end
      Sentinel = 1
      p defined?(Sentinel)

      # The mirror image, and a second cause: a TOP-LEVEL value constant used to
      # answer nil even AFTER its assignment. `directly_defines_const` reads a
      # class's `class_body_stmts`, and a top-level `NAME = ...` sits in the main
      # statement stream instead, belonging to no class body -- so nothing claimed
      # it for `Object`, where ruby puts it. Only STATEMENT-level writes are
      # claimed, the same rule a class body follows: `NAME = 1 if cond` names an
      # owner it may never get.
      AT_TOP_LEVEL = 7
      p defined?(AT_TOP_LEVEL)

      # A constant is defined once its VALUE has been computed, so a self-reference
      # in the initializer still answers nil.
      SELF_REF = defined?(SELF_REF)
      p SELF_REF

      # A query inside a method body has no document position -- it runs whenever
      # the method is called -- so it keeps answering from the whole program.
      def probe = defined?(DEFINED_LATER)
      DEFINED_LATER = :here
      p probe
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "constant"
      nil
      "constant"
      :not_yet
      "constant"
      "constant"
      nil
      "constant"
    OUT
  end

  it "defined stands down when a program can load at run time" do
    result = ze0(<<~'RUBY', files: beside("defined_defers/latecomer.rb"))
      $LOAD_PATH.unshift(File.join(__dir__, "defined_defers"))
      require "latecomer"

      p RUNTIME_MARK
      p defined?(RUNTIME_MARK)

      class Reader
        def mark = defined?(RUNTIME_MARK)
      end
      p Reader.new.mark

      # A program with a run-time load can gain a constant this compile never
      # saw, so "provably absent" is a claim the compiler is not entitled to
      # make. These ask at run time instead of folding to nil.
      p defined?(NEVER_DEFINED_ANYWHERE)
      p defined?(String)
      p defined?(Reader)
      module Holder; end
      p defined?(Holder)
      p defined?(Holder::MISSING)
      Object.const_set(:SET_AT_RUN_TIME, 1)
      p defined?(SET_AT_RUN_TIME)
      eval("EVAL_MARK = 2")
      p defined?(EVAL_MARK)
      p [defined?(RUNTIME_MARK), defined?(NEVER_DEFINED_ANYWHERE)]
    RUBY

    _(result).must_answer <<~'OUT'
      "assigned by a run-time load"
      "constant"
      "constant"
      nil
      "constant"
      "constant"
      "constant"
      nil
      "constant"
      "constant"
      ["constant", nil]
    OUT
  end

  it "defined value const guards class def" do
    result = ze0(<<~'RUBY')
      # A top-level class/module definition guarded by `defined?(Mod::VALUE_CONST)`
      # where the constant is a plain VALUE (not a class) that the module's own body
      # assigns. zeo must statically decide the guard (this is the rubygems idiom
      # `unless defined?(Psych::VERSION); module Psych; ...`).
      module Lib
        VERSION = "1.2.3"
      end

      unless defined?(Lib::VERSION)
        module Lib
          class Missing < StandardError; end
        end
      end

      puts(defined?(Lib::VERSION) ? "have-version" : "fallback")
      puts Lib::VERSION
      puts(defined?(Lib::Missing) ? "has-missing" : "no-missing")
    RUBY

    _(result).must_answer <<~'OUT'
      have-version
      1.2.3
      no-missing
    OUT
  end

  it "explicit so require resolves a statically linked extension" do
    result = ze0(<<~'RUBY')
      # A `.so` require resolves through the static-ext table rather than the
      # filesystem -- zeo is a Ruby built with `--with-static-linked-ext`, and
      # CRuby registers static exts under `"<feature>.so"` (`load.c:1161`).
      #
      # A .so naming no static ext resolves to nothing, so (like any unresolvable
      # plain require) it lowers to a runtime `Kernel#require` raising LoadError --
      # it COMPILES rather than failing the build.

      require "strscan.so"
      p StringScanner.new("ab").scan(/a/)
    RUBY

    _(result).must_answer "\"a\"\n"
  end

  it "feature probe defs fold" do
    result = ze0(<<~'RUBY')
      # Feature-probe guards fold against the compiled method tables, exactly as CRuby
      # decides them at load time. rubygems/bundler gate compat reopens on whether a
      # class already has a method -- e.g. bundler's
      #   VALIDATES_FOR_RESOLUTION = Specification.new.respond_to?(:validate_for_resolution).freeze
      #   unless VALIDATES_FOR_RESOLUTION
      #     class SpecificationPolicy ... end
      #   end
      # On a target whose Specification HAS the method, the boolean constant is true,
      # so the compat reopen is dropped (which zeo cannot express at runtime under
      # static MRO). This fixture mirrors that shape in a collision-free namespace.
      module App
        class Spec
          def validate!
            "real"
          end
        end

        # respond_to? on an instance folds through the method table; `.freeze` is a
        # no-op on the boolean, so the constant is a compile-time `true`.
        HAS_VALIDATE = Spec.new.respond_to?(:validate!).freeze

        class Policy
          def kind
            "modern"
          end
        end

        # HAS_VALIDATE is true -> `unless true` -> the legacy reopen folds away, so
        # `kind` stays the modern body (the observable proof the guard folded).
        unless HAS_VALIDATE
          class Policy
            def kind
              "legacy"
            end
          end
        end
      end

      puts App::Policy.new.kind
      puts App::HAS_VALIDATE
    RUBY

    _(result).must_answer "modern\ntrue\n"
  end

  it "fiber error guards" do
    result = ze0(<<~'RUBY')
      # A Fiber misused in ways CRuby rejects must raise FiberError, not crash:
      # yielding from the root fiber, yielding inside a fiber entered via #transfer,
      # and resuming a fiber that is still running (double resume). Each is catchable.

      # Yielding outside any fiber (from the root fiber) raises rather than crashing.
      begin
        Fiber.yield(1)
        puts "no raise (root yield)"
      rescue FiberError => e
        puts "raised (root yield): #{e.class}: #{e.message}"
      end

      # A fiber entered with #transfer has no resumer to yield back to.
      begin
        ft = Fiber.new { |x| Fiber.yield x }
        ft.transfer(1)
        puts "no raise (transfer yield)"
      rescue FiberError => e
        puts "raised (transfer yield): #{e.class}: #{e.message}"
      end

      # Resuming a fiber that is still running (an ancestor on the resume stack) is a
      # double resume. Both fibers are defined at top level and reached via globals so
      # the bodies capture no locals.
      $f1 = nil
      $f2 = nil
      $f1 = Fiber.new { $f2.resume }
      $f2 = Fiber.new { $f1.resume }   # $f1 is still running when this runs
      begin
        $f1.resume
        puts "no raise (double resume)"
      rescue FiberError => e
        puts "raised (double resume): #{e.class}: #{e.message}"
      end

      # The guards do not disturb a well-behaved fiber: resume/yield round-trips,
      # the terminal value comes back, and #alive? flips to false at the end.
      g = Fiber.new { |a| b = Fiber.yield(a + 1); Fiber.yield(b * 2); 99 }
      p g.resume(10)
      p g.resume(5)
      p g.resume(0)
      p g.alive?

      # An infinite generator still works.
      fib = Fiber.new do
        a, b = 0, 1
        loop { Fiber.yield a; a, b = b, a + b }
      end
      p Array.new(8) { fib.resume }
    RUBY

    _(result).must_answer <<~'OUT'
      raised (root yield): FiberError: attempt to yield on a not resumed fiber
      raised (transfer yield): FiberError: attempt to yield on a not resumed fiber
      raised (double resume): FiberError: attempt to resume a resumed fiber (double resume)
      11
      10
      99
      false
      [0, 1, 1, 2, 3, 5, 8, 13]
    OUT
  end

  it "fiber transfer root and error guards" do
    result = ze0(<<~'RUBY')
      # Fiber#transfer round-tripping through the root fiber, Fiber#[]/#[]=
      # storage, the FiberError guards (yield in a transfer-entered fiber, double
      # resume), and Fiber#kill running ensure blocks.

      main = Fiber.current
      f = Fiber.new do
        v = main.transfer(42)
        main.transfer(v + 1)
      end
      p f.transfer
      p f.transfer(7)

      Fiber[:tag] = :outer
      g = Fiber.new { Fiber[:tag] }
      p g.resume

      begin
        ft = Fiber.new { |x| Fiber.yield x }
        ft.transfer(1)
      rescue FiberError => e
        puts "transfer-yield: #{e.message}"
      end

      h = Fiber.new do
        begin
          Fiber.yield 1
        ensure
          puts "ensure ran"
        end
      end
      h.resume
      p h.kill.is_a?(Fiber)
      p h.alive?
    RUBY

    _(result).must_answer <<~'OUT'
      42
      8
      :outer
      transfer-yield: attempt to yield on a not resumed fiber
      ensure ran
      true
      false
    OUT
  end

  it "fnmatch casefold flag" do
    result = ze0(<<~'RUBY')
      p File.fnmatch("a*", "A.rb", File::FNM_CASEFOLD)
      p File.fnmatch("A*", "a.rb", File::FNM_CASEFOLD)
      p File.fnmatch("a*", "A.rb")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
    OUT
  end

  it "fold memo to proc" do
    result = ze0(<<~'RUBY')
      f001 = ->(m, k) { m << k }
      p(["a"].each_with_object([]) { |k001, m001| f001.call(m001, k001) })
      f002 = ->(m, k) { m[k] = 1 }
      p(["a"].each_with_object({}) { |k002, m002| f002.call(m002, k002) })
      f003 = ->(m, k) { p m }
      ["a"].each_with_object({}) { |k003, m003| f003.call(m003, k003) }
      f005 = ->(m, k) { m << k }
      p([1].inject([]) { |m005, k005| f005.call(m005, k005) })
      p([1, 2].each_with_object([]) { |x, m| m << x * 2 })
      p([1, 2].inject(0) { |a, x| a + x })
    RUBY

    _(result).must_answer <<~'OUT'
      ["a"]
      {"a" => 1}
      {}
      [1]
      [2, 4]
      3
    OUT
  end

  it "fold nonempty array seed" do
    result = ze0(<<~'RUBY')
      g = [[1, 2], [3, 4]]
      v = g.reduce([0]) { |a, r| a + r }
      p v

      g = [[1, 2], [3, 4]]
      v = g.inject([0]) { |a, r| a + r }; p v   # Ruby: [0, 1, 2, 3, 4]   Spinel: C compile abort
      p g.inject([]) { |a, r| a + r }            # => [1, 2, 3, 4]

      g = [[1, 2], [3, 4]]
      p(g.reduce([9]) { |a, r| a + r })
      p(g.reduce(["s"]) { |a, r| a + r })
      p([1, 2].reduce([0]) { |a, x| a << x })
      p([[1], [2]].inject([5]) { |a, r| a | r })
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2, 3, 4]
      [0, 1, 2, 3, 4]
      [1, 2, 3, 4]
      [9, 1, 2, 3, 4]
      ["s", 1, 2, 3, 4]
      [0, 1, 2]
      [5, 1, 2]
    OUT
  end

  it "forwarded nil guarded block" do
    result = ze0(<<~'RUBY')
      # A captured &blk that is nil-guarded (forcing a real proc param) and then
      # forwarded into a callee must still reach that callee's yield / block.call.

      def inner_yield
        yield 5
      end
      def inner_call(&b)
        b.call(5)
      end
      def inner_multi
        yield 3, 4
      end

      def y_guard(&blk)
        return -1 if blk.nil?
        inner_yield(&blk)
      end
      def c_guard(&blk)
        return -1 if blk.nil?
        inner_call(&blk)
      end
      def multi_guard(&blk)
        return -1 if blk.nil?
        inner_multi(&blk)
      end

      puts y_guard { |x| x * 2 }
      puts y_guard
      puts c_guard { |x| x + 100 }
      puts c_guard
      puts multi_guard { |a, b| a + b }
      p(y_guard { |x| "got #{x}" })

      # a yielding method shared across an Integer and a String forwarder: its yield
      # type unifies to poly, but each forwarder's result slot stays concrete.
      def s_guard(&blk)
        return "none" if blk.nil?
        inner_yield(&blk)
      end
      puts s_guard { |x| "v=#{x}" }
      puts s_guard
    RUBY

    _(result).must_answer <<~'OUT'
      10
      -1
      105
      -1
      7
      "got 5"
      v=5
      none
    OUT
  end

  it "guarded class defines only when its branch runs" do
    result = ze0(<<~'RUBY')
      puts defined?(Widget).inspect
      def probe? = false
      if probe?
        class Widget
          def kind = "guarded"
        end
      end
      puts defined?(Widget).inspect
      begin
        Widget.new
      rescue NameError => e
        puts e.class
        puts e.message[0, 30]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      NameError
      uninitialized constant Widget
    OUT
  end

  it "guarded class method does not take the later bodys position" do
    result = ze0(<<~'RUBY')
      # The class-method channel takes the same rule. It is counted apart from the
      # instance channel, so a fix that only watched one would pass everything
      # above and still hand `def self.x` the wrong body.

      def cpu = ["arm", "64"].join
      class C
        [:tag].each { |n| attr_accessor(n) }
        if cpu == "universal"
          ONLY = "universal"
          def self.which = ONLY
        end
      end
      class C
        def self.which = "real"
      end
      puts C.which
    RUBY

    _(result).must_answer "real\n"
  end

  it "a guarded reopen walked first does not displace the real definition" do
    result = ze0(<<~'RUBY', files: beside("guarded_def/base.rb", "guarded_def/real.rb"))
      module Probe
        # A question no compile-time fold can answer, the way bundler asks
        # `Gem::Platform.local.cpu`. Every guard below reads it.
        def self.cpu
          ["arm", "64"].join
        end
      end

      # Two units, the GUARDED reopen walked first -- the ordering that let a
      # guarded body take the unguarded one's document position.
      require_relative "guarded_def/base"
      unit = Probe::Unit.new
      p unit.extensions_dir
      p Probe::Unit.channel
      p Probe::Unit.const_defined?(:ONLY_IF_UNIVERSAL)
      unit.tag = "tagged"
      p unit.tag

    RUBY

    _(result).must_answer <<~'OUT'
      "real"
      "real class method"
      false
      "tagged"
    OUT
  end

  it "the same pair in one file, guarded first, keeps the unguarded body" do
    result = ze0(<<~'RUBY', files: beside("guarded_def/base.rb", "guarded_def/real.rb"))
      module Probe
        # A question no compile-time fold can answer, the way bundler asks
        # `Gem::Platform.local.cpu`. Every guard below reads it.
        def self.cpu
          ["arm", "64"].join
        end
      end

      # The same pair in one file: guarded first, unguarded second.
      module Probe
        class GuardedFirst
          [:tag].each { |n| attr_accessor(n) }
          if Probe.cpu == "universal"
            ONLY = "universal"
            def which = ONLY
            def self.which = ONLY
          end
        end

        class GuardedFirst
          def which = "real"
          def self.which = "real class method"
        end
      end
      p Probe::GuardedFirst.new.which
      p Probe::GuardedFirst.which

    RUBY

    _(result).must_answer <<~'OUT'
      "real"
      "real class method"
    OUT
  end

  it "and in the other order, the unguarded body still wins" do
    result = ze0(<<~'RUBY', files: beside("guarded_def/base.rb", "guarded_def/real.rb"))
      module Probe
        # A question no compile-time fold can answer, the way bundler asks
        # `Gem::Platform.local.cpu`. Every guard below reads it.
        def self.cpu
          ["arm", "64"].join
        end
      end

      # ...and the other order.
      module Probe
        class GuardedLast
          [:tag].each { |n| attr_accessor(n) }
          def which = "real"
        end

        class GuardedLast
          if Probe.cpu == "universal"
            def which = "universal"
          end
        end
      end
      p Probe::GuardedLast.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      "real"
    OUT
  end

  it "a guard that is true still installs its body" do
    result = ze0(<<~'RUBY', files: beside("guarded_def/base.rb", "guarded_def/real.rb"))
      module Probe
        # A question no compile-time fold can answer, the way bundler asks
        # `Gem::Platform.local.cpu`. Every guard below reads it.
        def self.cpu
          ["arm", "64"].join
        end
      end

      # A guard that is TRUE still installs, or the fix would just be "never
      # install a guarded body".
      module Probe
        class GuardTaken
          [:tag].each { |n| attr_accessor(n) }
          def which = "real"
          def self.which = "real class method"
          if Probe.cpu == "arm64"
            def which = "taken"
            def self.which = "taken class method"
          end
        end
      end
      p Probe::GuardTaken.new.which
      p Probe::GuardTaken.which

    RUBY

    _(result).must_answer <<~'OUT'
      "taken"
      "taken class method"
    OUT
  end

  it "a name only a false branch writes is absent, and so is its constant" do
    result = ze0(<<~'RUBY', files: beside("guarded_def/base.rb", "guarded_def/real.rb"))
      module Probe
        # A question no compile-time fold can answer, the way bundler asks
        # `Gem::Platform.local.cpu`. Every guard below reads it.
        def self.cpu
          ["arm", "64"].join
        end
      end

      # A name only a false branch writes is absent, and so is its constant.
      module Probe
        class OnlyGuarded
          [:tag].each { |n| attr_accessor(n) }
          if Probe.cpu == "universal"
            NEVER = 1
            def missing = NEVER
          end
        end
      end
      p Probe::OnlyGuarded.instance_methods(false).include?(:missing)
      p Probe::OnlyGuarded.const_defined?(:NEVER)
      begin
        Probe::OnlyGuarded.new.missing
      rescue NoMethodError => e
        p e.class.to_s
      end

    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      "NoMethodError"
    OUT
  end

  it "three bodies for one name, two of them guarded, install only the unguarded one" do
    result = ze0(<<~'RUBY', files: beside("guarded_def/base.rb", "guarded_def/real.rb"))
      module Probe
        # A question no compile-time fold can answer, the way bundler asks
        # `Gem::Platform.local.cpu`. Every guard below reads it.
        def self.cpu
          ["arm", "64"].join
        end
      end

      # Three bodies for one name, two of them guarded: the counts differ by two.
      module Probe
        class ThreeBodies
          [:tag].each { |n| attr_accessor(n) }
          if Probe.cpu == "universal"
            def which = "first guard"
          end
          if Probe.cpu == "sparc"
            def which = "second guard"
          end
          def which = "real"
        end
      end
      p Probe::ThreeBodies.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      "real"
    OUT
  end

  it "a guard inside a guard, with a local assigned between them, still reads right" do
    result = ze0(<<~'RUBY', files: beside("guarded_def/base.rb", "guarded_def/real.rb"))
      module Probe
        # A question no compile-time fold can answer, the way bundler asks
        # `Gem::Platform.local.cpu`. Every guard below reads it.
        def self.cpu
          ["arm", "64"].join
        end
      end

      # Bundler's actual nesting: a guard inside a guard, with a local assigned
      # between them.
      module Probe
        class Nested
          [:tag].each { |n| attr_accessor(n) }
          if Probe.cpu
            cpu = Probe.cpu
            if cpu == "universal"
              DEEP = "deep"
              def which = DEEP
            end
          end
          def which = "real"
        end
      end
      p Probe::Nested.new.which

    RUBY

    _(result).must_answer <<~'OUT'
      "real"
    OUT
  end

  it "a block-installed accessor loses to the def that always runs" do
    result = ze0(<<~'RUBY', files: beside("guarded_def/base.rb", "guarded_def/real.rb"))
      module Probe
        # A question no compile-time fold can answer, the way bundler asks
        # `Gem::Platform.local.cpu`. Every guard below reads it.
        def self.cpu
          ["arm", "64"].join
        end
      end

      # The pass's own job, unchanged: a block-installed accessor loses to the
      # `def` written below it, and so does a macro a class method expands.
      module Probe
        class StillPositional
          [:y].each { |a| attr_writer(a) }
          def y=(v)
            @y = [v, v]
          end
          attr_reader :y
        end

        class MacroPack
          def self.make(n) = attr_writer(n)
          make :z
          def z=(v)
            @z = [v, v]
          end
          attr_reader :z
        end
      end
      s = Probe::StillPositional.new
      s.y = 1
      p s.y
      m = Probe::MacroPack.new
      m.z = 2
      p m.z
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1]
      [2, 2]
    OUT
  end

  it "guarded def written first does not take the later bodys position" do
    result = ze0(<<~'RUBY')
      # The reported shape, smallest form: guarded body FIRST, unguarded second.

      def cpu = ["arm", "64"].join
      class C
        [:tag].each { |n| attr_accessor(n) }
        if cpu == "universal"
          ONLY = "universal"
          def which = ONLY
        end
      end
      class C
        def which = "real"
      end
      puts C.new.which
      puts C.const_defined?(:ONLY)
    RUBY

    _(result).must_answer "real\nfalse\n"
  end

  it "guarded def written last does not displace the earlier body" do
    result = ze0(<<~'RUBY')
      # ...and with the guarded body written last, which is the same rule read
      # from the other end.

      def cpu = ["arm", "64"].join
      class C
        [:tag].each { |n| attr_accessor(n) }
        def which = "real"
        if cpu == "universal"
          def which = "universal"
        end
      end
      puts C.new.which
    RUBY

    _(result).must_answer "real\n"
  end

  it "guarded top level def defines at runtime" do
    result = ze0(<<~'RUBY')
      # A guarded top-level plain `def` (myrrha's `def Boolean(s)` behind
      # `Myrrha.core_ext?`): defined -- as a private Object instance method --
      # exactly when the branch runs.
      module Switch
        def self.on?
          ENV["GUARDED_DEF_TEST"] != "off"
        end
      end

      if Switch.on?
        GUARD_TOOK = true
        def taken_helper(x)
          "took #{x}"
        end
      else
        GUARD_TOOK = false
        def skipped_helper(x)
          "skipped #{x}"
        end
      end

      p GUARD_TOOK
      p taken_helper(1)
      p Object.private_method_defined?(:taken_helper)
      p Object.private_method_defined?(:skipped_helper)

      # Callable via implicit self from inside another object's method (a private
      # Object instance method, unlike def self.x on main).
      class Elsewhere
        def call_it
          taken_helper(:from_method)
        end
      end
      p Elsewhere.new.call_it

      # Explicit receiver stays forbidden.
      begin
        Object.new.taken_helper(2)
      rescue NoMethodError => e
        puts "explicit receiver: #{e.class}"
      end

      # The untaken branch's method genuinely does not exist.
      begin
        skipped_helper(3)
      rescue NoMethodError => e
        puts "untaken: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "took 1"
      true
      false
      "took from_method"
      explicit receiver: NoMethodError
      untaken: NoMethodError
    OUT
  end

  it "hash symbol fold" do
    result = ze0(<<~'RUBY')
      p({ a: 1 }.inject(:+))
      p({ a: 1, b: 2 }.reduce(:+))
      a477 = { a: 1 }
      c477 = (a477.inject(:+))
      p c477
      p({ a: 1, b: 2 }.inject(0) { |acc, (_k, v)| acc + v })
      p([1, 2].inject(:+))
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1]
      [:a, 1, :b, 2]
      [:a, 1]
      3
      3
    OUT
  end

  it "isa fold leading statements" do
    result = ze0(<<~'RUBY')
      # A folded `is_a?` arm in EXPRESSION position must still run its statements in
      # order. The fold emitted the arm's leading statements inside a statement
      # expression wrapped around its value -- but the value itself, when it is a
      # conditional, hoists its branches into the enclosing prelude, which is
      # written out first. So the assignment landed BELOW the `if` that reads it,
      # the nil arm always won, and a branch reached its tail without having run its
      # own first line. (matz/spinel#4139, from a Roundhouse app where four
      # controller assertions raised "unknown status :success")
      RANGES = { success: 200..299, redirect: 300..399 }.freeze
      CODES  = { ok: 200, created: 201 }.freeze

      def check(expected, actual)
        if expected.is_a?(Symbol)
          range = RANGES[expected]
          if range.nil?
            code = CODES[expected]
            raise "unknown #{expected.inspect}" if code.nil?
            code == actual
          else
            range.include?(actual)
          end
        else
          expected == actual
        end
      end

      # The key that IS in the first hash: the fold's arm has to read the value its
      # own first statement assigned.
      p check(:success, 250)
      p check(:success, 404)
      p check(:redirect, 302)
      # A key that is only in the second hash still reaches the nil arm correctly.
      p check(:ok, 200)
      p check(:created, 200)
      # The non-Symbol path is untouched by the fold.
      p check(200, 200)
      p check(200, 404)

      # Two leading statements, so the ordering is pinned rather than coincidental.
      def two_leading(v)
        if v.is_a?(Integer)
          a = v * 2
          b = a + 1
          if b > 10
            "big:#{b}"
          else
            "small:#{b}"
          end
        else
          "other"
        end
      end
      p two_leading(1)
      p two_leading(9)
      p two_leading("x")

      # A leading statement in front of a plain expression, not a conditional.
      def leading_then_value(v)
        if v.is_a?(String)
          n = v.length
          n * 3
        else
          -1
        end
      end
      p leading_then_value("abcd")
      p leading_then_value(7)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      true
      false
      "small:3"
      "big:19"
      "other"
      12
      -1
    OUT
  end

  it "inject with an Integer seed folds to whatever type the elements widen it to" do
    result = ze0(<<~'RUBY')
      def horner(coeffs, x)
        coeffs.inject(0) { |acc, c| acc * x + c }
      end
      poly = [2, -3, 4, -5]
      puts "int:   #{horner(poly, 2)}"
      puts "rat:   #{horner(poly, Rational(1, 2))}"
      puts "float: #{horner(poly, 1.5)}"
      p horner([1, 1], Rational(3, 4))
      p [1.5, 2.5].inject(0) { |a, x| a + x }
    RUBY

    _(result).must_answer <<~'OUT'
      int:   7
      rat:   -7/2
      float: 1.0
      (7/4)
      4.0
    OUT
  end

  it "method defined folds inherited native" do
    result = ze0(<<~'RUBY')
      # `method_defined?` / `respond_to?` guards must see native methods a user
      # class inherits from Object/Kernel -- rspec-core's 1.8.7 shim gates a
      # self-recursive `singleton_class` def on exactly this probe, so a confident
      # false here bakes the shim in and it recurses forever.
      class Foo
        unless method_defined?(:singleton_class)
          def singleton_class
            "shim"
          end
        end
        if method_defined?(:object_id)
          def native_seen
            "native seen"
          end
        end
      end

      f = Foo.new
      p f.singleton_class.equal?(f.singleton_class)
      p f.native_seen
      p f.respond_to?(:itself)
      p Foo.method_defined?(:no_such_method)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "native seen"
      true
      false
    OUT
  end

  it "pattern match as and guard" do
    result = ze0(<<~'RUBY')
      # Issues #884 #905: pattern-match `as` binding and `if` guard
      # clause both used to leave the matched LV undeclared, causing
      # C compile errors. Now both bind correctly: CapturePatternNode
      # binds the as-var to the scrutinee at body entry; IfNode-wrapped
      # pattern AND-folds the guard against the inner match.

      # #884: array pattern with `=> arr` capture
      case [1, 2, 3]
      in [1, *] => arr
        puts arr.inspect
      end

      # #905: guard clause with bound variable
      case 10
      in n if n > 5
        puts "big: " + n.to_s
      in n
        puts "small: " + n.to_s
      end

      # #905: guard's else branch
      case 3
      in n if n > 5
        puts "big: " + n.to_s
      in n
        puts "small: " + n.to_s
      end

      # #884: object capture
      case 42
      in Integer => v
        puts "int: " + v.to_s
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      big: 10
      small: 3
      int: 42
    OUT
  end

  it "platform gate is a build time question" do
    result = ze0(<<~'RUBY')
      # `RUBY_PLATFORM =~ /mswin|mingw|windows/` is the platform gate half the gem
      # corpus writes, and it is decidable when the program is compiled: the platform
      # is baked in. Deciding it is what keeps a windows-only branch -- full of types
      # and calls that only exist there -- out of the build entirely.
      #
      # Only a pattern that is `|`-separated LITERAL text folds. Matching one of those
      # is a substring test, which cannot disagree with a regexp engine. Anything
      # carrying real regexp syntax stays undecided and runs normally.

      if RUBY_PLATFORM =~ /mswin|mingw|windows/
        class Impl
          def self.kind = :windows
        end
      else
        class Impl
          def self.kind = :posix
        end
      end

      p Impl.kind

      # The pattern on the other side asks the same question.
      if /mswin|mingw/ =~ RUBY_PLATFORM
        class Other
          def self.kind = :windows
        end
      else
        class Other
          def self.kind = :posix
        end
      end

      p Other.kind

      # `match?` is the same test without the capture.
      p RUBY_PLATFORM.match?(/darwin|linux/)
      p RUBY_ENGINE =~ /jruby|truffleruby/ ? :alt : :mri

      # A guard on a single alternative with nothing to split.
      if RUBY_ENGINE =~ /ruby/
        class OnMri
          def self.here = :yes
        end
      end

      p OnMri.here

      # A pattern with real regexp syntax does NOT fold -- and still answers
      # correctly at run time, which is the point of refusing to approximate it.
      p (RUBY_ENGINE =~ /^ru.y$/) == 0
      p RUBY_PLATFORM.match?(/[0-9]+/)
      p ("mswin32" =~ /mswin\d+/) == 0

      # ... nor does one whose flags change what matching means.
      p "MSWIN".match?(/mswin/i)
      p "MSWIN".match?(/mswin/)

      # The VALUE of `=~` is still an index, not the boolean the guard folded to.
      p("abc-darwin" =~ /darwin/)
      p("abc" =~ /darwin/)
    RUBY

    _(result).must_answer <<~'OUT'
      :posix
      :posix
      true
      :mri
      :yes
      true
      true
      true
      true
      false
      4
      nil
    OUT
  end

  it "platform guarded require is not loaded" do
    result = ze0(<<~'RUBY', files: beside("platform_guarded/posix_only.rb", "platform_guarded/windows_only.rb"))
      # A `require` under a platform guard names a file this program never loads, so
      # a whole-program compiler must not load it either. mixlib-shellout requires its
      # windows half from inside `class ShellOut`, and that half is full of windows
      # FFI types -- following the require compiled code written for a platform this
      # build is not, and failed on the first `:dword`.
      #
      # `windows_only.rb` here contains exactly that: a `:dword` field zeo has no type
      # for. If the require were followed, this file would not compile at all, which
      # is what makes the assertions below more than a `defined?` check.

      if RUBY_PLATFORM =~ /mswin|mingw|windows/
        require_relative "platform_guarded/windows_only"
      else
        require_relative "platform_guarded/posix_only"
      end

      p defined?(WINDOWS_MARKER)
      p defined?(POSIX_MARKER)
      p PosixOnly.kind

      # The same guard from inside a class body, which is where the real one sits.
      class Host
        if RUBY_PLATFORM =~ /mswin|mingw|windows/
          require_relative "platform_guarded/windows_only"
        end

        def self.kind = :host
      end

      p Host.kind
      p defined?(WINDOWS_MARKER)

      # `unless` reads the guard the other way round, and takes the other branch.
      unless RUBY_PLATFORM =~ /mswin|mingw|windows/
        POSIX_AGAIN = :yes
      else
        require_relative "platform_guarded/windows_only"
      end

      p POSIX_AGAIN

      # `match?` and the reversed operand order ask the same question.
      if /mswin|mingw/.match?(RUBY_PLATFORM)
        require_relative "platform_guarded/windows_only"
      end

      if /mswin|mingw/ =~ RUBY_PLATFORM
        require_relative "platform_guarded/windows_only"
      end

      p defined?(WINDOWS_MARKER)

      # `File::ALT_SEPARATOR` is the oldest windows test there is -- `"\\"` there and
      # `nil` everywhere else, so its TRUTH is a property of the build. sys-filesystem
      # picks its half with it.
      if File::ALT_SEPARATOR
        require_relative "platform_guarded/windows_only"
      end

      p File::ALT_SEPARATOR
      p defined?(WINDOWS_MARKER)

      # An engine gate is the same shape, on a different baked constant.
      if RUBY_ENGINE =~ /jruby|truffleruby/
        require_relative "platform_guarded/windows_only"
      end

      p defined?(WINDOWS_MARKER)
      p :done
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "constant"
      :posix
      :host
      nil
      :yes
      nil
      nil
      nil
      nil
      :done
    OUT
  end

  it "refine in a conditional reopen" do
    result = ze0(<<~'RUBY')
      # A `refine` written inside a class body that a RUNTIME-undecidable `if`
      # reopened. power_assert does exactly this -- every refinement it owns lives
      # inside `if PowerAssert.configuration._redefinition; module PowerAssert`,
      # and test-unit inherits the failure through it.
      #
      # `try_conditional_reopen` rewrites `if C; module M; BODY; end; end` into
      # `module M; if C; BODY; end; end`, so the class-body walk sees an `If`, not
      # the `refine` inside it. Which class a refinement refines is a compile-time
      # fact about SHAPE -- the same reason a nested `class`/`module` is registered
      # through that same `If` -- so it is recorded even though the branch may never
      # run, and the spent marker then emits nothing at its document position.

      class Conf
        def self.redefinition?
          true
        end
      end

      module Shouty
      end

      if Conf.redefinition?
        module Shouty
          refine String do
            def loud
              upcase + "!"
            end
          end

          refine Integer do
            def loud
              "<#{self}>"
            end
          end
        end
      end

      # The refinement answers only where it is activated...
      using Shouty
      p "hi".loud
      p 7.loud

      # ...and the holder module is still not a name the target answers to.
      p String.instance_methods.include?(:loud)
      p String.method_defined?(:loud)

      # An unrefined method on the same receiver is untouched.
      p "hi".upcase

      # The refinement is active inside its own block too, so a sibling `refine`
      # body reaches the set by explicit receiver.
      module Quiet
        refine String do
          def soft
            downcase
          end

          def whisper
            soft + "..."
          end
        end
      end

      using Quiet
      p "LOUD".whisper
    RUBY

    _(result).must_answer <<~'OUT'
      "HI!"
      "<7>"
      false
      false
      "HI"
      "loud..."
    OUT
  end

  it "regexp unicode casefold" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at fa06b601.
      #
      # `/i` folds only ASCII, so a non-ASCII literal does not match its
      # counterpart.
      #
      # CRuby folds by Unicode simple case folding, and a counterpart need not have
      # the same WIDTH (`U+212A` folds to `k`), which is why the fix is to emit the
      # counterparts as a class rather than to fold in place.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix, not zeo's divergence above.
      #
      # /i folds by Unicode simple case folding: the counterparts of a non-ASCII
      # literal are emitted as a class, since a counterpart need not have the same
      # width (U+212A folds to `k`). Ported from mruby-regexp (618ba9435). A build
      # made with -DRE_NO_UNICODE_CASE folds ASCII alone and matches the rest
      # literally, which is what this engine did before the table arrived.
      p("Ä" =~ /ä/i ? true : false)
      p("ä" =~ /Ä/i ? true : false)
      p("Ä" =~ /ä/ ? true : false)
      p("Σ" =~ /σ/i ? true : false)
      p("ς" =~ /σ/i ? true : false)
      p("K" =~ /k/i ? true : false)
      p("ÄB" =~ /äb/i ? true : false)
      p "ÄäÖ".scan(/ä/i)
      p "ÄäÖ".gsub(/ä/i, "-")

      # character classes fold their codepoint members and ranges
      p("ä" =~ /[Ä]/i ? true : false)
      p("ä" =~ /[À-Þ]/i ? true : false)
      p("Ä" =~ /[^ä]/i ? true : false)
      p("a" =~ /[A-Z]/i ? true : false)
      p("あ" =~ /[あ-ん]/i ? true : false)

      # and a backreference compares folded codepoints, whatever their widths
      p("Ää" =~ /(Ä)\1/i ? true : false)
      p("Kk" =~ /(K)\1/i ? true : false)
      p("ÄÖ" =~ /(Ä)\1/i ? true : false)

      # A source whose fold is several codepoints (U+00DF to "ss") has no single
      # counterpart to fold to and is matched literally, so `"ß" =~ /ss/i` answers
      # nil where CRuby answers 0 -- the same scope mruby-regexp draws.
      p("ß" =~ /ß/i ? true : false)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      true
      true
      true
      ["Ä", "ä"]
      "--Ö"
      true
      true
      false
      true
      true
      true
      true
      false
      true
    OUT
  end

  it "reopen guarded by an outer local" do
    result = ze0(<<~'RUBY')
      # A class reopened under a trailing `if` that reads a local of the ENCLOSING
      # scope. Zeo runs a class body at its document position, inside the enclosing
      # scope's own block, but built that body's context from the body's own
      # statements alone -- so the guard, which the site carries in with it, read the
      # outer local as an ordinary value while the enclosing scope was keeping it in
      # a shared cell. The two disagreed and the program did not compile.
      #
      # pp.rb is written this way -- `class Set ... end if set_pp`, where `set_pp` is
      # a top-level local decided a few lines above -- and it only bites once
      # something else in the program makes that scope hold its locals by reference.
      #
      # Only a TAKEN guard is exercised here. A `def` inside a reopen whose guard is
      # false still registers in zeo -- dispatch-table registration is hoisted and
      # only the body's EXECUTION is guarded -- which is its own divergence, and not
      # the one this covers.
      on = true

      class String
        def zeo_probe = "string probed"
      end if on

      p "x".zeo_probe

      # The guard is an ordinary expression, not just a bare read.
      label = "yes"

      class Symbol
        def zeo_probe = "symbol probed"
      end if label == "yes"

      p :s.zeo_probe

      # A class body's OWN local shadows the enclosing one rather than sharing it.
      shadowed = "outer"

      class Array
        shadowed = "inner"
        def zeo_probe = "array probed"
      end if on

      p shadowed
      p [].zeo_probe

      # What makes the enclosing scope keep its locals by reference in the first
      # place.
      p proc { 1 }.binding.local_variables.include?(:on)
    RUBY

    _(result).must_answer <<~'OUT'
      "string probed"
      "symbol probed"
      "outer"
      "array probed"
      true
    OUT
  end

  it "respond to true and false on a statically known receiver" do
    result = ze0(<<~'RUBY')
      class Dog
        def bark
          "woof"
        end
      end

      d = Dog.new
      puts d.respond_to?(:bark)
      puts d.respond_to?(:meow)
    RUBY

    _(result).must_answer "true\nfalse\n"
  end

  it "run time compile handles aliases and guards" do
    files = fixtures("runtime_compiled/aliased_extend.rb", "runtime_compiled/guarded_toplevel.rb")

    result = ze0(<<~'RUBY', files: files)
      # The RUN-TIME compiler on shapes real gems use. A `require` whose target only
      # the running program knows -- a computed feature name, or one reached through
      # a `$LOAD_PATH` the program just changed -- is compiled at run time by a
      # second compiler, and it used to refuse or mis-lower two ordinary things.
      #
      # AN ALIAS THROUGH `extend`. A method has two installed shapes: one taking an
      # `&RObj`, one taking a plain value. Only the second can run with a CLASS as
      # `self`. `runtime_alias_method` copied the first and not the second, so an
      # aliased method reached through `extend` ran against a surrogate object and a
      # receiverless call inside it looked for an INSTANCE method. Forwardable is
      # exactly this -- `alias def_delegators def_instance_delegators` -- so
      # `extend Forwardable; def_delegators :@t, :year` raised
      # `undefined method 'def_instance_delegator'`.
      #
      # A GUARDED TOP-LEVEL DEFINITION. `analyze::static_guards` rewrites one into a
      # synthesized `class Object` wrapper around a synthesized `if`, and neither
      # carried a span. A class body compiled at run time is re-evaluated from its
      # own SOURCE TEXT, sliced between its first and last statement -- and the slice
      # is taken only when the wrapper's span CONTAINS them. Span-less, it refused
      # the whole file: "a span-less `class` (`Object`) inside an `eval`". `time.rb`
      # has this shape, so it took `require "bundler/setup"` down with it.

      DIR = File.expand_path("../../fixtures/runtime_compiled", __dir__)
      $LOAD_PATH.unshift(DIR)

      # Computed, so the loader cannot resolve it and the run time must.
      %w[aliased_extend guarded_toplevel].each { |f| require f }

      p UsesAliasedExtend.collected
      p GUARDED_WHICH
      p guarded_choice
      p GuardedHolder.new.which
      p UsesAliasedExtend.singleton_class.ancestors.include?(AliasedExtend)
      p UsesAliasedExtend.respond_to?(:collect)
      p UsesAliasedExtend.method(:collect).owner
    RUBY

    _(result).must_answer <<~'OUT'
      ["a@UsesAliasedExtend", "b@UsesAliasedExtend", "c@UsesAliasedExtend"]
      :else_branch
      :else_branch
      :else_branch
      true
      true
      AliasedExtend
    OUT
  end

  it "runtime conditional class reveals on definition" do
    result = ze0(<<~'RUBY')
      def fancy? = true
      if fancy?
        module Helpers
          LEVEL = 3
          def self.tag = "fancy"
        end
        class Widget
          include Helpers
          def kind = "fancy-#{Helpers::LEVEL}"
        end
      end
      puts defined?(Helpers)
      puts Helpers.tag
      puts Widget.new.kind
      puts Widget.ancestors.first(2).inspect
      puts Object.const_defined?(:Widget)
    RUBY

    _(result).must_answer <<~'OUT'
      constant
      fancy
      fancy-3
      [Widget, Helpers]
      true
    OUT
  end

  it "runtime private constant reaches a folded read" do
    result = ze0(<<~'RUBY')
      # `private_constant` is a run-time flag: a snippet can set it on a constant
      # the compiler already resolved, so a program that can `eval` at all asks
      # the run time at every explicit-scope read instead of folding one.

      module N1
        A = 1
        class K; end
        def self.inside = A
      end

      eval(["module N1; private_constant :A, :K; end", "nil"].first)

      begin
        p N1::A
      rescue NameError => e
        puts e.message
      end
      begin
        p N1::K
      rescue NameError => e
        puts e.message
      end

      # `defined?` answers the same question, so it stands down from the fold too.
      p defined?(N1::A)
      p defined?(N1::K)
      p N1.constants
      # A bare name inside the owner's own body still reads it, and `const_get`
      # ignores privacy exactly as CRuby's does.
      p N1.inside
      p N1.const_get(:A)

      # The flag is restorable, and the read follows it.
      eval(["module N1; public_constant :A; end", "nil"].first)
      p N1::A
      p defined?(N1::A)
    RUBY

    _(result).must_answer <<~'OUT'
      private constant N1::A referenced
      private constant N1::K referenced
      nil
      nil
      []
      1
      1
      1
      "constant"
    OUT
  end

  it "scaffolded extension constant resolves but is a name error without require" do
    result = ze0(<<~'RUBY')
      # A scaffolded ext (json) is still require-gated: its constant is a
      # NameError until `require "json"` fires, exactly like the fully-built
      # ones -- scaffolding changes only what the METHODS do, not the gate.

      puts JSON.generate([1])
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      compiler/guards/guards_test.rb:5:in '<main>': uninitialized constant JSON (NameError)

      puts JSON.generate([1])
           ^^^^
    ERR
  end

  it "singleton class rescue guard" do
    result = ze0(<<~'RUBY')
      # A `rescue` guarding a statement inside `class << obj`, the per-instance
      # singleton class.
      #
      # The mapping accepts a fixed set of items and rejects the rest, because `self`
      # in that body is the object's singleton class and a statement that consults it
      # cannot simply run in the enclosing scope. A `begin/rescue` -- and the modifier
      # form, which lowers to the same node -- consults nothing itself: it only
      # guards. So the guarded statements map exactly as they would unguarded, and
      # the guard is kept.
      #
      # tins writes it: `class << modul; remove_method :now rescue nil; end`, where
      # the `rescue` is load-bearing because `remove_method` raises NameError unless
      # the method is defined at that exact level.

      module Clock
        def self.now
          "real now"
        end
      end

      p Clock.now

      class << Clock
        alias really_now now

        # The modifier form. The second one raises NameError, and the guard is what
        # the gem relies on to survive it.
        remove_method :now rescue nil
        remove_method :never_was_defined rescue nil

        def now
          "frozen now"
        end
      end

      p Clock.now
      p Clock.really_now

      # The explicit form, and nested inside a conditional the mapping already
      # recurses through, so the two compose.
      obj = Object.new

      class << obj
        if RUBY_VERSION > "2.0"
          begin
            remove_method :inspect
          rescue NameError
            nil
          end

          def to_s
            "custom"
          end
        end
      end

      p obj.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "real now"
      "frozen now"
      "real now"
      "custom"
    OUT
  end

  it "singleton prepend reaches static call sites" do
    result = ze0(<<~'RUBY')
      # `<expr>.singleton_class.prepend(M)` where the RECEIVER or the MODULE is not
      # a compile-time constant used to be rejected: statically resolved `X.m` call
      # sites never consulted the runtime singleton tables the send writes, so the
      # prepend would have compiled and then overridden nothing. It now runs as the
      # ordinary send it is, and the modules' method names de-optimize those call
      # sites so they see the override (`prepend_into_class_singleton`).
      module Loud
        def greet = "LOUD " + super
      end

      module Softer
        def greet = "soft " + super
      end

      class Speaker
        def self.greet = "hi"
      end

      # The receiver reaches the class through a LOCAL -- not a constant path.
      k = Speaker
      k.singleton_class.prepend(Loud)
      p Speaker.greet
      p Speaker.singleton_class.ancestors.include?(Loud)

      # The module reaches the call through an EXPRESSION -- also not a constant.
      mods = [Softer]
      Speaker.singleton_class.prepend(mods.first)
      p Speaker.greet

      # A method the modules do NOT define keeps answering the class's own.
      def Speaker.name_tag = "speaker"
      p Speaker.name_tag
    RUBY

    _(result).must_answer <<~'OUT'
      "LOUD hi"
      true
      "soft LOUD hi"
      "speaker"
    OUT
  end

  it "spaceship nil guard poly compare" do
    result = ze0(<<~'RUBY')
      # A `<=>` with a `return nil` guard has an sp_RbVal return, and its body's
      # compare goes through the polymorphic helper as soon as the ivar holds more
      # than one type -- or simply when a second class in the program also defines
      # `<=>`. The helper answers an mrb_int (the sentinel for nil), which went out
      # through the boxed signature unboxed and failed the C build (#3498).
      class A
        include Comparable
        attr_reader :v

        def initialize(v)
          @v = v
        end

        def <=>(other)
          return nil unless other.is_a?(A)
          @v <=> other.v
        end
      end

      # never instantiated: defining it is enough to route A's compare through the
      # polymorphic helper
      class B
        attr_reader :v

        def initialize(v)
          @v = v
        end

        def <=>(other)
          return nil unless other.is_a?(B)
          @v <=> other.v
        end
      end

      p(A.new(1) <=> A.new(2))
      p(A.new(2) <=> A.new(1))
      p(A.new(1) <=> A.new(1))

      # the guard's own answer
      p(A.new(1) <=> 5)
      p((A.new(1) <=> 5).nil?)

      # Comparable's derived operators over the boxed compare
      p(A.new(1) < A.new(2))
      p(A.new(2) >= A.new(1))
      p [A.new(3), A.new(1), A.new(2)].sort.map(&:v)
      p A.new(2).between?(A.new(1), A.new(3))
      p A.new(2).clamp(A.new(1), A.new(3)).v

      # a mixed-type ivar takes the same route
      p(A.new(1) <=> A.new(1))
      p(A.new(Rational(1, 2)) <=> A.new(Rational(1, 3)))
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
      nil
      true
      true
      true
      [1, 2, 3]
      true
      2
      0
      1
    OUT
  end

  it "static top level if guard registers or drops its definitions" do
    result = ze0(<<~'RUBY')
      # The `if defined?(Const) ... module M ... end` idiom (singleton's
      # `if defined?(Ractor)` tail): a decidably-TRUE guard's branch is spliced
      # through the top-level walk (its module registers, its methods resolve),
      # a decidably-FALSE guard's branch is dropped entirely -- exactly the
      # branch real Ruby would or wouldn't execute there. Nesting folds too.

      if defined?(String)
        module Kept
          def self.tag
            "kept"
          end
        end
        if defined?(Integer)
          module KeptNested
            def self.tag
              "nested"
            end
          end
        end
      end
      if defined?(NoSuchConstantAnywhere)
        module Dropped
          def self.tag
            "dropped"
          end
        end
      end
      puts Kept.tag
      puts KeptNested.tag
      puts defined?(Dropped).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      kept
      nested
      nil
    OUT
  end

  it "statically wrong arity call raises at runtime and dead code stays silent" do
    result = ze0(<<~'RUBY')
      # CRuby's behavior: the error belongs to the CALL, not the program.

      module M
        def self.run!(a, b, c, d)
          "#{a}#{b}#{c}#{d}"
        end
      end
      begin
        M.run!(1, 2, false)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
      puts M.run!(1, 2, 3, 4)
      def never_called
        M.run!(1)
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: wrong number of arguments (given 3, expected 4)
      1234
      done
    OUT
  end

  it "defined? of a constant the program never defines folds false" do
    result = ze0(<<~'RUBY')
      # A class or module defined inside a top-level `if`.
      #
      # zeo has to decide such a guard at compile time -- it registers definitions in
      # one whole-program walk, so a definition it cannot prove reachable is a
      # rejection rather than a runtime branch. `guard_fold` does the deciding, and
      # two shapes it could not read cover most of the real gem guards.
      #
      #   !defined?(X)              a reload guard, and `static_bool` had no `!`
      #   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
      #                             `instance_class` mapped only `X.new` / bare `new`
      #
      # The gems: addressable writes the first; httpclient, em-websocket, highline and
      # test-prof write the second.

      # `defined?` of a constant the whole program never defines folds false, so the
      # negation folds true and the branch is kept.
      if !defined?(SomeGemThatIsNotHere)
        class Provided
          def call
            "the guarded definition ran"
          end
        end
      end

      p Provided.new.call

    RUBY

    _(result).must_answer <<~'OUT'
      "the guarded definition ran"
    OUT
  end

  it "&& over two such probes waits on both" do
    result = ze0(<<~'RUBY')
      # A class or module defined inside a top-level `if`.
      #
      # zeo has to decide such a guard at compile time -- it registers definitions in
      # one whole-program walk, so a definition it cannot prove reachable is a
      # rejection rather than a runtime branch. `guard_fold` does the deciding, and
      # two shapes it could not read cover most of the real gem guards.
      #
      #   !defined?(X)              a reload guard, and `static_bool` had no `!`
      #   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
      #                             `instance_class` mapped only `X.new` / bare `new`
      #
      # The gems: addressable writes the first; httpclient, em-websocket, highline and
      # test-prof write the second.

      # `&&` over two of them, which is how a guard that waits on more than one
      # optional dependency is written.
      if !defined?(AbsentOne) && !defined?(AbsentTwo)
        module Both
          OK = "both absent"
        end
      end

      p Both::OK

    RUBY

    _(result).must_answer <<~'OUT'
      "both absent"
    OUT
  end

  it "a capability probe on a String literal answers from String's own surface" do
    result = ze0(<<~'RUBY')
      # A class or module defined inside a top-level `if`.
      #
      # zeo has to decide such a guard at compile time -- it registers definitions in
      # one whole-program walk, so a definition it cannot prove reachable is a
      # rejection rather than a runtime branch. `guard_fold` does the deciding, and
      # two shapes it could not read cover most of the real gem guards.
      #
      #   !defined?(X)              a reload guard, and `static_bool` had no `!`
      #   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
      #                             `instance_class` mapped only `X.new` / bare `new`
      #
      # The gems: addressable writes the first; httpclient, em-websocket, highline and
      # test-prof write the second.

      # A capability probe on a string literal. zeo answers `bytesize` from String's
      # own native surface, so the guard folds FALSE and the definition never reaches
      # codegen -- the native method is what runs.
      unless "".respond_to?(:bytesize)
        class String
          def bytesize
            -1
          end
        end
      end

      p "hello".bytesize
      p "héllo".bytesize

    RUBY

    _(result).must_answer <<~'OUT'
      5
      6
    OUT
  end

  it "the same probe answers on the other literal receivers and through a method" do
    result = ze0(<<~'RUBY')
      # A class or module defined inside a top-level `if`.
      #
      # zeo has to decide such a guard at compile time -- it registers definitions in
      # one whole-program walk, so a definition it cannot prove reachable is a
      # rejection rather than a runtime branch. `guard_fold` does the deciding, and
      # two shapes it could not read cover most of the real gem guards.
      #
      #   !defined?(X)              a reload guard, and `static_bool` had no `!`
      #   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
      #                             `instance_class` mapped only `X.new` / bare `new`
      #
      # The gems: addressable writes the first; httpclient, em-websocket, highline and
      # test-prof write the second.

      # The same probe on the other literal receivers, and through a method the
      # receiver inherits (`tap` comes from Kernel, not Array).
      unless [].respond_to?(:sum)
        class Array
          def sum
            -1
          end
        end
      end

      unless({}.respond_to?(:tap))
        class Hash
          def tap
            -1
          end
        end
      end

      unless 1.respond_to?(:zero?)
        class Integer
          def zero?
            false
          end
        end
      end

      p [1, 2, 3].sum
      p({ a: 1 }.tap { |h| h[:b] = 2 })
      p 0.zero?

    RUBY

    _(result).must_answer <<~'OUT'
      6
      {a: 1, b: 2}
      true
    OUT
  end

  it "unless !x folds too, and keeps the branch this time" do
    result = ze0(<<~'RUBY')
      # A class or module defined inside a top-level `if`.
      #
      # zeo has to decide such a guard at compile time -- it registers definitions in
      # one whole-program walk, so a definition it cannot prove reachable is a
      # rejection rather than a runtime branch. `guard_fold` does the deciding, and
      # two shapes it could not read cover most of the real gem guards.
      #
      #   !defined?(X)              a reload guard, and `static_bool` had no `!`
      #   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
      #                             `instance_class` mapped only `X.new` / bare `new`
      #
      # The gems: addressable writes the first; httpclient, em-websocket, highline and
      # test-prof write the second.

      # `unless !x` -- the double negative folds too, and keeps the branch this time.
      unless !defined?(StillNotHere)
        class NeverRuns
          def call
            "unreachable"
          end
        end
      end

      p defined?(NeverRuns).nil?

    RUBY

    _(result).must_answer <<~'OUT'
      true
    OUT
  end

  it "const_defined? is defined?'s reflective twin and reads the same state" do
    result = ze0(<<~'RUBY')
      # A class or module defined inside a top-level `if`.
      #
      # zeo has to decide such a guard at compile time -- it registers definitions in
      # one whole-program walk, so a definition it cannot prove reachable is a
      # rejection rather than a runtime branch. `guard_fold` does the deciding, and
      # two shapes it could not read cover most of the real gem guards.
      #
      #   !defined?(X)              a reload guard, and `static_bool` had no `!`
      #   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
      #                             `instance_class` mapped only `X.new` / bare `new`
      #
      # The gems: addressable writes the first; httpclient, em-websocket, highline and
      # test-prof write the second.

      # `const_defined?` -- `defined?`'s reflective twin, which guard-compat uses.
      unless Object.const_defined?("HostFrameworkIsAbsent")
        module Stubbed
          NAME = "stubbed"
        end
      end

      p Stubbed::NAME

    RUBY

    _(result).must_answer <<~'OUT'
      "stubbed"
    OUT
  end

  it "a capability probe whose answer is genuinely no takes the other branch" do
    result = ze0(<<~'RUBY')
      # A class or module defined inside a top-level `if`.
      #
      # zeo has to decide such a guard at compile time -- it registers definitions in
      # one whole-program walk, so a definition it cannot prove reachable is a
      # rejection rather than a runtime branch. `guard_fold` does the deciding, and
      # two shapes it could not read cover most of the real gem guards.
      #
      #   !defined?(X)              a reload guard, and `static_bool` had no `!`
      #   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
      #                             `instance_class` mapped only `X.new` / bare `new`
      #
      # The gems: addressable writes the first; httpclient, em-websocket, highline and
      # test-prof write the second.

      # A capability probe whose answer is genuinely NO. String's surface is
      # projected in full, so the absence is a fact rather than an unfinished class,
      # and the branch is kept -- test-prof asks exactly this to detect ActiveSupport.
      unless "".respond_to?(:parameterize)
        class Parameterizer
          def call
            "activesupport is not loaded"
          end
        end
      end

      p Parameterizer.new.call

    RUBY

    _(result).must_answer <<~'OUT'
      "activesupport is not loaded"
    OUT
  end

  it "a standard stream is an IO instance, which is how a gem probes for one" do
    result = ze0(<<~'RUBY')
      # A class or module defined inside a top-level `if`.
      #
      # zeo has to decide such a guard at compile time -- it registers definitions in
      # one whole-program walk, so a definition it cannot prove reachable is a
      # rejection rather than a runtime branch. `guard_fold` does the deciding, and
      # two shapes it could not read cover most of the real gem guards.
      #
      #   !defined?(X)              a reload guard, and `static_bool` had no `!`
      #   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
      #                             `instance_class` mapped only `X.new` / bare `new`
      #
      # The gems: addressable writes the first; httpclient, em-websocket, highline and
      # test-prof write the second.

      # A standard stream is an IO instance, which is how highline probes.
      unless STDIN.respond_to?(:getbyte)
        class IO
          def getbyte
            -1
          end
        end
      end

      p STDIN.respond_to?(:getbyte)
    RUBY

    _(result).must_answer <<~'OUT'
      true
    OUT
  end

  it "top level guarded directives" do
    result = ze0(<<~'RUBY')
      # A guarded `def` or `alias` at top level compiles with the guard deciding at
      # runtime -- the directive rides into an Object reopen, where the class-body
      # conditional machinery already knows how to register-but-not-promise it.
      def maybe_here
        "here"
      end if ENV["HOME"]
      puts maybe_here

      alias missing_alias maybe_here if ENV["ZEO_TEST_NEVER_SET"]
      begin
        missing_alias
      rescue NameError
        puts "not aliased"
      end
    RUBY

    _(result).must_answer "here\nnot aliased\n"
  end

  it "two guarded bodies and one real one still answer the real one" do
    result = ze0(<<~'RUBY')
      # Three bodies for one name, two of them guarded: the two lists differ by
      # two, so an off-by-one fix would still land on the wrong row.

      def cpu = ["arm", "64"].join
      class C
        [:tag].each { |n| attr_accessor(n) }
        if cpu == "universal"
          def which = "first guard"
        end
        if cpu == "sparc"
          def which = "second guard"
        end
        def which = "real"
      end
      puts C.new.which
    RUBY

    _(result).must_answer "real\n"
  end

  it "undef under dynamic guard" do
    result = ze0(<<~'RUBY')
      # `undef :m if <runtime condition>` -- drb's shape. The guard can't be decided
      # at compile time, so the undef has to become a runtime `undef_method` rather
      # than the compile-time record an unguarded `undef` is.
      class Ghost
        def to_a = [1]
        def to_s = "ghost"
        def size = 0

        # `self` in a class body is the CLASS, so this asks whether Ghost-the-object
        # responds -- it doesn't, and the undef is skipped.
        undef :to_a if respond_to?(:to_a, true)
        undef :to_s unless $stdout.nil?
        undef :size, :nonexistent_is_fine if false
      end

      p Ghost.new.respond_to?(:to_a)
      p Ghost.new.respond_to?(:to_s)
      p Ghost.new.respond_to?(:size)
      p Ghost.instance_methods(false).sort

      # An undef'd name stays gone through every reflection door, and `super` can't
      # reach past it either.
      class Base
        def greet = "base"
      end
      class Quiet < Base
        undef :greet if [1].size == 1
      end
      p Quiet.method_defined?(:greet)
      p Quiet.new.respond_to?(:greet)
      begin
        Quiet.new.greet
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      [:size, :to_a]
      false
      false
      undefined method 'greet' for an instance of Quiet
    OUT
  end

  it "user platform predicate folds and defers" do
    result = ze0(<<~'RUBY', files: beside("user_predicate/windows_only.rb"))
      # puppet's shape: the platform test is a USER method whose body is
      # `!!File::ALT_SEPARATOR`. The predicate's truth is a property of the build,
      # so a top-level guard reading it picks its branch at compile time -- and a
      # METHOD-BODY `require_relative` under the same (parse-undecidable) guard
      # defers to a gated unit instead of splicing eagerly, so a windows-only file
      # full of FFI vocabulary zeo has no types for never blocks the build.
      module Platform
        def self.windows?
          !!File::ALT_SEPARATOR
        end
      end

      if Platform.windows?
        KIND = :windows
      else
        KIND = :posix
      end
      p KIND

      module Manager
        def self.root?
          if Platform.windows?
            require_relative "user_predicate/windows_only"
            WindowsUser.admin?
          else
            :uid_zero
          end
        end
      end

      p Manager.root?
      p defined?(WINDOWS_MARKER)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      :posix
      :uid_zero
      nil
      still running
    OUT
  end

  it "version gate compares by version not by string" do
    result = ze0(<<~'RUBY')
      # Ruby preloads rubygems, so a gem reaches for `Gem::Version` without ever
      # requiring it -- and rubygems' `<=>` COERCES a plain string operand, making the
      # comparison version-segment-wise rather than lexicographic. The two answer
      # differently often enough to matter: `"10.0"` is greater than `"9.0"` as a
      # version and smaller as a string.
      #
      # unparser gates its two `Builder` definitions on one of these, one per branch
      # with a DIFFERENT superclass. A compiler that can't decide the guard registers
      # both arms and reports a superclass mismatch for a program ruby runs without
      # complaint, so deciding it is what makes the gem compile at all.

      module Unparsed
        if Gem::Version.new(RUBY_VERSION) <= "3.4"
          class Builder < String
            def which = :legacy
          end
        else
          class Builder < Array
            def which = :modern
          end
        end
      end

      p Unparsed::Builder.superclass
      p Unparsed::Builder.new.which

      # The same gate the other way round, so BOTH branches are exercised: no ruby
      # this compiles under is past 99.
      module Backport
        if Gem::Version.new(RUBY_VERSION) <= "99.0"
          class Shim < Array
            def which = :shimmed
          end
        else
          class Shim < String
            def which = :native
          end
        end
      end

      p Backport::Shim.superclass
      p Backport::Shim.new.which

      # Version semantics, proved: a string comparison would order these the other
      # way, and would pick the other branch.
      if Gem::Version.new("10.0") > "9.0"
        class TenIsNewer
          def ordering = :by_version
        end
      else
        class TenIsNewer
          def ordering = :by_string
        end
      end

      p TenIsNewer.new.ordering

      # `String#<=>` hands an operand it can't compare back to that operand's own
      # `<=>` and negates the answer, so a version on the RIGHT still orders by
      # version.
      module Reversed
        if "9.0" < Gem::Version.new("10.0")
          class Order < Array
            def which = :by_version
          end
        else
          class Order < String
            def which = :by_string
          end
        end
      end

      p Reversed::Order.superclass
      p Reversed::Order.new.which

      # Two versions, no coercion needed.
      module Both
        if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0")
          class Pick < Array
            def which = :at_least_three
          end
        else
          class Pick < String
            def which = :older
          end
        end
      end

      p Both::Pick.superclass
      p Both::Pick.new.which
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      :modern
      Array
      :shimmed
      :by_version
      Array
      :by_version
      Array
      :at_least_three
    OUT
  end

  it "version gate defs fold" do
    result = ze0(<<~'RUBY')
      # Version-gate guards wrapping whole definitions fold at compile time against
      # zeo's fixed target version, exactly as CRuby decides them at load time.
      # `RUBY_VERSION` is a build-time String, so `RUBY_VERSION <op> "x"` folds by the
      # same lexicographic String comparison CRuby evaluates natively -- letting this
      # fixture's oracle and zeo agree without any runtime stub. (The `Gem::Version`
      # segment path is covered by `guard_fold`'s unit tests, which can't share a
      # fixture with a real-rubygems oracle.)

      class Widget
        # "4.0.6" < "3.0" is false -> the compat module + prepend are dropped (a
        # conditional `prepend` zeo cannot express under static MRO).
        if RUBY_VERSION < "3.0"
          module LegacyPatch
            def name
              "patched"
            end
          end
          prepend LegacyPatch
        end

        # unless ("4.0.6" >= "3.0" == true) -> also dropped.
        unless RUBY_VERSION >= "3.0"
          class Nested
            def obsolete; end
          end
        end

        def name
          "plain widget"
        end
      end

      # A true top-level gate keeps its class (analyze registers the taken branch).
      if RUBY_VERSION >= "3.0"
        class Alive
          def status
            "alive"
          end
        end
      end

      # The dropped `prepend LegacyPatch` never takes effect, so `name` is the plain
      # body method, not "patched" -- the observable proof the false-guarded compat
      # definition folded away.
      puts Widget.new.name
      puts Alive.new.status
    RUBY

    _(result).must_answer "plain widget\nalive\n"
  end

  it "version gated def folds" do
    result = ze0(<<~'RUBY')
      module M
        def self.helper?
          true
        end
        if helper? && RUBY_VERSION[0, 3] == '1.9'
          def self.append_features(mod)
            raise "1.9-only path ran"
          end
        end
      end

      class K
        include M
      end
      p K.ancestors.include?(M)
    RUBY

    _(result).must_answer "true\n"
  end
  it "the named calls with a fast path answer as the call does, past the road and once redefined" do
    result = ze0(<<~'RUBY')
      # The named calls with a fast path: what they answer on the road, past
      # the fixnums, on a frozen receiver, and once the method is redefined.
      s = "abc".b
      p s.getbyte(1), s.getbyte(-1), s.getbyte(3)
      begin
        s.getbyte(2**70)
      rescue RangeError => e
        p e.class
      end
      s.setbyte(0, 0x41)
      s.setbyte(-1, 256 + 0x5A)
      p s
      begin
        s.setbyte(3, 1)
      rescue IndexError => e
        p e.message
      end
      begin
        "x".freeze.setbyte(0, 1)
      rescue FrozenError => e
        p e.class
      end
      p 41.succ, -1.succ, (2**62 - 1).succ, (2**62 - 1).succ.class, (2**70).succ
      begin
        1.5.succ
      rescue NoMethodError => e
        p e.class
      end
      a = [1, 2]
      p a.push(3), a.pop, a.shift, a, a.empty?, [].empty?
      begin
        [1].freeze.push(2)
      rescue FrozenError => e
        p e.class
      end
      class Array
        def push(x) = "no push of #{x}"
        def empty? = :never
      end
      class String
        def getbyte(i) = :byte
      end
      class Integer
        def succ = self + 10
      end
      p [1].push(2), [].empty?, "a".getbyte(0), 5.succ, "a".setbyte(0, 98), [3].pop, [4, 5].shift
    RUBY

    _(result).must_answer <<~'OUT'
      98
      99
      nil
      RangeError
      "AbZ"
      "index 3 out of string"
      FrozenError
      42
      0
      4611686018427387904
      Integer
      1180591620717411303425
      NoMethodError
      [2]
      3
      1
      [2]
      false
      true
      FrozenError
      "no push of 2"
      :never
      :byte
      15
      98
      3
      4
    OUT
  end

  it "a String's bytes are read and written in place, and every case past the road answers as the method does" do
    result = ze0(<<~'RUBY')
      # The bytes read and written where they stand: a loop over a copy, the
      # scans forgotten after a write, a chilled literal, a subclass, a frozen
      # String, the ends of the range, and a MatchData taken before the write.
      s = "hello".dup
      i = 0
      while i < s.bytesize
        s.setbyte(i, s.getbyte(i) - 32)
        i += 1
      end
      p s
      t = "abc".dup
      p t.ascii_only?, t.valid_encoding?
      t.setbyte(1, 0xff)
      p t.ascii_only?, t.valid_encoding?, t.bytes
      t.setbyte(1, 0x62 - 256)
      p t, t.ascii_only?
      lit = "xyz"
      lit.setbyte(0, 0x58)
      p lit
      class Bytes < String
        def getbyte(i) = -1
      end
      b = Bytes.new("ab")
      p b.getbyte(0), b.setbyte(0, 0x41), b
      m = "abc".dup
      md = m.match(/b/)
      m.setbyte(1, 0x42)
      p md[0], md.pre_match, md.string, m
      f = "abc".freeze
      begin
        f.setbyte(0, 1)
      rescue FrozenError => e
        p e.message
      end
      e = "ab".dup
      p e.getbyte(2), e.getbyte(-2), e.getbyte(-3), e.setbyte(-2, 0x7a), e
      begin
        e.setbyte(2, 1)
      rescue IndexError => x
        p x.message
      end
      begin
        e.setbyte(0, 1.5)
      rescue TypeError => x
        p x.class
      end
      p e.setbyte(0, 2**64 + 0x41), e
      h = "été".dup
      p h.getbyte(0), h.getbyte(1), h.length
      h.setbyte(0, 0x41)
      p h.length, h.valid_encoding?
      p e.setbyte(1, -(2**64) + 0x42), e, e.setbyte(1.9, 0x43), e
      [[5, 1], [0, nil], [nil, 1], [0, Object.new]].each do |at, byte|
        "x".freeze.setbyte(at, byte)
      rescue IndexError, TypeError, FrozenError => x
        p x
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "HELLO"
      true
      true
      false
      false
      [97, 255, 99]
      "abc"
      true
      "Xyz"
      -1
      65
      "Ab"
      "b"
      "a"
      "abc"
      "aBc"
      "can't modify frozen String: \"abc\""
      nil
      97
      nil
      122
      "zb"
      "index 2 out of string"
      18446744073709551681
      "Ab"
      195
      169
      3
      4
      false
      -18446744073709551550
      "AC"
      67
      "AC"
      #<IndexError: index 5 out of string>
      #<TypeError: no implicit conversion of nil into Integer>
      #<TypeError: no implicit conversion from nil to integer>
      #<TypeError: no implicit conversion of Object into Integer>
    OUT
  end

  it "a fixnum and a flonum are negated in place, and every other value is sent -@" do
    result = ze0(<<~'RUBY')
      # `-x` on a fixnum and on a flonum in place: the fixnum ends, the zeros,
      # the flonum whose negation is no flonum, a heap Float, NaN and the
      # infinities, a Rational, and both methods once redefined.
      def neg(x) = -x
      min = -(2**62)
      p neg(5), neg(-5), neg(0), neg(min), neg(min).class, neg(2**62 - 1), neg(2**64)
      p neg(1.5), neg(-2.25), neg(0.0), neg(-0.0), 1 / neg(0.0), 1 / neg(-0.0)
      hole = [0xB000000000000000].pack("Q<").unpack1("E")
      p neg(hole), neg(neg(hole)), neg(hole) == -hole, neg(1e300), neg(-1e-300)
      p neg(Float::INFINITY), neg(-Float::INFINITY), neg(Float::NAN).nan?, neg(3r / 4)
      x = 0.0
      i = 0
      while i < 1000
        x = -x + 1.0
        i += 1
      end
      p x
      class Float
        def -@ = :float_neg
      end
      p neg(1.5), neg(0.0), neg(2)
      class Integer
        def -@ = :int_neg
      end
      p neg(2), neg(1.5)
    RUBY

    _(result).must_answer <<~'OUT'
      -5
      5
      0
      4611686018427387904
      Integer
      -4611686018427387903
      -18446744073709551616
      -1.5
      2.25
      -0.0
      0.0
      -Infinity
      Infinity
      1.727233711018889e-77
      -1.727233711018889e-77
      true
      -1.0e+300
      1.0e-300
      -Infinity
      Infinity
      true
      (-3/4)
      0.0
      :float_neg
      :float_neg
      -2
      :int_neg
      :float_neg
    OUT
  end

  it "a new at the site allocates and sends initialize as Class#new does, whatever the class makes of either" do
    result = ze0(<<~'RUBY')
      # `new` at the site: every count of arguments, keywords, a splat, a
      # private initialize, a class's own new, an initialize redefined after
      # the site ran, a raise inside it, and a class with no allocator.
      class P0; def initialize = (@a = :none); attr_reader :a; end
      class P2; def initialize(x, y) = (@a = [x, y]); attr_reader :a; end
      class P5; def initialize(a, b, c, d, e) = (@a = a + b + c + d + e); attr_reader :a; end
      class Kw; def initialize(x, k: 1, **rest) = (@a = [x, k, rest]); attr_reader :a; end
      class Opt; def initialize(x = 7, *more) = (@a = [x, more]); attr_reader :a; end
      class Own
        def self.new(*args) = "own new #{args.inspect}"
      end
      class Kid < P2; end
      class Plain; end
      def make(k, *args) = k.new(*args)
      p P0.new.a, P2.new(1, 2).a, P5.new(1, 2, 3, 4, 5).a, Kw.new(1, k: 2, z: 3).a, Kw.new(0).a
      p Opt.new.a, Opt.new(1, 2, 3).a, Own.new(1), Kid.new(3, 4).a, Plain.new.class
      args = [8, 9]
      p P2.new(*args).a, make(P2, 5, 6).a, make(Own, 5).class, make(Kid, 1, 1).class
      p P2.new(1, 2).a.equal?(P2.new(1, 2).a)
      begin
        P2.new(1)
      rescue ArgumentError => e
        p e.message
      end
      begin
        Plain.new(1)
      rescue ArgumentError => e
        p e.message
      end
      class Boom
        def initialize(x)
          raise "boom #{x}" if x > 1
        end
      end
      3.times do |i|
        Boom.new(i)
        p i
      rescue => e
        p e.message, e.backtrace.first[/in '.*'/], e.backtrace[1][/in '.*'/]
      end
      objs = 3.times.map { |i| P2.new(i, i) }
      class P2
        def initialize(x, y) = (@a = x * y)
      end
      objs += 3.times.map { |i| P2.new(i, 3) }
      p objs.map(&:a)
      class Plain
        private_class_method :new
      end
      begin
        Plain.new
      rescue NoMethodError => e
        p e.message
      end
      class Class
        alias_method :old_new, :new
        def new(*args) = "Class#new of #{self} #{args.inspect}"
      end
      p P0.new, P2.new(1, 2)
      class Class
        alias_method :new, :old_new
      end
      p P0.new.a
      begin
        Integer.new
      rescue NoMethodError => e
        p e.message
      end
      S = Struct.new(:x, :y)
      D = Data.define(:x)
      p S.new(1, 2).to_a, D.new(x: 1).x, Class.new(Array).new(2, 0)
      GC.start
      many = 20_000.times.map { |i| P2.new(i, 1) }
      GC.start
      p many.sum(&:a), many.last.a
    RUBY

    _(result).must_answer <<~'OUT'
      :none
      [1, 2]
      15
      [1, 2, {z: 3}]
      [0, 1, {}]
      [7, []]
      [1, [2, 3]]
      "own new [1]"
      [3, 4]
      Plain
      [8, 9]
      [5, 6]
      String
      Kid
      false
      "wrong number of arguments (given 1, expected 2)"
      "wrong number of arguments (given 1, expected 0)"
      0
      1
      "boom 2"
      "in 'Boom#initialize'"
      "in 'block in <main>'"
      [[0, 0], [1, 1], [2, 2], 0, 3, 6]
      "private method 'new' called for class Plain"
      "Class#new of P0 []"
      "Class#new of P2 [1, 2]"
      :none
      "undefined method 'new' for class Integer"
      [1, 2]
      1
      [0, 0]
      199990000
      19999
    OUT
  end

  it "a relation over plain reads in a test branches on the comparison, and answers as the call does past the road" do
    result = ze0(<<~'RUBY')
      # A relation over plain reads as a test: fixnums, flonums, the two
      # mixed, a bignum, NaN, nil and a String, in `if`, `unless`, `while`,
      # `until`, a ternary and `elsif`; under a refinement; and once
      # Integer's and Float's relations are redefined.
      def rel(a, b)
        [a < b ? :lt : :no, a <= b ? :le : :no, (:gt if a > b), (:ge unless !(a >= b)), a == b ? :eq : :ne, a != b ? :ne : :eq]
      end
      p rel(1, 2), rel(2, 2), rel(3, 2), rel(-(2**62), 2**62 - 1)
      p rel(1.5, 2), rel(2, 1.5), rel(2.0, 2), rel(0.0, -0.0), rel(2**64, 1), rel(1, 2**64)
      nan = Float::NAN
      p rel(nan, 1.0), rel(1, nan), rel(nan, nan)
      p rel("a", "b"), rel("b", "b")
      begin
        1 < nil ? 1 : 2
      rescue ArgumentError => e
        p e.message
      end
      i = 0
      n = 5
      s = []
      while i < n
        s << i
        i += 1
      end
      until i <= 0
        i -= 2
      end
      p s, i
      x = 7
      r = if x < 5 then :small elsif x <= 7 then :seven else :big end
      p r
      module Backwards
        refine Integer do
          def <(other) = other.to_s < to_s
        end
      end
      module UseIt
        using Backwards
        def self.lt(a, b) = a < b ? :yes : :no
      end
      p UseIt.lt(9, 10), UseIt.lt(10, 9), 9 < 10 ? :yes : :no
      class Integer
        def <(other) = :redefined
        def ==(other) = false
      end
      class Float
        def <=(other) = nil
      end
      p(3 < 2 ? :truthy : :falsy, 2 == 2 ? :eq : :ne, 1.5 <= 2.5 ? :le : :nil)
    RUBY

    _(result).must_answer <<~'OUT'
      [:lt, :le, nil, nil, :ne, :ne]
      [:no, :le, nil, :ge, :eq, :eq]
      [:no, :no, :gt, :ge, :ne, :ne]
      [:lt, :le, nil, nil, :ne, :ne]
      [:lt, :le, nil, nil, :ne, :ne]
      [:no, :no, :gt, :ge, :ne, :ne]
      [:no, :le, nil, :ge, :eq, :eq]
      [:no, :le, nil, :ge, :eq, :eq]
      [:no, :no, :gt, :ge, :ne, :ne]
      [:lt, :le, nil, nil, :ne, :ne]
      [:no, :no, nil, nil, :ne, :ne]
      [:no, :no, nil, nil, :ne, :ne]
      [:no, :no, nil, nil, :ne, :ne]
      [:lt, :le, nil, nil, :ne, :ne]
      [:no, :le, nil, :ge, :eq, :eq]
      "comparison of Integer with nil failed"
      [0, 1, 2, 3, 4]
      -1
      :seven
      :yes
      :no
      :yes
      :truthy
      :ne
      :nil
    OUT
  end

  it "a def that begins with a pure test is answered at the site on that arm, and called on every other" do
    result = ze0(<<~'RUBY')
      # A def whose first decision is pure is answered at the site on that
      # arm: a recursion's leaves, a guard clause, operands past the fixnums,
      # a redefined operator, a redefined def, and a receiver of another class.
      def fib(n)
        if n < 2
          n
        else
          fib(n - 1) + fib(n - 2)
        end
      end
      def tak(x, y, z) = y < x ? tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y)) : z
      def guarded(a, b)
        return a if a == b
        return :nil_b if b.nil?
        [a, b].max
      end
      def deep(n) = n == 0 ? :bottom : deep(n - 1)
      p fib(20), tak(12, 6, 0), tak(1, 2, 2**70), tak(2**70, 2**71, 3), guarded(2**70, 2**70)
      p fib(1.5), fib(0.5), fib(-3)
      p guarded(1, 1), guarded(1, nil), guarded(3, 4), guarded(:x, :x), guarded("a", "a".dup)
      p deep(5000)
      begin
        deep(10_000_000)
      rescue SystemStackError => e
        p e.class
      end
      class Integer
        alias_method :lt, :<
        def <(other) = lt(other)
      end
      p fib(15)
      class Integer
        def <(other) = true
      end
      p fib(10)
      class Integer
        alias_method :<, :lt
      end
      def fib(n) = n < 2 ? :leaf : [fib(n - 1), fib(n - 2)].size
      p fib(5)
      class Other
        def fib(n) = :other
        def go = fib(1)
      end
      p Other.new.go, send(:fib, 1)
    RUBY

    _(result).must_answer <<~'OUT'
      6765
      1
      1180591620717411303424
      3
      1180591620717411303424
      1.5
      0.5
      -3
      1
      :nil_b
      4
      :x
      "a"
      :bottom
      SystemStackError
      610
      10
      2
      :other
      :leaf
    OUT
  end
end
