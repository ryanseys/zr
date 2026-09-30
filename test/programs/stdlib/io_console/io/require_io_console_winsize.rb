# `require "io/console"` enables the IO console methods (IO#winsize).
# Without the require, winsize raises NoMethodError, as in CRuby.
#
# Here stdout is not a tty, so IO#winsize raises Errno::ENOTTY.

require "io/console"
p STDOUT.winsize
