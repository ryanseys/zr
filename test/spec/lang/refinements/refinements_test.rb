# frozen_string_literal: true

require "spec_helper"

describe "Refinements programs" do
  it "refine block sees its sibling refinements" do
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
end
