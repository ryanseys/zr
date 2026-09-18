# frozen_string_literal: true

require "spec_helper"

describe "Process programs" do
  it "armed gvl holder waiting on a child process does not stall its siblings" do
    result = ze0(<<~'RUBY', env: {"ZEO_GVL" => "1"})
      # The process-family probe: the backtick child spins until main
      # creates its flag file, and main can only run if the thread parked
      # in read_to_end/wait(2) released the armed Gvl -- without the
      # release this is a three-way deadlock (thread waits on child, child
      # waits on main, main waits on the Gvl) and the test hangs.


      flag = File.join(ENV["TMPDIR"] || "/tmp", "zeo_gvl_probe_#{Process.pid}")
      t = Thread.new { `until [ -e #{flag} ]; do sleep 0.05; done; echo done` }
      sleep 0.2
      File.write(flag, "go")
      p t.value
      File.delete(flag)
    RUBY

    _(result).must_answer "\"done\\n\"\n"
  end

  it "at exit status override" do
    result = ze0(<<~'RUBY')
      # A handler's `exit` overrides the process status (checked by the e2e
      # suite); the REMAINING handlers still run -- the observable rule here.
      at_exit { puts "h1" }
      at_exit { puts "h2"; exit 42 }
      at_exit { puts "h3" }
      puts "body"
    RUBY

    _(result).must_answer <<~'OUT', status: 42
      body
      h3
      h2
      h1
    OUT
  end

  it "backticks and process status" do
    result = ze0(<<~'RUBY')
      # Backtick command literals, `system`, and `$?` as a `Process::Status`.
      # `` `cmd` `` lowers to an implicit-self fcall to the overridable `Kernel#\``,
      # capturing the child's stdout; `system` inherits stdio and answers a
      # true/false verdict. Both leave the child's wait status in `$?`.

      out = `echo hello`
      print out
      puts out.length
      puts $?.exitstatus
      puts $?.success?
      puts $?.class

      p system("true")
      puts $?.exitstatus
      p system("false")
      puts $?.success?
      puts $?.exitstatus

      # Interpolation uses the normal string path; a `;` forces the shell.
      name = "zeo"
      print `echo hi #{name}`
      print `echo a; echo b`
      puts $?.exited?
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      6
      0
      true
      Process::Status
      true
      0
      false
      false
      1
      hi zeo
      a
      b
      true
    OUT
  end

  it "boxs singleton alias is its own and does not abort" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # A class-method ALIAS written in a box's `class << self`. This ABORTED the
      # process before: the alias named the box's overlay class, which registers
      # no entry, and the registrar's `expect` on that lookup is reached across an
      # `extern "C"` boundary that cannot unwind.



      b = Ruby::Box.new
      b.eval("class Array; class << self; alias_method :zz2, :new; end; end")
      p Array.respond_to?(:zz2)
      p b.eval("Array.zz2(1, 5)")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      [5]
    OUT
  end

  it "busy loop threads are killable and raisable" do
    result = ze0(<<~'RUBY')
      # A compute-only loop never reaches a blocking primitive, so `#kill`/`#raise`
      # have no natural delivery point. The back-edge check in every native loop
      # delivers them anyway -- kill runs the ensure, raise is rescuable inside
      # the body.

      Thread.report_on_exception = false
      killed = []
      t = Thread.new do
        begin
          x = 0
          loop { x += 1 }
        ensure
          killed << :ensure_ran
        end
      end
      Thread.pass
      t.kill
      t.join
      p t.alive?
      p killed

      log = []
      u = Thread.new do
        begin
          i = 0
          i += 1 while true
          "unreached"
        rescue => e
          log << e.message
        end
      end
      Thread.pass
      u.raise("stop it")
      u.join
      p log
    RUBY

    _(result).must_answer <<~'OUT'
      false
      [:ensure_ran]
      ["stop it"]
    OUT
  end

  it "chld trap and child waiters share the signal" do
    result = ze0(<<~'RUBY')
      # A CHLD trap still runs while threads wait for children, and system
      # and backticks let other threads run; trap answers DEFAULT for the
      # handling the waiters install.
      got = 0
      Signal.trap("CHLD") { got += 1 }
      t = Thread.new { sleep 0.05; :slept }
      pid = spawn("sleep 0.1")
      Process.wait(pid)
      p t.value, got >= 1
      p Signal.trap("CHLD", "DEFAULT").class
      ticks = 0
      t2 = Thread.new { 20.times { sleep 0.01; ticks += 1 } }
      p system("sleep 0.15"), `echo hi`
      p ticks >= 5
      t2.join
      p Signal.trap("CHLD", "DEFAULT")

    RUBY

    _(result).must_answer <<~'OUT'
      :slept
      true
      Proc
      true
      "hi\n"
      true
      "DEFAULT"
    OUT
  end

  it "circular requires compose in rubys execution order" do
    result = ze0(<<~'RUBY', files: {"circular_requires_compose_in_rubys_execution_order/ca.rb" => "puts \"ca start\"\nrequire_relative \"cb\"\nputs \"ca end\"\n", "circular_requires_compose_in_rubys_execution_order/cb.rb" => "puts \"cb start\"\nrequire_relative \"ca\"\nputs \"cb end\"\n", "circular_requires_compose_in_rubys_execution_order/main.rb" => "require_relative \"ca\"\nputs \"main done\"\n"})
      # CRuby registers a feature as loading BEFORE executing it, so the
      # inner require of an in-progress file is a no-op and execution order
      # is ca-start, all of cb, ca-end -- the dedup-before-lowering rule
      # reproduces this exactly.

      require_relative "circular_requires_compose_in_rubys_execution_order/main"
    RUBY

    _(result).must_answer <<~'OUT'
      ca start
      cb start
      cb end
      ca end
      main done
    OUT
  end

  it "deadlocked wait raises fatal" do
    result = ze0(<<~'RUBY')
      # A wait only another Ruby thread can end, with no other Ruby thread left to
      # end it, is a deadlock. zeo used to HANG there; CRuby raises `fatal`.
      #
      # The check rides the poll the blocking waits already do. A wait registers
      # itself, and when every live thread is registered none of them can be the one
      # to push, unlock or send -- so nothing can make progress. The verdict needs
      # the condition to hold across two consecutive polls, because a thread between
      # two waits is briefly absent from the count without being runnable in any
      # useful sense, and one poll would call that a deadlock.
      #
      # Only UNTIMED waits count. `sleep 2` ends by itself, so a thread inside one is
      # not blocked on anybody, and CRuby draws the same line.
      #
      # `fatal` descends straight from `Exception`, so `rescue => e` misses it and
      # `rescue Exception` catches it. Its lower-case name cannot be written in Ruby
      # source at all -- a constant must start upper-case, and
      # `Object.const_defined?("fatal")` raises `wrong constant name` on ruby too --
      # so the class is reachable only through `e.class`.
      #
      # DIVERGENCE, deliberate: CRuby's message continues past the first line with a
      # thread dump -- native addresses, `rb_thread_t` pointers, a per-thread
      # backtrace. Those describe MRI's VM, are different on every run, and no
      # program can act on them. zeo's message is the first line, which is the part
      # that describes the program, and it is what this golden compares. The
      # uncaught render matches too:
      # `file:LINE:in 'Thread::Queue#pop': No live threads left. Deadlock? (fatal)`.

      def attempt
        yield
        :no_raise
      rescue StandardError => e
        [:standard, e.class]
      rescue Exception => e
        # The FIRST LINE only -- see the divergence note above.
        [:exception, e.class, e.message.lines.first.chomp]
      end

      # An empty Queue with nobody to push to it.
      p attempt { Queue.new.pop }

      # A producer exists, so the wait ends normally and the check must NOT fire.
      q = Queue.new
      producer = Thread.new { sleep 0.05; q << 42 }
      p q.pop
      producer.join

      # The consumer blocks first and the main thread pushes later -- the shape a
      # one-poll verdict would call a deadlock.
      slow = Queue.new
      consumer = Thread.new { slow.pop }
      sleep 0.05
      slow << 7
      p consumer.value

      # A timed sleep is not a deadlock: it ends by itself.
      p attempt { sleep 0.01 }

      # Several workers blocked while the MAIN thread is runnable and has never
      # waited for anything -- minitest's parallel executor, and the shape that
      # caught the first version of this check. The denominator has to be the live
      # RUBY thread count: a scheduling context is installed lazily, the first time
      # a thread waits, so counting contexts makes a runnable thread invisible and
      # declares a deadlock while the thread about to push is still working.
      work = Queue.new
      results = Queue.new
      workers = 3.times.map { Thread.new { results << work.pop * 2 } }
      busy = 0
      200_000.times { |i| busy += i % 3 }
      3.times { |i| work << i }
      p workers.each(&:join).size
      p 3.times.map { results.pop }.sum
      p busy > 0
    RUBY

    _(result).must_answer <<~'OUT'
      [:exception, fatal, "No live threads left. Deadlock?"]
      42
      7
      :no_raise
      3
      6
      true
    OUT
  end

  it "define finalizer runs at exit and validates args" do
    result = ze0(<<~'RUBY')
      # The finalizer for a still-referenced object runs at program exit; the
      # undefined one never runs; the bad-argument shapes match CRuby.

      s = Object.new
      ObjectSpace.define_finalizer(s, proc { |id| puts "finalized(#{id.class})" })
      t = Object.new
      ObjectSpace.define_finalizer(t) { |id| puts "block finalizer" }
      u = Object.new
      ObjectSpace.define_finalizer(u, proc { puts "SHOULD NOT RUN" })
      ObjectSpace.undefine_finalizer(u)
      begin
        ObjectSpace.define_finalizer("x")
      rescue ArgumentError => e
        puts "e1: #{e.message}"
      end
      begin
        ObjectSpace.define_finalizer("x", 5)
      rescue ArgumentError => e
        puts "e2: #{e.message}"
      end
      puts "before exit"
    RUBY

    _(result).must_answer <<~'OUT'
      e1: tried to create Proc object without a block
      e2: wrong type argument Integer (should be callable)
      before exit
      finalized(Integer)
      block finalizer
    OUT
  end

  it "dynamic load compiles and raises loaderror only when executed" do
    result = ze0(<<~'RUBY')
      # Guarded dynamic load: guard false -> never executes -> no error.
      path = nil
      load path if path
      puts "guard_ok"

      # A dynamic load that DOES execute raises a rescuable LoadError.
      missing = "/no/such/file.rb"
      begin
        load missing
      rescue LoadError => e
        puts e.message
      end

      # A dynamic require behaves the same, and the program continues.
      name = "definitely_missing_lib_" + "xyz"
      begin
        require name
      rescue LoadError => e
        puts e.message
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      guard_ok
      cannot load such file -- /no/such/file.rb
      cannot load such file -- definitely_missing_lib_xyz
      done
    OUT
  end

  it "empty command names no program" do
    result = ze0(<<~'RUBY')
      # A command with no word in it -- `system("")` or `system(" ")` -- still names
      # a program: the empty name, which no directory holds. ruby's exec answers
      # ENOENT, so `system` reports 127 and `exception: true` raises it.
      #
      # ze0 split the command into NO words and handed the spawn an empty list, so
      # the kernel read a program name that was not there: signal 11.

      def refusal(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      refusal("system('')") { [system(""), $?&.exitstatus, $?&.success?] }
      refusal("system(' ')") { [system(" "), $?&.exitstatus] }
      refusal("system('', exception: true)") { system("", exception: true) }
      refusal("spawn('')") { Process.spawn("") }
      refusal("backtick('')") { `` }

      # The neighbouring argument guards, which the same helper decides.
      refusal("system(nil)") { system(nil) }
      refusal("system('true', 1)") { system("true", 1) }
      refusal("system()") { system }

      # A command that is only a shell word still reaches the shell.
      refusal("system(';')") { [system(";"), $?&.exitstatus] }

    RUBY

    _(result).must_answer "system(''): [nil, 127, false]\nsystem(' '): [nil, 127]\nsystem('', exception: true): Errno::ENOENT: No such file or directory - \nspawn(''): Errno::ENOENT: No such file or directory - \nbacktick(''): Errno::ENOENT: No such file or directory - \nsystem(nil): TypeError: no implicit conversion of nil into String\nsystem('true', 1): TypeError: no implicit conversion of Integer into String\nsystem(): ArgumentError: wrong number of arguments (given 0, expected 1+)\nsystem(';'): [false, 2]\n", stderr: "sh: -c: line 0: syntax error near unexpected token `;'\nsh: -c: line 0: `;'\n"
  end

  it "every blocking wait is supervised" do
    result = ze0(<<~'RUBY')
      # Every blocking primitive registers with the deadlock detector and parks in
      # slices, so none of them can hang where CRuby raises.
      #
      # Before this, exactly ONE of six waits registered -- `Queue#pop`, which is
      # why `a_deadlocked_wait_raises_fatal.rb` passed while `Mutex#lock`,
      # `SizedQueue#push` back-pressure, `Thread.stop`, `Thread#join` and both
      # Ractor receive sites parked untimed and forever. Registration is now a
      # property of the wait primitive rather than something each site remembers.
      #
      # Two of these are not deadlock verdicts at all, and saying so is the point:
      # `Thread.stop` with no other thread is CRuby's `rb_thread_alone()`
      # ThreadError, decided BEFORE parking, and joining yourself is a ThreadError
      # because there is nobody left to finish the thread being waited on.
      #
      # DIVERGENCE, recorded rather than fixed: for a mutex deadlock CRuby's
      # verdict surfaces in the MAIN thread's `join` frame, while zeo's surfaces
      # in the blocked thread's own `Mutex#lock` -- whichever poll comes first.
      # The exception, its class and its message agree; only the frame that
      # reports it differs, so the rows below read the class and message and the
      # mutex row is not here.

      def attempt(name)
        r = begin
          yield.inspect
        rescue Exception => e
          # The first line only: CRuby's `fatal` continues with a thread dump of
          # native addresses that no other implementation can produce.
          "#{e.class}: #{e.message.lines.first.chomp}"
        end
        puts "#{name}\t#{r}"
      end

      # --- Not deadlocks: ThreadError, decided before any wait ------------------
      attempt("self join") { Thread.current.join }
      attempt("main join") { Thread.main.join }
      attempt("stop alone") { Thread.stop }
      attempt("recursive lock") do
        m = Mutex.new
        m.lock
        m.lock
      end

      # --- Real verdicts --------------------------------------------------------
      attempt("sized queue back-pressure") do
        q = SizedQueue.new(1)
        q << 1
        q << 2
      end

      # --- The limit argument, which used to be accepted and ignored ------------
      attempt("join(0.05) on a slow thread") do
        t = Thread.new { sleep 5 }
        r = t.join(0.05)
        t.kill
        r
      end
      attempt("join(0) on a slow thread") do
        t = Thread.new { sleep 5 }
        r = t.join(0)
        t.kill
        r
      end
      attempt("join(1) on a fast thread") { Thread.new { 1 }.join(1).class }
      attempt("join(nil) on a fast thread") { Thread.new { 1 }.join(nil).class }
      attempt("join(bad)") { Thread.new { 1 }.join(:x) }

      # --- Raising at yourself is delivered NOW, not at some later checkpoint ---
      attempt("current raise") { Thread.current.raise(ArgumentError, "now") }
      attempt("current raise class only") { Thread.current.raise(TypeError) }

      # --- Everything that should still just work -------------------------------
      attempt("mutex synchronize") { Mutex.new.synchronize { 42 } }
      attempt("uncontended lock") do
        m = Mutex.new
        m.lock
        m.unlock
        m.locked?
      end
      attempt("contended lock hands over") do
        m = Mutex.new
        out = []
        m.lock
        t = Thread.new { m.lock; out << :second; m.unlock }
        out << :first
        m.unlock
        t.join
        out
      end
      attempt("value") { Thread.new { 7 }.value }
      attempt("stop and wake") do
        # A rendezvous rather than a spin on `#status`: under load the status
        # poll is a race, and what this row is about is the park and the wake.
        ready = Queue.new
        t = Thread.new do
          ready << :parking
          Thread.stop
          :woke
        end
        ready.pop
        t.run until t.status == false || t.stop?
        t.run
        t.value
      end
      attempt("sized queue drains") do
        q = SizedQueue.new(1)
        consumer = Thread.new { 3.times.map { q.pop } }
        3.times { |i| q << i }
        consumer.value
      end
    RUBY

    _(result).must_answer <<~'OUT'
      self join	ThreadError: Target thread must not be current thread
      main join	ThreadError: Target thread must not be current thread
      stop alone	ThreadError: stopping only thread
      recursive lock	ThreadError: deadlock; recursive locking
      sized queue back-pressure	fatal: No live threads left. Deadlock?
      join(0.05) on a slow thread	nil
      join(0) on a slow thread	nil
      join(1) on a fast thread	Thread
      join(nil) on a fast thread	Thread
      join(bad)	TypeError: can't convert Symbol into Float
      current raise	ArgumentError: now
      current raise class only	TypeError: TypeError
      mutex synchronize	42
      uncontended lock	false
      contended lock hands over	[:first, :second]
      value	7
      stop and wake	:woke
      sized queue drains	[0, 1, 2]
    OUT
  end

  it "exit in an at exit handler sets the status" do
    result = ze0(<<~'RUBY')
      # Handlers run last first; the status a handler's `exit` gives wins over
      # the one the program asked for.
      at_exit { exit 3 }
      at_exit { puts :first, $!.inspect }
      exit 5

    RUBY

    _(result).must_answer <<~'OUT', status: 3
      first
      #<SystemExit: exit>
    OUT
  end

  it "exit poly status" do
    result = ze0(<<~'RUBY')
      # An `exit(status)` whose status expression is poly-typed (here a poly-hash
      # get) must unbox the value -- a bare (int)(sp_RbVal) cast is a cc error.
      h = { "status" => 0, "note" => "text" }
      puts "before exit"
      exit(h["status"])
    RUBY

    _(result).must_answer "before exit\n"
  end

  it "explicit return inside a block exits the enclosing method" do
    result = ze0(<<~'RUBY')
      # `c` is a `New`-assigned LOCAL, not a method parameter -- see
      # `an_escaping_block_can_mutate_an_ivar_via_self_capture`'s comment for
      # why (params are always statically `Poly`, a separate pre-existing
      # gap unrelated to this test's actual point: `return` inside a real
      # escaping Proc unwinding all the way out of `find_even`, not just the
      # block/`.each_num` call).

      class Collector
        def each_num(a, b, c)
          yield a
          yield b
          yield c
        end
      end
      class Finder
        def find_even
          c = Collector.new
          c.each_num(1, 3, 4) { |n| return n if n % 2 == 0 }
          -1
        end
      end
      puts Finder.new.find_even
    RUBY

    _(result).must_answer "4\n"
  end

  it "infinite recursion aborts" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # `loopy = -> { loopy.call }` -- a lambda reaching itself through a captured local.
      # At exit: cycle leak: 2 objects (Proc x1, cell x1)
      # Unbounded recursion kills the process with a native stack overflow. Ruby
      # raises `SystemStackError`, which is an ordinary rescuable exception -- the
      # program below catches it and keeps running.
      #
      # A compiled ruby method is a machine function, so ruby's frames are the
      # machine's frames and running out of them is a hardware fault, not a
      # condition anything can observe. Nothing checks the remaining stack before
      # recursing, so there is no point at which the error could be raised.
      #
      # Accidental infinite recursion is a routine bug -- a `method_missing` that
      # forwards to itself, a `to_s` that interpolates the object, a cycle in a
      # resolver -- and ruby's answer is a normal backtrace that names the method. An
      # abort gives a signal exit status, no backtrace, and nothing for a test runner
      # or a supervisor to catch. It is also unrescuable, so an `ensure` that would
      # release a lock or a file never runs.
      #
      # Bounded deep recursion is fine and must stay fast: 5000 frames answers below.
      #
      # Fix shape: a stack-limit check on entry to a compiled method, the way CRuby
      # checks `ruby_stack_check`. The cost has to be a comparison against a cached
      # limit, not a syscall, or it taxes every call in every program.

      def down(n) = n.zero? ? 0 : 1 + down(n - 1)
      p down(5000)

      def forever = forever
      begin
        forever
      rescue SystemStackError => e
        puts "rescued: #{e.class}"
      end

      # Mutual recursion reaches the same limit.
      def ping(n) = pong(n)
      def pong(n) = ping(n)
      begin
        ping(1)
      rescue SystemStackError
        puts "rescued mutual"
      end

      # A lambda recursing through a captured local, too.
      loopy = nil
      loopy = -> { loopy.call }
      begin
        loopy.call
      rescue SystemStackError
        puts "rescued lambda"
      end

      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      5000
      rescued: SystemStackError
      rescued mutual
      rescued lambda
      still running
    OUT
  end

  it "instance exec break" do
    result = ze0(<<~'RUBY')
      # `break` inside a direct instance_exec block exits the block. In
      # expression position `break <v>` makes <v> the value of the call,
      # matching CRuby. The body is spliced at the call site and wrapped in
      # a `do { } while (0)`, so a top-level break lowers to a C break that
      # carries the value; a break inside a nested loop binds to that loop
      # instead and the instance_exec block runs on to its last expression.

      class Box
        def initialize(v)
          @v = v
        end

        def val
          @v
        end
      end

      class BoxPlus < Box
      end

      b = BoxPlus.new(5)

      # Expression position: break short-circuits with a value.
      puts(b.instance_exec { break 7; 999 })              #=> 7

      # Guard-style break, taken and not-taken.
      puts(b.instance_exec { break 3 if val > 0; 999 })   #=> 3
      puts(b.instance_exec { break 3 if val < 0; 999 })   #=> 999

      # The break value reads the rebound self and a block argument.
      puts(b.instance_exec(10) { |x| break val + x; 0 })  #=> 15

      # A break inside a nested iterator binds to that iterator, not to the
      # instance_exec block; the block continues to its last expression.
      puts(b.instance_exec { [1, 2, 3].each { |x| break }; 42 })  #=> 42

      # Statement position: a bare break is an early exit; the captured
      # outer local keeps the value written before the break.
      acc = 0
      b.instance_exec { acc = 10; break; acc = 99 }
      puts acc                                            #=> 10

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      7
      3
      999
      15
      42
      10
      done
    OUT
  end

  it "instance exec const receiver" do
    result = ze0(<<~'RUBY')
      # A constant bound to an instance (`CONST = Foo.new`) works as an
      # instance_exec receiver: recv_class_idx_for_rebind resolves the
      # constant's registered obj_<Class> type, the same way the local and
      # ivar receiver forms resolve theirs.

      class Counter
        def initialize(n)
          @n = n
        end

        def bump
          @n + 1
        end
      end

      CTR = Counter.new(41)

      puts(CTR.instance_exec { @n })      #=> 41
      puts(CTR.instance_exec { bump })    #=> 42
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      41
      42
      done
    OUT
  end

  it "instance exec def singleton" do
    result = ze0(<<~'RUBY')
      # A `def` inside instance_exec defines a singleton method on the receiver
      # at runtime (CRuby), and zeo matches.
      class Box
        def initialize(v)
          @v = v
        end
      end

      b = Box.new(5)
      b.instance_exec { def greet; "hi"; end }
      puts b.greet
    RUBY

    _(result).must_answer "hi\n"
  end

  it "instance exec define method privacy" do
    result = ze0(<<~'RUBY')
      # define_method inside instance_exec: CRuby raises NoMethodError (it is a
      # private method of Module, and the receiver is a plain instance).
      class Box
        def initialize(v)
          @v = v
        end
      end

      b = Box.new(5)
      begin
        b.instance_exec { define_method(:greet) { 1 } }
      rescue NoMethodError => e
        puts "rescued: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      rescued: undefined method 'define_method' for an instance of Box
    OUT
  end

  it "instance exec dynamic ivar" do
    result = ze0(<<~'RUBY')
      # An ivar first assigned inside an instance_exec / instance_eval block
      # must get a struct slot on the receiver's class. collect_ivars only
      # scans method bodies, so the lift registers the slot (typed from the
      # assignment). No method here references @w or @s -- the only writes are
      # inside the blocks. Box has a subclass so Spinel keeps it heap.
      class Box
        def initialize
          @v = 1
        end
      end

      class BoxPlus < Box
      end

      b = BoxPlus.new

      # int ivar first assigned (and read) inside the block
      puts b.instance_exec { @w = 7; @w + 1 }

      # string ivar assigned in one block, read back in a later block
      b.instance_eval { @s = "hi" }
      puts b.instance_exec { @s }

      # the statically-declared ivar still resolves
      puts b.instance_exec { @v }
    RUBY

    _(result).must_answer <<~'OUT'
      8
      hi
      1
    OUT
  end

  it "instance exec kwargs" do
    result = ze0(<<~'RUBY')
      # Keyword block params bind by name from the call-site `key:` args. An
      # optional param falls back to its default expression when the call
      # omits it; a positional param can precede the keyword params.

      class Calc
        def initialize(base)
          @base = base
        end

        def base
          @base
        end
      end

      c = Calc.new(100)

      # Required keyword params, both supplied.
      puts(c.instance_exec(k: 9, j: 2) { |k:, j:| base + k + j })   #=> 111

      # Optional param supplied overrides its default.
      puts(c.instance_exec(k: 1, j: 7) { |k:, j: 5| k + j })        #=> 8

      # Optional param omitted uses its default.
      puts(c.instance_exec(k: 1) { |k:, j: 5| k + j })              #=> 6

      # Mixed: a positional param plus a keyword param.
      puts(c.instance_exec(10, k: 3) { |a, k:| base + a + k })      #=> 113

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      111
      8
      6
      113
      done
    OUT
  end

  it "instance exec mixed args" do
    result = ze0(<<~'RUBY')
      # Mixed-args instance_exec trampoline: the trampoline body forwards
      # a mix of forwarded locals, the receiver's ivars, and literals --
      # not just call-site params by index.
      #
      #   def fire(x, &b)
      #     instance_exec(x, @base, 7, &b)   # local, ivar, literal
      #   end
      #
      # Each positional arg is evaluated per-kind at the call site: the
      # local picks up the call-site value, the ivar reads the rebound
      # receiver's slot, and the literal is the same C value in any scope.
      #
      # The class keeps a mutating method so it stays heap-allocated
      # (value-type receivers route through a different call path that is
      # a separate change). The block runs in statement position --
      # expression-position return values are a separate change.

      class Mix
        def initialize
          @base = 100
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def sum
          @sum
        end

        def fire(x, &b)
          instance_exec(x, @base, 7, &b)
        end
      end

      m = Mix.new
      m2 = Mix.new   # second instance keeps Mix heap-allocated

      m.fire(3) { |a, b, c| add(a + b + c) }      # add(3 + 100 + 7 = 110)
      m.fire(10) { |a, b, c| add(a * b + c) }     # add(10 * 100 + 7 = 1007)
      puts m.sum                                   # 1117

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1117
      done
    OUT
  end

  it "instance exec module builder" do
    result = ze0(<<~'RUBY')
      # instance_exec in a method defined in an INCLUDED module must compile: the
      # block's self rebinds to the includer (CRuby inserts a per-includer iclass and
      # runs the block on the receiver), so bare calls inside the block dispatch on the
      # includer and ivars type against the includer's slot -- not the module's.
      module Builders
        def collect(&blk) = (instance_exec(&blk); @o)
        def leaf(x) = (@o << x)
      end

      class App
        include Builders
        def initialize = (@o = [])
      end

      # A second includer: each includer gets its own clone, so self resolves per
      # includer (App vs Widget), not to the shared module.
      class Widget
        include Builders
        def initialize = (@o = [])
      end

      p App.new.collect { leaf("a"); leaf("b") }
      p Widget.new.collect { leaf("w") }
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      ["w"]
    OUT
  end

  it "instance exec next" do
    result = ze0(<<~'RUBY')
      # `next` inside a direct instance_exec block exits the block once. In
      # expression position `next <v>` makes <v> the value of the call,
      # matching CRuby -- equivalent to `break <v>` for a once-run block. The
      # body is spliced at the call site and wrapped in a `do { } while (0)`,
      # so a top-level `next` lowers to a C `continue` that falls through the
      # `while (0)` and exits with that value; a `next` inside a nested loop
      # binds to that loop instead and the block runs on to its last
      # expression.

      class Box
        def initialize(v)
          @v = v
        end

        def val
          @v
        end
      end

      class BoxPlus < Box
      end

      b = BoxPlus.new(5)

      # Expression position: next short-circuits with a value.
      puts(b.instance_exec { next 3; 999 })               #=> 3

      # Guard-style next, taken and not-taken.
      puts(b.instance_exec { next val + 1 if val > 0; 999 })  #=> 6
      puts(b.instance_exec { next 7 if val < 0; 999 })        #=> 999

      # The next value reads the rebound self and a block argument.
      puts(b.instance_exec(10) { |x| next val + x; 0 })   #=> 15

      # A next inside a nested iterator binds to that iterator, not to the
      # instance_exec block; the block continues to its last expression.
      puts(b.instance_exec { [1, 2, 3].each { |x| next }; 42 })  #=> 42

      # Statement position: a bare next is an early exit; the captured outer
      # local keeps the value written before the next.
      acc = 0
      b.instance_exec { acc = 10; next; acc = 99 }
      puts acc                                            #=> 10

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      6
      999
      15
      42
      10
      done
    OUT
  end

  it "instance exec nonlocal return" do
    result = ze0(<<~'RUBY')
      # A `return` inside a direct instance_exec block returns from the
      # ENCLOSING method, not just the block -- matching CRuby. The block body
      # is spliced at the call site, so the return lowers to a real C return
      # from the enclosing function.

      class B
        def initialize(v)
          @v = v
        end

        def get
          @v
        end
      end

      class BP < B
      end

      class Host
        def initialize(v)
          @box = B.new(v)
        end

        # return short-circuits this method (guard-clause style); the tested
        # value is captured from the enclosing scope.
        def check(n)
          @box.instance_exec { return n if n > 0 }
          -1
        end

        # return a rebound-self method's value out of this method.
        def grab
          @box.instance_exec { return get }
          999
        end
      end

      h = Host.new(42)
      puts h.check(7)    #=> 7
      puts h.check(-3)   #=> -1
      puts h.grab        #=> 42

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      7
      -1
      42
      done
    OUT
  end

  it "instance exec return" do
    result = ze0(<<~'RUBY')
      # Direct instance_exec in expression position: the call's value is the
      # block's last expression (CRuby semantics), not the receiver.
      #
      # Heap receivers are inlined at the call site -- the block body runs
      # with self rebound to the receiver, so @ivar reads and bare method
      # calls resolve against it, and the block's final value flows out as
      # the call's value. The prior void-lift baseline wrapped the call in a
      # comma-expression that yielded the receiver instead.

      class Box
        def initialize(v)
          @v = v
        end

        def doubled
          @v * 2
        end

        def greet
          "hi"
        end
      end

      # A subclass keeps Box heap-allocated (multi-instance classes are not
      # SRA-promoted to value types), so the receiver is inlined at the call
      # site. Value-typed receivers are handled separately.
      class BoxPlus < Box
      end

      b = Box.new(10)

      # Expression position with an arg: value flows from the block.
      n = b.instance_exec(5) { |x| @v + x }
      puts n                                   #=> 15

      # Zero-arg block, bare method call against the rebound receiver.
      m = b.instance_exec { doubled }
      puts m                                   #=> 20

      # String-valued block.
      g = b.instance_exec { greet }
      puts g                                   #=> hi

      # Nested inside a larger expression.
      puts b.instance_exec(3) { |x| @v + x } + 100   #=> 113

      # Body-local variable inside the block.
      p = b.instance_exec(4) { |x| t = @v * x; t + @v }
      puts p                                   #=> 50

      # Statement position still inlines (value discarded).
      b.instance_exec(7) { |x| puts @v + x }   #=> 17

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      15
      20
      hi
      113
      50
      17
      done
    OUT
  end

  it "instance exec splat" do
    result = ze0(<<~'RUBY')
      # Splat-trampoline instance_exec:
      #
      #   def m(*args, &b)
      #     instance_exec(*args, &b)
      #   end
      #   recv.m(a, b, c) { |x, y, z| ... }   # x=a, y=b, z=c
      #
      # The detector accepts a SplatNode in the trampoline body when its
      # expression is a LocalVariableRead matching the method's rest
      # param name. At inlining time, each call-site positional arg
      # fans out into a block param (per-call-site specialisation:
      # different call sites can pass different numbers of args).
      #
      # Distinguished from fixed-arity trampolines by the SplatNode in
      # the trampoline body's args list; the splat detector requires
      # the splat is the sole positional arg (mixing splat with other
      # positional shapes isn't supported).

      class Builder
        def initialize
          @s = 0
        end
        def add(n)
          @s = @s + n
        end
        def total
          @s
        end
        def with_all(*args, &b)
          instance_exec(*args, &b)
        end
      end

      b = Builder.new
      b2 = Builder.new   # second instance keeps heap allocation

      # Three args at one call site, two args at another -- the splat
      # trampoline fans out each call's args to match its block params.
      b.with_all(1, 2, 3) { |a, b, c| add(a + b + c) }      # +6
      b.with_all(10, 20)  { |x, y|    add(x + y) }          # +30
      b.with_all(100)     { |n|       add(n) }              # +100
      puts b.total                                           # 136

      # Zero-arg splat edge case: no positional args, zero-param block. The splat
      # fans out to zero block params (effective arity 0); the body still splices.
      b2.with_all { add(7) }                                        # +7
      # Four args on the same trampoline, second instance -- per-call-site fan-out.
      b2.with_all(5, 5, 5, 5) { |a, b, c, d| add(a + b + c + d) }   # +20
      puts b2.total                                                  # 27

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      136
      27
      done
    OUT
  end

  it "instance exec toplevel method" do
    result = ze0(<<~'RUBY')
      # A local assigned `Class.new` inside a top-level method body resolves
      # as an instance_exec receiver. The rewrite now walks top-level method
      # bodies (ieval_walk_toplevel_methods), the sibling of the class-method
      # walk, so the receiver's class flows through scan_locals_first_type.

      class Tally
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def sum
          @sum
        end
      end

      def accumulate
        t = Tally.new
        t.instance_exec { add(3); add(4); sum }
      end

      puts accumulate     #=> 7
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      7
      done
    OUT
  end

  it "instance exec trampoline" do
    result = ze0(<<~'RUBY')
      # Inline-at-call-site instance_exec trampoline.
      #
      # Sibling of test/instance_eval_trampoline.rb. instance_exec differs
      # from instance_eval by forwarding positional args from the call site
      # into the block's parameters:
      #
      #   def configure(x, &block)
      #     instance_exec(x, &block)   # x flows into block param at call site
      #   end
      #   b.configure(10) { |n| add(n) }   # n == 10 inside the spliced block
      #
      # Same AOT compromise as instance_eval: detected at compile time by
      # shape match (def m(p1..pN, &b); instance_exec(p1..pN, &b); end),
      # inlined at the call site with self rebound to the receiver and block
      # params bound to fresh suffixed C locals carrying the call-site arg
      # values. A non-trampoline shape falls through to ordinary dispatch; an
      # arity mismatch between block params and forwarded args is a hard error.
      #
      # Limitations exercised by the asymmetry note in section A below:
      #   - Direct `recv.instance_exec(args) { ... }` (outside a trampoline
      #     method) lifts to a static function and cannot capture outer
      #     locals (a follow-up adds pointer capture on the direct path).
      #   - Trampoline body must forward params 1:1, no literals / ivars /
      #     splat (relaxed in follow-ups).
      #   - Value-typed receivers crash on the pointer cast in the splice
      #     today; multi-instance classes (which Spinel keeps heap-allocated)
      #     are the workaround until the TODO in
      #     compile_instance_exec_inlined_stmt is fixed.

      # A. Asymmetry note
      #
      # Outer-local capture works on THIS path (trampoline) because the
      # block body is spliced at the call site, so outer locals are in
      # scope. The direct form `obj.instance_exec(args) { ... }` does NOT
      # capture outer locals -- its lifted static function cannot see the
      # caller's locals. Use the trampoline form when you need capture; a
      # follow-up closes this gap on the direct path.

      # 1. Single fixed arg, statement form: forwards the call-site arg
      #    into the block param, then bare method calls dispatch against
      #    the receiver's class (same rebound-self mechanism as
      #    instance_eval).
      class Builder
        def initialize
          @sum = 0
        end

        def add(n)
          @sum = @sum + n
        end

        def total
          @sum
        end

        def configure(x, &block)
          instance_exec(x, &block)
        end
      end

      b = Builder.new
      b.configure(10) { |n| add(n) }
      b.configure(20) { |n| add(n) }
      b.configure(12) { |n| add(n) }
      puts b.total              #=> 42

      # 2. Two fixed args, ivar read/write inside the block: each arg
      #    becomes a typed C local, the block body computes against them
      #    and the rebound receiver's @ivars. Validates that the
      #    rebound-self retrofit composes with block-param renaming. Builder is
      #    reused (already heap-allocated above) instead of a fresh
      #    class -- single-instance classes with only ivar mutation in
      #    the block tend to value-promote, which the TODO in
      #    compile_instance_exec_inlined_stmt does not yet handle.
      class Acc < Builder
        def bump_by(step, k, &block)
          instance_exec(step, k, &block)
        end
      end

      a1 = Acc.new
      a2 = Acc.new                  # second instance keeps heap allocation
      a1.bump_by(3, 4) { |s, k| add(s * k) }
      a2.bump_by(7, 2) { |s, k| add(s * k) }
      a1.bump_by(1, 0) { |s, k| add(s + k) }
      puts a1.total                 #=> 13
      puts a2.total                 #=> 14

      # 3. Outer-local capture via the splice: total is in scope at the
      #    call site, so the block body reads and writes it. Validates
      #    that the trampoline path does NOT lift the block to a static
      #    function (which would lose closure scope) -- it splices,
      #    keeping outer locals reachable.
      total = 0
      b2 = Builder.new
      b2.configure(5) { |d| add(d); total = total + d }
      b2.configure(7) { |d| add(d); total = total + d }
      puts b2.total             #=> 12
      puts total                #=> 12

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      13
      14
      12
      12
      done
    OUT
  end

  it "instance exec valuetype trampoline" do
    result = ze0(<<~'RUBY')
      # A value-type receiver (small immutable class promoted to a by-value struct)
      # reached through an instance_exec *trampoline* method. The trampoline splice
      # must bind the rebound self by value and dereference its ivars with `.`, not
      # treat it as a pointer -- the receiver here is an sp_Pt struct, not sp_Pt*.
      # The trampoline body also forwards the receiver's own ivars as args, which are
      # read through the by-value self.

      class Pt
        def initialize(x, y)
          @x = x
          @y = y
        end

        # trampoline forwarding two ivars to the block
        def combine(&b)
          instance_exec(@x, @y, &b)
        end

        # trampoline forwarding an ivar plus a forwarded local
        def scale(k, &b)
          instance_exec(@x, k, &b)
        end
      end

      p1 = Pt.new(3, 4)
      p2 = Pt.new(10, 20)

      # expression position: the block value flows into puts
      puts(p1.combine { |a, b| a + b })     # 7
      puts(p2.combine { |a, b| a * b })     # 200
      puts(p1.scale(5) { |x, k| x * k })    # 15

      # statement position
      p2.combine { |a, b| puts(a + b) }     # 30

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      7
      200
      15
      30
      done
    OUT
  end

  it "uid, gid, getpgrp and getsid answer Integers" do
    result = ze0(<<~'RUBY')
      puts Process.uid.class
      puts Process.gid.class
      puts Process.euid.class
      puts Process.egid.class
      puts Process.getpgrp.class
      puts Process.getsid.class
      puts Process.getsid(0).class
      puts(Process.uid == Process.euid)
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      Integer
      Integer
      Integer
      Integer
      Integer
      Integer
      true
    OUT
  end

  it "Process.times answers a Process::Tms of Floats" do
    result = ze0(<<~'RUBY')
      p Process::Tms
      p Process.times.class
      p Process.times.utime.class
      p Process.times.stime >= 0.0
      p Process.times.cutime.class
      p Process.times.cstime.class
    RUBY

    _(result).must_answer <<~'OUT'
      Process::Tms
      Process::Tms
      Float
      true
      Float
      Float
    OUT
  end

  it "clock_getres answers in the unit it is asked for" do
    result = ze0(<<~'RUBY')
      r = Process.clock_getres(Process::CLOCK_MONOTONIC)
      puts r.class
      puts r > 0
      puts Process.clock_getres(Process::CLOCK_REALTIME, :nanosecond).class
      puts Process.clock_getres(Process::CLOCK_MONOTONIC, :float_second).class
    RUBY

    _(result).must_answer <<~'OUT'
      Float
      true
      Integer
      Float
    OUT
  end

  it "getpriority, groups and the PRIO_ constants" do
    result = ze0(<<~'RUBY')
      puts Process.getpriority(Process::PRIO_PROCESS, 0).class
      g = Process.groups
      puts g.class
      puts g.all? { |x| x.is_a?(Integer) }
      puts [Process::PRIO_PROCESS, Process::PRIO_PGRP, Process::PRIO_USER].inspect
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      Array
      true
      [0, 1, 2]
    OUT
  end

  it "Process.times answers a Process::Tms however its result is bound" do
    result = ze0(<<~'RUBY')
      r001 = (Process.times rescue $!.class); p r001.class
      t = (Process.times rescue nil)
      p t.class
      p Process.times.class
    RUBY

    _(result).must_answer <<~'OUT'
      Process::Tms
      Process::Tms
      Process::Tms
    OUT
  end

  it "an attribute named exit reads the attribute, not Kernel#exit" do
    result = ze0(<<~'RUBY')
      class Crash
        attr_accessor :exit
        def fn
          value = exit
          p value
        end
      end
      Crash.new.fn

    RUBY

    _(result).must_answer "nil\n"
  end

  it "issue dollar dollar pid missing" do
    result = ze0(<<~'RUBY')
      # The `$$` global answers the running process id, the same value
      # `Process.pid` does. Checked by equality and positivity rather than the
      # literal number, which necessarily differs between the ruby oracle run and
      # the zeo run.
      p $$ == Process.pid
      p $$.is_a?(Integer) && $$ > 0
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
    OUT
  end

  it "leading assignment and kernel select follow cruby" do
    result = ze0(<<~'RUBY')
      # A command whose first word holds an `=` is an assignment, and only a
      # shell can do that, so the command goes through /bin/sh. Beside it:
      # Kernel carries select as a private method and as a module function,
      # and $LOAD_PATH tells where a require of a name would read from.
      require "tmpdir"

      def t = yield rescue [$!.class, $!.message]

      p system("FOO=1 true")
      p system("FOO=1 false")
      p system("true")

      p Kernel.private_instance_methods.include?(:select)
      p Kernel.instance_method(:select).parameters
      p Kernel.select([], [], [], 0)
      p select([], [], [], 0)

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "thing.rb"), "")
        Dir.mkdir(File.join(dir, "sub"))
        File.write(File.join(dir, "sub", "deep.rb"), "")
        $LOAD_PATH.unshift(dir)
        kind, path = $LOAD_PATH.resolve_feature_path("thing")
        p kind, path == File.realpath(File.join(dir, "thing.rb"))
        p $LOAD_PATH.resolve_feature_path("thing.rb").first
        p $LOAD_PATH.resolve_feature_path("sub/deep").first
        p $LOAD_PATH.resolve_feature_path("nope")
        p t { $LOAD_PATH.resolve_feature_path(:thing) }
        p $LOAD_PATH.singleton_methods
        $LOAD_PATH.shift
      end

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      [[:rest]]
      nil
      nil
      :rb
      true
      :rb
      :rb
      nil
      [TypeError, "no implicit conversion of Symbol into String"]
      [:resolve_feature_path]
    OUT
  end

  it "method defined on a bootstrap class" do
    result = ze0(<<~'RUBY')
      # `method_defined?` on an EXCEPTION class asks at run time, because the
      # compiler cannot see the rows those classes have.
      #
      # The exception hierarchy is written in ruby but carries hand-registered
      # NATIVE rows (`exception.rs`'s `mark_owned_names`). Neither table the fold
      # consults holds them: they are not compiled `def`s, so `method_in_chain`
      # misses, and they reach no `ruby_class!` header, so the projected surface
      # misses too. The walk then concluded "not found, and fully projected" --
      # a confident FALSE about rows the class really has.
      #
      # The cost was silent and total: `error_highlight`'s core_ext gates its whole
      # API on `Exception.method_defined?(:detailed_message)`, so a false answer
      # picked the pre-3.2 `to_s` branch of a library that had already loaded.
      module Probe
        ANSWER = if Exception.method_defined?(:detailed_message)
          :folded_or_asked_true
        else
          :answered_false
        end
      end

      p Probe::ANSWER
      p Exception.method_defined?(:detailed_message)
      p Exception.method_defined?(:full_message)
      p Exception.method_defined?(:no_such_row_anywhere)
      p NameError.method_defined?(:name)
      p NoMethodError.method_defined?(:private_call?)
      p StandardError.method_defined?(:backtrace_locations)

      # A class body asks in its own scope, which is where the fold used to run.
      class Custom < StandardError
        RESULT = [
          method_defined?(:detailed_message),
          method_defined?(:message),
          method_defined?(:nope),
        ]
      end
      p Custom::RESULT
    RUBY

    _(result).must_answer <<~'OUT'
      :folded_or_asked_true
      true
      true
      false
      true
      true
      true
      [true, true, false]
    OUT
  end

  it "popen dash forks and daemon detaches" do
    result = ze0(<<~'RUBY')
      # IO.popen("-") forks with pipes on the child's standard streams, and
      # Process.daemon leaves the parent for a session of its own.
      out = IO.popen("-") do |io|
        if io
          io.read
        else
          print "from the child #{Process.ppid == Process.pid ? :no : :yes}"
        end
      end
      p out, $?.success?
      io = IO.popen("-", "r+")
      if io
        io.puts "ping"
        io.close_write
        p io.read
        io.close
      else
        $stdout.print "got #{$stdin.gets.chomp}"
        exit!(0)
      end
      r, w = IO.pipe
      pid = fork do
        r.close
        Process.daemon(false, true)
        w.puts [Process.ppid != 0, Dir.pwd == "/"].inspect
        w.close
      end
      w.close
      Process.wait(pid)
      p r.read

    RUBY

    _(result).must_answer <<~'OUT'
      "from the child yes"
      true
      "got ping"
      "[true, true]\n"
    OUT
  end

  it "process clock constants" do
    result = ze0(<<~'RUBY')
      # Process::CLOCK_MONOTONIC / CLOCK_REALTIME are Integer values, usable
      # beyond a direct clock_gettime argument.
      x = Process::CLOCK_MONOTONIC
      puts x.nil?
      puts Process::CLOCK_MONOTONIC.nil?
      puts Process::CLOCK_REALTIME.is_a?(Integer)
      clk = Process::CLOCK_MONOTONIC
      puts Process.clock_gettime(clk).is_a?(Float)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      true
    OUT
  end

  it "process identity and clocks" do
    result = ze0(<<~'RUBY')
      # `Process` identity and clocks -- asserted as FACTS about the values, never
      # the values themselves (a pid isn't reproducible).

      p Process.pid.is_a?(Integer)
      p Process.pid > 0
      p Process.clock_gettime(Process::CLOCK_MONOTONIC).is_a?(Float)
      p Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond).is_a?(Integer)
      p Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second).is_a?(Float)
      a = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      b = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      p b >= a
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "process pid" do
    result = ze0(<<~'RUBY')
      # Issue #893: Process.pid / Process.ppid dispatched via getpid /
      # getppid. Values vary by run; test the type. ppid is 0 on
      # Windows where MinGW lacks getppid, >= 0 elsewhere.
      puts Process.pid > 0
      puts Process.ppid >= 0
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
    OUT
  end

  it "process spawn" do
    result = ze0(<<~'RUBY')
      # Process.spawn + Process.waitpid2 + Process::Status.
      #
      # true/false are spelled /usr/bin/... because that is where macOS keeps them;
      # /bin/true and /bin/false do not exist there, and spawning them raised an
      # uncaught Errno::ENOENT part way through this file. Both paths exist on Linux.
      #
      # CRuby semantics:
      #   Process.spawn(cmd, *args, opts) -> Integer pid
      #   Process.waitpid2(pid) -> [pid, Process::Status]
      #   Process::Status#signaled?   -> true if killed by signal
      #   Process::Status#exited?     -> true if exited normally
      #   Process::Status#exitstatus  -> exit code (0..255) or nil
      #   Process::Status#termsig     -> signal number or nil
      #   Process::Status#coredump?   -> true if dumped core
      #   Process::Status#success?    -> true if exited? and exitstatus == 0
      #   Process::Status#pid         -> pid
      #
      # Process::Status has no public constructor in CRuby: the only way to
      # obtain one is Process.waitpid2 on a real subprocess. Both CRuby and
      # spinel must produce the same predicate answers here; the boxed-comparison
      # path (status.exitstatus == 0) is exercised by other tests, this one
      # focuses on the four predicates that the bash tool's signal-check path
      # actually uses (exited? / success? / signaled? / pid).

      # 1) Normal exit, success path. /bin/echo exits 0.
      r, w = IO.pipe
      pid = Process.spawn("/bin/echo", "-n", "hello", out: w)
      w.close
      out = r.read
      _, status = Process.waitpid2(pid)
      puts out == "hello"               # the spawned process actually ran
      puts status.exited?               # exited normally
      puts status.success?              # exited 0
      puts status.signaled? == false    # not killed by signal
      # status.pid is tested in (4) via the destructure, not via the boxed
      # == path that the spinel poly-comparison route doesn't handle yet.

      # 2) Nonexistent command -> Errno::ENOENT.
      ok = false
      begin
        r, w = IO.pipe
        pid = Process.spawn("/no/such/command", out: w)
        w.close
        r.read
        Process.waitpid2(pid)
      rescue Errno::ENOENT
        ok = true
      end
      puts ok

      # 3) /usr/bin/false exits 1: exited? true, success? false.
      r, w = IO.pipe
      pid = Process.spawn("/usr/bin/false", out: w)
      w.close
      r.read
      _, status = Process.waitpid2(pid)
      puts status.exited?
      puts status.success? == false

      # 4) The boxed status: from waitpid2's second element, .signaled? /
      #    .exited? dispatch on the cls_id the poly path reads out of the boxed
      #    value. Goes through emit_poly_builtin_method in codegen_call.c.
      r, w = IO.pipe
      pid = Process.spawn("/usr/bin/true", out: w)
      w.close
      r.read
      result = Process.waitpid2(pid)
      got_pid = result[0]
      got_st  = result[1]
      puts got_pid == pid
      puts got_st.exited?
      puts got_st.success?

      # 5) The boxed status in a String consumer. The accessors are answered on a
      #    poly receiver by emit_poly_builtin_method, which emits an unboxed scalar,
      #    so the inference has to type them the same way -- otherwise the
      #    interpolation asks sp_poly_to_s for what the emitter produced as sp_int.
      r, w = IO.pipe
      pid = Process.spawn("/usr/bin/false", out: w)
      w.close
      r.read
      res = Process.waitpid2(pid)
      st = res[1]
      puts "exit #{st.exitstatus}"
      puts "pid=#{st.pid}" == "pid=#{pid}"

      # 6) A status that did NOT exit normally. CRuby answers nil, not false, for
      #    success?, and nil for exitstatus; termsig carries the signal. The nil
      #    accessors ride the SP_INT_NIL sentinel, so they render as nil and answer
      #    .nil? rather than reading back as -1.
      r, w = IO.pipe
      pid = Process.spawn("/bin/sleep", "5", out: w)
      w.close
      Process.kill("KILL", pid)
      _, ks = Process.waitpid2(pid)
      p ks.signaled?
      p ks.exited?
      p ks.termsig
      p ks.exitstatus
      p ks.exitstatus.nil?
      p ks.success?
      p ks.coredump?
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
      exit 1
      true
      true
      false
      9
      nil
      true
      nil
      false
    OUT
  end

  it "process spawn exec" do
    result = ze0(<<~'RUBY')
      # Process.spawn / Process.exec: spawn starts a child WITHOUT waiting (answering
      # a reapable pid), exec replaces the current image. Output is written from exit
      # statuses only, so it stays byte-identical to CRuby with no temp files.

      # spawn answers a pid; Process.wait reaps it and sets $?.
      pid = Process.spawn("true")
      puts "pid?=#{pid.is_a?(Integer) && pid > 0}"
      Process.wait(pid)
      puts "true=#{$?.exitstatus}"

      pid = Process.spawn("false")
      Process.wait(pid)
      puts "false=#{$?.exitstatus}"

      # Multiple arguments exec directly (no shell); the shell here is explicit.
      pid = Process.spawn("sh", "-c", "exit 5")
      Process.wait(pid)
      puts "sh=#{$?.exitstatus}"

      # A leading env hash is passed through to the child.
      pid = Process.spawn({ "ZEO_X" => "9" }, "sh", "-c", 'exit $ZEO_X')
      Process.wait(pid)
      puts "env=#{$?.exitstatus}"

      # :unsetenv_others wipes the inherited environment (so ZEO_X is gone unless given).
      ENV["ZEO_Y"] = "7"
      pid = Process.spawn("sh", "-c", 'exit ${ZEO_Y:-3}', unsetenv_others: true)
      Process.wait(pid)
      puts "unsetenv=#{$?.exitstatus}"

      # exec inside a fork replaces the child image; its exit status flows to $?.
      pid = Process.fork { Process.exec("sh", "-c", "exit 4") }
      Process.wait(pid)
      puts "exec=#{$?.exitstatus}"

      # A missing program raises Errno::ENOENT.
      begin
        Process.spawn("no_such_command_zxcvb")
        puts "enoent=no"
      rescue Errno::ENOENT
        puts "enoent=yes"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      pid?=true
      true=0
      false=1
      sh=5
      env=9
      unsetenv=3
      exec=4
      enoent=yes
    OUT
  end

  it "process wait family" do
    result = ze0(<<~'RUBY')
      # Process.wait / waitpid / wait2 / waitpid2 / waitall / detach / last_status,
      # plus the $? Process::Status they publish and the Errno::ECHILD raised when no
      # children remain. Children are spawned with Process.fork and each exits with a
      # known code; the output is written relationally so it stays byte-identical to
      # CRuby despite the varying pids.

      # wait answers the reaped pid and sets $? (== Process.last_status).
      pid = Process.fork { exit 7 }
      rpid = Process.wait(pid)
      puts "wait: #{rpid == pid} status=#{$?.exitstatus} last=#{Process.last_status.exitstatus}"

      # waitpid is the same reap-one-child operation.
      pid = Process.fork { exit 4 }
      rpid = Process.waitpid(pid)
      puts "waitpid: #{rpid == pid} status=#{$?.exitstatus}"

      # wait2 / waitpid2 answer the [pid, status] pair.
      pid = Process.fork { exit 3 }
      rp, st = Process.wait2
      puts "wait2: #{rp == pid} exit=#{st.exitstatus} success=#{st.success?}"

      pid = Process.fork { exit 5 }
      rp, st = Process.waitpid2(pid)
      puts "waitpid2: #{rp == pid} exit=#{st.exitstatus}"

      # waitall reaps every remaining child, newest-status wins $?.
      3.times { |i| Process.fork { exit i } }
      results = Process.waitall
      codes = results.map { |(_p, s)| s.exitstatus }.sort
      puts "waitall: count=#{results.length} codes=#{codes.inspect}"

      # detach reaps in the background; the returned thread's value is the Status.
      t = Process.detach(Process.fork { exit 9 })
      puts "detach: value_exit=#{t.value.exitstatus}"

      # With no children left, wait raises Errno::ECHILD.
      begin
        Process.wait
        puts "echild: NO-RAISE"
      rescue Errno::ECHILD
        puts "echild: raised"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      wait: true status=7 last=7
      waitpid: true status=4
      wait2: true exit=3 success=false
      waitpid2: true exit=5
      waitall: count=3 codes=[0, 1, 2]
      detach: value_exit=9
      echild: raised
    OUT
  end

  it "process waiter" do
    result = ze0(<<~'RUBY')
      # Process::Waiter -- Process.detach's answer: a REAL thread retagged to the
      # subclass, with #pid as its one own method and #value joining the reaper.
      pid = Process.spawn("sleep", "0")
      w = Process.detach(pid)

      p w.class
      p w.class.superclass
      p w.pid == pid
      p w.is_a?(Thread)
      st = w.value
      p st.class
      p [st.pid == pid, st.success?]

      p Process::Waiter.instance_methods(false)
      p Process.constants.include?(:Waiter)

      # No allocator, no new -- CRuby undefs both.
      begin
        Process::Waiter.new {}
      rescue TypeError, NoMethodError => e
        puts e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Process::Waiter
      Thread
      true
      true
      Process::Status
      [true, true]
      [:pid]
      true
      NoMethodError
    OUT
  end

  it "system argument list" do
    result = ze0(<<~'RUBY')
      # Multi-argument system calls execute the command directly with its argv list.

      system("ruby", "-e", "puts 'stmt_ok'")

      ok = system("ruby", "-e", "exit 0")
      puts ok
      puts($? == 0)

      ok = system("ruby", "-e", "exit 1")
      puts ok
      puts($? == 0)

      ok = system("ruby", "-e", "exit(ARGV[0] == 'ok' ? 0 : 1)", "ok")
      puts ok
      puts($? == 0)
    RUBY

    _(result).must_answer <<~'OUT'
      stmt_ok
      true
      true
      false
      false
      true
      true
    OUT
  end

  it "system returns true false and sets status" do
    result = ze0(<<~'RUBY')
      # `system` inherits stdio and answers true (exit 0) / false (nonzero),
      # setting `$?` either way. A nonzero exit does not raise.

      p system("true")
      puts $?.exitstatus
      p system("false")
      puts $?.success?
      puts $?.exitstatus
    RUBY

    _(result).must_answer <<~'OUT'
      true
      0
      false
      false
      1
    OUT
  end

  it "systemcallerror case equality" do
    result = ze0(<<~'RUBY')
      # `SystemCallError.===` -- what `rescue Errno::ENOENT` really asks. It matches
      # on the ERRNO NUMBER, so any object answering that number matches, and the
      # bare `SystemCallError` matches every one of its instances outright.
      #
      # zeo answered this off `Module#===` (a plain kind-of test), which is right for
      # the two common cases and wrong for the duck-typed one.

      # Asked by inclusion, not by the whole list: zeo registers `exception` and
      # `to_tty?` on every exception id (flat dispatch), so its list carries two
      # names ruby keeps on `Exception` alone.
      p SystemCallError.singleton_methods(false).include?(:===)
      p SystemCallError.method(:===).arity

      # The bare class matches any instance; a specific one matches its own number.
      p SystemCallError === SystemCallError.new("m", 2)
      p SystemCallError === Errno::EACCES.new
      p Errno::ENOENT === Errno::ENOENT.new
      p Errno::ENOENT === Errno::EACCES.new
      p Errno::ENOENT === SystemCallError.new("m", Errno::ENOENT::Errno)

      # Anything that is not a SystemCallError and cannot answer `errno` misses.
      p SystemCallError === "x"
      p Errno::ENOENT === "x"
      p Errno::ENOENT === nil

      # ... and anything that CAN answer it matches by number alone.
      class Faker
        def initialize(n) = @n = n
        def errno = @n
      end
      p Errno::ENOENT === Faker.new(Errno::ENOENT::Errno)
      p Errno::ENOENT === Faker.new(Errno::EACCES::Errno)
      # On `SystemCallError` the name `Errno` reaches the top-level MODULE, which
      # equals no integer, so a duck never matches the bare class.
      p SystemCallError === Faker.new(Errno::ENOENT::Errno)

      # The whole point: a real rescue still selects the right handler.
      begin
        File.read("/definitely/not/here")
      rescue Errno::EACCES
        p :wrong
      rescue Errno::ENOENT => e
        p [e.class, e.errno]
      end

      begin
        raise Errno::EACCES
      rescue SystemCallError => e
        p e.class
      end

      # And a `case` over the same objects, which is `===` by another spelling.
      [Errno::ENOENT.new, Errno::EACCES.new, RuntimeError.new].each do |e|
        case e
        when Errno::ENOENT then p :enoent
        when SystemCallError then p :other_syscall
        else p :not_syscall
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      1
      true
      true
      true
      false
      true
      false
      false
      false
      true
      false
      false
      [Errno::ENOENT, 2]
      Errno::EACCES
      :enoent
      :other_syscall
      :not_syscall
    OUT
  end

  it "thread join waits for the body and returns" do
    result = ze0(<<~'RUBY')
      # Deterministic by construction: `join` blocks until the spawned thread's
      # body has run to completion, so "in thread" always prints before "after
      # join". (Real ruby agrees on this shape's ordering -- oracle-verified.)

      t = Thread.new do
        puts "in thread"
      end
      t.join
      puts "after join"
    RUBY

    _(result).must_answer <<~'OUT'
      in thread
      after join
    OUT
  end

  it "woken waiter is not a deadlock" do
    result = ze0(<<~'RUBY')
      # A wake is progress. The deadlock detector must not call a thread blocked
      # once its condition is already true.
      #
      # The verdict asks whether every LIVE ruby thread is registered in a wait
      # only another ruby thread can end. A woken thread stays registered for as
      # long as the scheduler takes to run it -- and on a busy machine that is
      # milliseconds. So a `SizedQueue(1)` with one producer and one consumer
      # reads as "both blocked" in the gap between the pop that frees a slot and
      # the producer actually running again, and the run reported `fatal: No
      # live threads left. Deadlock?` for a program that was working.
      #
      # It surfaced as a golden that passed alone and failed under a full
      # sixteen-job suite, which is exactly the shape a timing verdict fails in.
      # Every wake site now says so (`note_progress`), and the verdict needs
      # eight consecutive all-blocked polls with no wake between them. A real
      # deadlock has nobody to wake it EVER, so the longer streak costs a true
      # verdict nothing.
      #
      # The rows below are the shapes that hand a wait back and forth many times
      # over. None of them is a deadlock and none may report one.

      results = []

      # A one-slot queue: every push waits for a pop and every pop for a push.
      q = SizedQueue.new(1)
      consumer = Thread.new { 200.times.map { q.pop } }
      200.times { |i| q << i }
      results << consumer.value.sum

      # Two threads handing one mutex back and forth.
      m = Mutex.new
      n = 0
      ts = 2.times.map do
        Thread.new { 200.times { m.synchronize { n += 1 } } }
      end
      ts.each(&:join)
      results << n

      # A plain Queue drained by two consumers, closed to release them.
      work = Queue.new
      seen = Queue.new
      2.times do
        Thread.new do
          while (job = work.pop)
            seen << job
          end
        end
      end
      100.times { |i| work << i }
      sleep 0.05 until seen.size == 100
      work.close
      results << seen.size

      # A condition variable: the wait is untimed and only a signal ends it.
      cv = ConditionVariable.new
      lock = Mutex.new
      ready = false
      waiter = Thread.new do
        lock.synchronize do
          cv.wait(lock) until ready
          :signalled
        end
      end
      sleep 0.01
      lock.synchronize do
        ready = true
        cv.signal
      end
      results << waiter.value

      # A real deadlock is still a deadlock, and still prompt.
      verdict = begin
        full = SizedQueue.new(1)
        full << 1
        full << 2
      rescue Exception => e
        "#{e.class}: #{e.message.lines.first.chomp}"
      end
      results << verdict

      p results
    RUBY

    _(result).must_answer <<~'OUT'
      [19900, 400, 100, :signalled, "fatal: No live threads left. Deadlock?"]
    OUT
  end
end
