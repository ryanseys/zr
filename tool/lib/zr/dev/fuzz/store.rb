# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

module Zr
  module Dev
    module Fuzz
      # What the fuzzer keeps, below `log/fuzz` (which a clear of tmp/
      # keeps):
      #
      #   issues/<run>.jsonl         one line for each failure that a run logged
      #   buckets.json               each bucket: count, cases, smallest case, status
      #   cases/<bucket>/<id>.rb     a case, with .rb.expected, .err.expected, .orig.rb, .diff, .json
      #   corpus/<digest>.rb         programs that ran compiler lines that no other did
      #   coverage.json              the compiler lines that the runs ran
      #   runs/<run>.log             the live log of a run (tail -f)
      #   runs/summary.tsv           one row for each run
      #
      # Every method is safe to call from many threads.
      class Store
        ROOT = Dev.path("log/fuzz")

        attr_reader :root, :run

        def initialize(root: ROOT, run: nil)
          @root = root
          @run = run || "#{Time.now.strftime("%Y%m%d-%H%M%S")}-#{Process.pid}"
          @lock = Mutex.new
          @buckets = nil
        end

        def path(*parts) = File.join(@root, *parts)

        def issues_path = path("issues", "#{@run}.jsonl")
        def log_path = path("runs", "#{@run}.log")

        # A line in the run's live log.
        def log(line)
          @lock.synchronize do
            FileUtils.mkdir_p(path("runs"))
            File.open(log_path, "a") { |io| io.puts("#{Time.now.strftime("%H:%M:%S")} #{line}") }
          end
        end

        # { bucket => record }. A record has "kind", "key", "count",
        # "first", "last", "cases" (ids), "smallest" (a path below the
        # root, and its size), "status" ("open", "fixed@<rev>" or
        # "known: <why>"), "layer" and "features".
        def buckets
          @lock.synchronize { load_buckets.transform_values(&:dup) }
        end

        # Counts one more failure in `bucket`. Returns true when the bucket
        # is new to this store. `first` is the first bucket (from the
        # verdict alone, before a reduction) that led to `bucket`.
        def count(bucket, verdict, known: nil, first: nil)
          @lock.synchronize do
            all = load_buckets
            fresh = !all.key?(bucket)
            record = all[bucket] ||= { "kind" => verdict.kind, "key" => verdict.key, "count" => 0, "first" => now,
                                       "cases" => [], "status" => known ? "known: #{known}" : "open" }
            record["count"] += 1
            record["last"] = now
            record["firsts"] = (record["firsts"].to_a | [first]) if first
            save_buckets(all)
            fresh
          end
        end

        # The bucket that a reduction of a failure in the first bucket
        # `first` led to, or nil.
        def bucket_of(first)
          @lock.synchronize do
            load_buckets.find { |name, record| name == first || record["firsts"].to_a.include?(first) }&.first
          end
        end

        # Writes a case of `bucket`, and logs it in the run's issues. `id`
        # names the case. `source` is the program that the case keeps (the
        # reduced one when there is one), `original` the one that the
        # fuzzer found. `meta` goes into the issue line and the .json.
        def add_case(bucket, id, result, source:, original: nil, meta: {})
          dir = path("cases", bucket)
          FileUtils.mkdir_p(dir)
          base = File.join(dir, id)
          File.binwrite("#{base}.rb", source)
          File.binwrite("#{base}.orig.rb", original) if original && original != source
          if result.ruby&.code.is_a?(Integer)
            File.binwrite("#{base}.rb.expected", result.ruby.stdout)
            File.binwrite("#{base}.rb.err.expected", result.ruby.stderr) unless result.ruby.stderr.empty?
          end
          File.binwrite("#{base}.diff", Store.diff(result))
          File.write("#{base}.json", JSON.pretty_generate(meta.merge(answers(result))))
          rel = Dev.rel("#{base}.rb")
          line = meta.merge(id: id, bucket: bucket, verdict: result.verdict.to_h, case: rel, size: source.bytesize, time: now)
          @lock.synchronize do
            FileUtils.mkdir_p(path("issues"))
            File.open(issues_path, "a") { |io| io.puts(JSON.generate(line)) }
            all = load_buckets
            record = all[bucket]
            if record
              record["cases"] = (record["cases"] + [id]).last(20)
              small = record["smallest"]
              record["smallest"] = { "path" => rel, "size" => source.bytesize } if small.nil? || source.bytesize < small["size"]
              %w[layer features].each { |k| record[k] ||= meta[k.to_sym] if meta[k.to_sym] }
              save_buckets(all)
            end
          end
          rel
        end

        # Marks `bucket` with `status`.
        def mark(bucket, status)
          @lock.synchronize do
            all = load_buckets
            next unless all[bucket]

            all[bucket]["status"] = status
            save_buckets(all)
          end
        end

        # The last line of the run's issues, and a row of the summary.
        def finish(stats)
          @lock.synchronize do
            FileUtils.mkdir_p(path("issues"))
            File.open(issues_path, "a") { |io| io.puts(JSON.generate({ done: true, run: @run }.merge(stats))) }
            summary = path("runs", "summary.tsv")
            FileUtils.mkdir_p(File.dirname(summary))
            header = %w[run programs valid same failures new_buckets seconds per_second coverage]
            File.write(summary, "#{header.join("\t")}\n") unless File.file?(summary)
            File.open(summary, "a") { |io| io.puts([@run, *header.drop(1).map { |k| stats[k.to_sym] }].join("\t")) }
          end
        end

        # The global coverage: a Set of "file:line".
        def coverage
          @lock.synchronize do
            @coverage ||= File.file?(path("coverage.json")) ? Set.new(JSON.parse(File.read(path("coverage.json")))) : Set.new
          end
        end

        # Adds `lines` to the coverage. Returns the lines that are new.
        def cover(lines)
          set = coverage
          @lock.synchronize do
            fresh = lines.reject { |line| set.include?(line) }
            fresh.each { |line| set << line }
            fresh
          end
        end

        def save_coverage
          @lock.synchronize do
            next unless @coverage

            FileUtils.mkdir_p(@root)
            write_atomic(path("coverage.json"), JSON.generate(@coverage.to_a.sort))
          end
        end

        # Keeps `source` in the corpus. Returns its path.
        def keep(source)
          dir = path("corpus")
          FileUtils.mkdir_p(dir)
          file = File.join(dir, "#{Digest::SHA256.hexdigest(source)[0, 16]}.rb")
          File.binwrite(file, source) unless File.file?(file)
          file
        end

        # The parts of the two answers that differ, as unified diffs, or the
        # stderr of a build that failed.
        def self.diff(result)
          want, got = result.ruby, result.zr
          return result.build ? "--- build\n#{result.build.stderr}" : "" unless want && got

          %i[stdout stderr].filter_map do |part|
            a, b = want.public_send(part), got.public_send(part)
            "--- #{part} (ruby, then zr)\n#{Zr::Diff.unified(a.to_s, b.to_s)}" unless a == b
          end.push("--- status: ruby #{Classify.status(want)}, zr #{Classify.status(got)}").join("\n")
        end

        private

        def now = Time.now.utc.iso8601

        def load_buckets
          @buckets ||= File.file?(path("buckets.json")) ? JSON.parse(File.read(path("buckets.json"))) : {}
        end

        def save_buckets(all)
          FileUtils.mkdir_p(@root)
          write_atomic(path("buckets.json"), JSON.pretty_generate(all.sort.to_h))
        end

        def write_atomic(file, text)
          draft = "#{file}.#{Process.pid}.#{Thread.current.object_id}"
          File.write(draft, text)
          File.rename(draft, file)
        end

        def answers(result)
          side = ->(a) { a && { stdout: Classify.text(a.stdout), stderr: Classify.text(a.stderr), code: a.code, signal: a.signal } }
          { ruby: side.call(result.ruby), zr: side.call(result.zr),
            build: result.build && { status: result.build.status, signal: result.build.signal, timeout: result.build.timeout,
                                     stderr: Classify.text(result.build.stderr), seconds: result.build.seconds } }
        end
      end
    end
  end
end
