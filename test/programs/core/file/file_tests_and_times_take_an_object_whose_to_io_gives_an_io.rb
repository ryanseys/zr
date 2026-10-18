# A blank slate undefines every method but __id__ and __send__, as rbs's
# test doubles do (RBS::UnitTest::Convertibles), so any send that CRuby's
# C does not make raises here.
class Blank < BasicObject
  instance_methods.each { |im| undef_method im unless im == :__id__ || im == :__send__ }
end
class ToStr < Blank
  def initialize(v) = @v = v
  def to_str = @v
end
class ToInt < Blank
  def initialize(v) = @v = v
  def to_int = @v
end
class ToF < Blank
  def initialize(v) = @v = v
  def to_f = @v
end
class ToS < Blank
  def initialize(v) = @v = v
  def to_s = @v
end
class ToPath < Blank
  def initialize(v) = @v = v
  def to_path = @v
end
class ToIO < Blank
  def initialize(v) = @v = v
  def to_io = @v
end
class Span < Blank
  def initialize(b, e, x = false) = (@b = b; @e = e; @x = x)
  def begin = @b
  def end = @e
  def exclude_end? = @x
end

def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue ::Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

# rb_stat: an IO, or an object whose to_io gives one, is asked by
# fstat(2) on its descriptor, for File's times and FileTest's checks.
here = File.open(__FILE__)
mode = File.stat(__FILE__).mode
t("pipe?") { [FileTest.pipe?(ToIO.new(here)), File.pipe?(ToIO.new(IO.pipe[0]))] }
t("owned?") { FileTest.owned?(ToIO.new(here)) == FileTest.owned?(__FILE__) }
t("grpowned?") { FileTest.grpowned?(ToIO.new(here)) == FileTest.grpowned?(__FILE__) }
t("world_readable?") { FileTest.world_readable?(ToIO.new(here)) == ((mode & 0o004) != 0 ? mode & 0o777 : nil) }
t("world_writable?") { FileTest.world_writable?(ToIO.new(here)) }
t("sticky? setuid? setgid?") { [File.sticky?(ToIO.new(here)), File.setuid?(ToIO.new(here)), File.setgid?(ToIO.new(here))] }
t("socket? blockdev? chardev?") { [File.socket?(ToIO.new(here)), File.blockdev?(ToIO.new(here)), File.chardev?(ToIO.new(here))] }
t("times") { [File.atime(ToIO.new(here)), File.mtime(ToIO.new(here)), File.ctime(ToIO.new(here))].map(&:class) }
t("times of an IO") { [File.atime(here), File.mtime(here)] == [File.atime(__FILE__), File.mtime(__FILE__)] }
t("mtime same") { File.mtime(ToIO.new(here)) == File.mtime(__FILE__) }
t("to_io not an IO") { File.atime(ToIO.new(1)) }
t("closed") { io = File.open(__FILE__); io.close; File.mtime(io) }
t("symlink? takes no IO") { File.symlink?(here) }
t("missing path") { File.mtime("/nonexistent/zr-file") }
