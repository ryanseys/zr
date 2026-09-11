# The report of an uncaught exception names each cause after it, each
# once, as full_message does.
class Outer < StandardError; end

def a = raise("a")

def b
  a
rescue
  raise Outer, "b"
end

b

__END__
#@ stderr
lang/exceptions/an_uncaught_error_reports_its_causes.rb:10:in 'Object#b': b (Outer)
	from lang/exceptions/an_uncaught_error_reports_its_causes.rb:13:in '<main>'
lang/exceptions/an_uncaught_error_reports_its_causes.rb:5:in 'Object#a': a (RuntimeError)
	from lang/exceptions/an_uncaught_error_reports_its_causes.rb:8:in 'Object#b'
	from lang/exceptions/an_uncaught_error_reports_its_causes.rb:13:in '<main>'
#@ exit 1
