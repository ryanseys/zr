# IO.popen([env, cmd, ...]): a Hash at the start of the command Array is
# the child's environment, under the Hash given before the command. A
# command of one word after it runs with no shell.
p IO.popen([{ "A" => "1" }, "sh", "-c", "echo $A"], &:read)
p IO.popen([{ "A" => "2" }, "sh", "-c", "echo $A 1>&2", { err: [:child, :out] }], &:read)
p IO.popen({ "A" => "3" }, ["sh", "-c", "echo $A"], &:read)
p IO.popen({ "A" => "1", "B" => "b" }, [{ "A" => "2" }, "sh", "-c", "echo $A$B"], &:read)
p IO.popen([{ "A" => nil }, "sh", "-c", "echo [$A]"], &:read)
begin
  IO.popen([{ "A" => "2" }, "echo $A"], &:read)
rescue SystemCallError => e
  p e.class
end
begin
  IO.popen([{ "A" => "2" }], &:read)
rescue ArgumentError => e
  p e.message
end
