# frozen_string_literal: true

require "spec_helper"

describe "Refinements programs" do
  it "refine block sees its sibling refinements" do
    result = zr(<<~'RUBY')
      # Inside a refine block, every refinement the same module holds is in use,
      # the ones written after it too, as rb_mod_refine shares the module's
      # activated refinements. REXML's Array#dclone calls dclone on a Symbol
      # that way.
      module Clones
        refine Object do
          def dup_of = [:object, clone]
        end
        refine Symbol do
          def dup_of = [:symbol, self]
        end
        refine Array do
          def dup_of = map { |v| v.dup_of }
          def both = [1.dup_of, 1.later]
        end
        refine Integer do
          def later = :integer_seen_from_array
        end
      end
      using Clones
      p [:a, "s"].dup_of
      p [].both

    RUBY

    _(result).must_answer <<~'OUT'
      [[:symbol, :a], [:object, "s"]]
      [[:object, 1], :integer_seen_from_array]
    OUT
  end

  it "using covers a byte range of its scope" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `using M` turns M's refinements on for the rest of the LEXICAL scope that
      # wrote it -- the file, or the class body -- so a byte RANGE is the rule. A
      # `def` written below the `using` is covered, one written above it is not.
      #
      # WHICH classes M refines is a run-time fact, so the site names neither the
      # module nor the holder: it takes an activation slot, fills it where the
      # `using` runs, and every call the range covers hands its slots over.

      module Sizes
        refine Array do
          def second = self[1]
          def pair = [first, second]
        end
        refine String do
          def shout = upcase + "!"
        end
        refine Integer do
          def +(other) = 999
        end
      end

      module ClassSide
        refine Array.singleton_class do
          def pairs(n) = Array.new(n) { |i| [i, i] }
        end
      end

      def before = [1, 2].respond_to?(:second)
      p before

      using Sizes

      p [1, 2, 3].second
      p [1, 2, 3].pair
      p "hi".shout
      p 1 + 2
      p [1, 2].respond_to?(:second)
      p [1, 2].send(:second)
      p [1, 2].method(:second).call
      p [1, 2].method(:second).owner

      # A `def` below the `using` is covered wherever it runs.
      def through(a) = a.second
      def reflected(a) = a.method(:second).call
      p through([4, 5])
      p reflected([4, 5])

      # Safe navigation, a splat and a block argument all reach the refined body.
      p [7, 8]&.second
      def spread(*a) = a.second
      p spread(9, 10)
      p [[1, 2], [3, 4]].map { |a| a.second }

      using ClassSide
      p Array.pairs(2)

      # A class body scopes its own `using` to that body.
      class Narrow
        using Sizes
        def take(a) = a.second
      end
      class Wide
        def take(a) = a.respond_to?(:second)
      end
      p Narrow.new.take([11, 12])
      p Wide.new.take([11, 12])

      # A `using` under a guard covers the rest of the body either way; one whose
      # guard does not run leaves its slot empty, which activates nothing.
      module Never
        refine Integer do
          def nope = :nope
        end
      end
      using Never if RUBY_VERSION.to_i > 99
      begin
        p 1.nope
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      2
      [1, 2]
      "HI!"
      999
      true
      2
      2
      #<refinement:Array@Sizes>
      5
      5
      8
      10
      [2, 4]
      [[0, 0], [1, 1]]
      12
      true
      NoMethodError
    OUT
  end

  it "keeps a refinement in force after an eval loads the compiler" do
    result = zr(<<~'RUBY')
      # A program that evals carries the compiler, and the compiler loads
      # on the first eval, running each of its own files. Several of them
      # activate a refinement as they load -- the prism port reaches its
      # node writers through one. A `using` fills a row the compiler
      # numbered, so the rows a program holds and the rows its road holds
      # must not be the same rows, or the first eval takes this
      # program's refinement back off.
      module Tripler
        refine Integer do
          def trip = self * 3
        end
      end

      using Tripler
      p 7.trip

      n = ARGV.size + 1
      p eval("#{n} + 1")
      p 7.trip
      p [1, 2].map { |x| x.trip }
    RUBY

    _(result).must_answer <<~'OUT'
      21
      2
      21
      [3, 6]
    OUT
  end

  it "keeps a refinement a snippet activates out of the compiler's own rows" do
    result = zr(<<~'RUBY')
      # The other way round: a snippet numbers rows too, and it is
      # compiled while the program runs, so its rows have to start after
      # every row the program already holds. One that started from zero
      # took the compiler's, and the next parse stopped inside it --
      # "undefined method 'value=' for an instance of Prism::IntegerNode".
      module Tripler
        refine Integer do
          def trip = self * 3
        end
      end

      n = ARGV.size + 1
      p eval("using Tripler\n#{n}.trip")
      p eval("#{n} + 2")
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
    OUT
  end
  it "names the modules in use, refined class by refined class" do
    result = zr(<<~'RUBY')
      # `Module.used_modules` answered [] until the activation row could
      # reach the callee. CRuby reads its cref's refinement table, which
      # is keyed by the refined class, so the order is the classes in the
      # order a `using` first reached them and, down each class, the
      # newest refinement first -- Twice before Shout on String, and
      # Twice before Plain on Integer, then uniq.
      module Shout
        refine String do
          def loud = upcase
        end
      end

      module Twice
        refine String do
          def loud = upcase * 2
        end
        refine Integer do
          def loud = self * 2
        end
      end

      module Plain
        refine Integer do
          def loud = -self
        end
      end

      p Module.used_modules
      p Module.used_refinements

      using Shout
      using Plain
      using Twice

      p Module.used_modules
      p Module.used_refinements
      p Module.used_refinements.map(&:target)

      # A refinement holds its origin where no Ruby name reaches it.
      p Module.used_refinements.first.instance_variables
      p Module.used_refinements.first.to_s

      # A method's body stands in the scope the `def` was written in, so
      # it asks under the same rows.
      def asks = Module.used_modules
      p asks

      p "hi".loud
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      [Twice, Shout, Plain]
      [#<refinement:String@Twice>, #<refinement:String@Shout>, #<refinement:Integer@Twice>, #<refinement:Integer@Plain>]
      [String, String, Integer, Integer]
      []
      "#<refinement:String@Twice>"
      [Twice, Shout, Plain]
      "HIHI"
    OUT
  end
  it "a site under using takes every road, and a def inside refine closes the gate of the name it stands over" do
    result = zr(<<~'RUBY')
      # A site under `using` takes the same roads as any site: the inline
      # fixnum operator, the unary, the `[]`/`<<`/`push` entries, the cell,
      # a block's `call`. Each road is guarded by a gate the runtime closes
      # when a class redefines the name -- and a def inside `refine C`
      # stands over C, so the gate closes at the definition and the site
      # takes the call, which the refined lookup answers. The refinements
      # stay told to the task for the callee, so `send`, `respond_to?`,
      # `&:name` and `method` under `using` see them at a hot cell as ruby
      # does; a site outside the file sees none of it.
      module Arith
        refine Integer do
          def +(o) = [:plus, self, o]
          def succ = [:succ, self]
          def ==(o) = :eq
        end
        refine Array do
          def [](i) = [:aref, i]
          def <<(v) = [:shovel, v]
          def push(v) = [:push, v]
          def each = yield(:each)
        end
        refine String do
          def <<(v) = [:sh, v]
          def getbyte(i) = [:byte, i]
        end
        refine Proc do
          def call(*a) = [:called, *a]
        end
        refine Object do
          def hello = :hello
        end
      end
      def plain(a, s, pr) = [1 + 2, 3.succ, 1 == 1, a[0], a << 9, a.push(8), s << "x", s.getbyte(0), pr.call(4)]
      using Arith
      r = []
      3.times do
        a = [7]
        s = +"q"
        pr = proc { |x| x }
        r.concat([[1 + 2, 3.succ, 1 == 1, a[0], a << 9, a.push(8), s << "x", s.getbyte(0), pr.call(4), 5.nil?]])
        [1].each { |x| r.concat([x]) }
      end
      p r.uniq
      p plain([7], +"q", proc { |x| x })
      o = Object.new
      h = []
      4.times { h.concat([[o.send(:hello), o.respond_to?(:hello), [o].map(&:hello), o.method(:hello).call, o.public_send(:hello)]]) }
      p h.uniq
      def take(&b) = b.call(1)
      p take { |x| x }
    RUBY

    _(result).must_answer <<~'OUT'
      [[[:plus, 1, 2], [:succ, 3], :eq, [:aref, 0], [:shovel, 9], [:push, 8], [:sh, "x"], [:byte, 0], [:called, 4], false], :each]
      [3, 4, true, 7, [7, 9, 8], [7, 9, 8], "qx", 113, 4]
      [[:hello, true, [:hello], :hello, :hello]]
      [:called, 1]
    OUT
  end

  it "a send under using keeps its cells, and every change that moves the stamp is seen" do
    result = zr(<<~'RUBY')
      # A send written under `using` keeps cells like any other (SEND_USING):
      # the refinements at a site are the site's own, so what the lookup
      # answered under them is the class's and the stamp's at that site. A
      # later `using`, a refinement defined later, and a redefinition of the
      # method move the stamp; a send outside the file sees none of it, and
      # a `new` under `using` reaches the refined initialize as ruby does.
      class Foo; def hi = :plain; def bye = :plain_bye; end
      module R
        refine Foo do
          def hi = :refined
          def extra = :extra
        end
      end
      def outside(f) = [f.hi, (f.extra rescue :none)]
      using R
      f = Foo.new
      r = []
      5.times { r << [f.hi, f.bye, f.extra, outside(f)] }
      p r.uniq
      p f.respond_to?(:extra), (f.send(:extra) rescue :nosend)
      module R2
        refine Foo do
          def hi = :refined2
        end
      end
      using R2
      p f.hi, outside(f)
      class Foo; def hi = :redefined; end
      p f.hi, outside(f)
      p [1, 2].map { |x| f.hi }
      def later(f) = f.hi
      p later(f)
      class Foo; def bye = :new_bye; end
      p f.bye
      class Bar; attr_reader :v; def initialize(v) = @v = v; end
      module R3
        refine Bar do
          def initialize(v) = @v = v * 2
        end
      end
      using R3
      p Bar.new(2).v, Bar.new(3).v
      def make(v) = Bar.new(v)
      p make(4).v
      class Bar; def initialize(v) = @v = v + 100; end
      p Bar.new(2).v, make(2).v
    RUBY

    _(result).must_answer <<~'OUT'
      [[:refined, :plain_bye, :extra, [:plain, :none]]]
      true
      :extra
      :refined2
      [:plain, :none]
      :refined2
      [:redefined, :none]
      [:refined2, :refined2]
      :refined2
      :new_bye
      4
      6
      8
      4
      4
    OUT
  end

  it "interpolation calls a refined to_s" do
    result = zr(<<~'RUBY')
      module RS
        refine(Integer) { def to_s = "R" }
        refine(Symbol) { def to_s = "sym" }
      end
      using RS
      p "#{5}"
      p "a#{:b}c"
      p 5.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "R"
      "abc"
      "R"
    OUT
  end

  it "a Symbol block reaches a refined method" do
    result = zr(<<~'RUBY')
      module RS
        refine(String) { def shout = upcase + "!" }
        refine(Integer) { def to_s = "R" }
      end
      using RS
      p %w[a b].map(&:shout)
      p [1, 2].map(&:to_s)
      pr = :shout.to_proc
      p pr.call("c")
    RUBY

    _(result).must_answer <<~'OUT'
      ["A!", "B!"]
      ["R", "R"]
      "C!"
    OUT
  end

  it "using inside a block at the top level refines the rest of the file" do
    result = zr(<<~'RUBY')
      module RS
        refine(Integer) { def to_s = "R" }
      end
      def run = yield
      p 5.to_s
      run { using RS }
      p 5.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "5"
      "R"
    OUT
  end

  it "import_methods refuses a method not written as a def" do
    result = zr(<<~'RUBY')
      m = Module.new { attr_reader :q }
      begin
        Module.new { refine(String) { import_methods m } }
      rescue ArgumentError => e
        p e.message.sub(/#<Module:0x\h+>/, "M")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "Can't import method which is not defined with Ruby code: M#q"
    OUT
  end
end
