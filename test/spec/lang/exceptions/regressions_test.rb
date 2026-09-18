# frozen_string_literal: true

require "spec_helper"

describe "Exceptions: regressions" do
  it "issue 2899" do
    result = ze0(<<~'RUBY')
      def show(u)
        label = (u.details || "~")
        puts label
      rescue NoMethodError => e
        puts "caught"
      end
      show(nil)
    RUBY

    _(result).must_answer "caught\n"
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
      ZeroDivisionError
      ZeroDivisionError
      (0+0i)
    OUT
  end

  it "issue 2970" do
    result = ze0(<<~'RUBY')
      r = ([1, 2, 3].sample(random: Random.new(1)) rescue $!.class)
      p(r.nil? || [1, 2, 3].include?(r))
    RUBY

    _(result).must_answer "true\n"
  end

  it "issue 2979" do
    result = ze0(<<~'RUBY')
      r = ([[1, 2], [3]].transpose rescue $!.class); p r
      p([[1, 2], [3, 4]].transpose)
      p([[1], [2], [3]].transpose)
      p([[1, 2, 3], [4, 5, 6]].transpose)
    RUBY

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT', stderr: "bye now\n"
      status=1
      msg=bye now
      continued
      noarg-status=1
      noarg-msg=exit
    OUT
  end

  it "issue 3087" do
    result = ze0(<<~'RUBY')
      p(begin; throw :nope, 42; rescue => e; e.class; end)
      v = begin; throw :y; rescue UncaughtThrowError => e; e.tag; end
      p v
      w = begin; throw :z, 7; rescue UncaughtThrowError => e; e.value; end
      p w
    RUBY

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
      [true, false, true]
      [2, 4, 6]
    OUT
  end

  it "issue 3152" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer "ok\n"
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

    _(result).must_answer <<~'OUT'
      true
      [12, 25]
    OUT
  end

  it "issue 3200" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer "ok\n"
  end

  it "issue 3204" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer "ok\n"
  end

  it "issue 3208" do
    result = ze0(<<~'RUBY')
      values = ["<url>"]
      result = [].tap do |words|
        words << "Usage:"
        words.push(*values.map { _1 })
      end.join(" ")
      raise unless result == "Usage: <url>"
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "issue 3210" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer "ok\n"
  end

  it "issue 3212" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer "ok\n"
  end

  it "issue 3218" do
    result = ze0(<<~'RUBY')
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

    _(result).must_answer "ok\n"
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
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

    _(result).must_answer <<~'OUT'
      ["--name"]
      ["-h", "--help"]
      ArgumentError
    OUT
  end
end
