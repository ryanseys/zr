puts(/abc/ =~ "xxabcxx")
r = /foo/
puts r.source
puts(r === "foobar")
puts(r === "baz")
