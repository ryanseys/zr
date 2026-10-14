# frozen_string_literal: true

require "open3"

module Zr
  # Runs a program and compares two runs of it: under ruby and as a zr
  # binary. `zr diff` and the fuzzer use it.
  #
  # An object address (`0x` and 16 hex digits) is never the same in two
  # processes, so both outputs have each one as `0x...`.
  module Diff
    # One run: its stdout, stderr, exit status, and the signal that
    # stopped it (nil when it exited). `timeout` is true when the run took
    # longer than its limit and was stopped.
    # @rbs skip
    Answer = Data.define(:stdout, :stderr, :status, :signal, :timeout)

    # The fields are typed in sig/zr/diff.rbs, the methods here.
    class Answer
      #: () -> Hash[Symbol, untyped]
      def parts = { stdout: stdout, stderr: stderr, status: status, signal: signal }
    end

    # Seconds that one run can take.
    LIMIT = 60

    # An object address: 0x and 8 to 16 lowercase hex digits, no more.
    # The program tests' recordings mask it the same way.
    ADDRESS = /0x[0-9a-f]{8,16}(?![0-9a-f])/n

    # The parts of an answer, in the order that a report shows them.
    PARTS = %i[stdout stderr status signal].freeze

    module_function

    #: (String text) -> String
    def unaddressed(text) = text.b.gsub(ADDRESS, "0xADDR")

    # Runs `command` in `dir` with an empty stdin and `env` over this
    # environment, in a process group of its own. A run whose program, or
    # a child that holds its output open, takes longer than `limit`
    # seconds is stopped: its whole group is killed. (The tests' runner,
    # Harness::Child, does not ship with zr, and `zr diff` does.)
    #: (Array[String] command, ?dir: String, ?env: Hash[String, String?], ?limit: (Integer | Float)?) -> Answer
    def run(command, dir: Dir.pwd, env: {}, limit: LIMIT)
      Open3.popen3(env, *command, chdir: dir, pgroup: true) do |stdin, stdout, stderr, waiter|
        stdin.close
        out = Thread.new { stdout.read }
        err = Thread.new { stderr.read }
        deadline = limit && (clock + limit)
        stopped = [waiter, out, err].any? { |thread| !thread.join(deadline && [deadline - clock, 0].max) }
        kill_group(waiter.pid) if stopped
        status = waiter.value
        Answer.new(unaddressed(out.value), unaddressed(err.value), status.exitstatus, status.termsig, stopped)
      end
    end

    #: () -> Float
    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Kills the process group `pid`: the program and every child it left.
    #: (Integer pid) -> void
    def kill_group(pid)
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil
    end

    # The kind of difference between ruby's answer and zr's, in words:
    #
    #   same            every part is the same
    #   timeout         the zr binary ran longer than its limit
    #   crash           a signal stopped the zr binary, and not ruby
    #   status-diff     the exit statuses differ
    #   exception-diff  the stderr differs (ruby's report of an exception)
    #   output-diff     only the stdout differs
    #
    # A build that fails has its own kind (`refused`, `build-error`),
    # which the caller gives.
    #: (Answer ruby, Answer zr) -> String
    def kind(ruby, zr)
      return "same" if ruby.parts == zr.parts
      return "timeout" if zr.timeout && !ruby.timeout
      return "crash" if zr.signal && !ruby.signal
      return "status-diff" if ruby.status != zr.status || ruby.signal != zr.signal
      return "exception-diff" if ruby.stderr != zr.stderr

      "output-diff"
    end

    # Lines of context around each change in a hunk, as `diff -u` gives.
    CONTEXT = 3
    # The mark at the start of each line of a hunk.
    MARKS = { same: " ", del: "-", ins: "+" }.freeze
    # The most changes that a diff lists. The search keeps a row for each
    # change that it takes, so its work grows as their square; past the
    # cap, the diff shows the first change and the size of each side.
    MAX_CHANGES = 1_000

    # A unified diff of two texts, as `diff -u` writes it without its two
    # header lines: hunks of `-` lines (only in `a`), `+` lines (only in
    # `b`) and context lines. Empty when the texts are the same. In Ruby,
    # so zr needs no `diff` program.
    #: (String a, String b) -> String
    def unified(a, b)
      old = a.b.lines
      new = b.b.lines
      return "" if old == new

      edits = script(old, new) or return capped(old, new)
      hunks(edits).map { |hunk| hunk_text(hunk, old, new) }.join
    end

    # `[i, a[i], b[i]]` for the first line `i` where the two lists differ,
    # a side past its end giving nil; nil when they are the same.
    #: (Array[String] a, Array[String] b) -> [Integer, String?, String?]?
    def first_change(a, b)
      i = (0...[a.size, b.size].max).find { |n| a[n] != b[n] } or return nil
      [i, a[i], b[i]]
    end

    # One hunk of the first change, then a line that says how much the
    # cap left out.
    #: (Array[String] old, Array[String] new) -> String
    def capped(old, new)
      change = first_change(old, new) or return ""
      i, a, b = change
      out = +"@@ -#{range(i + 1, a ? 1 : 0)} +#{range(i + 1, b ? 1 : 0)} @@\n".b
      out << marked("-", a) if a
      out << marked("+", b) if b
      out << "\\ more than #{MAX_CHANGES} changes in all: #{old.size} lines, then #{new.size}\n"
    end

    # The edit script from `old` to `new`: `[op, i, j]` for each line, where
    # op is :same (old[i] is new[j]), :del (old[i] only) or :ins (new[j]
    # only). Myers' algorithm: the shortest script, in O((N+M)D) time.
    # Nil when it takes more than MAX_CHANGES changes.
    def script(old, new)
      n = old.size
      m = new.size
      max = n + m
      v = { 1 => 0 }
      trace = [] #: Array[Hash[Integer, Integer]]
      (0..[max, MAX_CHANGES].min).each do |d|
        trace << v.dup
        (-d..d).step(2) do |k|
          x = k == -d || (k != d && v[k - 1] < v[k + 1]) ? v[k + 1] : v[k - 1] + 1
          y = x - k
          while x < n && y < m && old[x] == new[y]
            x += 1
            y += 1
          end
          v[k] = x
          return backtrack(trace, n, m) if x >= n && y >= m
        end
      end
      nil
    end

    def backtrack(trace, x, y)
      edits = [] #: Array[[Symbol, Integer?, Integer?]]
      (trace.size - 1).downto(0) do |d|
        v = trace[d]
        k = x - y
        prev = k == -d || (k != d && v[k - 1] < v[k + 1]) ? k + 1 : k - 1
        px = v[prev]
        py = px - prev
        while x > px && y > py
          edits << [:same, x - 1, y - 1]
          x -= 1
          y -= 1
        end
        break if d.zero?

        edits << (x == px ? [:ins, nil, y - 1] : [:del, x - 1, nil])
        x = px
        y = py
      end
      # In each run of changes, the old lines go first, as `diff -u`
      # writes a change.
      edits.reverse.chunk_while { |a, b| (a[0] == :same) == (b[0] == :same) }.flat_map do |run|
        run.first[0] == :same ? run : run.partition { |op, _, _| op == :del }.flatten(1)
      end
    end

    # The edits in groups: each change with CONTEXT lines of `:same`
    # before and after, and two changes closer than 2 * CONTEXT in one.
    def hunks(edits)
      changes = edits.each_index.reject { |i| edits[i][0] == :same }
      groups = changes.slice_when { |a, b| b - a > 2 * CONTEXT }
      groups.map { |group| edits[[group.first - CONTEXT, 0].max..[group.last + CONTEXT, edits.size - 1].min] }
    end

    # The text of one hunk. Its first edit is at old line `a` and new line
    # `b` (from 0); a side with no lines names the line before the hunk,
    # as `diff -u` does.
    def hunk_text(hunk, old, new)
      op, i, j = hunk.first
      a = op == :ins ? before(hunk, 1) : i
      b = op == :del ? before(hunk, 2) : j
      a_count = hunk.count { |o, _, _| o != :ins }
      b_count = hunk.count { |o, _, _| o != :del }
      out = +"@@ -#{range(a_count.zero? ? a : a + 1, a_count)} +#{range(b_count.zero? ? b : b + 1, b_count)} @@\n".b
      hunk.each do |op, i, j|
        out << marked(MARKS.fetch(op), op == :ins ? new[j] : old[i])
      end
      out
    end

    # One line of a hunk after its mark, with diff's note when the line
    # has no newline.
    #: (String mark, String line) -> String
    def marked(mark, line) = line.end_with?("\n") ? "#{mark}#{line}" : "#{mark}#{line}\n\\ No newline at end of file\n"

    # The line of one side (1 for old, 2 for new) where the hunk starts:
    # its first edit that has a line on that side. A hunk has context
    # lines wherever the side has lines, so a hunk with none is a side
    # with no lines at all, which starts at 0.
    def before(hunk, side)
      first = hunk.find { |edit| edit[side] }
      first ? first[side] : 0
    end

    #: (Integer at, Integer count) -> String
    def range(at, count) = count == 1 ? at.to_s : "#{at},#{count}"

    # The report of each part that differs: a heading, then its diff.
    #: (Answer ruby, Answer zr) -> String
    def report(ruby, zr)
      PARTS.filter_map do |part|
        a = ruby.parts.fetch(part)
        b = zr.parts.fetch(part)
        next if a == b

        "--- #{part} (ruby, then zr)\n#{unified("#{a}\n", "#{b}\n")}"
      end.join
    end
  end
end
