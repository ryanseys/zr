# frozen_string_literal: true

require "spec_helper"

describe "CSV programs" do
  it "shift returns non-locally out of a block yielded deep inside the parser" do
    result = zr(<<~'RUBY')
      # `CSV#shift` is `parser.parse { |row| return row }` -- a non-local return out
      # of a block yielded from deep inside the parser, past frames that catch a
      # `Signal::Return` of their own. It is the reason `shift`/`gets`/`readline`
      # exist at all, so it is pinned here as well as in
      # `nonlocal_return_through_frames.rb`, which covers the shape in isolation.
      require "csv"

      c = CSV.new("a,b\nc,d\n")
      p c.shift
      p c.shift
      p c.shift
      p CSV.new("k,v\n").gets
      p CSV.new("m,n\n").readline

      # The collecting forms, which never return early, still agree.
      p CSV.parse("a,b\nc,d\n")
      p CSV.new("e,f\n").read
      p CSV.new("g,h\ni,j\n").each.to_a

      # `shift` and `each` share the parser's position.
      mixed = CSV.new("1,2\n3,4\n5,6\n")
      p mixed.shift
      rest = []
      mixed.each { |row| rest << row }
      p rest
      p mixed.shift
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      ["c", "d"]
      nil
      ["k", "v"]
      ["m", "n"]
      [["a", "b"], ["c", "d"]]
      [["e", "f"]]
      [["g", "h"], ["i", "j"]]
      ["1", "2"]
      [["3", "4"], ["5", "6"]]
      nil
    OUT
  end

  it "issue csv gem missing" do
    result = zr(<<~'RUBY')
      # `require "csv"` -- the vendored gem loads, which brings `CSV.parse` and
      # `CSV.generate` with it.
      require "csv"
      puts "loaded"
    RUBY

    _(result).must_answer "loaded\n"
  end

  it "qualified defined answers by position" do
    result = zr(<<~'RUBY')
      # `defined?` of a qualified path answers by POSITION, exactly like the bare
      # name: a constant a later require or a later statement defines is nil here,
      # whatever the whole program eventually holds. The runtime registry carries
      # every spliced class from startup, so the compiler must fold the nil --
      # a probe cannot see "not yet".
      p defined?(CSV)
      p defined?(CSV::Row)
      p defined?(Zed)
      p defined?(Zed::Q)
      require "csv"
      p defined?(CSV)
      p defined?(CSV::Row)
      if defined?(Zed::Q)
        puts "guard above: yes"
      else
        puts "guard above: no"
      end
      if defined?(Wob)
        puts "bare guard above: yes"
      else
        puts "bare guard above: no"
      end
      module Zed
        class Q; end
      end
      module Wob; end
      p defined?(Zed::Q)
      if defined?(Zed::Q)
        puts "guard below: yes"
      else
        puts "guard below: no"
      end
      GATED = 1 unless defined?(GATED)
      p GATED
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      "constant"
      "constant"
      guard above: no
      bare guard above: no
      "constant"
      guard below: yes
      1
    OUT
  end
end
