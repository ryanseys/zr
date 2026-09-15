# Which of Array's own methods its methods call on a subclass: every
# method Array defines is wrapped to log a call made from inside another,
# and each is then called once on a fresh receiver. CRuby calls one by
# dispatch only where it means to, and ze0's core, written in Ruby, has
# to call no more and no fewer. Written by tools/dispatch.rb.

class Probe < Array
  CALLING = []
  LOG = []
  [:&, :*, :+, :-, :<<, :<=>, :==, :[], :[]=, :all?, :any?, :append, :assoc, :at, :bsearch, :bsearch_index, :chain, :chunk, :chunk_while, :clear, :collect, :collect!, :collect_concat, :combination, :compact, :compact!, :concat, :count, :cycle, :deconstruct, :delete, :delete_at, :delete_if, :detect, :difference, :dig, :drop, :drop_while, :each, :each_cons, :each_entry, :each_index, :each_slice, :each_with_index, :each_with_object, :empty?, :entries, :eql?, :fetch, :fetch_values, :fill, :filter, :filter!, :filter_map, :find, :find_all, :find_index, :first, :flat_map, :flatten, :flatten!, :freeze, :grep, :grep_v, :group_by, :hash, :include?, :index, :initialize_copy, :inject, :insert, :inspect, :intersect?, :intersection, :join, :keep_if, :last, :lazy, :length, :map, :map!, :max, :max_by, :member?, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :pack, :partition, :permutation, :pop, :prepend, :product, :push, :rassoc, :reduce, :reject, :reject!, :repeated_combination, :repeated_permutation, :replace, :reverse, :reverse!, :reverse_each, :rfind, :rindex, :rotate, :rotate!, :sample, :select, :select!, :shift, :shuffle, :shuffle!, :size, :slice, :slice!, :slice_after, :slice_before, :slice_when, :sort, :sort!, :sort_by, :sort_by!, :sum, :take, :take_while, :tally, :to_a, :to_ary, :to_h, :to_s, :to_set, :transpose, :union, :uniq, :uniq!, :unshift, :values_at, :zip, :|].each do |m|
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
  r = Probe.new([3, 1, 2])
  Probe::LOG.clear
  begin
    yield r
  rescue StandardError => e
    Probe::LOG << "raised #{e.class}"
  end
  puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
end

call("&") { |r| r.__send__(:&, [1, 2]) { |*x| x.first } }
call("*") { |r| r.__send__(:*, 1) { |*x| x.first } }
call("+") { |r| r.__send__(:+, [1, 2]) { |*x| x.first } }
call("-") { |r| r.__send__(:-, [1, 2]) { |*x| x.first } }
call("<<") { |r| r.__send__(:<<, 1) { |*x| x.first } }
call("<=>") { |r| r.__send__(:<=>, 1) { |*x| x.first } }
call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
call("[]") { |r| r.__send__(:[], 1) { |*x| x.first } }
call("[]=") { |r| r.__send__(:[]=, 0, 1) { |*x| x.first } }
call("all?") { |r| r.all?() { |*x| x.first } }
call("any?") { |r| r.any?() { |*x| x.first } }
call("append") { |r| r.append() { |*x| x.first } }
call("assoc") { |r| r.assoc(1) { |*x| x.first } }
call("at") { |r| r.at(1) { |*x| x.first } }
call("bsearch") { |r| r.bsearch() { |*x| x.first } }
call("bsearch_index") { |r| r.bsearch_index() { |*x| x.first } }
call("chain") { |r| r.chain() { |*x| x.first } }
call("chunk") { |r| r.chunk() { |*x| x.first } }
call("chunk_while") { |r| r.chunk_while() { |*x| x.first } }
call("clear") { |r| r.clear() { |*x| x.first } }
call("collect") { |r| r.collect() { |*x| x.first } }
call("collect!") { |r| r.collect!() { |*x| x.first } }
call("collect_concat") { |r| r.collect_concat() { |*x| x.first } }
call("combination") { |r| r.combination(1) { |*x| x.first } }
call("compact") { |r| r.compact() { |*x| x.first } }
call("compact!") { |r| r.compact!() { |*x| x.first } }
call("concat") { |r| r.concat() { |*x| x.first } }
call("count") { |r| r.count() { |*x| x.first } }
call("deconstruct") { |r| r.deconstruct() { |*x| x.first } }
call("delete") { |r| r.delete(1) { |*x| x.first } }
call("delete_at") { |r| r.delete_at(1) { |*x| x.first } }
call("delete_if") { |r| r.delete_if() { |*x| x.first } }
call("detect") { |r| r.detect() { |*x| x.first } }
call("difference") { |r| r.difference() { |*x| x.first } }
call("dig") { |r| r.dig(1) { |*x| x.first } }
call("drop") { |r| r.drop(1) { |*x| x.first } }
call("drop_while") { |r| r.drop_while() { |*x| x.first } }
call("each") { |r| r.each() { |*x| x.first } }
call("each_cons") { |r| r.each_cons(1) { |*x| x.first } }
call("each_entry") { |r| r.each_entry() { |*x| x.first } }
call("each_index") { |r| r.each_index() { |*x| x.first } }
call("each_slice") { |r| r.each_slice(1) { |*x| x.first } }
call("each_with_index") { |r| r.each_with_index() { |*x| x.first } }
call("each_with_object") { |r| r.each_with_object(1) { |*x| x.first } }
call("empty?") { |r| r.empty?() { |*x| x.first } }
call("entries") { |r| r.entries() { |*x| x.first } }
call("eql?") { |r| r.eql?(1) { |*x| x.first } }
call("fetch") { |r| r.fetch(1) { |*x| x.first } }
call("fetch_values") { |r| r.fetch_values() { |*x| x.first } }
call("fill") { |r| r.fill() { |*x| x.first } }
call("filter") { |r| r.filter() { |*x| x.first } }
call("filter!") { |r| r.filter!() { |*x| x.first } }
call("filter_map") { |r| r.filter_map() { |*x| x.first } }
call("find") { |r| r.find() { |*x| x.first } }
call("find_all") { |r| r.find_all() { |*x| x.first } }
call("find_index") { |r| r.find_index() { |*x| x.first } }
call("first") { |r| r.first() { |*x| x.first } }
call("flat_map") { |r| r.flat_map() { |*x| x.first } }
call("flatten") { |r| r.flatten() { |*x| x.first } }
call("flatten!") { |r| r.flatten!() { |*x| x.first } }
call("grep") { |r| r.grep(1) { |*x| x.first } }
call("grep_v") { |r| r.grep_v(1) { |*x| x.first } }
call("group_by") { |r| r.group_by() { |*x| x.first } }
call("hash") { |r| r.hash() { |*x| x.first } }
call("include?") { |r| r.include?(1) { |*x| x.first } }
call("index") { |r| r.index() { |*x| x.first } }
call("initialize_copy") { |r| r.initialize_copy([1, 2]) { |*x| x.first } }
call("inject") { |r| r.inject() { |*x| x.first } }
call("insert") { |r| r.insert(1) { |*x| x.first } }
call("inspect") { |r| r.inspect() { |*x| x.first } }
call("intersect?") { |r| r.intersect?([1, 2]) { |*x| x.first } }
call("intersection") { |r| r.intersection() { |*x| x.first } }
call("join") { |r| r.join() { |*x| x.first } }
call("keep_if") { |r| r.keep_if() { |*x| x.first } }
call("last") { |r| r.last() { |*x| x.first } }
call("lazy") { |r| r.lazy() { |*x| x.first } }
call("length") { |r| r.length() { |*x| x.first } }
call("map") { |r| r.map() { |*x| x.first } }
call("map!") { |r| r.map!() { |*x| x.first } }
call("max") { |r| r.max() { |*x| x.first } }
call("max_by") { |r| r.max_by() { |*x| x.first } }
call("member?") { |r| r.member?(1) { |*x| x.first } }
call("min") { |r| r.min() { |*x| x.first } }
call("min_by") { |r| r.min_by() { |*x| x.first } }
call("minmax") { |r| r.minmax() { |*x| x.first } }
call("minmax_by") { |r| r.minmax_by() { |*x| x.first } }
call("none?") { |r| r.none?() { |*x| x.first } }
call("one?") { |r| r.one?() { |*x| x.first } }
call("pack") { |r| r.pack("l") { |*x| x.first } }
call("partition") { |r| r.partition() { |*x| x.first } }
call("permutation") { |r| r.permutation() { |*x| x.first } }
call("pop") { |r| r.pop() { |*x| x.first } }
call("prepend") { |r| r.prepend() { |*x| x.first } }
call("product") { |r| r.product() { |*x| x.first } }
call("push") { |r| r.push() { |*x| x.first } }
call("rassoc") { |r| r.rassoc(1) { |*x| x.first } }
call("reduce") { |r| r.reduce() { |*x| x.first } }
call("reject") { |r| r.reject() { |*x| x.first } }
call("reject!") { |r| r.reject!() { |*x| x.first } }
call("repeated_combination") { |r| r.repeated_combination(1) { |*x| x.first } }
call("repeated_permutation") { |r| r.repeated_permutation(1) { |*x| x.first } }
call("replace") { |r| r.replace([1, 2]) { |*x| x.first } }
call("reverse") { |r| r.reverse() { |*x| x.first } }
call("reverse!") { |r| r.reverse!() { |*x| x.first } }
call("reverse_each") { |r| r.reverse_each() { |*x| x.first } }
call("rfind") { |r| r.rfind() { |*x| x.first } }
call("rindex") { |r| r.rindex() { |*x| x.first } }
call("rotate") { |r| r.rotate() { |*x| x.first } }
call("rotate!") { |r| r.rotate!() { |*x| x.first } }
call("sample") { |r| r.sample() { |*x| x.first } }
call("select") { |r| r.select() { |*x| x.first } }
call("select!") { |r| r.select!() { |*x| x.first } }
call("shift") { |r| r.shift() { |*x| x.first } }
call("shuffle") { |r| r.shuffle() { |*x| x.first } }
call("shuffle!") { |r| r.shuffle!() { |*x| x.first } }
call("size") { |r| r.size() { |*x| x.first } }
call("slice") { |r| r.slice(1) { |*x| x.first } }
call("slice!") { |r| r.slice!(1) { |*x| x.first } }
call("slice_after") { |r| r.slice_after() { |*x| x.first } }
call("slice_before") { |r| r.slice_before() { |*x| x.first } }
call("slice_when") { |r| r.slice_when() { |*x| x.first } }
call("sort") { |r| r.sort() { |*x| x.first } }
call("sort!") { |r| r.sort!() { |*x| x.first } }
call("sort_by") { |r| r.sort_by() { |*x| x.first } }
call("sort_by!") { |r| r.sort_by!() { |*x| x.first } }
call("sum") { |r| r.sum() { |*x| x.first } }
call("take") { |r| r.take(1) { |*x| x.first } }
call("take_while") { |r| r.take_while() { |*x| x.first } }
call("tally") { |r| r.tally() { |*x| x.first } }
call("to_a") { |r| r.to_a() { |*x| x.first } }
call("to_ary") { |r| r.to_ary() { |*x| x.first } }
call("to_s") { |r| r.to_s() { |*x| x.first } }
call("to_set") { |r| r.to_set() { |*x| x.first } }
call("union") { |r| r.union() { |*x| x.first } }
call("uniq") { |r| r.uniq() { |*x| x.first } }
call("uniq!") { |r| r.uniq!() { |*x| x.first } }
call("unshift") { |r| r.unshift() { |*x| x.first } }
call("values_at") { |r| r.values_at() { |*x| x.first } }
call("zip") { |r| r.zip() { |*x| x.first } }
call("|") { |r| r.__send__(:|, [1, 2]) { |*x| x.first } }

__END__
collect_concat: collect_concat->each
each_cons: each_cons->size each_cons->each
each_entry: each_entry->each
each_slice: each_slice->size each_slice->each
each_with_index: each_with_index->each
each_with_object: each_with_object->each
entries: entries->each
filter_map: filter_map->each
find_all: find_all->each
flat_map: flat_map->each
grep: grep->each
grep_v: grep_v->each
group_by: group_by->each
initialize_copy: raised NoMethodError
inject: inject->each
max_by: max_by->each
member?: member?->each
min_by: min_by->each
minmax: minmax->each
minmax_by: minmax_by->each
partition: partition->each
reduce: reduce->each
sort_by: sort_by->each
sort_by!: sort_by!->sort_by sort_by->each
tally: tally->each
