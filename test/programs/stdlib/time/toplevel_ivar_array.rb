require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


def t_toplevel_ivar_array
  # Top-level instance variables: `@x` at script scope binds to the
  # main object, the same as inside an instance method. An ivar that
  # holds an Array takes `push` like any other Array.

  @n = 0
  @n = @n + 1
  @n = @n + 1
  puts @n

  @arr = []
  @arr.push(7)
  @arr.push(8)
  puts @arr.length
  @arr.each { |v| puts v }
end
t_toplevel_ivar_array
