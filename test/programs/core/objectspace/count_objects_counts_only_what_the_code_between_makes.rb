# ObjectSpace.count_objects makes no object while it counts, so two
# counts around a call count only what the call made. The keys a Hash
# already has count 0 before the counts go in.
$counts = {}
def arrays_made
  ObjectSpace.count_objects($counts)
  before = $counts[:T_ARRAY]
  yield
  ObjectSpace.count_objects($counts)
  $counts[:T_ARRAY] - before
end
def none = nil
GC.disable
p arrays_made { none }
p arrays_made { [1, 2] }
GC.enable
h = { T_FOO: 1000 }
p ObjectSpace.count_objects(h).equal?(h), h[:T_FOO]
p ObjectSpace.count_objects.keys.first(2)
p((ObjectSpace.count_objects(1) rescue $!.class))
