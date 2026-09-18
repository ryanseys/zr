# frozen_string_literal: true

require "spec_helper"

describe "Boxes: defining and naming methods" do
  it "box class method is invisible to main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; def self.zzz = 9; end")
      p Array.respond_to?(:zzz)
      p(begin; Array.zzz; rescue NoMethodError; :nome; end)
      p b.eval("Array.zzz")
      p b.eval("Array.respond_to?(:zzz)")
      p b.eval("Array.new(2, 7)")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      :nome
      9
      true
      [7, 7]
    OUT
  end

  it "box instance method is invisible to main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class String; def shout = 'S'; end")
      p "a".respond_to?(:shout)
      p(begin; "a".shout; rescue NoMethodError; :nome; end)
      p b.eval("'a'.shout")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      :nome
      "S"
    OUT
  end

  it "box removes only its own class method" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class String; def self.zz = 1; end")
      b.eval("class String; class << self; remove_method :zz; end; end")
      p(begin; b.eval("String.zz"); rescue NoMethodError; :nome; end)
      p String.respond_to?(:zz)
    RUBY

    _(result).must_answer <<~'OUT'
      :nome
      false
    OUT
  end

  it "box singleton alias aborts" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; class << self; alias_method :zz2, :new; end; end")
      p Array.respond_to?(:zz2)
    RUBY

    _(result).must_answer "false\n"
  end

  it "box singleton class body is invisible to main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Hash; class << self; def qq = 1; end; end")
      p Hash.respond_to?(:qq)
      p b.eval("Hash.qq")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      1
    OUT
  end

  it "box singleton define method reaches main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("Array.singleton_class.define_method(:dyn) { 42 }")
      p Array.respond_to?(:dyn)
    RUBY

    _(result).must_answer "false\n"
  end

  it "box write on a shared class reaches main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; def self.zzz = 9; end")
      p Array.respond_to?(:zzz)
    RUBY

    _(result).must_answer "false\n"
  end

  it "boxs class method on a shared class stays in the box" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # The class-method channel. A box's `def self.x` on a SHARED class is the
      # box's alone: main sees neither the method nor a `respond_to?` for it,
      # while the box still reaches `Array`'s ordinary rows.
      #
      # This is the shape that leaked -- `class_methods` was keyed by name only,
      # where the instance channel had carried `(box, name)` from the start.



      b = Ruby::Box.new
      b.eval("class Array; def self.zzz = 9; end")
      p Array.respond_to?(:zzz)
      p(begin; Array.zzz; rescue NoMethodError; :nome; end)
      p b.eval("Array.zzz")
      p b.eval("Array.respond_to?(:zzz)")
      p b.eval("Array.new(2, 7)")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      :nome
      9
      true
      [7, 7]
    OUT
  end

  it "boxs instance method on a shared class stays in the box" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # The instance channel, which had the box axis already -- kept here so the
      # pair reads together and a regression on either half is one file to look
      # at.



      b = Ruby::Box.new
      b.eval("class String; def shout = 'S'; end")
      p "a".respond_to?(:shout)
      p(begin; "a".shout; rescue NoMethodError; :nome; end)
      p b.eval("'a'.shout")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      :nome
      "S"
    OUT
  end

  it "boxs runtime singleton define method stays in the box" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # A RUN-TIME `define_method` on a shared class's singleton. The compiled
      # half and this one land in different tables -- the frozen registry and the
      # runtime overlay -- so both need saying.



      b = Ruby::Box.new
      b.eval("Array.singleton_class.define_method(:dyn) { 42 }")
      p Array.respond_to?(:dyn)
      p b.eval("Array.dyn")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      42
    OUT
  end

  it "boxs singleton class body stays in the box" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # The same isolation through a `class << self` body rather than a
      # `def self.x`, which reaches the class-method channel by another route.



      b = Ruby::Box.new
      b.eval("class Hash; class << self; def qq = 1; end; end")
      p Hash.respond_to?(:qq)
      p b.eval("Hash.qq")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      1
    OUT
  end

  it "class a box owns answers main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Owned; def self.go = 'go'; def inst = 'i'; end")
      p b::Owned.go
      p b::Owned.new.inst
      p b::Owned.respond_to?(:go)
    RUBY

    _(result).must_answer <<~'OUT'
      "go"
      "i"
      true
    OUT
  end

  it "class the box owns answers main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # The OTHER direction, and the one a strict reading of the rule gets
      # wrong: a class the box DEFINED is the box's own class, so its methods
      # answer every caller, main included. Isolation is a property of a shared
      # class the box patched, never of a class it owns outright.



      b = Ruby::Box.new
      b.eval("class Owned; def self.go = 'go'; def inst = 'i'; end")
      p b::Owned.go
      p b::Owned.new.inst
      p b::Owned.respond_to?(:go)
    RUBY

    _(result).must_answer <<~'OUT'
      "go"
      "i"
      true
    OUT
  end
end
