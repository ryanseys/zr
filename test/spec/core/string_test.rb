# frozen_string_literal: true

require "spec_helper"

describe "String" do
  it "a chilled literal warns on its first change" do
    result = ze0(<<~'RUBY', path: "core/string/a_chilled_literal_warns_on_its_first_change.rb")
      # A String literal in a file that sets no frozen_string_literal is
      # chilled: not frozen, but +@ copies it, and its first change warns when
      # deprecation warnings are on. Symbol#to_s chills its String too.

      s = "abc"
      t = +s
      p t.equal?(s), s.frozen?
      t << "x"
      p s
      u = +"lit"
      p((+u).equal?(u))
      Warning[:deprecated] = true
      %w[upcase! downcase! capitalize! swapcase! reverse! strip! squeeze! succ! chop! chomp! lstrip! clear].each do |m|
        x = "Abc "
        x.public_send(m)
      end
      [
        -> { a = "a"; a.concat("b") },
        -> { a = "a"; a.replace("b") },
        -> { a = "a"; a[0] = "b" },
        -> { a = "a"; a.insert(0, "b") },
        -> { a = "a"; a.prepend("b") },
        -> { a = "a"; a.force_encoding("BINARY") },
        -> { a = "a"; a.setbyte(0, 66) },
        -> { a = "a"; a.sub!("a", "b") },
        -> { a = "a"; a.gsub!("a", "b") },
        -> { a = "a"; a.tr!("a", "b") },
        -> { a = "a"; a.slice!(0) },
        -> { a = "a"; a.encode!("UTF-16LE") },
        -> { a = "a"; a.instance_variable_set(:@x, 1) },
        -> { a = "a"; a.freeze; p a.frozen? },
        -> { a = "a"; b = a.clone(freeze: false); b << "x" },
        -> { a = "a"; b = a.dup; b << "x" },
        -> { a = "a"; p a.frozen?; b = -a; p b.frozen? },
        -> { a = :sym.to_s; a << "!" },
        -> { a = :sym.name; p a.frozen? },
        -> { a = "a" "b"; a << "c" },
        -> { a = 'q'; a << "c" },
        -> { a = <<~X; a << "y" },
          text
        X
      ]
      .each_with_index { |f, i| $stderr.puts i; f.call }
      $VERBOSE = nil
      x = "v"
      x << "w"

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      false
      "abc"
      true
      true
      false
      true
      true
    OUT
    _(result.stderr).must_equal <<~'OUT'
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      core/string/a_chilled_literal_warns_on_its_first_change.rb:15: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      0
      core/string/a_chilled_literal_warns_on_its_first_change.rb:18: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      1
      core/string/a_chilled_literal_warns_on_its_first_change.rb:19: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      2
      core/string/a_chilled_literal_warns_on_its_first_change.rb:20: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      3
      core/string/a_chilled_literal_warns_on_its_first_change.rb:21: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      4
      core/string/a_chilled_literal_warns_on_its_first_change.rb:22: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      5
      core/string/a_chilled_literal_warns_on_its_first_change.rb:23: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      6
      core/string/a_chilled_literal_warns_on_its_first_change.rb:24: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      7
      core/string/a_chilled_literal_warns_on_its_first_change.rb:25: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      8
      core/string/a_chilled_literal_warns_on_its_first_change.rb:26: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      9
      core/string/a_chilled_literal_warns_on_its_first_change.rb:27: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      10
      core/string/a_chilled_literal_warns_on_its_first_change.rb:28: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      11
      core/string/a_chilled_literal_warns_on_its_first_change.rb:29: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      12
      core/string/a_chilled_literal_warns_on_its_first_change.rb:30: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      13
      14
      15
      16
      17
      core/string/a_chilled_literal_warns_on_its_first_change.rb:35: warning: string returned by :sym.to_s will be frozen in the future
      18
      19
      core/string/a_chilled_literal_warns_on_its_first_change.rb:37: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      20
      core/string/a_chilled_literal_warns_on_its_first_change.rb:38: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
      21
      core/string/a_chilled_literal_warns_on_its_first_change.rb:39: warning: literal string will be frozen in the future (run with --debug-frozen-string-literal for more information)
    OUT
  end

  it "a core string answers in us ascii" do
    result = ze0(<<~'RUBY')
      # The strings the core library builds from plain ASCII -- a number's
      # digits, nil's and true's names, an empty collection's inspect -- are
      # US-ASCII, not UTF-8, as rb_usascii_str_new makes them; a symbol's name
      # is US-ASCII when it is plain ASCII; the plain object form is binary.
      # Which encoding a string holds decides what joining it answers.
      rows = {
        "nil.to_s" => nil.to_s, "true.to_s" => true.to_s, "false.inspect" => false.inspect,
        "1.to_s" => 1.to_s, "(2**70).to_s" => (2**70).to_s, "1.5.to_s" => 1.5.to_s, "1.0.inspect" => 1.0.inspect,
        "1r.to_s" => 1r.to_s, "1i.inspect" => 1i.inspect, ":a.to_s" => :a.to_s, ":a.inspect" => :a.inspect,
        "nil.inspect" => nil.inspect, "[].inspect" => [].inspect, "[1].inspect" => [1].inspect, "{}.to_s" => {}.to_s,
        "(1..2).inspect" => (1..2).inspect, "Object.new.to_s" => Object.new.to_s, "Time.at(0).utc.to_s" => Time.at(0).utc.to_s,
        "3.chr" => 3.chr, "65.chr" => 65.chr, "255.chr" => 255.chr, "1.digits.inspect" => 1.digits.inspect,
        "12.to_s(2)" => 12.to_s(2), "format('%d', 1)" => format("%d", 1), "'%s' % 'a'" => "%s" % "a",
        "[1].join" => [1].join, "[].join" => [].join, "Integer.name" => Integer.name, "Comparable.to_s" => Comparable.to_s
      }
      rows.each { |label, value| puts "#{label}\t#{value.encoding}" }
      x = "a".b
      puts "joined\t#{"#{nil}#{x}".encoding} #{"#{1}#{x}".encoding} #{(1.to_s + "é").encoding} #{(+nil.to_s << "é".b).encoding}"

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil.to_s	US-ASCII
      true.to_s	US-ASCII
      false.inspect	US-ASCII
      1.to_s	US-ASCII
      (2**70).to_s	US-ASCII
      1.5.to_s	US-ASCII
      1.0.inspect	US-ASCII
      1r.to_s	US-ASCII
      1i.inspect	US-ASCII
      :a.to_s	US-ASCII
      :a.inspect	US-ASCII
      nil.inspect	US-ASCII
      [].inspect	US-ASCII
      [1].inspect	US-ASCII
      {}.to_s	US-ASCII
      (1..2).inspect	US-ASCII
      Object.new.to_s	ASCII-8BIT
      Time.at(0).utc.to_s	US-ASCII
      3.chr	US-ASCII
      65.chr	US-ASCII
      255.chr	ASCII-8BIT
      1.digits.inspect	US-ASCII
      12.to_s(2)	US-ASCII
      format('%d', 1)	UTF-8
      '%s' % 'a'	UTF-8
      [1].join	US-ASCII
      [].join	US-ASCII
      Integer.name	US-ASCII
      Comparable.to_s	US-ASCII
      joined	ASCII-8BIT ASCII-8BIT UTF-8 ASCII-8BIT
    OUT
  end

  it "a frozen literal follows the magic comment rules" do
    result = ze0(<<~'RUBY')
      # frozen-string-literal: TRUE
      # The magic comment reads as CRuby reads it: `-` and `_` alike, and the
      # value in any case. Adjacent strings and a heredoc with no
      # interpolation are literals too; an interpolated string is not.
      p "x".frozen?
      p ("a" "b").frozen?
      p <<~HEREDOC.frozen?
        heredoc
      HEREDOC
      p "i#{1}".frozen?
      p "same".equal?("same")
      p __FILE__.frozen?
      p %w[a b].all?(&:frozen?)

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      false
      true
      true
      true
    OUT
  end

  it "a frozen literal is one shared string" do
    result = ze0(<<~'RUBY')
      # `"lit".freeze` at any site answers the one frozen String the fstring
      # table holds for those bytes, as -"lit" and String#dedup do: the core
      # rows ruby defines on String itself leave the literal fast path alone.
      p "lit".freeze.equal?("lit".freeze), (-"lit").equal?(-"lit"), (-"lit").equal?("lit".freeze), "x".dedup.equal?("x".freeze)
      p nil === nil, [1].freeze.frozen?, "a".freeze.frozen?

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "a frozen string literal is not deduplicated" do
    result = ze0(<<~'RUBY')
      # `"lit".freeze` on a string LITERAL answers the interned fstring, so two of
      # them are the SAME object -- and CRuby REFUSES a singleton on one.
      #
      # The two halves ship together on purpose. Interning without the refusal would
      # let a program attach a singleton to a string another part of the program is
      # also holding, which is worse than the divergence it fixes.
      #
      # The rule is a COMPILE-TIME one about the literal RECEIVER, not about
      # `String#freeze`: CRuby compiles `<string literal>.freeze` to
      # `opt_str_freeze`, which answers the fstring table's entry. Freezing a string
      # that arrived any other way (`s = +"x"; s.freeze`) allocates nothing and
      # dedups nothing, on both engines.
      #
      # zeo already had the pool -- `String#-@` interns and `-"lit"` was correct --
      # so the fold routes a literal `.freeze` into the same entry the
      # `# frozen_string_literal: true` path already uses. It is guarded on `freeze`
      # not being reopened, exactly as CRuby guards `opt_str_freeze` on its own
      # redefinition flag.
      #
      # The refusal asks by object IDENTITY, not by a flag: the pool holds one
      # string per (bytes, encoding), so being interned means being THAT object.
      # All three singleton-CREATING surfaces refuse; the reading ones do not.
      p "lit".freeze.equal?("lit".freeze)
      p (-"lit").equal?(-"lit")
      p "lit".freeze.frozen?

      s = +"built"
      s.freeze
      p s.equal?("built".freeze)

      begin
        "lit".freeze.singleton_class
      rescue => e
        p [e.class, e.message]
      end

      t = +"unshared"
      t.freeze
      p t.singleton_class.equal?(t.singleton_class)

      # The sweep.

      # All three singleton-creating surfaces refuse; reading ones answer.
      f = "shared".freeze
      [[:singleton_class, -> { f.singleton_class }],
       [:define_singleton_method, -> { f.define_singleton_method(:x) { 1 } }],
       [:extend, -> { f.extend(Module.new) }],
       [:singleton_methods, -> { f.singleton_methods }],
       [:dup_then_singleton, -> { f.dup.singleton_class }]].each do |name, probe|
        begin
          p [name, probe.call.class]
        rescue => e
          p [name, e.class, e.message]
        end
      end

      # An interpolated literal is a fresh string every time: nothing to intern.
      x = 1
      p ["a#{x}b".freeze.equal?("a#{x}b".freeze), "a#{x}b".freeze.frozen?]

      # The fold answers the same object `-@` does -- one pool, not two.
      p "pool".freeze.equal?(-"pool")
      p "pool".freeze.equal?("pool".dup.freeze)

      # Mutating an fstring raises, and names it.
      begin
        "immutable".freeze << "x"
      rescue => e
        p [e.class, e.message]
      end

      # An empty literal and a literal holding a NUL byte both intern by content.
      p ["".freeze.equal?("".freeze), "a\0b".freeze.equal?("a\0b".freeze)]

      # Equal content in DIFFERENT encodings is not the same object.
      p "enc".freeze.equal?("enc".dup.force_encoding("ASCII-8BIT").freeze)

      # A frozen literal is still `==` to an unfrozen twin.
      p ["eq".freeze == +"eq", "eq".freeze.eql?(+"eq")]

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      false
      [TypeError, "can't define singleton"]
      true
      [:singleton_class, TypeError, "can't define singleton"]
      [:define_singleton_method, TypeError, "can't define singleton"]
      [:extend, TypeError, "can't define singleton"]
      [:singleton_methods, Array]
      [:dup_then_singleton, Class]
      [false, true]
      true
      false
      [FrozenError, "can't modify frozen String: \"immutable\""]
      [true, true]
      false
      [true, true]
    OUT
  end

  it "a plain string split goes straight to the kernel" do
    result = ze0(<<~'RUBY')
      # A split by a String pattern other than " " or "" with no limit takes
      # the kernel's path first; the answers agree with every other form.
      p "a,b,,c,,".split(",")
      p "a,b,,c,,".split(",", -1)
      p "a,b,,c,,".split(",", 2)
      p "a,b,,c,,".split(",", 0)
      p ",,".split(",")
      p "".split(",")
      p "abc".split(",")
      p "a--b--c".split("--")
      p " a  b ".split(" ")
      p "abc".split("")
      p "a,b".split(",", 1)
      p "a,b,c".split(",") { |x| print x.upcase }
      puts
      class Sep < String; end
      p "a;b;c".split(Sep.new(";"))
      p "a b".split(Sep.new(" "))
      p "x,y".split(",", 0.0)
      p "x,y".split(",", nil.to_a.size)
      p "a,b,c".split(",", 2 ** 70) rescue p $!.class
      p "ä,ö".split(",").map(&:encoding).uniq
      p "a,b".split(",".encode("UTF-16LE")) rescue p $!.class
      p "\xff,b".dup.force_encoding("UTF-8").split(",") rescue p $!.class
      p "a,b".split(",".b)
      p "a,b".split(:",") rescue p $!.class

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b", "", "c"]
      ["a", "b", "", "c", "", ""]
      ["a", "b,,c,,"]
      ["a", "b", "", "c"]
      []
      []
      ["abc"]
      ["a", "b", "c"]
      ["a", "b"]
      ["a", "b", "c"]
      ["a,b"]
      ABC"a,b,c"

      ["a", "b", "c"]
      ["a", "b"]
      ["x", "y"]
      ["x", "y"]
      RangeError
      [#<Encoding:UTF-8>]
      Encoding::CompatibilityError
      ArgumentError
      ["a", "b"]
      TypeError
    OUT
  end

  it "a scan over a long string takes linear time" do
    result = ze0(<<~'RUBY')
      # Each match's MatchData holds the text it matched. CRuby shares the
      # text's buffer with a frozen copy, so a match costs nothing for the
      # length of the text; here each match copies the whole of it, and a scan
      # over a long text is quadratic in its length.
      text = "ab " * 300_000
      p text.scan(/a/).size
      p text.gsub(/b/, "c").bytesize
      p text.split(/ /).size

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      300000
      900000
      300000
    OUT
  end

  it "a split on blanks goes straight to the kernel" do
    _(ze0(<<~'RUBY').stdout).must_equal "[\"a\", \"b\", \"c\"]\n[\"a\", \"b\", \"c\"]\n[\"a\", \"b\\tc\\n\"]\n[\"a\", \"b\", \"c\", \"\"]\n[]\n[]\n[\"a\"]\n[\"a\", \"\"]\n[\"a\", \"b\", \"\"]\nxyz\"x y z\"\n[\" a\", \"b\"]\n\n[\"a\", \"b\"]\n[\"a\\u0000b\", \"c\"]\n[\"a\", \"b c\"]\n[\"a\", \"b c\"]\n[\"a,b\", \"c\"]\n[\"a,b\", \"c\"]\n[#<Encoding:UTF-8>]\nArgumentError\none two three \n0\n\"kept\"\n\"one\\n\"\n\"one\\n\"\n0\n[\"a\", \"b\"]\n[\"a\\nb\"]\n"
      # A split with no pattern, or on " ", with no limit takes the kernel's
      # word scan; it agrees with the limit forms, `$;`, a block, tabs and
      # newlines, and IO#each_line counts `$.` without touching `$_`.
      p "  a  b\tc\n".split, "  a  b\tc\n".split(" "), "  a  b\tc\n".split(" ", 2), "  a  b\tc\n".split(" ", -1)
      p "".split, " ".split, "a".split, " a ".split(" ", 2), "a b ".split(" ", -1)
      p "x y z".split { |w| print w }, " a b".split
      puts
      class Sep < String; end
      p "a b".split(Sep.new(" ")), "a\0b c".split, "a,b c".split(",")
      $; = ","
      p "a,b c".split, "a,b c".split(" ")
      $; = nil
      p "a,b c".split
      p "ä ö".split.map(&:encoding).uniq, ("\xff a".dup.force_encoding("UTF-8").split rescue $!.class)
      require "stringio"
      io = StringIO.new("one\ntwo\nthree\n")
      $_ = "kept"
      io.each_line { |l| print l.chomp, " " }
      puts
      p $., $_
      io.rewind
      p io.gets, $_, $.
      p StringIO.new("a\nb").each_line(chomp: true).to_a, StringIO.new("a\nb").each_line("").to_a

    RUBY
  end

  it "a string eval builds its cref on the callers" do
    result = ze0(<<~'RUBY')
      # A string `class_eval`/`module_eval` builds its cref on the CALLER's
      # lexical chain -- CRuby pushes the receiver onto the cref of the frame the
      # call is written in, so a constant beside the CALL SITE resolves inside
      # the snippet. rss's dublincore writes `class DublinCoreTitle < Element`
      # in a module_eval string and Element lives two scopes out.
      module Outer
        class Element
          def self.tag = :outer_element
        end
        module Model; end
        Model.module_eval("p Module.nesting")
        Model.module_eval("class Kid < Element; end", __FILE__, __LINE__)
      end
      p Outer::Model::Kid.superclass
      p Outer::Model::Kid.tag

      module Outer
        module Deep
          Outer::Model.module_eval("p Module.nesting")
        end
      end

      def indirect_eval(mod, src)
        mod.class_eval(src)
      end
      module Outer
        module Deep
          E2 = Element
        end
      end
      p Outer::Deep.class_eval("E2") == Outer::Element

      # A method's OWN lexical scope is the cref an eval written in it uses,
      # wherever it is called from.
      module Outer
        module Deep
          def self.probe = Outer::Model.module_eval("Module.nesting")
        end
      end
      p Outer::Deep.probe
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [Outer::Model, Outer]
      Outer::Element
      :outer_element
      [Outer::Model, Outer::Deep, Outer]
      true
      [Outer::Model, Outer::Deep, Outer]
    OUT
  end

  it "a string pattern joins with its receiver" do
    result = ze0(<<~'RUBY')
      # A String argument at a search or a substitution site must join with
      # the receiver -- CRuby's rb_enc_check, the same test `+` makes. Without
      # it the argument's bytes are read under the receiver's encoding, so the
      # search quietly fails (or matches) where ruby raises.
      s = "日".encode("Shift_JIS")
      pat = "日".encode("EUC-JP")

      def show(name)
        p [name, yield]
      rescue Exception => e
        puts "#{name}: #{e.class}: #{e.message}"
      end

      show("gsub") { s.gsub(pat, "x") }
      show("sub") { s.sub(pat, "x") }
      show("index") { s.index(pat) }
      show("rindex") { s.rindex(pat) }
      show("byteindex") { s.byteindex(pat) }
      show("include?") { s.include?(pat) }
      show("start_with?") { s.start_with?(pat) }
      show("end_with?") { s.end_with?(pat) }
      show("split") { s.split(pat) }
      show("partition") { s.partition(pat) }
      show("rpartition") { s.rpartition(pat) }
      show("slice") { s[pat] }
      show("count") { s.count(pat) }
      show("delete") { s.delete(pat) }
      show("squeeze") { s.squeeze(pat) }
      show("tr") { s.tr(pat, "x") }
      show("plus") { s + pat }

      # Comparison makes no such test: two strings of different encodings are
      # simply unequal, and they still order.
      show("eq") { s == pat }
      show("eql") { s.eql?(pat) }
      show("cmp") { s <=> pat }

      # An ASCII-only argument joins with any ASCII-compatible receiver, so
      # these read the bytes and answer.
      show("ascii index") { s.index("x".encode("EUC-JP")) }
      show("ascii include?") { s.include?("x".encode("EUC-JP")) }
      show("ascii gsub") { s.gsub("x".encode("EUC-JP"), "y") }

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      gsub: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      sub: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      index: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      rindex: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      byteindex: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      include?: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      start_with?: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      end_with?: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      split: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      partition: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      rpartition: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      slice: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      count: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      delete: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      squeeze: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      tr: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      plus: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      ["eq", false]
      ["eql", false]
      ["cmp", -1]
      ["ascii index", nil]
      ["ascii include?", false]
      ["ascii gsub", "\x{93FA}"]
    OUT
  end

  it "a subclass sees only the calls ruby makes" do
    result = ze0(<<~'RUBY')
      # Which of String's own methods its methods call on a subclass: every
      # method String defines is wrapped to log a call made from inside another,
      # and each is then called once on a fresh receiver. CRuby calls one by
      # dispatch only where it means to, and ze0's core, written in Ruby, has
      # to call no more and no fewer. Written by tools/dispatch.rb.

      class Probe < String
        CALLING = []
        LOG = []
        [:%, :*, :+, :+@, :-@, :<, :<<, :<=, :<=>, :==, :===, :=~, :>, :>=, :[], :[]=, :append_as_bytes, :ascii_only?, :b, :between?, :byteindex, :byterindex, :bytes, :bytesize, :byteslice, :bytesplice, :capitalize, :capitalize!, :casecmp, :casecmp?, :center, :chars, :chomp, :chomp!, :chop, :chop!, :chr, :clamp, :clear, :codepoints, :concat, :count, :crypt, :dedup, :delete, :delete!, :delete_prefix, :delete_prefix!, :delete_suffix, :delete_suffix!, :downcase, :downcase!, :dump, :dup, :each_byte, :each_char, :each_codepoint, :each_grapheme_cluster, :each_line, :empty?, :encode, :encode!, :encoding, :end_with?, :eql?, :force_encoding, :freeze, :getbyte, :grapheme_clusters, :gsub, :gsub!, :hash, :hex, :include?, :index, :initialize_copy, :insert, :inspect, :intern, :length, :lines, :ljust, :lstrip, :lstrip!, :match, :match?, :next, :next!, :oct, :ord, :partition, :prepend, :replace, :reverse, :reverse!, :rindex, :rjust, :rpartition, :rstrip, :rstrip!, :scan, :scrub, :scrub!, :setbyte, :size, :slice, :slice!, :split, :squeeze, :squeeze!, :start_with?, :strip, :strip!, :sub, :sub!, :succ, :succ!, :sum, :swapcase, :swapcase!, :to_c, :to_f, :to_i, :to_r, :to_s, :to_str, :to_sym, :tr, :tr!, :tr_s, :tr_s!, :undump, :unicode_normalize, :unicode_normalize!, :unicode_normalized?, :unpack, :unpack1, :upcase, :upcase!, :upto, :valid_encoding?].each do |m|
          define_method(m) do |*args, &blk|
            LOG << "#{CALLING.last}->#{m}" unless CALLING.empty?
            CALLING << m
            begin
              super(*args, &blk)
            ensure
              CALLING.pop
            end
          end
          ruby2_keywords(m)
        end
      end

      def call(name)
        r = Probe.new(+"hello world")
        Probe::LOG.clear
        begin
          yield r
        rescue StandardError => e
          Probe::LOG << "raised #{e.class}"
        end
        puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
      end

      call("%") { |r| r.__send__(:%, 1) { |*x| x.first } }
      call("*") { |r| r.__send__(:*, 1) { |*x| x.first } }
      call("+") { |r| r.__send__(:+, "l") { |*x| x.first } }
      call("+@") { |r| r.__send__(:+@) { |*x| x.first } }
      call("-@") { |r| r.__send__(:-@) { |*x| x.first } }
      call("<") { |r| r.__send__(:<, "l") { |*x| x.first } }
      call("<<") { |r| r.__send__(:<<, 1) { |*x| x.first } }
      call("<=") { |r| r.__send__(:<=, "l") { |*x| x.first } }
      call("<=>") { |r| r.__send__(:<=>, 1) { |*x| x.first } }
      call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
      call("===") { |r| r.__send__(:===, 1) { |*x| x.first } }
      call("=~") { |r| r.__send__(:=~, /l/) { |*x| x.first } }
      call(">") { |r| r.__send__(:>, "l") { |*x| x.first } }
      call(">=") { |r| r.__send__(:>=, "l") { |*x| x.first } }
      call("[]") { |r| r.__send__(:[], 1) { |*x| x.first } }
      call("[]=") { |r| r.__send__(:[]=, "l", "L") { |*x| x.first } }
      call("append_as_bytes") { |r| r.append_as_bytes() { |*x| x.first } }
      call("ascii_only?") { |r| r.ascii_only?() { |*x| x.first } }
      call("b") { |r| r.b() { |*x| x.first } }
      call("between?") { |r| r.between?("l", "L") { |*x| x.first } }
      call("byteindex") { |r| r.byteindex("l") { |*x| x.first } }
      call("byterindex") { |r| r.byterindex("l") { |*x| x.first } }
      call("bytes") { |r| r.bytes() { |*x| x.first } }
      call("bytesize") { |r| r.bytesize() { |*x| x.first } }
      call("byteslice") { |r| r.byteslice(1) { |*x| x.first } }
      call("capitalize") { |r| r.capitalize() { |*x| x.first } }
      call("capitalize!") { |r| r.capitalize!() { |*x| x.first } }
      call("casecmp") { |r| r.casecmp(1) { |*x| x.first } }
      call("casecmp?") { |r| r.casecmp?(1) { |*x| x.first } }
      call("center") { |r| r.center(1) { |*x| x.first } }
      call("chars") { |r| r.chars() { |*x| x.first } }
      call("chomp") { |r| r.chomp() { |*x| x.first } }
      call("chomp!") { |r| r.chomp!() { |*x| x.first } }
      call("chop") { |r| r.chop() { |*x| x.first } }
      call("chop!") { |r| r.chop!() { |*x| x.first } }
      call("chr") { |r| r.chr() { |*x| x.first } }
      call("clear") { |r| r.clear() { |*x| x.first } }
      call("codepoints") { |r| r.codepoints() { |*x| x.first } }
      call("concat") { |r| r.concat() { |*x| x.first } }
      call("count") { |r| r.count("l") { |*x| x.first } }
      call("dedup") { |r| r.dedup() { |*x| x.first } }
      call("delete") { |r| r.delete("l") { |*x| x.first } }
      call("delete!") { |r| r.delete!("l") { |*x| x.first } }
      call("delete_prefix") { |r| r.delete_prefix("l") { |*x| x.first } }
      call("delete_prefix!") { |r| r.delete_prefix!("l") { |*x| x.first } }
      call("delete_suffix") { |r| r.delete_suffix("l") { |*x| x.first } }
      call("delete_suffix!") { |r| r.delete_suffix!("l") { |*x| x.first } }
      call("downcase") { |r| r.downcase() { |*x| x.first } }
      call("downcase!") { |r| r.downcase!() { |*x| x.first } }
      call("dump") { |r| r.dump() { |*x| x.first } }
      call("dup") { |r| r.dup() { |*x| x.first } }
      call("each_byte") { |r| r.each_byte() { |*x| x.first } }
      call("each_char") { |r| r.each_char() { |*x| x.first } }
      call("each_codepoint") { |r| r.each_codepoint() { |*x| x.first } }
      call("each_grapheme_cluster") { |r| r.each_grapheme_cluster() { |*x| x.first } }
      call("each_line") { |r| r.each_line() { |*x| x.first } }
      call("empty?") { |r| r.empty?() { |*x| x.first } }
      call("encode") { |r| r.encode() { |*x| x.first } }
      call("encode!") { |r| r.encode!() { |*x| x.first } }
      call("encoding") { |r| r.encoding() { |*x| x.first } }
      call("end_with?") { |r| r.end_with?() { |*x| x.first } }
      call("eql?") { |r| r.eql?(1) { |*x| x.first } }
      call("getbyte") { |r| r.getbyte(1) { |*x| x.first } }
      call("grapheme_clusters") { |r| r.grapheme_clusters() { |*x| x.first } }
      call("gsub") { |r| r.gsub(1) }
      call("gsub!") { |r| r.gsub!(1) }
      call("hash") { |r| r.hash() { |*x| x.first } }
      call("hex") { |r| r.hex() { |*x| x.first } }
      call("include?") { |r| r.include?("l") { |*x| x.first } }
      call("index") { |r| r.index("l") { |*x| x.first } }
      call("initialize_copy") { |r| r.initialize_copy("l") { |*x| x.first } }
      call("inspect") { |r| r.inspect() { |*x| x.first } }
      call("intern") { |r| r.intern() { |*x| x.first } }
      call("length") { |r| r.length() { |*x| x.first } }
      call("lines") { |r| r.lines() { |*x| x.first } }
      call("ljust") { |r| r.ljust(1) { |*x| x.first } }
      call("lstrip") { |r| r.lstrip() { |*x| x.first } }
      call("lstrip!") { |r| r.lstrip!() { |*x| x.first } }
      call("match") { |r| r.match("l") { |*x| x.first } }
      call("match?") { |r| r.match?("l") { |*x| x.first } }
      call("next") { |r| r.next() { |*x| x.first } }
      call("next!") { |r| r.next!() { |*x| x.first } }
      call("oct") { |r| r.oct() { |*x| x.first } }
      call("ord") { |r| r.ord() { |*x| x.first } }
      call("partition") { |r| r.partition("l") { |*x| x.first } }
      call("prepend") { |r| r.prepend() { |*x| x.first } }
      call("replace") { |r| r.replace("l") { |*x| x.first } }
      call("reverse") { |r| r.reverse() { |*x| x.first } }
      call("reverse!") { |r| r.reverse!() { |*x| x.first } }
      call("rindex") { |r| r.rindex("l") { |*x| x.first } }
      call("rjust") { |r| r.rjust(1) { |*x| x.first } }
      call("rpartition") { |r| r.rpartition("l") { |*x| x.first } }
      call("rstrip") { |r| r.rstrip() { |*x| x.first } }
      call("rstrip!") { |r| r.rstrip!() { |*x| x.first } }
      call("scan") { |r| r.scan("l") { |*x| x.first } }
      call("scrub") { |r| r.scrub() { |*x| x.first } }
      call("scrub!") { |r| r.scrub!() { |*x| x.first } }
      call("setbyte") { |r| r.setbyte(0, 1) { |*x| x.first } }
      call("size") { |r| r.size() { |*x| x.first } }
      call("slice") { |r| r.slice(1) { |*x| x.first } }
      call("slice!") { |r| r.slice!(1) { |*x| x.first } }
      call("split") { |r| r.split() { |*x| x.first } }
      call("squeeze") { |r| r.squeeze() { |*x| x.first } }
      call("squeeze!") { |r| r.squeeze!() { |*x| x.first } }
      call("start_with?") { |r| r.start_with?() { |*x| x.first } }
      call("strip") { |r| r.strip() { |*x| x.first } }
      call("strip!") { |r| r.strip!() { |*x| x.first } }
      call("sub") { |r| r.sub("l") { |*x| x.first } }
      call("sub!") { |r| r.sub!("l") { |*x| x.first } }
      call("succ") { |r| r.succ() { |*x| x.first } }
      call("succ!") { |r| r.succ!() { |*x| x.first } }
      call("sum") { |r| r.sum() { |*x| x.first } }
      call("swapcase") { |r| r.swapcase() { |*x| x.first } }
      call("swapcase!") { |r| r.swapcase!() { |*x| x.first } }
      call("to_c") { |r| r.to_c() { |*x| x.first } }
      call("to_f") { |r| r.to_f() { |*x| x.first } }
      call("to_i") { |r| r.to_i() { |*x| x.first } }
      call("to_r") { |r| r.to_r() { |*x| x.first } }
      call("to_s") { |r| r.to_s() { |*x| x.first } }
      call("to_str") { |r| r.to_str() { |*x| x.first } }
      call("to_sym") { |r| r.to_sym() { |*x| x.first } }
      call("tr") { |r| r.tr("l", "L") { |*x| x.first } }
      call("tr!") { |r| r.tr!("l", "L") { |*x| x.first } }
      call("tr_s") { |r| r.tr_s("l", "L") { |*x| x.first } }
      call("tr_s!") { |r| r.tr_s!("l", "L") { |*x| x.first } }
      call("unicode_normalize") { |r| r.unicode_normalize() { |*x| x.first } }
      call("unicode_normalize!") { |r| r.unicode_normalize!() { |*x| x.first } }
      call("unicode_normalized?") { |r| r.unicode_normalized?() { |*x| x.first } }
      call("unpack") { |r| r.unpack("l") { |*x| x.first } }
      call("unpack1") { |r| r.unpack1("l") { |*x| x.first } }
      call("upcase") { |r| r.upcase() { |*x| x.first } }
      call("upcase!") { |r| r.upcase!() { |*x| x.first } }
      call("upto") { |r| r.upto(1) }
      call("valid_encoding?") { |r| r.valid_encoding?() { |*x| x.first } }

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      <: <-><=>
      <=: <=-><=>
      >: >-><=>
      >=: >=-><=>
      between?: between?-><=>
      dup: dup->initialize_copy
      initialize_copy: raised NoMethodError
      unicode_normalize: unicode_normalize->encoding unicode_normalize->gsub
      unicode_normalize!: unicode_normalize!->encoding unicode_normalize!->gsub
      unicode_normalized?: unicode_normalized?->encoding unicode_normalized?->scan
    OUT
  end

  it "alias attr reader source" do
    result = ze0(<<~'RUBY')
      # `alias`/`alias_method` may name an attr_reader/attr_accessor-generated
      # method as the source. The new name then reads the same backing ivar,
      # carrying the ivar's inferred type (so typed uses like upcase work).
      class Token
        attr_reader :access_token
        attr_accessor :scope
        alias value access_token
        alias_method :token2, :access_token
        alias scope_alias scope

        def initialize
          @access_token = "tok"
          @scope = "read"
        end
      end

      t = Token.new
      puts t.value
      puts t.token2
      puts t.value.upcase          # type must propagate: string method
      puts "#{t.value}!"           # interpolation
      puts t.scope_alias

      # Aliasing an inherited attr_reader from the parent class.
      class Base
        attr_reader :name
        def initialize(n)
          @name = n
        end
      end

      class Derived < Base
        alias title name
      end

      d = Derived.new("spinel")
      puts d.title
      puts d.title.upcase
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      tok
      tok
      TOK
      tok!
      read
      spinel
      SPINEL
    OUT
  end

  it "alias supports the symbol spelling of both names" do
    _(ze0(<<~'RUBY').stdout).must_equal "hi\n"
      class Greeter
        def hello
          "hi"
        end
        alias :bonjour :hello
      end
      puts Greeter.new.bonjour
    RUBY
  end

  it "amp sym in string literals" do
    result = ze0(<<~'RUBY')
      s = "count(&:alive)"
      puts s
      puts s.length
      puts(s == "count(&:alive)")
      h = <<~EOS
        filter(&:active) and .send(:reload)
      EOS
      puts h
      puts h.length
      t = 'single &:quoted'
      puts t
      puts "interp works: #{[1, 2].map(&:to_s).join(",")}"
      puts %w[&:a &:b].join(" ")
      puts "obj.send(:name)"
      # comment with &:ignored and .send(:ignored)
      d = <<~'SQL'
        SELECT count(&:x) .send(:y)
      SQL
      puts d
      puts [3, 1, 2].sort_by(&:abs).inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      count(&:alive)
      14
      true
      filter(&:active) and .send(:reload)
      36
      single &:quoted
      interp works: 1,2
      &:a &:b
      obj.send(:name)
      SELECT count(&:x) .send(:y)
      [1, 2, 3]
    OUT
  end

  it "an armed each line streams a pipe the writer fills incrementally" do
    _(ze0(<<~'RUBY', env: {"ZEO_GVL" => "1"}).stdout).must_equal "[\"alpha\", \"beta\"]\n"
      # each_line re-enters the with_file seam once per line, so the
      # consumer parks BETWEEN lines while main wakes to write the next
      # one; the closed write end ends the stream.

      r, w = IO.pipe
      lines = []
      t = Thread.new { r.each_line { |l| lines << l.chomp } }
      sleep 0.1
      w.puts "alpha"
      sleep 0.1
      w.puts "beta"
      w.close
      t.join
      p lines
      r.close
    RUBY
  end

  it "an attr writer from a block loses to a later def" do
    result = ze0(<<~'RUBY')
      class C
        attr_writer :x
        def x=(v)
          @x = [v, v]
        end
        attr_reader :x
      end
      c = C.new
      c.x = 1
      p c.x

      class D
        [:y].each { |a| attr_writer(a) }
        def y=(v)
          @y = [v, v]
        end
        attr_reader :y
      end
      d = D.new
      d.y = 2
      p d.y

      class E
        %i[z].each { |a| attr_accessor(a) }
        def z = 9
      end
      p E.new.z

      class F
        def self.make(n) = attr_writer(n)
        make :w
        def w=(v)
          @w = [v]
        end
        attr_reader :w
      end
      f = F.new
      f.w = 3
      p f.w
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [1, 1]
      [2, 2]
      9
      [3]
    OUT
  end

  it "an element assignment splices in place" do
    result = ze0(<<~'RUBY')
      s = +"héllo wörld"
      s[1] = "E"; p s
      s[0, 3] = "日本"; p s, s.encoding, s.valid_encoding?
      s[-5..] = "!"; p s
      s["!"] = "?!?"; p s
      begin; s[/(ll)/, 1] = "LL"; rescue => e; p e.class; end
      p s
      t = +"abc"; t[1, 1] = t; p t
      u = +"x"; 20.times { |i| u[u.bytesize, 0] = "ab#{i}" }; p u, u.bytesize
      b = ("\0" * 16).b; b[4, 4] = [0xdeadbeef].pack("L<"); p b.bytes
      begin; b[0, 0] = "é"; p b.encoding, b.bytesize; rescue => e; p e.class; end
      ascii = +"plain"; ascii[0] = "ü"; p ascii, ascii.encoding
      begin; "frozen".freeze[0] = "x"; rescue => e; p e.class; end
      begin; bin = "\xff".b.dup; bin[0, 0] = "é"; p bin, bin.encoding; rescue => e; p e.class, e.message; end
      begin; x = +"é"; x[0, 0] = "\xff".b; p x; rescue => e; p e.class, e.message; end
      v = +"hello"; p v.insert(2, "XY"), v.insert(-1, "!"), v.insert(0, v)
      w = +"abc"; w[3, 0] = "d"; w[1, 5] = ""; p w
      begin; (+"ab")[5] = "x"; rescue => e; p e.class, e.message; end
      e = "".encode("UTF-16LE"); e[0, 0] = "a".encode("UTF-16LE"); p e.bytes


    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hEllo wörld"
      "日本lo wörld"
      #<Encoding:UTF-8>
      true
      "日本lo !"
      "日本lo ?!?"
      IndexError
      "日本lo ?!?"
      "aabcc"
      "xab0ab1ab2ab3ab4ab5ab6ab7ab8ab9ab10ab11ab12ab13ab14ab15ab16ab17ab18ab19"
      71
      [0, 0, 0, 0, 239, 190, 173, 222, 0, 0, 0, 0, 0, 0, 0, 0]
      Encoding::CompatibilityError
      "ülain"
      #<Encoding:UTF-8>
      FrozenError
      Encoding::CompatibilityError
      "incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8"
      Encoding::CompatibilityError
      "incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)"
      "heXYllo!heXYllo!"
      "heXYllo!heXYllo!"
      "heXYllo!heXYllo!"
      "a"
      IndexError
      "index 5 out of string"
      [97, 0]
    OUT
  end

  it "an eval string defines a module" do
    result = ze0(<<~'RUBY')
      # `eval` of a literal string that defines a `class`/`module`. At the TOP LEVEL
      # zeo parses the snippet at compile time and inlines it, so the definition is
      # ordinary; inside a METHOD body it falls through to the runtime eval VM,
      # which had no constant-write node -- `WHO = "made"` was the whole refusal,
      # not the `module` the gap header blamed.
      #
      # The second half is the cref: an eval'd `def self.hi` reading a bare constant
      # resolves against the module it was DEFINED into. Deriving that from the
      # receiver answers `Module`, which knows none of the module's constants.
      def make
        eval('module Made
          WHO = "made"
          INNER = [WHO, 1].freeze
          def self.hi = "made hi #{WHO}"
          class Deep
            D = :d
          end
        end')
      end

      make
      p [Made::WHO, Made.hi, Made.class]
      p [Made::INNER, Made::Deep::D, Made.const_get(:WHO)]
      p Made.constants.sort

      # A reopen from a second eval adds to the same module.
      def more
        eval('module Made
          SECOND = 2
        end')
      end
      more
      p [Made::SECOND, Made.constants.sort]

      # A scoped write, and the value an assignment answers.
      module Ns; end
      def scoped
        eval('Ns::SCOPED = 3')
      end
      p [scoped, Ns::SCOPED]

      # ...and the top-level form, which the compile-time path already covered.
      class Base
        def hi = "base"
      end

      eval('class Derived < Base
        def hi = "derived (#{super})"
      end')
      p Derived.new.hi
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["made", "made hi made", Module]
      [["made", 1], :d, "made"]
      [:Deep, :INNER, :WHO]
      [2, [:Deep, :INNER, :SECOND, :WHO]]
      [3, 3]
      "derived (base)"
    OUT
  end

  it "an extended attr accessor override wins" do
    result = ze0(<<~'RUBY')
      module Macros
        def attr_accessor(name)
          puts "macro attr_accessor #{name}"
          define_method(name) { 42 }
        end
      end

      class Direct
        extend Macros
        attr_accessor :alpha
      end
      p Direct.new.alpha
      p Direct.instance_methods(false).sort

      module ViaHook
        def self.included(mod) = mod.extend(Macros)
      end

      class Hooked
        include ViaHook
        attr_accessor :beta
      end
      p Hooked.new.beta
      p Hooked.instance_methods(false).sort

      module Silencer
        def attr_reader(*) = nil
      end

      class Silent
        extend Silencer
        attr_reader :gamma
      end
      p Silent.instance_methods(false).sort

      module Typed
        def attr_accessor(name, type: nil)
          define_method(name) { type }
        end
      end

      class Coerced
        extend Typed
        attr_accessor :delta, type: Integer
      end
      p Coerced.new.delta
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      macro attr_accessor alpha
      42
      [:alpha]
      macro attr_accessor beta
      42
      [:beta]
      []
      Integer
    OUT
  end

  it "an interpolated alias installs at runtime" do
    result = ze0(<<~'RUBY')
      # The `alias` KEYWORD with an interpolated symbol -- `alias :"#{kind}_attr"
      # :"#{kind}_attrs"` -- has no compile-time spelling, but it is still just a
      # runtime install on the default definee, in class-body order.
      #
      # zeo required a plain symbol and refused the whole file ("`alias`'s target
      # must be a plain method name") -- formal_wear builds its DSL in exactly
      # this loop.
      class Suit
        def tie_attrs
          ["windsor"]
        end

        kind = "tie"
        alias :"#{kind}_attr" :"#{kind}_attrs"
      end

      puts Suit.new.tie_attr.inspect

      # Top level: the same install onto Object.
      def given
        "given!"
      end

      adverb = "when"
      alias :"#{adverb}_step" :given
      puts when_step
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["windsor"]
      given!
    OUT
  end

  it "an interpolated undef is a runtime tombstone" do
    result = ze0(<<~'RUBY')
      # `undef :"#{name}"` (immutable_struct_ex strips Struct writers in a loop)
      # has no compile-time spelling: it desugars to a runtime `undef_method` on
      # the default definee, in class-body order.
      class Wardrobe
        def hat; "hat"; end
        def hat=(_v); end
        def coat; "coat"; end
        def coat=(_v); end

        %w[hat coat].each do |piece|
          undef :"#{piece}="
        end
      end

      w = Wardrobe.new
      p w.hat
      p w.coat
      begin
        w.hat = 1
      rescue NoMethodError => e
        puts "writer gone: #{e.class}"
      end
      p w.respond_to?(:coat=)

      # Inside instance_eval on a singleton (the immutable_struct_ex shape), and
      # mixed with a plain name in one statement.
      class Locker
        def a; :a; end
        def b; :b; end
        def c; :c; end
        gone = "b"
        undef :a, :"#{gone}"
      end
      l = Locker.new
      p l.c
      p l.respond_to?(:a)
      p l.respond_to?(:b)
      puts "still running"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hat"
      "coat"
      writer gone: NoMethodError
      false
      :c
      false
      false
      still running
    OUT
  end

  it "an io buffer reads and writes bytes in place" do
    _(ze0(<<~'RUBY').stdout).must_equal "Integer\n65536\n[1, 2, 4, 8, 32, 64, 128]\n[4, 8, 4, 8]\n1\n12\n[8, false, true, false, true, false]\n4660\n\"\\x124\\x00\\x00\\x00\\x00\\x00\\x00\"\n\"#<IO::Buffer 0xADDR+8 INTERNAL>\"\n\"#<IO::Buffer 0xADDR+8 INTERNAL>\\n0xADDR  12 34 00 00 00 00 00 00                         .4......\"\n\"hi\"\n\"\\x124\"\nString\n[6, true, true, \"abcdef\"]\n[IO::Buffer::AccessError, \"Buffer is not writable!\"]\n[false, \"Zbcdef\"]\n\"Zbcdef\"\n\"xyz\"\n[[18, 52]]\n\"\\x00\\x00\\x00\\x00\"\n[7, 7]\n[ArgumentError, \"Type extends beyond end of buffer! (offset=5 > size=2)\"]\n[RuntimeError, RuntimeError, RuntimeError, RuntimeError, ArgumentError]\nObject\nU8=1 S8=1 U16=2 S16=2 U32=4 S32=4 U64=8 S64=8 u16=2 s16=2 u32=4 s32=4 u64=8 s64=8 F32=4 F64=8 f32=4 f64=8 \n[52, 18]\n-1\n1.5\n[1.5, [0, 0, 192, 63]]\n[0, 0, 0, 0]\n[[0, 0], [1, 0], [2, 0], [3, 0]]\ntrue\n\"bc\"\n-1\n[15, 0]\n[ArgumentError, \"Invalid type name!\"]\n[IO::Buffer::AccessError, \"Cannot resize external buffer!\"]\n[true, 0]\n"
      # IO::Buffer is a window on bytes: its own, or a String's. A buffer made
      # `for` a String reads and writes that String's bytes in place, which is
      # what ruby means by locking the string for the block. Addresses in the
      # report are the object's, so this file scrubs them.
      $stderr.reopen(IO::NULL)
      p IO::Buffer::PAGE_SIZE.class
      p IO::Buffer::DEFAULT_SIZE
      p [IO::Buffer::EXTERNAL, IO::Buffer::INTERNAL, IO::Buffer::MAPPED, IO::Buffer::SHARED, IO::Buffer::LOCKED, IO::Buffer::PRIVATE, IO::Buffer::READONLY]
      p [IO::Buffer::LITTLE_ENDIAN, IO::Buffer::BIG_ENDIAN, IO::Buffer::HOST_ENDIAN, IO::Buffer::NETWORK_ENDIAN]
      p IO::Buffer.size_of(:U8)
      p IO::Buffer.size_of([:U32, :F64])
      b = IO::Buffer.new(8)
      p [b.size, b.external?, b.internal?, b.readonly?, b.valid?, b.empty?]
      b.set_value(:U16, 0, 0x1234)
      p b.get_value(:U16, 0)
      p b.get_string
      p b.to_s
      p b.inspect.sub(/0x\h{16}/, "0xADDR")
      b.set_string("hi", 4)
      p b.get_string(4, 2)
      p b.slice(0, 2).get_string
      p b.hexdump.class
      s = +"abcdef"
      v = IO::Buffer.for(s)
      p [v.size, v.readonly?, v.external?, v.get_string]
      begin; v.set_value(:U8, 0, 65); rescue => e; p [e.class, e.message]; end
      IO::Buffer.for(s) { |w| w.set_value(:U8, 0, 90); p [w.readonly?, s] }
      p s
      p IO::Buffer.string(3) { |w| w.set_string("xyz") }
      p [b.get_values([:U8, :U8], 0)]
      c = IO::Buffer.new(4)
      b.copy(c, 0, 4)
      p c.get_string
      p IO::Buffer.new(2).clear(7).get_string.bytes
      begin; IO::Buffer.new(2).get_value(:U8, 5); rescue => e; p [e.class, e.message]; end
      p [IO::Buffer::AccessError.superclass, IO::Buffer::AllocationError.superclass, IO::Buffer::InvalidatedError.superclass, IO::Buffer::LockedError.superclass, IO::Buffer::MaskError.superclass]
      p IO::Buffer.superclass
      b = IO::Buffer.new(8)
      %i[U8 S8 U16 S16 U32 S32 U64 S64 u16 s16 u32 s32 u64 s64 F32 F64 f32 f64].each { |t| print t, "=", IO::Buffer.size_of(t), " " }
      puts
      b.set_value(:u16, 0, 0x1234); p b.get_string(0, 2).bytes
      b.set_value(:S8, 0, -1); p b.get_value(:S8, 0)
      b.set_value(:F64, 0, 1.5); p b.get_value(:F64, 0)
      b.set_value(:f32, 0, 1.5); p [b.get_value(:f32, 0), b.get_string(0,4).bytes]
      p IO::Buffer.new(4).values(:U8, 0)
      p IO::Buffer.new(4).each(:U8, 0).to_a
      p IO::Buffer.new(0).empty?
      p IO::Buffer.for("abc").slice(1).get_string
      p IO::Buffer.for("abc") <=> IO::Buffer.for("abd")
      d = IO::Buffer.new(2); d.set_string("\x0f\xf0".b); p (d & IO::Buffer.for("\xff\x00".b)).get_string.bytes
      begin; IO::Buffer.new(2).set_value(:BAD, 0, 1); rescue => e; p [e.class, e.message]; end
      begin; IO::Buffer.for("x").resize(4); rescue => e; p [e.class, e.message]; end
      e2 = IO::Buffer.new(2); e2.free; p [e2.null?, e2.size]
      begin; e2.get_string; rescue => e; p [e.class, e.message]; end
    RUBY
  end

  it "appends and splices keep what a scan found only while it holds" do
    result = ze0(<<~'RUBY')
      # `<<` and `bytesplice` keep a String's known-ASCII state across a change
      # of plain ASCII, and lose it for a byte past ASCII: ascii_only?, index
      # and the encoding answer from the bytes as they are after each change.
      def show(label)
        v = yield
        v = [v, v.encoding, v.ascii_only?, v.valid_encoding?] if v.is_a?(String)
        puts "#{label}: #{v.inspect}"
      rescue => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      s = +"abc".b
      s.ascii_only?
      show("binary << binary past ASCII") { s << "\xFF".b }
      t = +"abc".b
      t.ascii_only?
      show("binary << UTF-8 ASCII") { t << "de" }
      show("then << UTF-8 past ASCII") { t << "é" }
      u = +"abc"
      u.ascii_only?
      show("UTF-8 << é") { u << "é" }
      show("index after it") { u.index("é") }
      v = +"héllo"
      show("index from a character") { v.index("l", 3) }
      show("rindex") { v.rindex("l") }
      w = +"abc".b
      w.ascii_only?
      w << "x".b
      w << "\x80".b
      show("two appends") { [w.ascii_only?, w.index("\x80".b)] }
      long = +""
      2000.times { |i| long << "n#{i}".b << "\0" }
      show("a long join") { [long.bytesize, long.encoding, long.ascii_only?, long.index("n1999"), long.count("\0")] }

      show("splice itself at the head") { x = +"abcdef"; x.bytesplice(0, 1, x) }
      show("splice itself in the middle") { x = +"abcdef"; x.bytesplice(2, 3, x) }
      show("splice a range") { x = +"hello"; x.bytesplice(1..2, "EE") }
      show("splice past ASCII into ASCII") { x = +"hello"; x.ascii_only?; x.bytesplice(1, 1, "é") }
      show("index after that splice") { x = +"hello"; x.ascii_only?; x.bytesplice(1, 1, "é"); x.index("l") }
      show("splice binary into UTF-8") { x = +"hello"; x.bytesplice(1, 1, "\xFF".b) }
      show("splice UTF-8 into binary past ASCII") { x = +"h\xFFllo".b; x.bytesplice(0, 1, "é") }
      show("splice binary ASCII into UTF-8") { x = +"héllo"; x.bytesplice(0, 1, "Z".b) }
      show("splice inside a character") { x = +"héllo"; x.bytesplice(2, 1, "Z") }
      show("splice a frozen String") { "abc".freeze.bytesplice(0, 1, "Z") }
      show("splice part of the text") { x = +"hello"; x.bytesplice(0, 1, "WXYZ", 1, 2) }
      show("splice that grows") { x = +"ab"; x.bytesplice(1, 0, "0123456789" * 20); [x.bytesize, x.ascii_only?] }
      show("many splices then index") { x = +("abcdefgh" * 50); x.ascii_only?; 50.times { |i| x.bytesplice(i * 8, 1, "Z") }; [x.index("Zb", 390), x.count("Z")] }

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      binary << binary past ASCII: ["abc\xFF", #<Encoding:BINARY (ASCII-8BIT)>, false, true]
      binary << UTF-8 ASCII: ["abcde", #<Encoding:BINARY (ASCII-8BIT)>, true, true]
      then << UTF-8 past ASCII: ["abcdeé", #<Encoding:UTF-8>, false, true]
      UTF-8 << é: ["abcé", #<Encoding:UTF-8>, false, true]
      index after it: 3
      index from a character: 3
      rindex: 3
      two appends: [false, 4]
      a long join: [10890, #<Encoding:UTF-8>, true, 10884, 2000]
      splice itself at the head: ["abcdefbcdef", #<Encoding:UTF-8>, true, true]
      splice itself in the middle: ["ababcdeff", #<Encoding:UTF-8>, true, true]
      splice a range: ["hEElo", #<Encoding:UTF-8>, true, true]
      splice past ASCII into ASCII: ["héllo", #<Encoding:UTF-8>, false, true]
      index after that splice: 2
      splice binary into UTF-8: ["h\xFFllo", #<Encoding:BINARY (ASCII-8BIT)>, false, true]
      splice UTF-8 into binary past ASCII: Encoding::CompatibilityError: incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8
      splice binary ASCII into UTF-8: ["Zéllo", #<Encoding:UTF-8>, false, true]
      splice inside a character: IndexError: offset 2 does not land on character boundary
      splice a frozen String: FrozenError: can't modify frozen String: "abc"
      splice part of the text: ["XYello", #<Encoding:UTF-8>, true, true]
      splice that grows: [202, true]
      many splices then index: [392, 50]
    OUT
  end

  it "array frozen slice bang" do
    result = ze0(<<~'RUBY')
      # Array#slice! must raise FrozenError on a frozen array (Gemini
      # follow-up to #1029: slice! was the remaining unguarded mutator).
      a = [1, 2, 3]
      a.freeze
      begin
        a.slice!(0, 1)
        puts "BUG: no raise"
      rescue FrozenError
        puts "int slice!"
      end

      s = ["a", "b", "c"]
      s.freeze
      begin
        s.slice!(1, 1)
        puts "BUG: no raise"
      rescue FrozenError
        puts "str slice!"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      int slice!
      str slice!
    OUT
  end

  it "array op assign concat" do
    result = ze0(<<~'RUBY')
      # `arr += other` on a typed array local — operator-assignment with `+`,
      # which is `arr = arr + other` (a fresh concatenation). Previously only
      # Int/Float/String/object locals had an op-assign path; a typed array
      # local fell through to "unsupported operator assignment". `<<` and
      # `concat` already worked; this covers `+=`.
      a = [1, 2]
      a += [3, 4]
      p a

      s = ["a"]
      s += ["b", "c"]
      p s

      f = [1.5]
      f += [2.5, 3.5]
      p f

      # genuinely heterogeneous (poly) array
      h = [1, "a", :sym]
      h += [2, "b"]
      p h

      # empty-literal RHS (must not build a wrong-kind array)
      e = [1, 2]
      e += []
      p e

      # poly array from a method whose element type the compiler widens
      def ids
        r = []
        r << "x"
        r
      end
      q = ids
      q += ids
      puts q.length
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [1, 2, 3, 4]
      ["a", "b", "c"]
      [1.5, 2.5, 3.5]
      [1, "a", :sym, 2, "b"]
      [1, 2]
      2
    OUT
  end

  it "array product block sample and each slice return" do
    result = ze0(<<~'RUBY')
      # product's block form yields each tuple and returns self; sample(-n) has
      # its own message; each_slice/each_cons block forms return the receiver.

      r = []
      ret = [1, 2].product([3, 4]) { |t| r << t }
      p r
      p ret
      p([1, 2, 3].each_slice(2) { |s| })
      p([1, 2, 3].each_cons(2) { |s| })
      begin
        [1, 2].sample(-1)
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [1, 2]
      [1, 2, 3]
      [1, 2, 3]
      "negative sample number"
    OUT
  end

  it "array slice bang" do
    result = ze0(<<~'RUBY')
      # Array#slice!(from, n) on every typed array. Returns a fresh
      # array of n elements starting at `from`, and mutates the receiver
      # to remove them. IntArray uses its `start` field for an O(1) head
      # peel; the others shift the tail down to fill the hole.

      # --- IntArray: head peel (from == 0) ---
      arr = [10, 20, 30, 40, 50]
      head = arr.slice!(0, 2)
      puts head.length        # 2
      puts head[0]            # 10
      puts head[1]            # 20
      puts arr.length         # 3
      puts arr[0]             # 30

      # --- IntArray: middle slice (from > 0, tail shift) ---
      arr2 = [1, 2, 3, 4, 5, 6, 7]
      mid = arr2.slice!(2, 3)
      puts mid[0]             # 3
      puts mid[2]             # 5
      puts arr2.length        # 4
      puts arr2[2]            # 6 (tail shifted down)
      puts arr2[3]            # 7

      # --- IntArray: n > available, clamped ---
      arr3 = [100, 200, 300]
      big = arr3.slice!(1, 999)
      puts big.length         # 2
      puts arr3.length        # 1

      # --- FloatArray ---
      fa = [1.5, 2.5, 3.5, 4.5, 5.5]
      fh = fa.slice!(0, 2)
      puts fh.length          # 2
      puts fh[0]              # 1.5
      puts fa.length          # 3
      puts fa[0]              # 3.5

      # --- StrArray ---
      sa = ["a", "b", "c", "d", "e"]
      sh = sa.slice!(1, 2)
      puts sh.length          # 2
      puts sh[0]              # b
      puts sh[1]              # c
      puts sa.length          # 3
      puts sa[0]              # a
      puts sa[1]              # d (tail shifted down)
      puts sa[2]              # e

      # --- SymArray (shares the IntArray helper internally) ---
      syms = [:foo, :bar, :baz, :qux]
      sym_h = syms.slice!(0, 2)
      puts sym_h.length       # 2
      puts sym_h[0]           # foo
      puts syms.length        # 2
      puts syms[0]            # baz
      puts syms[1]            # qux

      # --- PtrArray (array of obj_X instances) ---
      class Box
        attr_reader :v
        def initialize(v); @v = v; end
      end

      pa = [Box.new(10), Box.new(20), Box.new(30), Box.new(40)]
      ph = pa.slice!(1, 2)
      puts ph.length          # 2
      puts ph[0].v            # 20
      puts ph[1].v            # 30
      puts pa.length          # 2
      puts pa[0].v            # 10
      puts pa[1].v            # 40 (tail shifted down)

      # --- PolyArray (heterogeneous literal) ---
      poly = [1, "two", :three, 4.5, "five"]
      poly_h = poly.slice!(1, 3)
      puts poly_h.length      # 3
      puts poly_h[0]          # two
      puts poly_h[2]          # 4.5
      puts poly.length        # 2
      puts poly[0]            # 1
      puts poly[1]            # five
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      2
      10
      20
      3
      30
      3
      5
      4
      6
      7
      2
      1
      2
      1.5
      3
      3.5
      2
      b
      c
      3
      a
      d
      e
      2
      foo
      2
      baz
      qux
      2
      20
      30
      2
      10
      40
      3
      two
      4.5
      2
      1
      five
    OUT
  end

  it "array slice bang bounds" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Array#slice! past the end answers [] where ruby answers nil.
      #
      a = [1, 2, 3]
      p a.slice!(1, -1)
      p a
      b = [1, 2, 3]
      p b.slice!(..1)
      p b
      c = [1, 2, 3]
      p c.slice!(9, 2)
      d = [1, 2, 3]
      p d.slice!(0..1)
      p d
      e = [1, 2, 3]
      p e.slice!(1..)
      p e
      f = ["x", "y", "z"]
      p f.slice!(..0)
      p f
      g = [1, 2, 3]
      p g.slice!(0, -2)
      p g
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      [1, 2, 3]
      [1, 2]
      [3]
      nil
      [1, 2]
      [3]
      [2, 3]
      [1]
      ["x"]
      ["y", "z"]
      nil
      [1, 2, 3]
    OUT
  end

  it "array slice bang out of range" do
    result = ze0(<<~'RUBY')
      # slice!(start, len) with a start past the end is nil, not an empty slice --
      # only start == length answers []. The start was clamped to the length, so
      # every out-of-range call answered [].
      a=[1,2,3]; p a.slice!(9,2); p a
      b=[1,2,3]; p b.slice!(3,2); p b
      c=[1,2,3]; p c.slice!(1,2); p c
      d=[1,2,3]; p d.slice!(-1,1); p d
      e=[1,2,3]; p e.slice!(1,0); p e
      f=["a","b"]; p f.slice!(9,1); p f
      g=[1,:x]; p g.slice!(9,1); p g
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      [1, 2, 3]
      []
      [1, 2, 3]
      [2, 3]
      [1]
      [3]
      [1, 2]
      []
      [1, 2, 3]
      nil
      ["a", "b"]
      nil
      [1, :x]
    OUT
  end

  it "array slice before after" do
    result = ze0(<<~'RUBY')
      # Array#slice_before / #slice_after on int_array with a literal
      # int delimiter.
      puts [1, 2, 3, 4, 5].slice_before(3).to_a.inspect
      puts [1, 2, 3, 4, 5].slice_after(3).to_a.inspect
      # Empty matches: delimiter never appears.
      puts [1, 2, 3].slice_before(99).to_a.inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1, 2], [3, 4, 5]]
      [[1, 2, 3], [4, 5]]
      [[1, 2, 3]]
    OUT
  end

  it "array slice sample methods" do
    result = ze0(<<~'RUBY')
      # Array slicing/sampling coverage: rotate(n), slice(start, len) / [start, len],
      # sample(n), and the n-arg min(n)/max(n) forms across the typed-array kinds and
      # poly arrays. Receivers are routed through per-type method params so each stays
      # a concrete typed array (a shared param would widen to poly), exercising the
      # runtime builtin path rather than constant folding.
      def ints(a); a; end
      def strs(a); a; end
      def flts(a); a; end
      def polys(a); a; end

      # rotate: non-mutating, wraps around, negative counts rotate right
      p ints([1, 2, 3, 4, 5]).rotate(2)
      p ints([1, 2, 3, 4, 5]).rotate
      p ints([1, 2, 3, 4, 5]).rotate(-1)
      p strs(%w[a b c d]).rotate(1)
      p polys([1, :b, "c", 4]).rotate(2)

      # the receiver is left unmodified by the non-mutating rotate
      orig = ints([1, 2, 3])
      orig.rotate(1)
      p orig

      # slice(start, len) and the equivalent [start, len]
      p ints([1, 2, 3, 4, 5]).slice(1, 3)
      p ints([1, 2, 3, 4, 5])[1, 3]
      p strs(%w[a b c d e]).slice(2, 2)
      p polys([1, :b, "c", 4]).slice(1, 2)

      # min(n) / max(n): n smallest ascending, n largest descending
      p ints([3, 1, 4, 1, 5, 9, 2]).min(3)
      p ints([3, 1, 4, 1, 5, 9, 2]).max(2)
      p flts([1.5, 0.5, 2.5]).min(2)
      p strs(%w[banana apple cherry]).max(2)

      # sample(n): nondeterministic order, so assert on length and (when n >= size)
      # the sorted full set, which is deterministic
      p ints([1, 2, 3, 4, 5]).sample(2).length
      p ints([5, 3, 1, 4, 2]).sample(10).sort
      p strs(%w[a b c]).sample(5).sort
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [3, 4, 5, 1, 2]
      [2, 3, 4, 5, 1]
      [5, 1, 2, 3, 4]
      ["b", "c", "d", "a"]
      ["c", 4, 1, :b]
      [1, 2, 3]
      [2, 3, 4]
      [2, 3, 4]
      ["c", "d"]
      [:b, "c"]
      [1, 1, 2]
      [9, 5]
      [0.5, 1.5]
      ["cherry", "banana"]
      2
      [1, 2, 3, 4, 5]
      ["a", "b", "c"]
    OUT
  end

  it "array slice start oob nil" do
    result = ze0(<<~'RUBY')
      # Array#[start, len] / #slice(start, len) with start outside [-len, len]
      # returns nil like CRuby (start == len is the empty slice; a negative
      # length is nil) -- on typed int/str arrays and poly arrays, through both
      # the nil-capable and the plain slice arms.
      a = [1, 2, 3]
      p a[3, 1]
      p a[4, 1]
      p a[-4, 1]
      p a[3, 0]
      p a[2, -1]
      p a.slice(3, 1)
      p a.slice(5, 2)
      s = ["x", "y"]
      p s[2, 1]
      p s[3, 1]
      p s[2, 0]
      m = [1, "a", :b]
      p m[3, 1]
      p m[4, 2]
      p m[3, 0]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      []
      nil
      nil
      []
      nil
      []
      nil
      []
      nil
      []
      []
      nil
      []
    OUT
  end

  it "array slice when chunk" do
    result = ze0(<<~'RUBY')
      # Array#slice_when and Array#chunk on int_array. Materialises
      # directly (no Enumerator); .to_a is a no-op on the result.

      puts [1, 2, 3, 4, 5].slice_when { |a, b| b > 3 }.to_a.inspect
      puts [1, 2, 2, 3, 3, 3, 4].chunk { |x| x }.to_a.inspect
      # Empty array: empty result.
      puts [].slice_when { |a, b| true }.to_a.inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1, 2, 3], [4], [5]]
      [[1, [1]], [2, [2, 2]], [3, [3, 3, 3]], [4, [4]]]
      []
    OUT
  end

  it "array sum concat init" do
    result = ze0(<<~'RUBY')
      # Array#sum with a String or Array initial value folds by concatenation.
      p ["a", "b", "c"].sum("")
      p ["b", "c"].sum("a:")
      p [[1], [2], [3]].sum([])
      p [[1], [2]].sum([0])
      p [1, 2, 3].sum(0.5)
      p [1, 2, 3].sum
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "abc"
      "a:bc"
      [1, 2, 3]
      [0, 1, 2]
      6.5
      6
    OUT
  end

  it "attr accessor reader and writer generate real methods" do
    result = ze0(<<~'RUBY')
      class Box
        attr_accessor :value
        attr_reader :ro
        def initialize
          @value = 1
          @ro = 7
        end
      end
      b = Box.new
      puts b.value
      b.value = 99
      puts b.value
      puts b.ro
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      99
      7
    OUT
  end

  it "attr override dispatch" do
    result = ze0(<<~'RUBY')
      # An explicit method overriding an inherited (or same-class) attr_reader/
      # attr_accessor must run via normal dispatch, not be shadowed by direct field
      # access at the call site. The more-derived definition wins.

      # subclass def x overrides inherited attr_accessor reader
      class Attr
        attr_accessor :x
        def initialize(v)
          @x = v
        end
      end

      class Child < Attr
        def x
          @x * 10
        end
      end

      puts Child.new(3).x            # 30

      # subclass def x= overrides inherited attr_accessor writer
      class ChildW < Attr
        def x=(v)
          @x = v * 10
        end
      end

      cw = ChildW.new(1)
      cw.x = 5
      puts cw.x                       # 50

      # same-class def overrides its own attr_reader
      class Same
        attr_reader :x
        def initialize(v)
          @x = v
        end
        def x
          @x + 100
        end
      end

      puts Same.new(3).x             # 103

      # child attr_reader overrides parent's explicit def -> reads the field
      class Parent
        def initialize(v)
          @x = v
        end
        def x
          @x + 100
        end
      end

      class ChildA < Parent
        attr_reader :x
      end

      puts ChildA.new(3).x           # 3

      # plain attr with no override keeps direct field access
      class Plain
        attr_accessor :x
        def initialize(v)
          @x = v
        end
      end

      p = Plain.new(7)
      p.x = 9
      puts p.x                        # 9
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      30
      50
      103
      3
      9
    OUT
  end

  it "attr reader and attr writer declared standalone generate only their own half" do
    result = ze0(<<~'RUBY')
      class Point
        attr_reader :x
        attr_writer :y
        def initialize(x, y)
          @x = x
          @y = y
        end
        def show_y
          @y
        end
      end
      p1 = Point.new(1, 2)
      puts p1.x
      p1.y = 99
      puts p1.show_y
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      99
    OUT
  end

  it "attr reader override type" do
    result = ze0(<<~'RUBY')
      class Attr
        attr_accessor :x
        def initialize(v)
          @x = v
        end
      end

      class Child < Attr
        def x
          @x.length
        end
      end

      puts Child.new('abc').x

      class IntAttr
        attr_reader :n
        def initialize(n)
          @n = n
        end
      end

      class Formatted < IntAttr
        def n
          "n=#{@n}"
        end
      end

      puts Formatted.new(7).n
      puts IntAttr.new(7).n

      module Sized
        attr_reader :w
      end

      class Box
        include Sized
        def initialize(w)
          @w = w
        end
        def w
          "#{@w}px"
        end
      end

      puts Box.new(12).w
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      n=7
      7
      12px
    OUT
  end

  it "attr write boxed dispatch" do
    result = ze0(<<~'RUBY')
      class Attr
        attr_accessor :x

        def initialize
          @x = 0
        end
      end

      class Def
        def initialize
          @x1 = 0
        end

        def x
          @x1
        end

        def x=(v)
          @x1 = v
        end
      end

      class Sub < Attr
        def x=(v)
          @x = v * 2
        end
      end

      box = [Def.new, Attr.new, Sub.new]

      o = box[0]
      o.x = 42
      puts "def writer  x=#{o.x}"

      a = box[1]
      a.x = 99
      puts "attr writer x=#{a.x}"

      s = box[2]
      s.x = 21
      puts "override    x=#{s.x}"

      class Mute
        def initialize
          @y = 0
        end
      end

      begin
        m = [Mute.new, Attr.new][0]
        m.x = 7
        puts "no raise"
      rescue NoMethodError => e
        puts "raised: #{e.class}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      def writer  x=42
      attr writer x=99
      override    x=42
      raised: NoMethodError
    OUT
  end

  it "autoload interpolated dir feature" do
    result = ze0(<<~'RUBY', files: {"autoload_interpolated_dir_feature/sprocket.rb" => "class Sprocket\n  def self.size = 42\nend\n\nmodule Widget\n  NAME = \"widget\"\nend\n"})
      # `autoload :Const, "#{__dir__}/sibling"` -- how puma, rack and sidekiq name a
      # sibling file. zeo splices the target at compile time, so the interpolation
      # has to fold then; only a plain literal and `File.expand_path` did.

      autoload :Sprocket, "#{__dir__}/autoload_interpolated_dir_feature/sprocket"
      autoload :Widget, "#{__dir__}/autoload_interpolated_dir_feature/sprocket"

      p Sprocket.size
      p Widget::NAME
      p Sprocket.is_a?(Class)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      42
      "widget"
      true
    OUT
  end

  it "backtick interpolates and runs a shell command" do
    result = ze0(<<~'RUBY')
      # Interpolation shares the normal dstr path; a `;` forces the `/bin/sh -c`
      # path (shell metacharacter), while the bare word execs directly.

      name = "world"
      print `echo hi #{name}`
      print `echo a; echo b`
      puts $?.exited?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hi world
      a
      b
      true
    OUT
  end

  it "bigint to s is a heap string" do
    result = ze0(<<~'RUBY')
      # Integer#to_s on a Bignum answers an ordinary String, so it must live on the
      # string heap with its marker byte.
      #
      # It used to be a bare malloc'd buffer. Nothing reads the byte before such a
      # chunk deliberately, but sp_str_byte_len does -- it is how every spinel string
      # reports its length -- so the length came out of whatever the allocator had
      # put there, and the next concat memcpy'd that many bytes. Under GC stress that
      # is a heap-buffer-overflow inside sp_str_concat; the visible symptom is a SEGV
      # in memcpy with a concat on the stack.
      #
      # Interleaving other allocation is the point: it decides what sits before the
      # chunk, which is what the misread length came from.

      big = 2**200
      noise = []

      s = big.to_s
      p s.length
      p s[0, 3]
      p s.bytesize

      # through concat, the shape that overran
      20.times do |i|
        noise.push("filler-#{i}-#{'x' * i}")
        t = (2**200 + i).to_s + "-" + (2**64 + i).to_s
        p t if i == 19
      end

      # the same value reached through the poly path (a container read is poly)
      mixed = [big, "s"]
      p mixed[0].to_s.length
      p mixed[0].to_s + "!"

      # a BigRational renders by concatenating two of these
      r = Rational(2**100, 3)
      p r.to_s
      p r.inspect

      # and the small-value fast path inside the same function
      p (2**64).to_s
      p (-(2**64)).to_s
      p noise.length
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      61
      "160"
      61
      "1606938044258990275541962092341162602522202993782792835301395-18446744073709551635"
      61
      "1606938044258990275541962092341162602522202993782792835301376!"
      "1267650600228229401496703205376/3"
      "(1267650600228229401496703205376/3)"
      "18446744073709551616"
      "-18446744073709551616"
      20
    OUT
  end

  it "boxed nil string identity" do
    result = ze0(<<~'RUBY')
      # A NULL string is Ruby nil (the nullable-string invariant); boxing must
      # preserve it, or a boxed nil-string carries the string tag and fails
      # tag-keyed comparisons and nil?.
      x = defined?(no_such_thing)
      p x == nil
      arr = [defined?(nope), 1]
      p arr[0].nil?
      p arr[0] == nil
      h = { k: defined?(zilch) }
      p h[:k].inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      "nil"
    OUT
  end

  it "braceless hash non symbol keys" do
    result = ze0(<<~'RUBY')
      # A braceless hash argument is the keyword-argument spelling only when its keys
      # are Symbols. A non-Symbol key cannot be a keyword at all, so Ruby passes an
      # ordinary Hash positionally -- and pinning the collapsed parameter to the
      # symbol-keyed variant regardless made the callee read a string-keyed hash
      # through the wrong pointer: one empty-symbol key and no value, or a hang on
      # integer and mixed keys (#3487).
      #
      # Each form needs its own method: giving one method both a braceless and a
      # braced call site merges the inferred parameter type and hides the divergence.
      def s_key(h)
        p h
      end

      def i_key(h)
        p h
      end

      def mixed(h)
        p h
      end

      def sym_key(h)
        p h
      end

      def braced(h)
        p h
      end

      def dflt(h = {})
        p h
      end

      def after_positional(a, h)
        p [a, h]
      end

      def reads_it(h)
        p h["m"]
      end

      s_key('m' => 1)
      i_key(1 => 2)
      mixed('a' => 1, :b => 2)
      sym_key(k: 1)
      braced({ 'm' => 1 })
      dflt('z' => 9)
      dflt
      after_positional(5, 'q' => 7)
      reads_it('m' => 42)

      # the paths that already worked stay working
      h = { "z" => 9 }
      p h.merge('a' => 1)
      p [].push('a' => 1)
      f = ->(x) { x }
      p f.call('a' => 1)

      def rest(*a)
        p a
      end
      rest('a' => 1)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      {"m" => 1}
      {1 => 2}
      {"a" => 1, b: 2}
      {k: 1}
      {"m" => 1}
      {"z" => 9}
      {}
      [5, {"q" => 7}]
      42
      {"z" => 9, "a" => 1}
      [{"a" => 1}]
      {"a" => 1}
      [{"a" => 1}]
    OUT
  end

  it "bundle string a" do
    _(ze0(<<~'RUBY').stdout).must_equal "0\n1\n2\n3\nA\nB\nC\n3\n1\n1\n1\na\nb\nc\nALPHA\nBETA\nGAMMA\n0\nROW0\nROW1\nROW2\n3\nbeta\ngamma\ndelta\n2\nbeta\ngamma\n2\ndelta\nepsilon\n3\ngamma\nepsilon\nalpha\nepsilon\nbeta:gamma:delta\nhello, world!\na and b\n100% of coverage\n[x][y][z]\na\nno formatting here\n    hi    \n   hi    \n----hi----\n---hi----\nababhiabab\nabahiabab\nhiababab\nhixyzxyz\nabababhi\nxyzxyzhi\nhello\nhello\nhello\ndone\nh\nw\nd\no\ndone\nhell\nhello\nhello\n\n\nab\n97\n98\n65\n49\n122\n97\n10\n195\n169\n532\n532\nhello\n2\n4\n2\n1\n1\n1\n1\n3\n6\n42\n00007\n3.14\nhello!\n"
      # Bundled tests:
      #   - str_array_each
      #   - str_array_map
      #   - str_array_range
      #   - str_format_arr
      #   - str_justify
      #   - strindex
      #   - string_chop
      #   - string_each_byte
      #   - string_escape
      #   - string_format_single

      # === str_array_each ===
      def t_str_array_each
        # Array#each on a str_array. The block param must shadow an outer
        # same-named mrb_int local. Body skips `puts i` to keep this scope-
        # shadow case separate from the format-specifier path.
        
        3.times do |i|
          puts i
        end
        foo = ["a", "b", "c"]
        n = 0
        foo.each { |i| n = n + 1 }
        puts n   # 3
      end
      t_str_array_each

      # === str_array_map ===
      def t_str_array_map
        # Array#map on a str_array. Issue #43: compile_map_expr had no
        # str_array branch, so `tt = foo.map { |s| ... }` silently emitted
        # `lv_tt = 0` and the subsequent iteration crashed.
        
        # String -> string map (the original failure mode)
        foo = ["a", "b", "c"]
        tt = foo.map { |s| s.upcase }
        tt.each { |t| puts t }   # A B C
        
        # String -> int map: codepoint length, returning int_array
        sizes = foo.map { |s| s.length }
        puts sizes.length         # 3
        puts sizes[0]             # 1
        puts sizes[1]             # 1
        puts sizes[2]             # 1
        
        # Original receiver is unchanged
        puts foo[0]               # a
        puts foo[1]               # b
        puts foo[2]               # c
        
        # .map { ... }.each { ... } chain (the issue's pattern)
        words = ["alpha", "beta", "gamma"]
        words.map { |w| w.upcase }.each { |w| puts w }   # ALPHA BETA GAMMA
        
        # Empty input
        empty = "".split(",")
        e2 = empty.map { |s| s.upcase }
        puts e2.length            # 0
        
        # Block parameter is block-local: reusing the same name as an outer
        # differently-typed local must not leak. Issue #43 originally hit this
        # (3.times do |i| ... end then foo.map {|i| ...} where the times-block
        # had typed lv_i as mrb_int).
        rs = []
        3.times do |i|
          rs << "row#{i}"
        end
        out = rs.map { |i| i.upcase }
        out.each { |line| puts line }   # ROW0 ROW1 ROW2
      end
      t_str_array_map

      # === str_array_range ===
      def t_str_array_range
        # StrArray slicing: a[range] and a[start, len].
        # Same regression class as IntArray: a[1..2] failed to compile and
        # a[1, 2] silently dropped the second arg.
        
        a = "alpha,beta,gamma,delta,epsilon".split(",")
        
        # Range form
        b = a[1..3]
        puts b.length      # 3
        puts b[0]          # beta
        puts b[1]          # gamma
        puts b[2]          # delta
        
        # (start, len) form
        c = a[1, 2]
        puts c.length      # 2
        puts c[0]          # beta
        puts c[1]          # gamma
        
        # Negative start
        d = a[-2, 2]
        puts d.length      # 2
        puts d[0]          # delta
        puts d[1]          # epsilon
        
        # len exceeds remaining: clamped
        f = a[2, 100]
        puts f.length      # 3
        puts f[0]          # gamma
        puts f[2]          # epsilon
        
        # Bare a[i] still returns a string
        puts a[0]          # alpha
        puts a[-1]         # epsilon
        
        # Result is usable as a StrArray
        puts a[1..3].join(":")  # beta:gamma:delta
      end
      t_str_array_range

      # === str_format_arr ===
      def t_str_format_arr
        # String#% with a str_array RHS, routed through sp_str_format_strarr.
        # The integer % path (sp_imod) is unchanged — only str_array RHS triggers
        # sprintf-style formatting.
        
        # Single placeholder
        puts "hello, %s!" % ["world"]            # hello, world!
        
        # Multiple placeholders
        puts "%s and %s" % ["a", "b"]            # a and b
        
        # %% literal
        puts "100%% of %s" % ["coverage"]        # 100% of coverage
        
        # %s after literal text
        puts "[%s][%s][%s]" % ["x", "y", "z"]    # [x][y][z]
        
        # Extra args are ignored (matches CRuby tolerant behavior)
        puts "%s" % ["a", "b", "c"]              # a
        
        # Format string with no placeholders, args ignored
        puts "no formatting here" % ["x"]        # no formatting here
      end
      t_str_format_arr

      # === str_justify ===
      def t_str_justify
        # Test String#ljust, rjust, center with custom pad string
        
        # center with default (space) pad
        puts "hi".center(10)        #     hi
        puts "hi".center(9)         #    hi
        
        # center with single-char pad
        puts "hi".center(10, "-")   # ----hi----
        puts "hi".center(9,  "-")   # ---hi----
        
        # center with multi-char pad (cycling)
        puts "hi".center(10, "ab")  # ababhiabab
        puts "hi".center(9,  "ab")  # abahiabab
        
        # ljust with multi-char pad (cycling)
        puts "hi".ljust(8, "ab")    # hiababab
        puts "hi".ljust(8, "xyz")   # hixyzxyz
        
        # rjust with multi-char pad (cycling)
        puts "hi".rjust(8, "ab")    # abababhi
        puts "hi".rjust(8, "xyz")   # xyzxyzhi
        
        # no-op when string already long enough
        puts "hello".ljust(3, "x")  # hello
        puts "hello".rjust(3, "x")  # hello
        puts "hello".center(3, "x") # hello
        
        puts "done"
      end
      t_str_justify

      # === strindex ===
      def t_strindex
        s = "hello world"
        puts s[0]    # h
        puts s[6]    # w
        puts s[-1]   # d
        puts s[4]    # o
        puts "done"
      end
      t_strindex

      # === string_chop ===
      def t_string_chop
        # basic
        puts "hello".chop
        
        # crlf removed together
        puts "hello\r\n".chop
        
        # newline only
        puts "hello\n".chop
        
        # empty string
        puts "".chop
        
        # single char
        puts "x".chop
        
        # already no trailing newline
        puts "abc".chop
      end
      t_string_chop

      # === string_each_byte ===
      def t_string_each_byte
        # String#each_byte iterates the bytes of a string. Mirrors each_char
        # but yields the (unsigned) byte value at each position rather than
        # a single-char substring. ASCII-only test pins parity with CRuby's
        # byte-level iteration. Multi-byte UTF-8 prints the underlying byte
        # values, not codepoints (matches CRuby).
        
        # ASCII string
        "ab".each_byte { |b| puts b }
        
        # Empty string yields nothing
        "".each_byte { |b| puts b }
        
        # Mixed alphabetic and digit
        "A1z".each_byte { |b| puts b }
        
        # Newline byte
        "a\n".each_byte { |b| puts b }
        
        # Multi-byte UTF-8 (Latin Small Letter E with Acute): byte iteration, not codepoint
        "é".each_byte { |b| puts b }
        
        # Counted iteration via accumulator
        total = 0
        "hello".each_byte { |b| total = total + b }
        puts total
        
        # String#each_byte returns the receiver (CRuby parity). Pre-fix Spinel's
        # each_byte was statement-only and the assignment dropped the value.
        total2 = 0
        ret = "hello".each_byte { |b| total2 = total2 + b }
        puts total2
        puts ret
      end
      t_string_each_byte

      # === string_escape ===
      def t_string_escape
        # Literal backslash preservation — the original bug: "\\n" is two
        # bytes (backslash + n) in Ruby source-level escape, and length is 2.
        puts "\\n".length     # 2
        puts "a\\nb".length   # 4
        puts "\\\\".length    # 2
        
        # Standard runtime escape sequences must still work alongside the
        # fix — "\n" is one newline byte, "\t" tab, "\r" CR, "\"" quote.
        puts "\n".length      # 1
        puts "\t".length      # 1
        puts "\r".length      # 1
        puts "\"".length      # 1
        puts "a\nb".length    # 3
        
        # Mixed escapes — literal backslash AND a real newline in the same
        # string. "a\\nb\nc" = a, \, n, b, <newline>, c → length 6.
        puts "a\\nb\nc".length
      end
      t_string_escape

      # === string_format_single ===
      def t_string_format_single
        # `"fmt" % value` (the single-value form of String#%) used to fall
        # through to sp_imod, which rejected the format string as a non-int.
        
        puts "%d" % 42
        puts "%05d" % 7
        puts "%.2f" % 3.14159
        puts "%s!" % "hello"
      end
      t_string_format_single

    RUBY
  end

  it "bundle string b" do
    _(ze0(<<~'RUBY').stdout).must_equal "[\"hello\\n\", \"world\\n\"]\n[\"hello\\n\", \"world\"]\n[\"single line\"]\n[]\n[\"\\n\", \"\\n\", \"\\n\"]\n2\nhello\nworld\nhello\n13\nHELLO, WORLD!\nhello, world!\ntrue\nfalse\nfoobar\n42\nHello, World!\n  Hello, World!  \nHello world\ndlrow olleh\n5\ntrue\ntrue\nheLLo worLd\nhell0 world\n2\nhahaha\ntrue\nfalse\ntrue\nhi        \n        hi\n    hi    \nhi********\n00000000hi\nhello  \n  hello\nhippo\nhe wrd\nabc\n3\n3\n314\nell\nhe\n255\n63\nhello\nhello\ntrue\ntest\ndone\nhello world!\n12\n0,1,2,3,4,\nHELLO WORLD\ndlroW olleH\ntrue\nworld\n0\na\ni\n9\nhell0 w0rld\n3\nfoobar\nfoobarbaz\ntesting\n11\nhello world\nHello World\nHello world\ntrue\ntrue\nfalse\nHerro Worrd\nHello Ruby\n42\nhi        \n        hi\ntrue\nfalse\ndone\n"
      # Bundled tests:
      #   - string_lines
      #   - strings
      #   - strings2
      #   - strings3
      #   - mutable_str

      # === string_lines ===
      def t_string_lines
        # Tests String#lines preserves trailing newline on each piece (CRuby semantics).
        p "hello\nworld\n".lines
        p "hello\nworld".lines
        p "single line".lines
        p "".lines
        p "\n\n\n".lines
        puts "hello\nworld\n".lines.length
        puts "hello\nworld\n".lines[0]
        puts "hello\nworld\n".lines[1]
      end
      t_string_lines

      # === strings ===
      def t_strings
        # Test Symbol and String methods
        
        # Symbol
        s = :hello
        puts s  # hello
        
        # String methods
        str = "Hello, World!"
        puts str.length      # 13
        puts str.upcase      # HELLO, WORLD!
        puts str.downcase    # hello, world!
        puts str.include?("World")  # true
        puts str.include?("xyz")    # false
        
        # String concatenation
        a = "foo"
        b = "bar"
        c = a + b
        puts c  # foobar
        
        # to_s on integers
        n = 42
        puts n.to_s  # 42
      end
      t_strings

      # === strings2 ===
      def t_strings2
        # Test additional String methods
        
        str = "  Hello, World!  "
        puts str.strip           # "Hello, World!"
        puts str.chomp           # "  Hello, World!  " (no trailing newline)
        
        s = "hello world"
        puts s.capitalize        # "Hello world"
        puts s.reverse           # "dlrow olleh"
        puts s.count("lo")       # 5
        puts s.start_with?("hel")  # true
        puts s.end_with?("rld")    # true
        puts s.gsub("l", "L")   # heLLo worLd
        puts s.sub("o", "0")    # hell0 world
        puts s.split(" ").length # 2
        
        # String repeat
        puts "ha" * 3            # hahaha
        
        # String comparison
        puts "abc" == "abc"      # true
        puts "abc" == "def"      # false
        puts "abc" < "def"       # true
      end
      t_strings2

      # === strings3 ===
      def t_strings3
        # Test additional string methods
        
        # ljust / rjust / center
        puts "hi".ljust(10)         # "hi        "
        puts "hi".rjust(10)         # "        hi"
        puts "hi".center(10)        # "    hi    "
        puts "hi".ljust(10, "*")    # "hi********"
        puts "hi".rjust(10, "0")    # "00000000hi"
        
        # lstrip / rstrip
        puts "  hello  ".lstrip     # "hello  "
        puts "  hello  ".rstrip     # "  hello"
        
        # tr / delete / squeeze
        puts "hello".tr("el", "ip")      # "hippo"
        puts "hello world".delete("lo")  # "he wrd"
        puts "aaabbbccc".squeeze          # "abc"
        
        # chars / bytes
        puts "abc".chars.length     # 3
        puts "abc".bytes.length     # 3
        
        # to_f
        puts ("3.14".to_f * 100).to_i  # 314
        
        # slice
        puts "hello"[1..3]          # "ell"
        puts "hello"[0, 2]          # "he"
        
        # hex / oct
        puts "ff".hex    # 255
        puts "77".oct    # 63
        
        # dup / freeze / frozen?
        s = "hello"
        puts s.dup       # "hello"
        puts s.freeze    # "hello"
        puts s.frozen?   # true
        
        # to_s
        puts "test".to_s  # "test"
        
        puts "done"
      end
      t_strings3

      # === mutable_str ===
      def t_mutable_str
        # Mutable strings (sp_String): the `<<` mutation path, replace/clear,
        # index access, gsub/sub, split, ljust/rjust, downcase/strip/...,
        # start_with?/end_with?/empty?/include?, to_s/to_i. Combines what
        # was previously split across mutable_str.rb / _2.rb / _3.rb.
        
        # << (true mutation, not reassignment)
        a = "hello"
        a << " world"
        a << "!"
        puts a          # hello world!
        puts a.length   # 12
        
        # Build string incrementally
        buf = ""
        5.times do |i|
          buf << i.to_s
          buf << ","
        end
        puts buf        # 0,1,2,3,4,
        
        # upcase / reverse / include? on mutable receiver
        b = "Hello World"
        puts b.upcase                 # HELLO WORLD
        puts b.reverse                # dlroW olleH
        puts b.include?("World")      # true
        
        # replace / clear
        c = "hello"
        c.replace("world")
        puts c          # world
        c.clear
        puts c.length   # 0
        
        # [] on mutable string
        d = "abcdef"
        d << "ghi"
        puts d[0]       # a
        puts d[-1]      # i
        puts d.length   # 9
        
        # gsub on mutable receiver
        e = "hello"
        e << " world"
        puts e.gsub("o", "0")  # hell0 w0rld
        
        # split on mutable receiver
        f = "a"
        f << ",b,c"
        parts = f.split(",")
        puts parts.length  # 3
        
        # + creates a new string, does not mutate the receiver
        g = "foo"
        g << "bar"
        h = g + "baz"
        puts g        # foobar (unchanged)
        puts h        # foobarbaz
        
        # to_s on mutable receiver
        tst = "test"
        tst << "ing"
        puts tst.to_s   # testing
        
        # downcase / strip / capitalize / start_with? / end_with? / empty?
        j = ""
        j << "Hello"
        j << " "
        j << "World"
        puts j.length             # 11
        puts j.downcase           # hello world
        puts j.strip              # Hello World
        puts j.capitalize         # Hello world
        puts j.start_with?("Hello")  # true
        puts j.end_with?("World")    # true
        puts j.empty?             # false
        
        # sub / gsub on mutable receiver
        puts j.gsub("l", "r")        # Herro Worrd
        puts j.sub("World", "Ruby")  # Hello Ruby
        
        # to_i via mutable receiver
        n = ""
        n << "42"
        puts n.to_i    # 42
        
        # ljust / rjust
        t = ""
        t << "hi"
        puts t.ljust(10)   # "hi        "
        puts t.rjust(10)   # "        hi"
        
        # include?
        puts j.include?("World")  # true
        puts j.include?("xyz")    # false
        
        puts "done"
      end
      t_mutable_str

    RUBY
  end

  it "bundle string c" do
    result = ze0(<<~'RUBY')
      # Bundled tests:
      #   - str_index_range_eq
      #   - str_setbyte_dup_mutates
      #   - string_endless_range
      #   - string_index_from
      #   - string_index_nullable
      #   - string_index_oob_returns_nil
      #   - string_to_i_underscore

      # === str_index_range_eq ===
      def t_str_index_range_eq
        # `s[i..i] == "/"` used to skip compile_string_method_expr's `[]`
        # RangeNode arm and hit the `s[i] == "/"` single-char fast path
        # instead (compile_eq_char_index), which cast the RangeNode to
        # mrb_int and emitted `lv_s[(mrb_int)sp_range_new(i, i)] == '/'` —
        # C compile failure ("aggregate value used where an integer was
        # expected"). Issue #644.
        #
        # Fix: the single-char fast path bails out when the `[]` arg is a
        # Range or a 2-arg `s[start, len]` form, so the call falls through
        # to the proper sp_str_sub_range dispatch + string compare.
        
        s = "abc/def"
        i = 3
        if s[i..i] == "/"
          puts "match"
        end
        
        # Range literal as the [] arg (no LV indirection).
        puts s[1..2]            # "bc"
        puts s[3..3] == "/"     # true
        
        # Exclusive range.
        puts s[3...4] == "/"    # true
        
        # `s[start, len]` 2-arg form must also fall through cleanly.
        puts s[3, 1] == "/"     # true
      end
      t_str_index_range_eq

      # === str_setbyte_dup_mutates ===
      def t_str_setbyte_dup_mutates
        # `String#setbyte` on a heap-allocated string mutates in place.
        # Spinel adopts `# frozen_string_literal: true` semantics
        # globally: string literals are frozen (rodata-resident), so a
        # setbyte on a literal raises FrozenError; setbyte on a heap
        # buffer (from .dup, +, *, gsub, etc.) mutates as usual.
        #
        # This test pins the heap-mutate path. Literal -> FrozenError is
        # covered by test/str_setbyte_frozen_literal.
        
        # Dup'd string: setbyte mutates.
        s = "ab".dup
        s.setbyte(0, 67)  # 'C'
        s.setbyte(1, 68)  # 'D'
        puts s   # CD
        
        # String#+ produces a fresh heap buffer too.
        s2 = "x" + "y"
        s2.setbyte(0, 90)  # 'Z'
        puts s2  # Zy
      end
      t_str_setbyte_dup_mutates

      # === string_endless_range ===
      def t_string_endless_range
        # #543. `s[1..]` (Ruby 2.6+ endless range) returned an empty
        # string under spinel-AOT instead of the substring from index 1
        # to end. CRuby returns "id" for ":id"[1..]; spinel returned "".
        # Trigger: the codegen lowered `s[1..]`'s RangeNode `right` (an
        # AST -1 sentinel meaning "no value") to literal `0`, then
        # `sp_str_sub_range_r(s, 1, 0, 0)` produced a zero-length slice.
        #
        # Sam Ruby caught this when Roundhouse's router stripped the
        # leading `:` from `:id` pattern segments via `pp[1..]` and the
        # capture key became "" -- every `/articles/N` 404'd because
        # params["id"] was always the default fallback.
        #
        # Fix: in the bracket-call's RangeNode branch, treat the AST -1
        # sentinel for the endpoints as the corresponding end:
        #   - missing left  -> "0"  (s[..k] == s[0..k])
        #   - missing right -> "-1" (s[k..] == s[k..-1])
        # The exclusive flag is ignored on the missing endpoint (CRuby
        # semantics: `s[1..]` == `s[1...]` == `s[1..-1]`).
        
        s = "hello"
        
        # Endless from inclusive lower bound.
        puts s[1..]      # ello
        puts s[1...]     # ello  (CRuby treats endless ... same as ..)
        puts s[-2..]     # lo
        
        # Beginless to inclusive upper bound.
        puts s[..2]      # hel
        puts s[...2]     # he   (exclusive upper)
        
        # The Sam Ruby repro shape: strip the leading char.
        pp = ":id"
        puts pp[1..]     # id
      end
      t_string_endless_range

      # === string_index_from ===
      def t_string_index_from
        # Regression: `String#index(sub, start)` 2-arg form.
        # Pre-fix the codegen ignored `start` and re-emitted the 1-arg
        # call, so a "find next dot after position N" walk all returned
        # the first match.
        #
        # Updated for #532: `String#index` now returns nil (not -1) for
        # not-found, matching CRuby. `puts nil.to_s` prints an empty
        # line; the walk-all-dots loop checks `pos.nil?` instead of
        # `pos < 0`.
        
        s = "a.b.c.d"
        
        # 1-arg form -- baseline.
        puts s.index(".").to_s          # 1
        
        # 2-arg form -- the fix.
        puts s.index(".", 0).to_s       # 1   (no skip, finds the same first dot)
        puts s.index(".", 1).to_s       # 1   (start at the dot itself, finds it)
        puts s.index(".", 2).to_s       # 3   (skip past the first dot, find the second)
        puts s.index(".", 4).to_s       # 5
        puts s.index(".", 6).to_s       # "" (nil.to_s; CRuby would print blank)
        
        # Negative start counts from end.
        puts s.index(".", -1).to_s      # "" (not found, nil.to_s)
        puts s.index(".", -2).to_s      # 5    (last dot)
        puts s.index(".", -100).to_s    # 1    (clamps to 0)
        
        # Out-of-range positive start.
        puts s.index(".", 100).to_s     # "" (not found, nil.to_s)
        
        # Multibyte: codepoint indexing, not byte indexing.
        m = "α.β.γ"
        puts m.index(".").to_s          # 1   (one cp before the first dot)
        puts m.index(".", 2).to_s       # 3   (after the first dot)
        
        # Walk-all-dots loop -- the JWT use case that surfaced this bug.
        # Idiomatic post-#532: `break if pos.nil?` instead of `pos < 0`.
        t = "header.payload.sig"
        i = 0
        positions = ""
        while true
          pos = t.index(".", i)
          if pos.nil?
            break
          end
          positions = positions + pos.to_s + ","
          i = pos.to_i + 1
        end
        puts positions                  # 6,14,
      end
      t_string_index_from

      # === string_index_nullable ===
      def t_string_index_nullable
        # #532. `String#index` / `String#rindex` previously returned
        # mrb_int with -1 as the not-found sentinel. The CRuby idiom
        #
        #   pos = body.index('"content"', i)
        #   break if pos.nil?
        #
        # silently broke because `pos.nil?` on a plain-int local is
        # always false (per #521's strict `int == nil`), so the loop
        # never exits and i wanders past the buffer.
        #
        # Fix: widen `String#index` / `String#rindex` to return sp_RbVal
        # (boxed nil for the -1 sentinel, boxed int for found). The
        # CRuby semantics now work end-to-end:
        # - `pos.nil?` / `pos == nil` / `pos != nil` via tag check
        # - `pos.inspect` via sp_poly_inspect (prints "nil" or the int)
        # - `while pos = s.index(...)` truthiness (boxed nil is falsy)
        #
        # Cost: downstream call sites that consume `pos` as a raw int
        # need to unbox. compile_expr_as_int / compile_arg0_as_int in
        # the codegen handle the int-expecting C helper signatures
        # (sp_str_sub_range etc.).
        
        s = "hello world"
        
        # Found and not-found inspect (formerly "6" / "-1"; now "6" / "nil").
        puts s.index("world").inspect    # 6
        puts s.index("xyz").inspect      # nil
        puts s.index("hello").inspect    # 0   (real index 0, not nil)
        
        # CRuby's nil-lens idiom now works without rewrites.
        pos = s.index("xyz")
        puts pos.nil?                    # true
        puts (pos == nil)                # true
        puts (pos != nil)                # false
        
        pos = s.index("hello")
        puts pos.nil?                    # false (real index 0 is NOT nil)
        puts (pos != nil)                # true
        
        # rindex inherits the same shape.
        puts "abcdabcd".rindex("c").inspect    # 6
        puts "abcdabcd".rindex("z").inspect    # nil
        
        # Walk-all idiom from the issue's GPT-2 BPE example.
        body = "header.payload.sig"
        i = 0
        positions = ""
        while true
          pos = body.index(".", i)
          break if pos.nil?
          positions = positions + pos.to_s + ","
          i = pos.to_i + 1
        end
        puts positions                   # 6,14,
      end
      t_string_index_nullable

      # === string_index_oob_returns_nil ===
      def t_string_index_oob_returns_nil
        # `"hello"[20]` (single-int index past the end) returns nil in CRuby,
        # not "". Pre-fix spinel's sp_str_sub_range fell through to its
        # OOB branch and returned the empty string, so a `.nil?` check
        # (or any `== nil` comparison) saw a non-NULL pointer and surfaced
        # false. Issue #619 puzzle 3.
        puts "hello"[20].nil?     # true
        puts "hello"[5].nil?      # true (at end of string, single-int index)
        puts "hello"[0].nil?      # false (in bounds)
        puts "hello"[4].nil?      # false (last char)
        puts "hello"[0]           # "h"
        puts "hello"[4]           # "o"
        puts "hello"[-1]          # "o" (negative index normalizes)
        puts "hello"[-99].nil?    # true (past start)
      end
      t_string_index_oob_returns_nil

      # === string_to_i_underscore ===
      def t_string_to_i_underscore
        # CRuby's `String#to_i` accepts `_` between consecutive digits and
        # stops at the first non-digit. spinel previously emitted
        # `(mrb_int)atoll(s)` which stops at the first `_`, returning 1
        # for "1_2_3asdf" instead of 123. Now routes through
        # sp_str_to_i_cruby. Issue #619 puzzle 1.
        
        p("1_2_3asdf".to_i)
        p("-5_0".to_i)
        p("hello".to_i)
        p("  42  trailing".to_i)
        p("".to_i)
        p("0xFF".to_i)   # CRuby: 0 (only base-10 digits)
      end
      t_string_to_i_underscore

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      match
      bc
      true
      true
      true
      CD
      Zy
      ello
      ello
      lo
      hel
      he
      id
      1
      1
      1
      3
      5


      5


      1
      3
      6,14,
      6
      nil
      0
      true
      true
      false
      false
      true
      6
      nil
      6,14,
      true
      true
      false
      false
      h
      o
      o
      true
      123
      -50
      0
      42
      0
      0
    OUT
  end

  it "bundle tiny string" do
    result = ze0(<<~'RUBY')
      # Bundled tiny tests (auto-grouped by bundler):
      #   - empty_string_to_sym
      #   - str_each_line_chomp
      #   - str_lines_chomp
      #   - str_tr_empty_replacement
      #   - string_ascii_only
      #   - string_chomp_separator
      #   - string_codepoints
      #   - string_delete_multi_arg
      #   - string_gsub_empty_pat
      #   - string_range_splat
      #   - string_scan_capture
      #   - string_spaceship
      #   - string_squeeze_multi_arg
      #   - string_strip_nul
      #   - string_symbol_itself
      #   - string_tr_s
      #   - string_valid_encoding
      #   - string_with_nul_byte

      # === empty_string_to_sym ===
      def t_empty_string_to_sym
      # Empty-string interning: "".to_sym and the :"" literal must resolve to the
      # same symbol id (an empty symbol once broke the C build).
      p("".to_sym == :"")
      p(:"" == "".to_sym)
      p("abc".to_sym == :abc)
      p("".to_sym.to_s == "")
      end
      t_empty_string_to_sym

      # === str_each_line_chomp ===
      def t_str_each_line_chomp
      # String#each_line(chomp: true) strips trailing line endings.
      "a\nb\nc".each_line(chomp: true) { |l| p l }
      puts "---"
      "a\nb\nc".each_line { |l| p l }
      puts "---"
      "x\r\ny\r\n".each_line(chomp: true) { |l| p l }
      end
      t_str_each_line_chomp

      # === str_lines_chomp ===
      def t_str_lines_chomp
      # String#lines(chomp: true) strips line endings from each line.
      # Without the chomp: keyword, line endings are preserved.

      puts "a\nb\nc".lines(chomp: true).inspect
      puts "a\nb\nc".lines.inspect
      puts "a\r\nb\r\nc\r\n".lines(chomp: true).inspect
      end
      t_str_lines_chomp

      # === str_tr_empty_replacement ===
      def t_str_tr_empty_replacement
      # String#tr / tr_s with empty replacement string
      # When the to-string is empty, matched characters are deleted.

      puts "abc".tr("a", "").inspect
      puts "abcdef".tr("a-c", "").inspect
      puts "aabbbccc".tr_s("ab", "").inspect
      end
      t_str_tr_empty_replacement

      # === string_ascii_only ===
      def t_string_ascii_only
      # String#ascii_only? : true iff every byte is 7-bit ASCII.
      p "hello".ascii_only?
      p "héllo".ascii_only?
      p "".ascii_only?
      p "abc123!".ascii_only?
      p "あ".ascii_only?
      end
      t_string_ascii_only

      # === string_chomp_separator ===
      def t_string_chomp_separator
      # Issue #881: String#chomp with an explicit separator argument
      # strips that suffix. Without the fix the arg was silently dropped
      # and the default newline rules were applied.
      puts "hello!".chomp("!").inspect
      puts "hello\n".chomp.inspect
      puts "hello\r\n".chomp.inspect
      puts "hello".chomp("!").inspect
      puts "hello\n\n".chomp("").inspect
      end
      t_string_chomp_separator

      # === string_codepoints ===
      def t_string_codepoints
      # Issue #903: String#codepoints returns int_array of UTF-8
      # codepoints (not bytes).
      puts "hello".codepoints.inspect
      puts "あ".codepoints.inspect
      puts "".codepoints.inspect
      end
      t_string_codepoints

      # === string_delete_multi_arg ===
      def t_string_delete_multi_arg
      # String#delete with multiple args deletes the intersection of the
      # charsets (each arg is a charset spec).
      p "hello".delete("l", "o")
      p "hello".delete("lo", "l")
      p "hello".delete("l", "h", "e")
      p "hello".delete("el", "ello")
      p "hello".delete("l")
      p "hello".delete("^l")
      end
      t_string_delete_multi_arg

      # === string_gsub_empty_pat ===
      def t_string_gsub_empty_pat
      # Issue #850: String#gsub with empty pattern inserts the
      # replacement between every character (and at the start/end).
      # Pre-fix, empty pattern was a no-op.
      puts "hello".gsub("", "x")
      puts "abc".gsub("", "-")
      end
      t_string_gsub_empty_pat

      # === string_range_splat ===
      def t_string_range_splat
      # Splatting a string range into an array literal expands it into a
      # str_array (the runtime already has sp_StrArray_from_string_range; the
      # bug was the literal mis-typing to int_array and emitting a char*-in-
      # int-loop).
      p [*"a".."e"]
      p [*"a"..."d"]        # exclusive range drops the endpoint
      p [*"x".."z", "!"]    # splat-first, then a trailing literal
      p [*" ".."&"]         # the printable-ASCII idiom from the bug report
      end
      t_string_range_splat

      # === string_scan_capture ===
      def t_string_scan_capture
      # Issue #880: String#scan returns nested arrays for capture groups.

      puts "hello world".scan(/(\w+)/).inspect
      puts "a1 b22".scan(/([a-z]+)(\d+)/).inspect
      puts "hello world".scan(/\w+/).inspect
      puts "ab ac".scan(/a(?:b|c)/).inspect
      end
      t_string_scan_capture

      # === string_spaceship ===
      def t_string_spaceship
      # Issue #900: String#<=> dispatches strcmp clamped to -1/0/1.
      # Pre-fix: always returned 0.
      puts "abc" <=> "abd"
      puts "abd" <=> "abc"
      puts "abc" <=> "abc"
      puts "ab" <=> "abc"
      end
      t_string_spaceship

      # === string_squeeze_multi_arg ===
      def t_string_squeeze_multi_arg
      # String#squeeze with multiple args squeezes runs of chars in the
      # intersection of the charsets.
      p "aaabbbccc".squeeze("a", "b")
      p "aaabbbccc".squeeze("a", "ab")
      p "aaabbbccc".squeeze("abc")
      p "aaabbbccc".squeeze
      end
      t_string_squeeze_multi_arg

      # === string_strip_nul ===
      def t_string_strip_nul
      # String#strip / #lstrip / #rstrip remove the NUL byte along with ASCII
      # whitespace, matching CRuby.
      p "\0 abc \0".strip
      p "abc\0\0".rstrip
      p "\0\0abc".lstrip
      p "  \t\nx\r\f ".strip
      p "\0".strip
      p "no change".strip
      end
      t_string_strip_nul

      # === string_symbol_itself ===
      def t_string_symbol_itself
      # Kernel#itself on string and symbol returns self.
      puts "hello".itself
      puts :foo.itself.inspect
      end
      t_string_symbol_itself

      # === string_tr_s ===
      def t_string_tr_s
      # Issue #902: String#tr_s translates and squeezes adjacent
      # identical translated chars (untranslated runs keep their
      # duplicates).
      puts "hello".tr_s("l", "r")
      puts "aaabbbccc".tr_s("a", "x")
      # Without squeeze for comparison
      puts "hello".tr("l", "r")
      puts "aaabbb".tr_s("ab", "xy")
      end
      t_string_tr_s

      # === string_valid_encoding ===
      def t_string_valid_encoding
      # String#valid_encoding? — true for ASCII / well-formed UTF-8,
      # false for invalid byte sequences.
      puts "hello".valid_encoding?
      puts "".valid_encoding?
      puts "日本語".valid_encoding?
      puts "\xff\xff".valid_encoding?
      puts "abc\xc3\x28".valid_encoding?
      end
      t_string_valid_encoding

      # === string_with_nul_byte ===
      def t_string_with_nul_byte
      # Issue #722: a string literal with an embedded NUL byte reports
      # the full length, and .bytes iterates all bytes (not strlen-
      # truncated at the NUL). Pre-fix the parser AST text format also
      # truncated the field at the NUL.
      puts "hello\0world".length
      puts "hello\0world".bytes.length
      puts "a\0b\0c".length
      puts "\0\0\0".length
      end
      t_string_with_nul_byte

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      true
      "a"
      "b"
      "c"
      ---
      "a\n"
      "b\n"
      "c"
      ---
      "x"
      "y"
      ["a", "b", "c"]
      ["a\n", "b\n", "c"]
      ["a", "b", "c"]
      "bc"
      "def"
      "ccc"
      true
      false
      true
      true
      false
      "hello"
      "hello"
      "hello"
      "hello"
      "hello"
      [104, 101, 108, 108, 111]
      [12354]
      []
      "hello"
      "heo"
      "hello"
      "ho"
      "heo"
      "ll"
      xhxexlxlxox
      -a-b-c-
      ["a", "b", "c", "d", "e"]
      ["a", "b", "c"]
      ["x", "y", "z", "!"]
      [" ", "!", "\"", "#", "$", "%", "&"]
      [["hello"], ["world"]]
      [["a", "1"], ["b", "22"]]
      ["hello", "world"]
      ["ab", "ac"]
      -1
      1
      0
      -1
      "aaabbbccc"
      "abbbccc"
      "abc"
      "abc"
      "abc"
      "abc"
      "abc"
      "x"
      ""
      "no change"
      hello
      :foo
      hero
      xbbbccc
      herro
      xy
      true
      true
      true
      false
      false
      11
      11
      5
      3
    OUT
  end

  it "byref string param instance method" do
    result = ze0(<<~'RUBY')
      # `def add(buf, i); buf << ...; end` is ordinary Ruby: the append lands in the
      # caller's string. Only free functions and class methods took the out-param
      # ABI, so an INSTANCE method appended to a copy and the caller's buffer stayed
      # empty -- the log a benchmark built line by line came out zero-length and
      # every later match found nothing.

      class Builder
        def initialize
          @log = String.new
        end

        attr_reader :log

        def add(str, i)
          str << "line" << i.to_s << "\n"
        end

        def build_local(n)
          buf = String.new
          n.times { |i| add(buf, i) }
          buf
        end

        def build_ivar(n)
          @log = String.new
          n.times { |i| add(@log, i) }
          @log
        end
      end

      b = Builder.new
      p b.build_local(3).length
      p b.build_ivar(3).length
      p b.log.split("\n").size
      p b.build_ivar(2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      18
      18
      3
      "line0\nline1\n"
    OUT
  end

  it "capitalize titlecases the digraphs" do
    result = ze0(<<~'RUBY')
      # `String#capitalize` maps the Unicode digraphs to their TITLECASE forms
      # (U+01F3 dz -> U+01F2 Dz, and the Lj/Nj/Dz families), and #swapcase of a
      # titlecase char lowercases per-half ("Dz" -> "dZ"). zeo maps both
      # through the full-uppercase table. #upcase and #downcase already match;
      # only the titlecase third of the case-mapping triple is missing. (Found
      # by the 2026-08-24 probe sweep.)
      p "ǳ".capitalize
      p ["ǉx".capitalize, "ǌx".capitalize, "ǆx".capitalize]
      p "ǲ".swapcase
      p "ǳ".upcase
      p "ǲ".downcase
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ǲ"
      ["ǈx", "ǋx", "ǅx"]
      "dZ"
      "Ǳ"
      "ǳ"
    OUT
  end

  it "case when string range" do
    result = ze0(<<~'RUBY')
      # case/when with a String scrutinee and string-range conditions: Range#===
      # is cover? (lexicographic <=>), including exclusive, beginless, endless,
      # and non-literal endpoints, in both statement and value position.
      def label(c)
        case c
        when "a".."m" then "low"
        else "hi"
        end
      end
      p label("c")
      p label("a")
      p label("m")
      p label("n")
      p label("cat")
      p label("")

      def label_excl(c)
        case c
        when "a"..."m" then "low"
        else "hi"
        end
      end
      p label_excl("l")
      p label_excl("m")
      p label_excl("lz")

      def label_var(c, lo, hi)
        case c
        when lo..hi then "in"
        else "out"
        end
      end
      p label_var("dog", "d", "f")
      p label_var("cat", "d", "f")

      def label_open(c)
        case c
        when ..."d" then "early"
        when "n".. then "late"
        else "mid"
        end
      end
      p label_open("b")
      p label_open("q")
      p label_open("g")

      def bucket(c)
        r = case c
            when "a".."m" then 1
            when "x" then 2
            else 3
            end
        r
      end
      p bucket("b")
      p bucket("x")
      p bucket("q")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "low"
      "low"
      "low"
      "hi"
      "low"
      "hi"
      "low"
      "hi"
      "low"
      "in"
      "out"
      "early"
      "late"
      "mid"
      1
      2
      3
    OUT
  end

  it "case when string range nil bound" do
    result = ze0(<<~'RUBY')
      # A nil endpoint of a string range (here an unset String ivar, which reads as a
      # NULL slot) is an OPEN bound under Range#=== / case-when, exactly like CRuby:
      # `(nil.."m") === "c"` is true. The endpoint must not be dereferenced by strcmp,
      # and must widen its side rather than fail the match.
      class Bounds
        def initialize(set_lo, set_hi)
          @lo = "d" if set_lo
          @hi = "m" if set_hi
        end
        def classify(s)
          case s
          when @lo..@hi then "in"
          else "out"
          end
        end
      end

      p Bounds.new(false, true).classify("c")   # open lower, "c" <= "m"  -> in
      p Bounds.new(false, true).classify("z")   # open lower, "z" >  "m"  -> out
      p Bounds.new(true, false).classify("f")   # "f" >= "d", open upper  -> in
      p Bounds.new(true, false).classify("a")   # "a" <  "d"              -> out
      p Bounds.new(true, true).classify("g")    # "d" <= "g" <= "m"       -> in
      p Bounds.new(false, false).classify("x")  # both open               -> in
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "in"
      "out"
      "in"
      "out"
      "in"
      "in"
    OUT
  end

  it "casecmp folds ascii and casecmp p folds unicode" do
    result = ze0(<<~'RUBY')
      # casecmp folds ASCII alone and casecmp? folds all of Unicode, as
      # CRuby's str_casecmp and str_casecmp_p do. An operand the receiver has
      # no encoding in common with answers nil.
      def t = yield rescue [$!.class, $!.message]

      p t { "Ä".casecmp("ä") }, t { "Ä".casecmp?("ä") }, t { "ß".casecmp?("ss") }, t { "ﬃ".casecmp?("ffi") }
      p t { "abc".casecmp("ABD") }, t { "b".casecmp("A") }, t { "a".casecmp(1) }, t { "a".casecmp?(1) }
      p t { "İstanbul".downcase(:turkic) }, t { "Iı".swapcase(:turkic) }, t { "ΣΑΣ".downcase(:fold) }
      p t { "é".casecmp("É".b) }, t { "a".casecmp("A".b) }, t { "é".casecmp?("É") }

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      -1
      true
      true
      true
      -1
      1
      nil
      nil
      "istanbul"
      "ıI"
      "σασ"
      nil
      0
      true
    OUT
  end

  it "catch string tag" do
    _(ze0(<<~'RUBY').stdout).must_equal "UncaughtThrowError\n"
      begin
        catch("str") { throw "str", :s }
      rescue UncaughtThrowError => e
        p e.class
      end
    RUBY
  end

  it "chunk slice float" do
    result = ze0(<<~'RUBY')
      # Block-based slicing/chunking materialized via .to_a on Float-element
      # arrays and on an empty (untyped) array literal.

      p([1.0, 2.0, 4.0, 5.0].slice_when { |x, y| y - x > 1.0 }.to_a)
      p([1.0, 2.0, 4.0].chunk_while { |x, y| y - x <= 1.0 }.to_a)
      p([1.0, 2.0, 4.0].slice_before { |x| x > 3.0 }.to_a)
      p([1.0, 2.0, 4.0].slice_after { |x| x > 1.5 }.to_a)
      p([1.0, 1.0, 2.0].chunk { |x| x }.to_a)
      p([].chunk { |x| x }.to_a)
      p([].slice_when { |x, y| x < y }.to_a)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1.0, 2.0], [4.0, 5.0]]
      [[1.0, 2.0], [4.0]]
      [[1.0, 2.0], [4.0]]
      [[1.0, 2.0], [4.0]]
      [[1.0, [1.0, 1.0]], [2.0, [2.0]]]
      []
      []
    OUT
  end

  it "clamp string and range" do
    result = ze0(<<~'RUBY')
      # Comparable#clamp — string receiver and Range arg form.
      # 2-arg int form was already supported by #899.
      puts "b".clamp("a", "c")
      puts "z".clamp("a", "c")
      puts "a".clamp("b", "y")

      # Range arg on Integer
      puts 5.clamp(1..10)
      puts 0.clamp(1..10)
      puts 11.clamp(1..10)

      # Range arg on String
      puts "m".clamp("a".."z")
      puts "Z".clamp("a".."z")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      b
      c
      b
      5
      1
      10
      m
      a
    OUT
  end

  it "class eval string constant scope" do
    result = ze0(<<~'RUBY')
      # The STRING forms of `class_eval`/`module_eval`/`instance_eval` evaluate with
      # the receiver as the constant lookup scope. zeo evaluates them with the
      # caller's scope, so a constant owned by the receiver is not found.
      #
      #     Outer::Host.class_eval("HOST_C")   ruby :host   zeo NameError
      #
      # The BLOCK form is the opposite and zeo gets it right: a block keeps the
      # lexical scope where it was written, which is why `class_eval { VAL }` sees
      # the caller's constants and `class_eval("VAL")` does not. That contrast is the
      # documented reason both forms exist, and a library that builds code as a
      # string -- the classic `class_eval <<~RUBY` accessor generator -- depends on
      # the string form seeing the receiver.
      #
      # The NameError message shows the same missing scope: ruby names the constant
      # it looked for as `Outer::Host::VAL`, zeo as a bare `VAL`.

      module Outer
        VAL = :outer_val
        class Host
          HOST_C = :host
        end
      end

      p Outer::Host.class_eval("HOST_C")

      # `instance_eval`'s scope is the SINGLETON class, so an instance-level constant
      # is correctly absent there -- but the message names the scope it searched, and
      # that is the same information the case above is missing.
      begin
        Outer::Host.instance_eval("HOST_C")
      rescue NameError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        Outer::Host.class_eval("VAL")
      rescue NameError => e
        puts "#{e.class}: #{e.message}"
      end

      # The block form keeps the caller's lexical scope -- already correct.
      p Outer::Host.class_eval { Outer::VAL }
      p Outer::Host.class_eval { const_defined?(:HOST_C) }

      # A string that DEFINES a method lands on the receiver either way.
      Outer::Host.class_eval("def from_string = HOST_C")
      p Outer::Host.new.from_string
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :host
      NameError: uninitialized constant #<Class:Outer::Host>::HOST_C
      NameError: uninitialized constant Outer::Host::VAL
      :outer_val
      true
      :host
    OUT
  end

  it "class shovel self attr accessor backs onto class level ivars" do
    result = ze0(<<~'RUBY')
      # `class << self; attr_accessor :x; end` is THE idiomatic way to declare
      # class-level state, and it works by generating `def self.x; @x; end` --
      # so it only works once class-level `@x` has real storage.

      module Reg
        class << self
          attr_accessor :handler
          def helper; "helped"; end
        end
      end
      Reg.handler = "H"
      p Reg.handler
      p Reg.helper

      class Cfg
        class << self
          attr_reader :mode
          attr_writer :mode
        end
        @mode = "default"
      end
      p Cfg.mode
      Cfg.mode = "custom"
      p Cfg.mode
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "H"
      "helped"
      "default"
      "custom"
    OUT
  end

  it "clock symbol name" do
    result = ze0(<<~'RUBY')
      # `Process.clock_gettime` takes a clock as a SYMBOL name.
      #
      # The symbol spelling is the portable one -- a constant the platform does
      # not define is a `NameError` at the read, where the symbol form is a
      # rescuable `Errno::EINVAL` -- so it is the shape a library actually
      # writes. The name is looked up against `Process`'s own `CLOCK_*`
      # constants, so the two cannot drift.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # `Process.clock_gettime` takes a clock as a SYMBOL name as well as a constant
      # or a raw id. The symbol went into an Integer slot and raised (#4044).

      p Process.clock_gettime(:CLOCK_MONOTONIC).class
      p Process.clock_gettime(Process::CLOCK_MONOTONIC).class
      p Process.clock_gettime(:CLOCK_REALTIME).class
      p Process.clock_gettime(:CLOCK_MONOTONIC, :nanosecond).class
      p Process.clock_gettime(:CLOCK_MONOTONIC, :millisecond).class
      p Process.clock_getres(:CLOCK_MONOTONIC).class
      p Process.clock_gettime(:CLOCK_REALTIME) > 0
      p Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID) >= 0
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Float
      Float
      Float
      Integer
      Integer
      Float
      true
      true
    OUT
  end

  it "concat boxed source" do
    result = ze0(<<~'RUBY')
      # A boxed source for #concat: the element read out of a poly array is an array
      # at run time, and reading it as the receiver's C type did not compile (#3850).
      g = [[1, 2], [3, 4]]
      p g.each_with_object([]) { |r, acc| acc.concat(r) }
      acc2 = []
      g.each { |r| acc2.concat(r) }
      p acc2
      s = ["a", "b"]
      out = []
      [s].each { |r| out.concat(r) }
      p out
      p [1, 2].concat([3, 4])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      ["a", "b"]
      [1, 2, 3, 4]
    OUT
  end

  it "concat chain operand gc root" do
    result = ze0(<<~'RUBY')
      # A chained string concat `a + b + c` lowers to sp_str_concat3 (and
      # `a+b+c+d` to sp_str_concat4). The operands must be rooted before the
      # call: argument evaluation order is unspecified, so a fresh GC string
      # produced by one operand can be collected while a sibling operand
      # allocates. Here each tag() allocates and forces a GC, so a later
      # operand's GC.start collects an earlier operand's unrooted result.
      def tag(s)
        r = "[" + s + "]"   # fresh heap string
        GC.start            # collect; pre-fix frees sibling operands still pending
        r
      end

      three = tag("a") + "\n" + tag("b") + "\n" + tag("c")
      four  = tag("w") + tag("x") + tag("y") + tag("z")
      puts three
      puts four
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [a]
      [b]
      [c]
      [w][x][y][z]
    OUT
  end

  it "concat print poly unbox" do
    result = ze0(<<~'RUBY')
      # Conditional-assign of a poly value (e.g. nullable hash lookup
      # fused with a nil-guard fallback) leaves the local typed sp_RbVal
      # even when both branches produce strings. Downstream concat and
      # print sites must coerce on the sp_RbVal -> const char * boundary
      # rather than fall through to a struct-into-pointer cc error.
      #
      #   * `"a" + poly + "b"` -- chained concat collapses to
      #     sp_str_concat3; collect_concat_parts now wraps poly with
      #     sp_poly_to_s (mirrors the existing 2-arg sp_str_concat
      #     coercion at the single-`+` site).
      #   * `print poly` -- compile_print routes through sp_poly_to_s
      #     instead of the broken `printf("%lld", (long long)val)`
      #     fallback (sp_RbVal is a struct; the cast rejects).
      #
      # str_poly_hash lookup is the canonical shape that triggers the
      # poly local: { "text" => "hi", "n" => 42 }["text"] is sp_RbVal
      # because the value union spans String and Integer.

      def show_concat(node)
        raw = node["text"]
        text = if raw.nil?
                 ""
               else
                 raw
               end
        puts "[ " + text + " ]"
      end

      def show_print(node)
        raw = node["text"]
        text = if raw.nil?
                 ""
               else
                 raw
               end
        print "[ "
        print text
        print " ]\n"
      end

      # --- Present-key String value (the canonical bug-report shape).
      # Mixed-value hash -> str_poly_hash; the else branch produces a poly
      # value (raw), the if branch produces a string literal. The union of
      # the two branches stays sp_RbVal. Without the codegen-side coercion,
      # the downstream concat / print sites emit cc-rejected C.
      h_present = { "text" => "hello", "n" => 42 }
      show_concat(h_present)
      show_print(h_present)

      # --- Missing-key fallback. Exercises the if-true branch of the
      # nil-guard: raw is nil, text becomes "", concat / print emit
      # "[  ]" / "[  ]\n". h_missing keeps the same str_poly_hash shape
      # (mixed String + Integer values so the value union widens to
      # poly) but omits the "text" key so the lookup returns nil.
      # Without this case the if-branch of the conditional assignment
      # was untested.
      h_missing = { "other" => "x", "n" => 42 }
      show_concat(h_missing)
      show_print(h_missing)

      # --- Symbol-valued poly via `print`. CRuby's `print :sym` calls
      # `Symbol#to_s` -> "sym"; spinel's compile_print poly arm routes
      # through `sp_poly_to_s` whose SP_TAG_SYM case returns the same
      # rendering. Exercises the tag dispatch beyond SP_TAG_STR.
      def show_print_sym(node)
        raw = node["k"]
        text = raw.nil? ? "" : raw
        print "sym="
        print text
        puts ""
      end
      h_sym = { "k" => :hello, "n" => 42 }
      show_print_sym(h_sym)

      # --- Integer-valued poly via `print`. SP_TAG_INT path through
      # `sp_poly_to_s` returns `sp_int_to_s(...)`; CRuby's `print 42`
      # calls `Integer#to_s`. (Skipped for concat: CRuby raises
      # TypeError on `String + Integer`; the coercion path stays
      # behind `print` to preserve parity.)
      def show_print_int(node)
        raw = node["k"]
        text = raw.nil? ? "" : raw
        print "int="
        print text
        puts ""
      end
      h_int = { "k" => 42, "n" => "x" }
      show_print_int(h_int)

      # --- Explicit 4-part chained concat that exercises sp_str_concat4.
      # Uses bound prefix/suffix locals (rather than bare string literals)
      # so the part shape is unambiguous regardless of any literal-folding
      # optimization pass.
      def label_concat4(node)
        raw = node["text"]
        text = raw.nil? ? "" : raw
        prefix = "OPEN"
        suffix = "CLOSE"
        puts prefix + " " + text + " " + suffix
      end
      label_concat4(h_present)
      label_concat4(h_missing)

      # --- Variable-length sp_str_concat_arr (>= 5 parts) with bound
      # prefix / suffix to ensure the chain stays unambiguous.
      def label_wrap(node)
        raw = node["text"]
        text = raw.nil? ? "" : raw
        pre1 = "<"
        pre2 = "open "
        post1 = " close"
        post2 = ">"
        puts pre1 + pre2 + text + post1 + post2
      end
      label_wrap(h_present)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [ hello ]
      [ hello ]
      [  ]
      [  ]
      sym=hello
      int=42
      OPEN hello CLOSE
      OPEN  CLOSE
      <open hello close>
    OUT
  end

  it "concat source evaluated once" do
    result = ze0(<<~'RUBY')
      $calls = 0

      def src
        $calls += 1
        [1, 2, 3]
      end

      a = [0]
      a.concat(src)
      p a
      p $calls

      b = []
      b.concat(src, src)
      p b
      p $calls

      # a string's bytes: the source is a fresh array each time it is evaluated
      out = []
      out.concat("abc".bytes)
      out.concat("de".bytes)
      p out

      # mixed kinds still coerce
      poly = [:x]
      poly.concat([1, 2])
      p poly
      ints = [9]
      ints.concat([1, 2].map { |v| v })
      p ints
      strs = ["a"]
      strs.concat(%w[b c])
      p strs
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [0, 1, 2, 3]
      1
      [1, 2, 3, 1, 2, 3]
      3
      [97, 98, 99, 100, 101]
      [:x, 1, 2]
      [9, 1, 2]
      ["a", "b", "c"]
    OUT
  end

  it "container string index write" do
    result = ze0(<<~'RUBY')
      # `outer[i][k] = v` where the inner value is a String: spinel splices a String
      # into a FRESH buffer, so the result has to be stored back into outer's slot.
      # The store-back form existed for a statically Integer index and not for a boxed
      # one, so an index that came out of a container -- a destructured block parameter
      # whose receiver is a local, an element read -- wrote to the inner value alone
      # and the assignment was silently dropped (#4067).
      pairs = [[0, 1]]

      g = ["abc", "def"].map(&:dup)
      pairs.each { |r, c| g[0][c] = "*" }
      p g

      h = { 0 => +"abc" }
      pairs.each { |r, c| h[0][c] = "*" }
      p h

      # a single (non-destructured) boxed index, and one read out of an array
      idx = [[1]].first
      s = ["abcd"].map(&:dup)
      s[0][idx.first] = "1"
      p s

      # nesting an Array rather than a String still mutates in place
      t = [[1, 2], [3, 4]]
      pairs.each { |r, c| t[0][c] = 9 }
      p t

      # a nested Hash inner, keyed by the boxed index
      u = [{ 1 => "x" }]
      pairs.each { |r, c| u[0][c] = "y" }
      p u

      # a negative index counts from the end, and one past the end appends
      v = ["abc"].map(&:dup)
      [[-1]].each { |(n)| v[0][n] = "Z" }
      p v
      w = ["ab"].map(&:dup)
      [[2]].each { |(n)| w[0][n] = "c" }
      p w

      # out of range raises IndexError naming the original index
      x = ["ab"].map(&:dup)
      begin
        [[9]].each { |(n)| x[0][n] = "!" }
      rescue IndexError => e
        p e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a*c", "def"]
      {0 => "a*c"}
      ["a1cd"]
      [[1, 9], [3, 4]]
      [{1 => "y"}]
      ["abZ"]
      ["abc"]
      "index 9 out of string"
    OUT
  end

  it "conv to str duck" do
    result = ze0(<<~'RUBY')
      # to_str ducks at String-argument sites.
      class Sep
        def to_str
          "-"
        end
      end

      sep = Sep.new
      p "a" + sep
      p [1, 2, 3].join(sep)
      p "a-b".split(sep)
      p "a-b".index(sep)
      p "x".center(5, sep)
      p "a-b".start_with?(sep, "a")
      p "b-".end_with?(sep)
      s = +"a"
      s << sep
      p s
      p "a-b-c".sub(sep, "+")
      p "a-b".delete(sep)
      p "a-b-c".count(sep)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "a-"
      "1-2-3"
      ["a", "b"]
      1
      "--x--"
      true
      true
      "a-"
      "a+b-c"
      "ab"
      2
    OUT
  end

  it "default nil param with str return" do
    result = ze0(<<~'RUBY')
      # A method with `default = nil` whose body also returns a String from
      # another path: the function return type was `const char *` (string?)
      # but the param slot stayed `mrb_int` (the literal nil's int default),
      # so `return default` failed C compile. Fixed in #447.

      class Bag
        def initialize
          @data = {}
          @data["a"] = "alpha"
        end

        def fetch(key, default = nil)
          return @data[key] if @data.key?(key)
          default
        end
      end

      b = Bag.new
      puts b.fetch("a")
      puts b.fetch("missing").nil?

      # Top-level method variant.
      def lookup(map, key, default = nil)
        return map[key] if map.key?(key)
        default
      end

      m = { "x" => "ex" }
      puts lookup(m, "x")
      puts lookup(m, "z").nil?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      alpha
      true
      ex
      true
    OUT
  end

  it "define method with a symbol to proc block" do
    result = ze0(<<~'RUBY')
      # `define_method(:name, &:other)`. In CRuby the `&` conversion happens at
      # the CALL SITE, before rb_mod_define_method runs (proc.c:2872, which
      # rejects a bare Symbol as its second positional arg), so the body is the
      # symbol proc `->(recv, *rest) { recv.other(*rest) }` -- which is why the
      # defined method takes its RECEIVER as the first argument.

      class Widget
        define_method(:as_str, &:to_s)
      end
      class Gadget
        define_method :label, &:to_s
      end
      puts Widget.new.as_str(7)
      puts Gadget.new.label(8)
      p [1, 2, 3].map(&:to_s)
      p [10, 20, 30].inject(0, &:+)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      7
      8
      ["1", "2", "3"]
      60
    OUT
  end

  it "dynamic send with a non literal target" do
    _(ze0(<<~'RUBY').stdout).must_equal "hi\n"
      class Greeter
        define_method(:hello) do
          puts :hi
        end
      end

      name = :hello
      Greeter.new.send(name)
    RUBY
  end

  it "each cons each slice argument panic" do
    result = ze0(<<~'RUBY')
      begin
        [1, 2, 3].each_cons("l")
      rescue TypeError => e
        p e.class
      end
      begin
        [1, 2, 3].each_slice(:a)
      rescue TypeError => e
        p e.class
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      TypeError
    OUT
  end

  it "each slice and frozen hash filter error messages" do
    result = ze0(<<~'RUBY')
      # each_slice(0) says "invalid slice size", each_cons(0) just "invalid
      # size"; an in-place Hash filter on a frozen receiver raises FrozenError.

      begin; [1, 2, 3].each_slice(0).to_a; rescue ArgumentError => e; puts e.message; end
      begin; [1, 2, 3].each_cons(0).to_a; rescue ArgumentError => e; puts e.message; end
      begin; {a: 1}.freeze.reject! { |k, v| true }; rescue => e; puts e.class; end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      invalid slice size
      invalid size
      FrozenError
    OUT
  end

  it "each slice cons enumerator" do
    result = ze0(<<~'RUBY')
      # Blockless Array#each_slice(n) / Array#each_cons(n) return a materialized
      # Enumerator: a first-class value supporting to_a / next / peek / size / take /
      # first(n). The block and .map/.collect chain forms must keep working too.

      # --- blockless: a first-class Enumerator value ---
      e = [1, 2, 3, 4, 5].each_slice(2)
      p e.class
      p e.to_a
      p e.size
      p e.next
      p e.next
      p e.peek
      p e.next
      p [1, 2, 3, 4, 5].each_slice(2).first(2)
      p [1, 2, 3, 4, 5].each_slice(2).take(2)

      c = [1, 2, 3, 4].each_cons(2)
      p c.class
      p c.to_a
      p c.size

      # non-divisible and short receivers
      p [1, 2, 3, 4, 5].each_slice(3).to_a
      p [1, 2, 3].each_slice(5).to_a
      p [1].each_cons(2).to_a
      p %w[a b c d e].each_slice(2).to_a

      # --- assigned, then materialized ---
      slices = [10, 20, 30, 40, 50].each_slice(2)
      arr = slices.to_a
      p arr.length
      p arr

      # --- .map / .collect chains (fold-unrolled; must not regress) ---
      p [1, 2, 3, 4, 5].each_slice(2).map { |s| s.sum }
      p [1, 2, 3, 4, 5].each_slice(2).collect { |s| s.first }
      p [1, 2, 3, 4].each_cons(2).map { |a, b| a + b }
      p [1, 2, 3, 4].each_cons(2).map { |pair| pair }
      p [1, 2, 3, 4].each_cons(2).map { |(a, b)| a * b }
      p [1.5, 2.5, 3.5].each_slice(2).map { |s| s.sum }
      p %w[a b c].each_slice(2).map { |s| s.join }
      p [1, 2, 3, 4].each_cons(2).with_index.map { |w, i| [w, i] }

      # --- direct block form (yields each slice / window, returns receiver) ---
      acc = []
      [1, 2, 3, 4, 5].each_slice(2) { |s| acc << s }
      p acc
      acc2 = []
      [1, 2, 3, 4].each_cons(2) { |w| acc2 << w }
      p acc2

      # --- argument errors ---
      begin
        [1, 2, 3].each_slice(0).to_a
      rescue ArgumentError => err
        p err.message
      end
      begin
        [1, 2, 3].each_cons(0).to_a
      rescue ArgumentError => err
        p err.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Enumerator
      [[1, 2], [3, 4], [5]]
      3
      [1, 2]
      [3, 4]
      [5]
      [5]
      [[1, 2], [3, 4]]
      [[1, 2], [3, 4]]
      Enumerator
      [[1, 2], [2, 3], [3, 4]]
      3
      [[1, 2, 3], [4, 5]]
      [[1, 2, 3]]
      []
      [["a", "b"], ["c", "d"], ["e"]]
      3
      [[10, 20], [30, 40], [50]]
      [3, 7, 5]
      [1, 3, 5]
      [3, 5, 7]
      [[1, 2], [2, 3], [3, 4]]
      [2, 6, 12]
      [4.0, 3.5]
      ["ab", "c"]
      [[[1, 2], 0], [[2, 3], 1], [[3, 4], 2]]
      [[1, 2], [3, 4], [5]]
      [[1, 2], [2, 3], [3, 4]]
      "invalid slice size"
      "invalid size"
    OUT
  end

  it "each slice cons to a" do
    result = ze0(<<~'RUBY')
      # Array#each_slice(n) / #each_cons(n) without a block return an Enumerator;
      # materializing it with #to_a yields the array of slices / windows. Also the
      # single-param `.map { |s| ... }` chain binds the whole slice (not an element).
      p [1, 2, 3, 4, 5].each_slice(2).to_a       # [[1, 2], [3, 4], [5]]
      p [1, 2, 3, 4].each_cons(2).to_a           # [[1, 2], [2, 3], [3, 4]]
      p ["a", "b", "c", "d", "e"].each_slice(2).to_a

      nums = [1, 2, 3, 4, 5, 6]
      p nums.each_slice(3).to_a

      # the single-param map chain binds the slice as a whole
      p [1, 2, 3, 4, 5].each_slice(2).map { |s| s.sum }   # [3, 7, 5]
      p [1, 2, 3, 4].each_cons(2).map { |w| w.sum }       # [3, 5, 7]
      # many params destructure the slice into elements
      p [1, 2, 3, 4].each_slice(2).map { |a, b| a * b }   # [2, 12]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1, 2], [3, 4], [5]]
      [[1, 2], [2, 3], [3, 4]]
      [["a", "b"], ["c", "d"], ["e"]]
      [[1, 2, 3], [4, 5, 6]]
      [3, 7, 5]
      [3, 5, 7]
      [2, 12]
    OUT
  end

  it "each slice map" do
    result = ze0(<<~'RUBY')
      # Issue #829: array.each_slice(n).map { |x, y| ... } chains.
      a = [1, 3, 6, 10]
      p a.each_slice(2).map { |x, y| y - x }

      # A second chain to verify reuse.
      b = [2, 4, 8, 16]
      p b.each_slice(2).map { |x, y| y * x }

      # A single destructured param |(lo, hi)| splits the slice into its elements.
      c = [1, 3, 6, 10]
      p c.each_slice(2).map { |(lo, hi)| hi - lo }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [2, 4]
      [8, 128]
      [2, 4]
    OUT
  end

  it "empty array write over string" do
    result = ze0(<<~'RUBY')
      # An empty array literal carries no type of its own, so the union of a local's
      # writes kept the other write's type and the array was emitted into a slot
      # shaped for it: `a = ""; a = []` assigned an sp_IntArray to a const char *.
      # A non-empty literal already widened the slot to the boxed one.
      a = ""
      a = []
      a.each { |b| b }
      p a

      b = ""
      b = [1]
      p b

      c = 1
      c = []
      p c

      d = []
      d = ""
      p d

      e = []
      e << 1
      p e

      f = []
      p f
      p f.size

      g = {}
      g = []
      p g
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      []
      [1]
      []
      ""
      [1]
      []
      0
      []
    OUT
  end

  it "empty parens are nil and concat snapshots its sources" do
    result = ze0(<<~'RUBY')
      # `()` is nil (falsy as a condition, a nil value in expression position);
      # `Array#concat` copies all sources before appending, so a self-aliasing
      # `a.concat(a, a)` terminates at 6 elements rather than feeding itself.

      p(())
      p((() && true))
      n = 0
      while () ; n += 1 ; end
      p n
      a = [1, 2]
      a.concat(a, a)
      p a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      nil
      0
      [1, 2, 1, 2, 1, 2]
    OUT
  end

  it "empty symbol literal" do
    result = ze0(<<~'RUBY')
      # The empty symbol literal `:""` is a real SymbolNode whose content is
      # "". collect_sym_names skipped "" (its shared helper guards param-name
      # callers against a blank), so the symbol got no table entry and
      # compile_symbol_literal fell back to sp_sym_intern -- a function that is
      # only emitted when the intern path is otherwise needed, leaving an
      # `undefined reference to sp_sym_intern` link failure for a bare `:""`.

      s = :""
      puts s.to_s.length          #=> 0
      puts(s == :"")              #=> true
      puts(:"" == :"")           #=> true
      puts(:"" == :a)            #=> false

      # In a symbol array and as a value.
      arr = [:"", :a, :""]
      puts arr.length             #=> 3
      puts arr[0].to_s.length     #=> 0
      puts arr[1].to_s            #=> a

      # Round-trips through to_s/to_sym.
      t = "".to_sym
      puts(t == :"")             #=> true
      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0
      true
      true
      false
      3
      0
      a
      true
      done
    OUT
  end

  it "encode asks its fallback for an undefined character" do
    result = ze0(<<~'RUBY')
      # `fallback:` answers for each character the target has no room for:
      # a Hash, a Proc, a Method or anything that answers `[]`, given the
      # character in the encoding of the step that stopped.
      p "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"})
      p "\u{1F600}".encode("EUC-JP", fallback: ->(c){ "y" })
      p "\u{1F600}a".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"}.method(:[]))
      p "\u{1F600}".encode("ISO-8859-1", fallback: Hash.new { |h, k| k.bytesize.to_s })
      begin; "\u{1F600}".encode("EUC-JP", fallback: {}); rescue => e; p e; end
      begin; "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"\u{1F601}"}); rescue => e; p e; end
      begin; "\xFF".encode("EUC-JP", "UTF-8", fallback: {"\xFF"=>"x"}); rescue => e; p e; end
      begin; "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>1}); rescue => e; p e; end
      p "\u{1F600}".encode("EUC-JP", fallback: 5) rescue p $!
      p "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"}, undef: :replace)
      p "\xA4".b.force_encoding("ISO-8859-1").encode("US-ASCII", fallback: ->(c) { p [c, c.encoding]; "E" })
      p "é".encode("US-ASCII", fallback: ->(c) { "é" }) rescue p $!
      p "aア日".encode("Shift_JIS", "UTF-8").encode("ISO-8859-1", fallback: ->(c) { p [c.encoding, c.bytes]; "?" })
      p "\u{1F600}".encode("UTF-16LE", "UTF-8").encode("EUC-JP", fallback: ->(c) { p [c.encoding, c.bytes]; "?" })
      p "\x81".b.encode("UTF-8", fallback: ->(c) { p [c.encoding, c.bytes]; "B" })

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "x"
      "y"
      "xa"
      "4"
      #<Encoding::UndefinedConversionError: U+1F600 from UTF-8 to EUC-JP>
      #<ArgumentError: too big fallback string>
      #<Encoding::InvalidByteSequenceError: "\xFF" on UTF-8>
      #<TypeError: no implicit conversion of Integer into String>
      #<TypeError: no implicit conversion of String into Integer>
      "?"
      ["¤", #<Encoding:UTF-8>]
      "E"
      #<ArgumentError: too big fallback string>
      [#<Encoding:UTF-8>, [227, 130, 162]]
      [#<Encoding:UTF-8>, [230, 151, 165]]
      "a??"
      [#<Encoding:UTF-8>, [240, 159, 152, 128]]
      "?"
      [#<Encoding:BINARY (ASCII-8BIT)>, [129]]
      "B"
    OUT
  end

  it "enum chain splat sliceb wave6" do
    result = ze0(<<~'RUBY')
      # String#slice! statement forms, literal-splat expansion, each_codepoint
      # enumerator, hash comparator min/max, Hash#flat_map single-param pair,
      # chunk/slice enumerator chains (each/select/reject/flat_map),
      # &:sym.to_proc as a block argument, and lazy take(n).force.
      s = "hello"
      s.slice!(0)
      puts s
      s = "hello"
      s.slice!(1..2)
      puts s
      s = "hello"
      s.slice!(99)
      puts s
      p [1, 2, 3].min(*[2])
      p [1, 2, 3].first(*[2])
      add = ->(a, b) { a + b }
      p add.(*[3, 4])
      p "abc".each_codepoint.to_a
      h = { a: 1, b: 3, c: 2 }
      p h.min { |x, y| x[1] <=> y[1] }
      p h.max { |x, y| x[1] <=> y[1] }
      p h.minmax { |x, y| x[1] <=> y[1] }
      p({ a: [1, 2], b: [3, 4] }.flat_map { |pair| pair[1] })
      p({ a: 1, b: 2 }.flat_map { |k, v| [k, v] })
      [1, 1, 2, 3].chunk { |x| x }.each { |k, v| p [k, v] }
      p [1, 2, 3, 4].each_slice(2).select { |sl| sl.sum > 3 }
      p [1, 2, 3, 4].each_slice(2).reject { |sl| sl.sum > 3 }
      p [1, 2, 3, 4].each_cons(2).flat_map { |sl| sl }
      p ["a", "b"].map(&:upcase.to_proc)
      p [1, 2, 3, 4, 5, 6].lazy.map { |x| x * 2 }.take(3).force
      p (1..Float::INFINITY).lazy.map { |x| x * x }.take(3).force
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ello
      hlo
      hello
      [1, 2]
      [1, 2]
      7
      [97, 98, 99]
      [:a, 1]
      [:b, 3]
      [[:a, 1], [:b, 3]]
      [1, 2, 3, 4]
      [:a, 1, :b, 2]
      [1, [1, 1]]
      [2, [2]]
      [3, [3]]
      [[3, 4]]
      [[1, 2]]
      [1, 2, 2, 3, 3, 4]
      ["A", "B"]
      [2, 4, 6]
      [1, 4, 9]
    OUT
  end

  it "env nil string to s" do
    result = ze0(<<~'RUBY')
      v = ENV["SPINEL_NO_SUCH_1664"].to_s
      puts v == ""
      puts v.length
      puts v.nil?
      w = ENV["SPINEL_NO_SUCH_1664"]
      puts w.nil?
      ENV["SPINEL_T_1664"] = "val"
      puts ENV["SPINEL_T_1664"].to_s
      ENV["SPINEL_T_1664"] = nil
      puts ENV["SPINEL_T_1664"].nil?
      puts "x#{ENV["SPINEL_NO_SUCH_1664"]}y"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      0
      false
      true
      val
      true
      xy
    OUT
  end

  it "env string inference" do
    result = ze0(<<~'RUBY')
      # Issue #129: ENV["X"] was inferred as int at every call site even though
      # the dispatch correctly emits sp_str_dup_external(getenv(...)) returning
      # const char *. Fix is in `infer_operator_type`'s `[]` branch (early
      # ENV check) plus `compile_eq` for the `string == string` case (NULL-safe
      # via the new sp_str_eq runtime helper, since strcmp(NULL, ...) is UB and
      # segfaults on `"1" == ENV["UNSET"]`).
      #
      # Tests pin the four shapes from the issue body, plus the reverse-order
      # segfault case Sam called out.

      # Use a variable that's vanishingly unlikely to be set in any environment.
      UNSET = "SPINEL_TEST_VAR_THAT_DOES_NOT_EXIST_129"

      # 1. nil? on unset → true. Was: constant-folded to false at codegen.
      puts ENV[UNSET].nil?                      # true

      # 2. local capture + nil? roundtrip on unset → true.
      s = ENV[UNSET]
      puts s.nil?                                # true

      # 3. inline puts on unset → blank line. Was: printed pointer-as-int.
      puts ENV[UNSET]                            # (blank)

      # 4. equality on unset → false. Was: pointer-int compare, also always false
      #    but for the wrong reason (and would crash if the integer happened to
      #    be a valid pointer prefix).
      puts ENV[UNSET] == "1"                     # false

      # 5. Reverse-order equality on unset → false. Was: segfault. lt=string,
      #    at=int → fell through to strcmp("1", <int>), dereferencing the int
      #    as a pointer.
      puts "1" == ENV[UNSET]                     # false

      # 6. nil? on a likely-set var (PATH is universal on POSIX). The bootstrap
      #    needs PATH to find cc; if this test runs at all PATH is set. Pins the
      #    "set var" branch of the same fix.
      puts ENV["PATH"].nil?                      # false
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true

      false
      false
      false
    OUT
  end

  it "eq string vs int" do
    result = ze0(<<~'RUBY')
      # A String and an Integer are never == in Ruby (no implicit coercion).
      # Spinel used to lock the == operand types and emit sp_str_eq(str, int)
      # (or int == char*), failing to compile.
      p("3" == 3)
      p(3 == "3")
      p("3" != 3)
      p(3 != "3")
      # Same-type comparisons still behave normally.
      p("3" == "3")
      p(3 == 3)
      p("3" == "4")

      # Both operands are still evaluated (side effects preserved).
      $c = 0
      def bump
        $c = $c + 1
        "x"
      end
      p(bump == 5)
      p $c
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      false
      true
      true
      true
      true
      false
      false
      1
    OUT
  end

  it "eval non string argument is a type error" do
    _(ze0(<<~'RUBY').stdout).must_equal "no implicit conversion of Integer into String\n"
      begin
        eval(123)
      rescue TypeError => e
        puts e.message
      end
    RUBY
  end

  it "eval string interpolation inside source" do
    _(ze0(<<~'RUBY').stdout).must_equal "n=36\n"
      code = 'n = 6; "n=#{n * n}"'; puts eval(code)
    RUBY
  end

  it "exception super interpolated message" do
    result = ze0(<<~'RUBY')
      # A user exception subclass whose #initialize forwards an interpolated
      # string to super must report that interpolated message, with the
      # construction args bound to the initialize params -- not just the
      # first construction arg. Covers both raise E.new(...) and an assigned
      # E.new(...). Regression for #1048.
      class NotFoundError < StandardError
        def initialize(kind, id)
          super("not found - kind `#{kind}`, id `#{id}`")
        end
      end

      begin
        raise NotFoundError.new("company", "123")
      rescue => e
        puts e.message
      end

      err = NotFoundError.new("user", "42")
      puts err.message

      # Plain `super(msg)` (no interpolation) must still report the message.
      class Plain < StandardError
        def initialize(msg)
          super(msg)
        end
      end
      begin
        raise Plain.new("plain message")
      rescue => e
        puts e.message
      end

      # A default-valued param used in the super message resolves to its
      # default when no construction arg is given.
      class Defaulted < StandardError
        def initialize(detail = "fallback")
          super("oops: #{detail}")
        end
      end
      puts Defaulted.new.message
      puts Defaulted.new("custom").message
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      not found - kind `company`, id `123`
      not found - kind `user`, id `42`
      plain message
      oops: fallback
      oops: custom
    OUT
  end

  it "filter map" do
    result = ze0(<<~'RUBY')
      # Enumerable#filter_map (Ruby 2.7+): map, then drop falsy results, in one pass.
      # The result is a (boxed) array of the kept values; output matches whether the
      # block body is a nilable `expr if cond` or a plain transform.
      p [1, 2, 3, 4].filter_map { |x| x * 2 if x.even? }   # [4, 8]
      p [1, 2, 3].filter_map { |x| x * 2 }                 # always truthy -> like map
      p ["a", "", "b", ""].filter_map { |s| s.upcase unless s.empty? }
      p [1, 2, 3, 4, 5].filter_map { |x| x if x > 2 }

      # assigned and chained
      evens_doubled = [1, 2, 3, 4, 5, 6].filter_map { |x| x * 2 if x.even? }
      p evens_doubled
      p [1, 2, 3, 4, 5, 6].filter_map { |x| x * 2 if x.even? }.sum

      # nil and false are both dropped
      p [1, 2, 3].filter_map { |x| x.even? ? x : false }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [4, 8]
      [2, 4, 6]
      ["A", "B"]
      [3, 4, 5]
      [4, 8, 12]
      24
      [2]
    OUT
  end

  it "float round half modes and string hash sub" do
    result = ze0(<<~'RUBY')
      p 2.5.round(half: :even)
      p 3.5.round(half: :even)
      p 2.5.round(half: :down)
      puts "hello".sub("l", "l" => "X")
      puts "hello".gsub("l", "l" => "X")
      p 5 << 2.0
      p 100 >> 1.9
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      2
      4
      2
      heXlo
      heXXo
      20
      50
    OUT
  end

  it "frozen string double shovel" do
    result = ze0(<<~'RUBY')
      s001 = +"x"; s001.freeze
      p(begin; s001 << "y"; rescue FrozenError => e001; e001.receiver; end)
      p(begin; s001 << "y"; rescue FrozenError => e002; e002.receiver; end)
      s2 = +"a"; s2 << "b"; p s2
      s3 = "c".dup; s3.freeze; r3 = (begin; s3 << "d"; rescue FrozenError; :fz; end); p r3
      p s3.frozen?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "x"
      "x"
      "ab"
      :fz
      true
    OUT
  end

  it "frozen string global survives gc" do
    result = ze0(<<~'RUBY')
      # A heap string frozen by .freeze and bound to a constant is rooted via
      # sp_mark_user_globals, but the string-pool sweeper (sp_str_sweep) only kept
      # 0xfc-marked strings and freed the frozen (0xf1) one -- a GC use-after-free
      # on the next collect. Frozen globals must survive collection. (#1449)
      VERSION = "0.8.0".freeze
      NAME = ("spinel-" + "rt").freeze
      GC.start
      GC.start
      sum = 0.0
      i = 0
      while i < 50000
        a = [1.0, 2.0, 3.0, 4.0]
        sum += a[0]
        i += 1
      end
      GC.start
      puts VERSION
      puts NAME
      puts(sum > 0.0)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0.8.0
      spinel-rt
      true
    OUT
  end

  it "frozen string literal default" do
    result = ze0(<<~'RUBY')
      # fsl-true is Spinel's DEFAULT (no pragma in this file): literals are frozen,
      # mutation raises, and +"" / String.new / interpolation give mutable strings
      # that keep the full shared-mutation semantics.
      p "lit".frozen?
      s = "m"
      begin
        s << "!"
        puts "BUG: no raise"
      rescue FrozenError => e
        puts e.message
      end

      m = +"base"
      t = m
      m << "!"
      p t
      p m.equal?(t)

      n = String.new("n")
      arr = [n]
      n.upcase!
      p arr[0]

      who = "world"
      i = "hello #{who}"
      i << "!"
      p i
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      BUG: no raise
      "base!"
      true
      "N"
      "hello world!"
    OUT
  end

  it "frozen string literal gc root" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      first = "first literal"
      second = "second literal"

      GC.start

      puts first
      puts second
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      first literal
      second literal
    OUT
  end

  it "frozen string literal per file" do
    result = ze0(<<~'RUBY', files: {"frozen_string_literal_per_file/helper_frozen.rb" => "# frozen_string_literal: true\ndef frozen_helper_lit\n  \"helper frozen lit\"\nend\n\ndef frozen_helper_mutate\n  s = \"helper buf\"\n  s << \"y\"   # FrozenError: the literal comes from a pragma file\nend\n", "frozen_string_literal_per_file/helper_plain.rb" => "def plain_helper_lit\n  \"helper plain lit\"\nend\n\ndef plain_helper_build\n  s = \"plain\"\n  s << \"!\"\n  s\nend\n"})
      # Per-file frozen_string_literal: each literal carries its OWN file's pragma,
      # not the entry file's. helper_frozen.rb has the pragma; this entry file and
      # helper_plain.rb do not.
      require_relative "frozen_string_literal_per_file/helper_frozen"
      require_relative "frozen_string_literal_per_file/helper_plain"

      p frozen_helper_lit.frozen?   # true  -- literal from the pragma file
      p plain_helper_lit.frozen?    # false -- literal from a plain file
      p "entry lit".frozen?         # false -- entry has no pragma

      # mutating a pragma-file literal raises even when called from a plain file
      begin
        frozen_helper_mutate
        puts "BUG: no raise"
      rescue FrozenError => e
        puts e.message
      end

      # a plain-file literal stays mutable
      p plain_helper_build
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      false
      can't modify frozen String: "helper buf"
      "plain!"
    OUT
  end

  it "frozen string literal per file rev" do
    result = ze0(<<~'RUBY', files: {"frozen_string_literal_per_file/helper_plain.rb" => "def plain_helper_lit\n  \"helper plain lit\"\nend\n\ndef plain_helper_build\n  s = \"plain\"\n  s << \"!\"\n  s\nend\n"})
      # frozen_string_literal: true
      # Reverse direction: pragma entry + plain helper. The helper's literals stay
      # unfrozen and mutable; the entry's literals are frozen.
      require_relative "frozen_string_literal_per_file/helper_plain"

      p "entry lit".frozen?         # true
      p plain_helper_lit.frozen?    # false
      p plain_helper_build          # helper literals stay mutable
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      "plain!"
    OUT
  end

  it "frozen string literal pragma" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true
      # With the magic comment, string literals are frozen: frozen? is true and
      # mutation raises FrozenError (including through the mutable-string-buffer
      # optimization, which is disabled for pragma literals).
      def s(x); x; end

      p "abc".frozen?            # true
      p s("via method").frozen?  # true -- literal stays frozen through a call
      x = "local"
      p x.frozen?                # true
      p "interp #{1 + 1}".frozen?  # false -- interpolation builds a new string
      p "".frozen?               # true -- empty literal
      p :sym.frozen?             # true (symbols always)
      p [1, 2].frozen?           # false (array literal not affected by the pragma)

      # dup produces an unfrozen copy
      p "abc".dup.frozen?        # false

      # mutating a frozen literal raises; without the pragma this local would take
      # the in-place string-buffer path
      buf = "abc"
      begin
        buf << "y"
        puts "BUG: << did not raise"
      rescue FrozenError => e
        puts e.message
      end

      # a dup'd copy mutates freely
      cpy = "abc".dup
      cpy << "y"
      p cpy

      # synthesized strings are not literals: Symbol#to_s and Integer#to_s stay
      # unfrozen under the pragma
      p :sym.to_s.frozen?        # false
      p 42.to_s.frozen?          # false
      p __FILE__.frozen?         # true -- __FILE__ is a literal of its file
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      false
      true
      true
      false
      false
      can't modify frozen String: "abc"
      "abcy"
      false
      false
      true
    OUT
  end

  it "frozen string literal pragma freezes literals" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true
      p "abc".frozen?
      p "interp #{1 + 1}".frozen?
      p "abc".dup.frozen?
      buf = "abc"
      begin; buf << "y"; rescue FrozenError => e; puts e.message; end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      false
      can't modify frozen String: "abc"
    OUT
  end

  it "frozen strings" do
    result = ze0(<<~'RUBY')
      # Frozen strings: `-@`/`#dedup` interning and the frozen-mutation guard.

      # `-@` / `#dedup` intern by content: equal contents share one immortal frozen
      # object.
      p((-"hello").equal?(-"hello"))                 # true
      p("a".dedup.equal?("a".dedup))                 # true
      p(("he" + "llo").dedup.equal?("hello".dedup))  # true -- computed content interns

      # `-@` on an already-frozen string returns the receiver itself.
      a = "abc".freeze
      p((-a).equal?(a))                              # true

      # Different content interns to different objects.
      p((-"x").equal?(-"y"))                         # false
      p((-"frozen").frozen?)                         # true

      # Byte length counts real bytes, including an embedded NUL (nothing truncates).
      nul = "a\u0000b"
      p nul.bytesize                                 # 3
      p nul.dedup.bytesize                           # 3
      p("a\u0000b".dedup.equal?("a\u0000b".dedup))   # true

      # A frozen string raises on in-place mutation.
      begin
        (-"immutable") << "!"
      rescue FrozenError => e
        puts e.message                               # can't modify frozen String: "immutable"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      true
      false
      true
      3
      3
      true
      can't modify frozen String: "immutable"
    OUT
  end

  it "gc root ptr array literal" do
    _(ze0(<<~'RUBY').stdout).must_equal "0\n"
      # Regression test: `@x = [Klass.new(...)]` literal must keep the freshly
      # allocated PtrArray reachable across each element's allocation. Without
      # the SP_GC_ROOT on the temp, GC fired during a later Klass.new sees the
      # half-built array as unreachable and frees it, leaving a dangling
      # pointer that gets stored into the ivar.
      #
      # Each Tile holds a 256-float buffer (~2 KB) so that allocating a few
      # hundred Containers crosses the 256 KB GC threshold and forces a
      # collect mid-construction. Repro is non-deterministic without the fix
      # but reliably produces nonzero `errors` at this scale on darwin/arm64.

      class Tile
        attr_accessor :tag, :data
        def initialize(tag)
          @tag  = tag
          @data = Array.new(256, tag.to_f)
        end
      end

      class Container
        attr_accessor :a, :b, :c
        def initialize
          @a = [Tile.new(10), Tile.new(20), Tile.new(30), Tile.new(40)]
          @b = [Tile.new(11), Tile.new(21), Tile.new(31), Tile.new(41)]
          @c = [Tile.new(12), Tile.new(22), Tile.new(32), Tile.new(42)]
        end
      end

      containers = [Container.new]
      containers.pop

      n = 0
      while n < 1000
        containers.push(Container.new)
        n += 1
      end

      errors = 0
      ci = 0
      while ci < containers.length
        c = containers[ci]
        ta = c.a; tb = c.b; tc = c.c
        if ta.length != 4 || tb.length != 4 || tc.length != 4
          errors += 1
        else
          bad = false
          if ta[0].tag != 10 || ta[1].tag != 20 || ta[2].tag != 30 || ta[3].tag != 40
            bad = true
          end
          if tb[0].tag != 11 || tb[1].tag != 21 || tb[2].tag != 31 || tb[3].tag != 41
            bad = true
          end
          if tc[0].tag != 12 || tc[1].tag != 22 || tc[2].tag != 32 || tc[3].tag != 42
            bad = true
          end
          if bad
            errors += 1
          end
        end
        ci += 1
      end

      puts errors
    RUBY
  end

  it "gc stat string heap" do
    result = ze0(<<~'RUBY', path: "core/string/gc_stat_string_heap.rb")
      # GC.stat surfaces the string heap (str_bytes / str_count). Spinel allocates
      # string data on a separate malloc'd heap (sp_str_heap) that is deliberately
      # excluded from the object-heap `bytes` figure (see sp_str_alloc), so a
      # string-heavy workload can hold gigabytes that `bytes` never reflects.
      # Retaining 1000 strings makes str_count >= 1000 and str_bytes > 0.
      arr = []
      i = 0
      while i < 1000
        arr.push(i.to_s)
        i += 1
      end
      g = GC.stat
      puts "str_count >= 1000: " + (g["str_count"] >= 1000 ? "yes" : "no")
      puts "str_bytes > 0: " + (g["str_bytes"] > 0 ? "yes" : "no")
      puts "retained: " + arr.length.to_s
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "core/string/gc_stat_string_heap.rb:13:in '<main>': undefined method '>=' for nil (NoMethodError)\n\nputs \"str_count >= 1000: \" + (g[\"str_count\"] >= 1000 ? \"yes\" : \"no\")\n                                             ^^\n"
    _(result.status).must_equal 1
  end

  it "gc str arg rooted" do
    result = ze0(<<~'RUBY')
      # Regression: string arguments to allocating sp_str.c helpers must be
      # GC-rooted. sp_str_bytes / sp_str_codepoints allocate an IntArray before
      # reading the argument; when the argument is a fresh unrooted temp (an
      # interpolation result) and that allocation crosses the GC threshold, the
      # collection freed the argument mid-call and the result came back empty or
      # garbage (observed in the Doom port: Colormap lost a row, black screen).
      total = 0
      lens = 0
      keep = []
      200.times do |i|
        n = 3000 + (i % 7) * 500
        b = "row#{i}-#{'x' * n}".bytes
        total += b.sum
        lens += b.length
        keep << b if i % 10 == 0
      end
      puts total
      puts lens

      cps = 0
      clen = 0
      200.times do |i|
        n = 2000 + (i % 5) * 700
        c = "cp#{i}-#{'y' * n}".codepoints
        cps += c.sum
        clen += c.length
        keep << c if i % 10 == 0
      end
      puts cps
      puts clen
      puts keep.length
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      107743220
      898290
      82356620
      681090
      40
    OUT
  end

  it "grapheme clusters takes an invalid byte as a cluster" do
    result = ze0(<<~'RUBY')
      # grapheme_clusters matches \X from each place in turn, so a byte no
      # character holds is a cluster by itself; UTF-16 and UTF-32 cluster as
      # UTF-8 does, and an encoding that is not Unicode has characters alone.

      def show(s)
        c = s.grapheme_clusters
        p [c, c.map(&:encoding).uniq, s.each_grapheme_cluster.size]
      end
      show "a\xffb́c"
      show "\xff\xfe".b.force_encoding("UTF-8")
      show "é̂x\r\n👨‍👩‍👧🇯🇵"
      show "abc"
      show ""
      show "é".encode("UTF-16LE")
      show "a👍🏽b".encode("UTF-32BE")
      show "e\xCC\x81".b
      show "e\xCC\x81".force_encoding("US-ASCII")
      show "日本".encode("EUC-JP")
      class Sub < String; end
      show Sub.new("éx")
      r = +""
      "ab́".each_grapheme_cluster { |g| r << "[#{g}]" }
      p r

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [["a", "\xFF", "b́", "c"], [#<Encoding:UTF-8>], 4]
      [["\xFF", "\xFE"], [#<Encoding:UTF-8>], 2]
      [["é̂", "x", "\r\n", "👨‍👩‍👧", "🇯🇵"], [#<Encoding:UTF-8>], 5]
      [["a", "b", "c"], [#<Encoding:UTF-8>], 3]
      [[], [], 0]
      [["e\u0301"], [#<Encoding:UTF-16LE>], 1]
      [["a", "\u{1F44D}\u{1F3FD}", "b"], [#<Encoding:UTF-32BE>], 3]
      [["e", "\xCC", "\x81"], [#<Encoding:BINARY (ASCII-8BIT)>], 3]
      [["e", "\xCC", "\x81"], [#<Encoding:US-ASCII>], 3]
      [["\x{C6FC}", "\x{CBDC}"], [#<Encoding:EUC-JP>], 2]
      [["é", "x"], [#<Encoding:UTF-8>], 2]
      "[a][b́]"
    OUT
  end

  it "gsub bang without a replacement answers an enumerator" do
    result = ze0(<<~'RUBY')
      e = (+"hello world").gsub!(1)
      p e.class
      class P < String; end
      e2 = P.new("hello").gsub!("l")
      p e2.class
      p((+"hello").each_line.to_a)
      begin; (+"a").replace(1); rescue TypeError => e; p e.message; end
      begin; (+"a").replace(nil); rescue TypeError => e; p e.message; end
      o = Object.new; def o.to_str = "conv"
      p((+"a").replace(o))
      p (+"abc").gsub!(/b/).to_a

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Enumerator
      Enumerator
      ["hello"]
      "no implicit conversion of Integer into String"
      "no implicit conversion of nil into String"
      "conv"
      ["b"]
    OUT
  end

  it "hash array string batch8" do
    result = ze0(<<~'RUBY')
      # Hash.try_convert, Array member?/entries/find_all/
      # grep(variable pattern or block)/chain, String tr_s!/delete_prefix!/
      # delete_suffix!/byteindex(Regexp)/dedup.

      # Hash class methods
      p(Hash.try_convert({ a: 1 }))
      p(Hash.try_convert("x"))
      p(Hash.try_convert(nil))

      # Array#member? (include? alias), #entries (to_a alias)
      p([1, nil, 2].member?(nil))
      p([].member?(1))
      p((1..3).member?(2))
      a = []
      p(a.entries)
      b = [1, 2]
      p(b.entries)

      # find_all is select (blockless enumerator chain and empty receiver)
      p([1, 2, 3].find_all.with_index { |x, i| i.even? })
      p([].find_all { |x| x > 0 })
      p([1, 2, 3, 4].find_all { |x| x.odd? })

      # grep/grep_v with variable Class/Range patterns and the block form
      cls = String
      p([1, "a", 2, "b"].grep(cls))
      r = 1..2
      p([1, "a", 2, "b"].grep(r))
      p([1, "a", 2, "b"].grep(Integer) { |x| x * 10 })
      p([1, "a", 2, "b"].grep_v(Integer))
      p([1, 2, 3].grep(2..3) { |x| x + 100 })

      # eager chain
      p([1, 2].chain([3, 4]).to_a)
      p([1, 2].chain([3], [4, 5]).to_a)

      # String bang mutators and byte searches
      p "hello".tr_s!("l", "r")
      p "hello".delete_prefix!("hel")
      p "hello".delete_suffix!("llo")
      p "abc".delete_prefix!("x")
      p "hello".byteindex("l")
      p "hello".byteindex(/l+/)
      p "hello".byterindex("l")
      p "hello".byterindex(/l+/)
      p "hello".byteindex(/x/)
      p "hello".dedup
      p "hello".dedup.frozen?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      {a: 1}
      nil
      nil
      true
      false
      true
      []
      [1, 2]
      [1, 3]
      []
      [1, 3]
      ["a", "b"]
      [1, 2]
      [10, 20]
      ["a", "b"]
      [102, 103]
      [1, 2, 3, 4]
      [1, 2, 3, 4, 5]
      "hero"
      "lo"
      "he"
      nil
      2
      2
      3
      3
      nil
      "hello"
      true
    OUT
  end

  it "hash default array fetch concat wave9" do
    result = ze0(<<~'RUBY')
      # Hash store/default reader+writer/Hash.new(default) literal folds,
      # Array concat value form, fetch with default or block, repeated_permutation.
      p({ a: 1 }.store(:b, 2))
      h = { "x" => 1 }
      p(h.store("y", 5))
      p h
      g = { 1 => "a" }
      g.store(2, "b")
      p g
      p(Hash.new(7).default)
      p(({}.default = 9))
      p(Hash.new(0)[:missing])
      p(Hash.new("d")["nope"])
      h = Hash.new(42)
      p h.default
      h.default = 5
      p h.default
      p h[:zzz]
      a = [1, 2]
      a.concat([3, 4])
      p a
      b = [1, 2]
      r = b.concat([3])
      p r
      p([10, 20, 30].fetch(5, "default"))
      p([10, 20, 30].fetch(1, "default"))
      p([10, 20, 30].fetch(5) { |i| "missing #{i}" })
      p([10, 20, 30].fetch(-1))
      p([10, 20, 30].fetch(1) { |i| i * 100 })
      p([10, 20, 30].fetch(9) { |i| i * 100 })
      mixed = [1, "x"]
      p(mixed.fetch(7, :none))
      p([1, 2].concat([3, 4]))
      b = [1, 2]
      r = b.concat([3])
      p r
      p b
      s = %w[a b]
      p(s.concat(%w[c], %w[d e]))
      sc = [1, 2]
      p(sc.concat(sc))
      p([1, 2].repeated_permutation(2).to_a)
      p(%w[a b].repeated_permutation(2).to_a)
      p([1, 2, 3].repeated_permutation(0).to_a)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      2
      5
      {"x" => 1, "y" => 5}
      {1 => "a", 2 => "b"}
      7
      9
      0
      "d"
      42
      5
      5
      [1, 2, 3, 4]
      [1, 2, 3]
      "default"
      20
      "missing 5"
      30
      20
      900
      :none
      [1, 2, 3, 4]
      [1, 2, 3]
      [1, 2, 3]
      ["a", "b", "c", "d", "e"]
      [1, 2, 1, 2]
      [[1, 1], [1, 2], [2, 1], [2, 2]]
      [["a", "a"], ["a", "b"], ["b", "a"], ["b", "b"]]
      [[]]
    OUT
  end

  it "hash default proc symbol" do
    result = ze0(<<~'RUBY')
      h = {}
      p h.public_send(:default_proc=, :a).class
      p h.default_proc.class
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Proc
      Proc
    OUT
  end

  it "hash shorthand and interpolated symbols" do
    result = ze0(<<~'RUBY')
      x = 1
      name = "n"
      p({x:, name:})
      def kw(a:, b:); [a, b]; end
      a = 10
      b = 20
      p kw(a:, b:)
      w = "world"
      p :"hello_#{w}"
      p :"a#{1 + 1}b"
      p :"plain"
      p :"a#{1}b".class
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      {x: 1, name: "n"}
      [10, 20]
      :hello_world
      :a2b
      :plain
      Symbol
    OUT
  end

  it "hash shorthand str" do
    result = ze0(<<~'RUBY')
      # Hash shorthand with string-valued local variable.
      # Regression: scan_locals's first pass infers the hash literal value type
      # before the local's type lands in @scope_names, so `{first:}` mis-types
      # as int. Pre-fix: declared sp_SymIntHash / sp_SymPolyHash but built with
      # string values -> incompatible-pointer C error or unknown-type error.

      # Single string-valued shorthand
      name = "ada"
      who1 = {name:}
      puts who1[:name]
      puts who1.length

      # Mixed string-valued shorthand and explicit string pair
      first = "ada"
      who2 = {first:, last: "lovelace"}
      puts who2[:first]
      puts who2[:last]
      puts who2.length

      # Compare against the explicit equivalent (both should produce the same output)
      who3 = {first: first, last: "lovelace"}
      puts who3[:first]
      puts who3[:last]
      puts who3.length

      # Three string-valued shorthand keys
      a = "alpha"
      b = "beta"
      c = "gamma"
      who4 = {a:, b:, c:}
      puts who4[:a]
      puts who4[:b]
      puts who4[:c]
      puts who4.length

      # Mixed shorthand and explicit pairs round-tripping a single value type
      x = "one"
      y = "two"
      who5 = {x:, y:, z: "three"}
      puts who5[:x]
      puts who5[:y]
      puts who5[:z]
      puts who5.length

      # Has-key membership over the inferred hash type
      puts who1.has_key?(:name)
      puts who2.has_key?(:first)
      puts who2.has_key?(:missing)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ada
      1
      ada
      lovelace
      2
      ada
      lovelace
      2
      alpha
      beta
      gamma
      3
      one
      two
      three
      3
      true
      true
      false
    OUT
  end

  it "hash slice" do
    result = ze0(<<~'RUBY')
      # Hash#slice picks the given keys into a fresh hash (missing keys skipped).
      p({ a: 1, b: 2, c: 3 }.slice(:a, :b))
      p({ a: 1 }.slice(:zz))
      h = { "x" => 1, "y" => 2 }
      p h.slice("y")
      p({ a: 1, b: 2 }.except(:a))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      {a: 1, b: 2}
      {}
      {"y" => 2}
      {b: 2}
    OUT
  end

  it "hash str value poly coerce" do
    result = ze0(<<~'RUBY')
      # Storing a poly value (one that holds a String/Integer at runtime) into a
      # typed-value hash (Hash[String,String] / Hash[String,Integer]) must coerce the
      # poly to the hash's value representation -- the setter takes const char* /
      # mrb_int, not sp_RbVal. The receiver is a method-return hash (its value type is
      # fixed by the body, so an external poly store can't re-widen it to a poly hash).

      def fresh_strs
        h = {}
        h["seed"] = "x"
        h            # Hash[String, String]
      end

      def fresh_ints
        h = {}
        h["seed"] = 0
        h            # Hash[String, Integer]
      end

      data = { "k" => "v", "n" => 5 }   # heterogeneous -> poly values

      # expression position: a poly string value into a Hash[String,String]
      puts(fresh_strs["k"] = data["k"])   # "v"
      # expression position: a poly int value into a Hash[String,Integer]
      puts(fresh_ints["n"] = data["n"])   # 5

      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      v
      5
      done
    OUT
  end

  it "hash string key snapshot" do
    result = ze0(<<~'RUBY')
      # A String KEY is snapshotted on store: the hash keeps a frozen copy, so
      # mutating the string you stored under can never rewrite a key already in the
      # table. A stored VALUE is the opposite -- the shared handle, mutable through
      # the hash. Both halves matter, so both are asserted here.

      # --- the snapshot, through every way a key gets in ---------------------------
      k = "key"

      literal = { k => 1 }
      assign = {}
      assign[k] = 1
      stored = {}
      stored.store(k, 1)
      merged = {}.merge(k => 1)
      built = [[k, 1]].to_h
      bracketed = Hash[k, 1]
      folded = [k].each_with_object({}) { |s, h| h[s] = 1 }

      k << "-mut"

      p literal.keys, assign.keys, stored.keys, merged.keys
      p built.keys, bracketed.keys, folded.keys
      p k

      # The copy is frozen; the caller's string is untouched.
      h = {}
      s = "fresh"
      h[s] = 1
      p h.keys.first.frozen?
      p s.frozen?
      p h.keys.first.equal?(s)

      # An already-frozen key needs no copy -- it is stored as-is.
      f = "immutable".freeze
      h2 = { f => 1 }
      p h2.keys.first.equal?(f)

      # Lookup still works by content after the caller mutates its own string.
      h3 = {}
      name = "ada"
      h3[name] = 1
      name << "!"
      p h3["ada"]
      p h3["ada!"]
      p h3.size

      # --- the copy carries the key's own encoding, not a UTF-8 reinterpretation ---
      bin = "caf\xC3\xA9".b
      h4 = { bin => :binary }
      p h4.keys.first.encoding
      p h4.keys.first.bytes
      p h4.keys.first == bin

      # --- identity keying keeps YOUR object: its identity IS the key --------------
      h5 = {}.compare_by_identity
      id_key = "same"
      h5[id_key] = 1
      h5["same"] = 2
      p h5.size
      p h5.keys.first.equal?(id_key)
      p h5.keys.first.frozen?

      # --- VALUES stay shared: mutation through the hash is visible ----------------
      v = { k: "value" }
      v[:k] << "!"
      p v[:k]
      shared = "outer"
      v[:s] = shared
      v[:s].upcase!
      p shared
      p v[:s].frozen?

      # --- non-String keys are stored as-is ----------------------------------------
      arr = [1, 2]
      h6 = { arr => :a }
      arr << 3
      p h6.keys
      p h6.keys.first.equal?(arr)

      # --- dup/clone of a hash keep the frozen keys, no re-copy --------------------
      h7 = { "d" => 1 }
      p h7.dup.keys.first.equal?(h7.keys.first)
      p h7.clone.keys.first.frozen?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["key"]
      ["key"]
      ["key"]
      ["key"]
      ["key"]
      ["key"]
      ["key"]
      "key-mut"
      true
      false
      false
      true
      1
      nil
      1
      #<Encoding:BINARY (ASCII-8BIT)>
      [99, 97, 102, 195, 169]
      true
      2
      true
      false
      "value!"
      "OUTER"
      false
      [[1, 2, 3]]
      true
      true
      true
    OUT
  end

  it "hash strstr merge" do
    result = ze0(<<~'RUBY')
      a = { "O" => "Off-topic", "" => "Cancel" }
      b = a.merge({ "Q" => "Low Quality" })
      puts b.length
      p b["Q"]
      p a.length
      c = a.merge({ "O" => "Override" })
      p c["O"]
      p c.length
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      "Low Quality"
      2
      "Override"
      2
    OUT
  end

  it "hash value split widen" do
    result = ze0(<<~'RUBY')
      # Sibling to #437. `h = {}; h[pa[i]] = pb[i]` where both `pa` and
      # `pb` come from `split` results inside a method body. #437 added
      # str_int_hash → str_str_hash widening in refine_locals_multi_pass_full
      # but the analogous merge rule in refine_method_body_locals was
      # missing, so `def f; ... end` shapes stayed at str_int_hash even
      # after pass 2 resolved both key and value as string.

      def build_str_str(a, b)
        pa = a.split("/")
        pb = b.split("/")
        h = {}
        i = 0
        while i < pa.length
          h[pa[i]] = pb[i]
          i += 1
        end
        h
      end

      r = build_str_str("a/b", "x/y")
      puts r["a"]
      puts r["b"]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      x
      y
    OUT
  end

  it "hello prints a symbol" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      puts :ok
    RUBY
  end

  it "incompatible concatenation raises the compatibility error" do
    result = ze0(<<~'RUBY')
      # Two differently-encoded NON-7-bit strings; CRuby's exact message,
      # receiver's encoding first in its `inspect` form. `<<` past 255 on a
      # byte-encoded receiver is the RangeError, not a promotion.

      begin
        "é".b + "é"
      rescue Encoding::CompatibilityError => e
        puts "plus: #{e.message}"
      end
      begin
        ("é".b) << "é"
      rescue Encoding::CompatibilityError => e
        puts "shovel: #{e.message}"
      end
      begin
        "".b << 0x1F600
      rescue RangeError => e
        puts "range: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      plus: incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8
      shovel: incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8
      range: 128512 out of char range
    OUT
  end

  it "inherited kwarg nil default string ivar" do
    result = ze0(<<~'RUBY')
      # Three intertwined fixes around kwarg param inference on an
      # inherited instance method:
      #
      # 1. Analyze: the inh_ branch (bare call inside a class body that
      #    resolves to a parent's method) was iterating arg_ids by
      #    position, so a trailing `KeywordHashNode` landed on whatever
      #    positional slot came next instead of the matching kwarg
      #    slot. `head(204, content_type: "x")` widened `content_type`'s
      #    slot with the *whole keyword hash type* (sym_str_hash) and
      #    left it un-pinned to "string". Route through
      #    widen_ptypes_from_args so each `key: value` lands on the
      #    named-param slot.
      #
      # 2. Codegen: compile_typed_call_args had the same positional-
      #    only loop on the emit side. Extract KeywordHashNode pairs
      #    up front, inject them into arg_ids at the matching named
      #    slot, and route the existing per-arg type-coerce loop
      #    through that. Without this, the kwarg expression
      #    disappeared at the call site — `head(204, content_type:
      #    "application/json")` emitted `sp_Base_head(self, 204, 0)`.
      #
      # 3. Analyze ivar heterogeneity: the same-base nullable variant
      #    case (`@x = "hi"` + `@x = some_nullable_string_param`)
      #    counted as 2 distinct observations and widened the ivar to
      #    poly. Both write the same C storage (const char *) with
      #    NULL as the nil sentinel. update_ivar_type and
      #    finalize_ivar_heterogeneity now treat T + T? as a single
      #    nullable observation, preserving the typed pointer slot.

      class Base
        def initialize
          @content_type = "text/html"
        end

        def head(status, content_type: nil)
          @status = status
          @content_type = content_type unless content_type.nil?
          nil
        end

        def show_content_type
          @content_type
        end
      end

      class Child < Base
        def render_json
          head(204, content_type: "application/json")
        end

        def render_html
          head(200)
        end
      end

      c = Child.new
      c.render_json
      puts c.show_content_type
      c2 = Child.new
      c2.render_html
      puts c2.show_content_type
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      application/json
      text/html
    OUT
  end

  it "inject symbol op" do
    result = ze0(<<~'RUBY')
      # inject/reduce with an arithmetic operator passed as a symbol-to-proc block
      # (inject(&:+)). Previously emitted an empty accumulation loop with an
      # undeclared accumulator. The positional-symbol forms are unchanged. The
      # symbol-to-proc fold seeds with the first element (no-init-value form).
      p [1, 2, 3].inject(&:+)
      p [1, 2, 3, 4].inject(&:*)
      p [10, 3, 2].inject(&:-)
      p [1, 2, 3].inject(:+)
      p [1, 2, 3].inject(10, :+)
      p [100, 20, 3].inject(&:+)
      p [2, 3, 4].inject(&:*)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      6
      24
      5
      6
      16
      123
      24
    OUT
  end

  it "inject symbol to proc" do
    result = ze0(<<~'RUBY')
      # Enumerable#inject / #reduce with a symbol-to-proc argument
      # (`inject(&:&)`) and the seedless first-element fold.
      #
      # `inject(&:sym)` on a non-int_array receiver reached compile_reduce_block
      # with a synthetic accumulator `_acc` that was never declared in C
      # (`'lv__acc' undeclared`). The seedless fold also seeded the accumulator
      # with `0`/NULL and iterated from index 0 instead of seeding with the
      # first element and iterating from index 1 — wrong for non-additive ops
      # (`*` gave 0) and a NULL deref for array elements (`a & b` segfaulted).
      #
      # Fix: seed seedless folds with arr[0] (loop from 1), type the result as
      # the element type in analyze, declare the synthetic `_acc`, and lower
      # `&:sym` / `:sym` to `acc.sym(x)` for the modeled element/op pairs.

      # 1. Symbol-to-proc set operations on an array of int arrays.
      p [[1, 2, 3], [2, 3, 4]].inject(&:&)        #=> [2, 3]
      p [[1, 2], [2, 3], [3, 4]].inject(&:|)      #=> [1, 2, 3, 4]
      p [[1, 2, 3, 4], [2, 3]].inject(&:-)        #=> [1, 4]

      # 2. Single-element array: the fold returns that element (loop body
      #    never runs).
      p [[5, 6, 7]].inject(&:&)                   #=> [5, 6, 7]

      # 3. Symbol-to-proc arithmetic on int arrays (folds inline upstream).
      p [1, 2, 3, 4].inject(&:+)                  #=> 10
      p [1, 2, 3, 4].inject(&:*)                  #=> 24

      # 4. Seedless explicit-block fold seeds with the first element, not 0.
      p [1, 2, 3, 4].inject { |a, b| a * b }      #=> 24
      p [10, 3, 2].inject { |a, b| a - b }        #=> 5

      # 5. Seedless explicit-block fold over an array of arrays (was a NULL
      #    deref segfault when the accumulator seeded as NULL).
      p [[1, 2, 3], [2, 3, 4]].inject { |a, b| a & b }   #=> [2, 3]

      # 6. Result flows through a local, exercising the inferred result type.
      inter = [[1, 2, 3], [2, 3, 4], [3, 2, 5]].inject(&:&)
      puts inter.length                           #=> 2
      p inter                                     #=> [2, 3]

      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [2, 3]
      [1, 2, 3, 4]
      [1, 4]
      [5, 6, 7]
      10
      24
      24
      5
      [2, 3]
      2
      [2, 3]
      done
    OUT
  end

  it "inject symbol variable" do
    result = ze0(<<~'RUBY')
      # inject/reduce with the operator Symbol held in a VARIABLE: the sole-
      # assignment lookthrough resolves the op statically, in both the emit and
      # the result-type inference (was: typed as the symbol itself).
      s = :+
      p [3, 1, 2].inject(s)
      p [3, 1, 2].reduce(s)
      m = :*
      p [2, 3, 4].reduce(m)
      p [2.5, 1.5].inject(10.0, s)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      6
      6
      24
      14.0
    OUT
  end

  it "instance eval string mutates an ivar" do
    _(ze0(<<~'RUBY').stdout).must_equal "3\n"
      class Counter
        def initialize
          @n = 0
        end
      end
      c = Counter.new
      c.instance_eval("@n = @n + 3")
      puts c.instance_eval("@n")
    RUBY
  end

  it "instance eval string reads the receivers ivars" do
    _(ze0(<<~'RUBY').stdout).must_equal "105\n"
      class Account
        def initialize(n)
          @balance = n
        end
      end
      acct = Account.new(100)
      src = "@balance + 5"
      puts acct.instance_eval(src)
    RUBY
  end

  it "instance eval string rebinds self to a literal receiver" do
    _(ze0(<<~'RUBY').stdout).must_equal "OLLEH\n"
      src = "upcase.reverse"; puts "hello".instance_eval(src)
    RUBY
  end

  it "int element alias not string" do
    result = ze0(<<~'RUBY')
      # `b0 = bytes[i]` where bytes holds Integers, in a method that also appends to a
      # String: the mutator table is name-keyed, so `b0 << 4` (an integer shift) read
      # as a string append and the element was bound to a string handle (#3971).
      ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

      def encode(s)
        bytes = s.bytes
        n = bytes.length
        out = +""
        i = 0
        while i + 3 <= n
          b0 = bytes[i]
          b1 = bytes[i + 1]
          b2 = bytes[i + 2]
          out << ALPHABET[(b0 >> 2) & 0x3F].to_s
          out << ALPHABET[((b0 << 4) | (b1 >> 4)) & 0x3F].to_s
          out << ALPHABET[((b1 << 2) | (b2 >> 6)) & 0x3F].to_s
          out << ALPHABET[b2 & 0x3F].to_s
          i = i + 3
        end
        out
      end

      p encode("Man")
      p encode("any carnal pleasure")

      # the string alias through a container still works
      rows = [+"abc"]
      r = rows[0]
      r.upcase!
      p [rows, r.equal?(rows[0])]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "TWFu"
      "YW55IGNhcm5hbCBwbGVhc3Vy"
      [["ABC"], true]
    OUT
  end

  it "integer bit slice negative start and width" do
    result = ze0(<<~'RUBY')
      # Integer#[start, len]: a negative start shifts left (5[-1,3] == 2), a
      # negative len keeps the whole shifted value with no mask (5[2,-1] == 1,
      # 255[0,-5] == 255), a zero len selects nothing, and a positive len masks.

      p 0b1011010[1, 3]
      p 255[0, 4]
      p 5[2, -1]
      p 5[-1, 3]
      p 255[0, -5]
      p 7[0, 0]
      p(-1[60, 8])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      15
      1
      2
      255
      0
      255
    OUT
  end

  it "interp adjacent concat" do
    result = ze0(<<~'RUBY')
      # adjacent string literals joined by backslash-continuation, each with its own
      # interpolation -- parses to nested InterpolatedStringNodes
      def svg(px, inner)
        "<a width='#{px}' " \
        "height='#{px}'>#{inner}</a>"
      end

      # three-way adjacency mixing plain and interpolated parts
      def three(a, b)
        "[" \
        "#{a}-#{b}" \
        "]"
      end

      # adjacency where one fragment is a plain literal (no interpolation)
      def tail(n)
        "n=#{n}" \
        " done"
      end

      puts svg(16, "x")
      puts three("L", "R")
      puts tail(7)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      <a width='16' height='16'>x</a>
      [L-R]
      n=7 done
    OUT
  end

  it "interp symbol" do
    result = ze0(<<~'RUBY')
      # InterpolatedSymbolNode -- `:"foo_#{x}"`.
      #
      # Lowered to InterpolatedStringNode + sp_intern at codegen side.
      # The parser emits InterpolatedSymbolNode with parts; codegen
      # treats it like InterpolatedStringNode then routes through
      # the intern helper for symbol identity.

      x = "world"
      sym = :"hello_#{x}"
      puts sym                # hello_world

      n = 42
      sym2 = :"item_#{n}"
      puts sym2               # item_42

      # Symbol passed through a method
      def kind(s) = s.to_s
      puts kind(:"prefix_#{x}")   # prefix_world
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello_world
      item_42
      prefix_world
    OUT
  end

  it "interpolate handles" do
    result = ze0(<<~'RUBY')
      r, w = IO.pipe
      s = "#{r} #{w}"
      p s.start_with?("#<IO:")
      p s.include?(" #<IO:")
      pr = proc { 1 }
      p "#{pr}".start_with?("#<Proc:")
      f = Fiber.new { Fiber.yield 1 }
      p "#{f}".start_with?("#<Fiber:")
      e = [1, 2].each
      p "#{e}".start_with?("#<Enumerator")
      r.close
      w.close
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      true
      true
    OUT
  end

  it "interpolation multistmt" do
    result = ze0(<<~'RUBY')
      # Issue #729. `"#{stmt1; stmt2; ...; stmtN}"` should evaluate every
      # statement in source order (for side effects) and use the LAST
      # statement's value in the string. spinel used to take stmts.first,
      # silently dropping later statements -- losing both their effects on
      # locals and the correct interpolation value.

      y = 0
      s = "#{y = 10; y = 20; y}"
      puts s
      puts y

      # Side effect persists outside the interpolation.
      counter = 0
      "#{counter += 1; counter += 1; counter += 1}"
      puts counter
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      20
      20
      3
    OUT
  end

  it "interpolation symbol name" do
    result = ze0(<<~'RUBY')
      # `"#{sym}"` should render the symbol's name, not its int id.
      # Pre-fix compile_interpolated had no symbol arm in its
      # type-dispatch switch, so the default int path emitted the raw
      # `sp_sym` value (`0`, `1`, ...) instead of routing through
      # sp_sym_to_s. Issue #633.

      s = :hello
      puts s
      puts "#{s}"
      puts s.to_s
      puts "x_#{s}_y"

      # Multiple symbols + literal mix in one interpolation.
      a = :alpha
      b = :beta
      puts "#{a}-#{b}"

      # Symbol from a method return; the call-site infers symbol type
      # and the same arm should fire.
      def make_sym
        :payload
      end
      puts "tag=#{make_sym}"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello
      hello
      hello
      x_hello_y
      alpha-beta
      tag=payload
    OUT
  end

  it "interpolation takes multi statement empty and braceless forms" do
    result = ze0(<<~'RUBY')
      p "v=#{1; 2}"
      p "v=#{a = 3; a * 2}"
      p a
      p "x#{}y"
      $g = "glob"
      class C
        def initialize; @iv = "ivar"; end
        def show; "iv=#@iv g=#$g"; end
      end
      p C.new.show
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "v=2"
      "v=6"
      3
      "xy"
      "iv=ivar g=glob"
    OUT
  end

  it "io buffer for aliases its string" do
    result = ze0(<<~'RUBY')
      # `IO::Buffer.for(string)` shares the STRING's own bytes, so a buffer write
      # is visible through the string before the block ends -- CRuby's buffer
      # really aliases its string's storage, and this one does too.
      #
      # The earlier answer copied in and copied back at block exit: the END state
      # matched and a mid-block read of the string saw the original. The recorded
      # fix shape was a stable byte address for the string, which zeo's
      # `Arc<Mutex<StrBuf>>` does not have and which is a value-model change.
      #
      # It was not needed. The buffer already held its source string, so the
      # backing can BE that string (`Mem::Str`): every read and write locks it and
      # uses its bytes in place. The string's own mutex is what CRuby models as
      # "the string is locked for the duration", and no address is pinned at all.
      # Nothing is copied in either direction now.
      $stderr.reopen(IO::NULL)
      s = +"abcdef"
      IO::Buffer.for(s) do |b|
        b.set_value(:U8, 0, 0x5a)
        p s
        b.set_value(:U8, 5, 0x5a)
        p s
      end
      p s

      # The readonly (no-block) form shares the same bytes, and refuses a write.
      r = +"hello"
      view = IO::Buffer.for(r)
      p view.get_string
      p view.readonly?
      begin
        view.set_value(:U8, 0, 0x41)
      rescue IO::Buffer::AccessError => e
        p [:refused, e.class]
      end

      # A multi-byte string keeps its encoding across a byte write.
      u = +"héllo"
      IO::Buffer.for(u) do |b|
        b.set_value(:U8, 0, 0x48)
      end
      p [u, u.encoding.to_s, u.valid_encoding?]

      # `IO::Buffer.new` owns its bytes and aliases nothing.
      own = IO::Buffer.new(4)
      own.set_value(:U8, 0, 0x41)
      p own.get_string
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "Zbcdef"
      "ZbcdeZ"
      "ZbcdeZ"
      "hello"
      true
      [:refused, IO::Buffer::AccessError]
      ["Héllo", "UTF-8", true]
      "A\x00\x00\x00"
    OUT
  end

  it "issue203 string new" do
    result = ze0(<<~'RUBY')
      # Issue #203: `String.new` resolved to 0 because the constructor
      # dispatch had no String arm. Code that combined the result with
      # `<<` (the Rails view-emit accumulator pattern) failed to compile.

      # Bare String.new — empty mutable buffer.
      io = String.new
      io << "hello"
      puts io                   # hello

      # Constructor with seed.
      s = String.new("foo")
      s << "bar"
      puts s                    # foobar

      # Empty buffer reads as length 0.
      t = String.new
      puts t.length             # 0

      # Canonical Rails-style accumulator.
      def render(items)
        io = String.new
        io << "<ul>"
        items.each { |item| io << "<li>" << item << "</li>" }
        io << "</ul>"
        io
      end
      puts render(["a", "b"])   # <ul><li>a</li><li>b</li></ul>
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello
      foobar
      0
      <ul><li>a</li><li>b</li></ul>
    OUT
  end

  it "issue 2889" do
    result = ze0(<<~'RUBY')
      p(::Integer === 7)
      p(::Integer === "x")
      p(::String === "a")
      p(::Float === 1.5)
      p(::Symbol === :s)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      true
      true
      true
    OUT
  end

  it "issue 2910" do
    result = ze0(<<~'RUBY')
      p "ab cd".gsub(/\b\w/) { |c| c.upcase }
      p "hello world".gsub(/\w+/) { |w| w.capitalize }
      p "a1b2c3".gsub(/(\d)/) { |m| ($1.to_i * 2).to_s }
      p "  x  ".gsub(/\bx\b/) { |m| "[#{m}]" }
      p "aaa".sub(/a/) { |m| "X" }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "Ab Cd"
      "Hello World"
      "a2b4c6"
      "  [x]  "
      "Xaa"
    OUT
  end

  it "issue 2924" do
    result = ze0(<<~'RUBY')
      def k
        [5, [[1, 2, 3], [4, 5, 6]]]
      end
      total, chosen = k
      p total
      p chosen
      p chosen.sum { |_u, _v, w| w }

      def pair
        ["a", 7]
      end
      s, n = pair
      p s.upcase
      p n + 1
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      [[1, 2, 3], [4, 5, 6]]
      9
      "A"
      8
    OUT
  end

  it "issue 3063" do
    result = ze0(<<~'RUBY')
      p (1..3).flat_map { |x| x * 2 }
      p (1..3).flat_map { |x| [x, x] }
      p (1..4).flat_map { |x| x.even? ? [x, x] : x }
      p ("a".."c").flat_map { |s| s.upcase }
      p (1..3).collect_concat { |x| x + 1 }
      p [10, 20].flat_map { |x| x / 10 }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [2, 4, 6]
      [1, 1, 2, 2, 3, 3]
      [1, 2, 2, 3, 4, 4]
      ["A", "B", "C"]
      [2, 3, 4]
      [1, 2]
    OUT
  end

  it "issue 3164" do
    _(ze0(<<~'RUBY').stdout).must_equal "{\"a\" => \"b\\n\", \"c\" => \"d\"}\n"
      r = "a=b\nc=d".each_line.each_with_object({}) do |raw, config|
        key, value = raw.split("=", 2)
        config[key] = value
      end
      p r
    RUBY
  end

  it "issue 3227 full mutators" do
    result = ze0(<<~'RUBY')
      # Shared-mutable strings: every in-place mutator shares through aliases and
      # containers (P1+P2 of the reference-semantics plan).
      s = "hello world"
      arr = [s]
      s << "!"
      s["world"] = "ruby"
      p arr[0]
      s.insert(0, ">> ")
      p arr[0]
      p s.slice!(0, 3)
      p arr[0]
      s.clear
      p arr[0]
      p arr[0].equal?(s)

      # bang-only alias set
      b1 = "low"
      b2 = b1
      b1.upcase!
      p b2
      # mixed alias set
      c1 = "a"
      c2 = c1
      c1 << "b"
      c1.upcase!
      p c2
      # replace via alias
      d1 = "abc"
      d2 = d1
      d1.replace("xyz")
      p d2
      # non-literal write into a shared set
      def make = "dyn" + "amic"
      e1 = make
      e2 = e1
      e1 << "!"
      p e2
      p e1.equal?(e2)
      # frozen source stays frozen through the handle
      f1 = make.freeze
      f2 = f1
      begin
        f1 << "x"
      rescue FrozenError
        p :frozen_ok
      end
      p f2
      # setbyte shares
      g1 = "Abc"
      g2 = g1
      g1.setbyte(0, 97)
      p g2
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello ruby!"
      ">> hello ruby!"
      ">> "
      "hello ruby!"
      ""
      true
      "LOW"
      "AB"
      "xyz"
      "dynamic!"
      true
      :frozen_ok
      "dynamic"
      "abc"
    OUT
  end

  it "issue 3317 reader concat splat" do
    result = ze0(<<~'RUBY')
      class Config
        def str(*opts) = add_flag(Flag.new(opts))
        def prepare! = @help_flag = add_flag(Flag.new(["x"]))
        def add_flag(flag) = flag
      end

      class Flag
        attr_reader :switches
        def initialize(opts)
          @switches = []
          switches.concat(opts)
        end
      end

      flag = Config.new.str("y")
      raise "FAIL" unless flag.switches == ["y"]
      puts "ok"
      f2 = Config.new.prepare!
      p f2.switches
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ok
      ["x"]
    OUT
  end

  it "issue 3325 poly str shl store" do
    result = ze0(<<~'RUBY')
      class Res
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.pop
        end

        def add(name, value)
          line = name + "=" + value
          line << "; HttpOnly"
          @cookies.push(line)
        end
      end

      res = Res.new
      res.add("flash", "hello")
      head = +""
      res.cookies.each do |line|
        head << "Set-Cookie: " + line + "\r\n"
      end
      print head

      class Res2
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.pop
        end

        def add(name, value)
          line = name + "=" + value
          ["; Path=/", "; HttpOnly", "; SameSite=Lax"].each { |a| line << a }
          @cookies.push(line)
        end
      end

      r2 = Res2.new
      r2.add("sid", "42")
      puts r2.cookies[0]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Set-Cookie: flash=hello; HttpOnly
      sid=42; Path=/; HttpOnly; SameSite=Lax
    OUT
  end

  it "issue 3339 zero arg string mutators" do
    result = ze0(<<~'RUBY')
      m1 = +"hello"; r1 = (m1.prepend rescue $!.class); p r1
      f1 = "hello";  r2 = (f1.concat  rescue $!.class); p r2
      f2 = "hello";  r3 = (f2.prepend rescue $!.class); p r3
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello"
      "hello"
      "hello"
    OUT
  end

  it "issue attr in dynamic class body" do
    result = ze0(<<~'RUBY')
      # attr_reader/attr_accessor/attr_writer only work in a literal `class`/`module`
      # body. Invoked from inside a `Class.new { ... }` or `#class_eval { ... }`
      # block, zeo raises NoMethodError instead of defining the accessor.
      klass = Class.new do
        attr_reader :v
        def initialize(v)
          @v = v
        end
      end
      p klass.new(5).v

      Klass2 = Class.new
      Klass2.class_eval do
        attr_accessor :y
      end
      o = Klass2.new
      o.y = 99
      p o.y
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      99
    OUT
  end

  it "issue string subclass new with arg" do
    result = ze0(<<~'RUBY')
      # Instantiating a String subclass with a constructor argument
      # (`klass.new("x")`) raises ArgumentError ("wrong number of arguments") --
      # zeo doesn't forward the argument to String's own initializer for a
      # dynamically-created subclass.
      klass = Class.new(String) do
        def foo
          42
        end
      end
      s = klass.new("x")
      p s
      p s.foo
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "x"
      42
    OUT
  end

  it "kernel rational string zerodenom" do
    result = ze0(<<~'RUBY')
      # Kernel#Rational parses a String argument ("n", "n/d", "n.d", with optional
      # whitespace and sign) instead of reading the string pointer as an integer, and
      # raises ZeroDivisionError for a zero denominator instead of building (n/0).
      def r1(s); Rational(s); end
      p r1("3/4")                    # (3/4)
      p r1("  -5/2 ")                # (-5/2)
      p r1("6")                      # (6/1)
      p r1("2.5")                    # (5/2)

      def r2(a, b); Rational(a, b); end
      p r2(6, 4)                     # (3/2)  (still reduces)
      p r2(-1, 3)                    # (-1/3)

      def check
        yield
      rescue ZeroDivisionError => e
        puts "ZeroDivisionError: #{e.message}"
      end
      check { r2(1, 0) }             # ZeroDivisionError: divided by 0
      check { r2(0, 0) }             # ZeroDivisionError: divided by 0

      # The single-argument integer form is unchanged.
      p Rational(3)                  # (3/1)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      (3/4)
      (-5/2)
      (6/1)
      (5/2)
      (3/2)
      (-1/3)
      ZeroDivisionError: divided by 0
      ZeroDivisionError: divided by 0
      (3/1)
    OUT
  end

  it "kwrest non symbol keys" do
    result = ze0(<<~'RUBY')
      # A `**kwrest` parameter captures keyword arguments with ANY key, not just
      # symbols -- the options-hash idiom `method CONST => :value` (Thor's
      # `map HELP_MAPPINGS => :help`) passes a non-symbol key, which real Ruby routes
      # into `**kw` as a hash entry (a keyword parameter NAME is always a symbol, so a
      # non-symbol key can only land in the rest). Distinct from an explicit `{...}`
      # positional Hash, which the Ruby 3 keyword separation keeps out of `**kw`.
      HELP = %w[-h --help]

      def cmd(mappings = nil, **kw)
        "m=#{mappings.inspect} kw=#{kw.inspect}"
      end

      puts cmd HELP => :help        # non-symbol (array) key -> **kw
      puts cmd(a: 1, b: 2)          # symbol keys -> **kw
      puts cmd("s" => 1, x: 2)      # mixed keys -> one **kw hash
      puts cmd({ z: 9 })            # explicit hash is POSITIONAL, not keywords

      def only_kw(**opts)
        opts.inspect
      end

      puts only_kw HELP => :help
      puts only_kw(a: 1)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      m=nil kw={["-h", "--help"] => :help}
      m=nil kw={a: 1, b: 2}
      m=nil kw={"s" => 1, x: 2}
      m={z: 9} kw={}
      {["-h", "--help"] => :help}
      {a: 1}
    OUT
  end

  it "lambda arrow string return" do
    result = ze0(<<~'RUBY')
      # An arrow lambda (`-> {}`, the sp_Val / sp_lam_* ABI, distinct from the
      # `lambda {}` proc-call ABI) returning a string literal round-trips its
      # value instead of the old hardcoded sp_lam_int(0) stub.
      f = -> { "arrow" }
      puts f.call

      g = -> { 7 }
      puts g.call
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      arrow
      7
    OUT
  end

  it "last paren backreference and adjacent interpolation" do
    result = ze0(<<~'RUBY')
      # `$+` is the highest-numbered group that PARTICIPATED, skipping
      # declared-but-unmatched ones (rb_reg_match_last, re.c:2093), and is nil
      # when only group 0 matched -- it never reports the whole match.
      #
      # Backslash-continued adjacent literals parse as an InterpolatedStringNode
      # whose own parts are InterpolatedStringNodes, so parts must flatten
      # recursively rather than being treated as leaves.

      "abc123" =~ /([a-z]+)(\d+)/
      puts $1
      puts $2
      puts $+
      "abc" =~ /([a-z]+)(\d+)?/
      puts $+
      "xyz" =~ /xyz/
      p $+
      "b" =~ /(a)|(b)|(c)/
      p $+
      def svg(px, inner)
        "<a width='#{px}' " \
        "height='#{px}'>#{inner}</a>"
      end
      def tail(n)
        "n=#{n}" \
        " done"
      end
      puts svg(16, "x")
      puts tail(7)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      abc
      123
      123
      abc
      nil
      "b"
      <a width='16' height='16'>x</a>
      n=7 done
    OUT
  end

  it "lazy drop while each slice" do
    result = ze0(<<~'RUBY')
      p (1..10).lazy.drop_while { |x| x < 3 }.to_a
      p (1..10).lazy.each_slice(2).to_a
      p (1..10).lazy.each_slice(3).to_a
      p (1..10).lazy.map { |x| x * 2 }.drop_while { |x| x < 9 }.to_a
      p (1..10).lazy.select { |x| x.even? }.each_slice(2).to_a
      p (1..10).lazy.each_slice(4).first(2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [3, 4, 5, 6, 7, 8, 9, 10]
      [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10]]
      [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]]
      [10, 12, 14, 16, 18, 20]
      [[2, 4], [6, 8], [10]]
      [[1, 2, 3, 4], [5, 6, 7, 8]]
    OUT
  end

  it "lazy each cons slice" do
    result = ze0(<<~'RUBY')
      # `Enumerator::Lazy#each_cons`/`#each_slice` are lazy: an endless source is
      # workable, and the chain only advances as far as the terminal asks.
      p (1..Float::INFINITY).lazy.each_cons(3).first(2)
      p (1..Float::INFINITY).lazy.each_slice(3).first(2)
      p (1..10).lazy.each_slice(3).to_a
      p (1..7).lazy.each_cons(3).to_a
      p (1..2).lazy.each_cons(3).to_a
      p (1..10).lazy.each_cons(2).class
      p (1..10).lazy.each_cons(2).size
      p (1..Float::INFINITY).lazy.each_cons(2).size
      p (1..10).lazy.each_slice(3).size
      p (1..10).lazy.each_slice(4).size
      p (1..3).lazy.each_cons(5).size
      p (1..10).lazy.select { |x| x > 1 }.each_cons(2).size
      p [1, 2, 3].lazy.each_cons(2).each_cons(2).to_a
      p({ a: 1, b: 2, c: 3 }.lazy.each_cons(2).to_a)
      p (1..6).lazy.each_cons(2).with_index.first(2)
      p (1..6).lazy.each_cons(2).select { |a, b| a.odd? }.to_a
      p (1..8).lazy.each_slice(3).map { |g| g.sum }.to_a
      p (1..6).lazy.each_cons(0).to_a rescue p $!.message
      p (1..6).lazy.each_slice(0).to_a rescue p $!.message

      # a block runs the chain at once for its side effects and answers the receiver
      seen = []
      r = (1..6).lazy.each_cons(2) { |w| seen << w }
      p seen
      p r.first(3)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1, 2, 3], [2, 3, 4]]
      [[1, 2, 3], [4, 5, 6]]
      [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]]
      [[1, 2, 3], [2, 3, 4], [3, 4, 5], [4, 5, 6], [5, 6, 7]]
      []
      Enumerator::Lazy
      9
      Infinity
      4
      3
      0
      nil
      [[[1, 2], [2, 3]]]
      [[[:a, 1], [:b, 2]], [[:b, 2], [:c, 3]]]
      [[[1, 2], 0], [[2, 3], 1]]
      [[1, 2], [3, 4], [5, 6]]
      [6, 15, 15]
      "invalid size"
      "invalid slice size"
      [[1, 2], [2, 3], [3, 4], [4, 5], [5, 6]]
      [1, 2, 3]
    OUT
  end

  it "literal string markers" do
    result = ze0(<<~'RUBY')
      # Every string spinel hands back to Ruby carries a marker byte at [-1].
      # sp_gc_mark reads it to decide whether a rooted pointer is a literal to skip
      # or a heap object whose mark word it should write, so a runtime arm that
      # returns a BARE C literal is a fault waiting for a collection: the collector
      # reads whatever rodata precedes the literal, fails to recognise a marker,
      # concludes it has a heap object and writes into read-only memory.
      #
      # Each value below is held in a live local across an explicit GC.start, which
      # is exactly that window. #3393 fixed sp_sym_to_s's empty return; these are the
      # rest of the same family (class names, the inspect fallbacks, an exception
      # with no object behind it).

      def churn
        a = []
        200.times { |i| a.push("filler #{i}") }
        a.length
      end

      def through_gc(s)
        churn
        GC.start
        churn
        GC.start
        s
      end

      require "stringio"

      p through_gc(StringIO.new("x").class.to_s)
      p through_gc($stdout.class.to_s)
      p through_gc(proc { 1 }.inspect).start_with?("#<Proc")
      p through_gc([1, 2].each.inspect).start_with?("#<Enumerator")
      p through_gc(:sym.inspect)
      p through_gc(1.method(:+).inspect).start_with?("#<Method")

      begin
        raise "boom"
      rescue => e
        p through_gc(e.class.to_s)
        p through_gc(e.message)
      end

      # a nil Symbol slot renders through sp_sym_to_s's out-of-range arm (#3393)
      class Holder
        def initialize(s)
          @s = s
        end

        def label
          @s
        end
      end
      p through_gc(Holder.new(nil).label.to_s).length
      p through_gc(:named.to_s)

      # $0 is argv[0], which lives in the process's argument block rather than the
      # string heap; it is an ordinary Ruby String all the same
      p through_gc($0).class.to_s
      p through_gc($PROGRAM_NAME).length > 0
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "StringIO"
      "IO"
      true
      true
      ":sym"
      true
      "RuntimeError"
      "boom"
      0
      "named"
      "String"
      true
    OUT
  end

  it "loop do end with break value" do
    _(ze0(<<~'RUBY').stdout).must_equal "30\n"
      i = 0
      result = loop do
        i += 1
        break i * 10 if i == 3
      end
      puts result
    RUBY
  end

  it "map block string new join" do
    result = ze0(<<~'RUBY')
      # #526. Sibling to #522. #522 fixed `.map { String.new }` block-return
      # inference so the result is correctly typed as
      # `mutable_str_ptr_array` (a sp_PtrArray of sp_String*). But the
      # is_ptr_array_type recv block in codegen had no `join` arm for this
      # variant — `xs.map { String.new }.join(",")` fell through to the
      # unresolved-call warning and emitted 0 at the call site (compile-time
      # warning, runtime no-op producing empty output between separators in
      # the composite JSON-fragment use case in action_view/view_helpers).
      #
      # Fix: add the `join` arm in the ptr_array recv block (gated on
      # elem_type == "mutable_str") that emits sp_PtrArray_str_join, and the
      # matching runtime helper that reads each element's bytes via the
      # sp_String data/len pair.

      def make_str(x)
        s = String.new
        s << x.to_s
        s
      end

      xs = [1, 2, 3]

      # The repro case from the issue: block returns String.new directly.
      puts xs.map { |x| String.new }.join(",")

      # Block body is a method call returning a mutable_str — mirrors the
      # real-world action_view/view_helpers pattern where the map block calls
      # something like `Views::Articles.article_json(article)` and the result
      # is joined with "," to form a JSON fragment.
      puts xs.map { |x| make_str(x) }.join("-")

      # Single-element (no separator emitted in output).
      puts [1].map { |x| make_str(x) }.join(",")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ,,
      1-2-3
      1
    OUT
  end

  it "method level rescue return string" do
    result = ze0(<<~'RUBY')
      # Method-level rescue return value with string-returning bodies.
      # The int-returning shape works once compile_body_into /
      # compile_rescue_chain_into capture the begin / rescue last expr.
      # The string-returning shape additionally needs the method's
      # inferred return type to unify across both branches, which
      # requires BeginNode in infer_type's arms.

      # Both branches return string — unify_return_type picks string.
      def fetch(s)
        raise "empty" if s == ""
        "got " + s
      rescue
        "default"
      end
      puts fetch("data")
      puts fetch("")

      # Rescue body with multiple statements. Last is the value.
      def parse(s)
        raise "blank" if s == ""
        "len=" + s.length.to_s
      rescue
        msg = "fallback"
        msg + "!"
      end
      puts parse("hi")
      puts parse("")

      # Method body that's a BeginNode at the top, with a return inside
      # the begin. collect_return_types must walk the begin body for the
      # explicit `return X` to contribute to the unified type.
      def explicit(s)
        raise "neg" if s == ""
        return "early " + s
      rescue
        "late"
      end
      puts explicit("yes")
      puts explicit("")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      got data
      default
      len=2
      fallback!
      early yes
      late
    OUT
  end

  it "method name symbol" do
    result = ze0(<<~'RUBY')
      # Method#name returns a Symbol (not a String), matching CRuby. The method
      # object is also routed through a param so the `.name` runs on a non-folded
      # TY_METHOD value.
      class Calc
        def add(a, b); a + b; end
        def noarg; 0; end
        def +(other); 1; end
      end
      c = Calc.new

      m = c.method(:add)
      p m.name                  # :add
      puts m.name.inspect       # :add
      puts m.name == :add       # true
      puts m.name.class         # Symbol
      puts m.name.to_s          # add

      # no-arg method
      puts c.method(:noarg).name.inspect   # :noarg

      # operator method name
      p c.method(:+).name       # :+

      # routed through a method param to defeat constant-folding
      def id(x); x; end
      p id(c.method(:add)).name # :add

      # usable as a case/when scrutinee against symbol literals
      case m.name
      when :add then puts "is add"
      else puts "other"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :add
      :add
      true
      Symbol
      add
      :noarg
      :+
      :add
      is add
    OUT
  end

  it "method return mixed int string" do
    result = ze0(<<~'RUBY')
      # A method whose return paths mix a genuine int (an int literal or a
      # param-sourced int ivar) with a string must box its return to poly so
      # the int arm is not silently returned through the string pointer slot.
      class Record
        def initialize(id, name)
          @id = id
          @name = name
        end

        # Both arms are ivar reads; the unify picks "string", hiding the int
        # @id arm inside the tail IfNode.
        def [](field)
          if field == 0
            @id
          else
            @name
          end
        end
      end

      r = Record.new(7, "hi")
      puts r[0]
      puts r[1]
      p r[0]
      p r[1]

      # Int literal buried in a branch, string in the other.
      class Tagged
        def initialize(s)
          @s = s
        end

        def value(numeric)
          if numeric
            100
          else
            @s
          end
        end
      end

      t = Tagged.new("text")
      puts t.value(true)
      puts t.value(false)
      p t.value(true)
      p t.value(false)

      # The exact reported shape: a case/when field lookup over literal-init
      # ivars of mixed types.
      class Row
        def initialize
          @id = 7
          @name = "hi"
        end

        def [](field)
          case field
          when :id then @id
          when :name then @name
          end
        end
      end

      p Row.new[:id]
      p Row.new[:name]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      7
      hi
      7
      "hi"
      100
      text
      100
      "text"
      7
      "hi"
    OUT
  end

  it "min by string key" do
    result = ze0(<<~'RUBY')
      # min_by/max_by with a String or Symbol block key orders lexicographically
      # (String#<=>), not just for Integer/Float keys.
      p ["banana", "apple", "cherry"].min_by { |s| s }
      p ["banana", "apple", "cherry"].max_by { |s| s }
      p ["banana", "apple", "cherry"].max_by { |s| s.length }
      p [:foo, :bar, :baz].min_by { |s| s }
      def first_alpha(a); a.min_by { |s| s }; end
      p first_alpha(["c", "a", "b"])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "apple"
      "cherry"
      "banana"
      :bar
      "a"
    OUT
  end

  it "module attr alias include" do
    result = ze0(<<~'RUBY')
      module M001
        attr_accessor :x001
      end
      class C001
        include M001
        def initialize; @x001 = 5; end
      end
      p C001.new.x001
      c = C001.new
      c.x001 = 9
      p c.x001

      module M002
        def visible002; true; end
        alias_method :visible002?, :visible002
      end
      class C002
        include M002
      end
      p C002.new.visible002?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      9
      true
    OUT
  end

  it "module body string const interp" do
    result = ze0(<<~'RUBY')
      # Interpolating a String constant defined in the same module/class body
      # must read the constant's value, not its raw pointer. Before, the
      # constant reference inside another constant's initializer was annotated
      # as Integer (the lexical scope was not set while caching the RHS), so
      # "v#{A}" emitted the pointer of A formatted as %lld.

      module M
        A = "33"
        V = "v#{A}"
      end
      puts M::V

      class C
        NAME = "spinel"
        GREETING = "hello #{NAME}"
      end
      puts C::GREETING

      # Chained-VERSION shape (e.g. libdatadog's VERSION = "#{LIB}.#{MAJOR}.#{MINOR}")
      module Lib
        LIB = "ddtrace"
        MAJOR = "1"
        MINOR = "2"
        VERSION = "#{LIB}-#{MAJOR}.#{MINOR}"
      end
      puts Lib::VERSION

      # Constant-to-constant value reference inside a body
      module V
        A = "hi"
        B = A
      end
      puts V::B

      # Control: an Integer constant interpolates as its number
      module I
        N = 33
        S = "n=#{N}"
      end
      puts I::S
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      v33
      hello spinel
      ddtrace-1.2
      hi
      n=33
    OUT
  end

  it "module cls method string return" do
    result = ze0(<<~'RUBY')
      # Issue #127: a module-level singleton method (`module M; def self.X; ... end; end`)
      # whose body returns a non-int value used to be typed as `mrb_int` at every
      # call site. Capturing to a local emitted `mrb_int = const char *` (compile
      # error under -Werror); inline `puts M.X` compiled but printed the pointer
      # as an integer. The class form (same shape inside `class C`) already worked.
      # Fix is in `infer_constant_recv_type`: walk `@meth_return_types` for
      # `<Module>_cls_<method>` the same way the class branch walks `@cls_cmeth_returns`.

      # 1. Module + def self + String return + local capture — the failing shape.
      module M1
        def self.greet
          "hello"
        end
      end

      s = M1.greet
      puts s                              # hello

      # 2. Module + def self + String return + inline puts — same root, different consumer.
      module M2
        def self.greet
          "world"
        end
      end

      puts M2.greet                       # world

      # 3. Module + def self + Float return — non-int isn't string-specific.
      module M3
        def self.pi
          3.14
        end
      end

      puts M3.pi                          # 3.14

      # 4. Class + def self + String return — the path that already worked. Regression guard.
      class C1
        def self.greet
          "from class"
        end
      end

      t = C1.greet
      puts t                              # from class

      # 5. Top-level def returning String — separate inference path. Regression guard.
      def top_greet
        "top"
      end

      u = top_greet
      puts u                              # top
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello
      world
      3.14
      from class
      top
    OUT
  end

  it "module function promotes bareword and symbol forms" do
    result = ze0(<<~'RUBY')
      # A bare `module_function` promotes every following `def` to a module
      # method; `module_function :name` promotes an already-defined one.

      module M
        module_function
        def shout(s) = s.upcase
      end
      module N
        def whisper(s) = s.downcase
        module_function :whisper
      end
      puts M.shout("hi")
      puts N.whisper("HI")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      HI
      hi
    OUT
  end

  it "module function str method param" do
    _(ze0(<<~'RUBY').stdout).must_equal "RED and bold text\n"
      # A module_function-promoted method whose body calls a string method
      # on its param, invoked with a string-literal arg, must route the
      # param to the string path (not the int "0" NoMethodError fallback).
      # Mirrors strings-ansi's Strings::ANSI.sanitize gsub-with-regex-const.
      module Strings
        module ANSI
          ANSI_MATCHER = /\e\[[0-9;]*m/
          def sanitize(string)
            string.gsub(ANSI_MATCHER, "")
          end
          module_function :sanitize
        end
      end
      puts Strings::ANSI.sanitize("\e[31mRED\e[0m and \e[1mbold\e[0m text")
    RUBY
  end

  it "module metaprogramming attr class eval exec and invented ivars" do
    result = ze0(<<~'RUBY')
      # attr (== attr_reader), class_eval/module_exec block forms whose
      # added methods are inherited by subclasses and includers, and an
      # invented ivar (assigned by a class_eval/instance_exec body, never
      # declared on the struct) surviving in the per-object overflow map.

      class C001
        attr :x
        def initialize; @x = 5; end
      end
      p C001.new.x

      class Box
        def initialize(v); @v = v; end
      end
      class BoxPlus < Box; end
      Box.class_eval do
        def doubled; @v * 2; end
        define_method(:tripled) { @v * 3 }
        def labelled; @label = "n=#{@v}"; @label; end
      end
      b = Box.new(21)
      p [b.doubled, b.tripled, b.labelled]
      p BoxPlus.new(5).doubled

      module M; end
      M.module_exec { def mm; "mm"; end }
      class D; include M; end
      p D.new.mm

      o = Object.new
      o.instance_exec { @invented = 99 }
      p o.instance_variable_get(:@invented)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      [42, 63, "n=21"]
      10
      "mm"
      99
    OUT
  end

  it "module singleton attr accessor" do
    result = ze0(<<~'RUBY')
      # #511. `module M; class << self; attr_accessor :x; end; end` on a
      # module previously didn't recognize either the reader or writer
      # for non-constant-RHS assignments — the existing constant-fold
      # path (rewrite_module_singleton_accessors) only resolved when
      # every observed write was a ConstantReadNode RHS. Roundhouse hit
      # this with `ActiveRecord.adapter = SqliteAdapter.new` (the RHS
      # is a method call, not a constant).
      #
      # Fix: when the SingletonClassNode + attr_accessor shape is seen,
      # also synthesize a poly-typed file-scope const `<Mod>_<accessor>`.
      # Reads of `Mod.accessor` and writes of `Mod.accessor = v` then
      # fall through to the const slot when the constant-fold path is
      # empty or poisoned. The const initializes to `{SP_TAG_NIL,...}`
      # so an un-assigned read returns nil.

      module Cfg
        class << self
          attr_accessor :adapter, :timeout
        end
      end

      # String RHS (non-constant): codegen falls through to the poly
      # slot. Reader returns sp_RbVal -> sp_poly_puts.
      Cfg.adapter = "sqlite"
      puts Cfg.adapter

      # Int RHS.
      Cfg.timeout = 30
      puts Cfg.timeout

      # Re-assign.
      Cfg.adapter = "postgres"
      puts Cfg.adapter

      # Pre-assignment read is nil.
      module Empty
        class << self
          attr_accessor :slot
        end
      end
      puts Empty.slot.nil?
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      sqlite
      30
      postgres
      true
    OUT
  end

  it "mutable str alias uaf" do
    result = ze0(<<~'RUBY')
      # A mutable String (String.new + <<) owns its internal buffer, freed by
      # the object's finalizer. Boxing/coercing/returning that buffer as an
      # immutable string must copy it, not alias it: otherwise a GC that
      # collects the unreferenced builder frees the buffer out from under the
      # still-referenced string (a use-after-free). Each path below captures
      # the converted value, then churns the heap and forces a GC so a freed
      # buffer would be reused before it is read back.

      def build_io(n)
        io = String.new
        i = 0
        while i < n
          io << i.to_s
          io << ","
          i += 1
        end
        io
      end

      def hold(x)                 # poly param: arg is boxed via sp_box_str(->data)
        GC.start
        i = 0
        t = ""
        while i < 4000
          t = t + i.to_s
          i += 1
        end
        x
      end

      def via_to_s(n)             # mutable.to_s returned across a fn boundary
        build_io(n).to_s
      end

      def via_gsub(n)             # gsub with no match returns the receiver
        build_io(n).gsub("ZZZ", "x")
      end

      hold(42)                    # int call site forces hold's param to poly

      a = hold(build_io(6))       # poly-box conversion
      b = via_to_s(6)             # to_s conversion
      c = String(build_io(6))     # Kernel#String conversion
      d = via_gsub(6)             # no-op gsub returning the receiver

      i = 0
      t = ""
      while i < 8000
        t = t + i.to_s
        i += 1
      end
      GC.start
      i = 0
      while i < 8000
        t = t + i.to_s
        i += 1
      end

      puts a
      puts b
      puts c
      puts d
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0,1,2,3,4,5,
      0,1,2,3,4,5,
      0,1,2,3,4,5,
      0,1,2,3,4,5,
    OUT
  end

  it "mutable str into str array" do
    result = ze0(<<~'RUBY')
      # Pushing a mutable String builder (String.new + <<) into a str_array
      # must snapshot its buffer into a sweep-owned (0xfe) copy, not store the
      # sp_String pointer / alias its object-owned ->data buffer. The builder
      # is otherwise unreferenced after the push, so a GC collects it and frees
      # the buffer, leaving the array element dangling; the next mark walk
      # faults scanning it (the #1071 / #1314 use-after-free class). Pre-fix
      # this also emitted `sp_StrArray_push(arr, sp_String *)`, an
      # incompatible-pointer-type the -Werror test build rejects outright.

      # 1. `<<` (statement form) — many builders pushed under GC churn.
      arr = []
      i = 0
      while i < 4000
        s = String.new
        s << "item "
        s << i.to_s
        arr << s
        i = i + 1
      end
      puts arr.length                 #=> 4000
      puts arr[0]                     #=> item 0
      puts arr[4000 - 1]             #=> item 3999

      # 2. `push` (expression form).
      arr2 = []
      k = 0
      while k < 2000
        b = String.new
        b << "k="
        b << k.to_s
        arr2.push(b)
        k = k + 1
      end
      puts arr2.length                #=> 2000
      puts arr2[1000]                #=> k=1000

      # 3. Sum the lengths back (reads every element after GC).
      total = 0
      j = 0
      while j < arr.length
        total = total + arr[j].length
        j = j + 1
      end
      puts total                      #=> 34890

      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      4000
      item 0
      item 3999
      2000
      k=1000
      34890
      done
    OUT
  end

  it "negative range slice" do
    result = ze0(<<~'RUBY')
      # #496. `a[1..-2]` returned [] in spinel where CRuby returns
      # [a[1], a[2], a[3]]. Codegen emitted `sp_IntArray_slice(arr, 1,
      # -2 - 1 + 1)` (length = -2), and the runtime's `len <= 0` early
      # return produced an empty array. Fix: new `_slice_range` /
      # `_sub_range_r` runtime helpers take (start, end, exclusive)
      # and normalize negative end against the collection length
      # before computing slice length.
      #
      # Test covers the four receiver shapes that route through the
      # fixed emit sites: int_array, float_array, str_array, and
      # string. Exclusive (`...`) and inclusive (`..`) forms both
      # exercise negative endpoints.

      a = [0, 1, 2, 3, 4]
      p a[1..-2]   # inclusive: [1, 2, 3]
      p a[1...-1]  # exclusive: [1, 2, 3]
      p a[-3..-1]  # both negative: [2, 3, 4]
      p a[0..-1]   # whole array: [0, 1, 2, 3, 4]
      p a[2..-3]   # single element (-3 -> 2, so a[2..2]): [2]
      p a[-4..-2]  # negative start, negative end: [1, 2, 3]

      f = [0.5, 1.5, 2.5, 3.5]
      p f[1..-2]   # [1.5, 2.5]

      s_arr = ["a", "b", "c", "d", "e"]
      p s_arr[1..-2]   # ["b", "c", "d"]

      s = "hello"
      p s[1..-2]   # "ell"
      p s[1...-1]  # "ell"
      p s[-3..-1]  # "llo"
      p s[-4..-2]  # negative start + end: "ell"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      [2, 3, 4]
      [0, 1, 2, 3, 4]
      [2]
      [1, 2, 3]
      [1.5, 2.5]
      ["b", "c", "d"]
      "ell"
      "ell"
      "llo"
      "ell"
    OUT
  end

  it "next value each slice" do
    result = ze0(<<~'RUBY')
      # `next <value>` through each_slice(n).map contributes the value.
      p [1, 2, 3, 4].each_slice(2).map { |a, b| next 0 if a == 1; a + b }   # [0, 7]
      p [1, 2, 3, 4, 5].each_slice(2).map { |a, b| a }                      # [1, 3, 5]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [0, 7]
      [1, 3, 5]
    OUT
  end

  it "nil string receiver raises" do
    result = ze0(<<~'RUBY')
      v = ENV["NO_SUCH_1664"]
      begin; v.length; rescue NoMethodError => e; puts "length: #{e.message}"; end
      begin; v.upcase; rescue NoMethodError => e; puts "upcase: #{e.message}"; end
      begin; v.split(","); rescue NoMethodError => e; puts "split: #{e.message}"; end
      begin; v[0]; rescue NoMethodError => e; puts "slice: #{e.message}"; end
      begin; v.empty?; rescue NoMethodError => e; puts "empty?: #{e.message}"; end
      begin; v.include?("x"); rescue NoMethodError => e; puts "include?: #{e.message}"; end
      begin; v + "x"; rescue NoMethodError => e; puts "plus: #{e.message}"; end
      begin; "x" + v; rescue TypeError => e; puts "plus_nil_arg: TypeError"; end
      begin; v.to_str; rescue NoMethodError => e; puts "to_str: #{e.message}"; end
      begin; v.strip; rescue NoMethodError => e; puts "strip: #{e.message}"; end
      begin; v.index("x"); rescue NoMethodError => e; puts "index: #{e.message}"; end
      begin; v.chars; rescue NoMethodError => e; puts "chars: #{e.message}"; end
      puts v.to_s.inspect
      puts v.to_i
      puts v.dup.nil?
      puts v.frozen?
      puts v.inspect
      a = ["a", v, "b"]
      puts a.join("-")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      length: undefined method 'length' for nil
      upcase: undefined method 'upcase' for nil
      split: undefined method 'split' for nil
      slice: undefined method '[]' for nil
      empty?: undefined method 'empty?' for nil
      include?: undefined method 'include?' for nil
      plus: undefined method '+' for nil
      plus_nil_arg: TypeError
      to_str: undefined method 'to_str' for nil
      strip: undefined method 'strip' for nil
      index: undefined method 'index' for nil
      chars: undefined method 'chars' for nil
      ""
      0
      true
      true
      nil
      a--b
    OUT
  end

  it "numeric coerce non numeric string" do
    result = ze0(<<~'RUBY')
      begin
        42.coerce("l")
      rescue ArgumentError => e
        p e.class
      end
      begin
        2.5.coerce("")
      rescue ArgumentError => e
        p e.class
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      ArgumentError
    OUT
  end

  it "numeric string argument" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A numeric method with a String argument raises TypeError where ruby
      # raises ArgumentError.
      #
      r001 = (5.div("x") rescue $!.class)
      p r001

      r002 = (5.gcdlcm("x") rescue $!.class); p r002
      r003 = (5.modulo("x") rescue $!.class); p r003
      r004 = (5.remainder("x") rescue $!.class); p r004
      r005 = (5.divmod("x") rescue $!.class); p r005
      r006 = (5.pow("x") rescue $!.class); p r006
      r007 = (5.fdiv("x") rescue $!.class); p r007
      r008 = (5.digits("x") rescue $!.class); p r008
      r009 = (5.to_s("x") rescue $!.class); p r009
      r010 = (5.ceildiv("x") rescue $!.class); p r010
      r011 = (Integer.sqrt("x") rescue $!.class); p r011
      r012 = (1.5.fdiv("x") rescue $!.class); p r012
      r013 = (1.5.divmod("x") rescue $!.class); p r013
      r014 = (1.5.round("x") rescue $!.class); p r014
      r015 = (1.5.floor("x") rescue $!.class); p r015
      r016 = (1.5.ceil("x") rescue $!.class); p r016
      r017 = (1.5.truncate("x") rescue $!.class); p r017

      r018 = (5.coerce("x") rescue $!.class); p r018
      r019 = (1.5.coerce("x") rescue $!.class); p r019
      r020 = (5.clamp("a", "z") rescue $!.class); p r020
      r021 = (1.upto("a").to_a rescue $!.class); p r021
      r022 = (3.downto("a").to_a rescue $!.class); p r022
      r023 = (1.step("z", 1).to_a rescue $!.class); p r023
      r024 = (1.5.between?("a", "z") rescue $!.class); p r024

      r025 = (5.between?("a", "z") rescue $!.class); p r025   # Ruby: ArgumentError   Spinel: false

      p((5.gcd("x") rescue $!.class))     # both: TypeError
      p((5.lcm("x") rescue $!.class))     # both: TypeError
      p((1.5 + "x" rescue $!.class))      # both: TypeError
      p((1.5 ** "x" rescue $!.class))     # both: TypeError
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      TypeError
      TypeError
      TypeError
      TypeError
    OUT
  end

  it "param ptr from callee slot" do
    result = ze0(<<~'RUBY')
      # A method param passed unmodified to a callee whose corresponding
      # slot is `ptr` / a specific class pointer used to leave the caller's
      # param typed `mrb_int`. The C compile then failed at the call site
      # when the caller passed its mrb_int param into a `void *`-expecting
      # slot.
      #
      # Mirrors the Db.column_bool shape in real-blog: a thin wrapper
      # around a typed primitive (FFI sqlite handle) that didn't have its
      # `stmt` param widened from the body's call to column_int.

      module Box
        def self.read_int(p)
          p.length
        end

        def self.read_bool(p)
          read_int(p) != 0
        end
      end

      puts Box.read_int("abc")
      puts Box.read_bool("abc")
      puts Box.read_bool("")

      # Same pattern across two layers — three-deep chain.
      module Chain
        def self.head(s)
          middle(s)
        end

        def self.middle(s)
          tail(s)
        end

        def self.tail(s)
          s.length
        end
      end

      puts Chain.head("abc")
      puts Chain.middle("xyz")
      puts Chain.tail("hi")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      true
      false
      3
      3
      2
    OUT
  end

  it "param widens when body assigns string" do
    result = ze0(<<~'RUBY')
      # A method body that reassigns one of its parameters to a value
      # of an incompatible type (here: int call sites + string body
      # write) needs the param's slot widened to `poly` so the
      # generated C can hold both shapes via sp_RbVal. Without the
      # widening the parameter slot stays at the call-site-inferred
      # `mrb_int`, and the body's `lv_x = "forever"` assignment is
      # `mrb_int = const char *` — rejected by gcc under
      # `-Wint-conversion`.

      class Logger
        def report(label, hclk)
          hclk = "forever" if hclk == 4294967295
          puts label
          puts hclk
        end
      end

      l = Logger.new
      l.report("running", 1234)
      l.report("running", 4294967295)
      l.report("done", 17)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      running
      1234
      running
      forever
      done
      17
    OUT
  end

  it "plain string raise is caught by an explicit runtime error rescue" do
    _(ze0(<<~'RUBY').stdout).must_equal "caught runtime: just a string\n"
      begin
        raise "just a string"
      rescue RuntimeError => e
        puts "caught runtime: #{e.send(:message)}"
      end
    RUBY
  end

  it "poly array concat unshift rindex" do
    result = ze0(<<~'RUBY')
      # Poly (heterogeneous) array methods: concat (in-place append, incl. typed-array
      # arg), unshift/prepend (front insert), rindex (last match or nil).
      def cat(a, b); a.concat(b); end
      p cat([1, "x"], [:y, 2])
      def cat_typed(a); a.concat([9, 8]); end
      p cat_typed([1, "x"])
      def un(a); a.unshift(:z, 0); end
      p un([1, "x"])
      def ri(a, v); a.rindex(v); end
      p ri([1, "x", 1, "x"], "x")
      p ri([1, "x"], :nope)
      def mut; a = [1, "x"]; a.concat([:y]); a; end
      p mut
      # self-concat must not corrupt when the receiver reallocs mid-copy
      def selfcat(a); a.concat(a); end
      p selfcat([1, "x", 2.0, :q, 5, 6, 7, 8, 9, 10, 11])
      # multiple concat args (incl. a typed-array arg) are all evaluated before appending
      def cat3(a, b); a.concat(b, [9, 8]); end
      p cat3([1, "x"], [:y])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [1, "x", :y, 2]
      [1, "x", 9, 8]
      [:z, 0, 1, "x"]
      3
      nil
      [1, "x", :y]
      [1, "x", 2.0, :q, 5, 6, 7, 8, 9, 10, 11, 1, "x", 2.0, :q, 5, 6, 7, 8, 9, 10, 11]
      [1, "x", :y, 9, 8]
    OUT
  end

  it "poly array plus concat" do
    result = ze0(<<~'RUBY')
      # `Array#+` on a POLY-typed array value silently returned 0 instead of
      # concatenating. When a record field's only initializer is an empty `[]`, its
      # element type is unresolvable, so it is stored as a boxed poly value and `+`
      # compiles to sp_poly_add (the dynamic `+` dispatcher). sp_poly_add handled
      # numeric and string operands but fell through to `0` for arrays -- so the
      # append vanished. The dispatcher now concatenates when both operands are arrays.
      M = Data.define(:xs)

      m = M.new(xs: [])
      m2 = m.with(xs: m.xs + ["a", "b"])
      p m2.xs
      p m2.xs.size

      n = M.new(xs: [])
      p (n.xs + [1, 2]).size          # poly array + int array
      p (n.xs + [[1], [2]]).length    # poly array + nested array
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b"]
      2
      2
      2
    OUT
  end

  it "poly attr reader shadows builtin" do
    result = ze0(<<~'RUBY')
      # An attr_reader/attr_accessor whose name collides with a builtin poly
      # zero-arg helper (value/resume/join -> Thread#value, sum/min/max/first/
      # last/sample -> array reductions) must shadow the helper exactly like an
      # explicit `def` does.
      #
      # The shortcut in emit_call only counted comp_method_in_chain when deciding
      # "no user class defines this name", so an accessor-declared reader was
      # invisible: `node.value` on a poly element emitted sp_poly_fiber_value(...)
      # (an sp_RbVal), and typed arithmetic on the result failed C compilation with
      #   invalid operands to binary expression ('sp_RbVal' and 'sp_RbVal')
      #
      # Reduced from the BART engine, where @roots (a poly array of Nodes, ivar
      # arrays never narrow to obj arrays) made Tree.leaf_stats' `node.value *
      # node.value` the build blocker.

      class Node
        attr_accessor :value, :first
        attr_reader :max
        def initialize
          @value = 1.5
          @first = 7
          @max = "peak"
        end
      end

      class Forest
        def initialize
          @roots = []          # ivar array of user objects: stays poly_array
          @roots << Node.new
        end

        def go
          @roots[0].value * @roots[0].value   # Float reader named like Thread#value
        end

        def head
          n = @roots[0]
          n.first + n.first                   # Int reader named like Array#first
        end

        def peak
          @roots[0].max                       # String reader named like Array#max
        end
      end

      f = Forest.new
      puts f.go        # 2.25
      puts f.head      # 14
      puts f.peak      # peak

      # (The builtin side -- Thread#value through a poly container when NO user
      # class defines the name -- is covered by thread_value_through_container.rb.
      # A program mixing BOTH a user `value` reader and poly-carried Threads still
      # hits the missing Fiber arm in the dispatch switch: a separate, pre-existing
      # gap, out of scope here.)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      2.25
      14
      peak
    OUT
  end

  it "poly attr writer" do
    result = ze0(<<~'RUBY')
      # Regression: a setter call (`obj.x = val`) on a parameter typed as
      # a class union must execute the assignment. Previously the dispatch
      # loop emitted no arms for attr_writer setters on poly receivers and
      # silently dropped the store.
      #
      # Three subcases:
      #  1. Single class with `x`, second class without -- the union case
      #     where the dispatch arm is "skipped silently."
      #  2. Two classes share an ivar name; same value type. Verifies
      #     both arms emit and the result temp's C type fits the slot.
      #  3. Two classes share an ivar name; differing value types
      #     (string vs int). Forces the new arm to box the rhs poly-style
      #     for one cls_id and unbox for the other.
      #
      # Verifying via the *side effect* (the ivar's value) rather than the
      # setter expression's return value -- propagating setter returns
      # through the dispatch into the enclosing function's return is a
      # separate concern that this PR doesn't try to fix.

      # --- 1. Single class (the no-op repro) ---------------------------------

      class Foo
        attr_accessor :x
        def initialize; @x = 0; end
      end

      class Bar
        # No `x`; coexists only to widen `obj` to a class union.
      end

      def set_x(obj, v)
        obj.x = v
      end

      foo = Foo.new
      bar = Bar.new
      set_x(foo, 42)
      set_x(bar, 99) rescue nil

      puts foo.x


      # --- 2. Two classes share `body` (string in both) ---------------------

      class Req
        attr_accessor :body
        def initialize; @body = ""; end
      end

      class Res
        attr_accessor :body
        def initialize; @body = ""; end
      end

      def set_body(o, b)
        o.body = b
      end

      req = Req.new
      res = Res.new
      set_body(req, "REQ")
      set_body(res, "RES")

      puts req.body
      puts res.body


      # --- 3. Two classes share `slot` with *different* value types ---------
      # Pre-fix poly_dispatch_return_type returned "int" for any setter
      # whose name didn't appear as an explicit method, so the result temp
      # was mrb_int and the string arm's `tmp = lv` mismatched. The new
      # arm now also unboxes the rhs to the slot's concrete type when
      # the function param widened to poly.

      class IBox
        attr_accessor :slot
        def initialize; @slot = 0; end
      end

      class SBox
        attr_accessor :slot
        def initialize; @slot = ""; end
      end

      def set_slot(o, v)
        o.slot = v
      end

      ibox = IBox.new
      sbox = SBox.new
      set_slot(ibox, 7)
      set_slot(sbox, "hello")

      puts ibox.slot
      puts sbox.slot
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      42
      REQ
      RES
      7
      hello
    OUT
  end

  it "poly concat chain rooted" do
    result = ze0(<<~'RUBY')
      # A chained poly `+` whose later operand allocates.
      #
      # `a + b + c` on poly operands compiles to sp_poly_add(sp_poly_add(a, b), c).
      # The inner result is a freshly built string living only in a C temporary, and
      # `c` is evaluated after it -- so an allocation there collects with the
      # intermediate held nowhere the root scan can see. The sweep freed it and the
      # outer concat read freed memory: a use-after-free that ASAN names and a plain
      # build turns into a segfault or silent corruption, depending on what reused
      # the block.
      #
      # The monomorphic chain never had this; only the poly path left the
      # intermediate unrooted.

      def build_name(prefix, mid, i)
        prefix + mid + i.to_s
      end

      # an Integer call site widens the parameters to poly, which is what routes the
      # `+` through sp_poly_add
      def widen_them
        build_name(1, 2, 0)
      end

      s = ""
      i = 0
      while i < 2000
        s = build_name("blk.", "attn_k.head_", i)
        i += 1
      end
      p s
      p s.length

      # the same shape with the allocating operand in the middle
      def middle(a, b)
        a + b.to_s + "!"
      end

      def widen_middle
        middle(1, 2)
      end

      p middle("n=", 41)

      # a longer chain: every intermediate has to survive the next operand
      def four(a, b, c, d)
        a + b + c + d
      end

      def widen_four
        four(1, 2, 3, 4)
      end

      p four("a", "b", 3.to_s, "d")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "blk.attn_k.head_1999"
      20
      "n=41!"
      "ab3d"
    OUT
  end

  it "poly delete upcase chain" do
    result = ze0(<<~'RUBY')
      # String#delete then #upcase on a value that widened to poly, in a program
      # where a user class (the bundled Set) also defines `delete`: the poly delete
      # must keep the string possibility (unify with the class dispatch) instead of
      # binding exclusively to the user class, and the boxed string transforms must
      # stay poly-typed. Doom's texture parser hits this chain on WAD name fields:
      # `data[offset, 8].delete("\x00").upcase`.
      require 'set'

      def maybe(s)
        return nil if s.empty?
        s
      end

      s = Set.new([1, :two])
      s.delete(1)
      p s.size

      data = maybe("ab\x00\x00cd\x00\x00")
      name = data[0, 4].delete("\x00").upcase
      puts name
      puts data[4, 4].delete("\x00").upcase

      # delete through a poly slot that actually holds the Set.
      mix = [s, "str"]
      ps = mix[0]
      ps.delete(2)
      p s.size

      # ... and one that holds a string.
      puts mix[1].delete("t")

      # The other boxed string transforms on a poly value.
      y = maybe(" Hi ")
      puts y.strip
      puts y.reverse.strip
      p maybe("word").upcase
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      AB
      CD
      1
      sr
      Hi
      iH
      "WORD"
    OUT
  end

  it "poly dispatch attr reader" do
    result = ze0(<<~'RUBY')
      # Issue #119: an attr_reader-defined accessor on a polymorphic
      # receiver was lost — the cls_id-keyed dispatcher in
      # `compile_poly_method_call` only walked `@cls_meth_names` and never
      # checked `@cls_attr_readers`, so the if-cascade emitted an empty
      # body and the result temp stayed at its `0` default. The same shape
      # with an explicit `def v; @v; end` worked fine.
      #
      # Fix: poly_dispatch_return_type now also unions ivar types from
      # each class's attr_readers, and the cls_id-keyed cascade emits a
      # `_t = ((sp_<C> *)recv.v.p)->iv_<name>` branch for classes that
      # only declare the accessor as an attr_reader.

      class C
        def initialize(v); @v = v; end
        attr_reader :v
      end

      class D
        def initialize(v); @v = v; end
        attr_reader :v
      end

      # Same return type per class (string) — result temp stays
      # `const char *`, no boxing.
      def make(flag)
        flag ? C.new("c-val") : D.new("d-val")
      end

      puts make(true).v
      puts make(false).v

      # Mixing an explicit `def v` on one class with attr_reader on
      # others. The dispatcher must cover both shapes.
      class F
        def initialize(v); @v = v; end
        def v; @v; end
      end

      def mix(flag)
        flag ? C.new("from-attr") : F.new("from-def")
      end

      puts mix(true).v
      puts mix(false).v
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      c-val
      d-val
      from-attr
      from-def
    OUT
  end

  it "poly dispatch inherited attr reader" do
    result = ze0(<<~'RUBY')
      # Parent defines attr_reader :val, SubHolder inherits it.
      # Reading .val via a poly-typed parameter must dispatch
      # correctly for both parent and subclass instances.

      class Holder
        def initialize(v)
          @val = v
        end
        attr_reader :val
      end

      class SubHolder < Holder
      end

      def read_val(e)
        e.val
      end

      puts read_val(Holder.new("a"))
      puts read_val(SubHolder.new("b"))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      a
      b
    OUT
  end

  it "poly dispatch ptr array" do
    result = ze0(<<~'RUBY')
      # Polymorphic `[]` and `length` dispatch must reach a PtrArray
      # receiver. Pre-fix, two things were wrong:
      #
      # 1. `emit_poly_builtin_dispatch` had no SP_BUILTIN_PTR_ARRAY branch
      #    for `[]` (the in-source comment said "Defer (the issue notes
      #    this is more involved)"). The dispatch result silently stayed at
      #    its default 0 / NULL when the runtime tag was a PtrArray.
      #
      # 2. `box_expr_to_poly` checked `is_obj_type` *before*
      #    `is_ptr_array_type`. Both predicates fire on `obj_Foo_ptr_array`
      #    (it starts with `obj_` AND ends with `_ptr_array`), so the
      #    is_obj_type branch ran first and emitted
      #    `sp_box_obj(p, find_class_idx("Foo_ptr_array"))`
      #    = `sp_box_obj(p, -1)`. -1 happens to equal SP_BUILTIN_INT_ARRAY,
      #    so the runtime cls_id mis-tagged a PtrArray as an IntArray.
      #    Subsequent dispatch then fell into the IntArray branch and read
      #    garbage out of the PtrArray's layout.
      #
      # `lenof([Foo.new(1), Foo.new(2)])` previously printed 16 (a bogus
      # byte interpreted as IntArray length); now it prints 2.

      class Foo
        def initialize(n)
          @n = n
        end
        attr_reader :n
      end

      class Bar
        def length
          99
        end

        def [](_)
          77
        end
      end

      def lenof(a)
        a.length
      end

      def first(a)
        a[0]
      end

      # `length` over mixed call sites — IntArray, PtrArray<Foo>, and a
      # user class. The PtrArray branch is the new one for this PR.
      puts lenof([1, 2, 3])                  # 3
      puts lenof([Foo.new(1), Foo.new(2)])   # 2
      puts lenof(Bar.new)                    # 99

      # `[]` over the same shapes.
      puts first([10, 20, 30])               # 10
      foo = first([Foo.new(42)])
      puts foo.n                             # 42
      puts first(Bar.new)                    # 77
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      2
      99
      10
      42
      77
    OUT
  end

  it "poly dispatch string receiver split" do
    result = ze0(<<~'RUBY')
      # A poly receiver whose method name a user class also owns.
      #
      # Once any class defines `split` -- the bundled Pathname does -- the poly
      # receiver stopped taking its String arm and became a cls_id switch over the
      # user classes alone. A genuine String matched no case, the slot kept its NULL,
      # and `str.split.join(" ")` answered "" instead of raising or working. Two
      # fixes: String#split gets a tag pre-arm like the other String transforms, and
      # a switch made only of user arms raises on the fallthrough rather than handing
      # back its zero.

      class Path
        attr_reader :s

        def initialize(s)
          @s = s
        end

        def split
          [Path.new("a"), Path.new("b")]
        end

        def bytes
          [1, 2]
        end
      end

      module Util
        module_function

        def wrap(str) = str.split.join(" ")
        def widen(str) = str.length
      end

      # `help` comes off a rest-array pop, so the parameter is poly, not String
      class Flag
        attr_reader :help

        def initialize(*opts)
          @help = opts.pop
        end
      end

      p Util.wrap("Usage:  slap   [options]")
      p Util.wrap(Flag.new("-h", "some  help").help)
      p Util.widen("abcd")

      # the user's own method still wins for its own receiver
      p Path.new("x").split.map { |q| q.s }

      # a value that answers neither raises, rather than reading back as empty
      def poly_split(v) = v.split
      holder = [1, "a b"]
      p poly_split(holder[1])
      begin
        poly_split(holder[0])
        p "no raise"
      rescue NoMethodError
        p "NoMethodError"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "Usage: slap [options]"
      "some help"
      4
      ["a", "b"]
      ["a", "b"]
      "NoMethodError"
    OUT
  end

  it "poly keyed hash method dedup" do
    result = ze0(<<~'RUBY')
      # Hash with Method-typed keys — the optcarrot @peeks/@pokes dedup
      # pattern. Two `obj.method(:foo)` calls produce distinct Method
      # instances but eql? as keys (same bound receiver + fn_ptr), so the
      # `@cache[k] ||= k` cache stores only one entry for them.

      class Cache
        def initialize
          @h = {}
        end
        def add(k)
          @h[k] ||= k
        end
        def has?(k)
          !@h[k].nil?
        end
        def size
          @h.size
        end
      end

      class M
        def self.foo; end
        def self.bar; end
      end

      c = Cache.new
      m1 = M.method(:foo)
      c.add(m1)
      puts c.has?(m1)             # true (same instance round-trips)
      puts c.has?(M.method(:bar)) # false (different fn_ptr)

      # Two distinct Method instances for the same (receiver, fn_ptr)
      # hash and eql? identically, so the cache stays at size 1.
      c.add(M.method(:foo))
      puts c.size                 # 1
      puts c.has?(M.method(:foo)) # true via eql? (m1 returned for the
                                  # query Method instance)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      1
      true
    OUT
  end

  it "poly length string tag" do
    result = ze0(<<~'RUBY')
      # A poly receiver carrying a string at runtime previously had no
      # .length / .size dispatch arm — the per-tag emit covered SP_TAG_OBJ
      # (Array variants) but not SP_TAG_STR. Result: `v.length` on a
      # string-tagged poly silently returned 0. Surfaces when an
      # is_a?(String) guard appears alongside a length check:
      #   if v.is_a?(String) && v.length > 0; ... end
      # The && condition's right half always read 0 and the then-arm
      # never fired.

      class C; def x; 1; end; end

      arr = ["hello", C.new]
      v = arr[0]
      if v.is_a?(String) && v.length > 0
        puts v
      end
      if v.is_a?(String)
        puts v.size.to_s
      end
      puts "done"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello
      5
      done
    OUT
  end

  it "poly receiver string method" do
    result = ze0(<<~'RUBY')
      # A String method called on a POLY receiver. The receiver is only known at run
      # time (a container read, a yield), and the arms below coerced it with
      # sp_poly_to_s -- so a receiver that was not a string got the String method
      # applied to its #to_s RENDERING and answered in silence:
      #
      #   [1, Bare.new][1].upcase   =>  "#<BARE:0X0000560F...>"
      #
      # CRuby has no such method on the object and raises NoMethodError. Implicit
      # conversion does NOT rescue it either: #to_str converts an ARGUMENT into a
      # String slot and never a receiver, so a class defining #to_str still raises
      # here -- which is why this is not the conversion protocol's business.
      class Bare
      end

      class WithToStr
        def to_str
          "CONV"
        end

        def to_s
          "SHOW"
        end
      end

      def try(label)
        yield
      rescue NoMethodError => e
        p [label, e.class, e.message]
      end

      o = [1, Bare.new][1]
      try("upcase")  { p o.upcase }
      try("strip")   { p o.strip }
      try("reverse") { p o.reverse }
      try("chars")   { p o.chars }

      # #to_str does not make the receiver a String
      w = [1, WithToStr.new][1]
      try("to_str upcase") { p w.upcase }

      # every receiver kind that IS a string still answers, and the ones CRuby
      # refuses are refused: a Symbol has its own case conversion but no #strip,
      # and a shared-mutable string is a builtin box rather than a bare tag.
      p [1, "Ab c"][1].upcase
      p [1, String.new("Ab c")][1].upcase
      p [1, String.new("Ab c")][1].chars
      p [1, :ab][1].upcase
      try("sym strip") { p [1, :ab][1].strip }
      try("int upcase") { p [1, 5][1].upcase }
      try("nil strip")  { p [1, nil][1].strip }

      # a user class that owns the name keeps its own arm
      class Owns
        def upcase
          "MINE"
        end
      end
      p [1, Owns.new][1].upcase
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["upcase", NoMethodError, "undefined method 'upcase' for an instance of Bare"]
      ["strip", NoMethodError, "undefined method 'strip' for an instance of Bare"]
      ["reverse", NoMethodError, "undefined method 'reverse' for an instance of Bare"]
      ["chars", NoMethodError, "undefined method 'chars' for an instance of Bare"]
      ["to_str upcase", NoMethodError, "undefined method 'upcase' for an instance of WithToStr"]
      "AB C"
      "AB C"
      ["A", "b", " ", "c"]
      :AB
      ["sym strip", NoMethodError, "undefined method 'strip' for an instance of Symbol"]
      ["int upcase", NoMethodError, "undefined method 'upcase' for an instance of Integer"]
      ["nil strip", NoMethodError, "undefined method 'strip' for nil"]
      "MINE"
    OUT
  end

  it "poly recv aref str key" do
    result = ze0(<<~'RUBY')
      # Issue #341: user-defined `def [](k)` got its parameter type
      # inferred as `mrb_int` regardless of caller arg types. When the
      # receiver was poly (e.g. a method param widened to accept multiple
      # user classes) and callers passed a String key, the per-class
      # arms emitted by compile_poly_method_call called each class's
      # C function with `const char *` arg → Wint-conversion error
      # under -Werror, or hard incompatible-pointer error.
      #
      # A second symptom: the SP_TAG_INT branch of compile_poly_method_call
      # emitted `(recv.v.i >> key) & 1` unconditionally, which is invalid
      # C when `key` isn't an int. The same shape applies to the built-in
      # array dispatches in emit_poly_builtin_dispatch (sp_IntArray_get
      # etc. all expect `mrb_int` keys).
      #
      # Fix:
      #   1. scan_new_calls' receiver-method widening adds a poly arm:
      #      walk every user class that defines `mname` and unify each
      #      class's ptypes with the call site's arg types.
      #   2. compile_poly_method_call gates the int-bit-extract emit on
      #      arg type being int or poly.
      #   3. emit_poly_builtin_dispatch's `[]` block also gates on int/poly
      #      key — for non-int keys the built-in arms are unreachable and
      #      emitting them produces the same Wint-conversion warnings.

      class A
        def [](k)
          "from-A:" + k
        end
      end

      class B
        def [](k)
          "from-B:" + k
        end
      end

      def lookup(receiver, key)
        receiver[key]
      end

      puts lookup(A.new, "alpha")
      puts lookup(B.new, "beta")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      from-A:alpha
      from-B:beta
    OUT
  end

  it "poly recv two arg slice" do
    result = ze0(<<~'RUBY')
      # Issue #659: 2-arg `recv[start, length]` on a poly receiver.
      # The single-arg `[]` dispatcher in emit_poly_builtin_dispatch
      # dropped the second argument: each typed-array arm called
      # `*_Array_get(p, 0)` and there was no SP_TAG_STR arm at all.
      # A String-typed runtime value silently returned the empty
      # string, and an Array-typed value returned just element 0
      # instead of a length-N slice.
      #
      # Fix: add a 2-arg branch that
      #   (a) emits SP_TAG_STR -> sp_str_sub_range for the String recv
      #   (b) emits *_Array_slice for each typed-array recv
      # Both only fire when is_poly_ret is set (the result is itself
      # either a String or an Array; the concrete-typed dispatch
      # already covers single-element returns elsewhere).
      #
      # Also: sp_poly_puts now iterates Array tags one element per line
      # matching MRI's `puts arr` semantics, instead of printing the
      # array's inspect form.

      def tr(s, length: 30)
        s[0, length]
      end

      puts tr("Hello world this is a long string")
      puts tr([1, 2, 3, 4, 5])
      puts tr([10.5, 20.5, 30.5])
      puts tr(["a", "b", "c"])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Hello world this is a long str
      1
      2
      3
      4
      5
      10.5
      20.5
      30.5
      a
      b
      c
    OUT
  end

  it "poly reduce operator symbol" do
    result = ze0(<<~'RUBY')
      # `reduce(init, :+)` on a receiver that stayed boxed -- one of the two arrays
      # `partition` answers -- fell through to the Hash/Enumerable face, which
      # converts the receiver to a hash and refuses an Array at run time. The poly
      # arm that coerces to an array and re-enters the fold emitter required a BLOCK,
      # and the operator-symbol form carries none (#4079).
      class Fixed
        attr_reader :units

        def initialize(units) = @units = units
        def +(other) = Fixed.new(@units + other.units)
        def *(other) = Fixed.new(@units * other.units)
        def negative? = @units.negative?
        def to_s = @units.to_s
      end

      deltas = [Fixed.new(3), Fixed.new(-2), Fixed.new(5)]
      credits, debits = deltas.partition { |d| !d.negative? }

      puts credits.reduce(Fixed.new(0), :+)
      puts debits.reduce(Fixed.new(0), :+)
      puts credits.inject(Fixed.new(1), :*)

      # the block form on the same receiver, which already worked
      puts credits.reduce(Fixed.new(0)) { |a, b| a + b }

      # the seedless form, and Integers through the same shape
      ns = [1, 2, 3, 4]
      evens, odds = ns.partition(&:even?)
      p evens.reduce(0, :+)
      p evens.reduce(:+)
      p odds.inject(:+)

      # receivers that were never boxed keep answering
      p ns.reduce(0, :+)
      p ns.inject(:+)
      p [[1, 2], [3]].map { |x| x.reduce(:+) }

      # and a Hash really does take the face
      h = { "a" => 1, "b" => 2 }
      p h.reduce(0) { |s, (k, v)| s + v }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      8
      -2
      15
      8
      6
      6
      4
      10
      10
      [3, 3]
      3
    OUT
  end

  it "poly slice assign" do
    result = ze0(<<~'RUBY')
      # `compile_slice_assign` had no `rt == "poly"` arm; the
      # fall-through used arg[1] (the slice length) as the assignment
      # value and silently dropped the rhs entirely.
      #
      # Trigger: `arr[i, n] = src` where arr's slot type is plain poly
      # (widened via heterogeneous writes).

      class C
        def init_arr
          @arr = [10, 20, 30, 40, 50]
        end
        def init_str
          @arr = "scalar"     # widens slot to poly
        end
        def replace
          @arr[1, 2] = [99, 88]
        end
        def at(i); @arr[i]; end
      end

      c = C.new
      c.init_arr
      c.replace
      puts c.at(0)
      puts c.at(1)
      puts c.at(2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      10
      99
      88
    OUT
  end

  it "poly str append" do
    result = ze0(<<~'RUBY')
      # Issue #313: a poly-typed value flowing into `String#<<` (mutable_str)
      # used to emit `sp_String_append(io, sp_RbVal_value)` directly, which
      # C-rejects (`const char *` parameter vs `sp_RbVal` argument). The
      # canonical shape: a module-level method that returns
      # `@hash[k] || ""` over a heterogeneously-valued hash has return type
      # `sp_RbVal` per #303, and `io << M.get(:t)` then trips the bug.
      #
      # Fix: at the `mutable_str << poly` codegen site (both expression-
      # and statement-context emitters), wrap the arg in sp_poly_to_s
      # before calling sp_String_append. sp_poly_to_s coerces every tag —
      # strings pass through, ints stringify, sym/nil/etc fall through.
      #
      # Sister fix to #303 — that one made the *hash* poly when written
      # heterogeneously; this one handles the *read path* flowing into a
      # narrow callee.

      module M
        @data = {}

        def self.set(k, v)
          @data[k] = v
        end

        def self.get(k)
          @data[k] || ""
        end
      end

      # Mixed value types force the hash to be inferred as poly per #303.
      M.set(:n, 42)
      M.set(:t, "hello")

      io = String.new
      io << M.get(:t)
      puts io                # hello

      # Also exercise the expression-context << path via chained append.
      io2 = String.new
      (io2 << M.get(:t)) << M.get(:t)
      puts io2               # hellohello
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello
      hellohello
    OUT
  end

  it "poly str delete chain" do
    result = ze0(<<~'RUBY')
      class Wad
        def initialize(blob)
          @blob = blob
        end

        def read_lump(name)
          return nil unless name == "PNAMES"

          @blob
        end
      end

      class Texture
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def self.parse_texture(data, offset)
          name = data[offset, 8].delete("\x00").upcase
          new(name)
        end

        def self.load_all(wad)
          data = wad.read_lump("PNAMES")
          return [] unless data

          [parse_texture(data, 0), parse_texture(data, 8)]
        end
      end

      w = Wad.new("abcd\x00\x00\x00\x00tail\x00\x00\x00\x00rest")
      Texture.load_all(w).each { |t| puts t.name }

      # the plain string form keeps working
      puts "hi\x00\x00\x00".delete("\x00")
      puts Texture.load_all(Wad.new("x\x00\x00\x00\x00\x00\x00\x00")).map(&:name).inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ABCD
      TAIL
      hi
      ["X", ""]
    OUT
  end

  it "poly string append integer" do
    result = ze0(<<~'RUBY')
      # `str << int` appends that CODEPOINT, and one outside the range is a
      # RangeError. A String reached through a POLY slot -- the same local also
      # assigned from a container read, so its type is the union -- fell past the
      # String arms of the boxed `<<` and was read as a NUMBER, so the append
      # answered an integer shift: `a << -1` gave 0 where CRuby raises (#4015).
      a = +"a"
      r = (a << -1 rescue $!.class)
      p r
      h = { k: +"abc" }
      a = h[:k]
      a << "Z"
      p h

      # the same local, both directions
      b = { k: +"abc" }
      c = b[:k]
      p (c << -1 rescue $!.class)
      p (c << 66 rescue $!.class)
      p (c << 0x3042 rescue $!.class)
      p (c << 2**40 rescue $!.class)
      p b

      # through an Array element
      f = [+"q"]
      g = f[0]
      p (g << -5 rescue $!.class)
      p (g << 33 rescue $!.class)
      p f

      # a shared handle appends to a shared handle
      i = [+"x"]
      j = [+"y"]
      k = i[0]
      k << j[0]
      p i

      # and the typed route keeps answering what it answered
      m = +"a"
      p (m << 66 rescue $!.class)
      p (m << -1 rescue $!.class)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      RangeError
      {k: "abcZ"}
      RangeError
      "abcB"
      "abcBあ"
      RangeError
      {k: "abcBあ"}
      RangeError
      "q!"
      ["q!"]
      ["xy"]
      "aB"
      RangeError
    OUT
  end

  it "poly string arm" do
    result = ze0(<<~'RUBY')
      # A String reaching the dispatch through a poly slot -- an element of a nested
      # array, where inference does not narrow past the first level -- answered
      # NoMethodError for methods String has. `strip` had an arm and its one-sided
      # siblings did not, which is the shape of most of these.
      #
      # `to_str` is the one that matters beyond convenience: it is the implicit
      # conversion protocol, so a poly slot holding a String has to answer it.
      #
      # The argument-taking ones are here too. Their arm has to sit OUTSIDE the
      # emit_poly_call block the others are in, which is guarded on argc == 0: an
      # arm for them placed inside it is unreachable, which is what happened first.
      nested = [["k", "  Vv\tz  "]]
      s = nested[0][1]
      p s.lstrip
      p s.rstrip
      p s.to_str
      p s.ascii_only?
      p s.valid_encoding?
      p s.scrub
      p s.encode

      # above ASCII, where ascii_only? has something to say
      u = [["k", "日本"]]
      p u[0][1].ascii_only?
      p u[0][1].to_str
      p u[0][1].lstrip
      p u[0][1].valid_encoding?

      # the whole point is that these agree with the same call on a plain String
      plain = "  Vv\tz  "
      p [s.lstrip == plain.lstrip, s.rstrip == plain.rstrip, s.to_str == plain.to_str]
      p [s.ascii_only? == plain.ascii_only?, s.valid_encoding? == plain.valid_encoding?]

      # the argument-taking shapes, whose arm lives outside the argc==0 block
      p s.unpack("C*")
      p s.unpack("C3")
      p s.byteslice(2)
      p s.byteslice(2, 2)
      p s.scrub("?")
      p s.encode("UTF-8")
      p u[0][1].unpack("C*").length
      p u[0][1].byteslice(0, 3)

      # a poly slot holding something that is not a String still raises
      mixed = [1, "s"]
      def at(a, i); a[i]; end
      begin
        at(mixed, 0).lstrip
      rescue NoMethodError => e
        puts "NoMethodError"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "Vv\tz  "
      "  Vv\tz"
      "  Vv\tz  "
      true
      true
      "  Vv\tz  "
      "  Vv\tz  "
      false
      "日本"
      "日本"
      true
      [true, true, true]
      [true, true]
      [32, 32, 86, 118, 9, 122, 32, 32]
      [32, 32, 86]
      "V"
      "Vv"
      "  Vv\tz  "
      "  Vv\tz  "
      6
      "日"
      NoMethodError
    OUT
  end

  it "poly string at path slot" do
    result = ze0(<<~'RUBY')
      # A String reached through a poly binding landing in a `const char *` slot.
      # The File / Dir / IO surface took its path arguments with emit_expr, so a
      # String ivar the fixpoint had widened -- or any untyped accessor -- went in as
      # a raw sp_RbVal and the generated C did not compile. Three separate sightings
      # (#3256, #3330, #3385) were the same shape at different call sites.
      class Store
        def initialize(path)
          @path = path
        end

        # @path is widened to poly by the nil write below, so every use of it is a
        # boxed value rather than a const char *.
        def forget
          @path = nil
        end

        def write_it(text)
          File.open(@path, "w") { |f| f.write(text) }
        end

        # an empty block: the call's value still has to fit the slot it is typed into
        def touch
          File.open(@path, "a") { |f| }
        end

        def exists = File.exist?(@path)
        def sized = File.size(@path)
        def dir = File.directory?(@path)
        def base = File.basename(@path)
        def full = File.expand_path(@path)
        def read_it = File.read(@path)
        def drop = File.delete(@path)
      end

      path = "spinel_pathslot_#{Process.pid}.tmp"
      s = Store.new(path)
      s.write_it("hello")
      p s.exists
      p s.sized
      p s.dir
      p s.base == path
      p s.full.end_with?(path)
      p s.read_it
      s.touch
      p s.sized
      s.drop
      p s.exists
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      5
      false
      true
      true
      "hello"
      5
      false
    OUT
  end

  it "poly string char index" do
    result = ze0(<<~'RUBY')
      # String#[int] on a value that widened to poly (a method with multiple return
      # paths) must return the single character, not nil.
      def poly_str
        return @c if @c
        s = "ABCDEF"
        @c = s
        s
      end
      d = poly_str
      puts d[0]
      puts d[3]
      puts d[-1]
      puts d[99].inspect
      puts d[0].ord
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      A
      D
      F
      nil
      65
    OUT
  end

  it "poly string method vs class method" do
    result = ze0(<<~'RUBY')
      # A class method of the same name is reached only through a Class-valued
      # receiver: it must not capture a String instance call in a poly union.
      class Foo
        def self.downcase(s)
          s + "!"
        end

        def self.upcase(s, n)
          s * n
        end
      end

      def pick(n)
        if n > 0
          "HeLLo"
        else
          Foo
        end
      end

      k = pick(1)
      p k.downcase
      p k.upcase
      p k.reverse
      p k.chars.first(2)

      # the class method still answers through the class itself
      p Foo.downcase("x")
      p Foo.upcase("y", 3)

      # and an instance member of the name still wins over the String method
      Row = Struct.new(:upcase)
      def pick2(n)
        n > 0 ? Row.new(7) : "text"
      end
      p pick2(1).upcase
      p pick2(0).upcase
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello"
      "HELLO"
      "oLLeH"
      ["H", "e"]
      "x!"
      "yyy"
      7
      "TEXT"
    OUT
  end

  it "poly string transforms" do
    result = ze0(<<~'RUBY')
      # sub / gsub / tr / squeeze on a String that arrives boxed (a Fiber#resume
      # value, a container read), alongside the arms that already worked.
      f = Fiber.new { Fiber.yield("t=1.5"); nil }
      v = f.resume
      p (v.sub("t=", "") rescue $!.class)
      p (v.gsub("=", ":") rescue $!.class)
      p (v.tr("=", "-") rescue $!.class)
      p (v.squeeze("1") rescue $!.class)
      p v.delete_prefix("t=")
      p v.upcase
      p v.split("=")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "1.5"
      "t:1.5"
      "t-1.5"
      "t=1.5"
      "1.5"
      "T=1.5"
      ["t", "1.5"]
    OUT
  end

  it "poly to f via str poly hash" do
    result = ze0(<<~'RUBY')
      # sp_poly_to_f lacked the SP_TAG_STR arm its sibling sp_poly_to_i has
      # (strtoll), so `.to_f` on a poly-typed string value returned 0.0
      # instead of parsing the number. The typed String#to_f path (atof) was
      # unaffected, which makes the miss silent: the same source parses fine
      # under CRuby and with a statically-string receiver, then yields 0.0
      # only when the receiver is poly.
      #
      # Repro shape from a JSON-ish Hash[String, untyped]: read a string
      # value out of a heterogeneous hash and call .to_f on it.

      class C
        def initialize
          @h = { "w" => "900", "h" => "600.5", "pad" => " 2.5", "junk" => "abc", "blank" => "", "n" => 7, "f" => 1.25 }
        end

        def at(k)
          (@h[k]).to_f
        end
      end

      c = C.new
      puts c.at("w")
      puts c.at("h")
      puts c.at("pad")
      puts c.at("junk")
      puts c.at("blank")
      puts c.at("n")
      puts c.at("f")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      900.0
      600.5
      2.5
      0.0
      0.0
      7.0
      1.25
    OUT
  end

  it "poly to i base" do
    result = ze0(<<~'RUBY')
      # `to_i(base)` on a POLY receiver (a value whose static type widened to a union --
      # e.g. an array element that may be Integer or String, or a `case v` result that
      # returns the un-narrowed scrutinee) raised NoMethodError at runtime: the
      # poly-receiver method block is gated on argc == 0, so the one-arg radix form was
      # never handled. It now parses the string with the given base, like
      # String#to_i(base). No-arg to_i (base 10) is unchanged.
      vals = ["ff", 42]        # heterogeneous literal -> poly element type
      p vals[0].to_i(16)       # 255
      p vals[0].to_i           # base 10: "ff" -> 0

      bins = ["101", 0]
      p bins[0].to_i(2)        # 5

      octs = ["17", 0]
      p octs[0].to_i(8)        # 15

      def widen(v)
        case v
        when Integer then v
        when String then v
        else 0
        end
      end
      p widen("2a").to_i(16)   # 42 -- the motivating case/when-dispatch shape

      # A radix only applies to String#to_i; when the poly value is a non-String at
      # runtime (here the Integer 42), CRuby raises ArgumentError rather than parsing
      # the value's string form -- so `42.to_i(16)` is NOT a silent 66.
      begin
        p vals[1].to_i(16)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      255
      0
      5
      15
      42
      ArgumentError: wrong number of arguments (given 1, expected 0)
    OUT
  end

  it "poly to i via str poly hash" do
    _(ze0(<<~'RUBY').stdout).must_equal "42\n"
      # `compile_poly_method_call` lacked a `to_i` arm: `(poly).to_i` fell
      # through to `emit_poly_dispatch` → `emit_poly_builtin_dispatch`,
      # which only handles `[]` / `length` / `size`. The dispatched
      # result temp stayed at its `0` default, so any `.to_i` on a poly-
      # typed receiver returned 0 instead of unboxing the int payload.
      #
      # Repro: heterogeneous Hash returns a poly value; `.to_i` on that.

      class C
        def initialize
          @h = { "a" => 42, "b" => "hello" }
        end
        def at(k)
          (@h[k]).to_i
        end
      end

      c = C.new
      puts c.at("a")
    RUBY
  end

  it "poly to s into string slot" do
    result = ze0(<<~'RUBY')
      # f0a93f3d types a poly receiver's `to_s` for what BOTH arms can hold, which is
      # sp_RbVal when a user arm's return is untyped. Where the result lands in a
      # String slot the assignment needs the unboxing coercion; #4090 reported it
      # emitted uncoerced. It answers correctly now -- this pins the shape so the
      # next arm added to that section has to keep it.

      class Cand
        attr_accessor :id

        def initialize(id)
          self.id = id
        end

        def to_s
          id
        end
      end

      class Req
        attr_accessor :verb
      end

      def build(v)
        r = Req.new
        r.verb = (v || "GET").to_s
        r
      end

      p build(nil).verb
      p build("POST").verb
      p Cand.new("z").to_s

      # the same through a local rather than a writer
      def label(v)
        s = (v || "none").to_s
        s
      end
      p label(nil)
      p label("x")
      p label(Cand.new("c"))

      # and into an interpolation, where the slot is a string too
      def show(v) = "[#{(v || 'd').to_s}]"
      p show(nil)
      p show("e")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "GET"
      "POST"
      "z"
      "none"
      "x"
      "c"
      "[d]"
      "[e]"
    OUT
  end

  it "poly value into str str hash" do
    result = ze0(<<~'RUBY')
      # Issue #651: an ivar inferred as poly (sp_RbVal) because a
      # `kwarg: nil` default makes the writer's param nullable, then
      # read at a `str_str_hash[key] = ivar` site, used to flow the
      # boxed value into `sp_StrStrHash_set(_, _, sp_RbVal)` where the
      # C signature expects `const char *`. C compile failed with
      # "passing sp_RbVal to parameter of incompatible type const
      # char *".
      #
      # Reporter hit this in action_controller/base.rb's
      # `@location = location` (location is a `location: nil` kwarg)
      # followed by `res.headers["Location"] = controller.location`
      # at the Tep::Server entry. Same pattern, minimized here.
      #
      # Fix: compile_expr_as_string unboxes a poly value via `.v.s`
      # so the typed-hash setter type-checks. Mirrors the existing
      # symbol -> sp_sym_to_s coerce in the same helper.

      class C
        attr_reader :loc

        def initialize
          @loc = nil
        end

        def render(loc: nil)
          @loc = loc
        end
      end

      class Bag
        attr_reader :h

        def initialize
          @h = {}
          @h["k"] = "v"
        end
      end

      c = C.new
      c.render(loc: "/b")
      b = Bag.new
      b.h["k2"] = c.loc
      puts b.h["k"]
      puts b.h["k2"]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      v
      /b
    OUT
  end

  it "proc reads attr reader" do
    result = ze0(<<~'RUBY')
      class Scale
        attr_reader :factor
        def initialize(f); @factor = f; end
        def make; ->(n) { n * factor }; end
      end
      p Scale.new(3).make.call(2)
      class S2
        attr_accessor :k
        def initialize(k); @k = k; end
        def pr; proc { |n| n + k }; end
        def lm; lambda { |n| n * k }; end
      end
      p S2.new(4).pr.call(1)
      p S2.new(4).lm.call(2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      6
      5
      8
    OUT
  end

  it "proc source location is a string integer pair" do
    result = ze0(<<~'RUBY')
      loc = ->(x) { x }.source_location
      p loc.class
      p loc.length
      p loc[0].class
      p loc[1].class
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Array
      2
      String
      Integer
    OUT
  end

  it "ptr array" do
    result = ze0(<<~'RUBY')
      # Pointer-array (`<obj>_ptr_array`) coverage — typed-obj `[]` map,
      # value-class instances in array literals (and via `push`/`<<`),
      # and slot widening from `[nil] * N` writes. Was four tests; the
      # only class-name collisions were Foo (same definition reused
      # across the two value-class sections — kept once) and Bag (two
      # unrelated shapes — section 1's Bag renamed to MapBag).

      # === Section 1: ptr_array map ===
      # `compile_map_expr` had no `ptr_array` recv branch — `.map { ... }`
      # on a typed `obj_X[]` ivar/local fell through to the trailing
      # `"0"` placeholder.
      class Box
        attr_reader :v
        def initialize(v); @v = v; end
      end

      class MapBag
        def initialize
          @items = [Box.new(1), Box.new(2), Box.new(3)]
        end
        def doubled
          @items.map { |b| b.v * 2 }
        end
        def names
          @items.map { |b| "v=#{b.v}" }
        end
      end

      mbag = MapBag.new
      mints = mbag.doubled
      puts mints.length    # 3
      puts mints[0]        # 2
      puts mints[2]        # 6
      mnames = mbag.names
      puts mnames.length   # 3
      puts mnames[0]       # v=1
      puts mnames[2]       # v=3

      # === Section 2 + 3: value-class instances in ptr_array (literal + push) ===
      # A class with no attr_writers / no mutating methods would normally
      # be value-type'd, but its instances landing in an array literal or
      # being push'd into one must demote it to a heap-allocated obj so
      # `sp_PtrArray_push`'s `void *` arg type-checks. PR #87 covered the
      # literal case; #91 (follow-up) extended it to push / <<.
      class Foo
        def initialize(x); @x = x; end
        attr_reader :x
      end

      # Literal form.
      flit = [Foo.new(1), Foo.new(2), Foo.new(3)]
      puts flit.length
      flit.each { |f| puts f.x }

      # `push` form.
      fpush = []
      fpush.push(Foo.new(1))
      fpush.push(Foo.new(2))
      puts fpush.length
      fpush.each { |f| puts f.x }

      # `<<` form (same code path through the parser).
      fsh = []
      fsh << Foo.new(10)
      fsh << Foo.new(20)
      fsh << Foo.new(30)
      puts fsh.length
      fsh.each { |f| puts f.x }

      # === Section 4: ptr_array slot widening from [nil] * N ===
      # `@arr = [nil] * N` followed by `@arr[i] = obj` widens the slot
      # to `<obj>_ptr_array`. Without the widening, the slot stays at
      # the default IntArray and the object pointer write is truncated.
      class Item
        def initialize(label)
          @label = label
          @history = [0]   # array ivar keeps Item off the value-type fast path
        end
        def visit
          @history << @history.last + 1
          @label
        end
        def visits
          @history.length - 1
        end
      end

      class Bag
        def initialize
          @slots = [nil] * 4
          @slots[0] = Item.new("a")
          @slots[1] = Item.new("b")
          @slots[3] = Item.new("d")
        end
        attr_reader :slots
        def visit_at(i)
          @slots[i].visit
        end
      end

      b = Bag.new
      puts b.visit_at(0)
      puts b.visit_at(1)
      puts b.visit_at(3)
      puts b.slots[0].visits   # 1
      puts b.slots[1].visits   # 1
      puts b.slots[3].visits   # 1
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      2
      6
      3
      v=1
      v=3
      3
      1
      2
      3
      2
      1
      2
      3
      10
      20
      30
      a
      b
      d
      1
      1
      1
    OUT
  end

  it "ptr array to poly array at call" do
    result = ze0(<<~'RUBY')
      # #582 (Sam Ruby). Function param inferred as poly_array because
      # one caller passes a heterogeneous literal `[A.new, "x"]`, but
      # another caller passes a homogeneous PtrArray-shaped
      # `[A.new, A.new]` (sp_PtrArray of obj_A). The two array layouts
      # are incompatible at the C boundary (sp_PtrArray slots are raw
      # `void *`, sp_PolyArray slots are tagged sp_RbVal), so the
      # call site needs a conversion: allocate a fresh PolyArray and
      # box each PtrArray element via sp_box_obj.
      #
      # Fix: in compile_expr_for_expected_type, detect
      # `*_ptr_array → poly_array` at the call boundary and emit an
      # inline conversion loop. Element class id comes from the
      # ptr_array's elem type (`obj_A` → cls_id for A).

      class A
        attr_reader :tag
        def initialize(t = "default"); @tag = t; end
      end

      def take(arr)
        arr.first
      end

      a_arr = [A.new("homogeneous"), A.new("entry2")]
      mixed = [A.new("mixed_a"), "x"]
      r1 = take(a_arr)
      r2 = take(mixed)
      # r1 should be an A instance (poly value carrying the A boxed via the conversion).
      # Verify by reading back the tag via runtime cls_id check.
      if r1.is_a?(A)
        puts r1.tag
      else
        puts "NOT_A"
      end
      if r2.is_a?(A)
        puts r2.tag
      else
        puts "NOT_A"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      homogeneous
      mixed_a
    OUT
  end

  it "raise of a plain string is an implicit runtime error" do
    result = ze0(<<~'RUBY', path: "core/string/raise_of_a_plain_string_is_an_implicit_runtime_error.rb")
      class Risky
        def check
          raise "plain string error"
        end
      end
      Risky.new.check
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "core/string/raise_of_a_plain_string_is_an_implicit_runtime_error.rb:3:in 'Risky#check': plain string error (RuntimeError)\n\tfrom core/string/raise_of_a_plain_string_is_an_implicit_runtime_error.rb:6:in '<main>'\n"
    _(result.status).must_equal 1
  end

  it "range arguments across string and array slicing" do
    result = ze0(<<~'RUBY')
      p "hello".byteslice(1..3)
      p "hello".byteslice(2..)
      p "hello".byteslice(10..12)
      a = [1, 2, 3, 4]
      p a.slice!(1..2)
      p a
      b = [0, 0, 0, 0, 0]
      b.fill(1..2) { |i| i + 100 }
      p b
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ell"
      "llo"
      nil
      [2, 3]
      [1, 4]
      [0, 101, 102, 0, 0]
    OUT
  end

  it "range each slice answers receiver" do
    result = ze0(<<~'RUBY')
      v = (1..5).each_cons(2) { |s| s }
      p v

      v = (1..5).each_slice(2) { |s| s }; p v        # Ruby: 1..5    Spinel: [1, 2, 3, 4, 5]
      v = (1..5).each_cons(2) { |s| s }; p v.class   # Ruby: Range   Spinel: Array

      p((1..5).each_cons(2) { |s| s })                  # => 1..5
      p((1..5).each_slice(2) { |s| s })                 # => 1..5
      v = [1, 2, 3].each_cons(2) { |s| s }; p v         # => [1, 2, 3]
      v = [1, 2, 3].each_slice(2) { |s| s }; p v        # => [1, 2, 3]
      v = (1..5).each { |s| s }; p v                    # => 1..5
      v = (1..5).each_entry { |s| s }; p v              # => 1..5

      v = (1..5).reverse_each { |s| s }; p v
      h = { a: 1, b: 2 }
      v = h.each_slice(1) { |s| s }; p v
      p((1..6).each_cons(3) { |s| s })
      acc = []; (1..5).each_slice(2) { |s| acc << s }; p acc
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1..5
      1..5
      Range
      1..5
      1..5
      [1, 2, 3]
      [1, 2, 3]
      1..5
      1..5
      1..5
      {a: 1, b: 2}
      1..6
      [[1, 2], [3, 4], [5]]
    OUT
  end

  it "range each slice cons" do
    result = ze0(<<~'RUBY')
      # Range#each_slice / #each_cons: the block form, the blockless
      # Enumerator form (.to_a), and the .map chain all materialize the
      # integer range once and reuse the array emitters (range_enum_redispatch).
      p (1..6).each_slice(2).to_a
      (1..6).each_slice(2) { |s| p s }
      p (1..6).each_slice(2).map { |s| s.sum }
      p (1..6).each_cons(3).to_a
      (1..5).each_cons(2) { |a, b| puts "#{a}-#{b}" }
      p (1..6).each_cons(2).map { |a, b| a * b }
      r = (2..9)
      p r.each_slice(4).to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1, 2], [3, 4], [5, 6]]
      [1, 2]
      [3, 4]
      [5, 6]
      [3, 7, 11]
      [[1, 2, 3], [2, 3, 4], [3, 4, 5], [4, 5, 6]]
      1-2
      2-3
      3-4
      4-5
      [2, 6, 12, 20, 30]
      [[2, 3, 4, 5], [6, 7, 8, 9]]
    OUT
  end

  it "range each slice returns receiver" do
    result = ze0(<<~'RUBY')
      p((1..5).each_cons(2) { |s| s })
      p((1..5).each_slice(2) { |s| s })
      p([1, 2, 3].each_cons(2) { |s| s })
      p([1, 2, 3].each_slice(2) { |s| s })
      p({ a: 1, b: 2 }.each_cons(2) { |s| s })
      p({ a: 1, b: 2 }.each_slice(2) { |s| s })
      p((1..5).to_a.each_slice(2) { |s| s })
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1..5
      1..5
      [1, 2, 3]
      [1, 2, 3]
      {a: 1, b: 2}
      {a: 1, b: 2}
      [1, 2, 3, 4, 5]
    OUT
  end

  it "range step walks by succ" do
    result = ze0(<<~'RUBY')
      # `Range#step` over a NON-numeric range walks by `succ`, in both the block
      # and the blockless form.
      #
      # `docs/COMPATIBILITY.md` recorded this as the one outright panic in the
      # document -- "answers the right Enumerator, but WALKING it panics". It
      # does not: every row below matches ruby 4.0.6, so the note is deleted and
      # these rows replace it.

      p ("a".."e").step(2).to_a
      out = []
      ("a".."e").step(2) { |v| out << v }
      p out
      p ("a".."e").step(1).to_a
      p ("aa".."ad").step(2).to_a
      p ("a".."e").step(2).class
      p (:a..:e).step(2).to_a

      # A user class with `succ` and `<=>` walks the same way. Ruby reaches for
      # `+` first and only falls back to `succ`, so a class without `+` raises
      # -- which is the row that pins WHICH protocol is being used.
      class Countable
        include Comparable
        attr_reader :n

        def initialize(n) = @n = n
        def succ = Countable.new(@n + 1)
        def <=>(o) = @n <=> o.n
        def inspect = "C#{@n}"
      end
      begin
        (Countable.new(1)..Countable.new(5)).step(2).to_a
      rescue NoMethodError => e
        puts e.message
      end

      # Every numeric range keeps its ArithmeticSequence.
      p (1..9).step(2).class
      p (1..9).step(2).to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "c", "e"]
      ["a", "c", "e"]
      ["a", "b", "c", "d", "e"]
      ["aa", "ac"]
      Enumerator
      [:a, :c, :e]
      undefined method '+' for an instance of Countable
      Enumerator::ArithmeticSequence
      [1, 3, 5, 7, 9]
    OUT
  end

  it "range string cover" do
    result = ze0(<<~'RUBY')
      # Range#include? / cover? / === on string ranges. Spinel inlines
      # strcmp bounds for literal string-range receivers rather than
      # trying to fit the receiver into the int-only sp_Range struct.

      puts ("a".."z").include?("m")
      puts ("a".."z").cover?("m")
      puts ("a".."z").include?("Z")
      puts ("a".."z").cover?("a")
      puts ("a".."z").cover?("z")
      puts ("a"..."z").cover?("z")  # exclusive end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      false
      true
      true
      false
    OUT
  end

  it "rational and complex parse string arguments" do
    result = ze0(<<~'RUBY')
      p Rational("3/4")
      p Rational("  -5/2 ")
      p Rational("6")
      p Rational("2.5")
      p Rational(3)
      p Complex("2+3i")
      p Complex("1+2i")
      p Complex("3")
      p Complex("-i")
      p Complex("4i")
      def t; yield; rescue => e; "#{e.class}"; end
      p t { Rational("abc") }
      p t { Complex("xyz") }
      p t { Rational(1, 0) }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      (3/4)
      (-5/2)
      (6/1)
      (5/2)
      (3/1)
      (2+3i)
      (1+2i)
      (3+0i)
      (0-1i)
      (0+4i)
      "ArgumentError"
      "ArgumentError"
      "ZeroDivisionError"
    OUT
  end

  it "rational complex string args" do
    result = ze0(<<~'RUBY')
      # Kernel#Rational and Kernel#Complex parse a String argument as a numeric
      # literal, rather than reading the string's pointer as an integer.

      # Rational("n/d" | "n.d" | "n"): the DECIMAL value, so "2.5" is exactly 5/2
      # (not the Float value). Whitespace and a sign are allowed; a zero denominator
      # raises ZeroDivisionError, an unparseable string ArgumentError.
      p Rational("3/4")
      p Rational("  -5/2 ")
      p Rational("6")
      p Rational("2.5")
      p Rational(3)          # the numeric form is unchanged

      # Complex("a+bi"): each component is an Integer without a decimal point, else a
      # Float; a bare "±i" is the unit, a pure real or pure imaginary is supported.
      p Complex("2+3i")
      p Complex("1+2i")
      p Complex("3")
      p Complex("-i")
      p Complex("4i")
      p Complex("1.5-2.5i")

      def caught
        yield
      rescue => e
        "#{e.class}: #{e.message}"
      end
      p caught { Rational("abc") }
      p caught { Complex("xyz") }
      p caught { Rational(1, 0) }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      (3/4)
      (-5/2)
      (6/1)
      (5/2)
      (3/1)
      (2+3i)
      (1+2i)
      (3+0i)
      (0-1i)
      (0+4i)
      (1.5-2.5i)
      "ArgumentError: invalid value for convert(): \"abc\""
      "ArgumentError: invalid value for convert(): \"xyz\""
      "ZeroDivisionError: divided by 0"
    OUT
  end

  it "rational mod cmp slice default wave10" do
    result = ze0(<<~'RUBY')
      # Rational %/modulo/remainder/divmod, Complex <=> (real-valued compare,
      # nil otherwise), slice! on literal receivers, and Hash#default after
      # a default= on an un-narrowed empty hash.
      p("hello".slice!(/l+/))
      p("hello".slice!("ell"))
      s = "hello"
      p(s.slice!(/l+/))
      p s
      a = {}; a.default = 9; c = (a.default); p c
      p a[:missing]
      b = {}
      b.default = "d"
      p b["nope"]
      p(({}.default = 5))
      v = Rational(7,2) % Rational(1,3); p v
      p(Rational(7,2) % 2)
      p(Rational(7,2).modulo(Rational(1,3)))
      p(Rational(-7,2) % Rational(1,3))
      p(Rational(7,2).remainder(Rational(1,3)))
      p(Rational(-7,2).remainder(Rational(1,3)))
      p(Rational(7,2).divmod(Rational(1,3)))
      p(Complex(2, 0) <=> Complex(2, 0))
      p(Complex(3, 0) <=> Complex(2, 0))
      p(Complex(1, 0) <=> Complex(2, 0))
      p(Complex(2, 0) <=> 3)
      p(Complex(2, 3) <=> Complex(1, 1))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ll"
      "ell"
      "ll"
      "heo"
      9
      9
      "d"
      5
      (1/6)
      (3/2)
      (1/6)
      (1/6)
      (1/6)
      (-1/6)
      [10, (1/6)]
      0
      1
      -1
      -1
      nil
    OUT
  end

  it "reader named after string method" do
    result = ze0(<<~'RUBY')
      # A reader whose name is also a String method, read through a poly receiver.
      # The poly shortcuts stringified the receiver and applied the String method, so
      # a Struct member called `upcase` answered the UPCASED #inspect of the object
      # holding it. Declining to the general dispatch is not enough on its own: that
      # dispatch only covers SP_TAG_OBJ, so a genuine String receiver in the same
      # program then fell through to the slot's seed -- nil, or 0 for #bytes.
      E = Struct.new(:ip, :upcase, :downcase, :capitalize, :swapcase,
                     :strip, :reverse, :chomp, :chop, :succ, :chr, :bytes, :chars)
      e = E.new("a", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)

      # the member wins, inside a block and through &:sym
      [e].each { |x| p [x.upcase, x.downcase, x.capitalize, x.swapcase] }
      [e].each { |x| p [x.strip, x.reverse, x.chomp, x.chop] }
      [e].each { |x| p [x.succ, x.chr, x.bytes, x.chars] }
      p [e].map(&:upcase)
      p [e].map(&:bytes)

      D = Data.define(:upcase, :bytes)
      p [D.new(upcase: 7, bytes: 8)].map { |d| [d.upcase, d.bytes] }

      class C
        attr_accessor :upcase, :reverse, :chars
        def initialize; @upcase = 1; @reverse = 2; @chars = 3; end
      end
      p [C.new].map { |o| [o.upcase, o.reverse, o.chars] }

      # ... and a real String receiver still answers String, in the same program.
      # A mixed array makes the element genuinely poly, which is the case that broke.
      mixed = ["  Ab  ", 65]
      p mixed[0].upcase
      p mixed[0].downcase
      p mixed[0].capitalize
      p mixed[0].swapcase
      p mixed[0].strip
      p mixed[0].reverse
      p mixed[0].bytes
      p mixed[0].chars
      p mixed[1].chr
      p ["x\n", 1][0].chomp
      p ["xy", 1][0].chop
      p ["az", 1][0].succ
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [1, 2, 3, 4]
      [5, 6, 7, 8]
      [9, 10, 11, 12]
      [1]
      [11]
      [[7, 8]]
      [[1, 2, 3]]
      "  AB  "
      "  ab  "
      "  ab  "
      "  aB  "
      "Ab"
      "  bA  "
      [32, 32, 65, 98, 32, 32]
      [" ", " ", "A", "b", " ", " "]
      "A"
      "x"
      "x"
      "ba"
    OUT
  end

  it "reduce symbol only method" do
    result = ze0(<<~'RUBY')
      # `reduce(:sym)` / `inject(seed, :sym)` names the method by Symbol, which is not
      # a CallNode, so the reachability walk never saw the name and pruned the method.
      # The fold then fell through to the unresolved-call raise -- "undefined method
      # '^' for an instance of F" for a method the program plainly defines. Only a
      # method with NO other call site was affected, which is what made it look like
      # an operator problem rather than a reachability one (#4069).
      class F
        attr_reader :u
        def initialize(u) = @u = u
        def ^(other) = F.new(u + other.u)
        def to_s = u.to_s
      end
      p [F.new(1), F.new(2)].reduce(F.new(0), :^).to_s

      class G
        attr_reader :n
        def initialize(n) = @n = n
        def +(o) = G.new(n + o.n)
        def merge_with(o) = G.new(n * o.n)
      end
      p [G.new(1), G.new(2)].reduce(:+).n
      p [G.new(1), G.new(2)].inject(G.new(10), :+).n
      p [G.new(2), G.new(3)].reduce(:merge_with).n
      p [G.new(2), G.new(3)].inject(G.new(4), :merge_with).n

      # a method that also has an ordinary call site still works
      class H
        attr_reader :v
        def initialize(v) = @v = v
        def |(o) = H.new(v + o.v)
      end
      p (H.new(1) | H.new(2)).v
      p [H.new(1), H.new(2)].reduce(H.new(0), :|).v
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "3"
      3
      13
      6
      24
      3
      3
    OUT
  end

  it "reopen split superclass dispatch" do
    result = ze0(<<~'RUBY', path: "core/string/reopen_split_superclass_dispatch.rb")
      # Imported from the spinel corpus at c55d9bdb.
      # A class opened BARE and reopened with a superclass is ruby's own
      # `TypeError: superclass mismatch for class Sub` -- a real bare `class Sub`
      # gives the class Object as its parent, and a later `< Base` conflicts with
      # that. A forward SHELL (zeo's own device for a name a later file defines)
      # carries no such history and the reopen establishes its parent instead.
      module M
        class Base
          def run
            hook ? "blocked" : "ok"
          end
          def hook
            false
          end
        end

        class Sub                        # bare opening: holds a nested class
          class Nested
            def z
              1
            end
          end
        end

        class Sub < Base                 # reopen: declares a conflicting superclass
          def extra
            "x"
          end
        end
      end

      class Child < M::Sub
        def hook
          true
        end
      end

      puts Child.new.run
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "core/string/reopen_split_superclass_dispatch.rb:25:in '<module:M>': superclass mismatch for class Sub (TypeError)\n\tfrom core/string/reopen_split_superclass_dispatch.rb:7:in '<main>'\n"
    _(result.status).must_equal 1
  end

  it "rescue attr with sibling exc subclass" do
    result = ze0(<<~'RUBY')
      # Reading a rescued exception's attr must still compile when the program
      # defines a SECOND, unrelated exception subclass. The second subclass's
      # `initialize` `message` param is never constrained to a String (its own
      # call sites don't pin it), so `super(message)` must coerce the poly message
      # into the const-char* msg slot rather than emit a struct assignment.

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

      begin
        raise AError.new("boom", code: 9)
      rescue AError => ea
        puts ea.code
        puts "code is #{ea.code}"
      end

      begin
        raise BError.new("bad", 5)
      rescue BError => eb
        puts eb.level
        puts "msg=#{eb.message} level=#{eb.level}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      9
      code is 9
      5
      msg=bad level=5
    OUT
  end

  it "ruby engine name" do
    result = ze0(<<~'RUBY')
      p RUBY_ENGINE
      p RUBY_ENGINE.is_a?(String)
      p(RUBY_ENGINE == "spinel")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ruby"
      true
      false
    OUT
  end

  it "same named attr no widen" do
    _(ze0(<<~'RUBY').stdout).must_equal "104\n"
      # #684: a concretely-typed receiver's attr_reader must not widen to
      # poly just because an unrelated class shares the same attr name.
      class Bag
        attr_accessor :payload
        def initialize; @payload = {"k" => "v"}; end
      end

      class Wire
        attr_accessor :payload
        def initialize; @payload = ""; end
      end

      def first_byte_of(s)
        s.bytes[0]
      end

      def handle_wire(w)
        first_byte_of(w.payload)
      end

      _b = Bag.new
      _w = Wire.new
      _w.payload = "hello"
      puts handle_wire(_w)
    RUBY
  end

  it "send with a non literal target binds keyword args" do
    _(ze0(<<~'RUBY').stdout).must_equal "42\n"
      # The G2 trailing-kwargs-hash convention: `send`'s truly-dynamic
      # fallback (non-literal target name) carries kwargs as one trailing
      # Hash; the callee's trampoline pops and binds it.

      class Foo
        def bar(x:)
          x
        end
      end
      name = :bar
      puts Foo.new.send(name, x: 41) + 1
    RUBY
  end

  it "shared string reference links" do
    _(ze0(<<~'RUBY').stdout).must_equal "\"abz\"\n"
      # The same String written twice is a `@`-link the second time, so a
      # mutation through one alias is visible through the other after load.

      s = "ab"
      g = Marshal.load(Marshal.dump([s, s]))
      g[0] << "z"
      p g[1]
    RUBY
  end

  it "short strings live in their cell" do
    result = ze0(<<~'RUBY')
      # A String of up to 87 bytes keeps them in its own cell; growing past
      # that moves them to a buffer, and every way of writing keeps the
      # bytes right across the move and back.
      s = +"a" * 80
      s << "b" * 20
      puts s.size, s[78, 5]
      s.replace("short")
      puts s, s.size
      s << "x" * 200
      puts s.size, s[-3..]
      s.replace("tiny")
      puts s.dup, s.clone.frozen?, s.dup << "!"
      t = s.dup
      t[1, 2] = "ZZZZZZZZZZ" * 10
      puts t.size, t[0, 4], s
      u = +"seed"
      100.times { |i| u.append_as_bytes(i.chr) }
      puts u.bytesize, u.getbyte(4), u.getbyte(103)
      v = String.new("abc", capacity: 500)
      v << "d" * 90
      puts v.size, v.encoding
      w = "".dup
      w.replace(w)
      puts w.inspect
      x = "abc".dup
      x.replace(x)
      x.insert(1, "Z" * 100)
      puts x.size, x[0, 3], x[-2..]
      y = ("k" * 50).freeze
      puts y.frozen?, y.dup.size, (y + y).size, (y + y + y).size
      z = 3.times.map { |i| "row #{i}" * 20 }
      puts z.map(&:size).inspect, z[2][0, 5]
      require "objspace"
      puts ObjectSpace.memsize_of("x") <= ObjectSpace.memsize_of("x" * 1000)
      puts ObjectSpace.memsize_of("x" * 1000) > 1000

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      100
      aabbb
      short
      5
      205
      xxx
      tiny
      false
      tiny!
      102
      tZZZ
      tiny
      104
      0
      99
      93
      UTF-8
      ""
      103
      aZZ
      bc
      true
      50
      100
      150
      [100, 100, 100]
      row 2
      true
      true
    OUT
  end

  it "slice before after block" do
    result = ze0(<<~'RUBY')
      p [1, 2, 4, 9, 10, 11, 12, 0].slice_before { |x| x.even? }.to_a
      p [1, 2, 4, 9, 10, 11, 12, 0].slice_after { |x| x.even? }.to_a
      p %w[a bb c dd].slice_before { |s| s.length == 1 }.to_a
      p [3, 1, 4, 1, 5].slice_after { |x| x == 1 }.to_a
      e = [1, 2, 3, 4].slice_before { |x| x > 2 }
      p e.to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1], [2], [4, 9], [10, 11], [12], [0]]
      [[1, 2], [4], [9, 10], [11, 12], [0]]
      [["a", "bb"], ["c", "dd"]]
      [[3, 1], [4, 1], [5]]
      [[1, 2], [3], [4]]
    OUT
  end

  it "slice length overflow" do
    result = ze0(<<~'RUBY', argv: ["9223372036854775807"])
      # Ruby hands a slice length straight through from user code, so `a[1, huge]`
      # reaches the clamp with len == INT64_MAX. Written as `start + len > N` the sum
      # overflows, wraps negative, the guard reads false, and the clamp is skipped --
      # after which the copy loop, bounded only by len, walks off the heap. This
      # segfaulted on ordinary -O2 for an index CRuby answers fine.
      n = ARGV[0].to_i     # runtime value, so nothing folds it away

      p(["x", "y", "z"][1, n])
      p([1, 2, 3][1, n])
      p([1.5, 2.5, 3.5][1, n])
      p([1, "x", :y, 2.0][1, n])
      p("abcdef".byteslice(1, n))
      p("abcdef"[1, n])
      p("日本語です"[1, n])

      # the boundary cases the clamp still has to get right
      p([1, 2, 3][3, n])
      p([1, 2, 3][0, n])
      p("abc".byteslice(3, n))
      p([1, 2, 3][1, 0])
      p([1, 2, 3][-2, n])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["y", "z"]
      [2, 3]
      [2.5, 3.5]
      ["x", :y, 2.0]
      "bcdef"
      "bcdef"
      "本語です"
      []
      [1, 2, 3]
      ""
      []
      [2, 3]
    OUT
  end

  it "slice when first class" do
    result = ze0(<<~'RUBY')
      # int_array.slice_when { |a,b| cond }.to_a returns a first-class array of slices
      # (a new slice starts before b whenever the block is truthy).
      p [1, 2, 4, 5, 7].slice_when { |a, b| b - a > 1 }.to_a
      p [1, 2, 3].slice_when { |a, b| false }.to_a
      p [1, 2, 3].slice_when { |a, b| true }.to_a
      p [42].slice_when { |a, b| a < b }.to_a
      p [1, 3, 5, 2, 4].slice_when { |a, b| a > b }.to_a
      # the result is a real array: chain further
      p [1, 2, 4, 5].slice_when { |a, b| b - a > 1 }.to_a.map { |s| s.sum }
      p [1, 2, 4, 5, 7].slice_when { |a, b| b - a > 1 }.to_a.length
      # chunk_while (the inverse) still works
      p [1, 2, 4, 9, 10, 11, 12, 0].chunk_while { |a, b| b - a == 1 }.to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [[1, 2], [4, 5], [7]]
      [[1, 2, 3]]
      [[1], [2], [3]]
      [[42]]
      [[1, 3, 5], [2, 4]]
      [3, 9]
      3
      [[1, 2], [4], [9, 10, 11, 12], [0]]
    OUT
  end

  it "small string rules follow ruby" do
    result = ze0(<<~'RUBY')
      # Small String rules, each as ruby answers it.
      def t = yield rescue [$!.class, $!.message]

      o = Object.new
      def o.to_str = "x"
      def o.==(v) = (p [:asked, v]; true)
      S = Class.new(String)

      p t { s = +"aaabbb"; s.squeeze!("a"); s }, t { (+"a").prepend(1) }, t { "lit".freeze.send(:initialize, "x") }
      p t { "x" == o }, t { (+"a".encode("US-ASCII")).append_as_bytes("b").encoding }, t { ["ab"].pack("H*").unpack1("H*").encoding }
      p t { r = []; "abc".unpack("C*") { r << _1 }.inspect + r.inspect }, t { ["a\t"].pack("M") }, t { [1].pack("m") }
      p t { q = S.new("zzq").freeze; (-q).class }, t { (-"zzq".dup).class }, t { ({S.new("a") => 1}).keys[0].class }

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "abbb"
      [TypeError, "no implicit conversion of Integer into String"]
      [FrozenError, "can't modify frozen String: \"lit\""]
      [:asked, "x"]
      true
      #<Encoding:US-ASCII>
      #<Encoding:US-ASCII>
      "nil[97, 98, 99]"
      "a\t=\n"
      [TypeError, "no implicit conversion of Integer into String"]
      S
      String
      S
    OUT
  end

  it "splat slice keys" do
    result = ze0(<<~'RUBY')
      # `Hash#slice(*keys)` is variadic, but `slice` sat in the fixed-arity splat
      # expansion table with arity 1, so a splat whose length is not a literal was
      # rewritten to `keys[0]` -- every key after the first silently dropped. A
      # constant splat was not expanded at all and reached the emitter as one whole
      # array, which the key coercion answered nothing for. Three spellings of one
      # splat gave three answers (#4164).
      ATTRS = [:a, :b]
      IDX = [1, 2]
      h = { a: 1, b: 2, c: 3 }
      x = ATTRS
      y = IDX

      def poly(n) = n > 0 ? { a: 1, b: 2, c: 3 } : 7
      def polys(n) = n > 0 ? "abcdef" : 7
      def polya(n) = n > 0 ? [10, 20, 30, 40] : 7

      p h.slice(*[:a, :b]).keys
      p h.slice(*ATTRS).keys
      p h.slice(*x).keys
      p h.slice(:a, *[:b]).keys
      p h.slice(*[]).keys
      p h.except(*ATTRS).keys
      p h.values_at(*ATTRS)

      # the same splat on a BOXED receiver: Hash#slice answers a sub-Hash, while
      # String#slice / Array#slice is #[] and takes one argument or two -- only the
      # run time says which, so the key list decides
      p poly(1).slice(*ATTRS).keys
      p poly(1).values_at(*ATTRS)
      p polys(1).slice(*IDX)
      p polya(1).slice(*IDX)
      p polys(1).slice(*[1])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [:a, :b]
      [:a, :b]
      [:a, :b]
      [:a, :b]
      []
      [:c]
      [1, 2]
      [:a, :b]
      [1, 2]
      "bc"
      [20, 30]
      "b"
    OUT
  end

  it "split default separator global" do
    result = ze0(<<~'RUBY')
      $; = ","
      p "a,b".split
      p "a,b".split(nil)
      p "a b".split
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b"]
      ["a", "b"]
      ["a b"]
    OUT
  end

  it "split keeps leading and embedded empties but drops trailing ones" do
    result = ze0(<<~'RUBY')
      puts "a,b,,c".split(/,/)
      puts "---"
      puts ",a,b".split(/,/)
      puts "---"
      puts "a1b2c3".split(/\d/)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      a
      b

      c
      ---

      a
      b
      ---
      a
      b
      c
    OUT
  end

  it "split on unresolved chain" do
    _(ze0(<<~'RUBY').stdout).must_equal "ok\n"
      # A method compiled but never called whose body splits an unresolvable chain
      # (`Undefined.application.class.to_s.split("::")`) must still produce
      # compilable C: the chain resolves to a poly nil at codegen even though it is
      # typed String, so the split receiver is coerced (sp_poly_to_s) rather than
      # emitted as a raw sp_box_nil() where a const char* is expected.
      class T
        def initialize(s)
          @s = s
        end
        def name
          @s[:name] || fallback
        end
        def fallback
          Undefined.application.class.to_s.split("::").first
        end
      end

      puts T.new({ name: "ok" }).name
    RUBY
  end

  it "split on whitespace keeps nul inside a word" do
    result = ze0(<<~'RUBY')
      # awk-style split breaks on space and \t through \r only: a NUL stays
      # inside its word, while strip takes NUL off the ends.
      p "a\0b".split(" "), "a\0 b".split(" "), " a\v b\fc\r\n".split(" ")
      p "\0a\0".strip, "\0 a".lstrip, "a \0".rstrip
      p "x y z".split(" ", 2), " x  y ".split(" ", 2), "  x y  ".split(" ", -1)
      p "one".split(" ", -1), " a b ".split(" ", 3), " a b ".split(" ", 4), "   ".split(" ", -1)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a\u0000b"]
      ["a\u0000", "b"]
      ["a", "b", "c"]
      "a"
      "a"
      "a"
      ["x", "y z"]
      ["x", "y "]
      ["x", "y", ""]
      ["one"]
      ["a", "b", ""]
      ["a", "b", ""]
      [""]
    OUT
  end

  it "str append accumulator" do
    result = ze0(<<~'RUBY')
      # An append accumulator -- a string local appended to inside a loop -- rides
      # the growable handle so each `<<` is amortized O(1) rather than a copy of the
      # whole accumulation. The representation change must be invisible: what these
      # pin is that the results, the aliasing, and the shapes that must NOT be
      # promoted all still behave.
      def build(n)
        out = +""
        i = 0
        while i < n
          out << "ab"
          i += 1
        end
        out
      end
      p build(5).length
      p build(5)

      # a block-form loop accumulates the same way, and the value survives the method
      def joined(list)
        s = +""
        list.each { |x| s << x.to_s }
        s
      end
      p joined([1, 2, 3])

      # read after the loop, several ways
      acc = +""
      3.times { |i| acc << i.to_s }
      p acc
      p acc.length
      p acc[1]
      p acc.upcase
      p acc == "012"
      p acc + "!"
      p [acc].first

      # a local READ inside the loop keeps its plain representation and its answers
      r = +""
      sizes = []
      4.times do |i|
        r << "x"
        sizes << r.length
      end
      p sizes
      p r

      # a param appended through a call stays byref: the caller sees the append
      def feed(buf)
        buf << "!"
      end
      b = +""
      2.times { feed(b) }
      p b

      # a captured local is shared storage, and both writers are visible
      w = +""
      f = proc { w << "c" }
      2.times { w << "a" }
      f.call
      p w

      # `<<` outside any loop is unchanged
      z = +""
      z << "one"
      z << "two"
      p z

      # an each_with_object memo is the iterator's slot, not ours
      p({ "a" => 1, "b" => 2 }.each_with_object(+"") { |(k, _v), a| a << k })
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      10
      "ababababab"
      "123"
      "012"
      3
      "1"
      "012"
      true
      "012!"
      "012"
      [1, 2, 3, 4]
      "xxxx"
      "!!"
      "aac"
      "onetwo"
      "ab"
    OUT
  end

  it "str array max min by" do
    result = ze0(<<~'RUBY')
      # Issue #863: max_by / min_by on String arrays return the element,
      # not the score (and not 0).
      puts ["hello", "hi", "goodbye"].max_by { |s| s.length }
      puts ["hello", "hi", "goodbye"].min_by { |s| s.length }
      # Negation flips the ordering.
      puts ["a", "bb", "ccc"].max_by { |s| -s.length }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      goodbye
      hi
      a
    OUT
  end

  it "str array min max" do
    result = ze0(<<~'RUBY')
      # Array#min / #max / #minmax (no block) on String arrays, by String#<=> (byte
      # comparison). Previously rejected for String arrays while Integer/Float arrays
      # worked. Receivers route through a per-kind identity method so the typed
      # runtime path is exercised rather than a compile-time fold.
      def sw(x); x; end
      def si(x); x; end
      def sf(x); x; end

      p sw(%w[banana apple cherry]).min
      p sw(%w[banana apple cherry]).max
      p sw(%w[banana apple cherry]).minmax
      # byte ordering: uppercase precedes lowercase; lexicographic, not numeric
      p sw(%w[Z a]).min
      p sw(%w[10 9 100]).max
      p sw(%w[b a a c]).min
      # single element
      p sw(["only"]).min
      p sw(["only"]).minmax

      # empty -> nil
      def empty; a = ["x"]; a.clear; a; end
      p empty.min
      p empty.max

      # Integer / Float arrays remain unaffected
      p si([3, 1, 2]).min
      p si([3, 1, 2]).max
      p si([3, 1, 2]).minmax
      p sf([3.0, 1.0, 2.0]).min
      p sf([3.0, 1.0, 2.0]).minmax
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "apple"
      "cherry"
      ["apple", "cherry"]
      "Z"
      "9"
      "a"
      "only"
      ["only", "only"]
      nil
      nil
      1
      3
      [1, 3]
      1.0
      [1.0, 3.0]
    OUT
  end

  it "str array sort by" do
    result = ze0(<<~'RUBY')
      # sort_by on str_array previously bombed at C compile time:
      # `cannot resolve call to 'sort_by' on str_array`, then the
      # pointer slot got assigned (mrb_int)0. Explicit block and the
      # `&:length` / `&:bytesize` / `&:to_i` symbol-to-proc shortcuts
      # are now handled.
      puts ["bb", "a", "ccc"].sort_by(&:length).inspect
      puts ["bb", "a", "ccc"].sort_by { |s| s.length }.inspect
      puts ["10", "1", "100"].sort_by(&:to_i).inspect
      puts ["zzz", "a", "bb"].sort_by { |s| s.length }.inspect
      # Equal-key elements keep their original order (bubble sort is stable).
      puts ["bb", "a", "cc"].sort_by(&:length).inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "bb", "ccc"]
      ["a", "bb", "ccc"]
      ["1", "10", "100"]
      ["a", "bb", "zzz"]
      ["a", "bb", "cc"]
    OUT
  end

  it "str array uniq" do
    result = ze0(<<~'RUBY')
      # Array#uniq (non-bang) on a str_array — returns a fresh array with
      # duplicates removed, first occurrence kept, order preserved. The
      # receiver stays a str_array. Routed through an identity method to
      # defeat constant folding and exercise the real typed runtime path.
      def as(x); x; end

      a = as(["a", "b", "a", "c", "b"])
      puts a.uniq.inspect
      puts a.inspect            # non-bang leaves the receiver untouched

      puts as(["x", "y", "z"]).uniq.inspect
      puts as([]).uniq.inspect

      # built via gsub (the widened-but-still-str_array path)
      u = "http://example.com/page#frag"
      urls = [u.gsub(/#.*/, "")]
      urls.push u.gsub(/#.*/, "")
      urls.push "http://other.test"
      puts urls.uniq.length
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b", "c"]
      ["a", "b", "a", "c", "b"]
      ["x", "y", "z"]
      []
      2
    OUT
  end

  it "str chomp paragraph mode" do
    result = ze0(<<~'RUBY')
      # String#chomp edge cases: no-arg strips ONE separator,
      # paragraph mode (chomp("")) strips trailing \r\n/\n sequences
      # but not standalone \r.

      # No-arg chomp: one separator
      puts "hello\r\n".chomp.inspect
      puts "hello\n".chomp.inspect
      puts "hello\r".chomp.inspect
      puts "hello\r\n\r\n".chomp.inspect
      puts "hello".chomp.inspect

      # Paragraph mode
      puts "hello\r\n".chomp("").inspect
      puts "hello\n".chomp("").inspect
      puts "hello\r".chomp("").inspect
      puts "hello\r\n\r\n".chomp("").inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello"
      "hello"
      "hello"
      "hello\r\n"
      "hello"
      "hello"
      "hello"
      "hello\r"
      "hello"
    OUT
  end

  it "str concat raise operand" do
    result = ze0(<<~'RUBY')
      # A String-returning method unresolved on a poly value, used as a String#+
      # operand, must raise NoMethodError at run time -- not fail C compilation with a
      # sp_RbVal-into-const-char* mismatch (#2457 Family 2).
      class Note
        def initialize(t); @created_at = t; end
        def created_at; @created_at; end
      end
      def show(note)
        "at " + note.created_at.strftime("%Y")
      end
      begin
        show(Note.new(nil))
        p :no_raise
      rescue NoMethodError
        p :raised
      end
      # the ordinary path still works
      p("a" + "b")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :raised
      "ab"
    OUT
  end

  it "str count multi arg" do
    result = ze0(<<~'RUBY')
      # String#count with multiple args computes intersection of charsets
      # Each additional arg further restricts which chars to count.

      # single arg
      puts "hello world".count("lo")
      # two args (intersection of "lo" and "o" = just "o")
      puts "hello world".count("lo", "o")
      # two args with no intersection
      puts "hello world".count("l", "o")
      # two args with negation
      puts "hello world".count("^l", "lo")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      2
      0
      2
    OUT
  end

  it "str delete count negation" do
    result = ze0(<<~'RUBY')
      # String#delete and String#count with ^-negated charset
      # ^ at the start inverts the charset meaning.

      # delete: normal charset
      puts "hello".delete("l").inspect
      # delete: negated charset
      puts "hello".delete("^l").inspect

      # count: normal charset
      puts "hello".count("l")
      # count: negated charset
      puts "hello".count("^l")

      # a lone "^" is the literal caret, not negation
      puts "a^b^c".delete("^").inspect
      puts "a^b^c".count("^")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "heo"
      "ll"
      2
      3
      "abc"
      2
    OUT
  end

  it "str int hash missing key nil" do
    result = ze0(<<~'RUBY')
      h = {"a" => 1, "b" => 2}
      # Missing-key reads are value-level nil (#801).
      p h["miss"]
      p h["miss"].nil?
      p h["miss"].inspect
      p(h["miss"] || 42)
      # Stored in a local, then observed (the case the consumption-site rewrites miss).
      v = h["miss"]
      p v.nil?
      p(v || 7)
      # Present keys are unaffected.
      p h["a"]
      p h["a"].nil?
      p(h["a"] + 1)
      w = h["b"]
      p(w + 10)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      nil
      true
      "nil"
      42
      true
      7
      1
      false
      2
      12
    OUT
  end

  it "str method nil arg no segv" do
    result = ze0(<<~'RUBY', path: "core/string/str_method_nil_arg_no_segv.rb")
      # #504. Several String methods receiving the wrong arg shape used
      # to SEGV. CRuby raises ArgumentError; spinel can't raise but we
      # should at least not crash. Codegen emits compile_arg0 -> "0"
      # (NULL) for missing args and the runtime helpers then ran
      # strlen(NULL) or worse.
      #
      # Fix: NULL guards in sp_str_count / sp_str_delete /
      # sp_str_rindex / sp_str_concat; setbyte (which would have
      # written through a read-only string literal) is now warned and
      # returns 0 without mutating; rindex with a regex arg routes
      # through the new sp_re_rindex helper instead of the plain
      # string-substring path; `<<` on a string return-types as
      # `string` instead of falling through to the catch-all `int`.

      # count / rindex / include? / start_with? / end_with? with no arg
      # (NULL at C level): spinel now raises TypeError, matching CRuby's
      # nil-arg path more closely than the old silent sentinel return.
      begin
        "foo".count
        puts "BUG count: no raise"
      rescue TypeError => e
        puts "count: #{e.message}"
      end
      p "foo".delete   # CRuby: ArgumentError. spinel: "foo" unchanged (was: SEGV)
      p "foo".rindex(/missing/)  # CRuby + spinel post-#532: nil. (was: -1)
      p "abcdabcd".rindex(/c/)   # CRuby & spinel: 6 (new sp_re_rindex helper)
      begin
        "foo".send(:<<)          # CRuby: ArgumentError. spinel: FrozenError (after #886)
        puts "no raise"
      rescue FrozenError => e
        puts "send-lshift: " + e.message
      end

      # setbyte on a literal: WITHOUT the frozen_string_literal magic comment a
      # literal is mutable (CRuby); the write copies the static bytes and rebinds
      # the variable (#2029). A frozen-string-literal file or an explicit .freeze
      # still raises (pinned by bundle_classd_43).
      (str = "a")
      begin
        str.setbyte(0, 98)
        puts "literal not frozen: " + str
      rescue FrozenError => e
        puts "frozen literal: " + e.message
      end
      str2 = "a".dup
      str2.setbyte(0, 98)
      puts str2  # "b" (heap, mutates)
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "core/string/str_method_nil_arg_no_segv.rb:19:in 'String#count': wrong number of arguments (given 0, expected 1+) (ArgumentError)\n\n    caller: core/string/str_method_nil_arg_no_segv.rb:19\n    |   \"foo\".count\n             ^^^^^^\n\tfrom core/string/str_method_nil_arg_no_segv.rb:19:in '<main>'\n"
    _(result.status).must_equal 1
  end

  it "str oct prefix" do
    result = ze0(<<~'RUBY')
      # String#oct with prefix auto-detection.
      # CRuby's oct handles 0x (hex), 0b (binary), 0o (explicit octal),
      # 0 (implicit octal), and bare digits (base 8). Previously spinel
      # used strtoll(base=8) unconditionally, so "0xff".oct returned 0
      # instead of 255.

      p "0xff".oct      # hex prefix: 255
      p "0b101".oct     # binary prefix: 5
      p "0o77".oct      # explicit octal: 63
      p "77".oct        # bare digits base-8: 63
      p "010".oct       # implicit octal: 8
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      255
      5
      63
      63
      8
    OUT
  end

  it "str ord empty" do
    result = ze0(<<~'RUBY')
      # String#ord on empty string should raise ArgumentError, not return 0.
      begin
        "".ord
        puts "BUG: no raise"
      rescue ArgumentError => e
        puts "ArgumentError: " + e.message
      end

      # Normal ord still works
      p "A".ord
      p "a".ord
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError: empty string
      65
      97
    OUT
  end

  it "str poly hash dup widen" do
    result = ze0(<<~'RUBY')
      # A local declared `sp_StrPolyHash *` (because later poly-value writes
      # force the wider variant) initialized from `<str_str_hash>.dup`
      # previously emitted a raw `lv = sp_StrStrHash_dup(...)` assignment.
      # The two structs have different `vals[]` element types
      # (`const char **` vs `sp_RbVal *`), so subsequent reads through the
      # widened slot returned garbage (0 / nil) even when -Werror was off.
      # The prior `.length`-only assertion happened to land at an offset
      # both structs share. Issue #614.

      class Match
        attr_reader :path_params
        def initialize(pp); @path_params = pp; end
      end

      m = Match.new({ "article_id" => "1", "format" => "html" })
      merged = m.path_params.dup
      merged["x"] = 1        # int value forces analyzer-side widening to str_poly_hash
      puts merged["article_id"]   # round-trips the original str value
      puts merged["format"]
      puts merged["x"]
      puts merged.length
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      html
      1
      3
    OUT
  end

  it "str poly hash dup widen from int" do
    result = ze0(<<~'RUBY')
      # Sibling case to str_poly_hash_dup_widen: the narrower-source variant
      # is `sp_StrIntHash *` (int values). The fix wraps the `.dup` call
      # with `sp_StrPolyHash_from_str_int_hash` so the slot's
      # `sp_RbVal` reads round-trip the original int as a boxed int.
      # Issue #614.

      class Counter
        attr_reader :counts
        def initialize(h); @counts = h; end
      end

      c = Counter.new({ "a" => 1, "b" => 2 })
      merged = c.counts.dup
      merged["x"] = "label"   # str value forces analyzer-side widening
      puts merged["a"]
      puts merged["b"]
      puts merged["x"]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      2
      label
    OUT
  end

  it "str rindex position" do
    result = ze0(<<~'RUBY')
      # String#rindex with position argument
      # The position limits the search to codepoint index <= pos.
      # Negative pos counts from end: effective = cl + pos.

      r = "hello".rindex("l", 2); puts r == nil ? "nil" : r
      r = "hello".rindex("l", 3); puts r == nil ? "nil" : r
      r = "hello".rindex("l"); puts r == nil ? "nil" : r
      r = "hello".rindex("h", 0); puts r == nil ? "nil" : r
      r = "hello".rindex("h", 1); puts r == nil ? "nil" : r
      r = "hello".rindex("x", 2); puts r == nil ? "nil" : r
      r = "hello".rindex("l", 10); puts r == nil ? "nil" : r
      # negative position
      r = "hello".rindex("l", -1); puts r == nil ? "nil" : r
      r = "hello".rindex("l", -2); puts r == nil ? "nil" : r
      r = "hello".rindex("l", -3); puts r == nil ? "nil" : r
      r = "hello".rindex("l", -4); puts r == nil ? "nil" : r
      r = "hello".rindex("l", -6); puts r == nil ? "nil" : r
      # empty substring
      r = "hello".rindex(""); puts r == nil ? "nil" : r
      r = "hello".rindex("", 3); puts r == nil ? "nil" : r
      r = "hello".rindex("", 10); puts r == nil ? "nil" : r
      r = "hello".rindex("", -1); puts r == nil ? "nil" : r
      r = "hello".rindex("", -6); puts r == nil ? "nil" : r
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      2
      3
      3
      0
      0
      nil
      3
      3
      3
      2
      nil
      nil
      5
      3
      5
      4
      nil
    OUT
  end

  it "str split space dynamic limit" do
    result = ze0(<<~'RUBY')
      # A single-space separator selects Ruby's whitespace mode even when the
      # separator is held in a variable or an explicit limit is supplied.
      sep = " "
      p " one two  three ".split(sep)
      p " one two  three ".split(sep, 0)
      p " one two  three ".split(sep, 1)
      p " one two  three ".split(sep, 2)
      p " one two  three ".split(sep, -1)
      p "   ".split(sep, 0)
      p "   ".split(sep, 2)
      p "   ".split(sep, -1)
      p "trail   ".split(sep, 3)

      out = []
      "  a   b c ".split(sep, 2) { |piece| out << piece }
      p out
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["one", "two", "three"]
      ["one", "two", "three"]
      [" one two  three "]
      ["one", "two  three "]
      ["one", "two", "three", ""]
      []
      [""]
      [""]
      ["trail", ""]
      ["a", "b c "]
    OUT
  end

  it "str split space whitespace" do
    result = ze0(<<~'RUBY')
      # String#split(" ") is whitespace-split mode (CRuby special case)
      # Strips leading whitespace, collapses consecutive whitespace.

      # split(" ") is whitespace mode
      puts "  hello  world  ".split(" ").inspect
      puts "a  b".split(" ").inspect
      # no-arg split is also whitespace mode
      puts "  hello  world  ".split.inspect
      # split(",") is literal mode (preserves empty fields)
      puts "a,,b".split(",").inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["hello", "world"]
      ["a", "b"]
      ["hello", "world"]
      ["a", "", "b"]
    OUT
  end

  it "str split trailing empty" do
    result = ze0(<<~'RUBY')
      # String#split without limit drops trailing empty strings
      # String#split(sep, -1) keeps them (CRuby default vs no-limit behavior).
      # String#split(sep, 0) is "no limit" and drops trailing empties too;
      # only a negative limit keeps them.

      puts "a,b,c,".split(",").inspect
      puts "a,b,c,,,".split(",").inspect
      puts "a,b,c".split(",").inspect
      puts "a,b,c,".split(",", -1).inspect
      puts "a,b,c,".split(",", 0).inspect
      puts "a,b,c,,".split(",", 0).inspect
      puts "a,b,c,".split(",", 2).inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b", "c", ""]
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b,c,"]
    OUT
  end

  it "str squeeze arg" do
    result = ze0(<<~'RUBY')
      # String#squeeze with charset argument
      # The argument restricts which characters get squeezed.
      # "a" squeezes only 'a', "^a" squeezes everything except 'a'.

      # no-arg squeeze (all consecutive)
      puts "aaabbbccc".squeeze.inspect
      # single char
      puts "aaabbbccc".squeeze("a").inspect
      # multiple chars
      puts "aaabbbccc".squeeze("ab").inspect
      # range
      puts "aaabbbccc".squeeze("a-c").inspect
      # negated set
      puts "aaabbbccc".squeeze("^a").inspect
      # no change case
      puts "abc".squeeze("a").inspect
      # a lone "^" is the literal caret, not a negation
      puts "aaa^^^bbb".squeeze("^").inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "abc"
      "abbbccc"
      "abccc"
      "abc"
      "aaabc"
      "abc"
      "aaa^bbb"
    OUT
  end

  it "str str hash nullable bracket assign" do
    result = ze0(<<~'RUBY')
      # Silent-elision regression: `<str_str_hash?>[k] = v` previously
      # fell through every arm of compile_bracket_assign with no emit, so
      # the assignment vanished. The two missing entry points were the
      # `str_str_hash` / `str_int_hash` base arms (mirror of the existing
      # `sym_*_hash` / `int_str_hash` arms), plus the nullable-pointer
      # strip at the top so `str_str_hash?` reaches the same emit.
      # Issue #610: roundhouse's `dispatch_request` builds a merged
      # str_str_hash from a path-params dup (typed str_str_hash? because
      # the source ivar is nullable) and then writes into it inside a
      # `.each` block; pre-fix the entire merge loop body disappeared.

      class HashHolder
        def initialize
          @h = nil
        end

        attr_accessor :h
      end

      def fill(holder)
        # Force the slot's static type to `str_str_hash?` by routing the
        # initial value through a method that returns the nullable shape.
        holder.h = path_params
        holder.h["c"] = "3"
        holder.h["d"] = "4"
      end

      def path_params
        { "a" => "1", "b" => "2" }
      end

      hh = HashHolder.new
      fill(hh)
      m = hh.h
      puts m["a"]   # 1
      puts m["b"]   # 2
      puts m["c"]   # 3
      puts m["d"]   # 4
      puts m.length # 4
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      2
      3
      4
      4
    OUT
  end

  it "str to i overflow" do
    result = ze0(<<~'RUBY')
      # String#to_i overflow handling. Pre-fix: undefined behavior on
      # int64 wrap (#743) — addressed by overflow-detected saturation.
      # Per #842 the saturate path is gone; overflow now raises
      # RangeError so a `rescue` can react instead of silently
      # returning INT64_MAX/MIN.

      # Below int64 limit: unchanged.
      puts "12345".to_i
      puts "-67890".to_i

      # At/over int64 max: raises RangeError.
      begin
        puts "99999999999999999999999999999".to_i
      rescue RangeError
        puts "raised"
      end

      begin
        puts "-99999999999999999999999999999".to_i
      rescue RangeError
        puts "raised"
      end

      # Exactly INT64_MAX: parses fine, no raise.
      puts "9_223_372_036_854_775_807".to_i

      # One past INT64_MAX: raises.
      begin
        puts "9_223_372_036_854_775_808".to_i
      rescue RangeError
        puts "raised"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      12345
      -67890
      99999999999999999999999999999
      -99999999999999999999999999999
      9223372036854775807
      9223372036854775808
    OUT
  end

  it "str tr negation" do
    result = ze0(<<~'RUBY')
      # String#tr / tr_s with ^-negation in from-set
      # ^ at the start of from-set inverts which chars get translated.

      # tr with ^-negation
      puts "abc".tr("^a", "x").inspect
      puts "hello".tr("^aeiou", ".").inspect
      # tr without negation (positional mapping)
      puts "hello".tr("el", "ip").inspect
      # tr_s with ^-negation
      puts "hello".tr_s("^aeiou", ".").inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "axx"
      ".e..o"
      "hippo"
      ".e.o"
    OUT
  end

  it "string alias accessor read" do
    result = ze0(<<~'RUBY')
      # A String reached through an ACCESSOR call is the same object the container
      # holds, exactly as one reached through `[]` is. The shared-mutable-string
      # analysis keyed only off `[]`, so the accessor route handed out a copy: the
      # index assignment had no `[]=` to call on it, and the in-place mutators
      # silently left the container alone (#4013).
      b = [+"xyz"]
      b.first[1] = "*"
      p b

      b = [+"xyz"]
      b.last[1] = "*"
      p b

      b = [+"xyz"]
      b.fetch(0)[1] = "*"
      p b

      b = [+"abc"]
      b.first.replace("zzz")
      p b

      b = [+"abc"]
      b.first << "Z"
      p b

      h = { k: +"abc" }
      h.dig(:k) << "Z"
      p h

      # bound to a local first, which is the same alias
      b = [+"abc"]
      a = b.first
      a << "Z"
      p b

      b = [+"abc"]
      a = b.last
      a.replace("zzz")
      p b

      # the COUNT forms answer a new Array and are untouched by any of this
      b = [+"abc", +"def"]
      p b.first(1)
      p b.last(2)

      # and the ordinary reads keep their values
      p [1, 2, 3].first
      p [1, 2, 3].last
      p [].first
      p [].last
      p({ a: 1 }.first)
      p (1..3).first
      p [1, 2, 3].send(:first)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["x*z"]
      ["x*z"]
      ["x*z"]
      ["zzz"]
      ["abcZ"]
      {k: "abcZ"}
      ["abcZ"]
      ["zzz"]
      ["abc"]
      ["abc", "def"]
      1
      3
      nil
      nil
      [:a, 1]
      1
      1
    OUT
  end

  it "string alias out of container" do
    result = ze0(<<~'RUBY')
      # Reading a mutable String out of a container into a local aliases the
      # element: an in-place mutation through the local must show in the container,
      # and `equal?` must answer true. The local used to hold a COPY (#3941).
      rows = [+"abc"]
      r = rows[0]
      r.upcase!
      p [rows, r, r.equal?(rows[0])]
      r << "Z"
      p rows
      r.sub!("A", "q")
      p rows
      r.replace("new")
      p rows

      h = { a: +"abc" }
      v = h[:a]
      v << "Z"
      p [h, v.equal?(h[:a])]
      v.upcase!
      p h

      n = { 1 => +"one" }
      w = n[1]
      w << "!"
      p n

      # unrelated: a copy is still a copy when nothing mutates
      plain = ["abc"]
      q = plain[0]
      p [q, plain]

      # a store then an alias

      store = {}
      store[:k] = +"v"
      sv = store[:k]
      sv << "2"
      p store
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [["ABC"], "ABC", true]
      ["ABCZ"]
      ["qBCZ"]
      ["new"]
      [{a: "abcZ"}, true]
      {a: "ABCZ"}
      {1 => "one!"}
      ["abc", ["abc"]]
      {k: "v2"}
    OUT
  end

  it "string and hash leaf methods" do
    result = ze0(<<~'RUBY')
      puts "hello world".gsub(/[aeiou]/, "a" => "1", "e" => "2", "o" => "3")
      p "hello".split("")
      p "hello world"[/(\w+) (\w+)/, 2]
      p "Hello".casecmp?("HELLO")
      p "0x1f".oct
      s = "hello"; s.slice!(1, 2); p s
      p({ b: 2, a: 1 }.sort)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      h2ll3 w3rld
      ["h", "e", "l", "l", "o"]
      "world"
      true
      31
      "hlo"
      [[:a, 1], [:b, 2]]
    OUT
  end

  it "string append grows in place" do
    result = ze0(<<~'RUBY')
      def fill(str, n)
        n.times { |i| str << "ab" << i.to_s }
        str
      end

      s = String.new
      fill(s, 5)
      p s
      p s.length

      # an ivar filled through a helper that takes it as a parameter
      class Doc
        def initialize
          @buf = String.new
        end

        def add(n)
          n.times { |i| append(@buf, i) }
        end

        def append(str, i)
          str << "<" << i.to_s << ">"
        end

        def buf
          @buf
        end
      end

      d = Doc.new
      d.add(4)
      p d.buf
      p d.buf.bytesize

      # a frozen receiver still raises
      f = "abc".freeze
      begin
        f << "d"
        p :no_raise
      rescue FrozenError => e
        p e.class
      end

      # the value read out before the append is not disturbed by a later grow
      a = String.new
      a << "one"
      b = a.dup
      a << "-two"
      p [a, b]

      # binary content survives
      bin = String.new
      bin << "x" << 0.chr << "y"
      p bin.bytes
      p bin.bytesize
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ab0ab1ab2ab3ab4"
      15
      "<0><1><2><3>"
      12
      FrozenError
      ["one-two", "one"]
      [120, 0, 121]
      3
    OUT
  end

  it "string arg conformance" do
    result = ze0(<<~'RUBY')
      # Five String surfaces that answered where CRuby refuses, or refused where
      # CRuby answers.

      # an empty pad is rejected whatever the width -- the no-op width case used to
      # return the receiver before looking at the pad
      r = ("hi".ljust(5, "") rescue $!.class); p r
      r = ("hi".rjust(5, "") rescue $!.class); p r
      r = ("hi".center(5, "") rescue $!.class); p r
      r = ("hi".ljust(1, "") rescue $!.class); p r
      p "hi".ljust(5, ".")
      p "hi".rjust(5, ".")
      p "hi".center(6, ".")

      # a radix outside 2..36 is an error, not a silent fallback to 10
      r = ("12".to_i(1) rescue $!.class); p r
      r = ("12".to_i(37) rescue $!.class); p r
      p "12".to_i(0)
      p "ff".to_i(16)
      p "12".to_i

      # both prefix predicates take any number of candidates, so none is false
      p "hello".start_with?
      p "hello".end_with?
      p "hello".start_with?("he")
      p "hello".end_with?("lo", "xx")

      # #b answers a fresh mutable copy, not the frozen receiver
      p "abc".b.frozen?
      s = "abc".b
      s << "d"
      p s

      # `str =~ str` is a TypeError, not a missing method
      r = ("hello" =~ "l" rescue $!.class); p r
      p("hello" =~ /l/)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      "hi..."
      "...hi"
      "..hi.."
      ArgumentError
      ArgumentError
      12
      255
      12
      false
      false
      true
      true
      false
      "abcd"
      TypeError
      2
    OUT
  end

  it "string array hash symbol proc leaf methods" do
    result = ze0(<<~'RUBY')
      p "hello".codepoints
      s = "hi\n"; p s.chomp!; p s.chomp!
      p "hello".partition("l")
      p "hello".rpartition("l")
      p "a.b.c".partition(/\./)
      p "TestName".delete_prefix("Test")
      p "file.rb".delete_suffix(".rb")
      c = +"x"; c.clear; p c
      p((+"y").frozen?)
      p [1, 2].repeated_permutation(2).to_a
      p [1, 2].repeated_combination(2).to_a
      p [1, 2, 3].intersect?([3, 4])
      p [1, 2].chain([3], [4]).to_a
      p({ a: 1, b: 2, c: 3 }.slice(:a, :c))
      p({ a: 1, b: 2 }.except(:a))
      p({ a: 1, b: 2 }.fetch_values(:a, :b))
      p({ a: 1, b: [2, 3] }.flatten)
      p :hello[1, 3]
      p :Hello.casecmp?(:hELLO)
      f = ->(x) { x + 1 }
      g = ->(x) { x * 2 }
      p((f >> g).call(3))
      p((f << g).call(3))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [104, 101, 108, 108, 111]
      "hi"
      nil
      ["he", "l", "lo"]
      ["hel", "l", "o"]
      ["a", ".", "b.c"]
      "Name"
      "file"
      ""
      false
      [[1, 1], [1, 2], [2, 1], [2, 2]]
      [[1, 1], [1, 2], [2, 2]]
      true
      [1, 2, 3, 4]
      {a: 1, c: 3}
      {b: 2}
      [1, 2]
      [:a, 1, :b, [2, 3]]
      "ell"
      true
      8
      7
    OUT
  end

  it "string array leaves" do
    result = ze0(<<~'RUBY')
      # A grab-bag of String / Hash leaf methods.

      # `gsub` with a Hash maps each match to its replacement (missing keys -> "").
      puts "hello world".gsub(/[aeiou]/, "a" => "1", "e" => "2", "o" => "3")   # h2ll1 w3rld

      # `split` with an empty separator yields characters; a single space splits on
      # whitespace runs; a limit caps the field count.
      p "hello".split("")                    # ["h", "e", "l", "l", "o"]
      p "a b  c   d".split(" ")              # ["a", "b", "c", "d"]
      p "a,b,c,d".split(",", 2)              # ["a", "b,c,d"]

      # Regexp indexing pulls out the whole match or a capture group.
      p "hello world foo"[/\w+/]             # "hello"
      p "hello world"[/(\w+) (\w+)/, 2]      # "world"

      # Case-insensitive comparison and radix parsing.
      p "Hello".casecmp("hello")             # 0
      p "Hello".casecmp?("HELLO")            # true
      p "0x1f".oct                           # 31
      p "777".oct                            # 511
      p "ff".hex                             # 255

      # `slice!` removes a span in place and returns it.
      s = "hello"
      p s.slice!(1, 2)                       # "el"
      p s                                    # "hlo"

      # `Hash#sort` orders the [key, value] pairs.
      p({ b: 2, a: 1, c: 3 }.sort)           # [[:a, 1], [:b, 2], [:c, 3]]

      # Numeric stepping, integer and float lanes.
      p 1.step(10, 3).to_a                   # [1, 4, 7, 10]
      p 1.0.step(2.0, 0.5).to_a              # [1.0, 1.5, 2.0]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      h2ll3 w3rld
      ["h", "e", "l", "l", "o"]
      ["a", "b", "c", "d"]
      ["a", "b,c,d"]
      "hello"
      "world"
      0
      true
      31
      511
      255
      "el"
      "hlo"
      [[:a, 1], [:b, 2], [:c, 3]]
      [1, 4, 7, 10]
      [1.0, 1.5, 2.0]
    OUT
  end

  it "string bang mutators" do
    result = ze0(<<~'RUBY')
      # In-place gsub!/sub!/tr!/delete!/slice! reassign the transformed value
      # (statement position; the nil-when-unchanged return is not modeled, like
      # the other bang methods).
      s = "hello"
      s.gsub!("l", "L")
      puts s
      t = "hello"
      t.sub!("l", "_")
      puts t
      u = "hello"
      u.tr!("el", "ip")
      puts u
      v = "hello"
      v.delete!("l")
      puts v
      w = "hello world"
      w.slice!(5, 6)
      puts w
      x = "hello"
      x.slice!("ll")
      puts x
      y = "hello"
      y.slice!(2, 99)
      puts y
      z = "hello"
      z.gsub!(/l+/, "L")
      puts z
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      heLLo
      he_lo
      hippo
      heo
      hello
      heo
      he
      heLo
    OUT
  end

  it "string bang mutators and sum chr" do
    result = ze0(<<~'RUBY')
      s = "abc"; p s.upcase!; p s; p s.upcase!
      t = "  hi  "; t.strip!; p t
      u = "hello"; u.reverse!; p u
      v = "a b c"; v.gsub!(" ", "-"); p v
      w = "az"; w.succ!; p w
      p "hello".sum
      p "hello".chr
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ABC"
      "ABC"
      nil
      "hi"
      "olleh"
      "a-b-c"
      "ba"
      532
      "h"
    OUT
  end

  it "string bang returns self" do
    result = ze0(<<~'RUBY')
      p (+"").reverse!
      p (+"").succ!
      p (+"").next!
      p (+"a").reverse!
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ""
      ""
      ""
      "a"
    OUT
  end

  it "string breadth matches the oracle" do
    result = ze0(<<~'RUBY')
      # The String Tier A surface: case/strip families, split shapes, chomp,
      # indexing forms, sub/gsub (String + block), tr/delete/squeeze/count,
      # lenient conversions, succ carry, padding, and `%` formatting.

      p "hello world".capitalize
      p "HeLLo".swapcase
      p "hello".upcase
      p "HELLO".downcase
      p "  hi  ".strip
      p "  hi".lstrip
      p "hi  ".rstrip
      p "hello".chars
      p "a,b,,c".split(",")
      p "a b  c".split
      p "hello".split("l")
      p "hello".chomp("lo")
      p "hello".chop
      p "abc" * 3
      p "abc".reverse
      p "hello".index("l")
      p "hello".rindex("l")
      p "hello".index("x")
      p "hello"[1]
      p "hello"[1, 3]
      p "hello"[1..3]
      p "hello".sub("l", "L")
      p "hello".gsub("l", "L")
      p "hello".gsub("l") { |m| m.upcase }
      p "hello".start_with?("he")
      p "hello".end_with?("lo", "x")
      p "hello".tr("el", "ip")
      p "hello".tr("a-y", "b-z")
      p "42abc".to_i
      p "abc".to_i
      p "ff".to_i(16)
      p "42.5xyz".to_f
      p "hello".to_sym
      p "az".succ
      p "zz".succ
      p "a\nb\nc".lines
      p "Hello %s, you are %d" % ["Bob", 42]
      p "%05.1f|%x|%o|%b|%e|%g|%%" % [3.14159, 255, 8, 5, 12345.678, 0.00001]
      p "hi".center(7, "*")
      p "hi".ljust(5, ".")
      p "hi".rjust(5, ".")
      p "hello".delete("l")
      p "aabbcc".squeeze
      p "aabbcc".squeeze("a")
      p "hello world".count("lo")
      s = "orig"
      s.replace("xyz")
      p s
      s << "!"
      p s
      s.prepend("ab")
      p s
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "Hello world"
      "hEllO"
      "HELLO"
      "hello"
      "hi"
      "hi"
      "hi"
      ["h", "e", "l", "l", "o"]
      ["a", "b", "", "c"]
      ["a", "b", "c"]
      ["he", "", "o"]
      "hel"
      "hell"
      "abcabcabc"
      "cba"
      2
      3
      nil
      "e"
      "ell"
      "ell"
      "heLlo"
      "heLLo"
      "heLLo"
      true
      true
      "hippo"
      "ifmmp"
      42
      0
      255
      42.5
      :hello
      "ba"
      "aaa"
      ["a\n", "b\n", "c"]
      "Hello Bob, you are 42"
      "003.1|ff|10|101|1.234568e+04|1e-05|%"
      "**hi***"
      "hi..."
      "...hi"
      "heo"
      "abc"
      "abbcc"
      5
      "xyz"
      "xyz!"
      "abxyz!"
    OUT
  end

  it "string case delete affix" do
    result = ze0(<<~'RUBY')
      # String#swapcase, #delete_prefix, and #delete_suffix return new strings. Each
      # has a runtime helper already; this exercises the typed-String dispatch arms and
      # the inferred String return type (so the results chain and print). Receivers go
      # through a method param to defeat constant-folding.
      def ss(x); x; end

      # swapcase flips the case of each letter, leaving non-letters alone
      p ss("Hello World").swapcase
      p ss("aBcDeF 123").swapcase
      p ss("").swapcase

      # delete_prefix / delete_suffix remove a leading/trailing match, else unchanged
      p ss("hello").delete_prefix("he")
      p ss("hello").delete_prefix("xx")
      p ss("hello").delete_suffix("lo")
      p ss("hello").delete_suffix("xx")

      # they return Strings, so results chain
      p ss("hello").delete_prefix("he").delete_suffix("lo")
      p ss("Hello").swapcase.delete_prefix("h")

      # a non-literal argument works too
      affix = ss("foo")
      p ss("foobar").delete_prefix(affix)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hELLO wORLD"
      "AbCdEf 123"
      ""
      "llo"
      "hello"
      "hel"
      "hello"
      "l"
      "ELLO"
      "bar"
    OUT
  end

  it "string casecmp" do
    result = ze0(<<~'RUBY')
      # String#casecmp returns -1 / 0 / 1 for case-insensitive lex compare.
      # String#casecmp? returns true / false.
      puts "ABC".casecmp("abc")
      puts "ABC".casecmp("abd")
      puts "abc".casecmp("ABB")
      puts "ABC".casecmp?("abc")
      puts "ABC".casecmp?("abd")
      puts "".casecmp("")
      puts "a".casecmp("aa")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0
      -1
      1
      true
      false
      0
      -1
    OUT
  end

  it "string charset escape" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A character-set escape in a String method argument is not expanded, so
      # the range collapses.
      #
      # A backslash in a tr/count/delete/squeeze character set escapes the next
      # character, so "a\\-b" holds the three members a, - and b rather than the
      # range a..b. The set parser had no escape at all.
      p "a-b".tr("a\\-b", "*")
      p "a-b".count("a\\-b")
      p "a-b".delete("a\\-b")
      p "abc".tr("a-c", "x")
      p "a-b".tr("-", "_")
      p "a\\b".count("\\\\")
      p "abc".count("a-c")
      p "hello".delete("l")
      p "hello".squeeze("l")
      p "hello".tr("el", "ip")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "***"
      3
      ""
      "xxx"
      "a_b"
      1
      3
      "heo"
      "helo"
      "hippo"
    OUT
  end

  it "string charset range notation" do
    result = ze0(<<~'RUBY')
      # Issue #858: `a-z` range notation inside the charset string
      # argument of String#delete / #tr / #tr_s / #count expands to
      # the codepoint range. Previously the range syntax was treated
      # as three literal characters (a, -, z).
      puts "hello world".delete("a-z").inspect
      puts "abc123".tr("a-z", "X").inspect
      puts "Hello World".count("a-z")
      puts "AaBbCc".count("a-zA-Z")
      puts "abc-def".delete("a-c").inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      " "
      "XXX123"
      8
      6
      "-def"
    OUT
  end

  it "string chomp bang mutates" do
    result = ze0(<<~'RUBY')
      # Issue #859: String#chomp! on a mutable_str mutates in place.
      # Pre-fix, chomp! was a no-op (recursed into chomp which produces
      # a new string but doesn't write back to the receiver).
      # Frozen string literals raise FrozenError per #886.
      s = String.new("hello\n")
      s.chomp!
      puts s.to_s

      s2 = String.new("hi\r\n")
      s2.chomp!
      puts s2.to_s

      # upcase! / downcase! / strip! / lstrip! / rstrip! also mutate.
      u = String.new("abc")
      u.upcase!
      puts u.to_s

      t = String.new("  spaces  ")
      t.strip!
      puts t.to_s
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello
      hi
      ABC
      spaces
    OUT
  end

  it "string clamp ranges" do
    result = ze0(<<~'RUBY')
      p("z".clamp(.."c"))
      p("a".clamp("b"..))
      r001 = ("b".clamp("a"..."c") rescue $!.class); p r001
      r002 = ("b".clamp("c", "a") rescue $!.class); p r002
      p("b".clamp("a", "c"))
      p("z".clamp("b", "d"))
      p("b".clamp("a".."c"))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "c"
      "b"
      ArgumentError
      ArgumentError
      "b"
      "d"
      "b"
    OUT
  end

  it "string clone frozen" do
    result = ze0(<<~'RUBY')
      # String#clone preserves the frozen state; String#dup always returns unfrozen.
      def id(x) = x

      # clone keeps frozen, dup clears it
      p id("x").freeze.clone.frozen?     # true
      p id("x").freeze.dup.frozen?       # false
      # unfrozen original: both stay unfrozen
      p id("abc").clone.frozen?          # false
      p id("abc").dup.frozen?            # false
      # value is preserved across clone
      p id("hi").freeze.clone            # "hi"
      # through a local variable
      s = "y".freeze
      c = s.clone
      p c.frozen?                        # true
      p c                                # "y"
      d = s.dup
      p d.frozen?                        # false
      # a frozen clone still raises on mutation
      begin
        c << "z"
      rescue FrozenError => e
        p e.class                        # FrozenError
      end
      # literal receiver
      p "lit".freeze.clone.frozen?       # true
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      false
      false
      "hi"
      true
      "y"
      false
      FrozenError
      true
    OUT
  end

  it "string concat is variadic" do
    result = ze0(<<~'RUBY')
      s = "a"
      s.concat("b", "c", "d")
      puts s
      t = "x"
      t << "y" << "z"
      puts t
      u = "n"
      u.concat(65, 66)
      puts u
      puts "keep".concat
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      abcd
      xyz
      nAB
      keep
    OUT
  end

  it "string concat variadic" do
    result = ze0(<<~'RUBY')
      # String#concat accepts any number of arguments (appended left to right);
      # `<<` is the single-argument operator spelling.
      s = "a"
      s.concat("b", "c", "d")
      puts s

      t = "greet"
      t << "-" << "world"
      puts t

      # Integer arguments append the corresponding codepoint's character.
      u = "n"
      u.concat(0x61, 0x62)
      puts u

      # No arguments is a no-op that returns the receiver.
      puts "unchanged".concat

      # Mixed string and codepoint arguments.
      v = "x"
      v.concat("y", 0x7A, "!")
      puts v
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      abcd
      greet-world
      nab
      unchanged
      xyz!
    OUT
  end

  it "string conformance batch" do
    result = ze0(<<~'RUBY')
      # String conformance: to_f underscores, -@ frozen, clear as a value,
      # byteslice OOB->nil / boundary / Range, === with a non-String arg.
      p "1_000.5".to_f
      p "3.14".to_f
      p "abc".to_f
      p "x".-@.frozen?
      s = "abc"; v = s.clear; p v; p s
      p "abc".byteslice(5)
      p "abc".byteslice(3)
      p "abc".byteslice(2)
      p "abc".byteslice(3, 0)
      p "hello".byteslice(1..3)
      p "hello".byteslice(2..)
      p "hello".byteslice(10..12)
      p("abc" === nil)
      p("abc" === "abc")
      p("abc" === "xyz")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1000.5
      3.14
      0.0
      true
      ""
      ""
      nil
      nil
      "c"
      ""
      "ell"
      "llo"
      nil
      false
      true
      false
    OUT
  end

  it "string conformance batch3" do
    result = ze0(<<~'RUBY')
      # String#+ non-String -> TypeError; concat no-args -> self; match non-match
      # .class -> NilClass; frozen in-place bang -> FrozenError.
      p("ab".concat)
      begin; "a" + 1; rescue TypeError => e; puts e.message; end
      begin; "a" + nil; rescue TypeError => e; puts e.message; end
      begin; "a" + true; rescue TypeError => e; puts e.message; end
      p("a" + "b")
      p("hi".match(/z/).class)
      p("hi".match(/h/).class)
      s = "hi".freeze
      begin; s.upcase!; rescue FrozenError => e; puts "upcase!:#{e.class}"; end
      begin; s.sub!("h", "x"); rescue FrozenError => e; puts "sub!:#{e.class}"; end
      p s
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ab"
      no implicit conversion of Integer into String
      no implicit conversion of nil into String
      no implicit conversion of true into String
      "ab"
      NilClass
      MatchData
      upcase!:FrozenError
      sub!:FrozenError
      "hi"
    OUT
  end

  it "string conformance batch4" do
    result = ze0(<<~'RUBY')
      # String conformance (KieranP #2308,#2310,#2312,#2313)
      p("hello".match?("l"))              # #2310 match? String pattern
      p("hello".match?("z"))
      p("hello".match("l").class)
      p("hello".match("z").class)
      p("a".gsub("a", "\\\\").bytes)      # #2312 doubled backslash collapse
      p("ab".gsub("a", "[\\&]"))
      p("a.b".sub(".", "\\\\"))
      p("\x02".inspect)                   # #2313 control byte -> \uNNNN
      p("\e".inspect)
      p("\a\b\t\n\v\f\r".inspect)
      p("\x00\x1c\x7f".inspect)
      begin                                # #2308 negative codepoint RangeError
        s = "a"; s << -1
        p :no_error
      rescue RangeError => e
        p e.class
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      false
      MatchData
      NilClass
      [92]
      "[a]b"
      "a\\b"
      "\"\\u0002\""
      "\"\\e\""
      "\"\\a\\b\\t\\n\\v\\f\\r\""
      "\"\\u0000\\u001C\\u007F\""
      RangeError
    OUT
  end

  it "string conformance batch6" do
    result = ze0(<<~'RUBY')
      # String conformance (KieranP #2369, #2370)
      a = "abc".freeze
      p((-a).equal?(a))              # #2369 frozen receiver: -@ is identity
      s0 = "x" + "y"
      f = -s0
      p f.frozen?
      p((-("a" + "b")).equal?("a" + "b"))
      s = "hi"
      p(s[0] = "Y")                  # #2370 []= consumed as a value
      p s
      t = "hi"
      v = (t[0] = "Y")
      p v
      p t
      u = "hi"
      p(u[0, 2] = "AB")
      p u
      w = "abc"
      p(w["bc"] = "XY")
      p w
      x = "abcd"
      p(x[1..2] = "Z")
      p x
      p("abc".clear)                 # #2370 clear on a literal receiver
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      false
      "Y"
      "Yi"
      "Y"
      "Yi"
      "AB"
      "AB"
      "XY"
      "aXY"
      "Z"
      "aZd"
      ""
    OUT
  end

  it "string conformance wave2" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A String transform drops replacement characters ruby emits.
      #
      # Three more String surfaces from the conformance wave.

      # A Hash replacement in sub/gsub looks the match up with #[], so a miss takes
      # the hash's DEFAULT. The miss was hard-coded to the empty string.
      h = Hash.new("?")
      h["e"] = "3"
      p "hello".gsub(/[el]/, h)
      p "hello".sub(/[el]/, h)

      plain = { "e" => "3" }
      p "hello".gsub(/[el]/, plain)

      # `s[range] = v` with a beginless or endless bound: the sentinel was folded
      # through the negative-index fixup into a wild offset (RangeError)
      z = +"hello"
      z[..1] = "HE"
      p z

      y = +"hello"
      y[2..] = "LLO!"
      p y

      w = +"hello"
      w[1..2] = "X"
      p w

      v = +"hello"
      v[..-4] = "AB"
      p v

      u = +"hello"
      u[...2] = "Q"
      p u

      # split with a block iterates and answers the receiver, not the split array
      p("hello".split(",") { |piece| piece })
      out = []
      r = "a-b-c".split("-") { |piece| out << piece }
      p out
      p r
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "h3??o"
      "h3llo"
      "h3o"
      "HEllo"
      "heLLO!"
      "hXlo"
      "ABllo"
      "Qllo"
      "hello"
      ["a", "b", "c"]
      "a-b-c"
    OUT
  end

  it "string crypt" do
    result = ze0(<<~'RUBY')
      # String#crypt — real libc crypt(3) (traditional DES), matching MRI:
      # 13-char output whose first 2 chars are the salt.

      r = "hello".crypt("ab")
      puts r
      puts r.length
      puts r[0, 2]

      # Determinism: same inputs → identical output.
      puts "hello".crypt("ab") == "hello".crypt("ab")

      # Different password → different hash, same salt prefix.
      a = "hello".crypt("ab")
      b = "world".crypt("ab")
      puts b
      puts a[0, 2] == b[0, 2]   # same salt
      puts a == b                # different hash

      # A salt shorter than 2 characters is an ArgumentError.
      begin
        "x".crypt("z")
      rescue ArgumentError => e
        puts "salt too short"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      abl0JrMf6tlhw
      13
      ab
      true
      abMGUTItM1t0k
      true
      false
      salt too short
    OUT
  end

  it "string dedup frozen self" do
    result = ze0(<<~'RUBY')
      # String#-@ on an already-frozen string returns the receiver itself (#2630).
      a = "abc".freeze
      p((-a).equal?(a))
      c = -"xyz"
      p((-c).equal?(c))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
    OUT
  end

  it "string dedup intern" do
    result = ze0(<<~'RUBY')
      # String#-@ / #dedup interns by content: two dedups of equal contents return
      # the same immortal frozen object (#2462).
      p("hello".dedup.equal?("hello".dedup))
      p((-"world").equal?(-"world"))
      p(("he" + "llo").dedup.equal?("hello".dedup))   # computed string interns too
      p("".dedup.equal?("".dedup))
      p((-"a").equal?(-"b"))                            # different contents differ
      p("frozen".dedup.frozen?)
      p(-"frozen")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      true
      false
      true
      "frozen"
    OUT
  end

  it "string delete prefix suffix bang" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true
      # String#delete_prefix! / delete_suffix! on a mutable_str mutate in
      # place and return the receiver. On a frozen string literal they
      # raise FrozenError, consistent with chomp! / upcase! et al.
      s = String.new("hello")
      s.delete_prefix!("hel")
      puts s.to_s

      s2 = String.new("hello")
      s2.delete_suffix!("llo")
      puts s2.to_s

      # Non-matching prefix/suffix leaves the string unchanged.
      s3 = String.new("hello")
      s3.delete_prefix!("xyz")
      puts s3.to_s

      # Frozen string literals raise FrozenError.
      begin
        "hello".delete_prefix!("hel")
        puts "BUG: delete_prefix! no raise"
      rescue FrozenError => e
        puts "delete_prefix!: " + e.message
      end
      begin
        "hello".delete_suffix!("llo")
        puts "BUG: delete_suffix! no raise"
      rescue FrozenError => e
        puts "delete_suffix!: " + e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      lo
      he
      hello
      delete_prefix!: can't modify frozen String: "hello"
      delete_suffix!: can't modify frozen String: "hello"
    OUT
  end

  it "string dump undump" do
    result = ze0(<<~'RUBY')
      # String#dump: a re-parseable literal; String#undump: its inverse.

      # Named control escapes and quoting.
      puts "hello".dump
      puts "tab\tnewline\nreturn\r".dump
      puts "bell\a back\b form\f vtab\v esc\e".dump
      puts "quote\"q back\\slash".dump

      # A NUL and other non-named control bytes become \xNN (uppercase).
      puts "null\0byte".dump
      puts "\x01\x02\x1f ctrl \x7f".dump

      # '#' is escaped only before an interpolation sigil.
      puts ("hash#" + "{x}").dump
      puts ("hash#" + "$g").dump
      puts ("hash#" + "@v").dump
      puts "hash#plain".dump

      # UTF-8 non-ASCII uses \u escapes (BMP as \uXXXX, astral as \u{...}).
      puts "café".dump
      puts "emoji😀".dump

      # A binary string uses \xNN for high bytes and keeps its encoding.
      puts "\xC3\xA9".b.dump

      # undump is the exact inverse.
      p "café".dump.undump
      p "café".dump.undump == "café"
      p "\x01\x02\x1f\x7f ctrl".dump.undump.bytes
      p "emoji😀".dump.undump
      p "\xC3\xA9".b.dump.undump == "\xC3\xA9".b

      # undump rejects malformed input.
      begin
        "not a dump".undump
      rescue RuntimeError => e
        puts "raised: #{e.message}"
      end
      begin
        "café".undump
      rescue RuntimeError => e
        puts "raised: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello"
      "tab\tnewline\nreturn\r"
      "bell\a back\b form\f vtab\v esc\e"
      "quote\"q back\\slash"
      "null\x00byte"
      "\x01\x02\x1F ctrl \x7F"
      "hash\#{x}"
      "hash\#$g"
      "hash\#@v"
      "hash#plain"
      "caf\u00E9"
      "emoji\u{1F600}"
      "\xC3\xA9"
      "café"
      true
      [1, 2, 31, 127, 32, 99, 116, 114, 108]
      "emoji😀"
      true
      raised: invalid dumped string; not wrapped with '"' nor '"...".force_encoding("...")' form
      raised: non-ASCII character detected
    OUT
  end

  it "string each char returns self" do
    result = ze0(<<~'RUBY')
      # Issue #866: String#each_char with a block returns the receiver
      # (not nil and not 0).
      s = "hello".each_char {}
      puts s

      # Inside the block, characters are yielded.
      out = []
      "abc".each_char { |c| out.push(c) }
      puts out.inspect

      # Multi-byte UTF-8 chars are yielded as whole code points.
      mb_chars = []
      "héllo".each_char { |c| mb_chars.push(c) }
      puts mb_chars.length
      puts mb_chars.inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello
      ["a", "b", "c"]
      5
      ["h", "é", "l", "l", "o"]
    OUT
  end

  it "string each line enum" do
    result = ze0(<<~'RUBY')
      # Blockless String#each_line returns an Enumerator over the lines, mirroring the
      # blockless each_char enumerator.
      p "a\nb\nc".each_line.to_a
      p "a\nb\nc".each_line.first(2)
      p "".each_line.to_a
      p "nonewline".each_line.to_a
      p "x\ny\nz".each_line.take(2)
      e = "x\ny".each_line
      p e.next
      p e.next
      # each_line with a block still iterates and returns self (unchanged)
      buf = []
      "p\nq".each_line { |l| buf << l }
      p buf
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a\n", "b\n", "c"]
      ["a\n", "b\n"]
      []
      ["nonewline"]
      ["x\n", "y\n"]
      "x\n"
      "y"
      ["p\n", "q"]
    OUT
  end

  it "string each line expr" do
    result = ze0(<<~'RUBY')
      # String#each_line with a block returns the receiver (self), per CRuby.
      # The statement form already worked; the expression form (capturing the
      # return value) failed to resolve -- each_line was missing from the
      # string-block-method-returns-self arm that each_char / each_byte use.

      s = "a\nb\nc"

      # Expression form: capture the return and confirm it is the string back
      r = s.each_line { |line| puts line.inspect }
      puts r.class
      puts r            # the whole string, unchanged
      puts r.length
      puts (r == s)

      # Works after a conditional assignment (the issue's described trigger)
      x = (1 > 0) ? "p\nq\nr" : "z"
      r2 = x.each_line { |l| puts l.inspect }
      puts r2.class

      # chomp: keyword, expression form
      r3 = "1\n2\n3\n".each_line(chomp: true) { |l| puts l }
      puts r3.length

      # Statement form still works
      "x\ny".each_line { |l| puts l.inspect }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "a\n"
      "b\n"
      "c"
      String
      a
      b
      c
      5
      true
      "p\n"
      "q\n"
      "r"
      String
      1
      2
      3
      6
      "x\n"
      "y"
    OUT
  end

  it "string each line keeps newline" do
    result = ze0(<<~'RUBY')
      # String#each_line yields each line WITH its trailing newline
      # (CRuby behaviour). Last line keeps no newline only when the
      # source itself didn't end with one.
      "hello\nworld".each_line { |line| puts line.inspect }

      # Source with trailing newline — last yielded line includes it.
      "a\nb\n".each_line { |line| puts line.inspect }

      # Single line, no newline.
      "only".each_line { |line| puts line.inspect }

      # Empty input — block never fires.
      out = []
      "".each_line { |line| out.push(line) }
      puts out.length
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello\n"
      "world"
      "a\n"
      "b\n"
      "only"
      0
    OUT
  end

  it "string each line separator" do
    result = ze0(<<~'RUBY')
      z001 = []; "1-2-3".each_line("-") { |l001| z001 << l001 }; p z001
      p("1-2-3".each_line("-").to_a)
      z2 = []; "a\nb\n".each_line { |l| z2 << l }; p z2
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["1-", "2-", "3"]
      ["1-", "2-", "3"]
      ["a\n", "b\n"]
    OUT
  end

  it "string each with index chain" do
    result = ze0(<<~'RUBY')
      Line = Struct.new(:number, :label)
      lines = []
      "a\nb\n".each_line.with_index do |raw, number|
        lines << Line.new(number, raw.to_s)
      end
      p lines.map(&:number)
      p Line.new(99, "x").number

      "a\nb\n".each_line.with_index { |l, i| p [l, i] }
      "ab".each_byte.with_index { |b, i| p [b, i] }
      "ab".each_char.with_index { |ch, i| p [ch, i] }
      "a\nb\n".each_line.with_index(10) { |l, i| p [l, i] }
      "a|b".each_line("|").with_index { |l, i| p [l, i] }
      p("a\nb\n".each_line.with_index.to_a)
      p("ab".each_byte.with_index.map { |b, i| b + i })

      "a\nb\n".each_line.with_index do |raw, number|
        p number.class
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [0, 1]
      99
      ["a\n", 0]
      ["b\n", 1]
      [97, 0]
      [98, 1]
      ["a", 0]
      ["b", 1]
      ["a\n", 10]
      ["b\n", 11]
      ["a|", 0]
      ["b", 1]
      [["a\n", 0], ["b\n", 1]]
      [97, 99]
      Integer
      Integer
    OUT
  end

  it "string embedded nul compare" do
    result = ze0(<<~'RUBY')
      # A NUL is an ordinary byte in a Ruby String, and the representation records
      # the real length -- but comparison went through strcmp, which stops at the
      # first one. Two strings differing only after a NUL compared equal, so they
      # also sorted equal, deduplicated into one, and collapsed as Hash keys. #3471,
      # #3472.
      s = "a\0b"
      t = "a\0c"
      p(s == t)
      p(s.casecmp(t))
      p(s.casecmp?(t))
      p([t, s].sort.map(&:bytes))
      p([s, t].max.bytes)
      p([s, t].min.bytes)
      p([s, t].uniq.size)
      p([s, t].count(t))
      p([s, t].index(t))
      p([s, t].include?(t))
      p(([s, t] - [s]).map(&:bytes))
      p(([s, t] & [t]).map(&:bytes))
      p(([s] | [t]).map(&:bytes))
      p([s, t].group_by { |x| x }.size)
      p({ s => 1, t => 2 }.size)
      # The comparison operators themselves went through strcmp too, so `<=>` said 0
      # where `==` said false, and the relational four ordered by the shared prefix.
      p(s <=> t)
      p(s < t)
      p(s > t)
      p(s <= t)
      p(s >= t)
      p(s.between?("a\0a", "a\0d"))
      p(s.clamp("a\0c", "a\0d").bytes)
      p((s.."a\0d").include?(t))
      u = "a" + 0.chr + "b"
      p(u <=> "a\0c")
      p(u < "a\0c")
      case t
      when s.."a\0d" then puts "in"
      else puts "out"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      -1
      false
      [[97, 0, 98], [97, 0, 99]]
      [97, 0, 99]
      [97, 0, 98]
      2
      1
      1
      true
      [[97, 0, 99]]
      [[97, 0, 99]]
      [[97, 0, 98], [97, 0, 99]]
      2
      2
      -1
      true
      false
      true
      false
      true
      [97, 0, 99]
      true
      -1
      true
      in
    OUT
  end

  it "string embedded nul core" do
    result = ze0(<<~'RUBY')
      s = "a\0b"
      puts s.length
      puts s.bytes.inspect
      puts (s == "a\0b")
      puts (s == "a\0c")
      puts (s == "a")
      h = {}
      h[s] = 1
      h["a\0c"] = 2
      h["a"] = 3
      puts h.size
      d = s.dup
      puts d.bytes.inspect
      puts (d == s)
      t = "x" + 0.chr + "y"
      e = t[0, 3]
      puts e.bytes.inspect
      puts e.length
      puts s[2]
      f = "/tmp/spinel_nul_core_t.bin"
      File.write(f, s)
      r = File.read(f)
      puts r.bytes.inspect
      puts (r == s)
      File.delete(f)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      [97, 0, 98]
      true
      false
      false
      3
      [97, 0, 98]
      true
      [120, 0, 121]
      3
      b
      [97, 0, 98]
      true
    OUT
  end

  it "string embedded nul ops" do
    result = ze0(<<~'RUBY')
      # An embedded NUL is a byte of the string: the representation has always
      # carried it (the header records the true byte length), but an operation that
      # reached for strlen or strstr stopped at it and silently truncated. The policy
      # is opportunistic -- fix what is met -- and this is what a sweep of the common
      # String surface met.
      s = "a\0b"
      p s.bytesize
      p s.size
      p s == "a\0b"
      p s == "a"
      p s.bytes

      p s.upcase.bytesize
      p s.downcase.bytes
      p s.reverse.bytes

      p s.sub("\0", "-")
      p s.sub("a", "X")
      p s.gsub("\0", "-")
      p s.gsub("a", "X")
      p "abcabc".gsub("b", "-")
      p "abc".gsub("", "-")

      p s.split("\0").map(&:bytesize)
      p s.split("").map(&:bytesize)
      p "a\0b\0c".split("\0").size
      p "a,b,c".split(",")

      p [s].join.bytesize
      p [s, s].join("\0").bytesize
      p [1, 2].join("\0").bytesize
      p ["x", "y"].join("-")

      p s.tr("\0", "-")
      p s.delete("\0").bytesize
      p s.count("\0")
      p "a\0\0b".squeeze("\0").bytesize
      p "aabb".squeeze
      p "abc".tr("b", "-")

      p s.chomp.bytesize
      p s.chop.bytesize
      p s.swapcase.bytesize
      p s.capitalize.bytesize
      p s.succ.bytesize
      p "az".succ
      p "zz".succ
      p "abc\n".chomp

      p s.partition("\0").map(&:bytesize)
      p s.rpartition("\0").map(&:bytesize)
      p "a-b-c".partition("-")
      p "a-b-c".rpartition("-")

      p s.dump
      p s.dump.undump.bytesize
      p("\0" "1").bytesize
      p("x" "\0" "y").bytesize

      # and the operations that already carried it
      p s.b.bytesize
      p s.dup.bytesize
      p (+s).bytesize
      p ("a\0b" + "c\0d").bytesize
      p (s * 2).bytesize
      p s.include?("\0")
      p s.index("b")
      p s.start_with?("a\0")
      p s.end_with?("\0b")
      p s.hash == "a\0b".hash
      p({ s => 1 }[s])
      p s.inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      3
      true
      false
      [97, 0, 98]
      3
      [97, 0, 98]
      [98, 0, 97]
      "a-b"
      "X\u0000b"
      "a-b"
      "X\u0000b"
      "a-ca-c"
      "-a-b-c-"
      [1, 1]
      [1, 1, 1]
      3
      ["a", "b", "c"]
      3
      7
      3
      "x-y"
      "a-b"
      2
      1
      3
      "ab"
      "a-c"
      3
      2
      3
      3
      3
      "ba"
      "aaa"
      "abc"
      [1, 1, 1]
      [1, 1, 1]
      ["a", "-", "b-c"]
      ["a-b", "-", "c"]
      "\"a\\x00b\""
      3
      "\u00001"
      "x\u0000y"
      3
      3
      3
      6
      6
      true
      2
      true
      true
      true
      1
      "\"a\\u0000b\""
    OUT
  end

  it "string embedded nul transform" do
    result = ze0(<<~'RUBY')
      # A NUL is an ordinary byte in a Ruby String, but repeat, unary plus, the
      # justify family and the character walk all sized themselves with strlen and
      # so dropped the NUL and everything after it. #3473.
      s = "a\0b"
      p((s * 2).bytes)
      p((+s).bytes)
      p(s.center(7, "-").bytes)
      p(s.ljust(6, "-").bytes)
      p(s.rjust(6, "-").bytes)
      p(s.center(7).bytes)
      p(s.ljust(6).bytes)
      p(s.rjust(6).bytes)
      p(s.chars.map(&:bytes))
      p(s.each_char.to_a.map(&:bytes))
      n = 0
      s.each_char { |ch| n += 1 }
      p n
      u = 0.chr * 3
      p(u.bytes)
      p(u.length)
      p(("" + 0.chr).ljust(3, "x").bytes)
      # the copy unary plus hands back is mutable, and keeps the NUL through an append
      c = +s
      c << "z"
      p(c.bytes)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [97, 0, 98, 97, 0, 98]
      [97, 0, 98]
      [45, 45, 97, 0, 98, 45, 45]
      [97, 0, 98, 45, 45, 45]
      [45, 45, 45, 97, 0, 98]
      [32, 32, 97, 0, 98, 32, 32]
      [97, 0, 98, 32, 32, 32]
      [32, 32, 32, 97, 0, 98]
      [[97], [0], [98]]
      [[97], [0], [98]]
      3
      [0, 0, 0]
      3
      [0, 120, 120]
      [97, 0, 98, 122]
    OUT
  end

  it "string enum arg forms" do
    result = ze0(<<~'RUBY')
      # Blockless String#gsub(/re/) is an Enumerator over the matches, and
      # each_line(sep) / lines(sep) split on an arbitrary separator (kept on
      # each segment) like CRuby.
      p "aaa".gsub(/a/).to_a
      p "a1b2".gsub(/\d/).to_a
      p "1-2-3".each_line("-").to_a
      p "1-2-3".lines("-")
      e = "x,y".each_line(",")
      p e.to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "a", "a"]
      ["1", "2"]
      ["1-", "2-", "3"]
      ["1-", "2-", "3"]
      ["x,", "y"]
    OUT
  end

  it "string enum block returns self" do
    result = ze0(<<~'RUBY')
      # String#chars/#bytes/#codepoints/#lines with a block yield each element
      # and return the receiver (self), not the element array. The no-block
      # form still returns the array.
      s = "abc"

      r1 = s.chars { |c| print c }
      puts ""
      puts r1

      sum = 0
      r2 = s.bytes { |b| sum = sum + b }
      puts sum
      puts r2

      cps = 0
      r3 = "ab".codepoints { |cp| cps = cps + cp }
      puts cps
      puts r3

      n = 0
      r4 = "x\ny\n".lines { |l| n = n + 1 }
      puts n
      puts r4

      # No-block forms still return arrays.
      p "abc".chars
      p "abc".bytes
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      abc
      abc
      294
      abc
      195
      ab
      2
      x
      y
      ["a", "b", "c"]
      [97, 98, 99]
    OUT
  end

  it "string enum inspect source" do
    result = ze0(<<~'RUBY')
      # Blockless String#each_char / each_line / each_byte / each_codepoint
      # return Enumerators stamped with the ORIGINAL string receiver and creating
      # method, so #inspect shows #<Enumerator: "abc":each_char> -- not the
      # materialized snapshot array with a generic :each. Iteration still drains
      # the snapshot (next/to_a unchanged).
      p("abc".each_char)
      p("a\nb\n".each_line)
      p("ab".each_byte)
      p("ab".each_codepoint)
      p("x\ny\n".each_line(chomp: true))
      e = "hi".each_char
      p e.next
      p e.next
      p e.to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      #<Enumerator: "abc":each_char>
      #<Enumerator: "a\nb\n":each_line>
      #<Enumerator: "ab":each_byte>
      #<Enumerator: "ab":each_codepoint>
      #<Enumerator: "x\ny\n":each_line(chomp: true)>
      "h"
      "i"
      ["h", "i"]
    OUT
  end

  it "string equal identity" do
    result = ze0(<<~'RUBY')
      # String#equal? is pointer identity; each literal occurrence is a distinct
      # object (matching plain CRuby), while aliases and self-comparison hold.
      a = "abc"
      b = "abc"
      p a.equal?(b)        # two occurrences: distinct objects
      p a.equal?(a)
      c = a
      p a.equal?(c)        # alias preserves identity
      d = "ab" + "c"
      e = "ab" + "c"
      p d.equal?(e)        # heap strings are always distinct
      p a == b             # content equality unaffected
      h = { "k" => 1 }
      p h["k"]             # hash keys compare by content, unaffected
      p "".equal?("")      # empty literals are distinct occurrences too
      # value-embedded types: identity IS the value (flonum-style immediates)
      x = Complex(2, 3)
      p x.equal?(x)
      p 1.0.equal?(1.0)
      p 1.0.equal?(2.0)
      r = Rational(1, 2)
      p r.equal?(r)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      true
      true
      false
      true
      1
      false
      true
      true
      false
      true
    OUT
  end

  it "string freeze identity" do
    result = ze0(<<~'RUBY')
      # String#freeze marks in place and returns the SAME object:
      # s.freeze.equal?(s) is true and s.frozen? flips. equal? on two string
      # expressions compares pointers (identical literals share storage, like
      # the frozen-string-literal world, so that case is out of scope here).
      s = "hi"
      p s.frozen?
      p s.freeze.equal?(s)
      p s.frozen?
      t = "ab"
      p t.equal?(t)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      true
      true
      true
    OUT
  end

  it "string frozen mutation raises" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true
      # Issue #886: Mutating methods on a frozen string literal raise
      # FrozenError per MRI. spinel string literals are always frozen.
      # Mutable strings (String.new("...")) keep working via the
      # mutable_str arm.
      begin
        "hello".insert(0, "X")
        puts "BUG: insert no raise"
      rescue FrozenError => e
        puts "insert: " + e.message
      end
      begin
        "hello".prepend("X")
        puts "BUG: prepend no raise"
      rescue FrozenError => e
        puts "prepend: " + e.message
      end
      begin
        "hello" << "Y"
        puts "BUG: << no raise"
      rescue FrozenError => e
        puts "<<: " + e.message
      end

      # Mutable strings still work.
      s = String.new("hi")
      s << "!"
      puts s
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      insert: can't modify frozen String: "hello"
      prepend: can't modify frozen String: "hello"
      <<: can't modify frozen String: "hello"
      hi!
    OUT
  end

  it "string identity tap then" do
    result = ze0(<<~'RUBY')
      s = "hello"
      puts s.itself.equal?(s)
      puts s.tap { |x| x }.equal?(s)
      puts s.then { |x| x }.equal?(s)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
    OUT
  end

  it "string index accepts a start offset" do
    result = ze0(<<~'RUBY')
      p "hello world".index("o")
      p "hello world".index("o", 5)
      p "hello world".index("o", -3)
      p "hello".index("z", 2)
      p "abcabc".index(/b/, 2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      4
      7
      nil
      nil
      4
    OUT
  end

  it "string index assign" do
    result = ze0(<<~'RUBY')
      # String#[]= across every index shape.

      # Single integer index: replace one char, negative index, append at length,
      # and multi-char replacement.
      s = "hello"; s[0] = "H"; p s
      s = "hello"; s[-1] = "O"; p s
      s = "ab";    s[2] = "c"; p s
      s = "abc";   s[1] = "XYZ"; p s

      # (start, length): replace a run, insert (length 0), and clamp past the end.
      s = "hello"; s[0, 2] = "XY"; p s
      s = "hello"; s[1, 0] = "__"; p s
      s = "hello"; s[1, 10] = "Z"; p s
      s = "hello"; s[-2, 1] = "X"; p s

      # Range: inclusive, exclusive, endless, beginless, and an empty range (insert).
      s = "hello"; s[1..3] = "__"; p s
      s = "hello"; s[1...3] = "Z"; p s
      s = "hello"; s[3..] = "END"; p s
      s = "hello"; s[..1] = "HE"; p s
      s = "hello"; s[2..1] = "X"; p s

      # Substring and Regexp (whole match and a capture group).
      s = "hello"; s["ll"] = "LL"; p s
      s = "hello"; s[/l+/] = "L"; p s
      s = "hello world"; s[/(\w+) (\w+)/, 2] = "RUBY"; p s

      # The assignment expression evaluates to the RHS.
      s = "hello"; p(s[0, 2] = "XY")

      # Error paths: out-of-range index/length, unmatched substring/regexp, bad range.
      s = "hi"; begin; s[3] = "x"; rescue IndexError => e; puts e.message; end
      s = "hi"; begin; s[-3] = "x"; rescue IndexError => e; puts e.message; end
      s = "hello"; begin; s[1, -1] = "x"; rescue IndexError => e; puts e.message; end
      s = "hello"; begin; s["zz"] = "x"; rescue IndexError => e; puts e.message; end
      s = "hello"; begin; s[/z/] = "x"; rescue IndexError => e; puts e.message; end
      s = "hello"; begin; s[10..] = "x"; rescue RangeError => e; puts "#{e.class}: #{e.message}"; end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "Hello"
      "hellO"
      "abc"
      "aXYZc"
      "XYllo"
      "h__ello"
      "hZ"
      "helXo"
      "h__o"
      "hZlo"
      "helEND"
      "HEllo"
      "heXllo"
      "heLLo"
      "heLo"
      "hello RUBY"
      "XY"
      index 3 out of string
      index -3 out of string
      negative length -1
      string not matched
      regexp not matched
      RangeError: 10.. out of range
    OUT
  end

  it "string index assign forms" do
    result = ze0(<<~'RUBY')
      # String#[]= beyond the single integer index: Range, (start, length),
      # substring, and Regexp forms, plus the raising misses.
      s = "hello"
      s[1..2] = "XY"
      p s
      s = "hello"
      s[1, 2] = "XY"
      p s
      s = "hello"
      s["ell"] = "ELL"
      p s
      s = "hello"
      s[/l+/] = "L"
      p s
      s = "hello"
      s[0] = "H"
      p s
      s = "abcdef"
      s[-2, 2] = "!"
      p s
      s = "abc"
      s[3..5] = "def"
      p s
      begin
        s = "abc"
        s["zz"] = "x"
      rescue IndexError => e
        p e.message
      end
      begin
        s = "abc"
        s[/z+/] = "x"
      rescue IndexError => e
        p e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hXYlo"
      "hXYlo"
      "hELLo"
      "heLo"
      "Hello"
      "abcd!"
      "abcdef"
      "string not matched"
      "regexp not matched"
    OUT
  end

  it "string index assign through container" do
    result = ze0(<<~'RUBY')
      # `rows[0][1] = "*"` mutates the string the container holds: `[]=` was not a
      # container-reaching mutator, so the Array form raised NoMethodError and the
      # Hash form silently did nothing (#3940).
      rows = [+"abc", +"def"]
      rows[0][1] = "*"
      rows[1][-1] = "Z"
      p rows
      rows[0][0, 2] = "XY"
      p rows
      rows[0][1..2] = "-"
      p rows

      h = { a: +"abc" }
      h[:a][1] = "*"
      h[:a][0, 1] = "QQ"
      p h

      n = { 1 => +"one" }
      n[1][0] = "O"
      p n

      s = String.new("hello")
      list = [s]
      list[0][0] = "H"
      p [s, list]

      # the other in-place mutators through a container keep working
      rows[1].upcase!
      rows[1] << "!"
      rows[1].sub!("D", "d")
      rows[1].insert(1, ".")
      p rows

      # a plain local String is unaffected
      t = +"abc"
      t[1] = "*"
      t[0, 1] = "ZZ"
      p t

      # a nested array element still takes an index assignment
      grid = [[1, 2], [3, 4]]
      grid[0][1] = 9
      p grid
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a*c", "deZ"]
      ["XYc", "deZ"]
      ["X-", "deZ"]
      {a: "QQ*c"}
      {1 => "One"}
      ["Hello", ["Hello"]]
      ["X-", "d.EZ!"]
      "ZZ*c"
      [[1, 9], [3, 4]]
    OUT
  end

  it "string index coderange" do
    result = ze0(<<~'RUBY')
      # Character indexing takes a byte-indexed shortcut when every character is one
      # byte. Whether that holds is a property of the CONTENT, not just the encoding,
      # so it has to be re-decided after anything that changes the bytes.

      ascii = "hello world"
      p ascii[0], ascii[4], ascii[-1], ascii[11], ascii[3, 5], ascii[-4, 4]

      wide = "héllo wörld"
      p wide.length, wide[0], wide[1], wide[-1], wide[1, 4], wide[7, 2]

      # ASCII first, multibyte appended: the shortcut must stop applying.
      grown = "abc"
      p grown[1]
      grown << "é"
      p grown.length, grown[3], grown[1], grown[2, 2]

      # Multibyte first, then sliced back down to ASCII.
      shrunk = "aébc"
      p shrunk[1]
      shrunk.replace("abcd")
      p shrunk[1], shrunk[3], shrunk[1, 2]

      # `setbyte` rewrites bytes underneath the cached answer.
      poked = "aaaa".dup
      p poked[1]
      poked.setbyte(0, 0xC3)
      poked.setbyte(1, 0xA9)
      p poked.bytesize, poked.length

      # Binary strings index by byte whatever the bytes are.
      bin = "h\xC3\xA9y".b
      p bin.length, bin[1].bytes, bin[1, 2].bytes

      # Out-of-range answers on both paths.
      p ascii[99], wide[99], ascii[99, 1], wide[99, 1], ascii[-99], ascii[3, -1]

      # An empty slice at the very end is "" on both paths, not nil.
      p ascii[11, 3], wide[11, 3], "".dup[0, 0]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "h"
      "o"
      "d"
      nil
      "lo wo"
      "orld"
      11
      "h"
      "é"
      "d"
      "éllo"
      "ör"
      "b"
      4
      "é"
      "b"
      "cé"
      "é"
      "b"
      "d"
      "bc"
      "a"
      4
      3
      4
      [195]
      [195, 169]
      nil
      nil
      nil
      nil
      nil
      nil
      ""
      ""
      ""
    OUT
  end

  it "string index nil typeerror" do
    _(ze0(<<~'RUBY').stdout).must_equal "TypeError: no implicit conversion of nil into String\n"
      # Issue #847: String#index(nil) used to silently return -1 / nil,
      # conflating "no implicit conversion" with "not found". MRI raises
      # TypeError for nil arg.
      begin
        "hello".index(nil)
        puts "BUG: no raise"
      rescue TypeError => e
        puts "TypeError: " + e.message
      end
    RUBY
  end

  it "string index write boxed" do
    result = ze0(<<~'RUBY')
      # `s[i] = v` took a statically Integer index only. A boxed one reaches it
      # whenever the value came out of a container -- a destructured block parameter,
      # an element read, an untyped argument -- and the call fell through to
      # "undefined method '[]=' for an instance of String" on a program CRuby runs
      # (#4060). The conversion is the checked one, so a boxed Integer works and the
      # splice forms spinel does not support raise TypeError rather than being read
      # as a number.
      s = +"abc"
      pairs = [[0, 1]]
      pairs.each { |r, c| s[c] = "*" }
      p s

      t = +"hello"
      idx = [[0, 1], [2, 3]][1][0]
      t[idx] = "L"
      p t

      def write_at(str, i)
        str[i] = "@"
        str
      end
      p write_at(+"abcd", 2)

      # a negative boxed index counts from the end, and one past the end appends
      u = +"xyz"
      neg = [-1].first
      u[neg] = "Z"
      p u
      v = +"ab"
      at_end = [2].first
      v[at_end] = "c"
      p v

      # out of range still raises IndexError with the original index
      w = +"ab"
      far = [9].first
      begin
        w[far] = "!"
      rescue IndexError => e
        p e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "a*c"
      "heLlo"
      "ab@d"
      "xyZ"
      "abc"
      "index 9 out of string"
    OUT
  end

  it "string inspect dump escapes" do
    result = ze0(<<~'RUBY')
      p "a\#{x}".inspect
      p "a#b".dump
      p "é".dump
      p "é".inspect
      p "a#$g".dump
      p "a#@i".inspect
      p "plain".dump
      p "tab\there".dump
      p "\u{1F600}".dump
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "\"a\\\#{x}\""
      "\"a#b\""
      "\"\\u00E9\""
      "\"é\""
      "\"a\""
      "\"a\""
      "\"plain\""
      "\"tab\\there\""
      "\"\\u{1F600}\""
    OUT
  end

  it "string lines and prepend" do
    result = ze0(<<~'RUBY')
      # String#lines / #each_line take an optional separator and a chomp: keyword.
      p "one\ntwo\nthree".lines
      p "one\ntwo\nthree".lines(chomp: true)
      p "a\r\nb\r\n".lines(chomp: true)     # default sep also strips a preceding \r
      p "a|b|c".lines("|")

      seen = []
      "red\ngreen\nblue\n".each_line(chomp: true) { |line| seen << line.upcase }
      p seen

      # String#prepend accepts any number of strings, inserted in order at the front.
      greeting = "world"
      greeting.prepend("hello, ", "dear ")
      p greeting
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["one\n", "two\n", "three"]
      ["one", "two", "three"]
      ["a", "b"]
      ["a|", "b|", "c"]
      ["RED", "GREEN", "BLUE"]
      "hello, dear world"
    OUT
  end

  it "string lines chomp and prepend variadic" do
    result = ze0(<<~'RUBY')
      p "a\nb\nc".lines
      p "a\nb\nc".lines(chomp: true)
      p "a\r\nb\r\nc\r\n".lines(chomp: true)
      p "a-b-c".lines("-")
      collected = []
      "x\ny\n".each_line(chomp: true) { |l| collected << l }
      p collected
      t = "world"
      t.prepend("hello ", "big ")
      p t
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a\n", "b\n", "c"]
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a-", "b-", "c"]
      ["x", "y"]
      "hello big world"
    OUT
  end

  it "string lines paragraph mode" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # String#lines in paragraph mode (a "" separator) does not split on the
      # blank line.
      #
      p "a\n\nb\n".lines("")
      r004 = ("1-2-3".lines("-", chomp: true) rescue $!.class); p r004
      p "1-2-3".lines("-")
      p "a\nb\n".lines(chomp: true)
      p "a\n\n\nb".lines("")
      p "".lines("")
      p "a\n\n\n\nb".lines("")
      p "a\n\n\nb\n\n\n".lines("")
      p "a\nb".lines("")
      p "\n\na".lines("")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a\n\n", "b\n"]
      ["1", "2", "3"]
      ["1-", "2-", "3"]
      ["a", "b"]
      ["a\n\n", "b"]
      []
      ["a\n\n", "b"]
      ["a\n\n", "b\n\n"]
      ["a\nb"]
      ["\n\n", "a"]
    OUT
  end

  it "string literal" do
    result = ze0(<<~'RUBY')
      name = "world"
      greeting = "hello #{name}, #{1 + 2} times"
      puts(greeting)
      puts(greeting.length)
      puts(greeting[0])
      puts(greeting[-1])
      s = "cat"
      s[0] = "b"
      puts(s)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello world, 3 times
      20
      h
      s
      bat
    OUT
  end

  it "string literal interpolation indexing and mutation" do
    result = ze0(<<~'RUBY')
      name = "world"
      greeting = "hello #{name}, #{1 + 2} times"
      puts(greeting)
      puts(greeting.length)
      puts(greeting[0])
      puts(greeting[-1])
      s = "cat"
      s[0] = "b"
      puts(s)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      hello world, 3 times
      20
      h
      s
      bat
    OUT
  end

  it "string methods read wide and legacy text by characters" do
    result = ze0(<<~'RUBY')
      # String's own methods read wide and legacy text a character at a time:
      # length and each_char, reverse and slicing, justification, strip and
      # chomp with the encoding's own spaces and newlines, squeeze, count,
      # delete and tr over the encoding's characters, case mapping, succ,
      # inspect and dump, ord and codepoints, and lines in paragraph mode.
      def shown(v)
        case v
        when String then v.valid_encoding? && v.encoding != Encoding::BINARY ? [v.encoding.name, v.encode("UTF-8")] : [v.encoding.name, v.b]
        when Array then v.map { |x| shown(x) }
        else v
        end
      end

      def show(label)
        p [label, shown(yield)]
      rescue StandardError, NotImplementedError => e
        p [label, e.class, e.message.b]
      end

      SAMPLES = {
        "UTF-16LE" => " Grüße 世界😀\r\n\n\nend \n", "UTF-16BE" => " Grüße 世界😀\r\n\n\nend \n",
        "UTF-32LE" => " Grüße 世界😀\r\n\n\nend \n", "UTF-32BE" => " Grüße 世界😀\r\n\n\nend \n",
        "CESU-8" => " Grüße 世界😀\r\n\n\nend \n", "GB18030" => " Grüße 世界😀\r\n\n\nend \n",
        "EUC-JP" => " カナ 世界ａ\r\n\n\nend \n", "Shift_JIS" => " カナ ソ表\\\r\n\n\nend \n", "Big5" => " 中文 測試\r\n\n\nend \n",
        "GBK" => " 中文 测试\r\n\n\nend \n", "EUC-KR" => " 한국 세계\r\n\n\nend \n", "ISO-8859-7" => " Καλη ΑΒ\r\n\n\nend \n",
      }.freeze

      SAMPLES.each do |name, sample|
        e = ->(s) { s.encode(name) }
        text = e.(sample)
        show(:"#{name}_length") { [text.length, text.bytesize, text.chars.size, text.each_char.first(3), text.valid_encoding?, text.ascii_only?] }
        show(:"#{name}_reverse") { [text.reverse, text[2, 3], text[-4..], text.slice(1), text.byteslice(2, 4).valid_encoding?] }
        show(:"#{name}_justify") { [text.strip.center(20, e.("*")), text.strip.ljust(18), text.strip.rjust(18, e.("-="))] }
        show(:"#{name}_strip") { [text.strip, text.lstrip, text.rstrip, text.chomp, text.chop, text.chomp(e.("\n")), text.chomp(e.("d \n"))] }
        show(:"#{name}_lines") { [text.lines, text.lines(chomp: true), text.lines(e.("")), text.lines(e.(""), chomp: true), text.each_line(e.("e")).to_a] }
        show(:"#{name}_lines_default") { [text.lines($/).size, (text.lines("\n") rescue $!.class)] }
        show(:"#{name}_count") { [text.count(e.("e")), text.count(e.("a-z")), text.delete(e.(" ")), text.squeeze, text.squeeze(e.("\n"))] }
        show(:"#{name}_tr") { [text.tr(e.("a-y"), e.("b-z")), text.tr_s(e.("\n"), e.("|")), text.delete(e.("^a-z"))] }
        show(:"#{name}_case") { [text.upcase, text.downcase, text.swapcase, text.capitalize, text.upcase(:ascii)] }
        show(:"#{name}_casecmp") { [text.casecmp(text.upcase), text.casecmp?(text.upcase), text == text.dup, text.eql?(e.(sample))] }
        show(:"#{name}_succ") { [e.("az").succ, e.("zz").succ, text.strip.succ] }
        show(:"#{name}_inspect") { [text.inspect, text.dump] }
        show(:"#{name}_codepoints") { [text.ord, text.codepoints.first(8), text.sum, text.getbyte(1), text.hash == e.(sample).hash] }
        show(:"#{name}_index") { [text.index(e.("e")), text.rindex(e.("e")), text.byteindex(e.("end")), text.include?(e.("nd")), text.start_with?(e.(" ")), text.end_with?(e.("\n"))] }
        show(:"#{name}_split") { [text.split, text.split(e.("\n")), text.split(e.(""), 4), text.partition(e.(" ")), text.rpartition(e.(" "))] }
        show(:"#{name}_insert") { [text.dup.insert(2, e.("<>")), text.dup.prepend(e.(">")), text.dup << e.("!"), text * 2 == text + text] }
        show(:"#{name}_each_grapheme") { text.each_grapheme_cluster.first(4) }
        show(:"#{name}_scrub") { [text.scrub, (text.b + "\xFF".b).force_encoding(name).scrub.bytesize] }
        show(:"#{name}_unicode_normalize") { text.unicode_normalize(:nfd).length }
        show(:"#{name}_encode") { [text.encode("UTF-8").bytesize, text.encode("UTF-16LE").bytesize] }
      end

      # A UTF-16 or UTF-32 text that ends in broken units: the decoder's
      # tables say which bytes are invalid and which a longer text would
      # complete, and a bad byte inside a unit takes the rest of the unit.
      %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
        ["  ", " ", "\x00 ", "\x00\x00 ", "\x00\x11  ", "   ", "\xD8\x00\x00\x00", "\x00\xD8\x00\x00", "\xDC\x00a", "\x00\xDCa", "\x00\xD8\x00\xDC"].each do |tail|
          s = ("a".encode(enc).b + tail.b).force_encoding(enc)
          label = :"#{enc}_tail_#{tail.unpack1('H*')}"
          show(label) do
            s.encode("UTF-8")
          rescue Encoding::InvalidByteSequenceError => e
            [e.message.b, e.error_bytes.b, e.readagain_bytes&.b, e.incomplete_input?]
          end
          show(:"#{label}_replaced") { [s.encode("UTF-8", invalid: :replace), s.valid_encoding?, s.length, s.scrub.bytesize, s.chars.map(&:bytesize)] }
        end
      end


    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [:"UTF-16LE_length", [19, 40, 19, [["UTF-16LE", " "], ["UTF-16LE", "G"], ["UTF-16LE", "r"]], true, false]]
      [:"UTF-16LE_reverse", [["UTF-16LE", "\n dne\n\n\n\r😀界世 eßürG "], ["UTF-16LE", "rüß"], ["UTF-16LE", "nd \n"], ["UTF-16LE", "G"], true]]
      [:"UTF-16LE_justify", [["UTF-16LE", "**Grüße 世界😀\r\n\n\nend**"], ["UTF-16LE", "Grüße 世界😀\r\n\n\nend†"], ["UTF-16LE", "-=Grüße 世界😀\r\n\n\nend"]]]
      [:"UTF-16LE_strip", [["UTF-16LE", "Grüße 世界😀\r\n\n\nend"], ["UTF-16LE", "Grüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend"], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16LE", " Grüße 世界😀\r\n\n\nen"]]]
      [:"UTF-16LE_lines", [[["UTF-16LE", " Grüße 世界😀\r\n"], ["UTF-16LE", "\n"], ["UTF-16LE", "\n"], ["UTF-16LE", "end \n"]], [["UTF-16LE", " Grüße 世界😀\r"], ["UTF-16LE", ""], ["UTF-16LE", ""], ["UTF-16LE", "end "]], [["UTF-16LE", " Grüße 世界😀\r\n\n"], ["UTF-16LE", "end \n"]], [["UTF-16LE", " Grüße 世界😀"], ["UTF-16LE", "end \n"]], [["UTF-16LE", " Grüße"], ["UTF-16LE", " 世界😀\r\n\n\ne"], ["UTF-16LE", "nd \n"]]]]
      [:"UTF-16LE_lines_default", [4, Encoding::CompatibilityError]]
      [:"UTF-16LE_count", [2, 5, ["UTF-16LE", "Grüße世界😀\r\n\n\nend\n"], ["UTF-16LE", " Grüße 世界😀\r\nend \n"], ["UTF-16LE", " Grüße 世界😀\r\nend \n"]]]
      [:"UTF-16LE_tr", [["UTF-16LE", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["UTF-16LE", " Grüße 世界😀\r|end |"], ["UTF-16LE", "reend"]]]
      [:"UTF-16LE_case", [["UTF-16LE", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-16LE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-16LE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"UTF-16LE_casecmp", [1, true, true, true]]
      [:"UTF-16LE_succ", [["UTF-16LE", "ba"], ["UTF-16LE", "aaa"], ["UTF-16LE", "Grüße 世界😀\r\n\n\nene"]]]
      [:"UTF-16LE_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["ASCII-8BIT", "\" \\x00G\\x00r\\x00\\xFC\\x00\\xDF\\x00e\\x00 \\x00\\x16NLu=\\xD8\\x00\\xDE\\r\\x00\\n\\x00\\n\\x00\\n\\x00e\\x00n\\x00d\\x00 \\x00\\n\\x00\".dup.force_encoding(\"UTF-16LE\")"]]]
      [:"UTF-16LE_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 2013, 0, true]]
      [:"UTF-16LE_index", [5, 14, 30, true, true, true]]
      [:"UTF-16LE_split", [[["UTF-16LE", "Grüße"], ["UTF-16LE", "世界😀"], ["UTF-16LE", "end"]], [["UTF-16LE", " Grüße 世界😀\r"], ["UTF-16LE", ""], ["UTF-16LE", ""], ["UTF-16LE", "end "]], [["UTF-16LE", " "], ["UTF-16LE", "G"], ["UTF-16LE", "r"], ["UTF-16LE", "üße 世界😀\r\n\n\nend \n"]], [["UTF-16LE", ""], ["UTF-16LE", " "], ["UTF-16LE", "Grüße 世界😀\r\n\n\nend \n"]], [["UTF-16LE", " Grüße 世界😀\r\n\n\nend"], ["UTF-16LE", " "], ["UTF-16LE", "\n"]]]]
      [:"UTF-16LE_insert", [["UTF-16LE", " G<>rüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", "> Grüße 世界😀\r\n\n\nend \n"], ["UTF-16LE", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"UTF-16LE_each_grapheme", [["UTF-16LE", " "], ["UTF-16LE", "G"], ["UTF-16LE", "r"], ["UTF-16LE", "ü"]]]
      [:"UTF-16LE_scrub", [["UTF-16LE", " Grüße 世界😀\r\n\n\nend \n"], 42]]
      [:"UTF-16LE_unicode_normalize", 20]
      [:"UTF-16LE_encode", [28, 40]]
      [:"UTF-16BE_length", [19, 40, 19, [["UTF-16BE", " "], ["UTF-16BE", "G"], ["UTF-16BE", "r"]], true, false]]
      [:"UTF-16BE_reverse", [["UTF-16BE", "\n dne\n\n\n\r😀界世 eßürG "], ["UTF-16BE", "rüß"], ["UTF-16BE", "nd \n"], ["UTF-16BE", "G"], true]]
      [:"UTF-16BE_justify", [["UTF-16BE", "**Grüße 世界😀\r\n\n\nend**"], ["UTF-16BE", "Grüße 世界😀\r\n\n\nend†"], ["UTF-16BE", "-=Grüße 世界😀\r\n\n\nend"]]]
      [:"UTF-16BE_strip", [["UTF-16BE", "Grüße 世界😀\r\n\n\nend"], ["UTF-16BE", "Grüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend"], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-16BE", " Grüße 世界😀\r\n\n\nen"]]]
      [:"UTF-16BE_lines", [[["UTF-16BE", " Grüße 世界😀\r\n"], ["UTF-16BE", "\n"], ["UTF-16BE", "\n"], ["UTF-16BE", "end \n"]], [["UTF-16BE", " Grüße 世界😀\r"], ["UTF-16BE", ""], ["UTF-16BE", ""], ["UTF-16BE", "end "]], [["UTF-16BE", " Grüße 世界😀\r\n\n"], ["UTF-16BE", "end \n"]], [["UTF-16BE", " Grüße 世界😀"], ["UTF-16BE", "end \n"]], [["UTF-16BE", " Grüße"], ["UTF-16BE", " 世界😀\r\n\n\ne"], ["UTF-16BE", "nd \n"]]]]
      [:"UTF-16BE_lines_default", [4, Encoding::CompatibilityError]]
      [:"UTF-16BE_count", [2, 5, ["UTF-16BE", "Grüße世界😀\r\n\n\nend\n"], ["UTF-16BE", " Grüße 世界😀\r\nend \n"], ["UTF-16BE", " Grüße 世界😀\r\nend \n"]]]
      [:"UTF-16BE_tr", [["UTF-16BE", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["UTF-16BE", " Grüße 世界😀\r|end |"], ["UTF-16BE", "reend"]]]
      [:"UTF-16BE_case", [["UTF-16BE", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-16BE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-16BE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"UTF-16BE_casecmp", [1, true, true, true]]
      [:"UTF-16BE_succ", [["UTF-16BE", "ba"], ["UTF-16BE", "aaa"], ["UTF-16BE", "Grüße 世界😀\r\n\n\nene"]]]
      [:"UTF-16BE_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["ASCII-8BIT", "\"\\x00 \\x00G\\x00r\\x00\\xFC\\x00\\xDF\\x00e\\x00 N\\x16uL\\xD8=\\xDE\\x00\\x00\\r\\x00\\n\\x00\\n\\x00\\n\\x00e\\x00n\\x00d\\x00 \\x00\\n\".dup.force_encoding(\"UTF-16BE\")"]]]
      [:"UTF-16BE_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 2013, 32, true]]
      [:"UTF-16BE_index", [5, 14, 30, true, true, true]]
      [:"UTF-16BE_split", [[["UTF-16BE", "Grüße"], ["UTF-16BE", "世界😀"], ["UTF-16BE", "end"]], [["UTF-16BE", " Grüße 世界😀\r"], ["UTF-16BE", ""], ["UTF-16BE", ""], ["UTF-16BE", "end "]], [["UTF-16BE", " "], ["UTF-16BE", "G"], ["UTF-16BE", "r"], ["UTF-16BE", "üße 世界😀\r\n\n\nend \n"]], [["UTF-16BE", ""], ["UTF-16BE", " "], ["UTF-16BE", "Grüße 世界😀\r\n\n\nend \n"]], [["UTF-16BE", " Grüße 世界😀\r\n\n\nend"], ["UTF-16BE", " "], ["UTF-16BE", "\n"]]]]
      [:"UTF-16BE_insert", [["UTF-16BE", " G<>rüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", "> Grüße 世界😀\r\n\n\nend \n"], ["UTF-16BE", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"UTF-16BE_each_grapheme", [["UTF-16BE", " "], ["UTF-16BE", "G"], ["UTF-16BE", "r"], ["UTF-16BE", "ü"]]]
      [:"UTF-16BE_scrub", [["UTF-16BE", " Grüße 世界😀\r\n\n\nend \n"], 42]]
      [:"UTF-16BE_unicode_normalize", 20]
      [:"UTF-16BE_encode", [28, 40]]
      [:"UTF-32LE_length", [19, 76, 19, [["UTF-32LE", " "], ["UTF-32LE", "G"], ["UTF-32LE", "r"]], true, false]]
      [:"UTF-32LE_reverse", [["UTF-32LE", "\n dne\n\n\n\r😀界世 eßürG "], ["UTF-32LE", "rüß"], ["UTF-32LE", "nd \n"], ["UTF-32LE", "G"], false]]
      [:"UTF-32LE_justify", Encoding::InvalidByteSequenceError, "incomplete \"  \" on UTF-32LE"]
      [:"UTF-32LE_strip", [["UTF-32LE", "Grüße 世界😀\r\n\n\nend"], ["UTF-32LE", "Grüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend"], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32LE", " Grüße 世界😀\r\n\n\nen"]]]
      [:"UTF-32LE_lines", [[["UTF-32LE", " Grüße 世界😀\r\n"], ["UTF-32LE", "\n"], ["UTF-32LE", "\n"], ["UTF-32LE", "end \n"]], [["UTF-32LE", " Grüße 世界😀\r"], ["UTF-32LE", ""], ["UTF-32LE", ""], ["UTF-32LE", "end "]], [["UTF-32LE", " Grüße 世界😀\r\n\n"], ["UTF-32LE", "end \n"]], [["UTF-32LE", " Grüße 世界😀"], ["UTF-32LE", "end \n"]], [["UTF-32LE", " Grüße"], ["UTF-32LE", " 世界😀\r\n\n\ne"], ["UTF-32LE", "nd \n"]]]]
      [:"UTF-32LE_lines_default", [4, Encoding::CompatibilityError]]
      [:"UTF-32LE_count", [2, 5, ["UTF-32LE", "Grüße世界😀\r\n\n\nend\n"], ["UTF-32LE", " Grüße 世界😀\r\nend \n"], ["UTF-32LE", " Grüße 世界😀\r\nend \n"]]]
      [:"UTF-32LE_tr", [["UTF-32LE", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["UTF-32LE", " Grüße 世界😀\r|end |"], ["UTF-32LE", "reend"]]]
      [:"UTF-32LE_case", [["UTF-32LE", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-32LE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-32LE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"UTF-32LE_casecmp", [1, true, true, true]]
      [:"UTF-32LE_succ", [["UTF-32LE", "ba"], ["UTF-32LE", "aaa"], ["UTF-32LE", "Grüße 世界😀\r\n\n\nene"]]]
      [:"UTF-32LE_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["ASCII-8BIT", "\" \\x00\\x00\\x00G\\x00\\x00\\x00r\\x00\\x00\\x00\\xFC\\x00\\x00\\x00\\xDF\\x00\\x00\\x00e\\x00\\x00\\x00 \\x00\\x00\\x00\\x16N\\x00\\x00Lu\\x00\\x00\\x00\\xF6\\x01\\x00\\r\\x00\\x00\\x00\\n\\x00\\x00\\x00\\n\\x00\\x00\\x00\\n\\x00\\x00\\x00e\\x00\\x00\\x00n\\x00\\x00\\x00d\\x00\\x00\\x00 \\x00\\x00\\x00\\n\\x00\\x00\\x00\".dup.force_encoding(\"UTF-32LE\")"]]]
      [:"UTF-32LE_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 1761, 0, true]]
      [:"UTF-32LE_index", [5, 14, 56, true, true, true]]
      [:"UTF-32LE_split", [[["UTF-32LE", "Grüße"], ["UTF-32LE", "世界😀"], ["UTF-32LE", "end"]], [["UTF-32LE", " Grüße 世界😀\r"], ["UTF-32LE", ""], ["UTF-32LE", ""], ["UTF-32LE", "end "]], [["UTF-32LE", " "], ["UTF-32LE", "G"], ["UTF-32LE", "r"], ["UTF-32LE", "üße 世界😀\r\n\n\nend \n"]], [["UTF-32LE", ""], ["UTF-32LE", " "], ["UTF-32LE", "Grüße 世界😀\r\n\n\nend \n"]], [["UTF-32LE", " Grüße 世界😀\r\n\n\nend"], ["UTF-32LE", " "], ["UTF-32LE", "\n"]]]]
      [:"UTF-32LE_insert", [["UTF-32LE", " G<>rüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", "> Grüße 世界😀\r\n\n\nend \n"], ["UTF-32LE", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"UTF-32LE_each_grapheme", [["UTF-32LE", " "], ["UTF-32LE", "G"], ["UTF-32LE", "r"], ["UTF-32LE", "ü"]]]
      [:"UTF-32LE_scrub", [["UTF-32LE", " Grüße 世界😀\r\n\n\nend \n"], 80]]
      [:"UTF-32LE_unicode_normalize", 20]
      [:"UTF-32LE_encode", [28, 40]]
      [:"UTF-32BE_length", [19, 76, 19, [["UTF-32BE", " "], ["UTF-32BE", "G"], ["UTF-32BE", "r"]], true, false]]
      [:"UTF-32BE_reverse", [["UTF-32BE", "\n dne\n\n\n\r😀界世 eßürG "], ["UTF-32BE", "rüß"], ["UTF-32BE", "nd \n"], ["UTF-32BE", "G"], false]]
      [:"UTF-32BE_justify", Encoding::InvalidByteSequenceError, "\"  \" on UTF-32BE"]
      [:"UTF-32BE_strip", [["UTF-32BE", "Grüße 世界😀\r\n\n\nend"], ["UTF-32BE", "Grüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend"], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend "], ["UTF-32BE", " Grüße 世界😀\r\n\n\nen"]]]
      [:"UTF-32BE_lines", [[["UTF-32BE", " Grüße 世界😀\r\n"], ["UTF-32BE", "\n"], ["UTF-32BE", "\n"], ["UTF-32BE", "end \n"]], [["UTF-32BE", " Grüße 世界😀\r"], ["UTF-32BE", ""], ["UTF-32BE", ""], ["UTF-32BE", "end "]], [["UTF-32BE", " Grüße 世界😀\r\n\n"], ["UTF-32BE", "end \n"]], [["UTF-32BE", " Grüße 世界😀"], ["UTF-32BE", "end \n"]], [["UTF-32BE", " Grüße"], ["UTF-32BE", " 世界😀\r\n\n\ne"], ["UTF-32BE", "nd \n"]]]]
      [:"UTF-32BE_lines_default", [4, Encoding::CompatibilityError]]
      [:"UTF-32BE_count", [2, 5, ["UTF-32BE", "Grüße世界😀\r\n\n\nend\n"], ["UTF-32BE", " Grüße 世界😀\r\nend \n"], ["UTF-32BE", " Grüße 世界😀\r\nend \n"]]]
      [:"UTF-32BE_tr", [["UTF-32BE", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["UTF-32BE", " Grüße 世界😀\r|end |"], ["UTF-32BE", "reend"]]]
      [:"UTF-32BE_case", [["UTF-32BE", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-32BE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["UTF-32BE", " grüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"UTF-32BE_casecmp", [1, true, true, true]]
      [:"UTF-32BE_succ", [["UTF-32BE", "ba"], ["UTF-32BE", "aaa"], ["UTF-32BE", "Grüße 世界😀\r\n\n\nene"]]]
      [:"UTF-32BE_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["ASCII-8BIT", "\"\\x00\\x00\\x00 \\x00\\x00\\x00G\\x00\\x00\\x00r\\x00\\x00\\x00\\xFC\\x00\\x00\\x00\\xDF\\x00\\x00\\x00e\\x00\\x00\\x00 \\x00\\x00N\\x16\\x00\\x00uL\\x00\\x01\\xF6\\x00\\x00\\x00\\x00\\r\\x00\\x00\\x00\\n\\x00\\x00\\x00\\n\\x00\\x00\\x00\\n\\x00\\x00\\x00e\\x00\\x00\\x00n\\x00\\x00\\x00d\\x00\\x00\\x00 \\x00\\x00\\x00\\n\".dup.force_encoding(\"UTF-32BE\")"]]]
      [:"UTF-32BE_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 1761, 0, true]]
      [:"UTF-32BE_index", [5, nil, 56, true, true, true]]
      [:"UTF-32BE_split", [[["UTF-32BE", "Grüße"], ["UTF-32BE", "世界😀"], ["UTF-32BE", "end"]], [["UTF-32BE", " Grüße 世界😀\r"], ["UTF-32BE", ""], ["UTF-32BE", ""], ["UTF-32BE", "end "]], [["UTF-32BE", " "], ["UTF-32BE", "G"], ["UTF-32BE", "r"], ["UTF-32BE", "üße 世界😀\r\n\n\nend \n"]], [["UTF-32BE", ""], ["UTF-32BE", " "], ["UTF-32BE", "Grüße 世界😀\r\n\n\nend \n"]], [["UTF-32BE", ""], ["UTF-32BE", ""], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend \n"]]]]
      [:"UTF-32BE_insert", [["UTF-32BE", " G<>rüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", "> Grüße 世界😀\r\n\n\nend \n"], ["UTF-32BE", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"UTF-32BE_each_grapheme", [["UTF-32BE", " "], ["UTF-32BE", "G"], ["UTF-32BE", "r"], ["UTF-32BE", "ü"]]]
      [:"UTF-32BE_scrub", [["UTF-32BE", " Grüße 世界😀\r\n\n\nend \n"], 80]]
      [:"UTF-32BE_unicode_normalize", 20]
      [:"UTF-32BE_encode", [28, 40]]
      [:"CESU-8_length", [19, 30, 19, [["CESU-8", " "], ["CESU-8", "G"], ["CESU-8", "r"]], true, false]]
      [:"CESU-8_reverse", [["CESU-8", "\n dne\n\n\n\r😀界世 eßürG "], ["CESU-8", "rüß"], ["CESU-8", "nd \n"], ["CESU-8", "G"], false]]
      [:"CESU-8_justify", [["CESU-8", "**Grüße 世界😀\r\n\n\nend**"], ["CESU-8", "Grüße 世界😀\r\n\n\nend  "], ["CESU-8", "-=Grüße 世界😀\r\n\n\nend"]]]
      [:"CESU-8_strip", [["CESU-8", "Grüße 世界😀\r\n\n\nend"], ["CESU-8", "Grüße 世界😀\r\n\n\nend \n"], ["CESU-8", " Grüße 世界😀\r\n\n\nend"], ["CESU-8", " Grüße 世界😀\r\n\n\nend "], ["CESU-8", " Grüße 世界😀\r\n\n\nend "], ["CESU-8", " Grüße 世界😀\r\n\n\nend "], ["CESU-8", " Grüße 世界😀\r\n\n\nen"]]]
      [:"CESU-8_lines", [[["CESU-8", " Grüße 世界😀\r\n"], ["CESU-8", "\n"], ["CESU-8", "\n"], ["CESU-8", "end \n"]], [["CESU-8", " Grüße 世界😀"], ["CESU-8", ""], ["CESU-8", ""], ["CESU-8", "end "]], [["CESU-8", " Grüße 世界😀\r\n\n"], ["CESU-8", "end \n"]], [["CESU-8", " Grüße 世界😀"], ["CESU-8", "end \n"]], [["CESU-8", " Grüße"], ["CESU-8", " 世界😀\r\n\n\ne"], ["CESU-8", "nd \n"]]]]
      [:"CESU-8_lines_default", [4, [["CESU-8", " Grüße 世界😀\r\n"], ["CESU-8", "\n"], ["CESU-8", "\n"], ["CESU-8", "end \n"]]]]
      [:"CESU-8_count", [2, 5, ["CESU-8", "Grüße世界😀\r\n\n\nend\n"], ["CESU-8", " Grüße 世界😀\r\nend \n"], ["CESU-8", " Grüße 世界😀\r\nend \n"]]]
      [:"CESU-8_tr", [["CESU-8", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["CESU-8", " Grüße 世界😀\r|end |"], ["CESU-8", "reend"]]]
      [:"CESU-8_case", [["CESU-8", " GRÜSSE 世界😀\r\n\n\nEND \n"], ["CESU-8", " grüße 世界😀\r\n\n\nend \n"], ["CESU-8", " gRÜSSE 世界😀\r\n\n\nEND \n"], ["CESU-8", " grüße 世界😀\r\n\n\nend \n"], ["CESU-8", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:"CESU-8_casecmp", [1, true, true, true]]
      [:"CESU-8_succ", [["CESU-8", "ba"], ["CESU-8", "aaa"], ["CESU-8", "Grüße 世界😀\r\n\n\nene"]]]
      [:"CESU-8_inspect", [["UTF-8", "\" Gr\\u00FC\\u00DFe \\u4E16\\u754C\\u{1F600}\\r\\n\\n\\nend \\n\""], ["CESU-8", "\" Gr\\xC3\\xBC\\xC3\\x9Fe \\xE4\\xB8\\x96\\xE7\\x95\\x8C\\xED\\xA0\\xBD\\xED\\xB8\\x80\\r\\n\\n\\nend \\n\""]]]
      [:"CESU-8_codepoints", [32, [32, 71, 114, 252, 223, 101, 32, 19990], 3700, 71, true]]
      [:"CESU-8_index", [5, 14, 25, true, true, true]]
      [:"CESU-8_split", [[["CESU-8", "Grüße"], ["CESU-8", "世界😀"], ["CESU-8", "end"]], [["CESU-8", " Grüße 世界😀\r"], ["CESU-8", ""], ["CESU-8", ""], ["CESU-8", "end "]], [["CESU-8", " "], ["CESU-8", "G"], ["CESU-8", "r"], ["CESU-8", "üße 世界😀\r\n\n\nend \n"]], [["CESU-8", ""], ["CESU-8", " "], ["CESU-8", "Grüße 世界😀\r\n\n\nend \n"]], [["CESU-8", " Grüße 世界😀\r\n\n\nend"], ["CESU-8", " "], ["CESU-8", "\n"]]]]
      [:"CESU-8_insert", [["CESU-8", " G<>rüße 世界😀\r\n\n\nend \n"], ["CESU-8", "> Grüße 世界😀\r\n\n\nend \n"], ["CESU-8", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:"CESU-8_each_grapheme", [["CESU-8", " "], ["CESU-8", "G"], ["CESU-8", "r"], ["CESU-8", "ü"]]]
      [:"CESU-8_scrub", [["CESU-8", " Grüße 世界😀\r\n\n\nend \n"], 31]]
      [:"CESU-8_unicode_normalize", Encoding::CompatibilityError, "Unicode Normalization not appropriate for CESU-8"]
      [:"CESU-8_encode", [28, 40]]
      [:GB18030_length, [19, 28, 19, [["GB18030", " "], ["GB18030", "G"], ["GB18030", "r"]], true, false]]
      [:GB18030_reverse, [["GB18030", "\n dne\n\n\n\r😀界世 eßürG "], ["GB18030", "rüß"], ["GB18030", "nd \n"], ["GB18030", "G"], false]]
      [:GB18030_justify, [["GB18030", "**Grüße 世界😀\r\n\n\nend**"], ["GB18030", "Grüße 世界😀\r\n\n\nend  "], ["GB18030", "-=Grüße 世界😀\r\n\n\nend"]]]
      [:GB18030_strip, [["GB18030", "Grüße 世界😀\r\n\n\nend"], ["GB18030", "Grüße 世界😀\r\n\n\nend \n"], ["GB18030", " Grüße 世界😀\r\n\n\nend"], ["GB18030", " Grüße 世界😀\r\n\n\nend "], ["GB18030", " Grüße 世界😀\r\n\n\nend "], ["GB18030", " Grüße 世界😀\r\n\n\nend "], ["GB18030", " Grüße 世界😀\r\n\n\nen"]]]
      [:GB18030_lines, [[["GB18030", " Grüße 世界😀\r\n"], ["GB18030", "\n"], ["GB18030", "\n"], ["GB18030", "end \n"]], [["GB18030", " Grüße 世界😀"], ["GB18030", ""], ["GB18030", ""], ["GB18030", "end "]], [["GB18030", " Grüße 世界😀\r\n\n"], ["GB18030", "end \n"]], [["GB18030", " Grüße 世界😀"], ["GB18030", "end \n"]], [["GB18030", " Grüße"], ["GB18030", " 世界😀\r\n\n\ne"], ["GB18030", "nd \n"]]]]
      [:GB18030_lines_default, [4, [["GB18030", " Grüße 世界😀\r\n"], ["GB18030", "\n"], ["GB18030", "\n"], ["GB18030", "end \n"]]]]
      [:GB18030_count, [2, 5, ["GB18030", "Grüße世界😀\r\n\n\nend\n"], ["GB18030", " Grüße 世界😀\r\nend \n"], ["GB18030", " Grüße 世界😀\r\nend \n"]]]
      [:GB18030_tr, [["GB18030", " Gsüßf 世界😀\r\n\n\nfoe \n"], ["GB18030", " Grüße 世界😀\r|end |"], ["GB18030", "reend"]]]
      [:GB18030_case, [["GB18030", " GRüßE 世界😀\r\n\n\nEND \n"], ["GB18030", " grüße 世界😀\r\n\n\nend \n"], ["GB18030", " gRüßE 世界😀\r\n\n\nEND \n"], ["GB18030", " grüße 世界😀\r\n\n\nend \n"], ["GB18030", " GRüßE 世界😀\r\n\n\nEND \n"]]]
      [:GB18030_casecmp, [0, true, true, true]]
      [:GB18030_succ, [["GB18030", "ba"], ["GB18030", "aaa"], ["GB18030", "Grüße 世界😀\r\n\n\nene"]]]
      [:GB18030_inspect, [["UTF-8", "\" Gr\\x{A8B9}\\x{81308938}e \\x{CAC0}\\x{BDE7}\\x{9439FC36}\\r\\n\\n\\nend \\n\""], ["GB18030", "\" Gr\\xA8\\xB9\\x810\\x898e \\xCA\\xC0\\xBD\\xE7\\x949\\xFC6\\r\\n\\n\\nend \\n\""]]]
      [:GB18030_codepoints, [32, [32, 71, 114, 43193, 2167441720, 101, 32, 51904], 2794, 71, true]]
      [:GB18030_index, [5, 14, 23, true, true, true]]
      [:GB18030_split, [[["GB18030", "Grüße"], ["GB18030", "世界😀"], ["GB18030", "end"]], [["GB18030", " Grüße 世界😀\r"], ["GB18030", ""], ["GB18030", ""], ["GB18030", "end "]], [["GB18030", " "], ["GB18030", "G"], ["GB18030", "r"], ["GB18030", "üße 世界😀\r\n\n\nend \n"]], [["GB18030", ""], ["GB18030", " "], ["GB18030", "Grüße 世界😀\r\n\n\nend \n"]], [["GB18030", " Grüße 世界😀\r\n\n\nend"], ["GB18030", " "], ["GB18030", "\n"]]]]
      [:GB18030_insert, [["GB18030", " G<>rüße 世界😀\r\n\n\nend \n"], ["GB18030", "> Grüße 世界😀\r\n\n\nend \n"], ["GB18030", " Grüße 世界😀\r\n\n\nend \n!"], true]]
      [:GB18030_each_grapheme, [["GB18030", " "], ["GB18030", "G"], ["GB18030", "r"], ["GB18030", "ü"]]]
      [:GB18030_scrub, [["GB18030", " Grüße 世界😀\r\n\n\nend \n"], 29]]
      [:GB18030_unicode_normalize, 20]
      [:GB18030_encode, [28, 40]]
      [:"EUC-JP_length", [16, 21, 16, [["EUC-JP", " "], ["EUC-JP", "カ"], ["EUC-JP", "ナ"]], true, false]]
      [:"EUC-JP_reverse", [["EUC-JP", "\n dne\n\n\n\rａ界世 ナカ "], ["EUC-JP", "ナ 世"], ["EUC-JP", "nd \n"], ["EUC-JP", "カ"], false]]
      [:"EUC-JP_justify", [["EUC-JP", "***カナ 世界ａ\r\n\n\nend****"], ["EUC-JP", "カナ 世界ａ\r\n\n\nend     "], ["EUC-JP", "-=-=-カナ 世界ａ\r\n\n\nend"]]]
      [:"EUC-JP_strip", [["EUC-JP", "カナ 世界ａ\r\n\n\nend"], ["EUC-JP", "カナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend "], ["EUC-JP", " カナ 世界ａ\r\n\n\nend "], ["EUC-JP", " カナ 世界ａ\r\n\n\nend "], ["EUC-JP", " カナ 世界ａ\r\n\n\nen"]]]
      [:"EUC-JP_lines", [[["EUC-JP", " カナ 世界ａ\r\n"], ["EUC-JP", "\n"], ["EUC-JP", "\n"], ["EUC-JP", "end \n"]], [["EUC-JP", " カナ 世界ａ"], ["EUC-JP", ""], ["EUC-JP", ""], ["EUC-JP", "end "]], [["EUC-JP", " カナ 世界ａ\r\n\n"], ["EUC-JP", "end \n"]], [["EUC-JP", " カナ 世界ａ"], ["EUC-JP", "end \n"]], [["EUC-JP", " カナ 世界ａ\r\n\n\ne"], ["EUC-JP", "nd \n"]]]]
      [:"EUC-JP_lines_default", [4, [["EUC-JP", " カナ 世界ａ\r\n"], ["EUC-JP", "\n"], ["EUC-JP", "\n"], ["EUC-JP", "end \n"]]]]
      [:"EUC-JP_count", [1, 3, ["EUC-JP", "カナ世界ａ\r\n\n\nend\n"], ["EUC-JP", " カナ 世界ａ\r\nend \n"], ["EUC-JP", " カナ 世界ａ\r\nend \n"]]]
      [:"EUC-JP_tr", [["EUC-JP", " カナ 世界ａ\r\n\n\nfoe \n"], ["EUC-JP", " カナ 世界ａ\r|end |"], ["EUC-JP", "end"]]]
      [:"EUC-JP_case", [["EUC-JP", " カナ 世界ａ\r\n\n\nEND \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nEND \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nEND \n"]]]
      [:"EUC-JP_casecmp", [0, true, true, true]]
      [:"EUC-JP_succ", [["EUC-JP", "ba"], ["EUC-JP", "aaa"], ["EUC-JP", "カナ 世界ａ\r\n\n\nene"]]]
      [:"EUC-JP_inspect", [["UTF-8", "\" \\x{A5AB}\\x{A5CA} \\x{C0A4}\\x{B3A6}\\x{A3E1}\\r\\n\\n\\nend \\n\""], ["EUC-JP", "\" \\xA5\\xAB\\xA5\\xCA \\xC0\\xA4\\xB3\\xA6\\xA3\\xE1\\r\\n\\n\\nend \\n\""]]]
      [:"EUC-JP_codepoints", [32, [32, 42411, 42442, 32, 49316, 45990, 41953, 13], 2252, 165, true]]
      [:"EUC-JP_index", [11, 11, 16, true, true, true]]
      [:"EUC-JP_split", [[["EUC-JP", "カナ"], ["EUC-JP", "世界ａ"], ["EUC-JP", "end"]], [["EUC-JP", " カナ 世界ａ\r"], ["EUC-JP", ""], ["EUC-JP", ""], ["EUC-JP", "end "]], [["EUC-JP", " "], ["EUC-JP", "カ"], ["EUC-JP", "ナ"], ["EUC-JP", " 世界ａ\r\n\n\nend \n"]], [["EUC-JP", ""], ["EUC-JP", " "], ["EUC-JP", "カナ 世界ａ\r\n\n\nend \n"]], [["EUC-JP", " カナ 世界ａ\r\n\n\nend"], ["EUC-JP", " "], ["EUC-JP", "\n"]]]]
      [:"EUC-JP_insert", [["EUC-JP", " カ<>ナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", "> カナ 世界ａ\r\n\n\nend \n"], ["EUC-JP", " カナ 世界ａ\r\n\n\nend \n!"], true]]
      [:"EUC-JP_each_grapheme", [["EUC-JP", " "], ["EUC-JP", "カ"], ["EUC-JP", "ナ"], ["EUC-JP", " "]]]
      [:"EUC-JP_scrub", [["EUC-JP", " カナ 世界ａ\r\n\n\nend \n"], 22]]
      [:"EUC-JP_unicode_normalize", Encoding::CompatibilityError, "Unicode Normalization not appropriate for EUC-JP"]
      [:"EUC-JP_encode", [26, 32]]
      [:Shift_JIS_length, [16, 20, 16, [["Shift_JIS", " "], ["Shift_JIS", "カ"], ["Shift_JIS", "ナ"]], true, false]]
      [:Shift_JIS_reverse, [["Shift_JIS", "\n dne\n\n\n\r\\表ソ ナカ "], ["Shift_JIS", "ナ ソ"], ["Shift_JIS", "nd \n"], ["Shift_JIS", "カ"], true]]
      [:Shift_JIS_justify, [["Shift_JIS", "***カナ ソ表\\\r\n\n\nend****"], ["Shift_JIS", "カナ ソ表\\\r\n\n\nend     "], ["Shift_JIS", "-=-=-カナ ソ表\\\r\n\n\nend"]]]
      [:Shift_JIS_strip, [["Shift_JIS", "カナ ソ表\\\r\n\n\nend"], ["Shift_JIS", "カナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend "], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend "], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend "], ["Shift_JIS", " カナ ソ表\\\r\n\n\nen"]]]
      [:Shift_JIS_lines, [[["Shift_JIS", " カナ ソ表\\\r\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "end \n"]], [["Shift_JIS", " カナ ソ表\\"], ["Shift_JIS", ""], ["Shift_JIS", ""], ["Shift_JIS", "end "]], [["Shift_JIS", " カナ ソ表\\\r\n\n"], ["Shift_JIS", "end \n"]], [["Shift_JIS", " カナ ソ表\\"], ["Shift_JIS", "end \n"]], [["Shift_JIS", " カナ ソ表\\\r\n\n\ne"], ["Shift_JIS", "nd \n"]]]]
      [:Shift_JIS_lines_default, [4, [["Shift_JIS", " カナ ソ表\\\r\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "\n"], ["Shift_JIS", "end \n"]]]]
      [:Shift_JIS_count, [1, 3, ["Shift_JIS", "カナソ表\\\r\n\n\nend\n"], ["Shift_JIS", " カナ ソ表\\\r\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\nend \n"]]]
      [:Shift_JIS_tr, [["Shift_JIS", " カナ ソ表\\\r\n\n\nfoe \n"], ["Shift_JIS", " カナ ソ表\\\r|end |"], ["Shift_JIS", "end"]]]
      [:Shift_JIS_case, [["Shift_JIS", " カナ ソ表\\\r\n\n\nEND \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nEND \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nEND \n"]]]
      [:Shift_JIS_casecmp, [0, true, true, true]]
      [:Shift_JIS_succ, [["Shift_JIS", "ba"], ["Shift_JIS", "aaa"], ["Shift_JIS", "カナ ソ表\\\r\n\n\nene"]]]
      [:Shift_JIS_inspect, [["UTF-8", "\" \\x{834A}\\x{8369} \\x{835C}\\x{955C}\\\\\\r\\n\\n\\nend \\n\""], ["Shift_JIS", "\" \\x83J\\x83i \\x83\\\\\\x95\\\\\\\\\\r\\n\\n\\nend \\n\""]]]
      [:Shift_JIS_codepoints, [32, [32, 33610, 33641, 32, 33628, 38236, 92, 13], 1457, 131, true]]
      [:Shift_JIS_index, [11, 11, 15, true, true, true]]
      [:Shift_JIS_split, [[["Shift_JIS", "カナ"], ["Shift_JIS", "ソ表\\"], ["Shift_JIS", "end"]], [["Shift_JIS", " カナ ソ表\\\r"], ["Shift_JIS", ""], ["Shift_JIS", ""], ["Shift_JIS", "end "]], [["Shift_JIS", " "], ["Shift_JIS", "カ"], ["Shift_JIS", "ナ"], ["Shift_JIS", " ソ表\\\r\n\n\nend \n"]], [["Shift_JIS", ""], ["Shift_JIS", " "], ["Shift_JIS", "カナ ソ表\\\r\n\n\nend \n"]], [["Shift_JIS", " カナ ソ表\\\r\n\n\nend"], ["Shift_JIS", " "], ["Shift_JIS", "\n"]]]]
      [:Shift_JIS_insert, [["Shift_JIS", " カ<>ナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", "> カナ ソ表\\\r\n\n\nend \n"], ["Shift_JIS", " カナ ソ表\\\r\n\n\nend \n!"], true]]
      [:Shift_JIS_each_grapheme, [["Shift_JIS", " "], ["Shift_JIS", "カ"], ["Shift_JIS", "ナ"], ["Shift_JIS", " "]]]
      [:Shift_JIS_scrub, [["Shift_JIS", " カナ ソ表\\\r\n\n\nend \n"], 21]]
      [:Shift_JIS_unicode_normalize, Encoding::CompatibilityError, "Unicode Normalization not appropriate for Shift_JIS"]
      [:Shift_JIS_encode, [24, 32]]
      [:Big5_length, [15, 19, 15, [["Big5", " "], ["Big5", "中"], ["Big5", "文"]], true, false]]
      [:Big5_reverse, [["Big5", "\n dne\n\n\n\r試測 文中 "], ["Big5", "文 測"], ["Big5", "nd \n"], ["Big5", "中"], false]]
      [:Big5_justify, [["Big5", "****中文 測試\r\n\n\nend****"], ["Big5", "中文 測試\r\n\n\nend      "], ["Big5", "-=-=-=中文 測試\r\n\n\nend"]]]
      [:Big5_strip, [["Big5", "中文 測試\r\n\n\nend"], ["Big5", "中文 測試\r\n\n\nend \n"], ["Big5", " 中文 測試\r\n\n\nend"], ["Big5", " 中文 測試\r\n\n\nend "], ["Big5", " 中文 測試\r\n\n\nend "], ["Big5", " 中文 測試\r\n\n\nend "], ["Big5", " 中文 測試\r\n\n\nen"]]]
      [:Big5_lines, [[["Big5", " 中文 測試\r\n"], ["Big5", "\n"], ["Big5", "\n"], ["Big5", "end \n"]], [["Big5", " 中文 測試"], ["Big5", ""], ["Big5", ""], ["Big5", "end "]], [["Big5", " 中文 測試\r\n\n"], ["Big5", "end \n"]], [["Big5", " 中文 測試"], ["Big5", "end \n"]], [["Big5", " 中文 測試\r\n\n\ne"], ["Big5", "nd \n"]]]]
      [:Big5_lines_default, [4, [["Big5", " 中文 測試\r\n"], ["Big5", "\n"], ["Big5", "\n"], ["Big5", "end \n"]]]]
      [:Big5_count, [1, 3, ["Big5", "中文測試\r\n\n\nend\n"], ["Big5", " 中文 測試\r\nend \n"], ["Big5", " 中文 測試\r\nend \n"]]]
      [:Big5_tr, [["Big5", " 中文 測試\r\n\n\nfoe \n"], ["Big5", " 中文 測試\r|end |"], ["Big5", "end"]]]
      [:Big5_case, [["Big5", " 中文 測試\r\n\n\nEND \n"], ["Big5", " 中文 測試\r\n\n\nend \n"], ["Big5", " 中文 測試\r\n\n\nEND \n"], ["Big5", " 中文 測試\r\n\n\nend \n"], ["Big5", " 中文 測試\r\n\n\nEND \n"]]]
      [:Big5_casecmp, [0, true, true, true]]
      [:Big5_succ, [["Big5", "ba"], ["Big5", "aaa"], ["Big5", "中文 測試\r\n\n\nene"]]]
      [:Big5_inspect, [["UTF-8", "\" \\x{A4A4}\\x{A4E5} \\x{B4FA}\\x{B8D5}\\r\\n\\n\\nend \\n\""], ["Big5", "\" \\xA4\\xA4\\xA4\\xE5 \\xB4\\xFA\\xB8\\xD5\\r\\n\\n\\nend \\n\""]]]
      [:Big5_codepoints, [32, [32, 42148, 42213, 32, 46330, 47317, 13, 10], 2008, 164, true]]
      [:Big5_index, [10, 10, 14, true, true, true]]
      [:Big5_split, [[["Big5", "中文"], ["Big5", "測試"], ["Big5", "end"]], [["Big5", " 中文 測試\r"], ["Big5", ""], ["Big5", ""], ["Big5", "end "]], [["Big5", " "], ["Big5", "中"], ["Big5", "文"], ["Big5", " 測試\r\n\n\nend \n"]], [["Big5", ""], ["Big5", " "], ["Big5", "中文 測試\r\n\n\nend \n"]], [["Big5", " 中文 測試\r\n\n\nend"], ["Big5", " "], ["Big5", "\n"]]]]
      [:Big5_insert, [["Big5", " 中<>文 測試\r\n\n\nend \n"], ["Big5", "> 中文 測試\r\n\n\nend \n"], ["Big5", " 中文 測試\r\n\n\nend \n!"], true]]
      [:Big5_each_grapheme, [["Big5", " "], ["Big5", "中"], ["Big5", "文"], ["Big5", " "]]]
      [:Big5_scrub, [["Big5", " 中文 測試\r\n\n\nend \n"], 20]]
      [:Big5_unicode_normalize, Encoding::CompatibilityError, "Unicode Normalization not appropriate for Big5"]
      [:Big5_encode, [23, 30]]
      [:GBK_length, [15, 19, 15, [["GBK", " "], ["GBK", "中"], ["GBK", "文"]], true, false]]
      [:GBK_reverse, [["GBK", "\n dne\n\n\n\r试测 文中 "], ["GBK", "文 测"], ["GBK", "nd \n"], ["GBK", "中"], false]]
      [:GBK_justify, [["GBK", "****中文 测试\r\n\n\nend****"], ["GBK", "中文 测试\r\n\n\nend      "], ["GBK", "-=-=-=中文 测试\r\n\n\nend"]]]
      [:GBK_strip, [["GBK", "中文 测试\r\n\n\nend"], ["GBK", "中文 测试\r\n\n\nend \n"], ["GBK", " 中文 测试\r\n\n\nend"], ["GBK", " 中文 测试\r\n\n\nend "], ["GBK", " 中文 测试\r\n\n\nend "], ["GBK", " 中文 测试\r\n\n\nend "], ["GBK", " 中文 测试\r\n\n\nen"]]]
      [:GBK_lines, [[["GBK", " 中文 测试\r\n"], ["GBK", "\n"], ["GBK", "\n"], ["GBK", "end \n"]], [["GBK", " 中文 测试"], ["GBK", ""], ["GBK", ""], ["GBK", "end "]], [["GBK", " 中文 测试\r\n\n"], ["GBK", "end \n"]], [["GBK", " 中文 测试"], ["GBK", "end \n"]], [["GBK", " 中文 测试\r\n\n\ne"], ["GBK", "nd \n"]]]]
      [:GBK_lines_default, [4, [["GBK", " 中文 测试\r\n"], ["GBK", "\n"], ["GBK", "\n"], ["GBK", "end \n"]]]]
      [:GBK_count, [1, 3, ["GBK", "中文测试\r\n\n\nend\n"], ["GBK", " 中文 测试\r\nend \n"], ["GBK", " 中文 测试\r\nend \n"]]]
      [:GBK_tr, [["GBK", " 中文 测试\r\n\n\nfoe \n"], ["GBK", " 中文 测试\r|end |"], ["GBK", "end"]]]
      [:GBK_case, [["GBK", " 中文 测试\r\n\n\nEND \n"], ["GBK", " 中文 测试\r\n\n\nend \n"], ["GBK", " 中文 测试\r\n\n\nEND \n"], ["GBK", " 中文 测试\r\n\n\nend \n"], ["GBK", " 中文 测试\r\n\n\nEND \n"]]]
      [:GBK_casecmp, [0, true, true, true]]
      [:GBK_succ, [["GBK", "ba"], ["GBK", "aaa"], ["GBK", "中文 测试\r\n\n\nene"]]]
      [:GBK_inspect, [["UTF-8", "\" \\x{D6D0}\\x{CEC4} \\x{B2E2}\\x{CAD4}\\r\\n\\n\\nend \\n\""], ["GBK", "\" \\xD6\\xD0\\xCE\\xC4 \\xB2\\xE2\\xCA\\xD4\\r\\n\\n\\nend \\n\""]]]
      [:GBK_codepoints, [32, [32, 54992, 52932, 32, 45794, 51924, 13, 10], 2102, 214, true]]
      [:GBK_index, [10, 10, 14, true, true, true]]
      [:GBK_split, [[["GBK", "中文"], ["GBK", "测试"], ["GBK", "end"]], [["GBK", " 中文 测试\r"], ["GBK", ""], ["GBK", ""], ["GBK", "end "]], [["GBK", " "], ["GBK", "中"], ["GBK", "文"], ["GBK", " 测试\r\n\n\nend \n"]], [["GBK", ""], ["GBK", " "], ["GBK", "中文 测试\r\n\n\nend \n"]], [["GBK", " 中文 测试\r\n\n\nend"], ["GBK", " "], ["GBK", "\n"]]]]
      [:GBK_insert, [["GBK", " 中<>文 测试\r\n\n\nend \n"], ["GBK", "> 中文 测试\r\n\n\nend \n"], ["GBK", " 中文 测试\r\n\n\nend \n!"], true]]
      [:GBK_each_grapheme, [["GBK", " "], ["GBK", "中"], ["GBK", "文"], ["GBK", " "]]]
      [:GBK_scrub, [["GBK", " 中文 测试\r\n\n\nend \n"], 20]]
      [:GBK_unicode_normalize, Encoding::CompatibilityError, "Unicode Normalization not appropriate for GBK"]
      [:GBK_encode, [23, 30]]
      [:"EUC-KR_length", [15, 19, 15, [["EUC-KR", " "], ["EUC-KR", "한"], ["EUC-KR", "국"]], true, false]]
      [:"EUC-KR_reverse", [["EUC-KR", "\n dne\n\n\n\r계세 국한 "], ["EUC-KR", "국 세"], ["EUC-KR", "nd \n"], ["EUC-KR", "한"], false]]
      [:"EUC-KR_justify", [["EUC-KR", "****한국 세계\r\n\n\nend****"], ["EUC-KR", "한국 세계\r\n\n\nend      "], ["EUC-KR", "-=-=-=한국 세계\r\n\n\nend"]]]
      [:"EUC-KR_strip", [["EUC-KR", "한국 세계\r\n\n\nend"], ["EUC-KR", "한국 세계\r\n\n\nend \n"], ["EUC-KR", " 한국 세계\r\n\n\nend"], ["EUC-KR", " 한국 세계\r\n\n\nend "], ["EUC-KR", " 한국 세계\r\n\n\nend "], ["EUC-KR", " 한국 세계\r\n\n\nend "], ["EUC-KR", " 한국 세계\r\n\n\nen"]]]
      [:"EUC-KR_lines", [[["EUC-KR", " 한국 세계\r\n"], ["EUC-KR", "\n"], ["EUC-KR", "\n"], ["EUC-KR", "end \n"]], [["EUC-KR", " 한국 세계"], ["EUC-KR", ""], ["EUC-KR", ""], ["EUC-KR", "end "]], [["EUC-KR", " 한국 세계\r\n\n"], ["EUC-KR", "end \n"]], [["EUC-KR", " 한국 세계"], ["EUC-KR", "end \n"]], [["EUC-KR", " 한국 세계\r\n\n\ne"], ["EUC-KR", "nd \n"]]]]
      [:"EUC-KR_lines_default", [4, [["EUC-KR", " 한국 세계\r\n"], ["EUC-KR", "\n"], ["EUC-KR", "\n"], ["EUC-KR", "end \n"]]]]
      [:"EUC-KR_count", [1, 3, ["EUC-KR", "한국세계\r\n\n\nend\n"], ["EUC-KR", " 한국 세계\r\nend \n"], ["EUC-KR", " 한국 세계\r\nend \n"]]]
      [:"EUC-KR_tr", [["EUC-KR", " 한국 세계\r\n\n\nfoe \n"], ["EUC-KR", " 한국 세계\r|end |"], ["EUC-KR", "end"]]]
      [:"EUC-KR_case", [["EUC-KR", " 한국 세계\r\n\n\nEND \n"], ["EUC-KR", " 한국 세계\r\n\n\nend \n"], ["EUC-KR", " 한국 세계\r\n\n\nEND \n"], ["EUC-KR", " 한국 세계\r\n\n\nend \n"], ["EUC-KR", " 한국 세계\r\n\n\nEND \n"]]]
      [:"EUC-KR_casecmp", [0, true, true, true]]
      [:"EUC-KR_succ", [["EUC-KR", "ba"], ["EUC-KR", "aaa"], ["EUC-KR", "한국 세계\r\n\n\nene"]]]
      [:"EUC-KR_inspect", [["UTF-8", "\" \\x{C7D1}\\x{B1B9} \\x{BCBC}\\x{B0E8}\\r\\n\\n\\nend \\n\""], ["EUC-KR", "\" \\xC7\\xD1\\xB1\\xB9 \\xBC\\xBC\\xB0\\xE8\\r\\n\\n\\nend \\n\""]]]
      [:"EUC-KR_codepoints", [32, [32, 51153, 45497, 32, 48316, 45288, 13, 10], 2014, 199, true]]
      [:"EUC-KR_index", [10, 10, 14, true, true, true]]
      [:"EUC-KR_split", [[["EUC-KR", "한국"], ["EUC-KR", "세계"], ["EUC-KR", "end"]], [["EUC-KR", " 한국 세계\r"], ["EUC-KR", ""], ["EUC-KR", ""], ["EUC-KR", "end "]], [["EUC-KR", " "], ["EUC-KR", "한"], ["EUC-KR", "국"], ["EUC-KR", " 세계\r\n\n\nend \n"]], [["EUC-KR", ""], ["EUC-KR", " "], ["EUC-KR", "한국 세계\r\n\n\nend \n"]], [["EUC-KR", " 한국 세계\r\n\n\nend"], ["EUC-KR", " "], ["EUC-KR", "\n"]]]]
      [:"EUC-KR_insert", [["EUC-KR", " 한<>국 세계\r\n\n\nend \n"], ["EUC-KR", "> 한국 세계\r\n\n\nend \n"], ["EUC-KR", " 한국 세계\r\n\n\nend \n!"], true]]
      [:"EUC-KR_each_grapheme", [["EUC-KR", " "], ["EUC-KR", "한"], ["EUC-KR", "국"], ["EUC-KR", " "]]]
      [:"EUC-KR_scrub", [["EUC-KR", " 한국 세계\r\n\n\nend \n"], 20]]
      [:"EUC-KR_unicode_normalize", Encoding::CompatibilityError, "Unicode Normalization not appropriate for EUC-KR"]
      [:"EUC-KR_encode", [23, 30]]
      [:"ISO-8859-7_length", [17, 17, 17, [["ISO-8859-7", " "], ["ISO-8859-7", "Κ"], ["ISO-8859-7", "α"]], true, false]]
      [:"ISO-8859-7_reverse", [["ISO-8859-7", "\n dne\n\n\n\rΒΑ ηλαΚ "], ["ISO-8859-7", "αλη"], ["ISO-8859-7", "nd \n"], ["ISO-8859-7", "Κ"], true]]
      [:"ISO-8859-7_justify", [["ISO-8859-7", "***Καλη ΑΒ\r\n\n\nend***"], ["ISO-8859-7", "Καλη ΑΒ\r\n\n\nend    "], ["ISO-8859-7", "-=-=Καλη ΑΒ\r\n\n\nend"]]]
      [:"ISO-8859-7_strip", [["ISO-8859-7", "Καλη ΑΒ\r\n\n\nend"], ["ISO-8859-7", "Καλη ΑΒ\r\n\n\nend \n"], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend"], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend "], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend "], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend "], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nen"]]]
      [:"ISO-8859-7_lines", [[["ISO-8859-7", " Καλη ΑΒ\r\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "end \n"]], [["ISO-8859-7", " Καλη ΑΒ"], ["ISO-8859-7", ""], ["ISO-8859-7", ""], ["ISO-8859-7", "end "]], [["ISO-8859-7", " Καλη ΑΒ\r\n\n"], ["ISO-8859-7", "end \n"]], [["ISO-8859-7", " Καλη ΑΒ"], ["ISO-8859-7", "end \n"]], [["ISO-8859-7", " Καλη ΑΒ\r\n\n\ne"], ["ISO-8859-7", "nd \n"]]]]
      [:"ISO-8859-7_lines_default", [4, [["ISO-8859-7", " Καλη ΑΒ\r\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "\n"], ["ISO-8859-7", "end \n"]]]]
      [:"ISO-8859-7_count", [1, 3, ["ISO-8859-7", "ΚαληΑΒ\r\n\n\nend\n"], ["ISO-8859-7", " Καλη ΑΒ\r\nend \n"], ["ISO-8859-7", " Καλη ΑΒ\r\nend \n"]]]
      [:"ISO-8859-7_tr", [["ISO-8859-7", " Καλη ΑΒ\r\n\n\nfoe \n"], ["ISO-8859-7", " Καλη ΑΒ\r|end |"], ["ISO-8859-7", "end"]]]
      [:"ISO-8859-7_case", [["ISO-8859-7", " ΚΑΛΗ ΑΒ\r\n\n\nEND \n"], ["ISO-8859-7", " καλη αβ\r\n\n\nend \n"], ["ISO-8859-7", " κΑΛΗ αβ\r\n\n\nEND \n"], ["ISO-8859-7", " καλη αβ\r\n\n\nend \n"], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nEND \n"]]]
      [:"ISO-8859-7_casecmp", [1, true, true, true]]
      [:"ISO-8859-7_succ", [["ISO-8859-7", "ba"], ["ISO-8859-7", "aaa"], ["ISO-8859-7", "Καλη ΑΒ\r\n\n\nene"]]]
      [:"ISO-8859-7_inspect", [["UTF-8", "\" \\xCA\\xE1\\xEB\\xE7 \\xC1\\xC2\\r\\n\\n\\nend \\n\""], ["ISO-8859-7", "\" \\xCA\\xE1\\xEB\\xE7 \\xC1\\xC2\\r\\n\\n\\nend \\n\""]]]
      [:"ISO-8859-7_codepoints", [32, [32, 202, 225, 235, 231, 32, 193, 194], 1740, 202, true]]
      [:"ISO-8859-7_index", [12, 12, 12, true, true, true]]
      [:"ISO-8859-7_split", [[["ISO-8859-7", "Καλη"], ["ISO-8859-7", "ΑΒ"], ["ISO-8859-7", "end"]], [["ISO-8859-7", " Καλη ΑΒ\r"], ["ISO-8859-7", ""], ["ISO-8859-7", ""], ["ISO-8859-7", "end "]], [["ISO-8859-7", " "], ["ISO-8859-7", "Κ"], ["ISO-8859-7", "α"], ["ISO-8859-7", "λη ΑΒ\r\n\n\nend \n"]], [["ISO-8859-7", ""], ["ISO-8859-7", " "], ["ISO-8859-7", "Καλη ΑΒ\r\n\n\nend \n"]], [["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend"], ["ISO-8859-7", " "], ["ISO-8859-7", "\n"]]]]
      [:"ISO-8859-7_insert", [["ISO-8859-7", " Κ<>αλη ΑΒ\r\n\n\nend \n"], ["ISO-8859-7", "> Καλη ΑΒ\r\n\n\nend \n"], ["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend \n!"], true]]
      [:"ISO-8859-7_each_grapheme", [["ISO-8859-7", " "], ["ISO-8859-7", "Κ"], ["ISO-8859-7", "α"], ["ISO-8859-7", "λ"]]]
      [:"ISO-8859-7_scrub", [["ISO-8859-7", " Καλη ΑΒ\r\n\n\nend \n"], 18]]
      [:"ISO-8859-7_unicode_normalize", Encoding::CompatibilityError, "Unicode Normalization not appropriate for ISO-8859-7"]
      [:"ISO-8859-7_encode", [23, 34]]
      [:"UTF-16LE_tail_2020", ["UTF-8", "a†"]]
      [:"UTF-16LE_tail_2020_replaced", [["UTF-8", "a†"], true, 2, 4, [2, 2]]]
      [:"UTF-16LE_tail_20", [["ASCII-8BIT", "incomplete \" \" on UTF-16LE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16LE_tail_20_replaced", [["UTF-8", "a�"], false, 2, 4, [2, 1]]]
      [:"UTF-16LE_tail_0020", ["UTF-8", "a "]]
      [:"UTF-16LE_tail_0020_replaced", [["UTF-8", "a "], true, 2, 4, [2, 2]]]
      [:"UTF-16LE_tail_000020", [["ASCII-8BIT", "incomplete \" \" on UTF-16LE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16LE_tail_000020_replaced", [["UTF-8", "a\u0000�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16LE_tail_00112020", ["UTF-8", "aᄀ†"]]
      [:"UTF-16LE_tail_00112020_replaced", [["UTF-8", "aᄀ†"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-16LE_tail_202020", [["ASCII-8BIT", "incomplete \" \" on UTF-16LE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16LE_tail_202020_replaced", [["UTF-8", "a†�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16LE_tail_d8000000", ["UTF-8", "aØ\u0000"]]
      [:"UTF-16LE_tail_d8000000_replaced", [["UTF-8", "aØ\u0000"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-16LE_tail_00d80000", [["ASCII-8BIT", "\"\\x00\\xD8\" followed by \"\\x00\\x00\" on UTF-16LE"], ["ASCII-8BIT", "\x00\xD8"], ["ASCII-8BIT", "\x00\x00"], false]]
      [:"UTF-16LE_tail_00d80000_replaced", [["UTF-8", "a�\u0000"], false, 3, 6, [2, 2, 2]]]
      [:"UTF-16LE_tail_dc0061", [["ASCII-8BIT", "incomplete \"a\" on UTF-16LE"], ["ASCII-8BIT", "a"], nil, true]]
      [:"UTF-16LE_tail_dc0061_replaced", [["UTF-8", "aÜ�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16LE_tail_00dc61", [["ASCII-8BIT", "\"\\x00\\xDC\" on UTF-16LE"], ["ASCII-8BIT", "\x00\xDC"], nil, false]]
      [:"UTF-16LE_tail_00dc61_replaced", [["UTF-8", "a��"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16LE_tail_00d800dc", ["UTF-8", "a𐀀"]]
      [:"UTF-16LE_tail_00d800dc_replaced", [["UTF-8", "a𐀀"], true, 2, 6, [2, 4]]]
      [:"UTF-16BE_tail_2020", ["UTF-8", "a†"]]
      [:"UTF-16BE_tail_2020_replaced", [["UTF-8", "a†"], true, 2, 4, [2, 2]]]
      [:"UTF-16BE_tail_20", [["ASCII-8BIT", "incomplete \" \" on UTF-16BE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16BE_tail_20_replaced", [["UTF-8", "a�"], false, 2, 4, [2, 1]]]
      [:"UTF-16BE_tail_0020", ["UTF-8", "a "]]
      [:"UTF-16BE_tail_0020_replaced", [["UTF-8", "a "], true, 2, 4, [2, 2]]]
      [:"UTF-16BE_tail_000020", [["ASCII-8BIT", "incomplete \" \" on UTF-16BE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16BE_tail_000020_replaced", [["UTF-8", "a\u0000�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16BE_tail_00112020", ["UTF-8", "a\u0011†"]]
      [:"UTF-16BE_tail_00112020_replaced", [["UTF-8", "a\u0011†"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-16BE_tail_202020", [["ASCII-8BIT", "incomplete \" \" on UTF-16BE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-16BE_tail_202020_replaced", [["UTF-8", "a†�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16BE_tail_d8000000", [["ASCII-8BIT", "\"\\xD8\\x00\" followed by \"\\x00\" on UTF-16BE"], ["ASCII-8BIT", "\xD8\x00"], ["ASCII-8BIT", "\x00"], false]]
      [:"UTF-16BE_tail_d8000000_replaced", [["UTF-8", "a�\u0000"], false, 3, 6, [2, 2, 2]]]
      [:"UTF-16BE_tail_00d80000", ["UTF-8", "aØ\u0000"]]
      [:"UTF-16BE_tail_00d80000_replaced", [["UTF-8", "aØ\u0000"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-16BE_tail_dc0061", [["ASCII-8BIT", "\"\\xDC\\x00\" on UTF-16BE"], ["ASCII-8BIT", "\xDC\x00"], nil, false]]
      [:"UTF-16BE_tail_dc0061_replaced", [["UTF-8", "a��"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16BE_tail_00dc61", [["ASCII-8BIT", "incomplete \"a\" on UTF-16BE"], ["ASCII-8BIT", "a"], nil, true]]
      [:"UTF-16BE_tail_00dc61_replaced", [["UTF-8", "aÜ�"], false, 3, 6, [2, 2, 1]]]
      [:"UTF-16BE_tail_00d800dc", ["UTF-8", "aØÜ"]]
      [:"UTF-16BE_tail_00d800dc_replaced", [["UTF-8", "aØÜ"], true, 3, 6, [2, 2, 2]]]
      [:"UTF-32LE_tail_2020", [["ASCII-8BIT", "incomplete \"  \" on UTF-32LE"], ["ASCII-8BIT", "  "], nil, true]]
      [:"UTF-32LE_tail_2020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 2]]]
      [:"UTF-32LE_tail_20", [["ASCII-8BIT", "incomplete \" \" on UTF-32LE"], ["ASCII-8BIT", " "], nil, true]]
      [:"UTF-32LE_tail_20_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 1]]]
      [:"UTF-32LE_tail_0020", [["ASCII-8BIT", "incomplete \"\\x00 \" on UTF-32LE"], ["ASCII-8BIT", "\x00 "], nil, true]]
      [:"UTF-32LE_tail_0020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 2]]]
      [:"UTF-32LE_tail_000020", [["ASCII-8BIT", "\"\\x00\\x00 \" on UTF-32LE"], ["ASCII-8BIT", "\x00\x00 "], nil, false]]
      [:"UTF-32LE_tail_000020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32LE_tail_00112020", [["ASCII-8BIT", "\"\\x00\\x11  \" on UTF-32LE"], ["ASCII-8BIT", "\x00\x11  "], nil, false]]
      [:"UTF-32LE_tail_00112020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32LE_tail_202020", [["ASCII-8BIT", "\"   \" on UTF-32LE"], ["ASCII-8BIT", "   "], nil, false]]
      [:"UTF-32LE_tail_202020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32LE_tail_d8000000", ["UTF-8", "aØ"]]
      [:"UTF-32LE_tail_d8000000_replaced", [["UTF-8", "aØ"], true, 2, 8, [4, 4]]]
      [:"UTF-32LE_tail_00d80000", [["ASCII-8BIT", "\"\\x00\\xD8\\x00\\x00\" on UTF-32LE"], ["ASCII-8BIT", "\x00\xD8\x00\x00"], nil, false]]
      [:"UTF-32LE_tail_00d80000_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32LE_tail_dc0061", [["ASCII-8BIT", "\"\\xDC\\x00a\" on UTF-32LE"], ["ASCII-8BIT", "\xDC\x00a"], nil, false]]
      [:"UTF-32LE_tail_dc0061_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32LE_tail_00dc61", [["ASCII-8BIT", "\"\\x00\\xDCa\" on UTF-32LE"], ["ASCII-8BIT", "\x00\xDCa"], nil, false]]
      [:"UTF-32LE_tail_00dc61_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32LE_tail_00d800dc", [["ASCII-8BIT", "\"\\x00\\xD8\\x00\\xDC\" on UTF-32LE"], ["ASCII-8BIT", "\x00\xD8\x00\xDC"], nil, false]]
      [:"UTF-32LE_tail_00d800dc_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32BE_tail_2020", [["ASCII-8BIT", "\"  \" on UTF-32BE"], ["ASCII-8BIT", "  "], nil, false]]
      [:"UTF-32BE_tail_2020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 2]]]
      [:"UTF-32BE_tail_20", [["ASCII-8BIT", "\" \" on UTF-32BE"], ["ASCII-8BIT", " "], nil, false]]
      [:"UTF-32BE_tail_20_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 1]]]
      [:"UTF-32BE_tail_0020", [["ASCII-8BIT", "\"\\x00 \" on UTF-32BE"], ["ASCII-8BIT", "\x00 "], nil, false]]
      [:"UTF-32BE_tail_0020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 2]]]
      [:"UTF-32BE_tail_000020", [["ASCII-8BIT", "incomplete \"\\x00\\x00 \" on UTF-32BE"], ["ASCII-8BIT", "\x00\x00 "], nil, true]]
      [:"UTF-32BE_tail_000020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32BE_tail_00112020", [["ASCII-8BIT", "\"\\x00\\x11  \" on UTF-32BE"], ["ASCII-8BIT", "\x00\x11  "], nil, false]]
      [:"UTF-32BE_tail_00112020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32BE_tail_202020", [["ASCII-8BIT", "\"   \" on UTF-32BE"], ["ASCII-8BIT", "   "], nil, false]]
      [:"UTF-32BE_tail_202020_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32BE_tail_d8000000", [["ASCII-8BIT", "\"\\xD8\\x00\\x00\\x00\" on UTF-32BE"], ["ASCII-8BIT", "\xD8\x00\x00\x00"], nil, false]]
      [:"UTF-32BE_tail_d8000000_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32BE_tail_00d80000", [["ASCII-8BIT", "\"\\x00\\xD8\\x00\\x00\" on UTF-32BE"], ["ASCII-8BIT", "\x00\xD8\x00\x00"], nil, false]]
      [:"UTF-32BE_tail_00d80000_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
      [:"UTF-32BE_tail_dc0061", [["ASCII-8BIT", "\"\\xDC\\x00a\" on UTF-32BE"], ["ASCII-8BIT", "\xDC\x00a"], nil, false]]
      [:"UTF-32BE_tail_dc0061_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32BE_tail_00dc61", [["ASCII-8BIT", "\"\\x00\\xDCa\" on UTF-32BE"], ["ASCII-8BIT", "\x00\xDCa"], nil, false]]
      [:"UTF-32BE_tail_00dc61_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 3]]]
      [:"UTF-32BE_tail_00d800dc", [["ASCII-8BIT", "\"\\x00\\xD8\\x00\\xDC\" on UTF-32BE"], ["ASCII-8BIT", "\x00\xD8\x00\xDC"], nil, false]]
      [:"UTF-32BE_tail_00d800dc_replaced", [["UTF-8", "a�"], false, 2, 8, [4, 4]]]
    OUT
  end

  it "string multiply overflow" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # String#* overflow raises "string size too big"; ruby 4.0.6 says "argument
      # too big".
      #
      # Issue #836: String * <huge> raises ArgumentError instead of
      # segfaulting (the implicit malloc-NULL + memcpy chain).
      #
      # The receiver is 1000 bytes, not 1, so `len * times` overflows the size check
      # and raises before anything is allocated. A 1-byte receiver takes the ALLOCATE
      # path instead: ruby 4.0.6 answers NoMemoryError there, and which of the two
      # NoMemoryError messages it picks depends on the machine -- a golden that
      # travels has to stay on the arithmetic side of the guard.
      begin
        puts ("x" * 1000) * (1 << 60)
      rescue ArgumentError => e
        puts "huge: " + e.message
      end
      begin
        puts "x" * -1
      rescue ArgumentError => e
        puts "neg: " + e.message
      end
      puts "ab" * 3
      puts ("hi" * 0).inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      huge: argument too big
      neg: negative argument
      ababab
      ""
    OUT
  end

  it "string mutation plus" do
    result = ze0(<<~'RUBY')
      # Unary +@ on a string returns a mutable copy (so a literal can be built up),
      # and concat / []= mutate a mutable string local in place (statement position,
      # like the existing <</upcase!). -@ returns the string unchanged.

      # +"..." yields a mutable string; appends build it up
      s = +"abc"
      s << "d"
      p s
      s.concat("ef")
      p s
      s.concat("g", "h", "i")
      p s
      s.concat(33)            # an Integer appends its codepoint
      p s

      # build-in-a-loop starting from +""
      acc = +""
      3.times { |i| acc << i.to_s }
      p acc

      # in-place bang methods on a +string
      u = +"Hello"
      u.upcase!
      p u
      u.reverse!
      p u

      # []= single-index assignment (negative index counts from the end; the value
      # may be longer than one character)
      t = +"abcde"
      t[0] = "X"
      p t
      t[-1] = "Z"
      p t
      t[2] = "YY"
      p t
      # index == length appends (matches CRuby); out-of-range raises IndexError
      # carrying the original index
      g = +"abc"
      g[3] = "d"
      p g
      oob = +"abc"
      begin; oob[5] = "x"; rescue IndexError => e; puts "#{e.class}: #{e.message}"; end
      begin; oob[-4] = "x"; rescue IndexError => e; puts "#{e.class}: #{e.message}"; end

      # +@ / -@ as plain values
      p(+"plus")
      p(-"minus")

      # concat / []= also work on a dup'd string
      d = "orig".dup
      d.concat("!")
      d[0] = "O"
      p d
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "abcd"
      "abcdef"
      "abcdefghi"
      "abcdefghi!"
      "012"
      "HELLO"
      "OLLEH"
      "Xbcde"
      "XbcdZ"
      "XbYYdZ"
      "abcd"
      IndexError: index 5 out of string
      IndexError: index -4 out of string
      "plus"
      "minus"
      "Orig!"
    OUT
  end

  it "string new" do
    result = ze0(<<~'RUBY')
      # `String.new` builds a fresh, mutable String. With no argument it is an empty
      # ASCII-8BIT buffer; given a source string it copies that string's contents and
      # encoding, and an `encoding:` keyword overrides the result's encoding.
      p String.new                              # ""
      p String.new.encoding.name                # "ASCII-8BIT"

      p String.new("hello")                     # "hello"
      p String.new("hello").encoding.name       # "UTF-8"

      forced = String.new("bytes", encoding: "ASCII-8BIT")
      p forced.encoding.name                    # "ASCII-8BIT"

      # The copy is independent of its source.
      src = "abc"
      copy = String.new(src)
      copy << "d"
      p src                                     # "abc"
      p copy                                    # "abcd"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ""
      "ASCII-8BIT"
      "hello"
      "UTF-8"
      "ASCII-8BIT"
      "abc"
      "abcd"
    OUT
  end

  it "string new capacity" do
    result = ze0(<<~'RUBY')
      # The capacity: and encoding keyword arguments to String.new are hints that do
      # not change the value -- the content is the leading positional argument. Spinel
      # previously dropped the content whenever a keyword argument was present,
      # returning "".
      def with_cap; String.new("x", capacity: 100); end
      p with_cap                     # "x"

      def only_cap; String.new(capacity: 50); end
      p only_cap                     # ""

      def plain; String.new("y"); end
      p plain                        # "y"

      def empty; String.new; end
      p empty                        # ""

      # The result is a mutable copy (a literal passed as content is not aliased).
      def mutable
        s = String.new("ab", capacity: 8)
        s << "c"
        s
      end
      p mutable                      # "abc"

      # Content from a variable, with a capacity hint.
      def from_var(seed); String.new(seed, capacity: 32); end
      p from_var("hello")            # "hello"
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "x"
      ""
      "y"
      ""
      "abc"
      "hello"
    OUT
  end

  it "string new poly arg" do
    result = ze0(<<~'RUBY')
      # String.new(x) where x is a poly value -- an element read out of a nested
      # array, rather than a flat array, a local, or a literal -- previously failed
      # C compilation: the argument reached sp_str_dup_external (which takes a
      # plain `const char *`) still boxed as an sp_RbVal.
      nested = [["class", "x"]]
      p String.new(nested[0][1])             # "x"

      # A flat array element already worked; keep it covered alongside the nested
      # case so a future regression shows up as a diff, not a silent narrowing.
      flat = ["class", "y"]
      p String.new(flat[1])                  # "y"

      # The copy is independent of the source.
      def mutable_from_nested(pairs)
        s = String.new(pairs[0][1])
        s << "!"
        s
      end
      p mutable_from_nested([["k", "z"]])    # "z!"
      p [["k", "z"]][0][1]                   # "z" (unchanged)

      # A poly value that cannot convert to a String still raises TypeError, same as
      # a plain String.new(nil) / String.new(5). A variable index into a
      # heterogeneous array keeps the element poly-typed rather than narrowed.
      mixed = [nil, 5, "z"]
      def poly_at(arr, i); arr[i]; end
      begin
        String.new(poly_at(mixed, 0))
      rescue TypeError => e
        puts e.message
      end
      begin
        String.new(poly_at(mixed, 1))
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "x"
      "y"
      "z!"
      "z"
      no implicit conversion of nil into String
      no implicit conversion of Integer into String
    OUT
  end

  it "string nil arg typeerror" do
    result = ze0(<<~'RUBY')
      # String methods that raise TypeError for nil arguments.
      # Issue #847 covered index(); this extends to rindex,
      # include?, start_with?, end_with?, and count.

      begin
        "hello".rindex(nil)
        puts "BUG rindex: no raise"
      rescue TypeError => e
        puts "rindex: #{e.message}"
      end

      begin
        "hello".include?(nil)
        puts "BUG include?: no raise"
      rescue TypeError => e
        puts "include?: #{e.message}"
      end

      begin
        "hello".start_with?(nil)
        puts "BUG start_with?: no raise"
      rescue TypeError => e
        puts "start_with?: #{e.message}"
      end

      begin
        "hello".end_with?(nil)
        puts "BUG end_with?: no raise"
      rescue TypeError => e
        puts "end_with?: #{e.message}"
      end

      begin
        "hello".count(nil)
        puts "BUG count: no raise"
      rescue TypeError => e
        puts "count: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      rindex: no implicit conversion of nil into String
      include?: no implicit conversion of nil into String
      start_with?: no implicit conversion of nil into String
      end_with?: no implicit conversion of nil into String
      count: no implicit conversion of nil into String
    OUT
  end

  it "string nil float batch" do
    result = ze0(<<~'RUBY')
      # String#bytesplice with Range / #append_as_bytes / #crypt,
      # Float#=== against non-float operands, and nil & / | / ^ boolean ops
      # on a receiver that widened to poly.

      # bytesplice: integer start/length and Range forms
      s = "hello"
      s.bytesplice(0, 2, "HE")
      p s
      s = "hello"
      s.bytesplice(1..3, "___")
      p s

      # append_as_bytes
      s = "abc"
      s.append_as_bytes("de")
      p s

      # crypt(3): real libc DES with a two-character salt
      p "hello".crypt("ab")
      p "password".crypt("sa")

      # Float#=== : nil / Rational / Complex / Integer / Float operands
      p(1.0 === nil)
      p(1.0 === Rational(1, 2))
      p(1.0 === Complex(1, 0))
      p(0.5 === Rational(1, 2))
      p(1.0 === 1)
      p(1.0 === 1.0)
      p(1.0 == nil)
      p(1.0 == Rational(1, 2))

      # nil & / | / ^ stay boolean even when the local widens to poly
      n = nil
      p(n | 0)
      p(n & 0)
      p(n ^ 0)
      n = nil
      p(n | "x")
      p(n & "x")
      p(n ^ false)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "HEllo"
      "h___o"
      "abcde"
      "abl0JrMf6tlhw"
      "sa3tHJ3/KuYvI"
      false
      false
      true
      true
      true
      true
      false
      false
      true
      false
      true
      true
      false
      false
    OUT
  end

  it "string oct parse" do
    result = ze0(<<~'RUBY')
      # String#oct is a lenient Integer(str, 8)-style parse: leading whitespace, an
      # optional sign, an optional base prefix (0x/0b/0o/0d or a leading 0 = octal),
      # and single underscore separators between digits. Spinel previously mishandled
      # a sign before a base prefix, dropped underscore separators, and ignored the 0d
      # prefix.
      def o(x); x.oct; end

      p o("777")        # 511
      p o("17")         # 15
      p o("-0b1010")    # -10  (sign before base prefix)
      p o("+17")        # 15
      p o("1_0")        # 8    (underscore separator, octal)
      p o("0x1f")       # 31
      p o("0o17")       # 15
      p o("0b11")       # 3
      p o("0d99")       # 99   (0d = decimal prefix)
      p o("  0b11")     # 3    (leading whitespace)
      p o("0xff_ff")    # 65535
      p o("0b1_1")      # 3

      # Lenient stops and invalid forms return what was parsed (or 0).
      p o("88")         # 0    (8 is not an octal digit)
      p o("17x")        # 15   (stops at 'x')
      p o("1_")         # 1    (trailing underscore)
      p o("1__0")       # 1    (doubled underscore stops)
      p o("_1")         # 0    (leading underscore)
      p o("0b_1")       # 0    (underscore right after prefix)
      p o("")           # 0
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      511
      15
      -10
      15
      8
      31
      15
      3
      99
      3
      65535
      3
      0
      15
      1
      1
      0
      0
      0
    OUT
  end

  it "string optional arg arities" do
    result = ze0(<<~'RUBY')
      # `count`/`delete` take one OR MORE char-set specs (intersected, `^`
      # negation honored); `match`/`match?`/`rindex` take an optional start
      # position; `rindex` also accepts a Regexp; `each_line` an optional
      # separator; `split` an optional limit (positive caps fields, negative
      # keeps trailing empties). All oracle-verified against ruby 4.0.6.

      p "hello world".count("lo")
      p "hello world".count("lo", "o")
      p "hello world".count("^l", "lo")
      p "hello".rindex("l", 2)
      p "hello".rindex("l", 3)
      p "abcdabcd".rindex(/c/)
      p "hello".rindex(/l/, 2)
      p "hello".match?(/e/, 1)
      p "hello".match?(/o/, -1)
      r = "hello".match(/l/, 3); p(r && r[0])
      p "1-2-3".each_line("-").to_a
      p "a,b,c".split(",", 2)
      p "a,b,,".split(",")
      p "a,b,,".split(",", -1)
      p "a1b2c3".split(/\d/, 2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      2
      2
      2
      3
      6
      2
      true
      true
      "l"
      ["1-", "2-", "3"]
      ["a", "b,c"]
      ["a", "b"]
      ["a", "b", "", ""]
      ["a", "b2c3"]
    OUT
  end

  it "string param dead each branch" do
    result = ze0(<<~'RUBY')
      # A String|Hash parameter that this program only ever calls with a String.
      # `opts` is therefore monomorphically String, so the `else` (Hash) branch is
      # statically dead. `String#each` is a genuine NoMethodError in Ruby and never
      # runs here (CRuby always takes the is_a?(String) branch), so it lowers to a
      # runtime stub via the NoMethodError gate rather than aborting compilation (#1434).
      class Conn
        def initialize(opts)
          @kind = ""
          if opts.is_a?(String)
            @kind = "string:" + opts
          else
            opts.each { |k, v| @kind = @kind + k + "=" + v }
          end
        end
        def kind; @kind; end
      end
      puts Conn.new("hello").kind
      puts Conn.new("world").kind
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      string:hello
      string:world
    OUT
  end

  it "string param inference from body" do
    result = ze0(<<~'RUBY')
      # #450 cascade 2: a method like
      #
      #   def match_pattern(pattern, path)
      #     pp = pattern.split("/")
      #     p2 = path.split("/")
      #     ...
      #   end
      #
      # with no concrete-typed caller (or callers passing a still-int default
      # from a deeper chain) used to leave `pattern` / `path` typed mrb_int.
      # `.split("/")` on a mrb_int then failed C compile. Now the analyze
      # pass infers "string" for params that have String-specific methods
      # called on them in the body.

      module Router
        def self.match_pattern(pattern, path)
          pp = pattern.split("/")
          p2 = path.split("/")
          return nil if pp.length != p2.length
          pp[0] + ":" + p2[0]
        end
      end

      puts Router.match_pattern("a/b/c", "x/y/z")

      # Top-level def variant.
      def normalize(s)
        s.strip.downcase
      end

      puts normalize("  HELLO  ")

      # Param widened only when the called method is String-only. `length`
      # alone (a container builtin) stays int — only flagging "definitive
      # String evidence" methods keeps the inference conservative.
      def show_len(arr)
        arr.length
      end

      puts show_len([1, 2, 3])
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      a:x
      hello
      3
    OUT
  end

  it "string param mutate byref" do
    result = ze0(<<~'RUBY')
      # A string param mutated via `<<` is a byref out-param: the append lands in
      # the caller's variable, like CRuby's shared-object semantics (the classic
      # pass-an-output-buffer serializer pattern).
      def append(s)
        s << "world"
      end
      str = "hello".dup
      append(str)
      puts str

      # transitive: a wrapper that passes its param on into a byref slot
      def inner(s)
        s << "!"
      end
      def outer(s)
        inner(s)
      end
      a = "x".dup
      outer(a)
      puts a

      # the mutator's return value is the receiver, usable alongside the mutation
      def bang(s)
        s << "?"
      end
      b = "y".dup
      r = bang(b)
      puts b
      puts r

      # only the mutated param rides byref; its sibling stays a plain value
      def tag(buf, label)
        buf << "["
        buf << label
        buf << "]"
      end
      t = "".dup
      tag(t, "hi")
      puts t

      # a non-lvalue argument still compiles (CRuby's mutation is equally
      # invisible to the caller there)
      bang("zzz".dup)
      puts "lit ok"

      # a plain rebind keeps value semantics: CRuby `s = ...` rebinds the local,
      # invisible to the caller, so the param must NOT ride byref
      def rebind(s)
        s = "gone"
        s << "!"
      end
      u = "keep".dup
      rebind(u)
      puts u

      # repeated appends through a call inside a block (build-a-buffer loop)
      def ser(buf, n)
        buf << n.to_s
        buf << ","
      end
      o = "".dup
      3.times { |i| ser(o, i) }
      puts o

      # a caller variable that is also captured by a proc (celled) passes its cell
      w = "p".dup
      f = proc { w << "c" }
      bang(w)
      f.call
      puts w

      # element assignment is an in-place mutator too
      def fix(s)
        s[0] = "X"
      end
      e = "abc".dup
      fix(e)
      puts e

      # a frozen argument raises FrozenError from inside the callee, like CRuby
      frozen = "locked".freeze
      begin
        bang(frozen)
      rescue FrozenError
        puts "FrozenError"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      helloworld
      x!
      y?
      y?
      [hi]
      lit ok
      keep
      0,1,2,
      p?c
      Xbc
      FrozenError
    OUT
  end

  it "string plus heap gc" do
    result = ze0(<<~'RUBY', path: "core/string/string_plus_heap_gc.rb")
      # Regression for matz/spinel#1450. A `String#+` loop allocates only on the
      # string heap (no object-heap allocation), and before the fix the string heap
      # was swept only from sp_gc_collect, which fires on OBJECT-heap pressure
      # (sp_gc_bytes). So a string-only workload never collected and RSS grew without
      # bound. The fix drives collection off the string heap's own live-byte count.
      #
      # Assert that a collection actually fires here: GC.stat["cycle"] counts
      # sp_gc_collect runs, and since this loop never touches the object heap, the
      # ONLY thing that can advance it is the string-heap trigger. Pre-fix this prints
      # "NO COLLECTION"; post-fix it prints "collected".
      before = GC.stat["cycle"]
      s = ""
      i = 0
      while i < 50000
        s = s + "x"          # fresh result string each step; old s becomes garbage
        s = "" if s.length > 1000   # keep the live set tiny -- all the churn is collectable
        i += 1
      end
      after = GC.stat["cycle"]
      puts(after > before ? "collected" : "NO COLLECTION")
    RUBY

    _(result.stdout).must_equal ""
    _(result.stderr).must_equal "core/string/string_plus_heap_gc.rb:20:in '<main>': undefined method '>' for nil (NoMethodError)\n\nputs(after > before ? \"collected\" : \"NO COLLECTION\")\n           ^\n"
    _(result.status).must_equal 1
  end

  it "string range accessors" do
    result = ze0(<<~'RUBY')
      # begin/end/first/last/min/max on a String-endpoint Range read the endpoints
      # as strings (the int-backed sp_Range stores their pointers), and first(n)/
      # last(n) materialize n elements via string succ.
      p(("a".."e").begin)
      p(("a".."e").end)
      p(("a".."e").first)
      p(("a".."e").last)
      p(("a".."e").min)
      p(("a".."e").max)
      p(("a".."e").first(2))
      p(("a".."e").last(2))
      r = ("b".."d")
      p(r.begin)
      p(r.max)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "a"
      "e"
      "a"
      "e"
      "a"
      "e"
      ["a", "b"]
      ["d", "e"]
      "b"
      "d"
    OUT
  end

  it "string range each inspect" do
    _(ze0(<<~'RUBY').stdout).must_equal "abcde\nabc\naa ab ac \n26\n\"a\"..\"c\"\n\"a\"...\"e\"\n\"aa\"..\"ac\"\n15\n1..5\n1...5\n"
      # String-endpoint ranges have no int sp_Range representation. Iterating one
      # with a block (materialized as a succ-sequence) and inspecting a literal now
      # work instead of miscompiling. (Accumulating the yielded strings into an array
      # declared outside the block still needs wider element inference -- separate.)

      # each with a block
      letters = ""
      ("a".."e").each { |ch| letters += ch }
      puts letters

      # exclusive range each
      ("a"..."d").each { |ch| print ch }
      puts

      # multi-char succ
      seq = ""
      ("aa".."ac").each { |s| seq += s + " " }
      puts seq

      # counting
      n = 0
      ("a".."z").each { |_| n += 1 }
      puts n

      # inspect of a string-range literal (p uses #inspect: endpoints are quoted)
      p ("a".."c")
      p ("a"..."e")
      p ("aa".."ac")

      # numeric ranges are unaffected
      total = 0
      (1..5).each { |i| total += i }
      puts total
      p (1..5)
      p (1...5)
    RUBY
  end

  it "string range include iterates" do
    result = ze0(<<~'RUBY')
      # `Range#include?` WALKS the range; `Range#cover?` compares endpoints with
      # `<=>`. For a String range the two disagree, and zeo answers `cover?` for both.
      #
      # `("a".."e").include?("bb")` is false -- `bb` is not one of a, b, c, d, e --
      # while `cover?("bb")` is true, because `"a" <= "bb" <= "e"`. zeo aliases
      # `include?`/`member?` onto `===`'s cover check
      # (`builtins::range.rs`'s shared row), whose comment claims the approximation is
      # faithful "for the numeric/comparable cases this runtime supports". A String
      # range is exactly the case it is not faithful for, and ruby's own docs use this
      # pair as the illustration of the difference.
      #
      # Ruby takes the cover shortcut only for a range whose endpoints are Numeric
      # (`range.c`'s `range_include_internal` falls through to `rb_ary_includes`-style
      # iteration otherwise), so the numeric answers below must stay as they are.

      p ("a".."e").include?("bb")
      p ("a".."e").cover?("bb")
      p ("a".."e").member?("bb")
      p ("a".."e") === "bb"

      p ("a".."e").include?("c")
      p ("a".."z").include?("cc")

      # Numeric ranges take the shortcut in ruby too -- these must not change.
      p (1..10).include?(5.5)
      p (1..10).cover?(5.5)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      false
      true
      false
      true
      true
      false
      true
      true
    OUT
  end

  it "string range step" do
    result = ze0(<<~'RUBY')
      r001 = []; ("a".."e").step(2) { |s001| r001 << s001 }; p r001
      sr = ("a".."e")
      p sr.step(2).to_a
      p sr.step(2).class
      p (sr % 2).to_a
      p ("a".."e").to_a
      r2 = []; (("a".."e") % 2).each { |s| r2 << s }; p r2
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "c", "e"]
      ["a", "c", "e"]
      Enumerator
      ["a", "c", "e"]
      ["a", "b", "c", "d", "e"]
      ["a", "c", "e"]
    OUT
  end

  it "string range to a" do
    result = ze0(<<~'RUBY')
      # String range to_a — single-char ASCII case (the common subset
      # shape). Multi-char ranges need full String#succ with cross-position
      # carry and are out of scope for now (the runtime helper returns
      # an empty array on multi-char input).
      puts ("a".."c").to_a.inspect
      puts ("A".."E").to_a.inspect
      puts ("0".."5").to_a.inspect

      # Exclusive range
      puts ("a"..."c").to_a.inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b", "c"]
      ["A", "B", "C", "D", "E"]
      ["0", "1", "2", "3", "4", "5"]
      ["a", "b"]
    OUT
  end

  it "string replace prepend insert clear" do
    result = ze0(<<~'RUBY')
      # String#replace / prepend / insert / clear mutate a string held in a
      # local variable. The analyzer widens such a local to a mutable_str
      # (or, for clear, reassigns it), so these match CRuby instead of being
      # no-ops. Both string-literal locals and String.new receivers work.
      s = "abc"
      s.replace("xyz")
      p s

      s2 = "world"
      s2.prepend("hello ")
      p s2

      s3 = "hlo"
      s3.insert(1, "el")
      p s3

      s4 = "hello"
      s4.clear
      p s4.length

      # String.new receivers mutate through the same paths.
      m = String.new("abc")
      m.replace("xyz")
      m.prepend("> ")
      p m

      m2 = String.new("hello")
      m2.clear
      p m2.length

      # insert with a negative index counts from the end.
      s5 = "abcd"
      s5.insert(-2, "X")
      p s5
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "xyz"
      "hello world"
      "hello"
      0
      "> xyz"
      0
      "abcXd"
    OUT
  end

  it "string search slice" do
    result = ze0(<<~'RUBY')
      # String search/slice coverage: index-by-substring (returns the substring or
      # nil), start_with? with a regex (anchored at index 0), the byte-sum checksum,
      # and unpack1 (the first element of unpack). Receivers go through a method
      # param so the runtime path is exercised rather than constant folding.
      def s(x); x; end

      # s["sub"]: the matched substring, or nil
      p s("hello")["ll"]
      p s("hello")["zz"]
      p s("hello")["hello"]

      # start_with? accepts a regex, true only when it matches at the start
      p s("hello").start_with?(/he/)
      p s("hello").start_with?(/ell/)
      p s("hello").start_with?(/zz/)
      p s("hello").start_with?("he")

      # sum: 16-bit byte checksum
      p s("hello").sum
      p s("abc").sum

      # unpack1: first element of unpack
      p s("AB").unpack1("C")
      p s("ABCD").unpack1("N")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ll"
      nil
      "hello"
      true
      false
      false
      true
      532
      294
      65
      1094861636
    OUT
  end

  it "string shift chain" do
    result = ze0(<<~'RUBY')
      # chained string appends (`s << a << b`) evaluate each link exactly once and
      # every append lands on the base. The tail form used to re-run the inner
      # links when emitting the return value (doubling the appended text, and
      # writing the doubled string back through a byref param); the value form
      # wrote back only the innermost link, so the base missed the later appends.

      # tail position, through a mutated parameter (the byref shape)
      def emit(buf, label)
        buf << "[" << label << "]"
      end

      s = +""
      emit(s, "ok")
      p s
      r = emit(s, "go")
      p r
      p s

      # value position: assignment keeps base and result in step
      t = +"x"
      u = (t << "a" << "b")
      p t
      p u

      # parenthesized links and a longer chain
      v = +""
      (v << "1") << "2" << "3"
      p v

      # int argument appends its codepoint character
      w = +"y"
      w << "-" << 33
      p w

      # ivar base
      class Sink
        def initialize
          @buf = +"<"
        end

        def push(a, b)
          @buf << a << b
        end
      end

      k = Sink.new
      p k.push("m", ">")

      # repeated tail chains accumulate (the serializer shape)
      def line(out, op, arg)
        out << op << " " << arg << "\n"
      end

      prog = +""
      line(prog, "LOAD", "a")
      line(prog, "JUMP", "top")
      print prog
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "[ok]"
      "[ok][go]"
      "[ok][go]"
      "xab"
      "xab"
      "123"
      "y-!"
      "<m>"
      LOAD a
      JUMP top
    OUT
  end

  it "string shl identity" do
    result = ze0(<<~'RUBY')
      # String#<< returns the receiver itself (identity), not a copy (KieranP #2307).
      # The mutable-buffer receiver appends in place; the expression value and a
      # subsequent read of the variable are the same object.
      s = "a"
      p((s << "b").equal?(s))
      p s
      p((s.concat("e")).equal?(s))
      p s
      t = "x"
      u = "y"
      t << "z"
      p t.equal?(u)          # distinct buffers stay distinct
      p s.upcase.equal?(s)   # a non-mutating transform is a new object
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      "ab"
      true
      "abe"
      false
      false
    OUT
  end

  it "string slice bang value" do
    result = ze0(<<~'RUBY')
      # String#slice! in value position returns the removed part (or nil).
      s = "hello world"
      removed = s.slice!(0, 6)
      p removed
      p s
      t = "hello"
      r2 = t.slice!("ll")
      p r2
      p t
      u = "abc"
      p u.slice!("zz").inspect
      p u
      v = "hello"
      p v.slice!(2, 99)
      p v
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello "
      "world"
      "ll"
      "heo"
      "nil"
      "abc"
      "llo"
      "he"
    OUT
  end

  it "string slice casecmp succ" do
    result = ze0(<<~'RUBY')
      # CRuby contracts for three String surfaces: the [start, len] / [range]
      # nil boundaries, casecmp/casecmp? answering nil for a non-String argument,
      # and the alphanumeric-aware succ carry.

      def sub2(s, i, n); s[i, n]; end

      # in-range, boundary (start == length -> ""), past the end -> nil
      p sub2("hello", 1, 3)
      p sub2("hello", 5, 2)
      p sub2("hello", 6, 2)

      # negative starts: in range counts back; before -length -> nil
      p sub2("hello", -4, 2)
      p sub2("hello", -5, 1)
      p sub2("hello", -6, 1)

      # negative length -> nil; zero length -> ""
      p sub2("hello", 1, -1)
      p sub2("hello", 1, 0)

      def subr(s, r); s[r]; end
      p subr("hello", 3..9)
      p subr("hello", 9..12)
      p subr("hello", -99..2)
      p subr("hello", 5..7)

      # slice is the same method
      def sl2(s, i, n); s.slice(i, n); end
      p sl2("hello", 10, 2)
      p sl2("hello", 2, 2)

      def cc(a, b); a.casecmp(b); end
      def ccp(a, b); a.casecmp?(b); end
      p cc("abc", "ABD")
      p cc("ABC", "abc")
      p ccp("abc", "ABC")
      p ccp("abc", "abd")
      p cc("abc", :abc)
      p ccp("abc", :abc)
      p ccp("abc", 42)

      def sc(x); x.succ; end
      # digit carry across a same-class gap; alpha likewise
      p sc("1.9")
      p sc("1.99")
      p sc("z.z")
      # adjacent alnum takes the carry regardless of class
      p sc("a9")
      p sc("1z")
      p sc("z9")
      p sc("Zz9")
      # a different class across a gap inserts instead of carrying
      p sc("a-9")
      p sc("1.z")
      p sc(".9")
      # no alphanumerics: the last byte increments
      p sc("***")
      p sc("<<koala>>")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ell"
      ""
      nil
      "el"
      "h"
      nil
      nil
      ""
      "lo"
      nil
      nil
      ""
      nil
      "ll"
      -1
      0
      true
      false
      nil
      nil
      nil
      "2.0"
      "2.00"
      "aa.a"
      "b0"
      "2a"
      "aa0"
      "AAa0"
      "a-10"
      "1.aa"
      ".10"
      "**+"
      "<<koalb>>"
    OUT
  end

  it "string slice range" do
    result = ze0(<<~'RUBY')
      # String#slice(Range) — decompose the Range and reuse the same
      # runtime helper as String#[](Range). Inclusive, exclusive,
      # endless, beginless and negative endpoints all supported.
      p "hello".slice(1..3)
      p "hello".slice(1...3)
      p "hello".slice(1..)
      p "hello".slice(..2)
      p "hello".slice(1..-2)
      p "hello".slice(2..10)
      p "hello".slice(0..-1)

      # slice still works with (start, length) and single-index forms.
      p "hello".slice(1, 2)
      p "hello".slice(1)

      # Through a local receiver too.
      s = "spinel"
      p s.slice(2..4)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "ell"
      "el"
      "ello"
      "hel"
      "ell"
      "llo"
      "hello"
      "el"
      "e"
      "ine"
    OUT
  end

  it "string split block" do
    result = ze0(<<~'RUBY')
      # String#split with a block yields each substring (rather than ignoring the
      # block and returning the array). Spinel previously never ran the block. The
      # call is used in statement position, collecting via the block's side effects --
      # matching how String#scan with a block already behaves.
      def sp1(x); r = []; x.split(",") { |p| r << p }; r; end
      p sp1("a,b,c")                 # ["a", "b", "c"]

      # Whitespace mode (no separator / a single space).
      def spws(x); r = []; x.split { |w| r << w.upcase }; r; end
      p spws("  foo   bar ")         # ["FOO", "BAR"]

      # Explicit separator with a limit.
      def splim(x); r = []; x.split(",", 2) { |p| r << p }; r; end
      p splim("a,b,c,d")             # ["a", "b,c,d"]

      # The block runs for its side effects; the method returns another value.
      def total(x); n = 0; x.split("-") { |p| n += p.length }; n; end
      p total("aa-bbb-c")            # 6

      # Each yielded piece is a String (supports String methods in the block).
      def joined(x); acc = ""; x.split(":") { |p| acc += p.reverse }; acc; end
      p joined("ab:cd")              # "badc"

      # An empty result yields nothing.
      def none(x); c = 0; x.split(",") { |p| c += 1 }; c; end
      p none("")                     # 0
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b", "c"]
      ["FOO", "BAR"]
      ["a", "b,c,d"]
      6
      "badc"
      0
    OUT
  end

  it "string split capture" do
    result = ze0(<<~'RUBY')
      # Issue #856: split with a regex that has capture groups splices
      # the matched groups into the result between segments.
      puts "hello world".split(/(\s+)/).inspect
      # Without a capture group, behaviour unchanged.
      puts "hello world".split(/\s+/).inspect
      # Multiple capture groups: each captured substring is spliced
      # in, in group-index order.
      puts "a1b2c3d".split(/(\d)/).inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["hello", " ", "world"]
      ["hello", "world"]
      ["a", "1", "b", "2", "c", "3", "d"]
    OUT
  end

  it "string squeeze no trailing nul" do
    result = ze0(<<~'RUBY')
      # Issue #921: String#squeeze shrinks the heap-string header
      # so length / bytes report the post-squeeze size, not the
      # pre-squeeze allocation.
      s = "aaabbbccc"
      result = s.squeeze
      puts result.length
      puts result.bytes.inspect
      puts result.inspect

      # Trailing NULs leak the GC marker byte; ensure none.
      puts "xxxxx".squeeze.length
      puts "xxxxx".squeeze
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      [97, 98, 99]
      "abc"
      1
      x
    OUT
  end

  it "string sum bits" do
    result = ze0(<<~'RUBY')
      # String#sum(bits): byte checksum modulo 2**bits (default 16; <= 0 or
      # >= 64 untruncated like CRuby).
      puts "hello".sum(8)
      p "abc".sum
      p "hello".sum(0)
      p "hi".sum(64)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      20
      294
      532
      209
    OUT
  end

  it "string to c" do
    result = ze0(<<~'RUBY')
      # String#to_c: lenient leading-substring parse into a Complex.

      # Rectangular forms.
      p "3+4i".to_c
      p "-3-4i".to_c
      p "5+i".to_c
      p "1.5+2.5i".to_c

      # Pure real and pure imaginary.
      p "1.5".to_c
      p "7".to_c
      p "3i".to_c
      p "3.0e2i".to_c

      # Bare imaginary unit, with optional sign.
      p "i".to_c
      p "+i".to_c
      p "-i".to_c

      # Rational components.
      p "2/3".to_c
      p "2/3+1/4i".to_c
      p "1.5/2".to_c

      # Polar (magnitude@angle); a zero angle keeps the exact magnitude.
      p "1@2".to_c
      p "1@0".to_c

      # Whitespace is trimmed; junk and empty strings parse to (0+0i).
      p "  3+4i  ".to_c
      p "foo".to_c
      p "".to_c

      # Digit-group underscores; a trailing '.' and an unterminated tail stop the parse.
      p "1_000".to_c
      p "5.".to_c
      p "3+4".to_c

      # A zero denominator raises, matching Rational parsing.
      begin
        "1/0".to_c
      rescue ZeroDivisionError => e
        puts "raised: #{e.message}"
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      (3+4i)
      (-3-4i)
      (5+1i)
      (1.5+2.5i)
      (1.5+0i)
      (7+0i)
      (0+3i)
      (0+300.0i)
      (0+1i)
      (0+1i)
      (0-1i)
      ((2/3)+0i)
      ((2/3)+(1/4)*i)
      ((3/4)+0i)
      (-0.4161468365471424+0.9092974268256817i)
      (1+0.0i)
      (3+4i)
      (0+0i)
      (0+0i)
      (1000+0i)
      (5+0i)
      (3+0i)
      raised: divided by 0
    OUT
  end

  it "string to c lenient" do
    result = ze0(<<~'RUBY')
      # String#to_c raised where CRuby answers (0+0i). One parser was serving two
      # contracts: Kernel#Complex(str) must consume the whole string or raise, while
      # String#to_c reads a LEADING complex and ignores the rest. String#to_r has had
      # that pair (sp_str_to_r / sp_str_to_r_strict) all along; to_c had only the
      # strict half and #to_c was pointed at it.
      #
      # And sp_poly_to_r_m had no String arm, though sp_poly_to_c_m has carried one
      # all along -- so a String that widened to poly answered NoMethodError, which
      # is what `v&.to_r` is.

      # String#to_c: a leading complex, the rest ignored, (0+0i) when there is none
      p "abc".to_c
      p "".to_c
      p "5x".to_c
      p "1+2i".to_c
      p "3".to_c
      p "2.5".to_c
      p "  7  ".to_c

      # String#to_r, the sibling that was already right
      p "abc".to_r
      p "3/4".to_r
      p "1.5".to_r
      p "12".to_r
      p "5x".to_r
      p "".to_r

      # Kernel#Complex / #Rational keep the strict contract
      def try
        yield
      rescue ArgumentError
        "ArgumentError"
      end

      p try { Complex("abc") }
      p try { Complex("1+") }
      p try { Complex("5x") }
      p try { Complex("2+3i") }
      p try { Rational("abc") }
      p try { Rational("3/4") }
      p Complex("abc", exception: false)
      p Rational("abc", exception: false)

      # through a poly receiver, which is where the missing String arm showed
      def as_r(v) = v&.to_r
      def as_c(v) = v&.to_c

      p as_r("3/4")
      p as_r("abc")
      p as_r(nil)
      p as_r(5)
      p as_r(1.5)
      p as_c("1+2i")
      p as_c("abc")
      p as_c(nil)
      p as_c(5)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      (0+0i)
      (0+0i)
      (5+0i)
      (1+2i)
      (3+0i)
      (2.5+0i)
      (7+0i)
      (0/1)
      (3/4)
      (3/2)
      (12/1)
      (5/1)
      (0/1)
      "ArgumentError"
      "ArgumentError"
      "ArgumentError"
      (2+3i)
      "ArgumentError"
      (3/4)
      nil
      nil
      (3/4)
      (0/1)
      nil
      (5/1)
      (3/2)
      (1+2i)
      (0+0i)
      nil
      (5+0i)
    OUT
  end

  it "string to f bare dot" do
    result = ze0(<<~'RUBY')
      p ".5".to_f
      p "5.".to_f
      p "-.5".to_f
      p ".5e1".to_f
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0.5
      5.0
      -0.5
      5.0
    OUT
  end

  it "string to i base" do
    result = ze0(<<~'RUBY')
      # Issue #883: String#to_i with explicit base argument. Without the
      # fix, the base was silently dropped and the call returned 0 for
      # any non-decimal input.
      puts "ff".to_i(16)
      puts "1010".to_i(2)
      puts "777".to_i(8)
      puts "z".to_i(36)
      puts "-ff".to_i(16)
      puts "1_0".to_i(16)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      255
      10
      511
      35
      -255
      16
    OUT
  end

  it "string to i base prefix" do
    result = ze0(<<~'RUBY')
      p "0x1f".to_i(16)
      p "-0x1f".to_i(16)
      p "-1f".to_i(16)
      p "0b11".to_i(2)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      31
      -31
      -31
      3
    OUT
  end

  it "string to i base zero" do
    result = ze0(<<~'RUBY')
      # String#to_i(0) auto-detects the base from the literal prefix.
      puts "0xff".to_i(0)
      puts "0b10".to_i(0)
      puts "0777".to_i(0)
      puts "0o755".to_i(0)
      puts "42".to_i(0)         # no prefix → decimal
      # Sign handling.
      puts "-0xff".to_i(0)
      puts "+0b101".to_i(0)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      255
      2
      511
      493
      42
      -255
      5
    OUT
  end

  it "string to i base zero auto detects the prefix" do
    result = ze0(<<~'RUBY')
      puts "0xff".to_i(0)
      puts "0b101".to_i(0)
      puts "0o755".to_i(0)
      puts "0777".to_i(0)
      puts "42".to_i(0)
      puts "-0xff".to_i(0)
      puts "+0b101".to_i(0)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      255
      5
      493
      511
      42
      -255
      5
    OUT
  end

  it "string to i overflow raises" do
    result = ze0(<<~'RUBY')
      # String#to_i / Integer() on input exceeding int64 raises
      # RangeError rather than saturating silently. spinel's int model
      # is int64-only, so the CRuby Bignum promotion path lowers to a
      # user-catchable RangeError.

      begin
        "99999999999999999999".to_i
        puts "no exception"
      rescue RangeError
        puts "to_i raised RangeError"
      end

      begin
        "ffffffffffffffff0".to_i(16)
        puts "no exception"
      rescue RangeError
        puts "to_i(16) raised RangeError"
      end

      begin
        Integer("99999999999999999999")
        puts "no exception"
      rescue RangeError
        puts "Integer raised RangeError"
      end

      # In-range values still work.
      puts "42".to_i
      puts "ff".to_i(16)
      puts Integer("-1000")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      no exception
      no exception
      no exception
      42
      255
      -1000
    OUT
  end

  it "string tr bang identity" do
    result = ze0(<<~'RUBY')
      p (+"Hello").tr!("l", "l")
      p (+"Hello").tr!("z", "y")
      p (+"Hello").tr!("l", "L")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "Hello"
      nil
      "HeLLo"
    OUT
  end

  it "string tr duplicate from char uses the last mapping" do
    result = ze0(<<~'RUBY')
      # A char repeated in `from` takes its LAST corresponding `to` char
      # (CRuby's rule) -- previously the FIRST mapping wrongly won.

      p "a___b".tr("___", ".+-")
      p "abcaa".tr("aa", "xy")
      p "abcd".tr("abc", "x")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "a---b"
      "ybcyy"
      "xxxd"
    OUT
  end

  it "string try convert" do
    result = ze0(<<~'RUBY')
      # `String.try_convert(obj)` -- the `to_str` check-conversion, exposed. Unlike
      # `String(obj)` it never falls back to `to_s` and never raises for an object
      # that simply isn't string-like; a lying `to_str` is the one error case.

      # Already a String: returned as-is (the same object, not a copy).
      s = "hello"
      p String.try_convert(s)
      p String.try_convert(s).equal?(s)

      # A subclass is already a String too -- and `try_convert` hands back the very
      # object, so it comes out still wearing its own class.
      class Name < String; end
      sub = Name.new("ada")
      p String.try_convert(sub).class
      p String.try_convert(sub).equal?(sub)

      # Defines `to_str`: converted through it.
      class Path
        def to_str = "/tmp/x"
      end
      p String.try_convert(Path.new)

      # ...and a `to_str` that answers a String SUBCLASS satisfies the check without
      # being flattened to a plain String.
      class Quacker
        def to_str = Name.new("quack")
      end
      p String.try_convert(Quacker.new).class

      # `to_s` alone is NOT the protocol -- only `to_str` is.
      class Labelled
        def to_s = "label"
      end
      p String.try_convert(Labelled.new)

      # No conversion at all: nil, never an exception.
      p String.try_convert(42)
      p String.try_convert(nil)
      p String.try_convert([1, 2])
      p String.try_convert(:sym)

      # A `to_str` that answers a non-String is the one raising case.
      class Liar
        def to_str = 42
      end
      begin
        String.try_convert(Liar.new)
      rescue TypeError => e
        puts e.message
      end

      # `to_str` answering nil reads as "no conversion", not as a lie.
      class Absent
        def to_str = nil
      end
      p String.try_convert(Absent.new)

      # The encoding of the converted string survives.
      p String.try_convert("caf\xC3\xA9".b).encoding
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello"
      true
      Name
      true
      "/tmp/x"
      Name
      nil
      nil
      nil
      nil
      nil
      can't convert Liar to String (Liar#to_str gives Integer)
      nil
      #<Encoding:BINARY (ASCII-8BIT)>
    OUT
  end

  it "string undump" do
    result = ze0(<<~'RUBY')
      # String#undump is the inverse of String#dump. Round-tripping a string
      # through dump then undump returns the original (each engine round-trips
      # its own dump format, so the comparison is version-independent).
      # Previously undump was unresolved.
      ["hello", "a\tb\nc", "q\"u\\o#te", "tab\there", "café"].each do |s|
        puts(s.dump.undump == s)
      end
      # undump of an explicit dumped form
      puts "\"hi\\nthere\"".undump
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      true
      true
      true
      true
      hi
      there
    OUT
  end

  it "string upto" do
    result = ze0(<<~'RUBY')
      # String#upto walks successive strings (the same succ-based sequence a
      # String range produces) from the receiver to the argument inclusive,
      # yielding each to the block. The block-less form materializes the
      # sequence as an array. Previously codegen treated the receiver as an
      # integer loop variable and failed to compile.
      count = 0
      "a".upto("e") { |c| count += 1 }
      puts count

      out = ""
      "x".upto("z") { |c| out += c }
      puts out

      # multi-character carry
      multi = ""
      "ay".upto("bb") { |c| multi += c + "," }
      puts multi

      # block-less form materializes to an array
      puts "a".upto("c").to_a.join("-")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      5
      xyz
      ay,az,ba,bb,
      a-b-c
    OUT
  end

  it "string upto and range" do
    result = ze0(<<~'RUBY')
      z = []
      r = "a".upto("c") { |s| z << s }
      p z
      p r
      p "9".upto("11").to_a
      p "a".upto("e").to_a
      p ("9".."11").to_a
      p ("a".."e").to_a
      p ("y".."ab").to_a
      p ("a"..."d").to_a
      w = []
      "aa".upto("ac") { |s| w << s }
      p w
      p 1.upto(3).to_a
      q = []
      1.upto(3) { |i| q << i }
      p q
      p "a".upto("e", true).to_a
      p "a".upto("e", false).to_a
      x = []
      "a".upto("d", true) { |s| x << s }
      p x
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      ["a", "b", "c"]
      "a"
      ["9", "10", "11"]
      ["a", "b", "c", "d", "e"]
      ["9", "10", "11"]
      ["a", "b", "c", "d", "e"]
      []
      ["a", "b", "c"]
      ["aa", "ab", "ac"]
      [1, 2, 3]
      [1, 2, 3]
      ["a", "b", "c", "d"]
      ["a", "b", "c", "d", "e"]
      ["a", "b", "c"]
    OUT
  end

  it "string with embedded nul" do
    result = ze0(<<~'RUBY')
      # Spinel-allocated strings encode their byte length in the heap
      # header (sp_str_hdr.len), but several runtime helpers and one
      # codegen `bytesize` emit walked the buffer via NUL-terminated
      # strlen/`while(*p)` semantics. A `0.chr` value carrying a header
      # length of 1 with byte content `\x00` reported `length=0`,
      # `bytesize=0`, and sliced wrong past any embedded NUL.
      #
      # Fix: `sp_str_length` and `sp_utf8_byte_offset` consume the
      # header-tracked byte length instead of terminating at the first
      # NUL byte. `bytesize` codegen now emits
      # `sp_str_byte_len(...)` instead of `(mrb_int)strlen(...)`.
      # Issue #593.

      # Single-byte NUL.
      puts 0.chr.length              # 1
      puts 0.chr.bytesize            # 1
      puts 0.chr.ord                 # 0

      # Concat preserves NULs in the middle.
      b = 0.chr + 0xc8.chr
      puts b.length                  # 2
      puts b.bytesize                # 2
      puts b[0].ord                  # 0
      puts b[1].ord                  # 200 (0xc8)

      # Mixed ASCII + NUL + ASCII -- indexing past the NUL.
      c = "x" + 0.chr + "y"
      puts c.length                  # 3
      puts c[0].ord                  # 120 ('x')
      puts c[1].ord                  # 0
      puts c[2].ord                  # 121 ('y')

      # Progressive build with NUL in the middle.
      d = ""
      d = d + 0x81.chr
      d = d + 0x7e.chr
      d = d + 0x00.chr
      d = d + 0xc8.chr
      puts d.length                  # 4
      puts d[2].ord                  # 0
      puts d[3].ord                  # 200

      # Substring across NUL.
      e = d[0, 4]
      puts e.length                  # 4
      puts e[3].ord                  # 200
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      1
      0
      2
      2
      0
      200
      3
      120
      0
      121
      4
      0
      200
      4
      200
    OUT
  end

  it "strip nul" do
    result = ze0(<<~'RUBY')
      # strip/lstrip/rstrip remove the NUL byte (CRuby strips "\0\t\n\v\f\r ").
      # Embedded NUL needs a heap string (literals truncate at \0); build via pack.
      s = [0, 104, 105, 0].pack("C*")          # "\0hi\0"
      p s.strip.bytes
      p s.lstrip.bytes
      p s.rstrip.bytes
      mid = [0, 0, 104, 0, 105, 0].pack("C*")  # "\0\0h\0i\0" -- interior NUL survives
      p mid.strip.bytes
      # normal strings unchanged
      p "  hi  ".strip
      p "\tx\n".strip
      p "ab  ".rstrip
      p "  ab".lstrip
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [104, 105]
      [104, 105, 0]
      [0, 104, 105]
      [104, 0, 105]
      "hi"
      "x"
      "ab"
      "ab"
    OUT
  end

  it "struct inspect labels non identifier members as symbols" do
    result = ze0(<<~'RUBY')
      # A Struct/Data member whose name isn't a plain identifier prints with a
      # leading colon in inspect (`:verbose?=`), while a plain one stays bare.

      S = Struct.new(:verbose?, :name)
      p S.new(true, "x").inspect
      D = Data.define(:ok?, :count)
      p D.new(ok?: false, count: 3).inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "#<struct S :verbose?=true, name=\"x\">"
      "#<data D :ok?=false, count=3>"
    OUT
  end

  it "struct string member gc root" do
    result = ze0(<<~'RUBY')
      # A single fresh-string struct member must survive the struct's own allocation
      # (SP_POOL_NEW can trigger a GC before the member is stored). The constructor
      # roots its heap arguments so the collector cannot sweep the name before it is
      # assigned, nor read a freed name when it later marks the (live) struct.
      Entry = Struct.new(:name)
      entries = []
      8000.times do |i|
        entries << Entry.new("item#{i}".upcase)
      end
      GC.start
      bad = 0
      entries.each_with_index { |e, i| bad += 1 unless e.name == "ITEM#{i}" }
      puts "count=#{entries.size} bad=#{bad}"
      puts entries[0].name
      puts entries[4000].name
      puts entries.last.name

      # Non-string heap members must be rooted too. A bigint member is a heap object
      # but is neither string/poly/object/array/hash, so the old rooting predicate
      # skipped it: a fresh bigint temporary could be swept across SP_POOL_NEW's GC.
      Big = Struct.new(:n)
      bigs = []
      8000.times do |i|
        bigs << Big.new(2 ** 70 + i)
      end
      GC.start
      bbad = 0
      bigs.each_with_index { |x, i| bbad += 1 unless x.n == 2 ** 70 + i }
      puts "bcount=#{bigs.size} bbad=#{bbad}"
      puts bigs[0].n
      puts bigs.last.n
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      count=8000 bad=0
      ITEM0
      ITEM4000
      ITEM7999
      bcount=8000 bbad=0
      1180591620717411303424
      1180591620717411311423
    OUT
  end

  it "sub and gsub read a replacement in its own encoding" do
    result = ze0(<<~'RUBY')
      # sub and gsub read a replacement's backslashes as CRuby's rb_reg_regsub
      # reads them: a character at a time in the replacement's own encoding,
      # so UTF-16 and UTF-32 replacements fill in their groups and a
      # Shift_JIS trail byte 0x5C is no backslash. What the pieces join into
      # follows the encodings of the text, the replacement and the groups.
      def show(label)
        value = yield
        p [label, value.encoding.name, value.b]
      rescue StandardError => e
        p [label, e.class, e.message]
      end

      show(:named_ref) { "ab".sub(/(?<x>a)/, "[\\k<x>]") }
      show(:unknown_name) { "ab".sub(/(?<x>a)/, "[\\k<y>]") }
      show(:open_name) { "ab".sub(/(?<x>a)/, "[\\k<x]") }
      show(:bare_k) { "ab".sub(/(a)/, "[\\k]") }
      show(:k_then_x) { "ab".sub(/(a)/, "[\\kx]") }
      show(:trailing) { "ab".sub(/a/, "x\\") }
      show(:double) { "ab".sub(/a/, "x\\\\y") }
      show(:past_groups) { "ab".sub(/(a)/, "[\\9]") }
      show(:plus_none) { "ab".sub(/a/, "[\\+]") }
      show(:plus_last) { "abc".sub(/(a)(x)?(b)?/, "[\\+]") }
      show(:numbered_under_names) { "ab".sub(/(?<x>a)(b)/, "[\\1|\\2]") }
      show(:string_pattern) { "ab".sub("a", "[\\0|\\1|\\&|\\`|\\']") }
      show(:string_pattern_name) { "ab".sub("a", "[\\k<a>]") }
      show(:duplicate_names) { "xy".gsub(/(?<a>x)|(?<a>y)/, "<\\k<a>>") }
      show(:other_escape) { "ab".sub(/a/, "\\q\\n") }
      show(:escaped_multibyte) { "ab".sub(/a/, "\\é") }
      show(:name_multibyte) { "ab".sub(/(?<é>a)/, "\\k<é>") }

      sjis = ->(s) { s.encode("Shift_JIS") }
      show(:sjis_trail) { sjis.("表a").sub(sjis.("a"), sjis.("表0")) }
      show(:sjis_group) { sjis.("表a").sub(Regexp.new(sjis.("(表)")), sjis.("\\1\\1")) }
      show(:sjis_gsub) { sjis.("ソ表ソ").gsub(Regexp.new(sjis.("ソ")), sjis.("表\\0")) }

      %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
        u = ->(s) { s.encode(enc) }
        text = u.("héllo wörld")
        show(:"#{enc}_groups") { text.sub(Regexp.new(u.("(h)(é)")), u.("<\\2\\1\\0>")) }
        show(:"#{enc}_named") { text.gsub(Regexp.new(u.("(?<v>[éö])")), u.("[\\k<v>]")) }
        show(:"#{enc}_pre_post") { text.sub(Regexp.new(u.(" ")), u.("|\\'|\\`|")) }
        show(:"#{enc}_backslashes") { text.sub(Regexp.new(u.("o")), u.("\\\\\\x\\")) }
        show(:"#{enc}_plain") { text.gsub(Regexp.new(u.("l")), u.("L")) }
        show(:"#{enc}_bad_name") { text.sub(Regexp.new(u.("(?<v>h)")), u.("\\k<w>")) }
        show(:"#{enc}_open_name") { text.sub(Regexp.new(u.("(?<v>h)")), u.("\\k<v")) }
      end

      show(:utf16_into_utf8) { "abc".gsub("b", "x".encode("UTF-16LE")) }
      show(:utf16_into_utf8_sub_at_start) { "bc".sub("b", "x".encode("UTF-16LE")) }
      show(:utf16_into_utf8_sub_mid) { "abc".sub("b", "x".encode("UTF-16LE")) }
      show(:euc_into_ascii_utf8) { "abc".sub("b", "字".encode("EUC-JP")) }
      show(:euc_into_utf8) { "aéc".sub("c", "字".encode("EUC-JP")) }
      show(:euc_into_utf8_gsub) { "aéc".gsub("c", "字".encode("EUC-JP")) }
      show(:utf8_into_binary) { "a\xFFc".b.sub("c", "é") }
      show(:utf8_into_binary_gsub) { "abc".b.gsub("b", "é") }
      show(:group_of_binary) { "a\xFFc".b.sub(/(\xFF)/n, "é\\1") }
      show(:ascii_repl_utf16) { "héllo".encode("UTF-16LE").sub(Regexp.new("l".encode("UTF-16LE")), "L") }
      show(:block_utf16) { "abc".encode("UTF-32BE").gsub(Regexp.new("b".encode("UTF-32BE"))) { |m| m + m } }
      show(:hash_euc) { "abc".gsub(/b/, "b" => "字".encode("EUC-JP")) }
      show(:sub_bang) { s = +"hello".encode("UTF-16BE"); s.sub!(Regexp.new("(l+)".encode("UTF-16BE")), "<\\1>".encode("UTF-16BE")); s }
      show(:gsub_bang) { s = +"hello".encode("UTF-32LE"); s.gsub!(Regexp.new("l".encode("UTF-32LE")), "\\0\\0".encode("UTF-32LE")); s }

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [:named_ref, "UTF-8", "[a]b"]
      [:unknown_name, IndexError, "undefined group name reference: y"]
      [:open_name, RuntimeError, "invalid group name reference format"]
      [:bare_k, "UTF-8", "[\\k]b"]
      [:k_then_x, "UTF-8", "[\\kx]b"]
      [:trailing, "UTF-8", "x\\b"]
      [:double, "UTF-8", "x\\yb"]
      [:past_groups, "UTF-8", "[]b"]
      [:plus_none, "UTF-8", "[]b"]
      [:plus_last, "UTF-8", "[b]c"]
      [:numbered_under_names, "UTF-8", "[|]"]
      [:string_pattern, "UTF-8", "[a||a||b]b"]
      [:string_pattern_name, IndexError, "undefined group name reference: a"]
      [:duplicate_names, "UTF-8", "<x><y>"]
      [:other_escape, "UTF-8", "\\q\\nb"]
      [:escaped_multibyte, "UTF-8", "\\\xC3\xA9b"]
      [:name_multibyte, "UTF-8", "ab"]
      [:sjis_trail, "Shift_JIS", "\x95\\\x95\\0"]
      [:sjis_group, "Shift_JIS", "\x95\\\x95\\a"]
      [:sjis_gsub, "Shift_JIS", "\x95\\\x83\\\x95\\\x95\\\x83\\"]
      [:"UTF-16LE_groups", "UTF-16LE", "<\x00\xE9\x00h\x00h\x00\xE9\x00>\x00l\x00l\x00o\x00 \x00w\x00\xF6\x00r\x00l\x00d\x00"]
      [:"UTF-16LE_named", "UTF-16LE", "h\x00[\x00\xE9\x00]\x00l\x00l\x00o\x00 \x00w\x00[\x00\xF6\x00]\x00r\x00l\x00d\x00"]
      [:"UTF-16LE_pre_post", "UTF-16LE", "h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00|\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00"]
      [:"UTF-16LE_backslashes", "UTF-16LE", "h\x00\xE9\x00l\x00l\x00\\\x00\\\x00x\x00\\\x00 \x00w\x00\xF6\x00r\x00l\x00d\x00"]
      [:"UTF-16LE_plain", "UTF-16LE", "h\x00\xE9\x00L\x00L\x00o\x00 \x00w\x00\xF6\x00r\x00L\x00d\x00"]
      [:"UTF-16LE_bad_name", IndexError, "undefined group name reference: w"]
      [:"UTF-16LE_open_name", RuntimeError, "invalid group name reference format"]
      [:"UTF-16BE_groups", "UTF-16BE", "\x00<\x00\xE9\x00h\x00h\x00\xE9\x00>\x00l\x00l\x00o\x00 \x00w\x00\xF6\x00r\x00l\x00d"]
      [:"UTF-16BE_named", "UTF-16BE", "\x00h\x00[\x00\xE9\x00]\x00l\x00l\x00o\x00 \x00w\x00[\x00\xF6\x00]\x00r\x00l\x00d"]
      [:"UTF-16BE_pre_post", "UTF-16BE", "\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00|\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d"]
      [:"UTF-16BE_backslashes", "UTF-16BE", "\x00h\x00\xE9\x00l\x00l\x00\\\x00\\\x00x\x00\\\x00 \x00w\x00\xF6\x00r\x00l\x00d"]
      [:"UTF-16BE_plain", "UTF-16BE", "\x00h\x00\xE9\x00L\x00L\x00o\x00 \x00w\x00\xF6\x00r\x00L\x00d"]
      [:"UTF-16BE_bad_name", IndexError, "undefined group name reference: w"]
      [:"UTF-16BE_open_name", RuntimeError, "invalid group name reference format"]
      [:"UTF-32LE_groups", "UTF-32LE", "<\x00\x00\x00\xE9\x00\x00\x00h\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00>\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_named", "UTF-32LE", "h\x00\x00\x00[\x00\x00\x00\xE9\x00\x00\x00]\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00[\x00\x00\x00\xF6\x00\x00\x00]\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_pre_post", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00|\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_backslashes", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00\\\x00\x00\x00\\\x00\x00\x00x\x00\x00\x00\\\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_plain", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00L\x00\x00\x00L\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00L\x00\x00\x00d\x00\x00\x00"]
      [:"UTF-32LE_bad_name", IndexError, "undefined group name reference: w"]
      [:"UTF-32LE_open_name", RuntimeError, "invalid group name reference format"]
      [:"UTF-32BE_groups", "UTF-32BE", "\x00\x00\x00<\x00\x00\x00\xE9\x00\x00\x00h\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00>\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
      [:"UTF-32BE_named", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00[\x00\x00\x00\xE9\x00\x00\x00]\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00[\x00\x00\x00\xF6\x00\x00\x00]\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
      [:"UTF-32BE_pre_post", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00|\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
      [:"UTF-32BE_backslashes", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00\\\x00\x00\x00\\\x00\x00\x00x\x00\x00\x00\\\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
      [:"UTF-32BE_plain", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00L\x00\x00\x00L\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00L\x00\x00\x00d"]
      [:"UTF-32BE_bad_name", IndexError, "undefined group name reference: w"]
      [:"UTF-32BE_open_name", RuntimeError, "invalid group name reference format"]
      [:utf16_into_utf8, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and UTF-16LE"]
      [:utf16_into_utf8_sub_at_start, "UTF-16LE", "x\x00c"]
      [:utf16_into_utf8_sub_mid, "UTF-16LE", "ax\x00c"]
      [:euc_into_ascii_utf8, "EUC-JP", "a\xBB\xFAc"]
      [:euc_into_utf8, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and EUC-JP"]
      [:euc_into_utf8_gsub, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and EUC-JP"]
      [:utf8_into_binary, Encoding::CompatibilityError, "incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8"]
      [:utf8_into_binary_gsub, "UTF-8", "a\xC3\xA9c"]
      [:group_of_binary, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)"]
      [:ascii_repl_utf16, Encoding::CompatibilityError, "incompatible character encodings: UTF-16LE and UTF-8"]
      [:block_utf16, "UTF-32BE", "\x00\x00\x00a\x00\x00\x00b\x00\x00\x00b\x00\x00\x00c"]
      [:hash_euc, "EUC-JP", "a\xBB\xFAc"]
      [:sub_bang, "UTF-16BE", "\x00h\x00e\x00<\x00l\x00l\x00>\x00o"]
      [:gsub_bang, "UTF-32LE", "h\x00\x00\x00e\x00\x00\x00l\x00\x00\x00l\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00"]
    OUT
  end

  it "symbol breadth and to proc" do
    result = ze0(<<~'RUBY')
      # Symbol Tier A + the `&:sym` block-argument conversion
      # (`Symbol#to_proc`), previously unsupported.

      p :b <=> :a
      p :hello.length
      p :a.succ
      p :HeLLo.downcase
      p :he.to_s
      p :he.inspect
      p :he.upcase
      p :he.capitalize
      p :he.empty?
      p :upcase.to_proc.call("hi")
      p [3, 1, 2].map(&:to_s)
      p ["b", "a"].map(&:upcase)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      1
      5
      :b
      :hello
      "he"
      ":he"
      :HE
      :He
      false
      "HI"
      ["3", "1", "2"]
      ["B", "A"]
    OUT
  end

  it "symbol casecmp" do
    result = ze0(<<~'RUBY')
      # Symbol#casecmp and Symbol#casecmp? compare two symbols' names case-folded.
      # casecmp returns -1/0/1 (like <=>); casecmp? returns a boolean.
      # (String#casecmp/casecmp? already work; a couple are kept here as a guard.)
      def sy(x); x; end   # symbol receiver
      def st(x); x; end   # string receiver

      # casecmp orders case-insensitively
      p sy(:Foo).casecmp(:foo)      # 0
      p sy(:abc).casecmp(:abd)      # -1
      p sy(:b).casecmp(:A)          # 1  (case-folded: 'b' > 'a')
      p sy(:Foo).casecmp(:foobar)   # -1 (prefix is shorter)

      # casecmp? is the boolean case-insensitive equality
      p sy(:Foo).casecmp?(:foo)     # true
      p sy(:Foo).casecmp?(:FOO)     # true
      p sy(:Foo).casecmp?(:bar)     # false

      # literal-receiver forms
      p :HELLO.casecmp(:hello)      # 0
      p :HELLO.casecmp?(:world)     # false

      # usable directly in a condition
      puts(sy(:Yes).casecmp?(:yes) ? "match" : "no")   # match

      # String#casecmp / casecmp? remain correct
      p st("Foo").casecmp("FOO")    # 0
      p st("Foo").casecmp?("foo")   # true
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      0
      -1
      1
      -1
      true
      true
      false
      0
      false
      match
      0
      true
    OUT
  end

  it "symbol embedded nul" do
    result = ze0(<<~'RUBY')
      # A symbol's NAME may hold a NUL. Everything downstream of the parser lost it:
      # the compiler interned by strdup/strcmp, the emitted name table measured with
      # strlen, and the runtime intern compared with strcmp. The node table always
      # carried the byte -- nothing was lost before codegen.
      #
      # A symbol is an integer at run time, so equality, hash lookup and case/when
      # never touch a name; only interning, #to_s, ordering and inspect do.
      a = :"a\0b"
      b = "a\0b".to_sym

      p a.to_s.bytesize
      p b.to_s.bytesize
      p a == b
      p a.to_s == "a\0b"
      p a.to_s == "a"
      p a.to_s.bytes
      p a.length
      p a.size

      # distinct names that share a prefix up to the NUL stay distinct
      p :"a\0b" == :"a\0c"
      p :"a\0b" == :a
      p [:"a\0b", :"a\0c", :a].map { |s| s.to_s.bytesize }

      # ordering is byte-exact: strcmp called the first two equal
      p(:"a\0b" <=> :"a\0b")
      p(:"a\0b" <=> :"a\0c")
      p(:a <=> :"a\0b")
      p [:"a\0b", :a].sort.map { |s| s.to_s.bytesize }

      # hash keys keep them apart
      h = { a => 1, :a => 2 }
      p h.size
      p h[a]
      p h[b]
      p h[:a]

      # and the ordinary symbol surface is untouched
      p :abc.to_s
      p :abc == :abc
      p :abc == :abd
      p(:abc <=> :abd)
      p({ abc: 1 }[:abc])
      p :abc.inspect
      p :"a b".inspect
      p %i[x y].map(&:to_s)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      3
      true
      true
      false
      [97, 0, 98]
      3
      3
      false
      false
      [3, 3, 1]
      0
      -1
      -1
      [1, 3]
      2
      1
      1
      2
      "abc"
      true
      false
      -1
      1
      ":abc"
      ":\"a b\""
      ["x", "y"]
    OUT
  end

  it "symbol id2name ruby desc minmax" do
    result = ze0(<<~'RUBY')
      # #1249 Symbol#id2name: the symbol's name as a String (alias of to_s).
      p :hello.id2name
      p :foo_bar.id2name
      puts :sym.id2name.class

      # #1251 RUBY_DESCRIPTION is a String (value is engine-specific; only the
      # class is asserted so it stays portable).
      puts RUBY_DESCRIPTION.class

      # #1217 Range#minmax: [min, max], honouring exclusive end.
      p (1..10).minmax
      p (1...10).minmax
      p (5..5).minmax
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "hello"
      "foo_bar"
      String
      String
      [1, 10]
      [1, 9]
      [5, 5]
    OUT
  end

  it "symbol inspect quoting" do
    result = ze0(<<~'RUBY')
      # A symbol prints unquoted when its name is a plain identifier (incl. a
      # constant), an @ivar/@@cvar/$gvar, a name ending in ? ! =, or a known operator
      # method name; otherwise it is quoted like a string. Hash symbol keys use the
      # short `name:` form, quoting the name when needed.

      # plain identifiers and constants
      p :abc
      p :Foo
      p :_x9

      # variable-sigil names
      p :@iv
      p :@@cv
      p :$g

      # method-name suffixes
      p :foo?
      p :bar!
      p :baz=

      # every operator method symbol prints unquoted
      p :+
      p :-
      p :*
      p :/
      p :%
      p :**
      p :==
      p :===
      p :!=
      p :=~
      p :!~
      p :<
      p :<=
      p :>
      p :>=
      p :<=>
      p :<<
      p :>>
      p :&
      p :|
      p :^
      p :~
      p :!
      p :+@
      p :-@
      p :[]
      p :[]=
      p :`

      # names that REQUIRE quoting
      p :"a b"
      p :"1x"
      p :""
      p :"has\"quote"
      p :"with\nnewline"
      p :"foo?bar"
      p :"@"

      # the .inspect method (string-returning path) agrees with p
      puts :"a b".inspect
      puts :plain.inspect
      sym = :"x y"
      puts sym.inspect

      # symbol array and symbol-keyed hash
      p [:"a b", :ok, :+, :"with space"]
      p({a: 1, "k space": 2, normal: 3, "1bad": 4})
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :abc
      :Foo
      :_x9
      :@iv
      :@@cv
      :$g
      :foo?
      :bar!
      :baz=
      :+
      :-
      :*
      :/
      :%
      :**
      :==
      :===
      :!=
      :=~
      :!~
      :<
      :<=
      :>
      :>=
      :<=>
      :<<
      :>>
      :&
      :|
      :^
      :~
      :!
      :+@
      :-@
      :[]
      :[]=
      :`
      :"a b"
      :"1x"
      :""
      :"has\"quote"
      :"with\nnewline"
      :"foo?bar"
      :"@"
      :"a b"
      :plain
      :"x y"
      [:"a b", :ok, :+, :"with space"]
      {a: 1, "k space": 2, normal: 3, "1bad": 4}
    OUT
  end

  it "symbol nil bool float batch" do
    result = ze0(<<~'RUBY')
      # Symbol#intern/#name(frozen)/#casecmp(String), boolean & | ^ with Integer,
      # clone(freeze:) on immutable values, Float comparison/to_int/coerce edges,
      # nil <=> / rationalize / =~ / !~.

      # Symbol
      p(:hello.intern)
      s = :hello
      p(s.intern)
      p(:hello.name.frozen?)
      p(:hello.name)
      p(:HELLO.casecmp("hello"))
      p(:HELLO.casecmp?("hello"))
      p(:abc.casecmp(:ABD))
      p(:abc.casecmp?(:ABC))

      # true/false & | ^ with an Integer operand (0 is truthy)
      p(true & 0)
      p(true & 2)
      p(false | 0)
      p(true ^ 0)
      p(false ^ 0)
      a = true
      b = 0
      p(a & b)

      # clone(freeze:) on immutable values
      p(true.clone.class)
      p(true.clone(freeze: true).class)
      p(false.clone(freeze: true).class)
      p(nil.clone(freeze: true).class)
      p(1.clone(freeze: true).class)

      # Float comparisons with non-numeric operands raise ArgumentError
      f = 1.5
      begin
        p(f < nil)
      rescue => e
        p e.class
      end
      begin
        p(f > Object.new)
      rescue => e
        p e.class
      end

      # Float#to_int on Infinity/NaN raises FloatDomainError like to_i
      begin
        p(Float::INFINITY.to_int)
      rescue => e
        p e.class
      end
      begin
        p(Float::NAN.to_int)
      rescue => e
        p e.class
      end
      p(3.9.to_int)

      # Float#coerce with Rational/Complex arguments
      p(1.0.coerce(Rational(1, 2)))
      p(2.0.coerce(Complex(1, 0)))
      p(1.0.coerce(2))

      # nil <=> / rationalize / =~ / !~
      p(nil <=> nil)
      p(nil <=> 1)
      p(nil.rationalize)
      p(nil =~ /x/)
      p(nil !~ /x/)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :hello
      :hello
      true
      "hello"
      nil
      nil
      -1
      true
      true
      true
      true
      false
      true
      true
      TrueClass
      TrueClass
      FalseClass
      NilClass
      Integer
      ArgumentError
      ArgumentError
      FloatDomainError
      FloatDomainError
      3
      [0.5, 1.0]
      [1.0, 2.0]
      [2.0, 1.0]
      0
      nil
      (0/1)
      nil
      true
    OUT
  end

  it "symbol nil truthiness" do
    result = ze0(<<~'RUBY')
      # A nilable symbol slot stores (sp_sym)-1 as its nil sentinel. Truthiness
      # in conditions and in the value form of && / || must test the sentinel;
      # it used to read always-true, so `if @exit_triggered` fired on nil.

      class Level
        def initialize
          @exit_triggered = nil
        end

        def trigger(kind)
          @exit_triggered = kind
        end

        def check
          if @exit_triggered
            "exit:#{@exit_triggered}"
          else
            "playing"
          end
        end

        def check_and(intermission)
          # value-form && with a symbol left arm
          (@exit_triggered && !intermission) ? "finish" : "continue"
        end

        def sym_or_default
          @exit_triggered || :none
        end
      end

      lvl = Level.new
      puts lvl.check
      puts lvl.check_and(false)
      p lvl.sym_or_default
      lvl.trigger(:normal)
      puts lvl.check
      puts lvl.check_and(false)
      puts lvl.check_and(true)
      p lvl.sym_or_default

      # ||= / &&= on nilable symbol slots (ivar and local, statement and value form)
      class Cache
        def initialize
          @mode = nil
        end
        def mode_or_default
          @mode ||= :easy
        end
        def try_upgrade
          @mode &&= :hard
          @mode
        end
        def reset
          @mode = nil
        end
      end

      c = Cache.new
      p c.mode_or_default
      p c.mode_or_default
      p c.try_upgrade
      c.reset
      p c.try_upgrade

      def lsym(start)
        s = start ? :given : nil
        s ||= :fallback
        got = (s &&= :promoted)
        [s, got]
      end
      p lsym(true)
      p lsym(false)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      playing
      continue
      :none
      exit:normal
      finish
      continue
      :normal
      :easy
      :easy
      :hard
      nil
      [:promoted, :promoted]
      [:promoted, :promoted]
    OUT
  end

  it "symbol proc absent method" do
    result = ze0(<<~'RUBY')
      # max_by / min_by / sort_by with a symbol-proc naming a method the element does
      # not have compiles and raises NoMethodError, as map with the same proc does.
      a = ([1, 2].max_by(&:foo) rescue $!.class); p a
      b = ([1, 2].min_by(&:foo) rescue $!.class); p b
      c = ([1, 2].sort_by(&:foo) rescue $!.class); p c
      d = ([1, 2].map(&:foo) rescue $!.class); p d
      e = (["a", "b"].max_by(&:nope) rescue $!.class); p e
      p [1, 2].max_by(&:abs)
      p [3, 1, 2].sort_by { |x| -x }
      p [1, 2, 3].min_by(&:abs)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      2
      [3, 2, 1]
      1
    OUT
  end

  it "symbol range enum" do
    result = ze0(<<~'RUBY')
      # (:a..:e): a symbol-endpoint range enumerates by name succession --
      # the range lowers to a poly array of boxed symbols (to_a/map/each/
      # include?, exclusive ends, multi-char names).
      p (:a..:e).to_a
      p((:a..:c).map(&:to_s))
      p (:a...:d).to_a
      acc = []
      (:x..:z).each { |s| acc << s }
      p acc
      p (:a..:e).include?(:c)
      p (:aa..:ac).to_a
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [:a, :b, :c, :d, :e]
      ["a", "b", "c"]
      [:a, :b, :c]
      [:x, :y, :z]
      true
      [:aa, :ab, :ac]
    OUT
  end

  it "symbol string methods" do
    result = ze0(<<~'RUBY')
      # Symbol string-surface methods, lowered over the symbol's name: index/slice
      # yield a substring (or nil), succ re-interns a symbol, and start_with?/
      # end_with?/match? yield a bool. Receivers go through a method param so the
      # symbol value reaches the runtime path rather than being folded.
      def wrap(x); x; end

      p wrap(:hello)[1]
      p wrap(:hello)[1, 3]
      p wrap(:hello)[10]
      # a Range index yields a substring (inclusive, exclusive, and endless forms)
      p wrap(:hello)[1..3]
      p wrap(:hello)[1...3]
      p wrap(:hello)[2..]
      p wrap(:abc).succ
      p wrap(:az).succ
      p wrap(:hello).start_with?("he")
      p wrap(:hello).start_with?("xx")
      p wrap(:hello).end_with?("lo")
      p wrap(:hello).end_with?("xx")
      p wrap(:hello).match?(/ell/)
      p wrap(:hello).match?(/zzz/)

      # match? also works when the pattern is a non-literal regex (a local / param),
      # matching over the symbol's name rather than the raw symbol value.
      rx = /^he/
      p wrap(:hello).match?(rx)
      def sym_match(s, r); s.match?(r); end
      p sym_match(:hello, /lo$/)
      p sym_match(:hello, /zzz/)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "e"
      "ell"
      nil
      "ell"
      "el"
      "llo"
      :abd
      :ba
      true
      false
      true
      false
      true
      false
      true
      true
      false
    OUT
  end

  it "symbol to proc after positional" do
    result = ze0(<<~'RUBY')
      # &:symbol block-pass after a positional argument must parse as a
      # symbol-to-proc block, not a hash literal -- in both parenthesized
      # and command (paren-less) calls. Front-door blocker for bundler
      # (File.open(f, "r:UTF-8", &:read)) and minitest
      # (define_method :mu_pp, &:pretty_inspect).
      class Widget
        define_method(:as_str, &:to_s)   # parenthesized, after a positional
      end

      class Gadget
        define_method :label, &:to_s     # command (paren-less), after a positional
      end

      puts Widget.new.as_str(7)
      puts Gadget.new.label(8)
      p [1, 2, 3].map(&:to_s)            # sole arg in parens (regression guard)
      p [1, 2, 3].map &:to_s            # command-position sole arg
      p [10, 20, 30].inject(0, &:+)     # operator symbol after a positional (native)
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      7
      8
      ["1", "2", "3"]
      ["1", "2", "3"]
      60
    OUT
  end

  it "symbol to proc call" do
    result = ze0(<<~'RUBY')
      # Explicit Symbol#to_proc applied with a call: :sym.to_proc.call(recv, *args)
      # invokes the named method on the first argument. With the symbol and the call
      # site statically known, it lowers to an ordinary recv.sym(*args) method call.
      # (The &:sym block form is unaffected; a to_proc held in a variable is a
      # separate, still-unsupported case.)
      def ss(x); x; end   # string receiver (per-type helper avoids poly widening)
      def si(x); x; end   # integer receiver

      # a no-argument method on the receiver
      p :upcase.to_proc.call("hi")          # "HI"
      p :length.to_proc.call("hello")       # 5
      p :succ.to_proc.call(5)               # 6
      p :to_s.to_proc.call(42)              # "42"

      # a method that takes extra arguments (receiver first, then the rest)
      p :+.to_proc.call(2, 3)               # 5
      p :*.to_proc.call(3, 4)               # 12

      # the .() call shorthand lowers the same way
      p :downcase.to_proc.("HI")            # "hi"

      # receiver routed through a method parameter (runtime-typed path)
      p :upcase.to_proc.call(ss("world"))   # "WORLD"
      p :abs.to_proc.call(si(-7))           # 7

      # the &:sym block form still works
      p ["a", "b", "c"].map(&:upcase)       # ["A", "B", "C"]
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "HI"
      5
      6
      "42"
      5
      12
      "hi"
      "WORLD"
      7
      ["A", "B", "C"]
    OUT
  end

  it "symbol to proc forwards block" do
    result = ze0(<<~'RUBY')
      p :map.to_proc.call([1, 2]) { |x| x * 3 }
      p :each.to_proc.call([1, 2]) { |x| }
      p :select.to_proc.call([1, 2, 3]) { |x| x.odd? }
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      [3, 6]
      [1, 2]
      [1, 3]
    OUT
  end

  it "symbol to proc is lambda and hash values at uses default" do
    result = ze0(<<~'RUBY')
      # :name.to_proc.lambda? is true (CRuby). Hash#values_at routes each key
      # through [], so a missing key yields the hash's default, not bare nil.

      p :upcase.to_proc.lambda?
      p ["x", "y"].map(&:upcase)
      p Hash.new(0).values_at(:x, :y)
      p({ a: 1 }.values_at(:a, :z))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      true
      ["X", "Y"]
      [0, 0]
      [1, nil]
    OUT
  end

  it "symbol upcase interpolation" do
    result = ze0(<<~'RUBY')
      # Symbol#upcase / #downcase on a method-returned (branch-poly) symbol
      # inside string interpolation lowers through sp_sym_intern. The runtime
      # helper is gated on @needs_sym_intern, which analyze set as a memoized
      # side effect and missed for this shape -> link failure on the call.
      # Found via the spinelgems harness (nagiosplugin).
      class P
        def status(n)
          return :critical if n > 2
          return :warning if n > 1
          :ok
        end
        def output(n)
          "X #{status(n).upcase}"
        end
        def lower(n)
          "y #{status(n).downcase}"
        end
      end

      puts P.new.output(3)
      puts P.new.output(2)
      puts P.new.output(1)
      puts P.new.lower(3)
      puts "hi".to_sym.inspect
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      X CRITICAL
      X WARNING
      X OK
      y critical
      :hi
    OUT
  end

  it "the tr family counts characters not bytes" do
    result = ze0(<<~'RUBY')
      # tr, tr_s, count, delete and squeeze read a spec as characters, so a
      # multibyte character is one member of the set and one place in the
      # replacement. A range spans codepoints.
      p "あいう".tr("い", "X")
      p "あいう".tr("あ-う", "A-C")
      p "あいあいあ".count("あ")
      p "あいあいあ".delete("い")
      p "ああいいうう".squeeze
      p "あいう".count("^あ")
      p "あいう".delete("^あ")
      p "あいあ".squeeze("あ")
      p "\u{1F600}b".tr("\u{1F600}", "X")
      p "あああいいい".tr_s("あい", "AI")

      # The ASCII rules are unchanged.
      p "hello".tr("el", "ip")
      p "abc".tr("aa", "XY")
      p "abc".tr("^a", "Z")
      p "abc".tr("a-", "X")
      p "a-c".tr("\\-", "X")
      p "abc".tr("a", "")
      p "abc".tr("^", "X")
      p "abcdef".tr("a-cd", "1-4")
      p "abc".count("a-c", "^b")
      begin
        "abc".tr("c-a", "X")
      rescue ArgumentError => e
        p e.message
      end
      begin
        "abc".count(1)
      rescue TypeError => e
        p e.message
      end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "あXう"
      "ACC"
      3
      "あああ"
      "あいう"
      2
      "あ"
      "あいあ"
      "Xb"
      "AI"
      "hippo"
      "Ybc"
      "aZZ"
      "Xbc"
      "aXc"
      "bc"
      "abc"
      "1234ef"
      2
      "invalid range \"c-a\" in string transliteration"
      "no implicit conversion of Integer into String"
    OUT
  end

  it "to i agrees with integer and the split forms agree" do
    result = ze0(<<~'RUBY')
      # to_i, Integer() and the split forms answer over the same texts as
      # ruby's: blanks, signs, underscores, prefixes, bases and separators
      # of every kind, and split with a block.
      texts = ["12", " 12", "12 ", "+12", "-12", "1_2", "1__2", "_12", "12_", "0x1f", "0b11", "0o17", "017", "0d19", "12abc", "abc", "", "  ", "\t\n12", "12\n", "9" * 25, "-" + "9" * 25, "1e3", "1.5", "٣"]
      texts.each { |t| print t.inspect, " ", t.to_i, " ", (Integer(t) rescue "err"), " ", t.to_i(16), " ", t.to_i(2), "\n" }
      lines = ["a,b,c", "a,,b", ",a,", "abc", "", "a b  c", " a b ", "a\tb\nc", "a--b--c", "日本語、テキスト"]
      seps = [",", "", " ", nil, "--", "、", /,/, /\s+/, /(,)/]
      lines.each do |l|
        seps.each do |s|
          [0, 2, -1].each do |limit|
            r = (s.nil? ? l.split : l.split(s, limit)) rescue $!.class
            print l.inspect, " ", s.inspect, " ", limit, " ", r.inspect, "\n"
          end
        end
      end
      out = []
      "a,b,c".split(",") { |piece| out << piece.upcase }
      p out, "a,b".split(",").map(&:frozen?), "a,b".split(",").map(&:encoding).uniq.size
      $; = "-"
      p "x-y".split
      $; = nil

    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "12" 12 12 18 1
      " 12" 12 12 18 1
      "12 " 12 12 18 1
      "+12" 12 12 18 1
      "-12" -12 -12 -18 -1
      "1_2" 12 12 18 1
      "1__2" 1 err 1 1
      "_12" 0 err 0 0
      "12_" 12 err 18 1
      "0x1f" 0 31 31 0
      "0b11" 0 3 2833 3
      "0o17" 0 15 0 0
      "017" 17 15 23 1
      "0d19" 19 19 3353 0
      "12abc" 12 err 76476 1
      "abc" 0 err 2748 0
      "" 0 err 0 0
      "  " 0 err 0 0
      "\t\n12" 12 12 18 1
      "12\n" 12 12 18 1
      "9999999999999999999999999" 9999999999999999999999999 9999999999999999999999999 760590360136937640898021923225 0
      "-9999999999999999999999999" -9999999999999999999999999 -9999999999999999999999999 -760590360136937640898021923225 0
      "1e3" 1 err 483 1
      "1.5" 1 err 1 1
      "٣" 0 err 0 0
      "a,b,c" "," 0 ["a", "b", "c"]
      "a,b,c" "," 2 ["a", "b,c"]
      "a,b,c" "," -1 ["a", "b", "c"]
      "a,b,c" "" 0 ["a", ",", "b", ",", "c"]
      "a,b,c" "" 2 ["a", ",b,c"]
      "a,b,c" "" -1 ["a", ",", "b", ",", "c", ""]
      "a,b,c" " " 0 ["a,b,c"]
      "a,b,c" " " 2 ["a,b,c"]
      "a,b,c" " " -1 ["a,b,c"]
      "a,b,c" nil 0 ["a,b,c"]
      "a,b,c" nil 2 ["a,b,c"]
      "a,b,c" nil -1 ["a,b,c"]
      "a,b,c" "--" 0 ["a,b,c"]
      "a,b,c" "--" 2 ["a,b,c"]
      "a,b,c" "--" -1 ["a,b,c"]
      "a,b,c" "、" 0 ["a,b,c"]
      "a,b,c" "、" 2 ["a,b,c"]
      "a,b,c" "、" -1 ["a,b,c"]
      "a,b,c" /,/ 0 ["a", "b", "c"]
      "a,b,c" /,/ 2 ["a", "b,c"]
      "a,b,c" /,/ -1 ["a", "b", "c"]
      "a,b,c" /\s+/ 0 ["a,b,c"]
      "a,b,c" /\s+/ 2 ["a,b,c"]
      "a,b,c" /\s+/ -1 ["a,b,c"]
      "a,b,c" /(,)/ 0 ["a", ",", "b", ",", "c"]
      "a,b,c" /(,)/ 2 ["a", ",", "b,c"]
      "a,b,c" /(,)/ -1 ["a", ",", "b", ",", "c"]
      "a,,b" "," 0 ["a", "", "b"]
      "a,,b" "," 2 ["a", ",b"]
      "a,,b" "," -1 ["a", "", "b"]
      "a,,b" "" 0 ["a", ",", ",", "b"]
      "a,,b" "" 2 ["a", ",,b"]
      "a,,b" "" -1 ["a", ",", ",", "b", ""]
      "a,,b" " " 0 ["a,,b"]
      "a,,b" " " 2 ["a,,b"]
      "a,,b" " " -1 ["a,,b"]
      "a,,b" nil 0 ["a,,b"]
      "a,,b" nil 2 ["a,,b"]
      "a,,b" nil -1 ["a,,b"]
      "a,,b" "--" 0 ["a,,b"]
      "a,,b" "--" 2 ["a,,b"]
      "a,,b" "--" -1 ["a,,b"]
      "a,,b" "、" 0 ["a,,b"]
      "a,,b" "、" 2 ["a,,b"]
      "a,,b" "、" -1 ["a,,b"]
      "a,,b" /,/ 0 ["a", "", "b"]
      "a,,b" /,/ 2 ["a", ",b"]
      "a,,b" /,/ -1 ["a", "", "b"]
      "a,,b" /\s+/ 0 ["a,,b"]
      "a,,b" /\s+/ 2 ["a,,b"]
      "a,,b" /\s+/ -1 ["a,,b"]
      "a,,b" /(,)/ 0 ["a", ",", "", ",", "b"]
      "a,,b" /(,)/ 2 ["a", ",", ",b"]
      "a,,b" /(,)/ -1 ["a", ",", "", ",", "b"]
      ",a," "," 0 ["", "a"]
      ",a," "," 2 ["", "a,"]
      ",a," "," -1 ["", "a", ""]
      ",a," "" 0 [",", "a", ","]
      ",a," "" 2 [",", "a,"]
      ",a," "" -1 [",", "a", ",", ""]
      ",a," " " 0 [",a,"]
      ",a," " " 2 [",a,"]
      ",a," " " -1 [",a,"]
      ",a," nil 0 [",a,"]
      ",a," nil 2 [",a,"]
      ",a," nil -1 [",a,"]
      ",a," "--" 0 [",a,"]
      ",a," "--" 2 [",a,"]
      ",a," "--" -1 [",a,"]
      ",a," "、" 0 [",a,"]
      ",a," "、" 2 [",a,"]
      ",a," "、" -1 [",a,"]
      ",a," /,/ 0 ["", "a"]
      ",a," /,/ 2 ["", "a,"]
      ",a," /,/ -1 ["", "a", ""]
      ",a," /\s+/ 0 [",a,"]
      ",a," /\s+/ 2 [",a,"]
      ",a," /\s+/ -1 [",a,"]
      ",a," /(,)/ 0 ["", ",", "a", ","]
      ",a," /(,)/ 2 ["", ",", "a,"]
      ",a," /(,)/ -1 ["", ",", "a", ",", ""]
      "abc" "," 0 ["abc"]
      "abc" "," 2 ["abc"]
      "abc" "," -1 ["abc"]
      "abc" "" 0 ["a", "b", "c"]
      "abc" "" 2 ["a", "bc"]
      "abc" "" -1 ["a", "b", "c", ""]
      "abc" " " 0 ["abc"]
      "abc" " " 2 ["abc"]
      "abc" " " -1 ["abc"]
      "abc" nil 0 ["abc"]
      "abc" nil 2 ["abc"]
      "abc" nil -1 ["abc"]
      "abc" "--" 0 ["abc"]
      "abc" "--" 2 ["abc"]
      "abc" "--" -1 ["abc"]
      "abc" "、" 0 ["abc"]
      "abc" "、" 2 ["abc"]
      "abc" "、" -1 ["abc"]
      "abc" /,/ 0 ["abc"]
      "abc" /,/ 2 ["abc"]
      "abc" /,/ -1 ["abc"]
      "abc" /\s+/ 0 ["abc"]
      "abc" /\s+/ 2 ["abc"]
      "abc" /\s+/ -1 ["abc"]
      "abc" /(,)/ 0 ["abc"]
      "abc" /(,)/ 2 ["abc"]
      "abc" /(,)/ -1 ["abc"]
      "" "," 0 []
      "" "," 2 []
      "" "," -1 []
      "" "" 0 []
      "" "" 2 []
      "" "" -1 []
      "" " " 0 []
      "" " " 2 []
      "" " " -1 []
      "" nil 0 []
      "" nil 2 []
      "" nil -1 []
      "" "--" 0 []
      "" "--" 2 []
      "" "--" -1 []
      "" "、" 0 []
      "" "、" 2 []
      "" "、" -1 []
      "" /,/ 0 []
      "" /,/ 2 []
      "" /,/ -1 []
      "" /\s+/ 0 []
      "" /\s+/ 2 []
      "" /\s+/ -1 []
      "" /(,)/ 0 []
      "" /(,)/ 2 []
      "" /(,)/ -1 []
      "a b  c" "," 0 ["a b  c"]
      "a b  c" "," 2 ["a b  c"]
      "a b  c" "," -1 ["a b  c"]
      "a b  c" "" 0 ["a", " ", "b", " ", " ", "c"]
      "a b  c" "" 2 ["a", " b  c"]
      "a b  c" "" -1 ["a", " ", "b", " ", " ", "c", ""]
      "a b  c" " " 0 ["a", "b", "c"]
      "a b  c" " " 2 ["a", "b  c"]
      "a b  c" " " -1 ["a", "b", "c"]
      "a b  c" nil 0 ["a", "b", "c"]
      "a b  c" nil 2 ["a", "b", "c"]
      "a b  c" nil -1 ["a", "b", "c"]
      "a b  c" "--" 0 ["a b  c"]
      "a b  c" "--" 2 ["a b  c"]
      "a b  c" "--" -1 ["a b  c"]
      "a b  c" "、" 0 ["a b  c"]
      "a b  c" "、" 2 ["a b  c"]
      "a b  c" "、" -1 ["a b  c"]
      "a b  c" /,/ 0 ["a b  c"]
      "a b  c" /,/ 2 ["a b  c"]
      "a b  c" /,/ -1 ["a b  c"]
      "a b  c" /\s+/ 0 ["a", "b", "c"]
      "a b  c" /\s+/ 2 ["a", "b  c"]
      "a b  c" /\s+/ -1 ["a", "b", "c"]
      "a b  c" /(,)/ 0 ["a b  c"]
      "a b  c" /(,)/ 2 ["a b  c"]
      "a b  c" /(,)/ -1 ["a b  c"]
      " a b " "," 0 [" a b "]
      " a b " "," 2 [" a b "]
      " a b " "," -1 [" a b "]
      " a b " "" 0 [" ", "a", " ", "b", " "]
      " a b " "" 2 [" ", "a b "]
      " a b " "" -1 [" ", "a", " ", "b", " ", ""]
      " a b " " " 0 ["a", "b"]
      " a b " " " 2 ["a", "b "]
      " a b " " " -1 ["a", "b", ""]
      " a b " nil 0 ["a", "b"]
      " a b " nil 2 ["a", "b"]
      " a b " nil -1 ["a", "b"]
      " a b " "--" 0 [" a b "]
      " a b " "--" 2 [" a b "]
      " a b " "--" -1 [" a b "]
      " a b " "、" 0 [" a b "]
      " a b " "、" 2 [" a b "]
      " a b " "、" -1 [" a b "]
      " a b " /,/ 0 [" a b "]
      " a b " /,/ 2 [" a b "]
      " a b " /,/ -1 [" a b "]
      " a b " /\s+/ 0 ["", "a", "b"]
      " a b " /\s+/ 2 ["", "a b "]
      " a b " /\s+/ -1 ["", "a", "b", ""]
      " a b " /(,)/ 0 [" a b "]
      " a b " /(,)/ 2 [" a b "]
      " a b " /(,)/ -1 [" a b "]
      "a\tb\nc" "," 0 ["a\tb\nc"]
      "a\tb\nc" "," 2 ["a\tb\nc"]
      "a\tb\nc" "," -1 ["a\tb\nc"]
      "a\tb\nc" "" 0 ["a", "\t", "b", "\n", "c"]
      "a\tb\nc" "" 2 ["a", "\tb\nc"]
      "a\tb\nc" "" -1 ["a", "\t", "b", "\n", "c", ""]
      "a\tb\nc" " " 0 ["a", "b", "c"]
      "a\tb\nc" " " 2 ["a", "b\nc"]
      "a\tb\nc" " " -1 ["a", "b", "c"]
      "a\tb\nc" nil 0 ["a", "b", "c"]
      "a\tb\nc" nil 2 ["a", "b", "c"]
      "a\tb\nc" nil -1 ["a", "b", "c"]
      "a\tb\nc" "--" 0 ["a\tb\nc"]
      "a\tb\nc" "--" 2 ["a\tb\nc"]
      "a\tb\nc" "--" -1 ["a\tb\nc"]
      "a\tb\nc" "、" 0 ["a\tb\nc"]
      "a\tb\nc" "、" 2 ["a\tb\nc"]
      "a\tb\nc" "、" -1 ["a\tb\nc"]
      "a\tb\nc" /,/ 0 ["a\tb\nc"]
      "a\tb\nc" /,/ 2 ["a\tb\nc"]
      "a\tb\nc" /,/ -1 ["a\tb\nc"]
      "a\tb\nc" /\s+/ 0 ["a", "b", "c"]
      "a\tb\nc" /\s+/ 2 ["a", "b\nc"]
      "a\tb\nc" /\s+/ -1 ["a", "b", "c"]
      "a\tb\nc" /(,)/ 0 ["a\tb\nc"]
      "a\tb\nc" /(,)/ 2 ["a\tb\nc"]
      "a\tb\nc" /(,)/ -1 ["a\tb\nc"]
      "a--b--c" "," 0 ["a--b--c"]
      "a--b--c" "," 2 ["a--b--c"]
      "a--b--c" "," -1 ["a--b--c"]
      "a--b--c" "" 0 ["a", "-", "-", "b", "-", "-", "c"]
      "a--b--c" "" 2 ["a", "--b--c"]
      "a--b--c" "" -1 ["a", "-", "-", "b", "-", "-", "c", ""]
      "a--b--c" " " 0 ["a--b--c"]
      "a--b--c" " " 2 ["a--b--c"]
      "a--b--c" " " -1 ["a--b--c"]
      "a--b--c" nil 0 ["a--b--c"]
      "a--b--c" nil 2 ["a--b--c"]
      "a--b--c" nil -1 ["a--b--c"]
      "a--b--c" "--" 0 ["a", "b", "c"]
      "a--b--c" "--" 2 ["a", "b--c"]
      "a--b--c" "--" -1 ["a", "b", "c"]
      "a--b--c" "、" 0 ["a--b--c"]
      "a--b--c" "、" 2 ["a--b--c"]
      "a--b--c" "、" -1 ["a--b--c"]
      "a--b--c" /,/ 0 ["a--b--c"]
      "a--b--c" /,/ 2 ["a--b--c"]
      "a--b--c" /,/ -1 ["a--b--c"]
      "a--b--c" /\s+/ 0 ["a--b--c"]
      "a--b--c" /\s+/ 2 ["a--b--c"]
      "a--b--c" /\s+/ -1 ["a--b--c"]
      "a--b--c" /(,)/ 0 ["a--b--c"]
      "a--b--c" /(,)/ 2 ["a--b--c"]
      "a--b--c" /(,)/ -1 ["a--b--c"]
      "日本語、テキスト" "," 0 ["日本語、テキスト"]
      "日本語、テキスト" "," 2 ["日本語、テキスト"]
      "日本語、テキスト" "," -1 ["日本語、テキスト"]
      "日本語、テキスト" "" 0 ["日", "本", "語", "、", "テ", "キ", "ス", "ト"]
      "日本語、テキスト" "" 2 ["日", "本語、テキスト"]
      "日本語、テキスト" "" -1 ["日", "本", "語", "、", "テ", "キ", "ス", "ト", ""]
      "日本語、テキスト" " " 0 ["日本語、テキスト"]
      "日本語、テキスト" " " 2 ["日本語、テキスト"]
      "日本語、テキスト" " " -1 ["日本語、テキスト"]
      "日本語、テキスト" nil 0 ["日本語、テキスト"]
      "日本語、テキスト" nil 2 ["日本語、テキスト"]
      "日本語、テキスト" nil -1 ["日本語、テキスト"]
      "日本語、テキスト" "--" 0 ["日本語、テキスト"]
      "日本語、テキスト" "--" 2 ["日本語、テキスト"]
      "日本語、テキスト" "--" -1 ["日本語、テキスト"]
      "日本語、テキスト" "、" 0 ["日本語", "テキスト"]
      "日本語、テキスト" "、" 2 ["日本語", "テキスト"]
      "日本語、テキスト" "、" -1 ["日本語", "テキスト"]
      "日本語、テキスト" /,/ 0 ["日本語、テキスト"]
      "日本語、テキスト" /,/ 2 ["日本語、テキスト"]
      "日本語、テキスト" /,/ -1 ["日本語、テキスト"]
      "日本語、テキスト" /\s+/ 0 ["日本語、テキスト"]
      "日本語、テキスト" /\s+/ 2 ["日本語、テキスト"]
      "日本語、テキスト" /\s+/ -1 ["日本語、テキスト"]
      "日本語、テキスト" /(,)/ 0 ["日本語、テキスト"]
      "日本語、テキスト" /(,)/ 2 ["日本語、テキスト"]
      "日本語、テキスト" /(,)/ -1 ["日本語、テキスト"]
      ["A", "B", "C"]
      [false, false]
      1
      ["x", "y"]
    OUT
  end

  it "to i and a string split scan bytes in the kernel" do
    result = ze0(<<~'RUBY')
      # String#to_i in base 10 and a split by a String read their bytes in
      # the kernel: the same answers as ruby's for blanks, signs,
      # underscores, a `0d` prefix, numbers past a fixnum, and for pieces
      # with limits, empty pieces, multibyte separators and encodings.
      p "42".to_i, " \t\n\v\f\r42".to_i, "-42".to_i, "+42".to_i, "4_2".to_i, "4__2".to_i, "_42".to_i, "42_".to_i, "42abc".to_i, "abc".to_i, "".to_i
      p "0d42".to_i, "-0d42".to_i, " 0D42".to_i, "00d42".to_i, "10d".to_i, "0_d5".to_i, "0d".to_i, "0x1f".to_i, "0b101".to_i, "0o17".to_i, "017".to_i
      p "9223372036854775807".to_i, "4611686018427387903".to_i, "4611686018427387904".to_i, "-4611686018427387904".to_i, "123456789012345678901234567890".to_i, "000000000000000000000042".to_i
      p "1e5".to_i, "1.9".to_i, " 42".to_i, "４２".to_i, "42\0".to_i, "\0 42".to_i, "1_000_000".to_i, "12".to_i(10), "12".to_i(16), "z".to_i(36)
      p "a,b,c".split(","), "a,,b,,".split(","), "a,,b,,".split(",", -1), "a,b,c".split(",", 2), "a,b,c".split(",", 1), ",a".split(","), "".split(","), ",".split(",")
      p "a--b--c".split("--"), "a--b".split("-"), "abc".split("abc"), "abcabc".split("abc", -1), "aXbXc".split("X", 0), "a b  c".split(" "), "a\tb".split("\t")
      p "héllo wörld".split("ö"), "日本語、テキスト、です".split("、"), "日本".split("本", -1), "ab".split("c"), "a,b".split(",", 3), "a,b,c,d".split(",", -2)
      p "a,b".split(",").map(&:encoding).uniq, "a,b".b.split(",").first.encoding, "x".encode("UTF-16LE").split("x".encode("UTF-16LE")).size
      p (("a,b".split("é".encode("ISO-8859-1"))) rescue $!.class), ("ab".split("\xff") rescue $!.class), "ab".split("b".b)
      p "a,b,c".split(",") { |piece| print piece.upcase, " " }, "csv,line,here".split(",").map(&:size)


    RUBY

    _(result.stdout).must_equal <<~'OUT'
      42
      42
      -42
      42
      42
      4
      0
      42
      42
      0
      0
      42
      -42
      42
      0
      10
      0
      0
      0
      0
      0
      17
      9223372036854775807
      4611686018427387903
      4611686018427387904
      -4611686018427387904
      123456789012345678901234567890
      42
      1
      1
      0
      0
      42
      0
      1000000
      12
      18
      35
      ["a", "b", "c"]
      ["a", "", "b"]
      ["a", "", "b", "", ""]
      ["a", "b,c"]
      ["a,b,c"]
      ["", "a"]
      []
      []
      ["a", "b", "c"]
      ["a", "", "b"]
      []
      ["", "", ""]
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b"]
      ["héllo w", "rld"]
      ["日本語", "テキスト", "です"]
      ["日", ""]
      ["ab"]
      ["a", "b"]
      ["a", "b", "c", "d"]
      [#<Encoding:UTF-8>]
      #<Encoding:BINARY (ASCII-8BIT)>
      0
      ["a,b"]
      ArgumentError
      ["a"]
      A B C "a,b,c"
      [3, 4, 4]
    OUT
  end

  it "tr squeeze negation split block and chomp paragraph" do
    result = ze0(<<~'RUBY')
      # `^`-negated tr/squeeze sets, split's block form (yields fields, returns
      # the receiver), and chomp("") paragraph mode.

      p "abc".tr("^a", "x")
      p "hello".tr("^aeiou", ".")
      p "aaabbbccc".squeeze("^a")
      p "aaa^^^bbb".squeeze("^")
      r = []
      "a,b,c".split(",") { |p| r << p.upcase }
      p r
      acc = 0
      ret = "aa-bbb-c".split("-") { |p| acc += p.length }
      p acc
      p ret.equal?("aa-bbb-c".dup) == false && ret == "aa-bbb-c"
      p "hello\r\n\r\n".chomp("")
      p "hello\r".chomp("")
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      "axx"
      ".e..o"
      "aaabc"
      "aaa^bbb"
      ["A", "B", "C"]
      6
      true
      "hello"
      "hello\r"
    OUT
  end

  it "user to s and inspect drive puts interpolation and p" do
    result = ze0(<<~'RUBY')
      class Named
        def initialize(n)
          @n = n
        end

        def to_s
          "Named<#{@n}>"
        end

        def inspect
          "#<Named n=#{@n}>"
        end
      end

      n = Named.new(7)
      puts n
      puts "in a string: #{n}"
      p n
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      Named<7>
      in a string: Named<7>
      #<Named n=7>
    OUT
  end

  it "value subclass of string equality and hashing" do
    result = ze0(<<~'RUBY')
      # A `String` subclass (D3): inherited `String` methods, a `super`-free custom
      # method, `dup` independence, and payload-based equality/`Hash`-key identity
      # (`Tag.new("k")` is the same key as `"k"`, symmetric `==`).

      class Tag < String
        def shout; upcase + "!"; end
      end
      t = Tag.new("hi")
      puts t.shout
      puts t.class
      puts(t == "hi")
      puts("hi" == t)
      puts(Tag.new("x").hash == "x".hash)
      h = { "key" => 1 }
      puts h[Tag.new("key")].inspect
      d = Tag.new("a")
      d2 = d.dup
      d2 << "b"
      puts d
      puts d2
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      HI!
      Tag
      true
      true
      true
      1
      a
      ab
    OUT
  end

  it "volatile strip skips coerced arg" do
    _(ze0(<<~'RUBY').stdout).must_equal "2\n"
      # #700 secondary shape: cast_away_volatile_arg was wrapping a
      # coerced call-arg value with the LV's declared type, producing
      # `(sp_SymPolyHash *)sp_StrPolyHash_from_sym_poly_hash(lv_form_attrs)`
      # -- a SymPoly cast on a StrPoly result.
      #
      # Requires @needs_setjmp == 1 (any begin/rescue in the file), an
      # LV recv with a typed-hash declared type, a callee expecting a
      # different hash variant, and the call site to go through
      # compile_typed_call_args' compile_expr_for_expected_type +
      # cast_away_volatile_arg wrapping.

      def takes_str_poly(h)
        h.length
      end

      def trigger_setjmp
        begin
          raise "x"
        rescue
          1
        end
      end

      def build_and_call
        form_attrs = {a: "x", b: 1}    # sym_poly_hash
        takes_str_poly(form_attrs)     # callee expects str_poly_hash -> coerce
      end

      trigger_setjmp                    # arms @needs_setjmp = 1 globally
      puts build_and_call
    RUBY
  end

  it "when string range" do
    result = ze0(<<~'RUBY')
      # `when ("a".."e")`: the parentheses hid the range from the literal check, so
      # the arm declined and the whole when folded to false. A String range held in a
      # variable had no arm at all.
      case "c" when ("a".."e") then p :in else p :out end
      case "z" when ("a".."e") then p :in else p :out end
      case "c" when "a".."e" then p :in2 else p :out2 end
      p(("a".."e") === "c")
      r = ("a".."e")
      case "c" when r then p :in3 else p :out3 end
      case "z" when r then p :in3 else p :out3 end
      case 3 when (1..5) then p :n_in else p :n_out end
      case 9 when (1..5) then p :n_in else p :n_out end
      case "e" when ("a"..."e") then p :x_in else p :x_out end
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      :in
      :out
      :in2
      true
      :in3
      :out3
      :n_in
      :n_out
      :x_out
    OUT
  end

  it "yield autosplat kernel string" do
    result = ze0(<<~'RUBY')
      # CRuby auto-splat of a single yielded Array across multiple block params,
      # and Kernel#String on containers/ranges (returns the object's to_s).
      def pairs124; yield [1, 2]; end
      pairs124 { |a, b| p(a + b) }
      def trip; yield [3, 4, 5]; end
      trip { |a, b, c| p [a, b, c] }
      trip { |a, b| p [a, b] }
      def strs; yield ["x", "y"]; end
      strs { |a, b| p(a + b) }
      def one; yield [7]; end
      one { |a, b| p [a, b] }
      def three; yield [1, 2, 3]; end
      three { |a, *r| p [a, r] }
      three { |*r| p r }
      def two_args; yield 1, 2; end
      two_args { |a, b| p [a, b] }
      def poly_arr; yield [1, "x"]; end
      poly_arr { |a, b| p [a, b] }
      p(String([1, 2]))
      p(String(123))
      p(String(:sym))
      p(String(1.5))
      p(String(nil))
      p(String("s"))
      p(String({ a: 1 }))
      p(String(1..3))
    RUBY

    _(result.stdout).must_equal <<~'OUT'
      3
      [3, 4, 5]
      [3, 4]
      "xy"
      [7, nil]
      [1, [2, 3]]
      [[1, 2, 3]]
      [1, 2]
      [1, "x"]
      "[1, 2]"
      "123"
      "sym"
      "1.5"
      ""
      "s"
      "{a: 1}"
      "1..3"
    OUT
  end
end
