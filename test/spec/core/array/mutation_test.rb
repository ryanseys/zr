# frozen_string_literal: true

require "spec_helper"

describe "Array: changing in place" do
  it "clear answers the emptied array in expression position, whatever its element kind" do
    result = zr(<<~'RUBY')
      # Array#clear in expression position returns the emptied array, for
      # every element kind.

      p [1, 2, 3, 4].clear                #=> []
      p ["a", "b"].clear                   #=> []
      p [1.0, 2.0].clear                   #=> []
      p [:x, :y].clear                     #=> []
      p([1, 2, 3, 4].clear == [])          #=> true (same-typed empty arrays)
      p ["a", "b"].clear.length            #=> 0
      p [1.0, 2.0].clear.length            #=> 0

      # clear after a shift resets the array, so a later push refills
      # from index 0.
      a = [1, 2, 3]
      a.shift
      a.clear
      a.push(9)
      p a                                   #=> [9]

      # Statement form still empties in place.
      b = ["x", "y", "z"]
      b.clear
      p b.length                            #=> 0
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
      []
      true
      0
      0
      [9]
      0
      done
    OUT
  end

  it "rfind, fetch_values, try_convert, deconstruct and the prepend and append aliases answer" do
    result = zr(<<~'RUBY')
      # Array conformance: rfind, fetch_values (+IndexError), Array.try_convert,
      # empty-literal sample, deconstruct/to_ary identity, prepend/append aliases.
      p [1, 2, 3, 4].rfind { |x| x.even? }
      p [1, 2, 3, 4].rfind { |x| x > 10 }
      p [1, 2, 3].fetch_values(0, 2)
      p [1, 2, 3].fetch_values(0, -1)
      begin
        [1, 2, 3].fetch_values(0, 5)
      rescue IndexError => e
        puts "IE: #{e.message}"
      end
      p Array.try_convert([1, 2])
      p Array.try_convert("x")
      p [].sample
      p [1, 2, 3].deconstruct
      p [1, 2].to_ary
      p [].to_ary
      p [].deconstruct
      p [1, 2].prepend(0)
      a = [1, 2]; a.append(nil); p a
    RUBY

    _(result).must_answer <<~'OUT'
      4
      nil
      [1, 3]
      [1, 3]
      IE: index 5 outside of array bounds: -3...3
      [1, 2]
      nil
      nil
      [1, 2, 3]
      [1, 2]
      []
      []
      [0, 1, 2]
      [1, 2, nil]
    OUT
  end

  it "eql? and uniq are class-strict, and an array compares 0 with itself without deadlock" do
    result = zr(<<~'RUBY')
      # insert past the end pads with nil; eql?/uniq are class-strict (1 != 1.0);
      # <=> of an array with itself (incl. a cycle) is 0 without deadlock.
      #
      # The self-comparison needs a self-referential array, and it is still one
      # at exit -- the program never breaks the ring.
      # At exit: cycle leak: 1 objects (Array x1)

      b = [1, 2, 3]
      b.insert(5, 8)
      p b
      p [1, 2].eql?([1, 2.0])
      p [1, 2].eql?([1, 2])
      p [1.0, 1].uniq
      a = [1, 2, 3]
      p(a <=> a)
      r = [1, 2]
      r.push(r)
      p(r <=> r)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, nil, nil, 8]
      false
      true
      [1.0, 1]
      0
      0
    OUT
  end

  it "insert with no values leaves the array alone, whatever its element kind" do
    result = zr(<<~'RUBY')
      p [1, 2, 3].insert(1)
      w = [1, 2, 3].insert(1); p w
      p [1, 2, 3].insert(1, 9)
      p ["a", "b"].insert(0)
      x = [1, "a"]
      p x.insert(1)
      p [1.5, 2.5].insert(-1)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      [1, 9, 2, 3]
      ["a", "b"]
      [1, "a"]
      [1.5, 2.5]
    OUT
  end

  it "insert past the end pads the gap with nil" do
    result = zr(<<~'RUBY')
      # Array#insert beyond the length pads with nils like CRuby, on typed
      # int/str arrays (nil sentinel / NULL) and poly arrays.
      b = [1, 2, 3]
      b.insert(5, 8)
      p b
      s = %w[a b]
      s.insert(4, "z")
      p s
      q = [1, "x"]
      q.insert(4, :y)
      p q
      n = [1, 2]
      n.insert(1, 9)
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, nil, nil, 8]
      ["a", "b", nil, nil, "z"]
      [1, "x", nil, nil, :y]
      [1, 9, 2]
    OUT
  end

  it "append and prepend widen the local when the value its element kind cannot hold arrives" do
    result = zr(<<~'RUBY')
      # Array#append / #prepend are exact aliases for #push / #unshift. A value
      # of a different kind (e.g. nil onto an Integer array) keeps its own
      # value. It does not become 0.

      a = [1, 2]
      a.append(nil)
      p a                                   #=> [1, 2, nil]

      b = [1, 2]
      b.prepend(nil)
      p b                                   #=> [nil, 1, 2]

      c = [1, 2]
      c.append(3, nil)
      p c                                   #=> [1, 2, 3, nil]

      d = [1, 2]
      d.prepend(nil, 3)
      p d                                   #=> [nil, 3, 1, 2]

      e = [1, 2]
      e.append("x")
      p e                                   #=> [1, 2, "x"]

      f = [1, 2]
      f.push(3, nil)
      p f                                   #=> [1, 2, 3, nil]

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, nil]
      [nil, 1, 2]
      [1, 2, 3, nil]
      [nil, 3, 1, 2]
      [1, 2, "x"]
      [1, 2, 3, nil]
      done
    OUT
  end

  it "capturing a self-returning mutator that widens reads the receiver at its new layout" do
    result = zr(<<~'RUBY')
      # A self-returning Array mutator that adds an element of a new kind
      # returns the receiver. The captured value and the receiver show the
      # same elements.
      a001 = [1, 2]
      c001 = a001.push(:x)
      p c001
      p a001

      a002 = [1, 2]
      c002 = a002.unshift(:x)
      p c002

      a003 = [1, 2]
      c003 = (a003 << :x)
      p c003

      a004 = [1, 2]
      c004 = a004.concat([:x])
      p c004

      a005 = [1, 2]
      c005 = a005.insert(1, :x)
      p c005

      a006 = [1, 2]
      c006 = a006.push("x")
      p c006

      # an element of the same kind: the capture is the receiver too
      a007 = [1, 2]
      c007 = a007.push(3)
      p c007
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, :x]
      [1, 2, :x]
      [:x, 1, 2]
      [1, 2, :x]
      [1, 2, :x]
      [1, :x, 2]
      [1, 2, "x"]
      [1, 2, 3]
    OUT
  end

  it "rotate! turns every element kind, wrapping counts and the empty and single-element edges" do
    result = zr(<<~'RUBY')
      # rotate! over every element kind, including the wrap-around counts and the
      # empty / single-element edges: the block-move form has to agree with the
      # rotation it replaced.
      a = [1, 2, 3, 4, 5]
      a.rotate!
      p a
      a.rotate!(2)
      p a
      a.rotate!(-1)
      p a
      a.rotate!(0)
      p a
      a.rotate!(5)
      p a
      a.rotate!(7)
      p a
      b = ["a", "b", "c", "d"]
      b.rotate!(3)
      p b
      c = [1.5, 2.5, 3.5]
      c.rotate!(1)
      p c
      d = [1, "x", :y, nil]
      d.rotate!(2)
      p d
      e = []
      e.rotate!(3)
      p e
      f = [9]
      f.rotate!(4)
      p f
      big = (1..40).to_a
      big.rotate!(35)
      p big.first(3)
      p big.last(3)
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3, 4, 5, 1]
      [4, 5, 1, 2, 3]
      [3, 4, 5, 1, 2]
      [3, 4, 5, 1, 2]
      [3, 4, 5, 1, 2]
      [5, 1, 2, 3, 4]
      ["d", "a", "b", "c"]
      [2.5, 3.5, 1.5]
      [:y, nil, 1, "x"]
      []
      [9]
      [36, 37, 38]
      [33, 34, 35]
    OUT
  end

  it "select!, filter!, keep_if, reject! and delete_if filter in place and answer the receiver" do
    result = zr(<<~'RUBY')
      # Array#select! / #filter! / #keep_if / #reject! / #delete_if filter the
      # array in place and return the receiver. Elements keep their type.
      a = [1, 2, 3, 4, 5]
      a.select! { |x| x.even? }
      p a

      b = [1, 2, 3, 4, 5]
      b.reject! { |x| x.even? }
      p b

      c = [1, 2, 3, 4, 5]
      c.keep_if { |x| x > 2 }
      p c

      d = [1, 2, 3, 4, 5]
      d.delete_if { |x| x > 2 }
      p d

      e = ["apple", "fig", "cherry"]
      e.select! { |s| s.length > 3 }
      p e

      g = [1, "two", 3, "four"]
      g.select! { |x| x.is_a?(Integer) }
      p g

      h = [:a, :bb, :ccc]
      h.reject! { |x| x.size > 1 }
      p h

      # Return value is the (mutated) receiver when elements change.
      i = [1, 2, 3, 4]
      r = i.select! { |x| x > 2 }
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4]
      [1, 3, 5]
      [3, 4, 5]
      [1, 2]
      ["apple", "cherry"]
      [1, 3]
      [:a]
      [3, 4]
    OUT
  end

  it "element site reads and writes in place" do
    result = zr(<<~'RUBY')
      # `a[i]` and `a[i] = v` with a fixnum index in range are read and written
      # in place at the site; every other case still reaches Array's methods, and
      # a redefinition of `[]`, `[]=`, `/` or `%` turns the site back into a call.
      a = [10, 20, 30]
      p [a[0], a[2], a[3], a[-1], a[-4], a[1.0], a["x"] ? 1 : 0] rescue p $!.class
      p [a[0], a[2], a[3], a[-1], a[-4], a[1.0]]
      a[1] = 21
      a[3] = 40
      a[-1] = 41
      a[6] = 70
      p a
      begin
        a[9.5] = 1
      rescue TypeError => e
        p e.class
      end
      f = [1, 2].freeze
      begin
        f[0] = 9
      rescue FrozenError => e
        p [e.class, e.message]
      end
      p f[0]
      begin
        a[-10] = 1
      rescue IndexError => e
        p [e.class, e.message]
      end
      h = { 1 => :one }
      p [h[1], h[2]]
      h[2] = :two
      p h

      p [7 / 2, -7 / 2, 7 / -2, -7 / -2, 0 / 5, 7 % 2, -7 % 2, 7 % -2, -7 % -2, 0 % 5, 5 % 5]
      p [(2**61) / 3, (2**61) % 7, -(2**61) / 3, -(2**61) % 7, 4611686018427387903 % 2, 4611686018427387903 / 2]
      begin
        7 / 0
      rescue ZeroDivisionError => e
        p e.class
      end
      begin
        7 % 0
      rescue ZeroDivisionError => e
        p e.class
      end

      class Array
        alias_method :old_aref, :[]
        def [](i) = "got #{i}"
        def []=(i, v)
          old_aref(0)
        end
      end
      b = [5, 6]
      p [b[0], b[-1], b[1] = 8, b]
      class Integer
        def %(o) = :mod
        def /(o) = :div
      end
      p [7 % 2, 7 / 2, -7 % 2]

    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      [10, 30, nil, 30, nil, 20]
      [10, 21, 30, 41, nil, nil, 70]
      [FrozenError, "can't modify frozen Array: [1, 2]"]
      1
      [:one, nil]
      {1 => :one, 2 => :two}
      [3, -4, -4, 3, 0, 1, 1, -1, -1, 0, 0]
      [768614336404564650, 2, -768614336404564651, 5, 1, 2305843009213693951]
      ZeroDivisionError
      ZeroDivisionError
      ["got 0", "got -1", 8, [5, 6]]
      [:mod, :div, :mod]
    OUT
  end

  it "int array uniq bang" do
    result = zr(<<~'RUBY')
      # Array#uniq! on an Integer Array removes the duplicates in place.
      # (CRuby returns self when something was removed and nil otherwise.
      # This test prints the receiver, not the return value.)
      a = [1, 2, 2, 3, 3, 3]
      a.uniq!
      puts a.inspect

      b = [1, 2, 3]
      b.uniq!
      puts b.inspect

      c = []
      c.uniq!
      puts c.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      []
    OUT
  end

  it "reverse bang reverses in place" do
    result = zr(<<~'RUBY')
      # reverse! swaps the elements where they are and answers the receiver;
      # reverse, reverse_each and a subclass read a plain reversed copy.
      a = [1, 2, 3, 4, 5]
      p a.reverse!.equal?(a), a, a.reverse!, [].reverse!, [1].reverse!, [1, 2].reverse!
      b = a.reverse
      p b, b.class, a, a.reverse_each.to_a, a.reverse.equal?(a)
      class Stack < Array; end
      s = Stack.new([3, 1, 2])
      p s.reverse.class, s.reverse!.class, s
      f = [1, 2].freeze
      p (f.reverse! rescue $!.class), f.reverse
      q = (1..10_000).to_a
      q.reverse!
      p q.first(3), q.last(3), q.reverse.first(3), [].method(:reverse!).arity, [].method(:reverse!).source_location

    RUBY

    _(result).must_answer <<~'OUT'
      true
      [1, 2, 3, 4, 5]
      [1, 2, 3, 4, 5]
      []
      [1]
      [2, 1]
      [5, 4, 3, 2, 1]
      Array
      [1, 2, 3, 4, 5]
      [5, 4, 3, 2, 1]
      false
      Array
      Stack
      [2, 1, 3]
      FrozenError
      [2, 1]
      [10000, 9999, 9998]
      [3, 2, 1]
      [1, 2, 3]
      0
      nil
    OUT
  end

  it "a self-splice past the end copies the array as it was" do
    result = zr(<<~'RUBY')
      b = [1, 2, 3, 4, 5, 6, 7, 8]
      b[5, 0] = b
      p b
      c = [1, 2, 3]
      c[1, 1] = c
      p c
      d = [1, 2, 3]
      d[0..0] = d
      p d
      e = [1, 2]
      e.concat(e, e)
      p e
      f = [1, 2, 3]
      f.insert(1, *f)
      p f
      g = [1, 2, 3]
      g[10, 0] = g
      p g
      h = [1, 2, 3]
      h.replace(h)
      p h
      i = [1, 2, 3]
      i.unshift(*i)
      p i
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4, 5, 1, 2, 3, 4, 5, 6, 7, 8, 6, 7, 8]
      [1, 1, 2, 3, 3]
      [1, 2, 3, 2, 3]
      [1, 2, 1, 2, 1, 2]
      [1, 1, 2, 3, 2, 3]
      [1, 2, 3, nil, nil, nil, nil, nil, nil, nil, 1, 2, 3]
      [1, 2, 3]
      [1, 2, 3, 1, 2, 3]
    OUT
  end
end
