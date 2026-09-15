# Which of Hash's own methods its methods call on a subclass: every
# method Hash defines is wrapped to log a call made from inside another,
# and each is then called once on a fresh receiver. CRuby calls one by
# dispatch only where it means to, and ze0's core, written in Ruby, has
# to call no more and no fewer. Written by tools/dispatch.rb.

class Probe < Hash
  CALLING = []
  LOG = []
  [:<, :<=, :==, :>, :>=, :[], :[]=, :all?, :any?, :assoc, :chain, :chunk, :chunk_while, :clear, :collect, :collect_concat, :compact, :compact!, :compare_by_identity, :compare_by_identity?, :count, :cycle, :deconstruct_keys, :default, :default=, :default_proc, :default_proc=, :delete, :delete_if, :detect, :dig, :drop, :drop_while, :each, :each_cons, :each_entry, :each_key, :each_pair, :each_slice, :each_value, :each_with_index, :each_with_object, :empty?, :entries, :eql?, :except, :fetch, :fetch_values, :filter, :filter!, :filter_map, :find, :find_all, :find_index, :first, :flat_map, :flatten, :freeze, :grep, :grep_v, :group_by, :has_key?, :has_value?, :hash, :include?, :initialize_copy, :inject, :inspect, :invert, :keep_if, :key, :key?, :keys, :lazy, :length, :map, :max, :max_by, :member?, :merge, :merge!, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :partition, :rassoc, :reduce, :rehash, :reject, :reject!, :replace, :reverse_each, :select, :select!, :shift, :size, :slice, :slice_after, :slice_before, :slice_when, :sort, :sort_by, :store, :sum, :take, :take_while, :tally, :to_a, :to_h, :to_hash, :to_proc, :to_s, :to_set, :transform_keys, :transform_keys!, :transform_values, :transform_values!, :uniq, :update, :value?, :values, :values_at, :zip].each do |m|
    define_method(m) do |*args, &blk|
      LOG << "#{CALLING.last}->#{m}" unless CALLING.empty?
      CALLING << m
      begin
        super(*args, &blk)
      ensure
        CALLING.pop
      end
    end
    ruby2_keywords(m)
  end
end

def call(name)
  r = Probe.new.tap { |h| h[:a] = 1; h[:b] = 2 }
  Probe::LOG.clear
  begin
    yield r
  rescue StandardError => e
    Probe::LOG << "raised #{e.class}"
  end
  puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
end

call("<") { |r| r.__send__(:<, {a: 1}) { |*x| x.first } }
call("<=") { |r| r.__send__(:<=, {a: 1}) { |*x| x.first } }
call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
call(">") { |r| r.__send__(:>, {a: 1}) { |*x| x.first } }
call(">=") { |r| r.__send__(:>=, {a: 1}) { |*x| x.first } }
call("[]") { |r| r.__send__(:[], 1) { |*x| x.first } }
call("[]=") { |r| r.__send__(:[]=, 0, 1) { |*x| x.first } }
call("all?") { |r| r.all?() { |*x| x.first } }
call("any?") { |r| r.any?() { |*x| x.first } }
call("assoc") { |r| r.assoc(1) { |*x| x.first } }
call("chain") { |r| r.chain() { |*x| x.first } }
call("chunk") { |r| r.chunk() { |*x| x.first } }
call("chunk_while") { |r| r.chunk_while() { |*x| x.first } }
call("clear") { |r| r.clear() { |*x| x.first } }
call("collect") { |r| r.collect() { |*x| x.first } }
call("collect_concat") { |r| r.collect_concat() { |*x| x.first } }
call("compact") { |r| r.compact() { |*x| x.first } }
call("compact!") { |r| r.compact!() { |*x| x.first } }
call("compare_by_identity") { |r| r.compare_by_identity() { |*x| x.first } }
call("compare_by_identity?") { |r| r.compare_by_identity?() { |*x| x.first } }
call("count") { |r| r.count() { |*x| x.first } }
call("deconstruct_keys") { |r| r.deconstruct_keys(1) { |*x| x.first } }
call("default") { |r| r.default() { |*x| x.first } }
call("default=") { |r| r.__send__(:default=, 1) { |*x| x.first } }
call("default_proc") { |r| r.default_proc() { |*x| x.first } }
call("default_proc=") { |r| r.__send__(:default_proc=, :a) { |*x| x.first } }
call("delete") { |r| r.delete(1) { |*x| x.first } }
call("delete_if") { |r| r.delete_if() { |*x| x.first } }
call("detect") { |r| r.detect() { |*x| x.first } }
call("dig") { |r| r.dig(1) { |*x| x.first } }
call("drop") { |r| r.drop(1) { |*x| x.first } }
call("drop_while") { |r| r.drop_while() { |*x| x.first } }
call("each") { |r| r.each() { |*x| x.first } }
call("each_cons") { |r| r.each_cons(1) { |*x| x.first } }
call("each_entry") { |r| r.each_entry() { |*x| x.first } }
call("each_key") { |r| r.each_key() { |*x| x.first } }
call("each_pair") { |r| r.each_pair() { |*x| x.first } }
call("each_slice") { |r| r.each_slice(1) { |*x| x.first } }
call("each_value") { |r| r.each_value() { |*x| x.first } }
call("each_with_index") { |r| r.each_with_index() { |*x| x.first } }
call("each_with_object") { |r| r.each_with_object(1) { |*x| x.first } }
call("empty?") { |r| r.empty?() { |*x| x.first } }
call("entries") { |r| r.entries() { |*x| x.first } }
call("eql?") { |r| r.eql?(1) { |*x| x.first } }
call("except") { |r| r.except() { |*x| x.first } }
call("fetch") { |r| r.fetch(1) { |*x| x.first } }
call("fetch_values") { |r| r.fetch_values() { |*x| x.first } }
call("filter") { |r| r.filter() { |*x| x.first } }
call("filter!") { |r| r.filter!() { |*x| x.first } }
call("filter_map") { |r| r.filter_map() { |*x| x.first } }
call("find") { |r| r.find() { |*x| x.first } }
call("find_all") { |r| r.find_all() { |*x| x.first } }
call("find_index") { |r| r.find_index() { |*x| x.first } }
call("first") { |r| r.first() { |*x| x.first } }
call("flat_map") { |r| r.flat_map() { |*x| x.first } }
call("flatten") { |r| r.flatten() { |*x| x.first } }
call("grep") { |r| r.grep(1) { |*x| x.first } }
call("grep_v") { |r| r.grep_v(1) { |*x| x.first } }
call("group_by") { |r| r.group_by() { |*x| x.first } }
call("has_key?") { |r| r.has_key?(1) { |*x| x.first } }
call("has_value?") { |r| r.has_value?(1) { |*x| x.first } }
call("hash") { |r| r.hash() { |*x| x.first } }
call("include?") { |r| r.include?(1) { |*x| x.first } }
call("initialize_copy") { |r| r.initialize_copy({a: 1}) { |*x| x.first } }
call("inject") { |r| r.inject() { |*x| x.first } }
call("inspect") { |r| r.inspect() { |*x| x.first } }
call("invert") { |r| r.invert() { |*x| x.first } }
call("keep_if") { |r| r.keep_if() { |*x| x.first } }
call("key") { |r| r.key(1) { |*x| x.first } }
call("key?") { |r| r.key?(1) { |*x| x.first } }
call("keys") { |r| r.keys() { |*x| x.first } }
call("lazy") { |r| r.lazy() { |*x| x.first } }
call("length") { |r| r.length() { |*x| x.first } }
call("map") { |r| r.map() { |*x| x.first } }
call("max") { |r| r.max() }
call("max_by") { |r| r.max_by() { |*x| x.first } }
call("member?") { |r| r.member?(1) { |*x| x.first } }
call("merge") { |r| r.merge() { |*x| x.first } }
call("merge!") { |r| r.merge!() { |*x| x.first } }
call("min") { |r| r.min() }
call("min_by") { |r| r.min_by() { |*x| x.first } }
call("minmax") { |r| r.minmax() }
call("minmax_by") { |r| r.minmax_by() { |*x| x.first } }
call("none?") { |r| r.none?() { |*x| x.first } }
call("one?") { |r| r.one?() { |*x| x.first } }
call("partition") { |r| r.partition() { |*x| x.first } }
call("rassoc") { |r| r.rassoc(1) { |*x| x.first } }
call("reduce") { |r| r.reduce() { |*x| x.first } }
call("rehash") { |r| r.rehash() { |*x| x.first } }
call("reject") { |r| r.reject() { |*x| x.first } }
call("reject!") { |r| r.reject!() { |*x| x.first } }
call("replace") { |r| r.replace({a: 1}) { |*x| x.first } }
call("reverse_each") { |r| r.reverse_each() { |*x| x.first } }
call("select") { |r| r.select() { |*x| x.first } }
call("select!") { |r| r.select!() { |*x| x.first } }
call("shift") { |r| r.shift() { |*x| x.first } }
call("size") { |r| r.size() { |*x| x.first } }
call("slice") { |r| r.slice() { |*x| x.first } }
call("slice_after") { |r| r.slice_after() { |*x| x.first } }
call("slice_before") { |r| r.slice_before() { |*x| x.first } }
call("slice_when") { |r| r.slice_when() { |*x| x.first } }
call("sort") { |r| r.sort() }
call("sort_by") { |r| r.sort_by() { |*x| x.first } }
call("store") { |r| r.store(0, 1) { |*x| x.first } }
call("sum") { |r| r.sum([1, 2]) { |*x| x.first } }
call("take") { |r| r.take(1) { |*x| x.first } }
call("take_while") { |r| r.take_while() { |*x| x.first } }
call("tally") { |r| r.tally() { |*x| x.first } }
call("to_a") { |r| r.to_a() { |*x| x.first } }
call("to_h") { |r| r.to_h() }
call("to_hash") { |r| r.to_hash() { |*x| x.first } }
call("to_proc") { |r| r.to_proc() { |*x| x.first } }
call("to_s") { |r| r.to_s() { |*x| x.first } }
call("to_set") { |r| r.to_set() { |*x| x.first } }
call("transform_keys") { |r| r.transform_keys() { |*x| x.first } }
call("transform_keys!") { |r| r.transform_keys!() { |*x| x.first } }
call("transform_values") { |r| r.transform_values() { |*x| x.first } }
call("transform_values!") { |r| r.transform_values!() { |*x| x.first } }
call("uniq") { |r| r.uniq() { |*x| x.first } }
call("update") { |r| r.update() { |*x| x.first } }
call("value?") { |r| r.value?(1) { |*x| x.first } }
call("values") { |r| r.values() { |*x| x.first } }
call("values_at") { |r| r.values_at() { |*x| x.first } }
call("zip") { |r| r.zip() { |*x| x.first } }

__END__
[]: []->default
all?: all?->each
collect: collect->each
collect_concat: collect_concat->each
count: count->each
detect: detect->each
dig: dig->default
drop: drop->each
drop_while: drop_while->each
each_cons: each_cons->size each_cons->each
each_entry: each_entry->each
each_slice: each_slice->size each_slice->each
each_with_index: each_with_index->each
each_with_object: each_with_object->each
entries: entries->each
filter_map: filter_map->each
find: find->each
find_all: find_all->each
find_index: find_index->each
first: first->each
flat_map: flat_map->each
grep: grep->each
grep_v: grep_v->each
group_by: group_by->each
initialize_copy: raised NoMethodError
inject: inject->each
map: map->each
max: max->each
max_by: max_by->each
min: min->each
min_by: min_by->each
minmax: minmax->each
minmax_by: minmax_by->each
none?: none?->each
one?: one?->each
partition: partition->each
reduce: reduce->each
reverse_each: reverse_each->each
sort: sort->each
sort_by: sort_by->each
sum: sum->each
take: take->each
take_while: take_while->each
tally: tally->each
to_set: to_set->each_entry each_entry->each
uniq: uniq->each
zip: zip->each
