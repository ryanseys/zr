# A scope that holds a block keeps its locals in an Env. It starts
# as an image in the frame, whose slots are the frame's own -- and
# every collection reads a frame as a root, so a store into them
# owes the collector nothing. The first keeper of the scope, here
# the `keep` lambda, moves the Env to a cell and points the image's
# slots at the cell's. From then on the frame writes the cell's
# slots through the image, and the barrier belongs to the cell: a
# minor collection reaches those slots through it alone, and stops
# at the cell once it is old.
#
# So this writes an outer local from the frame that owns it, after
# the scope has escaped. It allocates between the writes to make
# collections happen, and holds every value it read, so the heap
# grows and the Env cell ages. Handed the image, the barrier writes
# nothing down and the String is swept while the Env still holds it.
def run
  held = "start"
  keep = -> { held }
  seen = []
  200.times do |i|
    held = "fresh #{i} #{"x" * 40}"
    300.times { |j| "garbage #{i} #{j}" }
    seen << keep.call
  end
  seen
end

rows = run
p rows.size
p rows.all? { |s| s.start_with?("fresh ") }
p rows.last == "fresh 199 #{"x" * 40}"
