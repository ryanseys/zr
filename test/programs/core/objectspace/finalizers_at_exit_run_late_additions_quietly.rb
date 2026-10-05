obj = +"Test"
handler = Proc.new do
  obj2 = +"Test"
  ObjectSpace.define_finalizer(obj2, Proc.new { puts "finalizer 2 run" })
  exit 0
end
ObjectSpace.define_finalizer(obj, handler)
$VERBOSE = nil
ObjectSpace.define_finalizer(Object.new) { raise "finalizing" }
exit 0
