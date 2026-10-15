# Range#bsearch searches only Integer and Float ends. Any other Range
# raises TypeError that names the class of its begin, nil included, with
# a block or without one.
def err
  yield
rescue TypeError => e
  e.message
end

p err { ("a".."e").bsearch { |x| x >= "c" } }
p err { ("a"..).bsearch { |x| x >= "c" } }
p err { (.."e").bsearch { |x| x >= "c" } }
p err { (nil..nil).bsearch { true } }
p err { (nil..nil).bsearch }
p err { ("a".."z").bsearch }
p err { (Time.at(0)..).bsearch { true } }
p (..10).bsearch { |x| x >= 7 }, (1.0..2.0).bsearch { |x| x >= 1.5 }
