# A command whose first word holds an `=` is an assignment, and only a
# shell can do that, so the command goes through /bin/sh. Beside it:
# Kernel carries select as a private method and as a module function,
# and $LOAD_PATH tells where a require of a name would read from.
require "tmpdir"

def t = yield rescue [$!.class, $!.message]

p system("FOO=1 true")
p system("FOO=1 false")
p system("true")

p Kernel.private_instance_methods.include?(:select)
p Kernel.instance_method(:select).parameters
p Kernel.select([], [], [], 0)
p select([], [], [], 0)

Dir.mktmpdir do |dir|
  File.write(File.join(dir, "thing.rb"), "")
  Dir.mkdir(File.join(dir, "sub"))
  File.write(File.join(dir, "sub", "deep.rb"), "")
  $LOAD_PATH.unshift(dir)
  kind, path = $LOAD_PATH.resolve_feature_path("thing")
  p kind, path == File.realpath(File.join(dir, "thing.rb"))
  p $LOAD_PATH.resolve_feature_path("thing.rb").first
  p $LOAD_PATH.resolve_feature_path("sub/deep").first
  p $LOAD_PATH.resolve_feature_path("nope")
  p t { $LOAD_PATH.resolve_feature_path(:thing) }
  p $LOAD_PATH.singleton_methods
  $LOAD_PATH.shift
end

