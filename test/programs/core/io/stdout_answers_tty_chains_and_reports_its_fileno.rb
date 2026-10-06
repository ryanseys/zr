# IO#tty?/#isatty, IO#<< (chainable), and IO#fileno on STDOUT/STDERR. Many gems
# call these on STDOUT/STDERR, which are concrete IO objects. The test harness
# redirects stdout/stderr, so tty? is false.
puts STDOUT.tty?
puts STDERR.isatty
STDOUT << "a" << "b" << "c\n"
puts STDOUT.fileno
puts STDERR.fileno
