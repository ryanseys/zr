# frozen_string_literal: true

require "spec_helper"

describe "Thread: frozen literals" do
  it "concurrency freeze" do
    result = ze0(<<~'RUBY')
      # A Mutex, ConditionVariable, Fiber or Thread is an ordinary heap instance
      # and freezes like one; a Queue is the exception Ruby itself makes (freezing
      # one raises, since a frozen queue could never be pushed to again).
      #
      # zeo's divergence: `freeze` on a Mutex/ConditionVariable is accepted but
      # does not stick -- `frozen?` answers false immediately after. The handle
      # types live outside the `__frozen` AtomicBool convention generated instances
      # carry, so freeze has nowhere to record itself. (Spinel once had the same
      # observable for its own reasons, #3483.)
      a = Mutex.new
      p a.frozen?
      p a.freeze.equal?(a)
      p a.frozen?

      b = ConditionVariable.new
      b.freeze
      p b.frozen?

      c = Fiber.new { 1 }
      c.freeze
      p c.frozen?

      t = Thread.new { 1 }
      t.join
      t.freeze
      p t.frozen?

      o = Object.new
      o.freeze
      p o.frozen?

      q = Queue.new
      p q.frozen?
      begin
        q.freeze
        p "no raise"
      rescue TypeError => e
        p [e.class, e.message.start_with?("cannot freeze #<Thread::Queue:")]
      end

      s = SizedQueue.new(1)
      begin
        s.freeze
        p "no raise"
      rescue TypeError => e
        p [e.class, e.message.start_with?("cannot freeze #<Thread::SizedQueue:")]
      end

      # a frozen handle still works as itself
      m = Mutex.new
      m.freeze
      m.lock
      p m.locked?
      m.unlock
      p m.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      true
      true
      true
      true
      false
      [TypeError, true]
      [TypeError, true]
      true
      true
    OUT
  end

  it "deeply frozen object crosses a ractor boundary by reference" do
    result = ze0(<<~'RUBY', path: "core/thread/a_deeply_frozen_object_crosses_a_ractor_boundary_by_reference.rb")
      class Box
        def initialize(v)
          @v = v
        end
        def v
          @v
        end
      end
      b = Box.new(41)
      Ractor.make_shareable(b)
      puts b.frozen?
      sink = Ractor.new do
        got = Ractor.receive
        got.send(:v)
      end
      sink.send(b)
      puts sink.value + 1
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/thread/a_deeply_frozen_object_crosses_a_ractor_boundary_by_reference.rb:12: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      true
      42
    OUT
  end

  it "fiber thread object face" do
    result = ze0(<<~'RUBY')
      # The concurrency handles are heap instances, so Object's identity face works
      # on them: equal? / eql? / == / != are pointer comparison and frozen? is
      # false.
      #
      # zeo's divergences: (1) `x.equal?(x)` answers FALSE for Mutex, Queue and
      # SizedQueue -- each read of the variable hands out a fresh box and equal?
      # compares the box rather than the handle behind it (ConditionVariable,
      # Fiber and Thread compare the handle and answer true); (2) Fiber#raise on a
      # fiber that has never been resumed delivers the requested RuntimeError
      # instead of ruby's FiberError (nowhere to deliver it yet). (Imported from
      # spinel, where the front end once refused these receivers outright, #3470.)
      a = Mutex.new
      b = Queue.new
      c = SizedQueue.new(2)
      d = ConditionVariable.new
      e = Fiber.new { 1 }
      p a.equal?(a), a.eql?(a), a == a
      p b.equal?(b), b.eql?(b)
      p c.equal?(c)
      p d.equal?(d)
      p e.equal?(e), e.eql?(e), e == e
      p e != Fiber.new { 2 }
      p a.frozen?, e.frozen?
      p a.equal?(b)

      # Fiber#raise on a fiber that has never run has nowhere to deliver, so it is a
      # FiberError -- not the requested exception raised in the caller. #3468.
      f = Fiber.new { Fiber.yield 1 }
      p (f.raise(RuntimeError, "boom") rescue $!.class)
      g = Fiber.new { Fiber.yield 1; :after }
      g.resume
      p (g.raise(RuntimeError, "boom") rescue $!.class)
      p Fiber.new { Fiber.yield 1 }.kill.class

      # Fiber#resume passes every argument to the block's parameters. The fiber
      # carries one value, so two or more are packed and the body unpacks them. #3469.
      h = Fiber.new { |x, y| x + y }
      p h.resume(3, 4)
      i = Fiber.new { |*r| r }
      p i.resume(1, 2)
      j = Fiber.new { |x, y| Fiber.yield(x); y }
      p j.resume(5, 6)
      p j.resume
      p Fiber.new { |x| x * 2 }.resume(21)
      p Fiber.new { 99 }.resume
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      false
      false
      false
      FiberError
      RuntimeError
      Fiber
      7
      [1, 2]
      5
      6
      42
      99
    OUT
  end

  it "freeze matrix covers the handle kinds and queue refuses" do
    result = ze0(<<~'RUBY')
      # The frozen flag on the non-collection heap kinds: Proc, Regexp
      # (literals frozen at birth, `Regexp.new` not), MatchData, Fiber,
      # Enumerator, Thread, Mutex (lockable while frozen) -- with the
      # dup-drops/clone-copies flag rule and the flag never aliasing an
      # earlier copy. Queue/SizedQueue refuse to freeze with CRuby's
      # TypeError. Expected output is verbatim ruby 4.0.6.

      pr = proc { 1 }
      puts pr.frozen?
      d = pr.dup
      pr.freeze
      puts pr.frozen?
      puts d.frozen?
      puts pr.dup.frozen?
      puts pr.clone.frozen?
      x = "b"
      puts /abc/.frozen?
      puts /a#{x}/.frozen?
      rn = Regexp.new("abc")
      puts rn.frozen?
      rn.freeze
      puts rn.frozen?
      puts rn.dup.frozen?
      puts rn.clone.frozen?
      md = "abc".match(/b/)
      puts md.frozen?
      md.freeze
      puts md.frozen?
      puts md.dup.frozen?
      puts md.clone.frozen?
      f = Fiber.new { }
      puts f.frozen?
      f.freeze
      puts f.frozen?
      en = [1].each_slice(1)
      puts en.frozen?
      en.freeze
      puts en.frozen?
      puts en.dup.frozen?
      puts en.clone.frozen?
      t = Thread.new { }
      t.join
      puts t.frozen?
      t.freeze
      puts t.frozen?
      m = Thread::Mutex.new
      m.freeze
      puts m.frozen?
      m.lock
      puts m.locked?
      m.unlock
      q = Thread::Queue.new
      begin
        q.freeze
      rescue TypeError => e
        puts "#{e.class}: #{e.message[0, 22]}"
      end
      puts q.frozen?
      sq = Thread::SizedQueue.new(1)
      begin
        sq.freeze
      rescue TypeError => e
        puts e.message.start_with?("cannot freeze #<Thread::SizedQueue:0x")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      false
      true
      true
      true
      false
      true
      false
      true
      false
      true
      false
      true
      false
      true
      false
      true
      false
      true
      false
      true
      true
      true
      TypeError: cannot freeze #<Thread
      false
      true
    OUT
  end

  it "ractor move" do
    result = ze0(<<~'RUBY')
      # Real Ractor move semantics: `send(obj, move: true)` hands the graph to the
      # receiver and poisons the source -- every later send to a moved object
      # raises Ractor::MovedError. (Sibling-duplicate husking and failed-move
      # partial poisoning are CRuby traversal accidents zeo does not copy; this
      # fixture stays on the well-defined surface.)
      $stderr.reopen(IO::NULL) # the experimental warning's file:line is the one nondeterminism

      # ---- A moved string: the value arrives, the source refuses everything.
      r = Ractor.new { Ractor.receive << "-recv" }
      s = +"hello"
      r.send(s, move: true)
      p r.value
      [:length, :==, :inspect, :class, :frozen?, :equal?, :!, :__id__].each do |m|
        begin
          s.__send__(m)
        rescue Ractor::MovedError => e
          p [m, e.class, e.message]
        end
      end
      begin
        s.instance_eval { 1 }
      rescue Ractor::MovedError => e
        p [:instance_eval, e.class, e.message]
      end

      # ---- Moving a container moves the elements too (single-occurrence graph).
      r2 = Ractor.new { Ractor.receive }
      inner = +"inner"
      arr = [inner]
      r2.send(arr, move: true)
      p r2.value
      p [(inner.length rescue $!.class), (arr.length rescue $!.class)]

      # ---- Shareable nodes pass by reference, un-poisoned.
      sh = "frozen-shareable".freeze
      r3 = Ractor.new { Ractor.receive }
      r3.send([sh], move: true)
      p [r3.value[0].equal?(sh), sh.length]
      r4 = Ractor.new { Ractor.receive }
      r4.send(sh, move: true)
      p [r4.value.equal?(sh), sh.length]

      # ---- Immediates are shareable: nothing to poison.
      r5 = Ractor.new { Ractor.receive }
      r5.send(42, move: true)
      p r5.value

      # ---- Unmovable graphs refuse.
      r6 = Ractor.new { Ractor.receive }
      begin
        r6.send(Thread.current, move: true)
      rescue Ractor::Error => e
        p [e.class, e.message]
      end
      begin
        r6.send(proc {}, move: true)
      rescue Ractor::Error => e
        p [e.class, e.message]
      end
      # ...and the COPY path refuses a proc with CRuby's allocator message.
      begin
        r6.send(proc {})
      rescue TypeError => e
        p [e.class, e.message]
      end
      r6.send(:done)
      r6.join

      # ---- Cycles reconstruct on both paths.
      r7 = Ractor.new { Ractor.receive }
      c = []
      c << c
      r7.send(c)
      p r7.value[0].equal?(r7.value)
      r8 = Ractor.new { Ractor.receive }
      c2 = []
      c2 << c2
      r8.send(c2, move: true)
      g8 = r8.value
      p g8[0].equal?(g8)

      # ---- Plain unfrozen objects: copy leaves the source alone, move poisons it.
      class Point
        def initialize
          @x = +"iv"
        end
        attr_reader :x
      end
      r9 = Ractor.new { Ractor.receive }
      pt = Point.new
      r9.send(pt)
      p [r9.value.class, r9.value.x, pt.x]
      r10 = Ractor.new { Ractor.receive }
      r10.send(pt, move: true)
      g10 = r10.value
      p [g10.class, g10.x]
      p (pt.x rescue $!.class)

      # ---- Hash move: pairs and the default travel.
      r11 = Ractor.new { Ractor.receive }
      h = { "k" => "v" }
      h.default = "d"
      r11.send(h, move: true)
      p [r11.value, r11.value.default, (h.size rescue $!.class)]

      # ---- Port#send takes move: too.
      r12 = Ractor.new do
        q = Ractor::Port.new
        Ractor.main.send(q)
        q.receive
      end
      port = Ractor.receive
      ms = +"via-port"
      port.send(ms, move: true)
      p r12.value
      p (ms.length rescue $!.class)

      # ---- move: false is the plain copy.
      r13 = Ractor.new { Ractor.receive }
      s13 = +"still-mine"
      r13.send(s13, move: false)
      p [r13.value, s13]

      # ---- The taxonomy the poison lives in.
      p Ractor::MovedError.ancestors[0..3]
      p Ractor::MovedObject.superclass
      p Ractor::MovedObject.instance_methods(false).sort
      p Ractor.shareable?(s) # a husk reports shareable
    RUBY

    _(result).must_answer <<~'OUT'
      "hello-recv"
      [:length, Ractor::MovedError, "can not send any methods to a moved object"]
      [:==, Ractor::MovedError, "can not send any methods to a moved object"]
      [:inspect, Ractor::MovedError, "can not send any methods to a moved object"]
      [:class, Ractor::MovedError, "can not send any methods to a moved object"]
      [:frozen?, Ractor::MovedError, "can not send any methods to a moved object"]
      [:equal?, Ractor::MovedError, "can not send any methods to a moved object"]
      [:!, Ractor::MovedError, "can not send any methods to a moved object"]
      [:__id__, Ractor::MovedError, "can not send any methods to a moved object"]
      [:instance_eval, Ractor::MovedError, "can not send any methods to a moved object"]
      ["inner"]
      [Ractor::MovedError, Ractor::MovedError]
      [true, 16]
      [true, 16]
      42
      [Ractor::Error, "can not move Thread object."]
      [Ractor::Error, "can not move Proc object."]
      [TypeError, "allocator undefined for Proc"]
      true
      true
      [Point, "iv", "iv"]
      [Point, "iv"]
      Ractor::MovedError
      [{"k" => "v"}, "d", Ractor::MovedError]
      "via-port"
      Ractor::MovedError
      ["still-mine", "still-mine"]
      [Ractor::MovedError, Ractor::Error, RuntimeError, StandardError]
      BasicObject
      [:!, :!=, :==, :__id__, :__send__, :equal?, :instance_eval, :instance_exec, :method_missing]
      true
    OUT
  end

  it "ractor ports" do
    result = ze0(<<~'RUBY')
      # The ruby 4 Ractor port model: Ractor::Port primitives, default-port
      # routing, select, monitor/join/value, locals, and the registry queries.
      $stderr.reopen(IO::NULL) # the experimental warning's file:line is the one nondeterminism

      # ---- Port primitives, inside a ractor (only the creator receives).
      r = Ractor.new do
        q = Ractor::Port.new
        p q.closed?
        p (q << 1).equal?(q)
        q.send(2)
        p [q.receive, q.receive]
        q.close
        p q.closed?
        begin
          q.receive
        rescue Ractor::ClosedError => err
          p [err.class, err.message]
        end
        :done
      end
      p r.value

      # ---- default_port routing: Ractor#send == default_port.send.
      r2 = Ractor.new do
        a = Ractor.receive
        b = Ractor.receive
        [a, b, Ractor.current.default_port.class]
      end
      p r2.send(:x).equal?(r2)
      r2 << :y
      p r2.value

      # ---- select over ports and ractors.
      r3 = Ractor.new { :from_r3 }
      got = Ractor.select(r3)
      p [got[0].equal?(r3), got[1]]

      # ---- monitor/unmonitor tokens.
      port = Ractor::Port.new
      r4 = Ractor.new { :ok }
      r4.join
      p r4.monitor(port)   # already terminated -> false, token sent
      p port.receive
      r5 = Ractor.new { Ractor.receive }
      p r5.monitor(port)
      p r5.unmonitor(port).equal?(r5)
      r5.send(:go)
      r5.join

      # ---- value/join, the successor rule, RemoteError.
      r6 = Ractor.new { 6 * 7 }
      p r6.value
      p r6.value  # same ractor may re-take
      r7 = Ractor.new { raise "boom" }
      begin
        r7.value
      rescue Ractor::RemoteError => e
        p [e.class, e.message, e.ractor.equal?(r7), e.cause.class, e.cause.message]
      end

      # ---- locals.
      Ractor[:k] = 1
      p Ractor[:k]
      p Ractor.current[:k]
      Ractor.current[:k] = 2
      p Ractor[:k]
      begin
        r6[:k]
      rescue RuntimeError => e
        puts e.message
      end
      p Ractor.store_if_absent(:memo) { 10 }
      p Ractor.store_if_absent(:memo) { 20 }

      # ---- registry queries and identity.
      p Ractor.main?
      p Ractor.current.equal?(Ractor.main)
      p Ractor.count >= 1
      p Ractor.main.inspect.sub(/#\d+/, "#N")
      r8 = Ractor.new { :x }
      r8.join
      p r8.inspect.sub(/#\d+/, "#N").sub(/ \S+\.rb:\d+/, " LOC")

      # ---- shareable_proc enforces self-shareability.
      pr = Ractor.shareable_proc { 5 }
      p [pr.call, pr.frozen?]
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      [1, 2]
      true
      [Ractor::ClosedError, "The port was already closed"]
      :done
      true
      [:x, :y, Ractor::Port]
      [true, :from_r3]
      false
      :exited
      true
      true
      42
      42
      [Ractor::RemoteError, "thrown by remote Ractor.", true, RuntimeError, "boom"]
      1
      1
      2
      Cannot get ractor local storage for non-current ractor
      10
      10
      true
      true
      true
      "#<Ractor:#N running>"
      "#<Ractor:#N LOC terminated>"
      [5, true]
    OUT
  end

  it "ractor shareable tiering and make shareable" do
    result = ze0(<<~'RUBY')
      puts Ractor.shareable?(1)
      puts Ractor.shareable?(:sym)
      puts Ractor.shareable?("mutable")
      frozen_str = "frozen".freeze
      puts Ractor.shareable?(frozen_str)
      arr = [1, 2]
      puts Ractor.shareable?(arr)
      Ractor.make_shareable(arr)
      puts Ractor.shareable?(arr)
      puts arr.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      true
      true
    OUT
  end

  it "ractors" do
    result = ze0(<<~'RUBY', path: "core/thread/ractors.rb")
      # Ractor -- parallel execution with a frozen-or-copy message boundary

      # args cross the boundary and bind to block params
      r = Ractor.new(20, 22) do |a, b|
        a + b
      end
      puts r.value

      # message passing
      worker = Ractor.new do
        msg = Ractor.receive
        msg * 10
      end
      worker.send(7)
      puts worker.value

      # shareability: immediates always, mutable values only once deeply frozen
      puts Ractor.shareable?(1)
      puts Ractor.shareable?("mutable")
      arr = [1, 2]
      puts Ractor.shareable?(arr)
      Ractor.make_shareable(arr)
      puts Ractor.shareable?(arr)
      puts arr.frozen?

      # an unshareable message is deep-copied: later mutation doesn't reach it
      echo = Ractor.new do
        Ractor.receive
      end
      payload = [100, 200]
      echo.send(payload)
      payload[0] = 999
      puts echo.value
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/thread/ractors.rb:4: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      42
      70
      true
      false
      false
      true
      true
      100
      200
    OUT
  end

  it "unfrozen object sent across a ractor boundary deep copies" do
    _(ze0(<<~'RUBY', path: "core/thread/an_unfrozen_object_sent_across_a_ractor_boundary_deep_copies.rb")).must_answer "[\"payload-seen\", \"payload\"]\n", stderr: "core/thread/an_unfrozen_object_sent_across_a_ractor_boundary_deep_copies.rb:12: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      # CRuby's rule, now real here too: an unfrozen plain object crosses as
      # a deep copy (dup + ivar rewrite -- `ractor::cross_graph`), so the
      # receiver sees the value and later mutation of the source's graph
      # never reaches it.

      class Box
        def initialize(v)
          @v = v
        end
        attr_accessor :v
      end
      sink = Ractor.new do
        got = Ractor.receive
        got.v << "-seen"
        got.v
      end
      b = Box.new(+"payload")
      sink.send(b)
      out = sink.value
      p [out, b.v]
    RUBY
  end
end
