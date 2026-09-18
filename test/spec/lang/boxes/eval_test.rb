# frozen_string_literal: true

require "spec_helper"

describe "Boxes: evaluating a string" do
  it "box eval defines and returns across the boundary" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # `Box#eval`: a statement-position eval may DEFINE classes in the box; an
      # expression-position eval returns a value whose static type is the box's
      # own class (Path 1 dispatch on a cross-boundary instance); two boxes
      # eval'ing the same class name get distinct classes.



      box = Ruby::Box.new
      box.eval("class Gadget; def spin; 'spinning'; end; end")
      g = box.eval("Gadget.new")
      p g.spin
      p box::Gadget.new.spin
      box2 = Ruby::Box.new
      box2.eval("class Gadget; def spin; 'other'; end; end")
      p box2::Gadget.new.spin
      p(box::Gadget == box2::Gadget)
      p box.eval("1 + 2")
    RUBY

    _(result).must_answer <<~'OUT'
      "spinning"
      "spinning"
      "other"
      false
      3
    OUT
  end

  it "box eval dynamic source routes through the vm" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, files: {"box_eval_dynamic_source_routes_through_the_vm/lib.rb" => "WIDGET_CONST = \"widget!\"\nclass Widget\n  def self.describe = \"a widget\"\nend\n", "box_eval_dynamic_source_routes_through_the_vm/main.rb" => "box = Ruby::Box.new\nbox.require_relative \"lib\"\ncode = \"1 + 2\"\np box.eval(code)\np box.eval(\"WIDGET_CONST\")\np box.eval(\"Widget.describe\")\n$g = \"main value\"\nread = \"$g\"\np box.eval(read)\nbox.eval(\"$g = 'box value'\")\np $g\np box.eval(read)\nbegin\n  box.eval(123)\nrescue TypeError => e\n  puts \"rescued: \#{e.message}\"\nend\n"}, ruby: ["-W:no-experimental"])
      # A NON-literal `box.eval` source (a variable, a computed string) routes
      # through the runtime `eval` in the box's dimension -- the same fall-through
      # `Kernel#eval` uses for a dynamic source, but carrying `box_id`. A dynamic
      # eval reads/calls the box's own (`require`-defined) constants and classes,
      # its globals stay isolated from main, and a non-String source raises a
      # catchable `TypeError` at runtime rather than a compile error.



      require_relative "box_eval_dynamic_source_routes_through_the_vm/main"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      "widget!"
      "a widget"
      nil
      "main value"
      "box value"
      rescued: no implicit conversion of Integer into String
    OUT
  end

  it "box global is its own" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("$boxg = 7")
      p $boxg
      p b.eval("$boxg")
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      7
    OUT
  end

  it "box kernel method is invisible to main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("module Kernel; def kmeth = 1; end")
      p(begin; kmeth; rescue NoMethodError, NameError; :nome; end)
      p b.eval("kmeth")
    RUBY

    _(result).must_answer <<~'OUT'
      :nome
      1
    OUT
  end

  it "box literal eval is spliced" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      p b.eval("__FILE__")
      begin
        b.eval("raise 'x'")
      rescue RuntimeError => e
        p e.backtrace.first(2)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "eval"
      ["eval:1:in '<compiled>'", "lang/boxes/eval_test.rb:6:in 'Ruby::Box#eval'"]
    OUT
  end

  it "box reopens its own patch twice" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      b = Ruby::Box.new
      b.eval("class Array; def self.a = 1; end")
      b.eval("class Array; def self.a = 2; end")
      p b.eval("Array.a")
      p(begin; Array.a; rescue NoMethodError; :nome; end)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      :nome
    OUT
  end

  it "spliced box eval names its own file" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      # A literal `box.eval` is SPLICED at compile time, and the snippet is a
      # file of its own -- `__FILE__` answers `eval`, the same name the runtime
      # `eval` entry gives a computed snippet. A backtrace must not say which
      # tier ran the code.
      #
      # What is still the caller's is the FRAME: a spliced body runs inside the
      # enclosing method's frame, and a frame carries ONE file string, stamped
      # once at emit time, while only the line is stamped per statement. So the
      # raise below reports the snippet's line under the caller's file and
      # label. Giving it its own frame costs two frame pushes per execution on
      # the path whose whole justification is being zero-cost, so it stays
      # recorded in `tests/gaps/a_box_literal_eval_is_spliced.rb`.
      b = Ruby::Box.new
      p b.eval("__FILE__")
      p b.eval("__FILE__ + '/x'")
      # Two statements: the second names the same file and its own line.
      p b.eval("__FILE__\n__LINE__")
      p b.eval("[__FILE__, __LINE__]")
      # The caller's own `__FILE__` is untouched by the splice beside it.
      p File.basename(__FILE__)
    RUBY

    _(result).must_answer <<~'OUT'
      "eval"
      "eval/x"
      2
      ["eval", 1]
      "eval_test.rb"
    OUT
  end

  it "two boxes patch one class independently" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])


      a = Ruby::Box.new
      b = Ruby::Box.new
      a.eval("class Array; def self.who = 'a'; end")
      b.eval("class Array; def self.who = 'b'; end")
      p a.eval("Array.who")
      p b.eval("Array.who")
      p(begin; Array.who; rescue NoMethodError; :nome; end)
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "b"
      :nome
    OUT
  end

  it "two boxes patch one shared class independently" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # Two boxes patching one shared class do not see each other, and main sees
      # neither. One box could be made to work by accident (any box-shaped key
      # answers); two cannot.



      a = Ruby::Box.new
      b = Ruby::Box.new
      a.eval("class Array; def self.who = 'a'; end")
      b.eval("class Array; def self.who = 'b'; end")
      p a.eval("Array.who")
      p b.eval("Array.who")
      p(begin; Array.who; rescue NoMethodError; :nome; end)
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "b"
      :nome
    OUT
  end

  it "value built in a box carries no box methods into main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # A box's patch of a shared class must not follow a value BACK to main:
      # the Array built inside the box is an ordinary Array in main, and calling
      # the box's method on it raises there.



      b = Ruby::Box.new
      b.eval("class Array; def self.zzz = 9; def mine = 'm'; end")
      a = b.eval("[1, 2]")
      p a
      p a.class == Array
      p(begin; a.mine; rescue NoMethodError; :nome; end)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      true
      :nome
    OUT
  end
end
