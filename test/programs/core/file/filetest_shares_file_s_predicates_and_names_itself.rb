# FileTest's predicates are File's own code, defined again on FileTest
# as define_filetest_function does: FileTest.exist? and a private
# instance method for a class that includes FileTest. They give File's
# answers, check their arguments as File's do, and a frame says
# 'FileTest.exist?' or 'FileTest#exist?'.
NAMES = %i[blockdev? chardev? directory? empty? executable? executable_real? exist? file? grpowned?
           identical? owned? pipe? readable? readable_real? setgid? setuid? size size? socket? sticky?
           symlink? world_readable? world_writable? writable? writable_real? zero?].freeze

class Holder
  include FileTest

  def ask(name, *args) = send(name, *args)
end

def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message} (#{e.backtrace_locations.first.label})"
end

def args_for(name, path) = name == :identical? ? [path, path] : [path]

NAMES.each do |name|
  show("FileTest.#{name}, missing") { FileTest.public_send(name, *args_for(name, "/nonexistent/zr")) }
  show("FileTest.#{name}, 1") { FileTest.public_send(name, *args_for(name, 1)) }
  show("FileTest.#{name}, no argument") { FileTest.public_send(name) }
  show("Holder##{name}, missing") { Holder.new.ask(name, *args_for(name, "/nonexistent/zr")) }
  show("Holder##{name}, nil") { Holder.new.ask(name, *args_for(name, nil)) }
  show("same as File, #{name}") do
    [__FILE__, __dir__, "/nonexistent/zr"].all? do |path|
      args = args_for(name, path)
      begin
        FileTest.public_send(name, *args) == File.public_send(name, *args)
      rescue SystemCallError
        true
      end
    end
  end
end

show("exist? of this file") { [FileTest.exist?(__FILE__), FileTest.file?(__FILE__), FileTest.directory?(__dir__)] }
show("with an IO") { File.open(__FILE__) { |f| [FileTest.exist?(f), FileTest.size(f) == File.size(f), FileTest.zero?(f)] } }
show("size of a missing file") { FileTest.size("/nonexistent/zr") }
show("listed") { [FileTest.singleton_methods.sort == NAMES.sort, FileTest.private_instance_methods.sort == NAMES.sort, FileTest.instance_methods] }
show("owners") { [FileTest.method(:exist?).owner, FileTest.instance_method(:size?).owner, FileTest.method(:exist?).arity] }
show("File's own labels") { [(File.empty?(1) rescue $!.backtrace_locations.first.label), (File.executable_real?(1) rescue $!.backtrace_locations.first.label)] }
