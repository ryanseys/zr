# Class method with a kwarg `set_cookies: {}`. Another call site
# passes a Hash with Symbol keys and String values. A call that
# omits the kwarg gets the empty `{}` default, so `each` runs zero
# times.

class T_kwarg_default_empty_hash_kind_W
  def self.write(io, status, set_cookies: {})
    n = 0
    set_cookies.each do |name, val|
      n = n + 1
    end
    n
  end
end

class T_kwarg_default_empty_hash_kind_Use
  def self.kick
    cookies = { flash_notice: "Hi" }
    T_kwarg_default_empty_hash_kind_W.write(1, 200, set_cookies: cookies)
  end
end

puts T_kwarg_default_empty_hash_kind_W.write(1, 404).to_s
