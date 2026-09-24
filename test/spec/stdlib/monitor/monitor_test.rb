# frozen_string_literal: true

require "spec_helper"

describe "Monitor programs" do
  it "five more native types can be subclassed" do
    result = zr(<<~'RUBY')
      # A subclass of an instantiable native builtin is one husk wrapping the real
      # native value as a PAYLOAD, with the subclass's own ivars beside it. Five more
      # builtins join that list, each because a gem subclasses it for the payload.
      #
      # `Pathname` is the one worth naming: it is pure Ruby over a `@path` ivar in
      # CRuby, so it looks like it should need nothing at all -- but zr reimplements
      # it natively, so it needs the payload treatment like the rest.
      require "pathname"
      require "monitor"
      require "tmpdir"

      # Pathname: the payload is the path, and `Pathname.new("")` is a real empty
      # form, so a subclass without its own `initialize` seeds straight from the root.
      class Plain < Pathname
      end
      p [Plain.new("/tmp/x").to_s, Plain.new("/tmp/x").basename.to_s]
      p Plain.new("/a/b").is_a?(Pathname)

      class Tagged < Pathname
        attr_reader :tag
        def initialize(path, tag)
          super(path)
          @tag = tag
        end
        def describe = "#{tag}:#{self}"
      end
      t = Tagged.new("/var/log", :logs)
      p [t.describe, t.tag, t.class.to_s]
      p [(t + "app.log").to_s, t.absolute?, t.each_filename.to_a]

      # It is a Pathname wherever one is expected, including as an ARGUMENT -- which
      # is the half a payload husk gets wrong if the comparison only downcasts.
      p [File.basename(t), File.join(t, "app.log"), t.to_path]
      p Pathname.new("/var/log") == t
      p t == Pathname.new("/var/log")

      # Monitor: the payload is the lock. This is the shape a gem reaches for when it
      # wants a lock bolted onto state of its own.
      class Registry < Monitor
        def initialize
          super
          @items = []
        end
        def add(x) = synchronize { @items << x; @items.size }
        def items = synchronize { @items.dup }
      end
      r = Registry.new
      p [r.add(:a), r.add(:b), r.items]
      p [r.is_a?(Monitor), r.mon_owned?]

      # Mutex: the same, with an explicit `super()`.
      class Guard < Mutex
        attr_reader :name
        def initialize(name)
          super()
          @name = name
        end
      end
      g = Guard.new("db")
      p [g.name, g.locked?]
      g.lock
      p g.locked?
      g.unlock
      p [g.synchronize { :inside }, g.class.to_s]

      # SizedQueue: no maximum can be invented, so the real queue is seated through
      # `super(max)` -- and a subclass that skipped it would fail loudly rather than
      # hold a queue sized by the compiler.
      class Bounded < SizedQueue
        def initialize(max)
          super(max)
          @seen = 0
        end
        def <<(x)
          @seen += 1
          super
        end
        attr_reader :seen
      end
      b = Bounded.new(2)
      b << 1
      b << 2
      p [b.size, b.max, b.seen, b.pop, b.class.to_s]

      # Dir: a directory that exists is needed, so this is the same seated-through-
      # super shape.
      class Listing < Dir
        attr_reader :note
        def initialize(path, note)
          super(path)
          @note = note
        end
      end
      d = Listing.new(Dir.tmpdir, "tmp")
      p [d.note, d.class.to_s, d.path == Dir.tmpdir]
      d.close
    RUBY

    _(result).must_answer <<~'OUT'
      ["/tmp/x", "x"]
      true
      ["logs:/var/log", :logs, "Tagged"]
      ["/var/log/app.log", true, ["var", "log"]]
      ["log", "/var/log/app.log", "/var/log"]
      true
      true
      [1, 2, [:a, :b]]
      [true, false]
      ["db", false]
      true
      [:inside, "Guard"]
      [2, 2, 2, 1, "Bounded"]
      ["tmp", "Listing", true]
    OUT
  end

  it "is a reentrant lock" do
    result = zr(<<~'RUBY')
      # `Monitor` is reentrant where `Mutex` deadlocks: the owner may enter again,
      # and the lock releases only at the outermost exit.

      require "monitor"
      m = Monitor.new
      m.synchronize do
        m.synchronize { p m.mon_owned? }
        p m.mon_locked?
      end
      p m.mon_locked?
      p(m.synchronize { 21 * 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      42
    OUT
  end

  it "new_cond checks the owner, hands off between threads, times out, and keeps the nesting count" do
    result = zr(<<~'RUBY')
      # monitor -- new_cond and MonitorMixin::ConditionVariable: the check-owner
      # rules, a producer/consumer handoff, the timeout return, and the nesting
      # count surviving a wait.
      require "monitor"

      m = Monitor.new
      c = m.new_cond
      p c.class

      begin
        c.signal
      rescue ThreadError => e
        p e.class
      end
      begin
        c.wait
      rescue ThreadError => e
        p e.class
      end

      buf = []
      done = false
      t = Thread.new do
        3.times do |i|
          m.synchronize do
            buf << i
            c.signal
          end
          sleep 0.01
        end
        m.synchronize do
          done = true
          c.signal
        end
      end
      got = []
      m.synchronize do
        until done && buf.empty?
          c.wait_until { !buf.empty? || done }
          got.concat(buf)
          buf.clear
        end
      end
      t.join
      p got.sort

      m.synchronize do
        p c.wait(0.05)
      end

      # A wait from a NESTED enter releases the whole monitor and restores the
      # nesting on wakeup.
      m.synchronize do
        m.synchronize do
          p c.wait(0.05)
          p m.mon_owned?
        end
        p m.mon_owned?
      end
      p m.mon_locked?

      class SharedBox
        include MonitorMixin
        def initialize
          super
          @items = []
        end

        def put(x)
          synchronize do
            @items << x
            @full ||= new_cond
            @full.signal
          end
        end

        def take
          synchronize do
            @full ||= new_cond
            @full.wait_while { @items.empty? }
            @items.shift
          end
        end
      end

      box = SharedBox.new
      w = Thread.new { p box.take }
      sleep 0.05
      box.put(:handoff)
      w.join
    RUBY

    _(result).must_answer <<~'OUT'
      MonitorMixin::ConditionVariable
      ThreadError
      ThreadError
      [0, 1, 2]
      false
      false
      true
      true
      false
      :handoff
    OUT
  end

  it "MonitorMixin is the Ruby half over the native reentrant lock" do
    result = zr(<<~'RUBY')
      # MonitorMixin is the Ruby half of `monitor` over the native reentrant lock.

      require "monitor"
      class Counter
        include MonitorMixin
        def initialize
          mon_initialize
          @n = 0
        end
        def bump; synchronize { @n += 1 }; end
        def reentrant; synchronize { synchronize { mon_owned? } }; end
        attr_reader :n
      end
      c = Counter.new
      c.bump
      c.bump
      p c.n
      p c.reentrant
      p c.mon_owned?
    RUBY

    _(result).must_answer <<~'OUT'
      2
      true
      false
    OUT
  end

  it "a Monitor re-acquires for the thread that holds it, where a Mutex raises" do
    result = zr(<<~'RUBY')
      # Monitor is a REENTRANT mutex, and that is the whole reason it exists: a
      # synchronized method calling another synchronized method of the same object
      # is the ordinary way to write one. Spinel aliased Monitor to Mutex, so the
      # inner acquire raised "deadlock; recursive locking" where CRuby just goes
      # deeper. A Mutex must still raise there, so reentrancy is per-object.
      require "monitor"

      m = Monitor.new
      m.synchronize { m.synchronize { m.synchronize { puts "three deep" } } }
      puts "released"

      # the lock is genuinely released at the outermost exit
      m.synchronize { puts "re-acquired" }

      # ... and a Mutex still refuses
      mx = Mutex.new
      begin
        mx.synchronize { mx.synchronize { puts "unreachable" } }
      rescue ThreadError => e
        puts e.message
      end

      # a monitor still excludes another thread
      counter = 0
      lock = Monitor.new
      ts = 4.times.map do
        Thread.new do
          100.times { lock.synchronize { counter += 1 } }
        end
      end
      ts.each(&:join)
      puts counter
    RUBY

    _(result).must_answer <<~'OUT'
      three deep
      released
      re-acquired
      deadlock; recursive locking
      400
    OUT
  end

  it "mutex synchronize block" do
    result = zr(<<~'RUBY')
      m = Mutex.new
      m.synchronize { puts "locked" }
      puts "done"

      x = m.synchronize { 21 * 2 }
      puts x
      puts(m.synchronize { "result" })

      require "monitor"
      mon = Monitor.new
      mon.synchronize { puts "monitor" }

      class Counter
        def initialize
          @lock = Mutex.new
          @count = 0
        end
        def bump
          @lock.synchronize { @count = @count + 1 }
        end
        def count
          @count
        end
      end
      c = Counter.new
      c.bump
      c.bump
      c.bump
      puts c.count
    RUBY

    _(result).must_answer <<~'OUT'
      locked
      done
      42
      result
      monitor
      3
    OUT
  end
end
