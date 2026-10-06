# A spawn's leading environment and trailing options may be any value
# with to_hash, but a String or an Array argument is never asked for one.
class Array
  def to_hash = raise("Array#to_hash is called")
end

class String
  def to_hash = raise("String#to_hash is called")
end

class Env
  def to_hash = { "SPAWN_ARG" => "env" }
end

class Opts
  def to_hash = { out: File::NULL }
end

p system(["true", "true"])
p system("true")
p system("echo", "quiet", Opts.new)
p IO.popen([Env.new, "sh", "-c", "echo $SPAWN_ARG"], &:read)
pid = spawn(Env.new, "sh", "-c", "test \"$SPAWN_ARG\" = env", Opts.new)
Process.wait(pid)
p $?.success?
p(begin
  system(Env.new, Opts.new)
rescue ArgumentError, TypeError => e
  e.class
end)
