# A `&blk` param on a per-object singleton binds to the method's call-site
# block, or nil when no block is passed.

obj = Object.new
def obj.wrap(&blk)
  blk.nil? ? "no block" : blk.call(41) + 1
end
puts obj.wrap { |n| n }
puts obj.wrap
