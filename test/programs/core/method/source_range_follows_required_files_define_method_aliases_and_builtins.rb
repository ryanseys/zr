# source_range of code in a required file has that file's real path. A
# method that define_method makes from a Method or an alias has the
# original def's range, one from a block has the block's, and a
# Method's Proc has its method's, also for a core method that ruby
# writes in Ruby. Struct and Data accessors, C methods and Symbol procs
# have none.
$stdout.sync = true
require_relative "source_range_lib/lib"
def show(label, x)
  r = x.source_range
  p [label, r && [File.basename(r.path), r.absolute_path && File.basename(r.absolute_path), r.start_line, r.start_column, r.end_line, r.end_column]]
end
show :lib_one, Lib.method(:one)
show :lib_block, Lib::BLOCK
p Lib.method(:one).source_range.absolute_path == File.realpath("source_range_lib/lib.rb", __dir__)
o = Object.new
def o.sing(a,
           b) = a
show :sing, o.method(:sing)
class C
  def orig = 1
  define_method(:via_m, instance_method(:orig))
  define_method(:via_p, proc { 2 })
  alias_method :al, :orig
  S = Struct.new(:a) do
    def extra = 3
  end
  D = Data.define(:b)
end
show :via_m, C.instance_method(:via_m)
show :via_p, C.instance_method(:via_p)
show :al, C.instance_method(:al)
show :struct_a, C::S.instance_method(:a)
show :struct_extra, C::S.instance_method(:extra)
show :data_b, C::D.instance_method(:b)
show :tap_proc, method(:tap).to_proc
show :then_alias, (Kernel.alias_method(:then2, :then); method(:then2))
show :cls_new, Class.new { def z = 1 }.instance_method(:z)
show :instance_exec, (proc { 1 }.tap { |pr| instance_exec(&pr) })
show :nested, proc { proc { 1 } }.call
show :bmethod_proc, C.new.method(:via_p).to_proc
show :unbound_bind, C.instance_method(:orig).bind(C.new)
show :module_function, (module MF; module_function; def mf = 1; end; MF.method(:mf))
show :mf_inst, MF.instance_method(:mf)
show :int_times, 3.method(:times)
show :int_times_um, Integer.instance_method(:times)
show :kernel_frozen, Kernel.instance_method(:frozen?)
show :array_each, [].method(:each)
show :hash_new, Hash.method(:new)
show :symproc, :to_s.to_proc
show :lambda_method, method(:lambda)
