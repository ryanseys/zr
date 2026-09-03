#!/usr/bin/env ruby
# frozen_string_literal: true

# The numbers ze0/README.md records, taken again:
#
#   ruby ze0/measure.rb [path/to/zeo]
#
# For every corpus program and three generated ones, the front-end time of
# the Rust emitter (`zeo-timings`), of ze0 under the JIT (cold and warm) and
# of stage 1, `zeo backend` alone, and the text each front end writes. Each
# timing is the best of three.

require "tmpdir"

ROOT = File.expand_path("..", __dir__)
ZEO = ARGV[0] || File.join(ROOT, "target/release/zeo")
CORPUS = Dir[File.join(ROOT, "test/ze0/*.rb")].sort

def best_of(n = 3)
  (1..n).map do
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  end.min
end

def run(*cmd, env: {}, chdir: nil)
  out = IO.popen(env, cmd, chdir: chdir, err: [:child, :out], &:read)
  raise "#{cmd.join(" ")} failed:\n#{out}" unless $?.success?

  out
end

# A program of about `lines` lines in the subset: defs, loops, arithmetic
# and prints, so the front ends have real work in proportion.
def generated(lines)
  out = +""
  i = 0
  while out.lines.size < lines
    out << <<~RUBY
      def f#{i}(a, b)
        c = a * #{i + 1} + b
        if c > 100
          c - 100
        else
          c + #{i}
        end
      end
      x#{i} = 0
      while x#{i} < 3
        x#{i} = x#{i} + 1
      end
      puts f#{i}(x#{i}, #{i})
    RUBY
    i += 1
  end
  out
end

Dir.mktmpdir("ze0-measure") do |dir|
  stage1 = File.join(dir, "ze0")
  run(ZEO, "build", "ze0/ze0.rb", "-o", stage1, chdir: ROOT)
  ze0 = File.join(ROOT, "ze0/ze0.rb")
  programs = CORPUS.map { |p| [File.basename(p, ".rb"), File.read(p)] }
  [50, 200, 500].each { |n| programs << ["generated_#{n}", generated(n)] }

  puts "| program | lines | rust front end ms | ze0 jit cold ms | ze0 jit warm ms | ze0 stage1 ms | backend ms | emitter text bytes | ze0 text bytes |"
  puts "|---|---:|---:|---:|---:|---:|---:|---:|---:|"
  programs.each do |name, source|
    rb = File.join(dir, "#{name}.rb")
    File.write(rb, source)
    timings = run(ZEO, "--emit-clif=/dev/null", "#{name}.rb", env: { "ZEO_TIMINGS" => "1", "ZEO_CACHE" => "0" }, chdir: dir)
    front = timings[/parse_lower=(\d+)ms analyze=(\d+)ms/] ? Regexp.last_match(1).to_i + Regexp.last_match(2).to_i : -1
    emitter_text = run(ZEO, "--emit-clif", "#{name}.rb", env: { "ZEO_DEBUG" => "outline-frames", "ZEO_CACHE" => "0" }, chdir: dir).bytesize
    jit_cold = best_of(1) { run(ZEO, ze0, "#{name}.rb", "-o", "#{name}.clif", env: { "ZEO_CACHE" => "0" }, chdir: dir) }
    jit_warm = best_of { run(ZEO, ze0, "#{name}.rb", "-o", "#{name}.clif", chdir: dir) }
    native = best_of { run(stage1, "#{name}.rb", "-o", "#{name}.clif", chdir: dir) }
    backend = best_of { run(ZEO, "backend", "#{name}.clif", "-o", "#{name}.bin", chdir: dir) }
    ze0_text = File.size(File.join(dir, "#{name}.clif"))
    # The recorded answer under `__END__` is not program text.
    lines = source.split(/^__END__$/, 2).first.lines.size
    puts "| #{name} | #{lines} | #{front} | #{(jit_cold * 1000).round} | #{(jit_warm * 1000).round} | " \
         "#{(native * 1000).round} | #{(backend * 1000).round} | #{emitter_text} | #{ze0_text} |"
  end
end
