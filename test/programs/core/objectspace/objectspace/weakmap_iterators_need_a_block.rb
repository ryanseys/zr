w = ObjectSpace::WeakMap.new
w["a"] = 1
%i[each each_pair each_key each_value].each do |m|
  w.public_send(m)
rescue LocalJumpError => e
  p [m, e.message]
end
