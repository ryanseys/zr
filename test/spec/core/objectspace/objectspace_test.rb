# frozen_string_literal: true

require "spec_helper"

describe "ObjectSpace programs" do
  it "each object count objects and id2ref" do
    result = zr(<<~'RUBY')
      # ObjectSpace walks the heap: each_object by class, the singleton classes a
      # walk shows and hides as internal_object_p does, the census by type, and
      # _id2ref for an id a program asked for.
      class Shape; end
      class Circle < Shape; end
      class Square < Shape; end
      o = Object.new
      def o.x = 1
      p ObjectSpace.each_object(Class).select { |k| k < Shape }.sort_by(&:name)
      p ObjectSpace.each_object(Shape.singleton_class).to_a.sort_by(&:name)
      p ObjectSpace.each_object(Class).any? { |k| k.singleton_class? && k.attached_object == o }
      shapes = [Circle.new, Circle.new, Square.new]
      p ObjectSpace.each_object(Circle).count
      e = ObjectSpace.each_object(Shape)
      p e.class, e.size
      p ObjectSpace.each_object(Square) { |s| p s.class }
      p ObjectSpace.count_objects.first(2).map(&:first)
      counts = ObjectSpace.count_objects
      p counts[:TOTAL] >= counts[:FREE] + counts[:T_STRING], counts.keys.include?(:T_ARRAY)
      h = {}
      p ObjectSpace.count_objects(h).equal?(h)
      x = "hello"
      p ObjectSpace._id2ref(x.object_id).equal?(x)
      p ObjectSpace._id2ref(nil.object_id), ObjectSpace._id2ref(7.object_id), ObjectSpace._id2ref(true.object_id)
      p((ObjectSpace._id2ref(1 << 40) rescue $!))
      p((ObjectSpace._id2ref(:a) rescue $!))
      p((ObjectSpace.each_object(3) rescue $!))
      p shapes.size

    RUBY

    _(result).must_answer <<~'OUT'
      [Circle, Square]
      [Circle, Shape, Square]
      true
      2
      Enumerator
      nil
      Square
      1
      [:TOTAL, :FREE]
      true
      true
      true
      true
      nil
      7
      true
      #<RangeError: 1099511627776 is not an id value>
      #<TypeError: no implicit conversion of Symbol into Integer>
      #<Enumerator: ObjectSpace:each_object(3)>
      3
    OUT
  end

  it "hash param each kv weak default" do
    result = zr(<<~'RUBY')
      # A method param that holds a Hash with String keys and values, where
      # the body iterates it with `pname.each do |k, v|`. This is the usual
      # string-keyed-Hash shape in Rails/Tep-like code.

      # Shape 1: the body concatenates `+ k + "=" + v` into `out`, so
      # both k and v are Strings.
      module Joiner
        def self.encode(h)
          out = ""
          first = true
          h.each do |k, v|
            if !first
              out = out + ","
            end
            first = false
            out = out + k + "=" + v
          end
          out
        end
      end

      puts Joiner.encode({"a" => "1", "b" => "2"})    # a=1,b=2

      # Shape 2: no concatenation, just each|k,v|. The body pushes each k
      # and v into an ivar array.
      class HashDumper
        def initialize
          @pairs = []
        end
        attr_reader :pairs

        def collect(h)
          h.each do |k, v|
            @pairs << k
            @pairs << v
          end
        end
      end

      d = HashDumper.new
      d.collect({"name" => "ada", "role" => "engineer"})
      puts d.pairs.length.to_s   # 4
      puts d.pairs[0]            # name
      puts d.pairs[1]            # ada
      puts d.pairs[2]            # role
      puts d.pairs[3]            # engineer
    RUBY

    _(result).must_answer <<~'OUT'
      a=1,b=2
      4
      name
      ada
      role
      engineer
    OUT
  end

  it "object spaceship default" do
    result = zr(<<~'RUBY')
      class C; end
      o = C.new
      p(o <=> o)
      p(o <=> C.new)
      class D; end
      p(o <=> D.new)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      nil
      nil
    OUT
  end

  it "objspace's reachable_objects_from_root and internal_super_of answer" do
    result = zr(<<~'RUBY')
      require "objspace"
      def t(name)
        p [name, yield]
      rescue Exception => e
        p [name, e.class, e.message]
      end
      t(:roots) { r = ObjectSpace.reachable_objects_from_root; [r.class, r.keys.all?(String)] }
      t(:internal_super) { ObjectSpace.internal_super_of(String).class }
    RUBY

    _(result).must_answer <<~'OUT'
      [:roots, [Hash, true]]
      [:internal_super, ObjectSpace::InternalObjectWrapper]
    OUT
  end
end
