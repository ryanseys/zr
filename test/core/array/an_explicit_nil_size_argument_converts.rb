# `first`, `last`, `pop`, `shift` and `sample` tell an absent count from
# one given as nil: the absent one takes the whole-receiver form, and an
# explicit nil goes through the same conversion any other value does.
def err
  p(yield)
rescue => e
  puts "#{e.class}: #{e.message}"
end
err { [1, 2, 3].first(nil) }
err { [1, 2, 3].last(nil) }
err { [1, 2, 3].sample(nil) }
err { [1, 2, 3].shift(nil) }
err { [1, 2, 3].pop(nil) }
err { [1, 2, 3].each_entry.first(nil) }
err { "abc".chars.first(nil) }
err { "abc".split(",", nil) }
err { [1].pack(1) }
err { "A".unpack(1) }
err { [1, 2, 3].each_slice(nil).to_a }

# The absent forms are unchanged.
p [[1, 2, 3].first, [1, 2, 3].last, [1, 2, 3].first(2), [1, 2, 3].last(2)]
p [[1, 2, 3].pop, [1, 2, 3].shift]

# A comparison reads the other side as a Hash.
err { {} < 1 }
err { {} <= 1 }
err { {} > 1 }
err { {} >= 1 }
p [{ a: 1 } > {}, {} < { a: 1 }, { a: 1 } >= { a: 1 }]
__END__
TypeError: no implicit conversion from nil to integer
TypeError: no implicit conversion from nil to integer
TypeError: no implicit conversion from nil to integer
TypeError: no implicit conversion from nil to integer
TypeError: no implicit conversion from nil to integer
TypeError: no implicit conversion from nil to integer
TypeError: no implicit conversion from nil to integer
TypeError: no implicit conversion from nil to integer
TypeError: no implicit conversion of Integer into String
TypeError: no implicit conversion of Integer into String
TypeError: no implicit conversion from nil to integer
[1, 3, [1, 2], [2, 3]]
[3, 1]
TypeError: no implicit conversion of Integer into Hash
TypeError: no implicit conversion of Integer into Hash
TypeError: no implicit conversion of Integer into Hash
TypeError: no implicit conversion of Integer into Hash
[true, true, true]
