# CRuby's method-call allocation checks (test/ruby/test_allocation.rb,
# TestAllocation::MethodCall, with no block), as data: each row is a call
# and the Arrays and Hashes that ruby makes for it. A group prints ok when
# zr makes no more of either for any of its rows; zr may make fewer.
empty_array = empty_array = []
empty_hash = empty_hash = {}
array1 = array1 = [1]
r2k_array = r2k_array = [Hash.ruby2_keywords_hash(a: 3)]
r2k_array1 = r2k_array1 = [1, Hash.ruby2_keywords_hash(a: 3)]
r2k_empty_array = r2k_empty_array = [Hash.ruby2_keywords_hash({})]
r2k_empty_array1 = r2k_empty_array1 = [1, Hash.ruby2_keywords_hash({})]
hash1 = hash1 = {a: 2}
nill = nill = nil
$counts = {}
$more = []
def row(arrays, hashes, code)
  ObjectSpace.count_objects($counts)
  a = $counts[:T_ARRAY]
  h = $counts[:T_HASH]
  yield
  ObjectSpace.count_objects($counts)
  got = [$counts[:T_ARRAY] - a, $counts[:T_HASH] - h]
  $more << "#{code}: #{got} where ruby makes #{[arrays, hashes]}" unless got[0] <= arrays && got[1] <= hashes
end

def group(name)
  $more = []
  yield
  puts $more.empty? ? "#{name}: ok" : ["#{name}:", *$more].join("\n  ")
end

GC.start
GC.disable

def self.none(); end

group(:test_no_parameters) do
  row(0, 0, "none()") { none() }
  row(0, 0, "none(*nil)") { none(*nil) }
  row(0, 0, "none(*empty_array)") { none(*empty_array) }
  row(0, 0, "none(**empty_hash)") { none(**empty_hash) }
  row(0, 0, "none(*empty_array, **empty_hash)") { none(*empty_array, **empty_hash) }
  row(1, 0, "none(*empty_array, *empty_array)") { none(*empty_array, *empty_array) }
  row(0, 1, "none(**empty_hash, **empty_hash)") { none(**empty_hash, **empty_hash) }
  row(1, 1, "none(*empty_array, *empty_array, **empty_hash, **empty_hash)") { none(*empty_array, *empty_array, **empty_hash, **empty_hash) }
  row(0, 0, "none(*r2k_empty_array)") { none(*r2k_empty_array) }
end

def self.required(x); end

group(:test_required_parameter) do
  row(0, 0, "required(1)") { required(1) }
  row(0, 0, "required(1, *empty_array)") { required(1, *empty_array) }
  row(0, 0, "required(1, **empty_hash)") { required(1, **empty_hash) }
  row(0, 0, "required(1, *empty_array, **empty_hash)") { required(1, *empty_array, **empty_hash) }
  row(0, 0, "required(*array1)") { required(*array1) }
  row(0, 1, "required(**hash1)") { required(**hash1) }
  row(1, 0, "required(*array1, *empty_array)") { required(*array1, *empty_array) }
  row(0, 1, "required(**hash1, **empty_hash)") { required(**hash1, **empty_hash) }
  row(1, 0, "required(*array1, *empty_array, **empty_hash)") { required(*array1, *empty_array, **empty_hash) }
  row(0, 0, "required(*r2k_empty_array1)") { required(*r2k_empty_array1) }
  row(0, 1, "required(*r2k_array)") { required(*r2k_array) }
  row(0, 1, "required(*empty_array, **hash1, **empty_hash)") { required(*empty_array, **hash1, **empty_hash) }
end

def self.optional(x=nil); end

group(:test_optional_parameter) do
  row(0, 0, "optional(1)") { optional(1) }
  row(0, 0, "optional(1, *empty_array)") { optional(1, *empty_array) }
  row(0, 0, "optional(1, **empty_hash)") { optional(1, **empty_hash) }
  row(0, 0, "optional(1, *empty_array, **empty_hash)") { optional(1, *empty_array, **empty_hash) }
  row(0, 0, "optional(*array1)") { optional(*array1) }
  row(0, 1, "optional(**hash1)") { optional(**hash1) }
  row(1, 0, "optional(*array1, *empty_array)") { optional(*array1, *empty_array) }
  row(0, 1, "optional(**hash1, **empty_hash)") { optional(**hash1, **empty_hash) }
  row(1, 0, "optional(*array1, *empty_array, **empty_hash)") { optional(*array1, *empty_array, **empty_hash) }
  row(0, 0, "optional(*r2k_empty_array)") { optional(*r2k_empty_array) }
  row(0, 0, "optional(*r2k_empty_array1)") { optional(*r2k_empty_array1) }
  row(0, 1, "optional(*r2k_array)") { optional(*r2k_array) }
  row(0, 0, "optional(*empty_array)") { optional(*empty_array) }
  row(0, 0, "optional(*nil)") { optional(*nil) }
  row(0, 0, "optional()") { optional() }
  row(0, 1, "optional(*empty_array, **hash1, **empty_hash)") { optional(*empty_array, **hash1, **empty_hash) }
end

def self.splat(*x); end

group(:test_positional_splat_parameter) do
  row(1, 0, "splat(1)") { splat(1) }
  row(1, 0, "splat(1, *empty_array)") { splat(1, *empty_array) }
  row(1, 0, "splat(1, **empty_hash)") { splat(1, **empty_hash) }
  row(1, 0, "splat(1, *empty_array, **empty_hash)") { splat(1, *empty_array, **empty_hash) }
  row(1, 0, "splat(*array1)") { splat(*array1) }
  row(1, 0, "splat(*array1, *empty_array)") { splat(*array1, *empty_array) }
  row(1, 0, "splat(*array1, **empty_hash)") { splat(*array1, **empty_hash) }
  row(1, 0, "splat(*array1, *empty_array, **empty_hash)") { splat(*array1, *empty_array, **empty_hash) }
  row(1, 0, "splat(1, *array1)") { splat(1, *array1) }
  row(1, 0, "splat(1, *array1, *empty_array)") { splat(1, *array1, *empty_array) }
  row(1, 0, "splat(1, *array1, **empty_hash)") { splat(1, *array1, **empty_hash) }
  row(1, 0, "splat(1, *array1, *empty_array, **empty_hash)") { splat(1, *array1, *empty_array, **empty_hash) }
  row(1, 0, "splat(*nil)") { splat(*nil) }
  row(1, 0, "splat()") { splat() }
  row(1, 1, "splat(**hash1)") { splat(**hash1) }
  row(1, 1, "splat(**hash1, **empty_hash)") { splat(**hash1, **empty_hash) }
  row(1, 1, "splat(*empty_array, **hash1, **empty_hash)") { splat(*empty_array, **hash1, **empty_hash) }
  row(1, 0, "splat(*r2k_empty_array)") { splat(*r2k_empty_array) }
  row(1, 0, "splat(*r2k_empty_array1)") { splat(*r2k_empty_array1) }
  row(1, 1, "splat(*r2k_array)") { splat(*r2k_array) }
  row(1, 1, "splat(*r2k_array1)") { splat(*r2k_array1) }
end

def self.req_splat(x, *y); end

group(:test_required_and_positional_splat_parameters) do
  row(1, 0, "req_splat(1)") { req_splat(1) }
  row(1, 0, "req_splat(1, *nil)") { req_splat(1, *nil) }
  row(1, 0, "req_splat(1, *empty_array)") { req_splat(1, *empty_array) }
  row(1, 0, "req_splat(1, **empty_hash)") { req_splat(1, **empty_hash) }
  row(1, 0, "req_splat(1, *empty_array, **empty_hash)") { req_splat(1, *empty_array, **empty_hash) }
  row(1, 0, "req_splat(*array1)") { req_splat(*array1) }
  row(1, 0, "req_splat(*array1, *empty_array)") { req_splat(*array1, *empty_array) }
  row(1, 0, "req_splat(*array1, **empty_hash)") { req_splat(*array1, **empty_hash) }
  row(1, 0, "req_splat(*array1, *empty_array, **empty_hash)") { req_splat(*array1, *empty_array, **empty_hash) }
  row(1, 0, "req_splat(1, *array1)") { req_splat(1, *array1) }
  row(1, 0, "req_splat(1, *array1, *empty_array)") { req_splat(1, *array1, *empty_array) }
  row(1, 0, "req_splat(1, *array1, **empty_hash)") { req_splat(1, *array1, **empty_hash) }
  row(1, 0, "req_splat(1, *array1, *empty_array, **empty_hash)") { req_splat(1, *array1, *empty_array, **empty_hash) }
  row(1, 1, "req_splat(**hash1)") { req_splat(**hash1) }
  row(1, 1, "req_splat(**hash1, **empty_hash)") { req_splat(**hash1, **empty_hash) }
  row(1, 1, "req_splat(*empty_array, **hash1, **empty_hash)") { req_splat(*empty_array, **hash1, **empty_hash) }
  row(1, 0, "req_splat(*r2k_empty_array1)") { req_splat(*r2k_empty_array1) }
  row(1, 1, "req_splat(*r2k_array)") { req_splat(*r2k_array) }
  row(1, 1, "req_splat(*r2k_array1)") { req_splat(*r2k_array1) }
end

def self.splat_post(*x, y); end

group(:test_positional_splat_and_post_parameters) do
  row(1, 0, "splat_post(1)") { splat_post(1) }
  row(1, 0, "splat_post(1, *nil)") { splat_post(1, *nil) }
  row(1, 0, "splat_post(1, *empty_array)") { splat_post(1, *empty_array) }
  row(1, 0, "splat_post(1, **empty_hash)") { splat_post(1, **empty_hash) }
  row(1, 0, "splat_post(1, *empty_array, **empty_hash)") { splat_post(1, *empty_array, **empty_hash) }
  row(1, 0, "splat_post(*array1)") { splat_post(*array1) }
  row(1, 0, "splat_post(*array1, *empty_array)") { splat_post(*array1, *empty_array) }
  row(1, 0, "splat_post(*array1, **empty_hash)") { splat_post(*array1, **empty_hash) }
  row(1, 0, "splat_post(*array1, *empty_array, **empty_hash)") { splat_post(*array1, *empty_array, **empty_hash) }
  row(1, 0, "splat_post(1, *array1)") { splat_post(1, *array1) }
  row(1, 0, "splat_post(1, *array1, *empty_array)") { splat_post(1, *array1, *empty_array) }
  row(1, 0, "splat_post(1, *array1, **empty_hash)") { splat_post(1, *array1, **empty_hash) }
  row(1, 0, "splat_post(1, *array1, *empty_array, **empty_hash)") { splat_post(1, *array1, *empty_array, **empty_hash) }
  row(1, 1, "splat_post(**hash1)") { splat_post(**hash1) }
  row(1, 1, "splat_post(**hash1, **empty_hash)") { splat_post(**hash1, **empty_hash) }
  row(1, 1, "splat_post(*empty_array, **hash1, **empty_hash)") { splat_post(*empty_array, **hash1, **empty_hash) }
  row(1, 0, "splat_post(*r2k_empty_array1)") { splat_post(*r2k_empty_array1) }
  row(1, 1, "splat_post(*r2k_array)") { splat_post(*r2k_array) }
  row(1, 1, "splat_post(*r2k_array1)") { splat_post(*r2k_array1) }
end

def self.keyword(a: nil); end

group(:test_keyword_parameter) do
  row(0, 0, "keyword(a: 2)") { keyword(a: 2) }
  row(0, 0, "keyword(*empty_array, a: 2)") { keyword(*empty_array, a: 2) }
  row(0, 1, "keyword(a:2, **empty_hash)") { keyword(a:2, **empty_hash) }
  row(0, 1, "keyword(**empty_hash, a: 2)") { keyword(**empty_hash, a: 2) }
  row(0, 0, "keyword(**nil)") { keyword(**nil) }
  row(0, 0, "keyword(**empty_hash)") { keyword(**empty_hash) }
  row(0, 0, "keyword(**hash1)") { keyword(**hash1) }
  row(0, 0, "keyword(*empty_array, **hash1)") { keyword(*empty_array, **hash1) }
  row(0, 1, "keyword(**hash1, **empty_hash)") { keyword(**hash1, **empty_hash) }
  row(0, 1, "keyword(**empty_hash, **hash1)") { keyword(**empty_hash, **hash1) }
  row(0, 0, "keyword(*nil)") { keyword(*nil) }
  row(0, 0, "keyword(*empty_array)") { keyword(*empty_array) }
  row(1, 0, "keyword(*empty_array, *empty_array, **empty_hash)") { keyword(*empty_array, *empty_array, **empty_hash) }
  row(0, 0, "keyword(*r2k_empty_array)") { keyword(*r2k_empty_array) }
  row(0, 0, "keyword(*r2k_array)") { keyword(*r2k_array) }
  row(0, 1, "keyword(*empty_array, a: 2, **empty_hash)") { keyword(*empty_array, a: 2, **empty_hash) }
  row(0, 1, "keyword(*empty_array, **hash1, **empty_hash)") { keyword(*empty_array, **hash1, **empty_hash) }
end

def self.keyword_splat(**kw); end

group(:test_keyword_splat_parameter) do
  row(0, 1, "keyword_splat(a: 2)") { keyword_splat(a: 2) }
  row(0, 1, "keyword_splat(*empty_array, a: 2)") { keyword_splat(*empty_array, a: 2) }
  row(0, 1, "keyword_splat(a:2, **empty_hash)") { keyword_splat(a:2, **empty_hash) }
  row(0, 1, "keyword_splat(**empty_hash, a: 2)") { keyword_splat(**empty_hash, a: 2) }
  row(0, 1, "keyword_splat(**nil)") { keyword_splat(**nil) }
  row(0, 1, "keyword_splat(**empty_hash)") { keyword_splat(**empty_hash) }
  row(0, 1, "keyword_splat(**hash1)") { keyword_splat(**hash1) }
  row(0, 1, "keyword_splat(*empty_array, **hash1)") { keyword_splat(*empty_array, **hash1) }
  row(0, 1, "keyword_splat(**hash1, **empty_hash)") { keyword_splat(**hash1, **empty_hash) }
  row(0, 1, "keyword_splat(**empty_hash, **hash1)") { keyword_splat(**empty_hash, **hash1) }
  row(0, 1, "keyword_splat(*nil)") { keyword_splat(*nil) }
  row(0, 1, "keyword_splat(*empty_array)") { keyword_splat(*empty_array) }
  row(1, 1, "keyword_splat(*empty_array, *empty_array, **empty_hash)") { keyword_splat(*empty_array, *empty_array, **empty_hash) }
  row(0, 1, "keyword_splat(*r2k_empty_array)") { keyword_splat(*r2k_empty_array) }
  row(0, 1, "keyword_splat(*r2k_array)") { keyword_splat(*r2k_array) }
  row(0, 1, "keyword_splat(*empty_array, a: 2, **empty_hash)") { keyword_splat(*empty_array, a: 2, **empty_hash) }
  row(0, 1, "keyword_splat(*empty_array, **hash1, **empty_hash)") { keyword_splat(*empty_array, **hash1, **empty_hash) }
end

def self.keyword_and_keyword_splat(a: 1, **kw); end

group(:test_keyword_and_keyword_splat_parameter) do
  row(0, 1, "keyword_and_keyword_splat(a: 2)") { keyword_and_keyword_splat(a: 2) }
  row(0, 1, "keyword_and_keyword_splat(*empty_array, a: 2)") { keyword_and_keyword_splat(*empty_array, a: 2) }
  row(0, 1, "keyword_and_keyword_splat(a:2, **empty_hash)") { keyword_and_keyword_splat(a:2, **empty_hash) }
  row(0, 1, "keyword_and_keyword_splat(**empty_hash, a: 2)") { keyword_and_keyword_splat(**empty_hash, a: 2) }
  row(0, 1, "keyword_and_keyword_splat(**nil)") { keyword_and_keyword_splat(**nil) }
  row(0, 1, "keyword_and_keyword_splat(**empty_hash)") { keyword_and_keyword_splat(**empty_hash) }
  row(0, 1, "keyword_and_keyword_splat(**hash1)") { keyword_and_keyword_splat(**hash1) }
  row(0, 1, "keyword_and_keyword_splat(*empty_array, **hash1)") { keyword_and_keyword_splat(*empty_array, **hash1) }
  row(0, 1, "keyword_and_keyword_splat(**hash1, **empty_hash)") { keyword_and_keyword_splat(**hash1, **empty_hash) }
  row(0, 1, "keyword_and_keyword_splat(**empty_hash, **hash1)") { keyword_and_keyword_splat(**empty_hash, **hash1) }
  row(0, 1, "keyword_and_keyword_splat(*nil)") { keyword_and_keyword_splat(*nil) }
  row(0, 1, "keyword_and_keyword_splat(*empty_array)") { keyword_and_keyword_splat(*empty_array) }
  row(1, 1, "keyword_and_keyword_splat(*empty_array, *empty_array, **empty_hash)") { keyword_and_keyword_splat(*empty_array, *empty_array, **empty_hash) }
  row(0, 1, "keyword_and_keyword_splat(*r2k_empty_array)") { keyword_and_keyword_splat(*r2k_empty_array) }
  row(0, 1, "keyword_and_keyword_splat(*r2k_array)") { keyword_and_keyword_splat(*r2k_array) }
  row(0, 1, "keyword_and_keyword_splat(*empty_array, a: 2, **empty_hash)") { keyword_and_keyword_splat(*empty_array, a: 2, **empty_hash) }
  row(0, 1, "keyword_and_keyword_splat(*empty_array, **hash1, **empty_hash)") { keyword_and_keyword_splat(*empty_array, **hash1, **empty_hash) }
end

def self.required_and_keyword(b, a: nil); end

group(:test_required_positional_and_keyword_parameter) do
  row(0, 0, "required_and_keyword(1, a: 2)") { required_and_keyword(1, a: 2) }
  row(0, 0, "required_and_keyword(1, *empty_array, a: 2)") { required_and_keyword(1, *empty_array, a: 2) }
  row(0, 1, "required_and_keyword(1, a:2, **empty_hash)") { required_and_keyword(1, a:2, **empty_hash) }
  row(0, 1, "required_and_keyword(1, **empty_hash, a: 2)") { required_and_keyword(1, **empty_hash, a: 2) }
  row(0, 0, "required_and_keyword(1, **nil)") { required_and_keyword(1, **nil) }
  row(0, 0, "required_and_keyword(1, **empty_hash)") { required_and_keyword(1, **empty_hash) }
  row(0, 0, "required_and_keyword(1, **hash1)") { required_and_keyword(1, **hash1) }
  row(0, 0, "required_and_keyword(1, *empty_array, **hash1)") { required_and_keyword(1, *empty_array, **hash1) }
  row(0, 1, "required_and_keyword(1, **hash1, **empty_hash)") { required_and_keyword(1, **hash1, **empty_hash) }
  row(0, 1, "required_and_keyword(1, **empty_hash, **hash1)") { required_and_keyword(1, **empty_hash, **hash1) }
  row(0, 0, "required_and_keyword(1, *nil)") { required_and_keyword(1, *nil) }
  row(0, 0, "required_and_keyword(1, *empty_array)") { required_and_keyword(1, *empty_array) }
  row(1, 0, "required_and_keyword(1, *empty_array, *empty_array, **empty_hash)") { required_and_keyword(1, *empty_array, *empty_array, **empty_hash) }
  row(0, 0, "required_and_keyword(*array1, a: 2)") { required_and_keyword(*array1, a: 2) }
  row(0, 0, "required_and_keyword(*array1, **nill)") { required_and_keyword(*array1, **nill) }
  row(0, 0, "required_and_keyword(*array1, **empty_hash)") { required_and_keyword(*array1, **empty_hash) }
  row(0, 0, "required_and_keyword(*array1, **hash1)") { required_and_keyword(*array1, **hash1) }
  row(1, 0, "required_and_keyword(*array1, *empty_array, **hash1)") { required_and_keyword(*array1, *empty_array, **hash1) }
  row(1, 0, "required_and_keyword(*array1, *empty_array)") { required_and_keyword(*array1, *empty_array) }
  row(1, 0, "required_and_keyword(*array1, *empty_array, **empty_hash)") { required_and_keyword(*array1, *empty_array, **empty_hash) }
  row(1, 1, "required_and_keyword(*array1, *empty_array, a: 2, **empty_hash)") { required_and_keyword(*array1, *empty_array, a: 2, **empty_hash) }
  row(1, 1, "required_and_keyword(*array1, *empty_array, **hash1, **empty_hash)") { required_and_keyword(*array1, *empty_array, **hash1, **empty_hash) }
  row(0, 0, "required_and_keyword(*r2k_empty_array1)") { required_and_keyword(*r2k_empty_array1) }
  row(0, 0, "required_and_keyword(*r2k_array1)") { required_and_keyword(*r2k_array1) }
  row(0, 1, "required_and_keyword(1, *empty_array, a: 2, **empty_hash)") { required_and_keyword(1, *empty_array, a: 2, **empty_hash) }
  row(0, 1, "required_and_keyword(1, *empty_array, **hash1, **empty_hash)") { required_and_keyword(1, *empty_array, **hash1, **empty_hash) }
  row(0, 1, "required_and_keyword(*array1, **empty_hash, a: 2)") { required_and_keyword(*array1, **empty_hash, a: 2) }
  row(0, 1, "required_and_keyword(*array1, **hash1, **empty_hash)") { required_and_keyword(*array1, **hash1, **empty_hash) }
  row(0, 0, "required_and_keyword(*array1, **nil)") { required_and_keyword(*array1, **nil) }
end

def self.splat_and_keyword(*b, a: nil); end

group(:test_positional_splat_and_keyword_parameter) do
  row(1, 0, "splat_and_keyword(1, a: 2)") { splat_and_keyword(1, a: 2) }
  row(1, 0, "splat_and_keyword(1, *empty_array, a: 2)") { splat_and_keyword(1, *empty_array, a: 2) }
  row(1, 1, "splat_and_keyword(1, a:2, **empty_hash)") { splat_and_keyword(1, a:2, **empty_hash) }
  row(1, 1, "splat_and_keyword(1, **empty_hash, a: 2)") { splat_and_keyword(1, **empty_hash, a: 2) }
  row(1, 0, "splat_and_keyword(1, **nil)") { splat_and_keyword(1, **nil) }
  row(1, 0, "splat_and_keyword(1, **empty_hash)") { splat_and_keyword(1, **empty_hash) }
  row(1, 0, "splat_and_keyword(1, **hash1)") { splat_and_keyword(1, **hash1) }
  row(1, 0, "splat_and_keyword(1, *empty_array, **hash1)") { splat_and_keyword(1, *empty_array, **hash1) }
  row(1, 1, "splat_and_keyword(1, **hash1, **empty_hash)") { splat_and_keyword(1, **hash1, **empty_hash) }
  row(1, 1, "splat_and_keyword(1, **empty_hash, **hash1)") { splat_and_keyword(1, **empty_hash, **hash1) }
  row(1, 0, "splat_and_keyword(1, *nil)") { splat_and_keyword(1, *nil) }
  row(1, 0, "splat_and_keyword(1, *empty_array)") { splat_and_keyword(1, *empty_array) }
  row(1, 0, "splat_and_keyword(1, *empty_array, *empty_array, **empty_hash)") { splat_and_keyword(1, *empty_array, *empty_array, **empty_hash) }
  row(1, 0, "splat_and_keyword(*array1, a: 2)") { splat_and_keyword(*array1, a: 2) }
  row(1, 0, "splat_and_keyword(*array1, **nill)") { splat_and_keyword(*array1, **nill) }
  row(1, 0, "splat_and_keyword(*array1, **empty_hash)") { splat_and_keyword(*array1, **empty_hash) }
  row(1, 0, "splat_and_keyword(*array1, **hash1)") { splat_and_keyword(*array1, **hash1) }
  row(1, 0, "splat_and_keyword(*array1, *empty_array, **hash1)") { splat_and_keyword(*array1, *empty_array, **hash1) }
  row(1, 0, "splat_and_keyword(*array1, *empty_array)") { splat_and_keyword(*array1, *empty_array) }
  row(1, 0, "splat_and_keyword(*array1, *empty_array, **empty_hash)") { splat_and_keyword(*array1, *empty_array, **empty_hash) }
  row(1, 1, "splat_and_keyword(*array1, *empty_array, a: 2, **empty_hash)") { splat_and_keyword(*array1, *empty_array, a: 2, **empty_hash) }
  row(1, 1, "splat_and_keyword(*array1, *empty_array, **hash1, **empty_hash)") { splat_and_keyword(*array1, *empty_array, **hash1, **empty_hash) }
  row(1, 1, "splat_and_keyword(1, *empty_array, a: 2, **empty_hash)") { splat_and_keyword(1, *empty_array, a: 2, **empty_hash) }
  row(1, 1, "splat_and_keyword(1, *empty_array, **hash1, **empty_hash)") { splat_and_keyword(1, *empty_array, **hash1, **empty_hash) }
  row(1, 1, "splat_and_keyword(*array1, **empty_hash, a: 2)") { splat_and_keyword(*array1, **empty_hash, a: 2) }
  row(1, 1, "splat_and_keyword(*array1, **hash1, **empty_hash)") { splat_and_keyword(*array1, **hash1, **empty_hash) }
  row(1, 0, "splat_and_keyword(*array1, **nil)") { splat_and_keyword(*array1, **nil) }
  row(1, 0, "splat_and_keyword(*r2k_empty_array)") { splat_and_keyword(*r2k_empty_array) }
  row(1, 0, "splat_and_keyword(*r2k_array)") { splat_and_keyword(*r2k_array) }
  row(1, 0, "splat_and_keyword(*r2k_empty_array1)") { splat_and_keyword(*r2k_empty_array1) }
  row(1, 0, "splat_and_keyword(*r2k_array1)") { splat_and_keyword(*r2k_array1) }
end

def self.required_and_keyword_splat(b, **kw); end

group(:test_required_and_keyword_splat_parameter) do
  row(0, 1, "required_and_keyword_splat(1, a: 2)") { required_and_keyword_splat(1, a: 2) }
  row(0, 1, "required_and_keyword_splat(1, *empty_array, a: 2)") { required_and_keyword_splat(1, *empty_array, a: 2) }
  row(0, 1, "required_and_keyword_splat(1, a:2, **empty_hash)") { required_and_keyword_splat(1, a:2, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(1, **empty_hash, a: 2)") { required_and_keyword_splat(1, **empty_hash, a: 2) }
  row(0, 1, "required_and_keyword_splat(1, **nil)") { required_and_keyword_splat(1, **nil) }
  row(0, 1, "required_and_keyword_splat(1, **empty_hash)") { required_and_keyword_splat(1, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(1, **hash1)") { required_and_keyword_splat(1, **hash1) }
  row(0, 1, "required_and_keyword_splat(1, *empty_array, **hash1)") { required_and_keyword_splat(1, *empty_array, **hash1) }
  row(0, 1, "required_and_keyword_splat(1, **hash1, **empty_hash)") { required_and_keyword_splat(1, **hash1, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(1, **empty_hash, **hash1)") { required_and_keyword_splat(1, **empty_hash, **hash1) }
  row(0, 1, "required_and_keyword_splat(1, *nil)") { required_and_keyword_splat(1, *nil) }
  row(0, 1, "required_and_keyword_splat(1, *empty_array)") { required_and_keyword_splat(1, *empty_array) }
  row(1, 1, "required_and_keyword_splat(1, *empty_array, *empty_array, **empty_hash)") { required_and_keyword_splat(1, *empty_array, *empty_array, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(*array1, a: 2)") { required_and_keyword_splat(*array1, a: 2) }
  row(0, 1, "required_and_keyword_splat(*array1, **nill)") { required_and_keyword_splat(*array1, **nill) }
  row(0, 1, "required_and_keyword_splat(*array1, **empty_hash)") { required_and_keyword_splat(*array1, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(*array1, **hash1)") { required_and_keyword_splat(*array1, **hash1) }
  row(1, 1, "required_and_keyword_splat(*array1, *empty_array, **hash1)") { required_and_keyword_splat(*array1, *empty_array, **hash1) }
  row(1, 1, "required_and_keyword_splat(*array1, *empty_array)") { required_and_keyword_splat(*array1, *empty_array) }
  row(1, 1, "required_and_keyword_splat(*array1, *empty_array, **empty_hash)") { required_and_keyword_splat(*array1, *empty_array, **empty_hash) }
  row(1, 1, "required_and_keyword_splat(*array1, *empty_array, a: 2, **empty_hash)") { required_and_keyword_splat(*array1, *empty_array, a: 2, **empty_hash) }
  row(1, 1, "required_and_keyword_splat(*array1, *empty_array, **hash1, **empty_hash)") { required_and_keyword_splat(*array1, *empty_array, **hash1, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(*r2k_empty_array1)") { required_and_keyword_splat(*r2k_empty_array1) }
  row(0, 1, "required_and_keyword_splat(*r2k_array1)") { required_and_keyword_splat(*r2k_array1) }
  row(0, 1, "required_and_keyword_splat(1, *empty_array, a: 2, **empty_hash)") { required_and_keyword_splat(1, *empty_array, a: 2, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(1, *empty_array, **hash1, **empty_hash)") { required_and_keyword_splat(1, *empty_array, **hash1, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(*array1, **empty_hash, a: 2)") { required_and_keyword_splat(*array1, **empty_hash, a: 2) }
  row(0, 1, "required_and_keyword_splat(*array1, **hash1, **empty_hash)") { required_and_keyword_splat(*array1, **hash1, **empty_hash) }
  row(0, 1, "required_and_keyword_splat(*array1, **nil)") { required_and_keyword_splat(*array1, **nil) }
end

def self.splat_and_keyword_splat(*b, **kw); end

group(:test_positional_splat_and_keyword_splat_parameter) do
  row(1, 1, "splat_and_keyword_splat(1, a: 2)") { splat_and_keyword_splat(1, a: 2) }
  row(1, 1, "splat_and_keyword_splat(1, *empty_array, a: 2)") { splat_and_keyword_splat(1, *empty_array, a: 2) }
  row(1, 1, "splat_and_keyword_splat(1, a:2, **empty_hash)") { splat_and_keyword_splat(1, a:2, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(1, **empty_hash, a: 2)") { splat_and_keyword_splat(1, **empty_hash, a: 2) }
  row(1, 1, "splat_and_keyword_splat(1, **nil)") { splat_and_keyword_splat(1, **nil) }
  row(1, 1, "splat_and_keyword_splat(1, **empty_hash)") { splat_and_keyword_splat(1, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(1, **hash1)") { splat_and_keyword_splat(1, **hash1) }
  row(1, 1, "splat_and_keyword_splat(1, *empty_array, **hash1)") { splat_and_keyword_splat(1, *empty_array, **hash1) }
  row(1, 1, "splat_and_keyword_splat(1, **hash1, **empty_hash)") { splat_and_keyword_splat(1, **hash1, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(1, **empty_hash, **hash1)") { splat_and_keyword_splat(1, **empty_hash, **hash1) }
  row(1, 1, "splat_and_keyword_splat(1, *nil)") { splat_and_keyword_splat(1, *nil) }
  row(1, 1, "splat_and_keyword_splat(1, *empty_array)") { splat_and_keyword_splat(1, *empty_array) }
  row(1, 1, "splat_and_keyword_splat(1, *empty_array, *empty_array, **empty_hash)") { splat_and_keyword_splat(1, *empty_array, *empty_array, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(*array1, a: 2)") { splat_and_keyword_splat(*array1, a: 2) }
  row(1, 1, "splat_and_keyword_splat(*array1, **nill)") { splat_and_keyword_splat(*array1, **nill) }
  row(1, 1, "splat_and_keyword_splat(*array1, **empty_hash)") { splat_and_keyword_splat(*array1, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(*array1, **hash1)") { splat_and_keyword_splat(*array1, **hash1) }
  row(1, 1, "splat_and_keyword_splat(*array1, *empty_array, **hash1)") { splat_and_keyword_splat(*array1, *empty_array, **hash1) }
  row(1, 1, "splat_and_keyword_splat(*array1, *empty_array)") { splat_and_keyword_splat(*array1, *empty_array) }
  row(1, 1, "splat_and_keyword_splat(*array1, *empty_array, **empty_hash)") { splat_and_keyword_splat(*array1, *empty_array, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(*array1, *empty_array, a: 2, **empty_hash)") { splat_and_keyword_splat(*array1, *empty_array, a: 2, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(*array1, *empty_array, **hash1, **empty_hash)") { splat_and_keyword_splat(*array1, *empty_array, **hash1, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(1, *empty_array, a: 2, **empty_hash)") { splat_and_keyword_splat(1, *empty_array, a: 2, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(1, *empty_array, **hash1, **empty_hash)") { splat_and_keyword_splat(1, *empty_array, **hash1, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(*array1, **empty_hash, a: 2)") { splat_and_keyword_splat(*array1, **empty_hash, a: 2) }
  row(1, 1, "splat_and_keyword_splat(*array1, **hash1, **empty_hash)") { splat_and_keyword_splat(*array1, **hash1, **empty_hash) }
  row(1, 1, "splat_and_keyword_splat(*array1, **nil)") { splat_and_keyword_splat(*array1, **nil) }
  row(1, 1, "splat_and_keyword_splat(*r2k_empty_array)") { splat_and_keyword_splat(*r2k_empty_array) }
  row(1, 1, "splat_and_keyword_splat(*r2k_array)") { splat_and_keyword_splat(*r2k_array) }
  row(1, 1, "splat_and_keyword_splat(*r2k_empty_array1)") { splat_and_keyword_splat(*r2k_empty_array1) }
  row(1, 1, "splat_and_keyword_splat(*r2k_array1)") { splat_and_keyword_splat(*r2k_array1) }
end

def self.r2k(*a); end
singleton_class.send(:ruby2_keywords, :r2k)

group(:test_ruby2_keywords) do
  row(1, 1, "r2k(1, a: 2)") { r2k(1, a: 2) }
  row(1, 1, "r2k(1, *empty_array, a: 2)") { r2k(1, *empty_array, a: 2) }
  row(1, 1, "r2k(1, a:2, **empty_hash)") { r2k(1, a:2, **empty_hash) }
  row(1, 1, "r2k(1, **empty_hash, a: 2)") { r2k(1, **empty_hash, a: 2) }
  row(1, 0, "r2k(1, **nil)") { r2k(1, **nil) }
  row(1, 0, "r2k(1, **empty_hash)") { r2k(1, **empty_hash) }
  row(1, 1, "r2k(1, **hash1)") { r2k(1, **hash1) }
  row(1, 1, "r2k(1, *empty_array, **hash1)") { r2k(1, *empty_array, **hash1) }
  row(1, 1, "r2k(1, **hash1, **empty_hash)") { r2k(1, **hash1, **empty_hash) }
  row(1, 1, "r2k(1, **empty_hash, **hash1)") { r2k(1, **empty_hash, **hash1) }
  row(1, 0, "r2k(1, *empty_array)") { r2k(1, *empty_array) }
  row(1, 0, "r2k(1, *empty_array, *empty_array, **empty_hash)") { r2k(1, *empty_array, *empty_array, **empty_hash) }
  row(1, 1, "r2k(*array1, a: 2)") { r2k(*array1, a: 2) }
  row(1, 0, "r2k(**nill)") { r2k(**nill) }
  row(1, 0, "r2k(*nil, **nill)") { r2k(*nil, **nill) }
  row(1, 0, "r2k(*array1, **nill)") { r2k(*array1, **nill) }
  row(1, 0, "r2k(*array1, **empty_hash)") { r2k(*array1, **empty_hash) }
  row(1, 1, "r2k(*array1, **hash1)") { r2k(*array1, **hash1) }
  row(1, 1, "r2k(*array1, *empty_array, **hash1)") { r2k(*array1, *empty_array, **hash1) }
  row(1, 0, "r2k(*array1, *empty_array)") { r2k(*array1, *empty_array) }
  row(1, 0, "r2k(*array1, *empty_array, **empty_hash)") { r2k(*array1, *empty_array, **empty_hash) }
  row(1, 1, "r2k(*array1, *empty_array, a: 2, **empty_hash)") { r2k(*array1, *empty_array, a: 2, **empty_hash) }
  row(1, 1, "r2k(*array1, *empty_array, **hash1, **empty_hash)") { r2k(*array1, *empty_array, **hash1, **empty_hash) }
  row(1, 1, "r2k(1, *empty_array, a: 2, **empty_hash)") { r2k(1, *empty_array, a: 2, **empty_hash) }
  row(1, 1, "r2k(1, *empty_array, **hash1, **empty_hash)") { r2k(1, *empty_array, **hash1, **empty_hash) }
  row(1, 1, "r2k(*array1, **empty_hash, a: 2)") { r2k(*array1, **empty_hash, a: 2) }
  row(1, 1, "r2k(*array1, **hash1, **empty_hash)") { r2k(*array1, **hash1, **empty_hash) }
  row(1, 0, "r2k(*array1, **nil)") { r2k(*array1, **nil) }
  row(1, 0, "r2k(*r2k_empty_array)") { r2k(*r2k_empty_array) }
end
