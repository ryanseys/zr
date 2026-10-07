# An `ensure` body whose statements compile to nothing (plain values)
# leaves its :line event to the next instruction. CRuby compiles the
# body once per path: on a raise the event goes to the `ensure` line; on
# the normal exit to what follows, which is the next statement, the
# write of `x = begin`, or the `end` of a method, block or class body. A
# jump that throws (a block's `break` or `return`) takes the raise path.
# A local jump (`return` in a method, `break` in a loop) gives the event
# to its own instruction, and a block's `next` to the block's `end`. Line
# coverage counts each.
require "coverage"
require "tmpdir"

SOURCES = {
  "method" => "def f(a)\n  raise if a\n  1.to_s\nensure\n  nil\nend\n",
  "block" => "def f(a)\n  [1].map do |w|\n    raise if a\n    w.to_s\n  ensure\n    nil\n  end\nend\n",
  "statement_after" => "def f(a)\n  begin\n    raise if a\n  ensure\n    nil\n  end\n  2.to_s\nend\n",
  "written" => "def f(a)\n  x = begin\n    raise if a\n    1\n  ensure\n    nil\n    :b\n  end\n  x\nend\n",
  "rescued" => "def f(a)\n  raise if a\nrescue\n  2\nensure\n  nil\nend\n",
  "jump" => "def f(a)\n  [1].each do\n    begin\n      return 1 if a\n      break\n    ensure\n      nil\n    end\n  end\n  3\nend\n",
  "local_return" => "def f(a)\n  begin\n    return 1 if a\n    2.to_s\n  ensure\n    nil\n  end\n  3\nend\n",
  "loop_break" => "def f(a)\n  while true\n    begin\n      break if a\n      break\n    ensure\n      nil\n    end\n  end\n  3\nend\n",
  "block_next" => "def f(a)\n  [1, 2].each do |i|\n    begin\n      next if a\n      i.to_s\n    ensure\n      nil\n    end\n  end\nend\n",
  "with_code" => "def f(a)\n  raise if a\nensure\n  nil\n  1.to_s\nend\n",
  "lambda" => "def f(a)\n  -> do\n    raise if a\n  ensure\n    nil\n  end.call\nend\n",
}.freeze

Dir.mktmpdir do |dir|
  Coverage.start(lines: true)
  SOURCES.each do |name, source|
    path = File.join(dir, "#{name}.rb")
    File.write(path, source.sub("def f", "def #{name}"))
    require path
  end
  SOURCES.each_key do |name|
    lines = [false, true].map do |arg|
      seen = []
      TracePoint.new(:line) { |tp| seen << tp.lineno if tp.path.end_with?("/#{name}.rb") }.enable do
        send(name, arg)
      rescue RuntimeError
        seen << :raised
      end
      seen
    end
    puts "#{name}: #{lines.inspect}"
  end
  result = Coverage.result
  SOURCES.each_key { |name| puts "#{name}: #{result.fetch(File.join(dir, "#{name}.rb"))[:lines].inspect}" }
end
