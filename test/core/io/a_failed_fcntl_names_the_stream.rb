# rb_sys_fail_path: a failing `IO#fcntl` names the call that set up its
# argument and the stream it was made on -- "... @ finish_narg - /etc/hosts"
# -- and a stream that carries no path, as a pipe end does, names neither.
#
# ze0 wrote "@ io_fcntl" for every stream and never named one.
require "fcntl"

def refusal
  "no refusal: #{yield.inspect}"
rescue SystemCallError => e
  "#{e.class}: #{e.message}"
end

f = File.open("/etc/hosts")
r, w = IO.pipe

# A command no descriptor answers, on a stream with a path, on one without,
# and on a standard stream, whose path is its own name.
puts refusal { f.fcntl(9999) }
puts refusal { r.fcntl(9999) }
puts refusal { $stdout.fcntl(9999) }

# The commands that do answer, as a control: the close-on-exec flag ruby
# sets on everything it opens, and the access mode the stream was opened in.
p f.fcntl(Fcntl::F_GETFD)
p (f.fcntl(Fcntl::F_GETFL) & Fcntl::O_ACCMODE) == Fcntl::O_RDONLY

# A closed stream refuses before the call.
f.close
puts refusal { f.fcntl(Fcntl::F_GETFD) } rescue puts "IOError: #{$!.message}"
r.close
w.close

__END__
Errno::ENOTTY: Inappropriate ioctl for device @ finish_narg - /etc/hosts
Errno::EBADF: Bad file descriptor
Errno::EBADF: Bad file descriptor @ finish_narg - <STDOUT>
1
true
IOError: closed stream
