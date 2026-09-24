# frozen_string_literal: true

require "spec_helper"

describe "Guards: dispatch" do
  it "case guard defines a nested conditional class" do
    result = zr(<<~'RUBY')
      module Host
      end
      def engine = "native"
      case engine
      when "java"
        module Host
          class Backend
            def id = "j"
          end
        end
      else
        module Host
          class Backend
            def id = "n"
          end
        end
      end
      puts Host.constants.sort.inspect
      puts Host::Backend.new.id
      puts defined?(Host::Backend)
      h = Host::Backend
      puts h.instance_method(:id).owner
      puts h.new.respond_to?(:id)
    RUBY

    _(result).must_answer <<~'OUT'
      [:Backend]
      n
      constant
      Host::Backend
      true
    OUT
  end

  it "case in guard and class precedence" do
    result = zr(<<~'RUBY')
      class Classifier
        def classify(v)
          case v
          in Integer => n if n % 2 == 0
            "even int #{n}"
          in Integer
            "odd int"
          in String
            "string"
          else
            "other"
          end
        end
      end
      c = Classifier.new
      puts c.classify(4)
      puts c.classify(3)
      puts c.classify("hi")
      puts c.classify(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      even int 4
      odd int
      string
      other
    OUT
  end

  it "class body guard asks about the class" do
    result = zr(<<~'RUBY', files: beside("class_body_guard/ext.rb", "class_body_guard/plat.rb"))
      # A guard the SOURCE wrote inside a class body asks about the CLASS, and runs
      # where it is written -- inside the class-body frame, with `self` bound to the
      # class.
      #
      # Zeo lifts a class body's sole `if` statement back out into the enclosing
      # scope, because analyze SYNTHESIZES exactly that shape when it pushes a
      # `class X ... end if cond` guard into the body: there the condition was
      # written outside, and its locals live outside. A guard the source wrote
      # inside the body is indistinguishable by shape, so it was lifted too -- and
      # then `self` was the enclosing module rather than the class, so every
      # `respond_to?` / `const_defined?` probe asked about the wrong object.
      #
      # Bundler's `rubygems_ext.rb` is written this way: `class Platform; unless
      # respond_to?(:generic)` guards twelve constants that RubyGems already
      # defines. Asked of `Gem` instead of `Gem::Platform` the probe answered false,
      # so `require "bundler"` redefined all twelve and printed 24 warnings ruby
      # does not.

      require_relative "class_body_guard/ext"

      p Gm::Plat::WIDTH
      p Gm::Plat::HEIGHT
      p Gm::Plat.constants.sort
      p Gm::Plat.generic("x")
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      [:HEIGHT, :WIDTH]
      "x"
    OUT
  end

  it "class body guard runs in the enclosing scope" do
    result = zr(<<~'RUBY')
      # A trailing `if`/`unless` on a `class` keyword belongs to the ENCLOSING
      # scope, not to the class body: ruby evaluates it there (a raise inside one
      # reports the enclosing frame, never `<class:X>`), and the locals it reads are
      # the enclosing scope's. zeo lifts a class body to its own function, so the
      # guard has to stay outside it.

      on = true

      class String
        def zeo_probe = "string probed"
      end if on

      p "x".zeo_probe

      # `unless` puts the body in the other branch and runs when the guard is FALSE.
      off = false

      class Symbol
        def zeo_probe = "symbol probed"
      end unless off

      p :s.zeo_probe

      # The guard is an ordinary expression, not just a bare read.
      label = "yes"

      class Integer
        def zeo_probe = "integer probed"
      end if label == "yes"

      p 1.zeo_probe

      # A guard that does NOT pass defines nothing at all.
      class NeverDefined
        def nope = 1
      end if false
      p defined?(NeverDefined)

      module NeverAModule
        def nope = 1
      end unless true
      p defined?(NeverAModule)

      # The guard runs in the ENCLOSING frame -- the label, not the line, is what
      # both backends agree on with ruby here.
      def boom = raise("guard raised")
      begin
        class Float
          def zeo_probe = 1
        end if boom
      rescue => e
        puts e.message
        puts e.backtrace.first(2).map { |l| l[/in '.*'/] }.inspect
      end

      # A class body's OWN `if` is not a guard and stays inside the body -- it
      # reads what a class body can see, which is never an enclosing local.
      FLAG = false
      class Array
        if FLAG
          def zeo_probe = "never"
        else
          def zeo_probe = "array probed"
        end
      end
      p [].zeo_probe

      # A class body's own local shadows the enclosing one rather than sharing it.
      shadowed = "outer"
      class Hash
        shadowed = "inner"
        def zeo_probe = "hash probed"
      end if on
      p shadowed
      p({}.zeo_probe)
    RUBY

    _(result).must_answer <<~'OUT'
      "string probed"
      "symbol probed"
      "integer probed"
      nil
      nil
      guard raised
      ["in 'Object#boom'", "in '<main>'"]
      "array probed"
      "outer"
      "hash probed"
    OUT
  end

  it "a guard that makes the namespace and fills it later reads the state of that moment" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # guard-compat's shape: create the namespace, then fill it in later.
      unless Object.const_defined?('Guard')
        module Guard
        end
      end
      module Guard
        module Compat
          class Plugin
            def tag = "p"
          end
        end
      end
      p Guard::Compat::Plugin.new.tag
      p Guard.instance_of?(Module)

    RUBY

    _(result).must_answer <<~'OUT'
      "p"
      true
    OUT
  end

  it "the same guard skips its branch once the name is bound" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # ...and the same guard once the name IS bound: the branch is skipped.
      module Already; end
      unless Object.const_defined?('Already')
        module Already
          LATE = :late
        end
      end
      p defined?(Already::LATE)

      unless defined?(Thor)
        class Thor
          def tag = "stub"
        end
      end
      p Thor.new.tag

    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "stub"
    OUT
  end

  it "a conjunction of defined? over a constant nothing has folds false" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # A conjunction of `defined?`s over a constant nothing in the program has:
      # the branch never runs.
      if defined?(HTTP) && defined?(HTTP::VERSION)
        module Adapter
          NOPE = 1
        end
      end
      p defined?(Adapter)

    RUBY

    _(result).must_answer <<~'OUT'
      nil
    OUT
  end

  it "a const_set pins down neither the constant it names nor the module it names it in" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # A `const_set` that pins down NEITHER the constant it names nor the module it
      # sets it on is evidence about no constant in particular. webmock's
      # `@webMockNetHTTP.const_set(c[0], c[1])` is one of these, and reading it as a
      # possible `HTTP::VERSION` left every scoped guard below it undecidable.
      class Registry; end
      into = Registry
      [["Alpha", 1]].each { |pair| into.const_set(pair[0], pair[1]) }
      p Registry::Alpha

      module HTTP; end
      if defined?(HTTP::VERSION)
        module Versioned
          NOPE = 1
        end
      end
      p defined?(Versioned)

    RUBY

    _(result).must_answer <<~'OUT'
      1
      nil
    OUT
  end

  it "Module.constants names the top level's list, and a map over it reads the same" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # `Module.constants` names the same list at the top level, and a `map` that
      # only respells each entry still holds the same names -- andand asks
      # `Module.constants.map { |c| c.to_s }.include?('BlankSlate')`.
      unless Module.constants.map { |c| c.to_s }.include?('BlankSlate')
        class BlankSlate
          def tag = "blank"
        end
      end
      p BlankSlate.new.tag

      if Module.constants.map(&:to_s).include?('String')
        module Stringy
          SEEN = true
        end
      end
      p Stringy::SEEN

    RUBY

    _(result).must_answer <<~'OUT'
      "blank"
      true
    OUT
  end

  it "Object.constants.include? asks the same question through the list" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # `Object.constants.include?` is the same question through the list -- for an
      # `Object` receiver its own constants ARE the top-level ones.
      if !Object.constants.include?(:Concurrent)
        module Concurrent
          def self.tag = "shim"
        end
      end
      p Concurrent.tag

      module Present; end
      if Object.constants.include?(:Present)
        module Present
          SEEN = true
        end
      end
      p Present::SEEN

    RUBY

    _(result).must_answer <<~'OUT'
      "shim"
      true
    OUT
  end

  it "a global nothing in the program assigns is not defined" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # A global nothing in the program assigns is not defined -- lockfile opens
      # with exactly this pair, and stamps the global on its last line. That stamp
      # is INSIDE the branch the guard controls, so at the guard it has not run:
      # same moment rule the constants above follow.
      unless(defined?($__lockfile__) or defined?(Lockfile))
        class Lockfile
          def tag = "lock"
        end
        $__lockfile__ = __FILE__
      end
      p Lockfile.new.tag
      p $__lockfile__.nil?

    RUBY

    _(result).must_answer <<~'OUT'
      "lock"
      false
    OUT
  end

  it "defined? of a literal is the string expression, so that branch always runs" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # `defined?` of a LITERAL is the string "expression", so the branch always
      # runs. faraday-stack's `if defined?("Faraday::Env")` means this, whatever
      # its author had in mind.
      if defined?("Faraday::Env")
        module Patch
          APPLIED = true
        end
      end
      p Patch::APPLIED

    RUBY

    _(result).must_answer <<~'OUT'
      true
    OUT
  end

  it "the constants the interpreter installs on Object are there before the first line" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # The interpreter installs a handful of constants on `Object` before the first
      # line runs, and no `NAME = ...` in the program says so. Scanning for one and
      # finding nothing must not read as "not defined": `defined?(RUBY_ENGINE)` is
      # "constant", and a gem that gates its whole engine-compat branch on the probe
      # takes the branch.
      #
      # Every name the runtime seeds is listed here, so a name added to one side and
      # not the other shows up as a divergence rather than as a quiet nil.
      %w[ARGF ARGV CROSS_COMPILING ENV RUBY_COPYRIGHT RUBY_DESCRIPTION RUBY_ENGINE
         RUBY_ENGINE_VERSION RUBY_PATCHLEVEL RUBY_PLATFORM RUBY_RELEASE_DATE
         RUBY_REVISION RUBY_VERSION STDERR STDIN STDOUT].each do |name|
        p [name, Object.const_defined?(name)]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["ARGF", true]
      ["ARGV", true]
      ["CROSS_COMPILING", true]
      ["ENV", true]
      ["RUBY_COPYRIGHT", true]
      ["RUBY_DESCRIPTION", true]
      ["RUBY_ENGINE", true]
      ["RUBY_ENGINE_VERSION", true]
      ["RUBY_PATCHLEVEL", true]
      ["RUBY_PLATFORM", true]
      ["RUBY_RELEASE_DATE", true]
      ["RUBY_REVISION", true]
      ["RUBY_VERSION", true]
      ["STDERR", true]
      ["STDIN", true]
      ["STDOUT", true]
    OUT
  end

  it "the mkmf gate is defined and nil before any require" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # The mkmf gate itself: defined, and nil, before any require -- CRuby sets
      # it at the VM level. A fold that scans the program for `CROSS_COMPILING =`
      # finds nothing and must still answer "constant".
      p defined?(CROSS_COMPILING)
      p CROSS_COMPILING

      p defined?(RUBY_ENGINE)
      p defined?(RUBY_VERSION)
      p defined?(RUBY_PLATFORM)
      p defined?(ENV)
      p defined?(ARGV)
      p defined?(STDOUT)
      p defined?(ARGF)
      p defined?(STDIN)
      p defined?(STDERR)
      p defined?(RUBY_PATCHLEVEL)
      p defined?(RUBY_REVISION)
      p defined?(RUBY_RELEASE_DATE)
      p defined?(RUBY_DESCRIPTION)
      p defined?(RUBY_COPYRIGHT)
      p defined?(RUBY_ENGINE_VERSION)
      p defined?(::RUBY_ENGINE)

      if defined?(RUBY_ENGINE)
        module Engine
          KNOWN = true
        end
      end
      p Engine::KNOWN

    RUBY

    _(result).must_answer <<~'OUT'
      "constant"
      nil
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      "constant"
      true
    OUT
  end

  it "the scope operator does not reach Object's constants" do
    result = zr(<<~'RUBY')
      # `defined?` and its `const_defined?` / `constants.include?` spellings ask
      # whether a name is bound YET. A definition further down the program has not
      # run, so at the guard the answer is no -- which is exactly what the
      # define-it-if-nobody-else-did idiom is written for.

      # The scope OPERATOR does not reach `Object`'s constants, so asking a real
      # namespace for one is nil -- the same rule every other qualified read follows.
      module Elsewhere; end
      p defined?(Elsewhere::RUBY_ENGINE)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
    OUT
  end

  it "defined guard dead branch" do
    result = zr(<<~'RUBY')
      # A statically-false defined?(Const) guard must fold the whole branch away:
      # the constant resolves to nothing at compile time, so the branch is dead code.
      # Shape from doom's gosu_window YJIT toggle:
      #   if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
      #     ... RubyVM::YJIT.enable ...
      #   end
      # The dead branch must neither pull its callees into emission (reachability)
      # nor be emitted itself (its body may be uncompilable, like an MRI-only hack).

      class YjitShim
      end

      # Only ever called from dead branches; `frobnicate` does not exist on
      # YjitShim, so emitting this body is a hard compile error.
      def setup_yjit_toggle
        shim = YjitShim.new
        shim.frobnicate
        puts "toggled"
      end

      def yjit_toggle
        if defined?(SomeMissingConst) && SomeMissingConst.enabled?
          SomeMissingConst.enable
          setup_yjit_toggle
          puts "on"
        end
        puts "after"
      end

      def elsif_variant(n)
        if n > 10
          puts "big"
        elsif defined?(AnotherMissingConst)
          setup_yjit_toggle
          puts "activated"
        else
          puts "small"
        end
      end

      def plain_guard
        if defined?(MissingToo::Nested)
          shim = YjitShim.new
          shim.enable_nested
          puts "unreachable"
        end
        puts "done"
      end

      # A builtin tail must not mask an unresolved parent: MissingParent does not
      # exist, so the whole path is statically false (CRuby agrees: nil).
      def qualified_tail_builtin
        if defined?(MissingParent::String)
          shim = YjitShim.new
          shim.frobnicate_qualified
          puts "unreachable"
        end
        puts "qualified done"
      end

      def nested_missing_root
        if defined?(MissingRoot::Sub::Thing) && MissingRoot::Sub::Thing.on?
          setup_yjit_toggle
          puts "nested on"
        end
        puts "nested done"
      end

      # Control: a truthy defined? over a real builtin keeps its branch.
      def known_guard
        if defined?(String)
          puts "string exists"
        else
          puts "no string"
        end
      end

      yjit_toggle
      elsif_variant(3)
      elsif_variant(42)
      plain_guard
      qualified_tail_builtin
      nested_missing_root
      known_guard
    RUBY

    _(result).must_answer <<~'OUT'
      after
      small
      big
      done
      qualified done
      nested done
      string exists
    OUT
  end

  it "defined guard over a missing constant folds its dead branch away" do
    result = zr(<<~'RUBY')
      # The dead arm references `Absent::Thing` and calls a method that doesn't
      # exist on `Shim` -- both must be eliminated, not emitted, or the program
      # fails to compile. CRuby's reachability agrees the branch never runs.

      class Shim; end
      v = defined?(Absent::Thing) ? Absent::Thing : "fallback"
      p v
      def guard
        if defined?(NoSuchFeature) && NoSuchFeature.on?
          Shim.new.method_that_does_not_exist
          "on"
        else
          "off"
        end
      end
      p guard
      p defined?(Absent::Thing)
      p defined?(String)
    RUBY

    _(result).must_answer <<~'OUT'
      "fallback"
      "off"
      nil
      "constant"
    OUT
  end

  it "defined guard static fold" do
    result = zr(<<~'RUBY')
      # A `defined?(Const)` guard over a constant that provably can't exist folds
      # the whole branch away at compile time -- the dead branch is never emitted,
      # so its body may reference the missing constant (or otherwise-uncompilable
      # code) without error, exactly as CRuby's reachability allows.
      class Config
        VERSION = "2.5"
      end

      # Live value arm chosen; the dead arm's `Config::MISSING` never evaluates.
      v = defined?(Config::MISSING) ? Config::MISSING : "1.0.0"
      p v

      # `&&` short-circuits on the missing left operand: the whole guard is
      # statically false, so `Missing.enabled?` is never reached or emitted.
      def toggle
        if defined?(MissingFeature) && MissingFeature.enabled?
          MissingFeature.enable
          "on"
        else
          "off"
        end
      end
      p toggle

      # A truthy guard keeps its branch; the resolvable constant reads normally.
      p(defined?(Config::VERSION) ? Config::VERSION : "none")

      # `defined?` on a missing constant is `nil` in value position, too.
      p defined?(Config::MISSING)
      p defined?(NoSuchName)
      p defined?(String)

      # The full core Exception tree is nameable and rescuable, including the
      # `Exception`-direct classes a bare `rescue` deliberately misses.
      [SystemExit, SignalException, Interrupt, NoMemoryError, SecurityError,
       SystemStackError].each { |k| puts "#{k} < #{k.superclass}" }

      begin
        raise SecurityError, "denied"
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "1.0.0"
      "off"
      "2.5"
      nil
      nil
      "constant"
      SystemExit < Exception
      SignalException < Exception
      Interrupt < SignalException
      NoMemoryError < Exception
      SecurityError < Exception
      SystemStackError < Exception
      SecurityError: denied
    OUT
  end

  it "folded guard still sets the match" do
    result = zr(<<~'RUBY')
      # A condition zeo folds at compile time must not eat the condition's own
      # EFFECT. `=~` writes `$~`, so `if RUBY_PLATFORM =~ /darwin|linux/` leaves a
      # match behind in ruby and the next line may read it.
      #
      # The build-gate fold (`if RUBY_PLATFORM =~ /mswin/`) is what lets a
      # windows-only file compile at all, so it stays -- the match is simply
      # re-run for its effect, which is free: the fold succeeded only because both
      # operands were static.
      #
      # A STRING LITERAL subject is not a gate. `if "ab" =~ /a/` is ordinary code,
      # and it no longer folds at all.
      p("ab" =~ /a/ ? $~[0] : nil)
      p($~ && $~[0])
      if "ab" =~ /a/
        p $~[0]
        p $1.nil?
      end
      p RUBY_PLATFORM =~ /darwin|linux/ ? $~[0].is_a?(String) : nil
      x = "cd"
      p(x =~ /c/ ? $~[0] : nil)
      p("zz" =~ /a/ ? "hit" : $~.inspect)
      p("ab".match?(/a/) ? 1 : 2)
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "a"
      "a"
      true
      true
      "c"
      "nil"
      1
    OUT
  end

  it "guard on a constant only this branch defines" do
    result = zr(<<~'RUBY')
      # `defined?`/`const_defined?` ask about a MOMENT: has this name been bound yet?
      # When the only definition of the name in the whole program is the branch the
      # guard itself decides, the answer at the guard is "not yet" -- so the `unless`
      # spelling TAKES its branch, and the `if` spelling skips one that would only
      # have reopened a class something outside the program was expected to supply.

      class Decimal
      end

      unless Object.const_defined?("Money")
        class Money < Decimal
        end
      end
      p Money.superclass

      module PG
      end

      # Nothing else defines PG::CancelConnection, so the reopening below is dead --
      # exactly as it is in a build carrying no C extension to reopen.
      if defined?(PG::CancelConnection)
        class PG::CancelConnection
          def cancel = :cancelled
        end
      end
      p defined?(PG::CancelConnection)

      # A guard the rest of the program DOES answer stays a real guard: `Decimal` is
      # defined above, so this branch is skipped and the class keeps its own name.
      unless Object.const_defined?("Decimal")
        class Decimal
          def self.name = "shadowed"
        end
      end
      p Decimal.name

      # A literal's class is fixed at compile time, and so is its name -- msgpack
      # picks between an Integer and a Fixnum reopening this way, and `Fixnum` no
      # longer exists, so the untaken branch must never be looked at.
      if 1.class.name == "Integer"
        class Reader
          def kind = :int
        end
      else
        class Reader < Fixnum
          def kind = :fixnum
        end
      end
      p Reader.new.kind
    RUBY

    _(result).must_answer <<~'OUT'
      Decimal
      nil
      "Decimal"
      :int
    OUT
  end

  it "guarded def whose guard passes still wins" do
    result = zr(<<~'RUBY')
      # A guard that PASSES still installs. Without this the rule could be
      # satisfied by never installing a guarded body at all, which is a different
      # bug wearing the same green.

      def cpu = ["arm", "64"].join
      class C
        [:tag].each { |n| attr_accessor(n) }
        def which = "real"
        def self.which = "real class method"
        if cpu == "arm64"
          def which = "taken"
          def self.which = "taken class method"
        end
      end
      puts C.new.which
      puts C.which
    RUBY

    _(result).must_answer "taken\ntaken class method\n"
  end

  it "logical pointer guard" do
    result = zr(<<~'RUBY')
      class Holder
        def initialize
          @text = nil
        end

        def attach
          @text = "hi"
        end

        def active?
          return false if @text && @text.length == 2

          true
        end
      end

      h = Holder.new
      puts h.active?
      h.attach
      puts h.active?
    RUBY

    _(result).must_answer "true\nfalse\n"
  end

  it "named build time predicate is still a build time guard" do
    result = zr(<<~'RUBY')
      # A gem that gives its build-time question a name asks it as an ordinary
      # method call -- `if Sass::Util.rbx?` -- and what sits behind the name is a
      # guard the compiler already decides. sass wraps its whole StringScanner class
      # in one, with a DIFFERENT superclass per branch, so a compiler that cannot
      # decide it registers both arms and reports a superclass mismatch for a program
      # ruby runs without complaint.

      module Engine
        extend self

        # The memoized spelling, the shape sass writes: the cache holds a constant,
        # so every call answers the same whether or not it is the first.
        def rbx?
          return @rbx if defined?(@rbx)
          @rbx = RUBY_ENGINE == "rbx"
        end

        def mri? = RUBY_ENGINE == "ruby"
      end

      if Engine.rbx?
        class Scanner < String
          def which = :rubinius
        end
      else
        class Scanner < Array
          def which = :mri
        end
      end

      p Scanner.superclass
      p Scanner.new.which

      # Only the VALUE folds. The predicate is still compiled and still callable --
      # what a decided guard drops is one call whose whole effect was to compute a
      # constant, and the memo it would have written is unobservable outside itself.
      p Engine.rbx?
      p Engine.mri?

      # `def self.x` reaches the same fold. lutaml-model gates a whole file of
      # `Mutex`/`ConditionVariable` shims on one of these.
      module Compat
        def self.opal?
          return @opal if defined?(@opal)
          @opal = RUBY_ENGINE == "opal"
        end
      end

      unless Compat.opal?
        class Native
          def which = :native
        end
      end
      p Native.new.which

      # A predicate whose body zeo cannot decide leaves its guard to run, exactly as
      # an undecidable guard written inline would.
      module Runtime
        def self.enabled? = ENV.fetch("ZR_TEST_NAMED_PREDICATE_UNSET", "off") == "on"
      end

      if Runtime.enabled?
        p :on
      else
        p :off
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      :mri
      false
      true
      :native
      :off
    OUT
  end

  it "platform guard decides at build time" do
    result = zr(<<~'RUBY')
      # Four more guard shapes that decide at compile time, each gating a NEW
      # class -- the shape that has no answer under a compile-time MRO unless
      # the condition folds:
      #   - `RUBY_PLATFORM.include?('java')` (the JRuby gate spelled without a
      #     regexp -- log4r)
      #   - `Gem.win_platform?` (chef, isomorfeus)
      #   - `X.singleton_class.method_defined?(:m)` (rbs's parser probe)
      #   - `Qualified::Path.method_defined?(:m)` (only bare names folded before)
      if RUBY_PLATFORM.include?("java")
        class JavaOnly; end
      end
      puts defined?(JavaOnly).inspect

      unless Gem.win_platform?
        class NotWindows
          def hi
            "posix"
          end
        end
      end
      puts NotWindows.new.hi

      module Deep
        class Thing
          def present; end
        end
      end

      if Deep::Thing.singleton_class.method_defined?(:new)
        class SawTheSingleton
          def hi
            "singleton fold"
          end
        end
      end
      puts SawTheSingleton.new.hi

      if Deep::Thing.method_defined?(:present)
        class SawTheQualifiedPath
          def hi
            "qualified fold"
          end
        end
      end
      puts SawTheQualifiedPath.new.hi
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      posix
      singleton fold
      qualified fold
    OUT
  end

  it "pruned guard still binds its locals" do
    result = zr(<<~'RUBY')
      # Ruby's parser creates a local binding for an assignment it never runs, so
      # `if false; x = 1; end; p x` answers nil rather than raising NameError. A
      # class-body guard zeo decides at compile time is spliced away entirely --
      # and the binding has to survive it, because the line after usually reads
      # the name. resolv.rb's `DefaultFileName = hosts || '/etc/hosts'` sits right
      # under the windows-only `if` that assigns `hosts`.
      class Hosts
        if RUBY_PLATFORM =~ /mswin/ || RbConfig::CONFIG["host_os"] =~ /mswin/
          path = "C:/windows/system32/drivers/etc/hosts"
        end
        DEFAULT = path || "/etc/hosts"

        # A name the body already assigned KEEPS its value: the dead branch binds,
        # it does not reset.
        kept = 5
        if RUBY_PLATFORM =~ /mswin/
          kept = 9
        end
        KEPT = kept

        # The `case` fold answers the same way.
        case RbConfig::CONFIG["host_os"]
        when /mswin/ then flavour = :windows
        end
        FLAVOUR = flavour.inspect

        # The branch that IS taken assigns for real.
        if RUBY_PLATFORM =~ /darwin|linux|bsd/
          live = :unix
        else
          live = :other
        end
        LIVE = live
      end

      p Hosts::DEFAULT
      p Hosts::KEPT
      p Hosts::FLAVOUR
      p Hosts::LIVE
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      "/etc/hosts"
      5
      "nil"
      :unix
      still running
    OUT
  end

  it "reload guard written with a bang" do
    result = zr(<<~'RUBY')
      # A gem's version file wraps its own definitions in a reload guard, so that
      # requiring it twice by two spellings is harmless. `unless defined?(X)` already
      # folded; `if !defined?(X)` -- the commoner spelling -- did not, because the
      # negation was only ever handed to the weaker of the two guard folders.

      if !defined?(Addressable::VERSION)
        module Addressable
          module VERSION
            STRING = "2.9.0"
          end
        end
      end
      p Addressable::VERSION::STRING

      # `not` is the same operator, and the guarded constant may be a plain value.
      if not defined?(Excon::VERSION)
        module Excon
          VERSION = "1.2.3"
        end
      end
      p Excon::VERSION

      # It is a REAL guard: a second copy of the same file must not redefine.
      if !defined?(Addressable::VERSION)
        module Addressable
          module VERSION
            STRING = "clobbered"
          end
        end
      end
      p Addressable::VERSION::STRING

      # `||` decides as soon as a branch does, the way `&&` already did.
      if defined?(Nowhere::AtAll) || !defined?(Kaboom)
        class Kaboom
          def hi = :hi
        end
      end
      p Kaboom.new.hi

      # ... and short-circuits: the right operand is never consulted when the left
      # has already settled it.
      if !defined?(Kaboom) && defined?(Nowhere::AtAll)
        class NeverBuilt; end
      end
      p defined?(NeverBuilt)
    RUBY

    _(result).must_answer <<~'OUT'
      "2.9.0"
      "1.2.3"
      "2.9.0"
      :hi
      nil
    OUT
  end

  it "ruby engine guard" do
    result = zr(<<~'RUBY')
      # A gem writes `if RUBY_ENGINE == "truffleruby"` around a whole `class`/`def`
      # to pick an engine-specific implementation (prism's serializer does exactly
      # this for its StringIO). zeo reports MRI's own identity, so the guard decides
      # at compile time and only the CRuby branch is registered -- without the fold,
      # the class in the untaken branch reached codegen as a definition the analyze
      # walk never registered.
      if RUBY_ENGINE == "truffleruby"
        class Fast
          def who = :truffle
        end
      else
        Fast = ::String
      end
      p Fast
      p RUBY_ENGINE

      if RUBY_ENGINE == "ruby"
        def picked = :mri
      else
        def picked = :other
      end
      p picked

      # The negated spelling decides too.
      p(RUBY_ENGINE != "jruby")

      # The same gate inside a CLASS BODY. Until `branch_has_top_defs` counted a
      # `def`, a guard whose branches held only methods never folded: both
      # registered, and the one written last won -- so this answered `:other`.
      class Engine
        if RUBY_ENGINE == "truffleruby"
          def which = :truffle
        else
          def which = :mri
        end

        if RUBY_ENGINE == "ruby"
          def self.built = :here
        else
          def self.built = :elsewhere
        end
      end
      p Engine.new.which
      p Engine.built

      # A guard whose predicate zeo cannot decide keeps BOTH branches and settles it
      # at runtime, which is what protects every gate this fold does not reach.
      class Dynamic
        if ENV.fetch("ZR_TEST_NOT_SET", "") == "yes"
          def pick = :env
        else
          def pick = :default
        end
      end
      p Dynamic.new.pick
    RUBY

    _(result).must_answer <<~'OUT'
      String
      "ruby"
      :mri
      true
      :mri
      :here
      :default
    OUT
  end

  it "string guard family" do
    result = zr(<<~'RUBY')
      # The String rows whose guard or option was remembered rather than
      # structural, in one place.
      #
      # Four of them share a shape worth naming: the answer was computed over a
      # TRANSFORMED copy of the receiver and then reported as if it were the
      # original.
      #
      #   * `match(pattern, pos)` ran over a SLICE, so the MatchData reported
      #     offsets relative to it -- `.begin(0)` said 1 where ruby says 4, and
      #     `pre_match` lost everything before `pos`. The engine takes a start
      #     offset directly, which is what CRuby uses.
      #   * `scrub` TRANSCODED to its own encoding, which has nowhere to put a
      #     block and re-encodes every valid character on the way. It now walks
      #     the decoded spans and touches only the invalid runs.
      #   * `encode` to an unknown encoding resolved each name as it read it, so
      #     it reported an ArgumentError about ONE name where ruby reports a
      #     converter failure naming the PAIR, source first, both raw as given.
      #   * `newline:` as a SYMBOL was simply absent, so `encode(newline: :crlf)`
      #     converted nothing. Its errors are asymmetric and copied that way: a
      #     bad symbol is named, a non-symbol value is not.
      #
      # `force_encoding` is the fifth and simplest: it needed the frozen guard
      # every other mutator has, BEFORE any comparison -- ruby refuses even when
      # the new encoding equals the current one.

      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { "a".freeze.force_encoding("BINARY") }
      show { "a".freeze.force_encoding("UTF-8") }
      show { (+"a").force_encoding("BINARY").encoding.to_s }
      show { "hello world".match(/o/, 3)&.begin(0) }
      show { "hello world".match(/o/, 5)&.begin(0) }
      show { "hello world".match?(/o/, 5) }
      show { "hello world".index("o", 5) }
      show { "hello world".match(/(w)(o)/, 3)&.captures }
      show { "hello world".match(/o/, 3)&.[](0) }
      show { "hello world".match(/o/, 3)&.post_match }
      show { "hello world".match(/o/, 3)&.pre_match }
      show { "\xE3\x81\x82ab\xFFcd".dup.force_encoding("UTF-8").scrub { |b| "<#{b.bytes.map { |x| x.to_s(16) }.join}>" } }
      show { "\xFF\xFEok".dup.force_encoding("UTF-8").scrub("?") }
      show { (+"\xFFok").force_encoding("UTF-8").scrub! { |b| "!" } }
      show { "a".encode("NoSuchEncoding") }
      show { "a".encode("NoSuchTarget", "NoSuchSource") }
      show { "a".encode("UTF-8", "NoSuchSource") }
      show { Encoding.find("NoSuchEncoding") }
      show { "a\r\nb".encode("UTF-8", newline: :universal) }
      show { "a\nb".encode("UTF-8", newline: :crlf) }
      show { "a\nb".encode("UTF-8", newline: :cr) }
      show { "a\nb".encode("UTF-8", newline: :nope) }
      show { "a\nb".encode("UTF-8", newline: 1) }
      show { "a\nb".encode("UTF-8", crlf_newline: true) }
      show { "a\nb".encode("UTF-8", cr_newline: true) }
      show { "a\r\nb".encode("UTF-8", universal_newline: true) }
      e = "\xC6\xFC".dup.force_encoding("EUC-JP")
      show { e.casecmp("x") }
      show { e.casecmp?("x") }
      show { e =~ /x/ }
      show { e.match?(/x/) }
      show { e.match(/x/) }
      show { e.index("x") }
      show { e.gsub("x", "y") }
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError: can't modify frozen String: "a"
      FrozenError: can't modify frozen String: "a"
      "ASCII-8BIT"
      4
      7
      true
      7
      ["w", "o"]
      "o"
      " world"
      "hell"
      "あab<ff>cd"
      "??ok"
      "!ok"
      Encoding::ConverterNotFoundError: code converter not found (UTF-8 to NoSuchEncoding)
      Encoding::ConverterNotFoundError: code converter not found (NoSuchSource to NoSuchTarget)
      Encoding::ConverterNotFoundError: code converter not found (NoSuchSource to UTF-8)
      ArgumentError: unknown encoding name - NoSuchEncoding
      "a\nb"
      "a\r\nb"
      "a\rb"
      ArgumentError: unexpected value for newline option: nope
      ArgumentError: unexpected value for newline option
      "a\r\nb"
      "a\rb"
      "a\nb"
      1
      false
      nil
      false
      nil
      nil
      "\x{C6FC}"
    OUT
  end

  it "undecidable class body guard still runs its directives" do
    result = zr(<<~'RUBY')
      # A class-body `if` whose condition is a real RUNTIME question -- reading ENV,
      # say -- cannot be folded away, so both branches survive to run at the class's
      # definition site. A `def` in one already had its own conditional registration
      # and its own runtime emission; every OTHER definition-level directive had none,
      # and reached codegen as "a definition-level construct used as a VALUE".
      #
      # ruby_parser closes with exactly this: `if ENV["RP_LINENO_DEBUG"] then class
      # RubyLexer; alias old_lineno= lineno=; ...`, a debug hook nobody can decide at
      # compile time.

      module Extra
        def extra = :mixed_in
      end

      module Front
        def size = "front(#{super})"
      end

      class L
        def size = 1
        def wide = :wide
        def narrow = :narrow
      end

      # `ENV["ZR_TEST_UNSET_AT_BUILD"]` is nil, so the branch does not run -- but it still
      # has to COMPILE, and the class must come out untouched.
      if ENV["ZR_TEST_UNSET_AT_BUILD"] then
        class L
          alias old_size size
          include Extra
          prepend Front
          private :wide
          undef narrow
          module_function :wide
        end
      end

      p L.new.size
      p [L.new.respond_to?(:old_size), L.include?(Extra), L.ancestors.first]
      p [L.new.respond_to?(:wide), L.new.respond_to?(:narrow)]

      # The same directives under a guard that is decidably TRUE take effect, so the
      # two halves are not just "compiles and does nothing".
      class R
        def size = 1
        def wide = :wide
      end

      if RUBY_VERSION then
        class R
          alias old_size size
          include Extra
          private :wide
        end
      end

      p [R.new.old_size, R.new.extra, R.include?(Extra)]
      p [R.new.respond_to?(:wide), R.new.respond_to?(:wide, true)]

      # A nested `if` inside the branch is rewritten the same way, at any depth.
      class N
        def a = :a
      end

      if ENV["ZR_TEST_UNSET_AT_BUILD"] then
        class N
          if ENV["ZR_TEST_ALSO_UNSET"] then
            alias b a
          else
            alias c a
          end
        end
      end

      p [N.new.respond_to?(:b), N.new.respond_to?(:c)]

      # ---------------------------------------------------------------------------
      # A version gate spelled as an ANCHORED regexp is a build-time question, the
      # same one `RUBY_VERSION < "2.0"` asks. ipaddress guards its 1.8 compatibility
      # shims with `if RUBY_VERSION =~ /^1\.8/`, and left undecided the whole branch
      # -- `class Hash; alias :key :index; end` -- had to compile.

      if RUBY_VERSION =~ /^1\.8/
        class Hash
          alias key index
        end
      end

      p({ a: 1 }.respond_to?(:key))

      # The anchor is what makes it decidable: `^` is a prefix test, `$` a suffix,
      # both together equality, and no anchor at all a substring search.
      p [(RUBY_VERSION =~ /^4\./) ? :yes : :no, (RUBY_VERSION =~ /^1\./) ? :yes : :no]
      p [(RUBY_ENGINE =~ /^ruby$/) ? :yes : :no, (RUBY_ENGINE =~ /^rub$/) ? :yes : :no]
      p [(RUBY_ENGINE =~ /ruby|jruby/) ? :yes : :no, (RUBY_ENGINE =~ /jruby|rbx/) ? :yes : :no]

      # An escaped dot means a real dot -- `/^1\.8/` must not match "148".
      p ["1.8.7" =~ /^1\.8/, "148" =~ /^1\.8/, "x1.8" =~ /^1\.8/]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [false, false, L]
      [true, true]
      [1, :mixed_in, true]
      [false, true]
      [false, false]
      true
      [:yes, :no]
      [:yes, :no]
      [:yes, :no]
      [0, nil, nil]
    OUT
  end

  it "version kept as segments is still a build time guard" do
    result = zr(<<~'RUBY')
      # A gem that gates on the ruby version by SEGMENT rather than by string writes
      # the split once, names it, and indexes the name at every guard beneath. Sass
      # is the shape:
      #
      #   RUBY_VERSION = ::RUBY_VERSION.split(".").map {|s| s.to_i}
      #   def ruby1_8? = ironruby? || (RUBY_VERSION[0] == 1 && RUBY_VERSION[1] < 9)
      #
      # Three things have to hold for that to decide at build time: the split-and-map
      # has to reduce to a list, an index into the list has to reduce to a number,
      # and the module's own `RUBY_VERSION` has to SHADOW the one ruby seeds -- it is
      # a different value under the same name, and every read inside the module means
      # the shadow.

      module Semver
        extend self

        RUBY_VERSION = ::RUBY_VERSION.split(".").map { |s| s.to_i }
        ENGINE = defined?(::RUBY_ENGINE) ? ::RUBY_ENGINE : "ruby"

        # `&:to_i` is the same mapping, spelled short.
        PARTS = "10.2.30".split(".").map(&:to_i)

        def ironruby? = ENGINE == "ironruby"

        def ruby1_8?
          ironruby? || (Semver::RUBY_VERSION[0] == 1 && Semver::RUBY_VERSION[1] < 9)
        end

        def modern? = Semver::RUBY_VERSION[0] >= 4

        # A negative index counts from the end, and the last segment of the pinned
        # version is what it names.
        def patch = Semver::RUBY_VERSION[-1]
      end

      p Semver::RUBY_VERSION
      p Semver::PARTS
      p Semver::ENGINE
      p Semver.ruby1_8?
      p Semver.modern?
      p Semver.patch

      # The guard decides, so only one of these classes is ever defined -- the same
      # reading `defined?` gives.
      if Semver.ruby1_8?
        class Scanner
          def which = :legacy
        end
      else
        class Scanner
          def which = :modern
        end
      end
      p Scanner.new.which

      # A receiverless call inside the module reaches the same definition, which is
      # what lets `ruby1_8?` open with a bare `ironruby?`.
      if Semver.ironruby?
        module Iron
          HERE = true
        end
      end
      p defined?(Iron)

      # `split` keeps a leading empty field and drops the trailing ones, and `to_i`
      # reads the leading digits and stops -- so a version with a suffix still
      # answers by segment.
      module Suffixed
        PARTS = "3.4.0.rc1".split(".").map(&:to_i)
      end
      p Suffixed::PARTS
      p Suffixed::PARTS[3]

      # An index past the end is nil in ruby, so a guard over it is not a build-time
      # question at all -- it raises, exactly as it would under the interpreter.
      module Short
        PARTS = "2.1".split(".").map(&:to_i)
      end
      p Short::PARTS[2]
      begin
        Short::PARTS[2] < 5
      rescue NoMethodError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [4, 0, 6]
      [10, 2, 30]
      "ruby"
      false
      true
      6
      :modern
      nil
      [3, 4, 0, 0]
      0
      nil
      NoMethodError
    OUT
  end

  it "version number guard folds numerically" do
    result = zr(<<~'RUBY')
      # A version gate written against the NUMBER folds at compile time even when
      # the kinds mix: `RUBY_VERSION.to_f >= 2.4` (rampi), `RUBY_VERSION.to_i <
      # 3.0` (sanity-ruby). The refinement activations gems guard this way NEED
      # the fold -- a `using` cannot defer to runtime, it activates lexically.
      module Doubling
        refine Integer do
          def doubled = self * 2
        end
      end

      using Doubling if RUBY_VERSION.to_f >= 2.4
      p 21.doubled

      # The false side: the guard folds away, so the refinement never activates.
      module Halving
        refine Integer do
          def halved = self / 2
        end
      end

      using Halving if RUBY_VERSION.to_i < 3.0
      begin
        p 42.halved
      rescue NoMethodError => e
        puts e.class
      end

      # The same folds decide plain definition gates.
      if RUBY_VERSION.to_f >= 2.4
        def modern? = true
      else
        def modern? = false
      end
      p modern?
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      NoMethodError
      true
      still running
    OUT
  end
end
