class C
  define_method(:dm) { __method__ }
  define_method(:nest) { [1].map { __method__ }.first }
  define_method(:callee) { __callee__ }
  define_method(:again, instance_method(:dm))
  pr = proc { __method__ }
  define_method(:from_proc, &pr)
  alias_method :dm_alias, :dm
end
o = C.new
o.define_singleton_method(:single) { __method__ }
p o.dm, o.nest, o.callee, o.again, o.from_proc, o.dm_alias, o.single
p o.method(:dm).to_proc.call
p proc { __method__ }.call
