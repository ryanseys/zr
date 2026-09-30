# Array error messages that CRuby spells precisely: a too-small negative index
# to `[]=` carries `; minimum: -N` (the number, so an empty array reads
# `minimum: 0`, not `-0`), and `drop`/`take` name the method that was actually
# called rather than always saying "take".

def msg
  yield
rescue => e
  puts "#{e.class}: #{e.message}"
end

msg { [1, 2, 3][-999] = 9 }
msg { [][-1] = 9 }
msg { [1, 2].drop(-1) }
msg { [1, 2].take(-1) }
