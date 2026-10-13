# ruby gives each ractor an object space of its own: ObjectSpace.each_object
# finds the objects of the calling ractor, and the shareable objects of the
# other live ractors, but never their unshareable ones. zr has one heap and
# does not record which ractor made an object, so each_object finds all of
# them: 19 here, where ruby finds 12 (test_ractor.rb
# test_each_object_own_all_and_foreign_shareables).
Warning[:experimental] = false
class Marker; end
main_un = Array.new(5) { Marker.new }
main_sh = Array.new(3) { Ractor.make_shareable(Marker.new) }
ready = Ractor::Port.new
child = Ractor.new(ready) do |ready_port|
  un = Array.new(7) { Marker.new }
  sh = Array.new(4) { Ractor.make_shareable(Marker.new) }
  ready_port << :built
  Ractor.receive
  [un.size, sh.size]
end
ready.receive
p ObjectSpace.each_object(Marker).count
child.send(:go)
p child.value
p [main_un.size, main_sh.size]
