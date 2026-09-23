# frozen_string_literal: true

require "spec_helper"

describe "Globals programs" do
  it "line number global follows reads" do
    result = ze0(<<~'RUBY')
      # `$.` is the number of the line the last read took: 0 before any
      # read, then what `gets` counts on the stream it read from. A write
      # sets it until the next read. `$<` is ARGF.
      p $.
      p $<.equal?(ARGF), $<.class
      r, w = IO.pipe
      w.write("a\nb\nc\n")
      w.close
      r.gets
      r.gets
      p $., r.lineno
      $. = 10
      p $.
      r.gets
      p $.
      p r.gets, $.
      r.close

    RUBY

    _(result).must_answer <<~'OUT'
      0
      true
      ARGF.class
      2
      2
      10
      3
      nil
      3
    OUT
  end

  it "match globals read the registers not matchdata methods" do
    result = ze0(<<~'RUBY')
      "ab" =~ /(a)(b)/
      p $~.respond_to?(:last_group), $~.respond_to?(:last_group, true)
      p $+, $&, $`, $', $1, $2, $3

      "b" =~ /(a)?b/
      p $+, $1
      "a" =~ /(a)|(b)/
      p $+, $1, $2
      "xyz" =~ /q/
      p $+, $&, $`, $', $1

      "héllo wörld" =~ /(ö)/
      p $`, $', $&, $+, $`.encoding

      class MatchData
        def pre_match = "PRE"
        def post_match = "POST"
        def [](i) = "IDX"
        def captures = ["CAP"]
        def to_a = ["ARR"]
        def size = 99
      end
      "xaby" =~ /(a)(b)/
      p $`, $', $&, $+, $1, $2
      p "xaby".sub(/(a)(b)/, '<\+|\0|\1|\2|\`|\'>')
      p "xaby".gsub(/(a)(b)/, '[\&]')

    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      "b"
      "ab"
      ""
      ""
      "a"
      "b"
      nil
      nil
      nil
      "a"
      "a"
      nil
      nil
      nil
      nil
      nil
      nil
      "héllo w"
      "rld"
      "ö"
      "ö"
      #<Encoding:UTF-8>
      "x"
      "y"
      "ab"
      "b"
      "a"
      "b"
      "x<b|ab|a|b|x|'>y"
      "x[ab]y"
    OUT
  end

  it "special global symbol prints bare" do
    result = ze0(<<~'RUBY')
      # `Symbol#inspect` prints a special global's name bare, the way ruby's
      # `is_special_global_name` reads it: one punctuation character from a fixed
      # set, `$0`, a run of digits, or `$-` with exactly one alphanumeric after it.
      # The name must END there, so `$00` and `$-ab` quote.
      bare = ["$~", "$*", "$$", "$?", "$!", "$@", "$/", "$\\", "$;", "$,", "$.",
              "$=", "$:", "$<", "$>", "$\"", "$&", "$`", "$'", "$+",
              "$0", "$1", "$12", "$-w", "$-0"]
      puts bare.map { |n| n.to_sym.inspect }.join(" ")

      # Everything else keeps its quotes.
      quoted = ["$00", "$-", "$-ab", "$^", "$#", "$[", "$%", "$ ", "$"]
      puts quoted.map { |n| n.to_sym.inspect }.join(" ")

      # The plain-identifier globals were already bare, and stay so.
      p [:$stdout, :$_, :$a, :$LOAD_PATH]

      # A bare name is still an ordinary symbol everywhere else.
      p :$1.to_s, :$1.length, :$~ == "$~".to_sym
      p [:$~, :$*].map(&:inspect)
      p({ :$~ => 1 })
      p [:$~, :$1].sort_by(&:to_s)

      # A hash label is STRICTER than a bare symbol: `:+` prints bare but `{+: 1}`
      # is not a literal anyone can paste back, so the shorthand quotes a leading
      # `@`/`$`/`!` and a trailing operator character.
      labels = ["a", "a?", "a!", "a=", "$~", "@a", "@@a", "+", "[]", "[]=", "<=>",
                "==", "!", "!~", "A", "café", "a@", "a<"]
      puts labels.map { |k| { k.to_sym => 1 }.inspect }.join(" ")
      p({ a: 1, "b c": 2, :$~ => 3 })
    RUBY

    _(result).must_answer <<~'OUT'
      :$~ :$* :$$ :$? :$! :$@ :$/ :$\ :$; :$, :$. :$= :$: :$< :$> :$" :$& :$` :$' :$+ :$0 :$1 :$12 :$-w :$-0
      :"$00" :"$-" :"$-ab" :"$^" :"$#" :"$[" :"$%" :"$ " :"$"
      [:$stdout, :$_, :$a, :$LOAD_PATH]
      "$1"
      2
      true
      [":$~", ":$*"]
      {"$~": 1}
      [:$1, :$~]
      {a: 1} {a?: 1} {a!: 1} {"a=": 1} {"$~": 1} {"@a": 1} {"@@a": 1} {"+": 1} {"[]": 1} {"[]=": 1} {"<=>": 1} {"==": 1} {"!": 1} {"!~": 1} {A: 1} {café: 1} {"a@": 1} {"a<": 1}
      {a: 1, "b c": 2, "$~": 3}
    OUT
  end

  it "an alias of a back-reference reaches the whole program, and reads the frame that asks" do
    result = ze0(<<~'RUBY', files: { "shouty.rb" => <<~'SHOUTY' })
      # `alias $hit $&` is an alias of a global, so it reaches every file the
      # program holds, not only the one that wrote it. What it answers is another
      # matter: `$&` belongs to the frame that last matched, so a method of its
      # own sees no match, and the frame that ran the match sees one.
      require_relative "shouty"
      "hello" =~ /l(l)o/
      p Shouty.hit
      p $hit
      p $hit.frozen?
      def here
        "abcd" =~ /b(c)/
        $hit
      end
      p here
      p $hit
    RUBY
      module Shouty
        alias $hit $&
        def self.hit = $hit
      end
    SHOUTY

    _(result).must_answer <<~'OUT'
      nil
      "llo"
      false
      "bc"
      "llo"
    OUT
  end

  it "an alias of a back reference where it may not run" do
    result = ze0(<<~'RUBY')
      if ARGV.size > 5
        alias $pre $`
      end
      p $pre
      def link = (alias $whole $&)
      link
      "xaby" =~ /ab/
      p [$whole, $pre]
      if true
        alias $post $'
      end
      "xaby" =~ /ab/
      p $post
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      ["ab", nil]
      "y"
    OUT
  end
end
