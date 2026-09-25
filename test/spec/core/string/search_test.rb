# frozen_string_literal: true

require "spec_helper"

describe "String: searching and matching" do
  it "container string index write" do
    result = zr(<<~'RUBY')
      # `outer[i][k] = v` where the inner value is a String and the index came out
      # of a container -- a destructured block parameter whose receiver is a local,
      # an element read. The write must reach the String that outer holds.
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

    _(result).must_answer <<~'OUT'
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

  it "scan over a long string takes linear time" do
    result = zr(<<~'RUBY')
      # Each match's MatchData holds the text it matched. CRuby shares the
      # text's buffer with a frozen copy, so a match costs nothing for the
      # length of the text; here each match copies the whole of it, and a scan
      # over a long text is quadratic in its length.
      text = "ab " * 300_000
      p text.scan(/a/).size
      p text.gsub(/b/, "c").bytesize
      p text.split(/ /).size

    RUBY

    _(result).must_answer <<~'OUT'
      300000
      900000
      300000
    OUT
  end

  it "str rindex position" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "index takes a start offset, counting from either end, and answers nil past the last match" do
    result = zr(<<~'RUBY')
      p "hello world".index("o")
      p "hello world".index("o", 5)
      p "hello world".index("o", -3)
      p "hello".index("z", 2)
      p "abcabc".index(/b/, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      4
      7
      nil
      nil
      4
    OUT
  end

  it "[]= at a single integer index replaces one character, appends at the length, or widens" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "[]= takes a Range, a (start, length), a substring or a pattern, and raises on a miss" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "[]= reaches the string a container holds, so rows[0][1] = x mutates it" do
    result = zr(<<~'RUBY')
      # `rows[0][1] = "*"` mutates the string the container holds, for both the
      # Array form and the Hash form.
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

    _(result).must_answer <<~'OUT'
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

  it "character indexing re-decides its byte shortcut after anything that changes the bytes" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "index(nil) raises TypeError rather than reporting no match" do
    result = zr(<<~'RUBY')
      # String#index(nil) raises TypeError. "No implicit conversion" is not the
      # same as "not found", so it does not return nil.
      begin
        "hello".index(nil)
        puts "BUG: no raise"
      rescue TypeError => e
        puts "TypeError: " + e.message
      end
    RUBY

    _(result).must_answer "TypeError: no implicit conversion of nil into String\n"
  end

  it "[]= takes an index that is only known to be an Integer at run time" do
    result = zr(<<~'RUBY')
      # `s[i] = v` takes an index that is only known to be an Integer at run time.
      # Such an index comes out of a container -- a destructured block parameter,
      # an element read, an untyped argument. The conversion is the checked one, so
      # a boxed Integer works.
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

    _(result).must_answer <<~'OUT'
      "a*c"
      "heLlo"
      "ab@d"
      "xyZ"
      "abc"
      "index 9 out of string"
    OUT
  end

  it "rindex, include?, start_with?, end_with? and count each raise TypeError on nil" do
    result = zr(<<~'RUBY')
      # String methods that raise TypeError for nil arguments.
      # The index() test covers index(); this one covers rindex,
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

    _(result).must_answer <<~'OUT'
      rindex: no implicit conversion of nil into String
      include?: no implicit conversion of nil into String
      start_with?: no implicit conversion of nil into String
      end_with?: no implicit conversion of nil into String
      count: no implicit conversion of nil into String
    OUT
  end

  it "count and delete take several char sets, and match, rindex and split take their optional arguments" do
    result = zr(<<~'RUBY')
      # `count`/`delete` take one OR MORE char-set specs (intersected, `^`
      # negation honored); `match`/`match?`/`rindex` take an optional start
      # position; `rindex` also accepts a Regexp; `each_line` an optional
      # separator; `split` an optional limit (positive caps fields, negative
      # keeps trailing empties). All oracle-verified against ruby 4.0.7.

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

    _(result).must_answer <<~'OUT'
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

  it "symbol string methods" do
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
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

  it "start_with? and end_with? read the bytes where they stand" do
    result = zr(<<~'RUBY')
      # The comparison is of the receiver's own bytes: a prefix that ends
      # inside a character is not a prefix, whatever its bytes say, and a
      # suffix is read from the offset its length puts it at. CRuby's
      # rb_str_start_with joins the encodings, checks the boundary and then
      # memcmps, and the boundary is what tells this from a byte compare.
      s = "日本語"
      p s.start_with?("日"), s.start_with?(s.byteslice(0, 2)), s.start_with?(s.byteslice(0, 4))
      p s.end_with?("語"), s.end_with?(s.byteslice(7, 2)), s.end_with?(s.byteslice(3, 6))
      p s.start_with?(""), s.end_with?("")
      p s.start_with?("x", "日本")
      p "".start_with?(""), "".start_with?("a"), "".end_with?("a")
      p "abc".start_with?("abcd"), "abc".end_with?("zabc")
      p "abc".start_with?("abc"), "abc".end_with?("abc")
      p "abc".start_with?(+"ab")
      p "hello".start_with?(/l+/), "hello".start_with?(/h/), $~[0]
      p "abc".start_with?("ab".dup.force_encoding("ASCII-8BIT"))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      true
      true
      true
      true
      true
      false
      false
      false
      false
      true
      true
      true
      false
      true
      "h"
      true
    OUT
  end

  it "scan and gsub leave $~ on the last match in every shape" do
    result = zr(<<~'RUBY')
      text = "one 1, two 22, three 333"
      # No block: the whole matches, then the groups; $~ is the last match.
      p text.scan(/\d+/)
      p [$~[0], $~.pre_match.size, $~.post_match]
      p text.scan(/(\w+) (\d+)/)
      p [$~[1], $~[2], $~.begin(2), $~.captures, $~.size]
      p text.scan(/(\w+) (x)?(\d)/)
      p $~.to_a
      # A String pattern, an empty match, and no match at all: $~ follows.
      p text.scan("e")
      p [$~[0], $~.begin(0)]
      p "aXbX".scan(/X?/)
      p [$~[0], $~.begin(0)]
      p text.scan(/zzz/)
      p $~
      p text.scan(/\d+/) { |d| }
      p $~[0]
      # With a block, $~ is each match in turn, and the answer is the receiver.
      seen = []
      r = text.scan(/(\w+) (\d+)/) { |w, d| seen << [w, d, $~.begin(0), $~[2]] }
      p seen
      p r.equal?(text)
      "zzz".scan(/q/) { }
      p $~
      # gsub with a block and with a Hash: $~ inside, and after.
      p text.gsub(/\d+/) { |d| "#{$~.begin(0)}:#{d.size}" }
      p [$~[0], $~.begin(0)]
      p text.gsub(/(\w+) (\d+)/, '\2-\1')
      p $~[1]
      p "héllo wörld".scan(/\w+/)
      p "héllo wörld".scan(/./).size
      p "aaa".scan(/a*/)
      p "abc".scan(/(?<x>b)/)
      p [$~[:x], $~.names]
      p "x".scan(/y/).frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      ["1", "22", "333"]
      ["333", 21, ""]
      [["one", "1"], ["two", "22"], ["three", "333"]]
      ["three", "333", 21, ["three", "333"], 3]
      [["one", nil, "1"], ["two", nil, "2"], ["three", nil, "3"]]
      ["three 3", "three", nil, "3"]
      ["e", "e", "e"]
      ["e", 19]
      ["", "X", "", "X", ""]
      ["", 4]
      []
      nil
      "one 1, two 22, three 333"
      "333"
      [["one", "1", 0, "1"], ["two", "22", 7, "22"], ["three", "333", 15, "333"]]
      true
      nil
      "one 4:1, two 11:2, three 21:3"
      ["333", 21]
      "1-one, 22-two, 333-three"
      "three"
      ["h", "llo", "w", "rld"]
      11
      ["aaa", ""]
      [["b"]]
      ["b", ["x"]]
      false
    OUT
  end
end
