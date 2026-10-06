# File.basename returns a String that stays valid after the GC frees
# the input path.
#
# The test needs:
#  - A path constructed dynamically (heap string, not literal).
#  - A basename returned from a helper, so the path goes out of scope.
#  - GC pressure that actually runs a collection, so the GC reaps the
#    unreferenced path. String allocations alone may not reach the GC
#    threshold, so the test also allocates objects.

class Trash
  def initialize(n)
    @n = n
    @s = "padding payload " * 64    # ~1 KB heap string per Trash
  end
  attr_reader :n
end

def name_of(i)
  path = "/very/deep/parent/directory/with/many/segments/file" + i.to_s + ".rb"
  File.basename(path)
end

names = []
i = 0
while i < 50
  names << name_of(i)
  i = i + 1
end

# Allocate ~5000 Trash instances (~5 MB) — far past the GC threshold —
# to force multiple collections and reap the unreferenced path strings.
junk = []
j = 0
while j < 5000
  junk << Trash.new(j)
  j = j + 1
end
puts junk.length     # 5000

# Each names[i] should still resolve to "fileN.rb".
ok = 1
i = 0
while i < 50
  expected = "file" + i.to_s + ".rb"
  if names[i] != expected
    ok = 0
  end
  i = i + 1
end
puts(ok == 1 ? "ok" : "corrupt")    # ok
