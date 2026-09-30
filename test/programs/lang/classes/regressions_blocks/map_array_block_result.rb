# `arr.map { array_block }` — the block returns an Integer Array
# (`(0..i).to_a` here). The result is an Array of Arrays, and the GC
# keeps each inner Array alive.

class T_map_array_block_result_C
  def initialize
    @rows = [1, 6].map { |i| (0..i).to_a }
  end

  def show
    @rows.each do |row|
      row.each { |x| print x, " " }
      puts
    end
  end
end

T_map_array_block_result_C.new.show
