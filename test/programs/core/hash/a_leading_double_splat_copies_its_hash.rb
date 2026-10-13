# ruby 4.1 builds {**h, ...} from a copy of h (core#hash_coerce and
# core#hash_merge_ptr): no key's hash runs, compare_by_identity stays,
# and a lone **h is rb_hash_dup's copy, with its class and default, in a
# literal and in a call, whose **rest is a copy of what it got.
class Bad
  def hash = raise("boom")
end
class H < Hash; end
def t; p yield; rescue => e; p [:err, e.class, e.message]; end
def m(**kw) = kw
def r(*a) = a
i = {}.compare_by_identity
i[Bad.new] = 1
d = Hash.new(5)
d[:a] = 1
dp = Hash.new { 9 }
dp[:a] = 1
h = H[a: 1]
h.instance_variable_set(:@iv, 7)
o = Object.new
def o.to_hash = {z: 1}
t { x = {**i}; [x.compare_by_identity?, x.size, x.class] }
t { x = {**i, k: 1}; [x.compare_by_identity?, x.size] }
t { x = {**i, **{q: 2}}; [x.compare_by_identity?, x.size] }
t { x = {k: 1, **i}; [x.compare_by_identity?, x.size] }
t { [{**d}.default, {**d, b: 2}.default, {b: 2, **d}.default, {**d, **{}}.default] }
t { [{**dp}[:zz], {**dp, b: 2}[:zz]] }
t { x = {**h}; [x.class, x.instance_variables, {**h, b: 1}.class] }
t { x = {**o}; [x, x.class] }
t { [{**nil}, {**nil, a: 1}, {a: 1, **nil}] }
t { x = {**d}; x[:new] = 2; d.key?(:new) }
t { f = {a: 1}.freeze; [{**f}.frozen?, {**f}.equal?(f)] }
t { [m(**d).default, m(**i).compare_by_identity?, m(**h).class, m(a: 1, **i).compare_by_identity?] }
t { [m(**dp)[:zz], m(**o), m(**nil)] }
t { x = r(**i); [x.size, x[0].size, x[0].compare_by_identity?] }
t { x = r(**d); [x, x[0].default] }
t { x = r(**{}); x }
t { x = [**d]; [x, x[0].default] }
def kr(a: 0, **kw) = kw
t { k = kr(**d); [k, k.default] }
t { [kr(**h).class, kr(**i).compare_by_identity?, m(**H[a: 1]).class, m(**d).default] }
t { x = m(**d); x[:new] = 1; d.key?(:new) }
t { y = {a: 1}; z = m(**y); z.equal?(y) }
