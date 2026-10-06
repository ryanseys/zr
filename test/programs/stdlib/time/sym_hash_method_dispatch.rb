require "time"  # Time#iso8601 is require-gated stdlib (matches CRuby)


def t_sym_hash_method_dispatch
  # merge / fetch / dup / delete on a Symbol-keyed Hash with String
  # values, and on a Symbol-keyed Hash with values of mixed types.
  # fetch with a default answers the stored value or the default.

  # sym_str_hash.merge
  base = { href: "/path" }
  extra = { class: "btn" }
  puts base.merge(extra).length

  # sym_str_hash.dup
  h = { a: "1", b: "2" }
  d = h.dup
  puts d.length

  # sym_str_hash.delete
  h2 = { a: "1", b: "2", c: "3" }
  h2.delete(:b)
  puts h2.length

  # sym_poly_hash.fetch with default
  opts = { method: :delete, form_class: "btn-form", id: 42 }
  m = opts.fetch(:method, :nope)
  puts m
  n = opts.fetch(:missing, :fallback)
  puts n

  # sym_poly_hash.dup + delete
  od = opts.dup
  od.delete(:method)
  puts od.length
end
t_sym_hash_method_dispatch
