# An uncaught exception prints the message and the backtrace and exits 1. The
# linked binary carries the source names its backtrace needs.
def inner
  raise ArgumentError, "bad thing"
end

def outer
  inner
end

outer



__END__
#@ stderr
e2e/lang/exceptions/uncaught_exception.rb:4:in 'Object#inner': bad thing (ArgumentError)

  raise ArgumentError, "bad thing"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^
	from e2e/lang/exceptions/uncaught_exception.rb:8:in 'Object#outer'
	from e2e/lang/exceptions/uncaught_exception.rb:11:in '<main>'
#@ exit 1
