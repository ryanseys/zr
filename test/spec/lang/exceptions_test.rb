# frozen_string_literal: true

require "spec_helper"

describe "Exceptions" do
  it "a block jump leaves an outer rescue its exception" do
    result = ze0(<<~'RUBY')
      # A `break`/`return` out of a block arms a signal and unwinds through the
      # landing chain, which pops `$!` itself -- the jump must not pop it too.
      def helper
        [1].each do
          begin
            raise "inner"
          rescue
            return 9
          end
        end
      end

      begin
        raise "outer"
      rescue
        r = [1].each do
          begin
            raise "nested"
          rescue
            break 7
          end
        end
        p r
        p $!.message
        p helper
        p $!.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      7
      "outer"
      9
      "outer"
    OUT
  end

  it "a core error shows only ruby frames" do
    _(ze0(<<~'RUBY', path: "lang/exceptions/a_core_error_shows_only_ruby_frames.rb").stdout).must_equal "NoMethodError: undefined method 'foo' for an instance of String\na_core_error_shows_only_ruby_frames.rb:12:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:12:Array#map\na_core_error_shows_only_ruby_frames.rb:12:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:12:<main>\nNoMethodError: undefined method 'zork' for an instance of Integer\na_core_error_shows_only_ruby_frames.rb:13:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:13:Array#each\na_core_error_shows_only_ruby_frames.rb:13:Enumerable#sort_by\na_core_error_shows_only_ruby_frames.rb:13:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:13:<main>\nArgumentError: invalid value for Integer(): \"x\"\na_core_error_shows_only_ruby_frames.rb:14:Kernel#Integer\na_core_error_shows_only_ruby_frames.rb:14:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:14:Array#map\na_core_error_shows_only_ruby_frames.rb:14:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:14:<main>\nJSON::ParserError: expected object key, got EOF at line 1 column 2\ncommon.rb:364:JSON::Ext::Parser.parse\ncommon.rb:364:JSON.parse\na_core_error_shows_only_ruby_frames.rb:15:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:15:<main>\nKeyError: key not found: :b\na_core_error_shows_only_ruby_frames.rb:16:Hash#fetch\na_core_error_shows_only_ruby_frames.rb:16:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:16:<main>\nIndexError: index 5 outside of array bounds: -1...1\na_core_error_shows_only_ruby_frames.rb:17:Array#fetch\na_core_error_shows_only_ruby_frames.rb:17:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:17:<main>\nArgumentError: comparison of Integer with String failed\na_core_error_shows_only_ruby_frames.rb:18:Array#sort\na_core_error_shows_only_ruby_frames.rb:18:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:18:<main>\nArgumentError: invalid slice size\na_core_error_shows_only_ruby_frames.rb:19:Enumerable#each_slice\na_core_error_shows_only_ruby_frames.rb:19:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:19:<main>\nArgumentError: @ outside of string\na_core_error_shows_only_ruby_frames.rb:20:String#unpack\na_core_error_shows_only_ruby_frames.rb:20:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:20:<main>\nRuntimeError: in min_by\na_core_error_shows_only_ruby_frames.rb:21:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:21:Array#each\na_core_error_shows_only_ruby_frames.rb:21:Enumerable#min_by\na_core_error_shows_only_ruby_frames.rb:21:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:21:<main>\nRuntimeError: in each\na_core_error_shows_only_ruby_frames.rb:22:block (2 levels) in <main>\na_core_error_shows_only_ruby_frames.rb:22:Hash#each\na_core_error_shows_only_ruby_frames.rb:22:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:22:<main>\nSyntaxError: (eval at lang/exceptions/a_core_error_shows_only_ruby_frames.rb:23):1: syntax errors found\n> 1 | 1 +\n    |    ^ unexpected end-of-input, assuming it is closing the parent top level context\n    |    ^ unexpected end-of-input; expected an expression after the operator\na_core_error_shows_only_ruby_frames.rb:23:Kernel#eval\na_core_error_shows_only_ruby_frames.rb:23:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:23:<main>\nArgumentError: struct size differs\na_core_error_shows_only_ruby_frames.rb:24:Struct#initialize\na_core_error_shows_only_ruby_frames.rb:24:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:24:<main>\nEncoding::ConverterNotFoundError: code converter not found (UTF-8 to NOPE)\na_core_error_shows_only_ruby_frames.rb:25:String#encode\na_core_error_shows_only_ruby_frames.rb:25:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:25:<main>\nArgumentError: min argument must be less than or equal to max argument\na_core_error_shows_only_ruby_frames.rb:26:Comparable#clamp\na_core_error_shows_only_ruby_frames.rb:26:UnboundMethod#bind_call\na_core_error_shows_only_ruby_frames.rb:26:block in <main>\na_core_error_shows_only_ruby_frames.rb:7:Object#show\na_core_error_shows_only_ruby_frames.rb:26:<main>\n"
      # An error a core method raises shows the frames of the methods the
      # program called and the C methods ruby shows, and none of the helpers
      # the runtime keeps for itself: in a block, in sort_by, in Integer(), in
      # JSON.parse, in fetch, in eval and in Comparable.
      require "json"
      def show
        yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
        puts e.backtrace_locations.map { |l| "#{File.basename(l.path)}:#{l.lineno}:#{l.label}" }
      end
      show { "a\xffb".force_encoding("UTF-8").grapheme_clusters.map { |c| c.foo } }
      show { [3, 1].sort_by { |x| x.zork } }
      show { %w[1 x].map { |v| Integer(v) } }
      show { JSON.parse("{") }
      show { {a: 1}.fetch(:b) }
      show { [1].fetch(5) }
      show { [1, "a"].sort }
      show { [1, 2].each_slice(0) }
      show { "abc".unpack("@9") }
      show { [1, 2].min_by { |x| raise "in min_by" } }
      show { {a: 1}.each { |k, v| raise "in each" } }
      show { eval("1 +") }
      show { Struct.new(:a).new(1, 2) }
      show { "x".encode("NOPE") }
      show { Comparable.instance_method(:clamp).bind_call(3, 5, 1) }

    RUBY
  end

  it "a core error shows only ruby frames pack" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb")
      # A pack or unpack that raises shows the frame of the method the program
      # called, and none of the helpers ze0 keeps for itself: CRuby does that
      # work in C, with no frame and no constant a program can see.

      def show
        yield
      rescue => e
        puts "#{e.class}: #{e.message}"
        puts e.backtrace
      end

      show { "abc".unpack("@9") }
      show { "abc".unpack1("x9") }
      show { [1].pack(1) }
      show { [1].pack("y") }
      show { "abc".unpack("m0") }
      p Object.constants.include?(:Packing)

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError: @ outside of string
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in 'String#unpack'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in '<main>'
      ArgumentError: x outside of string
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in 'String#unpack1'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in '<main>'
      TypeError: no implicit conversion of Integer into String
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in 'Array#pack'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in '<main>'
      ArgumentError: unknown pack directive 'y' in 'y'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in 'Array#pack'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in '<main>'
      ArgumentError: invalid base64
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in 'String#unpack'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in 'block in <main>'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
      lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in '<main>'
      false
    OUT
  end

  it "a cwd require that misses raises at runtime" do
    result = ze0(<<~'RUBY')
      # `require "./x"` resolves against the runtime working directory in real
      # Ruby. zeo resolves it against the requiring file's directory (the
      # deterministic analogue -- `load`'s documented rule), and a MISS defers to
      # a catchable runtime `LoadError` instead of refusing to compile: the gems
      # that write this shape only ever worked when run from the directory the
      # path assumes, and wrap it in a rescue for everywhere else.
      begin
        require "./tools/not_shipped_here"
      rescue LoadError => e
        puts "caught: #{e.class}"
      end

      begin
        require "~/nothing_under_home_either"
      rescue LoadError => e
        puts "caught: #{e.class}"
      end

      puts "still compiling"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught: LoadError
      caught: LoadError
      still compiling
    OUT
  end

  it "a def in a rescue clause is not promised" do
    result = ze0(<<~'RUBY')
      # The nested walk reaches a `rescue` clause, but reaching it is not the same as
      # promising it: the clause runs only if the body raised. The method's name goes
      # on record so a static call site stops folding, and reflection still answers
      # what actually ran.
      class Guarded
        begin
          Integer("1")
        rescue StandardError
          def only_on_failure
            :recovered
          end
        end
      end

      p Guarded.instance_methods(false)
      p Guarded.new.respond_to?(:only_on_failure)

      class Recovered
        begin
          Integer("not a number")
        rescue StandardError
          def only_on_failure
            :recovered
          end
        end
      end

      p Recovered.instance_methods(false)
      p Recovered.new.only_on_failure
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      []
      false
      [:only_on_failure]
      :recovered
    OUT
  end

  it "a definition ruby raises on is rescuable" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb")
      # `superclass mismatch` is an EXCEPTION in ruby, raised at the definition -- not
      # a broken program. A `begin ... rescue TypeError` around one catches it, prints,
      # and carries on, so a program that does that has to compile and do the same.
      #
      # Unrescued, zeo refuses the compile instead of emitting a program that aborts:
      # same problem, named earlier. That split is the whole point of this file -- the
      # rescued half is what a compile-time-only rejection would have made impossible.
      #
      # The KIND mismatch at the bottom is the same rule with a two-line message, and
      # both lines were wrong. `unmatched_redefinition` (vm_insnhelper.c) names the
      # LEAF -- `rb_id2str(id)`, the id off the cpath -- so `module Outer::Inner`
      # reports `Inner`, where zeo reported the qualified `Outer::Inner`. Then it
      # appends the previous definition's position, read from
      # `rb_const_source_location_at`: the point the CONSTANT was created, which is
      # the first declaring site, so a reopen leaves the first line standing. zeo
      # omitted that line entirely.

      class A; end
      class B < A; end

      # A cycle: `A < B` while `B < A`. Ruby raises rather than closing the loop --
      # and zeo must not build it either, because a superclass chain that points at
      # itself is an infinite walk for every pass that follows it.
      begin
        class A < B; end
      rescue TypeError => e
        p e.message
      end
      p A.superclass
      p B.superclass

      # A plain conflict: two different superclasses for one name.
      class D < String; end
      begin
        class D < Array; end
      rescue TypeError => e
        p e.message
      end
      p D.superclass

      # The definition RAISED, so it changed nothing -- the class is exactly what it
      # was, and the program keeps running.
      p D.new.class
      p B.new.is_a?(A)

      # --- the KIND mismatch, both directions -------------------------------------
      begin
        module D; end
      rescue TypeError => e
        p e.message
      end
      p D.superclass

      module M; end
      begin
        class M; end
      rescue TypeError => e
        p e.message
      end
      p M.class

      # The name reported is the LEAF, and the position is the first declaring site.
      module Outer
        class Inner; end
      end
      begin
        module Outer::Inner
        end
      rescue TypeError => e
        p e.message
      end

      # A REOPEN does not restamp the position: the line below is the one above.
      class Reopened; end
      class Reopened; end
      begin
        module Reopened; end
      rescue TypeError => e
        p e.message
      end

      # A builtin's constant carries no recorded position, and ruby prints the line
      # anyway -- with both fields empty.
      begin
        module String; end
      rescue TypeError => e
        p e.message
      end

      # A REOPEN creates no constant either, so a builtin a program reopened still
      # carries none.
      class Integer
        def doubled = self * 2
      end
      begin
        module Integer; end
      rescue TypeError => e
        p e.message
      end
      p 21.doubled

      p :after
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "superclass mismatch for class A"
      Object
      A
      "superclass mismatch for class D"
      String
      D
      true
      "D is not a module\nlang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb:33: previous definition of D was here"
      String
      "M is not a class\nlang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb:54: previous definition of M was here"
      Module
      "Inner is not a module\nlang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb:64: previous definition of Inner was here"
      "Reopened is not a module\nlang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb:74: previous definition of Reopened was here"
      "String is not a module\n:: previous definition of String was here"
      "Integer is not a module\n:: previous definition of Integer was here"
      42
      :after
    OUT
  end

  it "a definition ruby raises on raises" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_definition_ruby_raises_on_raises.rb")
      # A `class Foo` after `module Foo`, and a reopen that names a different
      # superclass, are both TypeError in ruby -- a real exception at the definition,
      # not a broken program. zeo used to REFUSE these at compile time whenever no
      # `rescue` was lexically visible inside the definition's own statement, on the
      # reasoning that an uncatchable raise aborts and a compile error naming the
      # same problem is the better version of aborting.
      #
      # Two things were wrong with that. The lexical scan cannot see the handler a
      # CALLER wraps the `require` in, which catches these perfectly well. And four
      # of the five registration sites never consulted the scan at all, so the shape
      # below -- a top-level kind collision, which is every `hola_*` tutorial gem on
      # rubygems, and a whole family of generated SDKs that declare one class name
      # under two superclasses -- could not be compiled either way.
      #
      # Both halves of the message are ruby's, including the second line, whose
      # position is the one stamped when the CONSTANT was created.
      module Foo
        X = 1
      end

      begin
        class Foo
          def never = "unreachable"
        end
      rescue TypeError => e
        puts e.message
      end

      # The definition that raised changed nothing: ruby leaves the module exactly
      # as it was.
      p Foo::X
      p Foo.instance_of?(Module)
      p Foo.respond_to?(:never)

      class Base; end
      class Other; end
      class Sub < Base; end

      begin
        class Sub < Other; end
      rescue TypeError => e
        puts e.message
      end

      p Sub.superclass
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Foo is not a class
      lang/exceptions/a_definition_ruby_raises_on_raises.rb:17: previous definition of Foo was here
      1
      true
      false
      superclass mismatch for class Sub
      Base
    OUT
  end

  it "a diverging receiver still compiles" do
    result = ze0(<<~'RUBY')
      # A receiver can DIVERGE -- `raise("x").foo`, or a `const_get` whose literal
      # name folds at compile time to a NameError. Such an expression has no value
      # type at all, and a dynamic send wants a receiver to borrow. So the whole
      # program failed to compile over an expression that never runs.
      begin
        Object.const_get("Bad.Name")
      rescue NameError => e
        p [e.class, e.message]
      end

      begin
        Object.const_get("Bad Name").to_s
      rescue NameError => e
        p [e.class, e.message, e.name.to_sym, e.receiver.to_s]
      end

      begin
        p Object.const_get("bad").anything
      rescue NameError => e
        p e.message
      end

      begin
        raise("boom").foo
      rescue RuntimeError => e
        p [e.class, e.message]
      end

      begin
        p [Object.const_get("1A")]
      rescue NameError => e
        p e.message
      end

      # The value positions that already worked, kept honest.
      begin
        p({ a: (raise "in a hash") })
      rescue RuntimeError => e
        p e.message
      end

      begin
        x = Object.const_get("also bad")
        p x
      rescue NameError => e
        p e.message
      end

      # A well-formed name still folds to the real answer.
      p Object.const_get("String")
      p Object.const_get(:Integer).name
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [NameError, "wrong constant name Bad.Name"]
      [NameError, "wrong constant name Bad Name", :"Bad Name", "Object"]
      "wrong constant name bad"
      [RuntimeError, "boom"]
      "wrong constant name 1A"
      "in a hash"
      "wrong constant name also bad"
      String
      "Integer"
    OUT
  end

  it "a jump across an ensure runs it" do
    result = ze0(<<~'RUBY')
      # A jump out of an ensure-carrying `begin` runs the ensure first: it
      # travels as a signal and the `begin` settles it onto its own target.
      i = 0
      while i < 4
        begin
          break if i == 2
          puts "b#{i}"
        ensure
          puts "e#{i}"
        end
        i += 1
      end
      puts "---"
      j = 0
      while j < 4
        j += 1
        begin
          next if j == 2
          puts "n#{j}"
        ensure
          puts "ne#{j}"
        end
      end
      puts "---"
      k = 0
      tries = 0
      while k < 2
        begin
          tries += 1
          redo if tries == 1
          puts "k#{k}"
        ensure
          puts "ke#{k}"
        end
        k += 1
      end
      puts "---"
      m = 0
      while m < 3
        m += 1
        begin
          raise "x" if m == 1
          puts "m#{m}"
        rescue
          next
        ensure
          puts "me#{m}"
        end
      end
      puts "---"
      n = 0
      while n < 3
        n += 1
        begin
          puts "n#{n}"
        ensure
          break if n == 2
        end
      end
      puts "done"
      puts "==="; 
      for x in [1,2,3]
        begin
          break if x == 3
          next if x == 2
          puts "f#{x}"
        ensure
          puts "fe#{x}"
        end
      end
      puts "---"
      3.times do |i|
        begin
          next if i == 1
          puts "t#{i}"
        ensure
          puts "te#{i}"
        end
      end
      puts "---"
      [1,2,3].each do |i|
        begin
          break if i == 3
          puts "a#{i}"
        ensure
          puts "ae#{i}"
        end
      end
      puts "---"
      y = 0
      until y >= 3
        y += 1
        begin
          begin
            next if y == 2
            puts "u#{y}"
          ensure
            puts "ui#{y}"
          end
        ensure
          puts "uo#{y}"
        end
      end
      puts "---"
      z = 0
      while z < 3
        z += 1
        begin
          begin
            break if z == 2
            puts "w#{z}"
          ensure
            puts "wi#{z}"
          end
        rescue
          puts "never"
        ensure
          puts "wo#{z}"
        end
      end
      puts "done"
      puts "==="; 
      def a
        begin
          return 1
        ensure
          puts "ensure a"
        end
      end
      p a

      def b
        begin
          raise "boom"
        rescue => e
          return "r:#{e.message}"
        ensure
          puts "ensure b"
        end
      end
      p b

      def c
        [10, 20].each do |x|
          begin
            return x if x == 20
            puts "seen #{x}"
          ensure
            puts "ensure c #{x}"
          end
        end
        :none
      end
      p c

      def d
        begin
          begin
            return 5
          ensure
            puts "inner d"
          end
        ensure
          puts "outer d"
        end
      end
      p d

      def e
        begin
          return 1
        ensure
          return 2
        end
      end
      p e

      def f
        begin
          yield
          return :after
        ensure
          puts "ensure f"
        end
      end
      p(f { 1 })
      puts "===";
      r = [1,2,3].map do |x|
        begin
          next x * 10 if x == 2
          x
        ensure
          puts "ens #{x}"
        end
      end
      p r
      r2 = [1,2,3].each do |x|
        begin
          break :stop if x == 2
        ensure
          puts "b ens #{x}"
        end
      end
      p r2
      tries = 0
      r3 = [1,2].map do |x|
        begin
          tries += 1
          redo if x == 1 && tries == 1
          x
        ensure
          puts "r ens #{x} #{tries}"
        end
      end
      p r3
      def deep
        [1,2].each do |x|
          begin
            begin
              next if x == 1
              return :from_block
            ensure
              puts "inner #{x}"
            end
          ensure
            puts "outer #{x}"
          end
        end
        :none
      end
      p deep
      r = [1,2,3].map do |x|
        begin
          next x * 10 if x == 2
          x
        ensure
          puts "ens #{x}"
        end
      end
      p r
      r2 = [1,2,3].each do |x|
        begin
          break :stop if x == 2
        ensure
          puts "b ens #{x}"
        end
      end
      p r2
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      b0
      e0
      b1
      e1
      e2
      ---
      n1
      ne1
      ne2
      n3
      ne3
      n4
      ne4
      ---
      ke0
      k0
      ke0
      k1
      ke1
      ---
      me1
      m2
      me2
      m3
      me3
      ---
      n1
      n2
      done
      ===
      f1
      fe1
      fe2
      fe3
      ---
      t0
      te0
      te1
      t2
      te2
      ---
      a1
      ae1
      a2
      ae2
      ae3
      ---
      u1
      ui1
      uo1
      ui2
      uo2
      u3
      ui3
      uo3
      ---
      w1
      wi1
      wo1
      wi2
      wo2
      done
      ===
      ensure a
      1
      ensure b
      "r:boom"
      seen 10
      ensure c 10
      ensure c 20
      20
      inner d
      outer d
      5
      2
      ensure f
      :after
      ===
      ens 1
      ens 2
      ens 3
      [1, 20, 3]
      b ens 1
      b ens 2
      :stop
      r ens 1 1
      r ens 1 2
      r ens 2 3
      [1, 2]
      inner 1
      outer 1
      inner 2
      outer 2
      :from_block
      ens 1
      ens 2
      ens 3
      [1, 20, 3]
      b ens 1
      b ens 2
      :stop
    OUT
  end

  it "a missing method via send raises a rescuable no method error" do
    result = ze0(<<~'RUBY')
      class Plain
        def real
          :real
        end
      end
      p1 = Plain.new
      begin
        p1.send(:nope)
      rescue NoMethodError => e
        puts "caught nope"
      end
      begin
        p1.send(:nope2)
      rescue NameError => e
        puts "caught via NameError"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught nope
      caught via NameError
    OUT
  end

  it "a module superclass raises rubys own type error" do
    result = ze0(<<~'RUBY')
      # Every built-in CLASS is subclassable (`zeo_abi::NOT_PAYLOAD_ROOTS` is a
      # denylist of the shapes that are not payload wrappers, not an allowlist
      # of the ones that are). What is left is the two superclasses RUBY
      # refuses, and zeo compiles each into ruby's own raise rather than a
      # compile error naming zeo.

      begin
        class WantsModule < Comparable
        end
      rescue TypeError => e
        puts "module: #{e.message}"
      end
      begin
        class WantsClass < Class
        end
      rescue TypeError => e
        puts "class: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      module: superclass must be an instance of Class (given an instance of Module)
      class: can't make subclass of Class
    OUT
  end

  it "a multi line exception message keeps its class tag on line one" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_multi_line_exception_message_keeps_its_class_tag_on_line_one.rb")
      # CRuby's uncaught-exception report puts the class tag at the end of the
      # message's FIRST line and lets the rest run underneath, unindented -- the
      # `error_pos`/`print_errinfo` split. zeo appended it after the whole message,
      # which nothing noticed while the only multi-line messages came from
      # constructs that failed to compile.
      #
      # A kind collision is exactly that shape: `X is not a class` on one line and
      # `<file>:<line>: previous definition of X was here` on the next.
      raise ArgumentError, "first\nsecond\nthird"
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "lang/exceptions/a_multi_line_exception_message_keeps_its_class_tag_on_line_one.rb:9:in '<main>': first (ArgumentError)\nsecond\nthird\n\nraise ArgumentError, \"first\\nsecond\\nthird\"\n      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n"
    _(result.status).must_equal 1
  end

  it "a pattern naming an undefined constant raises name error when tried" do
    _(ze0(<<~'RUBY').stdout).must_equal "NameError: uninitialized constant NopeClass\n"
      x = 5
      r = begin
        case x
        in NopeClass then "a"
        else "b"
        end
      rescue => e
        "#{e.class}: #{e.message}"
      end
      puts r
    RUBY
  end

  it "a raise in an argument keeps the block unbuilt" do
    result = ze0(<<~'RUBY', env: {"ZEO_RT_LEAKCHECK" => "1"})
      # A literal block's proc is MOVED to the callee, so no landing can release
      # it: on every path but the raise the callee has already taken the value
      # out of the slot. That makes the window between building the proc and
      # making the call load-bearing -- an argument that raises inside it leaks
      # the proc, once per execution.
      #
      # The emitter used to build the proc FIRST, before the receiver and the
      # argument list, at five call shapes. Each of the sends below raises from
      # an argument, and each leaked one `Proc` (tag 24) per iteration. The block
      # is now built last, which is also ruby's own order.
      #
      # `ZEO_RT_LEAKCHECK=1` is what makes this a test: the answers printed here
      # are the same either way, and the ledger's exit balance is the measurement.

      def missing
        raise ArgumentError, "no argument for you"
      end

      def takes_one(n)
        yield n
      end

      class Holder
        def initialize(n)
          @n = n
        end
      end

      def attempt
        yield
        "no raise"
      rescue ArgumentError
        "raised"
      end

      # A call to a compiled method, whose block rides its own parameter.
      p attempt { takes_one(missing) { |x| x } }

      # A dynamic send on a receiver the compiler cannot name.
      p attempt { [1, 2].fetch(missing) { |x| x } }

      # A splatted argument list, which builds its Array in the runtime.
      p attempt { takes_one(*[missing]) { |x| x } }

      # A keyword send.
      p attempt { [1, 2].each_slice(missing) { |x| x } }

      # A constructor, whose block forwards to `initialize`.
      p attempt { Holder.new(missing) { |x| x } }

      # Once more in a loop: a leak here is unbounded, not a one-off.
      10.times { attempt { takes_one(missing) { |x| x } } }
      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "raised"
      "raised"
      "raised"
      "raised"
      "raised"
      done
    OUT
  end

  it "a raise names its own cause" do
    result = ze0(<<~'RUBY')
      # `raise ..., cause: c` names the cause outright, so the automatic `$!`
      # chaining is skipped and the named one stands -- `cause: nil` suppresses
      # chaining entirely, and a non-exception cause is a TypeError.
      class Wrapped < StandardError; end
      begin
        begin
          raise "inner"
        rescue => e
          raise Wrapped, "outer", cause: e
        end
      rescue Wrapped => w
        p w.message
        p w.cause.message
      end

      begin
        raise "a", cause: nil
      rescue => e
        p e.cause
      end

      begin
        begin
          raise "x"
        rescue
          raise ArgumentError.new("y"), cause: $!
        end
      rescue ArgumentError => e
        p [e.message, e.cause.message]
      end

      begin
        raise "z", cause: 5
      rescue TypeError => e
        p e.message
      end

      err = RuntimeError.new("self")
      begin
        raise err, cause: err
      rescue => e
        p e.cause
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "outer"
      "inner"
      nil
      ["y", "x"]
      "exception object expected"
      nil
    OUT
  end

  it "a require that raises is rescuable" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/a_require_that_raises_is_rescuable.rb", files: {"../../fixtures/raising_feature/ok.rb" => "LOADED_CLEANLY = true\n", "../../fixtures/raising_feature/r7.rb" => "raise ArgumentError, \"raise from r7\"\n", "../../fixtures/raising_feature/r1.rb" => "raise ArgumentError, \"raise from r1\"\n", "../../fixtures/raising_feature/r2.rb" => "raise ArgumentError, \"raise from r2\"\n", "../../fixtures/raising_feature/r3.rb" => "raise ArgumentError, \"raise from r3\"\n", "../../fixtures/raising_feature/r4.rb" => "raise ArgumentError, \"raise from r4\"\n", "../../fixtures/raising_feature/r5.rb" => "raise ArgumentError, \"raise from r5\"\n", "../../fixtures/raising_feature/r6.rb" => "raise ArgumentError, \"raise from r6\"\n", "../../fixtures/raising_feature/r8.rb" => "raise ArgumentError, \"raise from r8\"\n"})
      # A `require` zeo resolves at COMPILE time is spliced in place, and the
      # spliced body has to land INSIDE the `begin` that wrote the require. CRuby
      # runs the required file during the `require` call, so a raise from the
      # file's top level both reaches the handler around it and aborts the rest of
      # the begin's body.
      #
      # zeo spliced it out as a SIBLING, and broke both halves: the program died
      # where ruby rescues, and the statements after the require ran anyway. It was
      # hidden because a require zeo CANNOT resolve statically takes the run-time
      # path, which was always rescuable.
      #
      # `begin; require "optional"; rescue LoadError; end` is the everyday shape.

      $LOAD_PATH.unshift(File.expand_path("../../fixtures/raising_feature", __dir__))

      begin
        require "r1"
        puts "after require -- must not print"
      rescue => e
        puts "bare rescue        #{e.class}: #{e.message}"
      end

      begin
        require "r2"
      rescue ArgumentError
        puts "named rescue       ok"
      ensure
        puts "ensure             ran"
      end

      # Nothing raises: the `else` runs and the handler stays dead.
      begin
        require_relative "../../fixtures/raising_feature/ok"
        puts "body finished      #{LOADED_CLEANLY}"
      rescue ArgumentError
        puts "must not run"
      else
        puts "else               ran"
      end

      begin
        require "r3"
      rescue TypeError
        puts "must not run"
      rescue ArgumentError
        puts "second clause      ok"
      end

      begin
        begin
          require "r4"
        rescue ArgumentError
          puts "inner rescue       ok"
        end
      rescue Exception
        puts "outer must not run"
      end

      # A method-body require runs when the method does, not at load.
      def load_r5
        require "r5"
      rescue ArgumentError => e
        "method rescued: #{e.message}"
      end
      puts "method body        #{load_r5}"

      # The begin is an EXPRESSION: the handler's value is the begin's value.
      value = begin
        require "r6"
        "no raise"
      rescue ArgumentError
        "value from rescue"
      end
      puts "as an expression   #{value}"

      # `require_relative` and `load` take the same path.
      begin
        require_relative "../../fixtures/raising_feature/r7"
      rescue ArgumentError => e
        puts "require_relative   #{e.message}"
      end

      begin
        load File.expand_path("../../fixtures/raising_feature/r8.rb", __dir__)
      rescue ArgumentError => e
        puts "load               #{e.message}"
      end

      puts "still running"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      bare rescue        ArgumentError: raise from r1
      named rescue       ok
      ensure             ran
      body finished      true
      else               ran
      second clause      ok
      inner rescue       ok
      method body        method rescued: raise from r5
      as an expression   value from rescue
      require_relative   raise from r7
      load               raise from r8
      still running
    OUT
  end

  it "a rescue binding rebinds whatever the name held" do
    result = ze0(<<~'RUBY')
      # `rescue => e` assigns `e`, and ruby does not care what `e` was before. The
      # name simply holds the exception inside the handler, and keeps holding it
      # afterwards -- a rescue binding is an ordinary local assignment, not a scoped
      # one.
      #
      # A compiler that infers a type per local has to widen the slot at that
      # assignment. Keeping the type the name had BEFORE emitted the handler's
      # `e.message` as a call on that earlier type while the value was an exception.

      class Box
        def initialize(v)
          @v = v
        end

        def message = "box(#{@v})"
      end

      # A user-class local, then the same name as a rescue binding.
      e = Box.new(1)
      p e.message

      begin
        raise ArgumentError, "boom"
      rescue ArgumentError => e
        p e.message
        p e.class
      end

      # ... and it is STILL the exception after the begin.
      p e.class
      p e.message

      # The other order: bound by a rescue first, then assigned an ordinary object.
      begin
        raise "first"
      rescue => x
        p x.message
      end

      x = Box.new(2)
      p x.message

      # An Integer local, and a String one -- the same widening, no user class in it.
      n = 42
      begin
        Integer("nope")
      rescue ArgumentError => n
        p n.class
      end
      p n.is_a?(Exception)

      s = "plain"
      p s.upcase
      begin
        raise TypeError, "typed"
      rescue TypeError => s
        p s.message
      end
      p s.class

      # One name across two clauses of the same begin, each raising a different class.
      def attempt(which)
        raise ArgumentError, "arg" if which == :arg
        raise TypeError, "type"
      end

      [:arg, :type].each do |which|
        outcome = Box.new(which)
        begin
          attempt(which)
        rescue ArgumentError => outcome
          p [:arg, outcome.message]
        rescue TypeError => outcome
          p [:type, outcome.message]
        end
        p outcome.class
      end

      # A nested begin reusing the outer handler's name.
      begin
        raise "outer"
      rescue => err
        p err.message
        begin
          raise KeyError, "inner"
        rescue KeyError => err
          p err.message
        end
        p err.message
      end

      # The binding survives a handler that never ran, too: `rescue` did not fire, so
      # the name keeps what it already had.
      untouched = Box.new(:kept)
      begin
        :fine
      rescue => untouched
        p :never
      end
      p untouched.message
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "box(1)"
      "boom"
      ArgumentError
      ArgumentError
      "boom"
      "first"
      "box(2)"
      ArgumentError
      true
      "PLAIN"
      "typed"
      TypeError
      [:arg, "arg"]
      ArgumentError
      [:type, "type"]
      TypeError
      "outer"
      "inner"
      "inner"
      "box(kept)"
    OUT
  end

  it "a rescue splat follows the splat rule" do
    result = ze0(<<~'RUBY')
      # `rescue A, *list => e` splats `list` by the SAME rule an argument list does.
      #
      # zeo tested the splat's value as if it were always one class, so `*nil` --
      # which splices nothing -- was tested as a nil class and raised
      # `TypeError: class or module required for rescue clause` INSTEAD of whatever
      # the body raised. It only showed when no earlier entry matched, which is why
      # it hid: the common path short-circuits before the splat is ever read.
      #
      # rubygems writes exactly that:
      #
      #     rescue Gem::Timeout::Error, IOError, SocketError, SystemCallError,
      #            *(OpenSSL::SSL::SSLError if Gem::HAVE_OPENSSL) => e
      #
      # so every failed download reported a TypeError from a rescue clause instead
      # of the error it was rescuing.

      class Splattable
        def to_a = [ArgumentError, TypeError]
      end

      def catch_with(list)
        raise KeyError, "k"
      rescue IOError, *list => e
        "caught #{e.class}"
      end

      [nil, [], [KeyError], KeyError, Splattable.new, false].each do |list|
        result = begin
          catch_with(list)
        rescue StandardError => e
          "#{e.class}: #{e.message}"
        end
        puts "#{list.class}\t#{result}"
      end

      # The splat entry really is consulted, not just tolerated.
      def only_via_splat
        raise ArgumentError, "a"
      rescue *[ArgumentError] => e
        "splat matched #{e.class}"
      end
      puts only_via_splat

      # A guarded splat that evaluates to a class still matches through it.
      HAVE = true
      def guarded
        raise ArgumentError, "a"
      rescue IOError, *(ArgumentError if HAVE) => e
        "guard matched #{e.class}"
      end
      puts guarded

      # And the same clause with the guard false lets the exception past.
      NONE = nil
      def unguarded
        raise ArgumentError, "a"
      rescue IOError, *(ArgumentError if NONE) => e
        "guard matched #{e.class}"
      end
      begin
        unguarded
      rescue ArgumentError => e
        puts "guard absent, propagated #{e.class}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NilClass	KeyError: k
      Array	KeyError: k
      Array	caught KeyError
      Class	caught KeyError
      Splattable	KeyError: k
      FalseClass	TypeError: class or module required for rescue clause
      splat matched ArgumentError
      guard matched ArgumentError
      guard absent, propagated ArgumentError
    OUT
  end

  it "a rescue target may be an attribute or index" do
    result = ze0(<<~'RUBY')
      # `rescue => target` accepts every lvalue Ruby accepts -- including an
      # attribute setter and an index write, which run only when the clause
      # fires (receiver evaluated at that moment, then `attr=`/`[]=` called
      # with the exception). zeo lowered only the variable-shaped targets and
      # rejected these two.
      class Holder
        attr_accessor :err
      end

      h = Holder.new
      begin
        raise ArgumentError, "boom"
      rescue => h.err
        puts "rescued into attr"
      end
      p h.err.class
      p h.err.message

      slot = {}
      begin
        raise KeyError, "missing"
      rescue KeyError => slot[:why]
        puts "rescued into index"
      end
      p slot[:why].class

      # The receiver expression is evaluated when the clause fires, not before.
      def fresh
        $built += 1
        Holder.new
      end
      $built = 0
      begin
        raise "later"
      rescue => fresh.err
      end
      p $built
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      rescued into attr
      ArgumentError
      "boom"
      rescued into index
      KeyError
      1
    OUT
  end

  it "a scoped const write to an undefined scope raises before the rhs runs" do
    _(ze0(<<~'RUBY').stdout).must_equal "NameError: uninitialized constant Nope\n"
      # CRuby resolves the scope BEFORE evaluating the value, so the RHS side
      # effect never runs.

      r = begin
        Nope::X = (puts "rhs-ran"; 5)
        "assigned"
      rescue => e
        "#{e.class}: #{e.message}"
      end
      puts r
    RUBY
  end

  it "a vcall miss is a name error" do
    result = ze0(<<~'RUBY')
      # A VCALL is a bare identifier ruby could have read as a local (`foo`, never
      # `foo()` or `self.foo`). The lookup is an ordinary send; the MISS is not.
      # Ruby cannot tell which the writer meant, so it says "undefined local
      # variable or method" and raises NameError. With parens or arguments it is
      # unambiguously a call, and a miss is NoMethodError.

      def show
        yield
      rescue NameError => e
        [e.class, e.message]
      end

      p(show { nope })
      p(show { nope() })
      p(show { nope(1) })
      p(show { self.nope })

      # In a method body, named for the instance.
      class K
        def go = show { missing }
        def show = (yield rescue [$!.class, $!.message])
      end
      p K.new.go

      # In a class body, named for the class -- an enclosing local is NOT in scope
      # there, which is exactly the case the message is written for.
      outer = 1
      class Arr
        begin
          outer
        rescue NameError => e
          p [e.class, e.message]
        end
      end

      # A name that IS a local reads it, no send at all.
      defined_local = :read
      p(defined_local)

      # NameError carries the name it could not find.
      begin
        absent_thing
      rescue NameError => e
        p [e.name, e.receiver == self]
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [NameError, "undefined local variable or method 'nope' for main"]
      [NoMethodError, "undefined method 'nope' for main"]
      [NoMethodError, "undefined method 'nope' for main"]
      [NoMethodError, "undefined method 'nope' for main"]
      [NameError, "undefined local variable or method 'missing' for an instance of K"]
      [NameError, "undefined local variable or method 'outer' for class Arr"]
      :read
      [:absent_thing, true]
    OUT
  end

  it "abstract raise override return" do
    result = ze0(<<~'RUBY')
      # A method whose base impl always raises (C void return) but is overridden by a
      # value-returning subclass must be callable in value position (#1416): widen the
      # raising base's return to the override's type since its body never returns.
      module Helper
        def self.find(t); t.to_s; end
      end
      class Base
        def self.table_name; raise "abstract"; end
        def self.lookup; Helper.find(table_name); end
      end
      class Article < Base
        def self.table_name; "articles"; end
        def self.lookup; 0; end
      end
      puts Article.lookup

      # instance method, two overrides of divergent types -> unified poly
      class Shape
        def area; raise "abstract"; end
        def describe; "area=#{area}"; end
      end
      class Sq < Shape
        def area; 4; end
      end
      class Nm < Shape
        def area; "n/a"; end
      end
      puts Sq.new.describe
      puts Nm.new.describe
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0
      area=4
      area=n/a
    OUT
  end

  it "an alias of the inherited builtin raise works in every call shape" do
    result = ze0(<<~'RUBY')
      # `alias_method :raise!, :raise` / `alias __raise__ raise` (ostruct's and
      # delegate's shapes): the source is Kernel's BUILTIN raise -- no user
      # `Scope` exists, so this used to be a compile error. Statically-resolved
      # sites substitute into the raise lowering (including the bare re-raise and the
      # 3-arg form, whose custom-backtrace argument is evaluated and dropped);
      # all outputs oracle-verified.

      class Reporter
        alias_method :raise!, :raise
        def two_arg
          raise! ArgumentError, "boom"
        rescue ArgumentError => e
          puts e.message
        end
        def re_raise
          begin
            raise IOError, "orig"
          rescue
            raise!
          end
        rescue IOError => e
          puts e.message
        end
        def three_arg
          raise! ArgumentError, "with-bt", caller(0)
        rescue ArgumentError => e
          puts e.message
        end
      end
      class Failer
        alias __raise__ raise
        def go
          __raise__ NotImplementedError, "need to define"
        rescue NotImplementedError => e
          puts e.message
        end
      end
      r = Reporter.new
      r.two_arg
      r.re_raise
      r.three_arg
      Failer.new.go
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      boom
      orig
      with-bt
      need to define
    OUT
  end

  it "an error names the code it came from" do
    _(ze0(<<~'RUBY', path: "lang/exceptions/an_error_names_the_code_it_came_from.rb").stdout).must_equal "undefined method 'lenght' for nil (NoMethodError)\n\nshow { x.lenght }\n        ^^^^^^^\n--\nundefined method 'bar' for nil (NoMethodError)\n\nshow { x&.foo.bar }\n             ^^^^\n--\nnil can't be coerced into Integer (TypeError)\n\nshow { 1 + nil }\n           ^^^\n--\ninvalid value for Integer(): \"zz\" (ArgumentError)\n\nshow { Integer(\"zz\") }\n               ^^^^\n--\nno implicit conversion of String into Integer (TypeError)\n\nshow { [1, 2].first(\"a\") }\n                    ^^^\n--\nwrong number of arguments (given 1, expected 2) (ArgumentError)\n\n    caller: lang/exceptions/an_error_names_the_code_it_came_from.rb:19\n    | show { two(1) }\n             ^^^\n    callee: lang/exceptions/an_error_names_the_code_it_came_from.rb:11\n    | def two(a, b) = a\n          ^^^\n--\nmissing keyword: :a (ArgumentError)\n\n    caller: lang/exceptions/an_error_names_the_code_it_came_from.rb:20\n    | show { kw }\n             ^^\n    callee: lang/exceptions/an_error_names_the_code_it_came_from.rb:12\n    | def kw(a:) = a\n          ^^\n--\nuninitialized constant UndefinedThing (NameError)\n\nshow { UndefinedThing }\n       ^^^^^^^^^^^^^^\n--\nuninitialized constant Comparable::Nope (NameError)\n\nshow { Comparable::Nope }\n                 ^^^^^^\n--\nundefined local variable or method 'foo_bar_baz' for main (NameError)\n\nshow { foo_bar_baz }\n       ^^^^^^^^^^^\n--\nundefined method 'foo=' for nil (NoMethodError)\n\nshow { x.foo = 1 }\n        ^^^^^^\n--\nundefined method '[]' for nil (NoMethodError)\n\nshow { h = nil; h[:a] += 1 }\n                 ^^^^\n--\nundefined method '+' for nil (NoMethodError)\n\nshow { a = nil; a += 1 }\n                  ^\n--\nwrong number of arguments (given 0, expected 1) (ArgumentError)\n\n    caller: lang/exceptions/an_error_names_the_code_it_came_from.rb:27\n    | show { ->(a) {}.call }\n                     ^^^^^\n    callee: lang/exceptions/an_error_names_the_code_it_came_from.rb:27\n    | show { ->(a) {}.call }\n             ^^\n--\nkey not found: :b (KeyError)\n--\nundefined method 'unknown_meth' for an instance of String (NoMethodError)\n\nshow { \"abc\".unknown_meth(1, 2) }\n            ^^^^^^^^^^^^^\n--\nundefined local variable or method 'lenghth' for main (NameError)\n\nshow { lengthh = 1; lenghth }\n                    ^^^^^^^\nDid you mean?  lengthh\n--\nundefined method 'frist' for an instance of Array (NoMethodError)\n\nshow { [1].frist }\n          ^^^^^^\nDid you mean?  first\n--\n"
      # detailed_message shows the line an error came from with a caret run
      # under the node that failed, as error_highlight spots it: a call's name
      # or arguments, a constant, an operator write, and for a wrong argument
      # count both the caller and the callee. did_you_mean adds its guess.

      def show
        yield
      rescue Exception => e
        puts e.detailed_message(highlight: false), "--"
      end
      def two(a, b) = a
      def kw(a:) = a
      x = nil
      show { x.lenght }
      show { x&.foo.bar }
      show { 1 + nil }
      show { Integer("zz") }
      show { [1, 2].first("a") }
      show { two(1) }
      show { kw }
      show { UndefinedThing }
      show { Comparable::Nope }
      show { foo_bar_baz }
      show { x.foo = 1 }
      show { h = nil; h[:a] += 1 }
      show { a = nil; a += 1 }
      show { ->(a) {}.call }
      show { {a: 1}.fetch(:b) }
      show { "abc".unknown_meth(1, 2) }
      show { lengthh = 1; lenghth }
      show { [1].frist }

    RUBY
  end

  it "an exception subclass instance is a boxed value everywhere" do
    result = ze0(<<~'RUBY')
      # `EE.new` for a user `class EE < Exception` constructs a native-backed
      # `RubyValue` (no generated struct exists) -- but registration-time type
      # inference consulted the not-yet-linearized `ancestors` and typed the
      # local as an unboxed struct handle, baking `new_handle` calls to a type
      # codegen never emits (an invalid program, from the timeout gem's
      # `ExitException`). The ancestry predicates now walk the recorded
      # superclass links, which exist from registration.

      module T
        class EE < Exception
        end
        class Er < RuntimeError
          def self.go(m)
            exc = EE.new(m)
            yield exc
          end
        end
      end
      T::Er.go("x") { |e| puts e.class; puts e.message }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      T::EE
      x
    OUT
  end

  it "an invalid attribute name is a name error" do
    result = ze0(<<~'RUBY')
      # `attr_accessor`/`attr_reader`/`attr_writer` validate the name ("invalid
      # attribute name '1bad'"); zeo accepts anything and mints :"1bad" rows,
      # which then leak into instance_methods. (Found by the 2026-08-24 probe
      # sweep.)
      c = Class.new
      begin
        c.send(:attr_accessor, "1bad")
      rescue NameError => e
        puts e.message
      end
      p c.instance_methods(false)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      invalid attribute name '1bad'
      []
    OUT
  end

  it "an overfull raise is a runtime argument error" do
    result = ze0(<<~'RUBY')
      # `Kernel#raise` with more than 3 positional arguments (appnexusapi passes
      # a message twice) or with only `cause:` is a RUNTIME ArgumentError: the
      # call evaluates its arguments first and raises only when reached, so the
      # program still loads and an untaken branch never complains.
      def never_reached
        raise RuntimeError, "a", "b", ["c"] if false
        :loadable
      end
      p never_reached

      side_effects = []
      begin
        raise RuntimeError, side_effects << :msg, side_effects << :bt, side_effects << :extra
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      p side_effects

      begin
        raise(cause: RuntimeError.new("x"))
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      puts "still running"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :loadable
      ArgumentError: wrong number of arguments (given 4, expected 0..3)
      [:msg, :bt, :extra]
      ArgumentError: only cause is given with no arguments
      still running
    OUT
  end

  it "an uncaught error reports its causes" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/an_uncaught_error_reports_its_causes.rb")
      # The report of an uncaught exception names each cause after it, each
      # once, as full_message does.
      class Outer < StandardError; end

      def a = raise("a")

      def b
        a
      rescue
        raise Outer, "b"
      end

      b

    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "lang/exceptions/an_uncaught_error_reports_its_causes.rb:10:in 'Object#b': b (Outer)\n\tfrom lang/exceptions/an_uncaught_error_reports_its_causes.rb:13:in '<main>'\nlang/exceptions/an_uncaught_error_reports_its_causes.rb:5:in 'Object#a': a (RuntimeError)\n\tfrom lang/exceptions/an_uncaught_error_reports_its_causes.rb:8:in 'Object#b'\n\tfrom lang/exceptions/an_uncaught_error_reports_its_causes.rb:13:in '<main>'\n"
    _(result.status).must_equal 1
  end

  it "an unknown keyword argument is an error" do
    result = ze0(<<~'RUBY')
      # A keyword a method does not declare raises ArgumentError ("unknown
      # keyword: :b") on EVERY call path. zeo's compile-time arity check gets the
      # static shapes right; the DYNAMIC paths -- a runtime-defined method, a
      # `Method#call`, a `send` -- silently drop the extra keyword and the call
      # succeeds. Likely the `**kwrest`-peel shape from the kwargs channel.
      # (Found by the 2026-08-24 probe sweep.)
      c = Class.new { def kw(a:) = a }

      begin
        p c.new.kw(a: 1, b: 2)
      rescue ArgumentError => e
        puts e.message
      end

      m = c.new.method(:kw)
      begin
        p m.call(a: 1, z: 9)
      rescue ArgumentError => e
        puts e.message
      end

      begin
        p c.new.send(:kw, a: 1, q: 3)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      unknown keyword: :b
      unknown keyword: :z
      unknown keyword: :q
    OUT
  end

  it "an unresolvable require inside rescue loaderror defers to runtime" do
    result = ze0(<<~'RUBY')
      # The optional-dependency idiom: `begin; require 'missing'; rescue
      # LoadError`. A literal require that can't be resolved but is lexically
      # inside a `rescue LoadError` is deferred to a runtime `Kernel#require`
      # (raising the LoadError the rescue handles), not a loud compile error.
      # net/http's `begin; require 'win32/sspi'; rescue LoadError` needs this.

      begin
        require "definitely_missing_optdep_xyz"
        puts "loaded"
      rescue LoadError => e
        puts "rescued: #{e.send(:message)}"
      end
      puts "after"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      rescued: cannot load such file -- definitely_missing_optdep_xyz
      after
    OUT
  end

  it "an unshareable message is deep copied across the boundary" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/an_unshareable_message_is_deep_copied_across_the_boundary.rb")
      # Mutating the original AFTER send must not affect the ractor's copy --
      # the whole point of the isolation discipline.
      # Asserted via `puts` on the round-tripped copy (collection methods on
      # the Poly-typed receive result are the pre-existing Poly-dispatch
      # gap, nothing Ractor-specific).

      echo = Ractor.new do
        Ractor.receive
      end
      payload = [100, 200]
      echo.send(payload)
      payload[0] = 999
      puts echo.value
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      100
      200
    OUT
    _(result.stderr).must_equal "lang/exceptions/an_unshareable_message_is_deep_copied_across_the_boundary.rb:7: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
  end

  it "bang exception object" do
    result = ze0(<<~'RUBY')
      # $! is the exception object the innermost active rescue is handling (nil
      # outside one): same identity as the rescue variable and the raised object.
      e = StandardError.new 'foo'
      begin
        raise e
      rescue => err
        puts err.message
        puts $!.message
        puts $!.equal?(err)
        puts $!.equal?(e)
      end
      p $!
      begin
        raise ArgumentError, "inner"
      rescue
        puts $!.message
        begin
          raise TypeError, "deep"
        rescue
          puts $!.message
        end
        puts $!.message
      end
      p $!
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      foo
      foo
      true
      true
      nil
      inner
      deep
      inner
      nil
    OUT
  end

  it "bare begin no handler" do
    result = ze0(<<~'RUBY')
      # A `begin ... end` with no rescue / else / ensure protects nothing, so it
      # emits no handler frame -- the do-while idiom above all. The forms that DO
      # need one still behave.
      i = 0
      begin
        i += 1
      end while i < 3
      p i

      j = 10
      begin
        j -= 1
      end until j <= 7
      p j

      v = begin
        1 + 1
      end
      p v

      w = begin
        "a"
        "b"
      end
      p w

      r = begin
        raise "x"
      rescue => e
        e.message
      end
      p r

      def f
        begin
          return 1
        ensure
          puts "ens"
        end
      end
      p f

      def g
        begin
          begin
            raise "inner"
          end
        rescue => e
          "caught #{e.message}"
        end
      end
      p g

      k = 0
      begin
        k += 1
        next if k == 1
      end while k < 2
      p k

      n = 0
      loop do
        begin
          n += 1
        end
        break if n > 2
      end
      p n
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      7
      2
      "b"
      "x"
      ens
      1
      "caught inner"
      2
      3
    OUT
  end

  it "bare raise re raises preserving a custom exceptions own ivars" do
    result = ze0(<<~'RUBY')
      class MyError < StandardError
        def initialize(msg, code)
          super(msg)
          @code = code
        end
        def code
          @code
        end
      end

      class Inner
        def call
          begin
            raise MyError.new("failed with code 42", 42)
          rescue MyError => e
            puts "inner saw code #{e.send(:code)}"
            raise
          end
        end
      end

      begin
        Inner.new.call
      rescue MyError => e
        puts "outer saw code #{e.send(:code)}"
        puts "outer message: #{e.send(:message)}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      inner saw code 42
      outer saw code 42
      outer message: failed with code 42
    OUT
  end

  it "bare raise with no active rescue constructs a runtime error" do
    _(ze0(<<~'RUBY').stdout).must_equal "[]\n"
      # Bare `raise` (re-raise) outside any active `rescue` clause -- real
      # Ruby constructs a fresh `RuntimeError` with an EMPTY message rather
      # than erroring (oracle-verified: `ruby -e 'begin; raise; rescue => e;
      # puts "[#{e.message}]"; end'` -> `"[]"`).

      begin
        raise
      rescue => e
        puts "[#{e.message}]"
      end
    RUBY
  end

  it "bare rescue does not catch a script error level exception" do
    _(ze0(<<~'RUBY').stdout).must_equal "outer caught ScriptError: script problem\n"
      # A bare `rescue` matches `StandardError` and below ONLY -- it must NOT
      # catch a raised `ScriptError` (a sibling branch of the hierarchy, both
      # direct children of `Exception`). This is the real semantic bare
      # `rescue`'s default narrows to `StandardError`, not `Exception`.

      begin
        begin
          raise ScriptError, "script problem"
        rescue => e
          puts "should not print: #{e.send(:message)}"
        end
      rescue ScriptError => e
        puts "outer caught ScriptError: #{e.send(:message)}"
      end
    RUBY
  end

  it "bare rescue standard error only" do
    result = ze0(<<~'RUBY')
      # A bare `rescue` matches only StandardError and its subclasses. An Exception
      # or NotImplementedError (which is a ScriptError, not a StandardError) falls
      # through to a later `rescue Exception`.
      def br(e)
        begin
          raise e
        rescue => x
          "bare"
        rescue Exception => x
          "typed"
        end
      end

      p br(NotImplementedError.new)   # "typed"  (NotImplementedError < ScriptError)
      p br(Exception.new)             # "typed"
      p br(ArgumentError.new)         # "bare"   (ArgumentError < StandardError)
      p br(RuntimeError.new)          # "bare"
      p br(KeyError.new)              # "bare"   (KeyError < IndexError < StandardError)

      # NotImplementedError is NOT a StandardError.
      p NotImplementedError.new.is_a?(StandardError)   # false
      p NotImplementedError.new.is_a?(ScriptError)     # true
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "typed"
      "typed"
      "bare"
      "bare"
      "bare"
      false
      true
    OUT
  end

  it "basicobject blank slate" do
    result = ze0(<<~'RUBY')
      # A BasicObject subclass is a blank slate (#2703): it answers only
      # BasicObject's own methods (==, equal?, instance_eval, ...) and what the user
      # defined; the Object/Kernel surface raises NoMethodError.
      class BO < BasicObject
        def greet; "hi"; end
      end
      a = BO.new
      r = (a.class rescue $!.class)
      p r
      p a.greet
      r2 = (a.inspect rescue "no-inspect")
      p r2
      r3 = (a.respond_to?(:greet) rescue "no-respond_to")
      p r3
      p(a == a)
      b = BO.new
      p(a == b)
      p(a.equal?(a))
      class Normal; end
      p Normal.new.class
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NoMethodError
      "hi"
      "no-inspect"
      "no-respond_to"
      true
      false
      true
      Normal
    OUT
  end

  it "basicobject dup rescued" do
    result = ze0(<<~'RUBY')
      # An absent Object method on a blank-slate receiver raises INSIDE the
      # enclosing handler's region (#2726): the raise is an expression-arm prelude,
      # which used to emit before the rescue modifier's setjmp.
      class BO < BasicObject
        def initialize; @x = 1; end
        def own; @x; end
      end
      a = BO.new
      r = (a.dup.own rescue $!.class)
      p r
      p a.own
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NoMethodError
      1
    OUT
  end

  it "begin else value" do
    result = ze0(<<~'RUBY')
      # The value of `begin ... rescue ... else ... end`: the else clause's on
      # success (including an empty else), the rescue arm's on an exception, in
      # expression and method-tail position and inside a block. CRuby generated
      # the expectations.
      a = begin; :body; rescue; :r; else; false; end
      p a
      b = begin; :body; rescue; :r; else; 3; end
      p b
      c = begin; 1; rescue; 2; else; nil; end
      p c
      d = begin; 1; rescue; 2; else; 42; end
      p d
      e = begin; "s"; rescue; "r"; else; "e"; end
      p e
      f = begin; raise "x"; rescue; :r; else; :e; end
      p f
      def g; begin; 1; rescue; 2; else; false; end; end
      p g
      h = begin; 1; rescue; 2; else; 7; ensure; 99; end
      p h
      i = begin; :body; rescue; :r; end
      p i
      def j(n)
        begin
          Integer(n)
        rescue ArgumentError
          :bad
        else
          [n, true]
        end
      end
      p j("1")
      p j("x")
      k = [1, 2].map { |v| begin; v; rescue; 0; else; v.to_s; end }
      p k
      m = begin; 1; rescue; 2; else; end
      p m
      def n; begin; :x; rescue; :r; else; end; end
      p n
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      3
      nil
      42
      "e"
      :r
      false
      7
      :body
      ["1", true]
      :bad
      ["1", "2"]
      nil
      nil
    OUT
  end

  it "begin ensure with no rescue clause still runs ensure and propagates" do
    result = ze0(<<~'RUBY')
      begin
        begin
          raise "boom"
        ensure
          puts "ensure ran"
        end
      rescue => e
        puts "caught outside: #{e.send(:message)}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ensure ran
      caught outside: boom
    OUT
  end

  it "begin rescue as expression" do
    result = ze0(<<~'RUBY')
      # Issue #704: begin/rescue used as an expression (puts arg).
      # Three shapes:
      #   - rescue path (raise + rescue + else + ensure)
      #   - else path (no raise, rescue chain skipped)
      #   - multi-class rescue (raise SubClass, match second clause)
      puts (begin; raise "x"; rescue; "caught"; else; "no error"; ensure; "ensured"; end)
      puts (begin; 42; rescue; "caught"; else; "no error"; end)
      puts (begin; raise ArgumentError; rescue TypeError; "type"; rescue ArgumentError; "arg"; end)

      # Bare begin..end as expression (no rescue / ensure).
      puts (begin; 100; end)

      # Single-class raise + rescue.
      puts (begin; raise NotImplementedError; rescue NotImplementedError; "ni"; end)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught
      no error
      arg
      100
      ni
    OUT
  end

  it "begin rescue catches and ensure always runs" do
    result = ze0(<<~'RUBY')
      begin
        puts "try"
        raise ArgumentError, "bad"
      rescue ArgumentError => e
        puts "caught: #{e.send(:message)}"
      ensure
        puts "ensure ran"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      try
      caught: bad
      ensure ran
    OUT
  end

  it "begin rescue else clause" do
    result = ze0(<<~'RUBY')
      # Phase 1B: `begin..rescue..else..end` the `else` body runs only when
      # the begin body completed without exception. Pre-fix the parser
      # emitted the else_clause field but the codegen ignored it -- the
      # else body was silently dropped from emit.
      #
      # Covered:
      #   - else with no exception (else runs)
      #   - else with exception (else does NOT run)
      #   - else combined with ensure
      #   - method-level def with begin..rescue..else

      # 1. No exception -- else runs.
      begin
        x = 1
      rescue
        puts "rescued"
      else
        puts "else ran"
      end

      # 2. Exception -- else skipped, rescue runs.
      begin
        raise "boom"
      rescue
        puts "rescued boom"
      else
        puts "should not appear"
      end

      # 3. else + ensure: order is body -> (else | rescue) -> ensure.
      begin
        y = 2
      rescue
        puts "rescue"
      else
        puts "else"
      ensure
        puts "ensure"
      end

      # 4. Method-level: else's last expr is the method return value
      # (overriding begin body's). When else's last is `puts ...` which
      # returns nil, the method returns nil (spinel's int slot lowers it
      # to 0).
      def m_else_succeeds
        10
      rescue
        -1
      else
        puts "else fired"
      end
      puts m_else_succeeds       # "else fired" then 0 (spinel int slot for nil)

      # 5. Method-level: exception path skips else, rescue value returned.
      def m_else_skipped
        raise "x"
        10
      rescue
        -1
      else
        puts "should not fire"
      end
      puts m_else_skipped        # -1
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      else ran
      rescued boom
      else
      ensure
      else fired

      -1
    OUT
  end

  it "begin rescue used as an expressions value" do
    _(ze0(<<~'RUBY').stdout).must_equal "-1\n"
      x = begin
        raise "bad"
      rescue
        -1
      end
      puts x
    RUBY
  end

  it "bigint div by zero" do
    result = ze0(<<~'RUBY')
      # Bigint division / modulo by zero raises ZeroDivisionError.
      #
      # Bigint detection: `a = a * 2` inside a `while` loop promotes the
      # local to bigint via scan_bigint_in_loop_node. Raising 1 by *2 50
      # times overflows the mrb_int range so `a` is bigint-typed by the
      # time we hit the / 0 expression.
      #
      # Runtime path: sp_bigint_div / sp_bigint_mod call into mini-gmp,
      # which detects the zero divisor at sp_bigint.c:2718 and calls
      # mrb_raise(mrb, E_ZERODIV_ERROR, "divided by 0"). The mrb_raise
      # macro now dispatches to sp_bigint_raise_zerodiv (defined non-
      # static in sp_runtime.h, linked from gen.c), which calls
      # sp_raise_cls — same longjmp path as the int-div case.

      a = 1
      i = 0
      while i < 50
        a = a * 2
        i = i + 1
      end

      # `a` is now 2^50, well above the mrb_int range — bigint-typed.

      begin
        x = a / 0
        puts "no raise"
      rescue ZeroDivisionError => e
        puts "caught bigint div: #{e}"
      end

      begin
        x = a % 0
        puts "no raise"
      rescue ZeroDivisionError => e
        puts "caught bigint mod: #{e}"
      end

      # Bare rescue also catches.
      begin
        a / 0
      rescue => e
        puts "bare-rescue: #{e}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught bigint div: divided by 0
      caught bigint mod: divided by 0
      bare-rescue: divided by 0
    OUT
  end

  it "bigint volatile combo" do
    result = ze0(<<~'RUBY')
      # Regression test: bigint operations inside begin/rescue must compile
      # clean under -Werror. Locals in setjmp-bearing functions are emitted
      # `volatile sp_Bigint *`, but the bigint runtime takes plain
      # `sp_Bigint *`. Without (sp_Bigint *) casts at every emit site, gcc
      # / clang warn about discarded qualifiers, and the test runner's
      # -Werror promotes that to a hard fail.
      #
      # Exercises every bigint operator dispatch path that previously
      # emitted a cast-free local read. Output values are not the focus —
      # the test runner gates on the C code compiling clean with -Werror.

      a = 1
      i = 0
      while i < 50
        a = a * 2
        i = i + 1
      end

      # Inside begin/rescue: every binary operator + comparison + to_s/to_i
      begin
        b = a + a
        puts b.to_s.length > 0
        c = a - a
        puts c.to_s.length > 0
        d = a * a
        puts d.to_s.length > 0
        e = a / 2
        puts e.to_s.length > 0
        f = a % 7
        puts f.to_s.length > 0
        puts a > 0
        puts a < 0
        puts a >= 0
        puts a <= 0
        puts a == a
        puts a != 0
        puts a.to_s.length > 0
        puts a.to_i > 0
      rescue
        puts "caught"
      end

      # Compound assignment inside begin/rescue. `x = x + 1` desugars to
      # LocalVariableWriteNode + CallNode; the `+=` family lowers through
      # LocalVariableOperatorWriteNode, a distinct code path that has its
      # own bigint cast in compile_LocalVariableAndWriteNode.
      begin
        x = a
        x += 1
        x *= 2
        x -= 1
        x /= 2
        x %= 7
        puts x.to_s.length > 0
      rescue
        puts "caught"
      end

      # puts/p of bigint inside begin/rescue. Single-arg dispatches through
      # compile_puts_single; multi-arg through compile_puts. Both arms have
      # their own bigint cast and need exercising. `print` lands in the
      # multi-arg path too.
      begin
        puts a
        puts a, a
        print a, "\n"
      rescue
        puts "caught"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      true
      true
      true
      false
      true
      false
      true
      true
      true
      true
      true
      1125899906842624
      1125899906842624
      1125899906842624
      1125899906842624
    OUT
  end

  it "block body rescue" do
    result = ze0(<<~'RUBY')
      r001 = [1, 2].map do |i|
        raise ArgumentError, "x" if i == 1
        i
      rescue ArgumentError
        :handled
      end
      p r001
      r2 = [1, 2].map { |i| begin; raise ArgumentError if i == 1; i; rescue ArgumentError; :h; end }
      p r2
      r3 = [1,2,3].each do |i|
        next if i == 2
      rescue StandardError
        :no
      end
      p r3
      def m3; yield 1; rescue; :caught; end
      p(m3 { |x| x * 2 })
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [:handled, 2]
      [:h, 2]
      [1, 2, 3]
      2
    OUT
  end

  it "block tail rescue modifier" do
    result = ze0(<<~'RUBY')
      # A GNU statement-expression's value is its last statement only when that
      # statement is an EXPRESSION. The statement form of a `rescue` modifier is an
      # if/else over setjmp whose two arms compute the value and drop it, so a block
      # whose tail is one produced a void:
      #
      #   error: void value not ignored as it ought to be
      #
      # The if / case / begin tails were already on the list it was missing from.
      def wrap
        p(yield)
      end

      wrap { 1 rescue 9 }
      wrap { (raise "x") rescue 9 }
      wrap { Integer("101", 2) rescue 9 }
      wrap { Integer("nope") rescue -1 }

      def twice
        [yield, yield]
      end
      p(twice { 2 rescue 0 })

      p [1, 2, 0].map { |d| 10 / d rescue :div0 }
      p ["1", "x"].map { |s| Integer(s) rescue nil }

      # and the tails that already worked, unchanged
      wrap { if true then 1 else 2 end }
      wrap { case 1 when 1 then "one" else "other" end }
      wrap { begin; 5; end }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      9
      5
      -1
      [2, 2]
      [10, 5, :div0]
      [1, nil]
      1
      "one"
      5
    OUT
  end

  it "break across rescue" do
    result = ze0(<<~'RUBY')
      # A bare `break`/`next` inside a `begin`/`rescue` targets the native loop
      # written OUTSIDE the `begin` (Batch H). The `begin` expression is spliced
      # inline in the loop body, so its final settling translates the bubbled
      # control-flow signal into the loop's own literal jump -- `ensure` still runs
      # exactly once on the way out, and a re-raised exception still propagates.

      # break out of a while loop from the begin body
      i = 0
      while i < 5
        begin
          break if i == 3
          puts "body #{i}"
        rescue
        end
        i += 1
      end
      puts "after while"

      # next from a rescue clause continues the loop
      i = 0
      while i < 5
        i += 1
        begin
          raise "even" if i.even?
          puts "odd #{i}"
        rescue
          next
        end
      end

      # ensure runs before the break crosses out
      i = 0
      while i < 4
        begin
          break if i == 2
          puts "b#{i}"
        ensure
          puts "e#{i}"
        end
        i += 1
      end

      # a break inside a nested begin bubbles through to the outer loop
      i = 0
      while i < 4
        begin
          begin
            break if i == 2
            puts "inner #{i}"
          rescue
          end
        rescue
        end
        i += 1
      end
      puts "after nested"

      # a re-raised exception is still free to propagate past the loop
      begin
        i = 0
        while i < 3
          begin
            raise "boom" if i == 1
          rescue => e
            raise "rethrow #{e.message}"
          end
          i += 1
        end
      rescue => e
        puts "caught: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      body 0
      body 1
      body 2
      after while
      odd 1
      odd 3
      odd 5
      b0
      e0
      b1
      e1
      e2
      inner 0
      inner 1
      after nested
      caught: rethrow boom
    OUT
  end

  it "break in begin still leaves a raise free to propagate" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught: rethrow boom\n"
      # The loop-crossing settle only translates Break/Next/Redo; a re-raised
      # exception still `?`-propagates out to the outer handler (H2).

      begin
        i = 0
        while i < 3
          begin
            raise "boom" if i == 1
          rescue => e
            raise "rethrow #{e.message}"
          end
          i += 1
        end
      rescue => e
        puts "caught: #{e.message}"
      end
    RUBY
  end

  it "break next from inside begin rescue nested in a real escaping block works" do
    result = ze0(<<~'RUBY')
      # A custom `yield`-based method attaches a real escaping block here
      # directly, exercising the same closure boundary `Array#each` would.
      # The begin/rescue lowering needs no
      # special handling: the block passed to `each_num` is ALREADY a real
      # escaping `Proc` (its own closure boundary, `in_real_proc` already
      # true), so a `next` inside the nested `begin`'s rescue clause raises
      # the exact same `Signal` it already would have -- caught by the Proc's
      # own wrapper loop, not by the (irrelevant here) native-loop rejection
      # check.

      class Each3
        def each_num
          yield 1
          yield 2
          yield 3
        end
      end

      Each3.new.each_num do |i|
        begin
          raise "boom" if i == 2
          puts "ok #{i}"
        rescue
          next
        ensure
          puts "ensure #{i}"
        end
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ok 1
      ensure 1
      ensure 2
      ok 3
      ensure 3
    OUT
  end

  it "builtin arg mismatches raise cruby error shapes" do
    result = ze0(<<~'RUBY')
      # The table rows validate argument TYPES with CRuby's exact TypeError/
      # ArgumentError messages (previously an arg-type mismatch degraded to
      # NoMethodError) -- all real, rescuable exceptions now.

      a = ["a"].first
      begin
        a + 1
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      arr = [[1]].first
      begin
        arr[:x]
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      one = [1].first
      begin
        one < "a"
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError: no implicit conversion of Integer into String
      TypeError: no implicit conversion of Symbol into Integer
      ArgumentError: comparison of Integer with String failed
    OUT
  end

  it "call arg valueless" do
    _(ze0(<<~'RUBY').stdout).must_equal "raised\n"
      # An argument with no value -- an unresolved call, which lowers to a raise --
      # sitting in a non-final position beside another side-effecting argument. The
      # argument-sequencing pass has nothing to sequence it into: a valueless
      # expression has no C storage, and it does not return, so no sibling can
      # observe it. Left to the argument slot, it coerces to the parameter's type.

      def join(a, b)
        a.to_s + b
      end

      key = "sid"
      begin
        puts join(nil.missing_method, "cookie." + key)
      rescue NoMethodError
        puts "raised"
      end
    RUBY
  end

  it "case in pattern matching inside a rescue body" do
    _(ze0(<<~'RUBY').stdout).must_equal "matched string: boom\n"
      # Composes pattern matching with exception handling --
      # `e.send(:message)` is a `Poly` expression, matched via `case/in`'s own
      # `#deconstruct`-independent `ClassCheck`/`Capture` path.

      begin
        raise "boom"
      rescue => e
        case e.send(:message)
        in String => s
          puts "matched string: #{s}"
        end
      end
    RUBY
  end

  it "case in with no matching arm and no else raises" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/case_in_with_no_matching_arm_and_no_else_raises.rb")
      # The message names the value and the sub-test that rejected it,
      # which is the whole diagnostic for a `case/in` -- oracle-verified.

      case 5
      in String
        puts "no"
      end
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "lang/exceptions/case_in_with_no_matching_arm_and_no_else_raises.rb:4:in '<main>': 5: String === 5 does not return true (NoMatchingPatternError)\n"
    _(result.status).must_equal 1
  end

  it "case when qualified exception" do
    result = ze0(<<~'RUBY')
      # An exception carries its fully qualified Ruby name at run time, but a
      # `when Mod::Klass` pattern node holds only the last segment. Comparing that
      # directly never matched, so the branch was silently skipped -- the case fell
      # through to no arm at all rather than mismatching visibly.
      module App
        class HelpRequested < RuntimeError; end
        class BadUsage < App::HelpRequested; end
        class Unrelated < RuntimeError; end
      end

      def classify(e)
        case e
        when App::BadUsage then "usage"
        when App::HelpRequested then "help"
        when App::Unrelated then "other"
        else "none"
        end
      end

      begin; raise App::HelpRequested; rescue => e; puts classify(e); end
      begin; raise App::BadUsage;      rescue => e; puts classify(e); end
      begin; raise App::Unrelated;     rescue => e; puts classify(e); end
      begin; raise RuntimeError;       rescue => e; puts classify(e); end

      # the subclass still matches its qualified ancestor
      begin
        raise App::BadUsage
      rescue App::HelpRequested => e
        puts e.is_a?(App::HelpRequested)
        puts e.class.to_s
      end

      # a case directly on the rescue-captured variable (the reported shape)
      $events = []
      begin
        raise App::HelpRequested
      rescue App::HelpRequested => e
        case e
        when App::HelpRequested then $events << "help"
        end
      end
      p $events
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      help
      usage
      other
      none
      true
      App::BadUsage
      ["help"]
    OUT
  end

  it "catch throw delivers values and uncaught throw raises" do
    result = ze0(<<~'RUBY')
      def thrower; throw :done, [1, 2]; end
      p catch(:done) { thrower }
      outer = Object.new; inner = Object.new
      p (catch(outer) { catch(inner) { throw outer, :to_outer }; :nr })
      begin
        throw :nope, 5; puts "WRONG"
      rescue UncaughtThrowError => e
        puts e.message
      end
      catch(:gone) { }
      begin
        throw :gone
      rescue UncaughtThrowError => e
        puts "gone: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [1, 2]
      :to_outer
      uncaught throw :nope
      gone: uncaught throw :gone
    OUT
  end

  it "catch throw ensure" do
    result = ze0(<<~'RUBY')
      # A non-local unwind -- a non-lambda proc's `return` and a `throw` -- runs the
      # `ensure` blocks it passes over before delivering, like an exception. An
      # uncaught `throw` raises a (catchable) UncaughtThrowError.

      # proc `return` runs an intervening ensure, then the home method returns.
      def ret_through_ensure
        begin
          proc { return 30 }.call
        ensure
          puts "ensure-ret"
        end
        40
      end
      p ret_through_ensure

      # Two nested ensures run inner-first as the proc return unwinds.
      def ret_through_two_ensures
        begin
          begin
            proc { return 1 }.call
          ensure
            puts "inner"
          end
        ensure
          puts "outer"
        end
        99
      end
      p ret_through_two_ensures

      # A non-matching rescue is skipped; the ensure still runs.
      def ret_nonmatching_rescue
        begin
          proc { return 7 }.call
        rescue TypeError
          puts "should-not-run"
        ensure
          puts "ensure-nonmatch"
        end
      end
      p ret_nonmatching_rescue

      # A proc return that passes through no ensure goes straight home (regression).
      def ret_no_ensure
        proc { return 5 }.call
        6
      end
      p ret_no_ensure

      # proc return passing through a rescue modifier still returns home.
      def ret_through_rescue_modifier
        x = (proc { return 9 }.call rescue 0)
        x + 100
      end
      p ret_through_rescue_modifier

      # `throw` runs an intervening ensure before reaching its catch.
      r = catch(:t) do
        begin
          throw :t, 11
        ensure
          puts "throw-ensure"
        end
      end
      p r

      # A throw to an outer tag passes an inner catch of a different tag and runs the
      # ensure between throw and the matching catch.
      r2 = catch(:outer) do
        catch(:inner) do
          begin
            throw :outer, 22
          ensure
            puts "between-ensure"
          end
        end
        :inner_normal
      end
      p r2

      # A throw NOT passing any ensure delivers directly (regression).
      p(catch(:q) { throw :q, 33 })

      # A normal exception still runs its ensure (regression).
      def raise_through_ensure
        begin
          raise "boom"
        ensure
          puts "exc-ensure"
        end
      end
      begin
        raise_through_ensure
      rescue => e
        puts "caught: #{e.message}"
      end

      # An uncaught throw raises UncaughtThrowError -- catchable by its class and by a
      # bare rescue (it is a StandardError), with a CRuby-shaped message.
      begin
        throw :nope
      rescue UncaughtThrowError => e
        puts e.message
      end

      begin
        throw :nope, 1
      rescue => e
        puts "bare: #{e.message}"
      end

      # An uncaught throw runs intervening ensures on its way out (it is an exception).
      def uncaught_runs_ensure
        begin
          throw :gone
        ensure
          puts "uncaught-ensure"
        end
      end
      begin
        uncaught_runs_ensure
      rescue UncaughtThrowError
        puts "rescued-uncaught"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ensure-ret
      30
      inner
      outer
      1
      ensure-nonmatch
      7
      5
      9
      throw-ensure
      11
      between-ensure
      22
      33
      exc-ensure
      caught: boom
      uncaught throw :nope
      bare: uncaught throw :nope
      uncaught-ensure
      rescued-uncaught
    OUT
  end

  it "class method begin rescue ensure with return" do
    result = ze0(<<~'RUBY')
      # Exercises the class-method body lowering's own `Signal::Return`
      # catch (added specifically for `Begin` nodes inside a class method --
      # class methods can't contain an escaping block at all, so `Begin` was
      # the only possible trigger there).

      class Factory
        def self.build(fail_it)
          begin
            raise "nope" if fail_it
            "built"
          rescue
            return "fallback"
          ensure
            puts "factory ensure"
          end
        end
      end
      puts Factory.build(false)
      puts Factory.build(true)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      factory ensure
      built
      factory ensure
      fallback
    OUT
  end

  it "coercion type errors name nil true false as literals not class names" do
    result = ze0(<<~'RUBY')
      # CRuby renders nil/true/false in a coercion TypeError as those words, not
      # `NilClass`/`TrueClass`/`FalseClass`; every other object uses its class
      # name (`Integer`, `Symbol`).

      def msg
        yield
      rescue TypeError => e
        puts e.message
      end
      msg { "" + nil }
      msg { "" + true }
      msg { "" + false }
      msg { "" + 1 }
      msg { "" + :s }
      msg { Float(nil) }
      msg { Integer(true) }
      # A non-class target phrase ("an exact number") keeps the CLASS name,
      # even for nil -- the value-name rule is specific to class targets.
      msg { Time.at(nil) }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      no implicit conversion of nil into String
      no implicit conversion of true into String
      no implicit conversion of false into String
      no implicit conversion of Integer into String
      no implicit conversion of Symbol into String
      can't convert nil into Float
      can't convert true into Integer
      can't convert NilClass into an exact number
    OUT
  end

  it "collection leaf methods" do
    result = ze0(<<~'RUBY')
      # Array, Hash, and Range leaf methods.

      # Array#rfind scans from the right; Array#fetch_values is strict.
      p [1, 2, 3, 4].rfind { |x| x.even? }
      p [1, 2, 3, 4].rfind { |x| x > 9 }
      p [10, 20, 30].fetch_values(0, 2)
      p([10, 20, 30].fetch_values(0, 5) { |i| i * 100 })
      begin
        [10, 20, 30].fetch_values(0, 9)
      rescue IndexError => e
        puts e.message
      end

      # Hash#to_proc turns a hash into a key-lookup callable; transform_keys! mutates.
      lookup = { a: 1, b: 2 }.to_proc
      p lookup.call(:a)
      p [:a, :b].map(&{ a: 10, b: 20 }.to_proc)
      h = { a: 1, b: 2 }
      p h.transform_keys!(&:to_s)
      p h

      # Range#overlap? tests whether two ranges share an element.
      p (1..5).overlap?(5..8)
      p (1...5).overlap?(5..8)
      p (1..5).overlap?(6..8)
      p (1..5).overlap?(0..0)
      p (1..10).overlap?(3..4)

      # String#upto walks succ values; the byte* methods index/slice on bytes.
      p "a8".upto("b1").to_a
      p "hello".byteindex("l")
      p "hello".byterindex("l")
      p "café".byteslice(0, 3)
      p "hello".byteslice(-2, 2)

      # tr_s squeezes translated runs; scrub! returns self.
      p "hello".tr_s("l", "r")
      p "aabbcc".tr_s("a-c", "x")
      p "clean".scrub!

      # Enumerable methods now reach Range and Hash.
      p (1..3).zip([4, 5, 6], [7, 8, 9])
      p (1..5).compact
      p (1..3).chain([4, 5]).to_a
      seen = []
      (1..3).cycle(2) { |x| seen << x }
      p seen
      p({ a: 1, b: 2 }.zip([10, 20]))
      p({ a: 1 }.rehash)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      4
      nil
      [10, 30]
      [10, 500]
      index 9 outside of array bounds: -3...3
      1
      [10, 20]
      {"a" => 1, "b" => 2}
      {"a" => 1, "b" => 2}
      true
      false
      false
      false
      true
      ["a8", "a9", "b0", "b1"]
      2
      3
      "caf"
      "lo"
      "hero"
      "x"
      "clean"
      [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
      [1, 2, 3, 4, 5]
      [1, 2, 3, 4, 5]
      [1, 2, 3, 1, 2, 3]
      [[[:a, 1], 10], [[:b, 2], 20]]
      {a: 1}
    OUT
  end

  it "compact definition with an absent container" do
    result = ze0(<<~'RUBY')
      # `class A::B` evaluates `A` when the definition RUNS. If nothing defines it,
      # ruby raises NameError right there and the class never comes into being --
      # it is not a load-time error, and the rest of the file is unaffected until
      # execution reaches it. zeo used to fail the whole compile instead, which cost
      # 68 gems: mostly Rails extensions reopening a host they don't depend on.

      # Reached and rescued: the constant read is what raises.
      begin
        class ActiveRecord::Associations::CollectionProxy
          def bulk_import(*args) = :never
        end
      rescue NameError => e
        puts e.class
        puts e.message
      end

      # A deeper path names its OUTERMOST missing segment, not the leaf.
      begin
        module Nope::Deeper::Still
        end
      rescue NameError => e
        puts e.message
      end

      # The definition really did not happen.
      p defined?(ActiveRecord)
      p Object.const_defined?(:Nope)

      # A container that DOES exist still works, including one reached through the
      # enclosing lexical scope.
      module Toolkit
        module CLI; end
      end
      module Toolkit
        class CLI::Common
          def helpful = :yes
        end
      end
      p Toolkit::CLI::Common.new.helpful
      p Toolkit::CLI::Common.name

      # ... and a top-anchored one.
      module Outer; end
      class ::Outer::Inner
        def here = :top
      end
      p Outer::Inner.new.here
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NameError
      uninitialized constant ActiveRecord
      uninitialized constant Nope
      nil
      false
      :yes
      "Toolkit::CLI::Common"
      :top
    OUT
  end

  it "const path deep nesting" do
    result = ze0(<<~'RUBY')
      # Stress test: ConstantPathNode resolution at depths beyond what
      # typical Ruby code reaches. const_ref_flat_name and
      # resolve_const_ref_name now have a depth=32 guard; this test
      # exercises 6 levels (well below the cap, well above the 3-4
      # levels seen in the rest of the regression suite) to catch
      # off-by-one errors in the depth bookkeeping or any premature
      # truncation.

      module L1
        module L2
          module L3
            module L4
              module L5
                class L6
                  def self.tag
                    "L1::L2::L3::L4::L5::L6"
                  end

                  def echo(s)
                    s + " <- " + L1::L2::L3::L4::L5::L6.tag
                  end
                end
              end
            end
          end
        end
      end

      puts L1::L2::L3::L4::L5::L6.tag
      puts L1::L2::L3::L4::L5::L6.new.echo("hi")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      L1::L2::L3::L4::L5::L6
      hi <- L1::L2::L3::L4::L5::L6
    OUT
  end

  it "const self ref raises name error" do
    result = ze0(<<~'RUBY')
      # Issue #646: a top-level const assigned via `<CONST> = <Class>.
      # new(...)` whose initialize body (or any method transitively
      # called from initialize) reads <CONST> now raises NameError at
      # runtime, matching MRI semantics.
      #
      # Before the fix the read returned NULL (cst_<CONST> = NULL during
      # the assignment's RHS evaluation), and a subsequent `.method` or
      # `->iv_` deref segfaulted. The reporter's tep#13 case hit this
      # via PG::Connection.new -> Tep::Scheduler.scheduled_context? ->
      # Tep::APP.sched_current.
      #
      # Implementation:
      # * analyze records `<CONST>`'s init RHS class (when it's
      #   `<Class>.new(...)`) in @const_init_class.
      # * codegen emits `static int sp_init_in_progress_<CONST>` and
      #   sets it around the assignment in main.
      # * read sites of <CONST> wrap with `(flag ? raise_NameError :
      #   cst_<CONST>)`.

      class App
        def initialize
          @arr = []
          @arr << 1   # force heap allocation so App is not value-type
          begin
            _ = APP
            puts "direct: no raise"
          rescue NameError => e
            puts "direct: " + e.message
          end
          helper
        end

        def helper
          begin
            _ = APP
            puts "indirect: no raise"
          rescue NameError => e
            puts "indirect: " + e.message
          end
        end
      end

      APP = App.new
      puts "after: APP class = " + APP.class.name
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      direct: uninitialized constant App::APP
      indirect: uninitialized constant App::APP
      after: APP class = App
    OUT
  end

  it "conv typeerror names the right class" do
    result = ze0(<<~'RUBY')
      # The class a conversion TypeError names has to survive the emission that sits
      # between taking it and writing it. class_ruby_name built the qualified name
      # into a shared static buffer, so a message built as
      #
      #   cn = class_ruby_name(...);  emit_expr(arg);  printf("...%s...", cn)
      #
      # printed whichever class the argument's own emission asked about. Below, the
      # inner conversion is EMITTED but never runs (its branch is not taken), and it
      # was enough to rename the error the outer one raises.
      #
      # The same buffer is why `is_a?` on a namespaced exception compared its
      # receiver against itself (#4133).
      module M
        class Alpha; end
        class Beta; end
      end

      x = M::Beta.new
      cond = (ARGV.length > 99)

      begin
        p 1.0.quo(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x)
      rescue TypeError => e
        p e.message
      end

      # The same shape through the Array and Hash protocols, which name a class the
      # same way.
      begin
        p [1, 2].product(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x)
      rescue TypeError => e
        p e.message
      end

      begin
        p({ 1 => 2 }.merge(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x))
      rescue TypeError => e
        p e.message
      end

      # A top-level class is not qualified and never used the buffer, so it was
      # right all along -- pinned so a future change cannot take it the other way.
      class Plain; end
      begin
        p 1.0.quo(Plain.new)
      rescue TypeError => e
        p e.message
      end

      # Two nested classes named in one expression, each keeping its own name.
      begin
        p 1.0.quo(M::Alpha.new)
      rescue TypeError => e
        p e.message
      end
      begin
        p 1.0.quo(M::Beta.new)
      rescue TypeError => e
        p e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "M::Beta can't be coerced into Float"
      "no implicit conversion of M::Beta into Array"
      "no implicit conversion of M::Beta into Hash"
      "Plain can't be coerced into Float"
      "M::Alpha can't be coerced into Float"
      "M::Beta can't be coerced into Float"
    OUT
  end

  it "current exception" do
    result = ze0(<<~'RUBY')
      # `$!` is the exception currently being handled -- inside any rescue,
      # including the one-line modifier form, it refers to the caught exception,
      # and is nil outside a rescue.
      p $!                                    # nil (nothing being handled)

      result = Integer("not a number") rescue $!.class
      p result                                # ArgumentError

      begin
        raise TypeError, "bad value"
      rescue
        puts "handling: #{$!.message}"        # handling: bad value
        puts "class: #{$!.class}"             # class: TypeError
      end

      p $!                                    # nil again (handling finished)

      # Exception#inspect renders "#<ClassName: message>", or just the class name
      # when the message is empty.
      p RuntimeError.new("boom").inspect      # "#<RuntimeError: boom>"
      p ArgumentError.new("").inspect         # "ArgumentError"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      ArgumentError
      handling: bad value
      class: TypeError
      nil
      "#<RuntimeError: boom>"
      "ArgumentError"
    OUT
  end

  it "deep object chain release" do
    result = ze0(<<~'RUBY')
      # Releasing a long chain of objects must not cost one stack frame per link.
      class Link
        attr_accessor :nxt
        def initialize(n)
          @nxt = n
          @tag = "link"
        end
      end

      def chain(len)
        head = nil
        len.times { head = Link.new(head) }
        head
      end

      head = chain(200_000)
      n = 0
      cur = head
      while cur
        n += 1
        cur = cur.nxt
      end
      p n

      # Dropping the only reference releases all 200,000 at once.
      head = nil
      GC.start
      p chain(200_000).nxt.nxt.nil?

      # A chain through an ivar that a runtime path invented releases the same way.
      deep = Link.new(nil)
      200_000.times do
        outer = Link.new(nil)
        outer.instance_variable_set(:@inner, deep)
        deep = outer
      end
      p deep.instance_variable_get(:@inner).class
      deep = nil
      GC.start
      p "released"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      200000
      false
      Link
      "released"
    OUT
  end

  it "defined does not swallow nomethoderror" do
    result = ze0(<<~'RUBY')
      # `defined?` must answer `nil` for a call chain that cannot run, never raise.
      # zeo evaluates the receiver chain and lets the `NoMethodError` escape.
      #
      # Ruby evaluates a method-call `defined?` by resolving each link and stopping at
      # the first miss (`defined?`'s `NODE_CALL` case walks the receiver, then probes
      # the method table without invoking). zeo emits the chain and guards only the
      # LAST send, so an intermediate miss escapes as an ordinary raise.
      #
      # This is the idiom's whole point -- `defined?(a.b.c)` is how ruby code asks
      # "is this reachable?" without a rescue -- so a raise here defeats the guard the
      # programmer wrote.

      # The single-link forms already answer correctly.
      p defined?([].size)
      p defined?(String.nope)
      p defined?([].nope)

      # ...and the chain raises rather than answering nil.
      p defined?([].nope.nope)
      p defined?(nil.foo.bar)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "method"
      nil
      nil
      nil
      nil
    OUT
  end

  it "definition hook defaults" do
    result = ze0(<<~'RUBY')
      # Ruby tells a class what was just defined in it, through eight private hooks.
      # This file covers only their DEFAULTS -- that they exist, that they are
      # private, that `super` reaches them, and that the three mix-in primitives
      # really do the mixing. What CALLS them is covered elsewhere.

      p Module.private_instance_methods(false).grep(/features|extend_object|added|removed|undefined/).sort
      p BasicObject.private_instance_methods(false).sort
      p [Module.private_method_defined?(:prepend_features), Module.method_defined?(:prepend_features)]
      p Module.instance_method(:const_added).arity

      # Private means private: an explicit receiver is refused.
      begin
        Comparable.prepend_features(Class.new)
      rescue NoMethodError => e
        puts "explicit: #{e.message}"
      end

      # The defaults answer nil and take exactly one argument.
      class Probe
        def self.reach(hook, arg) = send(hook, arg)
      end
      %i[method_added method_removed method_undefined const_added].each do |hook|
        puts "#{hook} -> #{Probe.reach(hook, :x).inspect}"
      end
      %i[singleton_method_added singleton_method_removed singleton_method_undefined].each do |hook|
        puts "#{hook} -> #{Object.new.send(hook, :x).inspect}"
      end

      # `prepend_features`/`append_features`/`extend_object` are the primitives that
      # perform the mixin -- not notifications. Called directly, they mix in.
      m = Module.new { def hi = "hi from M" }
      k = Class.new
      m.send(:prepend_features, k)
      p [k.ancestors.include?(m), k.new.hi]

      n = Module.new { def yo = "yo from N" }
      k2 = Class.new
      n.send(:append_features, k2)
      p [k2.ancestors.include?(n), k2.new.yo]

      o = Object.new
      Module.new { def ext = "extended" }.send(:extend_object, o)
      p o.ext

      # An override reaches the default through `super`, which is the whole reason
      # the defaults exist.
      class Sub
        def self.method_added(name)
          puts "Sub saw #{name.inspect}, super -> #{super.inspect}"
        end
      end
      p Sub.send(:method_added, :manual)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [:append_features, :const_added, :extend_object, :method_added, :method_removed, :method_undefined, :prepend_features]
      [:initialize, :method_missing, :singleton_method_added, :singleton_method_removed, :singleton_method_undefined]
      [true, false]
      1
      explicit: private method 'prepend_features' called for module Comparable
      method_added -> nil
      method_removed -> nil
      method_undefined -> nil
      const_added -> nil
      singleton_method_added -> nil
      singleton_method_removed -> nil
      singleton_method_undefined -> nil
      [true, "hi from M"]
      [true, "yo from N"]
      "extended"
      Sub saw :manual, super -> nil
      nil
    OUT
  end

  it "did you mean library" do
    _(ze0(<<~'RUBY').stdout).must_equal "false\n\"constant\"\n[\"length\"]\nundefined local variable or method 'frist_name' for main (NameError)\n\n  frist_name\n  ^^^^^^^^^^\nDid you mean?  first_name\n"
      # did_you_mean is loaded before the program, as ruby's gem prelude loads
      # it, and a NameError names the locals and methods it may have meant.
      p require("did_you_mean")
      p defined?(DidYouMean)
      p DidYouMean::SpellChecker.new(dictionary: %w[length size]).correct("lenght")
      first_name = "x"
      begin
        frist_name
      rescue NameError => e
        puts e.detailed_message(highlight: false)
      end

    RUBY
  end

  it "dollar bang reads the exception being handled" do
    result = ze0(<<~'RUBY')
      # `$!` is the current exception inside a rescue (block or modifier form),
      # nil outside one.

      p $!
      r = (Integer("x") rescue $!.class)
      p r
      begin
        raise "boom"
      rescue
        puts $!.message
      end
      p $!
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      ArgumentError
      boom
      nil
    OUT
  end

  it "dot class works on rescue bindings and poly receivers" do
    result = ze0(<<~'RUBY')
      begin
        raise "boom"
      rescue => e
        puts e.class
      end

      mixed = [1, "two", nil]
      mixed.each do |v|
        puts v.class
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      RuntimeError
      Integer
      String
      NilClass
    OUT
  end

  it "dup and clone of uncopyable handles raise cruby shapes" do
    result = ze0(<<~'RUBY')
      # The former loud-panic tier is real, rescuable raises now -- every
      # message verbatim from ruby 4.0.6. Fiber is the special one: CRuby's
      # shallow copy succeeds but skips the machine stack, so the COPY is an
      # uninitialized fiber (resume raises) while the original still runs.
      # Concurrent join/value on one Thread hands every joiner the outcome.

      begin; Thread.current.dup; rescue TypeError => e; puts "thread: #{e.message}"; end
      begin; Queue.new.clone; rescue NoMethodError => e; puts "queue: #{e.message}"; end
      begin; SizedQueue.new(1).dup; rescue NoMethodError => e; puts "sq: #{e.message}"; end
      g = Fiber.new { 42 }.dup
      begin; g.resume; rescue FiberError => e; puts "fiber: #{e.message}"; end
      f = Fiber.new { 7 }
      f.dup
      puts "orig: #{f.resume}"
      e = [1, 2].each
      e.next
      begin; e.dup; rescue TypeError => ex; puts "enum: #{ex.message}"; end
      t = Thread.new { sleep 0.05; :done }
      a = Thread.new { t.value }
      b = Thread.new { t.value }
      puts "joins: #{a.value} #{b.value}"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      thread: allocator undefined for Thread
      queue: undefined method 'initialize_copy' for an instance of Thread::Queue
      sq: undefined method 'initialize_copy' for an instance of Thread::SizedQueue
      fiber: uninitialized fiber
      orig: 7
      enum: can't copy execution context
      joins: done done
    OUT
  end

  it "else clause runs only on the no exception path" do
    result = ze0(<<~'RUBY')
      begin
        puts "body"
      rescue
        puts "rescued"
      else
        puts "else ran"
      ensure
        puts "ensure ran"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      body
      else ran
      ensure ran
    OUT
  end

  it "ensure runs on return" do
    result = ze0(<<~'RUBY')
      # `begin..ensure..end` must run the ensure clause when the body
      # exits via `return` (bare or with a value). Previously the
      # generated C placed the ensure body *after* the unconditional
      # `return` it followed, so the writeback was dead code.

      class C
        def initialize
          @x = 0
          @v = 0
          @a = 0
        end

        def bare_return
          begin
            x = 100
            return
          ensure
            @x = x
          end
        end

        def value_return
          begin
            v = 7
            return v * 6
          ensure
            @v = v
          end
        end

        def multi_return(c)
          begin
            a = 1
            if c == 1
              return 11
            end
            a = 2
            if c == 2
              return 22
            end
            a = 3
          ensure
            @a = a
          end
        end

        def report
          bare_return
          puts value_return
          multi_return(1)
          puts "a1=" + @a.to_s
          multi_return(2)
          puts "a2=" + @a.to_s
          multi_return(3)
          puts "a3=" + @a.to_s
          puts @x
          puts @v
        end
      end

      C.new.report
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      42
      a1=1
      a2=2
      a3=3
      100
      7
    OUT
  end

  it "ensure runs when no exception is raised and there is no rescue at all" do
    result = ze0(<<~'RUBY')
      begin
        puts "no exception"
      ensure
        puts "ensure always"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      no exception
      ensure always
    OUT
  end

  it "ensure still runs when break crosses out of a begin" do
    result = ze0(<<~'RUBY')
      # The bubbled `break` is translated only AFTER `ensure` runs, exactly once
      # -- the loop-crossing settle sits below the ensure block (H2).

      i = 0
      while i < 4
        begin
          break if i == 2
          puts "b#{i}"
        ensure
          puts "e#{i}"
        end
        i += 1
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      b0
      e0
      b1
      e1
      e2
    OUT
  end

  it "env dup clone freeze raise type error" do
    result = ze0(<<~'RUBY')
      # ENV overrides Kernel#dup/#clone/#freeze to raise (copy it via ENV.to_h).
      # These must route through dispatch, not the universal value fast paths,
      # which would silently shallow-copy/freeze the singleton instead.

      ENV['ZZ_E2E'] = '1'
      p (ENV.dup rescue $!.message)
      p (ENV.clone rescue $!.message)
      p (ENV.freeze rescue $!.message)
      p ENV['ZZ_E2E']
      p ENV.store('ZZ_E2E2', '3')
      p ENV.delete('ZZ_E2E2')
      p ENV.to_s
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "Cannot dup ENV, use ENV.to_h to get a copy of ENV as a hash"
      "Cannot clone ENV, use ENV.to_h to get a copy of ENV as a hash"
      "cannot freeze ENV"
      "1"
      "3"
      "3"
      "ENV"
    OUT
  end

  it "env error shapes" do
    result = ze0(<<~'RUBY')
      # ENV's error shapes: a non-String key is a TypeError, a bare `fetch` miss
      # is a KeyError.

      begin
        ENV[:PATH]
      rescue TypeError => e
        puts "TypeError"
      end
      begin
        ENV.fetch("ZEO_DEFINITELY_ABSENT")
      rescue KeyError => e
        puts "KeyError"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      KeyError
    OUT
  end

  it "errno messages name crubys call sites" do
    result = ze0(<<~'RUBY')
      # A SystemCallError message's `@ site` names CRuby's own C function, not
      # the syscall: `@ rb_sysopen`, `@ io_fread`, `@ dir_chdir0`,
      # `@ rb_check_realpath_internal`, `@ rb_file_s_stat`, `@ apply2files`, and
      # `@ rb_file_s_rename - (a, b)` with BOTH paths. zeo names the syscall
      # (`@ read`, `@ chdir`, ...). `File.expand_path("~nouser")` also words its
      # ArgumentError differently. (Found by the 2026-08-24 probe sweep.)
      def show
        yield
      rescue SystemCallError, ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
      show { File.read("/tmp") }
      show { Dir.chdir("/nonexistent_zeo_probe_xyz") { } }
      show { File.realpath("/nonexistent_zeo_probe_xyz") }
      show { File.stat("/nonexistent_zeo_probe_xyz") }
      show { File.delete("/nonexistent_zeo_probe_xyz") }
      show { File.rename("/nonexistent_zeo_probe_xyz", "/tmp/zzz") }
      show { File.expand_path("~xyz_no_such_user_probe") }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Errno::EISDIR: Is a directory @ io_fread - /tmp
      Errno::ENOENT: No such file or directory @ dir_chdir0 - /nonexistent_zeo_probe_xyz
      Errno::ENOENT: No such file or directory @ rb_check_realpath_internal - /nonexistent_zeo_probe_xyz
      Errno::ENOENT: No such file or directory @ rb_file_s_stat - /nonexistent_zeo_probe_xyz
      Errno::ENOENT: No such file or directory @ apply2files - /nonexistent_zeo_probe_xyz
      Errno::ENOENT: No such file or directory @ rb_file_s_rename - (/nonexistent_zeo_probe_xyz, /tmp/zzz)
      ArgumentError: user xyz_no_such_user_probe doesn't exist
    OUT
  end

  it "errno sites name crubys c functions" do
    result = ze0(<<~'RUBY')
      # The `@ site` in a SystemCallError message names CRuby's own C FUNCTION,
      # not the syscall underneath it. `File.stat` says `rb_file_s_stat`,
      # `File.delete` says `apply2files` (the shared helper behind chmod, chown,
      # utime and unlink alike), and a two-path operation prints BOTH operands:
      # `... @ rb_file_s_rename - (from, to)`.
      #
      # Two rows are where the mapping stops being mechanical. `Dir.chdir` names
      # a DIFFERENT function per form -- `dir_chdir0` with a block, `chdir_path`
      # without -- and reading a DIRECTORY says `io_fread`, because CRuby opens
      # and then reads, and only the read can answer EISDIR. One native call covers
      # both steps, so that site is picked from the errno.
      #
      # `File.readlines(a_directory)` is deliberately absent: CRuby answers
      # `@ io_fillbuf - fd:6 <path>`, naming a buffered-read helper AND the raw
      # descriptor number, which is not reproducible across runs.

      require "tmpdir"
      D = Dir.mktmpdir
      M = File.join(D, "gone")
      E = File.join(D, "here")
      File.write(E, "hi")
      def show(n)
        yield
      rescue Exception => e
        puts "#{n}\t#{e.class}: #{e.message.gsub(D, '<T>')}"
      end
      show("atime") { File.atime(M) }
      show("ctime") { File.ctime(M) }
      show("birthtime") { File.birthtime(M) }
      show("lstat") { File.lstat(M) }
      show("stat") { File.stat(M) }
      show("size") { File.size(M) }
      show("mtime") { File.mtime(M) }
      show("truncate") { File.truncate(M, 0) }
      show("realdirpath") { File.realdirpath(M) }
      show("link") { File.link(E, E) }
      show("symlink") { File.symlink(E, E) }
      show("rename") { File.rename(M, E) }
      show("chmod") { File.chmod(0o600, M) }
      show("chown") { File.chown(nil, nil, M) }
      show("utime") { File.utime(Time.now, Time.now, M) }
      show("delete") { File.delete(M) }
      show("readlink") { File.readlink(M) }
      show("expand ~x") { File.expand_path("~xyz_no_user") }
      show("Dir.mkdir") { Dir.mkdir(D) }
      show("Dir.rmdir") { Dir.rmdir(M) }
      show("Dir.entries") { Dir.entries(M) }
      show("Dir.open") { Dir.open(M) }
      show("Dir.new") { Dir.new(M) }
      show("IO.read dir") { IO.read(D) }
      show("chdir no block") { Dir.chdir(M) }
      show("chdir block") { Dir.chdir(M) { 1 } }
      show("File.read dir") { File.read(D) }
      show("File.open missing") { File.open(M) }
      show("File.write dir") { File.write(D, "x") }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      atime	Errno::ENOENT: No such file or directory @ rb_file_s_atime - <T>/gone
      ctime	Errno::ENOENT: No such file or directory @ rb_file_s_ctime - <T>/gone
      birthtime	Errno::ENOENT: No such file or directory @ rb_file_s_birthtime - <T>/gone
      lstat	Errno::ENOENT: No such file or directory @ rb_file_s_lstat - <T>/gone
      stat	Errno::ENOENT: No such file or directory @ rb_file_s_stat - <T>/gone
      size	Errno::ENOENT: No such file or directory @ rb_file_s_size - <T>/gone
      mtime	Errno::ENOENT: No such file or directory @ rb_file_s_mtime - <T>/gone
      truncate	Errno::ENOENT: No such file or directory @ rb_file_s_truncate - <T>/gone
      link	Errno::EEXIST: File exists @ syserr_fail2_in - <T>/here
      symlink	Errno::EEXIST: File exists @ syserr_fail2_in - <T>/here
      rename	Errno::ENOENT: No such file or directory @ rb_file_s_rename - (<T>/gone, <T>/here)
      chmod	Errno::ENOENT: No such file or directory @ apply2files - <T>/gone
      chown	Errno::ENOENT: No such file or directory @ apply2files - <T>/gone
      utime	Errno::ENOENT: No such file or directory @ apply2files - <T>/gone
      delete	Errno::ENOENT: No such file or directory @ apply2files - <T>/gone
      readlink	Errno::ENOENT: No such file or directory @ rb_readlink - <T>/gone
      expand ~x	ArgumentError: user xyz_no_user doesn't exist
      Dir.mkdir	Errno::EEXIST: File exists @ dir_s_mkdir - <T>
      Dir.rmdir	Errno::ENOENT: No such file or directory @ dir_s_rmdir - <T>/gone
      Dir.entries	Errno::ENOENT: No such file or directory @ dir_initialize - <T>/gone
      Dir.open	Errno::ENOENT: No such file or directory @ dir_initialize - <T>/gone
      Dir.new	Errno::ENOENT: No such file or directory @ dir_initialize - <T>/gone
      IO.read dir	Errno::EISDIR: Is a directory @ io_fread - <T>
      chdir no block	Errno::ENOENT: No such file or directory @ chdir_path - <T>/gone
      chdir block	Errno::ENOENT: No such file or directory @ dir_chdir0 - <T>/gone
      File.read dir	Errno::EISDIR: Is a directory @ io_fread - <T>
      File.open missing	Errno::ENOENT: No such file or directory @ rb_sysopen - <T>/gone
      File.write dir	Errno::EISDIR: Is a directory @ rb_sysopen - <T>
    OUT
  end

  it "error highlight library" do
    _(ze0(<<~'RUBY').stdout).must_equal "false\n\"constant\"\ntrue\nundefined method 'nope' for nil (NoMethodError)\n\n  nil.nope\n     ^^^^^\n"
      # error_highlight is loaded before the program, as ruby's gem prelude
      # loads it: a require of it answers false, and `detailed_message` shows
      # the line with a caret run under the call that failed. The program
      # carries no parser; the compiler found each spot while it held the tree.

      p require("error_highlight")
      p defined?(ErrorHighlight)
      p ErrorHighlight.respond_to?(:spot)

      def boom
        nil.nope
      rescue NoMethodError => e
        puts e.detailed_message(highlight: false)
      end
      boom

    RUBY
  end

  it "error protocol edges" do
    result = ze0(<<~'RUBY')
      # CRuby error-protocol edges:
      # - float modulo by zero raises ZeroDivisionError (int or float divisor);
      #   the divisor-sign result rule is preserved for nonzero divisors
      # - Array#first(n)/#last(n) with a negative count raise ArgumentError
      # - a rescue binding inside a yield-inlined method body resolves (the
      #   assignment used the unrenamed local and did not compile)
      def t
        yield
      rescue => e
        e.class.to_s
      end
      p t { 5.0 % 0 }
      p t { 5.0 % 0.0 }
      p t { -5.5 % 2 }
      p t { [1, 2, 3].first(-1) }
      p t { [1, 2, 3].last(-2) }
      p t { [1.0, 2.0].first(-1) }
      p t { [1, 2, 3].first(2) }
      p t { [1, 2, 3].last(2) }
      p t { 5 % 0 }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ZeroDivisionError"
      "ZeroDivisionError"
      0.5
      "ArgumentError"
      "ArgumentError"
      "ArgumentError"
      [1, 2]
      [2, 3]
      "ZeroDivisionError"
    OUT
  end

  it "eval of invalid literal source raises a catchable syntax error" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught\n"
      # A literal `eval("...")` whose source doesn't parse does not fail the
      # COMPILE: it falls through to the runtime `eval` and raises a catchable
      # SyntaxError, exactly as CRuby does.

      begin; eval("1 +"); rescue SyntaxError; puts "caught"; end
    RUBY
  end

  it "eval syntax error is catchable at runtime" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught\n"
      bad = "1 +"
      begin
        eval(bad)
      rescue SyntaxError
        puts "caught"
      end
    RUBY
  end

  it "exc stack window cleared" do
    _(ze0(<<~'RUBY').stdout).must_equal "true\n"
      # The exception stack's mark window follows sp_exc_top up and down, and a slot
      # that leaves it kept its pointer. Pop below a used slot, collect (the object
      # is now unreferenced, so it is freed), then push back over it, and the window
      # covers a dangling pointer again -- the collector then walks a header that the
      # allocator has since handed to a string.
      #
      # The slots above the window are cleared where the window is defined, so after
      # any collection a slot outside it holds nothing. This exercises the shape:
      # nesting that oscillates across a used depth, with allocation in between.

      class MissingTemplate < StandardError; end

      def churn(i)
        s = +""
        10.times { |j| s << "<input name=\"f#{i}_#{j}\" value=\"_csrf_token\">" }
        s.length
      end

      def deep(n, i)
        return (raise MissingTemplate, "t#{i}") if n == 0
        begin
          deep(n - 1, i)
        rescue MissingTemplate => e
          churn(i)
          raise e if n > 1
          e.message.length
        end
      end

      total = 0
      2000.times do |i|
        d = (i % 3) + 1
        begin
          total += deep(d, i)
        rescue MissingTemplate
          total += 1
        end
        total += churn(i)
      end
      p total > 0
    RUBY
  end

  it "exception attributes raise when unset and private call flag" do
    result = ze0(<<~'RUBY')
      # KeyError#key / #receiver and NameError#receiver raise ArgumentError when
      # never set, but a real miss (nil.foo, h.fetch) sets them. NoMethodError's
      # 4th positional is the private_call? flag.

      p((begin; KeyError.new("m").key; rescue => e; e.class; end))
      p((begin; KeyError.new("m").receiver; rescue => e; e.class; end))
      p((begin; NoMethodError.new("m").receiver; rescue => e; e.class; end))
      p((begin; NameError.new("m", :n).receiver; rescue => e; e.class; end))
      p((begin; KeyError.new("m", key: :k, receiver: {}).key; rescue => e; e.class; end))
      p((begin; nil.foo; rescue => e; e.receiver; end))
      h = { a: 1 }
      p((begin; h.fetch(:z); rescue => e; e.key; end))
      p NoMethodError.new("m", :nm, [1], true).private_call?
      p NoMethodError.new("m", :nm, [1]).private_call?
      p NoMethodError.new("m", :nm, [1, 2]).args
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      :k
      nil
      :z
      true
      false
      [1, 2]
    OUT
  end

  it "exception cause" do
    result = ze0(<<~'RUBY')
      # Exception#cause: the exception being handled when a new one is raised
      # is threaded in automatically as the new exception's cause.
      begin
        begin
          raise "root failure"
        rescue
          raise TypeError, "while handling"
        end
      rescue => e
        puts e.class
        puts e.message
        puts e.cause.class
        puts e.cause.message
      end

      # A top-level raise (no active rescue) has no cause.
      begin
        raise "lonely"
      rescue => e
        p e.cause
      end

      # A builtin-raised error inside a rescue also chains.
      begin
        begin
          Integer("not a number")
        rescue
          raise "rewrapped"
        end
      rescue => e
        puts e.cause.class
        puts e.cause.message
      end

      # Three-deep chain.
      begin
        begin
          begin
            raise "level 1"
          rescue
            raise "level 2"
          end
        rescue
          raise "level 3"
        end
      rescue => e
        puts e.message
        puts e.cause.message
        puts e.cause.cause.message
        p e.cause.cause.cause
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      while handling
      RuntimeError
      root failure
      nil
      ArgumentError
      invalid value for Integer(): "not a number"
      level 3
      level 2
      level 1
      nil
    OUT
  end

  it "exception cause chains from active rescue" do
    result = ze0(<<~'RUBY')
      begin
        begin
          raise "inner"
        rescue
          raise "outer"
        end
      rescue => e
        puts e.message
        puts e.cause.message
        puts e.cause.class
      end
      begin
        raise "solo"
      rescue => e
        p e.cause
      end
      begin
        begin
          Integer("x")
        rescue
          raise ArgumentError, "wrapped"
        end
      rescue => e
        puts e.cause.class
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      outer
      inner
      RuntimeError
      nil
      ArgumentError
    OUT
  end

  it "exception cause ensure reraise" do
    result = ze0(<<~'RUBY')
      r001 = (begin
        begin
          raise ArgumentError, "orig"
        ensure
          raise TypeError, "in-ensure"
        end
      rescue => e001
        [e001.class.to_s, e001.cause.class.to_s]
      end); p r001

      r002 = (begin
        begin
          begin; raise ArgumentError, "a"; rescue; raise TypeError, "b"; end
        rescue
          raise
        end
      rescue => e002
        [e002.class.to_s, e002.cause.class.to_s]
      end); p r002
      r3 = (begin; begin; raise "x"; rescue => e; raise ArgumentError, "y"; end; rescue => f; [f.class.to_s, f.cause.class.to_s]; end); p r3
      r4 = (begin; raise "z"; rescue => g; g.cause.inspect; end); p r4
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["TypeError", "ArgumentError"]
      ["TypeError", "ArgumentError"]
      ["ArgumentError", "RuntimeError"]
      "nil"
    OUT
  end

  it "exception class constants" do
    result = ze0(<<~'RUBY')
      # Builtin exception classes as first-class values: referencing the constant
      # (raise_error matchers, e.class comparisons, superclass walks) works like any
      # other builtin class object; raise/rescue position already resolved by name.
      # RuntimeError.superclass is StandardError (CRuby), previously Exception.
      p IndexError
      p FrozenError
      x = ZeroDivisionError
      p x
      p IndexError.name
      begin; raise IndexError, "m"; rescue => e; p e.class == IndexError; end
      p KeyError.superclass
      p FrozenError.superclass
      p RuntimeError.superclass
      p NotImplementedError.superclass
      p FloatDomainError.ancestors.include?(RangeError)
      p IndexError < StandardError
      p LocalJumpError <= Exception
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      IndexError
      FrozenError
      ZeroDivisionError
      "IndexError"
      true
      IndexError
      RuntimeError
      StandardError
      ScriptError
      true
      true
      true
    OUT
  end

  it "exception class new" do
    result = ze0(<<~'RUBY')
      # Phase 1C: built-in exception class `.new("msg")`.
      # `RuntimeError.new(...)`, `ArgumentError.new(...)` etc. previously
      # emitted an undefined `sp_RuntimeError` type (the analyze inferred
      # obj_RuntimeError but no struct backed it). Spinel now models
      # built-in exception objects as their message string plus a
      # side-channel cls name -- the same convention `rescue => e` uses.
      #
      # Covers (Phase 1C):
      #   - CLS.new("msg") with various exception classes
      #   - .class returns the class name (string in spinel)
      #   - .message returns the msg
      #   - .is_a? walks the hierarchy
      #
      # Covers (Phase 1D):
      #   - raise <exception_object> -- raise a pre-built exc
      #   - raise CLS.new("msg") -- raise an inline-constructed exc

      err = RuntimeError.new("created")
      puts err.class                     # RuntimeError
      puts err.message                   # created
      puts err.is_a?(RuntimeError)       # true
      puts err.is_a?(StandardError)      # true
      puts err.is_a?(Exception)          # true

      # raise the saved object
      begin
        raise err
      rescue => e
        puts "caught: #{e.class}: #{e.message}"
      end

      # raise an inline-constructed exception (1D)
      begin
        raise ArgumentError.new("inline ae")
      rescue => e
        puts "inline: #{e.class}: #{e.message}"
      end

      # StandardError subclass with .new
      e2 = TypeError.new("bad type")
      puts e2.class                      # TypeError
      puts e2.message                    # bad type

      # Various built-in exception classes
      e3 = NoMethodError.new("missing")
      puts e3.class                      # NoMethodError
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      RuntimeError
      created
      true
      true
      true
      caught: RuntimeError: created
      inline: ArgumentError: inline ae
      TypeError
      bad type
      NoMethodError
    OUT
  end

  it "exception classes work across namespaces" do
    result = ze0(<<~'RUBY')
      # Subclassing a nested error class from outside, raising with a
      # qualified path, and rescue-matching through the shared ancestor.

      module Errs
        class Base3 < StandardError
        end
      end

      class Deep < Errs::Base3
      end

      begin
        raise Deep, "boom"
      rescue Errs::Base3 => e
        puts "caught #{e.message}"
      end

      begin
        raise Errs::Base3, "direct"
      rescue StandardError => e
        puts "caught #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught boom
      caught direct
    OUT
  end

  it "exception detailed message" do
    result = ze0(<<~'RUBY')
      # Exception#detailed_message returns "message (ClassName)". (The core method;
      # the optional error_highlight gem's source-snippet augmentation, which applies
      # to a few argument-style errors, is a separate concern and not reproduced.)

      # a RuntimeError carrying a message
      begin
        raise "boom"
      rescue => e
        p e.detailed_message            # "boom (RuntimeError)"
      end

      # an explicit class with a message
      begin
        raise StandardError, "bad state"
      rescue => e
        p e.detailed_message            # "bad state (StandardError)"
      end

      # no message -> the class name is used as the message
      begin
        raise RuntimeError
      rescue => e
        p e.detailed_message            # "RuntimeError (RuntimeError)"
      end

      # a user-defined exception subclass
      class MyError < StandardError; end
      begin
        raise MyError, "oops"
      rescue => e
        p e.detailed_message            # "oops (MyError)"
      end

      # message and detailed_message side by side
      begin
        raise "x"
      rescue => e
        p [e.message, e.detailed_message]   # ["x", "x (RuntimeError)"]
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "boom (RuntimeError)"
      "bad state (StandardError)"
      "RuntimeError (RuntimeError)"
      "oops (MyError)"
      ["x", "x (RuntimeError)"]
    OUT
  end

  it "exception empty message" do
    result = ze0(<<~'RUBY')
      r001 = (begin; raise; rescue RuntimeError => e001; [e001.class.to_s, e001.message]; end); p r001
      p RuntimeError.new.message
      r2 = (begin; raise "x"; rescue => e; e.message; end); p r2
      r3 = (begin; raise RuntimeError; rescue => e; e.message; end); p r3
      r4 = (begin; raise ArgumentError, ""; rescue => e; e.message; end); p r4
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["RuntimeError", ""]
      "RuntimeError"
      "x"
      "RuntimeError"
      ""
    OUT
  end

  it "exception equality exception method and message coercion" do
    result = ze0(<<~'RUBY')
      e = RuntimeError.new("m")
      e2 = RuntimeError.new("m")
      p e == e2
      p e == RuntimeError.new("other")
      p e == "not an exception"
      p e.eql?(e)
      p e.eql?(e2)
      p e.exception.equal?(e)
      p e.exception("n").message
      p e.exception("n").equal?(e)
      p RuntimeError.exception("z").message
      p RuntimeError.exception("z").class
      p RuntimeError.new(42).message
      p RuntimeError.new(:sym).message
      p ArgumentError.new([1, 2]).message
      p [true, false].include?(Exception.to_tty?)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      false
      true
      false
      true
      "n"
      false
      "z"
      RuntimeError
      "42"
      "sym"
      "[1, 2]"
      true
    OUT
  end

  it "exception exception subclass copy" do
    result = ze0(<<~'RUBY')
      class SimpleError < StandardError
        attr_reader :code
        def initialize(code); @code = code; super("simple"); end
      end
      e010 = SimpleError.new(3); f010 = e010.exception("other"); p f010.class; p f010.message

      e = SimpleError.new(7)
      f = e.exception("changed")
      p f.code
      p f.equal?(e)
      p e.exception.equal?(e)
      r = (raise SimpleError.new(9) rescue $!.exception("x")); p [r.class, r.message]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      SimpleError
      "other"
      7
      false
      true
      [SimpleError, "x"]
    OUT
  end

  it "exception freeze" do
    result = ze0(<<~'RUBY')
      # freeze on an exception was a no-op and frozen? a hard-coded false, so an
      # exception the program froze itself still read back unfrozen.
      p(RuntimeError.new("f").freeze.frozen?)
      e = RuntimeError.new("f").freeze
      p e.frozen?
      class S1 < StandardError; end
      s = S1.new("x").freeze
      p s.frozen?
      p "a".freeze.frozen?
      p RuntimeError.new("g").frozen?
      begin
        raise "boom"
      rescue => x
        p x.frozen?
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      true
      false
      false
    OUT
  end

  it "exception full message without backtrace" do
    _(ze0(<<~'RUBY', path: "lang/exceptions/exception_full_message_without_backtrace.rb").stdout).must_equal "nil\n\"lang/exceptions/exception_full_message_without_backtrace.rb:7:in 'full_message': msg (StandardError)\\n\"\n\"lang/exceptions/exception_full_message_without_backtrace.rb:11:in 'full_message': unhandled exception\\n\"\n\"lang/exceptions/exception_full_message_without_backtrace.rb:12:in 'full_message': StandardError\\n\"\n\"StandardError\"\n\"\\e[1;4munhandled exception\\e[m\"\n\"a.rb:1:in 'x': msg (StandardError)\\n\\tfrom b.rb:2:in 'y'\\n\\tfrom c.rb:3:in 'z'\\n\"\n\"Traceback (most recent call last):\\n\\t2: from c.rb:3:in 'z'\\n\\t1: from b.rb:2:in 'y'\\na.rb:1:in 'x': msg (StandardError)\\n\"\n\"a.rb:1:in 'x': \\e[1mmsg (\\e[1;4mStandardError\\e[m\\e[1m)\\e[m\\n\\tfrom b.rb:2:in 'y'\\n\\tfrom c.rb:3:in 'z'\\n\"\n\"\\e[1mTraceback\\e[m (most recent call last):\\n\\t2: from c.rb:3:in 'z'\\n\\t1: from b.rb:2:in 'y'\\na.rb:1:in 'x': \\e[1mmsg (\\e[1;4mStandardError\\e[m\\e[1m)\\e[m\\n\"\nTraceback (most recent call last):\n\t11: from f12.rb:12:in 'g'\n\t10: from f11.rb:11:in 'g'\n\t 9: from f10.rb:10:in 'g'\n\t 8: from f9.rb:9:in 'g'\n\t 7: from f8.rb:8:in 'g'\n\t 6: from f7.rb:7:in 'g'\n\t 5: from f6.rb:6:in 'g'\n\t 4: from f5.rb:5:in 'g'\n\t 3: from f4.rb:4:in 'g'\n\t 2: from f3.rb:3:in 'g'\n\t 1: from f2.rb:2:in 'g'\nf1.rb:1:in 'g': m (StandardError)\n[ArgumentError, \"expected :top or :bottom as order: :sideways\"]\n[ArgumentError, \"expected true or false as highlight: 3\"]\n\"a.rb:1:in 'x': CUSTOM(false)\\n\"\n\"a.rb:1:in 'x': CUSTOM(true)\\n\"\n\"a.rb:1:in 'x': line one (Wide)\\nline two\\n\"\n\"a.rb:1:in 'x': \\e[1mline one (\\e[1;4mWide\\e[m\\e[1m)\\e[m\\n\\e[1mline two\\e[m\\n\"\n\"lang/exceptions/exception_full_message_without_backtrace.rb:55:in '<main>': outer (RuntimeError)\\nlang/exceptions/exception_full_message_without_backtrace.rb:53:in '<main>': inner (RuntimeError)\\n\"\n\"Traceback (most recent call last):\\nlang/exceptions/exception_full_message_without_backtrace.rb:53:in '<main>': inner (RuntimeError)\\nlang/exceptions/exception_full_message_without_backtrace.rb:55:in '<main>': outer (RuntimeError)\\n\"\n"
      # `full_message` renders through CRuby's `rb_error_write0`: the head line, the
      # `from` trail, then the cause chain. An exception carrying NO backtrace hangs
      # the head off the CALLER's own position under the reporting method's name,
      # which is why the first line below names `full_message`.
      e = StandardError.new("msg")
      p e.backtrace
      p e.full_message(highlight: false, order: :top)

      # An empty message prints the class alone -- `unhandled exception` for a bare
      # RuntimeError, which is what an argumentless `raise` builds.
      p RuntimeError.new("").full_message(highlight: false)
      p StandardError.new("").full_message(highlight: false)
      p StandardError.new("").detailed_message(highlight: false)
      p RuntimeError.new("").detailed_message(highlight: true)

      # `order:` picks the direction. `:bottom` numbers the trail, right-aligned to
      # the widest index, under the Traceback banner.
      b = StandardError.new("msg")
      b.set_backtrace(["a.rb:1:in 'x'", "b.rb:2:in 'y'", "c.rb:3:in 'z'"])
      p b.full_message(highlight: false, order: :top)
      p b.full_message(highlight: false, order: :bottom)
      p b.full_message(highlight: true, order: :top)
      p b.full_message(highlight: true, order: :bottom)
      wide = StandardError.new("m")
      wide.set_backtrace((1..12).map { |i| "f#{i}.rb:#{i}:in 'g'" })
      puts wide.full_message(highlight: false, order: :bottom)

      # Both keywords refuse anything else, in CRuby's own words.
      begin; b.full_message(order: :sideways); rescue => x; p [x.class, x.message]; end
      begin; b.full_message(highlight: 3); rescue => x; p [x.class, x.message]; end

      # `detailed_message` is SENT, not computed -- an override changes every report.
      class Custom < StandardError
        def detailed_message(**opt) = "CUSTOM(#{opt[:highlight]})"
      end
      c = Custom.new("m")
      c.set_backtrace(["a.rb:1:in 'x'"])
      p c.full_message(highlight: false)
      p c.full_message(highlight: true)

      # A multi-line message keeps the class tag on its first line.
      class Wide < StandardError
        def to_s = "line one\nline two"
      end
      w = Wide.new
      w.set_backtrace(["a.rb:1:in 'x'"])
      p w.full_message(highlight: false)
      p w.full_message(highlight: true)

      # The cause chain renders after the exception it caused (before it, reversed).
      begin
        begin
          raise "inner"
        rescue
          raise "outer"
        end
      rescue => chained
        p chained.full_message(highlight: false, order: :top)
        p chained.full_message(highlight: false, order: :bottom)
      end
    RUBY
  end

  it "exception inspect" do
    result = ze0(<<~'RUBY')
      class SubIns < StandardError; end
      p(SubIns.new("m").inspect)
      i = SubIns.new("m").inspect
      p i
      p(RuntimeError.new("m").inspect)
      p(StandardError.new.inspect)
      p(SubIns.new.inspect)
      begin
        raise SubIns, "z"
      rescue => e
        p e.inspect
      end
      p [RuntimeError.new("boxed")].first.inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "#<SubIns: m>"
      "#<SubIns: m>"
      "#<RuntimeError: m>"
      "#<StandardError: StandardError>"
      "#<SubIns: SubIns>"
      "#<SubIns: z>"
      "#<RuntimeError: boxed>"
    OUT
  end

  it "exception inspect empty message" do
    result = ze0(<<~'RUBY')
      class SubIns < StandardError; end
      p(SubIns.new("m").inspect)
      i001 = SubIns.new("m").inspect; p i001
      p(RuntimeError.new("").inspect)
      i002 = RuntimeError.new("").inspect; p i002
      p(RuntimeError.new("q").inspect)
      p RuntimeError.new.message
      p RuntimeError.new("").message
      p SubIns.new("").inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "#<SubIns: m>"
      "#<SubIns: m>"
      "RuntimeError"
      "RuntimeError"
      "#<RuntimeError: q>"
      "RuntimeError"
      ""
      "SubIns"
    OUT
  end

  it "exception introspection accessors" do
    result = ze0(<<~'RUBY')
      # Carried-state introspection accessors: KeyError#key/#receiver,
      # NameError/NoMethodError#receiver/#args/#private_call?, FrozenError#receiver,
      # LocalJumpError#reason/#exit_value, UncaughtThrowError#tag/#value,
      # and SystemExit (.new semantics, rescuable exit, #status/#success?).
      h = {"a" => 1}
      begin; h.fetch("zz"); rescue KeyError => e; p e.key; p e.receiver; end
      h0 = {}
      begin; h0.fetch(:x); rescue KeyError => e; p e.key; end
      ke = KeyError.new("m", key: :k, receiver: {1 => 2})
      p ke.key
      p ke.receiver
      p ke.message
      begin; nil.foo(1, 2); rescue NoMethodError => e; p e.receiver; p e.private_call?; end
      def m; yield; end
      begin; m; rescue LocalJumpError => e; p e.reason; p e.exit_value; end
      r = (begin; catch(:a) { throw :b }; rescue UncaughtThrowError => e; e.tag; end)
      p r
      r2 = (begin; catch(:a) { throw :b, 7 }; rescue UncaughtThrowError => e; e.value; end)
      p r2
      s = "x".freeze
      begin; s << "y"; rescue FrozenError => e; p e.receiver; end
      begin; raise "x"; rescue => e; (p e.key) rescue p $!.class; end
      p (SystemExit.new(2).class rescue $!.class)
      se = SystemExit.new(2)
      p se.message
      p se.status
      p se.success?
      p SystemExit.new.success?
      p SystemExit.new(true, "bye").message
      p SystemExit.superclass
      r3 = (begin; exit(false); "no"; rescue SystemExit; "caught"; end)
      p r3
      r4 = (begin; exit(3); "no"; rescue SystemExit => sx; sx.status; end)
      p r4
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "zz"
      {"a" => 1}
      :x
      :k
      {1 => 2}
      "m"
      nil
      false
      :noreason
      nil
      :b
      7
      "x"
      NoMethodError
      SystemExit
      "SystemExit"
      2
      false
      true
      "bye"
      Exception
      "caught"
      3
    OUT
  end

  it "exception message override" do
    result = ze0(<<~'RUBY')
      # A user exception's #message / #to_s override must drive the reported message.
      # Ruby's Exception#message calls #to_s, so overriding either changes #message,
      # while overriding only #message leaves #to_s at the default (the class name).

      class MsgOnly < StandardError
        def message = "msg-only"
      end

      class TosOnly < StandardError
        def to_s = "tos-only"
      end

      class Both < StandardError
        def message = "the-message"
        def to_s = "the-to-s"
      end

      class WithIvar < StandardError
        def initialize(n)
          @n = n
          super("stored")
        end
        def message = "n=#{@n}"
      end

      class Plain < StandardError
      end

      def show(e)
        puts "message=#{e.message} to_s=#{e.to_s}"
      end

      begin; raise MsgOnly; rescue => e; show(e); end
      begin; raise TosOnly; rescue => e; show(e); end
      begin; raise Both; rescue => e; show(e); end
      begin; raise Both, "ignored-arg"; rescue => e; show(e); end
      begin; raise WithIvar.new(7); rescue => e; show(e); end
      begin; raise Plain, "explicit"; rescue => e; show(e); end
      begin; raise Plain; rescue => e; show(e); end

      # specialized rescue (statically-typed binding) hits the override too
      begin; raise Both; rescue Both => e; show(e); end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      message=msg-only to_s=MsgOnly
      message=tos-only to_s=tos-only
      message=the-message to_s=the-to-s
      message=the-message to_s=the-to-s
      message=n=7 to_s=stored
      message=explicit to_s=explicit
      message=Plain to_s=Plain
      message=the-message to_s=the-to-s
    OUT
  end

  it "exception messages" do
    result = ze0(<<~'RUBY')
      # An exception's message comes from its own `initialize`/`to_s` chain, so
      # `raise SomeError` (no message) must actually RUN the class's constructor --
      # defaults, `super` and all -- rather than short-cutting to the class name.
      # The class-name default lives in Exception#to_s (`@message || self.class.name`).

      # Bare `super` forwards the defaulted parameter.
      class E < StandardError
        def initialize(m = "def")
          super
        end
      end
      begin; raise E; rescue => e; p e.message; end
      begin; raise E, "x"; rescue => e; p e.message; end
      begin; raise E.new; rescue => e; p e.message; end
      begin; raise E.new("y"); rescue => e; p e.message; end

      # `super("...")` with interpolation, raised argless.
      class F < StandardError
        def initialize(m = "dd")
          super("wrapped: #{m}")
        end
      end
      begin; raise F; rescue => e; p e.message; end
      begin; raise F, "given"; rescue => e; p e.message; end

      # No custom initialize: the message defaults to the class name.
      class G < StandardError; end
      begin; raise G; rescue => e; p e.message; end
      begin; raise G, "explicit"; rescue => e; p e.message; end

      # An inherited user initialize from a user parent.
      class Base < StandardError
        def initialize(m = "base-def")
          super
        end
      end
      class Sub < Base; end
      begin; raise Sub; rescue => e; p e.message; end

      # A custom initialize that also sets an ivar, raised argless.
      class H < StandardError
        def initialize(m = "oops", code = 42)
          @code = code
          super(m)
        end
        attr_reader :code
      end
      begin; raise H; rescue => e; p [e.message, e.code]; end
      begin; raise H.new("boom", 7); rescue => e; p [e.message, e.code]; end

      # Built-in raises are unaffected.
      begin; raise StandardError; rescue => e; p e.message; end
      begin; raise "boom"; rescue => e; p e.message; end
      begin; raise ArgumentError; rescue => e; p e.message; end
      begin; raise ArgumentError, "bad arg"; rescue => e; p e.message; end
      begin; raise RuntimeError.new("built"); rescue => e; p e.message; end

      # to_s and message agree, and inspect/class read correctly.
      begin
        raise E
      rescue => e
        p e.to_s
        p e.message
        p e.class
        p e.class.name
        p e.is_a?(StandardError)
      end

      # An exception with a custom to_s: message follows it (message calls to_s).
      class Custom < StandardError
        def to_s
          "custom-to-s"
        end
      end
      begin; raise Custom; rescue => e; p [e.message, e.to_s]; end

      # A message built from an ivar the constructor set.
      class Detailed < StandardError
        def initialize(field)
          @field = field
          super("invalid #{field}")
        end
        attr_reader :field
      end
      begin
        raise Detailed.new("email")
      rescue Detailed => e
        p [e.message, e.field]
      end

      # Re-raising preserves the same object, message and ivars.
      begin
        begin
          raise Detailed.new("name")
        rescue Detailed
          raise
        end
      rescue => e
        p [e.message, e.field]
      end

      # A rescued exception's message survives being stored and re-inspected.
      saved = nil
      begin; raise E; rescue => e; saved = e; end
      p saved.message
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "def"
      "x"
      "def"
      "y"
      "wrapped: dd"
      "wrapped: given"
      "G"
      "explicit"
      "base-def"
      ["oops", 42]
      ["boom", 7]
      "StandardError"
      "boom"
      "ArgumentError"
      "bad arg"
      "built"
      "def"
      "def"
      E
      "E"
      true
      ["custom-to-s", "custom-to-s"]
      ["invalid email", "email"]
      ["invalid name", "name"]
      "def"
    OUT
  end

  it "exception namespaced default message" do
    result = ze0(<<~'RUBY')
      # #692: namespaced exception class default message must use Ruby's
      # `::` module separator, not the C-mangled `_` form spinel uses
      # internally.

      module ActiveRecord
        class RecordNotFound < StandardError
        end

        class RecordInvalid < StandardError
        end
      end

      module Outer
        module Inner
          class DeepError < StandardError
          end
        end
      end

      # Non-namespaced subclass with underscore in its name should NOT
      # get the underscore replaced (My_Class is one identifier).
      class My_Class < StandardError
      end

      puts ActiveRecord::RecordNotFound.new.message
      puts ActiveRecord::RecordInvalid.new.message
      puts Outer::Inner::DeepError.new.message
      puts My_Class.new.message
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ActiveRecord::RecordNotFound
      ActiveRecord::RecordInvalid
      Outer::Inner::DeepError
      My_Class
    OUT
  end

  it "exception new nil message" do
    result = ze0(<<~'RUBY')
      # `Exception.new(nil)`: nil is not a message, so the class name answers, the
      # way the no-argument form does; an empty String is a message (#3812).
      p RuntimeError.new(nil).message
      p KeyError.new(nil).message
      p StandardError.new(nil).to_s
      p RuntimeError.new("").message
      p RuntimeError.new.message
      p RuntimeError.new("real").message
      class MyErr < StandardError; end
      p MyErr.new(nil).message
      p MyErr.new("m").message
      begin
        raise RuntimeError, nil
      rescue => e
        p e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "RuntimeError"
      "KeyError"
      "StandardError"
      ""
      "RuntimeError"
      "real"
      "MyErr"
      "m"
      "RuntimeError"
    OUT
  end

  it "exception nonstring message" do
    result = ze0(<<~'RUBY')
      class TS < StandardError
        def to_s; :sym; end
      end
      p(TS.new.message)

      r001 = (raise TS rescue $!.message); p r001   # Ruby: :sym   Spinel: "TS"

      p(TS.new.to_s)   # => :sym

      class TI < StandardError
        def to_s; 42; end
      end
      r = (raise TI rescue $!.message); p r
      r = (raise TI rescue $!.to_s); p r
      r = (raise "plain" rescue $!.message); p r
      class TM < StandardError
        def message; :mm; end
      end
      r = (raise TM rescue $!.message); p r
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :sym
      :sym
      :sym
      42
      42
      "plain"
      :mm
    OUT
  end

  it "exception nonstring to s" do
    result = ze0(<<~'RUBY')
      class TS < StandardError
        def to_s; :sym; end
      end
      p(TS.new.message)
      class TS2 < StandardError
        def to_s; "text"; end
      end
      p(TS2.new.message)
      p(StandardError.new("plain").message)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :sym
      "text"
      "plain"
    OUT
  end

  it "exception object methods" do
    result = ze0(<<~'RUBY')
      # Exception variable methods bound by `rescue => e`:
      # .message returns the message string
      # .class returns the class name string
      # .to_s returns the message
      # .inspect returns "#<ClassName: message>"
      # Bare raise re-raises the original class+message rather than
      # fabricating a fresh RuntimeError.

      # .message
      begin
        raise "boom"
      rescue => e
        puts "msg: #{e.message}"
      end

      # .class on default raise (RuntimeError)
      begin
        raise "boom2"
      rescue => e
        puts "cls: #{e.class}"
      end

      # .class with explicit class
      begin
        raise ArgumentError, "bad"
      rescue => e
        puts "cls2: #{e.class}"
        puts "msg2: #{e.message}"
      end

      # .to_s and .inspect
      begin
        raise TypeError, "wrong"
      rescue => e
        puts "tos: #{e.to_s}"
        puts "ins: #{e.inspect}"
      end

      # Bare `raise` inside a rescue body re-raises with original class+msg.
      begin
        begin
          raise ArgumentError, "inner"
        rescue => e
          raise
        end
      rescue => e
        puts "re-raised cls: #{e.class}"
        puts "re-raised msg: #{e.message}"
      end

      # Backward-compat: `puts e` still prints the message string,
      # preserving the existing test/rescue.rb shape.
      begin
        raise "compat-msg"
      rescue => e
        puts e
      end

      # Propagation when no rescue type matches (fix #3): a typed clause
      # whose sp_exc_is_a check returns false must re-raise so an enclosing
      # handler can catch it.
      begin
        begin
          raise ArgumentError, "propagate"
        rescue TypeError => e
          puts "should not be caught here"
        end
      rescue ArgumentError => e
        puts "caught propagated: #{e.class}"
        puts "msg: #{e.message}"
      end

      # .backtrace carries the real stamped frames (non-empty after a raise).
      begin
        raise "trace"
      rescue => e
        puts "backtrace is empty: #{e.backtrace.empty?}"
      end

      # .full_message renders the uncaught-report shape from the stamped frames;
      # path-portable via the frame suffix.
      begin
        raise ArgumentError, "fm"
      rescue => e
        puts "full: #{e.full_message(highlight: false).lines.first.chomp.end_with?("in '<main>': fm (ArgumentError)")}"
      end

      # Multi-clause rescue chain: first clause misses, second clause catches.
      # Exercises the recursive sub-chain path in compile_rescue_chain.
      begin
        raise TypeError, "multi"
      rescue ArgumentError => e
        puts "should not match"
      rescue TypeError => e
        puts "second clause: #{e.class} #{e.message}"
      rescue StandardError => e
        puts "should not reach"
      end

      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      msg: boom
      cls: RuntimeError
      cls2: ArgumentError
      msg2: bad
      tos: wrong
      ins: #<TypeError: wrong>
      re-raised cls: ArgumentError
      re-raised msg: inner
      compat-msg
      caught propagated: ArgumentError
      msg: propagate
      backtrace is empty: false
      full: true
      second clause: TypeError multi
      done
    OUT
  end

  it "exception override message unqueried" do
    result = ze0(<<~'RUBY')
      class Ov7 < StandardError
        def message; "overridden"; end
      end
      begin; raise Ov7; rescue Ov7 => x; end
      p :done
      begin; raise Ov7; rescue => y; p y.message; end
      p(Ov7.new.message)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :done
      "overridden"
      "overridden"
    OUT
  end

  it "exception own to s" do
    result = ze0(<<~'RUBY')
      # An exception subclass that defines its own to_s answers whatever that method
      # answers -- a Symbol, say. The call went through the message helper instead,
      # whose result is a string, and the Symbol came back empty.
      class TS < StandardError
        def to_s; :sym; end
      end
      p(TS.new.to_s)

      class TT < StandardError
        def to_s; "custom"; end
      end
      p(TT.new.to_s)
      begin
        raise TT
      rescue => e
        p e.to_s
      end

      class TU < StandardError; end
      p(TU.new("m").message)
      p(TU.new("m").to_s)
      p(TU.new.message)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :sym
      "custom"
      "custom"
      "m"
      "m"
      "TU"
    OUT
  end

  it "exception real objects" do
    result = ze0(<<~'RUBY')
      # An exception is a real object: $! and `rescue => e` bind the same object, its
      # #class is a real Class (usable in ==, case, printing), and `p` inspects it.

      # $! is the actual rescued object (identity), and its class/message read through
      begin
        raise "boom"
      rescue => e
        p $!.equal?(e)              # true
        p $!.class                  # RuntimeError
        p $!.class == RuntimeError  # true
        p $!.message                # "boom"
        p $!                        # #<RuntimeError: boom>
      end

      # outside any rescue, $! is nil
      p $!                          # nil

      # a typed exception class flows through == and drives a case
      begin
        raise ArgumentError, "bad arg"
      rescue => e
        p e.class                   # ArgumentError
        p e.class == ArgumentError  # true
        label = case e.class.to_s
                when "ArgumentError" then "arg"
                else "other"
                end
        p label                     # "arg"
      end

      # nested rescue: $! is the innermost handled exception and is identical to its
      # `=> e` binding
      begin
        raise TypeError, "outer"
      rescue => outer
        p outer.class               # TypeError
        begin
          raise IndexError, "inner"
        rescue => inner
          p $!.class                # IndexError
          p $!.equal?(inner)        # true
        end
      end

      # a user exception subclass keeps its class and custom message through => e
      class MyErr < StandardError
        def initialize(code)
          super("code #{code}")
        end
      end
      begin
        raise MyErr.new(42)
      rescue => e
        p e.class                   # MyErr
        p e.message                 # "code 42"
        p $!.equal?(e)              # true
      end

      # a nil $! (outside any rescue) reports NilClass; equal? against a non-exception
      # value is always false, since neither can be the one raised object
      p $!.class                    # NilClass
      begin
        raise "again"
      rescue => e
        p e.equal?(42)              # false
        p e.equal?("again")         # false
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      RuntimeError
      true
      "boom"
      #<RuntimeError: boom>
      nil
      ArgumentError
      true
      "arg"
      TypeError
      IndexError
      true
      MyErr
      "code 42"
      true
      NilClass
      false
      false
    OUT
  end

  it "exception reopen" do
    result = ze0(<<~'RUBY')
      # Reopening the native exception hierarchy and the builtin modules (D3).
      # The exception prelude lives natively, yet stays fully open: a reopen
      # ADDS a method reaching every subclass and OVERRIDES an existing one
      # everywhere, and a builtin module reopen reaches every includer.

      # --- add a method to the whole exception tree ---
      class Exception
        def tag
          "[#{self.class.name}]"
        end
      end

      # --- override a native method; it wins for every subclass ---
      class StandardError
        def message
          "handled: " + to_s
        end
      end

      begin
        raise ArgumentError, "bad value"
      rescue => e
        puts e.tag
        puts e.message
        puts e.is_a?(StandardError)
      end

      # CRuby stores the message in a hidden slot, not a @message ivar.
      begin
        raise "plain"
      rescue => e
        p e.instance_variables
        puts e.message
      end

      # --- reopen a builtin MODULE: reaches every includer ---
      module Enumerable
        def second
          first(2).last
        end
      end

      puts [10, 20, 30].second
      puts({ "a" => 1, "b" => 2 }.map { |_k, v| v }.second)

      # --- reopen restating the real superclass ---
      class String < Object
        def shout
          upcase + "!"
        end
      end
      puts "hi".shout
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [ArgumentError]
      handled: bad value
      true
      []
      handled: plain
      20
      2
      HI!
    OUT
  end

  it "exception subclass" do
    result = ze0(<<~'RUBY')
      # A user exception subclass is backed by the native RubyException (D3): custom
      # ivars, `super` into the native initialize (hidden message slot), multi-level
      # inheritance, class methods, and rescue-by-ancestry all match CRuby.

      class AppError < StandardError
        def initialize(code)
          @code = code
          super("app error #{code}")
        end

        def code
          @code
        end

        def self.with_code(n)
          new(n)
        end
      end

      class NotFound < AppError
        def initialize
          super(404)
          @where = "here"
        end

        def where
          @where
        end
      end

      e = AppError.new(7)
      puts e.message
      puts e.code
      p e.instance_variables
      p e.instance_variable_get(:@message)

      nf = NotFound.new
      puts nf.message
      puts nf.code
      puts nf.where
      puts nf.is_a?(AppError)
      puts nf.is_a?(StandardError)

      puts AppError.with_code(9).message

      begin
        raise NotFound
      rescue AppError => ex
        puts "rescued #{ex.class}: #{ex.message}"
      end

      # A subclass with no initialize inherits the native default.
      class Plain < RuntimeError
      end
      puts Plain.new("plain msg").message
      p Plain.new("plain msg").instance_variables
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      app error 7
      7
      [:@code]
      nil
      app error 404
      404
      here
      true
      true
      app error 9
      rescued NotFound: app error 404
      plain msg
      []
    OUT
  end

  it "exception subclass accessors" do
    result = ze0(<<~'RUBY')
      class SubX < StandardError; end
      p(SubX.new("m").cause)
      p(SubX.new("m").backtrace)
      p(SubX.new("m").message)
      p(SubX.new("m").detailed_message)
      p(SubX.new("m").exception.class)
      e = (begin; raise SubX, "z"; rescue SubX => x; x; end)
      p e.cause
      p e.message
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      nil
      "m"
      "m (SubX)"
      SubX
      nil
      "z"
    OUT
  end

  it "exception subclass custom method" do
    result = ze0(<<~'RUBY')
      # A user-defined method (or attr_reader) on an exception subclass dispatches:
      # the instance keeps its concrete class instead of collapsing to the base
      # exception type, while message/class/is_a? still route through the
      # exception machinery.
      class MyError < StandardError
        attr_reader :code
        def initialize(code = 7)
          super("failed(#{code})")
          @code = code
        end
        def detail = "boom detail"
      end

      puts MyError.new.detail
      e = MyError.new(42)
      puts e.detail
      puts e.code
      puts e.message
      puts e.class
      puts e.is_a?(MyError)
      puts e.is_a?(StandardError)
      puts e.is_a?(RuntimeError)
      begin
        raise MyError.new(9)
      rescue MyError => ex
        puts "#{ex.class}: #{ex.message} code=#{ex.code}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      boom detail
      boom detail
      42
      failed(42)
      MyError
      true
      true
      false
      MyError: failed(9) code=9
    OUT
  end

  it "exception subclass eq exception" do
    result = ze0(<<~'RUBY')
      class SubX < StandardError; end
      p(SubX.new("t") == StandardError.new("t"))

      e001 = SubX.new(3); f001 = e001.exception("other"); p f001.class; p f001.message

      p(SubX.new("t") == SubX.new("t"))    # => true
      p(SubX.new("m").exception.class)     # => SubX
      p(SubX.new("m").cause)               # => nil
      begin; raise SubX, "m"; rescue SubX => e002; p e002.cause; end   # => nil
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      SubX
      "other"
      true
      SubX
      nil
      nil
    OUT
  end

  it "exception subclass ivar" do
    result = ze0(<<~'RUBY')
      class MyError < StandardError
        attr_reader :record
        def initialize(record)
          super("boom")
          @record = record
        end
      end
      begin
        raise MyError.new("the-record")
      rescue MyError => e
        puts e.message
        puts e.record
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      boom
      the-record
    OUT
  end

  it "exception subclass ivar reraise" do
    result = ze0(<<~'RUBY')
      class PlainErr < StandardError; end
      class DataErr < StandardError
        attr_reader :data
        def initialize(d); super("data fail"); @data = d; end
      end
      begin
        raise PlainErr, "plain"
      rescue PlainErr => pe
        puts pe.message
      end
      begin
        raise DataErr.new(42)
      rescue StandardError => se   # broader catch: message works
        puts se.message
      end
      begin
        begin
          raise DataErr.new(7)
        rescue DataErr => de
          puts de.data
          raise
        end
      rescue => re
        puts "reraised: #{re.message}"
      end
      begin
        raise ArgumentError, "bad arg"
      rescue ArgumentError => ae
        puts ae.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      plain
      data fail
      7
      reraised: data fail
      bad arg
    OUT
  end

  it "exception subclass p inspect" do
    result = ze0(<<~'RUBY')
      # `p` on a user exception subclass renders like #inspect does, not as the
      # object default (#3813).
      class E1 < StandardError; end
      class E2 < StandardError
        def initialize(m = "d"); super; end
      end
      p(E1.new("m"))
      p(E1.new("m").inspect)
      p(E1.new)
      p(E2.new)
      p(RuntimeError.new("via p"))
      a = [E1.new("in array")]
      p a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      #<E1: m>
      "#<E1: m>"
      #<E1: E1>
      #<E2: d>
      #<RuntimeError: via p>
      [#<E1: in array>]
    OUT
  end

  it "exception subclass raise 2arg" do
    result = ze0(<<~'RUBY')
      class RecordInvalid < StandardError
        attr_reader :record
        def initialize(record)
          super("validation failed")
          @record = record
        end
      end
      begin
        raise RecordInvalid, "the-rec"
      rescue RecordInvalid => e
        puts e.message
        puts e.record
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      validation failed
      the-rec
    OUT
  end

  it "exception subclass result slot" do
    result = ze0(<<~'RUBY')
      # An exception subclass with ivars must reserve the StopIteration#result slot in
      # its generated struct (mirroring sp_Exception's cls_name/parent_cls_name/msg/
      # cause/result prefix). Without it `result` -- being wider than a pointer --
      # aliases and overruns the subclass's first ivar: a heap overflow in the
      # constructor's `result = nil` write and the GC scan's mark, and #result then
      # reads the ivar's bits instead of nil. A StopIteration subclass carrying an
      # ivar therefore reports nil #result (it was fed no iteration value): non-nil
      # would mean `result` overlaps @limit; 0 would mean the slot was never nil-init.
      class BoundedStop < StopIteration
        def initialize(limit)
          super("stop")
          @limit = limit
        end
      end

      begin
        raise BoundedStop.new(7)
      rescue StopIteration => e
        p e.result
      end

      # holds across repeated allocation churn (GC may scan live subclass exceptions)
      ok = true
      50.times do |i|
        begin
          raise BoundedStop.new(i)
        rescue StopIteration => e
          ok = false unless e.result.nil?
        end
      end
      p ok
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      true
    OUT
  end

  it "exception super message" do
    result = ze0(<<~'RUBY')
      # A user Exception subclass with a custom initialize that forwards to super must
      # carry the resolved message when raised WITHOUT an explicit message argument.
      # Previously `raise E` skipped the custom initialize and defaulted the message to
      # the class name, silently losing the default/super-built message.

      # Bare `super` forwards the defaulted param.
      class E < StandardError
        def initialize(m = "def"); super; end
      end
      begin; raise E; rescue => e; p e.message; end          # "def"
      begin; raise E, "x"; rescue => e; p e.message; end      # "x"
      begin; raise E.new; rescue => e; p e.message; end       # "def"
      begin; raise E.new("y"); rescue => e; p e.message; end  # "y"

      # super("...") with interpolation, raised argless.
      class F < StandardError
        def initialize(m = "dd"); super("wrapped: #{m}"); end
      end
      begin; raise F; rescue => e; p e.message; end           # "wrapped: dd"

      # No custom initialize: message defaults to the class name (unchanged fast path).
      class G < StandardError; end
      begin; raise G; rescue => e; p e.message; end           # "G"

      # Inherited user initialize from a user parent.
      class Base < StandardError
        def initialize(m = "base-def"); super; end
      end
      class Sub < Base; end
      begin; raise Sub; rescue => e; p e.message; end          # "base-def"

      # Custom initialize that also sets an ivar, raised argless.
      class H < StandardError
        def initialize(m = "oops", code = 42); @code = code; super(m); end
      end
      begin; raise H; rescue => e; p e.message; end            # "oops"

      # Built-in raises are unaffected.
      begin; raise StandardError; rescue => e; p e.message; end  # "StandardError"
      begin; raise "boom"; rescue => e; p e.message; end         # "boom"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "def"
      "x"
      "def"
      "y"
      "wrapped: dd"
      "G"
      "base-def"
      "oops"
      "StandardError"
      "boom"
    OUT
  end

  it "exception user subclass" do
    result = ze0(<<~'RUBY')
      # User subclasses of built-in exception classes should also lower
      # to first-class sp_Exception * with cls_name = subclass name.
      class MyError < StandardError
        def initialize(msg = "default msg")
          super(msg)
        end
      end

      e = MyError.new("hello")
      puts e.message
      puts e.class

      e2 = MyError.new
      puts e2.message
      puts e2.class

      # is_a? walks the parent chain.
      puts e.is_a?(MyError)
      puts e.is_a?(StandardError)
      puts e.is_a?(RuntimeError)

      # raise + rescue with user subclass
      begin
        raise MyError, "raised"
      rescue MyError => caught
        puts "caught: #{caught.message}"
      end

      # rescue by parent matches subclass
      begin
        raise MyError, "via parent"
      rescue StandardError => parent_caught
        puts "parent caught: #{parent_caught.message}"
        puts "parent caught cls: #{parent_caught.class}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello
      MyError
      default msg
      MyError
      true
      true
      false
      caught: raised
      parent caught: via parent
      parent caught cls: MyError
    OUT
  end

  it "exceptions" do
    result = ze0(<<~'RUBY')
      begin
        puts "try"
        raise ArgumentError, "bad"
      rescue ArgumentError => e
        puts "caught: #{e.send(:message)}"
      ensure
        puts "ensure ran"
      end

      begin
        puts "body"
      rescue => e
        puts "rescued"
      else
        puts "else ran"
      ensure
        puts "ensure2 ran"
      end

      class AppError < StandardError
      end
      class ValidationError < AppError
      end

      begin
        raise ValidationError, "bad input"
      rescue AppError => e
        puts "caught as AppError: #{e.send(:message)}"
      end

      begin
        raise TypeError, "wrong type"
      rescue ArgumentError, TypeError => e
        puts "caught one of: #{e.send(:message)}"
      end

      class Attempt
        def initialize
          @attempts = 0
        end

        def attempts
          @attempts
        end

        def run
          begin
            @attempts += 1
            raise "fail" if @attempts < 3
            puts "succeeded after #{@attempts} attempts"
          rescue
            retry if @attempts < 3
          ensure
            puts "ensure ran, attempts=#{@attempts}"
          end
        end
      end
      Attempt.new.run

      class Worker
        def safe
          raise "oops"
        rescue => e
          "handled: #{e.send(:message)}"
        end
      end
      puts Worker.new.safe

      class ReturnTester
        def m
          begin
            raise "x"
          rescue
            return "returned"
          ensure
            puts "ensure ran before return"
          end
        end
      end
      puts ReturnTester.new.m

      class Unsafe
        def op(n)
          raise "negative" if n < 0
          n * 2
        end
      end
      class Calc
        def safe_op(n) = Unsafe.new.op(n) rescue -1
      end
      c = Calc.new
      puts c.safe_op(5)
      puts c.safe_op(-5)

      class TopRisk
        def risky_top
          raise "bad"
        end
      end
      x = TopRisk.new.risky_top rescue "fallback"
      puts x

      class MyError < StandardError
        def initialize(msg, code)
          super(msg)
          @code = code
        end
        def code
          @code
        end
      end

      class Inner
        def call
          begin
            raise MyError.new("failed with code 42", 42)
          rescue MyError => e
            puts "inner saw code #{e.send(:code)}"
            raise
          end
        end
      end

      begin
        Inner.new.call
      rescue MyError => e
        puts "outer saw code #{e.send(:code)}"
        puts "outer message: #{e.send(:message)}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      try
      caught: bad
      ensure ran
      body
      else ran
      ensure2 ran
      caught as AppError: bad input
      caught one of: wrong type
      succeeded after 3 attempts
      ensure ran, attempts=3
      handled: oops
      ensure ran before return
      returned
      10
      -1
      fallback
      inner saw code 42
      outer saw code 42
      outer message: failed with code 42
    OUT
  end

  it "expr retry equal curry methodobj" do
    result = ze0(<<~'RUBY')
      # p(multi) / loop as expressions, retry with ensure, Array/Hash#equal?,
      # curry[a, b] multi-arg application, and &method(:kernel_builtin) procs.
      x = p(1, 2)
      p x
      y = p(5)
      p y
      z = loop { break }
      p z
      w = loop { break 42 }
      p w
      c = true
      begin
        raise "x"
      rescue
        (c = false; retry) if c
      ensure
        puts "ens"
      end
      puts "done"
      i = 0
      begin
        i += 1
        raise "boom" if i < 3
        puts "body done #{i}"
      rescue
        retry
      ensure
        puts "ens #{i}"
      end
      r = begin
        raise "x"
      rescue
        retry_done ||= 0
        retry_done += 1
        retry_done < 2 ? retry : "recovered"
      ensure
        puts "ens2"
      end
      p r
      a = [1, 2]
      b = a
      p a.equal?(b)
      p a.equal?([1, 2])
      s = "x"
      p s.equal?(s)
      h = { a: 1 }
      p h.equal?(h)
      add132 = proc { |a, b, c| a + b + c }
      p(add132.curry[1, 2][3])
      p(add132.curry[1][2][3])
      p(add132.curry[1, 2, 3])
      p([1, 2, 3].map(&method(:Integer)))
      p(["1", "2"].map(&method(:Integer)))
      p([1.7, 2.2].map(&method(:Integer)))
      m = method(:puts)
      m.call("hi")
      def shout(s); puts s; end
      m = method(:shout)
      m.call("hi")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      2
      [1, 2]
      5
      5
      nil
      42
      ens
      done
      body done 3
      ens 3
      ens2
      "recovered"
      true
      false
      true
      true
      6
      6
      6
      [1, 2, 3]
      [1, 2]
      [1, 2]
      hi
      hi
    OUT
  end

  it "extending a non module raises type error" do
    _(ze0(<<~'RUBY').stdout).must_equal "TypeError\n"
      begin
        Object.new.extend(42)
      rescue TypeError => e
        puts "TypeError"
      end
    RUBY
  end

  it "frozen error is caught by a runtime error rescue" do
    _(ze0(<<~'RUBY').stdout).must_equal "runtime-rescued\n"
      g = [1].freeze
      begin
        g[0] = 2
      rescue RuntimeError => e
        puts "runtime-rescued"
      end
    RUBY
  end

  it "hangs 548" do
    result = ze0(<<~'RUBY')
      # #548. Four shapes that compiled cleanly but hung at runtime.
      # Adam Doppelt's "Puzzles, third edition."
      #
      # 1. `a.concat(a, a)` -- two bugs in compile_call_stmt's concat
      #    arm. (a) Only the first arg was processed, so multi-arg
      #    concat dropped the tail silently. (b) The src-array length
      #    was queried inside the push loop; when an arg aliased the
      #    receiver (`a.concat(a)`) every push grew the source and
      #    the loop never terminated. Fix: snapshot each arg's length
      #    before its inner loop, then iterate every arg.
      #
      # 2. `/\#{re}/` -- regex compiler entered an infinite loop. The
      #    sequence `\#` lowered to literal `#`, then `{re}` arrived
      #    at compile_atom with `{` as the leading char. `{` was in
      #    compile_atom's "not an atom" filter, so the function
      #    returned without consuming and compile_seq's outer loop
      #    spun. CRuby treats `/{re}/` as matching the literal text
      #    `{re}` (`{...}` without a valid quantifier is literal); we
      #    mirror that by removing `{` from compile_atom's filter so
      #    a leading `{` falls through to the literal-char emit.
      #
      # 3. `while () ; 123 ; end` -- empty `()` infers as "void" and
      #    lowers to literal `0`. compile_cond_expr's catch-all
      #    `((expr), TRUE)` flipped the empty-parens condition to
      #    always-true and the loop hung. Treat "void" like "nil" in
      #    compile_cond_expr -- both lower to FALSE so `while ()`
      #    never enters the body, matching CRuby.
      #
      # 4. `i += 1; raise; rescue; retry unless i == 7` -- setjmp/
      #    longjmp local-preservation. `lv_i` modified inside the
      #    setjmp scope must be `volatile` to survive longjmp's
      #    register-unwind; with `-O3` the compiler register-cached
      #    `lv_i` and the rescue handler saw a stale 0, so `i == 7`
      #    was never satisfied and retry spun forever. Fix: pre-scan
      #    method bodies for setjmp-triggering shapes (begin/rescue,
      #    raise, retry) and mark non-pointer locals as `volatile`.
      #    Pointer locals stay non-volatile (GC-rooted via
      #    SP_GC_ROOT already keeps them stable; tagging them
      #    volatile triggers -Wdiscarded-qualifiers cascade at
      #    string/array helper call sites).

      # Repro 1: self-concat with self twice.
      a = [1, 2]
      a.concat(a, a)
      puts a.length      # 8 -- [1,2] + [1,2] + [1,2,1,2]

      # Repro 2: regex with literal `\#{re}` characters.
      re = /foo|bar/
      r2 = /\#{re}/
      puts "ok2"

      # Repro 3: while () never enters.
      while () ; 123 ; end
      puts "ok3"

      # Repro 4: retry-counter survives longjmp.
      def foo
        i = 0
        begin ; i += 1 ; raise "bar" ; rescue ; retry unless i == 7 ; end
        raise "baz" unless i == 7
      rescue
        123
      end
      puts foo  # 123  (foo's body would also raise "baz" if i != 7; here i == 7
                #       so no raise, and the function falls through. The
                #       outer rescue is dead code for this path.)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      6
      ok2
      ok3

    OUT
  end

  it "i1015" do
    result = ze0(<<~'RUBY')
      def check(selector, body)
        tag = selector[/\A[a-z]+/]
        raise "no #{selector}" unless tag && body.include?("<#{tag}")
        yield
      end
      check("div", "<div>x</div>") { puts "found div" }
      begin
        check("p", "<div>x</div>") { puts "unreachable" }
      rescue => e
        puts "raised: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      found div
      raised: no p
    OUT
  end

  it "i1041" do
    result = ze0(<<~'RUBY')
      # rescue of a namespaced exception class (rescue M::Err) must match a
      # raised M::Err. Both the raise and the rescue clause need to resolve
      # the ConstantPathNode (M::Err) to the registered class name (M_Err);
      # previously raise emitted a bare sp_raise (no class) and rescue
      # checked only the leaf name, so the handler never matched.
      module M
        class Err < StandardError; end
      end

      begin
        raise M::Err, "boom"
      rescue M::Err => e
        puts "caught: " + e.message
      end

      # Control: bare base class still matches a namespaced raise.
      begin
        raise M::Err, "again"
      rescue StandardError => e
        puts "base: " + e.message
      end

      # Control: top-level class name still matches.
      class TopErr < StandardError; end
      begin
        raise TopErr, "top"
      rescue TopErr => e
        puts "top: " + e.message
      end

      puts "after"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught: boom
      base: again
      top: top
      after
    OUT
  end

  it "i918" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 3].freeze
      puts a.frozen?
      begin
        a << 4
      rescue FrozenError
        puts "array << raised"
      end
      begin
        a[0] = 9
      rescue FrozenError
        puts "array []= raised"
      end
      begin
        a.push(5)
      rescue FrozenError
        puts "array push raised"
      end
      puts a.inspect

      b = [1, 2, 3]
      puts b.frozen?
      b << 4
      b[0] = 9
      puts b.inspect

      s = ["x", "y"].freeze
      begin
        s << "z"
      rescue FrozenError
        puts "str_array << raised"
      end
      puts s.inspect

      h = {a: 1}.freeze
      puts h.frozen?
      begin
        h[:b] = 2
      rescue FrozenError
        puts "hash []= raised"
      end

      g = {a: 1}
      puts g.frozen?
      g[:b] = 2
      puts g.length
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      array << raised
      array []= raised
      array push raised
      [1, 2, 3]
      false
      [9, 2, 3, 4]
      str_array << raised
      ["x", "y"]
      true
      hash []= raised
      false
      2
    OUT
  end

  it "i972" do
    result = ze0(<<~'RUBY')
      s = "hello".freeze
      puts s.frozen?
      begin
        s << " world"
      rescue FrozenError
        puts "<<: raised"
      end
      begin
        s.insert(0, "X")
      rescue FrozenError
        puts "insert: raised"
      end
      begin
        s.prepend("X")
      rescue FrozenError
        puts "prepend: raised"
      end
      begin
        s.replace("X")
      rescue FrozenError
        puts "replace: raised"
      end
      puts s

      s2 = "hello".dup
      puts s2.frozen?
      s2 << " world"
      puts s2

      s3 = String.new("abc")
      puts s3.frozen?
      s3.freeze
      puts s3.frozen?
      begin
        s3 << "d"
      rescue FrozenError
        puts "post-freeze: raised"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      <<: raised
      insert: raised
      prepend: raised
      replace: raised
      hello
      false
      hello world
      false
      true
      post-freeze: raised
    OUT
  end

  it "infer trailing raise return" do
    result = ze0(<<~'RUBY')
      # A method whose body ends in a bare `raise` never returns through that
      # statement, so the raise must not contribute to the return type. Unifying its
      # void with the explicit returns' Integer has no rule and lands on poly, which
      # boxes the return of every `return x if cond; raise` guard method and, through
      # its callers, whatever they feed.
      class Table
        def initialize(names) = @names = names

        def offsets
          h = {}
          i = 0
          while i < @names.length
            h[@names[i]] = i * 2
            i += 1
          end
          h
        end

        # the shape: two guarded returns, then a raise
        def lookup(token, offs)
          return offs[token] if offs.key?(token)
          return token.to_i if token != ""
          raise ArgumentError, "unknown token"
        end
      end

      t = Table.new(["a", "b", "c"])
      o = t.offsets
      p o.keys.sort
      p o["c"]
      p t.lookup("b", o)
      p t.lookup("41", o)
      p t.lookup("a", o) + t.lookup("1", o)
      begin
        t.lookup("", o)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b", "c"]
      4
      2
      41
      1
      unknown token
    OUT
  end

  it "instance eval rescue modifier" do
    result = ze0(<<~'RUBY')
      # An instance_eval/exec splice as the EXPRESSION of a rescue modifier (#2723):
      # the expression arm's own preludes must land inside the protected region, and
      # the splice temp's seeded type must survive the write pass's per-iteration
      # reset (users of the temp precede its synthesized write in node order).
      r = ("abc".instance_eval { upcase } rescue $!.class)
      p r
      r2 = ("ab".instance_exec(3) { |n| self * n } rescue $!.class)
      p r2
      r3 = (5.instance_eval { self + 1 } rescue :nope)
      p r3
      # a raise out of the spliced body reaches the enclosing handler with its
      # message: the splice rides a ParenthesesNode, not a BeginNode, whose own
      # exception region would swallow it
      r4 = ("x".instance_eval { raise "boom" } rescue :rescued)
      p r4
      r5 = ("x".instance_eval { raise "boom" } rescue $!.message)
      p r5
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ABC"
      "ababab"
      6
      :rescued
      "boom"
    OUT
  end

  it "isa namespaced exception collision" do
    result = ze0(<<~'RUBY')
      # `is_a?` against a namespaced exception class answered false when another
      # module held a class of the same leaf name. Two things had to line up:
      #
      #  - the colliding class is carried in the AST already flattened (`A::Error`
      #    arrives as `A__Error`), and the is_a? site prefixed its module again,
      #    asking about "A::A__Error" -- a name nothing answers to;
      #  - the repair for that read the class table's qualified name, which comes
      #    back in a SHARED static buffer that emitting the receiver then
      #    overwrote, so every check compared the receiver against itself.
      #
      # `rescue` and #ancestors were right throughout, which is what made it quiet:
      # only is_a?/kind_of?/instance_of? saw it. Found under net/http, where
      # Timeout::Error sits beside URI::Error. (matz/spinel#4133)
      module A
        class Error < StandardError; end
        class Sub < Error; end
      end

      module B
        class Error < RuntimeError; end
        class Sub < Error; end
      end

      a = A::Sub.new("x")
      b = B::Sub.new("x")

      # Each answers its own namespace's parent...
      p a.is_a?(A::Error)
      p b.is_a?(B::Error)
      # ...and not the other one's, which shares the leaf name.
      p a.is_a?(B::Error)
      p b.is_a?(A::Error)

      # The builtin grandparents still answer, and they differ between the two.
      p a.is_a?(StandardError)
      p b.is_a?(RuntimeError)
      p a.is_a?(RuntimeError)

      # instance_of? goes through the same name, and is exact.
      p a.instance_of?(A::Sub)
      p a.instance_of?(A::Error)

      # ancestors was never wrong; pinned so the two cannot drift apart.
      p A::Sub.ancestors.take(3).map(&:to_s)
      p B::Sub.ancestors.take(3).map(&:to_s)

      # rescue was never wrong either.
      begin
        raise A::Sub, "boom"
      rescue B::Error
        puts "WRONG namespace"
      rescue A::Error => e
        puts "rescued: #{e.class}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      false
      false
      true
      true
      false
      true
      false
      ["A::Sub", "A::Error", "StandardError"]
      ["B::Sub", "B::Error", "RuntimeError"]
      rescued: A::Sub
    OUT
  end

  it "issue 2899" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught\n"
      def show(u)
        label = (u.details || "~")
        puts label
      rescue NoMethodError => e
        puts "caught"
      end
      show(nil)
    RUBY
  end

  it "issue 2900" do
    result = ze0(<<~'RUBY')
      class Resp
        def code = 200
      end
      class Log
        def self.error(msg) = puts(msg)
      end
      def fetch(fail)
        begin
          raise "boom" if fail
          Resp.new
        rescue => e
          Log.error("failed: #{e.message}")
        end
      end
      r = fetch(false)
      puts r ? r.code : -1
      r2 = fetch(true)
      puts r2 ? r2.code : -1
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      200
      failed: boom
      -1
    OUT
  end

  it "issue 2963" do
    result = ze0(<<~'RUBY')
      p((Complex(2, 3) + "x" rescue $!.class))
      p((Complex(2, 3) - nil rescue $!.class))
      p((Complex(2, 3) * true rescue $!.class))
      p((Complex(2, 3) / "x" rescue $!.class))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      TypeError
      TypeError
      TypeError
    OUT
  end

  it "issue 2964" do
    result = ze0(<<~'RUBY')
      p((Complex(2, 3).coerce("x") rescue $!.class))
      p((Complex(2, 3).fdiv("x") rescue $!.class))
      p((Complex(2, 3).quo(nil) rescue $!.class))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      TypeError
      TypeError
    OUT
  end

  it "issue 2965" do
    result = ze0(<<~'RUBY')
      p((Complex(0, 0) ** -1 rescue $!.class))
      p((Complex(0, 0) ** -2 rescue $!.class))
      p(Complex(0, 0) ** 2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ZeroDivisionError
      ZeroDivisionError
      (0+0i)
    OUT
  end

  it "issue 2970" do
    _(ze0(<<~'RUBY').stdout).must_equal "true\n"
      r = ([1, 2, 3].sample(random: Random.new(1)) rescue $!.class)
      p(r.nil? || [1, 2, 3].include?(r))
    RUBY
  end

  it "issue 2979" do
    result = ze0(<<~'RUBY')
      r = ([[1, 2], [3]].transpose rescue $!.class); p r
      p([[1, 2], [3, 4]].transpose)
      p([[1], [2], [3]].transpose)
      p([[1, 2, 3], [4, 5, 6]].transpose)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      IndexError
      [[1, 3], [2, 4]]
      [[1, 2, 3]]
      [[1, 4], [2, 5], [3, 6]]
    OUT
  end

  it "issue 2983" do
    result = ze0(<<~'RUBY')
      def cls; begin; yield; rescue => e; e.class; end; end
      p(cls { [1, [2]].dig(1, 0, 3) })
      p [1, [2]].dig(1, 0)
      p [1, [2, [3]]].dig(1, 1, 0)
      p [[nil]].dig(0, 0, 5)
      p [{a: 7}].dig(0, :a)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      2
      3
      nil
      7
    OUT
  end

  it "issue 2984" do
    result = ze0(<<~'RUBY')
      r = ([] <=> [] rescue $!.class); p r
      p([1, 2] <=> [1, 2])
      p([1] <=> [1, 2])
      p([1, 2, 3] <=> [])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0
      0
      -1
      1
    OUT
  end

  it "issue 2990" do
    result = ze0(<<~'RUBY')
      def m
        raise "inner"
      rescue
        raise "outer", cause: nil
      end
      begin
        m
      rescue => e
        p e.message
        p e.cause
      end

      # an explicit non-nil cause is still threaded
      def m2
        raise "first"
      rescue => a
        begin
          raise "second"
        rescue
          raise "third", cause: a
        end
      end
      begin
        m2
      rescue => e
        p e.cause.message
      end

      # no cause: keeps the implicit chain
      def m3
        raise "lo"
      rescue
        raise "hi"
      end
      begin
        m3
      rescue => e
        p e.cause.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "outer"
      nil
      "first"
      "lo"
    OUT
  end

  it "issue 3000" do
    result = ze0(<<~'RUBY')
      ENV['ZZ_A'] = 'zzv'
      def cls; begin; yield; rescue => e; e.class; end; end
      p(cls { ENV.assoc(:sym) })
      p(cls { ENV.key(:sym) })
      p(cls { ENV.slice(:sym) })
      p(cls { ENV.values_at(:sym) })
      p ENV.assoc('ZZ_A')
      p ENV.key('zzv')
      p ENV.slice('ZZ_A')
      p ENV.values_at('ZZ_A')
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      TypeError
      TypeError
      TypeError
      ["ZZ_A", "zzv"]
      "ZZ_A"
      {"ZZ_A" => "zzv"}
      ["zzv"]
    OUT
  end

  it "issue 3001" do
    result = ze0(<<~'RUBY')
      h = {a: 1, b: 2}.freeze
      p (h.delete(:a) rescue $!.class); p h
      p (h.clear rescue $!.class)
      p (h.merge!({c: 3}) rescue $!.class)
      p (h.replace({z: 9}) rescue $!.class)
      g = {a: 1}
      p g.delete(:a); p g
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      FrozenError
      {a: 1, b: 2}
      FrozenError
      FrozenError
      FrozenError
      1
      {}
    OUT
  end

  it "issue 3002" do
    result = ze0(<<~'RUBY')
      a = [1, 2].freeze
      r = begin; a << 3; rescue FrozenError => e; e.receiver.equal?(a); end
      p r
      r2 = begin; [1].freeze << 2; rescue FrozenError => e; e.receiver; end
      p r2
      s = ["x"].freeze
      r3 = begin; s.push("y"); rescue FrozenError => e; e.receiver; end
      p r3
      h = { a: 1 }.freeze
      r4 = begin; h[:b] = 2; rescue FrozenError => e; e.class; end
      p r4
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      [1]
      ["x"]
      FrozenError
    OUT
  end

  it "issue 3003" do
    result = ze0(<<~'RUBY')
      s = "abc".freeze
      p (s.upcase! rescue $!.class); p s
      p ("xyz".freeze.reverse! rescue $!.class)
      p ("abc".freeze.slice!(0) rescue $!.class)
      p ("abc".freeze.slice!(0..1) rescue $!.class)
      p ("abc".freeze.insert(0, "x") rescue $!.class)
      p ("abc".freeze.replace("z") rescue $!.class)
      u = "abc"; p u.upcase!; p u
      p "hello".slice!(0)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      FrozenError
      "abc"
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      "ABC"
      "ABC"
      "h"
    OUT
  end

  it "issue 3004" do
    result = ze0(<<~'RUBY')
      begin
        raise "x"
      rescue => e
        p e.frozen?
      end
      begin
        raise ArgumentError, "y"
      rescue ArgumentError => e
        p e.frozen?
        p e.nil?
      end
      ex = RuntimeError.new("z")
      p ex.frozen?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      false
      false
      false
    OUT
  end

  it "issue 3008" do
    result = ze0(<<~'RUBY')
      def t
        yield
      rescue FloatDomainError => e
        e.message
      end
      puts t { (1.0/0.0).divmod(2) }
      puts t { (-1.0/0.0).divmod(2) }
      puts t { (0.0/0.0).divmod(2) }
      p (7.5).divmod(2)
      p (7.5).divmod(2.5)
      p (-7.5).divmod(2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Infinity
      -Infinity
      NaN
      [3, 1.5]
      [3, 0.0]
      [-4, 0.5]
    OUT
  end

  it "issue 3011" do
    result = ze0(<<~'RUBY')
      r1 = (Float::INFINITY.numerator rescue $!.class); p r1
      r2 = (Float::INFINITY.denominator rescue $!.class); p r2
      r3 = (Float::NAN.numerator rescue $!.class); p r3
      r4 = (Float::NAN.denominator rescue $!.class); p r4
      p 0.5.numerator
      p 0.5.denominator
      p((-Float::INFINITY).numerator)
      p 3.numerator, 3.denominator
      p (1/3r).numerator, (1/3r).denominator
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Infinity
      1
      NaN
      1
      1
      2
      -Infinity
      3
      1
      1
      3
    OUT
  end

  it "issue 3013" do
    result = ze0(<<~'RUBY')
      p ArgumentError.new.instance_of?(StandardError)
      p ArgumentError.new.instance_of?(ArgumentError)
      p ArgumentError.new.instance_of?(Exception)
      p ArgumentError.new.is_a?(StandardError)
      p RuntimeError.new.instance_of?(RuntimeError)
      p RuntimeError.new.instance_of?(StandardError)
      begin
        raise TypeError, "x"
      rescue => e
        p e.instance_of?(TypeError)
        p e.instance_of?(StandardError)
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      true
      false
      true
      true
      false
      true
      false
    OUT
  end

  it "issue 3020" do
    result = ze0(<<~'RUBY')
      class Box
        def initialize; @v = 1; @s = "hi"; end
        def drop; remove_instance_variable(:@v); end
        def drops; remove_instance_variable(:@s); end
      end
      b = Box.new
      p b.drop
      p b.drops
      class C
        def initialize; @x = 5; end
      end
      c = C.new
      r = begin; c.remove_instance_variable(:@nope); rescue => e; e.class; end
      p r
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      "hi"
      NameError
    OUT
  end

  it "issue 3021" do
    result = ze0(<<~'RUBY')
      r = (nil.clone(freeze: false) rescue $!.class); p r
      r2 = (nil.clone(freeze: false) rescue :err); p r2
      r3 = (Integer("x") rescue $!.class); p r3
      r4 = (nil.foo rescue $!.class); p r4
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      :err
      ArgumentError
      NoMethodError
    OUT
  end

  it "issue 3024" do
    result = ze0(<<~'RUBY')
      r = begin; pr = proc { break 5 }; pr.call; rescue LocalJumpError => e; e.exit_value; end
      p r
      r2 = begin; pr = proc { break }; pr.call; rescue LocalJumpError => e; [e.reason, e.exit_value]; end
      p r2
      r3 = begin; pr = proc { break "str" }; pr.call; rescue LocalJumpError => e; e.exit_value; end
      p r3
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      [:break, nil]
      "str"
    OUT
  end

  it "issue 3024b" do
    result = ze0(<<~'RUBY')
      begin; proc { break 7 }.call; rescue LocalJumpError => e001; p e001.exit_value; end
      def make001; proc { return 10 }; end
      p001 = make001
      begin; p001.call; rescue LocalJumpError => e002; p e002.exit_value; end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      7
      10
    OUT
  end

  it "issue 3027" do
    result = ze0(<<~'RUBY')
      begin
        ENV.fetch("SPINEL_NO_SUCH_VAR_XYZ")
      rescue KeyError => e
        p e.key
        p e.message
      end
      p ENV.fetch("SPINEL_NO_SUCH_VAR_XYZ", "dflt")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "SPINEL_NO_SUCH_VAR_XYZ"
      "key not found: \"SPINEL_NO_SUCH_VAR_XYZ\""
      "dflt"
    OUT
  end

  it "issue 3028" do
    result = ze0(<<~'RUBY')
      begin
        {}.fetch(:sym)
      rescue KeyError => e
        p e.key
      end
      begin
        {}.fetch(42)
      rescue KeyError => e
        p e.key
      end
      begin
        {}.fetch("str")
      rescue KeyError => e
        p e.key
      end
      p({}.fetch(:s, "d"))
      p({}.fetch(7, 0))
      p({}.key?(:x))
      p({}["str"])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :sym
      42
      "str"
      "d"
      0
      false
      nil
    OUT
  end

  it "issue 3030" do
    result = ze0(<<~'RUBY')
      p((KeyError.new("m").key rescue $!.class))
      p((KeyError.new("m").receiver rescue $!.class))
      p((FrozenError.new("m").receiver rescue $!.class))
      p((NoMethodError.new("m").receiver rescue $!.class))
      p((KeyError.new("m", key: :k, receiver: {}).key rescue $!.class))
      p((Interrupt.new.signo rescue $!.class))
      h = {a: 1}
      p((h.fetch(:z) rescue $!.key))
      p((h.fetch(:z) rescue $!.receiver))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      :k
      2
      :z
      {a: 1}
    OUT
  end

  it "issue 3031" do
    result = ze0(<<~'RUBY')
      begin
        raise ArgumentError, "x"
      rescue => e
        p e.class.superclass
      end
      begin
        raise TypeError, "y"
      rescue => e
        p e.class.superclass
      end
      begin
        {}.fetch(:missing)
      rescue KeyError => e
        p e.class.superclass
      end
      p ArgumentError.superclass
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      StandardError
      StandardError
      IndexError
      StandardError
    OUT
  end

  it "issue 3032" do
    result = ze0(<<~'RUBY')
      begin
        raise Interrupt
      rescue StandardError
        puts "wrong: StandardError caught Interrupt"
      rescue Exception => e
        puts "ok: #{e.class}"
      end
      begin
        raise ArgumentError, "x"
      rescue RuntimeError
        puts "wrong: RuntimeError caught ArgumentError"
      rescue ArgumentError
        puts "ok: ArgumentError"
      end
      begin
        raise ArgumentError, "y"
      rescue StandardError => e
        puts "ok: StandardError caught #{e.class}"
      end
      begin
        raise "plain"
      rescue RuntimeError => e
        puts "ok: RuntimeError caught #{e.class}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ok: Interrupt
      ok: ArgumentError
      ok: StandardError caught ArgumentError
      ok: RuntimeError caught RuntimeError
    OUT
  end

  it "issue 3033" do
    result = ze0(<<~'RUBY')
      x = nil
      r = begin; x.clone(freeze: false); rescue => e; e.class; end
      p r
      p x.clone(freeze: true)
      p x.clone
      def pick(b); b ? "hi" : nil; end
      z = pick(true)
      p z.clone(freeze: false)
      o = Object.new
      p o.clone(freeze: false).frozen?
      p o.clone(freeze: true).frozen?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      nil
      nil
      "hi"
      false
      true
    OUT
  end

  it "issue 3034" do
    result = ze0(<<~'RUBY')
      begin
        Object.const_get(:Nope)
      rescue NameError => e
        p e.name
        p e.message
        p e.receiver
      end
      begin
        Nonexistent
      rescue NameError => e
        p e.name
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :Nope
      "uninitialized constant Nope"
      Object
      :Nonexistent
    OUT
  end

  it "issue 3035" do
    result = ze0(<<~'RUBY')
      p self.class
      begin
        self.class.const_get(:MissingXYZ)
      rescue => e
        p e.class
        puts e.message
      end
      def topm; self.class; end
      p topm
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Object
      NameError
      uninitialized constant MissingXYZ
      Object
    OUT
  end

  it "issue 3036" do
    result = ze0(<<~'RUBY')
      r001 = (NameError.new("m", :n).receiver rescue $!.class)
      p r001
      r002 = (nil.foo rescue $!.receiver)
      p r002
      h = {a: 1}
      r003 = (h.fetch(:z) rescue $!.receiver)
      p r003
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      nil
      {a: 1}
    OUT
  end

  it "issue 3037" do
    result = ze0(<<~'RUBY')
      begin
        undefined_bareword_thing
      rescue NameError => e
        puts "caught #{e.class}"
        puts e.message
      end

      class K
        def probe
          maybe_defined_helper
        rescue NameError
          "fallback"
        end
      end
      p K.new.probe

      # a defined bareword still resolves normally
      def real_helper; 42; end
      p real_helper
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught NameError
      undefined local variable or method 'undefined_bareword_thing' for main
      "fallback"
      42
    OUT
  end

  it "issue 3039" do
    result = ze0(<<~'RUBY')
      begin
        raise Interrupt
      rescue Interrupt => e
        p e.signo
      end
      begin
        raise Interrupt, "boom"
      rescue Interrupt => e
        p e.signo
        p e.message
      end
      p Interrupt.new.signo
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      2
      2
      "boom"
      2
    OUT
  end

  it "issue 3047b" do
    result = ze0(<<~'RUBY')
      r = (Rational(1,2).round(half: :up) rescue $!.class); p r
      r2 = (Rational(5,2).round(0, half: :up) rescue $!.class); p r2
      r3 = (Rational(5,2).round(0, half: :even) rescue $!.class); p r3
      r4 = (Rational(5,2).round(0, half: :down) rescue $!.class); p r4
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      3
      2
      2
    OUT
  end

  it "issue 3049" do
    result = ze0(<<~'RUBY')
      inf = 1.0 / 0.0
      nan = 0.0 / 0.0
      begin
        x = rand(inf)
        puts "no-raise-inf"
      rescue FloatDomainError => e
        puts e.message
      end
      begin
        rand(nan)
        puts "no-raise-nan"
      rescue FloatDomainError => e
        puts e.message
      end
      puts rand(0.0).class
      puts(rand(3.5) >= 0)
      srand(42)
      r = rand(5.9)
      puts(r >= 0 && r <= 5)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Infinity
      NaN
      Float
      true
      true
    OUT
  end

  it "issue 3049b" do
    result = ze0(<<~'RUBY')
      r = Random.new(5)
      p((r.rand(Float::INFINITY) rescue $!.class))
      p((r.rand(-Float::INFINITY) rescue $!.class))
      p((r.rand(Float::NAN) rescue $!.class))
      p((r.rand(1.0..Float::INFINITY) rescue $!.class))
      p((r.rand(0.0).class rescue $!.class))
      p((Random.rand(Float::INFINITY) rescue $!.class))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Errno::EDOM
      Errno::EDOM
      Errno::EDOM
      Errno::EDOM
      Float
      Errno::EDOM
    OUT
  end

  it "issue 3050" do
    result = ze0(<<~'RUBY')
      r = Random.new(42)
      puts r.bytes(0).bytesize
      begin
        r.bytes(-1)
      rescue ArgumentError => e
        puts "ArgumentError"
        puts e.message
      end
      begin
        Random.bytes(-5)
      rescue ArgumentError
        puts "class ok"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0
      ArgumentError
      negative string size (or size too big)
      class ok
    OUT
  end

  it "issue 3059" do
    result = ze0(<<~'RUBY')
      class Obj9
        def initialize; @x = 7; end
      end
      a = Obj9.new
      r = (a.instance_variable_set(:@y, 11) rescue $!.class)
      p r
      p a.instance_variable_get(:@y)
      p a.instance_variable_get(:@x)

      class C
        def initialize; @x = 1; end
        def go; instance_variable_set(:@x, 5); @x; end
        def get; instance_variable_get(:@x); end
        def has?; instance_variable_defined?(:@z); end
      end
      o = C.new
      p o.go
      p o.get
      p o.has?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      11
      11
      7
      5
      5
      false
    OUT
  end

  it "issue 3060" do
    result = ze0(<<~'RUBY')
      v = (begin; nil.foo; rescue NoMethodError; true; end); p v
      w = (begin; nil.foo; rescue NoMethodError; $!.class; end); p w
      x = (begin; raise "boom"; rescue => e; e.message; end); p x
      y = (begin; 1 + 1; rescue; 0; end); p y
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      NoMethodError
      "boom"
      2
    OUT
  end

  it "issue 3065" do
    result = ze0(<<~'RUBY')
      def t
        yield
      rescue RangeError => e
        e.message
      end
      puts t { (1..).max }
      puts t { (1...).max }
      puts t { (..5).min }
      puts((1..).min)
      r = (10..)
      puts t { r.max }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      cannot get the maximum of endless range
      cannot get the maximum of endless range
      cannot get the minimum of beginless range
      1
      cannot get the maximum of endless range
    OUT
  end

  it "issue 3066" do
    result = ze0(<<~'RUBY')
      begin
        (..5).each { |x| x }
        puts "no-raise-1"
      rescue TypeError => e
        puts e.message
      end
      begin
        (...5).each { |x| x }
        puts "no-raise-2"
      rescue TypeError => e
        puts e.message
      end
      (1..3).each { |x| print x }
      puts
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      can't iterate from NilClass
      can't iterate from NilClass
      123
    OUT
  end

  it "issue 3068" do
    result = ze0(<<~'RUBY')
      begin
        "s".no_such
      rescue NoMethodError => e
        p e.receiver
      end
      begin
        42.frobnicate
      rescue NoMethodError => e
        p e.receiver
      end
      begin
        3.14.no_way
      rescue NoMethodError => e
        p e.receiver
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "s"
      42
      3.14
    OUT
  end

  it "issue 3071" do
    result = ze0(<<~'RUBY')
      require "set"

      r1 = (Set.new(5) rescue $!.class); p r1
      p Set.new([1, 2]).to_a
      p Set.new.to_a
      p Set.new([1, 2, 3]) { |x| x * 2 }.to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      [1, 2]
      []
      [2, 4, 6]
    OUT
  end

  it "issue 3072" do
    result = ze0(<<~'RUBY')
      require "set"

      r1 = (Set[1, 2] & 5 rescue $!.class); p r1
      r2 = (Set[1, 2] | 5 rescue $!.class); p r2
      r3 = (Set[1, 2].merge(5) rescue $!.class); p r3
      r4 = (Set[1, 2].subtract(5) rescue $!.class); p r4
      r5 = (Set[1, 2] - 5 rescue $!.class); p r5
      p((Set[1, 2] & [2, 3]).to_a)
      p((Set[1, 2] | [3]).to_a)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      [2]
      [1, 2, 3]
    OUT
  end

  it "issue 3073" do
    result = ze0(<<~'RUBY')
      e = SignalException.new(9, "custom")
      p e.message
      p e.signo
      p e.signm
      p SignalException.new(9).message
      r = begin; SignalException.new("KILL", "custom"); rescue => x; x.class; end
      p r
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "custom"
      9
      "custom"
      "SIGKILL"
      ArgumentError
    OUT
  end

  it "issue 3074" do
    result = ze0(<<~'RUBY')
      begin
        raise SignalException, "INT"
      rescue SignalException => e
        p e.signo
        p e.message
      end
      begin
        raise SignalException, "TERM"
      rescue SignalException => e
        p e.signo
      end
      begin
        raise SignalException, "SIGINT"
      rescue SignalException => e
        p e.signo
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      2
      "SIGINT"
      15
      2
    OUT
  end

  it "issue 3076" do
    result = ze0(<<~'RUBY')
      p((Signal.signame(nil) rescue $!.class))
      p((Signal.signame(true) rescue $!.class))
      p((Signal.signame("INT") rescue $!.class))
      p((Signal.signame(:INT) rescue $!.class))
      p(Signal.signame(9))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      TypeError
      TypeError
      TypeError
      "KILL"
    OUT
  end

  it "issue 3077" do
    result = ze0(<<~'RUBY')
      begin
        abort("bye now")
        puts "unreached"
      rescue SystemExit => e
        puts "status=#{e.status}"
        puts "msg=#{e.message}"
      end
      puts "continued"
      begin
        abort
      rescue SystemExit => e
        puts "noarg-status=#{e.status}"
        puts "noarg-msg=#{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      status=1
      msg=bye now
      continued
      noarg-status=1
      noarg-msg=exit
    OUT
    _(result.stderr).must_equal "bye now\n"
  end

  it "issue 3087" do
    result = ze0(<<~'RUBY')
      p(begin; throw :nope, 42; rescue => e; e.class; end)
      v = begin; throw :y; rescue UncaughtThrowError => e; e.tag; end
      p v
      w = begin; throw :z, 7; rescue UncaughtThrowError => e; e.value; end
      p w
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      UncaughtThrowError
      :y
      7
    OUT
  end

  it "issue 3088" do
    result = ze0(<<~'RUBY')
      r0 = begin; UncaughtThrowError.new; rescue => e; e.class; end
      p r0
      r1 = begin; UncaughtThrowError.new(:tag); rescue => e; e.class; end
      p r1
      p UncaughtThrowError.new(:tag, 5).class
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      ArgumentError
      UncaughtThrowError
    OUT
  end

  it "issue 3096" do
    result = ze0(<<~'RUBY')
      e001 = [1].each; e001.next
      ex001 = (begin; e001.next; rescue StopIteration => z001; z001; end)
      p ex001.class
      p ex001.is_a?(StandardError)
      p ex001.is_a?(Exception)
      p ex001.is_a?(StopIteration)
      p ex001.is_a?(ArgumentError)
      p ex001.kind_of?(IndexError)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      StopIteration
      true
      true
      true
      false
      true
    OUT
  end

  it "issue 3097" do
    result = ze0(<<~'RUBY')
      r1 = (:pow.to_proc.call(2, 3) rescue $!.class); p r1
      s = :+; r2 = (s.to_proc.call(4, 5) rescue $!.class); p r2
      p :+.to_proc.call(4, 5)
      p :upcase.to_proc.call("ab")
      p :sub.to_proc.call("hello", "l", "L")
      p :upcase.to_proc.arity
      p ["x", "y"].map(&:upcase)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      8
      9
      9
      "AB"
      "heLlo"
      -2
      ["X", "Y"]
    OUT
  end

  it "issue 3098" do
    result = ze0(<<~'RUBY')
      a001 = (throw :x rescue $!); b001 = (throw :y rescue $!); p(a001 == b001)
      c001 = (raise "x" rescue $!); d001 = (raise "y" rescue $!); p(c001 == d001)
      e001 = (throw :x rescue $!); p(a001 == e001.class)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      false
    OUT
  end

  it "issue 3120" do
    result = ze0(<<~'RUBY')
      e = begin; {5 => 0}.fetch(9); rescue KeyError => x; x; end
      p e.key
      p e.receiver
      e001 = [1].each; e001.next
      ex = (begin; e001.next; rescue StopIteration => z; z; end)
      p ex.class
      p ex.message
      p ex.result
      nm = begin; {1 => 2}.fetch(3); rescue KeyError => k2; k2; end
      p nm.message
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      9
      {5 => 0}
      StopIteration
      "iteration reached an end"
      [1]
      "key not found: 3"
    OUT
  end

  it "issue 3121" do
    result = ze0(<<~'RUBY')
      def undef_ref_m005; some_undefined_local_x005; end
      n = begin; undef_ref_m005; rescue => e; e.name; end
      p n
      n2 = begin; some_other_undef; rescue NameError => e; e.name; end
      p n2
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :some_undefined_local_x005
      :some_other_undef
    OUT
  end

  it "issue 3147" do
    result = ze0(<<~'RUBY')
      # nil.scan through a helper must compile (it emitted invalid C: an sp_RbVal
      # element assigned into a const char* block-param slot) and raise NoMethodError
      # at run time like CRuby, rather than failing C compilation.
      def wrap(value)
        tokens = tokenize(value)
        tokens.each { |word| }
        :done
      end

      def tokenize(value) = value.scan(/\S+|\n/)

      begin
        wrap(nil)
      rescue NoMethodError
        puts "raised NoMethodError"
      end
      puts "ok"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      raised NoMethodError
      ok
    OUT
  end

  it "issue 3148" do
    result = ze0(<<~'RUBY')
      # Left-to-right operand evaluation for ==: the left operand's side effect must
      # be visible to the right (Ruby order), not reordered by C's unsequenced
      # function arguments.
      class Crash
        attr_reader :foo
        def initialize = @foo = []
        def add(list) = list.tap { foo << _1 }
      end

      obj = Crash.new
      raise "tap push/return order" unless obj.add(Crash.new) == obj.foo[0]

      # direct (no tap) form
      class Box
        attr_reader :items
        def initialize = @items = []
        def push(x)
          items << x
          x
        end
      end
      b = Box.new
      raise "push order" unless b.push(Box.new) == b.items[0]

      # right operand carries the effect; left reads the pre-effect state
      arr = []
      def mutate(a, v) = (a << v; v)
      first = arr[0]
      res = (arr[0] == mutate(arr, 99))
      p res            # nil == 99 -> false in Ruby (arr[0] read before mutate)
      p arr.length
      puts "ok"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      1
      ok
    OUT
  end

  it "issue 3150" do
    result = ze0(<<~'RUBY')
      def str(*flags)
        out = []
        flags.each do
          raise unless _1.is_a?(String)
          out << _1.match?(/x/)
        end
        out
      end
      p str("axb", "y", "xx")

      # fail / abort forms also gate the fall-through
      def only_ints(*vals)
        out = []
        vals.each do |v|
          fail "not int" unless v.is_a?(Integer)
          out << v * 2
        end
        out
      end
      p only_ints(1, 2, 3)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [true, false, true]
      [2, 4, 6]
    OUT
  end

  it "issue 3152" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      require "stringio"

      5.times do
        buf = StringIO.new
        20.times { |i| buf << ("a".."z").to_a[i % 26] * (i + 1) }
        s = buf.string

        buf2 = StringIO.new
        20.times { |i| buf2 << ("a".."z").to_a[i % 26] * (i + 1) }
        s2 = buf2.string

        raise unless s == s2
      end

      puts "ok"
    RUBY
  end

  it "issue 3188" do
    result = ze0(<<~'RUBY')
      class Shape
        include Comparable
        def area; raise NotImplementedError; end
        def <=>(other); area <=> other.area; end
      end
      class Rectangle < Shape
        def initialize(w, h); @w = w; @h = h; end
        def area; @w * @h; end
      end
      class Square < Rectangle
        def initialize(s); super(s, s); end
      end
      p(Square.new(4) > Rectangle.new(2, 3))
      p([Rectangle.new(3, 4), Square.new(5)].sort.map(&:area))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      [12, 25]
    OUT
  end

  it "issue 3200" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      class Item
        attr_reader :values
        def initialize = @values = ["a"]
        def label
          [].tap do |result|
            result << values.map { _1 }.join(", ")
          end.join(" ")
        end
      end
      raise unless Item.new.label == "a"
      puts "ok"
    RUBY
  end

  it "issue 3204" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      class Crash
        attr_reader :ivar
        def fn(*opts, ivar: false)
          @ivar = ivar
        end
      end
      c = Crash.new
      c.fn("foo", "bar")
      raise if c.ivar
      puts "ok"
    RUBY
  end

  it "issue 3208" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      values = ["<url>"]
      result = [].tap do |words|
        words << "Usage:"
        words.push(*values.map { _1 })
      end.join(" ")
      raise unless result == "Usage: <url>"
      puts "ok"
    RUBY
  end

  it "issue 3210" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      class Foo
        def initialize
          @key = :enabled
        end
      end
      class Crash
        def key = @key ||= :url
      end
      Foo.new
      raise unless Crash.new.key == :url
      puts "ok"
    RUBY
  end

  it "issue 3212" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      def maybe_string(flag)
        flag ? " " : nil
      end
      module Crash
        def self.call(value)
          value.split(/ /)
        end
      end
      raise unless Crash.call(maybe_string(true)) == []
      puts "ok"
    RUBY
  end

  it "issue 3218" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      class Foo
        def initialize = @value = false
        def set(*names) = @value = true
        def value = @value
      end
      class Crash
        def initialize = yield (@foo = Foo.new)
        def fn = @foo.value
      end
      module App
        def self.fn(&) = Crash.new(&).fn
      end
      raise unless App.fn { _1.set "foo" }
      puts "ok"
    RUBY
  end

  it "issue 3227 deep return" do
    result = ze0(<<~'RUBY')
      # Deep-return sharing (P6): a method that keeps its shared string AND
      # returns it -- the caller's binding is the same object.
      $store = []
      def make_held
        s = +"kept"
        $store << s
        s << "-in"
        s
      end
      r = make_held
      r << "-out"
      p r
      p $store[0]
      p r.equal?($store[0])

      # multiple returns, all shared
      def pick(flag)
        a = +"aa"
        b = +"bb"
        $store << a
        $store << b
        a << "1"
        b << "2"
        return a if flag
        b
      end
      x = pick(true)
      x << "!"
      p $store[1]
      y = pick(false)
      y << "?"
      p $store[4] rescue p $store.last
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "kept-in-out"
      "kept-in-out"
      true
      "aa1!"
      "bb2?"
    OUT
  end

  it "issue 3229" do
    result = ze0(<<~'RUBY')
      p((1..).each.next)
      e = (1..).each
      p e.next
      p e.next
      p e.peek
      p e.next
      e.rewind
      p e.next
      f = (10..).each
      p f.next
      p f.next
      g = (1..3).each
      p g.next
      p g.next
      p g.next
      r = (g.next rescue $!.class)
      p r
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      1
      2
      3
      3
      1
      10
      11
      1
      2
      3
      StopIteration
    OUT
  end

  it "issue 3249" do
    result = ze0(<<~'RUBY')
      def dbl(n) = n * 2
      def add(a, b) = a + b

      p method(:dbl).inspect.start_with?("#<Method: Object#dbl(n)")
      p method(:dbl).to_s.start_with?("#<Method: Object#dbl(n)")
      p method(:dbl).unbind.class
      p method(:dbl).unbind.inspect.start_with?("#<UnboundMethod: Object#dbl(n)")
      p method(:dbl).source_location.is_a?(Array)

      begin
        (method(:dbl) << method(:add)).call(3)
      rescue ArgumentError => e
        p e.message
      end
      begin
        (method(:dbl) >> method(:add)).call(5)
      rescue ArgumentError => e
        p e.message
      end
      p (method(:add) >> method(:dbl)).call(3, 4) rescue p $!.class

      class Widget
        def render(depth, pad = 0, *rest) = depth
      end
      p Widget.instance_method(:render).inspect.start_with?("#<UnboundMethod: Widget#render(depth, pad=..., *rest)")
      p Widget.instance_method(:render).class

      module Api
        def self.fetch(url) = url
      end
      p Api.method(:fetch).inspect.start_with?("#<Method: Api.fetch(url)")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      UnboundMethod
      true
      true
      "wrong number of arguments (given 1, expected 2)"
      "wrong number of arguments (given 1, expected 2)"
      14
      true
      UnboundMethod
      true
    OUT
  end

  it "issue 3258" do
    result = ze0(<<~'RUBY')
      module Outer; class Thing; end; end
      r1 = (5.is_a?(::Integer) rescue "raise:#{$!.class}")
      r2 = ("s".is_a?(Outer::Thing) rescue "raise:#{$!.class}")
      r3 = ("s".is_a?(::String) rescue "raise:#{$!.class}")
      r4 = (5.is_a?(Outer::Thing) rescue "raise:#{$!.class}")
      o = Outer::Thing.new
      r5 = (o.is_a?(Outer::Thing) rescue "raise:#{$!.class}")
      r6 = (o.is_a?(Integer) rescue "raise:#{$!.class}")
      p r1; p r2; p r3; p r4; p r5; p r6
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      true
      false
      true
      false
    OUT
  end

  it "issue 3295" do
    result = ze0(<<~'RUBY')
      def value(assign)
        param = "x" if assign
        param
      end

      raise "FAIL" unless value(false).nil?
      p value(false)
      p value(true)
      x = "set" if false
      p x
      p x.nil?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      "x"
      nil
      true
    OUT
  end

  it "issue 3314 clear direct receiver" do
    result = ze0(<<~'RUBY')
      r001 = ((+"abc").clear rescue $!.class); p r001
      a001 = +"abc"; v001 = a001.clear; p v001
      p((+"x").clear.empty?)
      p(("frozen".clear rescue $!.class))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ""
      ""
      true
      ""
    OUT
  end

  it "issue 3341 poly uniq" do
    result = ze0(<<~'RUBY')
      class Flag
        attr_reader :switches, :help
        def initialize(opts)
          @help = if opts.last && opts.last[0] != "-"
            opts.pop
          end
          @switches = opts
          raise ArgumentError, "duplicate switch" unless switches.uniq.length == switches.length
        end
      end
      class Config
        def str(*opts) = Flag.new(opts)
        def builtin = Flag.new(["-h", "--help"] + ["Show this"])
      end
      c = Config.new
      p c.str("--name").switches
      p c.builtin.switches
      p c.str("-a", "-a", "x").switches rescue p $!.class
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["--name"]
      ["-h", "--help"]
      ArgumentError
    OUT
  end

  it "join separator slot" do
    result = ze0(<<~'RUBY')
      # `join`'s separator is a NILABLE String slot: nil is legal and means "" (it
      # is `$,`'s default), false and every other class are a TypeError. The
      # emitters passed the argument into the const char* slot raw, so both spellings
      # reached the join as a NULL and it read that as a string -- a segfault either
      # way, for every array kind (found reviewing PR #4029, whose sweep did not
      # reach this slot).
      def try
        yield
      rescue => e
        p [e.class, e.message]
      end

      p [1, 2].join(nil)
      p ["a", "b"].join(nil)
      p [1.5, 2.5].join(nil)
      p [[1], [2]].join(nil)
      p [1, [2, 3]].join(nil)
      p([:a, :b].join(nil))
      sep = nil
      p [1, 2].join(sep)
      p [1, 2].join
      p [1, 2].join("-")
      p ["a", "b"].join("")

      try { [1, 2].join(false) }
      try { [1, 2].join(true) }
      try { [1, 2].join(1) }
      try { ["a"].join(:x) }

      # through a poly receiver, where the array kind is a run-time question
      def pick(f) = f ? [1, 2] : "s"
      p pick(true).join(nil)
      try { pick(true).join(false) }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "12"
      "ab"
      "1.52.5"
      "12"
      "123"
      "ab"
      "12"
      "12"
      "1-2"
      "ab"
      [TypeError, "no implicit conversion of false into String"]
      [TypeError, "no implicit conversion of true into String"]
      [TypeError, "no implicit conversion of Integer into String"]
      [TypeError, "no implicit conversion of Symbol into String"]
      "12"
      [TypeError, "no implicit conversion of false into String"]
    OUT
  end

  it "load error path" do
    result = ze0(<<~'RUBY')
      # `LoadError#path` names the feature that would not load. It is one of the
      # typed introspection slots an exception carries beside its message, and the
      # raise site fills it; a hand-built LoadError leaves it nil rather than raising
      # the way an unset `KeyError#key` does.
      begin
        require "definitely_not_a_gem"
      rescue LoadError => e
        p e.path
        p e.message
      end

      p LoadError.new("hand built").path
      p LoadError.new.path
      p LoadError.instance_method(:path).owner
      p LoadError.new("x").respond_to?(:path)

      # A subclass inherits the reader, and a raise through it fills the same slot.
      class VendorMissing < LoadError; end
      p VendorMissing.new("nope").path
      begin
        raise VendorMissing, "no vendor"
      rescue LoadError => e
        p [e.class, e.path]
      end

      # `load` of a missing file records its argument too.
      begin
        load "no/such/script.rb"
      rescue LoadError => e
        p e.path
      end

      # The slot is hidden, like the message slot -- it is not an ivar.
      begin
        require "another_missing_one"
      rescue LoadError => e
        p e.instance_variables
      end

      # A sibling ScriptError has no `#path`.
      p NotImplementedError.new("x").respond_to?(:path)
      p ArgumentError.new("x").respond_to?(:path)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "definitely_not_a_gem"
      "cannot load such file -- definitely_not_a_gem"
      nil
      nil
      LoadError
      true
      nil
      [VendorMissing, nil]
      "no/such/script.rb"
      [:@path]
      false
      false
    OUT
  end

  it "make shareable deep freezes a nested object graph that then crosses" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/make_shareable_deep_freezes_a_nested_object_graph_that_then_crosses.rb")
      # The plan's own listed scenario: object -> array -> object, every node
      # frozen by one make_shareable, the whole graph then crossing a Ractor
      # boundary by reference and dispatching on the far side.

      class Node
        def initialize(v, child)
          @v = v
          @child = child
        end
        def v; @v; end
      end
      leaf = Node.new(3, nil)
      root = Node.new(1, [leaf])
      Ractor.make_shareable(root)
      puts root.frozen?
      puts leaf.frozen?
      puts Ractor.shareable?(root)
      sink = Ractor.new do
        got = Ractor.receive
        got.send(:v)
      end
      sink.send(root)
      puts sink.value
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      1
    OUT
    _(result.stderr).must_equal "lang/exceptions/make_shareable_deep_freezes_a_nested_object_graph_that_then_crosses.rb:18: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
  end

  it "method level implicit rescue with no explicit begin end" do
    _(ze0(<<~'RUBY').stdout).must_equal "handled: oops\n"
      # `def m; ...; rescue => e; ...; end` -- `DefNode::body()` is directly a
      # `BeginNode` with no `begin_keyword_loc` in this shape (confirmed via
      # `Prism.parse`), flowing through the SAME `HirNode::Begin` lowering as
      # an explicit `begin`.

      class Worker
        def safe
          raise "oops"
        rescue => e
          "handled: #{e.send(:message)}"
        end
      end
      puts Worker.new.safe
    RUBY
  end

  it "method level rescue return" do
    result = ze0(<<~'RUBY')
      # Method-level rescue: when a method body is a begin/rescue, the
      # rescue body's last expression should become the method's return
      # value. CRuby semantics: `def f; X; rescue; Y; end` returns X if
      # X succeeds, Y if X raises and the rescue catches.
      #
      # This test pins int-returning shapes only. String-returning method
      # bodies with begin/rescue need a separate fix to method return-type
      # inference (which currently picks int as the default for BeginNode-
      # bodied methods regardless of the begin/rescue branch types).

      # Bare rescue catches and returns fallback
      def safe(n)
        raise "boom" if n < 0
        n
      rescue
        -1
      end
      puts safe(5)
      puts safe(-1)

      # Typed rescue catches matching class and returns from rescue body.
      # Use explicit raise rather than Integer() since spinel's Integer()
      # doesn't raise on unparseable input — separate gap, not under test.
      def parse(s)
        raise ArgumentError, "bad" if s == "nope"
        s.to_i
      rescue ArgumentError
        -999
      end
      puts parse("42")
      puts parse("nope")

      # Rescue body with multiple statements: last is the return value
      def lookup(k)
        raise "missing" if k == "x"
        k.length
      rescue
        msg = "fallback"
        msg.length
      end
      puts lookup("hello")
      puts lookup("x")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      -1
      42
      -999
      5
      8
    OUT
  end

  it "method of an unknown name raises name error at construction" do
    result = ze0(<<~'RUBY')
      begin
        "str".method(:definitely_not_defined)
      rescue NameError => e
        puts e.message
      end
      class WithPrivate
        private
        def secret = "shh"
      end
      p WithPrivate.new.method(:secret).call
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      undefined method 'definitely_not_defined' for class 'String'
      "shh"
    OUT
  end

  it "method undefined name error" do
    result = ze0(<<~'RUBY')
      # Object#method / #public_method with an undefined name raise NameError
      # immediately; a defined name still returns a callable Method.
      r = (true.method(:nope) rescue $!.class); p r
      r2 = ("s".method(:zzz) rescue $!.class); p r2
      r3 = ([1].method(:qqq) rescue $!.class); p r3
      r4 = (nil.method(:blah) rescue $!.class); p r4
      m = "abc".method(:upcase)
      p m.class
      p m.call
      class UU; def go; 7; end; end
      r5 = (UU.new.method(:nope2) rescue $!.class); p r5
      p UU.new.method(:go).call
      r6 = (5.public_method(:nope3) rescue $!.class); p r6
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NameError
      NameError
      NameError
      NameError
      Method
      "ABC"
      NameError
      7
      NameError
    OUT
  end

  it "missing qualified constant raises name error with the full path" do
    _(ze0(<<~'RUBY').stdout).must_equal "NameError: uninitialized constant Store::MISSING\n"
      module Store
      end

      begin
        puts Store::MISSING
      rescue NameError => e
        puts "NameError: #{e.message}"
      end
    RUBY
  end

  it "modifier rescue standard error" do
    result = ze0(<<~'RUBY')
      # A modifier rescue catches StandardError and its descendants only, the way the
      # full begin/rescue form does. This arm caught everything, so a subclass of
      # Exception was swallowed.
      class NotStd < Exception; end
      class Std < StandardError; end

      p((raise(Std, "s") rescue "caught-std"))
      p((raise("plain") rescue "caught-runtime"))
      p((raise(ArgumentError, "a") rescue "caught-arg"))

      # a non-StandardError passes straight through the modifier rescue
      r = begin
        (raise(NotStd, "x") rescue "should-not-catch")
      rescue Exception => e
        [e.class.to_s, e.message]
      end
      p r

      # and an explicit rescue of it still catches
      s = begin
        raise NotStd, "y"
      rescue NotStd => e2
        e2.message
      end
      p s
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "caught-std"
      "caught-runtime"
      "caught-arg"
      ["NotStd", "x"]
      "y"
    OUT
  end

  it "module const get resolves or raises name error" do
    result = ze0(<<~'RUBY')
      class Foo; BAR = 42; end
      p Foo.const_get(:BAR)
      p Foo.const_get("BAR")
      p Object.const_get(:Foo)
      p((Object.const_get(:MissingXYZ) rescue $!.class))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      42
      42
      Foo
      NameError
    OUT
  end

  it "nameerror name for constant" do
    result = ze0(<<~'RUBY')
      module CM
        A = 1
      end
      begin
        CM.const_get(:nope)
      rescue NameError => e
        p e.name
      end
      begin
        CM::Nope
      rescue NameError => e
        p e.name
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :nope
      :Nope
    OUT
  end

  it "native exception hides its message ivar" do
    result = ze0(<<~'RUBY')
      # A raised native exception exposes NO `@message` ivar (CRuby stores it in a
      # hidden slot): `instance_variables` is empty and `@message` reads nil.

      begin
        raise ArgumentError, "boom"
      rescue => e
        p e.instance_variables
        p e.instance_variable_get(:@message)
        puts e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      []
      nil
      boom
    OUT
  end

  it "native exception reopen adds and overrides" do
    result = ze0(<<~'RUBY')
      # Reopening a NATIVE exception class (D3): a reopen `def` ADDS a method that
      # reaches every subclass, and OVERRIDES an existing native method everywhere.
      # The native message lives in a hidden slot, so a reopened `message` reading
      # `@message` sees nil (CRuby parity) -- here it reads `to_s`.

      class StandardError
        def code
          42
        end
      end
      class Exception
        def message
          "patched: " + to_s
        end
      end
      begin
        raise ArgumentError, "bad value"
      rescue => e
        puts e.code
        puts e.message
        puts e.is_a?(StandardError)
      end
      begin
        raise "plain"
      rescue => e
        puts e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      42
      patched: bad value
      true
      patched: plain
    OUT
  end

  it "nested begin ensure runs inner before outer" do
    result = ze0(<<~'RUBY')
      begin
        begin
          puts "inner body"
        ensure
          puts "inner ensure"
        end
      ensure
        puts "outer ensure"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      inner body
      inner ensure
      outer ensure
    OUT
  end

  it "nested ensure self" do
    result = ze0(<<~'RUBY')
      # A method shaped `save; begin; yield self; ensure; restore; end; self` must
      # compile when it yields to a block that calls the SAME method (re-entrantly).
      #
      # The yielding-method inliner recorded the receiver-temp name in a file-static
      # buffer that g_self points into. A nested inline (the yielded block calling the
      # method again) overwrote that single static, so the outer frame's ensure and
      # trailing self emitted the inner receiver temp -- "use of undeclared identifier
      # '_tN'". Making the buffer stack-local gives each recursive inline its own.

      class C
        attr_reader :log
        def initialize = (@log = [])
        def save = (@log << :save)
        def restore = (@log << :restore)
        def with_state
          save
          begin
            yield self
          ensure
            restore
          end
          self
        end
      end

      c = C.new
      # 1. Single call.
      c.with_state { |s| s.save }
      # 2. Two-level nesting (the gap).
      c.with_state { |s| s.with_state { |ss| ss.save } }
      # 3. Three-level nesting.
      c.with_state { |s| s.with_state { |ss| ss.with_state { |sss| sss.save } } }
      p c.log.length                     #=> 15
      # 4. ensure still runs when the block raises.
      begin
        c.with_state { |s| raise "boom" }
      rescue
      end
      p c.log.last                       #=> :restore

      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      15
      :restore
      done
    OUT
  end

  it "nested retry only restarts the innermost begin" do
    result = ze0(<<~'RUBY')
      outer_runs = 0
      inner_attempts = 0
      begin
        outer_runs += 1
        begin
          inner_attempts += 1
          raise "x" if inner_attempts < 2
          puts "inner ok after #{inner_attempts}"
        rescue
          retry if inner_attempts < 2
        end
        puts "outer ran #{outer_runs} times"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      inner ok after 2
      outer ran 1 times
    OUT
  end

  it "next inside begin rescue continues the enclosing native loop" do
    result = ze0(<<~'RUBY')
      # `next` from a `rescue` clause -> `continue` the enclosing loop (H2).

      i = 0
      while i < 5
        i += 1
        begin
          raise "x" if i.even?
          puts "odd #{i}"
        rescue
          next
        end
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      odd 1
      odd 3
      odd 5
    OUT
  end

  it "next runs ensure" do
    result = ze0(<<~'RUBY')
      r = []
      [1].each do |x|
        begin
          r << :begin
          next
          r << :nope
        ensure
          r << :ensure
        end
      end
      p r
      r2 = []
      [1, 2].each do |x|
        begin
          r2 << :outer_begin
          begin
            r2 << :inner_begin
            next if x == 1
          ensure
            r2 << :inner_ensure
          end
          r2 << :after
        ensure
          r2 << :outer_ensure
        end
      end
      p r2
      r3 = []
      begin
        [1].each do |x|
          r3 << :in
          next
        end
        r3 << :out
      ensure
        r3 << :ens
      end
      p r3
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [:begin, :ensure]
      [:outer_begin, :inner_begin, :inner_ensure, :outer_ensure, :outer_begin, :inner_begin, :inner_ensure, :after, :outer_ensure]
      [:in, :out, :ens]
    OUT
  end

  it "no matching pattern error message" do
    result = ze0(<<~'RUBY')
      # `NoMatchingPatternError` names the value and the test that failed:
      #
      #     1: String === 1 does not return true
      #
      # zeo raises the same class with the message "no matching pattern", which says
      # only that something did not match.
      #
      # The detail is the whole diagnostic. A `case/in` with several branches, each
      # with nested sub-patterns, gives no other clue about WHICH branch got closest
      # or which sub-test rejected the value -- ruby's message points straight at it,
      # and that is why the message was given this shape (Bug #17925) rather than
      # staying generic.
      #
      # `NoMatchingPatternKeyError` carries the same information structurally, in
      # `#key` and `#matchee`, which zeo does answer -- so the data is present and
      # only the `NoMatchingPatternError` message is not built from it.

      begin
        case 1
        in String then :never
        end
      rescue NoMatchingPatternError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        case { a: 1 }
        in { a: String } then :never
        end
      rescue NoMatchingPatternError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        case [1, 2]
        in [Integer, String] then :never
        end
      rescue NoMatchingPatternError => e
        puts "#{e.class}: #{e.message}"
      end

      # The key error already carries its detail.
      begin
        { a: 1 } => { b: }
      rescue NoMatchingPatternKeyError => e
        puts "#{e.class}: key=#{e.key.inspect} matchee=#{e.matchee.inspect}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NoMatchingPatternError: 1: String === 1 does not return true
      NoMatchingPatternError: {a: 1}: String === 1 does not return true
      NoMatchingPatternError: [1, 2]: String === 2 does not return true
      NoMatchingPatternKeyError: key=:b matchee={a: 1}
    OUT
  end

  it "no method error messages name the real class" do
    result = ze0(<<~'RUBY')
      class Widget
      end

      w = [Widget.new].first
      begin
        w.nope
      rescue NoMethodError => e
        puts e.message
      end

      module Helper
      end

      begin
        Helper.new
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      undefined method 'nope' for an instance of Widget
      undefined method 'new' for module Helper
    OUT
  end

  it "no method error names a singleton receiver" do
    result = ze0(<<~'RUBY')
      # A `NoMethodError` names its receiver one of two ways, and which one is
      # decided by whether the receiver has a SINGLETON CLASS: `an instance of K`
      # without, `#<K:0xADDR>` with. Materializing one is the whole trigger --
      # a bare `singleton_class` call flips it, removing the last `def obj.m`
      # does not flip it back, and `freeze` never flips it.
      #
      # The address form is `rb_any_to_s`, so it ignores a `to_s` or an
      # `inspect` the class defines. That matters beyond cosmetics: building
      # this message must run no user code, which is what lets a blank-slate
      # receiver report its own missing method instead of failing a second
      # lookup while describing the first.
      class K
        def to_s = "K-TO-S"
        def inspect = "K-INSPECT"
      end
      module M; end

      def why(label)
        yield
      rescue NoMethodError => e
        puts "#{label}: #{e.message}"
      end

      why("plain") { K.new.nope }
      why("frozen") { K.new.freeze.nope }

      k = K.new
      def k.mine; end
      why("own def") { k.nope }

      e = K.new
      e.extend(M)
      why("extended") { e.nope }

      s = K.new
      s.singleton_class
      why("singleton_class asked for") { s.nope }

      r = K.new
      def r.gone; end
      r.singleton_class.send(:remove_method, :gone)
      why("last singleton method removed") { r.nope }

      str = +"text"
      def str.mine; end
      why("string") { str.nope }

      arr = [1, 2]
      def arr.mine; end
      why("array") { arr.nope }

      why("class") { K.nope }
      why("module") { M.nope }
      why("nil") { nil.nope }
      why("true") { true.nope }
      why("integer") { 5.nope }
      why("main") { self.nope }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      plain: undefined method 'nope' for an instance of K
      frozen: undefined method 'nope' for an instance of K
      own def: undefined method 'nope' for #<K:0xADDR>
      extended: undefined method 'nope' for #<K:0xADDR>
      singleton_class asked for: undefined method 'nope' for #<K:0xADDR>
      last singleton method removed: undefined method 'nope' for #<K:0xADDR>
      string: undefined method 'nope' for #<String:0xADDR>
      array: undefined method 'nope' for #<Array:0xADDR>
      class: undefined method 'nope' for class K
      module: undefined method 'nope' for module M
      nil: undefined method 'nope' for nil
      true: undefined method 'nope' for true
      integer: undefined method 'nope' for an instance of Integer
      main: undefined method 'nope' for main
    OUT
  end

  it "nomethod raises on every receiver" do
    result = ze0(<<~'RUBY')
      # An undefined method raises a rescuable NoMethodError wherever CRuby does:
      # an Array/Hash/Symbol literal and a user-class instance were refused at
      # compile time, so a program that only reaches the call behind a rescue could
      # not be built at all (#3811).
      p(begin; [1].nope; rescue NoMethodError => e; e.receiver; end)
      p(begin; :s.nope; rescue NoMethodError => e; e.message; end)
      p(begin; ({ a: 1 }).nope; rescue NoMethodError => e; e.name; end)
      class Plain; end
      p(begin; Plain.new.nope; rescue NoMethodError => e; e.message; end)
      xs = [1, 2]
      p(begin; xs.nope; rescue NoMethodError => e; e.message; end)
      p(begin; (1..3).nope; rescue NoMethodError => e; e.message; end)
      p(begin; nil.nope; rescue NoMethodError => e; e.message; end)
      p(begin; "s".nope; rescue NoMethodError => e; e.message; end)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [1]
      "undefined method 'nope' for an instance of Symbol"
      :nope
      "undefined method 'nope' for an instance of Plain"
      "undefined method 'nope' for an instance of Array"
      "undefined method 'nope' for an instance of Range"
      "undefined method 'nope' for nil"
      "undefined method 'nope' for an instance of String"
    OUT
  end

  it "nomethod receiver parens" do
    result = ze0(<<~'RUBY')
      r001 = (begin; ({a: 1}).nope; rescue NoMethodError => e001; e001.receiver; end); p r001

      p(begin; ({}).nope; rescue NoMethodError => e; e.receiver; end)
      # Ruby: {}   Spinel: nil
      p(begin; ({"x" => 1}).nope; rescue NoMethodError => e; e.receiver; end)
      # Ruby: {"x" => 1}   Spinel: nil
      p(begin; ({a: 1}).nope; rescue NoMethodError => e; e.receiver.class; end)
      # Ruby: Hash   Spinel: NilClass

      h = {a: 1}
      p(begin; h.nope; rescue NoMethodError => e; e.receiver; end)      # => {a: 1}
      p(begin; ({a: 1}).nope; rescue NoMethodError => e; e.name; end)   # => :nope
      p(begin; ({a: 1}).nope; rescue NoMethodError => e; e.message; end)
      #   => "undefined method 'nope' for an instance of Hash"
      p(begin; [1].nope; rescue NoMethodError => e; e.receiver; end)    # => [1]
      p(begin; :s.nope; rescue NoMethodError => e; e.receiver; end)     # => :s
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      {a: 1}
      {}
      {"x" => 1}
      Hash
      {a: 1}
      :nope
      "undefined method 'nope' for an instance of Hash"
      [1]
      :s
    OUT
  end

  it "nomethod scalar slot" do
    _(ze0(<<~'RUBY').stdout).must_equal "NoMethodError\n"
      # An unresolved method on a poly receiver whose call type is a concrete scalar
      # must yield that scalar (a raising comma-expr), not the sp_RbVal raise token,
      # so it fits a typed slot rather than failing the C compile (#2451). The
      # raise still fires at runtime (CRuby's NoMethodError).
      class CommentRow
        def created_at; "2020-01-01"; end
      end
      class StoryRow
        def created_at; "2021-02-02"; end
      end
      class Wrap
        def initialize(note); @note = note; end
        def render
          s = @note.created_at.strftime("%Y")
          s.to_s
        end
      end
      begin
        puts Wrap.new(CommentRow.new).render
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY
  end

  it "pattern key error class" do
    result = ze0(<<~'RUBY')
      # A hash pattern that misses a KEY raises `NoMatchingPatternKeyError` in CRuby,
      # carrying the key it wanted and the Hash it was asked of. zeo raised the parent
      # `NoMatchingPatternError` with no detail.
      #
      # A pattern compiles to ONE boolean, so by the time the `expr => pattern` arm
      # raises, the expression tree that knew which key was absent is gone. The miss
      # is recorded where it happens and read back at the raise
      # (`zeo_rt::pattern_match_error`), and the record is cleared at the start of
      # every required match so a `case/in` arm that simply did not apply cannot leak
      # into a later failure.
      #
      # A key that is PRESENT with a non-matching value is a different failure and
      # keeps the parent class, which is why the two are kept apart at the check.

      def t(label)
        yield
        puts "#{label}: no raise"
      rescue NoMatchingPatternError => e
        key = e.respond_to?(:key) ? e.key.inspect : "-"
        matchee = e.respond_to?(:matchee) ? e.matchee.inspect : "-"
        puts "#{label}: #{e.class} key=#{key} matchee=#{matchee}"
      end

      t("missing key") { { a: 1 } => { b: } }
      t("missing, several") { { a: 1 } => { a:, b:, c: } }

      # A NESTED miss names the inner key and the inner hash -- but the message still
      # quotes the outermost subject.
      t("nested missing") { { a: { b: 1 } } => { a: { c: } } }

      # Everything that is not a missing key stays the parent class.
      t("wrong value") { { a: 1 } => { a: 2 } }
      t("array length") { [1] => [1, 2] }
      t("not a hash") { 5 => { a: } }

      # A match that SUCCEEDS leaves nothing behind for the next one to read.
      t("ok") { { a: 1 } => { a: } }
      t("after ok") { { a: 1 } => { z: } }

      # ...and neither does a `case/in` arm that merely did not apply: the array
      # failure below must not report itself as a key error.
      t("case then array fail") do
        case { a: 1 }
        in { q: } then :q
        in { a: } then :a
        end
        [1] => [1, 2]
      end

      # `case/in` itself never raises the key error -- a missing key just means that
      # arm does not match.
      result = case { a: 1 }
               in { b: } then :b
               in { a: } then :a
               end
      p result

      begin
        case { a: 1 }
        in { b: } then :b
        end
      rescue NoMatchingPatternError => e
        p e.class
      end

      p NoMatchingPatternKeyError.ancestors.include?(NoMatchingPatternError)
      p NoMatchingPatternKeyError.new(matchee: { a: 1 }, key: :b).key
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      missing key: NoMatchingPatternKeyError key=:b matchee={a: 1}
      missing, several: NoMatchingPatternKeyError key=:b matchee={a: 1}
      nested missing: NoMatchingPatternKeyError key=:c matchee={b: 1}
      wrong value: NoMatchingPatternError key=- matchee=-
      array length: NoMatchingPatternError key=- matchee=-
      not a hash: NoMatchingPatternError key=- matchee=-
      ok: no raise
      after ok: NoMatchingPatternKeyError key=:z matchee={a: 1}
      case then array fail: NoMatchingPatternError key=- matchee=-
      :a
      NoMatchingPatternKeyError
      true
      :b
    OUT
  end

  it "poly length size nomethod" do
    result = ze0(<<~'RUBY')
      # `length` / `size` on a boxed receiver that has neither: the poly length
      # helper answered 0 for nil, a number and a user object, so a nil read out of
      # a hash miss answered 0 where CRuby raises NoMethodError (#3974).
      def probe(v)
        begin
          v.length
        rescue NoMethodError => e
          "raise: #{e.message}"
        end
      end
      p probe(nil)
      p probe("abc")
      p probe([1, 2])
      p probe({ a: 1 })
      p probe(5)
      p probe(:sym)
      def psize(v)
        begin
          v.size
        rescue NoMethodError => e
          "raise: #{e.message}"
        end
      end
      p psize(nil)
      p psize(5)
      p psize("abc")
      p psize([1, 2])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "raise: undefined method 'length' for nil"
      3
      2
      1
      "raise: undefined method 'length' for an instance of Integer"
      3
      "raise: undefined method 'size' for nil"
      8
      3
      2
    OUT
  end

  it "poly receiver call with unknown keyword raises at runtime" do
    _(ze0(<<~'RUBY').stdout).must_equal "no method, kwargs carried\n"
      # The other old silent-drop site: kwargs on a Poly receiver now ride
      # the G2 convention; an undefined method stays a real NoMethodError.

      begin
        raise "boom"
      rescue => e
        begin
          e.foo(bar: 1)
        rescue NoMethodError
          puts "no method, kwargs carried"
        end
      end
    RUBY
  end

  it "poly recv int iterators" do
    result = ze0(<<~'RUBY')
      # times / upto / downto with a block, on a receiver only known to be an
      # Integer at run time. The arm that unboxes a boxed receiver and re-dispatches
      # through the typed Integer emitters only ever ran for the BLOCKLESS names, so
      # these raised NoMethodError naming Integer, the class that defines them.
      def pick(n) = n > 0 ? 3 : "x"

      v = pick(1)
      acc = []
      v.times { |i| acc << i }
      v.upto(5) { |i| acc << i }
      v.downto(1) { |i| acc << i }
      p acc

      # each answers the receiver, and a break value is still the call's value
      p v.times { |i| i }
      p v.upto(5) { |i| i }
      p v.downto(1) { |i| i }
      p(v.times { |i| break i * 10 if i == 2 })

      # a receiver that is not an Integer answers NoMethodError, as CRuby does --
      # the plain coercion the blockless names use would have run the loop zero
      # times instead
      begin
        pick(0).times { |i| p i }
      rescue NoMethodError => e
        p e.message
      end

      # and nil short-circuits through a safe-nav guard
      def maybe(n) = n > 0 ? 3 : nil
      [1, 0].each do |k|
        w = maybe(k)
        p w&.times { |i| i }
        p w&.upto(5) { |i| i }
        p w&.downto(1) { |i| i }
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [0, 1, 2, 3, 4, 5, 3, 2, 1]
      3
      3
      3
      20
      "undefined method 'times' for an instance of String"
      3
      3
      3
      nil
      nil
      nil
    OUT
  end

  it "poly sign predicate user zero" do
    result = ze0(<<~'RUBY')
      # A user class defining zero? claims the name, so every call on a poly receiver
      # goes through the class dispatch. A Float or Integer arriving at that same call
      # site still has to answer its own sign from the runtime tag - the dispatch used
      # to fall through to the empty default and report false for every number.

      class Meter
        def initialize(n) = @n = n
        def zero? = @n == 0
      end

      def zero(v) = v.zero?
      def zero_via(pair) = zero(pair[1])

      puts zero_via([:m, Meter.new(5)])
      puts zero_via([:m, Meter.new(0)])
      puts zero_via([:m, 0.004])
      puts zero_via([:m, 0.0])
      puts zero_via([:m, 3])
      puts zero_via([:m, 0])

      # A tag with no sign raises NoMethodError, the same as CRuby.
      begin
        puts zero_via([:m, "abc"])
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      true
      false
      true
      false
      true
      NoMethodError
    OUT
  end

  it "prepend on builtin exception ignored" do
    _(ze0(<<~'RUBY').stdout).must_equal "\"[undefined method 'lenght' for an instance of String (NoMethodError)\\n\\n  \\\"abc\\\".lenght\\n       ^^^^^^^\\nDid you mean?  length]\"\n"
      module Wrap
        def detailed_message(highlight: true, **)
          "[" + super + "]"
        end
      end

      NoMethodError.prepend(Wrap)

      begin
        "abc".lenght
      rescue NoMethodError => e
        p e.detailed_message(highlight: false)
      end
    RUBY
  end

  it "private method called with an explicit receiver raises at runtime" do
    result = ze0(<<~'RUBY')
      # A visibility violation is RUNTIME behavior in Ruby, not a syntax
      # error: it raises NoMethodError when the call actually runs, so it can
      # be rescued and an unreachable one stays silent. Message shape and
      # both behaviors oracle-verified.

      class Box
        def initialize
          @x = 1
        end

        private

        def helper
          2
        end
      end

      b = Box.new
      begin
        b.helper
      rescue NoMethodError => e
        puts e.message
      end

      def never_runs(b)
        b.helper
      end
      puts "still here"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      private method 'helper' called for an instance of Box
      still here
    OUT
  end

  it "proc return ensure raise" do
    _(ze0(<<~'RUBY').stdout).must_equal "rescued: from ensure\n"
      # An exception raised inside an `ensure` that runs during a proc-return unwind
      # supersedes the return: it must propagate as a real exception, not be swallowed
      # while the abandoned non-local return is silently resumed.
      def home
        proc {
          begin
            return 1
          ensure
            raise "from ensure"
          end
        }.call
        2
      end
      begin
        puts home
      rescue => e
        puts "rescued: #{e.message}"
      end
    RUBY
  end

  it "proc return nested ensure" do
    _(ze0(<<~'RUBY').stdout).must_equal "  inner ensure\nensure ran (10)\nouter-value\n"
      # A nested non-local return that itself runs an ensure -- and so completes a
      # full unwind -- while executing inside an outer proc-return's ensure must not
      # discard the outer return. The outer `return "outer-value"` runs its ensure,
      # which calls inner_ret (whose own proc-return passes an ensure and resolves);
      # the outer return value still has to be delivered.
      def inner_ret
        proc {
          begin
            return 10
          ensure
            puts "  inner ensure"
          end
        }.call
        20
      end
      def outer
        proc {
          begin
            return "outer-value"
          ensure
            x = inner_ret
            puts "ensure ran (#{x})"
          end
        }.call
        "WRONG: fell through"
      end
      puts outer
    RUBY
  end

  it "proc return rescue modifier escape" do
    result = ze0(<<~'RUBY')
      # Same home-escape-via-exception case as proc_return_escape_localjump, but the
      # exception is caught by an *expression-form* `rescue` modifier (a distinct
      # codegen path). The home node must still be dropped as the exception unwinds,
      # so the later return raises LocalJumpError rather than longjmping into a freed
      # frame.
      $escaped = nil
      def home
        $escaped = proc { return 99 }
        raise "boom"
      end
      v = (home rescue 123)
      p v
      begin
        $escaped.call
        puts "WRONG: no error"
      rescue LocalJumpError => e
        puts "localjump: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      123
      localjump: unexpected return
    OUT
  end

  it "proc unknown tail raise" do
    result = ze0(<<~'RUBY')
      # A proc whose tail is an sp_RbVal- or sp_Class-valued raising expression
      # (unresolved-call gate / NameError constant read) must coerce into the proc's
      # mrb_int return carrier instead of returning the mismatched C type raw.
      x = [1, "a"].sample
      g = -> { x.no_such_method_here }   # gate: sp_raise_nomethod (sp_RbVal tail)
      h = -> { NoSuchConst }             # NameError constant read (sp_Class dummy)
      begin
        g.call
      rescue Exception => e
        puts e.class
      end
      begin
        h.call
      rescue Exception => e
        puts e.class
      end
      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NoMethodError
      NameError
      done
    OUT
  end

  it "protected method called from outside any related class raises at runtime" do
    _(ze0(<<~'RUBY').stdout).must_equal "protected method 'amount' called for an instance of Money\n"
      # Same rule as the private case above -- a runtime NoMethodError.

      class Money
        def initialize(amount)
          @amount = amount
        end

        protected

        def amount
          @amount
        end
      end

      a = Money.new(10)
      begin
        a.amount
      rescue NoMethodError => e
        puts e.message
      end
    RUBY
  end

  it "raise branch does not widen" do
    result = ze0(<<~'RUBY')
      # a branch that raises contributes no type to the case/if it sits in
      def enc(o)
        case o
        when Integer then 7
        when String  then 12
        else raise ArgumentError, "no"
        end
      end
      v = enc("ab")
      p v.class
      p v.succ
      p v.succ.class

      def s(o)
        case o
        when Integer then "i"
        when String  then "sample text"
        else raise ArgumentError, "no"
        end
      end
      p s("ab").count("s")
      p s("ab").sum
      p s("ab").match?(/\w/)

      def enc2(o)
        if o.is_a?(String) then "sample text" else raise ArgumentError, "no" end
      end
      p enc2("ab").match?(/\w/)

      def h(o)
        case o
        when Integer then {"a" => 1}
        when String  then {"b" => 2}
        else raise ArgumentError, "no"
        end
      end
      p h("ab").sum { |_k, v| v }

      # the raising branch is still taken when it should be
      r = (enc(1.5) rescue $!.class)
      p r
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Integer
      13
      Integer
      1
      1127
      true
      true
      2
      ArgumentError
    OUT
  end

  it "raise cause and backrefs" do
    result = ze0(<<~'RUBY')
      # Three lowering gaps that CRuby resolves differently than a naive compiler
      # would: an explicit `cause:`, the `$+` backreference, and adjacent
      # interpolated string literals.

      # 1. `raise ..., cause:` is genuinely THREE-state. An omitted cause: chains
      #    automatically from $!; `cause: nil` SUPPRESSES that chaining; a value
      #    installs it. The first two mean opposite things, so they cannot share a
      #    representation.
      def blow(m); raise "top", cause: ArgumentError.new(m); end
      begin
        blow("root")
      rescue => e
        p e.cause
        puts e.message
      end

      begin
        begin
          raise ArgumentError, "inner"
        rescue ArgumentError
          raise "outer"
        end
      rescue => e
        p e.cause          # implicit chaining still applies
      end

      begin
        begin
          raise ArgumentError, "inner2"
        rescue ArgumentError
          raise "outer2", cause: nil
        end
      rescue => e
        p e.cause          # nil -- explicitly suppressed
      end

      begin
        raise "x", cause: 5
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end

      begin
        a = RuntimeError.new("a")
        b = RuntimeError.new("b")
        begin
          raise a, cause: b
        rescue; end
        raise b, cause: a
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end

      # 2. `$+` is the highest-numbered group that actually PARTICIPATED, skipping
      #    declared-but-unmatched ones, and is nil when only group 0 matched.
      "abc123" =~ /([a-z]+)(\d+)/
      puts $1
      puts $2
      puts $+
      "abc" =~ /([a-z]+)(\d+)?/
      puts $1
      puts $+           # steps back to the group that did match
      "xyz" =~ /xyz/
      p $+              # nil -- $+ never reports the whole match
      "b" =~ /(a)|(b)|(c)/
      p $+

      # 3. Backslash-continued adjacent literals parse as an interpolated string
      #    whose own parts are interpolated strings, so parts must flatten.
      def svg(px, inner)
        "<a width='#{px}' " \
        "height='#{px}'>#{inner}</a>"
      end
      def three(a, b)
        "[" \
        "#{a}-#{b}" \
        "]"
      end
      def tail(n)
        "n=#{n}" \
        " done"
      end
      puts svg(16, "x")
      puts three("L", "R")
      puts tail(7)

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      #<ArgumentError: root>
      top
      #<ArgumentError: inner>
      nil
      TypeError: exception object expected
      ArgumentError: circular causes
      abc
      123
      123
      abc
      abc
      nil
      "b"
      <a width='16' height='16'>x</a>
      [L-R]
      n=7 done
    OUT
  end

  it "raise cause is three state" do
    result = ze0(<<~'RUBY')
      # CRuby distinguishes three states with a Qundef/Qnil/value sentinel
      # (rb_f_raise, eval.c:740), and the first two mean OPPOSITE things: an
      # omitted `cause:` chains automatically from $!, while `cause: nil`
      # SUPPRESSES that chaining. Modeling this as Option<NodeId> would lower
      # `cause: nil` to None and silently chain anyway -- so both are asserted
      # here, along with the TypeError and circular-cause rejections.

      def blow(m); raise "top", cause: ArgumentError.new(m); end
      begin
        blow("root")
      rescue => e
        p e.cause
        puts e.message
      end
      begin
        begin
          raise ArgumentError, "inner"
        rescue ArgumentError
          raise "outer"
        end
      rescue => e
        p e.cause
      end
      begin
        begin
          raise ArgumentError, "inner2"
        rescue ArgumentError
          raise "outer2", cause: nil
        end
      rescue => e
        p e.cause
      end
      begin
        raise "x", cause: 5
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      begin
        a = RuntimeError.new("a")
        b = RuntimeError.new("b")
        begin
          raise a, cause: b
        rescue; end
        raise b, cause: a
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      #<ArgumentError: root>
      top
      #<ArgumentError: inner>
      nil
      TypeError: exception object expected
      ArgumentError: circular causes
    OUT
  end

  it "raise class value" do
    result = ze0(<<~'RUBY')
      # `raise` given the exception CLASS as a VALUE -- a local, an element of a
      # table of error classes, a retry list -- rather than as a syntactically
      # literal constant name. Codegen builds the literal form directly and hands
      # every other operand to the runtime coercion, which raises a fresh instance
      # of an Exception class through `#exception` (so a custom `initialize` runs),
      # raises an Exception object as itself, wraps a String in a `RuntimeError`,
      # and answers `TypeError: exception class/object expected` for anything else.
      module App
        class Failed < RuntimeError; end
        class Refused < App::Failed; end
      end

      k = App::Failed
      begin
        raise k
      rescue => e
        puts "#{e.class}|#{e.message}|#{e.is_a?(App::Failed)}"
      end

      [App::Failed, App::Refused, ArgumentError].each do |kk|
        begin
          raise kk
        rescue => e
          puts "#{e.class}|#{e.is_a?(App::Failed)}"
        end
      end

      # a rescue arm still selects on the raised class
      begin
        raise App::Refused
      rescue App::Failed => e
        puts "caught #{e.class}"
      end

      # a non-exception class is still CRuby's TypeError
      bad = String
      begin
        raise bad
      rescue TypeError => e
        puts "TypeError"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      App::Failed|App::Failed|true
      App::Failed|true
      App::Refused|true
      ArgumentError|false
      caught App::Refused
      TypeError
    OUT
  end

  it "raise computed class" do
    result = ze0(<<~'RUBY')
      # `raise <computed>, message` -- a runtime-computed exception class/instance
      # (not a literal constant) coerces like Kernel#raise (`klass.exception(msg)`).
      def boom(klass) = raise klass, "boom from #{klass}"

      [ArgumentError, TypeError, RuntimeError].each do |k|
        begin
          boom(k)
        rescue => e
          puts "#{e.class}: #{e.message}"
        end
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError: boom from ArgumentError
      TypeError: boom from TypeError
      RuntimeError: boom from RuntimeError
    OUT
  end

  it "raise forwards its arguments" do
    result = ze0(<<~'RUBY')
      # `raise(...)` -- argument forwarding into raise. The static raise desugar
      # has no shape for `...`, so it must route through the general call
      # lowering, which expands the forwarding into `*rest, **kw, &blk` and
      # reaches the runtime `Kernel#raise` row (sus forwards a matcher's whole
      # failure this way).
      def reraise(...)
        raise(...)
      end

      begin
        reraise(ArgumentError, "forwarded")
      rescue ArgumentError => e
        puts e.message
      end

      begin
        reraise("plain message")
      rescue RuntimeError => e
        puts e.message
      end

      # The splat spelling stays on the same path.
      def splat_raise(*exc)
        raise(*exc)
      end

      begin
        splat_raise(TypeError, "splatted")
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      forwarded
      plain message
      splatted
    OUT
  end

  it "raise in ensure loses cause" do
    result = ze0(<<~'RUBY')
      # An exception raised inside an `ensure` while another is propagating takes the
      # propagating one as its `cause`. zeo leaves `cause` nil, so the original
      # failure is gone.
      #
      # Ruby sets `cause` from whatever is in flight at the raise -- `$!` -- and an
      # `ensure` running during propagation has the original in `$!`. That is the one
      # case where the cause chain matters most: the ensure's own failure (a close
      # that fails, a rollback that fails) is what surfaces, and the cause is the only
      # remaining record of what went wrong first.
      #
      # zeo already builds the chain for the ordinary shape -- a raise inside a
      # `rescue` gets its cause (the second block below) -- so `$!` is tracked and the
      # ensure path simply does not consult it.

      begin
        begin
          raise "first"
        ensure
          raise "second"
        end
      rescue => e
        p [e.message, e.cause&.message]
      end

      # Already correct: raising from a rescue.
      begin
        begin
          raise "orig"
        rescue
          raise "wrapped"
        end
      rescue => e
        p [e.message, e.cause&.message]
      end

      # Three deep, through an ensure in the middle.
      begin
        begin
          begin
            raise "a"
          ensure
            raise "b"
          end
        rescue
          raise "c"
        end
      rescue => e
        p [e.message, e.cause&.message, e.cause&.cause&.message]
      end

      # An ensure that raises with NOTHING in flight has no cause in ruby either.
      begin
        begin
          :fine
        ensure
          raise "alone"
        end
      rescue => e
        p [e.message, e.cause&.message]
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["second", "first"]
      ["wrapped", "orig"]
      ["c", "b", "a"]
      ["alone", nil]
    OUT
  end

  it "raise inside ensure replaces the original exception" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught: from ensure\n"
      begin
        begin
          raise "original"
        ensure
          raise "from ensure"
        end
      rescue => e
        puts "caught: #{e.send(:message)}"
      end
    RUBY
  end

  it "raise kinds" do
    result = ze0(<<~'RUBY')
      # `raise` accepts several operand shapes: a message string raises a
      # RuntimeError, an exception class (with an optional message) raises an
      # instance of it, and any NON-exception value is a TypeError.
      def try
        yield
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      try { raise "boom" }                # RuntimeError: boom
      try { raise ArgumentError, "bad" }  # ArgumentError: bad
      try { raise ArgumentError }         # ArgumentError: ArgumentError
      try { raise 42 }                    # TypeError: exception class/object expected
      try { raise nil }                   # TypeError: exception class/object expected
      try { raise [1, 2] }                # TypeError: exception class/object expected
      try { raise :nope }                 # TypeError: exception class/object expected

      # The operand can be a runtime-typed (poly) value; raise dispatches on its
      # actual class.
      things = ["late", 99]
      try { raise things[0] }             # RuntimeError: late
      try { raise things[1] }             # TypeError: exception class/object expected
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      RuntimeError: boom
      ArgumentError: bad
      ArgumentError: ArgumentError
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      RuntimeError: late
      TypeError: exception class/object expected
    OUT
  end

  it "raise non exception typeerror" do
    result = ze0(<<~'RUBY')
      # `raise <non-exception>` is CRuby's TypeError, not a value smuggled into
      # the message slot (a C type error for scalars, garbage for the rest).
      def try
        yield
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      try { raise 42 }
      try { raise nil }
      try { raise [1, 2] }
      try { raise :sym }
      try { raise 3.5 }
      try { raise({ a: 1 }) }
      # a string still raises RuntimeError with the message
      begin
        raise "boom"
      rescue RuntimeError => e
        puts "RuntimeError: #{e.message}"
      end
      # a runtime-typed (poly) operand dispatches on the value
      mixed = [Object.new, "msg"]
      begin
        raise mixed[1]
      rescue RuntimeError => e
        puts "poly string: #{e.message}"
      end
      begin
        raise mixed[0]
      rescue TypeError => e
        puts "poly object: #{e.message}"
      end
      puts "after"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      RuntimeError: boom
      poly string: msg
      poly object: exception class/object expected
      after
    OUT
  end

  it "raise reraise in def" do
    result = ze0(<<~'RUBY')
      # Phase 1A: bare `raise` (re-raise) inside a def's rescue clause.
      # Pre-fix the codegen routed the surrounding begin/rescue's body
      # through compile_body_into which uses compile_expr for the last
      # stmt; compile_expr's raise arm ignored the 2-arg form and emitted
      # `sp_raise(<class_expr>)` -- passing an sp_Class compound literal to
      # sp_raise(const char *), C compile fail. Fix: expr-form raise now
      # mirrors compile_control_call_stmt's 2-arg handling
      # (sp_raise_cls("ClassName", msg)).

      def helper
        begin
          raise StandardError, "inner"
        rescue => e
          raise
        end
      end

      begin
        helper
      rescue => e
        puts "outer: #{e.class}: #{e.message}"
      end

      # Variant: 2-arg raise as the only statement (no rescue, propagates).
      def thrower
        raise ArgumentError, "from thrower"
      end

      begin
        thrower
      rescue ArgumentError => e
        puts "caught: #{e.message}"
      end

      # Variant: 1-arg raise (string only) in def + outer rescue.
      def thrower2
        raise "plain message"
      end

      begin
        thrower2
      rescue => e
        puts "got: #{e.class}: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      outer: StandardError: inner
      caught: from thrower
      got: RuntimeError: plain message
    OUT
  end

  it "raise shortform default args" do
    result = ze0(<<~'RUBY')
      # A short-form `raise Cls, "msg"` of an exception whose initialize has
      # defaulted parameters (positional or keyword) must fill those defaults at
      # the generated constructor call site: sp_Cls_new keeps the full signature,
      # so a message-only emission is a cc arity error.
      class Boom < StandardError
        attr_reader :level, :code
        def initialize(message, level = 7, code: 3)
          super(message)
          @level = level
          @code = code
        end
      end

      begin
        raise Boom, "one-arg raise"
      rescue Boom => e
        puts "#{e.message} level=#{e.level} code=#{e.code}"
      end

      begin
        raise Boom.new("explicit", 8, code: 9)
      rescue Boom => e
        puts "#{e.message} level=#{e.level} code=#{e.code}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      one-arg raise level=7 code=3
      explicit level=8 code=9
    OUT
  end

  it "raise takes one keyword and collapses the rest" do
    result = ze0(<<~'RUBY')
      # `cause:` is the only keyword `raise` reads. Anything else written that way is
      # not a keyword at all: ruby collapses the rest into ONE Hash and passes it as
      # an ordinary positional argument, so it lands in the MESSAGE slot and reaches
      # `TheError.exception(hash)`.
      #
      # pundit writes `raise NotAuthorizedError, query: query, record: record,
      # policy: policy`, and its error class takes a positional options hash. Reading
      # those as keywords zeo had to accept made the whole gem a compile error.

      class Denied < StandardError
        def initialize(options = {})
          @options = options
          super("denied #{options[:query]}")
        end

        attr_reader :options
      end

      begin
        raise Denied, query: :show?, record: 7
      rescue Denied => e
        p e.message
        p e.options
      end

      # An error class that takes a real message gets the HASH as its message, which
      # is exactly what ruby does -- no keyword is special here either.
      begin
        raise ArgumentError, message: "params must be a Hash"
      rescue ArgumentError => e
        p e.message
      end

      prior = RuntimeError.new("prior")

      # `cause:` is taken OUT of the collapsed hash, and the rest still collapses.
      begin
        raise Denied, query: :edit?, cause: prior
      rescue Denied => e
        p e.options
        p e.cause.message
      end

      # With nothing left after `cause:` comes out, no extra positional is passed at
      # all -- `Denied.new` runs on its default.
      begin
        raise Denied, cause: prior
      rescue Denied => e
        p e.options
        p e.cause.message
      end

      # `**h` is part of the collapsed hash like any pair.
      h = { query: :splatted, record: 1 }

      begin
        raise Denied, **h
      rescue Denied => e
        p e.options
      end

      # A `cause:` beside a real message positional leaves the message alone: the
      # keyword never reaches the exception at all.
      class Simple < StandardError; end

      begin
        raise Simple, "explicit", cause: prior
      rescue Simple => e
        p e.message
        p e.cause.message
      end

      # `fail` is the same method under its other name.
      begin
        fail Denied, query: :destroy?
      rescue Denied => e
        p e.options
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "denied show?"
      {query: :show?, record: 7}
      "{message: \"params must be a Hash\"}"
      {query: :edit?}
      "prior"
      {}
      "prior"
      {query: :splatted, record: 1}
      "explicit"
      "prior"
      {query: :destroy?}
    OUT
  end

  it "raise uses exception hook" do
    _(ze0(<<~'RUBY').stdout).must_equal "\"custom: x\"\n"
      class CustomE < StandardError
        def self.exception(msg = nil) = new("custom: #{msg}")
      end

      begin
        raise CustomE, "x"
      rescue => e
        p e.message
      end
    RUBY
  end

  it "raise with a bare class defaults the message to the class name" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/raise_with_a_bare_class_defaults_the_message_to_the_class_name.rb")
      # Assert the UNCAUGHT path here (see the `rescue` tests below for the
      # caught path): an unhandled `raise MyError` (no explicit message) exits 1 with the
      # class's own name as the message (no runtime `self.class` reflection
      # needed).

      class MyError < StandardError
      end
      class Box
        def check
          raise MyError
        end
      end
      Box.new.check
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "lang/exceptions/raise_with_a_bare_class_defaults_the_message_to_the_class_name.rb:10:in 'Box#check': MyError (MyError)\n\tfrom lang/exceptions/raise_with_a_bare_class_defaults_the_message_to_the_class_name.rb:13:in '<main>'\n"
    _(result.status).must_equal 1
  end

  it "raise with a bare class runs the classs own initialize" do
    result = ze0(<<~'RUBY')
      # `raise E` must CONSTRUCT via `E.new` -- running defaults and `super`
      # -- rather than short-cutting the message to the class name. The
      # class-name default lives in the prelude's `Exception#to_s`.

      class E < StandardError
        def initialize(m = "def")
          super
        end
      end
      class F < StandardError
        def initialize(m = "dd")
          super("wrapped: #{m}")
        end
      end
      class G < StandardError; end

      begin; raise E; rescue => e; p e.message; end
      begin; raise E, "x"; rescue => e; p e.message; end
      begin; raise E.new; rescue => e; p e.message; end
      begin; raise F; rescue => e; p e.message; end
      begin; raise G; rescue => e; p e.message; end
      begin; raise StandardError; rescue => e; p e.message; end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "def"
      "x"
      "def"
      "wrapped: dd"
      "G"
      "StandardError"
    OUT
  end

  it "raise with a splat argument reraises the class and message" do
    _(ze0(<<~'RUBY').stdout).must_equal "wrapped: orig\n"
      # `raise(*exc)` -- a splat whose element count is a runtime value -- routes
      # through the runtime `Kernel#raise` (optparse's `{|*exc| raise(*exc)}`),
      # rather than the static 0..3-arg form.

      def relay
        yield
      rescue => e
        exc = [ArgumentError, "wrapped: #{e.message}"]
        raise(*exc)
      end
      begin
        relay { raise "orig" }
      rescue ArgumentError => e
        puts e.message
      end
    RUBY
  end

  it "raise with an exception hook" do
    _(ze0(<<~'RUBY').stdout).must_equal "custom exception hook: hi\ncustom exception hook: \n"
      # `raise obj, "msg"` where obj's class overrides #exception does not even
      # BUILD: codegen hands the constructed object to the raise-argument
      # coercion unboxed, where a boxed value is wanted, and the generated program
      # is rejected. Any program using this shape fails to compile, so this gap
      # "diverges" by failing to produce a binary at all.
      class WithHook
        def exception(msg = nil)
          RuntimeError.new("custom exception hook: #{msg}")
        end
      end

      begin
        raise WithHook.new, "hi"
      rescue => e
        puts e.message
      end

      begin
        raise WithHook.new
      rescue => e
        puts e.message
      end
    RUBY
  end

  it "raise with an explicit message and class" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/raise_with_an_explicit_message_and_class.rb")
      class MyError < StandardError
      end
      class Risky
        def check(n)
          raise MyError, "bad value: #{n}" if n < 0
          n * 2
        end
      end
      r = Risky.new
      puts r.check(5)
      puts r.check(-1)
    RUBY

    _(result.stdout).must_equal "10\n"
    _(result.stderr).must_equal "lang/exceptions/raise_with_an_explicit_message_and_class.rb:5:in 'Risky#check': bad value: -1 (MyError)\n\tfrom lang/exceptions/raise_with_an_explicit_message_and_class.rb:11:in '<main>'\n"
    _(result.status).must_equal 1
  end

  it "raising a non exception is a type error" do
    result = ze0(<<~'RUBY')
      # `raise <non-exception>` coerces at runtime -- a String becomes a
      # RuntimeError, everything else is CRuby's TypeError -- instead of
      # panicking when the raise machinery unwraps a non-Object.

      def try
        yield
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      try { raise 42 }
      try { raise nil }
      try { raise :sym }
      begin
        raise "boom"
      rescue RuntimeError => e
        puts "RuntimeError: #{e.message}"
      end
      mixed = [Object.new, "msg"]
      begin
        raise mixed[1]
      rescue RuntimeError => e
        puts "poly string: #{e.message}"
      end
      begin
        raise mixed[0]
      rescue TypeError => e
        puts "poly object: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      TypeError: exception class/object expected
      RuntimeError: boom
      poly string: msg
      poly object: exception class/object expected
    OUT
  end

  it "raising an undefined constant with a message raises name error" do
    _(ze0(<<~'RUBY').stdout).must_equal "NameError: uninitialized constant Nope\n"
      # `raise UndefinedConst, "msg"` -- CRuby evaluates the constant (and
      # raises NameError) before the message is ever consulted.

      r = begin
        raise Nope, "msg"
      rescue => e
        "#{e.class}: #{e.message}"
      end
      puts r
    RUBY
  end

  it "re raise preserves the exact same object not a copy" do
    _(ze0(<<~'RUBY').stdout).must_equal "tag: mutated\n"
      # Proves re-raise doesn't construct a fresh exception -- mutating an
      # ivar (via an `attr_accessor`-generated setter) INSIDE the inner
      # `rescue`, then bare `raise`-ing, must be visible to the OUTER
      # `rescue` reading the same ivar back. Constructed and raised in ONE
      # expression (`raise Tagged.new(...)`), not first assigned to a named
      # local -- a named local assigned an `Object`-typed value inside a
      # `begin`'s body (or any branching construct) hits a real, pre-existing
      # codegen gap when that local's type has to widen
      # to `Poly` across branches (confirmed to affect plain `if`/`else` too,
      # unrelated to exception handling itself).

      class Tagged < StandardError
        def initialize(msg, tag)
          super(msg)
          @tag = tag
        end
        attr_accessor :tag
      end
      begin
        begin
          raise Tagged.new("x", "initial")
        rescue Tagged => e
          e.send(:tag=, "mutated")
          raise
        end
      rescue Tagged => e
        puts "tag: #{e.send(:tag)}"
      end
    RUBY
  end

  it "reopening a frozen class raises" do
    result = ze0(<<~'RUBY')
      # A REOPEN of a frozen class is a `FrozenError` and its body never runs -- so
      # the methods that body would have installed do not exist. zeo's compile-time
      # tables already carry them, so the guard retires them at the reopen's own
      # position. Gated on the program calling `freeze` at all: without one the shape
      # is unreachable and no name loses its static dispatch.
      class Fz
        def already = :already
      end
      Fz.freeze

      begin
        class Fz
          def x = :x
          def y = :y
        end
      rescue FrozenError => e
        p [e.class, e.message]
      end

      p Fz.frozen?
      p Fz.instance_methods(false).sort
      p Fz.method_defined?(:x)
      p Fz.new.respond_to?(:x)
      begin; Fz.new.x; rescue NoMethodError => e; p e.class; end
      # The body's earlier definition is untouched.
      p Fz.new.already

      # An UNFROZEN class reopens normally.
      class Ok
        def a = :a
      end
      class Ok
        def b = :b
      end
      p Ok.new.a
      p Ok.new.b
      p Ok.instance_methods(false).sort

      # A module reopen refuses the same way.
      module Mz
        def m = :m
      end
      Mz.freeze
      begin
        module Mz
          def n = :n
        end
      rescue FrozenError => e
        p [e.class, e.message]
      end
      p Mz.instance_methods(false)

      # A frozen class still answers every ordinary reflection.
      p Fz.name
      p Fz.superclass.to_s
      p Fz.new.class.to_s
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [FrozenError, "can't modify frozen Class: Fz"]
      true
      [:already]
      false
      false
      NoMethodError
      :already
      :a
      :b
      [:a, :b]
      [FrozenError, "can't modify frozen Module: Mz"]
      [:m]
      "Fz"
      "Object"
      "Fz"
    OUT
  end

  it "require gated extension constant is a name error without its require" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/require_gated_extension_constant_is_a_name_error_without_its_require.rb")
      # The ext require-gate: a require-gated builtin's constant
      # (`Base64`, gated by `"base64"`) is INVISIBLE until `require "base64"`
      # activates it -- referencing it un-required raises `NameError:
      # uninitialized constant Base64`, oracle-verified against ruby 4.0.6
      # (`uninitialized constant Base64 (NameError)`). The gate rides the
      # ordinary `resolve_class` -> unset-constant path, so it's a rescuable
      # RUNTIME NameError, not a compile error.

      puts Base64.strict_encode64("hi")
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "lang/exceptions/require_gated_extension_constant_is_a_name_error_without_its_require.rb:9:in '<main>': uninitialized constant Base64 (NameError)\n\nputs Base64.strict_encode64(\"hi\")\n     ^^^^^^\n"
    _(result.status).must_equal 1
  end

  it "require gated extension name error is rescuable" do
    _(ze0(<<~'RUBY').stdout).must_equal "rescued: uninitialized constant Base64\n"
      # Same gate, caught: since the miss surfaces through the runtime
      # constant path it's an ordinary rescuable `NameError` (oracle prints
      # `rescued: uninitialized constant Base64`). This program NEVER requires
      # base64, so activation stays off -- avoiding the documented
      # program-global-activation divergence (a `require` anywhere activates
      # the constant everywhere, unlike CRuby's file-ordered visibility).

      begin
        Base64.strict_encode64("hi")
      rescue NameError => e
        puts "rescued: #{e.message}"
      end
    RUBY
  end

  it "require that cannot resolve takes the rescue" do
    result = ze0(<<~'RUBY')
      # The i18n/excon shape: an optional accelerator behind `begin; require "x";
      # <definitions>; rescue LoadError; <fallback>`. The feature does not exist, so
      # ruby raises at the require and only the fallback ever runs.

      module Codec
        begin
          require "an_accelerator_that_is_not_installed"

          class Backend
            def self.name
              "native"
            end
          end
        rescue LoadError
          class Backend
            def self.name
              "pure ruby"
            end
          end
        end
      end

      puts Codec::Backend.name
      puts defined?(Codec::Backend)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      pure ruby
      constant
    OUT
  end

  it "reraise nested rescue" do
    result = ze0(<<~'RUBY')
      # A bare `raise` re-raises the exception its own rescue caught, even when the
      # rescue body ran another begin/rescue first. The saved class/message buffers
      # were shared across clauses, so the inner clause overwrote the outer one's
      # numbering and the re-raise named temporaries that were out of scope by then
      # -- the C build failed (#4052).

      def inner = raise(ArgumentError, "inner boom")

      def cleanup_that_raises
        yield
      rescue StandardError
        begin
          inner
        rescue StandardError => e
          puts "swallowed: #{e.class}: #{e.message}"
        end
        raise
      end

      begin
        cleanup_that_raises { raise "outer boom" }
      rescue StandardError => e
        puts "caught: #{e.class}: #{e.message}"
      end

      # the same with an ensure on the inner handler
      def cleanup_with_ensure
        yield
      rescue StandardError
        begin
          inner
        rescue StandardError
          nil
        ensure
          puts "ensured"
        end
        raise
      end

      begin
        cleanup_with_ensure { raise TypeError, "typed boom" }
      rescue StandardError => e
        puts "caught: #{e.class}: #{e.message}"
      end

      # two levels of nesting inside one rescue body
      def two_levels
        yield
      rescue StandardError
        begin
          begin
            inner
          rescue StandardError => e
            puts "inner: #{e.message}"
          end
          raise "middle boom"
        rescue StandardError => e
          puts "middle: #{e.message}"
        end
        raise
      end

      begin
        two_levels { raise "outermost boom" }
      rescue StandardError => e
        puts "caught: #{e.message}"
      end

      # a nested rescue in the body, then an explicit raise of a NEW exception
      def replaces
        yield
      rescue StandardError
        begin
          inner
        rescue StandardError
          nil
        end
        raise RuntimeError, "replacement"
      end

      begin
        replaces { raise "original" }
      rescue StandardError => e
        puts "caught: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      swallowed: ArgumentError: inner boom
      caught: RuntimeError: outer boom
      ensured
      caught: TypeError: typed boom
      inner: inner boom
      middle: middle boom
      caught: outermost boom
      caught: replacement
    OUT
  end

  it "rescue" do
    result = ze0(<<~'RUBY')
      # Test rescue/raise/ensure

      def safe_div(a, b)
        if b == 0
          raise "division by zero"
        end
        a / b
      end

      # Basic rescue
      begin
        result = safe_div(10, 2)
        puts result  # 5
      rescue
        puts "error"
      end

      # Rescue with exception
      begin
        result = safe_div(10, 0)
        puts result
      rescue => e
        puts e  # division by zero
      end

      # Ensure
      def with_ensure
        puts "start"
        raise "oops"
        puts "unreachable"
      rescue => e
        puts e  # oops
      ensure
        puts "cleanup"
      end
      with_ensure

      # Retry pattern
      attempts = 0
      begin
        attempts += 1
        raise "fail" if attempts < 3
        puts attempts  # 3
      rescue
        retry if attempts < 3
      end

      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      division by zero
      start
      oops
      cleanup
      3
      done
    OUT
  end

  it "rescue bind in lambda proc body" do
    result = ze0(<<~'RUBY')
      # `rescue => e` inside a lambda / proc body binds `e` as a body-local
      # exception. Before the fix the binding leaked to the enclosing scope so
      # the closure referenced an undeclared `lv_e`, and infer_type recomputed
      # `e.message` as int (a `#{e.message}` interp formatted the string
      # pointer with %lld). The string is observed inside the body so the test
      # is independent of the proc-call return-value ABI.
      lambda { begin; raise "a"; rescue => e; puts "got #{e.message}"; end }.call
      proc { begin; raise "boom"; rescue => e; puts "p #{e.message} (#{e.class})"; end }.call

      # Same construct, stored then called.
      f = lambda { begin; raise "late"; rescue => e; puts "f: #{e.message}"; end }
      f.call

      # A non-raising path through the body still compiles and runs.
      g = proc { begin; puts "no raise"; rescue => e; puts "unreached #{e.message}"; end }
      g.call
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      got a
      p boom (RuntimeError)
      f: late
      no raise
    OUT
  end

  it "rescue builtin module include" do
    result = ze0(<<~'RUBY')
      # `include IO::WaitReadable` -- a BUILTIN module named through its path -- was
      # dropped on the floor: the include recorder looked the name up in the class
      # table, found nothing (a builtin module has no user class), and skipped it
      # without a word. So `rescue IO::WaitReadable` fell through to the next arm
      # and `e.is_a?(IO::WaitReadable)` answered false, for an exception class that
      # said it included it.
      #
      # This is how a non-blocking read reports "would block" in CRuby:
      # OpenSSL::SSL::SSLErrorWaitReadable is a class including IO::WaitReadable,
      # not an SSLError extended at run time.
      module Plain
      end

      class ErrPlain < StandardError
        include Plain
      end

      class ErrWaitR < StandardError
        include IO::WaitReadable
      end

      class ErrWaitW < StandardError
        include IO::WaitWritable
      end

      # A user module already worked; the builtin one is what did not.
      begin
        raise ErrPlain, "a"
      rescue Plain => e
        puts "user module: #{e.class}"
      end

      begin
        raise ErrWaitR, "b"
      rescue IO::WaitReadable => e
        puts "builtin module: #{e.class}"
      rescue StandardError
        puts "WRONG: fell through"
      end

      # The two directions do not alias each other.
      begin
        raise ErrWaitW, "c"
      rescue IO::WaitReadable
        puts "WRONG arm"
      rescue IO::WaitWritable => e
        puts "other direction: #{e.class}"
      end

      p ErrWaitR.new("x").is_a?(IO::WaitReadable)
      p ErrWaitR.new("x").is_a?(IO::WaitWritable)
      p ErrWaitR.new("x").is_a?(StandardError)

      # An inherited include reaches the subclass too.
      class ErrChild < ErrWaitR
      end
      begin
        raise ErrChild, "d"
      rescue IO::WaitReadable => e
        puts "inherited: #{e.class}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      user module: ErrPlain
      builtin module: ErrWaitR
      other direction: ErrWaitW
      true
      false
      true
      inherited: ErrChild
    OUT
  end

  it "rescue exception class explicitly catches a script error" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught via Exception: script problem\n"
      begin
        raise ScriptError, "script problem"
      rescue Exception => e
        puts "caught via Exception: #{e.send(:message)}"
      end
    RUBY
  end

  it "rescue honors custom case eq" do
    result = ze0(<<~'RUBY')
      # `rescue M => e` matches via `===` (CRuby's rule) -- a matcher module that
      # OVERRIDES `self.===` decides for itself. rspec-support's
      # AllExceptionsExceptOnesWeMustNotRescue catches everything except
      # NoMemoryError/SignalException this way; an ancestry-only match let real
      # expectation failures escape Example#run.
      module CatchesRuntime
        def self.===(exception)
          RuntimeError === exception
        end
      end

      begin
        raise "boom"
      rescue CatchesRuntime => e
        puts "caught: #{e.message}"
      end

      begin
        raise TypeError, "nope"
      rescue CatchesRuntime => e
        puts "wrong: #{e.message}"
      rescue TypeError => e
        puts "type: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught: boom
      type: nope
    OUT
  end

  it "rescue matches an included module" do
    _(ze0(<<~'RUBY').stdout).must_equal "alertable: direct\n"
      module Alertable; end
      class AppError < StandardError
        include Alertable
      end
      begin
        raise AppError, "direct"
      rescue Alertable => e
        puts "alertable: #{e.message}"
      end
    RUBY
  end

  it "rescue modifier assign" do
    result = ze0(<<~'RUBY')
      # `expr rescue fallback` as an rvalue — verifies that
      # RescueModifierNode is wired into infer_type so the receiving
      # variable gets the unified type rather than the default int.
      #
      # Note: Ruby's `=` has higher precedence than the rescue modifier,
      # so `a = "x" rescue "y"` parses as `(a = "x") rescue "y"` — the
      # RescueModifierNode wraps the assignment, not the rvalue. To
      # actually exercise the RescueModifierNode-as-rvalue path through
      # infer_type, the rescue must be parenthesized as a sub-expression.

      # Same-type branches: string=string. Trivial baseline.
      a = ("ok" rescue "fallback")
      puts a

      # Mismatched branches: main is `raise` (returns int 0 from
      # compile_expr but never actually returns), fallback is string.
      # The fallback wins type inference; result type is string.
      b = (raise "boom" rescue "default")
      puts b

      # Same-type int. Endless method shape stays unchanged.
      def parse_int(s) = Integer(s) rescue 0
      puts parse_int("42")
      puts parse_int("abc")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ok
      default
      42
      0
    OUT
  end

  it "rescue module bare reader" do
    result = ze0(<<~'RUBY')
      # rescue-by-module matching (an exception matches a rescue arm naming a
      # module its class includes) and user readers on a bare-rescued exception.

      module Alertable; end
      module Ignorable; end

      class AppError < StandardError
        include Alertable
      end
      class SubAppError < AppError; end
      class PlainError < StandardError; end

      # direct include matches
      begin
        raise AppError, "direct"
      rescue Alertable => e
        puts "alertable: #{e.message}"
      end

      # subclass of an including class matches (module arrives via an ancestor)
      begin
        raise SubAppError, "inherited"
      rescue Alertable => e
        puts "alertable: #{e.message}"
      end

      # a class NOT including the module falls through to the next arm
      begin
        raise PlainError, "plain"
      rescue Ignorable
        puts "wrong arm"
      rescue StandardError => e
        puts "fell through: #{e.message}"
      end

      # module arm chained before a class arm picks the right one
      def classify(make_app)
        begin
          if make_app
            raise AppError, "app"
          else
            raise PlainError, "other"
          end
        rescue Alertable
          "matched module"
        rescue PlainError
          "matched class"
        end
      end
      puts classify(true)
      puts classify(false)

      # user reader on a bare-rescued exception
      class CodedError < StandardError
        attr_reader :code
        def initialize(c); @code = c; super("coded"); end
      end

      begin
        raise CodedError.new(42)
      rescue => err
        p err.code
        puts err.message
      end

      # bare rescue in a method body
      def risky(n)
        raise CodedError.new(n * 2)
      rescue => e
        e.code
      end
      p risky(21)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      alertable: direct
      alertable: inherited
      fell through: plain
      matched module
      matched class
      42
      coded
      42
    OUT
  end

  it "rescue namespaced exception" do
    result = ze0(<<~'RUBY')
      # A user exception raised under its qualified Ruby name ("App::Error") must be
      # matched by every arm shape: a namespaced arm (`rescue App::Error`, whose AST
      # name is the leaf), a leaf-referenced arm inside the module, a parent-class
      # arm catching a namespaced subclass (the hierarchy callback registers
      # qualified parents), and a builtin StandardError arm. Covers both the
      # class-fallback raise (sp_raise_cls) and the constructed-object raise.
      module App
        class Error < StandardError
        end

        class SubError < Error
        end

        def self.leafy
          raise Error, "leaf ref"
        rescue Error => e
          puts "leaf caught: #{e.message}"
        end
      end

      begin
        raise App::SubError, "sub raise"
      rescue App::Error => e
        puts "parent arm caught: #{e.message}"
      end

      App.leafy

      begin
        raise App::Error.new("explicit new")
      rescue StandardError => e
        puts "std caught: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      parent arm caught: sub raise
      leaf caught: leaf ref
      std caught: explicit new
    OUT
  end

  it "rescue naming an undefined constant compiles and never fires if no exception" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      # The `rescue` clause's class expression is only evaluated while matching
      # an actually-raised exception. A clause that never fires must not fail
      # the compile just because its class isn't defined.

      begin
        1 + 1
      rescue NeverDefined
        puts "caught"
      end
      puts "ok"
    RUBY
  end

  it "rescue naming an undefined constant raises name error when matched" do
    _(ze0(<<~'RUBY').stdout).must_equal "NameError: uninitialized constant NeverDefined\n"
      # When the body DOES raise, evaluating the undefined rescue constant is a
      # runtime NameError (which replaces the original exception) -- exactly
      # CRuby's behavior.

      begin
        begin
          raise "boom"
        rescue NeverDefined
          puts "caught"
        end
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY
  end

  it "rescue operand validation" do
    result = ze0(<<~'RUBY')
      r001 = (begin; begin; raise "x"; rescue 5; :matched; end; rescue TypeError => e001; e001.class.to_s; end); p r001
      empty002 = []
      r002 = (begin; begin; raise ArgumentError, "a"; rescue *empty002; :matched; end; rescue ArgumentError => e002; e002.message; end); p r002
      lst = [ArgumentError, TypeError]
      r1 = (begin; raise TypeError, "t"; rescue *lst => e; e.class.to_s; end); p r1
      r2 = (begin; raise "x"; rescue *lst; :m; rescue => e; e.class.to_s; end); p r2
      r3 = (begin; raise ArgumentError, "a"; rescue *[]; :m; rescue => e; e.message; end); p r3
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "TypeError"
      "a"
      "TypeError"
      "RuntimeError"
      "a"
    OUT
  end

  it "rescue return with ensure" do
    result = ze0(<<~'RUBY')
      # `return` / `next` from a rescue or else clause under `ensure` leaves the
      # handler stack intact for later rescues.
      def ret_from_rescue
        raise "x"
      rescue => e
        return "r:#{e.message}"
      ensure
        puts "ensure ran"
      end

      def ret_from_else
        1
      rescue
        return "rescued"
      else
        return "else"
      ensure
        puts "ensure ran"
      end

      def next_from_rescue(xs)
        out = []
        xs.each do |x|
          begin
            raise "odd" if x.odd?
            out << x
          rescue
            next
          ensure
            out << -x
          end
        end
        out
      end

      def nested_ret
        begin
          raise "inner"
        rescue
          return "inner-rescue"
        ensure
          puts "inner ensure"
        end
      ensure
        puts "outer ensure"
      end

      p ret_from_rescue
      p ret_from_else
      p next_from_rescue([1, 2, 3])
      p nested_ret

      # every later rescue must still catch
      begin
        raise "boom"
      rescue => e
        p e.message
      end
      p((Integer("zz") rescue -1))
      x = (raise "mod" rescue "modifier")
      p x
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ensure ran
      "r:x"
      ensure ran
      "else"
      [-1, 2, -2, -3]
      inner ensure
      outer ensure
      "inner-rescue"
      "boom"
      -1
      "modifier"
    OUT
  end

  it "rescue undefined constant" do
    result = ze0(<<~'RUBY')
      # A `rescue` clause naming an undefined constant compiles cleanly: CRuby only
      # evaluates the clause's class while matching an actually-raised exception.

      # Never fires -> the undefined name is never evaluated.
      begin
        1 + 1
      rescue NeverDefined
        puts "unreachable"
      end
      puts "no exception: ok"

      # Fires -> evaluating the undefined constant is a runtime NameError, which
      # replaces the original exception.
      begin
        begin
          raise "boom"
        rescue NeverDefined
          puts "unreachable"
        end
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      no exception: ok
      NameError: uninitialized constant NeverDefined
    OUT
  end

  it "rescue value empty container" do
    result = ze0(<<~'RUBY')
      # An empty container's type reads UNKNOWN for want of an element type, which is
      # not the same as producing no value. Wherever a rescue-bearing expression asks
      # "does this arm carry a value?", the two were conflated: the modifier form
      # built the array and threw it away (`x = ([] rescue 0)` assigned nil), and the
      # begin/rescue form took the other arm's type alone and put a container pointer
      # in an mrb_int slot (#3495, #3496). Both arms of both forms are covered here.
      a = ([] rescue 0)
      p a
      p a.class
      p ({} rescue 0)
      p (Array.new rescue 0)
      p (Hash.new rescue 0)
      p ([1] rescue 0)
      p (raise("x") rescue 0)

      # the value is a real container, not just something that prints like one
      b = ([] rescue 0)
      b << 1 if b.is_a?(Array)
      p b

      c = begin
        []
      rescue
        0
      end
      p c

      d = begin
        {}
      rescue
        0
      end
      p d

      # the empty container on the HANDLER side
      e = begin
        raise "e"
      rescue
        []
      end
      p e

      f = begin
        Integer("z")
      rescue ArgumentError
        {}
      end
      p f

      # both arms empty
      g = begin
        []
      rescue
        []
      end
      p g

      # a non-empty body still behaves
      h = begin
        [1, 2]
      rescue
        0
      end
      p h
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      []
      Array
      {}
      []
      {}
      [1]
      0
      [1]
      []
      {}
      []
      {}
      []
      [1, 2]
    OUT
  end

  it "rescue var subclass method" do
    result = ze0(<<~'RUBY')
      # A rescue arm binds its variable to the named exception subclass when that
      # class has state or behaviour of its own. Only ivars counted, so a subclass
      # whose body is a method was typed as the plain exception and the method could
      # not be called. A two-level chain missed on top of that: the parent links are
      # not resolved yet at that point, so the walk stopped at the subclass.
      class AErr < StandardError; end

      class BErr < AErr
        def code; 7; end
      end

      begin
        raise BErr
      rescue BErr => eb
        p eb.code
      end

      class CErr < StandardError
        def code; 9; end
        def label; "c"; end
      end

      begin
        raise CErr, "boom"
      rescue CErr => ec
        p ec.code
        p ec.label
        p ec.message
        p ec.class
      end

      # a subclass carrying ivars still specializes
      class DErr < StandardError
        def initialize(m, n)
          super(m)
          @n = n
        end
        def n; @n; end
      end

      begin
        raise DErr.new("m", 3)
      rescue DErr => ed
        p ed.n
        p ed.message
      end

      # a plain subclass keeps the exception face
      class EErr < StandardError; end
      begin
        raise EErr, "plain"
      rescue EErr => ee
        p ee.message
        p ee.class
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      7
      9
      "c"
      "boom"
      CErr
      3
      "m"
      "plain"
      EErr
    OUT
  end

  it "rescue walks class hierarchy" do
    result = ze0(<<~'RUBY')
      # `rescue ParentClass => e` should catch a raised subclass
      # instance, and `e.is_a?(AncestorClass)` should walk the class
      # hierarchy. Pre-fix sp_exc_is_a only strcmp'd the class name,
      # so a `raise C` where `C < B < A < StandardError` slipped past
      # every `rescue B` / `rescue A` / `rescue StandardError` rescue
      # arm, and `e.is_a?(X)` always returned false for any X.
      # Issue #627.

      class A < StandardError; end
      class B < A; end
      class C < B; end

      # `rescue B` catches a raised C
      begin
        raise C, "boom"
      rescue B => e
        puts "caught B: " + e.message
      end

      # is_a? walks the chain
      begin
        raise C, "x"
      rescue => e
        puts "is_a A? " + (e.is_a?(A) ? "yes" : "no")
        puts "is_a B? " + (e.is_a?(B) ? "yes" : "no")
        puts "is_a C? " + (e.is_a?(C) ? "yes" : "no")
        puts "is_a StandardError? " + (e.is_a?(StandardError) ? "yes" : "no")
        puts "is_a String? " + (e.is_a?(String) ? "yes" : "no")
      end

      # Standard library exception hierarchy: ArgumentError < StandardError.
      # `rescue StandardError` should catch ArgumentError.
      begin
        raise ArgumentError, "bad"
      rescue StandardError => e
        puts "caught StandardError via ArgumentError: " + e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      caught B: boom
      is_a A? yes
      is_a B? yes
      is_a C? yes
      is_a StandardError? yes
      is_a String? no
      caught StandardError via ArgumentError: bad
    OUT
  end

  it "rescue widens nil local to exception" do
    _(ze0(<<~'RUBY').stdout).must_equal "#<NotImplementedError: boom>\n"
      def f
        raised = nil
        begin
          raise NotImplementedError, "boom"
        rescue NotImplementedError => e
          raised = e
        end
        raised
      end

      puts f.inspect
    RUBY
  end

  it "rescue with a computed exception class expression" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught MyErr: boom\n"
      # A rescue-list entry that is a COMPUTED expression (not a bare constant or
      # splat) is evaluated and matched at runtime -- net/http's `rescue
      # defined?(OpenSSL::SSL) ? OpenSSL::SSL::SSLError : IOError`.

      class MyErr < StandardError; end
      def go
        raise MyErr, "boom"
      rescue IOError, (defined?(Nope) ? Nope : MyErr) => e
        "caught #{e.class}: #{e.send(:message)}"
      end
      puts go
    RUBY
  end

  it "rescue with a splatted exception list" do
    result = ze0(<<~'RUBY')
      ERRS = [ArgumentError, TypeError]

      # A constant array of classes.
      begin
        raise TypeError, "t"
      rescue *ERRS => e
        puts "const #{e.class}"
      end

      # A local array; no `=> e` capture.
      errs = [KeyError]
      begin
        raise KeyError, "k"
      rescue *errs
        puts "local no-capture"
      end

      # Static class mixed with a splat, in either order.
      extra = [TypeError]
      begin; raise TypeError, "t"; rescue ArgumentError, *extra => e; puts "mixed1 #{e.class}"; end
      lead = [KeyError]
      begin; raise TypeError, "t"; rescue *lead, TypeError => e; puts "mixed2 #{e.class}"; end

      # Splatting a single class (not an array) wraps it: `*one` == `[one]`.
      one = RuntimeError
      begin; raise "r"; rescue *one => e; puts "single #{e.class}"; end

      # An empty array catches nothing -> propagates.
      empty = []
      begin
        begin; raise TypeError, "t"; rescue *empty; puts "wrong"; end
      rescue TypeError
        puts "empty catches nothing"
      end

      # A non-matching splat re-raises to an outer handler.
      only_arg = [ArgumentError]
      begin
        begin; raise TypeError, "t"; rescue *only_arg; puts "wrong"; end
      rescue TypeError => e2
        puts "propagated #{e2.class}"
      end

      # ensure still runs; $! is the caught exception; module-include matches.
      module Alertable; end
      class Alarmed < StandardError; include Alertable; end
      mods = [Alertable]
      begin
        raise Alarmed, "a"
      rescue *mods
        puts "module-match #{$!.class}"
      ensure
        puts "ensure ran"
      end

      # Splat rescue as a method-body clause, with retry.
      E = [RuntimeError]
      def flaky
        @n = (@n || 0) + 1
        raise "x" if @n < 2
        "ok n=#{@n}"
      rescue *E
        retry if @n < 2
      end
      puts flaky
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      const TypeError
      local no-capture
      mixed1 TypeError
      mixed2 TypeError
      single RuntimeError
      empty catches nothing
      propagated TypeError
      module-match Alarmed
      ensure ran
      ok n=2
    OUT
  end

  it "rescue with multiple classes in one clause" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught one of: wrong type\n"
      begin
        raise TypeError, "wrong type"
      rescue ArgumentError, TypeError => e
        puts "caught one of: #{e.send(:message)}"
      end
    RUBY
  end

  it "rescued missing constant quiet" do
    result = ze0(<<~'RUBY')
      # Referencing a constant the program never defines, on purpose, behind a rescue
      # that catches the NameError is how a program probes for one -- ruby/spec does
      # exactly this. CRuby says nothing about it at any stage, and spinel's
      # defined-nowhere warning reported a program whose behaviour was already right
      # (#4062). The warning is for a reference nothing catches, and still fires there.
      p(begin; NoSuchConstA; rescue NameError => e; e.class.to_s; end)

      r = begin
        NoSuchConstB
      rescue => e
        e.class.to_s
      end
      p r

      c = (NoSuchConstC rescue "caught")
      p c

      def probe
        NoSuchConstD
      rescue NameError
        "rescued in a method"
      end
      p probe

      # a nested rescue whose OUTER clause is the one that catches it
      p(begin
          begin
            NoSuchConstE
          rescue TypeError
            "wrong one"
          end
        rescue NameError
          "outer caught it"
        end)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "NameError"
      "NameError"
      "caught"
      "rescued in a method"
      "outer caught it"
    OUT
  end

  it "rescued require load error" do
    result = ze0(<<~'RUBY', files: {"rescued_require_load_error/probe.rb" => "# The power_assert shape: a load-time probe that raises LoadError before any\n# definitions, so the file contributes nothing when the probe fails.\nraise LoadError, \"probe says no\"\nGOOD = 1\n"})
      # A require inside `begin ... rescue LoadError` whose FILE RESOLVES but whose
      # top level RAISES LoadError when it runs -- power_assert's TracePoint probe,
      # which test-unit requires exactly this way and degrades by rescuing. The
      # spliced statements sit inside a synthesized begin carrying the written
      # rescue clauses, so the raise lands in the handler CRuby's require timing
      # would give it, and execution continues after the begin.
      begin
        require_relative "rescued_require_load_error/probe"
      rescue LoadError => e
        p e.message
      end
      p :after
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "probe says no"
      :after
    OUT
  end

  it "rescuing a middle class catches a raised leaf subclass" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught as AppError: bad input\n"
      class AppError < StandardError
      end
      class ValidationError < AppError
      end

      begin
        raise ValidationError, "bad input"
      rescue AppError => e
        puts "caught as AppError: #{e.send(:message)}"
      end
    RUBY
  end

  it "retry and ensure combined inside an enclosing while loop" do
    _(ze0(<<~'RUBY').stdout).must_equal "2\n"
      # The `begin`'s own `retry` restarts just its OWN body (not the `while`
      # loop), and `ensure` runs once per `while` ITERATION (twice total,
      # once per `i`) -- not once per `retry` attempt within an iteration.

      total_ensure = 0
      i = 0
      while i < 2
        attempts = 0
        begin
          attempts += 1
          raise "x" if attempts < 2
        rescue
          retry if attempts < 2
        ensure
          total_ensure += 1
        end
        i += 1
      end
      puts total_ensure
    RUBY
  end

  it "retry loop runs ensure exactly once not per attempt" do
    result = ze0(<<~'RUBY')
      class Attempt
        def initialize
          @attempts = 0
        end
        def run
          begin
            @attempts += 1
            raise "fail" if @attempts < 3
            puts "succeeded after #{@attempts} attempts"
          rescue
            retry if @attempts < 3
          ensure
            puts "ensure ran, attempts=#{@attempts}"
          end
        end
      end
      Attempt.new.run
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      succeeded after 3 attempts
      ensure ran, attempts=3
    OUT
  end

  it "return from a rescue body still runs ensure exactly once" do
    result = ze0(<<~'RUBY')
      class ReturnTester
        def m
          begin
            raise "x"
          rescue
            return "returned"
          ensure
            puts "ensure ran before return"
          end
        end
      end
      puts ReturnTester.new.m
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ensure ran before return
      returned
    OUT
  end

  it "return from ensure overrides return from the begin body" do
    _(ze0(<<~'RUBY').stdout).must_equal "from ensure\n"
      # Real, tricky Ruby semantic: a `return` inside `ensure` wins over a
      # `return` already in flight from `begin`'s own body -- not just "ensure
      # runs afterward", it actually REPLACES the method's return value.
      # Falls out for free here: `ensure`'s own statements lower inline,
      # so a `return` inside it
      # exits the enclosing method directly, superseding the return value
      # already in flight.

      class M
        def m
          begin
            return "from begin"
          ensure
            return "from ensure"
          end
        end
      end
      puts M.new.m
    RUBY
  end

  it "runtime exception subclass" do
    result = ze0(<<~'RUBY')
      # A class MINTED at runtime from an exception root is an exception like any
      # other: `.new` builds the native instance every inherited `Exception` method
      # reads, `raise` accepts it in all three of its shapes, and a `rescue` clause
      # matches it by ancestry.
      R = Class.new(StandardError)
      p R.ancestors.first(3)
      p R.new("hi").message
      p R.new.message
      p R.superclass

      # A body: an override, an addition, and a custom `initialize` that calls super.
      Coded = Class.new(StandardError) do
        attr_reader :code
        def initialize(code)
          @code = code
          super("code #{code}")
        end
        def to_s = "<#{@code}>"
      end
      e = Coded.new(42)
      p [e.code, e.message, e.to_s]

      # Deeper than one level, and off a root other than StandardError.
      Sub = Class.new(Coded)
      p Sub.new(7).message
      p Sub.ancestors.include?(StandardError)
      p Class.new(ArgumentError).new("a").is_a?(ArgumentError)
      p Class.new(Exception).new("x").is_a?(StandardError)

      def caught
        yield
      rescue => e
        [e.class.name, e.message]
      end
      p(caught { raise R })
      p(caught { raise R, "with message" })
      p(caught { raise R.new("prebuilt") })

      # Matching: by an ancestor, and by a sibling that misses.
      begin
        raise Sub, 3
      rescue Coded => e
        p [:by_parent, e.message, e.class == Sub]
      end

      begin
        begin
          raise R, "inner"
        rescue Coded
          p :wrong
        end
      rescue R => e
        p [:not_matched_by_sibling, e.message]
      end

      # An anonymous one carries the same surface.
      anon = Class.new(RuntimeError).new("nameless")
      p anon.class.ancestors.include?(RuntimeError)
      p anon.message
      p anon.backtrace

      err = R.new("surface")
      err.set_backtrace(["a.rb:1"])
      p err.backtrace
      p err.full_message(highlight: false, order: :top).lines.first.chomp
      p [err.cause, err.frozen?]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [R, StandardError, Exception]
      "hi"
      "R"
      StandardError
      [42, "<42>", "<42>"]
      "<7>"
      true
      true
      false
      ["R", "R"]
      ["R", "with message"]
      ["R", "prebuilt"]
      [:by_parent, "<3>", true]
      [:not_matched_by_sibling, "inner"]
      true
      "nameless"
      nil
      ["a.rb:1"]
      "a.rb:1: surface (R)"
      [nil, false]
    OUT
  end

  it "runtime raise not compile error" do
    result = ze0(<<~'RUBY')
      # Cases where a compiler is tempted to reject at build time but real Ruby
      # raises at RUNTIME -- so the program must compile, run, and let a `rescue`
      # see the error. Codegen lowers every branch eagerly, so rejecting any of
      # these statically would kill an otherwise-correct program.

      def err
        yield
      rescue => e
        "#{e.class}: #{e.message}"
      end

      # 1. public_send is stricter than an explicit-receiver call: it rejects BOTH
      #    private and protected, with no self-relatedness relaxation.
      class Acct
        def balance = 100
        def peer_check(other) = other.guarded

        protected

        def guarded = "prot"

        private

        def secret = 42
      end

      a = Acct.new
      p a.public_send(:balance)
      puts err { a.public_send(:secret) }
      puts err { a.public_send(:guarded) }

      # send / __send__ stay visibility-blind
      p a.send(:secret)
      p a.__send__(:secret)

      # ...while a protected method IS callable when the caller's self is related.
      p a.peer_check(Acct.new)

      # A runtime-computed method name is checked per resolved arm.
      def dyn(o, m) = o.public_send(m)
      p dyn(a, :balance)
      puts err { dyn(a, :secret) }

      # 2. A blockless Thread.new / Fiber.new raises rather than failing to compile.
      puts err { Thread.new }
      puts err { Fiber.new }

      # 3. A non-finite float literal is a perfectly good value, not a codegen
      #    failure -- it just cannot be spelled as a float literal.
      big = 1e400
      p big
      p(-1e400)
      p big.infinite?
      p (big - big).nan?

      # 4. `for` performs no type dispatch in Ruby: it is just `each` with a block,
      #    so any object answering #each iterates.
      class Nums
        include Enumerable
        def initialize(*xs) = @xs = xs
        def each; @xs.each { |x| yield x }; end
      end

      total = 0
      for x in Nums.new(1, 2, 3, 4)
        total += x
      end
      p total

      # multi-assignment `for` over a pair-yielding each
      class Pairs
        include Enumerable
        def each; yield [1, :a]; yield [2, :b]; end
      end

      pairs = []
      for k, v in Pairs.new
        pairs << "#{k}:#{v}"
      end
      p pairs

      # `for` does NOT introduce a new scope: the variable survives the loop.
      for survivor in [10, 20, 30]
      end
      p survivor

      # an object with no #each fails at runtime, not at compile time
      puts err { for z in 5; end }

      # 5. Guards against loops that would otherwise never terminate.
      #
      # NOTE: `"x" * (1 << 60)` is deliberately NOT exercised here. CRuby's guard
      # only covers the length multiplication, so a 1-byte string times 2^60 reaches
      # the allocator and raises NoMemoryError -- which, not being a StandardError,
      # escapes `rescue => e` and kills the program. zeo caps the total size and
      # raises a catchable ArgumentError instead, so the two cannot share a golden
      # file; the corpus `string_multiply_overflow` pins that behavior separately.
      puts err { "x" * -1 }
      p "ab" * 3
      puts err { 1.step(10, 0) { } }
      puts err { Rational(1, 2).step(Rational(5, 2), 0) { } }
      puts err { (1..).to_a }
      p (1..4).to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      100
      NoMethodError: private method 'secret' called for an instance of Acct
      NoMethodError: protected method 'guarded' called for an instance of Acct
      42
      42
      "prot"
      100
      NoMethodError: private method 'secret' called for an instance of Acct
      ThreadError: must be called with a block
      ArgumentError: tried to create Proc object without a block
      Infinity
      -Infinity
      1
      true
      10
      ["1:a", "2:b"]
      30
      NoMethodError: undefined method 'each' for an instance of Integer
      ArgumentError: negative argument
      "ababab"
      ArgumentError: step can't be 0
      ArgumentError: step can't be 0
      RangeError: cannot convert endless range to an array
      [1, 2, 3, 4]
    OUT
  end

  it "singleton body begin rescue and self value" do
    result = ze0(<<~'RUBY')
      # securerandom picks its implementation with a `begin/rescue` inside `class <<
      # self`, aliasing whichever one works; and `class << self; self; end` is the
      # classic idiom whose VALUE is the singleton class.

      module Source
        class << self
          def from_device
            "device"
          end

          def from_fallback
            "fallback"
          end

          begin
            raise RuntimeError, "no device here"
            alias generate from_device
          rescue RuntimeError
            alias generate from_fallback
          end
        end

        SINGLETON = class << self
          self
        end
      end

      puts Source.generate
      puts Source::SINGLETON == Source.singleton_class
      puts Source::SINGLETON.instance_method(:generate).owner == Source.singleton_class
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      fallback
      true
      true
    OUT
  end

  it "super with no definition above raises at runtime" do
    _(ze0(<<~'RUBY').stdout).must_equal "super: no superclass method 'as_json' for an instance of Rec\n"
      # Real Ruby has no definition-time check for `super`: it resolves against
      # the receiver's live ancestry at CALL time and raises NoMethodError only
      # if that walk comes up empty (vm_search_super_method / vm_eval.c). So a
      # `super` with nothing above it must compile, and the raise must be
      # rescuable -- rejecting it at compile time would kill this whole program.

      class Rec
        def as_json
          h = super
          h[:x] = 1
          h
        end
      end
      begin
        Rec.new.as_json
      rescue NoMethodError => e
        puts e.message
      end
    RUBY
  end

  it "the core exception tree is nameable and rescuable" do
    result = ze0(<<~'RUBY')
      # The `Exception`-direct classes (uncaught by a bare `rescue`) and the
      # refined `StandardError`-branch classes all register with the right
      # superclass and can be raised/rescued by name.

      p SystemExit.superclass
      p Interrupt.superclass
      p NoMemoryError.superclass
      p NoMatchingPatternKeyError.superclass
      p Regexp::TimeoutError.superclass
      p IO::TimeoutError.superclass
      begin
        raise SecurityError, "denied"
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Exception
      SignalException
      Exception
      NoMatchingPatternError
      RegexpError
      IOError
      SecurityError: denied
    OUT
  end

  it "the name validation family" do
    _(ze0(<<~'RUBY').stdout).must_equal "NameError: '@@bad' is not allowed as an instance variable name\nNameError: '@1x' is not allowed as an instance variable name\nNameError: '@' is not allowed as an instance variable name\nNameError: 'x' is not allowed as an instance variable name\nNameError: '@@bad' is not allowed as an instance variable name\nNameError: '@@bad' is not allowed as an instance variable name\n1\n1\n2\n2\n[:@ok, :@日本]\nNameError: wrong constant name lower\nNameError: wrong constant name A::B\nNameError: wrong constant name \nNameError: wrong constant name 1A\n1\nNameError: wrong constant name lower\nNameError: constant #<Module:0xN>::Nope not defined\nComparable\nNameError: invalid attribute name '1bad'\nNameError: invalid attribute name 'x?'\nNameError: invalid attribute name 'x!'\nTypeError: 1 is not a symbol nor a string\n[:ok, :ok=]\nNameError: invalid attribute name '1bad'\nFrozenError: can't modify frozen Class: #<Class:0xN>\nTypeError: wrong argument type Class (expected Module)\nTypeError: wrong argument type Integer (expected Module)\nTypeError: wrong argument type Class (expected Module)\nTypeError: wrong argument type Class (expected Module)\nArgumentError: cyclic include detected\nArgumentError: cyclic include detected\nfalse\nTypeError: wrong argument type Class (expected Module)\nFrozenError: can't modify frozen Class: #<Class:0xN>\nTypeError: superclass must be an instance of Class (given an instance of Module)\nTypeError: superclass must be an instance of Class (given an instance of Integer)\nTypeError: can't make subclass of Class\nTypeError: can't make subclass of singleton class\ntrue\ntrue\n\"hi\"\n"
      # The reflection surface validates the NAMES it is given, through one
      # shared set of predicates rather than sixteen separate remembered checks.
      #
      # The five promoted gaps beside this file each cover one row. This covers
      # the RULES, which is where the next miss would come from -- and three of
      # them are surprising enough to be worth pinning:
      #
      #   * an identifier takes no trailing `?`/`!`/`=` (`attr_accessor :x?` is
      #     refused), while non-ASCII letters ARE identifier characters;
      #   * a constant is a SINGLE segment for `const_set` and a PATH for
      #     `const_get`, so `const_set("A::B")` is a wrong-name error rather than
      #     a nested write;
      #   * the NAME is checked before FROZEN, and per ARGUMENT rather than once
      #     up front, both of which are observable.

      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message.sub(/0x[0-9a-f]+/, "0xN")}"
      end

      # --- Instance-variable names ----------------------------------------------
      o = Object.new
      show { o.instance_variable_get("@@bad") }
      show { o.instance_variable_get("@1x") }
      show { o.instance_variable_get("@") }
      show { o.instance_variable_get("x") }
      show { o.instance_variable_set("@@bad", 1) }
      show { o.instance_variable_defined?("@@bad") }
      # Valid, including a non-ASCII name.
      show { o.instance_variable_set(:@ok, 1) }
      show { o.instance_variable_get(:@ok) }
      show { o.instance_variable_set(:@日本, 2) }
      show { o.instance_variable_get(:@日本) }
      show { o.instance_variables }

      # --- Constant names -------------------------------------------------------
      show { Module.new.const_set(:lower, 1) }
      show { Module.new.const_set("A::B", 1) }
      show { Module.new.const_set("", 1) }
      show { Module.new.const_set("1A", 1) }
      show { Module.new.const_set(:Ok, 1) }
      show { Module.new.const_get(:lower) }
      show { Module.new.send(:remove_const, :Nope) }
      # `const_get` takes a PATH where `const_set` takes a segment.
      show { Object.const_get("Comparable") }

      # --- Attribute names ------------------------------------------------------
      show { Class.new { attr_accessor :"1bad" } }
      show { Class.new { attr_accessor :"x?" } }
      show { Class.new { attr_accessor :"x!" } }
      show { Class.new { attr_accessor 1 } }
      # The name is checked per ARGUMENT: `:ok` is defined, and then it raises.
      show do
        c = Class.new
        begin
          c.send(:attr_accessor, :ok, :"1bad")
        rescue NameError
          nil
        end
        c.instance_methods(false).sort
      end
      # A frozen class given a BAD name says NameError, not FrozenError.
      show { Class.new.freeze.send(:attr_accessor, :"1bad") }
      show { Class.new.freeze.send(:attr_accessor, :ok) }

      # --- Module arguments -----------------------------------------------------
      show { Class.new { include String } }
      show { Class.new { include 1 } }
      show { Class.new { prepend String } }
      show { Object.new.extend(String) }
      show do
        m = Module.new
        m.send(:include, m)
      end
      show do
        m = Module.new
        n = Module.new { include m }
        m.send(:include, n)
      end
      # Every argument is validated BEFORE any is spliced.
      show do
        c = Class.new
        begin
          c.send(:include, Comparable, String)
        rescue TypeError
          nil
        end
        c.ancestors.include?(Comparable)
      end
      # Frozen sits between the type check and the cycle check.
      show { Class.new.freeze.send(:include, String) }
      show { Class.new.freeze.send(:include, Comparable) }

      # --- Superclasses ---------------------------------------------------------
      show { Class.new(Comparable) }
      show { Class.new(1) }
      show { Class.new(Class) }
      show { Class.new(Object.new.singleton_class) }
      # LEGAL, and both used to be conflated with the refusals: `Module` is a
      # Class, it is just not a module instance.
      show { Class.new(Module).ancestors.include?(Module) }
      show { Class.new(BasicObject).ancestors.include?(BasicObject) }
      show { Class.new(String).new("hi") }
    RUBY
  end

  it "the shareable predicate is deep" do
    result = ze0(<<~'RUBY')
      # A frozen container holding an UNFROZEN element is not shareable --
      # CRuby's frozen-and-everything-reachable-shareable rule.

      arr = ["mut"]
      arr.freeze
      puts Ractor.shareable?(arr)
      Ractor.make_shareable(arr)
      puts Ractor.shareable?(arr)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      true
    OUT
  end

  it "three rescue clauses skips non matching ones in order" do
    _(ze0(<<~'RUBY').stdout).must_equal "range: oops\n"
      begin
        raise RangeError, "oops"
      rescue ArgumentError
        puts "arg"
      rescue TypeError
        puts "type"
      rescue RangeError => e
        puts "range: #{e.send(:message)}"
      end
    RUBY
  end

  it "times loop containing begin rescue with no crossing control flow still works" do
    result = ze0(<<~'RUBY')
      # A native loop CONTAINING a `begin`/`rescue` (as opposed to a `begin`
      # containing a bare `break`/`next` TARGETING an outer loop, the
      # rejected shape) is completely unaffected -- the `.times` loop's own
      # control flow doesn't cross the begin/rescue closure boundary at all
      # here, so it just runs normally, once per iteration.

      3.times do |i|
        begin
          raise "x" if i == 1
          puts "ok #{i}"
        rescue
          puts "rescued #{i}"
        end
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ok 0
      rescued 1
      ok 2
    OUT
  end

  it "top level def recursion and mutual calls" do
    _(ze0(<<~'RUBY').stdout).must_equal "fib(10) = 55\n"
      def fib(n)
        n < 2 ? n : fib(n - 1) + fib(n - 2)
      end
      def announce(n)
        puts "fib(#{n}) = #{fib(n)}"
      end
      announce(10)
    RUBY
  end

  it "toplevel return from rescue" do
    result = ze0(<<~'RUBY')
      # `return` written at the top level ends the program. Zeo used to fold only
      # the plain statement form; from a position that RAISES the signal instead of
      # returning literally -- inside a `rescue` clause, an `ensure`, a `begin/end
      # while` -- it escaped every frame and the program died with "uncaught signal
      # escaped the top level". The exit status is 0 and `at_exit` still runs, both
      # of which say this is an ordinary end and not an error.
      at_exit { puts "at_exit ran" }

      puts "start"

      begin
        raise "boom"
      rescue RuntimeError => e
        puts "rescued #{e.message}"
        return
      end

      puts "never printed"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      start
      rescued boom
      at_exit ran
    OUT
  end

  it "transform keys combined cmp wave10" do
    result = ze0(<<~'RUBY')
      # transform_keys with a mapping AND a fallback block, and Comparable
      # operators over a nil-capable user <=> (incomparable raises).
      h = { a: 1, b: 2, c: 3 }
      p h.transform_keys({ a: :x })
      p h.transform_keys({ a: :x }) { |k| k.to_s }
      g = { a: 1 }
      p g.transform_keys { |k| k.to_s }
      class V124
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o)
          return nil unless o.is_a?(V124)
          n <=> o.n
        end
      end
      a = V124.new(1); b = V124.new(2)
      p(a < b)
      p(a > b)
      p(a.between?(a, b))
      r = (begin; a < 5; rescue ArgumentError; "AE"; end); p r
      p(a.clamp(a, b).n)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      {x: 1, b: 2, c: 3}
      {x: 1, "b" => 2, "c" => 3}
      {"a" => 1}
      true
      false
      true
      "AE"
      1
    OUT
  end

  it "uncaught exception message" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/uncaught_exception_message.rb")
      # An uncaught exception's tail format. In a --debug build the raising frame and
      # its callers are printed in front of it (#3974); an ordinary build has no frame
      # symbols, so the message alone is what it says.
      def boom(v)
        v.length
      end

      begin
        boom(nil)
      rescue NoMethodError => e
        p e.message
      end

      p "before"
      boom(nil)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "undefined method 'length' for nil"
      "before"
    OUT
    _(result.stderr).must_equal "lang/exceptions/uncaught_exception_message.rb:5:in 'Object#boom': undefined method 'length' for nil (NoMethodError)\n\n  v.length\n   ^^^^^^^\n\tfrom lang/exceptions/uncaught_exception_message.rb:15:in '<main>'\n"
    _(result.status).must_equal 1
  end

  it "uncaught exception report matches cruby shape" do
    result = ze0(<<~'RUBY', path: "lang/exceptions/uncaught_exception_report_matches_cruby_shape.rb")
      # The top-level report: innermost frame heads the message line, outer
      # frames follow tab-indented -- verbatim ruby 4.0.6 (as `-e`).

      def inner; raise "boom"; end
      def outer; inner; end
      outer
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "lang/exceptions/uncaught_exception_report_matches_cruby_shape.rb:4:in 'Object#inner': boom (RuntimeError)\n\tfrom lang/exceptions/uncaught_exception_report_matches_cruby_shape.rb:5:in 'Object#outer'\n\tfrom lang/exceptions/uncaught_exception_report_matches_cruby_shape.rb:6:in '<main>'\n"
    _(result.status).must_equal 1
  end

  it "undef method raises" do
    result = ze0(<<~'RUBY')
      # Issue #717. `undef <m>` removes the method from the class's
      # dispatch table AND a subsequent call to it raises NoMethodError
      # (matching CRuby). spinel previously recorded the undef but the
      # slot stayed callable.

      class C
        def meth; "method"; end
        undef meth
      end

      begin
        puts C.new.meth
      rescue NoMethodError
        puts "NoMethodError"
      end

      # Inheritance: child class's `undef <parent_method>` shadows the
      # parent. Calling on a Child instance must still raise; calling on
      # a parent instance still works.
      class P
        def hello; "hi"; end
      end

      class Child < P
        undef hello
      end

      begin
        puts Child.new.hello
      rescue NoMethodError
        puts "Child NoMethodError"
      end

      puts P.new.hello
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NoMethodError
      Child NoMethodError
      hi
    OUT
  end

  it "undefined constant deferred raise" do
    result = ze0(<<~'RUBY')
      # An undefined constant used in class position raises a runtime NameError,
      # never a compile-time failure -- shown across a pattern, a scoped constant
      # write, and `raise Const, msg`.

      x = 5
      begin
        case x
        in NopeClass then puts "unreachable"
        else puts "unreachable"
        end
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      # The scope is resolved BEFORE the RHS runs, so "rhs" never prints.
      begin
        Nope::X = (puts "rhs"; 5)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        raise Nope, "msg"
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NameError: uninitialized constant NopeClass
      NameError: uninitialized constant Nope
      NameError: uninitialized constant Nope
    OUT
  end

  it "uninit const raises nameerror" do
    result = ze0(<<~'RUBY')
      # Uninitialised constant reads raise NameError instead of
      # silently returning 0.

      begin
        puts NONEXISTENT_CONST
      rescue NameError
        puts "uninit raised"
      end

      # Self-referential init `X = X + 1` reads X before X is bound;
      # CRuby raises NameError. Spinel previously evaluated X as 0
      # and assigned 1.
      begin
        X = X + 1
        puts X
      rescue NameError
        puts "self-ref raised"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      uninit raised
      self-ref raised
    OUT
  end

  it "unmatched rescue class propagates to an outer rescue" do
    _(ze0(<<~'RUBY').stdout).must_equal "outer caught: inner\n"
      begin
        begin
          raise TypeError, "inner"
        rescue ArgumentError
          puts "wrong handler"
        end
      rescue TypeError => e
        puts "outer caught: #{e.send(:message)}"
      end
    RUBY
  end

  it "unrescued raise propagates through multiple method call frames" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught from deep: deep failure\n"
      # Three separate objects (not sibling methods on one class) --
      # implicit-self calls to a sibling method aren't supported yet
      # (a separate, pre-existing, documented gap), so each
      # level calls the next via an explicit receiver instead. Still a
      # genuine 3-frame unwind, crossing object boundaries too.

      class Level3
        def run
          raise "deep failure"
        end
      end
      class Level2
        def run
          Level3.new.run
        end
      end
      class Level1
        def run
          Level2.new.run
        end
      end
      begin
        Level1.new.run
      rescue => e
        puts "caught from deep: #{e.send(:message)}"
      end
    RUBY
  end

  it "unresolved call raises" do
    result = ze0(<<~'RUBY')
      def id(x); x; end
      begin
        id({}).no_such_method_xyz
        puts "not reached"
      rescue NoMethodError => e
        puts e.class
      end
      begin
        r = id(nil).no_such_method_abc
        puts r.inspect
      rescue NoMethodError => e
        puts e.class
      end
      puts "after"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NoMethodError
      NoMethodError
      after
    OUT
  end

  it "unresolved tail call value" do
    result = ze0(<<~'RUBY')
      # A method whose body ends in a call nothing resolves (`@text.string` with
      # @text a String) never returns a value: the emitter answers that tail with a
      # NoMethodError raise. A caller that READS the value still needs a typed
      # result, and the untyped return made the assignment a void expression.

      # A user class sharing the tail call's NAME is not a candidate when the
      # receiver is statically a String: only a reopen of String could answer it.
      class Holder
        def initialize
          @string = "held"
        end

        def string
          @string
        end
      end

      class Gen
        def initialize
          @text = ""
        end

        def text
          @text.string
        end
      end

      class Parse
        def initialize
          @t = ""
        end

        def prep
          g = Gen.new
          @t = g.text
        end

        def size
          @t.length
        end
      end

      p1 = Parse.new
      begin
        p1.prep
      rescue NoMethodError => e
        puts "raised"
      end
      p p1.size
      p Holder.new.string
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      raised
      0
      "held"
    OUT
  end

  it "unset constant raises a name error" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught: uninitialized constant UNDEFINED_CONST\n"
      begin
        puts UNDEFINED_CONST
      rescue NameError => e
        puts "caught: #{e.message}"
      end
    RUBY
  end

  it "user exception subclass class method constructs via runtime" do
    result = ze0(<<~'RUBY')
      # A `def self.x` on an exception subclass emits into a `pub mod` (no struct to
      # attach an `impl` to), and a bare `new` inside it constructs via the runtime
      # (D3) -- `Self.new` there yields the native `RubyException`, not a `new_handle`.

      class D < StandardError
        def self.build(n)
          new("built-#{n}")
        end
      end
      e = D.build(3)
      puts e.message
      puts e.class
      puts e.is_a?(StandardError)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      built-3
      D
      true
    OUT
  end

  it "user exception subclass keyword initialize" do
    result = ze0(<<~'RUBY')
      # An exception subclass whose `initialize` takes KEYWORD arguments (D3): the
      # runtime construction path (`construct_by_class_id`) must carry keywords as
      # the trailing-Hash the trampoline expects, or `code:` would default. Two
      # sibling subclasses -- neither's `message` param pinned to a String -- also
      # exercise the poly `super(message)` coercion into the native message slot.

      class AError < StandardError
        attr_reader :code
        def initialize(message, code: 3)
          super(message)
          @code = code
        end
      end
      class BError < StandardError
        attr_reader :level
        def initialize(message, level = 7)
          super(message)
          @level = level
        end
      end
      a = AError.new("boom", code: 9)
      puts a.code
      puts a.message
      b = BError.new("bad", 5)
      puts b.level
      puts b.message
      puts AError.new("d").code
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      9
      boom
      5
      bad
      3
    OUT
  end

  it "user exception subclass super chain and inherited initialize" do
    result = ze0(<<~'RUBY')
      # A user exception subclass with NO `initialize` inherits the native default:
      # `Plain.new(msg)` stores the message in the hidden slot, so `#message`
      # returns it and `instance_variables` is empty. Multi-level `super` chains
      # (`B < A < StandardError`, bare `super` forwarding) also resolve natively.

      class Plain < RuntimeError
      end
      p1 = Plain.new("hi")
      puts p1.message
      p p1.instance_variables

      class A < StandardError
        def initialize(msg = "a-default")
          super
        end
      end
      class B < A
        def initialize
          super()
          @tag = "b"
        end
        def tag; @tag; end
      end
      b = B.new
      puts b.message
      puts b.tag
      puts b.is_a?(A)

      class Done < StopIteration
      end
      puts Done.new("stop").message
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hi
      []
      a-default
      b
      true
      stop
    OUT
  end

  it "user exception subclass uses native representation" do
    result = ze0(<<~'RUBY')
      # A USER exception subclass is backed by the native `RubyException` (D3): a
      # custom ivar, `super` into the native `initialize` (which stores the message
      # in its hidden slot), and reflection all match CRuby -- `instance_variables`
      # is `[:@code]` only (NOT `@message`), and `@message` reads nil while
      # `#message` returns the super-provided text.

      class MyErr < StandardError
        def initialize(code)
          @code = code
          super("boom #{code}")
        end
        def code
          @code
        end
      end

      e = MyErr.new(42)
      puts e.message
      puts e.code
      puts e.is_a?(StandardError)
      p e.instance_variables
      p e.instance_variable_get(:@message)
      p e.instance_variable_get(:@code)
      begin
        raise MyErr, "direct"
      rescue StandardError => ex
        puts "#{ex.class}: #{ex.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      boom 42
      42
      true
      [:@code]
      nil
      42
      MyErr: boom direct
    OUT
  end

  it "valued break deep" do
    result = ze0(<<~'RUBY')
      # Deeply nested break scopes: each recursion level enters a break-wrapped
      # iterator whose scope stays live while the block recurses deeper, so many
      # scopes are simultaneously on the fixed-size break stack. This exercises the
      # push/pop balance and per-scope serial addressing at depth (well under the
      # SP_BRK_STACK_MAX guard that turns an overflow into a loud fatal rather than
      # corruption). deep(n) == n: each level's `each` returns its own break value.
      def deep(n)
        return 0 if n == 0
        [1, 2, 3].each do |x|
          break deep(n - 1) + 1
        end
      end
      p deep(1)
      p deep(40)

      # Depth through a yield method: the spliced block's break targets the call that
      # received it at each level, past the method's own iterator.
      def relay
        [1].each { |x| yield x }
      end
      def climb(n)
        return 0 if n == 0
        relay { |x| break climb(n - 1) + x }
      end
      p climb(50)

      # A break at a shallow level must still target its own scope when deeper
      # (already-returned) scopes have been popped: sequential, not just nested.
      def once
        [1, 2, 3].each { |x| break x * 10 if x == 2 }
      end
      sum = 0
      10.times { sum += once }
      p sum
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      40
      50
      200
    OUT
  end

  it "valued break ensure" do
    result = ze0(<<~'RUBY')
      # A break crossing begin/ensure frames runs the ensure bodies on the way out
      # (CRuby TAG_BREAK unwinding), then the call yields the break value.
      p([1, 2, 3].each { |x| begin; break 1 if x == 2; ensure; puts "e#{x}"; end })

      # nested ensures both run, innermost first
      p([1, 2].map do |x|
        begin
          begin
            break :deep if x == 2
            x
          ensure
            puts "inner#{x}"
          end
        ensure
          puts "outer#{x}"
        end
      end)

      # a rescue-only frame between break and the call unwinds cleanly, and a raise
      # AFTER the break-carrying loop still lands in the right handler
      begin
        r = [1, 2, 3].map { |x| begin; break x * 5 if x == 2; x; rescue; :never; end }
        p r
        raise "boom"
      rescue => e
        puts e.message
      end

      # an exception rescued OUTSIDE a wrapped call, then a later unrelated break
      begin
        [1, 2].each { |x| raise "mid" if x == 2 }
      rescue => e
        puts e.message
      end
      p([7, 8].each { |x| break x if x == 8 })

      # break through an ensure inside an inlined yield method
      def guarded
        begin
          yield
        ensure
          puts "guard"
        end
      end
      p(guarded { break :gv })

      # ensure that allocates while the break value is in flight
      p([1, 2].each { |x| begin; break [x, x + 1] if x == 2; ensure; s = "a#{x}" * 3; puts s; end })

      # next/redo in a wrapped block keep their meaning
      p([1, 2, 3].map { |x| next x * 2 if x == 2; break :b if x == 3; x })
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      e1
      e2
      1
      inner1
      outer1
      inner2
      outer2
      :deep
      10
      boom
      mid
      8
      guard
      :gv
      a1a1a1
      a2a2a2
      [2, 3]
      :b
    OUT
  end

  it "void value in value position" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      # A method that unconditionally raises has a C `void` return type. Using its
      # (never-produced) result in value position -- assigned to a local or passed
      # as an argument -- must still compile: the use is unreachable because the
      # call diverges. Previously codegen rejected it ('unsupported type void').

      def boom
        raise "always raises"
      end

      def sink(x)
        x.to_s
      end

      def use_arg
        sink(boom)        # boom never returns; arg in value position
      end

      def use_local
        v = boom          # boom never returns; local in value position
        v.to_s
      end

      # Never executed (CRuby never raises), but all must AOT-compile -- including
      # a void value handed straight to puts / print / p.
      if false
        use_arg
        use_local
        puts boom
        print boom
        p boom
      end
      puts "ok"
    RUBY
  end

  it "yield no block raises" do
    result = ze0(<<~'RUBY')
      # An unguarded yield in a method called with no block raises LocalJumpError.
      # A block_given?-guarded yield does not.
      def run
        yield
      end
      begin
        run
      rescue LocalJumpError => e
        puts "stmt: #{e.message}"
      end

      def ex
        x = yield
        x + 1
      end
      begin
        ex
      rescue LocalJumpError => e
        puts "expr: #{e.message}"
      end

      def guarded
        block_given? ? yield : 42
      end
      puts guarded

      def maybe
        yield if block_given?
        "done"
      end
      puts maybe

      # same method used with a block still works
      def twice
        yield + yield
      end
      puts twice { 21 }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      stmt: no block given (yield)
      expr: no block given (yield)
      42
      done
      42
    OUT
  end

  it "yielding call in rescue expr" do
    result = ze0(<<~'RUBY')
      def wrap001
        yield
      end
      r001 = (begin; wrap001 { raise ArgumentError, "d" }; rescue => e001; 0; end); p r001
      r002 = (begin; wrap001 { 5 }; rescue => e; 0; end); p r002
      def w2; yield; end
      r003 = begin; w2 { raise "z" }; rescue => e; :c; end; p r003
      def w3(a); yield a; end
      r004 = (begin; w3(2) { |x| raise ArgumentError if x == 2; x }; rescue ArgumentError; :r; end); p r004
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0
      5
      :c
      :r
    OUT
  end
end
