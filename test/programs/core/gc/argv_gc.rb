
# The ARGV strings stay alive across collections. The program reads
# ARGV[i], makes many objects so that the collector runs, and then
# reads ARGV[i] again. The harness passes five short args, so ARGV
# is not empty.

class Trash
  def initialize(n)
    @n = n
    @s = "padding payload " * 64    # ~1 KB heap string per Trash
  end
  attr_reader :n
end

# Allocate ~5000 Trash instances (~5 MB) to make the collector run.
junk = []
j = 0
while j < 5000
  junk << Trash.new(j)
  j = j + 1
end
puts junk.length     # 5000

# Read ARGV[i] and its length after GC.
i = 0
while i < ARGV.length
  puts ARGV[i] + ":" + ARGV[i].length.to_s
  i = i + 1
end
