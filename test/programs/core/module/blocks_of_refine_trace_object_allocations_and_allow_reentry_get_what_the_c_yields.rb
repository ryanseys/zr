# rb_yield_refine_block yields no value; ObjectSpace.trace_object_allocations
# and TracePoint.allow_reentry run the block with rb_ensure(rb_yield, Qnil),
# so it gets nil.
require "objspace"
got = []
Module.new { refine(Integer) { |*a| got << [:refine, a, self.class] } }
got << [:allocations, ObjectSpace.trace_object_allocations { |*a| a }]
got << [:allocations_value, ObjectSpace.trace_object_allocations { 1r }]
tp = TracePoint.new(:script_compiled) { got << [:reentry, TracePoint.allow_reentry { |*a| a }] }
tp.enable
eval("1")
tp.disable
got << [:reentry_lambda, (TracePoint.allow_reentry(&->(x) { x }) rescue $!.class)]
got.each { p it }
