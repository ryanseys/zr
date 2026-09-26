# frozen_string_literal: true

require "spec_helper"

describe "Classes: regressions" do
  it "array each with object" do
    result = zr(<<~'RUBY')
      # Array#each_with_object runs the block for each element, on a mixed
      # Array and on an Array of user objects.

      # mixed element classes
      n = 0
      [1, "x"].each_with_object("") {|_e, _a| n += 1 }
      puts n

      # user objects
      class T_array_each_with_object_Bar
        def initialize(x); @x = x; end
        attr_accessor :x
      end

      m = 0
      [T_array_each_with_object_Bar.new(1), T_array_each_with_object_Bar.new(2)].each_with_object("") {|_e, _a| m += 1 }
      puts m
    RUBY

    _(result).must_answer "2\n2\n"
  end

  it "each block cmeth widen" do
    result = zr(<<~'RUBY')
      # A class method called with the `k` and `v` of `h.each { |k, v| }`
      # gets the Hash's String keys and values as its argument.

      class T_each_block_cmeth_widen_Json
        def self.escape(s)
          out = ""
          i = 0
          n = s.length
          while i < n
            out = out + s[i]
            i += 1
          end
          out
        end

        def self.from_str_hash(h)
          out = "{"
          h.each do |k, v|
            out = out + "\"" + T_each_block_cmeth_widen_Json.escape(k) + "\":\"" + T_each_block_cmeth_widen_Json.escape(v) + "\""
          end
          out + "}"
        end
      end

      puts T_each_block_cmeth_widen_Json.from_str_hash({"a" => "b"})
      puts T_each_block_cmeth_widen_Json.from_str_hash({"x" => "y"})
    RUBY

    _(result).must_answer <<~'OUT'
      {"a":"b"}
      {"x":"y"}
    OUT
  end

  it "each poly recv block auto splat" do
    result = zr(<<~'RUBY')
      # `arr.each {|a, b| ... }` over an Array of Arrays auto-splats each
      # element across the block params, matching CRuby's
      # `arr.each {|*args| a, b, *_ = args }` shape. So `b` gets the second
      # element. The inner Arrays hold only Integers (as `[i, fixed]` in
      # optcarrot's `setup_lut`) or mixed classes.

      class T_each_poly_recv_block_auto_splat_C
        def initialize
          @h = {}
        end

        def push_int(bank, pair)
          # `pair` holds only Integers.
          (@h[bank] ||= []) << pair
        end

        def push_poly(bank, pair)
          # `pair` holds mixed classes.
          (@h[bank] ||= []) << pair
        end

        def each_pair(bank)
          arr = @h[bank]
          sum = 0
          arr.each {|a, b| sum += a.to_i + b.to_i }
          sum
        end
      end

      c = T_each_poly_recv_block_auto_splat_C.new
      c.push_int(0, [10, 20])
      c.push_int(0, [3,  4])
      puts c.each_pair(0)         # 10 + 20 + 3 + 4 = 37

      d = T_each_poly_recv_block_auto_splat_C.new
      d.push_poly(1, [100, "x"])  # b is a string, in a mixed Array
      d.push_poly(1, [5,   "y"])
      puts d.each_pair(1)         # 100 + 0 + 5 + 0 = 105 (string `to_i` of "x" / "y" = 0)
    RUBY

    _(result).must_answer "37\n105\n"
  end

  it "enumerable" do
    result = zr(<<~'RUBY')
      class T_enumerable_NumberList
        include Enumerable
        def initialize
          @data = (1..5).to_a
        end
        def each
          @data.each do |x|
            yield x
          end
        end
      end

      list = T_enumerable_NumberList.new
      total = 0
      list.each do |x|
        total += x
      end
      puts total  # 15
      puts "done"
    RUBY

    _(result).must_answer "15\ndone\n"
  end

  it "fiber yield across method call" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # An Outer and its inherited Sub hold each other through the forwarded class-method init.
      # At exit: cycle leak: 2 objects (T_forward_call_class_method_inherited_init_Outer x1, T_forward_call_class_method_inherited_init_Sub x1)
      # Bundled tests:
      #   - fiber_ivar_persists_across_yield
      #   - fiber_yield_across_method_call
      #   - file_write_poly_arg
      #   - forward_call_class_method_inherited_init
      #   - forward_call_class_method_inherited_init_int_array


      class T_fiber_yield_across_method_call_Stepper
        def initialize
          @count = 0
          @fiber = Fiber.new { main_loop }
        end

        def step
          @fiber.resume
          @count
        end

        def main_loop
          while @count < 5
            tick
            tick
            Fiber.yield
          end
        end

        def tick
          @count += 1
        end
      end

      s = T_fiber_yield_across_method_call_Stepper.new
      puts s.step
      puts s.step
      puts s.step
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      6
    OUT
  end

  it "hash each param narrow" do
    result = zr(<<~'RUBY')
      # A class method whose only use of its Hash param is `h.each |k, v|`.
      # The body joins `k` and `v` into a String with `+`, for a Hash with
      # String values and for a Hash with Integer values.

      class T_hash_each_param_narrow_Encoder
        def self.from_str_hash(h)
          out = "{"
          first = true
          h.each do |k, v|
            out += "," unless first
            first = false
            out += "\"" + k + "\":\"" + v + "\""
          end
          out + "}"
        end

        def self.from_int_hash(h)
          out = "{"
          first = true
          h.each do |k, v|
            out += "," unless first
            first = false
            out += "\"" + k + "\":" + v.to_s
          end
          out + "}"
        end
      end

      puts T_hash_each_param_narrow_Encoder.from_str_hash({"name" => "alice", "city" => "NYC"})
      puts T_hash_each_param_narrow_Encoder.from_int_hash({"a" => 1, "b" => 2, "c" => 3})
    RUBY

    _(result).must_answer <<~'OUT'
      {"name":"alice","city":"NYC"}
      {"a":1,"b":2,"c":3}
    OUT
  end

  it "a class method of the parent class answers through each subclass" do
    result = zr(<<~'RUBY')
      # A class method (`def self.<name>`) that the parent class defines
      # answers when a subclass calls it, at one level or at two.

      class T_issue208_inherited_class_method_Base
        def self.all
          [42, 1, 7]
        end
      end

      # Single level
      class T_issue208_inherited_class_method_Leaf < T_issue208_inherited_class_method_Base; end
      puts T_issue208_inherited_class_method_Leaf.all.size                   # 3

      # Multi level
      class T_issue208_inherited_class_method_Mid < T_issue208_inherited_class_method_Base; end
      class T_issue208_inherited_class_method_Deep < T_issue208_inherited_class_method_Mid; end
      puts T_issue208_inherited_class_method_Mid.all.size                    # 3
      puts T_issue208_inherited_class_method_Deep.all.size                   # 3

      # Direct call on the defining class still works
      puts T_issue208_inherited_class_method_Base.all.size                   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      3
      3
    OUT
  end

  it "map array block result" do
    result = zr(<<~'RUBY')
      # `arr.map { array_block }` — the block returns an Integer Array
      # (`(0..i).to_a` here). The result is an Array of Arrays, and the GC
      # keeps each inner Array alive.

      class T_map_array_block_result_C
        def initialize
          @rows = [1, 6].map { |i| (0..i).to_a }
        end

        def show
          @rows.each do |row|
            row.each { |x| print x, " " }
            puts
          end
        end
      end

      T_map_array_block_result_C.new.show
    RUBY

    _(result).must_answer <<~'OUT'
      0 1 
      0 1 2 3 4 5 6 
    OUT
  end

  it "map block returns nested array" do
    result = zr(<<~'RUBY')
      # `Range#map` / `Array#map` whose block returns an array
      # (1D, 2D, 3D nested). `arr[i][j][k]...` reads the right value at
      # each depth. Optcarrot builds a table this way:
      # `TILE_LUT = [...].map { (0..7).map { (0...0x10000).map { ... }
      # }.transpose }`.

      # Range#map -> an Array of Integer Arrays (2D)
      class T_map_block_returns_nested_array_M2
        def initialize
          @t = (0..2).map { |i| (0..3).map { |j| i * 10 + j } }
        end
        def read(i, j); @t[i][j]; end
      end
      m2 = T_map_block_returns_nested_array_M2.new
      puts m2.read(0, 0)   # 0
      puts m2.read(1, 2)   # 12
      puts m2.read(2, 3)   # 23

      # Integer Array map { Range#map { ... } } -> 3D
      class T_map_block_returns_nested_array_M3
        def initialize
          @t = [10, 20].map do |a|
            (0..2).map { |b| [a + b, a + b + 100] }
          end
        end
        def read(i, j, k); @t[i][j][k]; end
      end
      m3 = T_map_block_returns_nested_array_M3.new
      puts m3.read(0, 0, 0)   # 10
      puts m3.read(0, 1, 1)   # 111
      puts m3.read(1, 2, 0)   # 22
      puts m3.read(1, 2, 1)   # 122
    RUBY

    _(result).must_answer <<~'OUT'
      0
      12
      23
      10
      111
      22
      122
    OUT
  end

  it "map empty block" do
    result = zr(<<~'RUBY')
      # An empty `map {}` block still gives an array of the same length as
      # the receiver, with nil in each element. This is true for each kind
      # of receiver.

      # Range#map
      puts (0..2).map {}.length          # 3

      # N.times.map
      puts 4.times.map {}.length         # 4

      # Integer Array#map
      puts [10, 20, 30].map {}.length    # 3

      # String Array#map
      puts ["a", "b", "c", "d"].map {}.length   # 4

      # mixed Array#map
      puts [1, "two", :three].map {}.length     # 3

      # Array#map on objects of one user class
      class T_map_empty_block_Box
        def initialize(v); @v = v; end
      end
      puts [T_map_empty_block_Box.new(1), T_map_empty_block_Box.new(2), T_map_empty_block_Box.new(3)].map {}.length  # 3
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      3
      4
      3
      3
    OUT
  end

  it "map range recv array block" do
    result = zr(<<~'RUBY')
      # `Range#map { array_block }` gives an Array of Arrays, not a Range.
      # So the result can be indexed `arr[i][j]` directly. A second ivar
      # holds a plain Integer Array.

      class T_map_range_recv_array_block_C
        def initialize
          # Block returns an Integer Array — outer is an Array of Arrays.
          @rows = (0...3).map { |i| [i, i * 10] }
          # Separate ivar for a plain Integer Array.
          @flat = [10, 20, 30]
        end

        def show
          @rows.each { |row| row.each { |v| puts v } }
          @flat.each { |v| puts v }
        end
      end

      T_map_range_recv_array_block_C.new.show
      # Expected:
      #   0 / 0 / 1 / 10 / 2 / 20 (each row's elements)
      #   10 / 20 / 30 (flat)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      1
      10
      2
      20
      10
      20
      30
    OUT
  end

  it "multi arg block call" do
    result = zr(<<~'RUBY')
      # Multi-argument `block.call(a, b, ...)` on the proc-object path.
      #
      # Each positional argument reaches its block param, not only the
      # first one.

      # 1. Basic: forwarded `&block` invoked with 2 args.
      class T_multi_arg_block_call_App
        def run(&block)
          block.call(10, 20)
        end
      end

      T_multi_arg_block_call_App.new.run { |a, b| puts a + b }

      # 2. 3-arg block.call.
      class T_multi_arg_block_call_Wider
        def go(&block)
          block.call(1, 2, 3)
        end
      end

      T_multi_arg_block_call_Wider.new.go { |x, y, z| puts x + y + z }

      # 3. Same proc invoked twice with different concrete args.
      class T_multi_arg_block_call_Twice
        def both(&block)
          block.call(100, 1)
          block.call(200, 2)
        end
      end

      T_multi_arg_block_call_Twice.new.both { |a, b| puts a * b }

      # 4. 0-param block called with one arg. Extra arg is silently dropped
      # (matches CRuby semantics).
      class T_multi_arg_block_call_Drop
        def go(&block)
          block.call(99)
        end
      end

      T_multi_arg_block_call_Drop.new.go { puts "called" }
    RUBY

    _(result).must_answer <<~'OUT'
      30
      6
      100
      400
      called
    OUT
  end

  it "multi write map block" do
    result = zr(<<~'RUBY')
      # `A, B = arr.map { block }` is destructuring assignment where
      # each LHS target receives one element of the mapped array.
      # Here the block returns an Integer Array, so each constant holds an
      # Integer Array.

      class T_multi_write_map_block_C
        # Outer map produces an Array of Arrays (each element is an Integer
        # Array from `to_a`).
        P, Q = [3, 5].map { |n| (0...n).to_a }
      end

      # P and Q are Arrays, so `.length` and `[]` work on them.
      puts T_multi_write_map_block_C::P.length   # 3
      puts T_multi_write_map_block_C::P[0]       # 0
      puts T_multi_write_map_block_C::P[1]       # 1
      puts T_multi_write_map_block_C::P[2]       # 2
      puts T_multi_write_map_block_C::Q.length   # 5
      puts T_multi_write_map_block_C::Q[3]       # 3
      puts T_multi_write_map_block_C::Q[4]       # 4
    RUBY

    _(result).must_answer <<~'OUT'
      3
      0
      1
      2
      5
      3
      4
    OUT
  end

  it "nested proc interp capture" do
    result = zr(<<~'RUBY')
      # Nested blocks that capture a variable through string interpolation
      # inside a block that itself captures the same variable.
      #
      # LocalVariableReadNode("i") is nested under
      #   InterpolatedStringNode → EmbeddedStatementsNode → body
      # and each block sees the last value of `i`.

      class T_nested_proc_interp_capture_Defer
        def initialize
          @cnt = 0
        end

        def add(&blk)
          if @cnt == 0
            @blk0 = blk
          elsif @cnt == 1
            @blk1 = blk
          else
            @blk2 = blk
          end
          @cnt += 1
          nil
        end

        def call
          @blk2.call
          @blk1.call
          @blk0.call
        end
      end

      class T_nested_proc_interp_capture_Runner
        def self.with_deferred(&outer)
          d = T_nested_proc_interp_capture_Defer.new
          outer.call(d)
          d.call
        end
      end

      T_nested_proc_interp_capture_Runner.with_deferred do |d|
        i = 1
        d.add { puts "first #{i}" }
        i += 1
        d.add { puts "second #{i}" }
        puts "mid"
        i += 1
        d.add { puts "third #{i}" }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      mid
      third 3
      second 3
      first 3
    OUT
  end

  it "poly aref shift via block param" do
    result = zr(<<~'RUBY')
      # `a[idx]` goes into an Integer operator (`>>` / `<<` / ...)
      # inside an `.each {|a| ... }` block, where `a` is an Array of mixed
      # elements.
      #
      # `entries` here is one half of a destructured 2-tuple from a
      # nested-ivar chain (`@store[bank][idx]`). `a[2]` is an Integer, so
      # `data >> a[2]` is an Integer shift.

      class T_poly_aref_shift_via_block_param_C
        def initialize
          # @store[bank][idx] is a 2-tuple: (names, entries).  Each entry
          # in `entries` is a [tag, payload, shift] triple, with elements
          # of mixed classes.
          @store = [[ [[1], [[10, [0, 1, 2], 4], [20, [3, 4, 5], 6]]] ]]
        end

        def run(bank, idx, data)
          _names, entries = @store[bank][idx]
          entries.each do |a|
            shifted = data >> a[2]
            puts shifted & 3
          end
        end
      end

      T_poly_aref_shift_via_block_param_C.new.run(0, 0, 0xff)
    RUBY

    _(result).must_answer "3\n3\n"
  end

  it "poly proc call" do
    result = zr(<<~'RUBY')
      # `.call` on a Proc stored in an ivar runs the proc body.

      class T_poly_proc_call_Runner
        def initialize(pr)
          @pr = pr
        end

        def run
          @pr.call
        end
      end

      class T_poly_proc_call_Factory
        def wrap(&block)
          block
        end
      end

      f = T_poly_proc_call_Factory.new

      puts "start"
      T_poly_proc_call_Runner.new(f.wrap { puts "one" }).run
      T_poly_proc_call_Runner.new(f.wrap { puts "two" }).run
      puts "end"
    RUBY

    _(result).must_answer <<~'OUT'
      start
      one
      two
      end
    OUT
  end

  it "poly recv each" do
    result = zr(<<~'RUBY')
      # `.each` on an ivar `@store` that two methods set to different
      # Arrays: an Integer Array, and an Array filled with Strings. The
      # block runs for each element of the Array that `@store` holds.

      class T_poly_recv_each_C
        def store_int_array
          @store = [10, 20, 30]
        end
        def store_poly_array
          @store = [nil] * 3
          @store[0] = "a"
          @store[1] = "b"
          @store[2] = "c"
        end
        def visit
          @store.each do |x|
            puts x.to_s
          end
        end
      end

      c = T_poly_recv_each_C.new
      c.store_int_array
      c.visit
      puts "---"
      c.store_poly_array
      c.visit
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      ---
      a
      b
      c
    OUT
  end

  it "proc array push" do
    result = zr(<<~'RUBY')
      # Push a Proc into an ivar Array (set to `[]` first). Then
      # `.each { |b| b.call }` runs each proc.
      class T_proc_array_push_Runner
        def initialize
          @procs = []
        end

        def add(&block)
          @procs.push(block)
        end

        def call_all
          @procs.each do |p|
            p.call
          end
        end
      end

      r = T_proc_array_push_Runner.new
      r.add { puts "first" }
      r.add { puts "second" }
      puts "before"
      r.call_all
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      before
      first
      second
      after
    OUT
  end

  it "proc body nested block" do
    result = zr(<<~'RUBY')
      class T_proc_body_nested_block_Defer
        def initialize
          @blocks = []
        end

        def add(&blk)
          @blocks.push(blk)
        end

        def call_all
          @blocks.each do |b|
            b.call
          end
        end
      end

      class T_proc_body_nested_block_Runner
        def self.with_deferred(&outer)
          d = T_proc_body_nested_block_Defer.new
          outer.call(d)
          d.call_all
        end
      end

      T_proc_body_nested_block_Runner.with_deferred do |d|
        d.add { puts "first" }
        d.add { puts "second" }
        puts "mid"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      mid
      first
      second
    OUT
  end

  it "proc hash value" do
    result = zr(<<~'RUBY')
      # An ivar set to `{}` takes a captured `&block` proc as a value.

      class T_proc_hash_value_Registry
        def initialize
          @builtins = {}
        end

        def define_builtin(name, &block)
          @builtins[name] = block
        end
      end

      r = T_proc_hash_value_Registry.new
      r.define_builtin("x") { 1 }
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "super with block" do
    result = zr(<<~'RUBY')
      # `super { ... }` from a child method passes a literal block to the
      # parent, so `yield` inside the parent body runs the block.
      class T_super_with_block_Parent
        def test
          yield
        end
      end

      class T_super_with_block_Child < T_super_with_block_Parent
        def test
          super { puts "from child" }
        end
      end

      T_super_with_block_Child.new.test
    RUBY

    _(result).must_answer "from child\n"
  end

  it "while cond side effect" do
    result = zr(<<~'RUBY')
      # `while (n = gets.to_i) > 0` runs the call in the predicate on each
      # iteration, so each iteration reads a new line.
      #
      # The test uses an instance method that returns a String, then
      # calls `.to_i`. The test cannot give input to stdin `gets`, so an
      # iterator class takes its place.

      class T_while_cond_side_effect_Source
        def initialize
          @data = ["5", "4", "3", "0"]
          @idx = 0
        end

        def next_line
          s = @data[@idx]
          @idx += 1
          s
        end
      end

      src = T_while_cond_side_effect_Source.new
      count = 0
      while (n = src.next_line.to_i) > 0
        count += 1
      end
      puts count
    RUBY

    _(result).must_answer "3\n"
  end

  it "while condition recomputed" do
    result = zr(<<~'RUBY')
      # A while condition that depends on a mutated receiver must be evaluated on
      # every iteration.

      items = [1, 2, 3]
      sum = 0

      while items.length > 0
        item = items.pop
        sum += item
      end

      puts sum
      puts items.length

      items2 = [4, 5, 6]
      sum2 = 0

      while items2.length > 0
        sum2 += items2.pop
      end

      puts sum2
      puts items2.length

      items3 = [7, 8, 9]
      packed = 0

      while items3.length != 0
        packed = packed * 10 + items3.shift
      end

      puts packed
      puts items3.length

      class T_while_condition_recomputed_IvarDrain
        def initialize
          @items = [10, 20, 30]
        end

        def drain
          sum = 0
          while @items.length > 0
            sum += @items.pop
          end
          sum
        end

        def remaining
          @items.length
        end
      end

      drain = T_while_condition_recomputed_IvarDrain.new
      puts drain.drain
      puts drain.remaining
    RUBY

    _(result).must_answer <<~'OUT'
      6
      0
      15
      0
      789
      0
      60
      0
    OUT
  end

  it "group_by keys the groups by the block's value" do
    result = zr(<<~'RUBY')
      class Graph
        def key(x) = x % 3
        def buckets = (0...6).group_by { |x| key(x) }
      end
      p Graph.new.buckets
      p (0...6).group_by { |x| x % 3 }
      p %w[a bb ccc dd].group_by { |s| s.length }
    RUBY

    _(result).must_answer <<~'OUT'
      {0 => [0, 3], 1 => [1, 4], 2 => [2, 5]}
      {0 => [0, 3], 1 => [1, 4], 2 => [2, 5]}
      {1 => ["a"], 2 => ["bb", "dd"], 3 => ["ccc"]}
    OUT
  end

  it "an empty Range#sum with a block answers the block's zero, not an integer one" do
    result = zr(<<~'RUBY')
      # An empty `Range#sum { block }` whose block value is a product of Floats
      # read from nested Arrays. The sum uses the block, so it is the Integer 0,
      # and the division gives a Float.
      aug = [[2.0, 3.0, 0.0]]
      x = Array.new(1, 0.0)
      s = (1...1).sum { |j| aug[0][j] * x[j] }
      x[0] = (aug[0][1] - s) / aug[0][0]
      p x
      # non-empty range sum with a block
      t = (0...2).sum { |j| aug[0][j] * 2 }
      p t
    RUBY

    _(result).must_answer "[1.5]\n10.0\n"
  end

  it "sum with a block over objects rounds to the places asked for" do
    result = zr(<<~'RUBY')
      # An object whose ivar comes from a destructured-pair block param, summed via a
      # block and rounded.
      class Shape
        def initialize(s) = @s = s
        def area = @s * 3.14
      end

      shapes = [["a", 2], ["b", 3]].map { |_, s| Shape.new(s) }
      p shapes.sum { |x| x.area }.round(2)
    RUBY

    _(result).must_answer "15.7\n"
  end

  it "instance_exec passes its arguments to a BasicObject's block" do
    result = zr(<<~'RUBY')
      class BO < BasicObject
        def initialize; @x = 0; end
      end
      b001 = BO.new; p(b001.instance_exec(1, 2, 3) { |*xs| xs })
      b002 = BO.new; p(b002.instance_exec(9) { |*xs| xs })
      b003 = BO.new; p(b003.instance_exec(2, 3) { |a, *rest| [a, rest] })
      b004 = BO.new; p(b004.instance_exec { |*xs| xs })
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [9]
      [2, [3]]
      []
    OUT
  end

  it "select and reject with no block answer an Enumerator" do
    result = zr(<<~'RUBY')
      x = (1..3).select
      p x.class
      p x.next
      p [1, 2, 3].select.class
      p [1, 2, 3].reject.class
      p((1..3).select { |i| i.odd? })
      p((1..3).reject { |i| i.odd? })
      p [1, 2, 3].select.with_index { |v, i| i > 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      1
      Enumerator
      Enumerator
      [1, 3]
      [2]
      [2, 3]
    OUT
  end

  it "a method that writes through an Array.new block's array is seen by the caller" do
    result = zr(<<~'RUBY')
      def setit(arr, i)
        arr[i] = 99
      end
      a = Array.new(4) { |i| i }
      setit(a, 1)
      p a

      def bump(arr)
        arr.each_index { |k| arr[k] += 1 }
      end
      b = Array.new(3) { |i| i * 10 }
      bump(b)
      p b

      # a block that returns an empty Array literal
      def push_it(arr)
        arr << 5
      end
      c = Array.new(2) { [] }
      push_it(c)
      p c
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 99, 2, 3]
      [1, 11, 21]
      [[], [], 5]
    OUT
  end

  it "a matrix product built from zip and sum with a block" do
    result = zr(<<~'RUBY')
      a = [[1, 2, 3], [4, 5, 6]]
      b = [[7, 8], [9, 10], [11, 12]]
      result = Array.new(a.size) { Array.new(b.first.size, 0) }
      a.each_with_index do |row, i|
        b.transpose.each_with_index do |col, j|
          result[i][j] = row.zip(col).sum { |x, y| x * y }
        end
      end
      p result
    RUBY

    _(result).must_answer "[[58, 64], [139, 154]]\n"
  end

  it "Kernel#loop with no block answers an endless Enumerator of nil" do
    result = zr(<<~'RUBY')
      # Blockless Kernel#loop returns an infinite Enumerator (yields nil).
      e = loop
      p e.class
      p loop.first(3)
      p loop.take(2)
      e2 = loop
      p e2.next
      p e2.next
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [nil, nil, nil]
      [nil, nil]
      nil
      nil
    OUT
  end
end
