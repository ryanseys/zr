# frozen_string_literal: true

require "spec_helper"

describe "ObjectSpace: the objspace library" do
  it "gc weak" do
    result = zr(<<~'RUBY')
      # Weak references and finalizers: ObjectSpace::WeakMap (identity-keyed, holding
      # weak references to its keys and values), WeakRef (a delegator that raises
      # once its referent is gone), and ObjectSpace.define_finalizer.
      require "weakref"
      require "objspace"

      # --- ObjectSpace::WeakMap: an identity-keyed weak map ---
      # Keys and values are kept alive here by ordinary local variables, so the map
      # reads back exactly what was put in; entries would vanish only once their key
      # had no other reference anywhere.
      cache = ObjectSpace::WeakMap.new
      alice = Object.new
      bob = Object.new
      name_a = "Alice"
      name_b = "Bob"
      cache[alice] = name_a
      cache[bob] = name_b
      puts cache[alice]
      puts cache.key?(bob)
      puts cache.length
      puts cache.values.sort.inspect
      # Identity keying: a fresh, distinct object is never a member.
      puts cache.key?(Object.new)
      # delete returns the value and drops the entry.
      puts cache.delete(alice)
      puts cache.key?(alice)
      puts cache.length

      # --- WeakRef: delegate to a referent while it lives ---
      class Sensor
        def initialize(name) = (@name = name)
        def reading = "#{@name}: 42"
      end
      sensor = Sensor.new("temp")
      ref = WeakRef.new(sensor)
      puts ref.reading            # delegated to the referent
      puts ref.weakref_alive?
      puts ref.respond_to?(:reading)

      # Once the referent has been collected, every delegated call raises RefError.
      def dangling = WeakRef.new(Object.new)
      dead = dangling
      GC.start
      begin
        dead.reading
      rescue WeakRef::RefError => e
        puts "recycled: #{e.message}"
      end

      # --- define_finalizer: a best-effort callback that runs at program exit ---
      keeper = Object.new
      ObjectSpace.define_finalizer(keeper, proc { |_id| puts "keeper finalized at exit" })
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      Alice
      true
      2
      ["Alice", "Bob"]
      false
      Alice
      false
      1
      temp: 42
      true
      true
      recycled: Invalid Reference - probably recycled
      done
      keeper finalized at exit
    OUT
  end

  it "objspace introspection" do
    result = zr(<<~'RUBY')
      # `ObjectSpace`'s introspection half. CRuby ships it as `ext/objspace`, which
      # adds these methods to the module `gc.c` already defined, and so does
      # this runtime: `require "objspace"` loads them.
      #
      # `memsize_of`'s figures are implementation-defined in CRuby too ("dependent on
      # the version and build of the interpreter"), so only the SHAPE of the answer
      # is asserted here -- zero for an immediate, growing with the payload.
      require "objspace"

      p [nil, true, 1, :sym, 1.5].map { |v| ObjectSpace.memsize_of(v) }
      p ObjectSpace.memsize_of("hi").positive?
      p ObjectSpace.memsize_of("x" * 500) > ObjectSpace.memsize_of("hi")
      p ObjectSpace.memsize_of([1, 2, 3]) >= ObjectSpace.memsize_of([])

      # `reachable_objects_from` leads with the object's class, then its direct
      # references in order, dropping immediates (which aren't heap objects).
      p ObjectSpace.reachable_objects_from(nil)
      p ObjectSpace.reachable_objects_from(1)
      p ObjectSpace.reachable_objects_from(:sym)
      p ObjectSpace.reachable_objects_from("hi")
      p ObjectSpace.reachable_objects_from([1, "a", :b, "c"])
      p ObjectSpace.reachable_objects_from({ "k" => "v", 1 => 2 })
      p ObjectSpace.reachable_objects_from(1..5)
      # A bignum is the one heap shape whose class isn't a traversed reference.
      p ObjectSpace.reachable_objects_from(2**70)

      class Widget
        def initialize
          @name = "gear"
          @count = 3
        end
      end
      p ObjectSpace.reachable_objects_from(Widget.new)

      # Every symbol is immortal (nothing ever leaves the table), so the total is
      # the one census figure that can be answered.
      p ObjectSpace.count_symbols[:immortal_symbol].is_a?(Integer)
      p [ObjectSpace.count_nodes, ObjectSpace.count_tdata_objects].map(&:class)

      # Untraced objects have no allocation record -- nil, in CRuby as well.
      p ObjectSpace.allocation_sourcefile("x")
      p ObjectSpace.allocation_sourceline("x")
      p ObjectSpace.allocation_class_path("x")
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0, 0, 0, 0]
      true
      true
      true
      nil
      nil
      nil
      [String]
      [Array, "a", "c"]
      [Hash, "k", "v"]
      [Range]
      []
      [Widget, "gear"]
      true
      [Hash, Hash]
      nil
      nil
      nil
    OUT
  end

  it "objspace traces allocations" do
    result = zr(<<~'RUBY')
      # ObjectSpace.trace_object_allocations records where each object was made:
      # the file and line of the Ruby code, and the C method it was made in, if
      # any. An object made while tracing is off has no record.
      require "objspace"

      class Foo
        def make = "x" * 2
      end

      ObjectSpace.trace_object_allocations do
        $made = Object.new
        $joined = Foo.new.make
        $mapped = [1, 2].map { |v| v.to_s }
      end
      [$made, $joined, $mapped, $mapped[0]].each do |obj|
        p [ObjectSpace.allocation_sourcefile(obj), ObjectSpace.allocation_sourceline(obj),
           ObjectSpace.allocation_class_path(obj), ObjectSpace.allocation_method_id(obj),
           ObjectSpace.allocation_generation(obj).class]
      end
      p ObjectSpace.allocation_sourcefile(Object.new)
      p ObjectSpace.trace_object_allocations_start, ObjectSpace.trace_object_allocations_stop
      p ObjectSpace.trace_object_allocations_clear
      p ObjectSpace.allocation_sourcefile($made)

      # The census and the sizes.
      p ObjectSpace.memsize_of_all.class, ObjectSpace.memsize_of_all(String).positive?
      sizes = ObjectSpace.count_objects_size
      p sizes.keys.first(3), sizes.keys.last, sizes[:TOTAL] >= sizes[:T_STRING]
      p ObjectSpace.count_symbols.keys
      p ObjectSpace.count_tdata_objects.class, ObjectSpace.count_imemo_objects.class
      p ObjectSpace.internal_class_of("a")

      # dump writes JSON; the address and the sizes are the runtime's own.
      p ObjectSpace.dump("abc")[/"type":"STRING"/], ObjectSpace.dump("abc")[/"value":"abc"/]
      p ObjectSpace.dump(nil), ObjectSpace.dump(7), ObjectSpace.dump(true)

    RUBY

    _(result).must_answer <<~'OUT'
      ["stdlib/objspace/objspace_test.rb", 11, nil, nil, Integer]
      ["stdlib/objspace/objspace_test.rb", 7, "String", :*, Integer]
      ["stdlib/objspace/objspace_test.rb", 13, "Array", :map, Integer]
      ["stdlib/objspace/objspace_test.rb", 13, "Integer", :to_s, Integer]
      nil
      nil
      nil
      nil
      nil
      Integer
      true
      [:T_OBJECT, :T_CLASS, :T_MODULE]
      :TOTAL
      true
      [:mortal_dynamic_symbol, :immortal_dynamic_symbol, :immortal_static_symbol, :immortal_symbol]
      Hash
      Hash
      String
      "\"type\":\"STRING\""
      "\"value\":\"abc\""
      "null"
      "7"
      "true"
    OUT
  end

  it "dump writes special constants as ruby does and ends each object with a newline" do
    result = zr(<<~'RUBY')
      require "objspace"
      # A special constant is its JSON value, a static Symbol its name, and a
      # flonum "%#g"; any other object is a line of its own.
      p ObjectSpace.dump(nil), ObjectSpace.dump(7), ObjectSpace.dump(:sym), ObjectSpace.dump(1.5)
      p ObjectSpace.dump("x").end_with?("}\n"), ObjectSpace.dump(1e300)[/"frozen":true, "value":"[^"]*"/]
      p ObjectSpace.dump(Object.new)[/"address":"(0x\h+)"/, 1].match?(/\A0x[1-9a-f]/)
    RUBY

    _(result).must_answer <<~'OUT'
      "null"
      "7"
      "{\"type\":\"SYMBOL\", \"value\":\"sym\"}"
      "1.50000"
      true
      "\"frozen\":true, \"value\":\"1.00000e+300\""
      true
    OUT
  end
end
