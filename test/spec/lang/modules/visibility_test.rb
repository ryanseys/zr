# frozen_string_literal: true

require "spec_helper"

describe "Modules: visibility" do
  it "module_function with a name promotes an instance method already defined" do
    result = zr(<<~'RUBY')
      # `module_function :name` (argument form) promotes an already-defined
      # instance method to a module (class) method callable as M.name.
      module M
        def which(x)
          return x if x == "found"
          nil
        end
        module_function :which

        def exist?(x)
          !which(x).nil?
        end
        module_function :exist?
      end

      puts M.exist?("found")
      puts M.exist?("missing")
      puts M.which("found")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      found
    OUT
  end

  it "issue module function dynamic class body" do
    result = zr(<<~'RUBY')
      # The bare `module_function` directive (no args) is supposed to turn
      # subsequently defined methods into module functions, but this only takes
      # effect in a literal `module ... end` body -- inside a `Module.new { ... }`
      # block the resulting method isn't callable on the module itself.
      m = Module.new do
        module_function

        def helper
          "helped"
        end
      end
      p m.helper
    RUBY

    _(result).must_answer "\"helped\"\n"
  end

  it "module function can call another modules function" do
    result = zr(<<~'RUBY')
      # Pre-existing gap found by 14.2's cross-package test: module-function
      # bodies live inside a generated `pub mod` (a real child module), so a
      # reference to a sibling top-level module didn't resolve. One file, no
      # packages needed.

      module A
        def self.f
          41
        end
      end
      module B
        def self.g
          A.f + 1
        end
      end
      puts B.g
    RUBY

    _(result).must_answer "42\n"
  end

  it "module function in reopened body" do
    result = zr(<<~'RUBY')
      # `module_function` in a REOPENED module body. A module first named by a
      # version file and then filled in (the shape every gem has) gets module
      # functions, so `M.helper(x)` works.
      module M
        VERSION = "1"
      end
      module M
        module_function
        def valid?(x)
          !x.nil?
        end
        def twice(x)
          x * 2
        end
      end
      module M
        def named(x)
          "n#{x}"
        end
        module_function :named
      end
      p M.valid?("a")
      p M.twice(3)
      p M.named(1)
      p M::VERSION

      module N
        def self.direct = 1
      end
      module N
        module_function
        def mf = 2
      end
      p [N.direct, N.mf]

      class Includer
        include M
        def call_it = valid?("z")
      end
      p Includer.new.call_it
    RUBY

    _(result).must_answer <<~'OUT'
      true
      6
      "n1"
      "1"
      [1, 2]
      true
    OUT
  end

  it "module function in runtime branch" do
    result = zr(<<~'RUBY')
      # `module_function` mode applies to a `def` inside a RUNTIME-undecidable
      # branch when the branch executes -- rspec-support's
      # `RubyFeatures.ripper_supported?` sits under `if ripper_requirable`.
      # Both halves must exist: the public module method and the private
      # instance method an includer calls bare.
      module M
        module_function
        ok = begin
          require "definitely_not_a_real_feature"
          true
        rescue LoadError
          false
        end
        if ok
          def pick = "then branch"
        else
          def pick = "else branch"
        end
      end
      p M.pick
      class K
        include M
        def call_pick = pick
      end
      p K.new.call_pick
      begin
        K.new.pick
      rescue NoMethodError => e
        puts "explicit receiver: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "else branch"
      "else branch"
      explicit receiver: NoMethodError
    OUT
  end

  it "module function include" do
    result = zr(<<~'RUBY')
      module MF
        module_function
        def helper(x); x * 2; end
        def greet; "hi"; end
      end
      class Use
        include MF
        def go; helper(3); end
        def hello; greet; end
      end
      p Use.new.go
      p Use.new.hello
      p MF.helper(3)
      p MF.greet

      module MF2
        def named(x); x + 1; end
        module_function :named
      end
      class Use2
        include MF2
        def go; named(1); end
      end
      p Use2.new.go
      p MF2.named(1)

      module Util
        module_function
        def twice(n); n * 2; end
      end
      class Base
        include Util
      end
      class Child < Base
        def go; twice(5); end
      end
      p Child.new.go

      module Sh
        module_function
        def label; "mod"; end
      end
      class Own
        include Sh
        def label; "own"; end
        def go; label; end
      end
      p Own.new.go
    RUBY

    _(result).must_answer <<~'OUT'
      6
      "hi"
      6
      "hi"
      2
      2
      10
      "own"
    OUT
  end

  it "module function is callable via its own def self" do
    result = zr(<<~'RUBY')
      module Utility
        def self.triple(x)
          x * 3
        end
      end
      puts Utility.triple(4)
    RUBY

    _(result).must_answer "12\n"
  end

  it "module function namespace" do
    result = zr(<<~'RUBY')
      # `module_function` in a module body installs the subsequent
      # `def name` as both an instance method (for include-mixin)
      # and a class method (`Mod.name`). This test uses only the
      # class-method form.
      #
      # A bare class ref (`Box.new`) in any method body inside a module
      # resolves through the lexical scope, to `Outer::Box`. This is
      # also true without `module_function`.

      module Outer
        module Helper
          module_function
          def small;  [1, 2, 3]; end
          def medium; [4, 5, 6, 7]; end
        end

        class Conf
          def initialize(flag)
            @flag = flag
            @arr = []
            @arr << 0    # force heap layout
          end
          attr_reader :flag
        end

        class Box
          def initialize(conf)
            @c = conf
            @arr = []
            @arr << 0
          end
          attr_reader :c
        end

        module Builder
          # `def self.X` form — the bare `Box.new` inside walks the
          # lexical scope to resolve `Outer_Box`.
          def self.make(conf)
            Box.new(conf)
          end
        end
      end

      # module_function dispatch.
      puts Outer::Helper.small.length    # 3
      puts Outer::Helper.medium.length   # 4

      # Module class method body that references a sibling class
      # bare-named.
      b = Outer::Builder.make(Outer::Conf.new(true))
      puts b.c.flag                       # true
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      true
    OUT
  end

  it "module function private receiver" do
    result = zr(<<~'RUBY')
      # A `module_function` instance copy is PRIVATE, so an explicit receiver must
      # raise NoMethodError -- including a builtin-derived method reached through
      # an explicit-receiver call. `respond_to?` says false,
      # `private_method_defined?` says true, and `public_send` raises correctly.
      #
      # Predates the module_function conversion -- `5.puts("x")` has always answered
      # where ruby raises, for the same reason.

      class Host
        include Process
      end

      begin
        Host.new.pid
        puts "no raise"
      rescue NoMethodError => e
        puts e.message
      end

      begin
        5.puts("x")
        puts "no raise"
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      private method 'pid' called for an instance of Host
      private method 'puts' called for an instance of Integer
    OUT
  end
end
