# The Ruby Onigmo against ruby's own engine, in one process: the core
# compiles each pattern under this ruby, the kernel matcher searches
# JIT-loaded, and Regexp on the same subject is the oracle for the
# compile error, the warnings, the position and every capture's byte
# offsets (test/support/harness/regexp_diff.rb).
#
#   ruby tools/regexp_diff.rb --fuzz 3000 [--seed 1]
#   ruby tools/regexp_diff.rb --encodings 3000 [--seed 1]
#   ruby tools/regexp_diff.rb --harvest [--roots test,spec,ruby] [--limit 20000]
#   ruby tools/regexp_diff.rb --cases test/regexp/diff_sample.jsonl
#   ruby tools/regexp_diff.rb --harvest --fuzz 2000 --sample 2000 --out test/regexp/diff_sample.jsonl
#
# `--show N` prints the first N divergences (default 20); `--bench`
# adds the 20 worst kernel/ruby time ratios; `--patterns` prints the
# distinct patterns as they are met. The exit status is the number of
# divergences, capped at 255.
$LOAD_PATH.unshift File.expand_path("../lib", __dir__), File.expand_path("../test/support", __dir__)
require "harness/regexp_diff"

ROOT = File.expand_path("..", __dir__)
ROOTS = {
  "test" => File.join(ROOT, "test"),
  "rt" => File.join(ROOT, "rt"),
  "lib" => File.join(ROOT, "lib"),
  "spec" => File.expand_path("~/dev/spec"),
  "ruby" => File.expand_path("~/dev/github.com/ruby/ruby/test/ruby/test_regexp.rb"),
}.freeze

options = { show: 20, seed: 1, fuzz: 0, encodings: 0, roots: %w[test], limit: 200_000 }
cases = []
argv = ARGV.dup
until argv.empty?
  word = argv.shift
  case word
  when "--fuzz" then options[:fuzz] = Integer(argv.shift)
  when "--encodings" then options[:encodings] = Integer(argv.shift)
  when "--seed" then options[:seed] = Integer(argv.shift)
  when "--harvest" then options[:harvest] = true
  when "--roots" then options[:roots] = argv.shift.split(",")
  when "--limit" then options[:limit] = Integer(argv.shift)
  when "--cases" then cases.concat(Ze0::Harness::RegexpDiff.read_jsonl(argv.shift))
  when "--sample" then options[:sample] = Integer(argv.shift)
  when "--out" then options[:out] = argv.shift
  when "--show" then options[:show] = Integer(argv.shift)
  when "--bench" then options[:bench] = true
  when "--patterns" then options[:patterns] = true
  else abort "regexp_diff: what is #{word}?"
  end
end

diff = Ze0::Harness::RegexpDiff
if options[:harvest]
  files = options[:roots].flat_map do |name|
    root = ROOTS.fetch(name) { abort "regexp_diff: no root #{name}; #{ROOTS.keys.join(", ")}" }
    File.file?(root) ? [root] : Dir[File.join(root, "**/*.rb")].sort
  end
  patterns = {}
  subjects_by_pattern = Hash.new { |h, k| h[k] = [] }
  files.each do |path|
    found, subjects = diff.harvest_file(path)
    found.each do |pattern, opts|
      patterns[[pattern, opts]] = true
      subjects_by_pattern[[pattern, opts]].concat(subjects)
    end
  end
  warn "harvested #{patterns.size} patterns from #{files.size} files"
  patterns.each_key { |pattern, opts| cases.concat(diff.cases_for(pattern, opts, subjects_by_pattern[[pattern, opts]].uniq.first(8))) }
end
cases.concat(diff::Fuzz.new(options[:seed]).cases(options[:fuzz])) if options[:fuzz] > 0
cases.concat(diff::EncodingFuzz.new(options[:seed]).cases(options[:encodings])) if options[:encodings] > 0
cases = cases.first(options[:limit])
if options[:sample]
  # As many patterns as the sample holds cases, then more cases of them.
  shuffled = cases.shuffle(random: Random.new(options[:seed]))
  distinct = shuffled.uniq { |c| [c.pattern.b, c.pattern.encoding, c.options] }
  cases = (distinct + (shuffled - distinct)).first(options[:sample])
  if options[:out]
    diff.write_jsonl(options[:out], cases)
    warn "wrote #{cases.size} cases to #{options[:out]}"
  end
end
abort "regexp_diff: no cases; --fuzz N, --encodings N, --harvest or --cases FILE" if cases.empty?

Regexp.timeout = 2.0
runner = diff::Runner.new(bench: options[:bench])
shown = 0
seen_patterns = {}
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cases.each do |kase|
  if options[:patterns] && !seen_patterns[kase.pattern]
    seen_patterns[kase.pattern] = true
    puts "pattern /#{kase.pattern}/ o=#{kase.options}"
  end
  d = runner.run(kase)
  next unless d && shown < options[:show]

  shown += 1
  puts d
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
if options[:bench]
  worst = runner.timings.reject { |k, r, _| r < 20_000 }.sort_by { |k, r, _| -(k.to_f / r) }.first(20)
  puts "worst kernel/ruby time ratios (kernel ns, ruby ns):"
  worst.each { |k, r, kase| puts format("  %6.1fx %9d %9d  %s", k.to_f / r, k, r, kase.label) }
  total_k = runner.timings.sum { |k, _, _| k }
  total_r = runner.timings.sum { |_, r, _| r }
  puts format("total kernel %.3fs, ruby %.3fs, ratio %.2fx", total_k / 1e9, total_r / 1e9, total_k.to_f / total_r)
end
runner.slow.each { |kase, ns| puts format("SLOW %s (ruby %.2fs; the kernel ran past the limit)", kase.label, ns / 1e9) }
puts "#{runner.count} cases, #{runner.divergences.size} divergences, #{runner.slow.size} slow, #{elapsed.round(1)}s"
exit [runner.divergences.size, 255].min
