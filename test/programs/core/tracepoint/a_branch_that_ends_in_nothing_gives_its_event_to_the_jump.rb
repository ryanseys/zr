# When nothing uses a branch's value and its last statement starts a
# line but compiles to nothing (a plain value), CRuby gives that
# statement's :line event to the jump that ends the branch: on the
# `if` or `elsif` line when an `elsif` follows, on the `when` or `in`
# line for each body but the last, and for an `else`, on its first
# statement's line. TracePoint fires the line again, and line coverage
# counts it again.
require "coverage"
require "tmpdir"

SOURCES = {
  "if_elsif" => "def f(a)\n  if a\n    3\n  elsif a.nil?\n    4\n  end\n  nil\nend\n",
  "if_elsif_else" => "def f(a)\n  if a\n    3\n  elsif a.nil?\n    4\n  else\n    5\n  end\n  nil\nend\n",
  "if_else" => "def f(a)\n  if a\n    3\n  else\n    4\n  end\n  nil\nend\n",
  "elsif_chain" => "def f(a)\n  if a == 1\n    3\n  elsif a == 2\n    4\n  elsif a == 3\n    5\n  end\n  nil\nend\n",
  "statement_then_value" => "def f(a)\n  if a\n    b = 1\n    3\n  elsif a.nil?\n    4\n  end\n  nil\nend\n",
  "empty_body" => "def f(a)\n  if a\n  elsif a.nil?\n    4\n  end\n  nil\nend\n",
  "same_line" => "def f(a)\n  if a then 3 elsif a.nil? then 4 end\n  nil\nend\n",
  "used" => "def f(a)\n  x = if a\n    3\n  elsif a.nil?\n    4\n  end\n  x\nend\n",
  "case_when" => "def f(a)\n  case a\n  when 1\n    3\n  when 2\n    5\n  when nil\n    7\n  end\n  nil\nend\n",
  "case_else" => "def f(a)\n  case a\n  when 1\n    3\n  else\n    b = 1\n    7\n  end\n  nil\nend\n",
  "case_no_subject" => "def f(a)\n  case\n  when a == 1\n    3\n  when a == 2\n    5\n  else\n    7\n  end\n  nil\nend\n",
  "case_in" => "def f(a)\n  case a\n  in 1\n    3\n  in 2\n    5\n  else\n    7\n  end\n  nil\nend\n",
  "rescued_body" => "def f(a)\n  begin\n    a.to_s\n    :kept\n  rescue\n    nil\n  end\n  nil\nend\n",
  "begin_block" => "def f(a)\n  if a\n    begin\n      3\n    end\n  elsif a.nil?\n    4\n  end\n  nil\nend\n",
}.freeze

Dir.mktmpdir do |dir|
  Coverage.start(lines: true)
  SOURCES.each do |name, source|
    path = File.join(dir, "#{name}.rb")
    File.write(path, source.sub("def f", "def #{name}"))
    require path
  end
  SOURCES.each_key do |name|
    lines = [1, 2, 3, nil].map do |arg|
      seen = []
      TracePoint.new(:line) { |tp| seen << tp.lineno if tp.path.end_with?("/#{name}.rb") }.enable { send(name, arg) }
      seen
    end
    puts "#{name}: #{lines.inspect}"
  end
  result = Coverage.result
  SOURCES.each_key { |name| puts "#{name}: #{result.fetch(File.join(dir, "#{name}.rb"))[:lines].inspect}" }
end
