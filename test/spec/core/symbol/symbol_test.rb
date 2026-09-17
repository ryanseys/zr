# frozen_string_literal: true

require "spec_helper"

describe "Symbol programs" do
  it "keeps its encoding" do
    result = ze0(<<~'RUBY')
      # A Symbol is its bytes and the encoding they are in. Binary bytes past
      # ASCII make another Symbol than the same bytes as UTF-8, ASCII bytes
      # make the same one, and bytes invalid in their encoding make none.
      def t = yield rescue [$!.class, $!.message]

      p t { "é".b.to_sym == :"é" }, t { "é".b.to_sym.encoding }, t { :"é".encoding }
      p t { "ab".b.to_sym == :ab }, t { "ab".b.to_sym.encoding }, t { :ab.encoding }
      p t { "\xff".to_sym }, t { "\xff".b.to_sym.encoding }, t { "é".b.to_sym.inspect }
      p t { "é".b.to_sym.to_s.encoding }, t { "é".b.to_sym.length }, t { "é".b.to_sym.name.encoding }
      p t { "é".b.to_sym.equal?("é".b.intern) }, t { :"é".to_s.encoding }, t { "é".to_sym.equal?(:"é") }

    RUBY

    _(result).must_answer <<~'OUT'
      false
      #<Encoding:BINARY (ASCII-8BIT)>
      #<Encoding:UTF-8>
      true
      #<Encoding:US-ASCII>
      #<Encoding:US-ASCII>
      [EncodingError, "invalid symbol in encoding UTF-8 :\"\\xFF\""]
      #<Encoding:BINARY (ASCII-8BIT)>
      ":\"\\xC3\\xA9\""
      #<Encoding:BINARY (ASCII-8BIT)>
      2
      #<Encoding:BINARY (ASCII-8BIT)>
      true
      #<Encoding:UTF-8>
      true
    OUT
  end

  it "to proc answers one lambda per symbol" do
    result = ze0(<<~'RUBY')
      # `Symbol#to_proc` and `&:name` answer the same lambda for a symbol
      # every time, as ruby keeps one per symbol; it is a lambda, not
      # frozen, and it keeps what a program puts on it.
      a = :upcase.to_proc
      b = :upcase.to_proc
      p a.equal?(b), a.lambda?, a.frozen?, a.arity, a.call("x")
      a.instance_variable_set(:@tag, 1)
      p :upcase.to_proc.instance_variable_get(:@tag)
      pr = nil
      2.times { |i| q = ->(&blk) { blk }.call(&:downcase); p pr.equal?(q) if pr; pr = q }
      GC.start
      p pr.equal?(:downcase.to_proc), pr.call("ABC")
      dyn = "dyn#{1 + 1}".to_sym
      p dyn.to_proc.equal?(dyn.to_proc), :dyn2.to_proc.equal?(dyn.to_proc)
      p %w[a b].map(&:upcase), [1, 2].map(&:to_s), [[1, 2]].map(&:first)
      p :+.to_proc.call(1, 2), :size.to_proc.parameters, :size.to_proc.source_location
      p :"with space".to_proc.call(Struct.new(:"with space").new(3))


    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      -2
      "X"
      1
      true
      true
      "abc"
      true
      true
      ["A", "B"]
      ["1", "2"]
      [1]
      3
      [[:req], [:rest]]
      nil
      3
    OUT
  end
end
