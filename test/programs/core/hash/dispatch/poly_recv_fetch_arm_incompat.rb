# Sibling to the example "poly recv fetch hash arms". A user class has a
# `fetch` that only gets Symbol keys from its direct callers. A second call
# site passes a String key to `fetch` on a Hash. At run time that receiver
# is always a Hash, never the user class, so Hash#fetch answers.

class FlashLike
  def fetch(key, default)
    @last = key
    default
  end
end

# Direct callers pass only Symbols to FlashLike#fetch's `key`.
def warmup
  f = FlashLike.new
  f.fetch(:a, "1")
  f.fetch(:b, "2")
end

warmup

def get_raw(h); h["x"]; end

def lookup(h)
  sub = get_raw(h)
  sub.fetch("title", "")
end

puts lookup({ "x" => { "title" => "real" } })
