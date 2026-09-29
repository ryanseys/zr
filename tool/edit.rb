# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # Measures the edit loop: how long `zr run` takes right after an edit
    # to zr's own sources.
    #
    #   zr-dev edit                                   every kind of edit, both programs
    #   zr-dev edit --kind core-comment --program eval
    #   zr-dev edit --runs 3 --commit                 write a baseline to benchmark/results/edit/
    #
    # The tool works in a copy of the tree (`tmp/edit/tree`) with its own
    # cache (`tmp/edit/cache`). It keeps both between runs, so only the
    # first run builds everything. For each kind of edit and each program it:
    #
    # 1. brings the copy up to date with the checkout, and runs the program
    #    once, untimed, so that the cache holds the unedited tree;
    # 2. appends the kind's text to the kind's file. The text has a new
    #    number each time, so no cache holds its result;
    # 3. times `exe/zr run` in the copy, as a person runs it: no preset
    #    collector limits, and ruby, not the compiled compiler;
    # 4. puts the file back.
    #
    # The checkout never changes. A comment changes no code, so its time is
    # the least that a rebuild costs. A method adds a symbol name.
    class Edit < Command
      summary "How long `zr run` takes right after an edit to zr"
      usage "[--kind KIND,...] [--program NAME,...] [--runs N] [--commit]"
      host_ruby!

      WORK = Dev.path("tmp/edit")
      TREE = File.join(WORK, "tree")
      CACHE = File.join(WORK, "cache")
      RESULTS = Dev.path("benchmark/results/edit")
      RUNS = 1

      PROGRAMS = {
        "hello" => "puts 1 + 1\n",
        "eval" => "puts eval(\"1 + 1\")\n"
      }.freeze

      COMMENT = ->(n) { "\n# edit #{n}\n" }

      # A kind: the file that the edit appends to, and its text.
      EDITS = {
        "none" => nil,
        "kernel-comment" => ["runtime/kernel/proc.rb", COMMENT],
        "core-comment" => ["runtime/core/array.rb", COMMENT],
        "core-method" => ["runtime/core/array.rb", ->(n) { "\nclass Array\n  def __zr_edit_#{n} = #{n}\nend\n" }],
        "lower-comment" => ["lib/zr/lower/function.rb", COMMENT],
        "ext-comment" => ["runtime/ext/stringio.rb", COMMENT]
      }.freeze

      # The line `Zr.clock` writes: a label padded to 40, then the seconds.
      LINE = /\Azr: (.+?)\s+([\d.]+)s(?:\s|\z)/
      WHOLE = "the whole run"
      OTHER = "not in a phase"

      def options(o)
        o.on("--kind KINDS", Array, "kinds of edit (#{EDITS.keys.join(", ")})") { |v| @kinds = v }
        o.on("--program NAMES", Array, "programs (#{PROGRAMS.keys.join(", ")})") { |v| @programs = v }
        o.on("--runs N", Integer, "edits of each kind (default #{RUNS}); the median counts") { |v| @runs = v }
        o.on("--commit", "write the table to benchmark/results/edit/") { @commit = true }
      end

      def run(_argv)
        kinds = @kinds || EDITS.keys
        programs = @programs || PROGRAMS.keys
        (kinds - EDITS.keys).each { |k| fail!("no kind #{k}; the kinds are #{EDITS.keys.join(", ")}") }
        (programs - PROGRAMS.keys).each { |p| fail!("no program #{p}; the programs are #{PROGRAMS.keys.join(", ")}") }
        runs = @runs || RUNS

        rows = {}
        programs.each do |program|
          kinds.each do |kind|
            print format("%-16s %-6s ... ", kind, program)
            taken = Array.new(runs) { once(kind, program) }.sort_by { |p| p.fetch(WHOLE) }
            rows["#{kind} #{program}"] = taken[runs / 2].tap { |p| puts format("%.2fs", p.fetch(WHOLE)) }
          end
        end
        table = table(rows)
        puts "", table
        write!(table, runs) if @commit
        true
      end

      # One edit and one timed run. Returns `{phase => seconds}`.
      def once(kind, program)
        sync!
        main = program_file(program)
        timed(main) # the cache now holds the unedited tree
        file, text = EDITS.fetch(kind)
        return timed(main) unless file

        path = File.join(TREE, file)
        before = File.binread(path)
        begin
          File.binwrite(path, before + text.call(Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)))
          timed(main)
        ensure
          File.binwrite(path, before)
        end
      end

      # Runs `exe/zr run main` in the copy, and returns its phases and the
      # whole wall time.
      def timed(main)
        env = { "ZR_TIMING" => "1", "ZR_CACHE" => CACHE, "RUBY_GC_MALLOC_LIMIT" => nil,
                "RUBY_GC_OLDMALLOC_LIMIT" => nil, **Dev::UNDER_RUBY }
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        _, err, status = Open3.capture3(env, Dev.ruby, File.join(TREE, "exe/zr"), "run", main, chdir: TREE)
        took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began
        fail!("#{main} did not run\n#{err}") unless status.success?

        phases = err.lines.filter_map { |line| LINE.match(line.strip)&.captures }
                    .each_with_object(Hash.new(0.0)) { |(label, s), h| h[label] += s.to_f }
        phases.merge(WHOLE => took, OTHER => [took - phases.values.sum, 0].max)
      end

      def program_file(program)
        path = File.join(WORK, "programs", "#{program}.rb")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, PROGRAMS.fetch(program)) unless File.exist?(path) && File.read(path) == PROGRAMS.fetch(program)
        path
      end

      # Makes the copy equal to the checkout: the tracked and untracked
      # files that git does not ignore. It copies only the files whose size
      # or time changed, and deletes the files that the checkout no longer has.
      def sync!
        files, status = Open3.capture2("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", chdir: ROOT)
        fail!("git ls-files failed") unless status.success?
        wanted = files.split("\0").select { |f| File.file?(File.join(ROOT, f)) }
        wanted.each do |file|
          from = File.join(ROOT, file)
          to = File.join(TREE, file)
          next if File.exist?(to) && File.size(to) == File.size(from) && File.mtime(to) == File.mtime(from)

          FileUtils.mkdir_p(File.dirname(to))
          FileUtils.cp(from, to, preserve: true)
        end
        kept = wanted.to_set
        Dir.glob("**/*", File::FNM_DOTMATCH, base: TREE).each do |file|
          path = File.join(TREE, file)
          File.delete(path) if File.file?(path) && !kept.include?(file)
        end
      end

      # A table: one row for each phase, one column for each edit and program.
      def table(rows)
        labels = rows.values.flat_map(&:keys).uniq - [WHOLE, OTHER]
        labels += [OTHER, WHOLE]
        width = [labels.map(&:size).max, 8].max
        heads = rows.keys
        cols = heads.map { |h| [h.size, 7].max }
        lines = [format("%-#{width}s  %s", "", heads.each_with_index.map { |h, i| h.rjust(cols[i]) }.join("  "))]
        labels.each do |label|
          cells = rows.values.each_with_index.map { |p, i| (p.key?(label) ? format("%.2f", p[label]) : "-").rjust(cols[i]) }
          lines << format("%-#{width}s  %s", label, cells.join("  "))
        end
        lines.join("\n")
      end

      def write!(table, runs)
        FileUtils.mkdir_p(RESULTS)
        rev, = Open3.capture2("git", "rev-parse", "--short=8", "HEAD", chdir: ROOT)
        stamp = Time.now.utc.strftime("%Y%m%d-%H%M")
        path = File.join(RESULTS, "#{stamp}-#{rev.strip}.txt")
        File.write(path, "zr edit loop, the median of #{runs} run(s) at #{rev.strip}, #{Time.now.utc.strftime("%Y-%m-%d %H:%M")} UTC\n" \
                         "(seconds; each column is an edit kind and a program)\n\n#{table}\n")
        puts "wrote #{Dev.rel(path)}"
      end
    end
  end
end
