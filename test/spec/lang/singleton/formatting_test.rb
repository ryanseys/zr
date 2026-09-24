# frozen_string_literal: true

require "spec_helper"

describe "Singleton: formatting and inspection" do
  it "class singleton def" do
    result = zr(<<~'RUBY')
      # Issue #719. `class << self; def X; ...; end; end` inside a class
      # body defines a singleton method on the enclosing class, equivalent
      # to `def self.X`. spinel used to leave the SingletonClassNode
      # unhandled in classes; only the module-side attr_accessor path
      # fired.

      class C
        class << self
          def cls_method; "singleton"; end
          def with_arg(n); "got " + n.to_s; end
        end
      end

      puts C.cls_method
      puts C.with_arg(42)

      # Mixed form: regular `def self.X` plus a `class << self` block
      # coexist in the same class.
      class D
        def self.alpha; "a"; end
        class << self
          def beta; "b"; end
        end
      end

      puts D.alpha
      puts D.beta
    RUBY

    _(result).must_answer <<~'OUT'
      singleton
      got 42
      a
      b
    OUT
  end

  it "explicit receiver honours a singleton visibility" do
    result = zr(<<~'RUBY')
      # The explicit-receiver barrier does not read a per-object singleton's
      # visibility, so `obj.hidden` runs a method CRuby refuses.
      #
      # The barrier asks `instance_method_visibility(recv.class_id(), name)`. For an
      # object with its own rows that names the ORDINARY class, which knows nothing
      # about them -- they are keyed by identity, not by a class id. `public_send`
      # reaches the same question through `send_value_public_in`.
      #
      # Both spellings of the mark are covered: a module whose `module_function`
      # made the name private on the instance side, and a `private` sent to the
      # object's own singleton class.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.class.to_s]
      end

      module MFa
        module_function
        def helper = :helper
      end
      o = Object.new.extend(MFa)
      try(:dot)      { o.helper }
      try(:send)     { o.send(:helper) }
      try(:public)   { o.public_send(:helper) }
      try(:method)   { o.method(:helper).call }
      try(:inner)    { o.instance_eval { helper } }

      module Prot
        def pm = :pm
        protected :pm
      end
      q = Object.new.extend(Prot)
      try(:prot_dot) { q.pm }
      try(:prot_pub) { q.public_send(:pm) }

      r = Object.new
      def r.later = :later
      r.singleton_class.send(:private, :later)
      try(:late_dot) { r.later }
      try(:late_send){ r.send(:later) }
      r.singleton_class.send(:public, :later)
      try(:back_dot) { r.later }
    RUBY

    _(result).must_answer <<~'OUT'
      [:dot, :raised, "NoMethodError"]
      [:send, :helper]
      [:public, :raised, "NoMethodError"]
      [:method, :helper]
      [:inner, :helper]
      [:prot_dot, :raised, "NoMethodError"]
      [:prot_pub, :raised, "NoMethodError"]
      [:late_dot, :raised, "NoMethodError"]
      [:late_send, :later]
      [:back_dot, :later]
    OUT
  end

  it "extended module is not the singletons own" do
    result = zr(<<~'RUBY')
      # `obj.extend(M)` puts M in the singleton class's SUPER chain, so
      # `obj.singleton_class.instance_methods(false)` must NOT list names
      # that belong to the module. An own `def obj.x` defined beside the
      # extend must still show up in the narrow form.
      #
      # `singleton_methods` is deliberately NOT part of this: CRuby's wide form does
      # report an extended module's methods, and only the narrow `false` form skips
      # them.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.class.to_s]
      end

      module Plain
        def pn = :pn
      end
      r = Object.new.extend(Plain)
      try(:own_im)     { r.singleton_class.instance_methods(false) }
      try(:anc)        { r.singleton_class.ancestors[1].to_s }
      try(:wide_sing)  { r.singleton_methods }
      try(:call)       { r.pn }

      # An own `def obj.x` beside the extend stays own.
      def r.mine = :mine
      try(:own_after)  { r.singleton_class.instance_methods(false) }

      module Plain2
        def qn = :qn
      end
      s = Object.new
      s.extend(Plain, Plain2)
      try(:two_own)    { s.singleton_class.instance_methods(false) }
      try(:two_anc)    { s.singleton_class.ancestors[1, 2].map(&:to_s) }
    RUBY

    _(result).must_answer <<~'OUT'
      [:own_im, []]
      [:anc, "Plain"]
      [:wide_sing, [:pn]]
      [:call, :pn]
      [:own_after, [:mine]]
      [:two_own, []]
      [:two_anc, ["Plain", "Plain2"]]
    OUT
  end

  it "object methods report their own singletons" do
    result = zr(<<~'RUBY')
      # `Object#methods` and `#public_methods` must report a method installed
      # on the OBJECT itself, not just what the receiver's CLASS chain
      # carries -- and a private one must not wrongly show up in
      # `public_methods`.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.class.to_s]
      end

      o = Object.new
      class << o
        def pub = :pub
        private
        def hid = :hid
        protected
        def prot = :prot
      end
      try(:methods_pub)   { o.methods.include?(:pub) }
      try(:methods_prot)  { o.methods.include?(:prot) }
      try(:methods_hid)   { o.methods.include?(:hid) }
      try(:public_pub)    { o.public_methods.include?(:pub) }
      try(:public_hid)    { o.public_methods.include?(:hid) }
      try(:public_prot)   { o.public_methods.include?(:prot) }
      try(:public_false)  { o.public_methods(false).sort }
      try(:private_false) { o.private_methods(false).include?(:hid) }
      try(:prot_false)    { o.protected_methods(false) }

      module MFa
        module_function
        def helper = :helper
      end
      e = Object.new.extend(MFa)
      try(:ext_methods)   { e.methods.include?(:helper) }
      try(:ext_private)   { e.private_methods(false).include?(:helper) }
    RUBY

    _(result).must_answer <<~'OUT'
      [:methods_pub, true]
      [:methods_prot, true]
      [:methods_hid, false]
      [:public_pub, true]
      [:public_hid, false]
      [:public_prot, false]
      [:public_false, [:pub]]
      [:private_false, true]
      [:prot_false, [:prot]]
      [:ext_methods, false]
      [:ext_private, true]
    OUT
  end

  it "self named but not sent to in a singleton body" do
    result = zr(<<~'RUBY')
      # A statement inside `class << self` that consults `self` only by NAMING it --
      # never by sending to an implicit receiver -- needs no compile-time singleton
      # class at all. The `self` just has to evaluate to the right object, and
      # `self.singleton_class` in the enclosing class body IS that object.
      #
      # zr refused the whole shape, because the mapping works by rewriting a
      # statement's RECEIVER and this one has no receiver to rewrite.
      # `Mongoid.deprecate(self, :from_hash)` is 99 corpus rows of exactly it.
      class Sink
        def self.take(x) = x
        def self.pair(a, b) = [a, b]
      end

      class Foo
        class << self
          Sink.take(self)
        end
      end
      p Sink.take(Foo.singleton_class).equal?(Foo.singleton_class)

      # `self` here is the SINGLETON class, not the class -- which is the whole
      # reason passing the statement through unchanged was refused: it would have
      # handed over the enclosing class and answered silently wrong.
      $seen = []
      class Bar
        class << self
          $seen << Sink.take(self)
          def m = :m
        end
      end
      p $seen.first.equal?(Bar.singleton_class)
      p $seen.first.equal?(Bar)
      p $seen.first.to_s

      # `self` inside a nested `def` in the same body is that method's future
      # RECEIVER, not the singleton class, so it must NOT be rewritten.
      class Baz
        class << self
          def who = self
          def who_singleton = self.singleton_class
        end
      end
      p Baz.who.equal?(Baz)
      p Baz.who_singleton.equal?(Baz.singleton_class)

      # More than one `self` in one statement, and `self` in a nested argument.
      class Multi
        class << self
          Sink.pair(self, Sink.take(self))
        end
      end
      p Multi.singleton_class.to_s

      # `self` reached through a node that is NOT a call at all -- an assignment's
      # right-hand side. These never matched the plain `self`-receiver rule, which
      # only ever looked at a `Call`'s receiver.
      $captured = nil
      class Assigned
        class << self
          $captured = self
        end
      end
      p $captured.equal?(Assigned.singleton_class)
      p $captured.equal?(Assigned)

      # A statement whose `self` sits inside a BLOCK still works: the block runs with
      # the class as `self`, so `self.singleton_class` is the same object there.
      class Blocky
        class << self
          [1].each { Sink.take(self) }
        end
      end
      p Blocky.singleton_class.to_s

      # And a plain no-self statement beside them is untouched.
      class Plain
        class << self
          Sink.take(:no_self_here)
          def q = :q
        end
      end
      p Plain.q
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      "#<Class:Bar>"
      true
      true
      "#<Class:Multi>"
      true
      false
      "#<Class:Blocky>"
      :q
    OUT
  end

  it "a receiverless call in a class << X body reaches a private singleton method" do
    result = zr(<<~'RUBY')
      # Every shape where a `class << X` body's receiverless call reaches a method
      # that is private on the singleton class. Ruby runs those with no receiver, so
      # no visibility barrier applies -- zr rebinds them onto a synthesized
      # `X.singleton_class` and must keep the barrier down.

      module Priv
        def inst; "inst"; end
        def other; "other"; end
      end

      def try(tag)
        puts "#{tag}: #{yield.inspect}"
      rescue StandardError => e
        puts "#{tag}: #{e.class}: #{e.message}"
      end

      # a: `class << obj`, a private Module verb, splatted args.
      A = Module.new { def a; 1; end }
      class << A
        public(*[])
      end
      try("a") { A.singleton_class.private_method_defined?(:public) }

      # b: `class << self` in a class body -- the same verb.
      class B
        def self.b; 1; end
        private_class_method :b
        class << self
          public(*[:b])
        end
      end
      try("b") { B.b }

      # c: `class << obj`, a private Module verb reached receiverlessly.
      #    `define_method` is private on Module, so this is the same barrier as the
      #    fileutils shape with a body that proves the call ran.
      C = Module.new
      class << C
        define_method(:c1) { "c1" }
      end
      try("c") { C.c1 }

      # d: an explicit literal `self` receiver -- allowed since ruby 2.7.
      D = Module.new
      class << D
        self.define_method(:d1) { "d1" }
      end
      try("d") { D.d1 }

      # e: a receiver the SOURCE wrote must STILL raise. `public` stayed private on
      #    Module; `define_method` did not, which is why it is the one used above.
      E = Module.new
      try("e") { E.singleton_class.public(*[]) }

      # f: `module_function`-shaped -- private instance methods made public class
      #    methods from the singleton body, which is what fileutils does.
      module F
        include Priv
        private(*[:inst, :other])
        extend self
        class << self
          public(*[:inst, :other])
        end
      end
      try("f") { [F.inst, F.singleton_class.public_method_defined?(:inst)] }

      # g: the same through an eval, where the class body is re-sliced from source.
      eval(%q{
        module G
          include Priv
          private(*[:inst])
          extend self
          class << self
            public(*[:inst])
          end
        end
      })
      try("g") { [G.inst, G.singleton_class.public_method_defined?(:inst)] }

      # h: a private verb reached from inside a BLOCK in the singleton body.
      module H
        def self.h1; 1; end
        private_class_method :h1
        class << self
          [:h1].each { |n| public(*[n]) }
        end
      end
      try("h") { H.singleton_class.public_method_defined?(:h1) }
    RUBY

    _(result).must_answer <<~'OUT'
      a: true
      b: 1
      c: "c1"
      d: "d1"
      e: NoMethodError: private method 'public' called for class #<Class:E>
      f: ["inst", true]
      g: ["inst", true]
      h: true
    OUT
  end

  it "a visibility directive in a compiled class << obj body leaves every method public" do
    result = zr(<<~'RUBY')
      # `private` (bare, `private def`, and `private :name`) inside a
      # compiled `class << obj` body must mark the method PRIVATE on the
      # object, the same as it would on a class. A fresh `def` after that
      # resets to the running default. `clone` carries the singleton table,
      # and the visibility marks with it; `dup` does not carry the
      # singleton table at all. A non-object heap value (for example, a
      # String) keeps its own singleton table, and the marks must follow it
      # there too.
      #
      # The three spellings are one cause and are pinned together here.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.class.to_s]
      end

      o = Object.new
      class << o
        def pub = :pub
        private
        def cursor = :cursor
        protected
        def prot = :prot
      end
      try(:cursor_public) { o.public_send(:cursor) }
      try(:cursor_send)   { o.send(:cursor) }
      try(:prot_public)   { o.public_send(:prot) }
      try(:pub_public)    { o.public_send(:pub) }
      try(:singletons)    { o.singleton_methods.sort }
      try(:privates)      { o.private_methods(false).include?(:cursor) }
      try(:protecteds)    { o.protected_methods(false) }

      o2 = Object.new
      class << o2
        private def inline = :inline
        def open = :open
      end
      try(:inline_public) { o2.public_send(:inline) }
      try(:inline_list)   { o2.singleton_methods.sort }

      o3 = Object.new
      class << o3
        def named = :named
        private :named
      end
      try(:named_public)  { o3.public_send(:named) }
      try(:named_list)    { o3.singleton_methods }

      # A fresh `def` resets the name to the running default, on an object exactly
      # as on a class.
      o4 = Object.new
      class << o4
        private
        def reset = :first
      end
      def o4.reset = :second
      try(:reset_public)  { o4.public_send(:reset) }
      try(:reset_list)    { o4.singleton_methods }

      # `clone` carries the singleton table, so it carries the marks with it.
      o5 = Object.new
      class << o5
        private
        def carried = :carried
      end
      try(:clone_public)  { o5.clone.public_send(:carried) }
      try(:clone_list)    { o5.clone.singleton_methods }
      try(:dup_list)      { o5.dup.singleton_methods }

      # A non-object heap value keeps its rows in a table of its own, and the mark
      # has to follow them there.
      s = +"str"
      class << s
        private
        def shout = :shout
      end
      try(:value_public)  { s.public_send(:shout) }
      try(:value_list)    { s.singleton_methods }
    RUBY

    _(result).must_answer <<~'OUT'
      [:cursor_public, :raised, "NoMethodError"]
      [:cursor_send, :cursor]
      [:prot_public, :raised, "NoMethodError"]
      [:pub_public, :pub]
      [:singletons, [:prot, :pub]]
      [:privates, true]
      [:protecteds, [:prot]]
      [:inline_public, :raised, "NoMethodError"]
      [:inline_list, [:open]]
      [:named_public, :raised, "NoMethodError"]
      [:named_list, []]
      [:reset_public, :second]
      [:reset_list, [:reset]]
      [:clone_public, :raised, "NoMethodError"]
      [:clone_list, []]
      [:dup_list, []]
      [:value_public, :raised, "NoMethodError"]
      [:value_list, []]
    OUT
  end

  it "a singleton class reports every per-object row as public, whatever mark the object carries" do
    result = zr(<<~'RUBY')
      # A singleton class's instance-method reflection reports every per-object row
      # as PUBLIC, whatever mark the object carries.
      #
      # `sc.instance_methods(false)`, `sc.private_instance_methods(false)`,
      # `sc.method_defined?` and `sc.private_method_defined?` all resolve through
      # the singleton class ID. The rows themselves live in the identity-keyed
      # per-object tables, and so does the mark, so a class-id walk sees the names
      # but not their visibility.
      #
      # The dispatch half is `an_explicit_receiver_honours_a_singleton_visibility`;
      # this is the reflection half of the same missing dimension.

      def try(label)
        p [label, yield]
      rescue NoMethodError, NameError => e
        p [label, :raised, e.class.to_s]
      end

      o = Object.new
      class << o
        def pub = :pub
        private
        def hid = :hid
        protected
        def prot = :prot
      end
      sc = o.singleton_class
      try(:im)        { sc.instance_methods(false).sort }
      try(:pim)       { sc.private_instance_methods(false) }
      try(:pubim)     { sc.public_instance_methods(false).sort }
      try(:protim)    { sc.protected_instance_methods(false) }
      try(:md_pub)    { sc.method_defined?(:pub) }
      try(:md_hid)    { sc.method_defined?(:hid) }
      try(:pmd_hid)   { sc.private_method_defined?(:hid) }
      try(:pmd_pub)   { sc.private_method_defined?(:pub) }
      try(:prmd_prot) { sc.protected_method_defined?(:prot) }
      try(:im_named)  { sc.instance_method(:hid).name }

      r = Object.new
      def r.later = :later
      rsc = r.singleton_class
      rsc.send(:private, :later)
      try(:r_im)      { rsc.instance_methods(false) }
      try(:r_pim)     { rsc.private_instance_methods(false) }
      try(:r_pmd)     { rsc.private_method_defined?(:later) }
    RUBY

    _(result).must_answer <<~'OUT'
      [:im, [:prot, :pub]]
      [:pim, [:hid]]
      [:pubim, [:pub]]
      [:protim, [:prot]]
      [:md_pub, true]
      [:md_hid, false]
      [:pmd_hid, true]
      [:pmd_pub, false]
      [:prmd_prot, true]
      [:im_named, :hid]
      [:r_im, []]
      [:r_pim, [:later]]
      [:r_pmd, true]
    OUT
  end
end
