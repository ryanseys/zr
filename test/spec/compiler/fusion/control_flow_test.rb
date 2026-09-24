# frozen_string_literal: true

require "spec_helper"

describe "Fusion: control flow" do
  it "a times block inlines to a native loop" do
    result = zr(<<~'RUBY')
      3.times do |i|
        puts i
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
    OUT
  end

  it "destructure typed ptr array return" do
    result = zr(<<~'RUBY')
      # Top-level `y, z = call_returning_pair_of_objs` segfaulted pre-fix:
      # collect_scoped_multi_const pushed every top-level MultiWriteNode
      # into @multi_const_inits, even when no target was a constant. The
      # codegen loop then planted a pre-body `_t = call(lv_a, lv_b);` emit
      # before the locals it reads from had been assigned. With both
      # args still NULL the inlined method body deref'd NULL and crashed.
      # Issue #630.

      class Mat
        attr_accessor :nrows, :ncols
        def initialize(nrows, ncols)
          @nrows = nrows
          @ncols = ncols
        end
        def matmul(other)
          Mat.new(@nrows, other.ncols)
        end
      end

      def fwd(w, x)
        y = w.matmul(x)
        z = w.matmul(x)
        [y, z]
      end

      w = Mat.new(3, 4)
      x = Mat.new(4, 1)
      y, z = fwd(w, x)
      puts y.nrows
      puts z.ncols
    RUBY

    _(result).must_answer "3\n1\n"
  end

  it "fused loop binds every block parameter shape" do
    result = zr(<<~'RUBY')
      # `3.times`, `(a..b).each` and `arr.each` fuse into a counted loop when the
      # block takes at most one required parameter. Ruby binds every other shape
      # happily -- `3.times { |a, b| }` gives `b` nil -- so those take the ordinary
      # block send instead of being refused.
      #
      # The emitter used to check the parameter shape AFTER deciding to splice, and
      # refused what it found. Found 2026-08-21 while looking for a live refusal to
      # pin a diagnostics test on.
      3.times { |a, b| p [a, b] }
      (1..3).each { |a, b| p [a, b] }
      [10, 20].each { |a, b| p [a, b] }

      3.times { |a,| p a }
      3.times { |*a| p a }
      3.times { |a, (b, c)| p [a, b, c] }
      3.times { |a, *rest| p [a, rest] }
      3.times { |a, b: 9| p [a, b] }
      3.times { |a, &blk| p [a, blk] }

      [[1, 2], [3, 4]].each { |a, b| p [a, b] }
      [[1, 2], [3, 4]].each { |(a, b)| p [a, b] }

      # The one-parameter shapes still fuse, and answer the same.
      3.times { |i| p i }
      (1..3).each { |i| p i }
      [7, 8].each { |e| p e }
      3.times { p :none }

      # The loop's own value survives either path.
      p 3.times { |a, b| }
      p((1..3).each { |a, b| })
      p [1, 2].each { |a, b| }

      # A block-local and a closure capture, on the non-fused path.
      seen = []
      3.times { |a, b; tmp| tmp = a * 2; seen << tmp }
      p seen
    RUBY

    _(result).must_answer <<~'OUT'
      [0, nil]
      [1, nil]
      [2, nil]
      [1, nil]
      [2, nil]
      [3, nil]
      [10, nil]
      [20, nil]
      0
      1
      2
      [0]
      [1]
      [2]
      [0, nil, nil]
      [1, nil, nil]
      [2, nil, nil]
      [0, []]
      [1, []]
      [2, []]
      [0, 9]
      [1, 9]
      [2, 9]
      [0, nil]
      [1, nil]
      [2, nil]
      [1, 2]
      [3, 4]
      [1, 2]
      [3, 4]
      0
      1
      2
      1
      2
      3
      7
      8
      :none
      :none
      :none
      3
      1..3
      [1, 2]
      [0, 2, 4]
    OUT
  end

  it "fused loop binds its names per iteration" do
    result = zr(<<~'RUBY')
      # `n.times { |i| }` and `(a..b).each { |i| }` on a LITERAL receiver splice
      # into a counted loop with no frame of their own. Ruby still binds the block's
      # names PER INVOCATION, so a closure built in one iteration must keep what it
      # captured when the next iteration rebinds -- the splice cannot hand every
      # closure one shared slot.
      #
      # Giving the spliced param a plain slot means REFUSING any escaping block
      # that captures it ("the shadow dies with the loop"), which takes out
      # `3.times { |i| Process.fork { exit i } }` among others. A name a closure
      # escapes with now gets a fresh cell each iteration; a name nothing escapes
      # with keeps the slot, and the uncaptured loop is untouched.

      # --- the parameter ----------------------------------------------------------
      procs = []
      3.times { |i| procs << -> { i } }
      p procs.map(&:call)

      ranged = []
      (1..3).each { |i| ranged << -> { i * 10 } }
      p ranged.map(&:call)

      # --- a name first assigned inside the body ---------------------------------
      doubled = []
      3.times do |i|
        n = i * 2
        doubled << -> { n }
      end
      p doubled.map(&:call)

      # --- an explicit block-local (`|i; n|`) ------------------------------------
      n = "outer"
      labels = []
      3.times do |i; n|
        n = "in#{i}"
        labels << -> { n }
      end
      p labels.map(&:call)
      p n

      # --- a block-local that is never assigned is nil each time ------------------
      seen = []
      2.times { |i; fresh| seen << fresh; fresh = i }
      p seen

      # --- a conditional first assignment does not carry over --------------------
      carried = []
      3.times do |i|
        once = i if i == 1
        carried << once
      end
      p carried

      # --- the param shadows an enclosing local of the same name -----------------
      i = :outer
      2.times { |i| }
      p i

      # --- nested splices: each level binds its own ------------------------------
      pairs = []
      2.times do |a|
        2.times do |b|
          pairs << -> { [a, b] }
        end
      end
      p pairs.map(&:call)

      # --- a splice inside a real block ------------------------------------------
      mixed = []
      [10, 20].each do |base|
        2.times { |k| mixed << -> { base + k } }
      end
      p mixed.map(&:call)

      # --- the uncaptured fast path is untouched ---------------------------------
      total = 0
      5.times { |x| total += x }
      p total

      acc = []
      (0..4).each do |x|
        next if x == 2
        break if x == 4
        acc << x
      end
      p acc

      # --- a closure captured mid-loop sees the value at capture time ------------
      snapshots = []
      3.times do |i|
        snapshots << -> { i }
        i = i + 100
      end
      p snapshots.map(&:call)
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2]
      [10, 20, 30]
      [0, 2, 4]
      ["in0", "in1", "in2"]
      "outer"
      [nil, nil]
      [nil, 1, nil]
      :outer
      [[0, 0], [0, 1], [1, 0], [1, 1]]
      [10, 11, 20, 21]
      10
      [0, 1, 3]
      [100, 101, 102]
    OUT
  end

  it "fused loop guard fails at run time" do
    result = zr(<<~'RUBY', env: {"ZEO_RT_LEAKCHECK" => "1"})

      # A fused `arr.each` splice is guarded twice at run time -- the receiver's
      # tag must be Array, and `zeo_rt_iter_inline_ok_for` must still hold -- and
      # the FALLBACK arm is what runs when either fails. That arm reaches the same
      # epilogue as the inline one, so every slot the epilogue releases has to be
      # initialised on it too.
      #
      # `Array.send(:define_method, :each)` is what makes the second guard answer
      # false, so both arms run here in one program: the first call takes the
      # inline arm, the second the fallback. Before slot initialization moved to
      # the entry block, the block parameter's slot was nil-initialised INSIDE the
      # inline arm, so the second call released a slot holding stack garbage.
      # `tests/compiled_code_releases_a_dead_slot.rb` has the mechanism.
      #
      # A RUN-TIME redefinition, deliberately. A compile-time `class Array; def
      # each` reaches backwards and makes the FIRST call answer 30 as well --
      # that is `tests/gaps/a_later_def_on_a_builtin_reaches_back.rb`, a separate
      # gap this file must not depend on.
      #
      # Runs under `ZEO_RT_LEAKCHECK=1`, which is what makes it a memory-safety
      # test rather than an output test.
      #
      # HONEST LIMIT: this golden does NOT reproduce the bug on the pre-fix
      # emitter -- it was tried, and it came out clean. The released bytes are
      # stack garbage, and a short frame leaves benign garbage behind. What this
      # file adds is coverage of the path, so a LOUD failure on it is caught.

      def sum_of(a)
        total = 0
        a.each { |x| total += x }
        total
      end

      p sum_of([1, 2, 3])

      Array.send(:define_method, :each) do |&b|
        b.call(10)
        b.call(20)
        self
      end

      p sum_of([1, 2, 3])
    RUBY

    _(result).must_answer "6\n30\n"
  end

  it "inlined loop var capture" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A torus grid: every Cell holds its neighbours and the wraparound closes the ring.
      # At exit: cycle leak: 24 objects (Array x12, Cell x12)
      # A proc lifted out of a NESTED block reads the enclosing INLINED loop's
      # variable. The outer `each_with_index` is spliced into a C loop, so `y` binds
      # to a plain C slot; the inner block is materialized as a proc by the runtime
      # dispatch and needs a cell to read `y` through. The cell now shadows the slot:
      # the loop binds the slot as before and the body's opening line copies it in.

      class Cell
        def initialize
          @n = []
        end
        def add_neighbor(c)
          @n << c
        end
        def count
          @n.length
        end
      end

      class Ring
        def initialize(v)
          @v = v
        end
        def each(&blk)
          blk.call(@v)
        end
        def each_with_index(&blk)
          blk.call(@v, 0)
        end
      end

      def pick(f, rows)
        f ? rows : Ring.new(1)
      end

      class Grid
        def initialize(w, h)
          @width = w
          @height = h
          @cells = Array.new(@height) { Array.new(@width) { Cell.new } }
          link_neighbors
        end

        def link_neighbors
          @cells.each_with_index do |column, y|
            pick(true, column).each_with_index do |cell, x|
              (-1..1).each do |dy|
                (-1..1).each do |dx|
                  next if dx == 0 && dy == 0
                  ny = (y + dy + @height) % @height
                  nx = (x + dx + @width) % @width
                  cell.add_neighbor(@cells[ny][nx])
                end
              end
            end
          end
        end

        def total
          @cells.map { |r| r.map { |c| c.count }.sum }.sum
        end
      end

      p Grid.new(4, 3).total
    RUBY

    _(result).must_answer "96\n"
  end

  it "isa guarded return narrow" do
    result = zr(<<~'RUBY')
      module Addressable
        class URI
          attr_reader :host
          def self.parse(uri)
            return uri if uri.is_a?(URI)
            new(uri.to_s)
          end
          def initialize(host)
            @host = host
          end
          def join(other)
            URI.new(URI.parse(other.to_s).host)
          end
        end
      end
      j = Addressable::URI.parse("h").join("c")
      puts j.host

      # a genuinely mixed call profile still works (param widens to poly)
      class Wrapper
        attr_reader :v
        def self.wrap(x)
          return x if x.is_a?(Wrapper)
          new(x)
        end
        def initialize(v) = @v = v
      end
      a = Wrapper.wrap("s")
      b = Wrapper.wrap(a)
      p a.v
      p b.v
    RUBY

    _(result).must_answer <<~'OUT'
      c
      "s"
      "s"
    OUT
  end

  it "next splat typed map" do
    result = zr(<<~'RUBY')
      # A splat-valued `next` contributes the array value to the map result.
      p (1..3).map { |v| next *[v, v] if v == 2; v }
    RUBY

    _(result).must_answer "[1, [2, 2], 3]\n"
  end

  it "nil time return guard narrow" do
    result = zr(<<~'RUBY')
      # A method returning `nil | Time` types poly (Time has no first-class
      # nullable slot). A caller branch guarded by `a.nil?` or `a` truthiness
      # narrows reads of the local to Time inside the non-nil arm (read-site
      # unbox, the #1661 machinery on the caller side). Reassigned locals and
      # reads outside a guard stay poly and keep the honest NoMethodError.
      module M
        def self.maybe_time(s)
          return nil if s.nil?
          Time.at(0).utc
        end
      end

      # if a.nil? ... else (the issue's shape)
      a = M.maybe_time("x")
      if a.nil?
        puts "branch-nil"
      else
        puts "branch-time"
        y = a.year
        puts "year:" + y.to_s
      end

      # unless a.nil? (the silent variant from the report)
      b = M.maybe_time("x")
      unless b.nil?
        puts b.year.to_s
      end

      # bare truthiness guard, method with an argument
      c = M.maybe_time("x")
      if c
        puts c.strftime("%Y-%m-%d")
      end

      # the nil path through the same guards
      d = M.maybe_time(nil)
      if d.nil?
        puts "d-nil"
      else
        puts d.year
      end
      unless d.nil?
        puts "not-reached"
      end

      # chained use inside the arm
      e = M.maybe_time("x")
      unless e.nil?
        puts e.month + e.day
      end
      puts "end"
    RUBY

    _(result).must_answer <<~'OUT'
      branch-time
      year:1970
      1970
      1970-01-01
      d-nil
      2
      end
    OUT
  end

  it "safe nav typed receiver" do
    result = zr(<<~'RUBY')
      class Combat
        def initialize
          @count = 3
          @name = "shotgun"
        end

        def sprites
          @count * 2
        end

        def update(n)
          @count += n
          @count
        end

        def name
          @name
        end
      end

      class Player
        def initialize(armed)
          @combat = Combat.new if armed
        end

        def combat
          @combat
        end

        def tick
          p @combat&.sprites
          p @combat&.update(1)
        end
      end

      alive = Player.new(true)
      alive.tick
      alive.tick

      dead = Player.new(false)
      dead.tick

      p alive.combat&.name&.length
      p dead.combat&.name&.length
    RUBY

    _(result).must_answer <<~'OUT'
      6
      4
      8
      5
      nil
      nil
      7
      nil
    OUT
  end
end
