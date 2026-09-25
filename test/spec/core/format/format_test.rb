# frozen_string_literal: true

require "spec_helper"

describe "Format programs" do
  it "percent r literal syntax" do
    result = zr(<<~'RUBY')
      r = %r{foo/bar}
      puts r.match?("xxfoo/barxx")
      puts r.source
    RUBY

    _(result).must_answer "true\nfoo/bar\n"
  end

  it "numbered widths, a hash of mixed keys, %c of strings and bad code points" do
    result = zr(<<~'RUBY')
      def t(*a) = p(format(*a))
      t("%1$*2$d|%2$d", 5, 8)
      t("%*d|%-*d|", -6, 3, 4, 2)
      t("%{a} %<a>s", {"a" => 1, a: 2})
      t("%c|%c|%5c|", "hello", 0x3042, "x")
      p format("%c".encode("US-ASCII"), 200).encoding
      o = Object.new
      def o.to_ary = ["q", "r"]
      p "%s %s" % o
      h = Object.new
      def h.to_hash = {k: 9}
      p format("%{k}", h)
      ["%**d", "%.*.*d", "%1$d %d", "%d %1$d", "%<a>d %d"].each do |spec|
        format(spec, 1, 2, 3)
      rescue ArgumentError => e
        p e.message
      end
      [-1, 0x110000].each do |c|
        format("%c", c)
      rescue RangeError, ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "       5|8"
      "3     |2   |"
      "2 2"
      "h|あ|    x|"
      #<Encoding:BINARY (ASCII-8BIT)>
      "q r"
      "9"
      "width given twice"
      "precision given twice"
      "unnumbered(1) mixed with numbered"
      "numbered(1) after unnumbered(1)"
      "one hash required"
      "invalid character"
      "invalid character"
    OUT
  end

  it "too many arguments warn under VERBOSE and raise under DEBUG" do
    result = zr(<<~'RUBY')
      def f = format("%d", 1, 2)
      $VERBOSE = true
      p f
      $DEBUG = true
      begin
        f
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/format/format_test.rb:1: warning: too many arguments for format string\nException 'ArgumentError' at core/format/format_test.rb:1 - too many arguments for format string\n"
      "1"
      "too many arguments for format string"
    OUT
  end
end
