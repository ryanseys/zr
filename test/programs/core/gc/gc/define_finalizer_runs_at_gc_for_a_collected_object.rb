def register = ObjectSpace.define_finalizer(Object.new, proc { |id| puts "collected" })
register
GC.start
puts "after gc"
