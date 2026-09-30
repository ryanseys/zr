# `.dup` on a hash value read out of a hash with mixed values: the
# call `outer[k].dup` answers a copy of the inner hash.
#
# The shape comes from a blog app's `merged = matched[:path_params].dup`.

module Router
  def self.match(present)
    if present
      return { controller: :a, path_params: { "id" => "7" } }
    end
    nil
  end
end

# Sink consuming a hash of mixed type. The literal-init call below
# passes such a hash.
def first_value(h)
  h["id"]
end

# Pin first_value's `h` param to poly via a direct poly-call
# site. This is a workaround for the LV-widening gap: without
# it the param defaults to int because the only call site is
# downstream of the .dup widening.
def make_poly_hash
  hh = { "id" => "fallback" }
  m = Router.match(true)
  if m
    return m[:path_params].dup
  end
  hh
end

x = make_poly_hash
puts first_value(x)
