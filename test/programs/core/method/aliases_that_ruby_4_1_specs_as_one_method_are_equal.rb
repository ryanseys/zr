# Methods that ruby defines with one C function are equal, also as
# Methods of their singletons: Regexp.escape and quote, FileTest and
# File's empty? and zero?, Syslog's reopen and open!. Each keeps its name.
require "syslog"
p Regexp.method(:escape) == Regexp.method(:quote), Regexp.method(:quote).original_name, Regexp.method(:quote).name
p FileTest.method(:zero?) == FileTest.method(:empty?), File.method(:zero?) == File.method(:empty?), FileTest.method(:zero?).original_name
p Syslog.method(:reopen) == Syslog.method(:open!), Syslog.method(:reopen).original_name
p Regexp.method(:escape).hash == Regexp.method(:quote).hash, Regexp.quote("a.b"), FileTest.zero?(__FILE__)
# Kernel.format and sprintf, Kernel#then and yield_self (yield_self is an
# alias of then), Process.wait and waitpid, wait2 and waitpid2.
p Kernel.method(:format) == Kernel.method(:sprintf), Kernel.instance_method(:then) == Kernel.instance_method(:yield_self)
p Kernel.instance_method(:yield_self).original_name, Kernel.instance_method(:then).original_name
a = Kernel.instance_method(:then)
b = Kernel.instance_method(:yield_self)
p [a.eql?(b), a.hash == b.hash, 1.method(:then) == 1.method(:yield_self), 1.method(:then).hash == 1.method(:yield_self).hash]
p Process.method(:waitpid) == Process.method(:wait), Process.method(:waitpid2) == Process.method(:wait2)
# StringIO's and Zlib::GzipReader's names that one C function defines.
require "stringio"
require "zlib"
p %i[eof isatty size tell].zip(%i[eof? tty? length pos]).map { |a, b| StringIO.instance_method(a) == StringIO.instance_method(b) }
p %i[each_line eof tell].zip(%i[each eof? pos]).map { |a, b| Zlib::GzipReader.instance_method(a) == Zlib::GzipReader.instance_method(b) }
p Zlib::GzipWriter.instance_method(:tell) == Zlib::GzipWriter.instance_method(:pos), StringIO.instance_method(:tell).name
# Dir.getwd and pwd, Dir's rmdir, unlink and delete, File's fnmatch? and
# fnmatch and unlink and delete, ENV.filter and select.
p Dir.method(:getwd) == Dir.method(:pwd), Dir.method(:rmdir) == Dir.method(:delete), Dir.method(:unlink) == Dir.method(:delete)
p File.method(:fnmatch?) == File.method(:fnmatch), File.method(:unlink) == File.method(:delete), ENV.method(:filter) == ENV.method(:select)
p Dir.method(:getwd).name, File.method(:unlink).original_name
