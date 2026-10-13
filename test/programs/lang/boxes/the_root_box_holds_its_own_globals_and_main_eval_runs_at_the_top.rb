# Ruby::Box.root keeps globals, $LOADED_FEATURES and constants of its own,
# as a box from Ruby::Box.new does: a write there leaves main's alone.
# Ruby::Box.main is the program: its eval runs at the top level.
p Ruby::Box.root.root?, Ruby::Box.main.main?, Ruby::Box.main == Ruby::Box.current
$a = 1
$LOADED_FEATURES.push("/tmp/foobar")
p Ruby::Box.root.eval('$a = 2; $a')
p Ruby::Box.root.eval('$LOADED_FEATURES.push("/tmp/barbaz"); $LOADED_FEATURES').include?("/tmp/foobar")
p Ruby::Box.root.eval('class FooClass; end; Object.const_get(:FooClass).to_s')
p $a, $LOADED_FEATURES.include?("/tmp/barbaz"), Object.const_defined?(:FooClass)
p Ruby::Box.root.eval("$a"), Ruby::Box.root.equal?(Ruby::Box.root), Ruby::Box.root.inspect
$z = 5
p Ruby::Box.main.eval("$z + 1"), Ruby::Box.main.eval("$z = 7"), $z
b = Ruby::Box.new
p b.eval("$a = 3; $a"), $a, Ruby::Box.root.eval("$a")
