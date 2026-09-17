# frozen_string_literal: true

require "spec_helper"

describe "Builtins: formatting and inspection" do
  it "allocate rows" do
    result = ze0(<<~'RUBY')
      # `allocate` -- a blank instance with no `initialize`. zeo raised
      # "allocator undefined" for `Object`, `BasicObject`, `Range` and every
      # exception class, and `Class.allocate` (ruby declares it on `Class`'s OWN
      # singleton) answered off the generic row.

      def show(label)
        print label, ": "
        p yield
      rescue Exception => e # rubocop:disable Lint/RescueException
        p [e.class, e.message]
      end

      p Class.singleton_methods(false).sort

      # `Class.allocate` is a class with NO superclass -- not one whose superclass is
      # `BasicObject`. Nothing can come of it until `initialize` runs.
      c = Class.allocate
      show("class") { c.class }
      show("is_a") { [c.is_a?(Class), c.is_a?(Module)] }
      show("name") { c.name }
      show("ancestors") { c.ancestors == [c] }
      show("instance_methods") { c.instance_methods }
      show("superclass") { c.superclass }
      show("new") { c.new }
      show("allocate") { c.allocate }
      show("distinct") { Class.allocate.equal?(Class.allocate) }

      # The value classes answer their empty value.
      show("String") { String.allocate }
      show("Array") { Array.allocate }
      show("Hash") { Hash.allocate }
      show("Object") { Object.allocate.class }
      show("Range") { Range.allocate.inspect }

      # An exception's payload allocates too, so every `Exception` method still
      # reads. A blank message defaults to the class name.
      show("RuntimeError") { [RuntimeError.allocate.class, RuntimeError.allocate.message] }
      show("Exception") { Exception.allocate.inspect }
      show("Errno") { Errno::ENOENT.allocate.class }

      # The immediates have no allocator, and a module has no `allocate` at all.
      show("Integer") { Integer.allocate }
      show("Symbol") { Symbol.allocate }
      show("Comparable") { Comparable.allocate }

      # `first`/`last` are not `begin`/`end`: an open endpoint HAS no element.
      show("beginless first") { (..5).first }
      show("beginless begin") { (..5).begin }
      show("beginless last") { (..5).last }
      show("endless last") { (1..).last }
      show("endless end") { (1..).end }
      show("endless first") { (1..).first }
      show("bounded") { [(1..5).first, (1..5).last, (1...5).last] }
      show("n-form") { [(1..5).first(2), (1..5).last(2), (1..).first(2)] }
    RUBY

    _(result).must_answer <<~'OUT'
      [:allocate]
      class: Class
      is_a: [true, true]
      name: nil
      ancestors: true
      instance_methods: []
      superclass: [TypeError, "uninitialized class"]
      new: [TypeError, "can't instantiate uninitialized class"]
      allocate: [TypeError, "can't instantiate uninitialized class"]
      distinct: false
      String: ""
      Array: []
      Hash: {}
      Object: Object
      Range: "nil..nil"
      RuntimeError: [RuntimeError, "RuntimeError"]
      Exception: "#<Exception: Exception>"
      Errno: Errno::ENOENT
      Integer: [TypeError, "allocator undefined for Integer"]
      Symbol: [TypeError, "allocator undefined for Symbol"]
      Comparable: [NoMethodError, "undefined method 'allocate' for module Comparable"]
      beginless first: [RangeError, "cannot get the first element of beginless range"]
      beginless begin: nil
      beginless last: 5
      endless last: [RangeError, "cannot get the last element of endless range"]
      endless end: nil
      endless first: 1
      bounded: [1, 5, 5]
      n-form: [[1, 2], [4, 5], [1, 2]]
    OUT
  end

  it "builtin reopen" do
    result = ze0(<<~'RUBY')
      # Phase 16.3 -- reopening builtin classes in root: fresh methods, overrides
      # of native methods, class-level state, and protocol overrides all attach to
      # the real builtin classes and win everywhere real Ruby's would.

      class String
        def blank?
          length == 0
        end

        def shout
          exclaim + "?"
        end

        def exclaim
          self + "!"
        end
      end

      class Integer
        def repeat(sep = "-")
          out = ""
          i = 0
          while i < self
            out = out + yield(i).to_s
            out = out + sep if i < self - 1
            i = i + 1
          end
          out
        end
      end

      class Array
        @@made = 0
        LIMIT = 3

        def self.tally_up
          @@made = @@made + 1
          @@made
        end

        def under_limit?
          length < LIMIT
        end
      end

      class Range
        def span
          self.last - self.first
        end
      end

      class NilClass
        def describe
          "nothing"
        end
      end

      puts "".blank?
      puts "  hi".blank?
      puts "hey".shout

      puts 3.repeat { |i| i * 2 }
      puts 2.repeat("+") { |i| i + 1 }

      puts Array.tally_up
      puts Array.tally_up
      puts [1, 2].under_limit?
      puts [1, 2, 3, 4].under_limit?
      puts Array::LIMIT

      puts (3..9).span
      puts nil.describe

      # A user override of an EXISTING native method wins at every call site --
      # static and dynamic -- while `length` (a separate method, not an alias)
      # stays native. (Overriding a name no earlier statement calls, so the
      # compile-time class model and Ruby's sequential execution agree.)
      class Hash
        def size
          42
        end
      end

      h = { a: 1, b: 2 }
      puts h.size
      puts [h].first.size
      puts h.length

      # An unknown method on a builtin still raises real Ruby's NoMethodError.
      begin
        "hey".nope
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      hey!?
      0-2-4
      1+2
      1
      2
      true
      false
      3
      6
      nothing
      42
      42
      2
      undefined method 'nope' for an instance of String
    OUT
  end

  it "builtin reopen to s and inspect drive rendering" do
    result = ze0(<<~'RUBY')
      # `to_s`/`inspect` overrides on a builtin drive `puts`, interpolation,
      # `p`, CONTAINER inspect (real Ruby's rb_inspect dispatches per element --
      # oracle-verified `[5].inspect` -> `[I]`), and explicit `.to_s`.

      class Integer
        def to_s
          "int"
        end

        def inspect
          "I"
        end
      end

      puts 5
      puts "v=#{5}"
      p 7
      puts [5].inspect
      puts 6.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      int
      v=int
      I
      [I]
      int
    OUT
  end

  it "env enumerable and mutator surface" do
    result = ze0(<<~'RUBY')
      # ENV's read-only surface (value?/each_value/min via the Hash snapshot) and
      # the mutators (update/merge!/reject!/delete_if). Uses unique names/values
      # so it never depends on the ambient environment.

      ENV["ZZE_A"] = "uniqA"; ENV["ZZE_B"] = "uniqB"
      p ENV.value?("uniqA")
      p ENV.has_value?("nope_zzz_xyz")
      p ENV.update("ZZE_A" => "uniq9")["ZZE_A"]
      p ENV.merge!("ZZE_C" => "uniq3")["ZZE_C"]
      p ENV.reject! { |k, v| false }
      p [ENV.each_value.is_a?(Enumerator), ENV.count { |k, v| k.start_with?("ZZE_") } >= 3]
      ENV.delete_if { |k, v| k.start_with?("ZZE_") }
      p ENV.key?("ZZE_C")
      p ENV.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "uniq9"
      "uniq3"
      nil
      [true, true]
      false
      "ENV"
    OUT
  end

  it "env full surface" do
    result = ze0(<<~'RUBY')
      # ENV's enumeration surface rides a StrStr-hash snapshot (__env_to_h), so the
      # Hash machinery serves keys/each/select/count{}/fetch{}/inspect (#2742, #2744,
      # #2745); direct arms cover identity, copy refusal, mutators, arity and
      # key-type validation (#2743, #2746, #2747, #2765, #2766, #2773).
      ENV['ZZ_A'] = '1'
      p ENV.keys.include?('ZZ_A')
      p ENV.count { |k, v| k == 'ZZ_A' }
      p ENV.fetch('ZZ_NOPE') { |k| "missing:#{k}" }
      p ENV.to_s
      r = (ENV.dup rescue $!.message); p r
      r = (ENV.clone rescue $!.message); p r
      r = (ENV.freeze rescue $!.message); p r
      r = (ENV.fetch rescue $!.message); p r
      r = (ENV.fetch('A', 'd', 'x') rescue $!.message); p r
      r = (ENV['a', 'b'] rescue $!.message); p r
      r = (ENV[:sym] rescue $!.class); p r
      r = (ENV[5] rescue $!.class); p r
      p(ENV['ZZ_A'] = '9')
      v = (ENV['ZZ_A'] = '7')
      p v
      p ENV['ZZ_A']
      p ENV.store('ZZ_B', '3')
      p ENV.delete('ZZ_B')
      p ENV.delete('ZZ_NOPE')
      p ENV.inspect.class
      p ENV.hash.class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      1
      "missing:ZZ_NOPE"
      "ENV"
      "Cannot dup ENV, use ENV.to_h to get a copy of ENV as a hash"
      "Cannot clone ENV, use ENV.to_h to get a copy of ENV as a hash"
      "cannot freeze ENV"
      "wrong number of arguments (given 0, expected 1..2)"
      "wrong number of arguments (given 3, expected 1..2)"
      "wrong number of arguments (given 2, expected 1)"
      TypeError
      TypeError
      "9"
      "7"
      "7"
      "3"
      "3"
      nil
      String
      Integer
    OUT
  end

  it "format float rounding surface" do
    result = ze0(<<~'RUBY')
      # Ruby rounds a float conversion on the SHORTEST round-trip decimal (ties to
      # even), not on the exact binary double -- 2.675 is stored as 2.67499999999999982,
      # so C printf answers 2.67 where ruby answers 2.68, and 2.345 goes the other way.
      # `%e` and `%g` round the same string.
      vals = [0.0, -0.0, 1.0, 0.5, 2.5, 3.5, 0.05, 0.005, 0.0005, 2.675, 2.345, 1.005, 8.835,
              0.145, 1.115, 1.255, 0.615, 4.985, 123.456, 1e10, 1e-10, 1.0/3, 2.0/3, 9.995,
              99.995, 0.9999, 1e15, 1e16, 1.23456789012345e5, 0.1, 0.2, 0.3, 1e-5, 12345.6789,
              -2.675, -0.005, 1e100, 1e-100, 3.14159265358979, 1e300]
      convs = ["%f","%.0f","%.1f","%.2f","%.3f","%.5f","%.10f","%.17f","%.20f","%e","%.0e","%.1e","%.2e","%.5e","%E","%g","%.1g","%.2g","%.3g","%.6g","%.10g","%G","%10.2f","%-10.2f","%+.2f","%08.2f","% .2f","%#.3g"]
      convs.each do |c|
        puts(vals.map { |v| format(c, v) }.join("|"))
      end
    RUBY

    _(result).must_answer "0.000000|-0.000000|1.000000|0.500000|2.500000|3.500000|0.050000|0.005000|0.000500|2.675000|2.345000|1.005000|8.835000|0.145000|1.115000|1.255000|0.615000|4.985000|123.456000|10000000000.000000|0.000000|0.333333|0.666667|9.995000|99.995000|0.999900|1000000000000000.000000|10000000000000000.000000|123456.789012|0.100000|0.200000|0.300000|0.000010|12345.678900|-2.675000|-0.005000|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.000000|0.000000|3.141593|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.000000\n0|-0|1|0|2|4|0|0|0|3|2|1|9|0|1|1|1|5|123|10000000000|0|0|1|10|100|1|1000000000000000|10000000000000000|123457|0|0|0|0|12346|-3|-0|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104|0|3|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160\n0.0|-0.0|1.0|0.5|2.5|3.5|0.1|0.0|0.0|2.7|2.3|1.0|8.8|0.1|1.1|1.3|0.6|5.0|123.5|10000000000.0|0.0|0.3|0.7|10.0|100.0|1.0|1000000000000000.0|10000000000000000.0|123456.8|0.1|0.2|0.3|0.0|12345.7|-2.7|-0.0|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.0|0.0|3.1|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.0\n0.00|-0.00|1.00|0.50|2.50|3.50|0.05|0.01|0.00|2.68|2.34|1.00|8.84|0.14|1.12|1.26|0.62|4.98|123.46|10000000000.00|0.00|0.33|0.67|10.00|100.00|1.00|1000000000000000.00|10000000000000000.00|123456.79|0.10|0.20|0.30|0.00|12345.68|-2.68|-0.01|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00|0.00|3.14|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00\n0.000|-0.000|1.000|0.500|2.500|3.500|0.050|0.005|0.001|2.675|2.345|1.005|8.835|0.145|1.115|1.255|0.615|4.985|123.456|10000000000.000|0.000|0.333|0.667|9.995|99.995|1.000|1000000000000000.000|10000000000000000.000|123456.789|0.100|0.200|0.300|0.000|12345.679|-2.675|-0.005|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.000|0.000|3.142|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.000\n0.00000|-0.00000|1.00000|0.50000|2.50000|3.50000|0.05000|0.00500|0.00050|2.67500|2.34500|1.00500|8.83500|0.14500|1.11500|1.25500|0.61500|4.98500|123.45600|10000000000.00000|0.00000|0.33333|0.66667|9.99500|99.99500|0.99990|1000000000000000.00000|10000000000000000.00000|123456.78901|0.10000|0.20000|0.30000|0.00001|12345.67890|-2.67500|-0.00500|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00000|0.00000|3.14159|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00000\n0.0000000000|-0.0000000000|1.0000000000|0.5000000000|2.5000000000|3.5000000000|0.0500000000|0.0050000000|0.0005000000|2.6750000000|2.3450000000|1.0050000000|8.8350000000|0.1450000000|1.1150000000|1.2550000000|0.6150000000|4.9850000000|123.4560000000|10000000000.0000000000|0.0000000001|0.3333333333|0.6666666667|9.9950000000|99.9950000000|0.9999000000|1000000000000000.0000000000|10000000000000000.0000000000|123456.7890123450|0.1000000000|0.2000000000|0.3000000000|0.0000100000|12345.6789000000|-2.6750000000|-0.0050000000|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.0000000000|0.0000000000|3.1415926536|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.0000000000\n0.00000000000000000|-0.00000000000000000|1.00000000000000000|0.50000000000000000|2.50000000000000000|3.50000000000000000|0.05000000000000000|0.00500000000000000|0.00050000000000000|2.67499999999999982|2.34500000000000020|1.00499999999999989|8.83500000000000085|0.14499999999999999|1.11499999999999999|1.25499999999999989|0.61499999999999999|4.98500000000000032|123.45600000000000307|10000000000.00000000000000000|0.00000000010000000|0.33333333333333331|0.66666666666666663|9.99499999999999922|99.99500000000000455|0.99990000000000001|1000000000000000.00000000000000000|10000000000000000.00000000000000000|123456.78901234500517603|0.10000000000000001|0.20000000000000001|0.29999999999999999|0.00001000000000000|12345.67890000000079453|-2.67499999999999982|-0.00500000000000000|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00000000000000000|0.00000000000000000|3.14159265358979001|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00000000000000000\n0.00000000000000000000|-0.00000000000000000000|1.00000000000000000000|0.50000000000000000000|2.50000000000000000000|3.50000000000000000000|0.05000000000000000278|0.00500000000000000010|0.00050000000000000001|2.67499999999999982236|2.34500000000000019540|1.00499999999999989342|8.83500000000000085265|0.14499999999999999001|1.11499999999999999112|1.25499999999999989342|0.61499999999999999112|4.98500000000000031974|123.45600000000000306954|10000000000.00000000000000000000|0.00000000010000000000|0.33333333333333331483|0.66666666666666662966|9.99499999999999921840|99.99500000000000454747|0.99990000000000001101|1000000000000000.00000000000000000000|10000000000000000.00000000000000000000|123456.78901234500517603010|0.10000000000000000555|0.20000000000000001110|0.29999999999999998890|0.00001000000000000000|12345.67890000000079453457|-2.67499999999999982236|-0.00500000000000000010|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00000000000000000000|0.00000000000000000000|3.14159265358979000737|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00000000000000000000\n0.000000e+00|-0.000000e+00|1.000000e+00|5.000000e-01|2.500000e+00|3.500000e+00|5.000000e-02|5.000000e-03|5.000000e-04|2.675000e+00|2.345000e+00|1.005000e+00|8.835000e+00|1.450000e-01|1.115000e+00|1.255000e+00|6.150000e-01|4.985000e+00|1.234560e+02|1.000000e+10|1.000000e-10|3.333333e-01|6.666667e-01|9.995000e+00|9.999500e+01|9.999000e-01|1.000000e+15|1.000000e+16|1.234568e+05|1.000000e-01|2.000000e-01|3.000000e-01|1.000000e-05|1.234568e+04|-2.675000e+00|-5.000000e-03|1.000000e+100|1.000000e-100|3.141593e+00|1.000000e+300\n0e+00|-0e+00|1e+00|5e-01|2e+00|4e+00|5e-02|5e-03|5e-04|3e+00|2e+00|1e+00|9e+00|1e-01|1e+00|1e+00|6e-01|5e+00|1e+02|1e+10|1e-10|3e-01|7e-01|1e+01|1e+02|1e+00|1e+15|1e+16|1e+05|1e-01|2e-01|3e-01|1e-05|1e+04|-3e+00|-5e-03|1e+100|1e-100|3e+00|1e+300\n0.0e+00|-0.0e+00|1.0e+00|5.0e-01|2.5e+00|3.5e+00|5.0e-02|5.0e-03|5.0e-04|2.7e+00|2.3e+00|1.0e+00|8.8e+00|1.4e-01|1.1e+00|1.3e+00|6.2e-01|5.0e+00|1.2e+02|1.0e+10|1.0e-10|3.3e-01|6.7e-01|1.0e+01|1.0e+02|1.0e+00|1.0e+15|1.0e+16|1.2e+05|1.0e-01|2.0e-01|3.0e-01|1.0e-05|1.2e+04|-2.7e+00|-5.0e-03|1.0e+100|1.0e-100|3.1e+00|1.0e+300\n0.00e+00|-0.00e+00|1.00e+00|5.00e-01|2.50e+00|3.50e+00|5.00e-02|5.00e-03|5.00e-04|2.68e+00|2.34e+00|1.00e+00|8.84e+00|1.45e-01|1.12e+00|1.26e+00|6.15e-01|4.98e+00|1.23e+02|1.00e+10|1.00e-10|3.33e-01|6.67e-01|1.00e+01|1.00e+02|1.00e+00|1.00e+15|1.00e+16|1.23e+05|1.00e-01|2.00e-01|3.00e-01|1.00e-05|1.23e+04|-2.68e+00|-5.00e-03|1.00e+100|1.00e-100|3.14e+00|1.00e+300\n0.00000e+00|-0.00000e+00|1.00000e+00|5.00000e-01|2.50000e+00|3.50000e+00|5.00000e-02|5.00000e-03|5.00000e-04|2.67500e+00|2.34500e+00|1.00500e+00|8.83500e+00|1.45000e-01|1.11500e+00|1.25500e+00|6.15000e-01|4.98500e+00|1.23456e+02|1.00000e+10|1.00000e-10|3.33333e-01|6.66667e-01|9.99500e+00|9.99950e+01|9.99900e-01|1.00000e+15|1.00000e+16|1.23457e+05|1.00000e-01|2.00000e-01|3.00000e-01|1.00000e-05|1.23457e+04|-2.67500e+00|-5.00000e-03|1.00000e+100|1.00000e-100|3.14159e+00|1.00000e+300\n0.000000E+00|-0.000000E+00|1.000000E+00|5.000000E-01|2.500000E+00|3.500000E+00|5.000000E-02|5.000000E-03|5.000000E-04|2.675000E+00|2.345000E+00|1.005000E+00|8.835000E+00|1.450000E-01|1.115000E+00|1.255000E+00|6.150000E-01|4.985000E+00|1.234560E+02|1.000000E+10|1.000000E-10|3.333333E-01|6.666667E-01|9.995000E+00|9.999500E+01|9.999000E-01|1.000000E+15|1.000000E+16|1.234568E+05|1.000000E-01|2.000000E-01|3.000000E-01|1.000000E-05|1.234568E+04|-2.675000E+00|-5.000000E-03|1.000000E+100|1.000000E-100|3.141593E+00|1.000000E+300\n0|-0|1|0.5|2.5|3.5|0.05|0.005|0.0005|2.675|2.345|1.005|8.835|0.145|1.115|1.255|0.615|4.985|123.456|1e+10|1e-10|0.333333|0.666667|9.995|99.995|0.9999|1e+15|1e+16|123457|0.1|0.2|0.3|1e-05|12345.7|-2.675|-0.005|1e+100|1e-100|3.14159|1e+300\n0|-0|1|0.5|2|4|0.05|0.005|0.0005|3|2|1|9|0.1|1|1|0.6|5|1e+02|1e+10|1e-10|0.3|0.7|1e+01|1e+02|1|1e+15|1e+16|1e+05|0.1|0.2|0.3|1e-05|1e+04|-3|-0.005|1e+100|1e-100|3|1e+300\n0|-0|1|0.5|2.5|3.5|0.05|0.005|0.0005|2.7|2.3|1|8.8|0.14|1.1|1.3|0.62|5|1.2e+02|1e+10|1e-10|0.33|0.67|10|1e+02|1|1e+15|1e+16|1.2e+05|0.1|0.2|0.3|1e-05|1.2e+04|-2.7|-0.005|1e+100|1e-100|3.1|1e+300\n0|-0|1|0.5|2.5|3.5|0.05|0.005|0.0005|2.68|2.34|1|8.84|0.145|1.12|1.26|0.615|4.98|123|1e+10|1e-10|0.333|0.667|10|100|1|1e+15|1e+16|1.23e+05|0.1|0.2|0.3|1e-05|1.23e+04|-2.68|-0.005|1e+100|1e-100|3.14|1e+300\n0|-0|1|0.5|2.5|3.5|0.05|0.005|0.0005|2.675|2.345|1.005|8.835|0.145|1.115|1.255|0.615|4.985|123.456|1e+10|1e-10|0.333333|0.666667|9.995|99.995|0.9999|1e+15|1e+16|123457|0.1|0.2|0.3|1e-05|12345.7|-2.675|-0.005|1e+100|1e-100|3.14159|1e+300\n0|-0|1|0.5|2.5|3.5|0.05|0.005|0.0005|2.675|2.345|1.005|8.835|0.145|1.115|1.255|0.615|4.985|123.456|1e+10|1e-10|0.3333333333|0.6666666667|9.995|99.995|0.9999|1e+15|1e+16|123456.789|0.1|0.2|0.3|1e-05|12345.6789|-2.675|-0.005|1e+100|1e-100|3.141592654|1e+300\n0|-0|1|0.5|2.5|3.5|0.05|0.005|0.0005|2.675|2.345|1.005|8.835|0.145|1.115|1.255|0.615|4.985|123.456|1E+10|1E-10|0.333333|0.666667|9.995|99.995|0.9999|1E+15|1E+16|123457|0.1|0.2|0.3|1E-05|12345.7|-2.675|-0.005|1E+100|1E-100|3.14159|1E+300\n      0.00|     -0.00|      1.00|      0.50|      2.50|      3.50|      0.05|      0.01|      0.00|      2.68|      2.34|      1.00|      8.84|      0.14|      1.12|      1.26|      0.62|      4.98|    123.46|10000000000.00|      0.00|      0.33|      0.67|     10.00|    100.00|      1.00|1000000000000000.00|10000000000000000.00| 123456.79|      0.10|      0.20|      0.30|      0.00|  12345.68|     -2.68|     -0.01|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00|      0.00|      3.14|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00\n0.00      |-0.00     |1.00      |0.50      |2.50      |3.50      |0.05      |0.01      |0.00      |2.68      |2.34      |1.00      |8.84      |0.14      |1.12      |1.26      |0.62      |4.98      |123.46    |10000000000.00|0.00      |0.33      |0.67      |10.00     |100.00    |1.00      |1000000000000000.00|10000000000000000.00|123456.79 |0.10      |0.20      |0.30      |0.00      |12345.68  |-2.68     |-0.01     |10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00|0.00      |3.14      |1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00\n+0.00|-0.00|+1.00|+0.50|+2.50|+3.50|+0.05|+0.01|+0.00|+2.68|+2.34|+1.00|+8.84|+0.14|+1.12|+1.26|+0.62|+4.98|+123.46|+10000000000.00|+0.00|+0.33|+0.67|+10.00|+100.00|+1.00|+1000000000000000.00|+10000000000000000.00|+123456.79|+0.10|+0.20|+0.30|+0.00|+12345.68|-2.68|-0.01|+10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00|+0.00|+3.14|+1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00\n00000.00|-0000.00|00001.00|00000.50|00002.50|00003.50|00000.05|00000.01|00000.00|00002.68|00002.34|00001.00|00008.84|00000.14|00001.12|00001.26|00000.62|00004.98|00123.46|10000000000.00|00000.00|00000.33|00000.67|00010.00|00100.00|00001.00|1000000000000000.00|10000000000000000.00|123456.79|00000.10|00000.20|00000.30|00000.00|12345.68|-0002.68|-0000.01|10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00|00000.00|00003.14|1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00\n 0.00|-0.00| 1.00| 0.50| 2.50| 3.50| 0.05| 0.01| 0.00| 2.68| 2.34| 1.00| 8.84| 0.14| 1.12| 1.26| 0.62| 4.98| 123.46| 10000000000.00| 0.00| 0.33| 0.67| 10.00| 100.00| 1.00| 1000000000000000.00| 10000000000000000.00| 123456.79| 0.10| 0.20| 0.30| 0.00| 12345.68|-2.68|-0.01| 10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00| 0.00| 3.14| 1000000000000000052504760255204420248704468581108159154915854115511802457988908195786371375080447864043704443832883878176942523235360430575644792184786706982848387200926575803737830233794788090059368953234970799945081119038967640880074652742780142494579258788820056842838115669472196386865459400540160.00\n0.00|-0.00|1.00|0.500|2.50|3.50|0.0500|0.00500|0.000500|2.68|2.34|1.00|8.84|0.145|1.12|1.26|0.615|4.98|123.|1.00e+10|1.00e-10|0.333|0.667|10.0|100.|1.00|1.00e+15|1.00e+16|1.23e+05|0.100|0.200|0.300|1.00e-05|1.23e+04|-2.68|-0.00500|1.00e+100|1.00e-100|3.14|1.00e+300\n"
  end

  it "kernel intrinsic rows" do
    result = ze0(<<~'RUBY')
      # The `Kernel` functions the compiler folds straight into the caller, asked
      # for the three ways a fold cannot answer: `send`, `method` and `respond_to?`.
      #
      # `printf(...)` has always worked, because `codegen::call::kernel` compiles it
      # in place. Without a method-table row, though, `send(:printf, ...)` raised
      # NoMethodError, `method(:printf)` raised NameError, `respond_to?(:printf,
      # true)` answered false, and `Kernel.printf(...)` had nowhere to land. Each
      # row calls the very function the fold calls, so the two forms cannot
      # diverge.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      NAMES = %i[
        Pathname printf exit exit! abort at_exit lambda fork syscall set_trace_func
        __method__ __callee__ __dir__
      ].freeze

      # `syscall` is a NOTIMPLEMENT STUB on this platform, and ruby answers
      # `respond_to?` false for those while still listing them -- see
      # `tests/gaps/notimplement_stub_respond_to.rb`.
      ASKABLE = NAMES - %i[syscall]

      # ruby files all of these as PRIVATE instance methods and PUBLIC singleton
      # methods of Kernel -- what `module_function` means.
      show("private instance") { NAMES.all? { |m| Kernel.private_instance_methods(false).include?(m) } }
      show("public singleton") { NAMES.all? { |m| Kernel.singleton_methods(false).include?(m) } }
      show("not public instance") { NAMES.none? { |m| Kernel.instance_methods(false).include?(m) } }
      show("respond_to? private") { ASKABLE.all? { |m| respond_to?(m, true) } }
      show("respond_to? public") { ASKABLE.none? { |m| respond_to?(m) } }
      show("method objects") { NAMES.map { |m| method(m).class }.uniq }
      show("arities") { NAMES.to_h { |m| [m, Kernel.instance_method(m).arity] } }

      # Each one, called through `send`.
      show("send printf") { send(:printf, "%d-%s\n", 1, "a"); :printed }
      show("Kernel.printf") { Kernel.printf("%04b\n", 5); :printed }
      show("send lambda") { l = send(:lambda) { |x| x * 2 }; [l.class, l.lambda?, l.call(3)] }
      show("send Pathname") { send(:Pathname, "/x").to_s }
      show("send exit") { begin; send(:exit, 3); rescue SystemExit => e; e.status; end }
      show("send exit true") { begin; send(:exit); rescue SystemExit => e; e.status; end }
      show("send exit false") { begin; send(:exit, false); rescue SystemExit => e; e.status; end }
      show("send abort") { begin; send(:abort, "boom"); rescue SystemExit => e; [e.status, e.message]; end }
      show("send syscall") { send(:syscall, 999_999) }
      show("send set_trace_func nil") { send(:set_trace_func, nil) }
      show("send at_exit") { send(:at_exit) { nil }.class }

      # The frame readers. A builtin row pushes no frame of its own, so the current
      # frame is the CALLER's -- which is what makes these answer at all.
      def named_method = send(:__method__)
      def named_callee = send(:__callee__)
      class Holder
        def inside = send(:__method__)
      end
      show("send __method__") { named_method }
      show("direct __method__") { def d = __method__; d }
      show("send __callee__") { named_callee }
      show("__method__ in a class") { Holder.new.inside }
      show("__method__ at top level") { send(:__method__) }
      show("send __dir__ class") { send(:__dir__).class }
      show("__dir__ agrees with File") { send(:__dir__) == File.dirname(File.expand_path(__FILE__)) }
      show("Kernel.__dir__ is a String") { Kernel.__dir__.class }

      # `fork` is `Process.fork` under another name, so a gem's `Process._fork`
      # hook stays in the path.
      show("fork runs the child") do
        pid = send(:fork) { exit 7 }
        Process.wait2(pid)[1].exitstatus
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: "boom\n"
      private instance: true
      public singleton: true
      not public instance: true
      respond_to? private: true
      respond_to? public: true
      method objects: [Method]
      arities: {Pathname: 1, printf: -1, exit: -1, exit!: -1, abort: -1, at_exit: 0, lambda: 0, fork: 0, syscall: 0, set_trace_func: 1, __method__: 0, __callee__: 0, __dir__: 0}
      1-a
      send printf: :printed
      0101
      Kernel.printf: :printed
      send lambda: [Proc, true, 6]
      send Pathname: "/x"
      send exit: 3
      send exit true: 0
      send exit false: 1
      send abort: [1, "boom"]
      send syscall: NotImplementedError: syscall() function is unimplemented on this machine
      send set_trace_func nil: nil
      send at_exit: Proc
      send __method__: :named_method
      direct __method__: :d
      send __callee__: :named_callee
      __method__ in a class: :inside
      __method__ at top level: nil
      send __dir__ class: String
      __dir__ agrees with File: true
      Kernel.__dir__ is a String: String
      fork runs the child: 7
    OUT
  end

  it "module reflection rows" do
    result = ze0(<<~'RUBY')
      # `Module`'s reflection surface: the constant hooks, the class-variable
      # removal, the undef listing, and the lexical-nesting query.

      module Outer
        INNER_CONST = 1
        module Inner
          puts "nesting inner: #{Module.nesting.inspect}"
        end
        puts "nesting outer: #{Module.nesting.inspect}"
      end
      puts "nesting top: #{Module.nesting.inspect}"

      class Named
        puts "nesting class: #{Module.nesting.inspect}"
      end

      # `const_source_location`: an Array for a constant that exists (CRuby fills in
      # the file and line; zeo answers the empty Array it gives every C-defined
      # constant), nil for one that does not, NameError for a bad name.
      puts "source loc known: #{Outer.const_source_location(:INNER_CONST).class}"
      puts "source loc missing: #{Object.const_source_location(:Nope).inspect}"
      begin
        Object.const_source_location("nope")
      rescue NameError => e
        puts "source loc bad: #{e.message}"
      end

      # The default `const_missing` raises the NameError a plain miss would.
      begin
        Outer.const_missing(:Zed)
      rescue NameError => e
        puts "const_missing: #{e.message}"
      end

      # `autoload` resolves at compile time, so both rows answer nil -- what CRuby
      # answers once the feature has loaded.
      puts "autoload: #{Outer.autoload(:Later, 'later').inspect}"
      puts "autoload?: #{Outer.autoload?(:Later).inspect}"

      # `undefined_instance_methods` -- Complex is the one core class that undefs.
      puts "complex undefs: #{Complex.undefined_instance_methods.sort.inspect}"
      puts "object undefs: #{Object.undefined_instance_methods.inspect}"

      class Undefer
        def gone; end
        undef gone
      end
      puts "user undefs: #{Undefer.undefined_instance_methods.inspect}"
      puts "user instance methods: #{Undefer.instance_methods(false).inspect}"

      # `public_instance_method` refuses a private method by name.
      class Secretive
        def open_door; end
        private def shut_door; end
      end
      puts "public im: #{Secretive.public_instance_method(:open_door).class}"
      begin
        Secretive.public_instance_method(:shut_door)
      rescue NameError => e
        puts "public im private: #{e.message}"
      end
      begin
        Secretive.public_instance_method(:absent)
      rescue NameError => e
        puts "public im absent: #{e.message}"
      end

      # `remove_class_variable` answers the value it dropped.
      class Holder
        @@count = 42
      end
      puts "removed: #{Holder.remove_class_variable(:@@count)}"
      puts "after remove: #{Holder.class_variables.inspect}"
      begin
        Holder.remove_class_variable(:@@count)
      rescue NameError => e
        puts "remove twice: #{e.message}"
      end

      # `set_temporary_name` only takes on a class with no constant path.
      anon = Class.new
      puts "anon name: #{anon.name.inspect}"
      anon.set_temporary_name("scratch")
      puts "temp name: #{anon.name.inspect}"
      anon.set_temporary_name(nil)
      puts "cleared name: #{anon.name.inspect}"
      begin
        anon.set_temporary_name("")
      rescue ArgumentError => e
        puts "temp empty: #{e.message}"
      end
      begin
        anon.set_temporary_name("Scratch")
      rescue ArgumentError => e
        puts "temp const path: #{e.message}"
      end
      begin
        Named.set_temporary_name("nope")
      rescue RuntimeError => e
        puts "temp permanent: #{e.message}"
      end

      puts "refinements: #{Outer.refinements.inspect}"
      puts "used_modules: #{Module.used_modules.inspect}"
      puts "used_refinements: #{Module.used_refinements.inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      nesting inner: [Outer::Inner, Outer]
      nesting outer: [Outer]
      nesting top: []
      nesting class: [Named]
      source loc known: Array
      source loc missing: nil
      source loc bad: wrong constant name nope
      const_missing: uninitialized constant Outer::Zed
      autoload: nil
      autoload?: "later"
      complex undefs: [:%, :<, :<=, :>, :>=, :between?, :ceil, :clamp, :div, :divmod, :floor, :i, :modulo, :negative?, :positive?, :remainder, :round, :step, :truncate]
      object undefs: []
      user undefs: [:gone]
      user instance methods: []
      public im: UnboundMethod
      public im private: method 'shut_door' for class 'Secretive' is private
      public im absent: undefined method 'absent' for class 'Secretive'
      removed: 42
      after remove: []
      remove twice: class variable @@count not defined for Holder
      anon name: nil
      temp name: "scratch"
      cleared name: nil
      temp empty: empty class/module name
      temp const path: the temporary name must not be a constant path to avoid confusion
      temp permanent: can't change permanent name
      refinements: []
      used_modules: []
      used_refinements: []
    OUT
  end

  it "nil sentinel receiver surface" do
    result = ze0(<<~'RUBY')
      # A miss on a specialized container hands back the element type's own C nil --
      # SP_INT_NIL, a NULL string -- and the receiver arms read it as an ordinary
      # value. #4070 spelled the check out per name (to_s, inspect, to_i, to_f) and
      # every name it did not reach kept answering: `h["zz"].succ` was
      # -9223372036854775807, `h["zz"].bit_length` was 63, `s["zz"].hex` was 0.
      #
      # CRuby's nil answers only what NilClass defines. That is the exception list;
      # everything else is a NoMethodError. This program walks both halves so a name
      # added to one of the receiver chains has to say which half it is in.

      def try
        yield
      rescue NoMethodError
        "NoMethodError"
      rescue => e
        e.class.to_s
      end

      n = { "a" => 1 }

      # the names nil REFUSES on an int-typed miss
      %w[succ pred next bit_length ceil floor round truncate ord size magnitude
         digits chr integer? finite? real imaginary numerator denominator].each do |m|
        puts m + ": " + try { n["zz"].send(m).inspect }.to_s
      end

      # the names nil ANSWERS
      puts "to_i: " + n["zz"].to_i.inspect
      puts "to_f: " + n["zz"].to_f.inspect
      puts "to_r: " + n["zz"].to_r.inspect
      puts "to_c: " + n["zz"].to_c.inspect
      puts "to_s: " + n["zz"].to_s.inspect
      puts "inspect: " + n["zz"].inspect.inspect
      puts "nil?: " + n["zz"].nil?.inspect

      # and the same names on a real value still work
      puts "hit succ: " + n["a"].succ.inspect
      puts "hit bit_length: " + n["a"].bit_length.inspect
      puts "hit to_r: " + n["a"].to_r.inspect
      puts "hit to_c: " + n["a"].to_c.inspect
      puts "hit numerator: " + n["a"].numerator.inspect
      puts "hit denominator: " + n["a"].denominator.inspect

      s = { "a" => "ab" }

      %w[b hex oct intern to_sym lines].each do |m|
        puts "s " + m + ": " + try { s["zz"].send(m).inspect }.to_s
      end

      puts "s to_i: " + s["zz"].to_i.inspect
      puts "s to_s: " + s["zz"].to_s.inspect
      puts "s nil?: " + s["zz"].nil?.inspect
      puts "s hit hex: " + s["a"].hex.inspect
      puts "s hit to_sym: " + s["a"].to_sym.inspect
      puts "s hit lines: " + s["a"].lines.inspect

      # an array miss carries the same sentinel
      a = [7]
      puts "a succ: " + try { a[9].succ.inspect }.to_s
      puts "a to_i: " + a[9].to_i.inspect
      puts "a hit succ: " + a[0].succ.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      succ: NoMethodError
      pred: NoMethodError
      next: NoMethodError
      bit_length: NoMethodError
      ceil: NoMethodError
      floor: NoMethodError
      round: NoMethodError
      truncate: NoMethodError
      ord: NoMethodError
      size: NoMethodError
      magnitude: NoMethodError
      digits: NoMethodError
      chr: NoMethodError
      integer?: NoMethodError
      finite?: NoMethodError
      real: NoMethodError
      imaginary: NoMethodError
      numerator: NoMethodError
      denominator: NoMethodError
      to_i: 0
      to_f: 0.0
      to_r: (0/1)
      to_c: (0+0i)
      to_s: ""
      inspect: "nil"
      nil?: true
      hit succ: 2
      hit bit_length: 1
      hit to_r: (1/1)
      hit to_c: (1+0i)
      hit numerator: 1
      hit denominator: 1
      s b: NoMethodError
      s hex: NoMethodError
      s oct: NoMethodError
      s intern: NoMethodError
      s to_sym: NoMethodError
      s lines: NoMethodError
      s to_i: 0
      s to_s: ""
      s nil?: true
      s hit hex: 171
      s hit to_sym: :ab
      s hit lines: ["ab"]
      a succ: NoMethodError
      a to_i: 0
      a hit succ: 8
    OUT
  end

  it "process tms rows" do
    result = ze0(<<~'RUBY')
      # `Process::Tms` is a Struct in ruby, so its own singleton carries the five
      # names every generated Struct class carries. zeo had three of them; `new` was
      # a NoMethodError and `inspect` came off `Module`.

      p Process::Tms.singleton_methods(false).sort
      p [Process::Tms.method(:new).arity, Process::Tms.method(:inspect).arity]

      # `inspect` on the CLASS answers the class name -- the same string `to_s`
      # answers. Only the declaring owner differs.
      p Process::Tms.inspect
      p Process::Tms.to_s

      # `new` is `[]` under its other name. Fewer values than members leaves the
      # rest nil; more is an error.
      p Process::Tms.new.to_a
      p Process::Tms.new(1, 2, 3, 4).to_a
      p Process::Tms[1, 2, 3, 4].to_a
      p Process::Tms.new(1, 2).to_a
      begin
        Process::Tms.new(1, 2, 3, 4, 5)
      rescue ArgumentError => e
        p e.message
      end

      # The members keep whatever was given, so `inspect` on an INSTANCE renders the
      # struct line rather than the class name.
      p Process::Tms.new(1, 2, 3, 4).inspect
      p Process::Tms.members
      p Process::Tms.keyword_init?

      # `Process.times` still answers Floats through the same class.
      t = Process.times
      p [t.utime.class, t.stime.class, t.cutime.class, t.cstime.class]
      p t.to_a.size
    RUBY

    _(result).must_answer <<~'OUT'
      [:[], :inspect, :keyword_init?, :members, :new]
      [-1, 0]
      "Process::Tms"
      "Process::Tms"
      [nil, nil, nil, nil]
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      [1, 2, nil, nil]
      "struct size differs"
      "#<struct Process::Tms utime=1, stime=2, cutime=3, cstime=4>"
      [:utime, :stime, :cutime, :cstime]
      nil
      [Float, Float, Float, Float]
      4
    OUT
  end
end
