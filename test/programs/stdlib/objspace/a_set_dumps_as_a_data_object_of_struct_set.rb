# ObjectSpace.dump of a Set: in ruby 4.1 a Set is a T_DATA whose type is
# "set" and does not free at once. A subclass's Set, a frozen one and a
# shareable one are the same, and the counts that group the objects by
# type count each Set as a T_DATA. The objects that a Set reaches are
# its class and its elements that are not special constants.
require "objspace"
class MySet < Set; end
sets = [Set.new, Set[1, 2, 3], MySet.new([1]), Set[1].freeze, Ractor.make_shareable(Set["a"]), Set.new.compare_by_identity]
sets.each do |set|
  dump = ObjectSpace.dump(set)
  p [set.class, dump[/"type":"[A-Z]+"/], dump[/"struct":"[^"]*"/], dump[/"free_immediately":\w+/], dump.include?('"frozen":true')]
end
p ObjectSpace.dump(Set[Object.new]).include?('"references":["0x')
p ObjectSpace.count_tdata_objects.key?(Set)
p ObjectSpace.count_tdata_objects.fetch(MySet, 0) >= 1
p ObjectSpace.count_objects_size.key?(:T_DATA)
p ObjectSpace.reachable_objects_from(Set[[1]]).any?(Array)
p ObjectSpace.reachable_objects_from(Set[[1], "a", 2, :b, nil])
p ObjectSpace.reachable_objects_from(Set.new)
p ObjectSpace.reachable_objects_from(MySet[1.5, 2**70])
p ObjectSpace.reachable_objects_from(Set[[3]].compare_by_identity)
