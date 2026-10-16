require "objspace"
require "json"

# objspace.c reads each object's struct. Not one of these methods may run
# while a dump looks at the objects that define them.
module Trap
  def self.ran(name) = raise("#{name} ran")
end

class Equalish
  def ==(_) = Trap.ran(:==)
  def is_a?(_) = Trap.ran(:is_a?)
  def kind_of?(_) = Trap.ran(:kind_of?)
  def frozen? = Trap.ran(:frozen?)
  def instance_variables = Trap.ran(:instance_variables)
  def class = Trap.ran(:class)
  def initialize = @a = 1
end

module Named
  def self.name = Trap.ran(:name)
  def self.singleton_class? = Trap.ran(:singleton_class?)
end

module Functions
  module_function

  def name = Trap.ran(:module_function_name)
end

class Classy
  def self.superclass = Trap.ran(:superclass)
  def self.name = Trap.ran(:class_name)
end

class Sized < Hash
  def size = Trap.ran(:hash_size)
  def default_proc = Trap.ran(:default_proc)
end

class Listed < Array
  def size = Trap.ran(:array_size)
end

class Texty < String
  def bytesize = Trap.ran(:bytesize)
  def encoding = Trap.ran(:encoding)
  def empty? = Trap.ran(:empty?)
  def ascii_only? = Trap.ran(:ascii_only?)
end

class Piped < IO
  def fileno = Trap.ran(:fileno)
  def closed? = Trap.ran(:closed?)
end

def fields(obj)
  JSON.parse(ObjectSpace.dump(obj)).reject { |key, _| %w[address class superclass references file line method generation memsize flags shape_id slot_size default embedded].include?(key) }
end

def t(label)
  puts "#{label}: #{yield.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end

reader, writer = IO.pipe
piped = Piped.for_fd(reader.fileno, autoclose: false)

t(:object) { fields(Equalish.new) }
t(:named_module) { fields(Named) }
t(:module_function) { fields(Functions) }
t(:class) { fields(Classy).slice("type", "variation_count") }
t(:hash_subclass) { fields(Sized.new { 1 }.merge!(a: 1)).slice("type", "size") }
t(:array_subclass) { fields(Listed.new([1, 2, 3])) }
t(:string_subclass) { fields(Texty.new("abc")).slice("type", "bytesize", "value", "encoding", "coderange") }
t(:io_subclass) { fields(piped).slice("type", "fd") == { "type" => "FILE", "fd" => reader.fileno } }
t(:basic_object) { fields(BasicObject.new).slice("type", "ivars") }
t(:singleton_of_named) { fields(Named.singleton_class).slice("type", "singleton", "real_class_name") }

# The whole heap, with every one of these objects in it.
keep = [Equalish.new, Sized.new, Listed.new, Texty.new("x"), BasicObject.new, piped]
t(:dump_all) { ObjectSpace.dump_all(output: :string).lines.size > 100 }
t(:count_objects_size) { ObjectSpace.count_objects_size.key?(:TOTAL) }
t(:count_tdata_objects) { ObjectSpace.count_tdata_objects.is_a?(Hash) }
t(:memsize_of_all) { ObjectSpace.memsize_of_all(Equalish).positive? }
t(:reachable) { ObjectSpace.reachable_objects_from(keep).size }
t(:not_a_module) { ObjectSpace.memsize_of_all(Equalish.new) }
t(:not_a_hash) { ObjectSpace.count_objects_size(Equalish.new) }
writer.close
reader.close
