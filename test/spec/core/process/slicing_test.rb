# frozen_string_literal: true

require "spec_helper"

describe "Process: slicing" do
  it "at exit lifo" do
    result = ze0(<<~'RUBY')
      # at_exit hooks run in LIFO order after main returns. Spinel used
      # to silently drop the block.
      at_exit { puts "first registered" }
      at_exit { puts "second registered" }
      at_exit { puts "third registered" }
      puts "main"
    RUBY

    _(result).must_answer <<~'OUT'
      main
      third registered
      second registered
      first registered
    OUT
  end

  it "instance exec direct splat" do
    result = ze0(<<~'RUBY')
      # A single splat arg to a *direct* instance_exec spreads its source
      # array across the block's params, exactly as passing the array
      # directly does (CRuby auto-splat). The receiver stays heap (Box has a
      # subclass), and the block reads the rebound self's ivar alongside the
      # spread elements. (The implicit-self trampoline splat is covered by
      # instance_exec_splat.rb; this is the explicit-receiver direct lift.)
      class Box
        def initialize(v)
          @v = v
        end
      end

      class BoxPlus < Box
      end

      b = BoxPlus.new(5)

      # splat of an int array across two params
      args = [10, 7]
      puts b.instance_exec(*args) { |a, c| a + c + @v }

      # a directly-passed array auto-splats the same way (regression anchor)
      puts b.instance_exec([3, 4]) { |a, c| a * c }

      # splat of a string array
      words = ["x", "y"]
      puts b.instance_exec(*words) { |a, c| a + c }

      # a sole splat spreads across a single param too: the block's lone param
      # binds to the first spread element (arr[0]), not the whole array -- this
      # is where a splat diverges from a directly-passed array, and the param
      # count alone (1) would otherwise leave the splat un-spread.
      puts b.instance_exec(*args) { |a| a + @v }
      puts b.instance_exec(*words) { |a| a }
    RUBY

    _(result).must_answer <<~'OUT'
      22
      12
      xy
      15
      x
    OUT
  end

  it "instance exec trampoline receiverless" do
    result = ze0(<<~'RUBY')
      # A receiverless call to an instance_exec trampoline splices the literal
      # block with self rebound (previously the block was silently dropped), and
      # a parenthesized value-tail keeps its leading statements ordered ahead of
      # the spliced block body.
      class App
        def initialize = (@o = [])
        def go(&blk) = instance_exec(&blk)
        def leaf(x) = (@o << x)
        def render = (go { leaf("a") }; @o)
      end
      p App.new.render

      class Builder
        def initialize = (@o = [])
        def el(tag, &blk) = (@o << tag; instance_exec(&blk))
        def leaf(x) = (@o << x)
        def render = (el("col") { leaf("a") }; @o)
      end
      p Builder.new.render

      class WithArgs
        def initialize = (@sum = 0)
        def run(x, &blk) = instance_exec(x, &blk)
        def add(n) = (@sum += n)
        def total = (run(5) { |v| add(v * 2) }; @sum)
      end
      p WithArgs.new.total

      class Both
        def initialize = (@log = [])
        def outer(&blk) = instance_exec(&blk)
        def mark(t) = (@log << t)
        def drive
          outer { mark(:first) }
          self.outer { mark(:second) }
          @log
        end
      end
      p Both.new.drive
    RUBY

    _(result).must_answer <<~'OUT'
      ["a"]
      ["col", "a"]
      10
      [:first, :second]
    OUT
  end

  it "post execution" do
    result = ze0(<<~'RUBY')
      # PostExecutionNode -- `END { ... }`.
      #
      # CRuby runs END blocks at program exit in REVERSE order of
      # registration. Spinel emits each END body as a static C function
      # and registers it via atexit() during main() startup.

      puts "middle"

      END {
        puts "last-1"
      }

      END {
        puts "last-2"  # registered second; runs first per atexit semantics
      }

      puts "before-end"
    RUBY

    _(result).must_answer <<~'OUT'
      middle
      before-end
      last-2
      last-1
    OUT
  end

  it "pre execution" do
    result = ze0(<<~'RUBY')
      # PreExecutionNode -- `BEGIN { ... }`.
      #
      # CRuby runs all BEGIN blocks in source order, BEFORE any other
      # top-level statements, regardless of where they appear in the file.
      # Spinel hoists each BEGIN body to the top of main() in source-encounter
      # order during a pre-pass.

      puts "middle"

      BEGIN {
        puts "first"
      }

      BEGIN {
        puts "first-2"
      }

      puts "last"
    RUBY

    _(result).must_answer <<~'OUT'
      first
      first-2
      middle
      last
    OUT
  end

  it "process exit family" do
    result = ze0(<<~'RUBY')
      # Process.exit / Process.abort are the module-function twins of the Kernel
      # forms: both raise a RESCUABLE SystemExit carrying the status, unwinding
      # through ensure, and abort writes its message to stderr first.
      begin
        Process.exit(5)
        puts "unreached"
      rescue SystemExit => e
        puts "exit-status=#{e.status}"
        puts "exit-success=#{e.success?}"
      end
      puts "continued"

      begin
        Process.abort("boom-message")
      rescue SystemExit => e
        puts "abort-status=#{e.status}"
        puts "abort-msg=#{e.message}"
      end

      # The unwind runs ensure blocks on its way out of Process.exit too.
      def guarded
        Process.exit(0)
      ensure
        puts "ensure ran"
      end
      begin
        guarded
      rescue SystemExit => e
        puts "guarded-status=#{e.status}"
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "boom-message\n"
      exit-status=5
      exit-success=false
      continued
      abort-status=1
      abort-msg=boom-message
      ensure ran
      guarded-status=0
      done
    OUT
  end

  it "signal trap stub" do
    result = ze0(<<~'RUBY')
      # trap / Signal.trap / ::Signal.trap compile to no-ops at every shape;
      # Spinel has no signal-handler runtime, so the block body (if any)
      # never fires. Expression position returns "DEFAULT" -- CRuby's value
      # for any signal that was never previously trapped.
      #
      # Each section uses a distinct signal name so no signal's state is
      # observed twice (CRuby would return the prior handler on the second
      # touch, which Spinel does not yet model).

      # Stmt position, implicit-self.
      trap("INT") { puts "handler" }

      # Stmt position, explicit Signal receiver (ConstantReadNode).
      Signal.trap("TERM") { puts "handler" }

      # Stmt position, toplevel ::Signal receiver (ConstantPathNode).
      ::Signal.trap("HUP") { puts "handler" }

      # Stmt position, no block.
      trap("QUIT", "EXIT")

      # Expr position, first call on a never-trapped signal returns "DEFAULT".
      prev = trap("USR1") { puts "x" }
      puts prev

      # Expr position via Signal receiver, also returns "DEFAULT" on first call.
      prev2 = Signal.trap("USR2") { puts "y" }
      puts prev2

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      DEFAULT
      DEFAULT
      done
    OUT
  end

  it "spawn and exec take every option" do
    result = ze0(<<~'RUBY')
      # The spawn options posix_spawn cannot carry go through fork and execve:
      # umask, pgroup and rlimit_*. exec takes an environment and options,
      # every refusal names what rb_execarg_addopt names, and open("|cmd")
      # names a file, as ruby 4.0 reads it.
      p system("sh", "-c", "umask", umask: 0o077)
      r, w = IO.pipe
      pid = spawn("sh", "-c", "ps -o pgid= -p $$; echo $$", pgroup: true, out: w)
      w.close
      pgid, me = r.read.split.map(&:to_i)
      Process.wait(pid)
      p pgid == me
      p IO.popen(["sh", "-c", "ulimit -n"], rlimit_nofile: 100, &:read)
      p IO.popen(["sh", "-c", "ulimit -c"], rlimit_core: [0, 0], &:read)
      p IO.popen(["sh", "-c", "echo $FOO-$HOME"], unsetenv_others: true, &:read)
      p IO.popen([{"FOO" => "bar"}, "sh", "-c", "echo $FOO"], &:read)
      [-> { spawn("true", new_pgroup: true) }, -> { spawn("true", pgroup: -1) }, -> { spawn("true", umask: "x") },
       -> { spawn("true", rlimit_bogus: 1) }, -> { spawn("true", rlimit_core: [1, 2, 3]) }, -> { spawn("definitely_not_zz") },
       -> { spawn("definitely_not_zz", umask: 0) }, -> { system("definitely_not_zz", exception: true) }].each do |bad|
        p bad.call
      rescue => e
        p e
      end
      p system("definitely_not_zz"), $?.exitstatus
      pid = fork { exec({"GREETING" => "hi"}, "sh", "-c", "echo $GREETING-$(pwd)", chdir: "/", umask: 0o22) }
      Process.wait(pid)
      pid = fork { exec("sh", "-c", "echo to-err >&2", err: :out) }
      Process.wait(pid)
      p (open("|echo hi") rescue $!.class)

    RUBY

    _(result).must_answer <<~'OUT'
      0077
      true
      true
      "100\n"
      "0\n"
      "-\n"
      "bar\n"
      #<ArgumentError: wrong exec option symbol: new_pgroup>
      #<ArgumentError: negative process group ID : -1>
      #<TypeError: no implicit conversion of String into Integer>
      #<ArgumentError: wrong exec option symbol: rlimit_bogus>
      #<ArgumentError: wrong exec rlimit option>
      #<Errno::ENOENT: No such file or directory - definitely_not_zz>
      #<Errno::ENOENT: No such file or directory - definitely_not_zz>
      #<Errno::ENOENT: No such file or directory - definitely_not_zz>
      nil
      127
      hi-/
      to-err
      Errno::ENOENT
    OUT
  end
end
