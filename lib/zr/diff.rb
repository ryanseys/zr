# frozen_string_literal: true

require "open3"

module Zr
  # Runs a program and compares two runs of it: under ruby and as a zr
  # binary. `zr diff` and `zr-dev probe` use it.
  #
  # An object address (`0x` and 16 hex digits) is never the same in two
  # processes, so both outputs have each one as `0x...`.
  module Diff
    # One run: its stdout, stderr, exit status, and the signal that
    # stopped it (nil when it exited). `timeout` is true when the run took
    # longer than its limit and was stopped.
    Answer = Struct.new(:stdout, :stderr, :status, :signal, :timeout) do
      def parts = { stdout: stdout, stderr: stderr, status: status, signal: signal }
    end

    # Seconds that one run can take.
    LIMIT = 60

    ADDRESS = /0x\h{16}/n

    # The parts of an answer, in the order that a report shows them.
    PARTS = %i[stdout stderr status signal].freeze

    module_function

    def unaddressed(text) = text.b.gsub(ADDRESS, "0x...")

    # Runs `command` in `dir` with an empty stdin and `env` over this
    # environment. A run longer than `limit` seconds is killed.
    def run(command, dir: Dir.pwd, env: {}, limit: LIMIT)
      Open3.popen3(env, *command, chdir: dir) do |stdin, stdout, stderr, waiter|
        stdin.close
        out = Thread.new { stdout.read }
        err = Thread.new { stderr.read }
        stopped = !waiter.join(limit)
        Process.kill("KILL", waiter.pid) if stopped
        status = waiter.value
        Answer.new(unaddressed(out.value), unaddressed(err.value), status.exitstatus, status.termsig, stopped)
      end
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

    # A unified diff of two texts, as `diff -u` writes it without its two
    # header lines: hunks of `-` lines (only in `a`), `+` lines (only in
    # `b`) and context lines. Empty when the texts are the same. In Ruby,
    # so zr needs no `diff` program.
    def unified(a, b)
      old = a.b.lines
      new = b.b.lines
      edits = script(old, new)
      return "" if edits.all? { |op, _, _| op == :same }

      hunks(edits).map { |hunk| hunk_text(hunk, old, new) }.join
    end

    # The edit script from `old` to `new`: `[op, i, j]` for each line, where
    # op is :same (old[i] is new[j]), :del (old[i] only) or :ins (new[j]
    # only). Myers' algorithm: the shortest script, in O((N+M)D) time.
    def script(old, new)
      n = old.size
      m = new.size
      max = n + m
      v = { 1 => 0 }
      trace = []
      (0..max).each do |d|
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
      []
    end

    def backtrack(trace, x, y)
      edits = []
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
        line = op == :ins ? new[j] : old[i]
        out << MARKS.fetch(op) << line
        out << "\n\\ No newline at end of file\n" unless line.end_with?("\n")
      end
      out
    end

    # The line of one side (1 for old, 2 for new) where the hunk starts:
    # its first edit that has a line on that side. A hunk has context
    # lines wherever the side has lines, so a hunk with none is a side
    # with no lines at all, which starts at 0.
    def before(hunk, side)
      first = hunk.find { |edit| edit[side] }
      first ? first[side] : 0
    end

    def range(at, count) = count == 1 ? at.to_s : "#{at},#{count}"

    # The report of each part that differs: a heading, then its diff.
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
