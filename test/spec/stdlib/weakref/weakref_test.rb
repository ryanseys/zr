# frozen_string_literal: true

require "spec_helper"

describe "Weakref programs" do
  it "is a real delegator" do
    result = ze0(<<~'RUBY')
      # `WeakRef` is CRuby's own pure-Ruby file now (`gems/weakref`), so it really
      # descends from `Delegator < BasicObject` -- which means a `WeakRef` is NOT an
      # `Object`, the one consequence with a sharp edge (a guard sorted it the wrong
      # way before). The builtin id is a namespace slot only: it exists so
      # `WeakRef::RefError` has a scope, and the vendored file's `< Delegator`
      # establishes the superclass.
      require "weakref"

      p WeakRef.superclass.to_s
      p WeakRef.ancestors.map(&:to_s).include?("Delegator")
      p WeakRef.ancestors.map(&:to_s).include?("Object")

      referent = +"referent"
      w = WeakRef.new(referent)
      p w.is_a?(Delegator)
      p w.is_a?(Object)
      p w.upcase
      p w.weakref_alive?
      p w.respond_to?(:upcase)
      p w.respond_to?(:no_such_method)
      p w.__getobj__.equal?(referent)

      # A `true`/`false`/`nil` referent cannot go in a WeakMap, so weakref.rb stashes
      # it in an ivar -- which is why `weakref_alive?` answers `defined?`'s String.
      t = WeakRef.new(true)
      p t.weakref_alive?

      # A user subclass runs its OWN initialize and reaches WeakRef's through super.
      class TaggedRef2 < WeakRef
        def initialize(obj)
          super(obj)
          @tagged = true
        end

        def tagged? = @tagged
      end
      s = +"held"
      r = TaggedRef2.new(s)
      p r.class
      p r.tagged?
      p r.upcase
      p r.weakref_alive?
      p TaggedRef2.ancestors.map(&:to_s).first(3)

      # Arity is the vendored file's own.
      begin; WeakRef.new; rescue ArgumentError => e; p e.message; end
      begin; WeakRef.new(1, 2); rescue ArgumentError => e; p e.message; end

      # `WeakRef::RefError` is a StandardError, resolvable by name.
      p WeakRef::RefError.superclass.to_s
      p WeakRef::RefError.ancestors.map(&:to_s).include?("StandardError")

      # `Delegator` and its concrete subclasses are untouched.
      p SimpleDelegator.superclass.to_s
      p DelegateClass(Hash).superclass.to_s
      p SimpleDelegator.new([1, 2]).size
    RUBY

    _(result).must_answer <<~'OUT'
      "Delegator"
      true
      false
      true
      false
      "REFERENT"
      true
      true
      false
      true
      "instance-variable"
      TaggedRef2
      true
      "HELD"
      true
      ["TaggedRef2", "WeakRef", "Delegator"]
      "wrong number of arguments (given 0, expected 1)"
      "wrong number of arguments (given 2, expected 1)"
      "StandardError"
      true
      "Delegator"
      "Delegator"
      2
    OUT
  end

  it "raises ref error once collected" do
    result = ze0(<<~'RUBY')
      # `nil`, not `false`: weakref.rb spells it `@@__map.key?(self) or
      # defined?(@delegate_sd_obj)`, and `defined?` answers nil.

      require "weakref"
      def make = WeakRef.new(Object.new)
      w = make
      GC.start
      p w.weakref_alive?
      begin
        w.some_method
      rescue WeakRef::RefError => e
        puts "RefError: #{e.message}"
      end
      begin
        w.__getobj__
      rescue WeakRef::RefError => e
        puts "getobj: #{e.class}"
      end
      # WeakRef::RefError is a StandardError, so a bare rescue catches it
      p WeakRef::RefError.superclass
      p WeakRef::RefError.ancestors.include?(StandardError)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      RefError: Invalid Reference - probably recycled
      getobj: WeakRef::RefError
      StandardError
      true
    OUT
  end

  it "weakref delegates to a live referent" do
    result = ze0(<<~'RUBY')
      require "weakref"
      s = "hello"
      w = WeakRef.new(s)
      p w.class
      p w.upcase
      p w.__getobj__
      p w.weakref_alive?
      p w.respond_to?(:upcase)
      p w.respond_to?(:no_such_method)
      obj = Object.new
      def obj.greet(name) = "hi, #{name}"
      w2 = WeakRef.new(obj)
      p w2.greet("world")
    RUBY

    _(result).must_answer <<~'OUT'
      WeakRef
      "HELLO"
      "hello"
      true
      true
      false
      "hi, world"
    OUT
  end

  it "weakref subclass is the native delegator" do
    result = ze0(<<~'RUBY')
      # `WeakRef`'s constructor takes the receiver class, so a subclass IS the
      # native delegator -- no payload wrapper, no re-tagging. What a subclass
      # needs beyond that is its own copy of the two delegation rows: the send-miss
      # fallback looks `method_missing` up on the receiver's own class, so without
      # them every forwarded name raises instead. hexapdf's `NullableWeakRef` is
      # the shape, and it reaches the corpus through thirteen gems.
      require "weakref"

      class NullableWeakRef < WeakRef
        def __getobj__
          super
        rescue StandardError
          nil
        end

        def shout = "#{__getobj__.upcase}!"
      end

      target = "held"
      ref = NullableWeakRef.new(target)

      p ref.class
      p NullableWeakRef.superclass
      p ref.is_a?(WeakRef)
      p ref.weakref_alive?
      p ref.__getobj__
      p ref.shout
      p ref.upcase
      p ref.length
      p ref.respond_to?(:upcase)
      p ref.respond_to?(:no_such_method_at_all)
    RUBY

    _(result).must_answer <<~'OUT'
      NullableWeakRef
      WeakRef
      true
      true
      "held"
      "HELD!"
      "HELD"
      4
      true
      false
    OUT
  end

  it "weakref subclass runs its own initialize" do
    result = ze0(<<~'RUBY')
      # `class TaggedRef < WeakRef` used to be registered with the ROOT's own
      # constructor, which seated the referent straight from the args -- the
      # subclass's `initialize` never ran and `@tagged` read back nil.
      #
      # A `WeakRef` is now allocated UNSEATED and `initialize` seats it, so a
      # subclass's body runs and its `super(obj)` reaches `WeakRef#initialize`, the
      # same split CRuby's pure-Ruby weakref.rb has. That split also made the rest
      # of the surface expressible, and the oracle disagreed with zeo on all of it:
      #
      #   - `__setobj__` is a NO-OP answering nil. The referent lives in a map keyed
      #     on the WeakRef object, which `__setobj__` never touches; the method
      #     exists only because `Delegator` demands it.
      #   - `weakref_alive?` is `@@__map.key?(self) or defined?(@delegate_sd_obj)`,
      #     so it answers `true`, `defined?`'s STRING, or nil -- never `false`.
      #   - `#dup` LOSES the referent (the copy is a different map key). Only a
      #     `true`/`false`/`nil` referent survives, because that one is stashed in
      #     an ivar rather than the map.
      require "weakref"

      class TaggedRef < WeakRef
        def initialize(obj)
          super(obj)
          @tagged = true
        end

        def tagged? = @tagged
      end

      s = +"referent"
      r = TaggedRef.new(s)
      p r.class
      p r.tagged?
      p r.upcase
      p r.weakref_alive?

      # A subclass with no body of its own still works.
      class PlainRef < WeakRef; end
      p PlainRef.new(s).upcase

      w = WeakRef.new(s)
      p w.__setobj__(+"ignored")
      p w.__getobj__

      # The three referents that live in an ivar instead of the map.
      p WeakRef.new(true).weakref_alive?
      p WeakRef.new(true).__getobj__
      p WeakRef.new(false).__getobj__
      p WeakRef.new(nil).__getobj__
      # ... and two immediates that do go in the map.
      p WeakRef.new(7).__getobj__
      p WeakRef.new(:sym).weakref_alive?

      # A copy keeps only the ivar-held kind.
      p w.dup.weakref_alive?
      begin
        w.dup.__getobj__
      rescue WeakRef::RefError => e
        p [e.class.to_s, e.message]
      end
      d = WeakRef.new(true).dup
      p [d.weakref_alive?, d.__getobj__]

      begin
        WeakRef.new
      rescue ArgumentError => e
        p e.message
      end
      begin
        WeakRef.new(s, 2)
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      TaggedRef
      true
      "REFERENT"
      true
      "REFERENT"
      nil
      "referent"
      "instance-variable"
      true
      false
      nil
      7
      true
      nil
      ["WeakRef::RefError", "Invalid Reference - probably recycled"]
      ["instance-variable", true]
      "wrong number of arguments (given 0, expected 1)"
      "wrong number of arguments (given 2, expected 1)"
    OUT
  end
end
