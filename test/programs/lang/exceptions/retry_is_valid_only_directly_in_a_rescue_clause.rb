# A retry is valid where the innermost rescue clause, ensure clause, block,
# lambda, for body or END around it is a rescue clause. Loops and plain
# begin blocks do not count. Elsewhere ruby's compiler raises SyntaxError.
def again
  tries = 0
  begin
    tries += 1
    raise "again" if tries < 3
  rescue
    yield
  end
  tries
end

tries = 0
begin
  tries += 1
  raise "x" if tries < 2
rescue
  while true
    retry
  end
end
p tries

tries = 0
begin
  tries += 1
  raise "x" if tries < 2
rescue
  begin
    retry
  end
end
p tries

tries = 0
begin
  begin
    tries += 1
    raise "x" if tries < 2
  rescue
    retry
  end
ensure
  p tries
end

tries = 0
value = [1].map do
  begin
    tries += 1
    raise "x" if tries < 3
    tries
  rescue
    retry
  end
end
p value

p(again { nil })

[
  "begin; rescue; [1].each { retry }; end",
  "begin; rescue; -> { retry }; end",
  "begin; rescue; for x in [1]; retry; end; end",
  "begin; rescue; begin; ensure; retry; end; end",
  "begin; ensure; retry; end",
  "begin; rescue; END { retry }; end",
  "begin; rescue; if false; [1].each { retry }; end; end; :dead_code_compiles",
].each do |code|
  p eval(code)
rescue SyntaxError => e
  puts e.message
end
