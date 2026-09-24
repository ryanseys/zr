# frozen_string_literal: true

require "spec_helper"

describe "String: splitting and joining" do
  it "armed each line streams a pipe the writer fills incrementally" do
    result = zr(<<~'RUBY', env: {"ZR_TEST_GVL" => "1"})
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

    _(result).must_answer "[\"alpha\", \"beta\"]\n"
  end

  it "chunk slice float" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      [[1.0, 2.0], [4.0, 5.0]]
      [[1.0, 2.0], [4.0]]
      [[1.0, 2.0], [4.0]]
      [[1.0, 2.0], [4.0]]
      [[1.0, [1.0, 1.0]], [2.0, [2.0]]]
      []
      []
    OUT
  end

  it "hash value split widen" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer "x\ny\n"
  end

  it "plain string split goes straight to the kernel" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "reopen split superclass dispatch" do
    result = zr(<<~'RUBY')
      # Imported from the spinel corpus at c55d9bdb.
      # A class opened BARE and reopened with a superclass is ruby's own
      # `TypeError: superclass mismatch for class Sub` -- a real bare `class Sub`
      # gives the class Object as its parent, and a later `< Base` conflicts with
      # that. A forward SHELL (zr's own device for a name a later file defines)
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

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      core/string/splitting_test.rb:25:in '<module:M>': superclass mismatch for class Sub (TypeError)
      	from core/string/splitting_test.rb:7:in '<main>'
    ERR
  end

  it "split default separator global" do
    result = zr(<<~'RUBY')
      $; = ","
      p "a,b".split
      p "a,b".split(nil)
      p "a b".split
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      ["a", "b"]
      ["a b"]
    OUT
  end

  it "split keeps leading and embedded empties but drops trailing ones" do
    result = zr(<<~'RUBY')
      puts "a,b,,c".split(/,/)
      puts "---"
      puts ",a,b".split(/,/)
      puts "---"
      puts "a1b2c3".split(/\d/)
    RUBY

    _(result).must_answer <<~'OUT'
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

  it "split on blanks goes straight to the kernel" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b\tc\n"]
      ["a", "b", "c", ""]
      []
      []
      ["a"]
      ["a", ""]
      ["a", "b", ""]
      xyz"x y z"
      [" a", "b"]

      ["a", "b"]
      ["a\u0000b", "c"]
      ["a", "b c"]
      ["a", "b c"]
      ["a,b", "c"]
      ["a,b", "c"]
      [#<Encoding:UTF-8>]
      ArgumentError
      one two three 
      0
      "kept"
      "one\n"
      "one\n"
      0
      ["a", "b"]
      ["a\nb"]
    OUT
  end

  it "split on unresolved chain" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer "ok\n"
  end

  it "split on whitespace keeps nul inside a word" do
    result = zr(<<~'RUBY')
      # awk-style split breaks on space and \t through \r only: a NUL stays
      # inside its word, while strip takes NUL off the ends.
      p "a\0b".split(" "), "a\0 b".split(" "), " a\v b\fc\r\n".split(" ")
      p "\0a\0".strip, "\0 a".lstrip, "a \0".rstrip
      p "x y z".split(" ", 2), " x  y ".split(" ", 2), "  x y  ".split(" ", -1)
      p "one".split(" ", -1), " a b ".split(" ", 3), " a b ".split(" ", 4), "   ".split(" ", -1)
    RUBY

    _(result).must_answer <<~'OUT'
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

  it "str split space dynamic limit" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      ["hello", "world"]
      ["a", "b"]
      ["hello", "world"]
      ["a", "", "b"]
    OUT
  end

  it "str split trailing empty" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b", "c", ""]
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b,c,"]
    OUT
  end

  it "each_char with a block answers the receiver, and yields whole code points" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      hello
      ["a", "b", "c"]
      5
      ["h", "é", "l", "l", "o"]
    OUT
  end

  it "a blockless each_line is an Enumerator that to_a, first, take and next all read" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "each_line answers the receiver in expression position as well as in statement" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "each_line yields each line with its newline, the last one only if the source had it" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      "hello\n"
      "world"
      "a\n"
      "b\n"
      "only"
      0
    OUT
  end

  it "each_line takes a separator and yields the pieces with it still attached" do
    result = zr(<<~'RUBY')
      z001 = []; "1-2-3".each_line("-") { |l001| z001 << l001 }; p z001
      p("1-2-3".each_line("-").to_a)
      z2 = []; "a\nb\n".each_line { |l| z2 << l }; p z2
    RUBY

    _(result).must_answer <<~'OUT'
      ["1-", "2-", "3"]
      ["1-", "2-", "3"]
      ["a\n", "b\n"]
    OUT
  end

  it "lines with an empty separator splits into paragraphs, keeping the blank line with the one before" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "split with a block yields each piece, and the method still answers its own value" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["FOO", "BAR"]
      ["a", "b,c,d"]
      6
      "badc"
      0
    OUT
  end

  it "split by a pattern with capture groups splices the captures between the pieces" do
    result = zr(<<~'RUBY')
      # Issue #856: split with a regex that has capture groups splices
      # the matched groups into the result between segments.
      puts "hello world".split(/(\s+)/).inspect
      # Without a capture group, behaviour unchanged.
      puts "hello world".split(/\s+/).inspect
      # Multiple capture groups: each captured substring is spliced
      # in, in group-index order.
      puts "a1b2c3d".split(/(\d)/).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ["hello", " ", "world"]
      ["hello", "world"]
      ["a", "1", "b", "2", "c", "3", "d"]
    OUT
  end

  it "upto walks the succ sequence to its argument inclusive" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      5
      xyz
      ay,az,ba,bb,
      a-b-c
    OUT
  end
end
