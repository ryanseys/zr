# CRuby's Proc#call allocation checks (test/ruby/test_allocation.rb,
# TestAllocation::ProcCall::WithBlock), as data: each row is a call
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
block = block = lambda {}
$counts = {}
$more = []
# Each call runs once before it is measured, so a cache that its first
# run fills does not count.
def row(arrays, hashes, code)
  yield
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

none = none = proc{ |&block|   }

group(:test_no_parameters) do
  row(0, 0, "none.(&block)") { none.(&block) }
  row(0, 0, "none.(*nil, &block)") { none.(*nil, &block) }
  row(0, 0, "none.(*empty_array, &block)") { none.(*empty_array, &block) }
  row(0, 0, "none.(**empty_hash, &block)") { none.(**empty_hash, &block) }
  row(0, 0, "none.(*empty_array, **empty_hash, &block)") { none.(*empty_array, **empty_hash, &block) }
  row(1, 0, "none.(*empty_array, *empty_array, &block)") { none.(*empty_array, *empty_array, &block) }
  row(0, 1, "none.(**empty_hash, **empty_hash, &block)") { none.(**empty_hash, **empty_hash, &block) }
  row(1, 1, "none.(*empty_array, *empty_array, **empty_hash, **empty_hash, &block)") { none.(*empty_array, *empty_array, **empty_hash, **empty_hash, &block) }
  row(0, 0, "none.(*r2k_empty_array, &block)") { none.(*r2k_empty_array, &block) }
end

required = required = proc{ |x, &block|   }

group(:test_required_parameter) do
  row(0, 0, "required.(1, &block)") { required.(1, &block) }
  row(0, 0, "required.(1, *empty_array, &block)") { required.(1, *empty_array, &block) }
  row(0, 0, "required.(1, **empty_hash, &block)") { required.(1, **empty_hash, &block) }
  row(0, 0, "required.(1, *empty_array, **empty_hash, &block)") { required.(1, *empty_array, **empty_hash, &block) }
  row(0, 0, "required.(*array1, &block)") { required.(*array1, &block) }
  row(0, 1, "required.(**hash1, &block)") { required.(**hash1, &block) }
  row(1, 0, "required.(*array1, *empty_array, &block)") { required.(*array1, *empty_array, &block) }
  row(0, 1, "required.(**hash1, **empty_hash, &block)") { required.(**hash1, **empty_hash, &block) }
  row(1, 0, "required.(*array1, *empty_array, **empty_hash, &block)") { required.(*array1, *empty_array, **empty_hash, &block) }
  row(0, 0, "required.(*r2k_empty_array1, &block)") { required.(*r2k_empty_array1, &block) }
  row(0, 1, "required.(*r2k_array, &block)") { required.(*r2k_array, &block) }
  row(0, 1, "required.(*empty_array, **hash1, **empty_hash, &block)") { required.(*empty_array, **hash1, **empty_hash, &block) }
end

optional = optional = proc{ |x=nil, &block|   }

group(:test_optional_parameter) do
  row(0, 0, "optional.(1, &block)") { optional.(1, &block) }
  row(0, 0, "optional.(1, *empty_array, &block)") { optional.(1, *empty_array, &block) }
  row(0, 0, "optional.(1, **empty_hash, &block)") { optional.(1, **empty_hash, &block) }
  row(0, 0, "optional.(1, *empty_array, **empty_hash, &block)") { optional.(1, *empty_array, **empty_hash, &block) }
  row(0, 0, "optional.(*array1, &block)") { optional.(*array1, &block) }
  row(0, 1, "optional.(**hash1, &block)") { optional.(**hash1, &block) }
  row(1, 0, "optional.(*array1, *empty_array, &block)") { optional.(*array1, *empty_array, &block) }
  row(0, 1, "optional.(**hash1, **empty_hash, &block)") { optional.(**hash1, **empty_hash, &block) }
  row(1, 0, "optional.(*array1, *empty_array, **empty_hash, &block)") { optional.(*array1, *empty_array, **empty_hash, &block) }
  row(0, 0, "optional.(*r2k_empty_array, &block)") { optional.(*r2k_empty_array, &block) }
  row(0, 0, "optional.(*r2k_empty_array1, &block)") { optional.(*r2k_empty_array1, &block) }
  row(0, 1, "optional.(*r2k_array, &block)") { optional.(*r2k_array, &block) }
  row(0, 0, "optional.(*empty_array, &block)") { optional.(*empty_array, &block) }
  row(0, 0, "optional.(*nil, &block)") { optional.(*nil, &block) }
  row(0, 0, "optional.(&block)") { optional.(&block) }
  row(0, 1, "optional.(*empty_array, **hash1, **empty_hash, &block)") { optional.(*empty_array, **hash1, **empty_hash, &block) }
end

splat = splat = proc{ |*x, &block|   }

group(:test_positional_splat_parameter) do
  row(1, 0, "splat.(1, &block)") { splat.(1, &block) }
  row(1, 0, "splat.(1, *empty_array, &block)") { splat.(1, *empty_array, &block) }
  row(1, 0, "splat.(1, **empty_hash, &block)") { splat.(1, **empty_hash, &block) }
  row(1, 0, "splat.(1, *empty_array, **empty_hash, &block)") { splat.(1, *empty_array, **empty_hash, &block) }
  row(1, 0, "splat.(*array1, &block)") { splat.(*array1, &block) }
  row(1, 0, "splat.(*array1, *empty_array, &block)") { splat.(*array1, *empty_array, &block) }
  row(1, 0, "splat.(*array1, **empty_hash, &block)") { splat.(*array1, **empty_hash, &block) }
  row(1, 0, "splat.(*array1, *empty_array, **empty_hash, &block)") { splat.(*array1, *empty_array, **empty_hash, &block) }
  row(1, 0, "splat.(1, *array1, &block)") { splat.(1, *array1, &block) }
  row(1, 0, "splat.(1, *array1, *empty_array, &block)") { splat.(1, *array1, *empty_array, &block) }
  row(1, 0, "splat.(1, *array1, **empty_hash, &block)") { splat.(1, *array1, **empty_hash, &block) }
  row(1, 0, "splat.(1, *array1, *empty_array, **empty_hash, &block)") { splat.(1, *array1, *empty_array, **empty_hash, &block) }
  row(1, 0, "splat.(*nil, &block)") { splat.(*nil, &block) }
  row(1, 0, "splat.(&block)") { splat.(&block) }
  row(1, 1, "splat.(**hash1, &block)") { splat.(**hash1, &block) }
  row(1, 1, "splat.(**hash1, **empty_hash, &block)") { splat.(**hash1, **empty_hash, &block) }
  row(1, 1, "splat.(*empty_array, **hash1, **empty_hash, &block)") { splat.(*empty_array, **hash1, **empty_hash, &block) }
  row(1, 0, "splat.(*r2k_empty_array, &block)") { splat.(*r2k_empty_array, &block) }
  row(1, 0, "splat.(*r2k_empty_array1, &block)") { splat.(*r2k_empty_array1, &block) }
  row(1, 1, "splat.(*r2k_array, &block)") { splat.(*r2k_array, &block) }
  row(1, 1, "splat.(*r2k_array1, &block)") { splat.(*r2k_array1, &block) }
end

req_splat = req_splat = proc{ |x, *y, &block|   }

group(:test_required_and_positional_splat_parameters) do
  row(1, 0, "req_splat.(1, &block)") { req_splat.(1, &block) }
  row(1, 0, "req_splat.(1, *nil, &block)") { req_splat.(1, *nil, &block) }
  row(1, 0, "req_splat.(1, *empty_array, &block)") { req_splat.(1, *empty_array, &block) }
  row(1, 0, "req_splat.(1, **empty_hash, &block)") { req_splat.(1, **empty_hash, &block) }
  row(1, 0, "req_splat.(1, *empty_array, **empty_hash, &block)") { req_splat.(1, *empty_array, **empty_hash, &block) }
  row(1, 0, "req_splat.(*array1, &block)") { req_splat.(*array1, &block) }
  row(1, 0, "req_splat.(*array1, *empty_array, &block)") { req_splat.(*array1, *empty_array, &block) }
  row(1, 0, "req_splat.(*array1, **empty_hash, &block)") { req_splat.(*array1, **empty_hash, &block) }
  row(1, 0, "req_splat.(*array1, *empty_array, **empty_hash, &block)") { req_splat.(*array1, *empty_array, **empty_hash, &block) }
  row(1, 0, "req_splat.(1, *array1, &block)") { req_splat.(1, *array1, &block) }
  row(1, 0, "req_splat.(1, *array1, *empty_array, &block)") { req_splat.(1, *array1, *empty_array, &block) }
  row(1, 0, "req_splat.(1, *array1, **empty_hash, &block)") { req_splat.(1, *array1, **empty_hash, &block) }
  row(1, 0, "req_splat.(1, *array1, *empty_array, **empty_hash, &block)") { req_splat.(1, *array1, *empty_array, **empty_hash, &block) }
  row(1, 1, "req_splat.(**hash1, &block)") { req_splat.(**hash1, &block) }
  row(1, 1, "req_splat.(**hash1, **empty_hash, &block)") { req_splat.(**hash1, **empty_hash, &block) }
  row(1, 1, "req_splat.(*empty_array, **hash1, **empty_hash, &block)") { req_splat.(*empty_array, **hash1, **empty_hash, &block) }
  row(1, 0, "req_splat.(*r2k_empty_array1, &block)") { req_splat.(*r2k_empty_array1, &block) }
  row(1, 1, "req_splat.(*r2k_array, &block)") { req_splat.(*r2k_array, &block) }
  row(1, 1, "req_splat.(*r2k_array1, &block)") { req_splat.(*r2k_array1, &block) }
end

splat_post = splat_post = proc{ |*x, y, &block|   }

group(:test_positional_splat_and_post_parameters) do
  row(1, 0, "splat_post.(1, &block)") { splat_post.(1, &block) }
  row(1, 0, "splat_post.(1, *nil, &block)") { splat_post.(1, *nil, &block) }
  row(1, 0, "splat_post.(1, *empty_array, &block)") { splat_post.(1, *empty_array, &block) }
  row(1, 0, "splat_post.(1, **empty_hash, &block)") { splat_post.(1, **empty_hash, &block) }
  row(1, 0, "splat_post.(1, *empty_array, **empty_hash, &block)") { splat_post.(1, *empty_array, **empty_hash, &block) }
  row(1, 0, "splat_post.(*array1, &block)") { splat_post.(*array1, &block) }
  row(1, 0, "splat_post.(*array1, *empty_array, &block)") { splat_post.(*array1, *empty_array, &block) }
  row(1, 0, "splat_post.(*array1, **empty_hash, &block)") { splat_post.(*array1, **empty_hash, &block) }
  row(1, 0, "splat_post.(*array1, *empty_array, **empty_hash, &block)") { splat_post.(*array1, *empty_array, **empty_hash, &block) }
  row(1, 0, "splat_post.(1, *array1, &block)") { splat_post.(1, *array1, &block) }
  row(1, 0, "splat_post.(1, *array1, *empty_array, &block)") { splat_post.(1, *array1, *empty_array, &block) }
  row(1, 0, "splat_post.(1, *array1, **empty_hash, &block)") { splat_post.(1, *array1, **empty_hash, &block) }
  row(1, 0, "splat_post.(1, *array1, *empty_array, **empty_hash, &block)") { splat_post.(1, *array1, *empty_array, **empty_hash, &block) }
  row(1, 1, "splat_post.(**hash1, &block)") { splat_post.(**hash1, &block) }
  row(1, 1, "splat_post.(**hash1, **empty_hash, &block)") { splat_post.(**hash1, **empty_hash, &block) }
  row(1, 1, "splat_post.(*empty_array, **hash1, **empty_hash, &block)") { splat_post.(*empty_array, **hash1, **empty_hash, &block) }
  row(1, 0, "splat_post.(*r2k_empty_array1, &block)") { splat_post.(*r2k_empty_array1, &block) }
  row(1, 1, "splat_post.(*r2k_array, &block)") { splat_post.(*r2k_array, &block) }
  row(1, 1, "splat_post.(*r2k_array1, &block)") { splat_post.(*r2k_array1, &block) }
end

keyword = keyword = proc{ |a: nil, &block|   }

group(:test_keyword_parameter) do
  row(0, 0, "keyword.(a: 2, &block)") { keyword.(a: 2, &block) }
  row(0, 0, "keyword.(*empty_array, a: 2, &block)") { keyword.(*empty_array, a: 2, &block) }
  row(0, 1, "keyword.(a:2, **empty_hash, &block)") { keyword.(a:2, **empty_hash, &block) }
  row(0, 1, "keyword.(**empty_hash, a: 2, &block)") { keyword.(**empty_hash, a: 2, &block) }
  row(0, 0, "keyword.(**nil, &block)") { keyword.(**nil, &block) }
  row(0, 0, "keyword.(**empty_hash, &block)") { keyword.(**empty_hash, &block) }
  row(0, 0, "keyword.(**hash1, &block)") { keyword.(**hash1, &block) }
  row(0, 0, "keyword.(*empty_array, **hash1, &block)") { keyword.(*empty_array, **hash1, &block) }
  row(0, 1, "keyword.(**hash1, **empty_hash, &block)") { keyword.(**hash1, **empty_hash, &block) }
  row(0, 1, "keyword.(**empty_hash, **hash1, &block)") { keyword.(**empty_hash, **hash1, &block) }
  row(0, 0, "keyword.(*nil, &block)") { keyword.(*nil, &block) }
  row(0, 0, "keyword.(*empty_array, &block)") { keyword.(*empty_array, &block) }
  row(1, 0, "keyword.(*empty_array, *empty_array, **empty_hash, &block)") { keyword.(*empty_array, *empty_array, **empty_hash, &block) }
  row(0, 0, "keyword.(*r2k_empty_array, &block)") { keyword.(*r2k_empty_array, &block) }
  row(0, 0, "keyword.(*r2k_array, &block)") { keyword.(*r2k_array, &block) }
  row(0, 1, "keyword.(*empty_array, a: 2, **empty_hash, &block)") { keyword.(*empty_array, a: 2, **empty_hash, &block) }
  row(0, 1, "keyword.(*empty_array, **hash1, **empty_hash, &block)") { keyword.(*empty_array, **hash1, **empty_hash, &block) }
end

keyword_splat = keyword_splat = proc{ |**kw, &block|   }

group(:test_keyword_splat_parameter) do
  row(0, 1, "keyword_splat.(a: 2, &block)") { keyword_splat.(a: 2, &block) }
  row(0, 1, "keyword_splat.(*empty_array, a: 2, &block)") { keyword_splat.(*empty_array, a: 2, &block) }
  row(0, 1, "keyword_splat.(a:2, **empty_hash, &block)") { keyword_splat.(a:2, **empty_hash, &block) }
  row(0, 1, "keyword_splat.(**empty_hash, a: 2, &block)") { keyword_splat.(**empty_hash, a: 2, &block) }
  row(0, 1, "keyword_splat.(**nil, &block)") { keyword_splat.(**nil, &block) }
  row(0, 1, "keyword_splat.(**empty_hash, &block)") { keyword_splat.(**empty_hash, &block) }
  row(0, 1, "keyword_splat.(**hash1, &block)") { keyword_splat.(**hash1, &block) }
  row(0, 1, "keyword_splat.(*empty_array, **hash1, &block)") { keyword_splat.(*empty_array, **hash1, &block) }
  row(0, 1, "keyword_splat.(**hash1, **empty_hash, &block)") { keyword_splat.(**hash1, **empty_hash, &block) }
  row(0, 1, "keyword_splat.(**empty_hash, **hash1, &block)") { keyword_splat.(**empty_hash, **hash1, &block) }
  row(0, 1, "keyword_splat.(*nil, &block)") { keyword_splat.(*nil, &block) }
  row(0, 1, "keyword_splat.(*empty_array, &block)") { keyword_splat.(*empty_array, &block) }
  row(1, 1, "keyword_splat.(*empty_array, *empty_array, **empty_hash, &block)") { keyword_splat.(*empty_array, *empty_array, **empty_hash, &block) }
  row(0, 1, "keyword_splat.(*r2k_empty_array, &block)") { keyword_splat.(*r2k_empty_array, &block) }
  row(0, 1, "keyword_splat.(*r2k_array, &block)") { keyword_splat.(*r2k_array, &block) }
  row(0, 1, "keyword_splat.(*empty_array, a: 2, **empty_hash, &block)") { keyword_splat.(*empty_array, a: 2, **empty_hash, &block) }
  row(0, 1, "keyword_splat.(*empty_array, **hash1, **empty_hash, &block)") { keyword_splat.(*empty_array, **hash1, **empty_hash, &block) }
end

keyword_and_keyword_splat = keyword_and_keyword_splat = proc{ |a: 1, **kw, &block|   }

group(:test_keyword_and_keyword_splat_parameter) do
  row(0, 1, "keyword_and_keyword_splat.(a: 2, &block)") { keyword_and_keyword_splat.(a: 2, &block) }
  row(0, 1, "keyword_and_keyword_splat.(*empty_array, a: 2, &block)") { keyword_and_keyword_splat.(*empty_array, a: 2, &block) }
  row(0, 1, "keyword_and_keyword_splat.(a:2, **empty_hash, &block)") { keyword_and_keyword_splat.(a:2, **empty_hash, &block) }
  row(0, 1, "keyword_and_keyword_splat.(**empty_hash, a: 2, &block)") { keyword_and_keyword_splat.(**empty_hash, a: 2, &block) }
  row(0, 1, "keyword_and_keyword_splat.(**nil, &block)") { keyword_and_keyword_splat.(**nil, &block) }
  row(0, 1, "keyword_and_keyword_splat.(**empty_hash, &block)") { keyword_and_keyword_splat.(**empty_hash, &block) }
  row(0, 1, "keyword_and_keyword_splat.(**hash1, &block)") { keyword_and_keyword_splat.(**hash1, &block) }
  row(0, 1, "keyword_and_keyword_splat.(*empty_array, **hash1, &block)") { keyword_and_keyword_splat.(*empty_array, **hash1, &block) }
  row(0, 1, "keyword_and_keyword_splat.(**hash1, **empty_hash, &block)") { keyword_and_keyword_splat.(**hash1, **empty_hash, &block) }
  row(0, 1, "keyword_and_keyword_splat.(**empty_hash, **hash1, &block)") { keyword_and_keyword_splat.(**empty_hash, **hash1, &block) }
  row(0, 1, "keyword_and_keyword_splat.(*nil, &block)") { keyword_and_keyword_splat.(*nil, &block) }
  row(0, 1, "keyword_and_keyword_splat.(*empty_array, &block)") { keyword_and_keyword_splat.(*empty_array, &block) }
  row(1, 1, "keyword_and_keyword_splat.(*empty_array, *empty_array, **empty_hash, &block)") { keyword_and_keyword_splat.(*empty_array, *empty_array, **empty_hash, &block) }
  row(0, 1, "keyword_and_keyword_splat.(*r2k_empty_array, &block)") { keyword_and_keyword_splat.(*r2k_empty_array, &block) }
  row(0, 1, "keyword_and_keyword_splat.(*r2k_array, &block)") { keyword_and_keyword_splat.(*r2k_array, &block) }
  row(0, 1, "keyword_and_keyword_splat.(*empty_array, a: 2, **empty_hash, &block)") { keyword_and_keyword_splat.(*empty_array, a: 2, **empty_hash, &block) }
  row(0, 1, "keyword_and_keyword_splat.(*empty_array, **hash1, **empty_hash, &block)") { keyword_and_keyword_splat.(*empty_array, **hash1, **empty_hash, &block) }
end

required_and_keyword = required_and_keyword = proc{ |b, a: nil, &block|   }

group(:test_required_positional_and_keyword_parameter) do
  row(0, 0, "required_and_keyword.(1, a: 2, &block)") { required_and_keyword.(1, a: 2, &block) }
  row(0, 0, "required_and_keyword.(1, *empty_array, a: 2, &block)") { required_and_keyword.(1, *empty_array, a: 2, &block) }
  row(0, 1, "required_and_keyword.(1, a:2, **empty_hash, &block)") { required_and_keyword.(1, a:2, **empty_hash, &block) }
  row(0, 1, "required_and_keyword.(1, **empty_hash, a: 2, &block)") { required_and_keyword.(1, **empty_hash, a: 2, &block) }
  row(0, 0, "required_and_keyword.(1, **nil, &block)") { required_and_keyword.(1, **nil, &block) }
  row(0, 0, "required_and_keyword.(1, **empty_hash, &block)") { required_and_keyword.(1, **empty_hash, &block) }
  row(0, 0, "required_and_keyword.(1, **hash1, &block)") { required_and_keyword.(1, **hash1, &block) }
  row(0, 0, "required_and_keyword.(1, *empty_array, **hash1, &block)") { required_and_keyword.(1, *empty_array, **hash1, &block) }
  row(0, 1, "required_and_keyword.(1, **hash1, **empty_hash, &block)") { required_and_keyword.(1, **hash1, **empty_hash, &block) }
  row(0, 1, "required_and_keyword.(1, **empty_hash, **hash1, &block)") { required_and_keyword.(1, **empty_hash, **hash1, &block) }
  row(0, 0, "required_and_keyword.(1, *nil, &block)") { required_and_keyword.(1, *nil, &block) }
  row(0, 0, "required_and_keyword.(1, *empty_array, &block)") { required_and_keyword.(1, *empty_array, &block) }
  row(1, 0, "required_and_keyword.(1, *empty_array, *empty_array, **empty_hash, &block)") { required_and_keyword.(1, *empty_array, *empty_array, **empty_hash, &block) }
  row(0, 0, "required_and_keyword.(*array1, a: 2, &block)") { required_and_keyword.(*array1, a: 2, &block) }
  row(0, 0, "required_and_keyword.(*array1, **nill, &block)") { required_and_keyword.(*array1, **nill, &block) }
  row(0, 0, "required_and_keyword.(*array1, **empty_hash, &block)") { required_and_keyword.(*array1, **empty_hash, &block) }
  row(0, 0, "required_and_keyword.(*array1, **hash1, &block)") { required_and_keyword.(*array1, **hash1, &block) }
  row(1, 0, "required_and_keyword.(*array1, *empty_array, **hash1, &block)") { required_and_keyword.(*array1, *empty_array, **hash1, &block) }
  row(1, 0, "required_and_keyword.(*array1, *empty_array, &block)") { required_and_keyword.(*array1, *empty_array, &block) }
  row(1, 0, "required_and_keyword.(*array1, *empty_array, **empty_hash, &block)") { required_and_keyword.(*array1, *empty_array, **empty_hash, &block) }
  row(1, 1, "required_and_keyword.(*array1, *empty_array, a: 2, **empty_hash, &block)") { required_and_keyword.(*array1, *empty_array, a: 2, **empty_hash, &block) }
  row(1, 1, "required_and_keyword.(*array1, *empty_array, **hash1, **empty_hash, &block)") { required_and_keyword.(*array1, *empty_array, **hash1, **empty_hash, &block) }
  row(0, 0, "required_and_keyword.(*r2k_empty_array1, &block)") { required_and_keyword.(*r2k_empty_array1, &block) }
  row(0, 0, "required_and_keyword.(*r2k_array1, &block)") { required_and_keyword.(*r2k_array1, &block) }
  row(0, 1, "required_and_keyword.(1, *empty_array, a: 2, **empty_hash, &block)") { required_and_keyword.(1, *empty_array, a: 2, **empty_hash, &block) }
  row(0, 1, "required_and_keyword.(1, *empty_array, **hash1, **empty_hash, &block)") { required_and_keyword.(1, *empty_array, **hash1, **empty_hash, &block) }
  row(0, 1, "required_and_keyword.(*array1, **empty_hash, a: 2, &block)") { required_and_keyword.(*array1, **empty_hash, a: 2, &block) }
  row(0, 1, "required_and_keyword.(*array1, **hash1, **empty_hash, &block)") { required_and_keyword.(*array1, **hash1, **empty_hash, &block) }
  row(0, 0, "required_and_keyword.(*array1, **nil, &block)") { required_and_keyword.(*array1, **nil, &block) }
end

splat_and_keyword = splat_and_keyword = proc{ |*b, a: nil, &block|   }

group(:test_positional_splat_and_keyword_parameter) do
  row(1, 0, "splat_and_keyword.(1, a: 2, &block)") { splat_and_keyword.(1, a: 2, &block) }
  row(1, 0, "splat_and_keyword.(1, *empty_array, a: 2, &block)") { splat_and_keyword.(1, *empty_array, a: 2, &block) }
  row(1, 1, "splat_and_keyword.(1, a:2, **empty_hash, &block)") { splat_and_keyword.(1, a:2, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword.(1, **empty_hash, a: 2, &block)") { splat_and_keyword.(1, **empty_hash, a: 2, &block) }
  row(1, 0, "splat_and_keyword.(1, **nil, &block)") { splat_and_keyword.(1, **nil, &block) }
  row(1, 0, "splat_and_keyword.(1, **empty_hash, &block)") { splat_and_keyword.(1, **empty_hash, &block) }
  row(1, 0, "splat_and_keyword.(1, **hash1, &block)") { splat_and_keyword.(1, **hash1, &block) }
  row(1, 0, "splat_and_keyword.(1, *empty_array, **hash1, &block)") { splat_and_keyword.(1, *empty_array, **hash1, &block) }
  row(1, 1, "splat_and_keyword.(1, **hash1, **empty_hash, &block)") { splat_and_keyword.(1, **hash1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword.(1, **empty_hash, **hash1, &block)") { splat_and_keyword.(1, **empty_hash, **hash1, &block) }
  row(1, 0, "splat_and_keyword.(1, *nil, &block)") { splat_and_keyword.(1, *nil, &block) }
  row(1, 0, "splat_and_keyword.(1, *empty_array, &block)") { splat_and_keyword.(1, *empty_array, &block) }
  row(1, 0, "splat_and_keyword.(1, *empty_array, *empty_array, **empty_hash, &block)") { splat_and_keyword.(1, *empty_array, *empty_array, **empty_hash, &block) }
  row(1, 0, "splat_and_keyword.(*array1, a: 2, &block)") { splat_and_keyword.(*array1, a: 2, &block) }
  row(1, 0, "splat_and_keyword.(*array1, **nill, &block)") { splat_and_keyword.(*array1, **nill, &block) }
  row(1, 0, "splat_and_keyword.(*array1, **empty_hash, &block)") { splat_and_keyword.(*array1, **empty_hash, &block) }
  row(1, 0, "splat_and_keyword.(*array1, **hash1, &block)") { splat_and_keyword.(*array1, **hash1, &block) }
  row(1, 0, "splat_and_keyword.(*array1, *empty_array, **hash1, &block)") { splat_and_keyword.(*array1, *empty_array, **hash1, &block) }
  row(1, 0, "splat_and_keyword.(*array1, *empty_array, &block)") { splat_and_keyword.(*array1, *empty_array, &block) }
  row(1, 0, "splat_and_keyword.(*array1, *empty_array, **empty_hash, &block)") { splat_and_keyword.(*array1, *empty_array, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword.(*array1, *empty_array, a: 2, **empty_hash, &block)") { splat_and_keyword.(*array1, *empty_array, a: 2, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword.(*array1, *empty_array, **hash1, **empty_hash, &block)") { splat_and_keyword.(*array1, *empty_array, **hash1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword.(1, *empty_array, a: 2, **empty_hash, &block)") { splat_and_keyword.(1, *empty_array, a: 2, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword.(1, *empty_array, **hash1, **empty_hash, &block)") { splat_and_keyword.(1, *empty_array, **hash1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword.(*array1, **empty_hash, a: 2, &block)") { splat_and_keyword.(*array1, **empty_hash, a: 2, &block) }
  row(1, 1, "splat_and_keyword.(*array1, **hash1, **empty_hash, &block)") { splat_and_keyword.(*array1, **hash1, **empty_hash, &block) }
  row(1, 0, "splat_and_keyword.(*array1, **nil, &block)") { splat_and_keyword.(*array1, **nil, &block) }
  row(1, 0, "splat_and_keyword.(*r2k_empty_array, &block)") { splat_and_keyword.(*r2k_empty_array, &block) }
  row(1, 0, "splat_and_keyword.(*r2k_array, &block)") { splat_and_keyword.(*r2k_array, &block) }
  row(1, 0, "splat_and_keyword.(*r2k_empty_array1, &block)") { splat_and_keyword.(*r2k_empty_array1, &block) }
  row(1, 0, "splat_and_keyword.(*r2k_array1, &block)") { splat_and_keyword.(*r2k_array1, &block) }
end

required_and_keyword_splat = required_and_keyword_splat = proc{ |b, **kw, &block|   }

group(:test_required_and_keyword_splat_parameter) do
  row(0, 1, "required_and_keyword_splat.(1, a: 2, &block)") { required_and_keyword_splat.(1, a: 2, &block) }
  row(0, 1, "required_and_keyword_splat.(1, *empty_array, a: 2, &block)") { required_and_keyword_splat.(1, *empty_array, a: 2, &block) }
  row(0, 1, "required_and_keyword_splat.(1, a:2, **empty_hash, &block)") { required_and_keyword_splat.(1, a:2, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(1, **empty_hash, a: 2, &block)") { required_and_keyword_splat.(1, **empty_hash, a: 2, &block) }
  row(0, 1, "required_and_keyword_splat.(1, **nil, &block)") { required_and_keyword_splat.(1, **nil, &block) }
  row(0, 1, "required_and_keyword_splat.(1, **empty_hash, &block)") { required_and_keyword_splat.(1, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(1, **hash1, &block)") { required_and_keyword_splat.(1, **hash1, &block) }
  row(0, 1, "required_and_keyword_splat.(1, *empty_array, **hash1, &block)") { required_and_keyword_splat.(1, *empty_array, **hash1, &block) }
  row(0, 1, "required_and_keyword_splat.(1, **hash1, **empty_hash, &block)") { required_and_keyword_splat.(1, **hash1, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(1, **empty_hash, **hash1, &block)") { required_and_keyword_splat.(1, **empty_hash, **hash1, &block) }
  row(0, 1, "required_and_keyword_splat.(1, *nil, &block)") { required_and_keyword_splat.(1, *nil, &block) }
  row(0, 1, "required_and_keyword_splat.(1, *empty_array, &block)") { required_and_keyword_splat.(1, *empty_array, &block) }
  row(1, 1, "required_and_keyword_splat.(1, *empty_array, *empty_array, **empty_hash, &block)") { required_and_keyword_splat.(1, *empty_array, *empty_array, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(*array1, a: 2, &block)") { required_and_keyword_splat.(*array1, a: 2, &block) }
  row(0, 1, "required_and_keyword_splat.(*array1, **nill, &block)") { required_and_keyword_splat.(*array1, **nill, &block) }
  row(0, 1, "required_and_keyword_splat.(*array1, **empty_hash, &block)") { required_and_keyword_splat.(*array1, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(*array1, **hash1, &block)") { required_and_keyword_splat.(*array1, **hash1, &block) }
  row(1, 1, "required_and_keyword_splat.(*array1, *empty_array, **hash1, &block)") { required_and_keyword_splat.(*array1, *empty_array, **hash1, &block) }
  row(1, 1, "required_and_keyword_splat.(*array1, *empty_array, &block)") { required_and_keyword_splat.(*array1, *empty_array, &block) }
  row(1, 1, "required_and_keyword_splat.(*array1, *empty_array, **empty_hash, &block)") { required_and_keyword_splat.(*array1, *empty_array, **empty_hash, &block) }
  row(1, 1, "required_and_keyword_splat.(*array1, *empty_array, a: 2, **empty_hash, &block)") { required_and_keyword_splat.(*array1, *empty_array, a: 2, **empty_hash, &block) }
  row(1, 1, "required_and_keyword_splat.(*array1, *empty_array, **hash1, **empty_hash, &block)") { required_and_keyword_splat.(*array1, *empty_array, **hash1, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(*r2k_empty_array1, &block)") { required_and_keyword_splat.(*r2k_empty_array1, &block) }
  row(0, 1, "required_and_keyword_splat.(*r2k_array1, &block)") { required_and_keyword_splat.(*r2k_array1, &block) }
  row(0, 1, "required_and_keyword_splat.(1, *empty_array, a: 2, **empty_hash, &block)") { required_and_keyword_splat.(1, *empty_array, a: 2, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(1, *empty_array, **hash1, **empty_hash, &block)") { required_and_keyword_splat.(1, *empty_array, **hash1, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(*array1, **empty_hash, a: 2, &block)") { required_and_keyword_splat.(*array1, **empty_hash, a: 2, &block) }
  row(0, 1, "required_and_keyword_splat.(*array1, **hash1, **empty_hash, &block)") { required_and_keyword_splat.(*array1, **hash1, **empty_hash, &block) }
  row(0, 1, "required_and_keyword_splat.(*array1, **nil, &block)") { required_and_keyword_splat.(*array1, **nil, &block) }
end

splat_and_keyword_splat = splat_and_keyword_splat = proc{ |*b, **kw, &block|   }

group(:test_positional_splat_and_keyword_splat_parameter) do
  row(1, 1, "splat_and_keyword_splat.(1, a: 2, &block)") { splat_and_keyword_splat.(1, a: 2, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, *empty_array, a: 2, &block)") { splat_and_keyword_splat.(1, *empty_array, a: 2, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, a:2, **empty_hash, &block)") { splat_and_keyword_splat.(1, a:2, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, **empty_hash, a: 2, &block)") { splat_and_keyword_splat.(1, **empty_hash, a: 2, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, **nil, &block)") { splat_and_keyword_splat.(1, **nil, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, **empty_hash, &block)") { splat_and_keyword_splat.(1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, **hash1, &block)") { splat_and_keyword_splat.(1, **hash1, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, *empty_array, **hash1, &block)") { splat_and_keyword_splat.(1, *empty_array, **hash1, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, **hash1, **empty_hash, &block)") { splat_and_keyword_splat.(1, **hash1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, **empty_hash, **hash1, &block)") { splat_and_keyword_splat.(1, **empty_hash, **hash1, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, *nil, &block)") { splat_and_keyword_splat.(1, *nil, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, *empty_array, &block)") { splat_and_keyword_splat.(1, *empty_array, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, *empty_array, *empty_array, **empty_hash, &block)") { splat_and_keyword_splat.(1, *empty_array, *empty_array, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, a: 2, &block)") { splat_and_keyword_splat.(*array1, a: 2, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, **nill, &block)") { splat_and_keyword_splat.(*array1, **nill, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, **empty_hash, &block)") { splat_and_keyword_splat.(*array1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, **hash1, &block)") { splat_and_keyword_splat.(*array1, **hash1, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, *empty_array, **hash1, &block)") { splat_and_keyword_splat.(*array1, *empty_array, **hash1, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, *empty_array, &block)") { splat_and_keyword_splat.(*array1, *empty_array, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, *empty_array, **empty_hash, &block)") { splat_and_keyword_splat.(*array1, *empty_array, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, *empty_array, a: 2, **empty_hash, &block)") { splat_and_keyword_splat.(*array1, *empty_array, a: 2, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, *empty_array, **hash1, **empty_hash, &block)") { splat_and_keyword_splat.(*array1, *empty_array, **hash1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, *empty_array, a: 2, **empty_hash, &block)") { splat_and_keyword_splat.(1, *empty_array, a: 2, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(1, *empty_array, **hash1, **empty_hash, &block)") { splat_and_keyword_splat.(1, *empty_array, **hash1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, **empty_hash, a: 2, &block)") { splat_and_keyword_splat.(*array1, **empty_hash, a: 2, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, **hash1, **empty_hash, &block)") { splat_and_keyword_splat.(*array1, **hash1, **empty_hash, &block) }
  row(1, 1, "splat_and_keyword_splat.(*array1, **nil, &block)") { splat_and_keyword_splat.(*array1, **nil, &block) }
  row(1, 1, "splat_and_keyword_splat.(*r2k_empty_array, &block)") { splat_and_keyword_splat.(*r2k_empty_array, &block) }
  row(1, 1, "splat_and_keyword_splat.(*r2k_array, &block)") { splat_and_keyword_splat.(*r2k_array, &block) }
  row(1, 1, "splat_and_keyword_splat.(*r2k_empty_array1, &block)") { splat_and_keyword_splat.(*r2k_empty_array1, &block) }
  row(1, 1, "splat_and_keyword_splat.(*r2k_array1, &block)") { splat_and_keyword_splat.(*r2k_array1, &block) }
end

r2k = r2k = proc{ |*a, &block|   }
r2k.ruby2_keywords

group(:test_ruby2_keywords) do
  row(1, 1, "r2k.(1, a: 2, &block)") { r2k.(1, a: 2, &block) }
  row(1, 1, "r2k.(1, *empty_array, a: 2, &block)") { r2k.(1, *empty_array, a: 2, &block) }
  row(1, 1, "r2k.(1, a:2, **empty_hash, &block)") { r2k.(1, a:2, **empty_hash, &block) }
  row(1, 1, "r2k.(1, **empty_hash, a: 2, &block)") { r2k.(1, **empty_hash, a: 2, &block) }
  row(1, 0, "r2k.(1, **nil, &block)") { r2k.(1, **nil, &block) }
  row(1, 0, "r2k.(1, **empty_hash, &block)") { r2k.(1, **empty_hash, &block) }
  row(1, 1, "r2k.(1, **hash1, &block)") { r2k.(1, **hash1, &block) }
  row(1, 1, "r2k.(1, *empty_array, **hash1, &block)") { r2k.(1, *empty_array, **hash1, &block) }
  row(1, 1, "r2k.(1, **hash1, **empty_hash, &block)") { r2k.(1, **hash1, **empty_hash, &block) }
  row(1, 1, "r2k.(1, **empty_hash, **hash1, &block)") { r2k.(1, **empty_hash, **hash1, &block) }
  row(1, 0, "r2k.(1, *empty_array, &block)") { r2k.(1, *empty_array, &block) }
  row(1, 0, "r2k.(1, *empty_array, *empty_array, **empty_hash, &block)") { r2k.(1, *empty_array, *empty_array, **empty_hash, &block) }
  row(1, 1, "r2k.(*array1, a: 2, &block)") { r2k.(*array1, a: 2, &block) }
  row(1, 0, "r2k.(**nill, &block)") { r2k.(**nill, &block) }
  row(1, 0, "r2k.(*nil, **nill, &block)") { r2k.(*nil, **nill, &block) }
  row(1, 0, "r2k.(*array1, **nill, &block)") { r2k.(*array1, **nill, &block) }
  row(1, 0, "r2k.(*array1, **empty_hash, &block)") { r2k.(*array1, **empty_hash, &block) }
  row(1, 1, "r2k.(*array1, **hash1, &block)") { r2k.(*array1, **hash1, &block) }
  row(1, 1, "r2k.(*array1, *empty_array, **hash1, &block)") { r2k.(*array1, *empty_array, **hash1, &block) }
  row(1, 0, "r2k.(*array1, *empty_array, &block)") { r2k.(*array1, *empty_array, &block) }
  row(1, 0, "r2k.(*array1, *empty_array, **empty_hash, &block)") { r2k.(*array1, *empty_array, **empty_hash, &block) }
  row(1, 1, "r2k.(*array1, *empty_array, a: 2, **empty_hash, &block)") { r2k.(*array1, *empty_array, a: 2, **empty_hash, &block) }
  row(1, 1, "r2k.(*array1, *empty_array, **hash1, **empty_hash, &block)") { r2k.(*array1, *empty_array, **hash1, **empty_hash, &block) }
  row(1, 1, "r2k.(1, *empty_array, a: 2, **empty_hash, &block)") { r2k.(1, *empty_array, a: 2, **empty_hash, &block) }
  row(1, 1, "r2k.(1, *empty_array, **hash1, **empty_hash, &block)") { r2k.(1, *empty_array, **hash1, **empty_hash, &block) }
  row(1, 1, "r2k.(*array1, **empty_hash, a: 2, &block)") { r2k.(*array1, **empty_hash, a: 2, &block) }
  row(1, 1, "r2k.(*array1, **hash1, **empty_hash, &block)") { r2k.(*array1, **hash1, **empty_hash, &block) }
  row(1, 0, "r2k.(*array1, **nil, &block)") { r2k.(*array1, **nil, &block) }
  row(1, 0, "r2k.(*r2k_empty_array, &block)") { r2k.(*r2k_empty_array, &block) }
end
