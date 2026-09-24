# frozen_string_literal: true

require "spec_helper"

describe "Delegate programs" do
  it "class nested in a runtime minted namespace" do
    result = zr(<<~'RUBY')
      # `class SecretKeys::Encryptor` where `SecretKeys` itself came from
      # `class SecretKeys < DelegateClass(Hash)` -- a namespace no compile-time class
      # backs, because its own superclass is only computed when the program RUNS.
      #
      # The static path can only report `unknown class/module SecretKeys`, so the
      # nested definition is minted at runtime too: the constant lands inside the
      # parent that does exist by then. `Kanshi = Class.new` and
      # `class FA < Struct.new(...)` reach the same place by different routes.
      require "delegate"

      class SecretKeys < DelegateClass(Hash)
        def initialize(h)
          super
        end
      end

      # A body carrying everything the runtime spelling has to re-say: a constant,
      # a class method, an `include`, a visibility directive and an `alias`.
      module Tagged
        def tagged = "<#{tag}>"
      end

      class SecretKeys::Encryptor
        PREFIX = "$AES$:"
        include Tagged

        def self.build = new
        def tag = "enc"
        def encrypt(s) = PREFIX + hidden(s)
        alias cipher encrypt

        private

        def hidden(s) = s.reverse
      end

      module SecretKeys::Util
        def self.on? = true
      end

      p SecretKeys::Encryptor::PREFIX
      p SecretKeys::Encryptor.build.tagged
      p SecretKeys::Encryptor.new.encrypt("abc")
      p SecretKeys::Encryptor.new.cipher("abc")
      p SecretKeys::Encryptor.name
      p SecretKeys::Util.on?
      begin
        SecretKeys::Encryptor.new.hidden("x")
      rescue NoMethodError => e
        puts e.message
      end
      p SecretKeys.new({a: 1})[:a]

      # The `Class.new` route into the same shape.
      Kanshi = Class.new

      class Kanshi::Collector
        def self.run = "collected"
      end

      p Kanshi::Collector.run
      p Kanshi::Collector.name

      # And the `Struct.new` one, with a superclass of its own on the nested class.
      class FA < Struct.new(:a, :b)
      end

      class FA::Agg < Hash
        def initialize
          super
          self.default = 0
        end
      end

      p FA.new(1, 2).a
      p FA::Agg.new[:missing]
      p FA::Agg.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      "$AES$:"
      "<enc>"
      "$AES$:cba"
      "$AES$:cba"
      "SecretKeys::Encryptor"
      true
      private method 'hidden' called for an instance of SecretKeys::Encryptor
      1
      "collected"
      "Kanshi::Collector"
      1
      0
      Hash
    OUT
  end

  it "weakref is not a delegator" do
    result = zr(<<~'RUBY')
      # CRuby's `WeakRef < Delegator`. zeo's is a native class under `Object`, so
      # the superclass, the ancestry and `is_a?(Delegator)` all answer differently,
      # and a `rescue`/`case`/guard written against `Delegator` never matches.
      #
      # The gap is NARROWER than "no delegate library". zeo has `Delegator` and
      # `SimpleDelegator`, and `DelegateClass(Hash)` answers a class whose
      # superclass really is `Delegator` -- the shape
      # `a_class_nested_in_a_runtime_minted_namespace.rb` is built on. Two things
      # are missing, and only these two:
      #
      # 1. `require "weakref"` does not pull delegate.rb in. Requiring it FIRST does
      #    not help either, which is what makes this a reparenting job and not a
      #    require-graph one.
      # 2. zeo's native `WeakRef` is registered under `Object` and never reparented.
      #
      # The consequence with the sharpest edge is `is_a?(Object)`: CRuby's
      # `Delegator` descends from `BasicObject` and undefines most of Object, so a
      # `WeakRef` is NOT an Object there and IS one here -- inverted, not merely
      # absent. Any `obj.is_a?(Object)` guard sorts a WeakRef the wrong way.
      #
      # A fix reparents the native class onto the existing `Delegator` (and moves
      # the `method_missing`/`respond_to_missing?` rows there, since Delegator owns
      # them in CRuby). The delegation BEHAVIOUR is already right --
      # `a_weakref_subclass_runs_its_own_initialize.rb` pins the constructor split
      # and the forwarding.
      require "delegate"
      require "weakref"

      p WeakRef.superclass.to_s
      p WeakRef.ancestors.map(&:to_s).include?("Delegator")

      # A strong reference kept on purpose: zeo's weak handles are `Arc::downgrade`d,
      # so an unreferenced referent is collected the instant the literal goes out of
      # scope, where MRI's GC has simply not run yet. That is a separate, documented
      # divergence and would drown this one.
      referent = +"referent"
      w = WeakRef.new(referent)
      p w.is_a?(Delegator)
      p w.is_a?(Object)
      p w.upcase

      # What zeo DOES have, so a fix must not disturb it.
      p SimpleDelegator.superclass.to_s
      p DelegateClass(Hash).superclass.to_s
      p SimpleDelegator.new([1, 2]).size
    RUBY

    _(result).must_answer <<~'OUT'
      "Delegator"
      true
      true
      false
      "REFERENT"
      "Delegator"
      "Delegator"
      2
    OUT
  end
end
